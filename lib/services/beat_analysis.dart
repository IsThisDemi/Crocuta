import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'key_analysis.dart';

/// Com'e' fatto un brano nel tempo: dove cadono i battiti, dove comincia e
/// finisce la musica. E' quello che serve ad AutoMix per mixare a tempo.
class BeatGrid {
  /// Battiti al minuto.
  final double bpm;

  /// Il primo battito della griglia, in secondi. La griglia e' regolare:
  /// il battito n cade a [firstBeat] + n * [beatLength].
  final double firstBeat;

  /// Quale battito della battuta e' il primo (0-3), contando da
  /// [firstBeat]: dove la cassa e' piu' forte.
  final int downbeat;

  /// Dove comincia e finisce il suono, in secondi: il silenzio prima e
  /// dopo non si ascolta, si salta.
  final double musicStart;
  final double musicEnd;

  /// Quanto ci si puo' fidare della griglia, 0-1. Sotto una soglia non si
  /// fa beatmatching: un battito sbagliato si sente peggio di nessuno.
  final double confidence;

  /// Il volume del brano secondo per secondo, in dB (RMS). Dice dov'e' la
  /// parte calma del finale e quanto e' forte un tratto rispetto a un altro
  /// brano: a parita' di volume medio, un finale piano e un inizio forte
  /// sono un salto che si sente.
  final List<double> energy;

  /// La tonalita', per il riordino armonico delle playlist. Null se non si
  /// e' potuta stimare.
  final MusicalKey? key;

  /// La griglia del finale, dove si esce in un mix. Quella di questa
  /// classe e' dell'inizio, dove si entra: un tempo che deriva appena in
  /// tre minuti fa sbagliare di mezzo battito una griglia sola per tutto il
  /// brano, e il mix guarda comunque un tratto per volta. Nullo nelle
  /// analisi senza la rete dei battiti.
  final ({double bpm, double firstBeat, int downbeat, double confidence})?
  ending;

  /// Da quale analisi viene: 4 e' Beat This! con le feature per le frasi,
  /// 3 senza, 2 con la griglia contata battito per battito, 1 il
  /// rilevatore classico.
  final int version;

  /// Il timbro del brano nel tempo, per trovare frasi e sezioni (vedi
  /// phrase_analysis.dart): [featureRate] fotogrammi al secondo, e per
  /// ognuno [featureDims] valori in fila — l'energia dei bassi (sotto i
  /// 150 Hz, cassa e basso), dei medi (fino a 2 kHz, voce e accordi), degli
  /// acuti (piatti e charleston), tutte in dB, e quanto e' fitto di attacchi,
  /// in dB anche lui. Mezzo secondo basta: una battuta ne contiene quattro a
  /// 120 BPM, e le frasi si cercano battuta per battuta. Vuoto nelle analisi
  /// di prima.
  final List<double> features;

  static const int featureDims = 4;
  static const double featureRate = 2;

  /// L'inviluppo per le macchie che pulsano con la musica, come un
  /// visualizzatore: [envelopeRate] fotogrammi al secondo, e per ognuno
  /// [envelopeDims] valori — il picco dei bassi (sotto i 150 Hz) in dB, e
  /// quanto sono fitti gli attacchi sopra i 150 Hz (rullante, charleston,
  /// voce), in dB anche lui. Trenta al secondo per prendere ogni colpo di
  /// cassa al suo posto. Non sta nel json salvato con la griglia ma in un
  /// file suo (vedi TrackAnalyzer.envelopeFor): sono una decina di
  /// kilobyte a brano, e la scatola delle griglie sta tutta in memoria.
  final List<double> envelope;

  static const int envelopeDims = 2;
  static const double envelopeRate = 30;

  const BeatGrid({
    required this.bpm,
    required this.firstBeat,
    required this.downbeat,
    required this.musicStart,
    required this.musicEnd,
    required this.confidence,
    this.energy = const [],
    this.key,
    this.ending,
    this.version = 1,
    this.features = const [],
    this.envelope = const [],
  });

