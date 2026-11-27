import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../models/lyrics.dart';
import '../models/track.dart';
import '../providers.dart';
import 'automix.dart';
import 'beat_analysis.dart' show BeatGrid, beatGridVersion;
import 'beat_pulse.dart';
import 'mix_sync.dart';
import 'track_analyzer.dart';
import 'waveform.dart';
import 'karaoke.dart';
import 'mini_player_window.dart';
import 'mix_info.dart';
import 'radio_seeds.dart';
import 'shuffle_order.dart';
import 'smart_reorder.dart';
import 'player_state.dart';
import 'stem_service.dart';
import 'stream_proxy.dart';

/// Riverpod notifier that drives playback through media_kit (libmpv).
///
/// libmpv (the engine behind Yattee and Spotube) natively handles the
/// fragmented MP4 / opus streams that YouTube serves, which AVPlayer
/// cannot play.
class PlayerController extends Notifier<PlayerState> {
  // Due player alternati: durante il crossfade uno suona la coda del brano
  // corrente mentre l'altro ha gia' aperto il successivo a volume zero e
  // sale. Con un solo player non c'e' sovrapposizione, solo una dissolvenza
  // in uscita seguita da una in entrata.
  late final mk.Player _a;
  late final mk.Player _b;

  /// Il terzo player: suona il tratto dell'uscente rifatto con voce e base
  /// separate, al posto dell'uscente, per la durata del mix.
  late final mk.Player _stem;

  /// Il quarto: il tratto dell'entrante con la voce che aspetta il suo
  /// turno, per il passaggio di voce. Alla fine del mix restituisce il
  /// posto all'entrante vero, che intanto suonava muto e a tempo.
  late final mk.Player _stemIn;
  bool _useA = true;

  /// Il player che sta suonando e che detta lo stato.
  mk.Player get _player => _useA ? _a : _b;

  /// Quello libero, su cui si prepara il brano successivo.
  mk.Player get _idle => _useA ? _b : _a;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _advancing = false;

  /// True while a media is being opened/loaded. The media_kit `completed`
  /// event can fire spuriously around track switches; ignoring it while
  /// loading prevents skipping two songs at once.
  bool _loading = false;

  /// Prevents multiple crossfade triggers for the same track.
  bool _crossfading = false;

  /// Cambia a ogni dissolvenza avviata o interrotta.
  ///
  /// Serve perche' la preparazione del brano successivo e' asincrona: se
  /// nel frattempo premi un altro brano, quella preparazione arriva
  /// comunque e scambierebbe i player sotto la tua scelta.
  int _crossfadeGen = 0;

  /// Invalida le dissolvenze in corso quando ne parte una nuova: senza,
  /// i callback ritardati della precedente continuano ad arrivare e
  /// riportano il volume a un valore vecchio.
  int _fadeToken = 0;

  Timer? _fadeTimer;

  /// Le tre bande di ogni player durante un mix, in dB — bassi, medi,
  /// acuti — e i due filtri: dove la curva del mix li vuole. Neutri fuori
  /// dai mix.
  final Map<mk.Player, MixStage> _bands = {};

  /// Come sono davvero i filtri di AutoMix nella catena di ogni player:
  /// quello che la catena o l'ultimo `af-command` gli hanno detto. Si
  /// rimette a posto solo quando la catena si ricostruisce, perche' e' li'
  /// che libmpv cambia davvero (vedi mixFilterCommands).
  final Map<mk.Player, MixFilterState> _applied = {};

  /// Di quanti semitoni e' spostato il brano di ogni player (vedi
  /// keyShiftFor): l'entrante di un mix fra tonalita' che stridono, e i
  /// player che suonano con lui — i suoi tratti separati, la base del
  /// karaoke. Si decide quando il brano si carica e resta fino alla sua
  /// fine; un brano scelto a mano parte senza.
  ///
  /// Con lo spostamento la velocita' di mpv non e' piu' il tempo del brano:
  /// l'etichetta della catena lo accelera gia' del suo rapporto. Per questo
  /// tutte le velocita' passano da [_setTempo] e si leggono con [_tempoOf].
  final Map<mk.Player, int> _keyShift = {};

  /// Fa suonare [p] a [tempo] secondi di brano al secondo, spostamento di
  /// tonalita' compreso.
  Future<void> _setTempo(mk.Player p, double tempo) =>
      p.setRate(mpvSpeedFor(tempo, _keyShift[p] ?? 0));

  /// Quanti secondi di brano suona [p] in un secondo: la sua velocita' di
  /// mpv per il rapporto dello spostamento.
  double _tempoOf(mk.Player p) =>
      p.state.rate * keyShiftRatio(_keyShift[p] ?? 0);

  /// Da' a [to] lo spostamento di [from], prima che la sua catena si
  /// costruisca: un player che suona accanto a un altro deve avere il suo
  /// stesso tono.
  void _copyKeyShift({required mk.Player from, required mk.Player to}) {
    final k = _keyShift[from] ?? 0;
    if (k == 0) {
      _keyShift.remove(to);
    } else {
      _keyShift[to] = k;
    }
  }

  /// La correzione di livello dell'entrante: la differenza fra i due tratti
  /// che si sovrappongono. Dopo il mix torna a zero piano.
  final Map<mk.Player, double> _trimDb = {};
  int _trimToken = 0;

  /// L'analisi ritmica dei brani, per il mix a tempo.
  late final TrackAnalyzer _analyzer = TrackAnalyzer(
    storage: ref.read(storageServiceProvider),
    fileFor: ref.read(songPreloaderProvider).fileFor,
  );

  /// La musica del brano in ascolto per le macchie, che si muovono con
  /// lei come un visualizzatore (vedi [beatPulse]). Null finche' il brano
  /// non e' analizzato.
  BeatPulse? _pulse;
  String? _pulseFor;
  String? _pulseAskedFor;

  /// True quando [_pulse] e' gia' il migliore possibile per il brano: la
  /// griglia dell'ultima versione, col suo inviluppo se c'e'.
  bool _pulseFinal = false;
  DateTime _pulseLookedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Come si muovono le macchie in questo istante.
  ///
  /// Lo chiede l'orologio delle macchie a ogni fotogramma, quindi niente
  /// lavoro: la posizione dell'ultimo aggiornamento piu' il tempo passato
  /// da allora, alla velocita' a cui suona il brano. Ferme in pausa, mentre
  /// carica, e quando la posizione e' ferma da un secondo (sta bufferizzando
  /// anche se dice di suonare): una macchia che batte sul silenzio stona.
  SpotBeat beatPulse() {
    final s = state;
    final p = _pulse;
    if (p == null || !s.isPlaying || s.isLoading) return noSpotBeat;
    if (_pulseFor != s.current?.id) return noSpotBeat;
    final since = DateTime.now().difference(_posAt).inMicroseconds / 1e6;
    if (since > 1) return noSpotBeat;
    return p.at(s.position.inMicroseconds / 1e6 + since * _tempoOf(_player));
  }

  /// Cambia [_pulse] e lo passa al mini player del Mac, che ha la sua
  /// macchia e la muove da se': gli si manda tutto il brano, letto a
  /// trenta valori al secondo, una volta sola.
  void _setPulse(BeatPulse? p) {
    _pulse = p;
    if (!MiniPlayerWindow.isSupported) return;
    if (p == null) {
      unawaited(MiniPlayerWindow.clearMusic());
      return;
    }
    const rate = 30.0;
    final n = ((p.grid.musicEnd + 1) * rate).ceil();
    final pulse = Float32List(n),
        snap = Float32List(n),
        energy = Float32List(n);
    for (var i = 0; i < n; i++) {
      final m = p.at(i / rate);
      pulse[i] = m.pulse;
      snap[i] = m.snap;
      energy[i] = m.energy;
    }
    unawaited(
      MiniPlayerWindow.setMusic(
        rate: rate,
        pulse: pulse,
        snap: snap,
        energy: energy,
      ),
    );
  }

  /// Tiene [_pulse] sul brano in ascolto. Gira a ogni aggiornamento di
  /// posizione, quindi esce subito quando non c'e' niente da fare.
  ///
  /// L'analisi e' quella di AutoMix. Con AutoMix spento il brano non si
  /// analizza da solo: lo si fa qui, dopo i primi secondi per non rubare
  /// banda all'avvio dello stream. Costa un download del brano se suonava
  /// in streaming, una volta sola: l'analisi resta salvata. Una griglia di
  /// una versione di prima, senza inviluppo, serve intanto: le macchie
  /// battono sulla griglia finche' l'analisi nuova non e' pronta.
  void _watchPulse() {
    final cur = state.current;
    if (cur == null || ref.read(spotsMusicProvider) <= 0) return;
    final now = DateTime.now();
    if (_pulseFor != cur.id) {
      _pulseFor = cur.id;
      _setPulse(null);
      _pulseFinal = false;
      _pulseLookedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (_pulseFinal) return;
    if (now.difference(_pulseLookedAt) < const Duration(seconds: 3)) return;
    _pulseLookedAt = now;
    final service = ref.read(youtubeServiceProvider);
    final audioId = service.knownAudioId(cur.id);
    final grid = _analyzer.known(audioId, minVersion: 4);
    if (grid != null && _pulse?.grid != grid) _setPulse(BeatPulse(grid));
    if (grid != null && grid.version >= beatGridVersion) {
      _pulseFinal = true;
      final id = cur.id;
      unawaited(
        _analyzer.envelopeFor(audioId).then((env) {
          if (env != null && _pulseFor == id) {
            _setPulse(BeatPulse(grid, envelope: env));
          }
        }),
      );
      return;
    }
    if (_pulseAskedFor == cur.id ||
        state.position < const Duration(seconds: 3)) {
      return;
    }
    _pulseAskedFor = cur.id;
    unawaited(_ensureAnalyzed(cur));
  }

  String? _waveFor;
  bool _waveFinal = false;
  DateTime _waveLookedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Tiene [waveformProvider] sul brano in ascolto: l'onda della barra.
  ///
  /// Viene dall'analisi, che fanno AutoMix o le macchie a tempo di musica;
  /// se non c'e' ancora la si chiede, dopo i primi secondi, come fa
  /// [_watchPulse]. Finche' non arriva la barra mostra un'onda piatta.
  void _watchWave() {
    final cur = state.current;
    if (cur == null) return;
    final now = DateTime.now();
    if (_waveFor != cur.id) {
      _waveFor = cur.id;
      _waveFinal = false;
      _waveLookedAt = DateTime.fromMillisecondsSinceEpoch(0);
      final shown = ref.read(waveformProvider);
      if (shown != null && shown.trackId != cur.id) {
        ref.read(waveformProvider.notifier).state = null;
      }
    }
    if (_waveFinal) return;
    if (now.difference(_waveLookedAt) < const Duration(seconds: 2)) return;
    _waveLookedAt = now;
    final service = ref.read(youtubeServiceProvider);
    final grid = _analyzer.known(service.knownAudioId(cur.id), minVersion: 4);
    if (grid != null) {
      _waveFinal = true;
      final levels = waveformOf(grid);
      if (levels.isNotEmpty) {
        ref.read(waveformProvider.notifier).state = (
          trackId: cur.id,
          levels: levels,
        );
      }
      // Poi coi colpi, dall'inviluppo, che sta in un file suo.
      final id = cur.id;
      unawaited(
        _analyzer.envelopeFor(service.knownAudioId(id)).then((env) {
          if (env == null || _waveFor != id) return;
          final full = waveformOf(grid, envelope: env);
          if (full.isEmpty) return;
          ref.read(waveformProvider.notifier).state = (
            trackId: id,
            levels: full,
          );
        }),
      );
      return;
    }
    if (_pulseAskedFor == cur.id ||
        state.position < const Duration(seconds: 3)) {
      return;
    }
    _pulseAskedFor = cur.id;
    unawaited(_ensureAnalyzed(cur));
  }

  /// Separa voce e base del tratto che l'uscente suonera' nel mix.
  late final StemService _stemService = StemService(
    fileFor: ref.read(songPreloaderProvider).fileFor,
  );

  /// Il karaoke: le basi separate dei brani, e il quinto player che suona
  /// quella del brano in corso accanto a lui.
  ///
  /// Accanto e non al posto: la voce si regola mescolando i due. Il brano
  /// a volume a, la base a 1 - a: la somma e' la base piu' a volte la voce,
  /// quindi a = 1 e' il brano com'e' e a = 0 la sola base. Il volume passa
  /// da _vol come ogni altro, e cosi' dissolvenze, preamp e volume allineato
  /// valgono anche per la base.
  late final KaraokeBases _bases = KaraokeBases(_stemService);
  late final mk.Player _base;
  bool _karaokeOn = false;

  /// La voce in questo istante: segue quella scelta, ma entrando e uscendo
  /// dal karaoke ci arriva in una rampa invece che di colpo.
  double _voiceNow = 1;
  Timer? _voiceRamp;
  DateTime _karaokeCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// L'ultimo livello chiesto per ogni player, prima di guadagni e
  /// karaoke: serve a ridistribuirlo quando cambia la voce.
  final Map<mk.Player, double> _level = {};

  /// Il tratto separato pronto per il mix in piano, e se e' caricato sul
  /// terzo player. Una separazione alla volta: la coda le mette in fila.
  File? _stemFile;
  bool _stemLoaded = false;

  /// Lo stesso per l'entrante, quando c'e' un passaggio di voce.
  File? _stemInFile;
  bool _stemInLoaded = false;
  Future<void> _stemQueue = Future.value();

  /// I brani aggiunti dalla radio: anche con lo shuffle restano in fondo,
  /// dopo la raccolta, nel loro ordine.
  final Set<String> _radioIds = {};

  /// La radio del punto di partenza in uso, ancora da consumare: YouTube ne
  /// manda una cinquantina per brano, e prima se ne prendevano cinque e il
  /// resto si buttava.
  final List<Track> _radioPool = [];

  /// I brani gia' usati come punto di partenza, e quelli della radio
  /// ascoltati fino in fondo, che possono diventarlo (vedi radio_seeds).
  final Set<String> _radioSeedsUsed = {};
  final Set<String> _radioLiked = {};

  /// La raccolta nell'ordine in cui era prima dello shuffle, per rimetterla
  /// cosi' quando lo si spegne. Null se non la si conosce (una sessione
  /// ripresa dopo un riavvio).
  Map<String, int>? _unshuffled;

  /// Quanti brani devono ancora suonare prima della fine della coda.
  int _remaining() => state.queue.length - state.currentIndex - 1;

  /// L'indice del brano successivo, lo stesso per chi prepara il mix e per
  /// chi poi avanza: il prossimo della coda, o da capo con la ripetizione.
  /// Oltre la coda, nella coda non c'e': lo aggiunge la radio.
  int _upcomingIndex() {
    final s = state;
    final q = s.queue;
    final i = s.currentIndex + 1;
    if (i >= q.length && s.repeat == RepeatMode.all && q.isNotEmpty) return 0;
    return i;
  }

  /// La coda con cio' che viene dopo il brano in corso rimescolato.
  List<Track> _shuffled(List<Track> queue, int current) {
    final upcoming = shuffleUpcoming(
      queue.sublist(current + 1),
      isRadio: (t) => _radioIds.contains(t.id),
    );
    return [...queue.sublist(0, current + 1), ...upcoming];
  }

  /// Il mix a tempo pianificato fra il brano che suona e il successivo, e
  /// a che punto e': entrante caricato e fermo, partenza armata.
  BeatMixPlan? _beatPlan;
  String? _beatPlanKey;
  bool _beatLoading = false;
  bool _beatReady = false;
  Timer? _beatStartTimer;

  /// L'ultima posizione di ogni player e quando e' arrivata: per far
  /// partire l'entrante sul battere serve sapere dove sta l'uscente al
  /// millisecondo, non all'ultimo aggiornamento.
  final Map<mk.Player, Duration> _posOf = {};
  DateTime _posAt = DateTime.now();

  /// Quando e' arrivata l'ultima posizione di ogni player: il controllo del
  /// tempo durante il mix confronta due player, e le loro posizioni
  /// arrivano a scatti e in momenti diversi. Senza contare il tempo passato
  /// da ognuna, lo scatto stesso sembrava uno scarto.
  final Map<mk.Player, DateTime> _posStampOf = {};

  /// Dove e' [p] adesso, in secondi del suo file: l'ultima posizione
  /// arrivata piu' il tempo passato da allora, alla velocita' a cui suona.
  /// Nulla se dopo [after] non e' ancora arrivata nessuna posizione — quella
  /// di prima e' di quando era fermo — o se l'ultima e' vecchia di oltre un
  /// quarto di secondo: un player che non aggiorna non si indovina.
  double? _posNow(mk.Player p, {required DateTime after}) {
    final pos = _posOf[p];
    final at = _posStampOf[p];
    if (pos == null || at == null || at.isBefore(after)) return null;
    final since = DateTime.now().difference(at).inMicroseconds / 1e6;
    if (since > 0.25) return null;
    return pos.inMicroseconds / 1e6 + since * _tempoOf(p);
  }

  /// Quanto prima del battere va dato il play all'entrante: un player in
  /// pausa ci mette un attimo a far uscire il suono, misurato sui 200 ms.
  /// Si affina a ogni mix con lo scarto trovato al primo controllo.
  double _playLead = 0.2;

  /// Il ritorno graduale alla velocita' normale dopo un mix a tempo.
  int _rateToken = 0;

  /// Per quale brano si e' gia' preparato il successivo a fine brano.
  String? _lateWarmFor;

  /// Dove finisce la voce nel brano che suona, dal testo sincronizzato.
  /// Guida il punto in cui comincia AutoMix.
  Duration? _vocalsEnd;
  String? _vocalsFor;

  /// Gli inizi delle righe del testo del brano che suona, in secondi.
  List<double> _vocalLines = const [];

  /// Per quale brano la ricerca del testo e' finita, trovato o no. Il mix a
  /// tempo la aspetta: pianificato prima, partiva sopra la voce — "Girl
  /// Like Me" veniva mixata a 2:08, dodici secondi prima dell'ultimo verso.
  String? _vocalsDoneFor;

  /// Dove comincia a cantare il brano successivo, per chiudere il mix
  /// prima: due voci insieme sono il mix peggiore, anche in questo verso.
  final Map<String, Duration?> _vocalsStartOf = {};

  /// Set by [restoreSession]; consumed by the first play. While it is set
  /// the state describes a track that is not actually open yet.
  Duration? _pendingResume;

  /// Throttle for the position listener, the only high-frequency writer.
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);

