import 'dart:math' as math;
import 'dart:typed_data';

import 'beat_analysis.dart';

/// Come si muovono le macchie in un istante del brano.
///
/// Tutti 0-1. [pulse]: i colpi di cassa e di basso, che le fanno crescere
/// e gonfiare. [snap]: quelli di rullante, charleston e voce, che le
/// deformano in altri punti. [energy]: quanto e' pieno il tratto, che le
/// fa ondeggiare piu' ampie e piu' svelte. E' lo stesso tipo di SpotMusic
/// (design/spot.dart): i record con gli stessi campi sono lo stesso tipo.
typedef SpotBeat = ({double pulse, double snap, double energy});

const SpotBeat noSpotBeat = (pulse: 0, snap: 0, energy: 0);

/// La musica del brano in ascolto tradotta in movimento delle macchie,
/// come un visualizzatore.
///
/// Con l'inviluppo dell'analisi ([BeatGrid.envelope]) le macchie seguono
/// l'audio vero: ogni colpo di cassa o di basso le gonfia di quanto e'
/// forte, anche fuori dalla griglia, e il tratto pieno di rullante,
/// charleston e voce le fa ondeggiare piu' svelte. I numeri si preparano
/// una volta per brano; [at] legge solo due valori e li interpola, perche'
/// gira a ogni fotogramma.
///
/// Senza inviluppo (un brano analizzato da una versione di prima, finche'
/// non si rifa') resta un colpo su ogni battito della griglia, piu' forte
/// sul primo della battuta e dove i bassi sono pieni.
class BeatPulse {
  final BeatGrid grid;

  /// I colpi dei bassi, gia' con la loro coda, a [BeatGrid.envelopeRate].
  final Float32List? _hits;

  /// I colpi sopra i bassi, con la loro coda, alla stessa frequenza.
  final Float32List? _snaps;

  /// Quanto e' pieno il tratto, gia' lisciato, alla stessa frequenza.
  final Float32List? _energy;

  /// Il livello dei bassi del tratto piu' pieno del brano, in dB, per la
  /// griglia senza inviluppo.
  final double _lowTop;

  /// La griglia del finale, fatta una volta sola: [at] gira a ogni
  /// fotogramma.
  final BeatGrid _outro;

  BeatPulse._(this.grid, this._hits, this._snaps, this._energy)
    : _lowTop = _top(grid),
      _outro = grid.outro;

  factory BeatPulse(BeatGrid grid, {List<double>? envelope}) {
    final env = envelope ?? grid.envelope;
    const dims = BeatGrid.envelopeDims;
    if (env.length < dims * 30) return BeatPulse._(grid, null, null, null);
    final (hits, snaps, energy) = _prepare(env, grid);
    return BeatPulse._(grid, hits, snaps, energy);
  }

  /// True se le macchie seguono l'audio e non solo la griglia.
  bool get followsAudio => _hits != null;

  /// Sotto questa fiducia la griglia non e' affidabile, e una macchia
  /// fuori tempo sembra un difetto: senza inviluppo, meglio che respiri e
  /// basta.
  static const double minConfidence = 0.3;

  /// Quanto dura la coda di un colpo: dopo questo tempo e' scesa a un
  /// terzo circa.
  static const double decay = 0.12;

  /// Il colpo arriva un attimo prima di quanto dice il player: la
  /// posizione e' quella che il decoder ha gia' passato all'uscita audio,
  /// e il suono esce dalle casse un po' dopo.
  static const double lead = 0.04;

  /// Quanto ci mette un colpo sulla griglia ad arrivare al massimo.
  static const double attack = 0.025;

  /// Le macchie all'istante [t] del brano, in secondi.
  SpotBeat at(double t) {
    if (t < grid.musicStart || t > grid.musicEnd) return noSpotBeat;
    final hits = _hits;
    if (hits != null) {
      final p = (t + lead) * BeatGrid.envelopeRate;
      return (
        pulse: _lerp(hits, p),
        snap: _lerp(_snaps!, p),
        energy: _lerp(_energy!, p),
      );
    }
    // Sulla griglia sola: i colpi sui battiti, e un po' di energia dove i
    // bassi sono pieni, perche' anche li' il ritornello si muova di piu'.
    return (pulse: _onGrid(t), snap: 0, energy: 0.5 * _strength(t));
  }

  static double _lerp(Float32List x, double p) {
    if (p <= 0) return x.first;
    if (p >= x.length - 1) return x.last;
    final i = p.floor();
    final k = p - i;
    return x[i] * (1 - k) + x[i + 1] * k;
  }

