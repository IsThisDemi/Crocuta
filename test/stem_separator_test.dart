import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/stem_separator.dart';

/// Una rete che non separa niente: restituisce il mix intero come "voce".
class _Identity implements SpectrogramNet {
  int calls = 0;
  @override
  Float32List run(Float32List spec) {
    calls++;
    return Float32List.fromList(spec);
  }
}

Float32List _tone(int n, double hz, {double phase = 0}) => Float32List.fromList([
  for (var i = 0; i < n; i++) 0.5 * math.sin(2 * math.pi * hz * i / 44100 + phase),
]);

double _maxErr(Float32List a, Float32List b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

void main() {
  // Minuscolo ma con tutte le bande alla rete: la ricostruzione deve
  // essere esatta, e con un segnale lungo parecchi blocchi si vede se i
  // bordi fra un blocco e l'altro combaciano.
  const tiny = MdxConfig(nFft: 64, hop: 16, dimF: 33, dimT: 16, compensate: 1);

  test('con la rete identita\' la voce e\' il mix, anche fra un blocco e l\'altro', () {
    final l = Float32List.fromList([
      for (var i = 0; i < 1000; i++) math.sin(i * 0.37) + 0.3 * math.cos(i * 1.9),
    ]);
    final r = Float32List.fromList([for (var i = 0; i < 1000; i++) math.sin(i * 0.11)]);
    final net = _Identity();
    final s = StemSeparator(net, tiny).separate(l, r);
    expect(net.calls, greaterThan(5)); // davvero piu' blocchi
    expect(_maxErr(s.vocalsL, l), lessThan(1e-5));
    expect(_maxErr(s.vocalsR, r), lessThan(1e-5));
    for (final x in [...s.baseL, ...s.baseR]) {
      expect(x.abs(), lessThan(1e-5));
    }
  });

  test('voce piu\' base rifanno sempre il brano', () {
    final l = _tone(700, 440);
    final r = _tone(700, 660);
    final s = StemSeparator(_Identity(), tiny).separate(l, r);
    for (var i = 0; i < l.length; i++) {
      expect(s.vocalsL[i] + s.baseL[i], closeTo(l[i], 1e-6));
      expect(s.vocalsR[i] + s.baseR[i], closeTo(r[i], 1e-6));
    }
  });

  test('col modello vero la voce esce compensata e senza le bande alte', () {
    // Un La a 440 Hz sta sotto le 3072 bande: passa, alzato di 1.021.
    final l = _tone(44100, 440);
    final r = _tone(44100, 440, phase: 1);
    final s = StemSeparator(_Identity()).separate(l, r);
    for (var i = 1000; i < 43000; i += 997) {
      expect(s.vocalsL[i], closeTo(l[i] * 1.021, 1e-3));
      expect(s.vocalsR[i], closeTo(r[i] * 1.021, 1e-3));
    }
  });
}
