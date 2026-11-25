import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/beat_analysis.dart';

/// Una batteria finta: cassa sul primo battito di ogni battuta, charleston
/// su tutti, silenzio prima e dopo.
Int16List drums({
  required double bpm,
  double lead = 2,
  double length = 40,
  double tail = 3,
  double offset = 0.137,
}) {
  final n = ((lead + length + tail) * analysisRate).round();
  final out = Float64List(n);
  final rnd = math.Random(7);
  final beat = 60 / bpm;
  var k = 0;
  for (var t = lead + offset; t < lead + length; t += beat, k++) {
    final start = (t * analysisRate).round();
    final kick = k % 4 == 0;
    for (var i = 0; i < analysisRate * 0.15 && start + i < n; i++) {
      final s = i / analysisRate;
      final env = math.exp(-s * 25);
      if (kick) out[start + i] += 0.8 * env * math.sin(2 * math.pi * 55 * s);
      out[start + i] += 0.25 * math.exp(-s * 60) * (rnd.nextDouble() * 2 - 1);
    }
  }
  return Int16List.fromList([
    for (final v in out) (v.clamp(-1.0, 1.0) * 32767).round(),
  ]);
}

void main() {
  for (final bpm in [120.0, 128.0, 95.0, 140.0]) {
    test('trova $bpm BPM, i battiti e il battere', () {
      const lead = 2.0, offset = 0.137;
      final g = analyzeBeats(drums(bpm: bpm, lead: lead, offset: offset));
      expect(g.bpm, closeTo(bpm, 1.0));
      // Il battito vero piu' vicino alla griglia: entro 20 ms.
      final beat = 60 / bpm;
      final truth = lead + offset;
      final phaseErr =
          ((g.firstBeat - truth) / beat -
                  ((g.firstBeat - truth) / beat).roundToDouble())
              .abs() *
          beat;
      expect(phaseErr, lessThan(0.02), reason: 'fase');
      // Il battere cade sulla cassa.
      final bars = (g.firstBar - truth) / (4 * beat);
      expect(
        (bars - bars.roundToDouble()).abs() * 4 * beat,
        lessThan(0.03),
        reason: 'battere',
      );
      // La musica comincia col primo colpo, non allo scadere del silenzio.
      expect(g.musicStart, closeTo(lead + offset, 0.05));
      expect(g.musicEnd, closeTo(lead + 40, 0.5));
      expect(g.confidence, greaterThan(0.3));
    });
  }

  test('il mezzo tempo del trap si legge al tempo intero', () {
    // Cassa ogni due battiti a 140, charleston su tutti: il rullante del
    // trap. Il periodo che si ripete di piu' e' quello a 70.
    final n = analysisRate * 40;
    final out = Float64List(n);
    final rnd = math.Random(5);
    const beat = 60 / 140;
    var k = 0;
    for (var t = 1.0; t < 39; t += beat, k++) {
      final start = (t * analysisRate).round();
      for (var i = 0; i < analysisRate * 0.12 && start + i < n; i++) {
        final s = i / analysisRate;
        if (k % 2 == 0) {
          out[start + i] +=
              0.8 * math.exp(-s * 20) * math.sin(2 * math.pi * 50 * s);
        }
        out[start + i] += 0.15 * math.exp(-s * 80) * (rnd.nextDouble() * 2 - 1);
      }
    }
    final pcm = Int16List.fromList([
      for (final v in out) (v.clamp(-1.0, 1.0) * 32767).round(),
    ]);
    expect(analyzeBeats(pcm).bpm, closeTo(140, 1.5));
  });

  test('il rumore non ha un tempo di cui fidarsi', () {
    final rnd = math.Random(3);
    final noise = Int16List.fromList([
      for (var i = 0; i < analysisRate * 30; i++)
        ((rnd.nextDouble() * 2 - 1) * 8000).round(),
    ]);
    expect(analyzeBeats(noise).confidence, lessThan(0.3));
  });

  test('la griglia va e torna dal json', () {
    const g = BeatGrid(
      bpm: 128,
      firstBeat: 0.5,
      downbeat: 2,
      musicStart: 0.4,
      musicEnd: 180,
      confidence: 0.8,
    );
    final back = BeatGrid.fromJson(g.toJson());
    expect(back.bpm, 128);
    expect(back.firstBar, closeTo(0.5 + 2 * 60 / 128, 1e-9));
    expect(back.barAtOrBefore(10), lessThanOrEqualTo(10));
  });

  test('le feature per le frasi: bassi, medi, acuti e attacchi', () {
    final g = analyzeBeats(drums(bpm: 120, length: 30));
    const dims = BeatGrid.featureDims;
    expect(g.features.length % dims, 0);
    final frames = g.features.length ~/ dims;
    // Mezzo secondo l'uno, per tutto il brano (2 + 30 + 3 secondi).
    expect(frames, inInclusiveRange(68, 70));
    double at(double t, int d) =>
        g.features[(t * BeatGrid.featureRate).floor() * dims + d];
    // Nel silenzio prima della musica niente; dentro, la cassa nei bassi.
    expect(at(0.5, 0), lessThan(-60));
    expect(at(10, 0), greaterThan(at(0.5, 0) + 30));
    expect(at(10, 3), greaterThan(at(0.5, 3)));
    // E tornano dal json.
    final back = BeatGrid.fromJson(g.toJson());
    expect(back.features.length, g.features.length);
  });
}