  /// I colpi e l'energia dall'inviluppo.
  ///
  /// Un colpo e' quanto salgono i bassi rispetto al punto piu' basso
  /// dell'ultimo quinto di secondo: una linea di basso tenuta non gonfia
  /// la macchia e la lascia li', la gonfia ogni nota che attacca. Poi la
  /// coda, che scende in [decay] e si riprende al colpo dopo. A questo si
  /// somma un poco del livello, perche' un tratto coi bassi pieni stia un
  /// filo piu' gonfio di uno vuoto. L'energia sale in fretta e scende piano,
  /// in un secondo: la velocita' che cambia a ogni colpo sarebbe un
  /// tremolio.
  ///
  /// I colpi sopra i bassi allo stesso modo, ma con una coda piu' corta e
  /// una soglia piu' bassa: un charleston sale di pochi dB, e dura meno di
  /// una cassa.
  static (Float32List, Float32List, Float32List) _prepare(
    List<double> env,
    BeatGrid g,
  ) {
    const dims = BeatGrid.envelopeDims;
    const rate = BeatGrid.envelopeRate;
    final n = env.length ~/ dims;
    final low = [for (var i = 0; i < n; i++) env[i * dims]];
    final air = [for (var i = 0; i < n; i++) env[i * dims + 1]];
    // I riferimenti dal tratto con la musica: il silenzio prima e dopo
    // abbasserebbe tutto.
    final a = (g.musicStart * rate).floor().clamp(0, n - 1);
    final b = (g.musicEnd * rate).ceil().clamp(a + 1, n);
    final lowTop = _percentile(low.sublist(a, b), 0.97);
    final airTop = _percentile(air.sublist(a, b), 0.95);
    final airFloor = _percentile(air.sublist(a, b), 0.2);
    final airSpan = math.max(airTop - airFloor, 3.0);

    final hits = Float32List(n);
    final snaps = Float32List(n);
    final energy = Float32List(n);
    final tail = math.exp(-1 / rate / decay);
    final snapTail = math.exp(-1 / rate / 0.08);
    final ease = math.exp(-1 / rate / 1.0);
    const window = 6; // un quinto di secondo
    var held = 0.0, snapHeld = 0.0, e = 0.0;
    for (var i = 0; i < n; i++) {
      var floor = low[i], airMin = air[i];
      for (var j = math.max(0, i - window); j < i; j++) {
        if (low[j] < floor) floor = low[j];
        if (air[j] < airMin) airMin = air[j];
      }
      // Nove dB di salita sono un colpo pieno; e conta di piu' un colpo
      // forte che uno sottovoce: per la sua altezza rispetto al massimo.
      final loud = ((low[i] - (lowTop - 30)) / 30).clamp(0.0, 1.0);
      final kick = ((low[i] - floor) / 9).clamp(0.0, 1.0) * math.sqrt(loud);
      held = math.max(kick, held * tail);
      hits[i] = (0.85 * held + 0.15 * loud * loud).clamp(0.0, 1.0);
      final level = ((air[i] - airFloor) / airSpan).clamp(0.0, 1.0);
      final tick = ((air[i] - airMin) / 6).clamp(0.0, 1.0) * level;
      snapHeld = math.max(tick, snapHeld * snapTail);
      snaps[i] = snapHeld;
      e = level > e ? e + (level - e) * 0.35 : e * ease + level * (1 - ease);
      energy[i] = e;
    }
    return (hits, snaps, energy);
  }

  static double _percentile(List<double> v, double q) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[((s.length - 1) * q).round()];
  }

  /// Un colpo su ogni battito della griglia, per i brani senza inviluppo.
  double _onGrid(double t) {
    if (grid.confidence < minConfidence || grid.bpm <= 0) return 0;
    // Nella seconda meta' la griglia del finale: una sola, su tre minuti,
    // finisce mezzo battito fuori (vedi BeatGrid.ending).
    final g = t > (grid.musicStart + grid.musicEnd) / 2 ? _outro : grid;
    if (g.confidence < minConfidence) return 0;
    final beat = g.beatLength;
    final x = (t + lead - g.firstBeat) / beat;
    final n = x.floor();
    final since = (x - n) * beat;
    // Sale in [attack] e poi si spegne: a gradino, da fermo al massimo in
    // un fotogramma, sembrava uno scatto e non un colpo.
    final hit = since < attack
        ? since / attack
        : math.exp(-(since - attack) / decay);
    final accent = (n - g.downbeat) % 4 == 0 ? 1.0 : 0.62;
    return hit * accent * _strength(t);
  }

  /// Quanto e' pieno di bassi il brano attorno a [t], 0-1.
  double _strength(double t) {
    final low = _lowAt(t);
    if (low == null) return 0.7;
    // Venti dB sotto il tratto piu' pieno e' gia' silenzio, per i bassi;
    // un minimo resta, perche' anche una strofa senza cassa ha un tempo.
    return (0.2 + 0.8 * ((low - (_lowTop - 20)) / 20)).clamp(0.2, 1.0);
  }

  double? _lowAt(double t) {
    final f = grid.features;
    const dims = BeatGrid.featureDims;
    final frames = f.length ~/ dims;
    if (frames > 1) {
      // Fra due fotogrammi in linea retta: a due al secondo, a scalini la
      // forza cambierebbe di colpo a meta' battuta.
      final p = (t * BeatGrid.featureRate).clamp(0.0, frames - 1.0);
      final i = p.floor().clamp(0, frames - 2);
      final k = p - i;
      return f[i * dims] * (1 - k) + f[(i + 1) * dims] * k;
    }
    final e = grid.energy;
    if (e.isEmpty) return null;
    return e[t.floor().clamp(0, e.length - 1)];
  }

  static double _top(BeatGrid g) {
    final f = g.features;
    const dims = BeatGrid.featureDims;
    final lows = f.length >= dims
        ? [for (var i = 0; i + dims <= f.length; i += dims) f[i]]
        : g.energy;
    // Il 95° percentile e non il massimo: un colpo isolato non deve far
    // sembrare vuoto tutto il resto.
    return _percentile(lows, 0.95);
  }
}
