import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/screens/stats_screen.dart';

void main() {
  test('il tempo di ascolto si legge, non si converte a mente', () {
    // "188 minuti" e' un'unita' grezza: sono tre ore e otto.
    expect(listeningTime(188), '3 h 8 min');
    expect(listeningTime(45), '45 min');
    expect(listeningTime(60), '1 h');
    expect(listeningTime(120), '2 h');
    expect(listeningTime(0), '0 min');
    expect(listeningTime(59), '59 min');
    expect(listeningTime(61), '1 h 1 min');
  });
}
