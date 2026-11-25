import 'dart:math' as math;
import 'dart:typed_data';

/// I battiti con una rete neurale: Beat This! (Foscarin, Schlüter e
/// Widmer, ISMIR 2024, licenza MIT), il riferimento di oggi per battiti e
/// primi tempi di battuta in ogni genere.
///
/// Sostituisce il rilevatore classico di [analyzeBeats] per la griglia: su
/// quaranta brani della libreria quello azzeccava i battiti in dodici e le
/// battute in nove — tempi letti a 4/3 sulla trap con le terzine, fase
/// sfasata di mezzo battito, battere spostato di uno — e la sua fiducia non
/// lo diceva. Con la rete e una griglia locale: trentuno e ventotto, e
/// [LocalGrid.confidence] separa esattamente i buoni dagli altri.
///
/// Qui c'e' tutto tranne la rete, che sta dietro [BeatLogitsNet]: lo
/// spettrogramma com'e' in PyTorch, i blocchi da trenta secondi, i picchi,
/// la griglia.

/// La frequenza a cui la rete vuole l'audio.
const int beatNetRate = 22050;

/// Fotogrammi al secondo dello spettrogramma e delle uscite della rete.
const int beatNetFps = 50;

const int _nFft = 1024;
const int _hop = 441; // 22050 / 50
const int _mels = 128;

/// Quanti fotogrammi entrano nella rete per volta: trenta secondi, come in
/// addestramento. Fissi, perche' CoreML rifiuta una dimensione libera.
const int beatNetChunk = 1500;

/// Su iPhone quindici secondi: l'attenzione cresce col quadrato della
/// lunghezza, e un blocco da trenta chiede un gigabyte — col resto
/// dell'app, iOS la chiudeva per memoria. Da quindici il picco e' 515 MB e
/// i battiti coincidono con quelli da trenta al 94%.
const int beatNetChunkSmall = 750;

/// I fotogrammi scartati a ogni bordo di blocco: la rete li vede senza il
/// contesto da un lato, e in addestramento non contavano.
const int _border = 6;

/// La rete: da un blocco di spettrogramma, [frames] x 128, i logit di
/// battito e battere per fotogramma.
abstract class BeatLogitsNet {
  /// Quanti fotogrammi per blocco.
  int get frames => beatNetChunk;

  ({Float32List beat, Float32List downbeat}) run(Float32List spect);
}

/// Lo spettrogramma log-mel di Beat This!, com'e' nel suo `LogMelSpect`:
/// torchaudio `MelSpectrogram` a 22050 Hz, finestra di Hann da 1024,
/// passo 441, 128 bande mel "slaney" fra 30 Hz e 11 kHz, ampiezza
/// divisa per la radice di 1024, poi `log1p(1000 * x)`.
///
/// Fotogrammi in fila, 128 valori l'uno.
Float32List beatNetSpectrogram(Float32List mono) {
  final frames = 1 + mono.length ~/ _hop;
  final out = Float32List(frames * _mels);
  if (mono.isEmpty) return out;

  // Hann periodica, come torch.hann_window.
  final window = Float64List(_nFft);
  for (var i = 0; i < _nFft; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / _nFft);
  }
  // normalized="frame_length" vuol dire torch.stft(normalized=True): diviso
  // per la radice della lunghezza della finestra, non della sua energia.
  final norm = 1 / math.sqrt(_nFft);
  final bank = _MelBank.slaney();

  // center=True con riflessione ai bordi.
  const pad = _nFft ~/ 2;
  double sample(int i) {
    var j = i - pad;
    final n = mono.length;
    if (n == 1) return mono[0];
    while (j < 0 || j >= n) {
      if (j < 0) j = -j;
      if (j >= n) j = 2 * (n - 1) - j;
    }
    return mono[j];
  }

  final re = Float64List(_nFft);
  final im = Float64List(_nFft);
  final mag = Float64List(_nFft ~/ 2 + 1);
  for (var f = 0; f < frames; f++) {
    final start = f * _hop;
    for (var i = 0; i < _nFft; i++) {
      re[i] = sample(start + i) * window[i];
      im[i] = 0;
    }
    _fft(re, im);
    for (var k = 0; k < mag.length; k++) {
      mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]) * norm;
    }
    for (var m = 0; m < _mels; m++) {
      var sum = 0.0;
      final w = bank.weights[m];
      final lo = bank.from[m];
      for (var k = 0; k < w.length; k++) {
        sum += w[k] * mag[lo + k];
      }
      out[f * _mels + m] = _log1p(1000 * sum);
    }
  }
  return out;
}