  /// True once a restore has run, so persisting can't write an empty state
  /// over a saved session before it has been read back.
  bool _restored = false;

  /// How many times the current track has been reloaded after a premature
  /// stream end (YouTube truncates streams to ~1 MiB when it flags the
  /// client; a fresh URL / different format often serves the full song).
  int _retryCount = 0;

  /// Timestamp when the current track started playing (for stats).
  DateTime? _playStartedAt;

  /// Quanto il brano ha suonato davvero, pause escluse. Prima l'ascolto
  /// era il tempo dall'orologio fra partenza e fine: un brano lasciato in
  /// pausa per la notte ne contava decine di ore.
  Duration _listened = Duration.zero;
  DateTime? _playingSince;

  /// The last track id for which we recorded stats (avoid double-counting).
  String? _lastStatsTrackId;

  /// Whether we're currently fetching radio tracks (to avoid duplicates).
  bool _radioFetching = false;

  /// The underlying media_kit player (used e.g. by the EQ controller
  /// to set libmpv properties).
  mk.Player get rawPlayer => _player;

  // Now Playing sync (iOS lock screen / Control Center).
  String? _npTrackId;
  bool _npPlaying = false;
  DateTime _npLastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  PlayerState build() {
    _a = mk.Player();
    _b = mk.Player();
    _stem = mk.Player();
    _stemIn = mk.Player();
    _base = mk.Player();
    for (final p in [_stem, _stemIn, _base]) {
      _subs.add(
        p.stream.position.listen((pos) {
          _posOf[p] = pos;
          _posStampOf[p] = DateTime.now();
        }),
      );
    }

    final nowPlaying = ref.read(nowPlayingProvider);
    nowPlaying.listen();
    nowPlaying.onRemoteCommand = (command, position) {
      switch (command) {
        case 'play':
        case 'toggle':
          toggle();
        case 'pause':
          _player.pause();
        case 'next':
          next();
        case 'previous':
          previous();
        case 'seek':
          if (position != null) {
            seek(Duration(milliseconds: (position * 1000).round()));
          }
      }
    };

    _attachListeners(_a);
    _attachListeners(_b);

    // Accendere la radio deve riempire la coda subito: senza questo la
    // pagina Coda restava vuota fino al cambio di brano successivo.
    ref.listen<bool>(radioProvider, (_, on) {
      if (on) _topUpRadio();
    });

    ref.onDispose(() {
      _fadeTimer?.cancel();
      nowPlaying.onRemoteCommand = null;
      for (final s in _subs) {
        s.cancel();
      }
      _a.dispose();
      _b.dispose();
      _stem.dispose();
      _stemIn.dispose();
      _voiceRamp?.cancel();
      _base.dispose();
    });

    return const PlayerState();
  }

  /// Pushes the current state to the OS Now Playing widget, throttled to
  /// ~2s (position ticks fire often) and always on track/play-state change.
  void _syncNowPlaying() {
    final s = state;
    final track = s.current;
    if (track == null) return;
    final now = DateTime.now();
    final trackChanged = _npTrackId != track.id;
    final playingChanged = _npPlaying != s.isPlaying;
    if (!trackChanged &&
        !playingChanged &&
        now.difference(_npLastSync) < const Duration(seconds: 2)) {
      return;
    }
    _npTrackId = track.id;
    _npPlaying = s.isPlaying;
    _npLastSync = now;
    ref
        .read(nowPlayingProvider)
        .update(
          track: track,
          isPlaying: s.isPlaying,
          position: s.position,
          duration: s.duration,
        );
  }

