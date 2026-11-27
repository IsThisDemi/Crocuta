import 'package:flutter_test/flutter_test.dart';
import 'package:yeen_music/services/automix.dart';
import 'package:yeen_music/services/beat_analysis.dart';
import 'package:yeen_music/services/mix_info.dart';
import 'package:yeen_music/services/waveform.dart';

/// Un brano compresso come quelli veri: medi e acuti quasi fermi, e i
/// bassi che spariscono in uno stacco a meta'.
BeatGrid _grid({bool breakdown = true}) {
  final f = <double>[];
  const n = 240; // due minuti
  for (var i = 0; i < n; i++) {
    final gap = breakdown && i >= 100 && i < 150;
    f
      ..add(gap ? -38 : -9 + (i % 3) * 0.5)
      ..add(-18 + (i % 2) * 0.5)
      ..add(-27 + (i % 4) * 0.3)
      ..add(18);
  }
  return BeatGrid(
    bpm: 90,
    firstBeat: 0,
    downbeat: 0,
    musicStart: 0,
    musicEnd: 120,
    confidence: 1,
    features: f,
  );
}

void main() {
  test(
    "l'onda si abbassa dove spariscono i bassi, anche a volume quasi fermo",
    () {
      final w = waveformOf(_grid());
      expect(w.length, 120 * waveformRate);
      final inside = w[(125 * waveformRate / 2).round()];
      final outside = w[(40 * waveformRate / 2).round()];
      expect(outside, greaterThan(0.3));
      expect(inside, lessThan(outside * 0.4));
    },
  );

  test("con l'inviluppo, i colpi di ogni istante cambiano le barrette", () {
    final env = <double>[];
    for (var i = 0; i < 120 * 30; i++) {
      // Una cassa ogni 20 fotogrammi, che decade in un terzo di secondo.
      env
        ..add(-6 - 2.5 * (i % 20))
        ..add(17.0 + (i % 7));
    }
    final plain = waveformOf(_grid(breakdown: false));
    final hits = waveformOf(_grid(breakdown: false), envelope: env);
    double spread(List<double> v) {
      final s = v.sublist(80, 400);
      return s.reduce((a, b) => a > b ? a : b) -
          s.reduce((a, b) => a < b ? a : b);
    }

    expect(spread(hits), greaterThan(spread(plain) + 0.1));
  });

  test('quanto si sentono le bande: filtri ed equalizzatore', () {
    expect(MixStage.flat.audible.low, closeTo(1, 1e-9));
    final hp = const MixStage(volume: 1, highpass: 300).audible;
    expect(hp.low, closeTo(0, 1e-9));
    expect(hp.mid, closeTo(1, 1e-9));
    final lp = const MixStage(volume: 1, lowpass: 2000).audible;
    expect(lp.high, closeTo(0, 1e-9));
    expect(lp.low, closeTo(1, 1e-9));
    final cut = const MixStage(volume: 1, low: lowCutDb).audible;
    expect(cut.low, lessThan(0.06));
    expect(const MixStage(volume: 0.5).audible.mid, closeTo(0.5, 1e-9));
  });
}