double _log1p(double x) => x < 1e-4 ? x - x * x / 2 : math.log(1 + x);

/// Il banco di filtri mel di torchaudio (`melscale_fbanks`, scala
/// "slaney", senza normalizzazione): per ogni banda, i pesi non nulli e da
/// quale frequenza partono.
class _MelBank {
  final List<Float64List> weights;
  final List<int> from;

  _MelBank(this.weights, this.from);

  factory _MelBank.slaney() {
    const nFreqs = _nFft ~/ 2 + 1;
    const fMin = 30.0, fMax = 11000.0;
    const nyquist = beatNetRate ~/ 2; // torchaudio: sample_rate // 2
    const fSp = 200.0 / 3;
    const minLogHz = 1000.0;
    const minLogMel = minLogHz / fSp;
    final logStep = math.log(6.4) / 27;
    double toMel(double hz) => hz >= minLogHz
        ? minLogMel + math.log(hz / minLogHz) / logStep
        : hz / fSp;
    double toHz(double mel) => mel >= minLogMel
        ? minLogHz * math.exp(logStep * (mel - minLogMel))
        : fSp * mel;

    final mMin = toMel(fMin), mMax = toMel(fMax);
    final pts = [
      for (var i = 0; i < _mels + 2; i++)
        toHz(mMin + (mMax - mMin) * i / (_mels + 1)),
    ];
    final weights = <Float64List>[];
    final from = <int>[];
    for (var m = 0; m < _mels; m++) {
      final row = Float64List(nFreqs);
      var lo = -1, hi = -1;
      for (var k = 0; k < nFreqs; k++) {
        final f = nyquist * k / (nFreqs - 1);
        final down = (f - pts[m]) / (pts[m + 1] - pts[m]);
        final up = (pts[m + 2] - f) / (pts[m + 2] - pts[m + 1]);
        final v = math.max(0.0, math.min(down, up));
        row[k] = v;
        if (v > 0) {
          if (lo < 0) lo = k;
          hi = k;
        }
      }
      if (lo < 0) {
        weights.add(Float64List(0));
        from.add(0);
      } else {
        weights.add(Float64List.sublistView(row, lo, hi + 1));
        from.add(lo);
      }
    }
    return _MelBank(weights, from);
  }
}

/// Battiti e primi tempi di battuta di un brano, in secondi.
({List<double> beats, List<double> downbeats}) trackBeats(
  Float32List mono,
  BeatLogitsNet net,
) {
  final spect = beatNetSpectrogram(mono);
  final frames = spect.length ~/ _mels;
  final (beat, down) = _predict(spect, frames, net);
  final beats = _peaks(beat);
  final downs = _peaks(down);
  // Il battere va sul battito piu' vicino, come nell'originale.
  final snapped = <double>{};
  for (final d in downs) {
    if (beats.isEmpty) break;
    var best = beats.first;
    for (final b in beats) {
      if ((b - d).abs() < (best - d).abs()) best = b;
    }
    snapped.add(best);
  }
  return (beats: beats, downbeats: snapped.toList()..sort());
}

