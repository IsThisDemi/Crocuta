import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/queue_screen.dart';
import 'package:crocuta/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

Track _t(String id) =>
    Track(id: id, title: 'Brano $id', author: 'Tizio', thumbnailUrl: '');

void main() {
  testWidgets('in cima quello che suona, sotto solo quelli che vengono', (
    tester,
  ) async {
    await capture(
      tester,
      const QueueScreen(),
      name: 'coda_sezioni',
      size: const Size(430, 932),
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(
            PlayerState(
              queue: [_t('a'), _t('b'), _t('c'), _t('d')],
              currentIndex: 1,
              isPlaying: true,
            ),
          ),
        ),
      ],
    );

    expect(find.text('Brano b'), findsOneWidget, reason: 'in riproduzione');
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Brano c'), findsOneWidget);
    expect(find.text('Brano d'), findsOneWidget);
    // Il gia' ascoltato sta nella cronologia, chiusa.
    expect(find.text('Brano a'), findsNothing);
    expect(find.text('History'), findsOneWidget);
    for (final m in ['Shuffle', 'Repeat', 'Autoplay']) {
      expect(find.text(m), findsOneWidget);
    }

    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Brano a'), findsOneWidget);
  });
}
