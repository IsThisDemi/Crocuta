import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/track.dart';
import '../providers.dart';
import 'library_views.dart';
import 'voice_command.dart';

/// A che punto e' l'assistente.
enum VoicePhase { idle, listening, working, done, failed }

@immutable
class VoiceState {
  final VoicePhase phase;

  /// Quello che ha sentito finora, mentre si parla.
  final String heard;

  /// La risposta: "Ecco Hope", "Non ho capito".
  final String reply;

  /// Il livello del microfono, 0-1, per l'animazione.
  final double level;

  const VoiceState({
    this.phase = VoicePhase.idle,
    this.heard = '',
    this.reply = '',
    this.level = 0,
  });

  VoiceState copyWith({
    VoicePhase? phase,
    String? heard,
    String? reply,
    double? level,
  }) => VoiceState(
    phase: phase ?? this.phase,
    heard: heard ?? this.heard,
    reply: reply ?? this.reply,
    level: level ?? this.level,
  );
}

/// L'assistente vocale interno: ascolta una frase, la capisce con
/// [parseVoiceCommand] e la esegue.
///
/// Il riconoscimento e' quello del sistema — su iPhone e Mac lo stesso
/// motore di Siri, su Windows quello di Windows — e la frase non passa da
/// nessun server nostro. Mentre ascolta la musica si ferma: il microfono
/// sentirebbe lei invece di chi parla.
class VoiceAssistant extends Notifier<VoiceState> {
  late final _SpeechBackend _speech = Platform.isIOS || Platform.isMacOS
      ? _NativeSpeech()
      : _PluginSpeech();
  bool _ready = false;
  bool _wasPlaying = false;
  bool _handled = false;
  Timer? _silence;
  Timer? _limit;

  static const _audio = MethodChannel('crocuta/now_playing');

  @override
  VoiceState build() {
    ref.onDispose(() {
      _silence?.cancel();
      _limit?.cancel();
    });
    return const VoiceState();
  }

  /// Comincia ad ascoltare.
  Future<void> listen() async {
    if (state.phase == VoicePhase.listening) return;
    _handled = false;
    state = const VoiceState(phase: VoicePhase.listening);

    if (!_ready) {
      try {
        _ready = await _speech.init(
          onResult: _onResult,
          onLevel: (v) {
            if (state.phase == VoicePhase.listening) {
              state = state.copyWith(level: v);
            }
          },
          onError: (msg) {
            debugPrint('voce: errore ($msg)');
            if (state.phase == VoicePhase.listening && !_handled) {
              unawaited(_handle(state.heard));
            }
          },
        );
      } catch (e) {
        debugPrint('voce: riconoscimento non disponibile ($e)');
        _ready = false;
      }
    }
    if (!_ready) {
      _finish(
        'Allow microphone and speech recognition for Crocuta in Settings',
        failed: true,
      );
      return;
    }

    final player = ref.read(playerProvider);
    _wasPlaying = player.isPlaying;
    if (_wasPlaying) await ref.read(playerProvider.notifier).toggle();

    try {
      await _speech.start(_locale());
    } catch (e) {
      debugPrint('voce: ascolto non partito ($e)');
      await _resumeIfNeeded();
      _finish("Couldn't listen", failed: true);
      return;
    }
    // Chi non dice niente: dopo sette secondi si lascia perdere. E in ogni
    // caso non piu' di quindici.
    _armSilence(const Duration(seconds: 7));
    _limit?.cancel();
    _limit = Timer(const Duration(seconds: 15), () => unawaited(stopAndRun()));
  }

  /// Quando si smette di parlare, si esegue: il riconoscimento del sistema
  /// non lo decide da se'.
  void _armSilence(Duration after) {
    _silence?.cancel();
    _silence = Timer(after, () => unawaited(stopAndRun()));
  }