/// La rete su tutto il brano, a blocchi che si sovrappongono di
/// [_border] fotogrammi, come `split_predict_aggregate` con "keep_first".
(Float32List, Float32List) _predict(
  Float32List spect,
  int frames,
  BeatLogitsNet net,
) {
  final n = net.frames;
  final beat = Float32List(frames)..fillRange(0, frames, -1000);
  final down = Float32List(frames)..fillRange(0, frames, -1000);
  final starts = <int>[
    for (var s = -_border; s < frames - _border; s += n - 2 * _border) s,
  ];
  if (frames > n - 2 * _border) {
    starts[starts.length - 1] = frames - (n - _border);
  }
  // Al contrario, cosi' i blocchi prima sovrascrivono quelli dopo.
  for (final start in starts.reversed) {
    final chunk = Float32List(n * _mels);
    for (var i = 0; i < n; i++) {
      final f = start + i;
      if (f < 0 || f >= frames) continue; // zeri: il bordo e la coda
      chunk.setRange(i * _mels, (i + 1) * _mels, spect, f * _mels);
    }
    final out = net.run(chunk);
    for (var i = _border; i < n - _border; i++) {
      final f = start + i;
      if (f < 0 || f >= frames) continue;
      beat[f] = out.beat[i];
      down[f] = out.downbeat[i];
    }
  }
  return (beat, down);
}

/// I picchi dei logit: massimi locali su sette fotogrammi e sopra zero
/// (probabilita' oltre meta'), con i vicini fusi nella loro media.
List<double> _peaks(Float32List logits) {
  final frames = <int>[];
  for (var i = 0; i < logits.length; i++) {
    final v = logits[i];
    if (v <= 0) continue;
    var isMax = true;
    for (
      var j = math.max(0, i - 3);
      j <= math.min(logits.length - 1, i + 3);
      j++
    ) {
      if (logits[j] > v) {
        isMax = false;
        break;
      }
    }
    if (isMax) frames.add(i);
  }
  final out = <double>[];
  var i = 0;
  while (i < frames.length) {
    var p = frames[i].toDouble();
    var prev = frames[i];
    var c = 1;
    var j = i + 1;
    while (j < frames.length && frames[j] - prev <= 1) {
      c++;
      p += (frames[j] - p) / c;
      prev = frames[j];
      j++;
    }
    out.add(p / beatNetFps);
    i = j;
  }
  return out;
}

/// Una griglia regolare adattata ai battiti di un tratto del brano.
class LocalGrid {
  final double bpm;

  /// Un battito della griglia; gli altri a multipli di 60/[bpm].
  final double firstBeat;

  /// Quale battito, contando da [firstBeat], apre la battuta (0-3).
  final int downbeat;

  /// Quanti battiti della rete la griglia prende, e quanti suoi battiti
  /// la rete conferma (F-measure a 70 ms), nel tratto: sopra 0,8 la
  /// griglia e' giusta, battute comprese, in 29 casi su 31 misurati.
  final double confidence;

  const LocalGrid(this.bpm, this.firstBeat, this.downbeat, this.confidence);
}

