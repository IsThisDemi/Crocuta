import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'models/track.dart';
import 'providers.dart';
import 'services/storage_service.dart';
import 'theme.dart';

/// Entry point used to debug playback on desktop.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  mk.MediaKit.ensureInitialized();
  final storage = StorageService();
  await storage.init();

  runApp(
    ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(storage)],
      child: const _AutoTestApp(),
    ),
  );
}

class _AutoTestApp extends ConsumerStatefulWidget {
  const _AutoTestApp();

  @override
  ConsumerState<_AutoTestApp> createState() => _AutoTestAppState();
}

class _AutoTestAppState extends ConsumerState<_AutoTestApp> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 500), _runTest);
  }

  Future<void> _runTest() async {
    if (_started) return;
    _started = true;

    // Test 1: file audio locale (nessuna rete) — media_kit funziona?
    debugPrint('=== TEST 1: file locale ===');
    try {
      final player = mk.Player();
      player.stream.error.listen((e) => debugPrint('LOCAL ERROR: $e'));
      await player.open(mk.Media('/System/Library/Sounds/Ping.aiff'));
      await Future.delayed(const Duration(seconds: 2));
      debugPrint(
        'TEST 1 stato: playing=${player.state.playing} '
        'dur=${player.state.duration.inSeconds}s '
        'pos=${player.state.position.inSeconds}s',
      );
      await player.play();
      await Future.delayed(const Duration(seconds: 2));
      debugPrint(
        'TEST 1 dopo play: playing=${player.state.playing} '
        'pos=${player.state.position.inSeconds}s',
      );
      player.dispose();
    } catch (e) {
      debugPrint('TEST 1 ERRORE: $e');
    }

    // Test 2: MP3 pubblico su https (rete) — il player HTTP funziona?
    debugPrint('=== TEST 2: MP3 remoto ===');
    try {
      final player = mk.Player();
      player.stream.error.listen((e) => debugPrint('REMOTE ERROR: $e'));
      await player.open(
        mk.Media(
          'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        ),
      );
      await Future.delayed(const Duration(seconds: 3));
      debugPrint(
        'TEST 2 stato: playing=${player.state.playing} '
        'dur=${player.state.duration.inSeconds}s '
        'pos=${player.state.position.inSeconds}s',
      );
      await player.play();
      await Future.delayed(const Duration(seconds: 3));
      debugPrint(
        'TEST 2 dopo play: playing=${player.state.playing} '
        'pos=${player.state.position.inSeconds}s',
      );
      player.dispose();
    } catch (e) {
      debugPrint('TEST 2 ERRORE: $e');
    }

    // Test 3: proxy YouTube
    debugPrint('=== TEST 3: proxy YouTube ===');
    final player = ref.read(playerProvider.notifier);
    final yt = ref.read(youtubeServiceProvider);

    // 3a: brano con URL noto-validato per questa sessione. Dimostra che
    // quando la validazione passa, la riproduzione supera il taglio di
    // ~1 MiB (~1:04) che uccideva la versione precedente dell'app.
    final candidates = <Track>[
      const Track(
        id: '2Ia7MjrKY4g',
        title: 'Crash Out (Tinashe, test loop)',
        author: 'Tinashe',
        thumbnailUrl: 'https://img.youtube.com/vi/2Ia7MjrKY4g/hqdefault.jpg',
      ),
      const Track(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up (verificato)',
        author: 'Rick Astley',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      ),
    ];

    // 3b: poi i risultati reali della ricerca YTM (alcuni videoId sono
    // flaggati da Google per questa sessione e falliscono la validazione:
    // e' il comportamento atteso del nuovo resolver).
    try {
      candidates.addAll(
        await yt.search('never gonna give you up').then((s) => s.songs),
      );
    } catch (_) {}

    // Prova fino a 6 brani totali.
    candidateLoop:
    for (final track in candidates.take(6)) {
      debugPrint('=== TEST 3: riproduco "${track.title}" (${track.id}) ===');
      await player.playTrack(
        Track(
          id: track.id,
          title: track.title,
          author: track.author,
          duration: track.duration,
          thumbnailUrl: track.thumbnailUrl,
        ),
      );

      var count = 0;
      var lastPos = 0;
      var resets = 0;
      // 220s di osservazione per intercettare loop/reset oltre il muro.
      while (count < 220) {
        await Future.delayed(const Duration(seconds: 1));
        final s = ref.read(playerProvider);
        final p = s.position.inSeconds;
        if (p < lastPos - 3) {
          resets++;
          debugPrint(
            '=== RESET POSIZIONE n.' +
                resets.toString() +
                ': ' +
                lastPos.toString() +
                's -> ' +
                p.toString() +
                's ===',
          );
        }
        lastPos = p;
        debugPrint(
          'TEST 3 [${s.currentIndex}] pos=${p}s '
          'dur=${s.duration.inSeconds}s playing=${s.isPlaying} '
          'loading=${s.isLoading} err=${(s.error ?? '-').length > 100 ? '${s.error!.substring(0, 100)}...' : s.error}',
        );
        // Successo solo se si arriva in FONDO al brano (o quasi) senza
        // reset: il vecchio bug loopava a 1:04, il nuovo deve finire.
        final dur = s.duration.inSeconds;
        if (dur > 0 && p >= dur - 2) {
          debugPrint(
            '=== TEST 3: BRANO COMPLETATO, reset totali: ' +
                resets.toString() +
                ' ===',
          );
          if (resets == 0) {
            debugPrint('=== TEST 3: NESSUN LOOP — SUPERATO ===');
          }
          return;
        }
        // Errore stabile senza playback: brano non riproducibile da
        // questa sessione, si passa al candidato successivo.
        if (!s.isPlaying && !s.isLoading && s.error != null && count > 20) {
          debugPrint('=== TEST 3: brano non riproducibile, prossimo ===');
          continue candidateLoop;
        }
        count++;
      }
    }
    debugPrint('=== TEST 3: nessuna riproduzione ===');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: Text(
            'Auto test in corso... guarda i log.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
