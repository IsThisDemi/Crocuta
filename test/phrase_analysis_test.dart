import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/beat_analysis.dart';
import 'package:yeen_music/services/phrase_analysis.dart';

import 'sectioned_grid.dart';

/// Battute finte a una feature: [levels] per ogni gruppo di [every]
/// battute, in fila.
List<List<double>> steps(List<double> levels, {int every = 16}) => [
  for (final l in levels)
    for (var i = 0; i < every; i++) [l],
];

void main() {
  test('i confini cadono dove l energia cambia, ogni 16 battute', () {
    final bars = steps([-10, -20, -10, -20]);
    final novelty = footeNovelty(bars);
    expect(pickBoundaries(novelty), [16, 32, 48]);
    // Dentro una sezione la novelty e' zero: il brano continua com'era.
    expect(novelty[8], closeTo(0, 1e-9));
    expect(novelty[16], greaterThan(1));
  });

  test('un brano piatto non ha sezioni, anche col respiro di mezzo dB', () {
    final bars = [
      for (var i = 0; i < 64; i++) [-10.0 + (i % 3 == 0 ? 0.5 : 0)],
    ];
    expect(pickBoundaries(footeNovelty(bars)), isEmpty);
  });

  test('i confini si portano sull 1 della frase da 8', () {
    // Trovati una o due battute in la': tornano sulla frase.
    expect(snapBoundaries([15, 34, 47], offset: 0, bars: 64), [0, 16, 32, 48]);
    // Troppo lontani dalla frase da 8 (tre battute), ma a una dalla frase
    // da 4: li'.
    expect(snapBoundaries([21], offset: 0, bars: 64), [0, 20]);
    // Due confini a meno di quattro battute: resta il primo.
    expect(snapBoundaries([16, 18], offset: 0, bars: 64), [0, 16]);
  });

  test(
    'lo sfasamento delle frasi lo decidono i confini, lo zero e favorito',
    () {
      final novelty = List<double>.filled(80, 0);
      for (final p in [18, 34, 50, 66]) {
        novelty[p] = 2;
      }
      // Quattro confini d'accordo su due battute di pick-up: frasi spostate.
      expect(phraseOffset([18, 34, 50, 66], novelty), 2);
      // Uno solo non sposta il conto dal primo battere.
      expect(phraseOffset([50], novelty), 0);
      expect(phraseOffset([], novelty), 0);
    },
  );

  test('sezioni: intro, brano, break, brano, outro', () {
    final kinds = labelSections(
      [-20, -10, -18, -10, -20],
      [-30, -12, -28, -12, -30],
      typical: -10,
      typicalLow: -12,
      starts: [0, 16 / 112, 48 / 112, 64 / 112, 96 / 112],
      ends: [16 / 112, 48 / 112, 64 / 112, 96 / 112, 1],
    );
    expect(kinds, [
      SectionKind.intro,
      SectionKind.body,
      SectionKind.breakdown,
      SectionKind.body,
      SectionKind.outro,
    ]);
    // Un brano che comincia e finisce pieno: niente intro ne' outro.
    expect(
      labelSections(
        [-10, -18, -10],
        [-12, -12, -12],
        typical: -10,
        typicalLow: -12,
        starts: [0, 0.4, 0.6],
        ends: [0.4, 0.6, 1],
      ),
      [SectionKind.body, SectionKind.breakdown, SectionKind.body],
    );
    // Stesso volume, ma senza cassa: e' un break lo stesso.
    expect(
      labelSections(
        [-10, -10, -10],
        [-12, -24, -12],
        typical: -10,
        typicalLow: -12,
        starts: [0, 0.4, 0.6],
        ends: [0.4, 0.6, 1],
      )[1],
      SectionKind.breakdown,
    );
  });

  test('un brano intero: frasi, sezioni, fine dell intro e outro', () {
    final g = sectionedGrid(sections: clubSong);
    final m = analyzePhrases(g);
    expect(m.phrased, isTrue);
    expect(m.offset, 0);
    expect(m.boundaryBars, [0, 16, 48, 64, 96]);
    expect(m.sections.map((s) => s.kind), [
      SectionKind.intro,
      SectionKind.body,
      SectionKind.breakdown,
      SectionKind.body,
      SectionKind.outro,
    ]);
    // In secondi: battute da due secondi dal primo battere, a 0,5.
    expect(m.introEnd, closeTo(32.5, 1e-9));
    expect(m.outroStart, closeTo(192.5, 1e-9));
    expect(m.sections[1].isDrop, isTrue);
    expect(m.introRise, greaterThanOrEqualTo(dropRiseDb));
    expect(m.describe(), contains('outro@192.5'));
  });

  test('i punti di frase: vicino, avanti, indietro', () {
    final m = analyzePhrases(sectionedGrid(sections: clubSong));
    bool any(double _) => true;
    // A una battuta da un confine trovato: il confine.
    expect(m.nearest(34.5, ok: any), closeTo(32.5, 1e-9));
    // Fra due confini, su una frase da 8 (battuta 24 = 48,5 s).
    expect(m.nearest(50.5, ok: any), closeTo(48.5, 1e-9));
    expect(m.levelOf(48.5), 'frase da 8');
    expect(m.levelOf(32.5), 'confine di sezione');
    // Se il vicino non va bene, nessuno entro il raggio.
    expect(m.nearest(50.5, ok: (p) => p > 60), isNull);
    expect(m.atOrAfter(33), closeTo(48.5, 1e-9));
    // Indietro: entro quattro battute c'e' solo la frase da 4 (battuta
    // 20); entro otto, il confine della battuta 16.
    expect(m.atOrBefore(47), closeTo(40.5, 1e-9));
    expect(m.atOrBefore(47, reach: 8), closeTo(32.5, 1e-9));
  });

  test('senza feature, niente frasi: il mix resta quello di prima', () {
    const g = BeatGrid(
      bpm: 120,
      firstBeat: 0.5,
      downbeat: 0,
      musicStart: 0.4,
      musicEnd: 200,
      confidence: 0.9,
      energy: [-10, -10, -10],
    );
    final m = analyzePhrases(g);
    expect(m.phrased, isFalse);
    expect(m.nearest(100, ok: (_) => true), isNull);
    expect(m.introEnd, isNull);
    expect(m.outroStart, isNull);
  });

  test('le feature vanno e tornano dal json, a mezzo decibel', () {
    final g = sectionedGrid(sections: clubSong);
    final back = BeatGrid.fromJson(g.toJson());
    expect(back.features.length, g.features.length);
    for (var i = 0; i < g.features.length; i++) {
      expect(back.features[i], closeTo(g.features[i], 0.25));
    }
    expect(back.version, beatGridVersion);
    expect(back.outro.features, same(back.features));
  });
}
