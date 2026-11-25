import 'dart:math' as math;
import 'dart:typed_data';

import 'automix.dart';

// --- L'attesa della pausa nella voce ---
//
// Il piano decide dove la voce dell'uscente si spegne (o passa
// all'entrante) dal testo sincronizzato: un verso comincia a un certo
// secondo, e la voce finisce quattro secondi dopo l'ultimo. E' una stima,
// e il testo non dice dove il cantante prende fiato: lo spegnimento
// poteva cadere a meta' parola, e una voce tagliata a meta' frase e'
// proprio quello che un DJ non fa mai. Lui aspetta la pausa.
//
// Quando la separazione e' finita la voce dell'uscente c'e', da sola, per
// tutto il mix: se ne misura il volume ogni 20 ms, e se lo spegnimento
// cade mentre il cantante canta, si sposta nella pausa di almeno un
// battito piu' vicina — meglio se comincia su un battito, una battuta o
// una frase. Mai oltre i limiti del piano: mai dopo che comincia a cantare
// l'entrante (salvo nel passaggio di voce, dove l'entrante e' muto finche'
// non tocca a lui), mai oltre la fine del mix. Senza una pausa il piano
// resta com'e': non e' un ripiego, e' che non c'e' niente di meglio da
// fare, e il registro lo dice.

/// Ogni quanto si misura il volume della voce, in secondi.
const double vocalEnvelopeHop = 0.02;

/// Quanto sotto il volume tipico del cantato deve scendere la voce perche'
/// sia una pausa, in dB. La voce separata non e' mai zero: resta un filo
/// della base (qualche decina di dB sotto) e la coda del riverbero. Venti
/// dB sotto il cantato pieno sono gia' silenzio per l'orecchio, sopra quel
/// filo; e la coda del riverbero conta come voce, cosi' la pausa comincia
/// quando e' finita anche lei.
const double vocalQuietDb = 20;

/// Sotto questo volume, in dBFS, la voce e' muta comunque: un tratto senza
/// cantato ha il volume tipico del filo che resta, e le sue pause
/// relative sarebbero rumore.
const double vocalFloorDb = -55;

/// Il volume della voce dell'uscente nel tratto del mix, in dB, un valore
/// ogni [vocalEnvelopeHop] secondi dall'inizio del mix.
class VocalEnvelope {
  final Float32List db;

  const VocalEnvelope(this.db);

  /// Quanto dura, in secondi.
  double get length => db.length * vocalEnvelopeHop;

  /// Sotto quale volume la voce tace: [vocalQuietDb] sotto il cantato pieno
  /// (il 90° percentile: le note piu' forti, ma non un colpo isolato), e
  /// comunque non sotto [vocalFloorDb]. Senza cantato nel tratto e' il
  /// pavimento, e tutto il tratto e' una pausa.
  double get quietBelow {
    if (db.isEmpty) return vocalFloorDb;
    final sorted = Float32List.fromList(db)..sort();
    final loud = sorted[((sorted.length - 1) * 0.9).round()];
    return math.max(loud - vocalQuietDb, vocalFloorDb);
  }

  /// Se fra [from] e [to] secondi la voce canta, anche per un attimo.
  bool activeBetween(double from, double to) {
    final quiet = quietBelow;
    final a = (from / vocalEnvelopeHop).floor().clamp(0, db.length);
    final b = (to / vocalEnvelopeHop).ceil().clamp(a, db.length);
    for (var i = a; i < b; i++) {
      if (db[i] >= quiet) return true;
    }
    return false;
  }
}

/// Il volume della voce [left]/[right] (a [rate] campioni al secondo) da
/// [from] secondi per [length] secondi: un valore RMS ogni
/// [vocalEnvelopeHop], in dB. Oltre la fine dei campioni e' silenzio.
VocalEnvelope vocalEnvelope(
  Float32List left,
  Float32List right, {
  required double from,
  required double length,
  required int rate,
}) {
  final frames = math.max(0, (length / vocalEnvelopeHop).floor());
  final hop = vocalEnvelopeHop * rate;
  final out = Float32List(frames);
  final n = math.min(left.length, right.length);
  for (var k = 0; k < frames; k++) {
    final a = ((from + k * vocalEnvelopeHop) * rate).round();
    final b = (a + hop).round();
    var sum = 0.0;
    var count = 0;
    for (var i = math.max(0, a); i < math.min(b, n); i++) {
      final m = (left[i] + right[i]) / 2;
      sum += m * m;
      count++;
    }
    final rms = count == 0 ? 0.0 : math.sqrt(sum / count);
    out[k] = rms <= 1e-6 ? -120 : 20 * math.log(rms) / math.ln10;
  }
  return VocalEnvelope(out);
}

/// Le pause della voce lunghe almeno [minLength] secondi: dove il volume
/// resta sotto [VocalEnvelope.quietBelow], in ordine, in secondi dall'inizio
/// del mix.
List<({double start, double end})> vocalGaps(
  VocalEnvelope env, {
  required double minLength,
}) {
  final quiet = env.quietBelow;
  final gaps = <({double start, double end})>[];
  int? from;
  void close(int to) {
    final f = from;
    if (f == null) return;
    final start = f * vocalEnvelopeHop, end = to * vocalEnvelopeHop;
    if (end - start >= minLength - 1e-9) gaps.add((start: start, end: end));
    from = null;
  }

  for (var i = 0; i < env.db.length; i++) {
    if (env.db[i] < quiet) {
      from ??= i;
    } else {
      close(i);
    }
  }
  close(env.db.length);
  return gaps;
}

