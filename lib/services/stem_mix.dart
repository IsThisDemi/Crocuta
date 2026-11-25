import 'dart:math' as math;
import 'dart:typed_data';

import 'automix.dart';
import 'stem_separator.dart';

/// La frequenza di voce e base: quella del modello di separazione.
const stemRate = 44100;

/// Quanto del brano uscente serve separare per [plan].
///
/// Dall'inizio del mix alla fine, o fino alla fine del loop se la musica
/// si ripete. Nell'eco il loop e' il battito *prima* del mix: allora si
/// parte da li', o il tratto sarebbe lungo zero.
({double start, double end}) outgoingWindow(BeatMixPlan plan) {
  final st = plan.stems;
  // La battuta dell'eco va sempre separata: quando la musica finisce
  // subito dopo l'ultima frase cade oltre la fine del loop, e senza di lei
  // l'eco ripeteva silenzio.
  final echoEnd = st?.echoFrom == null
      ? 0.0
      : plan.outStart + st!.echoFrom! + st.echoLength;
  if (!plan.loops) {
    return (
      start: plan.outStart,
      end: math.max(plan.outStart + plan.length, echoEnd),
    );
  }
  // Oltre la fine del loop la base non va: si ripete.
  return (
    start: math.min(plan.outStart, plan.loopStart!),
    end: math.max(plan.loopEnd!, echoEnd),
  );
}

