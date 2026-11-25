import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/screens/eq_screen.dart';
import 'package:yeen_music/services/eq_controller.dart';

EqState _with(List<double> gains, {double preamp = 0, bool on = true}) =>
    EqState(
      [
        for (var i = 0; i < eqFrequencies.length; i++)
          EqBand(frequency: eqFrequencies[i], gain: gains[i]),
      ],
      preamp: preamp,
      enabled: on,
    );

void main() {
  final flat = List<double>.filled(10, 0);

  test('la catena: solo le bande mosse, a ottave, niente filtro volume', () {
    final s = _with([6, 0, 0, 0, 0, 0, 0, 0, 0, -3], preamp: -4);
    // Il preamp non entra nella catena: "volume" in questo libmpv non
    // esiste, e con lui dentro la catena intera veniva rifiutata. Lo
    // applica il player al proprio volume.
    expect(
      s.filterChain,
      '@eq:lavfi=['
      'equalizer=f=32:t=o:w=1:g=6.0,'
      'equalizer=f=16000:t=o:w=1:g=-3.0]',
    );
  });

  test('spento o piatto, al player non arriva nessun filtro', () {
    expect(_with(flat).filterChain, '');
    expect(_with([6, ...flat.skip(1)], on: false).filterChain, '');
    expect(_with(flat, preamp: -2).filterChain, '');
  });

  test('le vecchie cinque bande diventano dieci con la stessa forma', () {
    final ten = gainsFromFiveBands([6, 4, 1, 0, -2]);
    expect(ten.length, 10);
    // 32 e 64 vicino ai 60 di prima, 16K vicino ai 12K.
    expect(ten[0], 6);
    expect(ten[1], 6);
    expect(ten[3], 4); // 250
    expect(ten[5], 1); // 1K
    expect(ten[9], -2);
  });

  test('ogni preset di Apple ha dieci bande, e si riconosce', () {
    for (final p in eqPresets) {
      expect(p.gains.length, 10, reason: p.name);
      expect(_with(p.gains).activePreset?.name, p.name);
    }
    expect(_with([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]).activePreset, isNull);
  });

  test('pallino e tocco usano la stessa scala', () {
    for (final g in [-12.0, -6.5, 0.0, 3.0, 12.0]) {
      expect(EqGraph.gainAt(EqGraph.yOf(g)), g);
    }
    // Oltre il bordo si ferma a +-12.
    expect(EqGraph.gainAt(-50), 12);
    expect(EqGraph.gainAt(EqGraph.height + 50), -12);
  });

  testWidgets(
    'trascinare alza la banda sotto il dito, doppio tocco la azzera',
    (tester) async {
      var gains = List<double>.filled(10, 0);
      var preamp = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 440,
                child: StatefulBuilder(
                  builder: (context, setState) => EqGraph(
                    preamp: preamp,
                    gains: gains,
                    labels: [for (final f in eqFrequencies) '$f'],
                    onPreamp: (v) => setState(() => preamp = v),
                    onBand: (i, v) =>
                        setState(() => gains = [...gains]..[i] = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final graph = tester.getRect(find.byType(CustomPaint).last);
      // 11 colonne da 40: la terza banda (125 Hz) e' la colonna 3.
      final x = graph.left + 40 * 3 + 20;
      await tester.dragFrom(
        Offset(x, graph.top + EqGraph.yOf(0)),
        const Offset(0, -60),
      );
      await tester.pump();
      expect(gains[2], greaterThan(0));
      expect(
        [
          for (var i = 0; i < 10; i++)
            if (i != 2) gains[i],
        ].every((g) => g == 0),
        isTrue,
      );
      expect(preamp, 0);

      await tester.tapAt(Offset(x, graph.top + 30));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(Offset(x, graph.top + 30));
      await tester.pumpAndSettle();
      expect(gains[2], 0);
    },
  );
}
