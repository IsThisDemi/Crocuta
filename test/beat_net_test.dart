import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/beat_net.dart';

void main() {
  // Tre minuti a 95 BPM, battere sul terzo battito, con i difetti di una
  // rete vera: un po' di tremolio, qualche battito perso, qualche falso.
  ({List<double> beats, List<double> downbeats}) song({double drift = 0}) {
    final rnd = math.Random(7);
    const period = 60 / 95;
    final beats = <double>[];
    final downs = <double>[];
    for (var i = 0; i < 280; i++) {
      final t = 1.3 + i * period * (1 + drift * i / 280);
      if (rnd.nextDouble() < 0.05) continue; // perso
      final b = t + (rnd.nextDouble() - 0.5) * 0.02;
      beats.add(b);
      if (i % 4 == 2) downs.add(b);
      if (rnd.nextDouble() < 0.03) beats.add(t + period * 0.37); // falso
    }
    beats.sort();
    return (beats: beats, downbeats: downs);
  }

  test('la griglia trova tempo, fase e battere', () {
    final s = song();
    final g = fitGrid(s.beats, s.downbeats)!;
    expect(g.bpm, closeTo(95, 0.05));
    // Il battito 2 (il battere) cade a 1,3 + 2 periodi.
    final bar = g.firstBeat + g.downbeat * 60 / g.bpm;
    final expected = 1.3 + 2 * 60 / 95;
    final k = ((expected - bar) / (4 * 60 / g.bpm)).round();
    expect(bar + k * 4 * 60 / g.bpm, closeTo(expected, 0.02));
    expect(g.confidence, greaterThan(0.9));
  });

  test('un tempo che deriva: la griglia locale tiene, quella intera no', () {
    // Mezzo per cento in tre minuti: basta per sfasare di mezzo battito.
    final s = song(drift: 0.012);
    final whole = fitGrid(s.beats, s.downbeats)!;
    final tail = fitGrid(s.beats, s.downbeats, from: 110, to: 180)!;
    expect(tail.confidence, greaterThan(0.85));
    expect(tail.confidence, greaterThan(whole.confidence));
  });

  test('troppo pochi battiti: nessuna griglia', () {
    expect(fitGrid([1, 2, 3], const []), isNull);
  });

  test('lo spettrogramma ha 128 bande e un fotogramma ogni 441 campioni', () {
    final mono = Float32List(22050 * 2);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = math.sin(2 * math.pi * 440 * i / 22050) * 0.5;
    }
    final spect = beatNetSpectrogram(mono);
    expect(spect.length, (1 + mono.length ~/ 441) * 128);
    // Un La: l'energia sta in una banda sola, non ovunque.
    final frame = spect.sublist(50 * 128, 51 * 128);
    var top = 0;
    for (var m = 1; m < 128; m++) {
      if (frame[m] > frame[top]) top = m;
    }
    expect(frame[top], greaterThan(frame[5] + 3));
    expect(frame[top], greaterThan(frame[120] + 3));
  });
}