/// La griglia dei battiti fra [from] e [to] secondi.
///
/// Il periodo e' la mediana degli intervalli; ogni battito prende il suo
/// numero contando i salti uno a uno (un battito saltato vale due), cosi'
/// un periodo appena sbagliato non fa slittare la numerazione in fondo al
/// brano. Poi minimi quadrati sui battiti che la griglia spiega, ripetuti.
/// Il battere e' il voto dei primi tempi della rete, battuta per battuta.
LocalGrid? fitGrid(
  List<double> beats,
  List<double> downbeats, {
  double from = 0,
  double to = double.infinity,
}) {
  final b = [
    for (final t in beats)
      if (t >= from && t <= to) t,
  ];
  if (b.length < 16) return null;
  final gaps = [for (var i = 1; i < b.length; i++) b[i] - b[i - 1]]..sort();
  var period = gaps[gaps.length ~/ 2];
  if (period <= 0) return null;

  // Il periodo e la fase che fanno cadere piu' battiti sulla griglia, fra
  // i periodi entro il 3% della mediana. Nessun conteggio progressivo: un
  // battito falso a meta' periodo (le parti a tempo doppio, i rullanti
  // della trap) faceva avanzare la numerazione di uno, e da li' tutta la
  // griglia usciva sfasata — 77,7 BPM su un brano fermo a 76,9.
  double bestScore = -1, bestPhase = b.first;
  final base = period;
  for (var step = -60; step <= 60; step++) {
    final p = base * (1 + step * 0.0005);
    var sx = 0.0, sy = 0.0;
    for (final t in b) {
      final a = 2 * math.pi * (t % p) / p;
      sx += math.cos(a);
      sy += math.sin(a);
    }
    var ph = math.atan2(sy, sx) / (2 * math.pi) * p;
    if (ph < 0) ph += p;
    var score = 0;
    for (final t in b) {
      final d = ((t - ph) / p);
      if ((d - d.roundToDouble()).abs() * p <= 0.05) score++;
    }
    if (score > bestScore) {
      bestScore = score.toDouble();
      period = p;
      bestPhase = ph;
    }
  }
  final k = Float64List(b.length);
  final inlier = List<bool>.filled(b.length, true);
  for (var i = 0; i < b.length; i++) {
    final x = (b[i] - bestPhase) / period;
    k[i] = x.roundToDouble();
    inlier[i] = (x - k[i]).abs() * period <= 0.05;
  }
  var phase = bestPhase;
  for (var round = 0; round < 4; round++) {
    var n = 0.0, sk = 0.0, st = 0.0, skk = 0.0, skt = 0.0;
    for (var i = 0; i < b.length; i++) {
      if (!inlier[i]) continue;
      n++;
      sk += k[i];
      st += b[i];
      skk += k[i] * k[i];
      skt += k[i] * b[i];
    }
    final den = n * skk - sk * sk;
    if (n < 8 || den == 0) break;
    period = (n * skt - sk * st) / den;
    phase = (st - period * sk) / n;
    var kept = 0;
    for (var i = 0; i < b.length; i++) {
      inlier[i] = (b[i] - (phase + k[i] * period)).abs() < 0.08 * period;
      if (inlier[i]) kept++;
    }
    if (kept < 8) break;
  }
  if (period <= 0) return null;
  final first = phase - (phase / period).floor() * period;

  final votes = List<double>.filled(4, 0);
  for (final d in downbeats) {
    if (d < from || d > to) continue;
    final idx = ((d - first) / period).round();
    votes[idx % 4]++;
  }
  var down = 0;
  for (var i = 1; i < 4; i++) {
    if (votes[i] > votes[down]) down = i;
  }

  // Quanto la griglia e la rete sono d'accordo nel tratto.
  final lo = math.max(from, b.first - period / 2);
  final hi = math.min(to, b.last + period / 2);
  final grid = <double>[];
  for (
    var t = first + ((lo - first) / period).ceil() * period;
    t <= hi;
    t += period
  ) {
    grid.add(t);
  }
  final confidence = _fMeasure(grid, b, 0.07);
  return LocalGrid(60 / period, first, down, confidence);
}

/// F-measure fra due elenchi di istanti ordinati, con tolleranza [tol].
double _fMeasure(List<double> est, List<double> ref, double tol) {
  if (est.isEmpty || ref.isEmpty) return 0;
  var hits = 0;
  var j = 0;
  for (final r in ref) {
    while (j < est.length && est[j] < r - tol) {
      j++;
    }
    if (j < est.length && (est[j] - r).abs() <= tol) {
      hits++;
      j++;
    }
  }
  final p = hits / est.length, rc = hits / ref.length;
  return p + rc == 0 ? 0 : 2 * p * rc / (p + rc);
}

/// FFT radix-2 sul posto.
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang), wi = math.sin(ang);
    final half = len ~/ 2;
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var q = 0; q < half; q++) {
        final ur = re[i + q], ui = im[i + q];
        final xr = re[i + q + half], xi = im[i + q + half];
        final vr = xr * cr - xi * ci;
        final vi = xr * ci + xi * cr;
        re[i + q] = ur + vr;
        im[i + q] = ui + vi;
        re[i + q + half] = ur - vr;
        im[i + q + half] = ui - vi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}
