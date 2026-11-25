import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// La tonalita' di un brano: la nota di base (0 = do, 11 = si), maggiore o
/// minore, e quanto ci si puo' fidare della stima.
class MusicalKey {
  final int pitchClass;
  final bool minor;

  /// Di quanto la tonalita' scelta batte la seconda, 0-1. Sotto 0,05 la
  /// stima e' quasi un tiro di moneta: brani senza un centro chiaro, o
  /// parlati.
  final double confidence;

  const MusicalKey(this.pitchClass, this.minor, [this.confidence = 1]);

  static const _names = [
    'C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B', //
  ];

  String get name => '${_names[pitchClass]}${minor ? 'm' : ''}';

  /// Il numero sulla ruota di Camelot, quella dei DJ: tonalita' con numeri
  /// vicini, o con lo stesso numero, si mescolano senza stonare.
  int get camelot => minor
      ? const [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10][pitchClass]
      : const [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1][pitchClass];

  String get camelotName => '$camelot${minor ? 'A' : 'B'}';

  /// La stessa tonalita' spostata di [semitones] semitoni, con la stessa
  /// fiducia: e' quella che si sente quando AutoMix sposta un brano (vedi
  /// keyShiftFor). Un semitono in su sono sette caselle avanti sulla ruota,
  /// uno in giu' cinque.
  MusicalKey transposed(int semitones) => semitones == 0
      ? this
      : MusicalKey((pitchClass + semitones) % 12, minor, confidence);

  /// Quanto stona passare da questa tonalita' a [other], 0-1, sulla ruota:
  /// stessa casella 0, una accanto o la relativa (stesso numero, altra
  /// lettera) poco, piu' lontano sempre di piu'.
  double distanceTo(MusicalKey other) {
    final d = (camelot - other.camelot).abs();
    final steps = math.min(d, 12 - d) + (minor == other.minor ? 0 : 1);
    return switch (steps) {
      0 => 0,
      1 => 0.3,
      2 => 0.7,
      _ => 1,
    };
  }
}

/// I profili di Albrecht e Shanahan: quanto ciascuna delle dodici note
/// "appartiene" a una tonalita' maggiore o minore, misurato su un corpus di
/// musica. Provati sui brani della libreria contro le tonalita' pubblicate,
/// insieme a Krumhansl-Kessler, Temperley e quelli di KeyFinder: questi ne
/// azzeccano 5 su 7 (Krumhansl 2), e gli altri due li sbagliano di una
/// quinta, cioe' di una casella sulla ruota — per il riordino, quasi nulla.
const _majorProfile = [
  0.238, 0.006, 0.111, 0.006, 0.137, 0.094, 0.016, 0.214, 0.009, 0.080, //
  0.008, 0.081,
];
const _minorProfile = [
  0.220, 0.006, 0.104, 0.123, 0.019, 0.103, 0.012, 0.214, 0.062, 0.022, //
  0.061, 0.052,
];

const int _frame = 8192;

/// Stima la tonalita' da campioni mono a [rate] Hz.
///
/// Il metodo classico: per ogni finestra, quanta energia cade su ciascuna
/// delle dodici note (il cromagramma), sommata su tutto il brano e
/// confrontata con i profili delle 24 tonalita'. Ogni finestra pesa uguale,
/// cosi' il ritornello forte non conta piu' della strofa. Null su un brano
/// troppo corto o muto.
MusicalKey? estimateKey(Int16List samples, int rate) {
  final frames = samples.length ~/ _frame;
  if (frames < 8) return null;
  final fft = FFT(_frame);
  final window = Float64List(_frame);
  for (var i = 0; i < _frame; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_frame - 1));
  }
  // Da ogni banda alla sua nota, fra 100 Hz e 5 kHz: sotto c'e' soprattutto
  // la cassa, che confonde. Provato anche 65 Hz - 2 kHz: peggio.
  final pcOf = Int8List(_frame ~/ 2)..fillRange(0, _frame ~/ 2, -1);
  for (var k = 1; k < _frame ~/ 2; k++) {
    final f = k * rate / _frame;
    if (f < 100 || f > 5000) continue;
    final midi = 69 + 12 * math.log(f / 440) / math.ln2;
    pcOf[k] = midi.round() % 12;
  }

  final chroma = Float64List(12);
  final buf = Float64List(_frame);
  final frameChroma = Float64List(12);
  for (var t = 0; t < frames; t++) {
    final start = t * _frame;
    for (var i = 0; i < _frame; i++) {
      buf[i] = samples[start + i] / 32768 * window[i];
    }
    final bins = fft.realFft(buf);
    frameChroma.fillRange(0, 12, 0);
    var sum = 0.0;
    for (var k = 1; k < _frame ~/ 2; k++) {
      final pc = pcOf[k];
      if (pc < 0) continue;
      final z = bins[k];
      // L'energia e non l'ampiezza: le note che dominano contano di piu'
      // del tappeto di armonici fra una e l'altra.
      final m = z.x * z.x + z.y * z.y;
      frameChroma[pc] += m;
      sum += m;
    }
    // Le finestre quasi mute non dicono niente, e normalizzate
    // gonfierebbero il rumore.
    if (sum < 1e-3) continue;
    for (var pc = 0; pc < 12; pc++) {
      chroma[pc] += frameChroma[pc] / sum;
    }
  }
  if (chroma.every((c) => c == 0)) return null;

  var best = -2.0, second = -2.0;
  var bestPc = 0;
  var bestMinor = false;
  for (final minor in [false, true]) {
    final profile = minor ? _minorProfile : _majorProfile;
    for (var tonic = 0; tonic < 12; tonic++) {
      final r = _correlation(chroma, profile, tonic);
      if (r > best) {
        second = best;
        best = r;
        bestPc = tonic;
        bestMinor = minor;
      } else if (r > second) {
        second = r;
      }
    }
  }
  return MusicalKey(bestPc, bestMinor, (best - second).clamp(0.0, 1.0));
}

/// La correlazione di Pearson fra il cromagramma e il profilo spostato
/// sulla tonica [tonic].
double _correlation(Float64List chroma, List<double> profile, int tonic) {
  var mc = 0.0, mp = 0.0;
  for (var i = 0; i < 12; i++) {
    mc += chroma[i];
    mp += profile[i];
  }
  mc /= 12;
  mp /= 12;
  var num = 0.0, dc = 0.0, dp = 0.0;
  for (var i = 0; i < 12; i++) {
    final c = chroma[(i + tonic) % 12] - mc;
    final p = profile[i] - mp;
    num += c * p;
    dc += c * c;
    dp += p * p;
  }
  return dc == 0 || dp == 0 ? 0 : num / math.sqrt(dc * dp);
}
