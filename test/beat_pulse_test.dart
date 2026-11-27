import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/spot.dart';
import 'package:crocuta/services/beat_analysis.dart';
import 'package:crocuta/services/beat_pulse.dart';

extension on BeatPulse {
  double at_(double t) => at(t).pulse;
}

/// Le macchie a tempo: un colpo su ogni battito, piu' forte sul primo
/// della battuta e dove i bassi sono pieni, niente fuori dalla musica.
void main() {
  // 120 BPM, un battito ogni mezzo secondo, primo battere a 1 s. I bassi:
  // vuoti nei primi 20 secondi, pieni dopo.
  final grid = BeatGrid(
    bpm: 120,
    firstBeat: 1,
    downbeat: 0,
    musicStart: 0.5,
    musicEnd: 60,
    confidence: 0.9,
    version: beatGridVersion,
    features: [
      for (var i = 0; i < 120; i++) ...[i < 40 ? -40.0 : -10.0, -20, -30, -20],
    ],
  );
  final pulse = BeatPulse(grid);
  // Il colpo arriva [BeatPulse.lead] prima del battito e sale in
  // [BeatPulse.attack]: il massimo cade qui.
  double peak(double beat) => beat - BeatPulse.lead + BeatPulse.attack;

  test('batte sul battito e si spegne prima del successivo', () {
    expect(pulse.followsAudio, isFalse);
    final on = pulse.at_(peak(31));
    final mid = pulse.at_(31.25);
    expect(on, greaterThan(0.9));
    expect(mid, lessThan(on * 0.15));
  });

  test('il primo della battuta e\' piu\' forte degli altri', () {
    expect(pulse.at_(peak(31)), greaterThan(pulse.at_(peak(31.5)) * 1.4));
  });

  test('dove i bassi sono vuoti batte piano', () {
    expect(pulse.at_(peak(11)), lessThan(pulse.at_(peak(31)) * 0.4));
    expect(pulse.at_(peak(11)), greaterThan(0));
  });

  test('niente prima e dopo la musica, niente con una griglia incerta', () {
    expect(pulse.at_(0.2), 0);
    expect(pulse.at_(61), 0);
    final shaky = BeatPulse(
      BeatGrid(
        bpm: 120,
        firstBeat: 1,
        downbeat: 0,
        musicStart: 0,
        musicEnd: 60,
        confidence: 0.1,
      ),
    );
    expect(shaky.at_(peak(30)), 0);
  });

  group('come un visualizzatore, con l\'inviluppo', () {
    // Trenta secondi a 30 fotogrammi: bassi bassi, con un colpo di cassa
    // ogni 15 fotogrammi (mezzo secondo) che sale di 20 dB per un
    // fotogramma. Gli attacchi sopra i bassi: radi nei primi 15 secondi,
    // fitti dopo.
    const rate = BeatGrid.envelopeRate;
    final env = <double>[
      for (var i = 0; i < 30 * rate; i++) ...[
        i % 15 == 0 ? -10.0 : -30.0,
        i < 15 * rate ? -20.0 : 0.0,
      ],
    ];
    final g = BeatGrid(
      bpm: 120,
      firstBeat: 0,
      downbeat: 0,
      musicStart: 0,
      musicEnd: 30,
      confidence: 0.9,
    );
    final v = BeatPulse(g, envelope: env);
    double frame(int i) => i / rate - BeatPulse.lead;

    test('ogni colpo di cassa gonfia, e la coda si spegne', () {
      expect(v.followsAudio, isTrue);
      final hit = v.at(frame(300)).pulse;
      final after = v.at(frame(307)).pulse;
      expect(hit, greaterThan(0.8));
      expect(after, lessThan(hit * 0.3));
    });

    test('segue l\'audio anche fuori dalla griglia', () {
      // Un colpo in piu' fra due battiti: la griglia non lo vede.
      final extra = [...env];
      extra[307 * BeatGrid.envelopeDims] = -10;
      final w = BeatPulse(g, envelope: extra);
      expect(w.at(frame(307)).pulse, greaterThan(0.8));
    });

    test('un tratto fitto ha piu\' energia di uno rado', () {
      expect(v.at(frame(5 * 30)).energy, lessThan(0.2));
      expect(v.at(frame(25 * 30)).energy, greaterThan(0.8));
    });

    test('niente fuori dalla musica', () {
      expect(v.at(31), noSpotBeat);
    });
  });

  test('dall\'audio vero: una cassa ogni mezzo secondo', () {
    // Venti secondi a 11 kHz: un colpo a 60 Hz ogni mezzo secondo, che si
    // spegne in 80 ms, sopra un fruscio leggero.
    const sr = analysisRate;
    final rnd = math.Random(3);
    final pcm = Int16List(sr * 20);
    for (var i = 0; i < pcm.length; i++) {
      final t = i / sr;
      final since = t % 0.5;
      final kick = math.sin(2 * math.pi * 60 * since) * math.exp(-since / 0.08);
      pcm[i] = ((kick * 0.8 + (rnd.nextDouble() - 0.5) * 0.02) * 32767).round();
    }
    final g = analyzeBeats(pcm);
    expect(g.envelope.length, greaterThan(19 * 30 * BeatGrid.envelopeDims));
    final v = BeatPulse(g);
    expect(v.followsAudio, isTrue);
    // Sul colpo e a meta' fra due colpi, su tutti i colpi da 5 a 15 s.
    var on = 0.0, off = 0.0;
    for (var k = 10; k < 30; k++) {
      on += v.at(k * 0.5 + 0.03 - BeatPulse.lead).pulse;
      off += v.at(k * 0.5 + 0.3 - BeatPulse.lead).pulse;
    }
    expect(on / 20, greaterThan(0.6));
    expect(off / 20, lessThan(on / 20 * 0.4));
  });

  group('la forma', () {
    const rect = Rect.fromLTWH(0, 0, 200, 200);
    const seed = 'https://example.com/cover.jpg';
    List<Offset> samples(Path p) => [
      for (final m in p.computeMetrics())
        for (var d = 0.0; d < m.length; d += m.length / 24)
          m.getTangentForOffset(d)!.position,
    ];
    double moved(Path a, Path b) {
      final sb = samples(b);
      return [
        for (final (i, p) in samples(a).indexed) (p - sb[i]).distance,
      ].reduce((x, y) => x > y ? x : y);
    }

    test('senza battito e\' quella di sempre', () {
      expect(
        moved(
          spotPath(rect, seed, time: 3),
          spotPath(rect, seed, time: 3, music: silentMusic),
        ),
        lessThan(0.01),
      );
    });

    test('col battito sobbalza, restando nel riquadro', () {
      final still = spotPath(rect, seed, time: 3);
      final kicked = spotPath(
        rect,
        seed,
        time: 3,
        music: (pulse: 1, snap: 0, energy: 0),
      );
      final snapped = spotPath(
        rect,
        seed,
        time: 3,
        music: (pulse: 0, snap: 1, energy: 0),
      );
      expect(moved(still, kicked), greaterThan(6));
      expect(moved(still, snapped), greaterThan(4));
      final b = kicked.getBounds();
      expect(b.left, closeTo(0, 0.5));
      expect(b.right, closeTo(200, 0.5));
    });

    test('una superficie piena cresce sul colpo, il filo no', () {
      const loud = (pulse: 1.0, snap: 0.0, energy: 0.0);
      final full = const SpotBorder(
        seed: seed,
        time: 3,
        music: loud,
      ).getOuterPath(rect).getBounds();
      final rim = const SpotBorder(
        seed: seed,
        time: 3,
        music: loud,
        swell: false,
      ).getOuterPath(rect).getBounds();
      expect(full.width, closeTo(200 * spotSwell(1), 0.5));
      expect(rim.width, closeTo(200, 0.5));
    });

    test('un tratto pieno respira piu\' ampio', () {
      final calm = spotPath(rect, seed, time: 3);
      final full = spotPath(
        rect,
        seed,
        time: 3,
        music: (pulse: 0, snap: 0, energy: 1),
      );
      final rest = spotPath(rect, seed, time: 0);
      expect(moved(rest, full), greaterThan(moved(rest, calm) * 1.5));
    });
  });
}
