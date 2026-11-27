import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/eq_screen.dart';
import 'package:crocuta/services/eq_controller.dart';
import 'package:crocuta/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _track = Track(
  id: 'xyz',
  title: 'Corrente Ascensionale',
  author: 'Marea Bassa',
  thumbnailUrl: '',
);

/// Un equalizzatore gia' regolato: piatto non si vedrebbe la curva.
class _FakeEq extends EqController {
  @override
  EqState build() => EqState([
    for (final (f, g) in [
      (32.0, 6.0),
      (64.0, 5.0),
      (125.0, 3.0),
      (250.0, 1.0),
      (500.0, -2.0),
      (1000.0, -1.5),
      (2000.0, 0.0),
      (4000.0, 2.0),
      (8000.0, 4.0),
      (16000.0, 5.0),
    ])
      EqBand(frequency: f, gain: g),
  ], preamp: -3);
}

void main() {
  testWidgets('cattura: equalizzatore', (tester) async {
    await capture(
      tester,
      const EqScreen(),
      name: 'equalizzatore',
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(const PlayerState(queue: [_track], currentIndex: 0)),
        ),
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
        eqProvider.overrideWith(_FakeEq.new),
      ],
    );
  });

  testWidgets('cattura: equalizzatore su finestra larga', (tester) async {
    await capture(
      tester,
      const EqScreen(),
      name: 'equalizzatore_largo',
      size: const Size(1100, 800),
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(const PlayerState(queue: [_track], currentIndex: 0)),
        ),
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
        eqProvider.overrideWith(_FakeEq.new),
      ],
    );
  });
}
