import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/services/player_controller.dart';

/// Applica lo spostamento a una coda finta, per verificare insieme dove
/// finisce l'elemento e cosa resta a suonare.
(List<String>, String?) move(
  List<String> queue,
  int currentIndex,
  int from,
  int rawTo,
) {
  final plan = PlayerController.resolveMove(
    length: queue.length,
    current: currentIndex,
    from: from,
    rawTo: rawTo,
  );
  if (plan == null) return (queue, queue[currentIndex]);
  final q = [...queue];
  q.insert(plan.$1, q.removeAt(from));
  return (q, q[plan.$2]);
}

void main() {
  const q = ['a', 'b', 'c', 'd'];

  test('sposta in avanti', () {
    // Trascinando "a" fra "c" e "d", ReorderableListView riferisce 3.
    final (out, playing) = move(q, 0, 0, 3);
    expect(out, ['b', 'c', 'a', 'd']);
    // Suonava "a": deve continuare a suonare "a".
    expect(playing, 'a');
  });

  test('sposta indietro', () {
    final (out, playing) = move(q, 3, 3, 1);
    expect(out, ['a', 'd', 'b', 'c']);
    expect(playing, 'd');
  });

  test('il brano in ascolto resta lo stesso quando si sposta un altro', () {
    // Suona "c". Si sposta "a" dopo di esso: "c" scala indietro di uno,
    // ma deve restare lui a suonare.
    final (out, playing) = move(q, 2, 0, 4);
    expect(out, ['b', 'c', 'd', 'a']);
    expect(playing, 'c');
  });

  test('spostare qualcosa prima di quello in ascolto lo fa scalare avanti', () {
    // Suona "b". Si porta "d" in cima.
    final (out, playing) = move(q, 1, 3, 0);
    expect(out, ['d', 'a', 'b', 'c']);
    expect(playing, 'b');
  });

  test('uno spostamento che non muove niente viene ignorato', () {
    expect(
      PlayerController.resolveMove(length: 4, current: 0, from: 1, rawTo: 1),
      isNull,
    );
    expect(
      PlayerController.resolveMove(length: 4, current: 0, from: 1, rawTo: 2),
      isNull,
    );
  });

  test('indici fuori dalla coda non fanno niente', () {
    expect(
      PlayerController.resolveMove(length: 4, current: 0, from: 9, rawTo: 1),
      isNull,
    );
    expect(
      PlayerController.resolveMove(length: 4, current: 0, from: 0, rawTo: 99),
      isNull,
    );
  });
}
