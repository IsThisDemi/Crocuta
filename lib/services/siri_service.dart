import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers.dart';
import 'library_views.dart';
import 'follows_controller.dart';
import 'voice_assistant.dart';

/// Il ponte con Siri, su iOS.
///
/// Su iOS gli App Intents girano fuori da Flutter — a volte prima ancora che
/// il motore Dart esista — quindi il giro non puo' essere una chiamata
/// diretta. Funziona cosi', in due direzioni indipendenti:
///
///  * **In uscita** pubblichiamo un indice della libreria (brani, artisti
///    seguiti, playlist). Le frasi di Siri non accettano testo libero: i
///    valori devono essere *enumerabili*, e quell'indice e' l'elenco dei
///    valori. E' il motivo per cui "riproduci X su Crocuta" funziona per
///    la roba tua e non per il catalogo intero.
///  * **In entrata** l'intent non ci parla: deposita il comando e basta.
///    Noi lo ritiriamo con `takeCommand`, che legge e cancella in un colpo
///    solo. Cosi' lo stesso comando non puo' essere eseguito due volte, e
///    uno arrivato ad app spenta ci aspetta finche' non siamo pronti.
///
/// Su macOS e Windows il canale non esiste e ogni chiamata e' un no-op.
class SiriService {
  static const _channel = MethodChannel('crocuta/siri');

  /// Quanti brani pubblicare. Siri genera una frase per ogni valore, quindi
  /// l'elenco non e' gratis: oltre il migliaio l'indicizzazione rallenta e
  /// il riconoscimento peggiora, perche' i titoli simili si accavallano.
  static const _maxSongs = 600;

  final Ref _ref;
  Timer? _debounce;
  bool _started = false;

  SiriService(this._ref);

  /// Attacca i listener e pubblica una prima volta.
  void start() {
    if (_started) return;
    _started = true;

    _channel.setMethodCallHandler((call) async {
      // L'unico messaggio che ci arriva e' "c'e' qualcosa da ritirare".
      // Il contenuto lo andiamo a prendere noi, per non avere due copie
      // dello stesso comando in giro.
      if (call.method == 'poke') await takePendingCommand();
    });

    // La libreria cambia, l'indice la segue. Sono quattro sorgenti perche'
    // quattro sono le cose che Siri puo' nominare.
    for (final provider in [
      favoritesProvider,
      recentlyPlayedProvider,
      playlistsProvider,
      followsProvider,
    ]) {
      _ref.listen(provider, (_, _) => _schedulePublish());
    }

    _schedulePublish();
    unawaited(takePendingCommand());
    // E una seconda volta poco dopo. All'avvio a freddo non e' garantito
    // che l'intent abbia gia' depositato quando arriviamo qui: il sistema
    // lancia l'app e fa girare `perform()` senza un ordine fisso fra i
    // due. Il ritiro e' idempotente, quindi al massimo non trova niente.
    Timer(const Duration(seconds: 2), () => unawaited(takePendingCommand()));
  }