  /// Plays a single track, optionally replacing the whole queue.
  ///
  /// The current index is set to the position of [track] inside the queue so
  /// the Now Playing info (mini player / full player) shows the tapped song
  /// and not always the first one.
  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    Duration? startAt,
  }) async {
    _abortCrossfade();
    _retryCount = 0;
    var q = queue ?? [track];
    var index = q.indexWhere((t) => t.id == track.id);
    // Una coda nuova ricomincia da zero: niente radio. Con lo shuffle
    // acceso, parte il brano toccato e poi tutti gli altri della raccolta,
    // rimescolati — anche quelli che nella lista stavano prima di lui. La
    // stessa coda riaperta (un nuovo tentativo, una ripresa) resta com'e'.
    if (!identical(q, state.queue)) {
      _radioIds.clear();
      _radioPool.clear();
      _radioSeedsUsed.clear();
      _radioLiked.clear();
      _unshuffled = {for (var i = 0; i < q.length; i++) q[i].id: i};
      if (state.shuffle && index >= 0) {
        q = [
          q[index],
          ...shuffleUpcoming([
            ...q.sublist(0, index),
            ...q.sublist(index + 1),
          ], isRadio: (_) => false),
        ];
        index = 0;
      }
    }
    // copyWith, not a fresh PlayerState: building one from scratch reset
    // shuffle, repeat and crossfade to their defaults on every play. It also
    // meant the crossfade fade-in below could never fire, because it reads
    // state.crossfadeDuration a few lines after wiping it.
    state = state.copyWith(
      queue: q,
      currentIndex: index >= 0 ? index : 0,
      isLoading: true,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      clearError: true,
    );
    await _loadAndPlay(track, startAt: startAt);
    // Record play start time for stats.
    _playStartedAt = DateTime.now();
    _lastStatsTrackId = track.id;
  }

  /// La stazione di un artista: i suoi brani migliori mescolati, e poi
  /// brani simili senza fine.
  ///
  /// Senza la sua pagina (manca l'id, o la rete) si parte da [seed], un suo
  /// brano: la radio fa il resto, e la stazione suona comunque.
  Future<void> playStation({required Track seed, String? artistId}) async {
    var songs = <Track>[];
    if (artistId != null) {
      try {
        final page = await ref
            .read(youtubeServiceProvider)
            .getArtistPage(artistId);
        songs = [...page.topSongs]..shuffle(math.Random());
      } catch (_) {}
    }
    if (songs.isEmpty) songs = [seed];
    // Prima il brano, poi la radio: accesa prima, cominciava a cercare i
    // simili del brano di prima.
    await playTrack(songs.first, queue: songs);
    ref.read(radioProvider.notifier).set(true);
  }

  /// Una radio da un brano: parte lui, da solo, e dopo vengono i brani
  /// simili, che la radio aggiunge man mano. Toccato fra i preferiti non
  /// mette in coda i preferiti: e' il punto.
  Future<void> startRadio(Track track) async {
    await playTrack(track, queue: [track]);
    ref.read(radioProvider.notifier).set(true);
    // Accesa gia' da prima, l'accensione non scatta: i simili si chiedono
    // qui, che il brano e' quello giusto.
    _topUpRadio();
  }

  /// Smoothly transitions volume from [from] to [to] over [duration].
  /// Dissolvenza a potenza costante.
  ///
  /// Due differenze rispetto alla versione precedente, che si sentivano
  /// entrambe:
  ///
  /// * Un solo timer a ~16ms invece di undici `Future.delayed` a gradini da
  ///   40ms. I gradini erano il rumore "a scatti".
  /// * Curva coseno/seno invece che lineare. Una dissolvenza lineare perde
  ///   circa 6 dB a meta' transizione, perche' potenza e ampiezza stanno in
  ///   rapporto quadratico: si sente come un buco di volume anche quando i
  ///   numeri scorrono lisci.
  void _fadeVolume(double from, double to, Duration duration) {
    final token = ++_fadeToken;
    _fadeTimer?.cancel();

    final total = duration.inMilliseconds;
    if (total <= 0) {
      _vol(_player, to);
      return;
    }

    final started = DateTime.now();
    const tick = Duration(milliseconds: 16);

    _fadeTimer = Timer.periodic(tick, (timer) {
      if (token != _fadeToken) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final t = (elapsed / total).clamp(0.0, 1.0);

      // In salita seno, in discesa coseno: la somma delle potenze resta
      // costante lungo tutta la transizione.
      final shaped = to > from
          ? math.sin(t * math.pi / 2)
          : math.cos(t * math.pi / 2);
      final v = to > from
          ? from + (to - from) * shaped
          : to + (from - to) * shaped;

      _vol(_player, v.clamp(0.0, 100.0));

      if (t >= 1.0) {
        timer.cancel();
        _vol(_player, to);
      }
    });
  }

  /// Riporta il volume al livello scelto dall'utente, annullando qualunque
  /// dissolvenza in corso. Rete di sicurezza contro il silenzio permanente.
  void _restoreVolume() {
    _fadeToken++;
    _fadeTimer?.cancel();
    _vol(_player, state.volume);
  }

  /// Plays the track at [index] of the current queue.
  Future<void> playAt(int index) async {
    _abortCrossfade();
    // Record stats for the previous track before switching.
    _recordStats();
    _retryCount = 0;
    final q = state.queue;
    if (index < 0 || index >= q.length) return;
    state = state.copyWith(currentIndex: index, isLoading: true);
    await _loadAndPlay(q[index]);
    _playStartedAt = DateTime.now();
    _lastStatsTrackId = q[index].id;
  }

  /// Porta la coda al brano [index] senza farlo suonare: partira'
  /// dall'inizio al prossimo play. Per i videoclip, che vanno avanti nella
  /// coda mentre la musica e' ferma: chiuso il video, si riprende dal brano
  /// di cui si stava guardando il video.
  void cueAt(int index) {
    final q = state.queue;
    if (index < 0 || index >= q.length || index == state.currentIndex) return;
    _abortCrossfade();
    unawaited(_player.pause());
    state = state.copyWith(
      currentIndex: index,
      position: Duration.zero,
      duration: q[index].duration ?? Duration.zero,
      isPlaying: false,
      isLoading: false,
    );
    _pendingResume = Duration.zero;
    _syncNowPlaying();
  }

  /// Adds [track] to the end of the current queue.
  void addToQueue(Track track) {
    state = state.copyWith(queue: [...state.queue, track]);
    _persist(now: true);
  }

  /// Aggancia gli stream a un player.
  ///
  /// Si registra su entrambi, ma ogni callback esce subito se il player non
  /// e' quello attivo: durante il crossfade suonano insieme e solo l'uscente
  /// deve dettare posizione, durata e stato finche' non avviene lo scambio.
  void _attachListeners(mk.Player p) {
    _subs.add(
      p.stream.playing.listen((playing) {
        if (p != _player) return;
        if (_karaokeOn) unawaited(playing ? _base.play() : _base.pause());
        final now = DateTime.now();
        if (playing) {
          _playingSince ??= now;
        } else if (_playingSince != null) {
          _listened += now.difference(_playingSince!);
          _playingSince = null;
        }
        state = state.copyWith(isPlaying: playing);
        _syncNowPlaying();
        _persist(now: true);
      }),
    );
    _subs.add(
      p.stream.buffering.listen((buffering) {
        if (p != _player) return;
        state = state.copyWith(isLoading: buffering);
      }),
    );
    _subs.add(
      p.stream.position.listen((pos) {
        _posOf[p] = pos;
        _posStampOf[p] = DateTime.now();
        if (p != _player) return;
        _posAt = DateTime.now();
        _logClock(p, pos);
        state = state.copyWith(position: pos);
        _syncKaraoke(pos);
        _persist();
        _watchPulse();
        _watchWave();
        // Il mix a tempo, se c'e' un piano: si occupa lui della transizione.
        if (_handleBeatMix(pos)) {
          _syncNowPlaying();
          return;
        }
        _syncNowPlaying();
      }),
    );
    _subs.add(
      p.stream.duration.listen((dur) {
        if (p != _player) return;
        _adoptDuration(dur);
      }),
    );
    _subs.add(
      p.stream.completed.listen((completed) {
        if (p != _player) return;
        // Senza !_crossfading, la fine naturale del brano uscente faceva
        // partire l'avanzamento normale mentre l'altro player stava gia'
        // suonando la stessa traccia: si sentiva due volte, sfasata.
        if (completed && !_loading && !_crossfading) _onCompleted();
      }),
    );
    _subs.add(
      p.stream.error.listen((e) {
        if (p != _player) return;
        debugPrint('PLAYER ERROR: $e');
        state = state.copyWith(error: 'Player error: $e');
      }),
    );
  }

  /// Ogni quindici secondi: dove e' il brano, quanto dura, a che velocita'
  /// va e quanto tempo vero e' passato. Per capire quando un brano dura
  /// piu' di quanto dice la barra.
  DateTime? _clockAt;
  Duration? _clockPos;
  String? _clockTrack;
  void _logClock(mk.Player p, Duration pos) {
    final now = DateTime.now();
    final id = state.current?.id;
    if (id != _clockTrack) {
      _clockTrack = id;
      _clockAt = now;
      _clockPos = pos;
      return;
    }
    final at = _clockAt;
    if (at == null || now.difference(at) < const Duration(seconds: 15)) {
      return;
    }
    final wall = now.difference(at).inMilliseconds / 1000;
    final moved = (pos - (_clockPos ?? pos)).inMilliseconds / 1000;
    debugPrint(
      'orologio: ${state.current?.title} a ${pos.inMilliseconds / 1000} s di '
      '${state.duration.inMilliseconds / 1000}, velocita\' '
      '${_tempoOf(p).toStringAsFixed(3)} (mpv ${p.state.rate}, '
      'spostamento ${_keyShift[p] ?? 0}), '
      'in ${wall.toStringAsFixed(1)} s veri avanzato di '
      '${moved.toStringAsFixed(1)}, suona ${state.isPlaying}',
    );
    _clockAt = now;
    _clockPos = pos;
  }

  /// La durata del brano che suona, dal suo player.
  void _adoptDuration(Duration dur) {
    final s = state;
    var updated = s.copyWith(duration: dur);
    // The stream knows the real length even when the track arrived from
    // search with duration == null: write it back into the queue (and
    // persist it) so lists show real times after a song has played once.
    final t = s.current;
    if (t != null && dur > Duration.zero && t.duration != dur) {
      final q = [...s.queue];
      q[s.currentIndex] = t.copyWith(duration: dur);
      updated = updated.copyWith(queue: q);
      final storage = ref.read(storageServiceProvider);
      storage.updateFavoriteDuration(t.id, dur);
      storage.saveDuration(t.id, dur);
    }
    state = updated;
    _syncNowPlaying();
  }

  /// La catena di filtri di un player: AutoMix, poi l'equalizzatore.
  ///
  /// Una sola catena per player, costruita qui: prima l'equalizzatore la
  /// scriveva da solo, e solo sul player attivo — durante un crossfade il
  /// brano entrante suonava senza equalizzatore e alla fine cambiava suono
  /// di colpo.
  ///
  /// Serve il libmpv ricompilato con i filtri audio (vedi
  /// tool/build_libmpv.sh): quello di media_kit ha solo `equalizer`, e con
  /// `highpass` o `ebur128` la catena veniva rifiutata e il brano non
  /// suonava.
  ///
  /// Con AutoMix, le tre bande per il passaggio a tappe e i due filtri
  /// delle sweep, neutri finche' non servono. Sempre presenti, cosi' il mix
  /// li sposta con un comando senza ricostruire la catena, che ricostruita
  /// fa uno scatto. In testa, se il brano e' spostato di tonalita', le due
  /// `format` dello spostamento (vedi keyShiftChain).
  String _chainFor(mk.Player p) => playerFilterChain(
    automix: state.automix,
    stage: _bands[p] ?? MixStage.flat,
    keyShift: _keyShift[p] ?? 0,
    eq: ref.read(eqProvider).filterChain,
  );

  Future<void> _applyChain(mk.Player p) async {
    try {
      final native = p.platform;
      if (native is! mk.NativePlayer) return;
      _applied[p] = MixFilterState.of(_bands[p] ?? MixStage.flat);
      await native.setProperty('af', _chainFor(p));
    } catch (e) {
      developer.log('filtri non applicati: $e');
    }
  }

  /// Il guadagno di un player, in dB: il preamplificatore dell'equalizzatore
  /// piu', con AutoMix, l'allineamento fra i due tratti del mix.
  ///
  /// Niente piu' normalizzazione col volume dichiarato da YouTube: toglieva
  /// fino a dodici decibel ai brani forti e ne lasciava altri pieni, e il
  /// volume saltava piu' di quanto lo uniformasse.
  ///
  /// Passano dal volume del player e non da un filtro: cambiano a ogni
  /// brano e a ogni tocco del preamp, e un filtro andrebbe ricostruito
  /// ogni volta, con lo scatto che ne segue.
  double _gainDb(mk.Player p) {
    final eq = ref.read(eqProvider);
    return (eq.enabled ? eq.preamp : 0) +
        (state.automix ? (_trimDb[p] ?? 0) : 0);
  }

  /// Imposta il volume di un player, col suo guadagno. Tutte le dissolvenze
  /// passano di qui: cosi' preamp e volume allineato valgono anche a meta'
  /// di una transizione.
  Future<void> _vol(mk.Player p, double v) {
    _level[p] = v;
    final g = math.pow(10, _gainDb(p) / 20);
    if (p == _player && _karaokeOn) {
      // Il livello si divide fra brano e base: vedi _bases.
      final a = _voiceNow;
      unawaited(_base.setVolume((v * (1 - a) * g).clamp(0.0, _volumeMax)));
      return p.setVolume((v * a * g).clamp(0.0, _volumeMax));
    }
    return p.setVolume((v * g).clamp(0.0, _volumeMax));
  }

  /// Tetto del volume di mpv: 100 e' il volume del file, sopra si amplifica.
  /// Alzato perche' un preamplificatore positivo possa esistere.
  static const double _volumeMax = 400;

  /// Riapplica filtri e guadagni a entrambi i player: l'equalizzatore o
  /// AutoMix sono cambiati.
  Future<void> refreshFilters() async {
    for (final p in [_a, _b, _stem, _stemIn, _base]) {
      try {
        final native = p.platform;
        if (native is mk.NativePlayer) {
          await native.setProperty('volume-max', '$_volumeMax');
        }
      } catch (_) {}
      await _applyChain(p);
    }
    // Il volume del player che suona, col guadagno nuovo. Non durante un
    // mix: li' i volumi li sta muovendo la transizione.
    if (!_crossfading) await _vol(_player, state.volume);
  }

  static const _flat = MixStage.flat;

  /// Sposta bande e filtri di un player mentre suona: solo quello che si e'
  /// mosso abbastanza da sentirsi, rispetto a quello che il player ha
  /// davvero (vedi mixFilterCommands).
  Future<void> _setBands(mk.Player p, MixStage stage) async {
    _bands[p] = stage;
    if (!state.automix) return;
    final native = p.platform;
    if (native is! mk.NativePlayer) return;
    final step = mixFilterCommands(
      _applied[p] ?? MixFilterState.of(_flat),
      stage,
    );
    _applied[p] = step.applied;
    for (final cmd in step.commands) {
      try {
        await native.command(cmd);
      } catch (_) {}
    }
  }

  /// Dopo il mix la correzione di livello torna a zero a mezzo decibel al
  /// secondo: abbastanza piano da non sentirla, come in kumone.
  Future<void> _glideTrim(mk.Player p) async {
    final token = ++_trimToken;
    while ((_trimDb[p] ?? 0).abs() > 0.05) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (token != _trimToken || p != _player) return;
      final v = _trimDb[p] ?? 0;
      _trimDb[p] = v > 0 ? math.max(0, v - 0.1) : math.min(0, v + 0.1);
      if (!_crossfading) await _vol(p, state.volume);
    }
    _trimDb.remove(p);
  }

  /// Prima di aprire un brano: il suo volume allineato e, se non entra in
  /// un mix, i bassi aperti. Il taglio per il mix lo decide chi prepara il
  /// mix, prima di chiamare il caricamento.
  ///
  /// [keyShift] e' lo spostamento di tonalita' con cui il brano suonera',
  /// sempre deciso qui, a ogni caricamento: un player che aveva fatto
  /// l'entrante spostato di un mix non lo passa al brano dopo.
  Future<void> _prepareFilters(
    mk.Player p,
    String audioId, {
    required bool silent,
    int keyShift = 0,
  }) async {
    if (!silent) {
      _bands.remove(p);
      _trimDb.remove(p);
      // Un brano scelto a mano ferma la rampa di velocita' in corso.
      _rateToken++;
    }
    if (keyShift == 0) {
      _keyShift.remove(p);
    } else {
      _keyShift[p] = keyShift;
    }
    // Ogni brano parte alla sua velocita': un player che aveva fatto
    // l'entrante di un mix a tempo potrebbe essere rimasto accelerato. Il
    // mix a tempo la reimposta dopo il caricamento.
    await _setTempo(p, 1.0);
    await _applyChain(p);
  }

  /// Legge dove finisce la voce, dal testo, quando AutoMix e' acceso.
  Future<void> _loadVocalsEnd(Track track) async {
    if (!state.automix || _vocalsFor == track.id) return;
    _vocalsFor = track.id;
    _vocalsEnd = null;
    _vocalLines = const [];
    try {
      final lyrics = await lyricsFor(
        ref,
        title: track.title,
        artist: track.author,
      );
      if (_vocalsFor == track.id) {
        _vocalsEnd = vocalsEndOf(lyrics);
        // Dove comincia ogni riga, cioe' dove finisce la precedente: e'
        // li' che la voce puo' passare all'entrante senza tagliare niente.
        _vocalLines = [
          for (final l in lyrics?.lines ?? const <LyricsLine>[])
            l.time.inMilliseconds / 1000,
        ];
      }
    } catch (_) {}
    if (_vocalsFor == track.id) _vocalsDoneFor = track.id;
  }

  /// Gli scarti fra dove dovrebbe essere l'entrante e dov'e', misurati
  /// durante l'ultimo mix a tempo, in secondi. Per le verifiche.
  @visibleForTesting
  final List<double> debugDrift = [];

  /// Il piano del mix a tempo in vigore, per le verifiche.
  @visibleForTesting
  BeatMixPlan? get debugBeatPlan => _beatPlan;

  /// Per quale coppia "brano che suona > successivo" si e' gia' chiesta
  /// l'analisi.
  String? _gridsKey;

  /// Chiede l'analisi del brano che suona e del successivo, se su disco.
  void _requestGrids() {
    if (!state.automix) return;
    final s = state;
    final service = ref.read(youtubeServiceProvider);
    // Il testo del successivo: da li' si sa quando comincia a cantare.
    final ni = _upcomingIndex();
    _gridsKey = '${s.current?.id}>${ni < s.queue.length ? s.queue[ni].id : ''}';
    if (ni < s.queue.length) {
      final next = s.queue[ni];
      if (!_vocalsStartOf.containsKey(next.id)) {
        unawaited(() async {
          Duration? start;
          try {
            start = vocalsStartOf(
              await service.getLyrics(title: next.title, artist: next.author),
            );
          } catch (_) {}
          _vocalsStartOf[next.id] = start;
        }());
      }
    }
    for (final i in [s.currentIndex, ni]) {
      if (i < 0 || i >= s.queue.length) continue;
      unawaited(_ensureAnalyzed(s.queue[i]));
    }
  }

  /// Scarica il brano, se non c'e' gia', e lo analizza.
  ///
  /// Con AutoMix acceso anche il brano che suona in streaming: analisi e
  /// separazione della voce lavorano su file, e senza il primo brano
  /// scelto a mano non si sarebbe mai mixato col secondo. E' il prezzo in
  /// banda di un AutoMix che c'e' sempre, invece che solo a volte.
  Future<void> _ensureAnalyzed(Track track) async {
    try {
      final service = ref.read(youtubeServiceProvider);
      final id = await service.audioIdFor(track.id);
      await ref.read(songPreloaderProvider).ensureDownloaded(id);
      await _analyzer.gridFor(id);
    } catch (_) {}
  }

  /// Il piano del mix a tempo fra il brano che suona e il successivo, se
  /// entrambi sono analizzati e i loro tempi si possono accordare.
  BeatMixPlan? _beatPlanNow() {
    final s = state;
    final cur = s.current;
    if (!s.automix || cur == null) return null;
    final ni = _upcomingIndex();
    if (ni >= s.queue.length) return null;
    final next = s.queue[ni];
    // Il brano dopo dello stesso disco non si mixa.
    if (cur.albumId != null && next.albumId == cur.albumId) return null;
    final late = _lateFor == cur.id ? _lateFrom : null;
    final key = '${cur.id}>${next.id}${late == null ? '' : '@$late'}';
    if (_beatPlanKey == key) return _beatPlan;
    if (_vocalsDoneFor != cur.id) return null;
    if (!_vocalsStartOf.containsKey(next.id)) return null;
    final service = ref.read(youtubeServiceProvider);
    final a = _analyzer.known(service.knownAudioId(cur.id));
    final b = _analyzer.known(service.knownAudioId(next.id));
    if (a == null || b == null) return null;
    _beatPlanKey = key;
    _beatLoading = false;
    _beatReady = false;
    final vocals = _vocalsFor == cur.id ? _vocalsEnd : null;
    final plan = planBeatMix(
      // Chi esce si guarda dal finale, chi entra dall'inizio: ognuno con
      // la griglia del tratto che suona nel mix.
      out: a.outro,
      incoming: b,
      vocalsEnd: vocals == null ? null : vocals.inMilliseconds / 1000,
      inVocalsStart: switch (_vocalsStartOf[next.id]) {
        final d? => d.inMilliseconds / 1000,
        null => null,
      },
      outLines: _vocalsFor == cur.id ? _vocalLines : const [],
      stems: true,
      notBefore: late,
      // Il brano che suona puo' essere a sua volta spostato, dal mix che
      // l'ha portato: la sua tonalita' e' quella che si sente.
      outKeyShift: _keyShift[_player] ?? 0,
    );
    if (plan != null) {
      debugPrint(
        describeBeatMix(
          plan,
          from: cur.title,
          to: next.title,
          out: a.outro,
          incoming: b,
        ),
      );
      switch (plan.kind) {
        // Il cambio secco non tocca la voce: niente da separare, solo
        // l'eco d'uscita da calcolare.
        case MixKind.cut:
          _startEchoJob(key, service.knownAudioId(cur.id), plan);
        // La dissolvenza suona i brani come sono.
        case MixKind.fade:
          _dropStem();
        default:
          _startStemJob(
            key,
            service.knownAudioId(cur.id),
            service.knownAudioId(next.id),
            plan,
          );
      }
    }
    return _beatPlan = plan;
  }

  /// Il mix rifatto in ritardo: per quale brano, e da che secondo in poi.
  String? _lateFor;
  double? _lateFrom;

  /// Per quale brano si e' gia' scritto perche' il mix manca.
  String? _noPlanLoggedFor;

  /// Scrive cosa manca al mix, una volta per brano, verso la fine: senza,
  /// un brano che finisce senza mix non dice perche'.
  void _logWhyNoPlan() {
    final s = state;
    final cur = s.current;
    final ni = _upcomingIndex();
    final service = ref.read(youtubeServiceProvider);
    final next = ni < s.queue.length ? s.queue[ni] : null;
    debugPrint(
      'mix: nessun piano per ${cur?.title}: '
      'successivo ${next?.title ?? 'nessuno'}, '
      'stesso disco ${cur?.albumId != null && next?.albumId == cur?.albumId}, '
      'testo ${_vocalsDoneFor == cur?.id}, '
      'testo successivo ${next != null && _vocalsStartOf.containsKey(next.id)}, '
      'analisi ${cur != null && _analyzer.known(service.knownAudioId(cur.id)) != null}, '
      'analisi successivo '
      '${next != null && _analyzer.known(service.knownAudioId(next.id)) != null}',
    );
  }

  /// Separa voce e base del tratto dell'uscente, in sottofondo.
  ///
  /// Parte appena il mix e' deciso, di solito minuti prima: la
  /// separazione ha tutto il brano per finire. Se il piano cambia nel
  /// frattempo, il risultato si butta.
  void _startStemJob(String key, String outId, String inId, BeatMixPlan plan) {
    _dropStem();
    _stemQueue = _stemQueue.then((_) async {
      if (_beatPlanKey != key) return;
      try {
        final out = await _stemService.renderOutgoing(outId, plan);
        if (out == null) return;
        if (_beatPlanKey != key) {
          unawaited(out.file.delete().then((_) {}, onError: (_) {}));
          return;
        }
        _stemFile = out.file;
        // La voce separata ha detto dove il cantante prende fiato: lo
        // spegnimento della voce, o il passaggio all'entrante, puo' essersi
        // spostato in una pausa. Il piano in vigore diventa quello — stessa
        // chiave, stesso mix, solo la voce diversa — e il tratto
        // dell'entrante si calcola con lui.
        final placed = out.plan;
        if (out.note.isNotEmpty) debugPrint('mix: ${out.note}');
        if (!identical(placed, plan)) _beatPlan = placed;
        // Il tratto dell'entrante solo se c'e' un passaggio di voce: senza,
        // l'entrante suona gia' com'e'.
        if (placed.stems?.exchangeAt == null) return;
        final inFile = await _stemService.renderIncoming(inId, placed);
        if (inFile == null) return;
        if (_beatPlanKey != key) {
          unawaited(inFile.delete().then((_) {}, onError: (_) {}));
          return;
        }
        _stemInFile = inFile;
      } catch (e) {
        debugPrint('stem: separazione non riuscita ($e)');
      }
    });
  }

  /// Prepara l'eco d'uscita del cambio secco, sul posto del tratto
  /// separato: stesso player, stesso scambio inudibile con l'uscente.
  void _startEchoJob(String key, String outId, BeatMixPlan plan) {
    _dropStem();
    _stemQueue = _stemQueue.then((_) async {
      if (_beatPlanKey != key) return;
      try {
        final file = await _stemService.renderEchoOut(outId, plan);
        if (file == null) return;
        if (_beatPlanKey != key) {
          unawaited(file.delete().then((_) {}, onError: (_) {}));
          return;
        }
        _stemFile = file;
      } catch (e) {
        debugPrint('eco: non riuscita ($e)');
      }
    });
  }

  /// Toglie il tratto separato: fermo il terzo player e cancellato il file.
  void _dropStem() {
    if (_stemLoaded) unawaited(_stem.stop());
    if (_stemInLoaded) unawaited(_stemIn.stop());
    _stemLoaded = false;
    _stemInLoaded = false;
    for (final p in [_stem, _stemIn]) {
      _bands.remove(p);
      _trimDb.remove(p);
    }
    for (final f in [_stemFile, _stemInFile]) {
      if (f != null) unawaited(f.delete().then((_) {}, onError: (_) {}));
    }
    _stemFile = null;
    _stemInFile = null;
  }

  /// Carica il tratto separato sul terzo player, fermo all'inizio e muto,
  /// con la catena e il livello dell'uscente: suonera' esattamente come
  /// lui, tranne la voce.
  Future<void> _loadStem(double rate) async {
    final f = _stemFile;
    if (f == null) return;
    try {
      _bands[_stem] = _bands[_player] ?? _flat;
      // E con lo stesso spostamento di tonalita', se l'uscente ne ha uno.
      _copyKeyShift(from: _player, to: _stem);
      // Lo stesso livello dell'uscente, anche se la sua correzione dal mix
      // prima non e' ancora tornata a zero: altrimenti al cambio di player
      // il volume farebbe un gradino.
      if (_trimDb[_player] case final t?) {
        _trimDb[_stem] = t;
      } else {
        _trimDb.remove(_stem);
      }
      await _applyChain(_stem);
      await _vol(_stem, 0);
      await _setTempo(_stem, rate);
      await _stem.open(mk.Media(f.path), play: false);
      _stemLoaded = true;
    } catch (e) {
      debugPrint('stem: tratto non caricato ($e)');
      _stemLoaded = false;
    }
  }

  /// Carica il tratto dell'entrante sul quarto player, con catena, livello
  /// e velocita' dell'entrante: suona come lui, ma con la voce che aspetta.
  Future<void> _loadStemIn(mk.Player incoming, double speed) async {
    final f = _stemInFile;
    if (f == null) return;
    try {
      _trimDb[_stemIn] = _trimDb[incoming] ?? 0;
      _bands[_stemIn] = _bands[incoming] ?? _flat;
      _copyKeyShift(from: incoming, to: _stemIn);
      await _applyChain(_stemIn);
      await _vol(_stemIn, 0);
      await _stemIn.open(mk.Media(f.path), play: false);
      await _setTempo(_stemIn, speed);
      _stemInLoaded = true;
    } catch (e) {
      debugPrint('stem: tratto entrante non caricato ($e)');
      _stemInLoaded = false;
    }
  }

  /// Il mix a tempo, guidato dalla posizione del brano che suona.
  ///
  /// Vero se se ne sta occupando lui: allora il piano normale non si
  /// guarda. Sei secondi prima del punto il successivo si carica fermo sul
  /// suo primo battere; a un secondo e mezzo si arma un timer che lo fa
  /// partire sul battere esatto dell'uscente. Se qualcosa non e' pronto in
  /// tempo, si lascia al mix normale.
  BeatMixPlan? _shownPlan;

  /// Passa il piano del mix a [mixPlanProvider], per la barra: solo quando
  /// cambia, non a ogni passo.
  void _publishMixPlan(BeatMixPlan? plan) {
    if (identical(plan, _shownPlan)) return;
    _shownPlan = plan;
    final s = state;
    final cur = s.current;
    final ni = _upcomingIndex();
    final notifier = ref.read(mixPlanProvider.notifier);
    if (plan == null || cur == null || ni >= s.queue.length) {
      notifier.state = null;
      return;
    }
    final next = s.queue[ni];
    final service = ref.read(youtubeServiceProvider);
    final a = _analyzer.known(service.knownAudioId(cur.id), minVersion: 4);
    final b = _analyzer.known(service.knownAudioId(next.id), minVersion: 4);
    const samples = 64;
    final stems = plan.stems;
    double? frac(double? sec) =>
        sec == null || !sec.isFinite || plan.length <= 0
        ? null
        : (sec / plan.length).clamp(0.0, 1.0);
    MixBands? bands(BeatGrid? g) {
      final b = g == null ? null : bandsOf(g);
      return b == null ? null : (low: b.low, mid: b.mid, high: b.high);
    }

    notifier.state = MixPlanInfo(
      fromId: cur.id,
      to: next,
      outStart: plan.outStart,
      length: plan.length,
      inStart: plan.inStart,
      inPerOut: plan.speed / plan.outSpeed,
      toWave: b == null ? const [] : waveformOf(b),
      waveRate: waveformRate,
      fromBands: bands(a),
      toBands: bands(b),
      bandRate: BeatGrid.featureRate,
      outStages: [
        for (var i = 0; i <= samples; i++)
          plan.stage(i / samples, incoming: false),
      ],
      inStages: [
        for (var i = 0; i <= samples; i++)
          plan.stage(i / samples, incoming: true),
      ],
      voiceOff: frac(stems?.duckAt),
      voiceSwap: frac(stems?.exchangeAt),
    );
  }

  bool _handleBeatMix(Duration pos) {
    if (!_crossfading && (pauseAtEndOfTrack || !state.automix)) {
      _publishMixPlan(null);
    }
    if (_crossfading || pauseAtEndOfTrack || !state.automix) return false;
    final s = state;
    // Verso la fine il successivo potrebbe essere comparso solo ora (la
    // radio lo aggiunge tardi): lo si prepara e analizza adesso.
    final cur = s.current;
    if (cur != null &&
        _lateWarmFor != cur.id &&
        s.duration - pos < const Duration(seconds: 60)) {
      _lateWarmFor = cur.id;
      _warmNextTrack(cur);
      _requestGrids();
    }
    // Il successivo e' cambiato (messo in coda a mano, la coda
    // riordinata) o AutoMix e' stato acceso a brano gia' partito: si
    // prepara adesso, non nell'ultimo minuto. Senza, il piano — e il suo
    // segno sulla barra — arrivava solo verso la fine.
    final ni = _upcomingIndex();
    if (cur != null &&
        ni < s.queue.length &&
        _gridsKey != '${cur.id}>${s.queue[ni].id}' &&
        pos > const Duration(seconds: 3)) {
      _requestGrids();
    }
    final plan = _beatPlanNow();
    _publishMixPlan(plan);
    if (plan == null) {
      if (cur != null &&
          _noPlanLoggedFor != cur.id &&
          s.duration - pos < const Duration(seconds: 25)) {
        _noPlanLoggedFor = cur.id;
        _logWhyNoPlan();
      }
      return false;
    }
    final start = plan.outStart;
    final now = pos.inMilliseconds / 1000;
    if (now > start + 0.3) {
      // Il punto e' passato (un salto in avanti, un caricamento lento). Una
      // volta sola si rifa' il piano da qui in avanti: lasciar perdere
      // voleva dire far finire il brano col suo silenzio in coda e
      // l'altro dal suo silenzio iniziale.
      debugPrint(
        'mix: punto passato (a ${now.toStringAsFixed(1)} s, pronto '
        '$_beatReady, caricamento $_beatLoading)',
      );
      if (cur != null && _lateFor != cur.id) {
        // L'uscente poteva gia' andare verso il tempo d'incontro: torna al
        // suo, il piano nuovo decide di nuovo.
        _rateToken++;
        _outRampKey = null;
        unawaited(_setTempo(_player, 1.0));
        _lateFor = cur.id;
        _lateFrom = double.parse((now + 2.5).toStringAsFixed(1));
        _beatPlanKey = null;
        _beatPlan = null;
        return true;
      }
      _beatPlan = null;
      return false;
    }
    // Tempi lontani: l'uscente va verso il tempo d'incontro nelle otto
    // battute prima del mix, a passi che non si sentono.
    if (plan.outSpeed != 1 && _outRampKey != _beatPlanKey) {
      final bar = plan.bars > 0 ? plan.length / plan.bars : 2.0;
      final from = start - 8 * bar;
      if (now >= from) {
        _outRampKey = _beatPlanKey;
        unawaited(_rampOutgoing(from, start, plan.outSpeed));
      }
    }
    if (!_beatLoading && now >= start - 6) {
      _beatLoading = true;
      unawaited(_prepareBeatMix(plan));
    }
    if (_beatReady && _beatStartTimer == null && now >= start - 1.5) {
      // Dov'e' l'uscente adesso, contando il tempo dall'ultimo
      // aggiornamento di posizione — alla velocita' a cui sta suonando.
      final rate = _tempoOf(_player);
      final sinceUpdate =
          DateTime.now().difference(_posAt).inMicroseconds / 1e6;
      final delay = (start - (now + sinceUpdate * rate)) / rate - _playLead;
      _crossfading = true;
      _beatStartTimer = Timer(
        Duration(microseconds: (delay * 1e6).round().clamp(0, 5000000)),
        () => unawaited(_startBeatMix(plan)),
      );
    }
    return true;
  }

  /// Per quale piano l'uscente ha gia' cominciato ad andare verso il tempo
  /// d'incontro.
  String? _outRampKey;

  /// Porta l'uscente da velocita' 1 a [target] fra [from] e [to] secondi
  /// del brano, seguendo la sua posizione: arriva al tempo d'incontro
  /// esattamente all'inizio del mix.
  Future<void> _rampOutgoing(double from, double to, double target) async {
    final token = ++_rateToken;
    final p = _player;
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (token != _rateToken || p != _player || !state.isPlaying) return;
      final at = (_posOf[p]?.inMilliseconds ?? 0) / 1000;
      final f = ((at - from) / (to - from)).clamp(0.0, 1.0);
      await _setTempo(p, 1 + (target - 1) * f);
      if (f >= 1) return;
    }
  }

  /// Carica il successivo fermo sul suo primo battere, gia' alla velocita'
  /// del mix, senza bassi e a volume zero.
  Future<void> _prepareBeatMix(BeatMixPlan plan) async {
    // Il mix suona i brani interi, voce compresa: la voce torna piano,
    // qualche secondo prima, invece che di colpo sul battere.
    _karaokeLeave();
    final s = state;
    final ni = _upcomingIndex();
    if (ni >= s.queue.length) return;
    final key = _beatPlanKey;
    final incoming = _idle;
    try {
      await _vol(incoming, 0);
      // Entra gia' con le bande dell'inizio del mix: senza bassi, medi
      // bassi.
      _bands[incoming] = plan.stage(0, incoming: true);
      _trimDb[incoming] = levelTrimDb(
        outLevel: plan.outLevel ?? 0,
        inLevel: plan.inLevel ?? 0,
      );
      await _loadAndPlay(
        s.queue[ni],
        target: incoming,
        paused: true,
        startAt: Duration(milliseconds: (plan.inStart * 1000).round()),
        // L'etichetta dello spostamento entra nella catena adesso, col
        // brano fermo e muto: quando si sente, e' gia' al suo tono.
        keyShift: plan.keyShift,
      ).timeout(const Duration(seconds: 5));
      await _setTempo(incoming, plan.speed);
      await _loadStem(plan.outSpeed).timeout(const Duration(seconds: 3));
      await _loadStemIn(
        incoming,
        plan.speed,
      ).timeout(const Duration(seconds: 3));
      debugPrint(
        'mix: pronto (stem uscente $_stemLoaded, entrante $_stemInLoaded)',
      );
      if (_beatPlanKey == key) _beatReady = true;
    } catch (e) {
      debugPrint('mix: entrante non pronto ($e)');
      if (_beatPlanKey == key) _beatPlan = null;
    }
  }

  /// Il mix a tempo vero e proprio.
  Future<void> _startBeatMix(BeatMixPlan plan) async {
    _beatStartTimer = null;
    _karaokeStop();
    final s = state;
    final nextIdx = _upcomingIndex();
    if (!_crossfading || nextIdx >= s.queue.length) return;
    final nextTrack = s.queue[nextIdx];
    final outgoing = _player;
    final incoming = _idle;
    final vol = s.volume;
    final gen = ++_crossfadeGen;
    final outCut = outgoingCutDb(
      outLevel: plan.outLevel ?? 0,
      inLevel: plan.inLevel ?? 0,
    );

    // Il play parte in anticipo della sua latenza: il battere, per
    // l'entrante, e' fra [_playLead] secondi.
    final started = DateTime.now().add(
      Duration(microseconds: (_playLead * 1e6).round()),
    );
    // Il tratto separato parte insieme all'entrante: all'istante zero e'
    // identico all'uscente, e in 40 ms ne prende il posto.
    final useStem = _stemLoaded;
    final useStemIn = _stemInLoaded;
    debugPrint(
      'mix: parte (stem uscente $useStem, entrante $useStemIn, voce spenta a '
      '${plan.stems?.duckAt.toStringAsFixed(2)}, passaggio '
      '${plan.stems?.exchangeAt?.toStringAsFixed(2)})',
    );
    await Future.wait([
      incoming.play(),
      if (useStem) _stem.play(),
      if (useStemIn) _stemIn.play(),
    ]);
    debugDrift.clear();
    var firstCheck = true;
    state = state.copyWith(mixing: true);
    final mixFrom = s.current;
    if (mixFrom != null) {
      ref.read(mixInfoProvider.notifier).state = MixInfo(
        from: mixFrom,
        to: nextTrack,
        progress: 0,
      );
    }
    var lastMixShown = -1;
    // Oltre la fine della musica: l'ultima battuta si ripete, a tempo.
    if (plan.loops) {
      final native = outgoing.platform;
      if (native is mk.NativePlayer) {
        await native.setProperty(
          'ab-loop-a',
          plan.loopStart!.toStringAsFixed(3),
        );
        await native.setProperty('ab-loop-b', plan.loopEnd!.toStringAsFixed(3));
      }
    }

    // Secondi veri: l'uscente puo' suonare piu' svelto o piu' piano.
    final total = plan.wallLength;
    var lastBands = -1000;
    var lastDrift = 0;

    // Il controllo del tempo (vedi mix_sync.dart): nei mix a tempo i
    // player dell'entrante — quello vero e il suo tratto separato, se c'e' —
    // si tengono sulla fase di quello che si sente dell'uscente, il tratto
    // separato o l'uscente stesso. Una misura a ogni fotogramma, una
    // correzione a ogni controllo, sulla mediana delle misure.
    // C'e' una fase da tenere solo nei mix a tempo, con le due griglie:
    // gli altri restano sull'orologio, come prima.
    final phased =
        mixPhaseOffset(plan, outAt: plan.outStart, inAt: plan.inStart) != null;
    final outRef = useStem ? _stem : outgoing;
    final inSide = [incoming, if (useStemIn) _stemIn];
    final heard = useStemIn ? _stemIn : incoming;
    final phase = {for (final p in inSide) p: <double>[]};
    final nudgeOf = {for (final p in inSide) p: 0.0};
    final checked = <double>[];
    var corrections = 0;
    var maxNudge = 0.0;
    final token = ++_fadeToken;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (token != _fadeToken || gen != _crossfadeGen) {
        timer.cancel();
        return;
      }
      final ms = DateTime.now().difference(started).inMilliseconds;
      if (ms < 0) return; // il battere non e' ancora arrivato
      final t = (ms / (total * 1000)).clamp(0.0, 1.0);
      // Trenta volte al secondo bastano all'occhio, e sono la meta' dei
      // ridisegni.
      if (mixFrom != null && ms - lastMixShown >= 33) {
        lastMixShown = ms;
        ref.read(mixInfoProvider.notifier).state = MixInfo(
          from: mixFrom,
          to: nextTrack,
          progress: t,
        );
      }
      final o = plan.stage(t, incoming: false);
      final i = plan.stage(t, incoming: true);
      final g = mixGains(
        o.volume,
        i.volume,
        outCutDb: outCut,
        outShape: o,
        inShape: i,
      );
      if (useStem) {
        final x = (ms / 40).clamp(0.0, 1.0);
        _vol(outgoing, vol * g.out * (1 - x));
        _vol(_stem, vol * g.out * x);
      } else {
        _vol(outgoing, vol * g.out);
      }
      if (useStemIn) {
        // Il tratto dell'entrante suona per tutto il mix; negli ultimi
        // 50 ms restituisce il posto all'entrante vero, identico a lui a
        // quel punto perche' la voce e' gia' entrata.
        final back = ((ms - (total * 1000 - 60)) / 50).clamp(0.0, 1.0);
        _vol(_stemIn, vol * g.inc * (1 - back));
        _vol(incoming, vol * g.inc * back);
      } else {
        _vol(incoming, vol * g.inc);
      }
      if (ms - lastBands >= 40 || t >= 1.0) {
        lastBands = ms;
        unawaited(_setBands(useStem ? _stem : outgoing, o));
        unawaited(_setBands(incoming, i));
        if (useStemIn) unawaited(_setBands(_stemIn, i));
      }
      // La fase, a ogni fotogramma: dove cade il battito dell'entrante
      // rispetto a quello dell'uscente che si sente. Le posizioni si
      // contano adesso, non all'ultimo aggiornamento di ognuna.
      if (phased) {
        final o = _posNow(outRef, after: started);
        if (o != null) {
          final outAt = useStem ? plan.outStart + o : o;
          for (final p in inSide) {
            final x = _posNow(p, after: started);
            if (x == null) continue;
            final off = mixPhaseOffset(
              plan,
              outAt: outAt,
              inAt: p == _stemIn ? plan.inStart + x : x,
            );
            if (off != null) phase[p]!.add(off);
          }
        }
      }
      // La deriva, ogni mezzo secondo. Si corregge con un filo di velocita'
      // in piu' o in meno, mai con un salto, che si sentirebbe.
      if (ms - lastDrift >= 500) {
        lastDrift = ms;
        // Dove dovrebbe essere l'entrante a quest'ora, e dove e': resta la
        // misura della latenza di partenza, e il riferimento dei mix senza
        // battiti in comune.
        final actual = _posOf[incoming];
        if (actual != null) {
          final expected = plan.inStart + ms / 1000 * plan.speed;
          final err = expected - actual.inMilliseconds / 1000;
          debugDrift.add(err);
          if (firstCheck) {
            // Il primo scarto e' quasi tutto latenza di partenza: la
            // prossima volta si parte prima di tanto. Non da un entrante
            // spostato di tonalita': mpv conta il suono ancora nel buffer
            // d'uscita alla sua velocita', non a quella vera, e la sua
            // posizione e' avanti (o indietro) di un 6% di quel buffer,
            // una decina di millesimi fissi che non sono latenza.
            firstCheck = false;
            if (plan.keyShift == 0) {
              _playLead = (_playLead + err * 0.8).clamp(0.0, 0.5);
            }
          }
          // Sotto i trenta millesimi e' il passo con cui arrivano le
          // posizioni, non una deriva: misurato, oscilla di +-28 ms con lo
          // stesso disegno a ogni mix. Inseguirlo faceva solo tremare la
          // velocita'.
          if (!phased) {
            final nudge = err.abs() < 0.03
                ? 0.0
                : (err * 0.6).clamp(-0.05, 0.05);
            unawaited(_setTempo(incoming, plan.speed * (1 + nudge)));
          }
        }
        // Il tratto separato dell'uscente sull'orologio, alla velocita'
        // dell'uscente: e' lui il riferimento della fase, quando c'e'.
        final stemAt = useStem ? _posOf[_stem] : null;
        if (stemAt != null) {
          final err = ms / 1000 * plan.outSpeed - stemAt.inMilliseconds / 1000;
          final nudge = err.abs() < 0.03 ? 0.0 : (err * 0.6).clamp(-0.05, 0.05);
          unawaited(_setTempo(_stem, plan.outSpeed * (1 + nudge)));
        }
        if (phased) {
          // Nei mix a tempo l'entrante non va piu' sull'orologio ma sulla
          // fase dell'uscente: la mediana delle misure del mezzo secondo
          // toglie gli scatti delle posizioni, e sopra i 25 ms si corregge.
          for (final p in inSide) {
            final samples = phase[p]!;
            if (samples.length < syncMinSamples) continue;
            final off = medianOf(samples);
            samples.clear();
            final nudge = syncNudge(off);
            if (p == heard) checked.add(off);
            if (nudge != 0) corrections++;
            if (nudge.abs() > maxNudge.abs()) maxNudge = nudge;
            final was = nudgeOf[p]!;
            nudgeOf[p] = nudge;
            unawaited(_setTempo(p, plan.speed * (1 + nudge)));
            if (nudge != 0 || was != 0) {
              debugPrint(
                'mix: a tempo a ${(ms / 1000).toStringAsFixed(1)} s: '
                '${p == _stemIn ? 'tratto entrante' : 'entrante'} '
                '${_ms(off)} ms dalla fase dell\'uscente '
                '(${p == heard ? 'si sente' : 'muto'}), velocita\' '
                '${nudge >= 0 ? '+' : ''}${(nudge * 100).toStringAsFixed(1)}%',
              );
            }
          }
        } else {
          // Senza battiti in comune il tratto dell'entrante va
          // sull'orologio, come l'entrante.
          final inAt = useStemIn ? _posOf[_stemIn] : null;
          if (inAt != null) {
            final err = ms / 1000 * plan.speed - inAt.inMilliseconds / 1000;
            final nudge = err.abs() < 0.03
                ? 0.0
                : (err * 0.6).clamp(-0.05, 0.05);
            unawaited(_setTempo(_stemIn, plan.speed * (1 + nudge)));
          }
        }
      }
      if (t < 1.0) return;
      timer.cancel();
      if (phased) {
        final worst = checked.fold(0.0, (m, x) => math.max(m, x.abs()));
        debugPrint(
          'mix: controllo del tempo: ${checked.length} controlli, scarto '
          'mediano ${_ms(medianOf(checked))} ms, massimo ${_ms(worst)} ms, '
          '$corrections correzioni (al massimo '
          '${(maxNudge * 100).toStringAsFixed(1)}%)',
        );
      }
      _finishCrossfade(outgoing, incoming, nextIdx, nextTrack, vol);
      unawaited(_rampRate(incoming, from: plan.speed));
    });
  }

  /// Uno scarto in millisecondi col segno, per il registro.
  static String _ms(double seconds) {
    final v = (seconds * 1000).round();
    return v > 0 ? '+$v' : '$v';
  }

  /// Dopo un mix a tempo l'entrante torna piano alla sua velocita': da otto
  /// a venti secondi secondo quanto era spostato, a passi che non si
  /// sentono.
  ///
  /// Torna il tempo, non il tono: lo spostamento di tonalita' resta fino
  /// alla fine del brano (vedi keyShiftChain), e alla fine della rampa mpv
  /// suona a 1 diviso il suo rapporto, con scaletempo2 che toglie il 5,9%
  /// di troppo.
  Future<void> _rampRate(mk.Player p, {required double from}) async {
    if ((from - 1).abs() < 0.001) {
      await _setTempo(p, 1.0);
      return;
    }
    final token = ++_rateToken;
    // Otto secondi per un 4%, di piu' per salti piu' grandi: col tempo
    // blend l'entrante puo' essere spostato del 12%, e riportarlo in otto
    // secondi si sentiva come un brano che accelera.
    final steps = (40 * (from - 1).abs() / 0.04).round().clamp(40, 100);
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (token != _rateToken || p != _player) return;
      await _setTempo(p, from + (1 - from) * i / steps);
    }
  }

  Future<void> _clearLoop(mk.Player p) async {
    try {
      final native = p.platform;
      if (native is! mk.NativePlayer) return;
      await native.setProperty('ab-loop-a', 'no');
      await native.setProperty('ab-loop-b', 'no');
    } catch (_) {}
  }

  /// Scambio dei ruoli a dissolvenza conclusa.
  /// Interrompe una dissolvenza in corso.
  ///
  /// Durante una dissolvenza suonano due player. Un play esplicito ne
  /// caricava uno solo e l'altro restava in riproduzione: si sentivano due
  /// canzoni insieme, e nessuna delle due spariva finche' non finiva da
  /// sola. Qui si ferma quello entrante e si riporta il volume dove deve
  /// stare, perche' la dissolvenza lo aveva lasciato a meta' corsa.
  void _abortCrossfade() {
    _beatStartTimer?.cancel();
    _dropStem();
    _beatStartTimer = null;
    _beatPlanKey = null;
    _beatPlan = null;
    _beatLoading = false;
    _beatReady = false;
    if (!_crossfading) return;
    unawaited(_clearLoop(_player));
    state = state.copyWith(mixing: false);
    ref.read(mixInfoProvider.notifier).state = null;
    _crossfading = false;
    _crossfadeGen++;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeToken++;
    final vol = state.volume;
    _idle.stop();
    _vol(_idle, vol);
    _vol(_player, vol);
    // Interrotto a meta' scambio, il brano che resta potrebbe essere senza
    // bassi.
    unawaited(_setBands(_player, _flat));
    _trimDb.remove(_player);
  }

  void _finishCrossfade(
    mk.Player outgoing,
    mk.Player incoming,
    int nextIdx,
    Track nextTrack,
    double vol,
  ) {
    _recordStats();
    outgoing.stop();
    _dropStem();
    _vol(outgoing, vol);
    _vol(incoming, vol);
    unawaited(_setBands(incoming, _flat));
    _bands.remove(outgoing);
    _trimDb.remove(outgoing);
    unawaited(_glideTrim(incoming));

    _useA = !_useA;
    state = state.copyWith(
      currentIndex: nextIdx,
      isPlaying: true,
      isLoading: false,
      clearError: true,
      position: _posOf[incoming] ?? Duration.zero,
    );
    // La durata dell'entrante: il suo player l'aveva gia' annunciata mentre
    // era in attesa, quando non era lui a suonare, e non la ripete. Senza,
    // dopo ogni mix la barra teneva la durata del brano prima — e AutoMix
    // la usava per sapere quando preparare il successivo.
    _adoptDuration(incoming.state.duration);

    _playStartedAt = DateTime.now();
    _lastStatsTrackId = nextTrack.id;
    _retryCount = 0;
    _crossfading = false;
    state = state.copyWith(mixing: false);
    ref.read(mixInfoProvider.notifier).state = null;
    _beatPlanKey = null;
    _beatPlan = null;
    _beatLoading = false;
    _beatReady = false;
    unawaited(_clearLoop(outgoing));
    _requestGrids();

    // Il testo del brano nuovo, per sapere dove finira' la sua voce.
    unawaited(_loadVocalsEnd(nextTrack));

    ref.read(recentlyPlayedProvider.notifier).add(nextTrack);
    _persist(now: true);
    _warmNextTrack(nextTrack);
    // Anche dopo un mix: la radio si riforniva solo al cambio di brano
    // normale, e con AutoMix la coda arrivava in fondo vuota.
    _topUpRadio();
    unawaited(_karaokeStart(nextTrack));
    _syncNowPlaying();
  }

  /// Cio' che va fatto una volta che il brano suona, da qualunque strada sia
  /// arrivato — file locale o rete.
  ///
  /// Sta in un metodo perche' ci sono due percorsi d'ingresso: quando ne
  /// esisteva uno solo questa coda di operazioni stava in fondo a
  /// `_loadAndPlay`, e duplicarla sarebbe il modo piu' rapido per farle
  /// divergere.
  void _afterOpen(Track track, {Duration? startAt}) {
    unawaited(_karaokeStart(track));
    state = state.copyWith(clearError: true, isLoading: false, isPlaying: true);
    // Il volume si gestisce QUI, non in playTrack: la coda avanza con
    // next() -> playAt(), che non passa da playTrack. La dissolvenza in
    // entrata stava solo la', quindi dopo un crossfade il volume restava
    // a zero e l'app suonava muta fino al riavvio.
    if (state.automix) {
      _fadeVolume(0, state.volume, const Duration(milliseconds: 600));
    } else {
      _restoreVolume();
    }
    // Registrato qui e non in playTrack, cosi' conta anche avanzare nella
    // coda: prima finiva nei recenti solo il brano scelto a mano.
    ref.read(recentlyPlayedProvider.notifier).add(track);
    _persist(now: true);
    unawaited(_loadVocalsEnd(track));
    _warmNextTrack(track);
    _requestGrids();
    _topUpRadio();
    _enrichAlbumInfo(track);
  }

  Future<void> _loadAndPlay(
    Track track, {
    int attempt = 0,
    bool preferHls = false,
    Duration? startAt,
    // Quando valorizzato si apre su quel player e non si tocca lo stato:
    // e' il modo in cui il crossfade prepara il brano successivo senza
    // duplicare tutta la catena di risoluzione degli stream.
    mk.Player? target,
    // Aperto e fermo, pronto a partire: AutoMix lo fa suonare sul battere
    // esatto del brano uscente, e aprire in quell'istante sarebbe tardi.
    bool paused = false,
    // Lo spostamento di tonalita' con cui suonera' (vedi _prepareFilters):
    // quello del piano per l'entrante di un mix, zero per tutto il resto.
    int keyShift = 0,
  }) async {
    final into = target ?? _player;
    final silent = target != null;
    if (!silent) {
      _loading = true;
      // La base del brano di prima non vale per questo.
      _karaokeStop();
    }
    try {
      // Prima il file locale, poi la rete.
      //
      // Questa riga mancava, ed era il buco piu' grosso rimasto: il
      // preloader scaricava i brani interi — fino a due giga — e nessuno
      // li riapriva mai. Si pagava banda e disco per niente, e i download
      // scelti non avrebbero avuto alcun effetto. Con il file locale il
      // brano parte all'istante e funziona anche senza rete.
      final service = ref.read(youtubeServiceProvider);
      // Da dove viene il suono: per un videoclip, la sua versione canzone.
      // Anche il file locale si cerca con questo id, altrimenti un
      // videoclip gia' in scorta continuerebbe a suonare col suo intro.
      final audioId = await service.audioIdFor(track.id);
      // E anche come si presenta: titolo, copertina e durata della canzone,
      // non del video. Nella coda si sostituisce la stessa voce — stesso
      // id — cosi' player, mini player e schermata di blocco la mostrano
      // gia' pulita.
      final dressed = service.dressed(track);
      if (!identical(dressed, track) && !silent) {
        final i = state.currentIndex;
        if (i >= 0 && i < state.queue.length && state.queue[i].id == track.id) {
          final q = [...state.queue]..[i] = dressed;
          state = state.copyWith(queue: q);
        }
        track = dressed;
      }
      final local = await ref.read(songPreloaderProvider).fileFor(audioId);
      if (local != null) {
        await _prepareFilters(
          into,
          audioId,
          silent: silent,
          keyShift: keyShift,
        );
        await into.open(mk.Media(local.path, start: startAt), play: !paused);
        if (!silent) {
          _afterOpen(track, startAt: startAt);
        }
        return;
      }

      // Streaming immediato attraverso il proxy validante: nessun blocco
      // per scaricare il file intero (era la causa della clessidra su reti
      // lente/flaggate). Ogni URL candidato viene sondato con GET ranged
      // (offset 0 e oltre la finestra anti-bot di ~1 MiB): una sorgente
      // flaggata cade sul client successivo qui, invece di uccidere la
      // riproduzione dopo ~1:04.
      // NB: preferHls=true preferisce l'HLS (segmenti immuni al taglio
      // progressivo da 1 MiB) quindi le canzoni durano intere.
      var rs = await service
          .resolveAudio(audioId, attempt: attempt, preferHls: preferHls)
          .timeout(const Duration(seconds: 45));
      rs ??= await service
          .resolveAudio(audioId, attempt: attempt + 1, preferHls: !preferHls)
          .timeout(const Duration(seconds: 45));

      // Niente HLS/progressivo valido? Ultimo giro forzando l'HLS: i
      // segmenti sfuggono al taglio dei ~1 MiB sugli URL progressivi.
      if (rs == null) {
        rs = await service
            .resolveAudio(audioId, attempt: attempt + 2, preferHls: true)
            .timeout(const Duration(seconds: 45));
      }
      if (rs == null) {
        throw Exception(
          'No stream available: Google is blocking this session. '
          'Add your YouTube cookie in the settings to unblock it.',
        );
      }
      developer.log(
        'PLAYER url=${rs.url.length > 50 ? rs.url.substring(0, 50) : rs.url} '
        'client=${rs.clientName} hls=${rs.isHls} retry=$attempt',
      );

      // Route playback through the local proxy: it adds the headers the
      // stream requires, serves verified <=1 MiB chunks and — crucially —
      // swaps in a freshly-resolved URL mid-song when Google kills the
      // current one, so the player never sees the interruption.
      final proxy = ref.read(streamProxyProvider);
      if (!proxy.isRunning) {
        await proxy.start();
      }
      var nextAttempt = attempt + 2;
      final playable = proxy.proxiedUrl(
        rs.url,
        userAgent: rs.userAgent,
        hls: rs.isHls,
        refresh: () async {
          // Preferire l'HLS al refresh: i segmenti sono immuni al taglio
          // progressivo di ~1 MiB che uccideva i brani a ~1:04.
          final r2 = await service
              .resolveAudio(audioId, attempt: nextAttempt++, preferHls: true)
              .timeout(const Duration(seconds: 60));
          if (r2 == null) return null;
          developer.log(
            'PROXY refresh -> client=${r2.clientName} '
            'hls=${r2.isHls}',
          );
          return ProxiedStreamSource(r2.url, userAgent: r2.userAgent);
        },
      );
      debugPrint('Proxy URL: $playable (hls=${rs.isHls})');

      await _prepareFilters(into, audioId, silent: silent, keyShift: keyShift);
      try {
        await into.open(mk.Media(playable, start: startAt), play: !paused);
      } catch (e) {
        // An HLS manifest the player refuses to open: fall back to a
        // progressive stream instead of surfacing an error.
        if (rs.isHls) {
          debugPrint('HLS non apribile ($e), ripiego sul progressivo');
          final alt = await service
              .resolveAudio(audioId, attempt: nextAttempt++, preferHls: false)
              .timeout(const Duration(seconds: 60));
          if (alt != null) {
            final playable2 = proxy.proxiedUrl(
              alt.url,
              userAgent: alt.userAgent,
            );
            await into.open(mk.Media(playable2, start: startAt), play: !paused);
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      if (!silent) {
        state = state.copyWith(clearError: true, isLoading: false);
      }
      if (!paused) await into.play();
      // Quando si prepara il brano per il crossfade il volume, lo stato e le
      // statistiche li gestisce chi ha chiesto la preparazione: qui si
      // aprirebbe e basta.
      if (silent) return;
      _afterOpen(track);
    } catch (e) {
      debugPrint('ERRORE riproduzione ${track.id}: $e');
      developer.log('PLAYER errore: $e');
      final err = 'Error: \$e';
      // Se il caricamento fallisce dopo una dissolvenza in uscita, il volume
      // resterebbe a zero anche per il brano successivo.
      _restoreVolume();
      state = state.copyWith(error: err, isLoading: false, isPlaying: false);
      // Auto-clear after a while so a stale error doesn't linger forever
      // (the mini player showed it as a persistent yellow bar).
      Timer(const Duration(seconds: 10), () {
        if (state.error == err) {
          state = state.copyWith(clearError: true);
        }
      });
      // Do NOT auto-skip: keep the error visible so the user can report it.
    } finally {
      _loading = false;
    }
  }

  Future<void> toggle() async {
    if (state.current == null) return;
    // A restored session has a queue and a position but nothing open, so
    // playOrPause would be a no-op. The first press loads it for real.
    if (_pendingResume != null) return resumeSession();
    await _player.playOrPause();
  }

  Future<void> seek(Duration position) async {
    // Sessione ripristinata e non ancora aperta: non c'e' niente da spostare
    // nel motore, si sposta il punto da cui ripartira' al primo play (senza,
    // la barra tornava indietro appena lasciata).
    if (_pendingResume != null) {
      _pendingResume = position;
      state = state.copyWith(position: position);
      _syncNowPlaying();
      return;
    }
    if (_karaokeOn) unawaited(_base.seek(position));
    await _player.seek(position);
  }

  /// Per il timer di spegnimento: a fine brano si ferma invece di passare
  /// al successivo.
  ///
  /// Sta qui e non in chi usa il timer: da fuori ci si accorgerebbe della
  /// fine solo quando il brano dopo e' gia' partito, e se ne sentirebbe
  /// l'attacco prima della pausa. Qui invece si evita anche il crossfade,
  /// che il successivo lo farebbe partire secondi prima della fine.
  bool pauseAtEndOfTrack = false;

  /// Chiamata quando il timer di fine brano ha fatto il suo lavoro.
  VoidCallback? onPausedAtEndOfTrack;

  /// Abbassa piano e mette in pausa: il timer di spegnimento non stacca di
  /// colpo, che nel dormiveglia sveglierebbe. Il volume torna com'era
  /// subito dopo, cosi' il prossimo play non parte muto.
  Future<void> fadeOutAndPause({
    Duration fade = const Duration(seconds: 8),
  }) async {
    if (!state.isPlaying) return;
    _fadeVolume(state.volume, 0, fade);
    await Future<void>.delayed(fade);
    await _player.pause();
    _restoreVolume();
  }

  /// Sets the output volume (0-100).
  Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 100.0);
    state = state.copyWith(volume: v);
    await _vol(_player, v);
  }

  /// Nudges the volume, for the keyboard shortcuts.
  Future<void> adjustVolume(double delta) => setVolume(state.volume + delta);

  // --- Session persistence -------------------------------------------------

  /// Writes the queue and playback state to disk.
  ///
  /// [now] bypasses the throttle; discrete events (track change, queue edit,
  /// mode toggle, play/pause) use it. The position listener does not: it
  /// fires several times a second, and writing every tick would hammer Hive
  /// for no benefit.
  void _persist({bool now = false}) {
    if (!_restored) return;
    if (!now) {
      final since = DateTime.now().difference(_lastPersist);
      if (since < const Duration(seconds: 5)) return;
    }
    _lastPersist = DateTime.now();

    final storage = ref.read(storageServiceProvider);
    final s = state;
    if (s.queue.isEmpty) {
      unawaited(storage.clearPlaybackSession());
      return;
    }
    unawaited(storage.saveQueue(s.queue));
    unawaited(
      storage.savePlaybackSession(
        index: s.currentIndex,
        position: s.position,
        duration: s.duration,
        shuffle: s.shuffle,
        repeat: s.repeat.name,
        crossfade: s.crossfadeDuration,
        radio: ref.read(radioProvider),
        automix: s.automix,
      ),
    );
  }

  /// Public hook for the app lifecycle (window close, backgrounding).
  void persistNow() => _persist(now: true);

  /// Rebuilds the last session's state *without* opening anything.
  ///
  /// No media, no network: the mini player simply reappears showing the
  /// track where you left it, paused. The stream is resolved only when the
  /// user presses play, because a saved URL would have expired anyway.
  Future<void> restoreSession() async {
    _restored = true;
    final storage = ref.read(storageServiceProvider);
    final queue = storage.savedQueue;
    if (queue.isEmpty) return;

    final saved = storage.playbackSession;
    final index = (saved['index'] as int? ?? 0).clamp(0, queue.length - 1);
    final position = Duration(milliseconds: saved['positionMs'] as int? ?? 0);

    state = state.copyWith(
      queue: queue,
      currentIndex: index,
      position: position,
      duration: Duration(milliseconds: saved['durationMs'] as int? ?? 0),
      isPlaying: false,
      isLoading: false,
      shuffle: saved['shuffle'] as bool? ?? false,
      repeat: RepeatMode.values.firstWhere(
        (r) => r.name == saved['repeat'],
        orElse: () => RepeatMode.off,
      ),
      crossfadeDuration: Duration(
        milliseconds: saved['crossfadeMs'] as int? ?? 0,
      ),
      // Chi aveva una dissolvenza fissa, che non esiste piu', aveva scelto
      // di avere le transizioni: si ritrova AutoMix.
      automix:
          saved['automix'] as bool? ??
          ((saved['crossfadeMs'] as int? ?? 0) > 0),
      clearError: true,
    );
    ref.read(radioProvider.notifier).set(saved['radio'] as bool? ?? false);

    _pendingResume = position;
    _syncNowPlaying();
  }

  /// Solo per le foto del README: da qui in poi la sessione non si salva
  /// piu', cosi' quello che le foto fanno al player resta in memoria.
  void debugStopPersisting() {
    assert(kDebugMode);
    _restored = false;
  }

  /// Solo per le foto del README (lib/dev/readme_shots.dart): mostra
  /// [track] come se fosse la sessione ripristinata, fermo ad [at], seguito
  /// dalla coda di adesso. Non apre niente, e da qui in poi non salva piu'
  /// la sessione: quella vera, sul disco, resta com'era.
  void debugStageForShots(Track track, Duration at) {
    debugStopPersisting();
    final rest = state.queue
        .skip(state.currentIndex + 1)
        .where((t) => t.id != track.id)
        .take(30);
    state = state.copyWith(
      queue: [track, ...rest],
      currentIndex: 0,
      position: at,
      duration: track.duration ?? state.duration,
      isPlaying: false,
      isLoading: false,
    );
    _pendingResume = at;
    _syncNowPlaying();
  }

  /// Per le foto della barra (lib/dev/readme_shots.dart): l'onda del brano
  /// in ascolto subito, e un mix verso il brano dopo — in arrivo, o in corso
  /// a [progress] — senza suonare niente. Le onde sono quelle vere se i
  /// brani sono analizzati.
  void debugMixForShots({double? progress}) {
    final s = state;
    final cur = s.current;
    if (cur == null || s.queue.length < 2) return;
    final next = s.queue[1];
    final service = ref.read(youtubeServiceProvider);
    final a = _analyzer.known(service.knownAudioId(cur.id), minVersion: 4);
    final b = _analyzer.known(service.knownAudioId(next.id), minVersion: 4);
    debugPrint('readme: analisi ${a != null} ${b != null}');
    // Senza analisi (la libreria finta delle foto) un'analisi inventata,
    // per vedere la barra: strofe, ritornelli, un'intro e un finale.
    BeatGrid fake(int seed, double seconds) {
      final r = math.Random(seed);
      final n = (seconds * BeatGrid.featureRate).round();
      final f = <double>[];
      for (var i = 0; i < n; i++) {
        final u = i / n;
        final edge = math.min(1.0, math.min(u * 14, (1 - u) * 10));
        final chorus = (u * 7).floor().isOdd;
        final drop = (u * 23).floor() % 9 == 4;
        f
          ..add(
            drop
                ? -40
                : -24 + 14 * edge * (chorus ? 1 : 0.7) + 2 * r.nextDouble(),
          )
          ..add(-30 + 12 * edge * (chorus ? 1 : 0.8) + 2 * r.nextDouble())
          ..add(-40 + 14 * edge * (chorus ? 1 : 0.6) + 2 * r.nextDouble())
          ..add(18);
      }
      return BeatGrid(
        bpm: 90,
        firstBeat: 0,
        downbeat: 0,
        musicStart: 0,
        musicEnd: seconds,
        confidence: 1,
        features: f,
      );
    }

    final end = s.duration.inMilliseconds / 1000;
    final ga = a ?? fake(1, end);
    final gb = b ?? fake(2, 180);
    ref.read(waveformProvider.notifier).state = (
      trackId: cur.id,
      levels: waveformOf(ga),
    );
    MixBands? bands(BeatGrid g) {
      final x = bandsOf(g);
      return x == null ? null : (low: x.low, mid: x.mid, high: x.high);
    }

    // Un mix quick come quelli veri: l'entrante senza bassi, poi i bassi
    // passano; i medi dell'uscente si abbassano; la voce passa a meta'.
    const samples = 64;
    MixStage outAt(double t) => MixStage(
      volume: t < 0.85 ? 1 : 1 - (t - 0.85) / 0.15,
      low: t < 0.5 ? 0 : -26 * ((t - 0.5) / 0.1).clamp(0.0, 1.0),
      mid: -10 * (t / 0.5).clamp(0.0, 1.0),
    );
    MixStage inAt(double t) => MixStage(
      volume: (t / 0.2).clamp(0.0, 1.0),
      low: t < 0.5 ? -26 : -26 + 26 * ((t - 0.5) / 0.1).clamp(0.0, 1.0),
      mid: -6 + 6 * t,
    );
    ref.read(mixPlanProvider.notifier).state = MixPlanInfo(
      fromId: cur.id,
      to: next,
      outStart: math.max(0, end - 34),
      length: 24,
      inStart: 4,
      inPerOut: 1,
      toWave: waveformOf(gb),
      waveRate: waveformRate,
      fromBands: bands(ga),
      toBands: bands(gb),
      bandRate: BeatGrid.featureRate,
      outStages: [for (var i = 0; i <= samples; i++) outAt(i / samples)],
      inStages: [for (var i = 0; i <= samples; i++) inAt(i / samples)],
      voiceOff: 0.55,
      voiceSwap: 0.5,
    );
    if (progress == null) {
      ref.read(mixInfoProvider.notifier).state = null;
      state = state.copyWith(mixing: false);
      return;
    }
    ref.read(mixInfoProvider.notifier).state = MixInfo(
      from: cur,
      to: next,
      progress: progress,
    );
    state = state.copyWith(mixing: true);
  }

  /// Opens the restored track and picks up at the saved position.
  Future<void> resumeSession() async {
    final at = _pendingResume;
    final track = state.current;
    _pendingResume = null;
    if (track == null) return;
    await playTrack(track, queue: state.queue, startAt: at);
  }

  Future<void> next() async {
    // Anche saltare avanti a mano interrompe una dissolvenza: altrimenti
    // il brano che stava entrando continua a suonare sotto quello nuovo.
    _abortCrossfade();
    final q = state.queue;
    if (q.isEmpty) return;
    // Record stats for the current track before advancing.
    _recordStats();

    // Lo stesso brano che il mix aveva preparato, anche a caso.
    var index = _upcomingIndex();

    if (index >= q.length) {
      if (state.repeat == RepeatMode.all) {
        index = 0;
      } else if (ref.read(radioProvider)) {
        // Radio mode: fetch related tracks and keep playing.
        await _fetchAndAppendRadioTracks();
        final newQ = state.queue;
        if (newQ.length > q.length) {
          index = q.length; // play the first newly added track
        } else {
          // Failed to fetch radio tracks — stop.
          await _player.stop();
          state = state.copyWith(position: Duration.zero, isPlaying: false);
          ref.read(nowPlayingProvider).clear();
          return;
        }
      } else {
        // End of queue: stop.
        await _player.stop();
        state = state.copyWith(position: Duration.zero, isPlaying: false);
        ref.read(nowPlayingProvider).clear();
        return;
      }
    }
    if (index < 0) return;

    await playAt(index);
  }

  Future<void> previous() async {
    _abortCrossfade();
    if (state.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    final q = state.queue;
    if (q.isEmpty) return;
    final index = state.currentIndex - 1;
    if (index < 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await playAt(index);
  }

  Future<void> _onCompleted() async {
    // Guard against premature stream ends (e.g. the proxy losing a range
    // request mid-song): only advance when the track really played to its
    // end. A song that "completed" way before its duration means the
    // stream was cut — retry with a fresh URL/format, and only surface an
    // error when every attempt fails.
    final s = state;
    if (s.duration > const Duration(seconds: 3) &&
        s.position < s.duration - const Duration(seconds: 3)) {
      debugPrint(
        'COMPLETED prematuro: pos=${s.position} dur=${s.duration} '
        'retry=$_retryCount',
      );
      developer.log(
        'PLAYER prematuro pos=${s.position.inSeconds}s '
        'dur=${s.duration.inSeconds}s retry=$_retryCount',
      );
      final track = s.current;
      if (track != null && _retryCount < 3) {
        _retryCount++;
        state = s.copyWith(isLoading: true, clearError: true, isPlaying: false);
        // Retries prefer the HLS playlist when available: segments are
        // small and are not cut by YouTube's 1 MiB stream truncation.
        await _loadAndPlay(
          track,
          attempt: _retryCount,
          preferHls: _retryCount >= 1,
          // Lo stesso brano che riparte: col tono con cui stava suonando.
          keyShift: _keyShift[_player] ?? 0,
        );
        return;
      }
      _retryCount = 0;
      // Record partial listen stats before stopping.
      _recordStats();
      state = s.copyWith(
        isPlaying: false,
        error: 'Playback interrupted: the stream ended early.',
      );
      return;
    }
    _retryCount = 0;
    await _onTrackCompleted();
  }

  Future<void> _onTrackCompleted() async {
    if (_advancing) return;
    _advancing = true;
    try {
      // Record stats for the finished track.
      _recordStats();
      if (pauseAtEndOfTrack) {
        pauseAtEndOfTrack = false;
        state = state.copyWith(isPlaying: false);
        onPausedAtEndOfTrack?.call();
        return;
      }
      if (state.repeat == RepeatMode.one && state.currentIndex >= 0) {
        await _player.seek(Duration.zero);
        await _player.play();
        return;
      }
      await next();
    } finally {
      _advancing = false;
    }
  }

  /// Records play count and listen duration for stats.
  void _recordStats() {
    final trackId = _lastStatsTrackId ?? state.current?.id;
    if (trackId == null) return;
    Duration? listenDuration;
    if (_playStartedAt != null) {
      listenDuration = _listened;
      if (_playingSince != null) {
        listenDuration += DateTime.now().difference(_playingSince!);
      }
    }
    Track? track;
    for (final t in state.queue) {
      if (t.id == trackId) track = t;
    }
    // Un brano della radio ascoltato fino in fondo puo' guidare la radio
    // dopo; uno saltato no.
    if (_radioIds.contains(trackId) &&
        listenDuration != null &&
        listenedThrough(listenDuration, track?.duration ?? state.duration)) {
      _radioLiked.add(trackId);
    }
    ref
        .read(statsProvider.notifier)
        .recordPlay(trackId, listenDuration: listenDuration, track: track);
    _lastStatsTrackId = null;
    _playStartedAt = null;
    _listened = Duration.zero;
    // Se suona ancora (un brano che finisce e il successivo che parte
    // senza pausa), il conteggio riparte da adesso per il nuovo.
    if (_playingSince != null) _playingSince = DateTime.now();
  }

  /// Riempie la coda in anticipo quando la radio e' attiva.
  ///
  /// Prima i brani correlati si chiedevano solo a coda esaurita, cioe' a
  /// brano finito: la pagina Coda restava vuota sotto quello in ascolto e
  /// non si sapeva cosa sarebbe arrivato. Chiedendoli appena il margine
  /// scende, la coda e' sempre popolata e la dissolvenza trova gia' pronto
  /// il brano successivo invece di doverlo aspettare.
  void _topUpRadio() {
    if (!ref.read(radioProvider)) return;
    const margin = 3;
    // Contati i brani che mancano davvero: con la riproduzione casuale la
    // posizione nella coda non dice niente, e la radio partiva a meta'
    // raccolta.
    if (_remaining() >= margin) return;
    unawaited(_fetchAndAppendRadioTracks());
  }

  /// Fetches related tracks from YouTube and appends them to the queue.
  /// This is the "radio" / "smart shuffle" feature: when the queue ends
  /// and radio is enabled, the player keeps going with related music.
  Future<void> _fetchAndAppendRadioTracks() async {
    if (_radioFetching) return;
    _radioFetching = true;
    try {
      final current = state.current;
      if (current == null) return;
      final service = ref.read(youtubeServiceProvider);
      final recentlyHeard = _recentlyHeard();
      var fresh = <Track>[];
      // Al massimo due punti di partenza per giro: se la radio del primo e'
      // tutta gia' sentita, si passa al successivo.
      for (var attempt = 0; attempt < 2 && fresh.isEmpty; attempt++) {
        if (_radioPool.isEmpty) {
          final seed =
              pickRadioSeed(
                queue: state.queue,
                current: state.currentIndex,
                radioIds: _radioIds,
                liked: _radioLiked,
                used: _radioSeedsUsed,
              ) ??
              // Nessuno rimasto: come prima, il brano in corso.
              current;
          _radioSeedsUsed.add(seed.id);
          final related = await service.getUpNext(seed.id, artist: seed.author);
          // Nel frattempo e' cambiata la coda (un'altra raccolta): questi
          // non c'entrano piu'.
          if (state.current?.id != current.id) return;
          debugPrint(
            'radio: ${related.length} simili di ${seed.title}'
            '${_radioIds.contains(seed.id) ? ' (dalla radio)' : ''}',
          );
          _radioPool.addAll(related);
        }
        final available = freshRadio(
          _radioPool,
          inQueue: state.queue.map((t) => t.id).toSet(),
          recentlyHeard: recentlyHeard,
        );
        fresh = available.take(5).toList();
        // Si consuma nell'ordine di YouTube, che per la radio di un brano e'
        // gia' pensato per scorrere: via quelli presi e quelli scartati.
        final taken = fresh.map((t) => t.id).toSet();
        final keep = available.skip(5).toList();
        _radioPool
          ..clear()
          ..addAll(keep);
        if (taken.isEmpty) _radioPool.clear();
      }
      if (fresh.isNotEmpty) {
        _radioIds.addAll(fresh.map((t) => t.id));
        state = state.copyWith(queue: [...state.queue, ...fresh]);
        _warmNextTrack(current);
      }
    } catch (e) {
      debugPrint('RADIO errore: $e');
    } finally {
      _radioFetching = false;
    }
  }

  /// I brani sentiti nelle ultime sei ore: la radio non li ripropone.
  Set<String> _recentlyHeard() {
    final since = DateTime.now().subtract(const Duration(hours: 6));
    try {
      return {
        for (final (id, at, _) in ref.read(storageServiceProvider).playLog)
          if (at.isAfter(since)) id,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Best-effort background warmup of the NEXT queue track so advancing
  /// is instant: caches the full song locally for a fast, glitch-free
  /// subsequent play. Fire-and-forget, never blocks or errors.
  void _warmNextTrack(Track current) {
    final q = state.queue;
    if (q.length < 2) return;
    final nextIndex = _upcomingIndex();
    if (nextIndex >= q.length) return;
    final next = q[nextIndex];
    if (next.id == current.id) return;
    try {
      // Shared instance: a throwaway per track change would discard the
      // in-flight dedup map and leak an http.Client each time.
      // Solo se lo vuoi: e' un brano alla volta e ora viene davvero
      // riletto, ma resta banda spesa senza che tu l'abbia chiesto.
      // Con AutoMix sempre: il mix ha bisogno del file.
      if (!ref.read(autoPreloadProvider) && !state.automix) return;
      final preloader = ref.read(songPreloaderProvider);
      final service = ref.read(youtubeServiceProvider);
      unawaited(() async {
        try {
          final id = await service.audioIdFor(next.id);
          await preloader.ensureDownloaded(id);
          // Scaricato, si analizza: il mix a tempo ha bisogno dei suoi
          // battiti prima che tocchi a lui.
          if (state.automix) await _analyzer.gridFor(id);
        } catch (_) {}
      }());
    } catch (_) {}
  }

  /// Background enrichment: if the current track is missing album info,
  /// look it up from the artist's page and update the queue item so the
  /// player screen can show a tappable album link.
  void _enrichAlbumInfo(Track track) {
    // Non serve piu' un artistId: l'album si legge dal byline del brano
    // nella coda watch-next. Prima, senza, si rinunciava — ed e' proprio il
    // caso dei brani della radio, dove l'album non compariva mai.
    if (track.albumId != null) return;
    final service = ref.read(youtubeServiceProvider);
    unawaited(
      (() async {
        try {
          final result = await service.getAlbumForSong(track.id);
          if (result == null) return;
          final q = [...state.queue];
          final idx = q.indexWhere((t) => t.id == track.id);
          if (idx < 0) return;
          q[idx] = q[idx].copyWith(albumId: result.$1, albumName: result.$2);
          state = state.copyWith(queue: q);
          // Also update favorites if this track is favorited.
          final favs = ref.read(favoritesProvider.notifier);
          if (favs.isFavorite(track.id)) {
            // The favorites storage will persist the enriched data on next save.
          }
        } catch (_) {}
      })(),
    );
  }

  /// Karaoke acceso o spento. Acceso, si prepara la base del brano in
  /// corso e, appena c'e', la voce scende al livello scelto.
  void setKaraoke(bool on) {
    final k = ref.read(karaokeProvider);
    ref.read(karaokeProvider.notifier).state = k.copyWith(
      enabled: on,
      clearPreparing: !on,
    );
    if (on) {
      final t = state.current;
      if (t != null && _pendingResume == null) unawaited(_karaokeStart(t));
    } else {
      _karaokeLeave();
    }
  }

  /// Quanta voce resta, da 0 a 1.
  void setKaraokeVoice(double voice) {
    final v = voice.clamp(0.0, 1.0);
    final k = ref.read(karaokeProvider);
    ref.read(karaokeProvider.notifier).state = k.copyWith(voice: v);
    if (!_karaokeOn) return;
    _voiceRamp?.cancel();
    _voiceNow = v;
    unawaited(_vol(_player, _level[_player] ?? state.volume));
  }

  void _publishKaraoke(KaraokeState Function(KaraokeState) change) {
    final n = ref.read(karaokeProvider.notifier);
    n.state = change(n.state);
  }

  /// Porta la voce a [to] in [ms] millisecondi, poi chiama [then].
  void _rampVoice(double to, int ms, [VoidCallback? then]) {
    _voiceRamp?.cancel();
    final from = _voiceNow;
    final started = DateTime.now();
    _voiceRamp = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      final t = (DateTime.now().difference(started).inMilliseconds / ms).clamp(
        0.0,
        1.0,
      );
      _voiceNow = from + (to - from) * t;
      if (_karaokeOn && !_crossfading) {
        unawaited(_vol(_player, _level[_player] ?? state.volume));
      }
      if (t >= 1) {
        timer.cancel();
        then?.call();
      }
    });
  }

  /// Prepara la base di [track] e, se e' ancora lui a suonare, la aggancia.
  Future<void> _karaokeStart(Track track) async {
    if (!ref.read(karaokeProvider).enabled) return;
    try {
      final audioId = await ref
          .read(youtubeServiceProvider)
          .audioIdFor(track.id);
      bool stillHere() =>
          ref.read(karaokeProvider).enabled && state.current?.id == track.id;
      // Serve il file: la separazione legge dal disco, non dallo stream.
      final preloader = ref.read(songPreloaderProvider);
      if (await preloader.fileFor(audioId) == null) {
        _publishKaraoke((k) => k.copyWith(preparing: 0));
        await preloader.ensureDownloaded(audioId);
      }
      if (!stillHere()) return;
      if (_bases.readyFor(audioId) == null) {
        _publishKaraoke((k) => k.copyWith(preparing: 0));
      }
      final file = await _bases.baseFor(
        audioId,
        onProgress: (p) {
          if (stillHere()) _publishKaraoke((k) => k.copyWith(preparing: p));
        },
      );
      if (state.current?.id == track.id) {
        _publishKaraoke((k) => k.copyWith(clearPreparing: true));
      }
      if (file == null || !stillHere() || _crossfading || _karaokeOn) return;

      // La base col tono del brano: se il brano e' stato spostato da un mix,
      // anche lei.
      _copyKeyShift(from: _player, to: _base);
      await _applyChain(_base);
      await _setTempo(_base, _tempoOf(_player));
      await _base.open(mk.Media(file.path, start: state.position), play: false);
      if (!stillHere() || _crossfading) {
        await _base.stop();
        return;
      }
      _karaokeOn = true;
      _voiceNow = 1;
      await _vol(_player, _level[_player] ?? state.volume);
      if (state.isPlaying) await _base.play();
      _publishKaraoke((k) => k.copyWith(active: true));
      // Entra in una rampa: la voce scende, non sparisce.
      _rampVoice(ref.read(karaokeProvider).voice, 600);

      // La base del prossimo, in anticipo e in silenzio, se il suo file
      // c'e' gia': cosi' al cambio di brano il karaoke non si interrompe.
      final ni = _upcomingIndex();
      if (ni < state.queue.length) {
        final nextId = await ref
            .read(youtubeServiceProvider)
            .audioIdFor(state.queue[ni].id);
        if (await preloader.fileFor(nextId) != null) {
          unawaited(_bases.baseFor(nextId));
        }
      }
    } catch (e) {
      debugPrint('karaoke: non agganciato ($e)');
      _publishKaraoke((k) => k.copyWith(clearPreparing: true));
    }
  }

  /// Esce dal karaoke con la voce che torna piano.
  void _karaokeLeave() {
    if (!_karaokeOn) return;
    _rampVoice(1, 900, _karaokeStop);
  }

  /// Esce dal karaoke subito: il brano cambia, o parte un mix.
  void _karaokeStop() {
    _voiceRamp?.cancel();
    if (!_karaokeOn) return;
    _karaokeOn = false;
    _voiceNow = 1;
    unawaited(_base.stop());
    unawaited(_vol(_player, _level[_player] ?? state.volume));
    _publishKaraoke((k) => k.copyWith(active: false));
  }

  /// Tiene la base al passo del brano: un salto se si e' persa, altrimenti
  /// un filo di velocita' in piu' o in meno, che non si sente.
  void _syncKaraoke(Duration pos) {
    if (!_karaokeOn) return;
    final now = DateTime.now();
    if (now.difference(_karaokeCheck).inMilliseconds < 500) return;
    _karaokeCheck = now;
    final at = _posOf[_base];
    if (at == null) return;
    final err = (pos - at).inMilliseconds / 1000;
    final rate = _tempoOf(_player);
    if (err.abs() > 0.25) {
      unawaited(_base.seek(pos + const Duration(milliseconds: 40)));
      return;
    }
    final nudge = err.abs() < 0.03 ? 0.0 : (err * 0.6).clamp(-0.05, 0.05);
    unawaited(_setTempo(_base, rate * (1 + nudge)));
  }

  /// Tempo e tonalita' di un brano, per il riordino. Lo scarica nella
  /// scorta se non c'e': l'analisi legge dal disco. Null se non si riesce.
  Future<MixTraits?> mixTraitsOf(Track track) async {
    try {
      final audioId = await ref
          .read(youtubeServiceProvider)
          .audioIdFor(track.id);
      final preloader = ref.read(songPreloaderProvider);
      if (await preloader.fileFor(audioId) == null) {
        await preloader
            .ensureDownloaded(audioId)
            .timeout(const Duration(seconds: 90));
      }
      // Tempo e tonalita' ci sono gia' nelle analisi della versione 3: non
      // serve rifarle per riordinare.
      final grid = await _analyzer.gridFor(audioId, minVersion: 3);
      if (grid == null || grid.bpm <= 0 || grid.musicEnd <= 0) return null;
      return MixTraits(grid.bpm, grid.key);
    } catch (e) {
      debugPrint('riordino: ${track.title} non analizzato ($e)');
      return null;
    }
  }

  /// [tracks] nell'ordine in cui i passaggi scorrono meglio, per tempo e
  /// tonalita'. Il primo resta il primo. [onProgress] riceve quanti brani
  /// sono stati analizzati; [cancelled], se torna vero, ferma tutto.
  Future<List<Track>?> smartOrderOf(
    List<Track> tracks, {
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final traits = <MixTraits?>[];
    for (var i = 0; i < tracks.length; i++) {
      if (cancelled?.call() ?? false) return null;
      traits.add(await mixTraitsOf(tracks[i]));
      onProgress?.call(i + 1, tracks.length);
    }
    if (cancelled?.call() ?? false) return null;
    final order = smartOrder(traits);
    final before = pathCost(traits, [
      for (var i = 0; i < traits.length; i++) i,
    ]);
    debugPrint(
      'riordino: ${tracks.length} brani, passaggi da '
      '${before.toStringAsFixed(2)} a '
      '${pathCost(traits, order).toStringAsFixed(2)}, '
      '${traits.where((t) => t == null).length} senza analisi',
    );
    return [for (final i in order) tracks[i]];
  }

  /// Riordina cio' che viene dopo il brano in corso, a partire da lui.
  Future<bool> smartReorderUpcoming({
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final s = state;
    final current = s.current;
    if (current == null || s.currentIndex + 2 >= s.queue.length) return false;
    final ordered = await smartOrderOf(
      s.queue.sublist(s.currentIndex),
      onProgress: onProgress,
      cancelled: cancelled,
    );
    if (ordered == null) return false;
    // La coda puo' essere cambiata nel frattempo: si applica solo se il
    // brano in corso e' ancora lui e i brani sono gli stessi.
    final now = state;
    if (now.current?.id != current.id || now.queue.length != s.queue.length) {
      return false;
    }
    if (!_crossfading) _abortCrossfade();
    state = now.copyWith(
      queue: [...now.queue.sublist(0, now.currentIndex), ...ordered],
    );
    _persist(now: true);
    _warmNextTrack(current);
    return true;
  }

  void setShuffle(bool value) {
    // Il brano dopo cambia: il mix preparato non vale piu'. Uno gia' in
    // corso invece finisce: interromperlo taglierebbe l'entrante a meta'.
    if (!_crossfading) _abortCrossfade();
    // La coda cambia ordine davvero, come in Apple Music: "Playing Next"
    // mostra cosi' l'ordine in cui i brani suoneranno. Spento, torna
    // quello della raccolta.
    final s = state;
    var queue = s.queue;
    if (s.current != null && value != s.shuffle) {
      final head = queue.sublist(0, s.currentIndex + 1);
      final upcoming = queue.sublist(s.currentIndex + 1);
      final original = _unshuffled;
      if (value) {
        _unshuffled ??= {for (var i = 0; i < queue.length; i++) queue[i].id: i};
        queue = _shuffled(queue, s.currentIndex);
      } else if (original != null) {
        queue = [
          ...head,
          ...unshuffleUpcoming(upcoming, originalIndex: (t) => original[t.id]),
        ];
      }
    }
    state = state.copyWith(shuffle: value, queue: queue);
    if (s.current != null) _warmNextTrack(s.current!);
    _persist(now: true);
  }

  void toggleShuffle() => setShuffle(!state.shuffle);

  void setRepeat(RepeatMode mode) {
    state = state.copyWith(repeat: mode);
    _persist(now: true);
  }

  void toggleRepeat() {
    final next = switch (state.repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeat: next);
    // Come setRepeat: senza, la ripetizione scelta dal player spariva al
    // riavvio mentre quella di Siri restava.
    _persist(now: true);
  }

  /// AutoMix acceso o spento. Le dissolvenze a durata fissa non ci sono
  /// piu': AutoMix sceglie da se' punto e lunghezza, e una durata da
  /// scegliere a mano era solo un modo peggiore di fare la stessa cosa.
  void toggleAutomix() {
    final on = !state.automix;
    state = state.copyWith(automix: on, crossfadeDuration: Duration.zero);
    _persist(now: true);
    // AutoMix aggiunge o toglie i suoi filtri, e senza di lui il volume
    // allineato non vale piu'.
    unawaited(refreshFilters());
    if (on && state.current != null) unawaited(_loadVocalsEnd(state.current!));
  }

  /// Inserts a track right after the currently playing one.
  void playNext(Track track) {
    final q = [...state.queue];
    final insertAt = state.currentIndex + 1;
    q.insert(insertAt.clamp(0, q.length), track);
    state = state.copyWith(queue: q);
    _persist(now: true);
  }

  /// Sposta un brano nella coda.
  ///
  /// L'indice corrente va aggiornato insieme, altrimenti dopo un
  /// riordino la barra mostrerebbe un brano e ne suonerebbe un altro: cio'
  /// che sta suonando e' il brano, non la posizione, e la posizione e'
  /// esattamente quello che stai cambiando.
  void moveInQueue(int from, int rawTo) {
    final plan = resolveMove(
      length: state.queue.length,
      current: state.currentIndex,
      from: from,
      rawTo: rawTo,
    );
    if (plan == null) return;
    final q = [...state.queue];
    q.insert(plan.$1, q.removeAt(from));
    state = state.copyWith(queue: q, currentIndex: plan.$2);
    _persist(now: true);
  }

  /// Dove va l'elemento e dove finisce l'indice corrente, oppure null se
  /// lo spostamento non cambia niente.
  ///
  /// Sta fuori dal metodo perche' e' l'unica parte che si puo' sbagliare, e
  /// sbagliarla qui significa mostrare un brano e suonarne un altro: cio'
  /// che sta suonando e' il brano, non la posizione, e la posizione e'
  /// esattamente quello che stai cambiando.
  static (int, int)? resolveMove({
    required int length,
    required int current,
    required int from,
    required int rawTo,
  }) {
    if (from < 0 || from >= length) return null;
    // ReorderableListView riferisce la destinazione come se l'elemento
    // fosse ancora al suo posto: spostando in avanti va scalata di uno.
    final to = rawTo > from ? rawTo - 1 : rawTo;
    if (to < 0 || to >= length || to == from) return null;

    var next = current;
    if (from == current) {
      next = to;
    } else if (from < current && to >= current) {
      next -= 1;
    } else if (from > current && to <= current) {
      next += 1;
    }
    return (to, next);
  }

  void removeFromQueue(int index) {
    // If removing the current track, record its stats first.
    if (index == state.currentIndex) _recordStats();
    final q = [...state.queue]..removeAt(index);
    var current = state.currentIndex;
    if (q.isEmpty) {
      _player.stop();
      _pendingResume = null;
      state = const PlayerState();
      ref.read(nowPlayingProvider).clear();
      _persist(now: true);
      return;
    }
    if (index < current) {
      current -= 1;
    } else if (index == current) {
      current = current.clamp(0, q.length - 1);
    }
    state = state.copyWith(queue: q, currentIndex: current);
    _persist(now: true);
  }

  void clearQueue() {
    _recordStats();
    _player.stop();
    _pendingResume = null;
    state = const PlayerState();
    ref.read(nowPlayingProvider).clear();
    _persist(now: true);
  }
}
