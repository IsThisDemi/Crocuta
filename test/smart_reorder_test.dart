import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/services/key_analysis.dart';
import 'package:crocuta/services/smart_reorder.dart';

MixTraits t(double bpm, int pc, {bool minor = false}) =>
    MixTraits(bpm, MusicalKey(pc, minor));

void main() {
  test('doppio e meta\' tempo battono insieme', () {
    expect(transitionCost(t(87, 0), t(174, 0)), closeTo(0, 1e-9));
    expect(transitionCost(t(120, 0), t(140, 0)), greaterThan(0.5));
  });

  test('stessa casella della ruota costa meno di una lontana', () {
    final c = t(120, 0); // 8B
    expect(
      transitionCost(c, t(120, 7)),
      lessThan(transitionCost(c, t(120, 6))),
    );
    expect(transitionCost(c, t(120, 9, minor: true)), 0.45 * 0.3);
  });

  test('una tonalita\' incerta pesa poco', () {
    const a = MixTraits(120, MusicalKey(0, false, 0.02));
    const b = MixTraits(120, MusicalKey(6, false, 0.02));
    expect(transitionCost(a, b), closeTo(0.45 * 0.5, 1e-9));
  });

  test('riordinata, la playlist costa meno, il primo resta il primo', () {
    final random = Random(7);
    for (var round = 0; round < 20; round++) {
      final traits = <MixTraits?>[
        for (var i = 0; i < 25; i++)
          MixTraits(
            <double>[90, 100, 120, 124, 128, 140, 174][random.nextInt(7)],
            MusicalKey(random.nextInt(12), random.nextBool(), 0.2),
          ),
      ];
      final order = smartOrder(traits);
      expect(order.first, 0);
      expect(order.toSet().length, traits.length);
      expect(
        pathCost(traits, order),
        lessThanOrEqualTo(pathCost(traits, [for (var i = 0; i < 25; i++) i])),
      );
    }
  });

  test('i brani senza analisi restano in fondo, in ordine', () {
    final order = smartOrder([
      t(120, 0),
      null,
      t(128, 7),
      t(121, 0),
      null,
      t(127, 7),
    ]);
    expect(order.sublist(0, 4).toSet(), {0, 2, 3, 5});
    expect(order.sublist(4), [1, 4]);
    // Vicini con vicini: dopo il primo (120, do) viene il 121 in do.
    expect(order[1], 3);
  });
}
