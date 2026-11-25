import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/now_playing_screen.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/services/storage_service.dart';
import 'package:yeen_music/widgets/app_background.dart';

import 'support/fake_player.dart';

/// Titolo reale restituito da YouTube Music: il gruppo feat e' duplicato
/// nei loro dati (un solo `run` contiene entrambi), quindi va a capo su due
/// righe ed e' il caso peggiore per l'altezza del blocco.
const long = Track(
  id: 'xyz',
  title: 'CLUB TEST (con IvanBi, Diss Gacha) (con IvanBi e Diss Gacha)',
  author: 'Sala, IvanBi, Diss Gacha',
  duration: Duration(minutes: 3, seconds: 42),
  thumbnailUrl: '',
  albumName: 'Nebbia in Pianura Padana Occidentale',
);

void main() {
  // Il player promette di stare in una schermata sola: quella promessa e'
  // esattamente cio' che lo fa sfondare quando la finestra e' piccola o il
  // titolo va a capo. Qui si passano molte dimensioni con un titolo lungo
  // vero e si pretende che nessuna produca un overflow.
  testWidgets('la riproduzione non sfonda a nessuna dimensione', (
    tester,
  ) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('sweep');
      storage = StorageService();
      await storage.init(path: d.path);
    });

    final bad = <String>[];
    for (final w in [300.0, 320.0, 360.0, 390.0, 430.0, 520.0, 800.0]) {
      for (var h = 380.0; h <= 1000.0; h += 10) {
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storageServiceProvider.overrideWithValue(storage),
              playerProvider.overrideWith(
                () => FakePlayer(
                  const PlayerState(
                    queue: [long],
                    currentIndex: 0,
                    isPlaying: true,
                    position: Duration(minutes: 1, seconds: 18),
                    duration: Duration(minutes: 3, seconds: 42),
                  ),
                ),
              ),
              backdropColorProvider(
                '',
              ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
              upNextProvider(
                'xyz|Sala, IvanBi, Diss Gacha',
              ).overrideWith((ref) async => <Track>[]),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: Material(
                type: MaterialType.transparency,
                child: AppBackground(child: const NowPlayingScreen()),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final e = tester.takeException();
        if (e != null) bad.add('${w.toInt()}x${h.toInt()}: $e');
      }
    }
    tester.view.reset();
    expect(bad, isEmpty, reason: 'dimensioni che sfondano:\n${bad.join("\n")}');
  });

  // Testo e coda si aprono dentro il player, al posto della copertina: la
  // stessa promessa di non sfondare vale anche con loro aperti.
  testWidgets('testo e coda aperti nel player non sfondano', (tester) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('panes');
      storage = StorageService();
      await storage.init(path: d.path);
    });

    final bad = <String>[];
    for (final pane in ['Lyrics', 'Queue']) {
      for (final size in const [
        Size(320, 568),
        Size(390, 844),
        Size(430, 932),
        Size(800, 600),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storageServiceProvider.overrideWithValue(storage),
              playerProvider.overrideWith(
                () => FakePlayer(
                  const PlayerState(
                    queue: [long, long, long],
                    currentIndex: 0,
                    isPlaying: true,
                  ),
                ),
              ),
              backdropColorProvider(
                '',
              ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
              upNextProvider(
                'xyz|Sala, IvanBi, Diss Gacha',
              ).overrideWith((ref) async => <Track>[]),
              lyricsProvider(
                '${long.title}|${long.author}',
              ).overrideWith((ref) async => null),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              home: Material(
                type: MaterialType.transparency,
                child: AppBackground(child: const NowPlayingScreen()),
              ),
            ),
          ),
        );
        await tester.pump();
        // Sulle finestre piu' basse la fila in fondo sta sotto la piega.
        await tester.ensureVisible(find.byTooltip(pane));
        await tester.pump();
        await tester.tap(find.byTooltip(pane));
        await tester.pump(const Duration(milliseconds: 500));
        // Un fotogramma in piu': il testo arriva dopo quello che lo chiede.
        await tester.pump();
        final e = tester.takeException();
        if (e != null) {
          bad.add('$pane ${size.width.toInt()}x${size.height.toInt()}: $e');
        }
        // Il pannello c'e' davvero, e la copertina ha lasciato il posto.
        expect(
          find.text(pane == 'Lyrics' ? 'No lyrics for this song.' : 'Up next'),
          findsOneWidget,
        );
      }
    }
    tester.view.reset();
    expect(bad, isEmpty, reason: 'dimensioni che sfondano:\n${bad.join("\n")}');
  });

  // Sul desktop tutti i comandi, fila in fondo compresa, stanno nella
  // finestra: in una finestra del Mac alta 609 punti la fila finiva oltre
  // il bordo, sotto l'altezza minima del player.
  testWidgets('la fila in fondo resta dentro la finestra', (tester) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('fits');
      storage = StorageService();
      await storage.init(path: d.path);
    });
    final bad = <String>[];
    for (final size in const [
      Size(804, 609),
      Size(1000, 540),
      Size(700, 500),
      Size(1400, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            playerProvider.overrideWith(
              () => FakePlayer(
                const PlayerState(
                  queue: [long],
                  currentIndex: 0,
                  isPlaying: true,
                  duration: Duration(minutes: 3),
                ),
              ),
            ),
            backdropColorProvider(
              '',
            ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
            upNextProvider(
              'xyz|Sala, IvanBi, Diss Gacha',
            ).overrideWith((ref) async => <Track>[]),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Material(
              type: MaterialType.transparency,
              child: AppBackground(child: const NowPlayingScreen()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final queue = tester.getRect(find.byTooltip('Queue'));
      if (queue.bottom > size.height) {
        bad.add(
          '${size.width.toInt()}x${size.height.toInt()}: ${queue.bottom}',
        );
      }
    }
    tester.view.reset();
    expect(bad, isEmpty, reason: 'fila in fondo fuori:\n${bad.join("\n")}');
  });
}