  BeatGrid withKey(MusicalKey? key) => BeatGrid(
    bpm: bpm,
    firstBeat: firstBeat,
    downbeat: downbeat,
    musicStart: musicStart,
    musicEnd: musicEnd,
    confidence: confidence,
    energy: energy,
    key: key,
    ending: ending,
    version: version,
    features: features,
    envelope: envelope,
  );

  /// La stessa griglia vista dal finale: quella da usare per il brano che
  /// esce. Senza una griglia del finale, quella di sempre.
  BeatGrid get outro {
    final e = ending;
    if (e == null) return this;
    return BeatGrid(
      bpm: e.bpm,
      firstBeat: e.firstBeat,
      downbeat: e.downbeat,
      musicStart: musicStart,
      musicEnd: musicEnd,
      confidence: e.confidence,
      energy: energy,
      key: key,
      version: version,
      features: features,
      envelope: envelope,
    );
  }

  /// Il volume medio fra [from] e [to], in dB. Nullo senza misure.
  double? levelBetween(double from, double to) {
    if (energy.isEmpty) return null;
    final a = from.floor().clamp(0, energy.length - 1);
    final b = to.ceil().clamp(a + 1, energy.length);
    // Media in potenza, non in dB: un secondo di silenzio non deve pesare
    // quanto un secondo di ritornello.
    var sum = 0.0;
    for (var i = a; i < b; i++) {
      sum += math.pow(10, energy[i] / 10);
    }
    return 10 * math.log(sum / (b - a)) / math.ln10;
  }

  /// Il volume tipico del brano, fra inizio e fine della musica.
  double? get medianLevel {
    if (energy.isEmpty) return null;
    final a = musicStart.floor().clamp(0, energy.length - 1);
    final b = musicEnd.ceil().clamp(a + 1, energy.length);
    final v = energy.sublist(a, b)..sort();
    return v[v.length ~/ 2];
  }

  double get beatLength => 60 / bpm;
  double get barLength => beatLength * 4;

  /// Il primo battere di battuta della griglia.
  double get firstBar => firstBeat + downbeat * beatLength;

  /// Il battere di battuta piu' vicino a [t], in avanti o indietro.
  double barAtOrBefore(double t) =>
      firstBar + ((t - firstBar) / barLength).floorToDouble() * barLength;

  double barAtOrAfter(double t) =>
      firstBar + ((t - firstBar) / barLength).ceilToDouble() * barLength;

  /// L'inizio della prossima frase da [t] in avanti: gruppi di quattro
  /// battute contati dal primo battere della musica.
  double phraseAtOrAfter(double t) {
    final origin = barAtOrAfter(musicStart - 0.05);
    final phrase = 4 * barLength;
    if (t <= origin) return origin;
    return origin + ((t - origin) / phrase - 1e-9).ceilToDouble() * phrase;
  }

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'firstBeat': firstBeat,
    'downbeat': downbeat,
    'musicStart': musicStart,
    'musicEnd': musicEnd,
    'confidence': confidence,
    'energy': [for (final e in energy) double.parse(e.toStringAsFixed(1))],
    // Anche senza tonalita' la chiave c'e': dice che la si e' cercata.
    'key': key == null
        ? -1
        : {
            'pc': key!.pitchClass,
            'minor': key!.minor,
            'conf': double.parse(key!.confidence.toStringAsFixed(3)),
          },
    if (ending != null)
      'ending': {
        'bpm': ending!.bpm,
        'firstBeat': ending!.firstBeat,
        'downbeat': ending!.downbeat,
        'confidence': ending!.confidence,
      },
    'v': version,
    // Un byte per valore, a mezzo decibel: in base64 sono tre kilobyte a
    // brano invece di dieci in numeri, e la scatola delle griglie sta tutta
    // in memoria.
    if (features.isNotEmpty) 'feat': encodeFeatures(features),
    if (envelope.isNotEmpty) 'env': encodeFeatures(envelope),
  };

  factory BeatGrid.fromJson(Map<String, dynamic> j) => BeatGrid(
    bpm: (j['bpm'] as num).toDouble(),
    firstBeat: (j['firstBeat'] as num).toDouble(),
    downbeat: (j['downbeat'] as num).toInt(),
    musicStart: (j['musicStart'] as num).toDouble(),
    musicEnd: (j['musicEnd'] as num).toDouble(),
    confidence: (j['confidence'] as num).toDouble(),
    energy: [
      for (final e in (j['energy'] as List?) ?? const []) (e as num).toDouble(),
    ],
    key: switch (j['key']) {
      final Map k => MusicalKey(
        (k['pc'] as num).toInt(),
        k['minor'] as bool,
        (k['conf'] as num?)?.toDouble() ?? 1,
      ),
      _ => null,
    },
    ending: switch (j['ending']) {
      final Map e => (
        bpm: (e['bpm'] as num).toDouble(),
        firstBeat: (e['firstBeat'] as num).toDouble(),
        downbeat: (e['downbeat'] as num).toInt(),
        confidence: (e['confidence'] as num).toDouble(),
      ),
      _ => null,
    },
    version: (j['v'] as num?)?.toInt() ?? 1,
    features: switch (j['feat']) {
      final String f => decodeFeatures(f),
      _ => const [],
    },
    envelope: switch (j['env']) {
      final String e => decodeFeatures(e),
      _ => const [],
    },
  );
}