/// Il tratto del brano uscente come suonera' nel mix, rifatto da voce e base.
///
/// All'istante zero e' identico al brano: il player che lo suona prende il
/// posto dell'uscente senza che si senta. Poi:
///
/// - dove la musica finisce e l'ultima battuta si ripete, si ripete la sola
///   base — la voce ripetuta a pezzi e' proprio il loop che si nota;
/// - l'ultima battuta cantata torna in eco, ogni volta piu' piano;
/// - la voce, eco compresa, si spegne in un battito prima che canti
///   l'entrante.
///
/// Stereo interleaved, [stemRate] campioni al secondo, lungo quanto il mix.
Float32List renderOutgoing(Stems stems, BeatMixPlan plan) {
  final st = plan.stems ?? const StemPlan();
  final window = outgoingWindow(plan);
  final frames = (plan.length * stemRate).round();
  final available = stems.baseL.length;
  final out = Float32List(frames * 2);
  final loopLen = plan.loops ? plan.loopEnd! - plan.loopStart! : 0.0;

  // Da che punto del tratto separato viene l'istante [t] del mix.
  double source(double t) {
    var src = plan.outStart + t;
    if (plan.loops && src >= plan.loopEnd!) {
      src = plan.loopStart! + (src - plan.loopStart!) % loopLen;
    }
    return src - window.start;
  }

  int at(double sec) => (sec * stemRate).round().clamp(0, available - 1);

  // Oltre la fine del file (il brano finisce prima della battuta dell'eco)
  // e' silenzio, non l'ultimo campione ripetuto, che ronzerebbe.
  bool inside(double sec) => sec >= 0 && sec * stemRate < available;

  // Una rampa breve ai bordi di ogni pezzo: un taglio netto sulla voce e'
  // uno schiocco.
  const edge = 0.01;
  double ramp(double into, double length) {
    if (into < 0 || into >= length) return 0;
    return math.min(1, math.min(into / edge, (length - into) / edge));
  }

  final echoFrom = st.echoFrom;
  final echoEnd = echoFrom == null ? double.infinity : echoFrom + st.echoLength;

  // La cucitura del loop: negli ultimi 20 ms prima di ogni ritorno la fine
  // della battuta sfuma in quello che precede il suo inizio, cosi' il salto
  // indietro trova l'onda gia' dov'era. Senza, a ogni giro c'era uno
  // schiocco: il loop che si sente tagliato.
  const seam = 0.02;

  for (var i = 0; i < frames; i++) {
    final t = i / stemRate;
    final src = source(t);
    final j = at(src);
    var l = stems.baseL[j];
    var r = stems.baseR[j];
    if (plan.loops) {
      final toEnd = plan.loopEnd! - window.start - src;
      if (toEnd > 0 && toEnd <= seam) {
        final w = 1 - toEnd / seam;
        final k = at(src - loopLen);
        l = l * (1 - w) + stems.baseL[k] * w;
        r = r * (1 - w) + stems.baseR[k] * w;
      }
    }

    // La voce originale va sempre avanti col brano, anche dove la base
    // si ripete: fino alla fine della battuta dell'eco, se c'e' — l'ultima
    // frase si sente intera — e altrimenti fino a dove comincia il loop,
    // perche' una voce ripetuta a pezzi e' proprio il loop che si nota.
    var vl = 0.0, vr = 0.0;
    final looping = plan.loops && plan.outStart + t >= plan.loopEnd!;
    final voiceUntil = echoFrom != null
        ? echoEnd
        : plan.loops
        ? plan.loopEnd! - plan.outStart
        : double.infinity;
    if (t < voiceUntil && (echoFrom != null || !looping)) {
      final g = voiceUntil.isFinite
          ? math.min(1.0, (voiceUntil - t) / edge).clamp(0.0, 1.0)
          : 1.0;
      final sv = plan.outStart - window.start + t;
      if (inside(sv)) {
        final jv = at(sv);
        vl += stems.vocalsL[jv] * g;
        vr += stems.vocalsR[jv] * g;
      }
    }

    // L'eco: la battuta cantata per ultima, ripetuta.
    if (echoFrom != null && t >= echoEnd) {
      final k = ((t - echoFrom) / st.echoLength).floor();
      if (k >= 1 && k <= st.echoRepeats) {
        final into = t - echoFrom - k * st.echoLength;
        final g = StemPlan.echoGain(k) * ramp(into, st.echoLength);
        final se = plan.outStart - window.start + echoFrom + into;
        if (inside(se)) {
          final e = at(se);
          vl += stems.vocalsL[e] * g;
          vr += stems.vocalsR[e] * g;
        }
      }
    }

    // Spenta prima che canti l'entrante.
    final duck = t <= st.duckAt - StemPlan.duckFade
        ? 1.0
        : t >= st.duckAt
        ? 0.0
        : (st.duckAt - t) / StemPlan.duckFade;
    l += vl * duck;
    r += vr * duck;

    out[2 * i] = l;
    out[2 * i + 1] = r;
  }
  // L'eco a tempo degli stili che la vogliono: sul tratto intero, voce e
  // base insieme, come la manda un DJ dal mixer.
  final delay = plan.echoDelay;
  if (delay != null && plan.length > 0) {
    applyTempoEcho(
      out,
      delay: delay,
      send: (sec) => plan.stage(sec / plan.length, incoming: false).echo,
    );
  }
  return out;
}

