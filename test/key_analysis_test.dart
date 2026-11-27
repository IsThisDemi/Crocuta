import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/services/key_analysis.dart';

const rate = 11025;

/// Una progressione di accordi, un secondo ciascuno, con qualche armonico:
/// abbastanza per avere un centro tonale, come un brano.
Int16List chords(List<List<double>> progression, {int seconds = 24}) {
  final out = Int16List(rate * seconds);
  for (var i = 0; i < out.length; i++) {
    final t = i / rate;
    final chord = progression[(t).floor() % progression.length];
    var v = 0.0;
    for (final f in chord) {
      v += math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t);
    }
    out[i] = (v / chord.length * 0.5 * 32767).round();
  }
  return out;
}

double hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();
List<double> triad(int root, {bool minor = false}) => [
  hz(root),
  hz(root + (minor ? 3 : 4)),
  hz(root + 7),
];

void main() {
  test('do maggiore: I IV V I', () {
    final key = estimateKey(
      chords([triad(60), triad(65), triad(67), triad(60)]),
      rate,
    )!;
    expect(key.name, 'C');
    expect(key.camelotName, '8B');
  });

  test('la minore: i iv v i', () {
    final key = estimateKey(
      chords([
        triad(57, minor: true),
        triad(62, minor: true),
        triad(64, minor: true),
        triad(57, minor: true),
      ]),
      rate,
    )!;
    expect(key.name, 'Am');
    expect(key.camelotName, '8A');
  });

  test('sol maggiore', () {
    final key = estimateKey(
      chords([triad(55), triad(60), triad(62), triad(55)]),
      rate,
    )!;
    expect(key.name, 'G');
  });

  test('la ruota di Camelot: vicine, relative, lontane', () {
    const c = MusicalKey(0, false); // 8B
    expect(c.distanceTo(const MusicalKey(0, false)), 0);
    expect(c.distanceTo(const MusicalKey(7, false)), 0.3); // G, 9B
    expect(c.distanceTo(const MusicalKey(9, true)), 0.3); // Am, 8A
    expect(c.distanceTo(const MusicalKey(6, false)), 1); // F#, 2B
  });

  test('troppo corto o muto: nessuna tonalita\'', () {
    expect(estimateKey(Int16List(rate * 2), rate), isNull);
    expect(estimateKey(Int16List(rate * 30), rate), isNull);
  });
}
