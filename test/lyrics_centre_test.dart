import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/app_theme.dart';
import 'package:crocuta/models/lyrics.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/lyrics_screen.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/services/storage_service.dart';

import 'package:crocuta/services/player_controller.dart';

import 'support/fake_player.dart';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

const _track = Track(
  id: 'xyz',
  title: 'Corrente Ascensionale',
  author: 'Marea Bassa',
  thumbnailUrl: '',
);

final _lyrics = Lyrics(
  title: _track.title,
  artist: _track.author,
  lines: [
    for (var i = 0; i < 14; i++)
      LyricsLine(
        time: Duration(seconds: i * 6),
        text: i == 5
            ? 'Un verso lungo che non sta su una riga sola e deve andare a '
                  'capo senza farsi tagliare via la seconda meta'
            : 'Verso numero ${i + 1}',
      ),
  ],
);

/// Un player che si puo' far avanzare: [FakePlayer] restituisce uno stato
/// fisso, quindi non puo' mostrare se il testo segue il brano nel tempo.
class DrivablePlayer extends PlayerController {
  DrivablePlayer(this._state);
  PlayerState _state;

  @override
  PlayerState build() => _state;

  void moveTo(Duration position) {
    _state = _state.copyWith(position: position);
    state = _state;
  }
}

void main() {
  testWidgets('il testo segue il brano mentre avanza', (tester) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('lyr2');
      storage = StorageService();
      await storage.init(path: d.path);
    });

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = DrivablePlayer(
      const PlayerState(
        queue: [_track],
        currentIndex: 0,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration(minutes: 2),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          playerProvider.overrideWith(() => player),
          backdropColorProvider(
            '',
          ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
          lyricsProvider(
            'Corrente Ascensionale|Marea Bassa',
          ).overrideWith((ref) async => _lyrics),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LyricsScreen(
            title: 'Corrente Ascensionale',
            artist: 'Marea Bassa',
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // find.text esatto: "Verso numero 1" corrisponderebbe anche a 10-14.
    double centreOf(String text) => tester.getRect(find.text(text)).center.dy;

    final atStart = centreOf('Verso numero 1');

    // Il brano avanza: il testo deve scorrere con lui.
    player.moveTo(const Duration(seconds: 48));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final afterSeek = centreOf('Verso numero 1');

    expect(
      afterSeek,
      lessThan(atStart - 100),
      reason: 'il testo non ha seguito la posizione del brano',
    );
    // E il verso giusto deve essere al centro.
    expect((centreOf('Verso numero 9') - 932 / 2).abs(), lessThan(24));
  });

  testWidgets('il verso in corso finisce al centro dello schermo', (
    tester,
  ) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('lyr');
      storage = StorageService();
      await storage.init(path: d.path);
    });

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          playerProvider.overrideWith(
            () => FakePlayer(
              const PlayerState(
                queue: [_track],
                currentIndex: 0,
                isPlaying: true,
                position: Duration(seconds: 32),
                duration: Duration(minutes: 2),
              ),
            ),
          ),
          backdropColorProvider(
            '',
          ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
          lyricsProvider(
            'Corrente Ascensionale|Marea Bassa',
          ).overrideWith((ref) async => _lyrics),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LyricsScreen(
            title: 'Corrente Ascensionale',
            artist: 'Marea Bassa',
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final active = find.textContaining('Un verso lungo');
    expect(active, findsOneWidget);
    final rect = tester.getRect(active);
    final viewportCentre = 932 / 2;
    // ignore: avoid_print
    print(
      '>>> verso: ${rect.top.toStringAsFixed(0)}..${rect.bottom.toStringAsFixed(0)} '
      'centro=${rect.center.dy.toStringAsFixed(0)}  '
      'viewport=${viewportCentre.toStringAsFixed(0)}  '
      'scarto=${(rect.center.dy - viewportCentre).toStringAsFixed(0)}',
    );
    expect(
      (rect.center.dy - viewportCentre).abs(),
      lessThan(24),
      reason: 'il verso in corso non e\' centrato',
    );
  });

  testWidgets('scorrendo a mano i versi tornano nitidi, poi si riprende', (
    tester,
  ) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('lyr');
      storage = StorageService();
      await storage.init(path: d.path);
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
          playerProvider.overrideWith(
            () => FakePlayer(
              const PlayerState(
                queue: [_track],
                currentIndex: 0,
                isPlaying: true,
                position: Duration(seconds: 32),
                duration: Duration(minutes: 2),
              ),
            ),
          ),
          backdropColorProvider(
            '',
          ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
          lyricsProvider(
            'Corrente Ascensionale|Marea Bassa',
          ).overrideWith((ref) async => _lyrics),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const LyricsScreen(
            title: 'Corrente Ascensionale',
            artist: 'Marea Bassa',
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    final lines = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(ImageFiltered),
    );
    await settle();
    // Da fermi: tutti sfocati tranne quello in corso.
    expect(lines, findsNWidgets(_lyrics.lines.length - 1));

    final gesture = await tester.startGesture(const Offset(215, 500));
    await gesture.moveBy(const Offset(0, -120));
    await settle();
    expect(lines, findsNothing, reason: 'mentre scorri si legge tutto');

    await gesture.up();
    await settle();
    expect(lines, findsNothing, reason: 'non riparte appena alzi il dito');

    await tester.pump(const Duration(seconds: 3));
    await settle();
    expect(lines, findsNWidgets(_lyrics.lines.length - 1));
  });
}