/// Un'eco a tempo su [io] (stereo interleaved a [stemRate]), sul posto.
///
/// [delay] e' il passo delle ripetizioni in secondi — una frazione di
/// battito, perche' cadano a tempo — e [send] dice, secondo per secondo,
/// quanta eco c'e', 0-1. E' la mandata di un DJ al contrario: invece di
/// sommare l'eco al brano, l'eco ne prende il posto. A 0 il tratto esce
/// identico; a 1 il suono asciutto e' sparito e restano solo le
/// ripetizioni di quello che si e' appena sentito, ognuna alla meta' della
/// precedente e un po' piu' sottile (un passa-alto a [cutHz] a ogni giro:
/// niente cassa ne' basso che ritornano sotto l'entrante).
///
/// Mai piu' forte del tratto com'era. Con le ripetizioni a meta' volume la
/// somma dei loro pesi e' 1/2 + 1/4 + ... = 1, quindi l'eco non supera il
/// picco del suono che ripete; e asciutto ed eco si dividono l'ampiezza,
/// (1 - send) e send, quindi la somma neppure. Il passa-alto potrebbe
/// sporgere di un soffio sui transitori: alla fine si misura il picco, e se
/// supera quello del tratto originale l'eco si abbassa finche' non ci sta.
///
/// Il suono asciutto entra nell'eco pieno finche' si sente, e smette di
/// entrarci mentre sparisce: altrimenti l'eco ripeterebbe un brano che
/// nessuno sta piu' ascoltando, come una seconda copia in ritardo.
void applyTempoEcho(
  Float32List io, {
  required double delay,
  required double Function(double seconds) send,
  double feedback = 0.5,
  double cutHz = 250,
}) {
  final frames = io.length ~/ 2;
  if (frames == 0) return;
  final d = math.max(1, (delay * stemRate).round());
  final w = Float32List(frames);
  var any = false;
  for (var i = 0; i < frames; i++) {
    final v = send(i / stemRate).clamp(0.0, 1.0);
    w[i] = v;
    if (v > 0) any = true;
  }
  if (!any) return;
  final wet = Float32List(io.length);
  final a = math.exp(-2 * math.pi * cutHz / stemRate);
  var pzL = 0.0, pzR = 0.0, hL = 0.0, hR = 0.0;
  var peakIn = 0.0;
  for (var i = 0; i < frames; i++) {
    final l = io[2 * i].abs(), r = io[2 * i + 1].abs();
    if (l > peakIn) peakIn = l;
    if (r > peakIn) peakIn = r;
    if (i < d) continue;
    final j = i - d;
    // Quanto del suono asciutto di allora entra nell'eco: tutto, finche'
    // la mandata non arriva quasi in fondo.
    final x = ((w[j] - 0.9) / 0.1).clamp(0.0, 1.0);
    final capture = 1 - x * x * (3 - 2 * x);
    final zL = io[2 * j] * capture + wet[2 * j];
    final zR = io[2 * j + 1] * capture + wet[2 * j + 1];
    hL = a * (hL + zL - pzL);
    hR = a * (hR + zR - pzR);
    pzL = zL;
    pzR = zR;
    wet[2 * i] = feedback * hL;
    wet[2 * i + 1] = feedback * hR;
  }
  double peakWith(double scale) {
    var p = 0.0;
    for (var i = 0; i < frames; i++) {
      final g = w[i];
      if (g == 0) continue;
      final l = ((1 - g) * io[2 * i] + scale * g * wet[2 * i]).abs();
      final r = ((1 - g) * io[2 * i + 1] + scale * g * wet[2 * i + 1]).abs();
      if (l > p) p = l;
      if (r > p) p = r;
    }
    return p;
  }

  var scale = 1.0;
  for (var k = 0; k < 4; k++) {
    final p = peakWith(scale);
    if (p <= peakIn) break;
    scale *= peakIn / p;
  }
  // Se ancora sporge, a dimezzamenti fra zero (che ci sta sempre: resta il
  // solo suono asciutto, abbassato) e la scala trovata.
  if (peakWith(scale) > peakIn) {
    var lo = 0.0, hi = scale;
    for (var k = 0; k < 12; k++) {
      final mid = (lo + hi) / 2;
      if (peakWith(mid) <= peakIn) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    scale = lo;
  }
  for (var i = 0; i < frames; i++) {
    final g = w[i];
    if (g == 0) continue;
    io[2 * i] = (1 - g) * io[2 * i] + scale * g * wet[2 * i];
    io[2 * i + 1] = (1 - g) * io[2 * i + 1] + scale * g * wet[2 * i + 1];
  }
}

/// Quanto del brano entrante suona durante il mix: dal suo primo battere,
/// per la durata del mix alla sua velocita'.
({double start, double end}) incomingWindow(BeatMixPlan plan) => (
  start: plan.inStart,
  end: plan.inStart + plan.incomingSeconds(plan.wallLength),
);

/// Il tratto dell'entrante per il passaggio di voce: la base piena da
/// subito, la voce solo da quando l'uscente ha finito la sua riga.
///
/// Alla fine e' identico al brano, voce compresa: il player che lo suona
/// puo' restituire il posto all'entrante vero senza che si senta.
///
/// In secondi dell'entrante, che suona alla velocita' del mix: l'istante
/// u del tratto e' l'istante u / speed del mix.
Float32List renderIncoming(Stems stems, BeatMixPlan plan) {
  final st = plan.stems ?? const StemPlan();
  final n = stems.baseL.length;
  final out = Float32List(n * 2);
  for (var i = 0; i < n; i++) {
    final g = st.incomingVoice(i / stemRate / plan.speed * plan.outSpeed);
    out[2 * i] = stems.baseL[i] + stems.vocalsL[i] * g;
    out[2 * i + 1] = stems.baseR[i] + stems.vocalsR[i] * g;
  }
  return out;
}

/// L'uscita in eco del cambio secco: il tratto dell'uscente fino allo
/// sgancio, poi solo l'eco del suo ultimo battito.
///
/// Come fa un DJ quando i tempi non si possono accordare: all'ultimo
/// battito accende l'eco e chiude il brano. Il battito si ripete a tempo,
/// ogni volta al 55%, e passa per un passa-alto a 250 Hz: l'eco non porta
/// cassa ne' basso, che sotto l'entrante sarebbero un altro tempo. Senza,
/// il cambio secco era cosi' discreto da sembrare nessuna transizione.
///
/// [left] e [right] partono dall'inizio del mix; [drop] e [beat] sono in
/// secondi; il risultato e' stereo interleaved, lungo [length] secondi.
Float32List renderEchoOut(
  Float32List left,
  Float32List right, {
  required double drop,
  required double beat,
  required double length,
}) {
  final frames = (length * stemRate).round();
  final out = Float32List(frames * 2);
  final dropAt = (drop * stemRate).round();
  final period = math.max(1, (beat * stemRate).round());
  final grab = dropAt - period;
  final available = left.length;
  const fade = 441; // 10 ms: un taglio netto e' uno schiocco
  const feedback = 0.55;
  final hp = math.exp(-2 * math.pi * 250 / stemRate);
  var pl = 0.0, pr = 0.0, yl = 0.0, yr = 0.0;
  for (var i = 0; i < frames; i++) {
    var l = 0.0, r = 0.0;
    if (i < dropAt && i < available) {
      final g = i > dropAt - fade ? (dropAt - i) / fade : 1.0;
      l = left[i] * g;
      r = right[i] * g;
    }
    var wl = 0.0, wr = 0.0;
    if (i >= dropAt && grab >= 0) {
      final into = (i - dropAt) % period;
      final k = (i - dropAt) ~/ period + 1;
      final j = grab + into;
      if (j < available) {
        final edge = math.min(1.0, math.min(into / 220, (period - into) / 220));
        final g = math.pow(feedback, k).toDouble() * edge;
        wl = left[j] * g;
        wr = right[j] * g;
      }
    }
    // Passa-alto a un polo sull'eco.
    yl = hp * (yl + wl - pl);
    yr = hp * (yr + wr - pr);
    pl = wl;
    pr = wr;
    out[2 * i] = l + yl;
    out[2 * i + 1] = r + yr;
  }
  return out;
}

/// Un wav float a 32 bit, stereo: quello che mpv legge senza decodificare
/// e senza perdere niente.
Uint8List wavFloat32(Float32List interleaved, {int rate = stemRate}) {
  final dataBytes = interleaved.length * 4;
  final b = ByteData(44 + dataBytes);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 3, Endian.little); // IEEE float
  b.setUint16(22, 2, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 8, Endian.little);
  b.setUint16(32, 8, Endian.little);
  b.setUint16(34, 32, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  final bytes = b.buffer.asUint8List();
  bytes.setRange(
    44,
    44 + dataBytes,
    interleaved.buffer.asUint8List(interleaved.offsetInBytes, dataBytes),
  );
  return bytes;
}