  /// Smette di ascoltare senza fare niente.
  Future<void> cancel() async {
    _handled = true;
    _silence?.cancel();
    _limit?.cancel();
    await _speech.cancel();
    await _restoreAudio();
    if (_wasPlaying && !ref.read(playerProvider).isPlaying) {
      await ref.read(playerProvider.notifier).toggle();
    }
    _wasPlaying = false;
    state = const VoiceState();
  }

  /// Basta ascoltare: si esegue quello che si e' sentito.
  Future<void> stopAndRun() async {
    if (state.phase != VoicePhase.listening || _handled) return;
    await _handle(state.heard);
  }

  /// La lingua del sistema: "it_IT" diventa "it-IT".
  String _locale() => Platform.localeName.split('.').first.replaceAll('_', '-');

  void _onResult(String words, bool isFinal) {
    if (_handled) return;
    state = state.copyWith(heard: words);
    if (isFinal) {
      unawaited(_handle(words));
    } else if (words.trim().isNotEmpty) {
      _armSilence(const Duration(milliseconds: 1600));
    }
  }

  Future<void> _handle(String words) async {
    if (_handled) return;
    _handled = true;
    _silence?.cancel();
    _limit?.cancel();
    await _speech.stop();
    await _restoreAudio();
    final heard = words.trim();
    if (heard.isEmpty) {
      await _resumeIfNeeded();
      _finish("I didn't catch that", failed: true);
      return;
    }
    state = state.copyWith(phase: VoicePhase.working, heard: heard, level: 0);
    final command = parseVoiceCommand(heard);
    debugPrint('voce: "$heard" -> $command');
    String reply;
    var failed = false;
    try {
      reply = await _run(command);
    } on _Miss catch (m) {
      reply = m.message;
      failed = true;
    } catch (e) {
      debugPrint('voce: comando fallito ($e)');
      reply = 'Something went wrong';
      failed = true;
    }
    if (failed) await _resumeIfNeeded();
    _finish(reply, failed: failed);
  }

  void _finish(String reply, {bool failed = false}) {
    state = state.copyWith(
      phase: failed ? VoicePhase.failed : VoicePhase.done,
      reply: reply,
      level: 0,
    );
  }

  Future<void> _resumeIfNeeded() async {
    if (_wasPlaying && !ref.read(playerProvider).isPlaying) {
      await ref.read(playerProvider.notifier).toggle();
    }
    _wasPlaying = false;
  }

  /// Su iPhone il riconoscimento, finito, spegne la sessione audio
  /// dell'app: senza riaccenderla la musica dopo restava muta.
  Future<void> _restoreAudio() async {
    if (!Platform.isIOS) return;
    try {
      await _audio.invokeMethod('restoreSession');
    } catch (_) {}
  }

  // -------------------------------------------------------------------
  // L'esecuzione
  // -------------------------------------------------------------------

  Future<String> _run(VoiceCommand c) async {
    final player = ref.read(playerProvider.notifier);
    switch (c) {
      case Control(action: PlayerAction.pause):
        _wasPlaying = false;
        return 'Paused';
      case Control(action: PlayerAction.resume):
        _wasPlaying = false;
        if (ref.read(playerProvider).current == null) {
          throw const _Miss('Nothing to resume');
        }
        if (!ref.read(playerProvider).isPlaying) await player.toggle();
        return 'Playing';
      case Control(action: PlayerAction.next):
        await player.next();
        await _resumeIfNeeded();
        return 'Next song';
      case Control(action: PlayerAction.previous):
        await player.previous();
        await _resumeIfNeeded();
        return 'Previous song';
      case Control(action: PlayerAction.louder):
        await player.adjustVolume(15);
        await _resumeIfNeeded();
        return 'Louder';
      case Control(action: PlayerAction.quieter):
        await player.adjustVolume(-15);
        await _resumeIfNeeded();
        return 'Quieter';
      case Control(action: PlayerAction.shuffle):
        player.toggleShuffle();
        await _resumeIfNeeded();
        return ref.read(playerProvider).shuffle ? 'Shuffle on' : 'Shuffle off';
      case Control(action: PlayerAction.like):
        final t = ref.read(playerProvider).current;
        await _resumeIfNeeded();
        if (t == null) throw const _Miss('Nothing is playing');
        final liked = ref.read(favoritesProvider).any((f) => f.id == t.id);
        if (!liked) await ref.read(favoritesProvider.notifier).toggle(t);
        return 'Added to Liked Songs';
      case Control(action: PlayerAction.favorites):
        final favs = _shuffled(ref.read(favoritesProvider));
        if (favs.isEmpty) throw const _Miss('No liked songs yet');
        _wasPlaying = false;
        await player.playTrack(favs.first, queue: favs);
        return 'Your liked songs';
      case PlayPlaylist(:final name):
        return _playPlaylist(name);
      case PlayArtist(:final name):
        return _playArtistNamed(name);
      case StartRadio(:final query):
        final t = _inLibrary(query) ?? await _searchSong(query);
        if (t == null) throw _Miss('No results for "$query"');
        _wasPlaying = false;
        await player.startRadio(t);
        return 'Radio from ${t.title}';
      case PlayQuery(:final query, :final artist):
        return _playQuery(query, artist);
      case NotUnderstood():
        throw const _Miss("I didn't understand");
    }
  }

