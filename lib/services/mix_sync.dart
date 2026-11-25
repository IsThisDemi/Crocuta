import 'automix.dart';

// --- Il controllo del tempo durante il mix ---
//
// Il mix a tempo regge se i battiti dei due brani cadono insieme per tutta
// la transizione. All'inizio cadono insieme per costruzione: l'entrante
// parte sul suo battere quando l'uscente e' sul suo. Poi ognuno va per
// conto suo, e prima lo si teneva legato all'orologio: l'entrante doveva
// essere a inStart + secondi passati per la velocita'. Ma quello che si
// sente non e' l'orologio, sono i due brani: se l'uscente scivola (la
// latenza d'uscita che cambia, una rampa di velocita' che arriva un filo
// prima o dopo, un player che riparte dal loop), l'entrante perfettamente
// sull'orologio e' comunque fuori tempo rispetto a lui.
//
// Qui si confrontano i due player fra loro, sulle loro griglie: dov'e'
// ognuno rispetto al suo ultimo battito, in secondi veri. Le due griglie
// battono insieme (stesso battito, o doppio e meta' tempo), quindi lo
// scarto fra le due fasi e' lo scarto che si sente fra le due casse. Sopra
// [syncTolerance] l'entrante va un filo piu' svelto o piu' piano — mai un
// salto, che si sentirebbe — e torna alla velocita' del mix quando lo
// scarto rientra.

/// Lo scarto oltre il quale si corregge, in secondi: 25 ms, la soglia sotto
/// cui due colpi di cassa si sentono ancora come uno solo.
const double syncTolerance = 0.025;

/// Quanto della velocita' si sposta per secondo di scarto: 40 ms in ritardo
/// sono il 2,4% in piu', e in mezzo secondo recuperano 12 ms. Un terzo
/// dello scarto a ogni controllo: rientra in qualche secondo senza
/// oscillare.
const double syncGain = 0.6;

/// Lo spostamento massimo di velocita', in frazione: il 3%. Con scaletempo2
/// l'intonazione non cambia, e per qualche secondo il 3% di tempo non lo
/// sente nessuno.
const double syncMaxNudge = 0.03;

/// Quante misure servono per un controllo: una ogni fotogramma del mix
/// (16 ms), e le posizioni di mpv arrivano a scatti. Con meno di otto la
/// mediana non toglie gli scatti, e quel controllo salta.
const int syncMinSamples = 8;

/// Lo scarto di fase fra uscente ed entrante, in secondi veri: positivo se
/// l'entrante e' indietro — la sua cassa arriva dopo quella dell'uscente —
/// e negativo se e' avanti. Nullo nei mix senza battiti in comune.
///
/// [outAt] e [inAt] sono le posizioni nei due brani, in secondi di
/// ciascuno. Il mix comincia su un battere di entrambi (outStart e
/// inStart), quindi la fase di ognuno si conta da li': quanto e' passato
/// dall'ultimo battito, in secondi veri, cioe' diviso per la velocita' a
/// cui suona. Il periodo comune e' il battito piu' corto dei due: col
/// doppio tempo ogni battito dell'uno e' un battito su due dell'altro, e
/// la fase del piu' corto basta. Lo scarto si porta fra meno e piu' mezzo
/// periodo: una cassa 10 ms prima della successiva e' avanti di 10 ms, non
/// indietro di un battito meno 10.
///
/// Contare sulla griglia e non sulla posizione esatta rende la misura
/// indifferente al loop: l'uscente che torna indietro di una battuta (o di
/// un battito, nell'eco) resta nella stessa fase.
double? mixPhaseOffset(
  BeatMixPlan plan, {
  required double outAt,
  required double inAt,
}) {
  final ob = plan.outBeat, ib = plan.inBeat;
  if (!plan.matched || ob == null || ib == null || ob <= 0 || ib <= 0) {
    return null;
  }
  final outWall = ob / plan.outSpeed;
  final inWall = ib / plan.speed;
  final period = outWall < inWall ? outWall : inWall;
  final a = (outAt - plan.outStart) / plan.outSpeed;
  final b = (inAt - plan.inStart) / plan.speed;
  var d = (a - b) % period;
  if (d >= period / 2) d -= period;
  return d;
}

/// Lo spostamento di velocita' per uno scarto di [offset] secondi (vedi
/// [mixPhaseOffset]), in frazione: zero fino a [syncTolerance] compreso,
/// poi [syncGain] per lo scarto, fino a [syncMaxNudge]. Positivo, piu'
/// svelto: l'entrante in ritardo recupera.
double syncNudge(double offset) {
  if (offset.abs() <= syncTolerance) return 0;
  return (offset * syncGain).clamp(-syncMaxNudge, syncMaxNudge).toDouble();
}

/// La mediana di [values], senza toccarli. Zero se vuota.
double medianOf(List<double> values) {
  if (values.isEmpty) return 0;
  final v = [...values]..sort();
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}