/// L'ultima versione dell'analisi: le griglie piu' vecchie si rifanno
/// quando servono a un mix, perche' senza feature non ci sono frasi. La 5
/// aggiunge l'inviluppo per le macchie ([BeatGrid.envelope]).
const int beatGridVersion = 5;

/// Le feature in un byte l'una, da -100 a +27,5 dB a passi di mezzo
/// decibel: sotto i -100 e' silenzio comunque, e nessuna banda di un
/// master supera lo zero di molto.
String encodeFeatures(List<double> values) => base64Encode(
  Uint8List.fromList([
    for (final v in values) ((v + 100) * 2).round().clamp(0, 255),
  ]),
);

List<double> decodeFeatures(String encoded) => [
  for (final b in base64Decode(encoded)) b / 2 - 100,
];

/// Frequenza di campionamento dell'audio da analizzare. Undicimila bastano:
/// i battiti stanno nei bassi e nei transitori, non negli ultimi kHz.
const int analysisRate = 11025;

const int _fftSize = 512;
const int _hop = 128; // ~11,6 ms: la precisione con cui si trova un battito.

/// Analizza un brano da campioni mono a [analysisRate] Hz.
///
/// Il metodo e' quello classico dei rilevatori di tempo: un segnale di
/// "novita'" dallo spettro (quanto cresce l'energia da un istante al
/// successivo, banda per banda), la sua autocorrelazione per trovare il
/// periodo che si ripete, un pettine per la fase, e i bassi per capire
/// quale battito apre la battuta.
BeatGrid analyzeBeats(Int16List samples) {
  final fps = analysisRate / _hop;
  final frames = (samples.length - _fftSize) ~/ _hop;
  if (frames < fps * 10) {
    // Meno di dieci secondi: niente da misurare.
    return const BeatGrid(
      bpm: 120,
      firstBeat: 0,
      downbeat: 0,
      musicStart: 0,
      musicEnd: 0,
      confidence: 0,
    );
  }

  final window = Float64List(_fftSize);
  for (var i = 0; i < _fftSize; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_fftSize - 1));
  }
  final re = Float64List(_fftSize);
  final im = Float64List(_fftSize);
  const bins = _fftSize ~/ 2;
  // Fino a ~5 kHz per il flusso generale, fino a ~150 Hz per la cassa.
  final topBin = (5000 * _fftSize / analysisRate).floor().clamp(1, bins);
  final lowBin = (150 * _fftSize / analysisRate).ceil().clamp(2, bins);

  final onset = Float64List(frames);
  final lowOnset = Float64List(frames);
  final rmsDb = Float64List(frames);
  // L'energia di bassi, medi e acuti fotogramma per fotogramma, per le
  // feature delle frasi: viene dalla stessa FFT, quasi gratis.
  final midBin = (2000 * _fftSize / analysisRate).ceil().clamp(
    lowBin + 1,
    bins,
  );
  final bandLow = Float64List(frames);
  final bandMid = Float64List(frames);
  final bandHigh = Float64List(frames);
  var prev = Float64List(bins);
  var cur = Float64List(bins);

  for (var f = 0; f < frames; f++) {
    final off = f * _hop;
    var energy = 0.0;
    for (var i = 0; i < _fftSize; i++) {
      final v = samples[off + i] / 32768.0;
      energy += v * v;
      re[i] = v * window[i];
      im[i] = 0;
    }
    rmsDb[f] = 10 * math.log(energy / _fftSize + 1e-12) / math.ln10;
    _fft(re, im);
    var flux = 0.0;
    var lowFlux = 0.0;
    var pLow = 0.0, pMid = 0.0, pHigh = 0.0;
    for (var b = 1; b < bins; b++) {
      final power = re[b] * re[b] + im[b] * im[b];
      if (b < lowBin) {
        pLow += power;
      } else if (b < midBin) {
        pMid += power;
      } else {
        pHigh += power;
      }
      if (b >= topBin) continue;
      // Logaritmo: un colpo di cassa e uno di charleston devono contare
      // per quanto crescono, non per quanto sono forti in assoluto.
      final mag = math.log(1 + 100 * math.sqrt(power));
      cur[b] = mag;
      final d = mag - prev[b];
      if (d > 0) {
        flux += d;
        if (b < lowBin) lowFlux += d;
      }
    }
    onset[f] = flux;
    lowOnset[f] = lowFlux;
    bandLow[f] = pLow;
    bandMid[f] = pMid;
    bandHigh[f] = pHigh;
    final t = prev;
    prev = cur;
    cur = t;
  }

  // Dove c'e' musica: sopra i -50 dBFS e a meno di 35 dB dal punto piu'
  // forte, cosi' anche un master piano ha il suo inizio e la sua fine.
  var peak = -120.0;
  for (final v in rmsDb) {
    if (v > peak) peak = v;
  }
  final threshold = math.max(-50.0, peak - 35);
  var first = 0;
  while (first < frames - 1 && rmsDb[first] < threshold) {
    first++;
  }
  var last = frames - 1;
  while (last > first && rmsDb[last] < threshold) {
    last--;
  }
  final musicStart = first / fps;
  final musicEnd = (last * _hop + _fftSize) / analysisRate;

  // Il segnale di novita', ripulito dalla sua media locale: resta solo
  // cio' che sporge, cioe' gli attacchi.
  final novelty = _detrend(onset, (fps * 0.5).round());

  // Tempo: l'autocorrelazione fra 60 e 200 BPM, pesata verso i 120 come
  // fanno tutti i rilevatori — altrimenti meta' e doppio si equivalgono.
  final minLag = (60 * fps / 200).floor();
  final maxLag = (60 * fps / 60).ceil();
  final ac = Float64List(maxLag + 2);
  for (var lag = minLag; lag <= maxLag + 1; lag++) {
    var s = 0.0;
    for (var i = first; i + lag <= last; i++) {
      s += novelty[i] * novelty[i + lag];
    }
    ac[lag] = s / (last - first - lag + 1).clamp(1, 1 << 30);
  }
  var bestLag = minLag;
  var bestScore = -double.infinity;
  for (var lag = minLag + 1; lag <= maxLag; lag++) {
    // Solo i picchi veri.
    if (ac[lag] < ac[lag - 1] || ac[lag] < ac[lag + 1]) continue;
    final bpm = 60 * fps / lag;
    final prior = math.exp(
      -0.5 * math.pow(math.log(bpm / 120) / math.ln2 / 0.8, 2),
    );
    final score = ac[lag] * prior;
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  // Frazione di fotogramma: interpolazione parabolica sul picco.
  final a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1];
  final denom = a - 2 * b + c;
  var period = bestLag + (denom == 0 ? 0 : 0.5 * (a - c) / denom);
  // Mezzo tempo: rap e trap si leggono spesso a 70 invece che a 140,
  // perche' il rullante cade un battito si' e uno no. Sotto i 90, se il
  // doppio si ripete quasi altrettanto forte, il tempo vero e' il doppio —
  // "Illegal" di PinkPantheress usciva a 70,7 invece di 141.
  if (60 * fps / period < 90 && _at(ac, period / 2) >= 0.5 * b) {
    period /= 2;
  }

  // Quanto il picco sporge dalle altre correlazioni: la fiducia.
  final values = [for (var l = minLag; l <= maxLag; l++) ac[l]]..sort();
  final median = values[values.length ~/ 2];
  final top = values.last;
  final confidence = top <= 0
      ? 0.0
      : ((b - median) / (top.abs() + 1e-9)).clamp(0.0, 1.0);

  // Fase: il pettine con quel periodo che raccoglie piu' attacchi.
  var bestPhase = 0.0;
  var bestSum = -double.infinity;
  for (var ph = 0.0; ph < period; ph += 0.25) {
    var s = 0.0;
    for (var t = first + ph; t < last; t += period) {
      s += _at(novelty, t);
    }
    if (s > bestSum) {
      bestSum = s;
      bestPhase = first + ph;
    }
  }
  // Affinamento: il picco vero vicino a ogni battito della griglia, poi
  // una retta per tutti. Il periodo dall'autocorrelazione ha un piccolo
  // errore che battito dopo battito si accumula — su tre minuti sono
  // decine di millisecondi, e un mix a tempo li sente tutti. La retta
  // invece li distribuisce: nessun battito sbaglia di piu' degli altri.
  var fitPeriod = period;
  var fitPhase = bestPhase;
  for (var pass = 0; pass < 2; pass++) {
    final ks = <double>[];
    final ts = <double>[];
    final kFirst = ((first - fitPhase) / fitPeriod).ceil();
    for (var k = kFirst; fitPhase + k * fitPeriod < last; k++) {
      final c = fitPhase + k * fitPeriod;
      final lo = (c - fitPeriod / 4).floor().clamp(1, frames - 2);
      final hi = (c + fitPeriod / 4).ceil().clamp(1, frames - 2);
      var m = lo;
      for (var i = lo; i <= hi; i++) {
        if (novelty[i] > novelty[m]) m = i;
      }
      if (novelty[m] <= 0) continue;
      // Il picco fra due fotogrammi, dalla parabola sui tre vicini.
      final y0 = novelty[m - 1], y1 = novelty[m], y2 = novelty[m + 1];
      final d = y0 - 2 * y1 + y2;
      ks.add(k.toDouble());
      ts.add(m + (d == 0 ? 0 : 0.5 * (y0 - y2) / d));
    }
    if (ks.length < 8) break;
    final n = ks.length;
    final mk = ks.reduce((a, b) => a + b) / n;
    final mt = ts.reduce((a, b) => a + b) / n;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < n; i++) {
      num += (ks[i] - mk) * (ts[i] - mt);
      den += (ks[i] - mk) * (ks[i] - mk);
    }
    fitPeriod = num / den;
    fitPhase = mt - fitPeriod * mk;
  }
  final finalBpm = 60 * fps / fitPeriod;

  // Il primo battito della griglia, riportato all'inizio del brano.
  var firstBeatFrame = fitPhase;
  while (firstBeatFrame - fitPeriod >= 0) {
    firstBeatFrame -= fitPeriod;
  }
  while (firstBeatFrame < 0) {
    firstBeatFrame += fitPeriod;
  }
  // Il fotogramma misura dall'inizio della sua finestra; l'attacco sta
  // circa a meta'.
  final firstBeat = (firstBeatFrame * _hop + _fftSize / 2) / analysisRate;

  // Il battere: fra i quattro battiti, quello con la cassa piu' forte.
  final low = _detrend(lowOnset, (fps * 0.5).round());
  final sums = List<double>.filled(4, 0);
  var k = 0;
  for (var t = firstBeatFrame; t < last; t += fitPeriod, k++) {
    if (t < first) continue;
    sums[k % 4] += _at(low, t);
  }
  var downbeat = 0;
  for (var i = 1; i < 4; i++) {
    if (sums[i] > sums[downbeat]) downbeat = i;
  }

  // Il volume secondo per secondo, dalla stessa misura della fine della
  // musica.
  final seconds = (frames / fps).floor();
  final energy = <double>[
    for (var sec = 0; sec < seconds; sec++)
      () {
        final a = (sec * fps).floor(), b = ((sec + 1) * fps).floor();
        var p = 0.0;
        for (var i = a; i < b && i < frames; i++) {
          p += math.pow(10, rmsDb[i] / 10);
        }
        return 10 * math.log(p / (b - a) + 1e-12) / math.ln10;
      }(),
  ];

  // Le feature per le frasi, a mezzo secondo: la media in potenza di ogni
  // banda, e quella degli attacchi. La potenza si divide per quella di una
  // finestra piena, cosi' i dB sono quelli di un segnale a fondo scala.
  final step = fps / BeatGrid.featureRate;
  final count = (frames / step).floor();
  const norm = 1 / (_fftSize * _fftSize / 4.0);
  double db(double p) => 10 * math.log(p + 1e-10) / math.ln10;
  final features = <double>[];
  for (var k = 0; k < count; k++) {
    final a = (k * step).floor(),
        b = math.min(frames, ((k + 1) * step).floor());
    var l = 0.0, m = 0.0, h = 0.0, o = 0.0;
    for (var i = a; i < b; i++) {
      l += bandLow[i];
      m += bandMid[i];
      h += bandHigh[i];
      o += onset[i];
    }
    final n = math.max(1, b - a);
    features
      ..add(db(l / n * norm))
      ..add(db(m / n * norm))
      ..add(db(h / n * norm))
      ..add(10 * math.log(o / n + 1e-3) / math.ln10);
  }

  // L'inviluppo per le macchie: dei bassi il picco e non la media, perche'
  // una cassa dura meno di un fotogramma e nella media si perderebbe; degli
  // attacchi sopra i bassi la media, che dice quanto e' fitto il tratto.
  final envStep = fps / BeatGrid.envelopeRate;
  final envCount = (frames / envStep).floor();
  final envelope = <double>[];
  for (var k = 0; k < envCount; k++) {
    final a = (k * envStep).floor(),
        b = math.min(frames, math.max(a + 1, ((k + 1) * envStep).floor()));
    var l = 0.0, o = 0.0;
    for (var i = a; i < b; i++) {
      if (bandLow[i] > l) l = bandLow[i];
      o += math.max(0.0, onset[i] - lowOnset[i]);
    }
    envelope
      ..add(db(l * norm))
      ..add(10 * math.log(o / (b - a) + 1e-3) / math.ln10);
  }

  return BeatGrid(
    bpm: finalBpm,
    energy: energy,
    firstBeat: firstBeat,
    downbeat: downbeat,
    musicStart: musicStart,
    musicEnd: musicEnd,
    confidence: confidence,
    features: features,
    envelope: envelope,
  );
}