  Future<String> _playQuery(String query, String? artist) async {
    final player = ref.read(playerProvider.notifier);
    // Prima la libreria: un brano che hai gia' e' quello che intendi.
    final mine = _inLibrary(query, artist: artist);
    if (mine != null) {
      _wasPlaying = false;
      await player.startRadio(mine);
      return mine.title;
    }
    final service = ref.read(youtubeServiceProvider);
    final sections = await service.search(
      artist == null ? query : '$query $artist',
    );
    // Solo un nome, ed e' quello di un artista: i suoi brani.
    if (artist == null && sections.artists.isNotEmpty) {
      final a = sections.artists.first;
      final sameName = normalizeSpeech(a.title) == normalizeSpeech(query);
      final songTitled = sections.songs.any(
        (s) => normalizeSpeech(s.title) == normalizeSpeech(query),
      );
      if (sameName && !songTitled) return _playArtistPage(a.browseId, a.title);
    }
    if (sections.songs.isEmpty) throw _Miss('No results for "$query"');
    final t = sections.songs.first;
    _wasPlaying = false;
    await player.startRadio(t);
    return '${t.title} · ${t.author}';
  }

  Future<String> _playArtistNamed(String name) async {
    final sections = await ref.read(youtubeServiceProvider).search(name);
    if (sections.artists.isEmpty) {
      // Nessun artista con quel nome: si prova come brano.
      return _playQuery(name, null);
    }
    final a = sections.artists.first;
    return _playArtistPage(a.browseId, a.title);
  }

  Future<String> _playArtistPage(String browseId, String title) async {
    final page = await ref.read(youtubeServiceProvider).getArtistPage(browseId);
    final songs = _shuffled(page.topSongs);
    if (songs.isEmpty) throw _Miss('Nothing to play from $title');
    _wasPlaying = false;
    await ref
        .read(playerProvider.notifier)
        .playTrack(songs.first, queue: songs);
    // Pochi brani migliori finiscono presto: la radio tiene viva la coda.
    ref.read(radioProvider.notifier).set(true);
    return title;
  }

  Future<String> _playPlaylist(String name) async {
    final wanted = normalizeSpeech(name);
    bool matches(String title) {
      final t = normalizeSpeech(title);
      return t == wanted || t.contains(wanted) || wanted.contains(t);
    }

    for (final p in ref.read(playlistsProvider)) {
      if (p.tracks.isNotEmpty && matches(p.name)) {
        _wasPlaying = false;
        await ref
            .read(playerProvider.notifier)
            .playTrack(p.tracks.first, queue: List.of(p.tracks));
        return p.name;
      }
    }
    for (final p in ref.read(smartPlaylistsProvider)) {
      if (p.tracks.isNotEmpty && matches(p.title)) {
        _wasPlaying = false;
        await ref
            .read(playerProvider.notifier)
            .playTrack(p.tracks.first, queue: List.of(p.tracks));
        return p.title;
      }
    }
    throw _Miss('No playlist called "$name"');
  }

