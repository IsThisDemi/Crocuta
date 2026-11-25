import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/queue_screen.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/widgets/sub_page.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const track = Track(
  id: 'x1',
  title: 'Fame is a Gun',
  author: 'Addison Rae',
  thumbnailUrl: '',
);

final playing = [
  playerProvider.overrideWith(
    () => FakePlayer(
      const PlayerState(queue: [track], currentIndex: 0, isPlaying: true),
    ),
  ),
];

void main() {
  testWidgets('la coda aperta dal player non raddoppia il margine', (
    tester,
  ) async {
    await capture(
      tester,
      const SubPage(child: QueueScreen()),
      name: 'coda_da_player',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: playing,
    );
    final pushed = tester.getRect(find.text('Queue')).top;

    await capture(
      tester,
      const QueueScreen(),
      name: 'coda_da_navbar',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: playing,
    );
    final root = tester.getRect(find.text('Queue')).top;

    // Aperta dal brano in riproduzione la coda sta dentro una SubPage, che
    // ha gia' la sua barra di vetro: il titolo scende di quella, non del
    // doppio. Prima sommava anche una SafeArea sua, e si apriva con circa
    // duecento pixel di vuoto sopra il titolo.
    expect(pushed, greaterThan(root));
    expect(
      pushed - root,
      lessThan(80),
      reason: 'la differenza deve essere la barra, non barra + area sicura',
    );
  });
}
