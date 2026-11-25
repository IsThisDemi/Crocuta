import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/shuffle_order.dart';

void main() {
  test('rimescolati, tutti e una volta sola', () {
    final ids = [for (var i = 0; i < 30; i++) 'b$i'];
    for (var seed = 0; seed < 20; seed++) {
      final out = shuffleUpcoming(
        ids,
        isRadio: (_) => false,
        random: Random(seed),
      );
      expect(out.toSet(), ids.toSet());
      expect(out.length, ids.length);
    }
    // E davvero rimescolati: con trenta brani l'ordine uguale e' un caso
    // che non capita.
    expect(
      shuffleUpcoming(ids, isRadio: (_) => false, random: Random(1)),
      isNot(ids),
    );
  });

  test('i brani della radio restano in fondo, nel loro ordine', () {
    final own = [for (var i = 0; i < 10; i++) 'b$i'];
    const radio = ['r0', 'r1', 'r2'];
    final out = shuffleUpcoming(
      [...own.sublist(0, 5), 'r0', 'r1', ...own.sublist(5), 'r2'],
      isRadio: (t) => t.startsWith('r'),
      random: Random(3),
    );
    expect(out.sublist(0, 10).toSet(), own.toSet());
    expect(out.sublist(10), radio);
  });

  test('spento lo shuffle torna l\'ordine della raccolta', () {
    const original = {'a': 0, 'b': 1, 'c': 2, 'd': 3};
    final out = unshuffleUpcoming([
      'd',
      'x',
      'b',
      'c',
      'y',
    ], originalIndex: (t) => original[t]);
    // Quelli della raccolta al loro posto; gli aggiunti dopo in fondo, come
    // erano.
    expect(out, ['b', 'c', 'd', 'x', 'y']);
  });
}
