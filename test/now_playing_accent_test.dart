import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/accent.dart';
import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/now_playing_screen.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/services/storage_service.dart';

import 'support/fake_player.dart';

const _art = 'https://example.invalid/cover.png';
const _teal = Color(0xFF4FC3C7);

const _track = Track(
  id: 'a',
  title: 'ALL MY FELLAS',
  author: 'Frizk',
  thumbnailUrl: _art,
);

void main() {
  // Gli interruttori accesi (radio, shuffle, ripeti) prendono il colore
  // del brano, come la barra di avanzamento e AutoMix. Leggevano il colore
  // dal contesto della schermata, sopra l'AccentScope, e restavano sul
  // viola di marca a ogni brano.
  testWidgets('gli interruttori accesi prendono il colore del brano', (
    tester,
  ) async {
    late final StorageService storage;
    await tester.runAsync(() async {
      final d = await Directory.systemTemp.createTemp('accent');
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
                shuffle: true,
              ),
            ),
          ),
          artworkAccentProvider(_art).overrideWith((ref) async => _teal),
          backdropColorProvider(
            _art,
          ).overrideWith((ref) async => const Color(0xFF1E4D4B)),
          upNextProvider('a|Frizk').overrideWith((ref) async => <Track>[]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const NowPlayingScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final shuffle = tester.widget<Icon>(find.byIcon(Icons.shuffle_rounded));
    expect(shuffle.color, _teal);
  });
}
