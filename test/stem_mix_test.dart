import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/automix.dart';
import 'package:yeen_music/services/stem_mix.dart';
import 'package:yeen_music/services/stem_separator.dart';

/// Base costante 0.1, voce che sale col tempo (0.5 + secondi/100): cosi'
/// dal valore si capisce anche *da dove* viene la voce.
Stems _stems(double seconds) {
  final n = (seconds * stemRate).round();
  final base = Float32List(n)..fillRange(0, n, 0.1);
  final voice = Float32List.fromList([
    for (var i = 0; i < n; i++) 0.5 + i / stemRate / 100,
  ]);
  return (vocalsL: voice, vocalsR: voice, baseL: base, baseR: base);
}

double _left(Float32List out, double t) => out[2 * (t * stemRate).round()];

BeatMixPlan _plan({StemPlan? stems, double? loopStart, double? loopEnd}) =>
    BeatMixPlan(
      kind: MixKind.blend,
      outStart: 100,
      inStart: 0.5,
      bars: 8,
      length: 16,
      speed: 1,
      loopStart: loopStart,
      loopEnd: loopEnd,
      stems: stems,
    );

void main() {
  test('all inizio e\' il brano com\'e\': voce piu\' base', () {
    final out = renderOutgoing(_stems(16), _plan(stems: const StemPlan()));
    expect(out.length, 16 * stemRate * 2);
    expect(_left(out, 0), closeTo(0.6, 1e-6));
    expect(_left(out, 10), closeTo(0.1 + 0.6, 1e-3));
  });

  test('la voce si spegne un battito prima dell entrante, la base resta', () {
    final out = renderOutgoing(
      _stems(16),
      _plan(stems: const StemPlan(duckAt: 6)),
    );
    expect(_left(out, 5), closeTo(0.1 + 0.55, 1e-3));
    // A meta' dello spegnimento, meta' voce.
    expect(_left(out, 5.75), closeTo(0.1 + 0.5575 / 2, 2e-3));
    expect(_left(out, 6.5), closeTo(0.1, 1e-6));
    expect(_left(out, 15), closeTo(0.1, 1e-6));
  });

  test('l ultima battuta cantata torna in eco, sempre piu piano', () {
    final out = renderOutgoing(
      _stems(16),
      _plan(stems: const StemPlan(echoFrom: 2, echoLength: 2, echoRepeats: 3)),
    );
    // Prima dell'eco la voce vera.
    expect(_left(out, 3), closeTo(0.1 + 0.53, 1e-3));
    // Prima ripetizione: la voce di 1 s dentro la battuta (a 3 s), ridotta.
    expect(_left(out, 5), closeTo(0.1 + 0.53 * StemPlan.echoGain(1), 1e-3));
    expect(_left(out, 7), closeTo(0.1 + 0.53 * StemPlan.echoGain(2), 1e-3));
    expect(_left(out, 9), closeTo(0.1 + 0.53 * StemPlan.echoGain(3), 1e-3));
    // Finite le ripetizioni, solo base.
    expect(_left(out, 11), closeTo(0.1, 1e-6));
  });

  test('dove la musica si ripete, si ripete solo la base', () {
    // La musica finisce a 110: l'ultima battuta (108-110) va in loop.
    final out = renderOutgoing(
      _stems(10),
      _plan(stems: const StemPlan(), loopStart: 108, loopEnd: 110),
    );
    expect(_left(out, 9), closeTo(0.1 + 0.59, 1e-3));
    expect(_left(out, 12), closeTo(0.1, 1e-6));
  });

  test('il wav ha l intestazione float stereo e i campioni giusti', () {
    final data = Float32List.fromList([0.25, -0.5, 1, 0]);
    final wav = wavFloat32(data);
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(b.getUint16(20, Endian.little), 3);
    expect(b.getUint16(22, Endian.little), 2);
    expect(b.getFloat32(44 + 4, Endian.little), -0.5);
    expect(wav.length, 44 + 16);
  });

  test(
    'nell eco il tratto parte dal battito prima del mix, e si ripete la base',
    () {
      // Eco: il battito 99.5-100 ripetuto per tutto il mix.
      final plan = _plan(
        stems: const StemPlan(),
        loopStart: 99.5,
        loopEnd: 100,
      );
      final w = outgoingWindow(plan);
      expect(w.start, 99.5);
      expect(w.end, 100);
      final out = renderOutgoing(_stems(0.5), plan);
      expect(out.length, 16 * stemRate * 2);
      // Solo base, niente voce ripetuta.
      expect(_left(out, 3.2), closeTo(0.1, 1e-6));
    },
  );

  test('l entrante: base da subito, voce dal passaggio, alla fine com e', () {
    final plan = BeatMixPlan(
      kind: MixKind.blend,
      outStart: 100,
      inStart: 0.5,
      bars: 8,
      length: 16,
      speed: 1.0,
      stems: const StemPlan(exchangeAt: 4),
    );
    final w = incomingWindow(plan);
    expect(w.start, 0.5);
    expect(w.end, 16.5);
    final out = renderIncoming(_stems(16), plan);
    expect(_left(out, 2), closeTo(0.1, 1e-6)); // solo base
    expect(_left(out, 4), closeTo(0.1 + 0.54 / 2, 1e-3)); // a meta' passaggio
    expect(_left(out, 10), closeTo(0.1 + 0.6, 1e-3)); // il brano com'e'
  });

  test('senza passaggio l entrante e il brano com e', () {
    final plan = _plan(stems: const StemPlan());
    final out = renderIncoming(_stems(4), plan);
    expect(_left(out, 1), closeTo(0.1 + 0.51, 1e-3));
  });

  test(
    'eco dopo la fine della musica: la battuta si separa e si sente intera',
    () {
      // La musica (e il loop) finisce a 102, l'ultima frase cantata e' la
      // battuta 102-104: oltre il loop, ma va separata e suonata.
      final plan = _plan(
        stems: const StemPlan(echoFrom: 2, echoLength: 2, echoRepeats: 3),
        loopStart: 100,
        loopEnd: 102,
      );
      final w = outgoingWindow(plan);
      expect(w.end, 104);
      final out = renderOutgoing(_stems(4), plan);
      // A 3 s: base in loop (0.1) e la voce vera di 103 s (0.53), non zittita.
      expect(_left(out, 3), closeTo(0.1 + 0.53, 1e-3));
      // A 5 s: la prima eco, di quella stessa battuta.
      expect(_left(out, 5), closeTo(0.1 + 0.53 * StemPlan.echoGain(1), 1e-3));
    },
  );

  test(
    'eco d uscita: il brano fino allo sgancio, poi l ultimo battito sempre piu piano',
    () {
      const rate = stemRate;
      const drop = 1.0, beat = 0.25, length = 2.0;
      final n = (drop * rate).round();
      // Un La a 1 kHz (passa il passa-alto) piu' un basso costante (no).
      final l = Float32List(n);
      for (var i = 0; i < n; i++) {
        l[i] = 0.5 * math.sin(2 * math.pi * 1000 * i / rate) + 0.3;
      }
      final out = renderEchoOut(l, l, drop: drop, beat: beat, length: length);
      expect(out.length, (length * rate).round() * 2);
      // Prima dello sgancio: il brano com'e'.
      expect(out[2 * 1000], closeTo(l[1000], 1e-6));
      // Dopo: ripetizioni, ognuna piu' debole, senza la parte costante.
      double peak(double from, double to) {
        var m = 0.0, sum = 0.0;
        final a = (from * rate).round(), b = (to * rate).round();
        for (var i = a; i < b; i++) {
          m = math.max(m, out[2 * i].abs());
          sum += out[2 * i];
        }
        expect((sum / (b - a)).abs(), lessThan(0.05), reason: 'niente bassi');
        return m;
      }

      final first = peak(drop + 0.05, drop + 0.2);
      final second = peak(drop + beat + 0.05, drop + beat + 0.2);
      expect(first, greaterThan(0.15));
      expect(second, lessThan(first * 0.7));
      expect(second, greaterThan(first * 0.4));
    },
  );

  test('eco a tempo: a mandata zero il tratto esce identico', () {
    final rnd = math.Random(1);
    final x = Float32List.fromList([
      for (var i = 0; i < stemRate * 2; i++) rnd.nextDouble() * 1.6 - 0.8,
    ]);
    final y = Float32List.fromList(x);
    applyTempoEcho(y, delay: 0.375, send: (_) => 0);
    expect(y, x);
  });

  test('eco a tempo: le ripetizioni cadono a tempo, ognuna a meta', () {
    // Un colpo a 0,1 s, poi silenzio; l'eco si manda tutta da 0,2 s: il
    // colpo asciutto c'e' ancora, poi solo le sue ripetizioni.
    final y = Float32List(stemRate * 2 * 2);
    final click = (0.1 * stemRate).round();
    y[2 * click] = 1;
    y[2 * click + 1] = 1;
    const delay = 0.25;
    applyTempoEcho(y, delay: delay, send: (t) => t < 0.2 ? 0 : 1);
    final d = (delay * stemRate).round();
    expect(y[2 * click], 1);
    expect(y[2 * (click + d)], closeTo(0.5, 0.05));
    expect(y[2 * (click + 2 * d)], closeTo(0.25, 0.05));
    expect(y[2 * (click + 3 * d)], closeTo(0.125, 0.04));
    // Fra una ripetizione e l'altra quasi niente.
    expect(y[2 * (click + d + d ~/ 2)].abs(), lessThan(0.01));
  });

  test('eco a tempo: mai piu forte del tratto com era', () {
    // Rumore forte e una cassa a tempo, con la mandata che sale: il caso
    // peggiore per un'eco che si somma.
    final rnd = math.Random(4);
    final n = stemRate * 4;
    final x = Float32List(n * 2);
    for (var i = 0; i < n; i++) {
      final t = i / stemRate;
      final kick = math.exp(-((t % 0.5) * 30)) * math.sin(2 * math.pi * 55 * t);
      final v = 0.6 * kick + 0.35 * (rnd.nextDouble() * 2 - 1);
      x[2 * i] = v;
      x[2 * i + 1] = -v;
    }
    var peakIn = 0.0;
    for (final v in x) {
      peakIn = math.max(peakIn, v.abs());
    }
    for (final delay in [0.25, 0.375, 0.5]) {
      final y = Float32List.fromList(x);
      applyTempoEcho(y, delay: delay, send: (t) => (t / 3).clamp(0.0, 1.0));
      var peakOut = 0.0;
      for (final v in y) {
        peakOut = math.max(peakOut, v.abs());
      }
      expect(peakOut, lessThanOrEqualTo(peakIn + 1e-6), reason: '$delay');
    }
  });

  test('la salita col filtro porta l eco nel tratto separato', () {
    final plan = BeatMixPlan(
      kind: MixKind.filterBuild,
      outStart: 100,
      inStart: 0.5,
      bars: 8,
      length: 16,
      speed: 1,
      stems: const StemPlan(),
      echoDelay: 0.25,
    );
    final out = renderOutgoing(_stems(16), plan);
    // All'inizio il brano com'e': l'eco non e' ancora mandata.
    expect(_left(out, 0), closeTo(0.6, 1e-6));
    expect(_left(out, 4), closeTo(0.1 + 0.54, 1e-3));
    // Alla fine il suono asciutto e' sparito: restano ripetizioni sempre
    // piu' deboli, mai sopra il tratto.
    expect(_left(out, 15.9).abs(), lessThan(0.3));
    for (final v in out) {
      expect(v.abs(), lessThanOrEqualTo(0.1 + 0.66 + 1e-6));
    }
  });
}