/// Il valore di [x] in una posizione frazionaria, interpolato.
double _at(Float64List x, double t) {
  final i = t.floor();
  if (i < 0 || i + 1 >= x.length) return 0;
  final f = t - i;
  return x[i] * (1 - f) + x[i + 1] * f;
}

/// [x] meno la sua media mobile, e mai sotto zero.
Float64List _detrend(Float64List x, int radius) {
  final out = Float64List(x.length);
  var sum = 0.0;
  var count = 0;
  var lo = 0, hi = -1;
  for (var i = 0; i < x.length; i++) {
    while (hi < i + radius && hi + 1 < x.length) {
      hi++;
      sum += x[hi];
      count++;
    }
    while (lo < i - radius) {
      sum -= x[lo];
      lo++;
      count--;
    }
    final v = x[i] - sum / count;
    out[i] = v > 0 ? v : 0;
  }
  return out;
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
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ur = re[i + k], ui = im[i + k];
        final xr = re[i + k + len ~/ 2], xi = im[i + k + len ~/ 2];
        final vr = xr * cr - xi * ci;
        final vi = xr * ci + xi * cr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + len ~/ 2] = ur - vr;
        im[i + k + len ~/ 2] = ui - vi;
        final ncr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = ncr;
      }
    }
  }
}
