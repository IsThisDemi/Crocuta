import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/automix.dart';
import 'package:yeen_music/services/vocal_pause.dart';

/// Una voce che canta a -12 dB per [length] secondi, tranne nelle [gaps],
/// dove resta il filo della base a -45 dB.
VocalEnvelope _voice(double length, List<(double, double)> gaps) {
  final n = (length / vocalEnvelopeHop).round();
  return VocalEnvelope(
    Float32List.fromList([
      for (var k = 0; k < n; k++)
        gaps.any(
              (g) =>
                  k * vocalEnvelopeHop >= g.$1 - 1e-9 &&
                  k * vocalEnvelopeHop < g.$2 - 1e-9,
            )
            ? -45
            : -12,
    ]),
  );
}

/// Un blend di otto battute a 120 BPM: battito di mezzo secondo, battuta
/// di due, mix di sedici secondi.
BeatMixPlan _plan(StemPlan stems) => BeatMixPlan(
  kind: MixKind.blend,
  outStart: 100,
  inStart: 0.5,
  bars: 8,
  length: 16,
  speed: 1,
  stems: stems,
  outBeat: 0.5,
  inBeat: 0.5,
  reason: 'prova',
);

void main() {
  group('inviluppo e pause', () {
    test('il volume della voce, e la pausa dove tace', () {
      const rate = 1000;
      final n = 6 * rate;
      final v = Float32List.fromList([
        for (var i = 0; i < n; i++)
          i >= 4 * rate && i < 5 * rate ? 0.0 : (i.isEven ? 0.5 : -0.5),
      ]);
      // Dal secondo 1 del tratto: la pausa e' da 3 a 4 s del mix.
      final env = vocalEnvelope(v, v, from: 1, length: 5, rate: rate);
      expect(env.length, closeTo(5, 1e-9));
      expect(env.db.first, closeTo(-6.02, 0.01)); // RMS 0,5
      final gaps = vocalGaps(env, minLength: 0.5);
      expect(gaps, hasLength(1));
      expect(gaps.single.start, closeTo(3, 1e-9));
      expect(gaps.single.end, closeTo(4, 1e-9));
    });

    test('una pausa piu corta di un battito non conta', () {
      final env = _voice(8, [(2, 2.3), (5, 6)]);
      final gaps = vocalGaps(env, minLength: 0.5);
      expect(gaps, hasLength(1));
      expect(gaps.single.start, closeTo(5, 1e-9));
    });

    test('senza cantato tutto il tratto e una pausa', () {
      final env = VocalEnvelope(Float32List(400)..fillRange(0, 400, -70));
      expect(env.activeBetween(0, 8), isFalse);
      expect(vocalGaps(env, minLength: 0.5), hasLength(1));
    });
  });

  group('scelta della pausa', () {
    test('trovata: il battito dentro la pausa, piu vicino del suo inizio', () {
      final c = chooseVocalHandover(
        vocalGaps(_voice(16, [(10.2, 11)]), minLength: 0.5),
        planned: 12,
        earliest: 1.5,
        latest: 14,
        beat: 0.5,
      )!;
      // Dalle 10,2 alle 10,5 (lo spegnimento deve finire prima che il
      // cantante riprenda a 11): 10,5 e' un battito.
      expect(c.at, closeTo(10.5, 1e-9));
      expect(c.level, 1);
      expect(c.gapStart, closeTo(10.2, 1e-9));
    });

    test('nessuna pausa: niente', () {
      expect(
        chooseVocalHandover(
          vocalGaps(_voice(16, const []), minLength: 0.5),
          planned: 12,
          earliest: 1.5,
          latest: 14,
          beat: 0.5,
        ),
        isNull,
      );
    });

    test('preferisce la pausa su una battuta a una piu vicina a caso', () {
      // A, piu' vicina: 12,15-12,9, utile fino a 12,4, nessun battito.
      // B, piu' lontana: 13,95-14,6, con la battuta dei 14 s dentro.
      final gaps = vocalGaps(
        _voice(16, [(12.15, 12.9), (13.95, 14.6)]),
        minLength: 0.5,
      );
      final c = chooseVocalHandover(
        gaps,
        planned: 12.9,
        earliest: 1.5,
        latest: 15,
        beat: 0.5,
      )!;
      expect(c.at, closeTo(14, 1e-9));
      expect(c.level, 2);
      // L'"1" di una frase (16 battiti, 8 s) vale ancora di piu'.
      expect(handoverLevel(8, 0.5), 3);
      expect(handoverLevel(8.25, 0.5), 0);
    });

    test(
      'mai oltre il limite: la pausa dopo si ignora anche se piu vicina',
      () {
        final gaps = vocalGaps(
          _voice(16, [(4, 5), (12.2, 13)]),
          minLength: 0.5,
        );
        final c = chooseVocalHandover(
          gaps,
          planned: 12,
          earliest: 1.5,
          latest: 12,
          beat: 0.5,
        )!;
        // La pausa prima, sull'ultimo battito utile (fino a 4,5): il piu'
      // vicino a 12.
      expect(c.at, closeTo(4.5, 1e-9));
        expect(
          chooseVocalHandover(
            [gaps.last],
            planned: 12,
            earliest: 1.5,
            latest: 12,
            beat: 0.5,
          ),
          isNull,
        );
      },
    );
  });

  group('il piano', () {
    test('lo spegnimento a meta frase va nella pausa, sulla battuta', () {
      // Spegnimento previsto a 12,5 (comincia a 12): il cantante canta
      // fino a 9,8 e riprende a 10,9.
      final plan = _plan(const StemPlan(duckAt: 12.5));
      final r = placeVocalHandover(plan, _voice(16, [(9.8, 10.9)]));
      final st = r.plan.stems!;
      expect(st.handoverStart, closeTo(10, 1e-9));
      expect(st.duckAt, closeTo(10.5, 1e-9));
      expect(st.exchangeAt, isNull);
      // Il resto del piano non cambia.
      expect(r.plan.outStart, 100);
      expect(r.plan.length, 16);
      expect(r.plan.reason, 'prova');
      expect(r.note, contains('9.80-10.90'));
      expect(r.note, contains('su una battuta'));
    });

    test('il passaggio di voce puo scivolare in avanti, fino al limite', () {
      // Passaggio a 12 (spegnimento da 11,75), limite 14,25: la pausa
      // dopo, 12,9-13,8, va bene, e il battito dei 13 s ci cade dentro.
      final plan = _plan(
        const StemPlan(duckAt: 12.25, exchangeAt: 12, latestDuck: 14.25),
      );
      final r = placeVocalHandover(plan, _voice(16, [(12.9, 13.8)]));
      final st = r.plan.stems!;
      expect(st.handoverStart, closeTo(13, 1e-9));
      expect(st.exchangeAt, closeTo(13.25, 1e-9));
      expect(st.duckAt, closeTo(13.5, 1e-9));
      expect(st.latestDuck, 14.25);
      // Lo spegnimento senza passaggio invece non va mai dopo: l'entrante
      // canterebbe sopra.
      final duck = placeVocalHandover(
        _plan(const StemPlan(duckAt: 12.25)),
        _voice(16, [(12.9, 13.8)]),
      );
      expect(duck.plan.stems!.duckAt, 12.25);
      expect(duck.note, contains('resta'));
    });

    test('mai oltre la fine del mix', () {
      // La sola pausa e' nell'ultimo mezzo secondo: lo spegnimento
      // finirebbe dopo il mix.
      final plan = _plan(
        const StemPlan(duckAt: 15.3, exchangeAt: 15.05, latestDuck: 40),
      );
      final r = placeVocalHandover(plan, _voice(16, [(15.6, 16)]));
      expect(identical(r.plan, plan), isTrue);
      expect(r.note, contains("nessuna pausa"));
    });

    test('gia in una pausa, o senza pausa: il piano resta quello', () {
      final plan = _plan(const StemPlan(duckAt: 12.5));
      final quiet = placeVocalHandover(plan, _voice(16, [(11.8, 13)]));
      expect(identical(quiet.plan, plan), isTrue);
      expect(quiet.note, contains("gia' in una pausa"));
      final sung = placeVocalHandover(plan, _voice(16, const []));
      expect(identical(sung.plan, plan), isTrue);
      expect(sung.note, contains("a meta' frase"));
      // Con l'eco la frase e' gia' chiusa; senza spegnimento non c'e'
      // niente da spostare.
      final echo = _plan(
        const StemPlan(
          duckAt: 12.5,
          echoFrom: 4,
          echoLength: 2,
          echoRepeats: 2,
        ),
      );
      expect(
        identical(placeVocalHandover(echo, _voice(16, [])).plan, echo),
        isTrue,
      );
      final none = _plan(const StemPlan());
      expect(
        identical(placeVocalHandover(none, _voice(16, [])).plan, none),
        isTrue,
      );
    });
  });
}
