import 'dart:ui' show PictureRecorder;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/accent.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/now_playing_screen.dart';
import 'package:yeen_music/services/mix_info.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/widgets/mini_player.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _fromArt = 'https://example.invalid/from.png';
const _toArt = 'https://example.invalid/to.png';

const _from = Track(
  id: 'f',
  title: 'Corrente Ascensionale',
  author: 'Marea Bassa',
  thumbnailUrl: _fromArt,
);
const _to = Track(
  id: 't',
  title: 'Vento di Terra',
  author: 'Onde Corte',
  thumbnailUrl: _toArt,
);

/// Una copertina finta di un colore solo: il mix si giudica dai colori.
Future<void> _seed(WidgetTester tester, String url, Color color) async {
  await tester.runAsync(() async {
    final recorder = PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = color);
    final image = await recorder.endRecording().toImage(64, 64);
    PaintingBinding.instance.imageCache.putIfAbsent(
      NetworkImage(url),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image)),
      ),
    );
  });
}

final _overrides = [
  playerProvider.overrideWith(
    () => FakePlayer(
      const PlayerState(
        queue: [_from, _to],
        currentIndex: 0,
        isPlaying: true,
        mixing: true,
        position: Duration(seconds: 200),
        duration: Duration(seconds: 210),
      ),
    ),
  ),
  mixInfoProvider.overrideWith(
    (ref) => const MixInfo(from: _from, to: _to, progress: 0.5),
  ),
  artworkAccentProvider(
    _fromArt,
  ).overrideWith((ref) async => const Color(0xFFFF7A59)),
  artworkAccentProvider(
    _toArt,
  ).overrideWith((ref) async => const Color(0xFF4FC3F7)),
  backdropColorProvider(
    _fromArt,
  ).overrideWith((ref) async => const Color(0xFF5A2A1E)),
  upNextProvider('f|Marea Bassa').overrideWith((ref) async => <Track>[]),
];

void main() {
  tearDown(() => PaintingBinding.instance.imageCache.clear());

  Future<void> seedBoth(WidgetTester tester) async {
    await _seed(tester, _fromArt, const Color(0xFFE0603A));
    await _seed(tester, _toArt, const Color(0xFF2C8FD8));
  }

  testWidgets('cattura: mini player a meta\' mix', (tester) async {
    await seedBoth(tester);
    await capture(
      tester,
      const Align(child: SizedBox(height: 64, child: MiniPlayer())),
      name: 'mix_mini_player',
      size: const Size(430, 200),
      overrides: _overrides,
    );
  });

  testWidgets('cattura: player a meta\' mix', (tester) async {
    await seedBoth(tester);
    await capture(
      tester,
      const NowPlayingScreen(),
      name: 'mix_player',
      overrides: _overrides,
    );
    // Solo "AutoMix": il titolo di chi arriva non si mostra.
    expect(find.text('Vento di Terra'), findsNothing);
  });
}
