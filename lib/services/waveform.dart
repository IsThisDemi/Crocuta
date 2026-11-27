import 'dart:math' as math;

import 'beat_analysis.dart';

/// Quanti valori al secondo ha l'onda di [waveformOf].
const double waveformRate = 8;

/// L'onda di un brano per la barra di avanzamento: [waveformRate] valori al
/// secondo, 0-1, dall'inizio alla fine.
///
/// Il volume medio non serve: nei brani di oggi, compressi, fra medio e
/// forte ci sono 2-5 dB, e l'onda usciva tutta alla stessa altezza. Quello
/// che cambia davvero sono i bassi, che spariscono negli stacchi e nelle
/// strofe vuote: le sezioni si leggono da loro (pesati piu' di medi e
/// acuti, e misurati fra il punto piu' piano e il piu' forte del brano).
/// Dentro ogni sezione, se c'e' l'inviluppo a 30 al secondo
/// ([BeatGrid.envelope]), i colpi di quell'istante: la cassa che batte o
/// no, gli attacchi di rullante e charleston. Viene dall'analisi di
/// AutoMix; vuota per le analisi senza feature.
List<double> waveformOf(BeatGrid grid, {List<double>? envelope}) {
  final b = bandsOf(grid);
  if (b == null) return const [];
  final n = b.low.length;
  final duration = n / BeatGrid.featureRate;
  // Le sezioni: bassi per sei decimi, medi e acuti per il resto, sul
  // mezzo secondo e mezzo attorno.
  final midHigh = _norm(
    [
      for (var i = 0; i < n; i++)
        _sumDb(
          grid.features[i * BeatGrid.featureDims + 1],
          grid.features[i * BeatGrid.featureDims + 2],
        ),
    ],
    0.15,
    0.95,
    1,
  );
  final lowN = _norm(b.lowDb, 0.15, 0.95, 1);
  final count = (duration * waveformRate).floor();
  final env = envelope;
  final hasEnv = env != null && env.length >= BeatGrid.envelopeDims * 30;
  List<double>? hits, air;
  if (hasEnv) {
    const dims = BeatGrid.envelopeDims;
    final m = env.length ~/ dims;
    hits = _norm([for (var i = 0; i < m; i++) env[i * dims]], 0.1, 0.99, 1);
    air = _norm([for (var i = 0; i < m; i++) env[i * dims + 1]], 0.1, 0.99, 1);
  }
  return [
    for (var k = 0; k < count; k++)
      () {
        final c = (k + 0.5) / waveformRate;
        final base = math
            .pow(
              0.6 * _mean(lowN, BeatGrid.featureRate, c - 0.75, c + 0.75) +
                  0.4 *
                      _mean(midHigh, BeatGrid.featureRate, c - 0.75, c + 0.75),
              1.8,
            )
            .toDouble();
        if (hits == null || air == null) return base;
        const rate = BeatGrid.envelopeRate;
        final local = math.max(1e-6, _max(hits, rate, c - 0.75, c + 0.75));
        final tex = _at(hits, rate, c) / local;
        return (base * (0.45 + 0.4 * tex + 0.15 * _at(air, rate, c))).clamp(
          0.0,
          1.0,
        );
      }(),
  ];
}

/// Bassi, medi e acuti del brano nel tempo, 0-1, a
/// [BeatGrid.featureRate] valori al secondo: per la barra durante il mix,
/// dove ognuno si alza e si abbassa come lo lascia passare AutoMix.
({List<double> low, List<double> mid, List<double> high, List<double> lowDb})?
bandsOf(BeatGrid grid) {
  const dims = BeatGrid.featureDims;
  final f = grid.features;
  final n = f.length ~/ dims;
  if (n < 4) return null;
  List<double> band(int k) => [for (var i = 0; i < n; i++) f[i * dims + k]];
  final low = band(0);
  return (
    low: _norm(low, 0.15, 0.95, 1.7),
    mid: _norm(band(1), 0.15, 0.95, 1.7),
    high: _norm(band(2), 0.15, 0.95, 1.7),
    lowDb: low,
  );
}

double _sumDb(double a, double b) =>
    10 *
    math.log(math.pow(10, a / 10) + math.pow(10, b / 10) + 1e-12) /
    math.ln10;

double _pct(List<double> v, double q) {
  final s = [...v]..sort();
  return s[((s.length - 1) * q).round()];
}

/// [v] (in dB) fra il suo [lo]-esimo e il suo [hi]-esimo percentile, a
/// 0-1, con la curva [gamma] che allarga le differenze in alto. Almeno 6
/// dB di scarto: in una banda quasi ferma mezzo dB di rumore diventerebbe
/// un'onda a tutta altezza.
List<double> _norm(List<double> v, double lo, double hi, double gamma) {
  if (v.isEmpty) return const [];
  final b = _pct(v, hi);
  // Ancorato in alto: in un brano tutto uguale le parti forti restano
  // alte, non scendono a meta'.
  final a = math.min(_pct(v, lo), b - 6.0);
  final span = b - a;
  return [
    for (final x in v)
      math.pow(((x - a) / span).clamp(0.0, 1.0), gamma).toDouble(),
  ];
}

double _at(List<double> v, double rate, double sec) {
  final x = (sec * rate).clamp(0.0, v.length - 1.0);
  final i = x.floor();
  final j = math.min(i + 1, v.length - 1);
  return v[i] + (v[j] - v[i]) * (x - i);
}

(int, int) _span(int n, double rate, double a, double b) {
  final i0 = (a * rate).floor().clamp(0, n - 1);
  final i1 = math.max(i0 + 1, (b * rate).ceil()).clamp(1, n);
  return (i0, i1);
}

double _mean(List<double> v, double rate, double a, double b) {
  final (i0, i1) = _span(v.length, rate, a, b);
  var s = 0.0;
  for (var i = i0; i < i1; i++) {
    s += v[i];
  }
  return s / (i1 - i0);
}

double _max(List<double> v, double rate, double a, double b) {
  final (i0, i1) = _span(v.length, rate, a, b);
  var m = 0.0;
  for (var i = i0; i < i1; i++) {
    if (v[i] > m) m = v[i];
  }
  return m;
}