/// Dove cade un istante sulla griglia del mix: 3 sull'"1" di una frase da
/// quattro battute, 2 su una battuta, 1 su un battito, 0 altrove. Il mix
/// comincia sull'"1" di una frase, quindi la griglia parte da zero.
int handoverLevel(double t, double beat) {
  final k = (t / beat).round();
  if ((t - k * beat).abs() > 1e-6) return 0;
  if (k % 16 == 0) return 3;
  if (k % 4 == 0) return 2;
  return 1;
}

/// Quanto vale, in battiti di distanza, cadere su un battito, una battuta,
/// una frase: una pausa sulla battuta e' meglio di una a meta' battito un
/// battito piu' vicina; una sulla frase vale due battiti di strada.
const List<double> _levelBonus = [0, 0.25, 1, 2];

/// Il punto in cui far cominciare lo spegnimento della voce, in una delle
/// [gaps]: il piu' vicino a [planned], fra [earliest] e [latest], con la
/// preferenza per i confini di [_levelBonus]. Nullo se nessuna pausa ci sta.
///
/// In ogni pausa lo spegnimento, lungo [fade], puo' cominciare dall'inizio
/// della pausa fino a [fade] prima della sua fine — finisce prima che il
/// cantante riprenda — e dentro i limiti del piano. Si provano l'inizio di
/// quel tratto e ogni battito che ci cade dentro; vince il costo piu'
/// basso, distanza in battiti meno il bonus del confine, e a parita' il
/// piu' presto. Sempre lo stesso risultato per le stesse misure.
({double at, double gapStart, double gapEnd, int level})? chooseVocalHandover(
  List<({double start, double end})> gaps, {
  required double planned,
  required double earliest,
  required double latest,
  required double beat,
  double fade = StemPlan.duckFade,
}) {
  ({double at, double gapStart, double gapEnd, int level})? best;
  var bestCost = double.infinity;
  void consider(double at, ({double start, double end}) gap) {
    final level = handoverLevel(at, beat);
    final cost = (at - planned).abs() / beat - _levelBonus[level];
    if (cost < bestCost - 1e-9) {
      bestCost = cost;
      best = (at: at, gapStart: gap.start, gapEnd: gap.end, level: level);
    }
  }

  for (final gap in gaps) {
    final lo = math.max(gap.start, earliest);
    final hi = math.min(math.max(gap.start, gap.end - fade), latest);
    if (lo > hi + 1e-9) continue;
    consider(lo, gap);
    for (var k = ((lo - 1e-6) / beat).ceil(); k * beat <= hi + 1e-6; k++) {
      final at = k * beat;
      if (at < lo - 1e-6) continue;
      consider(at, gap);
    }
  }
  return best;
}

/// Un istante del mix per il registro: secondi dall'inizio del mix, nel
/// tempo dell'uscente, come tutti quelli di [StemPlan].
String _s(double x) => x.toStringAsFixed(2);

const _levelNames = [
  "all'inizio della pausa",
  'su un battito',
  'su una battuta',
  "sull'1 di una frase",
];

/// Il passaggio di voce di [plan] spostato nella pausa del cantato piu'
/// vicina, misurata su [env], e la riga del registro che lo racconta.
///
/// Il piano resta lo stesso (lo stesso oggetto) quando la voce non si
/// spegne, quando torna in eco (la frase e' gia' chiusa sulla battuta
/// dell'eco), quando lo spegnimento cade gia' in una pausa, o quando una
/// pausa di almeno un battito non c'e': allora la riga dice perche'.
({BeatMixPlan plan, String note}) placeVocalHandover(
  BeatMixPlan plan,
  VocalEnvelope env,
) {
  final st = plan.stems;
  final start = st?.handoverStart;
  if (st == null || start == null) {
    return (plan: plan, note: 'voce: non si spegne nel mix');
  }
  if (st.echoFrom != null) {
    return (plan: plan, note: "voce: chiusa dall'eco, niente da spostare");
  }
  final beat = plan.outBeat;
  if (beat == null || beat <= 0) {
    return (plan: plan, note: 'voce: senza battiti, niente da spostare');
  }
  const fade = StemPlan.duckFade;
  final what = st.exchangeAt == null ? 'spegnimento' : 'passaggio';
  if (!env.activeBetween(start, start + fade)) {
    return (
      plan: plan,
      note: "voce: $what a ${_s(start)} s del mix gia' in una pausa",
    );
  }
  // Non prima di una battuta di mix, come lo spegnimento del piano; mai
  // oltre il suo limite, e mai che finisca oltre la fine del mix.
  final earliest = math.max(0.0, 4 * beat - fade);
  final latest = math.min(st.latestHandoverStart, plan.length - fade);
  final gaps = vocalGaps(env, minLength: beat);
  final choice = chooseVocalHandover(
    gaps,
    planned: start,
    earliest: earliest,
    latest: latest,
    beat: beat,
    fade: fade,
  );
  if (choice == null) {
    return (
      plan: plan,
      note:
          "voce: $what a ${_s(start)} s del mix a meta' frase, nessuna pausa di "
          'almeno un battito fra ${_s(earliest)} e ${_s(latest)} s: resta',
    );
  }
  if ((choice.at - start).abs() < 1e-6) {
    return (plan: plan, note: 'voce: $what a ${_s(start)} s del mix, resta');
  }
  return (
    plan: plan.withStems(st.handoverAt(choice.at)),
    note:
        "voce: $what da ${_s(start)} a ${_s(choice.at)} s del mix, nella pausa "
        '${_s(choice.gapStart)}-${_s(choice.gapEnd)} s '
        '${_levelNames[choice.level]}',
  );
}