  /// Un brano gia' in libreria, per titolo (e artista, se detto).
  Track? _inLibrary(String query, {String? artist}) {
    final q = normalizeSpeech(query);
    final a = artist == null ? null : normalizeSpeech(artist);
    final pool = <Track>[
      ...ref.read(favoritesProvider),
      for (final p in ref.read(playlistsProvider)) ...p.tracks,
      ...ref.read(recentlyPlayedProvider),
    ];
    for (final t in pool) {
      if (normalizeSpeech(t.title) != q) continue;
      if (a != null && !normalizeSpeech(t.author).contains(a)) continue;
      return t;
    }
    return null;
  }

  Future<Track?> _searchSong(String query) async {
    final sections = await ref.read(youtubeServiceProvider).search(query);
    return sections.songs.firstOrNull;
  }

  List<Track> _shuffled(List<Track> tracks) =>
      List.of(tracks)..shuffle(Random());
}

/// Il riconoscimento: il nostro su iPhone e Mac, il pacchetto su Windows.
abstract class _SpeechBackend {
  Future<bool> init({
    required void Function(String words, bool isFinal) onResult,
    required void Function(double level) onLevel,
    required void Function(String message) onError,
  });
  Future<void> start(String locale);
  Future<void> stop();
  Future<void> cancel();
}

/// VoiceRecognizer.swift: microfono del dispositivo e non degli AirPods,
/// liberato appena finito.
class _NativeSpeech implements _SpeechBackend {
  static const _channel = MethodChannel('crocuta/voice');

  @override
  Future<bool> init({
    required void Function(String words, bool isFinal) onResult,
    required void Function(double level) onLevel,
    required void Function(String message) onError,
  }) async {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'result':
          final m = Map<String, Object?>.from(call.arguments as Map);
          onResult(m['text'] as String? ?? '', m['final'] == true);
        case 'level':
          onLevel((call.arguments as num).toDouble());
        case 'error':
          onError('${call.arguments}');
      }
    });
    return await _channel.invokeMethod<bool>('authorize') ?? false;
  }

  @override
  Future<void> start(String locale) =>
      _channel.invokeMethod('start', {'locale': locale});

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Future<void> cancel() => _channel.invokeMethod('cancel');
}

/// Il pacchetto speech_to_text, per Windows.
class _PluginSpeech implements _SpeechBackend {
  final SpeechToText _stt = SpeechToText();
  late void Function(String, bool) _onResult;
  late void Function(double) _onLevel;

  @override
  Future<bool> init({
    required void Function(String words, bool isFinal) onResult,
    required void Function(double level) onLevel,
    required void Function(String message) onError,
  }) {
    _onResult = onResult;
    _onLevel = onLevel;
    return _stt.initialize(onError: (e) => onError(e.errorMsg));
  }

  @override
  Future<void> start(String locale) => _stt.listen(
    onResult: (SpeechRecognitionResult r) =>
        _onResult(r.recognizedWords, r.finalResult),
    // Il livello arriva in dB, all'incirca da -2 a 10.
    onSoundLevelChange: (l) => _onLevel(((l + 2) / 12).clamp(0.0, 1.0)),
    listenOptions: SpeechListenOptions(
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.search,
      localeId: locale.replaceAll('-', '_'),
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(milliseconds: 1800),
    ),
  );

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();
}

class _Miss implements Exception {
  final String message;
  const _Miss(this.message);
}

/// Le richieste di aprire l'assistente da fuori dall'albero dei widget: il
/// collegamento crocuta://listen, la scorciatoia da tastiera. L'app le
/// ascolta e apre il pannello.
final voiceRequests = ValueNotifier<int>(0);

final voiceAssistantProvider = NotifierProvider<VoiceAssistant, VoiceState>(
  VoiceAssistant.new,
);
