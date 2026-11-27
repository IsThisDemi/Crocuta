import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/services/automix.dart';
import 'package:crocuta/services/mix_sync.dart';

BeatMixPlan _plan({
  double speed = 1,
  double outSpeed = 1,
  double outBeat = 0.5,
  double inBeat = 0.5,
  bool matched = true,
}) => BeatMixPlan(
  kind: matched ? MixKind.blend : MixKind.cut,
  outStart: 100,
  inStart: 2,
  bars: 8,
  length: 16,
  speed: speed,
  outSpeed: outSpeed,
  matched: matched,
  outBeat: matched ? outBeat : null,
  inBeat: matched ? inBeat : null,
);

void main() {
  group('lo scarto di fase', () {
    test('a tempo e zero; il segno dice chi e indietro', () {
      final p = _plan();
      expect(mixPhaseOffset(p, outAt: 105, inAt: 7), closeTo(0, 1e-9));
      // L'entrante e' 40 ms indietro: positivo.
      expect(mixPhaseOffset(p, outAt: 105, inAt: 6.96), closeTo(0.04, 1e-9));
      // Avanti di 30 ms: negativo.
      expect(mixPhaseOffset(p, outAt: 105, inAt: 7.03), closeTo(-0.03, 1e-9));
    });

    test('su un battito intero di distanza la fase e la stessa', () {
      // L'uscente che riparte dal loop di una battuta, o mezzo battito di
      // misura in piu': conta solo dove cade dentro il battito.
      final p = _plan();
      expect(mixPhaseOffset(p, outAt: 103, inAt: 6.96), closeTo(0.04, 1e-9));
      // Uno scarto di 480 ms su 500 e' 20 ms avanti, non indietro.
      expect(mixPhaseOffset(p, outAt: 105, inAt: 6.52), closeTo(-0.02, 1e-9));
    });

    test('con velocita e doppio tempo, in secondi veri', () {
      // L'entrante a 0,96x: 40 ms del suo brano sono 41,7 ms veri.
      final p = _plan(speed: 0.96, inBeat: 0.48);
      expect(
        mixPhaseOffset(p, outAt: 105, inAt: 2 + 5 * 0.96 - 0.04),
        closeTo(0.04 / 0.96, 1e-9),
      );
      // Entrante a doppio tempo: il suo battito e' mezzo di quello
      // dell'uscente, e la fase si conta sul piu' corto.
      final d = _plan(outBeat: 0.5, inBeat: 0.25);
      expect(mixPhaseOffset(d, outAt: 105, inAt: 6.98), closeTo(0.02, 1e-9));
      expect(mixPhaseOffset(d, outAt: 105, inAt: 6.75), closeTo(0, 1e-9));
    });

    test('senza battiti in comune non c e fase', () {
      expect(
        mixPhaseOffset(_plan(matched: false), outAt: 105, inAt: 7),
        isNull,
      );
    });
  });

  group('la correzione', () {
    test('sotto la soglia nessuna, sopra col segno dello scarto', () {
      expect(syncNudge(0), 0);
      expect(syncNudge(0.02), 0);
      expect(syncNudge(-0.025), 0);
      expect(syncNudge(0.04), closeTo(0.024, 1e-9)); // indietro: piu' svelto
      expect(syncNudge(-0.04), closeTo(-0.024, 1e-9)); // avanti: piu' piano
    });

    test('mai oltre il limite', () {
      expect(syncNudge(0.2), syncMaxNudge);
      expect(syncNudge(-0.2), -syncMaxNudge);
      expect(syncMaxNudge, lessThanOrEqualTo(0.03));
    });

    test('la mediana toglie gli scatti delle posizioni', () {
      expect(medianOf([0.01, 0.2, 0.012, -0.15, 0.011]), 0.011);
      expect(medianOf([1, 3]), 2);
      expect(medianOf(const []), 0);
    });
  });
}
