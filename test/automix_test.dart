import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/lyrics.dart';
import 'package:crocuta/services/automix.dart';
import 'package:crocuta/services/beat_analysis.dart';
import 'package:crocuta/services/key_analysis.dart';
import 'package:crocuta/services/phrase_analysis.dart';

import 'sectioned_grid.dart';

Duration s(int seconds) => Duration(seconds: seconds);

void main() {
  test('la voce finisce all ultimo verso con del testo', () {
    final lyrics = Lyrics(
      title: 't',
      artist: 'a',
      lines: [
        LyricsLine(time: s(10), text: 'uno'),
        LyricsLine(time: s(150), text: 'ultimo'),
        LyricsLine(time: s(170), text: ''),
      ],
    );
    expect(vocalsEndOf(lyrics), s(154));
    expect(vocalsEndOf(null), isNull);
  });

  BeatGrid grid(double bpm, {double end = 200, double conf = 0.8}) => BeatGrid(
    bpm: bpm,
    firstBeat: 0.5,
    downbeat: 0,
    musicStart: 0.4,
    musicEnd: end,
    confidence: conf,
  );

  test('velocita per battere insieme, doppio e meta tempo compresi', () {
    expect(beatMatchSpeed(120, 124), closeTo(120 / 124, 1e-9));
    expect(beatMatchSpeed(140, 71), closeTo(140 / 142, 1e-9));
    expect(beatMatchSpeed(120, 100), isNull, reason: 'venti per cento: no');
  });

  test('il mix a tempo sta sulle battute e finisce con la musica', () {
    final p = planBeatMix(out: grid(120), incoming: grid(124))!;
    final out = grid(120);
    expect(p.speed, closeTo(120 / 124, 1e-9));
    // Tempi vicini e battiti sicuri: la transizione lunga, sedici battute.
    expect(p.kind, MixKind.blend);
    expect(p.bars, 16);
    expect(p.length, closeTo(32, 1e-9));
    // Su un battere.
    final bars = (p.outStart - out.firstBar) / out.barLength;
    expect((bars - bars.roundToDouble()).abs(), lessThan(1e-9));
    expect(p.outStart + p.length, lessThanOrEqualTo(out.musicEnd));
    expect(p.loops, isFalse);
    // L'entrante dal suo primo battere dopo il silenzio.
    expect(p.inStart, closeTo(0.5, 1e-9));
  });

  test('coda lunga dopo la voce: si comincia subito dopo il verso', () {
    // Voce finita a 2:30 su 3:20: saltare fin li' taglierebbe piu' di
    // trenta secondi di finale. Il mix finisce con la musica.
    final p = planBeatMix(out: grid(120), incoming: grid(120), vocalsEnd: 150)!;
    expect(p.outStart, closeTo(166.5, 1e-9));
  });

  test(
    'voce fino alla fine: si aspetta il verso e l ultima battuta va in loop',
    () {
      final p = planBeatMix(
        out: grid(120),
        incoming: grid(120),
        vocalsEnd: 197,
      )!;
      expect(p.outStart, greaterThanOrEqualTo(196));
      expect(p.loops, isTrue);
      expect(p.loopEnd! - p.loopStart!, closeTo(2, 1e-9)); // una battuta
      expect(p.loopEnd, lessThanOrEqualTo(200));
    },
  );

  test(
    'tempi lontani o battiti incerti: cambio secco, senza battiti in comune',
    () {
      for (final p in [
        planBeatMix(out: grid(120), incoming: grid(90))!,
        planBeatMix(out: grid(120, conf: 0.1), incoming: grid(120))!,
        planBeatMix(out: grid(120), incoming: grid(120, conf: 0.6))!,
      ]) {
        expect(p.kind, MixKind.cut);
        expect(p.matched, isFalse);
        expect(p.speed, 1.0);
        expect(p.length, greaterThan(6));
        expect(p.loops, isFalse);
        // Lo sgancio prima della fine della musica: dopo c'e' solo la coda.
        expect(p.outStart + cutLength * cutDrop, lessThanOrEqualTo(200));
      }
      expect(planBeatMix(out: grid(120), incoming: grid(124))!.matched, isTrue);
    },
  );

  test('transizione filtrata: una sola batteria alla volta', () {
    for (var t = 0.0; t <= 1.0; t += 0.01) {
      final o = cutStage(t, incoming: false);
      final i = cutStage(t, incoming: true);
      if (o.volume > 0.1 && i.volume > 0.1) {
        expect(math.min(o.low, i.low), lessThanOrEqualTo(-12), reason: '$t');
      }
    }
    // Prima dello scambio l'entrante si sente, ma "da sott'acqua".
    final early = cutStage(0.4, incoming: true);
    expect(early.volume, greaterThan(0.9));
    expect(early.low, lowCutDb);
    expect(early.high, lessThan(-6));
    // Alla fine resta l'entrante, pieno e piatto.
    final end = cutStage(1, incoming: true);
    expect(end.volume, closeTo(1, 1e-9));
    expect([end.low, end.mid, end.high], everyElement(closeTo(0, 1e-9)));
    expect(cutStage(1, incoming: false).volume, closeTo(0, 1e-9));
  });

  test('transizione filtrata: lo scambio cade sul battere di entrambi', () {
    final out = grid(120);
    final inc = grid(90);
    final p = planBeatMix(out: out, incoming: inc)!;
    expect(p.kind, MixKind.cut);
    final swapIn = p.inStart + p.length * cutDrop;
    final swapOut = p.outStart + p.length * cutDrop;
    double off(BeatGrid g, double t) {
      final b = (t - g.firstBar) / g.barLength;
      return (b - b.roundToDouble()).abs();
    }

    expect(off(inc, p.inStart), lessThan(1e-9));
    expect(off(inc, swapIn), lessThan(1e-6));
    expect(off(out, swapOut), lessThan(1e-9));
    expect(swapOut, lessThanOrEqualTo(out.musicEnd));
    expect(p.length, inInclusiveRange(6, 12));
  });

  test('tempi lontani fino al 25%: si incontrano a meta strada', () {
    final b = tempoBlend(85, 98)!;
    expect(85 * b.out, closeTo(98 * b.inc, 1e-9));
    expect((b.out - 1).abs(), lessThan(0.081));
    expect((b.inc - 1).abs(), lessThan(0.081));
    // 140 e 120: ognuno del 7-8%. 98 e 77 (27%): troppo, niente tempo.
    expect(tempoBlend(140, 120), isNotNull);
    expect(tempoBlend(98, 77), isNull);
    final far = tempoBlend(125, 100)!;
    expect((far.out - 1).abs(), lessThan(0.121));
    expect(tempoBlend(120, 124)!.out, 1, reason: 'vicini: si muove l entrante');
    expect(tempoBlend(120, 90), isNull);
    final p = planBeatMix(out: grid(85), incoming: grid(98))!;
    expect(p.matched, isTrue);
    expect(p.outSpeed, closeTo(b.out, 1e-9));
    expect(p.kind, MixKind.quick);
    expect(p.wallLength, closeTo(p.length / p.outSpeed, 1e-9));
  });

  test('in ritardo: il piano si rifa da li in avanti invece di rinunciare', () {
    final p = planBeatMix(out: grid(120), incoming: grid(124), notBefore: 190)!;
    expect(p.outStart, greaterThanOrEqualTo(190));
    expect(p.outStart + p.length, lessThanOrEqualTo(200));
    final q = planBeatMix(out: grid(120), incoming: grid(124), notBefore: 170)!;
    expect(q.outStart, greaterThanOrEqualTo(170));
    expect(q.kind, isNot(MixKind.cut), reason: 'c e ancora posto per un mix');
  });

  test('il mix comincia su una frase di quattro battute', () {
    // La fine della musica non cade su una frase: il mix, che finisce con
    // lei, comincerebbe a meta' frase; si sposta sulla frase vicina.
    final out = grid(120, end: 203.5);
    final p = planBeatMix(out: out, incoming: grid(124))!;
    final phrases = (p.outStart - out.firstBar) / (4 * out.barLength);
    expect((phrases - phrases.roundToDouble()).abs(), lessThan(1e-9));
  });

  BeatGrid withEnergy(double bpm, List<double> energy) => BeatGrid(
    bpm: bpm,
    firstBeat: 0.5,
    downbeat: 0,
    musicStart: 0.4,
    musicEnd: energy.length.toDouble(),
    confidence: 0.8,
    energy: energy,
  );

  test('si esce all inizio della parte calma del finale', () {
    // Tre minuti e mezzo a -10 dB, poi un outro a -18 da 170: il volume lo
    // trova alla battuta di 170,5, la frase vera comincia a 168,5 — una
    // battuta prima — e si esce li'.
    final e = [for (var i = 0; i < 210; i++) i < 170 ? -10.0 : -18.0];
    final p = planBeatMix(out: withEnergy(120, e), incoming: grid(120))!;
    expect(p.outStart, closeTo(168.5, 1e-9));
  });

  test('la transizione finisce prima che l entrante canti', () {
    // L'entrante canta dopo 10 s: stanno solo quattro battute.
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      inVocalsStart: 10.5,
    )!;
    expect(p.bars, 4);
    expect(p.kind, MixKind.quick);
    expect(p.inStart + p.length * p.speed, lessThanOrEqualTo(10.5));
  });

  test('se l entrante canta subito, si esce in eco', () {
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      inVocalsStart: 3,
    )!;
    expect(p.kind, MixKind.echo);
    expect(p.bars, 2);
    // Si ripete l'ultimo battito prima del mix.
    expect(p.loopEnd, p.outStart);
    expect(p.loopEnd! - p.loopStart!, closeTo(0.5, 1e-9));
  });

  test(
    'con la voce separata, lo scontro non accorcia il mix: la voce si spegne',
    () {
      // Lo stesso caso dell'eco: l'entrante canta dopo 2,5 s.
      final p = planBeatMix(
        out: grid(120),
        incoming: grid(120),
        inVocalsStart: 3,
        stems: true,
      )!;
      expect(p.kind, MixKind.blend);
      expect(p.bars, 16);
      // Spenta un battito prima che canti l'entrante.
      expect(p.stems!.duckAt, closeTo(2.5 - 0.5, 1e-9));
    },
  );

  test('senza scontro la voce uscente non si spegne', () {
    final p = planBeatMix(out: grid(120), incoming: grid(120), stems: true)!;
    expect(p.stems!.duckAt, double.infinity);
    expect(p.stems!.echoFrom, isNull);
  });

  test('l ultima battuta cantata si ripete in eco, se c e posto', () {
    // La voce arriva fin quasi alla fine: il mix parte col verso ancora in
    // corso e l'ultima battuta di voce si ripete sopra la musica.
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      vocalsEnd: 173,
      stems: true,
    )!;
    final st = p.stems!;
    expect(st.echoFrom, isNotNull);
    expect(st.echoLength, closeTo(2, 1e-9)); // una battuta
    expect(st.echoRepeats, 3);
    // La battuta dell'eco contiene la fine della voce.
    final from = p.outStart + st.echoFrom!;
    expect(from, lessThanOrEqualTo(173));
    expect(from + st.echoLength, greaterThan(173));
    expect(StemPlan.echoGain(1), lessThan(1));
    expect(StemPlan.echoGain(3), lessThan(StemPlan.echoGain(2)));
  });

  test(
    'con la voce separata il mix parte una battuta prima dell ultima cantata',
    () {
      // Senza stem si aspetterebbe la fine del verso (a 185 su 200); con gli
      // stem si entra prima, e l'ultima battuta cantata va in eco.
      final p = planBeatMix(
        out: grid(120),
        incoming: grid(120),
        vocalsEnd: 185,
        stems: true,
      )!;
      final st = p.stems!;
      expect(st.echoFrom, closeTo(2, 1e-9)); // una battuta dentro il mix
      expect(p.outStart + st.echoFrom!, lessThanOrEqualTo(185));
      expect(p.outStart + st.echoFrom! + 2, greaterThan(185));
      expect(st.echoRepeats, greaterThanOrEqualTo(2));
      final classic = planBeatMix(
        out: grid(120),
        incoming: grid(120),
        vocalsEnd: 185,
      )!;
      expect(p.outStart, lessThan(classic.outStart));
    },
  );

  test('entrante che canta subito: niente voce tagliata a meta frase', () {
    // Il caso di "moment": canta appena parte. L'eco non ci sta e la voce
    // spenta all'istante zero taglierebbe l'uscente: si aspetta il verso.
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      vocalsEnd: 185,
      inVocalsStart: 0.8,
      stems: true,
    )!;
    expect(p.stems!.echoFrom, isNull);
    expect(p.stems!.duckAt, double.infinity);
    expect(p.outStart, greaterThanOrEqualTo(185));
  });

  test(
    'passaggio di voce: l uscente finisce la riga, poi canta l entrante',
    () {
      // L'entrante canterebbe a 2,5 s dal via; l'uscente ha una riga che
      // finisce a 3,7 s dal via (170,2 con il mix da 166,5).
      final p = planBeatMix(
        out: grid(120),
        incoming: grid(120),
        inVocalsStart: 3,
        outLines: const [150, 170.2],
        stems: true,
      )!;
      expect(p.outStart, 166.5);
      expect(p.kind, MixKind.blend); // non si accorcia
      final st = p.stems!;
      expect(st.exchangeAt, closeTo(3.7, 1e-9));
      // L'uscente sfuma attorno alla fine della riga...
      expect(st.duckAt, closeTo(3.95, 1e-9));
      // Nella pausa del cantato il passaggio puo' scivolare fino a due
      // battute dopo che l'entrante avrebbe cominciato (2,5 + 4 s).
      expect(st.latestDuck, closeTo(6.75, 1e-9));
      expect(st.handoverStart, closeTo(3.45, 1e-9));
      // Le griglie dei due brani, per il controllo del tempo.
      expect(p.outBeat, 0.5);
      expect(p.inBeat, 0.5);
      // ...mentre la voce dell'entrante entra li'.
      expect(st.incomingVoice(3.0), 0);
      expect(st.incomingVoice(3.7), closeTo(0.5, 1e-9));
      expect(st.incomingVoice(4.0), 1);
    },
  );

  test('senza una riga che finisca in tempo, niente passaggio', () {
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      inVocalsStart: 3,
      outLines: const [150, 180], // la riga finisce troppo tardi
      stems: true,
    )!;
    expect(p.stems!.exchangeAt, isNull);
    expect(p.stems!.incomingVoice(1), 1);
  });

  test('l eco non arriva mai sopra la voce dell entrante', () {
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      vocalsEnd: 173,
      inVocalsStart: 12,
      stems: true,
    )!;
    final st = p.stems!;
    if (st.echoFrom != null) {
      final end = st.echoFrom! + st.echoLength * (st.echoRepeats + 1);
      expect(end, lessThanOrEqualTo(st.duckAt + 1e-9));
    }
  });

  test('tempi un po lontani: transizione media', () {
    final p = planBeatMix(out: grid(120), incoming: grid(126))!;
    expect(p.kind, MixKind.quick);
    expect(p.bars, 8);
  });

  test('a tappe: una cassa per volta, e alla fine resta solo l entrante', () {
    for (var t = 0.0; t <= 1.0; t += 0.05) {
      final o = blendStage(t, incoming: false);
      final i = blendStage(t, incoming: true);
      // Mai due bassi pieni insieme: almeno uno dei due tagliato di 12 dB.
      if (o.volume > 0.1 && i.volume > 0.1) {
        expect(math.min(o.low, i.low), lessThanOrEqualTo(-12), reason: '$t');
      }
    }
    expect(blendStage(0, incoming: true).volume, closeTo(0, 1e-9));
    expect(blendStage(1, incoming: true).low, 0);
    expect(blendStage(1, incoming: false).volume, closeTo(0, 1e-9));
    // L'uscente resta pieno finche' l'entrante non ha preso i bassi.
    expect(blendStage(0.6, incoming: false).volume, closeTo(1, 1e-9));
  });

  test('il livello dell entrante si allinea al tratto dell uscente', () {
    // L'outro a -18, l'intro dell'altro a -10: l'entrante va giu' di 3
    // (non di 8: il limite e' tre, di piu' il mix sembra un calo).
    expect(levelTrimDb(outLevel: -18, inLevel: -10), -3);
    expect(levelTrimDb(outLevel: -14, inLevel: -12), -2);
    // Mai in su: un master a 0 dBFS alzato satura. Scende l'uscente.
    expect(levelTrimDb(outLevel: -8, inLevel: -16), 0);
    expect(outgoingCutDb(outLevel: -8, inLevel: -16), 3);
    expect(outgoingCutDb(outLevel: -18, inLevel: -10), 0);
  });

  test('nel mix i due brani insieme non superano un brano solo', () {
    // Era l'entrata "a tutto volume": entrambi pieni per un tratto, e la
    // somma saturava.
    for (final stage in [blendStage, echoStage]) {
      for (var k = 0; k <= 100; k++) {
        final t = k / 100;
        for (final cut in [0.0, 3.0, 6.0]) {
          final g = mixGains(
            stage(t, incoming: false).volume,
            stage(t, incoming: true).volume,
            outCutDb: cut,
          );
          expect(
            g.out * g.out + g.inc * g.inc,
            lessThanOrEqualTo(1 + 1e-9),
            reason: 't=$t cut=$cut',
          );
        }
      }
    }
    // Ai capi resta un brano solo, pieno: l'inizio e la fine del mix non
    // cambiano, e il passaggio di mano all'entrante non fa gradini.
    final start = mixGains(1, 0, outCutDb: 6);
    expect(start.out, closeTo(1, 1e-9));
    final end = mixGains(0, 1, outCutDb: 6);
    expect(end.inc, closeTo(1, 1e-9));
    // L'uscente scende verso il livello dell'entrante man mano che entra.
    expect(mixGains(1, 0.5, outCutDb: 6).out, lessThan(mixGains(1, 0.5).out));

    // Con le bande: la potenza vera dei due non supera un brano solo, e un
    // entrante ancora senza bassi ne' medi non abbassa quasi l'uscente.
    for (var k = 0; k <= 100; k++) {
      final t = k / 100;
      final o = blendStage(t, incoming: false);
      final i = blendStage(t, incoming: true);
      final g = mixGains(o.volume, i.volume, outShape: o, inShape: i);
      final eo = g.out * bandEnergy(o), ei = g.inc * bandEnergy(i);
      expect(eo * eo + ei * ei, lessThanOrEqualTo(1 + 1e-9), reason: '$t');
    }
    final thin = blendStage(0.3, incoming: true);
    final full = blendStage(0.3, incoming: false);
    final g = mixGains(1, 1, outShape: full, inShape: thin);
    expect(g.out, greaterThan(0.9), reason: 'prima -3 dB, ora meno di 1');
  });

  test('dopo l ultimo verso dell uscente, la voce dell entrante non conta', () {
    // L'uscente ha finito di cantare: la sua coda e' strumentale, e
    // l'entrante che canta subito ci sta sopra senza scontri.
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      vocalsEnd: 150,
      inVocalsStart: 3,
    )!;
    expect(p.kind, isNot(MixKind.echo));
    expect(p.bars, greaterThanOrEqualTo(8));
  });

  test('col loop, al massimo otto battute', () {
    final p = planBeatMix(out: grid(120), incoming: grid(120), vocalsEnd: 197)!;
    expect(p.loops, isTrue);
    expect(p.bars, 8);
  });

  // --- Frasi, stili ed effetti ---

  test('lo stile per coppia: le regole, in tabella', () {
    const rollingPair = MixFacts(
      phrased: true,
      closeTempo: true,
      keyDistance: 0.3,
      lowOutro: true,
      outroBars: 16,
      introBars: 16,
    );
    final cases = <(String, MixFacts, MixKind)>[
      (
        'senza sezioni, tempi vicini',
        const MixFacts(closeTempo: true),
        MixKind.blend,
      ),
      ('senza sezioni, tempi lontani', const MixFacts(), MixKind.quick),
      (
        'outro calmo, intro lunga, tonalita vicine',
        rollingPair,
        MixKind.rolling,
      ),
      (
        'la stessa coppia, tonalita ignota',
        const MixFacts(
          phrased: true,
          closeTempo: true,
          lowOutro: true,
          outroBars: 16,
          introBars: 16,
        ),
        MixKind.blend,
      ),
      (
        'la stessa coppia, tempi meno vicini',
        const MixFacts(
          phrased: true,
          keyDistance: 0,
          lowOutro: true,
          outroBars: 16,
          introBars: 16,
        ),
        MixKind.quick,
      ),
      (
        'outro calmo ma corto',
        const MixFacts(
          phrased: true,
          closeTempo: true,
          keyDistance: 0,
          lowOutro: true,
          outroBars: 8,
          introBars: 16,
        ),
        MixKind.blend,
      ),
      (
        'tonalita che stridono',
        const MixFacts(
          phrased: true,
          closeTempo: true,
          keyDistance: 1,
          introBars: 8,
          dropRise: 6,
        ),
        MixKind.filterBuild,
      ),
      (
        'drop dopo otto battute, uscente pieno',
        const MixFacts(
          phrased: true,
          closeTempo: true,
          keyDistance: 0,
          introBars: 8,
          dropRise: 6,
        ),
        MixKind.dropSwap,
      ),
      (
        'drop troppo debole',
        const MixFacts(
          phrased: true,
          closeTempo: true,
          introBars: 8,
          dropRise: 2,
        ),
        MixKind.blend,
      ),
      (
        'drop, ma l uscente esce da un outro calmo',
        const MixFacts(
          phrased: true,
          closeTempo: true,
          lowOutro: true,
          outroBars: 8,
          introBars: 8,
          dropRise: 6,
        ),
        MixKind.blend,
      ),
      (
        'entrante pieno su uscente pieno',
        const MixFacts(phrased: true, closeTempo: true),
        MixKind.filterBuild,
      ),
      (
        'entrante pieno su outro calmo',
        const MixFacts(phrased: true, lowOutro: true, outroBars: 16),
        MixKind.quick,
      ),
    ];
    for (final (name, facts, kind) in cases) {
      final a = chooseMixStyle(facts), b = chooseMixStyle(facts);
      expect(a.kind, kind, reason: name);
      expect(a.reason, isNotEmpty, reason: name);
      // Niente a caso: la stessa coppia, lo stesso mix.
      expect((b.kind, b.reason), (a.kind, a.reason), reason: name);
    }
  });

  final styles = <String, MixStage Function(double, {required bool incoming})>{
    'blend': blendStage,
    'rolling': rollingStage,
    'learned': learnedStage,
    'dropSwap': (t, {required incoming}) =>
        dropSwapStage(t, incoming: incoming, swapAt: 0.8, swapWidth: 0.025),
    'filterBuild': filterBuildStage,
    'echo': echoStage,
    'cut': cutStage,
    'fade': fadeStage,
  };

  // L'ampiezza di bassi, medi e acuti di un player, 0-1: il volume per il
  // guadagno della banda.
  List<double> bandAmps(MixStage s) => [
    for (final db in [s.low, s.mid, s.high])
      s.volume * math.pow(10, db / 20).toDouble(),
  ];

  bool neutralFilters(MixStage s) =>
      highpassSetting(s.highpass).mix == 0 &&
      lowpassSetting(s.lowpass).mix == 0;

  for (final MapEntry(key: name, value: stage) in styles.entries) {
    test('$name: capi del mix, curve monotone, niente sale mai', () {
      // All'inizio l'uscente com'e' e l'entrante muto; alla fine il
      // contrario, l'entrante pieno e piatto.
      final o0 = stage(0, incoming: false), i0 = stage(0, incoming: true);
      final o1 = stage(1, incoming: false), i1 = stage(1, incoming: true);
      expect(o0.volume, closeTo(1, 1e-9));
      expect([o0.low, o0.mid, o0.high, o0.echo], everyElement(0));
      expect(neutralFilters(o0), isTrue);
      expect(i0.volume, closeTo(0, 1e-9));
      expect(o1.volume, closeTo(0, 1e-9));
      expect(i1.volume, closeTo(1, 1e-9));
      expect([i1.low, i1.mid, i1.high], everyElement(closeTo(0, 1e-9)));
      expect(neutralFilters(i1), isTrue);
      expect(i1.echo, 0);

      MixStage? po, pi;
      for (var k = 0; k <= 400; k++) {
        final t = k / 400;
        final o = stage(t, incoming: false), i = stage(t, incoming: true);
        for (final x in [o, i]) {
          expect(x.volume, inInclusiveRange(0, 1), reason: '$t');
          expect(x.low, lessThanOrEqualTo(0), reason: '$t');
          expect(x.mid, lessThanOrEqualTo(0), reason: '$t');
          expect(x.high, lessThanOrEqualTo(0), reason: '$t');
          expect(x.echo, inInclusiveRange(0, 1), reason: '$t');
        }
        expect(i.echo, 0, reason: "l'eco e' solo sull'uscente");
        if (po != null && pi != null) {
          const e = 1e-12;
          expect(o.volume, lessThanOrEqualTo(po.volume + e), reason: '$t');
          expect(i.volume, greaterThanOrEqualTo(pi.volume - e), reason: '$t');
          // Ogni banda, come si sente: volume per guadagno. Scende
          // nell'uscente e sale nell'entrante, sempre.
          for (final (now, before) in [
            (bandAmps(o), bandAmps(po)),
            (bandAmps(pi), bandAmps(i)),
          ]) {
            for (var b = 0; b < 3; b++) {
              expect(now[b], lessThanOrEqualTo(before[b] + 1e-9), reason: '$t');
            }
          }
          // E le manopole stesse. Non nelle curve dai DJ: li' i medi
          // dell'uscente se ne vanno prima dei suoi acuti, il volume scende
          // con loro e gli acuti, che in assoluto calano, risalgono verso lo
          // zero rispetto al volume.
          if (name != 'learned') {
            expect(o.low, lessThanOrEqualTo(po.low + e), reason: '$t');
            expect(o.mid, lessThanOrEqualTo(po.mid + e), reason: '$t');
            expect(o.high, lessThanOrEqualTo(po.high + e), reason: '$t');
          }
          expect(i.low, greaterThanOrEqualTo(pi.low - e), reason: '$t');
          expect(i.mid, greaterThanOrEqualTo(pi.mid - e), reason: '$t');
          expect(i.high, greaterThanOrEqualTo(pi.high - e), reason: '$t');
          expect(o.highpass, greaterThanOrEqualTo(po.highpass - e));
          expect(i.lowpass, greaterThanOrEqualTo(pi.lowpass - e));
          expect(o.echo, greaterThanOrEqualTo(po.echo - e));
        }
        po = o;
        pi = i;
        // Una sola cassa per volta: mai due bassi pieni insieme. Tranne la
        // dissolvenza, che si sceglie proprio quando uno dei due non ha
        // batteria.
        if (name != 'fade' && o.volume > 0.1 && i.volume > 0.1) {
          expect(
            math.min(o.low, i.low) + 0.0,
            lessThanOrEqualTo(-12),
            reason: '$name a $t',
          );
        }
        // E insieme, coi tagli e i filtri, mai piu' di un brano solo.
        for (final cut in [0.0, 3.0, 6.0]) {
          final g = mixGains(
            o.volume,
            i.volume,
            outCutDb: cut,
            outShape: o,
            inShape: i,
          );
          expect(g.out, lessThanOrEqualTo(1 + 1e-9));
          expect(g.inc, lessThanOrEqualTo(1 + 1e-9));
          final eo = g.out * bandEnergy(o), ei = g.inc * bandEnergy(i);
          expect(eo * eo + ei * ei, lessThanOrEqualTo(1 + 1e-9), reason: '$t');
        }
      }
    });
  }

  group('curve dai DJ', () {
    // A che punto del mix un'ampiezza passa una soglia, a passi di un
    // millesimo.
    double when(double Function(double t) f, bool Function(double) hit) {
      for (var k = 0; k <= 1000; k++) {
        if (hit(f(k / 1000))) return k / 1000;
      }
      return double.infinity;
    }

    double outAmp(int band, double t) =>
        bandAmps(learnedStage(t, incoming: false))[band];
    double inAmp(int band, double t) =>
        bandAmps(learnedStage(t, incoming: true))[band];
    const half = 0.5; // -6 dB in ampiezza

    test('i tempi mediani di DJtransGAN', () {
      // L'uscente: bassi a -6 dB a 0,41, medi pieni fino a 0,73, acuti a
      // -6 dB a 0,70 e ancora li' quando i medi sono spariti.
      expect(when((t) => outAmp(0, t), (a) => a <= half), closeTo(0.41, 0.01));
      expect(learnedStage(0.73, incoming: false).volume, 1);
      expect(learnedStage(0.73, incoming: false).mid, 0);
      expect(when((t) => outAmp(2, t), (a) => a <= half), closeTo(0.70, 0.01));
      final tail = learnedStage(0.95, incoming: false);
      expect(tail.high, 0);
      expect(tail.mid, midCutDb);
      // L'entrante: prima gli acuti (-6 dB a 0,38, pieni a 0,60), coi bassi
      // e i medi al taglio; poi medi e bassi insieme (-6 dB a 0,69 e 0,76).
      expect(when((t) => inAmp(2, t), (a) => a >= half), closeTo(0.375, 0.01));
      final early = learnedStage(0.6, incoming: true);
      expect(early.volume, 1);
      expect(early.high, 0);
      expect(early.low, lowCutDb);
      expect(early.mid, midCutDb);
      expect(when((t) => inAmp(1, t), (a) => a >= half), closeTo(0.685, 0.01));
      expect(when((t) => inAmp(0, t), (a) => a >= half), closeTo(0.76, 0.01));
    });

    test('il volume e\' la banda piu\' alta, le altre sotto', () {
      for (var k = 0; k <= 200; k++) {
        for (final incoming in [false, true]) {
          final s = learnedStage(k / 200, incoming: incoming);
          if (s.volume == 0) continue;
          expect(math.max(s.low, math.max(s.mid, s.high)), 0, reason: '$k');
          expect(s.low, greaterThanOrEqualTo(lowCutDb));
          expect(s.mid, greaterThanOrEqualTo(midCutDb));
          expect(s.high, greaterThanOrEqualTo(highCutDb));
        }
      }
    });

    test('una cassa per volta, ma senza buco nei bassi', () {
      // Il modello lascia la somma dei bassi a -13 dB a 0,62; qui mai sotto
      // -9, e le due casse non sono mai piene insieme: quando si
      // incrociano stanno a -12 dB o meno l'una.
      final floor = math.pow(10, -9 / 20).toDouble();
      var worst = double.infinity;
      for (var k = 0; k <= 1000; k++) {
        final t = k / 1000;
        final o = learnedStage(t, incoming: false);
        final i = learnedStage(t, incoming: true);
        final lo = bandAmps(o)[0], li = bandAmps(i)[0];
        expect(math.min(lo, li), lessThanOrEqualTo(0.25), reason: '$t');
        final g = mixGains(o.volume, i.volume, outShape: o, inShape: i);
        final heard =
            g.out * math.pow(10, o.low / 20) + g.inc * math.pow(10, i.low / 20);
        worst = math.min(worst, heard);
      }
      expect(worst, greaterThanOrEqualTo(floor));
      // E il buco c'e' davvero, nelle rampe del modello: 0,22 contro 0,10.
      double modelOut(double t) => 1 - ((t - 0.02) / 0.77).clamp(0.0, 1.0);
      double modelIn(double t) => ((t - 0.62) / 0.28).clamp(0.0, 1.0);
      expect(modelOut(0.62) + modelIn(0.62), lessThan(floor));
    });

    test('il rolling usa le curve dai DJ, e lo dice', () {
      final p = planBeatMix(
        out: sectionedGrid(sections: clubSong, key: const MusicalKey(9, true)),
        incoming: sectionedGrid(
          sections: clubSong,
          key: const MusicalKey(9, true),
          bpm: 122,
        ),
        vocalsEnd: 150,
      )!;
      expect(p.kind, MixKind.rolling);
      expect(p.reason, contains('curve dai DJ'));
      for (var k = 0; k <= 20; k++) {
        for (final incoming in [false, true]) {
          expect(
            p.stage(k / 20, incoming: incoming),
            learnedStage(k / 20, incoming: incoming),
          );
        }
      }
      // Il blend resta quello di sempre.
      final b = planBeatMix(out: grid(120), incoming: grid(121))!;
      expect(b.kind, isNot(MixKind.rolling));
      expect(
        b.stage(0.5, incoming: true),
        isNot(learnedStage(0.5, incoming: true)),
      );
    });
  });

  test('cambio sul drop: i bassi si scambiano sull 1, in un battito', () {
    const at = 0.8, w = 0.025;
    final before = at - w, after = at + w;
    expect(
      dropSwapStage(before, incoming: true, swapAt: at, swapWidth: w).low,
      lowCutDb,
    );
    expect(
      dropSwapStage(before, incoming: false, swapAt: at, swapWidth: w).low,
      0,
    );
    expect(
      dropSwapStage(after, incoming: true, swapAt: at, swapWidth: w).low,
      0,
    );
    expect(
      dropSwapStage(after, incoming: false, swapAt: at, swapWidth: w).low,
      lowCutDb,
    );
    // Fino al drop l'uscente suona pieno.
    expect(
      dropSwapStage(before, incoming: false, swapAt: at, swapWidth: w).volume,
      1,
    );
  });

  test('salita col filtro: il passa-alto sale, il passa-basso si apre', () {
    expect(
      filterBuildStage(0, incoming: true).lowpass,
      closeTo(buildLowpassFrom, 1e-9),
    );
    expect(
      filterBuildStage(0.9, incoming: true).lowpass,
      closeTo(lowpassOpen, 1e-6),
    );
    expect(
      filterBuildStage(0.85, incoming: false).highpass,
      closeTo(buildHighpassTop, 1e-6),
    );
    // A meta' strada l'uscente e' gia' senza bassi e l'entrante ancora
    // chiuso: le due bande non si toccano.
    final o = filterBuildStage(0.5, incoming: false);
    final i = filterBuildStage(0.5, incoming: true);
    expect(o.highpass, greaterThan(150));
    expect(i.lowpass, lessThan(3000));
    // E l'eco arriva prima che l'uscente sparisca.
    expect(filterBuildStage(0.8, incoming: false).echo, closeTo(1, 1e-9));
    expect(filterBuildStage(0.8, incoming: false).volume, greaterThan(0.5));
  });

  test('i filtri: spenti col mix a zero, accesi piano', () {
    expect(highpassSetting(0), (f: highpassOff, mix: 0.0));
    expect(highpassSetting(highpassOff).mix, 0);
    expect(highpassSetting(30).mix, inExclusiveRange(0, 1));
    expect(highpassSetting(40).mix, 1);
    expect(highpassSetting(800), (f: 800.0, mix: 1.0));
    expect(lowpassSetting(lowpassOpen).mix, 0);
    expect(lowpassSetting(20000).mix, 0);
    expect(lowpassSetting(300), (f: 300.0, mix: 1.0));
    expect(lowpassSetting(8000).mix, 1);
    final top = lowpassSetting(14000);
    expect(top.mix, inExclusiveRange(0, 1));
    // Mai oltre 12 kHz: un brano a 32 kHz non regge un filtro sopra la
    // meta' della sua frequenza di campionamento.
    expect(top.f, 12000);
    // L'energia che resta: un passa-alto a 2,5 kHz toglie quasi tutto, un
    // passa-basso a 300 Hz lascia i bassi.
    expect(bandEnergy(MixStage.flat), closeTo(1, 1e-9));
    expect(
      bandEnergy(const MixStage(volume: 1, highpass: 2500)),
      lessThan(0.5),
    );
    expect(bandEnergy(const MixStage(volume: 1, lowpass: 300)), lessThan(0.8));
    expect(
      bandEnergy(const MixStage(volume: 1, lowpass: 300)),
      greaterThan(0.6),
    );
  });

  test('la catena dei filtri: neutra fuori dai mix, coi valori durante', () {
    expect(mixFilterChain(MixStage.flat), [
      '@lo:lavfi=[bass=f=120:g=0.0]',
      '@mid:lavfi=[equalizer=f=1000:t=o:w=2:g=0.0]',
      '@hi:lavfi=[treble=f=5000:g=0.0]',
      '@hp:lavfi=[highpass=f=20:mix=0.000]',
      '@lp:lavfi=[lowpass=f=12000:mix=0.000]',
    ]);
    // La dissolvenza non tocca i filtri: la catena resta quella di sempre.
    expect(
      mixFilterChain(fadeStage(0.5, incoming: true)),
      mixFilterChain(MixStage.flat),
    );
    expect(
      mixFilterChain(
        const MixStage(volume: 0.5, low: -26, highpass: 800, lowpass: 300),
      ),
      [
        '@lo:lavfi=[bass=f=120:g=-26.0]',
        '@mid:lavfi=[equalizer=f=1000:t=o:w=2:g=0.0]',
        '@hi:lavfi=[treble=f=5000:g=0.0]',
        '@hp:lavfi=[highpass=f=800:mix=1.000]',
        '@lp:lavfi=[lowpass=f=300:mix=1.000]',
      ],
    );
  });

  test('i comandi: solo quello che cambia, la frequenza prima del mix', () {
    final flat = MixFilterState.of(MixStage.flat);
    expect(mixFilterCommands(flat, MixStage.flat).commands, isEmpty);
    expect(
      mixFilterCommands(
        flat,
        const MixStage(volume: 1, highpass: 800),
      ).commands,
      [
        ['af-command', 'hp', 'f', '800'],
        ['af-command', 'hp', 'mix', '1.000'],
      ],
    );
    // Il ritorno a neutro arriva esatto, anche da un passo piccolo.
    final near = MixFilterState.of(const MixStage(volume: 1, low: -0.1));
    expect(mixFilterCommands(near, MixStage.flat).commands, [
      ['af-command', 'lo', 'g', '0.0'],
    ]);
  });

  test('i comandi: una curva lenta arriva in fondo, a piccoli passi', () {
    // I bassi di un blend lungo: 26 dB in mille passi da 40 ms, un
    // quarantesimo di decibel per passo. Prima ogni passo si confrontava
    // col precedente, sotto la soglia, e non partiva mai niente.
    var applied = MixFilterState.of(MixStage.flat);
    var sent = 0;
    for (var k = 1; k <= 1000; k++) {
      final step = mixFilterCommands(
        applied,
        MixStage(volume: 1, low: lowCutDb * k / 1000, highpass: 20 + k * 1.0),
      );
      sent += step.commands.length;
      applied = step.applied;
    }
    expect(applied.low, closeTo(lowCutDb, 0.25));
    expect(applied.hpF, closeTo(1020, 1020 * 0.02));
    expect(applied.hpMix, 1);
    expect(sent, inInclusiveRange(150, 400));
  });

  const am = MusicalKey(9, true);

  test('rolling: si esce sull outro, il drop dell entrante cade alla fine', () {
    final out = sectionedGrid(sections: clubSong, key: am);
    final inc = sectionedGrid(sections: clubSong, key: am, bpm: 122);
    final p = planBeatMix(
      out: out,
      incoming: inc,
      vocalsEnd: 150,
      stems: true,
    )!;
    expect(p.kind, MixKind.rolling);
    expect(p.bars, 16);
    // L'outro comincia alla battuta 96, a 192,5 s.
    expect(p.outStart, closeTo(192.5, 1e-9));
    // L'intro dell'entrante dura sedici battute: parte dal suo primo
    // battere e il suo drop arriva esattamente quando il mix finisce.
    final drop = analyzePhrases(inc).introEnd!;
    expect(p.inStart + p.incomingSeconds(p.wallLength), closeTo(drop, 0.02));
    expect(p.reason, contains('outro calmo'));
    expect(p.notes, contains('confine di sezione'));
    expect(p.notes, contains('outro@192.5'));
  });

  test('rolling di trentadue battute quando outro e intro le hanno', () {
    const long = <FakeSection>[
      (bars: 32, level: -20, low: -30),
      (bars: 64, level: -10, low: -12),
      (bars: 32, level: -20, low: -30),
    ];
    final p = planBeatMix(
      out: sectionedGrid(sections: long, key: am, bpm: 128),
      incoming: sectionedGrid(sections: long, key: am, bpm: 128),
      vocalsEnd: 150,
    )!;
    expect(p.kind, MixKind.rolling);
    expect(p.bars, 32);
    expect(p.wallLength, lessThanOrEqualTo(64));
  });

  const pumping = <FakeSection>[
    (bars: 8, level: -18, low: -12),
    (bars: 40, level: -10, low: -12),
    (bars: 16, level: -16, low: -14),
    (bars: 48, level: -10, low: -12),
  ];
  const withDrop = <FakeSection>[
    (bars: 8, level: -15, low: -26),
    (bars: 40, level: -9, low: -11),
    (bars: 64, level: -10, low: -12),
  ];

  test('cambio sul drop: il drop cade sull 1 di una frase dell uscente', () {
    final out = sectionedGrid(sections: pumping, key: am);
    final inc = sectionedGrid(
      sections: withDrop,
      key: const MusicalKey(4, true),
    );
    final p = planBeatMix(
      out: out,
      incoming: inc,
      vocalsEnd: 150,
      stems: true,
    )!;
    expect(p.kind, MixKind.dropSwap);
    expect(p.bars, 10);
    expect(p.swapAt, closeTo(0.8, 1e-9));
    final outMap = analyzePhrases(out);
    // Lo scambio sull'uscente cade su una frase da 8...
    final swapOut = p.outStart + p.swapAt * p.length;
    expect(outMap.levelOf(swapOut), anyOf('frase da 8', 'confine di sezione'));
    expect(
      outMap.levelOf(p.outStart),
      anyOf('frase da 8', 'confine di sezione'),
    );
    // ...e sull'entrante proprio sul suo drop.
    final drop = analyzePhrases(inc).introEnd!;
    expect(
      p.inStart + p.incomingSeconds(p.swapAt * p.wallLength),
      closeTo(drop, 0.02),
    );
    // Mezzo battito per parte: lo scambio dura un battito.
    expect(p.swapWidth * p.length, closeTo(out.beatLength / 2, 1e-9));
  });

  test('tonalita che stridono: salita col filtro, eco a mezzo battito', () {
    final out = sectionedGrid(sections: pumping, key: am);
    final inc = sectionedGrid(
      sections: clubSong,
      key: const MusicalKey(3, false),
    );
    final p = planBeatMix(
      out: out,
      incoming: inc,
      vocalsEnd: 150,
      stems: true,
    )!;
    expect(p.kind, MixKind.filterBuild);
    expect(p.echoDelay, closeTo(out.beatLength / 2, 1e-9));
    // L'intro di sedici battute si salta a meta': il drop alla fine del mix.
    final drop = analyzePhrases(inc).introEnd!;
    expect(p.inStart + p.incomingSeconds(p.wallLength), closeTo(drop, 0.02));
    expect(p.stage(0.5, incoming: false).highpass, greaterThan(100));
    // L'uscente finisce con la musica, su una frase.
    expect(p.outStart + p.length, lessThanOrEqualTo(out.musicEnd + 1e-9));
    expect(analyzePhrases(out).levelOf(p.outStart), isNot('battuta'));
  });

  test('l uscita in eco ha l eco a tempo di tre quarti di battito', () {
    final p = planBeatMix(
      out: grid(120),
      incoming: grid(120),
      inVocalsStart: 3,
    )!;
    expect(p.kind, MixKind.echo);
    expect(p.echoDelay, closeTo(0.375, 1e-9));
    // Gli altri stili senza eco.
    expect(planBeatMix(out: grid(120), incoming: grid(124))!.echoDelay, isNull);
  });

  test('tempi che non si accordano e un finale che sfuma: dissolvenza', () {
    final out = sectionedGrid(sections: clubSong, key: am);
    final p = planBeatMix(
      out: out,
      incoming: sectionedGrid(sections: clubSong, bpm: 90),
      vocalsEnd: 150,
    )!;
    expect(p.kind, MixKind.fade);
    expect(p.matched, isFalse);
    expect(p.length, fadeLength);
    expect(p.echoBeat, isNull);
    expect(p.stems!.duckAt, double.infinity);
    // Il centro sull'inizio dell'outro, dopo la voce.
    expect(p.outStart + p.length / 2, closeTo(192.5, 1e-9));
    expect(p.reason, contains('sfumando'));
  });

  test('con le frasi il mix comincia sempre sull 1 di una frase', () {
    // Un brano che finisce pieno e a meta' di una frase da 8: si esce
    // prima, sulla frase, invece che dove la fine lascerebbe.
    const odd = <FakeSection>[
      (bars: 16, level: -18, low: -12),
      (bars: 85, level: -10, low: -12),
    ];
    final out = sectionedGrid(sections: odd);
    final m = analyzePhrases(out);
    for (final inc in [
      sectionedGrid(sections: clubSong),
      sectionedGrid(sections: withDrop),
      sectionedGrid(sections: pumping, bpm: 124),
    ]) {
      final p = planBeatMix(
        out: out,
        incoming: inc,
        vocalsEnd: 150,
        stems: true,
      )!;
      expect(m.levelOf(p.outStart), isNot('battuta'), reason: '${p.kind}');
      expect(p.outStart + p.length, lessThanOrEqualTo(out.musicEnd + 1e-9));
      expect(p.notes, contains('uscita'));
    }
  });

  // --- Correzione di tonalita' di un semitono ---

  group('spostamento di tonalita', () {
    // La ruota: La minore e' 8A.
    const bbm = MusicalKey(10, true); // 3A: stride con 8A
    const abm = MusicalKey(8, true); // 1A
    const cMaj = MusicalKey(0, false); // 8B, la relativa
    const em = MusicalKey(4, true); // 9A, accanto
    const dbMaj = MusicalKey(1, false); // 3B
    const fsm = MusicalKey(6, true); // 11A
    const ebm = MusicalKey(3, true); // 2A, il tritono sulla ruota

    test('trasposta: un semitono in su sono sette caselle avanti', () {
      expect(am.transposed(1).pitchClass, 10);
      expect(am.transposed(-1).pitchClass, 8);
      expect(cMaj.transposed(-1).pitchClass, 11);
      expect(identical(am.transposed(0), am), isTrue);
      for (var pc = 0; pc < 12; pc++) {
        for (final minor in [false, true]) {
          final k = MusicalKey(pc, minor, 0.4);
          expect(k.transposed(1).camelot, (k.camelot + 6) % 12 + 1);
          expect(k.transposed(-1).camelot, (k.camelot + 4) % 12 + 1);
          expect(k.transposed(1).confidence, 0.4);
        }
      }
    });

    test('quale spostamento per quale coppia', () {
      final table = <(MusicalKey?, MusicalKey?, double, int)>[
        // Gia' compatibili: mai spostare.
        (am, am, 1, 0),
        (am, cMaj, 1, 0),
        (am, em, 1, 0),
        // Stridono, e un semitono le porta sulla stessa casella...
        (am, bbm, 1, -1),
        (am, abm, 1, 1),
        // ...o sulla relativa.
        (am, dbMaj, 1, -1),
        // Nessun semitono ci arriva.
        (am, fsm, 1, 0),
        // Il tritono: tutti e due ci arrivano, a una casella. Vince quello
        // che chiede meno a scaletempo2: fermo, in su (l'etichetta va a
        // 0,944); rallentato per il mix, in giu' (quasi 1).
        (am, ebm, 1, 1),
        (am, ebm, 0.95, -1),
        (am, ebm, 1.05, 1),
        // Oltre il 12% di stiramento no: 1,08 / 0,944 fa 1,144.
        (am, bbm, 1.05, -1),
        (am, bbm, 1.08, 0),
        // Senza tonalita'.
        (null, bbm, 1, 0),
        (am, null, 1, 0),
      ];
      for (final (out, inc, speed, want) in table) {
        expect(
          keyShiftFor(out, inc, speed: speed),
          want,
          reason: '${out?.camelotName} > ${inc?.camelotName} a $speed',
        );
      }
    });

    test('fiducia bassa: niente spostamento', () {
      const unsure = MusicalKey(10, true, 0.06);
      const sure = MusicalKey(10, true, keyShiftMinConfidence);
      expect(keyShiftFor(am, unsure), 0);
      expect(keyShiftFor(const MusicalKey(9, true, 0.09), bbm), 0);
      expect(keyShiftFor(am, sure), -1);
      expect(keyShiftNote(am, unsure, 0), contains('fiducia bassa'));
      expect(keyShiftNote(am, bbm, -1), contains('-1 semitono'));
      expect(keyShiftNote(am, em, 0), contains('compatibili'));
      expect(keyShiftNote(am, bbm, 0, speed: 1.08), contains('12%'));
    });

    test('tono di 2^(1/12), tempo del mix intatto', () {
      expect(keyShiftRateFor(0), 48000);
      expect(keyShiftRateFor(1), 50854);
      expect(keyShiftRateFor(-1), 45306);
      expect(keyShiftRatio(0), 1);
      for (final s in [1, -1]) {
        final r = keyShiftRatio(s);
        expect(r, closeTo(math.pow(2, s / 12), 1e-5));
        // Meno di un centesimo di centesimo dal semitono esatto.
        expect(1200 * math.log(r) / math.ln2, closeTo(100.0 * s, 0.01));
        for (final tempo in [0.9, 0.983, 1.0, 1.02, 1.12]) {
          // Quello che si sente: la velocita' di mpv (scaletempo2) per il
          // rapporto dell'etichetta.
          expect(mpvSpeedFor(tempo, s) * r, closeTo(tempo, 1e-12));
        }
      }
      expect(mpvSpeedFor(1.02, 0), 1.02);
      const plan = BeatMixPlan(
        kind: MixKind.blend,
        outStart: 100,
        inStart: 1,
        bars: 16,
        length: 32,
        speed: 1.02,
        keyShift: 1,
      );
      expect(plan.mpvSpeed, closeTo(1.02 * 48000 / 50854, 1e-12));
      expect(plan.mpvSpeed * keyShiftRatio(1), closeTo(plan.speed, 1e-12));
      // La posizione attesa dell'entrante si conta col tempo, non con mpv.
      expect(plan.incomingSeconds(10), closeTo(10.2, 1e-12));
    });

    test('catena: senza spostamento identica a prima', () {
      const eq = '@eq:lavfi=[equalizer=f=60:t=o:w=1:g=2]';
      expect(keyShiftChain(0), isEmpty);
      expect(
        playerFilterChain(automix: true),
        mixFilterChain(MixStage.flat).join(','),
      );
      expect(
        playerFilterChain(automix: true, eq: eq),
        [...mixFilterChain(MixStage.flat), eq].join(','),
      );
      expect(playerFilterChain(automix: false), '');
      expect(playerFilterChain(automix: false, eq: eq), eq);
      const stage = MixStage(volume: 0.5, low: -12, highpass: 300);
      expect(
        playerFilterChain(automix: true, stage: stage),
        mixFilterChain(stage).join(','),
      );
    });

    test('catena: l etichetta in testa, e resta anche senza AutoMix', () {
      const head =
          '@key:format=srate=48000:out-srate=50854,'
          '@keyrs:format=srate=48000';
      expect(keyShiftChain(1).join(','), head);
      expect(
        keyShiftChain(-1).first,
        '@key:format=srate=48000:out-srate=45306',
      );
      expect(
        playerFilterChain(automix: true, keyShift: 1),
        '$head,${mixFilterChain(MixStage.flat).join(',')}',
      );
      expect(playerFilterChain(automix: false, keyShift: 1), head);
    });

    test('il piano sposta l entrante e lo stile lo sa', () {
      final out = sectionedGrid(sections: pumping, key: am);
      final inc = sectionedGrid(sections: clubSong, key: bbm);
      final p = planBeatMix(
        out: out,
        incoming: inc,
        vocalsEnd: 150,
        stems: true,
      )!;
      expect(p.keyShift, -1);
      expect(p.matched, isTrue);
      // Accordate dallo spostamento: niente salita col filtro per le
      // tonalita'.
      expect(p.reason, isNot(contains("tonalita' che stridono")));
      expect(p.keyNote, contains('-1 semitono'));
      final line = describeBeatMix(
        p,
        from: 'Uno',
        to: 'Due',
        out: out,
        incoming: inc,
      );
      expect(line, startsWith('mix: piano Uno > Due: '));
      expect(line, contains('spostamento -1 semitoni'));
      expect(line, contains('(mpv ${p.mpvSpeed.toStringAsFixed(3)})'));
      expect(line, contains('8A > 3A'));

      // Lo stesso entrante con una stima incerta: com'era, filtro.
      final unsure = planBeatMix(
        out: out,
        incoming: sectionedGrid(
          sections: clubSong,
          key: const MusicalKey(10, true, 0.06),
        ),
        vocalsEnd: 150,
        stems: true,
      )!;
      expect(unsure.keyShift, 0);
      expect(unsure.kind, MixKind.filterBuild);
      expect(unsure.reason, contains("tonalita' che stridono"));
      expect(unsure.keyNote, contains('fiducia bassa'));
    });

    test('blend lungo dopo lo spostamento, e lo dice', () {
      final p = planBeatMix(
        out: sectionedGrid(sections: clubSong, key: am),
        incoming: sectionedGrid(sections: clubSong, key: bbm, bpm: 122),
        vocalsEnd: 150,
        stems: true,
      )!;
      expect(p.keyShift, -1);
      expect(p.kind, MixKind.rolling);
      expect(p.reason, contains('spostato di -1 semitono'));
      // Tempo del mix: quello di sempre. mpv va piu' svelto del 5,9%.
      expect(p.speed, closeTo(120 / 122, 1e-9));
      expect(p.mpvSpeed, closeTo(120 / 122 * 48000 / 45306, 1e-9));
    });

    test('gia compatibili o senza battiti: nessuno spostamento', () {
      final p = planBeatMix(out: grid(120), incoming: grid(124))!;
      expect(p.keyShift, 0);
      final line = describeBeatMix(
        p,
        from: 'a',
        to: 'b',
        out: grid(120),
        incoming: grid(124),
      );
      expect(line, contains('spostamento 0 semitoni'));
      expect(line, isNot(contains('(mpv')));
      // Tempi che non si accordano: il piano senza tempo non sposta.
      final cut = planBeatMix(
        out: sectionedGrid(sections: clubSong, key: am),
        incoming: sectionedGrid(sections: clubSong, key: bbm, bpm: 90),
        vocalsEnd: 150,
      )!;
      expect(cut.matched, isFalse);
      expect(cut.keyShift, 0);
    });

    test('l uscente gia spostato conta col tono che si sente', () {
      final out = sectionedGrid(sections: pumping, key: am);
      final inc = sectionedGrid(sections: clubSong, key: bbm);
      // La minore portata su di un semitono e' Si bemolle minore: con
      // l'entrante in Si bemolle minore non c'e' piu' niente da spostare.
      final p = planBeatMix(
        out: out,
        incoming: inc,
        vocalsEnd: 150,
        stems: true,
        outKeyShift: 1,
      )!;
      expect(p.keyShift, 0);
      expect(p.keyNote, contains('compatibili'));
    });
  });
}