  /// Pubblicare a ogni singola modifica vorrebbe dire riscrivere l'indice
  /// cinque volte mentre aggiungi cinque preferiti.
  void _schedulePublish() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), publish);
  }

  /// Manda a iOS l'elenco dei valori che Siri puo' nominare.
  Future<void> publish() async {
    try {
      await _channel.invokeMethod('publish', {'index': jsonEncode(_index())});
    } catch (_) {
      // Non siamo su iOS, o il canale non c'e': niente Siri, niente danni.
    }
  }

  Map<String, dynamic> _index() => buildIndex(
    favorites: _ref.read(favoritesProvider),
    playlists: _ref.read(playlistsProvider),
    recents: _ref.read(recentlyPlayedProvider),
    artists: _ref.read(followsProvider),
  );

  /// L'indice come dato puro, cosi' l'ordine e il taglio si possono
  /// verificare senza iOS, senza Hive e senza un motore Flutter.
  ///
  /// L'ordine dei brani e' l'ordine di probabilita': cio' che hai messo nei
  /// preferiti e' piu' probabile che tu lo chieda a voce di un brano
  /// passato una volta nella radio. Conta perche' in coda alla lista si
  /// taglia, e a essere tagliato dev'essere il meno probabile.
  static Map<String, dynamic> buildIndex({
    required List<Track> favorites,
    required List<UserPlaylist> playlists,
    required List<Track> recents,
    required List<FollowedArtist> artists,
    int maxSongs = _maxSongs,
  }) {
    final songs = <String, Track>{};
    void addAll(Iterable<Track> tracks) {
      for (final t in tracks) {
        if (songs.length >= maxSongs) return;
        if (t.title.trim().isEmpty) continue;
        songs.putIfAbsent(t.id, () => t);
      }
    }

    addAll(favorites);
    for (final p in playlists) {
      addAll(p.tracks);
    }
    addAll(recents);

    return {
      'songs': [
        for (final t in songs.values)
          {'id': t.id, 'title': t.title, 'artist': t.author},
      ],
      'artists': [
        for (final a in artists)
          if (a.name.trim().isNotEmpty) {'id': a.browseId, 'name': a.name},
      ],
      // Una playlist vuota non si puo' riprodurre: nominarla a Siri
      // porterebbe a un comando che non fa niente.
      'playlists': [
        for (var i = 0; i < playlists.length; i++)
          if (playlists[i].tracks.isNotEmpty)
            {'id': '$i', 'name': playlists[i].name},
      ],
    };
  }

  /// Ritira ed esegue il comando lasciato da un App Intent, se c'e'.
  ///
  /// Va chiamata anche al ritorno in primo piano: con l'app spenta l'intent
  /// deposita e basta, e il comando resta li' ad aspettarci.
  Future<void> takePendingCommand() async {
    Map<Object?, Object?>? command;
    try {
      command = await _channel.invokeMethod<Map<Object?, Object?>>(
        'takeCommand',
      );
    } catch (_) {
      return;
    }
    if (command == null) return;

    final action = command['action'] as String?;
    final value = command['value'] as String?;
    if (action == null) return;

    try {
      await _run(action, value);
    } catch (_) {
      // Un comando che fallisce non deve portarsi dietro l'app: Siri ha
      // gia' detto che stava partendo, al massimo non parte niente.
    }
  }

  Future<void> _run(String action, String? value) async {
    final player = _ref.read(playerProvider.notifier);

    switch (action) {
      case 'song':
        final track = _findSong(value);
        if (track != null) await player.playTrack(track);

      case 'artist':
        if (value != null) await _playArtist(value);

      case 'playlist':
        final index = int.tryParse(value ?? '');
        final playlists = _ref.read(playlistsProvider);
        if (index != null && index >= 0 && index < playlists.length) {
          final tracks = playlists[index].tracks;
          if (tracks.isNotEmpty) {
            await player.playTrack(tracks.first, queue: List.of(tracks));
          }
        }

      case 'favorites':
        final favorites = _shuffled(_ref.read(favoritesProvider));
        if (favorites.isNotEmpty) {
          await player.playTrack(favorites.first, queue: favorites);
        }

      case 'search':
        if (value != null && value.trim().isNotEmpty) await _search(value);

      // "Avvia la radio di X": il brano, poi i simili.
      case 'radio':
        final track = _findSong(value);
        if (track != null) await player.startRadio(track);

      // Una playlist intelligente, da Siri o dal widget "Play".
      case 'smart':
        final list = _ref
            .read(smartPlaylistsProvider)
            .where((p) => p.id == value)
            .firstOrNull;
        if (list != null && list.tracks.isNotEmpty) {
          await player.playTrack(
            list.tracks.first,
            queue: List.of(list.tracks),
          );
        }

      // crocuta://listen, dal tasto Azione: l'assistente vocale interno.
      case 'listen':
        voiceRequests.value++;

      // "Riprendi la musica": solo se non sta gia' suonando, altrimenti la
      // metterebbe in pausa.
      case 'resume':
        if (!_ref.read(playerProvider).isPlaying) await player.toggle();
    }
  }

  Track? _findSong(String? id) {
    if (id == null) return null;
    for (final t in _ref.read(favoritesProvider)) {
      if (t.id == id) return t;
    }
    for (final p in _ref.read(playlistsProvider)) {
      for (final t in p.tracks) {
        if (t.id == id) return t;
      }
    }
    for (final t in _ref.read(recentlyPlayedProvider)) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// "Riproduci Yeat": i suoi brani migliori, mescolati.
  ///
  /// Mescolati e non in ordine perche' la domanda a voce e' generica — e'
  /// il caso in cui non stai scegliendo un pezzo — e sentire sempre partire
  /// lo stesso brano piu' ascoltato renderebbe la frase inutile la seconda
  /// volta che la dici.
  Future<void> _playArtist(String browseId) async {
    final page = await _ref
        .read(youtubeServiceProvider)
        .getArtistPage(browseId);
    final songs = _shuffled(page.topSongs);
    if (songs.isEmpty) return;
    await _ref
        .read(playerProvider.notifier)
        .playTrack(songs.first, queue: songs);
    // Con pochi brani migliori la coda finisce in un quarto d'ora: la radio
    // la tiene viva, che e' cio' che ci si aspetta da un ascolto a voce.
    _ref.read(radioProvider.notifier).set(true);
  }

  /// L'unico punto in cui il testo e' libero: qui la frase non porta il
  /// valore, lo chiede Siri a voce dopo ("Cosa cerchi?").
  Future<void> _search(String query) async {
    final sections = await _ref.read(youtubeServiceProvider).search(query);
    final songs = sections.songs;
    if (songs.isEmpty) return;
    await _ref
        .read(playerProvider.notifier)
        .playTrack(songs.first, queue: List.of(songs));
  }

  List<Track> _shuffled(List<Track> tracks) {
    final out = List.of(tracks);
    out.shuffle(Random());
    return out;
  }

  void dispose() {
    _debounce?.cancel();
    _channel.setMethodCallHandler(null);
    _started = false;
  }
}

/// Il ponte con Siri. Inerte finche' non si chiama `start()`.
final siriServiceProvider = Provider<SiriService>((ref) {
  final service = SiriService(ref);
  ref.onDispose(service.dispose);
  return service;
});
