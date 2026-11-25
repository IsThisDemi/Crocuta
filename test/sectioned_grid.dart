import 'package:yeen_music/services/beat_analysis.dart';
import 'package:yeen_music/services/key_analysis.dart';

/// Una sezione di un brano finto: quante battute, il volume e i bassi.
typedef FakeSection = ({int bars, double level, double low});

/// Un brano finto fatto di sezioni, con le feature e il volume che
/// l'analisi vera gli darebbe: a ogni sezione bassi, medi e acuti fissi, e
/// in mezzo nient'altro. Il primo battere cade a [firstBeat], la musica
/// comincia un decimo prima e finisce con l'ultima battuta.
BeatGrid sectionedGrid({
  required List<FakeSection> sections,
  double bpm = 120,
  double firstBeat = 0.5,
  double confidence = 0.9,
  MusicalKey? key,
}) {
  final bar = 4 * 60 / bpm;
  final total = sections.fold<int>(0, (a, s) => a + s.bars);
  final end = firstBeat + total * bar;
  FakeSection at(double t) {
    var k = ((t - firstBeat) / bar).floor();
    if (k < 0) k = 0;
    for (final s in sections) {
      if (k < s.bars) return s;
      k -= s.bars;
    }
    return sections.last;
  }

  final frames = (end * BeatGrid.featureRate).floor();
  return BeatGrid(
    bpm: bpm,
    firstBeat: firstBeat,
    downbeat: 0,
    musicStart: firstBeat - 0.1,
    musicEnd: end,
    confidence: confidence,
    key: key,
    energy: [for (var s = 0; s < end.floor(); s++) at(s + 0.5).level],
    features: [
      for (var f = 0; f < frames; f++)
        ...() {
          final s = at((f + 0.5) / BeatGrid.featureRate);
          return [s.low, s.level, s.level - 6, s.level / 4];
        }(),
    ],
    version: beatGridVersion,
  );
}

/// Le sezioni di un brano da club: intro senza cassa, corpo, break, corpo,
/// outro senza cassa.
const List<FakeSection> clubSong = [
  (bars: 16, level: -20, low: -30),
  (bars: 32, level: -10, low: -12),
  (bars: 16, level: -18, low: -28),
  (bars: 32, level: -10, low: -12),
  (bars: 16, level: -20, low: -30),
];
