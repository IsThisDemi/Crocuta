import 'dart:math' as math;

import '../models/lyrics.dart';
import 'beat_analysis.dart';
import 'key_analysis.dart';
import 'phrase_analysis.dart';

/// Dove finisce la voce: l'ultimo verso con del testo, piu' il tempo di
/// cantarlo. Nullo senza un testo sincronizzato.
Duration? vocalsEndOf(Lyrics? lyrics) {
  if (lyrics == null) return null;
  for (final line in lyrics.lines.reversed) {
    if (line.text.trim().isEmpty) continue;
    return line.time + const Duration(seconds: 4);
  }
  return null;
}

/// Dove comincia la voce: il primo verso con del testo. Nullo senza un
/// testo sincronizzato, o se il primo verso sta nei primi istanti — un
/// testo che parte da zero di solito e' solo sfasato.
Duration? vocalsStartOf(Lyrics? lyrics) {
  if (lyrics == null) return null;
  for (final line in lyrics.lines) {
    if (line.text.trim().isEmpty) continue;
    return line.time > const Duration(milliseconds: 500) ? line.time : null;
  }
  return null;
}

/// Lo stato di un player durante un mix, a meta' corsa [t] (0-1): il suo
/// volume (0-1), il guadagno delle tre bande in dB, i due filtri e quanta
/// eco a tempo.
///
/// Tutto solo verso il basso: il volume non supera 1, le bande non
/// superano lo zero, i filtri tolgono e l'eco prende il posto del suono
/// asciutto invece di sommarsi (vedi applyTempoEcho in stem_mix.dart). E'
/// la regola che ha tolto l'"earrape" all'ingresso del secondo brano: in un
/// mix niente sale mai.
///
/// Era un record di quattro numeri; con filtri ed eco una classe con i
/// valori neutri gia' scritti, cosi' ogni stile dice solo cosa muove.
class MixStage {
  final double volume;
  final double low;
  final double mid;
  final double high;

  /// La frequenza del passa-alto, in Hz: fino a [highpassOff] e' spento.
  final double highpass;

  /// La frequenza del passa-basso, in Hz: da [lowpassOpen] in su e' spento.
  final double lowpass;

  /// Quanta eco a tempo sull'uscente, 0-1: a 1 il suono asciutto e' sparito
  /// e resta solo la coda delle ripetizioni. Vive nel tratto separato
  /// dell'uscente, calcolato prima del mix: libmpv non ha filtri d'eco.
  final double echo;

  const MixStage({
    required this.volume,
    this.low = 0,
    this.mid = 0,
    this.high = 0,
    this.highpass = 0,
    this.lowpass = lowpassOpen,
    this.echo = 0,
  });

  /// Un brano che suona come e', fuori da un mix.
  static const flat = MixStage(volume: 1);

  @override
  bool operator ==(Object other) =>
      other is MixStage &&
      other.volume == volume &&
      other.low == low &&
      other.mid == mid &&
      other.high == high &&
      other.highpass == highpass &&
      other.lowpass == lowpass &&
      other.echo == echo;

  @override
  int get hashCode =>
      Object.hash(volume, low, mid, high, highpass, lowpass, echo);

  @override
  String toString() =>
      'MixStage(vol ${volume.toStringAsFixed(2)}, '
      '${low.toStringAsFixed(1)}/${mid.toStringAsFixed(1)}/'
      '${high.toStringAsFixed(1)} dB, hp ${highpass.round()}, '
      'lp ${lowpass.round()}, eco ${echo.toStringAsFixed(2)})';
}

/// Quanto si tagliano bassi, medi e acuti quando una banda "esce".
const double lowCutDb = -26;
const double midCutDb = -12;
const double highCutDb = -12;

/// Sotto questa frequenza il passa-alto e' spento: a 20 Hz non toglie
/// niente che si senta.
const double highpassOff = 20;

/// Da questa frequenza in su il passa-basso e' spento: il brano e' aperto.
const double lowpassOpen = 16000;

double _smooth(double t, double from, double to) {
  final x = ((t - from) / (to - from)).clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// Una frequenza che va da [from] a [to] in modo esponenziale, come si
/// sente una sweep: ogni ottava prende lo stesso tempo.
double _sweep(double x, double from, double to) =>
    from * math.pow(to / from, x.clamp(0.0, 1.0)).toDouble();

/// Il passaggio da un brano all'altro, a tappe, come lo fa un DJ con le
/// tre manopole dell'EQ.
///
/// L'entrante arriva in fretta ma senza bassi e con i medi bassi: si
/// sentono i suoi acuti, il charleston, sopra l'uscente pieno. Poi i medi
/// si scambiano (35-55%), poi i bassi (55-70%), in una battuta o due e non
/// in un battito: una sola cassa per volta, sempre, ma senza il colpo
/// secco che si nota. Solo allora l'uscente scende, gia' senza bassi ne'
/// medi, e i suoi acuti sfumano per ultimi.
///
/// Era uno scambio secco dei bassi in un battito, e poi l'uscente che si
/// assottigliava fino a 800 Hz: una mossa da DJ, che proprio per questo si
/// sentiva. Apple fa sparire la transizione, e cosi' si fa sparire.
MixStage blendStage(double t, {required bool incoming}) {
  final mids = _smooth(t, 0.35, 0.55);
  final lows = _smooth(t, 0.55, 0.70);
  if (incoming) {
    return MixStage(
      volume: math.sin(_smooth(t, 0, 0.3) * math.pi / 2),
      low: lowCutDb * (1 - lows),
      mid: midCutDb * (1 - mids),
    );
  }
  return MixStage(
    volume: math.cos(_smooth(t, 0.65, 1) * math.pi / 2),
    low: lowCutDb * lows,
    mid: midCutDb * mids,
    high: highCutDb * _smooth(t, 0.5, 0.9),
  );
}

/// Il blend lungo, da 16 a 32 battute: per due brani che stanno bene
/// insieme — tempi quasi uguali, tonalita' vicine — e un uscente che esce
/// da un outro calmo. E' il "rolling" dei DJ: per mezzo minuto o piu' i due
/// brani suonano davvero insieme, l'entrante che cresce piano sotto l'outro.
///
/// Rispetto a [blendStage] tutto e' piu' disteso: l'entrante impiega il
/// 40% del mix a salire, coi suoi acuti appena smorzati all'inizio; i medi
/// si scambiano fra il 25 e il 50%, i bassi fra il 45 e il 60% — su 32
/// battute sono cinque battute, uno scambio che non si sente arrivare —
/// e l'uscente sfuma solo nell'ultimo 40%.
///
/// Era la curva del rolling prima di [learnedStage]: resta qui per
/// tornarci con una riga in [BeatMixPlan.stage], se all'ascolto le curve
/// dai DJ non convincono.
MixStage rollingStage(double t, {required bool incoming}) {
  final lows = _smooth(t, 0.45, 0.6);
  if (incoming) {
    return MixStage(
      volume: math.sin(_smooth(t, 0, 0.4) * math.pi / 2),
      low: lowCutDb * (1 - lows),
      mid: midCutDb * (1 - _smooth(t, 0.25, 0.5)),
      high: highCutDb * 0.5 * (1 - _smooth(t, 0, 0.3)),
    );
  }
  return MixStage(
    volume: math.cos(_smooth(t, 0.6, 1) * math.pi / 2),
    low: lowCutDb * lows,
    mid: midCutDb * _smooth(t, 0.4, 0.7),
    high: highCutDb * _smooth(t, 0.55, 0.95),
  );
}

/// Il rolling con le curve dai DJ: i tempi mediani che DJtransGAN genera su
/// 516 transizioni (Chen et al., "Automatic DJ Transitions with
/// Differentiable Audio Effects and Generative Adversarial Networks",
/// ICASSP 2022), senza la rete. Le dissolvenze del modello, lineari in
/// ampiezza, qui sono le solite rampe di [_smooth], con lo stesso inizio e
/// la stessa fine.
///
/// Il modello non ha un volume a parte: le bande sono il volume. Qui il
/// volume del player segue la banda piu' alta, e le altre stanno sotto di
/// lui in dB, fino ai tagli di sempre ([lowCutDb], [midCutDb],
/// [highCutDb]): mai sopra lo zero.
///
/// - L'uscente perde i bassi da subito e piano (-6 dB a 0,41), tiene i medi
///   pieni fino a 0,73 e li lascia entro 0,93; i suoi acuti scendono da
///   0,42 a 0,98, e sono l'ultima cosa che si sente.
/// - L'entrante arriva coi soli acuti (0,15-0,60, -6 dB a 0,38), poi
///   insieme medi (0,61-0,76) e bassi (0,62-0,90, -6 dB a 0,76).
///
/// Due differenze dal modello. I bassi dell'uscente: nel modello scendono
/// in linea fino a 0,79 e a 0,62, quando partono quelli dell'entrante, ne
/// resta un quinto, la somma dei bassi a -13 dB (-18 con le nostre rampe):
/// un buco che si sente come un calo. Qui fanno la prima meta' della
/// discesa come il modello, fino a 0,50 (-6 dB a 0,41), si fermano a -7 dB e
/// se ne vanno in passo coi bassi dell'entrante (0,63-0,76): le due casse
/// s'incrociano a -14 dB l'una, una sola per volta, e la somma non scende
/// sotto -8 dB. E l'aria sopra i 12 kHz, che il modello tratta a parte,
/// qui va con gli acuti: il nostro scaffale parte da 5 kHz e non le separa.
/// Le bande dell'entrante prima del loro ingresso, poi, non sono zero ma
/// i tagli di sempre: un -12 dB sui medi e' quanto tolgono le manopole.
MixStage learnedStage(double t, {required bool incoming}) {
  // Le ampiezze di ogni banda, 0-1, come il modello le genera.
  final double low, mid, high;
  if (incoming) {
    low = _smooth(t, 0.62, 0.90);
    mid = _smooth(t, 0.61, 0.76);
    high = _smooth(t, 0.15, 0.60);
  } else {
    low = 1 - 0.55 * _smooth(t, 0.02, 0.50) - 0.45 * _smooth(t, 0.63, 0.76);
    mid = 1 - _smooth(t, 0.73, 0.93);
    high = 1 - _smooth(t, 0.42, 0.98);
  }
  final volume = math.max(low, math.max(mid, high));
  // Una banda in dB sotto il volume, fra il taglio e lo zero. Una banda
  // spenta, o tutto a volume zero, sta al taglio. Anche un'ampiezza appena
  // sotto lo zero, che e' solo l'arrotondamento di 1 - 0,55 - 0,45: il
  // logaritmo darebbe NaN.
  double below(double a, double cut) => a <= 0 || volume <= 0
      ? cut
      : (20 * math.log(a / volume) / math.ln10).clamp(cut, 0.0).toDouble();
  return MixStage(
    volume: volume,
    low: below(low, lowCutDb),
    mid: below(mid, midCutDb),
    high: below(high, highCutDb),
  );
}

/// Il cambio sul drop: l'entrante fa sentire la fine della sua intro sopra
/// l'uscente pieno — senza bassi, coi medi bassi — e sull'"1" del suo drop,
/// che cade sull'"1" di una frase dell'uscente, i bassi si scambiano in un
/// battito. Da li' l'uscente, gia' senza bassi, perde medi e acuti e sparisce
/// in un paio di battute.
///
/// [swapAt] e' dove cade il drop, in frazione del mix; [swapWidth] meta'
/// della durata dello scambio, mezzo battito: e' il gesto secco del DJ, ma
/// non un taglio, che sulla cassa schiocca.
MixStage dropSwapStage(
  double t, {
  required bool incoming,
  double swapAt = 0.8,
  double swapWidth = 0.02,
}) {
  final swap = _smooth(t, swapAt - swapWidth, swapAt + swapWidth);
  if (incoming) {
    return MixStage(
      volume: math.sin(_smooth(t, 0, 0.5 * swapAt) * math.pi / 2),
      low: lowCutDb * (1 - swap),
      mid: -6 * (1 - _smooth(t, 0.3 * swapAt, swapAt)),
    );
  }
  final tail = (1 - swapAt).clamp(0.01, 1.0);
  return MixStage(
    volume: math.cos(_smooth(t, swapAt, 1) * math.pi / 2),
    low: lowCutDb * swap,
    mid: midCutDb * _smooth(t, swapAt, swapAt + 0.5 * tail),
    high: highCutDb * _smooth(t, swapAt, 1),
  );
}

/// La frequenza a cui arriva il passa-alto dell'uscente nella salita col
/// filtro: a 2,5 kHz resta il fruscio dei piatti, che poi va in eco.
const double buildHighpassTop = 2500;

/// La frequenza da cui parte il passa-basso dell'entrante: a 300 Hz se ne
/// sente il colpo e l'ombra, "da sott'acqua".
const double buildLowpassFrom = 300;

/// La salita col filtro: l'uscente si assottiglia con un passa-alto che
/// sale da 20 Hz a [buildHighpassTop] — la tensione di un build — e alla
/// fine si lancia in eco, mentre l'entrante cresce sotto un passa-basso che
/// si apre da [buildLowpassFrom] fino al brano intero.
///
/// Per due brani che non si accordano in un blend pulito: un uscente che
/// arriva in fondo ancora pieno e un entrante che parte pieno, o due
/// tonalita' che stridono. I filtri tengono i due brani in bande diverse
/// per tutto il mix: si sentono insieme, ma non si scontrano. I bassi si
/// passano a meta' (50-62%), quando il passa-alto dell'uscente e' gia'
/// sopra i 150 Hz: una sola cassa per volta anche qui.
MixStage filterBuildStage(double t, {required bool incoming}) {
  final lows = _smooth(t, 0.5, 0.62);
  if (incoming) {
    return MixStage(
      volume: math.sin(_smooth(t, 0, 0.35) * math.pi / 2),
      low: lowCutDb * (1 - lows),
      lowpass: _sweep(_smooth(t, 0.05, 0.9), buildLowpassFrom, lowpassOpen),
    );
  }
  return MixStage(
    volume: math.cos(_smooth(t, 0.65, 1) * math.pi / 2),
    low: lowCutDb * lows,
    highpass: _sweep(_smooth(t, 0.05, 0.85), highpassOff, buildHighpassTop),
    echo: _smooth(t, 0.55, 0.8),
  );
}

/// La dissolvenza semplice, corta: per due brani che non si possono
/// mettere a tempo e che non ne hanno bisogno, perche' l'uscente finisce gia'
/// sfumando o l'entrante comincia piano, senza batteria. Non e' un ripiego:
/// e' lo stile giusto quando una transizione costruita si sentirebbe piu'
/// della dissolvenza — Apple a volte fa proprio questo. Potenza costante:
/// a meta' i due brani sono a -3 dB ciascuno.
MixStage fadeStage(double t, {required bool incoming}) => MixStage(
  volume: incoming ? math.sin(t * math.pi / 2) : math.cos(t * math.pi / 2),
);

/// Quanto dura la dissolvenza semplice, in secondi.
const double fadeLength = 4;

/// L'uscita in eco: quando la voce dell'entrante arriva subito e non c'e'
/// spazio per una transizione vera. L'uscente ripete il suo ultimo battito
/// sempre piu' piano e sempre piu' sottile — come il "loop roll" di un DJ,
/// un'eco a tempo — mentre l'entrante parte pulito sul battere. Sopra il
/// loop, un'eco di tre quarti di battito che prende il posto del suono
/// asciutto: la coda continua a ripetere mentre il volume scende.
MixStage echoStage(double t, {required bool incoming}) {
  if (incoming) {
    return MixStage(
      volume: math.sin(_smooth(t, 0, 0.15) * math.pi / 2),
      low: lowCutDb * (1 - _smooth(t, 0.1, 0.35)),
    );
  }
  return MixStage(
    volume: math.pow(1 - t, 2).toDouble(),
    low: lowCutDb * _smooth(t, 0, 0.25),
    mid: midCutDb * _smooth(t, 0.2, 0.7),
    high: highCutDb * _smooth(t, 0.3, 1),
    echo: _smooth(t, 0.05, 0.45),
  );
}

/// La transizione filtrata, per due brani i cui battiti non si possono far
/// coincidere: tempi troppo lontani, o una griglia di cui non ci si fida.
///
/// Come i preset di Spotify Mix e come fa Apple quando non puo' mettere a
/// tempo: i due brani suonano insieme per una decina di secondi, ma la
/// batteria ce l'ha sempre uno solo. L'entrante sale "da sott'acqua" —
/// senza bassi, acuti chiusi — mentre l'uscente suona pieno; a [cutDrop]
/// i bassi si scambiano sul battere dell'entrante, l'uscente chiude in eco
/// (vedi renderEchoOut) e l'entrante si apre. Prima era un cambio di
/// quattro secondi: corretto, ma non si sentiva come una transizione.
MixStage cutStage(double t, {required bool incoming}) {
  final swap = _smooth(t, cutDrop - 0.03, cutDrop + 0.03);
  if (incoming) {
    return MixStage(
      volume: math.sin(_smooth(t, 0, 0.35) * math.pi / 2),
      low: lowCutDb * (1 - swap),
      mid: -8 * (1 - _smooth(t, 0.1, cutDrop)),
      high: highCutDb * (1 - _smooth(t, cutDrop, 0.85)),
    );
  }
  return MixStage(
    volume: math.cos(_smooth(t, cutDrop, 1) * math.pi / 2),
    low: lowCutDb * swap,
    mid: midCutDb * _smooth(t, cutDrop - 0.1, cutDrop + 0.1),
    high: highCutDb * 0.5 * _smooth(t, cutDrop, 1),
  );
}

/// Come si regola un passa-alto a [cutoff] Hz in libmpv: la frequenza, e
/// quanto del suono filtrato si sente (il `mix` dei filtri di ffmpeg).
///
/// Spento vuol dire mix a zero: il filtro c'e' sempre nella catena, ma il
/// suono esce identico a com'entra, cosi' fuori da un mix la catena non
/// cambia niente e durante il mix basta un comando per muoverlo. Fra 20 e
/// 40 Hz il mix sale da 0 a 1: a quelle frequenze il filtro non si sente,
/// e accenderlo di colpo non fa scalini.
({double f, double mix}) highpassSetting(double cutoff) {
  if (cutoff <= highpassOff) return (f: highpassOff, mix: 0);
  final mix = (math.log(cutoff / highpassOff) / math.ln2).clamp(0.0, 1.0);
  return (f: cutoff, mix: mix);
}

/// Il passa-basso piu' alto che si chiede a libmpv: sopra, con un brano a
/// 32 kHz, si andrebbe oltre la meta' della frequenza di campionamento.
const double _lowpassTop = 12000;

/// Come si regola un passa-basso a [cutoff] Hz: fino a 8 kHz filtro pieno,
/// poi, mentre si apre verso [lowpassOpen], il mix scende a zero e il
/// suono asciutto prende il posto di quello filtrato. Un passa-basso a 16
/// kHz toglie ancora un po' d'aria: spegnerlo di colpo li' si sentirebbe.
({double f, double mix}) lowpassSetting(double cutoff) {
  if (cutoff >= lowpassOpen) return (f: _lowpassTop, mix: 0);
  final f = math.min(cutoff, _lowpassTop);
  if (cutoff <= 8000) return (f: f, mix: 1);
  final mix = 1 - math.log(cutoff / 8000) / math.log(lowpassOpen / 8000);
  return (f: f, mix: mix.clamp(0.0, 1.0));
}

String _hz(double f) => f.round().toString();
String _mix(double m) => m.toStringAsFixed(3);

/// I filtri di AutoMix nella catena di un player, regolati su [s].
///
/// Sempre presenti quando AutoMix e' acceso, e con [MixStage.flat] tutti
/// neutri — bande a zero, filtri col mix a zero — cosi' il mix li muove con
/// `af-command` senza ricostruire la catena, che ricostruita fa uno scatto.
/// Le etichette `@lo` `@mid` `@hi` `@hp` `@lp` sono quelle a cui i comandi
/// si rivolgono. Solo filtri che il libmpv ricompilato ha davvero (vedi
/// tool/libmpv/crocuta-filters.patch): con uno mancante la catena viene
/// rifiutata e il brano non suona.
List<String> mixFilterChain(MixStage s) {
  final hp = highpassSetting(s.highpass);
  final lp = lowpassSetting(s.lowpass);
  return [
    '@lo:lavfi=[bass=f=120:g=${s.low.toStringAsFixed(1)}]',
    '@mid:lavfi=[equalizer=f=1000:t=o:w=2:g=${s.mid.toStringAsFixed(1)}]',
    '@hi:lavfi=[treble=f=5000:g=${s.high.toStringAsFixed(1)}]',
    '@hp:lavfi=[highpass=f=${_hz(hp.f)}:mix=${_mix(hp.mix)}]',
    '@lp:lavfi=[lowpass=f=${_hz(lp.f)}:mix=${_mix(lp.mix)}]',
  ];
}

/// Come sono regolati davvero i filtri di AutoMix in un player: quello che
/// la catena o l'ultimo comando gli hanno detto. Puo' restare indietro di
/// un soffio rispetto alla curva del mix, perche' i passi troppo piccoli
/// non si mandano.
class MixFilterState {
  final double low, mid, high;
  final double hpF, hpMix, lpF, lpMix;

  const MixFilterState({
    required this.low,
    required this.mid,
    required this.high,
    required this.hpF,
    required this.hpMix,
    required this.lpF,
    required this.lpMix,
  });

  factory MixFilterState.of(MixStage s) {
    final hp = highpassSetting(s.highpass);
    final lp = lowpassSetting(s.lowpass);
    return MixFilterState(
      low: s.low,
      mid: s.mid,
      high: s.high,
      hpF: hp.f,
      hpMix: hp.mix,
      lpF: lp.f,
      lpMix: lp.mix,
    );
  }
}

/// I comandi `af-command` per portare i filtri di un player da [applied] a
/// [now], e come saranno dopo.
///
/// Solo quello che si e' spostato abbastanza da sentirsi — un quarto di
/// decibel, il 2% di frequenza, due centesimi di mix — o che arriva al
/// valore neutro, che va raggiunto esatto. Ogni comando in meno e' lavoro
/// in meno per libmpv, che li riceve venticinque volte al secondo.
///
/// Il confronto e' con l'ultimo valore *mandato*, non con l'ultimo passo
/// della curva: prima era col passo, e in un blend lungo le bande si
/// muovono di un decimo di decibel ogni 40 ms — sempre sotto la soglia,
/// mai mandate, e i bassi dell'uscente restavano pieni fino alla fine.
///
/// La frequenza prima del mix: un filtro che si accende parte gia' dalla
/// frequenza giusta.
({List<List<String>> commands, MixFilterState applied}) mixFilterCommands(
  MixFilterState applied,
  MixStage now,
) {
  final want = MixFilterState.of(now);
  final out = <List<String>>[];
  double band(String label, double a, double b) {
    if (a == b) return a;
    if ((a - b).abs() < 0.25 && b != 0) return a;
    out.add(['af-command', label, 'g', b.toStringAsFixed(1)]);
    return b;
  }

  double freq(String label, double a, double b, {required bool atRest}) {
    if (a == b) return a;
    if ((a - b).abs() / a < 0.02 && !atRest) return a;
    out.add(['af-command', label, 'f', _hz(b)]);
    return b;
  }

  double mix(String label, double a, double b) {
    if (a == b) return a;
    if ((a - b).abs() < 0.02 && b != 0 && b != 1) return a;
    out.add(['af-command', label, 'mix', _mix(b)]);
    return b;
  }

  final low = band('lo', applied.low, want.low);
  final mid = band('mid', applied.mid, want.mid);
  final high = band('hi', applied.high, want.high);
  final hpF = freq('hp', applied.hpF, want.hpF, atRest: want.hpMix == 0);
  final hpMix = mix('hp', applied.hpMix, want.hpMix);
  final lpF = freq('lp', applied.lpF, want.lpF, atRest: want.lpMix == 0);
  final lpMix = mix('lp', applied.lpMix, want.lpMix);
  return (
    commands: out,
    applied: MixFilterState(
      low: low,
      mid: mid,
      high: high,
      hpF: hpF,
      hpMix: hpMix,
      lpF: lpF,
      lpMix: lpMix,
    ),
  );
}

/// Quanto dura di solito la transizione filtrata, in secondi: la durata
/// vera si aggiusta perche' lo scambio cada su un battere dell'entrante.
const double cutLength = 8;

/// A che punto della transizione filtrata si scambiano i bassi.
const double cutDrop = 0.55;

/// Il tipo di transizione, scelto per ogni coppia di brani: vedi
/// [chooseMixStyle].
enum MixKind {
  /// Sedici battute a tappe: brani con tempi quasi uguali e battiti sicuri.
  blend,

  /// Otto battute (o quattro): si accordano, ma con meno margine.
  quick,

  /// Il blend lungo, 16-32 battute, su un outro calmo, con le curve dai DJ:
  /// vedi [learnedStage].
  rolling,

  /// Il cambio sul drop dell'entrante: vedi [dropSwapStage].
  dropSwap,

  /// La salita col filtro e l'eco: vedi [filterBuildStage].
  filterBuild,

  /// Due battute in eco: la voce dell'entrante arriva subito.
  echo,

  /// Senza battiti in comune, filtrata e con l'eco d'uscita: [cutStage].
  cut,

  /// Senza battiti in comune, una dissolvenza corta: [fadeStage].
  fade,
}

/// Cosa fare con voce e base dell'uscente, quando sono separate.
///
/// I tempi sono in secondi dall'inizio del mix. E' la parte che il mix
/// intero non poteva fare: toccare la voce senza toccare la musica.
class StemPlan {
  /// Da qui la voce dell'uscente e' gia' spenta: un battito prima che
  /// canti l'entrante. Infinito se le voci non si incontrano.
  final double duckAt;

  /// L'inizio della battuta in cui l'uscente canta per l'ultima volta:
  /// quella battuta di sola voce si ripete in eco sopra la musica.
  final double? echoFrom;

  /// Quanto dura la battuta dell'eco.
  final double echoLength;

  /// Quante volte si ripete, sempre piu' piano.
  final int echoRepeats;

  /// Il passaggio di voce: a quest'istante l'uscente ha finito la sua riga
  /// e la voce passa all'entrante, che fin qui e' entrato con la sola base.
  /// Nullo se le voci non si incontrano o se non c'e' una riga che finisca
  /// in tempo.
  final double? exchangeAt;

  /// Fin dove la voce dell'uscente puo' restare accesa, al massimo: il
  /// [duckAt] piu' tardo che il piano accetta quando l'attesa della pausa
  /// (vedi vocal_pause.dart) lo sposta. Nullo vuol dire [duckAt] stesso:
  /// quando la voce si spegne perche' sta per cantare l'entrante, spegnerla
  /// dopo vorrebbe dire due voci insieme, e si puo' solo anticipare. Nel
  /// passaggio di voce invece l'entrante resta muto finche' non tocca a lui,
  /// e il passaggio puo' scivolare fin dove lo accetta il piano: due battute
  /// dopo che l'entrante avrebbe cominciato, e una battuta prima della fine.
  final double? latestDuck;

  const StemPlan({
    this.duckAt = double.infinity,
    this.echoFrom,
    this.echoLength = 0,
    this.echoRepeats = 0,
    this.exchangeAt,
    this.latestDuck,
  });

  /// Dove la voce dell'uscente comincia a spegnersi: [duckFade] prima di
  /// [duckAt], e nel passaggio di voce meta' incrocio prima del passaggio.
  /// Nullo se la voce non si spegne mai.
  double? get handoverStart => duckAt.isFinite ? duckAt - duckFade : null;

  /// Il punto piu' tardo in cui puo' cominciare lo spegnimento.
  double get latestHandoverStart => (latestDuck ?? duckAt) - duckFade;

  /// Lo stesso piano con la voce che comincia a spegnersi a [start]: lo
  /// spegnimento, e il passaggio all'entrante se c'e', spostati insieme.
  /// Eco e limite restano quelli.
  StemPlan handoverAt(double start) => StemPlan(
    // Nel passaggio la voce dell'uscente si spegne in tutto l'incrocio,
    // centrato sul passaggio; altrimenti in [duckFade].
    duckAt: start + (exchangeAt == null ? duckFade : exchangeFade),
    echoFrom: echoFrom,
    echoLength: echoLength,
    echoRepeats: echoRepeats,
    exchangeAt: exchangeAt == null ? null : start + exchangeFade / 2,
    latestDuck: latestDuck,
  );

  /// Quanto dura il passaggio di voce: le due voci si incrociano per mezzo
  /// secondo, centrato sulla fine della riga.
  static const exchangeFade = 0.5;

  /// Il volume della voce dell'entrante all'istante [t] del mix: zero fino
  /// al passaggio, poi piena. Senza passaggio, sempre piena.
  double incomingVoice(double t) {
    final at = exchangeAt;
    if (at == null) return 1;
    return ((t - (at - exchangeFade / 2)) / exchangeFade).clamp(0.0, 1.0);
  }

  /// Il volume della ripetizione [k] (da 1): ogni volta un po' piu' lontana.
  static double echoGain(int k) => math.pow(0.55, k).toDouble();

  /// Quanto dura lo spegnimento della voce: un battito, abbastanza per non
  /// sentire un taglio e abbastanza poco per non sovrapporsi all'entrante.
  static const duckFade = 0.5;
}

/// Un mix a tempo: dove esce il brano che suona, dove entra il successivo,
/// quante battute dura, a che velocita' va l'entrante e se l'uscente deve
/// ripetere un tratto per arrivarci.
class BeatMixPlan {
  final MixKind kind;

  /// Da dove, nel brano uscente, parte il mix: un battere di battuta.
  final double outStart;

  /// Da dove parte il brano entrante: il suo primo battere dopo il
  /// silenzio iniziale.
  final double inStart;

  /// Quante battute del brano uscente dura il mix.
  final int bars;

  /// La durata del mix, in secondi del brano uscente.
  final double length;

  /// A che velocita' suona l'entrante durante il mix, perche' i battiti
  /// coincidano.
  final double speed;

  /// A che velocita' suona l'uscente durante il mix: 1, tranne quando i
  /// tempi sono troppo lontani perche' si muova il solo entrante. Allora si
  /// incontrano a meta' strada, e l'uscente ci arriva piano nelle battute
  /// prima del mix.
  final double outSpeed;

  /// Il tratto dell'uscente da ripetere a tempo, se serve: l'ultima
  /// battuta quando il mix va oltre la musica, l'ultimo battito nell'eco.
  final double? loopStart;
  final double? loopEnd;

  /// Il volume dei due brani nei tratti che si sovrappongono, in dB. Il
  /// player li confronta e corregge l'entrante della differenza.
  final double? outLevel;
  final double? inLevel;

  /// Cosa fare con voce e base separate. Nullo senza separazione: allora
  /// il mix e' quello di sempre, sui brani interi.
  final StemPlan? stems;

  /// Nel cambio secco, quanto dura un battito dell'uscente: il passo della
  /// sua eco d'uscita. Nullo negli altri mix.
  final double? echoBeat;

  /// Se i battiti dei due brani coincidono. Falso quando i tempi non si
  /// accordano: il mix e' corto e l'entrante resta alla sua velocita'.
  final bool matched;

  /// Nel cambio sul drop, dove cade il drop dell'entrante, in frazione del
  /// mix, e meta' della durata dello scambio dei bassi.
  final double swapAt;
  final double swapWidth;

  /// Il passo dell'eco a tempo sull'uscente, in secondi del brano uscente:
  /// tre quarti di battito nell'uscita in eco, mezzo nella salita col
  /// filtro. Nullo negli stili senza eco.
  final double? echoDelay;

  /// Di quanti semitoni si sposta l'entrante, -1, 0 o +1 (vedi
  /// [keyShiftFor]): l'etichetta si mette quando si carica, e resta fino
  /// alla fine del brano. [speed] resta il tempo che si sente; la velocita'
  /// da dare a mpv e' [mpvSpeed].
  final int keyShift;

  /// Le tonalita' e lo spostamento in una riga, per il registro.
  final String keyNote;

  /// Perche' questo stile, in parole: finisce nel registro.
  final String reason;

  /// Frasi e sezioni dei due brani e dove cade il mix, per il registro.
  final String notes;

  /// Quanto dura un battito nelle griglie dei due brani, in secondi di
  /// ciascun brano: quella del finale dell'uscente, quella dell'inizio
  /// dell'entrante. Servono al controllo del tempo durante il mix (vedi
  /// mix_sync.dart), che misura la fase di ognuno sul suo battito. Nulli
  /// nei mix senza battiti in comune: li' non c'e' una fase da tenere.
  final double? outBeat;
  final double? inBeat;

  const BeatMixPlan({
    required this.kind,
    required this.outStart,
    required this.inStart,
    required this.bars,
    required this.length,
    required this.speed,
    this.outSpeed = 1,
    this.loopStart,
    this.loopEnd,
    this.outLevel,
    this.inLevel,
    this.stems,
    this.matched = true,
    this.echoBeat,
    this.swapAt = 0.8,
    this.swapWidth = 0.02,
    this.echoDelay,
    this.keyShift = 0,
    this.keyNote = '',
    this.reason = '',
    this.notes = '',
    this.outBeat,
    this.inBeat,
  });

  /// Lo stesso piano con un altro [StemPlan]: quando la separazione, finita,
  /// sposta il passaggio di voce in una pausa del cantato.
  BeatMixPlan withStems(StemPlan stems) => BeatMixPlan(
    kind: kind,
    outStart: outStart,
    inStart: inStart,
    bars: bars,
    length: length,
    speed: speed,
    outSpeed: outSpeed,
    loopStart: loopStart,
    loopEnd: loopEnd,
    outLevel: outLevel,
    inLevel: inLevel,
    stems: stems,
    matched: matched,
    echoBeat: echoBeat,
    swapAt: swapAt,
    swapWidth: swapWidth,
    echoDelay: echoDelay,
    keyShift: keyShift,
    keyNote: keyNote,
    reason: reason,
    notes: notes,
    outBeat: outBeat,
    inBeat: inBeat,
  );

  bool get loops => loopStart != null;

  /// La velocita' di mpv per l'entrante nel mix: [speed] diviso il rapporto
  /// dello spostamento, che l'etichetta aggiunge da se'.
  double get mpvSpeed => mpvSpeedFor(speed, keyShift);

  /// Quanto dura il mix in secondi veri: [length] e' misurata nel brano
  /// uscente, che puo' suonare a [outSpeed].
  double get wallLength => length / outSpeed;

  /// Quanti secondi del brano entrante suonano in [wall] secondi di mix.
  double incomingSeconds(double wall) => wall * speed;

  MixStage stage(double t, {required bool incoming}) => switch (kind) {
    MixKind.blend || MixKind.quick => blendStage(t, incoming: incoming),
    // Il rolling con le curve dai DJ, da confrontare a orecchio col blend:
    // per tornare alle curve di prima basta [rollingStage].
    MixKind.rolling => learnedStage(t, incoming: incoming),
    MixKind.dropSwap => dropSwapStage(
      t,
      incoming: incoming,
      swapAt: swapAt,
      swapWidth: swapWidth,
    ),
    MixKind.filterBuild => filterBuildStage(t, incoming: incoming),
    MixKind.echo => echoStage(t, incoming: incoming),
    MixKind.cut => cutStage(t, incoming: incoming),
    MixKind.fade => fadeStage(t, incoming: incoming),
  };
}

/// La riga del registro per un piano: `mix: piano <uscente> > <entrante>:`
/// stile, battute, velocita' (e quella di mpv, se l'entrante e' spostato),
/// tempi, tonalita' e spostamento, voce, eco, il perche' e le frasi. E'
/// quella da guardare in crocuta.log quando un mix suona strano.
String describeBeatMix(
  BeatMixPlan plan, {
  required String from,
  required String to,
  required BeatGrid out,
  required BeatGrid incoming,
}) {
  final mpv = plan.keyShift == 0
      ? ''
      : ' (mpv ${plan.mpvSpeed.toStringAsFixed(3)})';
  return 'mix: piano $from > $to: ${plan.kind.name} '
      '${plan.bars} battute da ${plan.outStart.toStringAsFixed(1)} s '
      '(${plan.length.toStringAsFixed(1)} s, velocita\' '
      '${plan.speed.toStringAsFixed(3)}$mpv, uscente '
      '${plan.outSpeed.toStringAsFixed(3)}, a tempo ${plan.matched}, '
      'BPM ${out.bpm.toStringAsFixed(1)} > ${incoming.bpm.toStringAsFixed(1)} '
      'fiducia ${out.confidence.toStringAsFixed(2)}/'
      '${incoming.confidence.toStringAsFixed(2)}, '
      'spostamento ${plan.keyShift > 0 ? '+' : ''}${plan.keyShift} '
      'semitoni, ${plan.keyNote}, '
      'voce spenta a ${plan.stems?.duckAt.toStringAsFixed(1)}, '
      'eco ${plan.stems?.echoFrom?.toStringAsFixed(1)}, '
      'passaggio ${plan.stems?.exchangeAt?.toStringAsFixed(1)}, '
      'eco a tempo ${plan.echoDelay?.toStringAsFixed(3)} s) '
      'perche\' ${plan.reason}; ${plan.notes}';
}

/// La correzione del livello dell'entrante durante il mix, in dB: la
/// differenza fra i due tratti che si sovrappongono, misurata sull'audio.
///
/// Solo verso il basso. Prima arrivava a +4 dB quando l'entrante era piu'
/// piano, ma un master di oggi sta gia' a 0 dBFS: qualunque guadagno
/// positivo lo satura, e la saturazione restava finche' la correzione non
/// tornava a zero, mezzo decibel al secondo — l'entrata a tutto volume che
/// poi "si normalizza". Quando l'entrante e' piu' piano scende invece
/// l'uscente: vedi [mixGains].
///
/// Al massimo 3 dB: con 6, sommati al resto, il mix intero suonava come
/// un calo di volume.
double levelTrimDb({required double outLevel, required double inLevel}) =>
    (outLevel - inLevel).clamp(-3.0, 0.0);

/// Di quanto va abbassato l'uscente quando l'entrante e' piu' piano, in
/// dB positivi: l'altra meta' di [levelTrimDb].
double outgoingCutDb({required double outLevel, required double inLevel}) =>
    (outLevel - inLevel).clamp(0.0, 3.0);

/// Quanta dell'energia di un brano resta con le bande e i filtri di [s],
/// 0-1, in ampiezza. I pesi sono quelli di un master tipico, in potenza:
/// meta' nei bassi, un terzo nei medi, il resto negli acuti. I filtri si
/// contano col loro effetto al centro di ogni banda — 80 Hz, 1 kHz, 6 kHz —
/// come un passa-alto e un passa-basso di Butterworth a due poli, quelli di
/// ffmpeg. L'eco no: prende il posto del suono asciutto senza aggiungere
/// potenza, e contarla piena e' la stima prudente.
double bandEnergy(MixStage s) {
  double g(double db) => math.pow(10, db / 20).toDouble();
  double hp(double f) {
    final m = highpassSetting(s.highpass);
    if (m.mix == 0) return 1;
    final r = math.pow(f / m.f, 2).toDouble();
    return (1 - m.mix) + m.mix * r / math.sqrt(1 + r * r);
  }

  double lp(double f) {
    final m = lowpassSetting(s.lowpass);
    if (m.mix == 0) return 1;
    final r = math.pow(f / m.f, 2).toDouble();
    return (1 - m.mix) + m.mix / math.sqrt(1 + r * r);
  }

  final low = g(s.low) * hp(80) * lp(80);
  final mid = g(s.mid) * hp(1000) * lp(1000);
  final high = g(s.high) * hp(6000) * lp(6000);
  return math.sqrt(0.5 * low * low + 0.35 * mid * mid + 0.15 * high * high);
}

/// I volumi dei due brani a un istante del mix, da 0 a 1.
///
/// Partono dalle curve di [MixStage], con due correzioni:
///
/// - l'uscente scende di [outCutDb] man mano che l'entrante sale, cosi' i
///   due livelli si incontrano senza mai alzare niente;
/// - insieme non superano la potenza di un brano solo. Le curve tengono
///   entrambi i brani pieni per un tratto (l'entrante con i bassi tagliati,
///   l'uscente intero): sommati erano 3 dB piu' forti e fino a 6 dB sui
///   picchi, e due master a 0 dBFS sommati saturano. Riportati a potenza
///   costante mantengono lo stesso equilibrio.
///
/// La potenza si conta con le bande di [outShape] e [inShape], quando ci
/// sono: un entrante senza bassi e coi medi bassi ha un sesto dell'energia
/// di un brano pieno. Contato pieno, l'uscente scendeva di 3 dB per fare
/// posto a un brano che quasi non c'era, e il mix intero si sentiva come
/// un calo di volume.
({double out, double inc}) mixGains(
  double outVolume,
  double inVolume, {
  double outCutDb = 0,
  MixStage? outShape,
  MixStage? inShape,
}) {
  var out = outVolume * math.pow(10, -outCutDb * inVolume / 20).toDouble();
  var inc = inVolume;
  final eo = outShape == null ? 1.0 : bandEnergy(outShape);
  final ei = inShape == null ? 1.0 : bandEnergy(inShape);
  final power = math.sqrt(out * out * eo * eo + inc * inc * ei * ei);
  if (power > 1) {
    out /= power;
    inc /= power;
  }
  return (out: out, inc: inc);
}

/// La velocita' a cui far suonare un brano a [inBpm] perche' batta a
/// [outBpm], contando che doppio e meta' tempo sono lo stesso battito.
/// Nulla se la differenza e' troppa: oltre l'8% un brano accelerato si
/// sente snaturato, e allora meglio non forzarlo.
double? beatMatchSpeed(double outBpm, double inBpm) {
  double? best;
  for (final m in [0.5, 1.0, 2.0]) {
    final r = outBpm / (inBpm * m);
    if ((r - 1).abs() > 0.08) continue;
    if (best == null || (r - 1).abs() < (best - 1).abs()) best = r;
  }
  return best;
}

/// Le velocita' di uscente e entrante per battere insieme.
///
/// Fino all'8% si muove il solo entrante, come prima. Oltre, fino al 25%,
/// si incontrano a meta' strada — la media geometrica dei due tempi — e
/// ciascuno si sposta al massimo del 12%: due brani a 85 e 98 BPM si
/// trovano a 91, 140 e 120 a 130. E' il "tempo blend" dei DJ, spinto fin
/// dove lo spinge Apple: un filo di artefatto in cambio del mix a tempo.
({double out, double inc})? tempoBlend(double outBpm, double inBpm) {
  double? best;
  for (final m in [0.5, 1.0, 2.0]) {
    final r = outBpm / (inBpm * m);
    if (best == null || (r - 1).abs() < (best - 1).abs()) best = r;
  }
  final r = best!;
  if ((r - 1).abs() <= 0.08) return (out: 1, inc: r);
  if ((r - 1).abs() <= 0.25) {
    final half = math.sqrt(r);
    return (out: 1 / half, inc: half);
  }
  return null;
}

// --- La correzione di tonalita' di un semitono ---
//
// Quando le tonalita' dei due brani stridono, l'entrante si sposta di un
// semitono, in su o in giu', verso una tonalita' che con l'uscente va
// d'accordo: la stessa, la relativa, o una casella accanto sulla ruota di
// Camelot. Mai piu' di un semitono: oltre, una voce si sente cantare da
// un'altra persona.
//
// Come, nel nostro libmpv. Il cambio di velocita' di mpv passa gia' da
// `scaletempo2` (allunga o accorcia senza toccare l'intonazione) finche'
// `audio-pitch-correction` resta acceso, com'e' di serie: e' il key-lock
// del mix a tempo, ed e' gia' li'. Per l'intonazione invece serve un
// ricampionamento "a nastro", che sposta insieme tono e tempo:
// - `rubberband` e' GPL, e comunque non c'e';
// - `asetrate` di ffmpeg (il modo solito) non e' fra i filtri compilati
//   (vedi tool/libmpv/crocuta-filters.patch: ci sono `aresample` e `atempo`);
// - `atempo` dopo un ricampionamento darebbe il tempo giusto, ma i suoi
//   timestamp contano i secondi in uscita e non quelli del brano: la
//   posizione che mpv riporta scivolerebbe di un secondo al minuto, e il
//   mix a tempo si regge proprio sulla posizione;
// - il `pitch` di media_kit riscrive tutto `af` a ogni cambio di velocita'
//   e spegne la correzione: ci porterebbe via la catena del mix.
// Resta `format` di mpv stesso, che c'e' in ogni libmpv: con `out-srate`
// cambia solo l'etichetta della frequenza, senza convertire — 48000
// campioni dichiarati 50854 suonano un semitono sopra e il 5,9% piu'
// svelti. E' l'`asetrate` di mpv, e lascia i timestamp del brano dov'erano.
// La velocita' di mpv poi si divide per lo stesso rapporto, e scaletempo2
// riporta il tempo esattamente a quello del mix: tono spostato, battiti
// dove devono essere.
//
// L'etichetta si mette quando il brano si carica, prima che si senta:
// `format` non accetta `af-command`, e cambiarla vuol dire ricostruire la
// catena, con lo scatto che ne segue. Per questo lo spostamento resta fino
// alla fine del brano invece di tornare indietro dopo il mix: tornare in
// qualche battuta vorrebbe dire una decina di catene ricostruite, uno
// scatto ciascuna; e anche potendo scorrere, un semitono che scivola via
// si sente come un nastro che rallenta sulle note tenute, mentre un brano
// un semitono sopra, finita l'uscente che faceva da riferimento, non lo
// nota quasi nessuno. I DJ con key-lock fanno lo stesso: il brano resta
// dove l'hanno portato. Il mix dopo parte dalla tonalita' spostata.

/// La frequenza su cui si appoggia lo spostamento: il brano si porta prima
/// a 48 kHz, cosi' l'etichetta non dipende da quella del file (44,1 kHz o
/// 48), e dopo l'etichetta torna a 48 kHz, cosi' il resto della catena e
/// l'uscita audio vedono una frequenza normale e non chiedono al sistema di
/// aprire il dispositivo a 50854 Hz.
const int keyShiftBaseRate = 48000;

/// Quanto deve vincere la tonalita' stimata sulla seconda perche' ci si
/// sposti sopra: il doppio di quello che basta per scegliere lo stile
/// (0,05, vedi MusicalKey.confidence). Spostare un brano su una tonalita'
/// sbagliata crea lo stridore invece di toglierlo. Sui brani della
/// libreria la meta' circa resta sotto: allora niente spostamento.
const double keyShiftMinConfidence = 0.1;

/// Quanto al massimo scaletempo2 puo' allungare o accorciare l'entrante,
/// spostamento compreso: lo stesso 12% che il tempo blend concede a ogni
/// brano (vedi [tempoBlend]). Un semitono vale da solo il 5,9%.
const double keyShiftMaxStretch = 0.12;

/// La frequenza dichiarata per uno spostamento di [semitones] semitoni:
/// 50854 per uno in su, 45306 per uno in giu', 48000 per nessuno.
int keyShiftRateFor(int semitones) =>
    (keyShiftBaseRate * math.pow(2, semitones / 12)).round();

/// Il rapporto di tono (e di tempo) che l'etichetta da' davvero: quello
/// arrotondato all'hertz, non 2^(1/12) esatto, cosi' il tempo del mix torna
/// esatto. Lo scarto di tono e' di millesimi di centesimo.
double keyShiftRatio(int semitones) =>
    semitones == 0 ? 1 : keyShiftRateFor(semitones) / keyShiftBaseRate;

/// La velocita' da dare a mpv perche' un brano spostato di [semitones]
/// suoni a [tempo]: l'etichetta lo accelera gia' del suo rapporto, e
/// scaletempo2 fa il resto senza toccare il tono.
double mpvSpeedFor(double tempo, int semitones) =>
    tempo / keyShiftRatio(semitones);

/// I filtri dello spostamento, in testa alla catena: vuoti senza
/// spostamento, cosi' la catena resta quella di prima. In testa perche'
/// bande, filtri ed equalizzatore lavorino gia' sul suono spostato, con le
/// frequenze che si sentono.
List<String> keyShiftChain(int semitones) => semitones == 0
    ? const []
    : [
        '@key:format=srate=$keyShiftBaseRate:'
            'out-srate=${keyShiftRateFor(semitones)}',
        '@keyrs:format=srate=$keyShiftBaseRate',
      ];

/// La catena `af` intera di un player: lo spostamento di tonalita', se
/// c'e', i filtri di AutoMix se e' acceso, l'equalizzatore.
///
/// Lo spostamento resta anche se AutoMix si spegne a meta' brano: la
/// velocita' di mpv lo conta (vedi [mpvSpeedFor]), e toglierlo farebbe
/// andare il brano piu' piano o piu' svelto del dovuto.
String playerFilterChain({
  required bool automix,
  MixStage stage = MixStage.flat,
  int keyShift = 0,
  String eq = '',
}) => [
  ...keyShiftChain(keyShift),
  if (automix) ...mixFilterChain(stage),
  if (eq.isNotEmpty) eq,
].join(',');

/// Di quanti semitoni spostare l'entrante perche' la sua tonalita' vada
/// d'accordo con quella dell'uscente [out]: -1, 0 o +1. [speed] e' la
/// velocita' a cui l'entrante suona nel mix.
///
/// Zero quando una delle due non si sa o non e' sicura (sotto
/// [keyShiftMinConfidence]), quando vanno gia' d'accordo (distanza fino a
/// 0,3: stessa casella, relativa, una accanto), o quando nessuno dei due
/// spostamenti ci arriva. Fra i due che ci arrivano, quello che le avvicina
/// di piu'; a pari distanza quello che chiede meno a scaletempo2 — un
/// entrante gia' accelerato per il mix va spostato in su, che l'etichetta
/// accelera a sua volta e scaletempo2 lavora meno — e a parita' anche di
/// quello, in su, come fanno i DJ per alzare l'energia. Sempre lo stesso
/// risultato per la stessa coppia.
int keyShiftFor(
  MusicalKey? out,
  MusicalKey? incoming, {
  double speed = 1,
  double minConfidence = keyShiftMinConfidence,
}) {
  if (out == null || incoming == null) return 0;
  if (out.confidence < minConfidence || incoming.confidence < minConfidence) {
    return 0;
  }
  if (out.distanceTo(incoming) <= 0.3) return 0;
  var best = 0;
  var bestDistance = double.infinity;
  var bestStretch = double.infinity;
  for (final s in const [1, -1]) {
    final d = out.distanceTo(incoming.transposed(s));
    if (d > 0.3) continue;
    final stretch = (mpvSpeedFor(speed, s) - 1).abs();
    if (stretch > keyShiftMaxStretch) continue;
    if (d < bestDistance || (d == bestDistance && stretch < bestStretch)) {
      best = s;
      bestDistance = d;
      bestStretch = stretch;
    }
  }
  return best;
}

/// Le tonalita' del mix in una riga, per il registro: le due sulla ruota,
/// e lo spostamento se c'e', o perche' non c'e'.
String keyShiftNote(
  MusicalKey? out,
  MusicalKey? incoming,
  int shift, {
  double speed = 1,
}) {
  if (out == null || incoming == null) return "tonalita' non note";
  final pair = '${out.camelotName} > ${incoming.camelotName}';
  final conf =
      '${out.confidence.toStringAsFixed(2)}/'
      '${incoming.confidence.toStringAsFixed(2)}';
  if (shift != 0) {
    final to = incoming.transposed(shift);
    return "tonalita' $pair (fiducia $conf), entrante "
        "${shift > 0 ? '+' : ''}$shift semitono: ${to.name} ${to.camelotName}";
  }
  final d = out.distanceTo(incoming);
  if (d <= 0.3) return "tonalita' $pair compatibili";
  if (out.confidence < keyShiftMinConfidence ||
      incoming.confidence < keyShiftMinConfidence) {
    return "tonalita' $pair, fiducia bassa ($conf): niente spostamento";
  }
  final reachable = [
    1,
    -1,
  ].any((s) => out.distanceTo(incoming.transposed(s)) <= 0.3);
  return reachable
      ? "tonalita' $pair: un semitono le accorderebbe, ma l'entrante andrebbe "
            "allungato oltre il ${(keyShiftMaxStretch * 100).round()}%"
      : "tonalita' $pair, nessun semitono le avvicina";
}

/// I fatti di una coppia di brani da cui si sceglie lo stile del mix:
/// tutti misurati sull'audio dei due brani, niente a caso. La stessa
/// coppia ha sempre lo stesso mix.
class MixFacts {
  /// Se entrambi i brani hanno frasi e sezioni dall'audio. Senza, si sa
  /// solo il tempo, e gli stili sono quelli di prima: blend o blend corto.
  final bool phrased;

  /// Tempi entro il 4%, con l'uscente alla sua velocita'.
  final bool closeTempo;

  /// Quanto stridono le tonalita', 0-1 (vedi MusicalKey.distanceTo). Nullo
  /// se una delle due non si sa.
  final double? keyDistance;

  /// Di quanti semitoni e' spostato l'entrante (vedi [keyShiftFor]): allora
  /// [keyDistance] e' gia' quella dopo lo spostamento, e lo stile lo dice.
  final int keyShift;

  /// Se l'uscente ha un outro calmo dopo la voce, almeno 4 dB sotto il suo
  /// volume tipico, e quante battute dura.
  final bool lowOutro;
  final int outroBars;

  /// Quante battute del mix dura l'intro dell'entrante senza voce, prima
  /// che entri il brano pieno. Zero se parte pieno.
  final int introBars;

  /// Di quanto sale l'entrante dove finisce l'intro, in dB: un drop vero e'
  /// almeno [dropRiseDb]. Nullo se l'intro ha la voce, o non c'e'.
  final double? dropRise;

  const MixFacts({
    this.phrased = false,
    this.closeTempo = false,
    this.keyDistance,
    this.keyShift = 0,
    this.lowOutro = false,
    this.outroBars = 0,
    this.introBars = 0,
    this.dropRise,
  });
}

/// Lo stile del mix per una coppia di brani, e perche'.
///
/// Le regole, in ordine, come le userebbe un DJ:
///
/// 1. Il blend lungo ([MixKind.rolling]) quando i due brani sono fatti per
///    stare insieme a lungo: tempi entro il 4%, tonalita' vicine sulla
///    ruota, un uscente che esce da un outro calmo di almeno 16 battute e
///    un entrante con un'intro di almeno 16.
/// 2. La salita col filtro ([MixKind.filterBuild]) quando le tonalita'
///    stridono: i filtri tengono i due brani in bande diverse, e lo
///    stridore non si sente.
/// 3. Il cambio sul drop ([MixKind.dropSwap]) quando l'uscente e' ancora
///    pieno e l'entrante ha un'intro di almeno 4 battute che sfocia in un
///    drop: il drop cade sull'"1" della frase dell'uscente.
/// 4. Di nuovo la salita col filtro quando l'uscente e' ancora pieno e
///    l'entrante parte pieno: un blend sovrapporrebbe due brani interi.
/// 5. Altrimenti il blend a tappe, lungo o corto secondo i tempi.
///
/// Il cambio secco e la dissolvenza non stanno qui: servono quando i
/// battiti non si accordano, e li sceglie il piano senza tempo comune.
({MixKind kind, String reason}) chooseMixStyle(MixFacts f) {
  final closeOrNot = f.closeTempo ? 'tempi vicini' : "tempi un po' lontani";
  if (!f.phrased) {
    return (
      kind: f.closeTempo ? MixKind.blend : MixKind.quick,
      reason: '$closeOrNot, senza analisi delle sezioni',
    );
  }
  // La distanza e' quella che si sentira': dopo lo spostamento di un
  // semitono, se il piano l'ha deciso. Due tonalita' che stridevano e che
  // lo spostamento ha accordato non chiedono piu' la salita col filtro, e
  // possono fare anche il blend lungo.
  final key = f.keyDistance;
  final keyOk = key != null && key <= 0.3;
  final keyClash = key != null && key >= 0.7;
  final shifted = f.keyShift == 0
      ? ''
      : " (con l'entrante spostato di ${f.keyShift > 0 ? '+' : ''}"
            '${f.keyShift} semitono)';
  if (f.closeTempo &&
      keyOk &&
      f.lowOutro &&
      f.outroBars >= 16 &&
      f.introBars >= 16) {
    return (
      kind: MixKind.rolling,
      reason:
          'outro calmo di ${f.outroBars} battute, intro di ${f.introBars}, '
          "tempi e tonalita' compatibili$shifted, curve dai DJ",
    );
  }
  if (keyClash) {
    return (
      kind: MixKind.filterBuild,
      reason: "tonalita' che stridono: i filtri tengono separati i due brani",
    );
  }
  final rise = f.dropRise;
  if (!f.lowOutro && f.introBars >= 4 && rise != null && rise >= dropRiseDb) {
    return (
      kind: MixKind.dropSwap,
      reason:
          "drop dell'entrante dopo ${f.introBars} battute d'intro "
          '(+${rise.toStringAsFixed(0)} dB), uscente ancora pieno',
    );
  }
  if (!f.lowOutro && f.introBars < 4) {
    return (
      kind: MixKind.filterBuild,
      reason: "uscente ancora pieno ed entrante che parte pieno",
    );
  }
  return (
    kind: f.closeTempo ? MixKind.blend : MixKind.quick,
    reason: '$closeOrNot${f.lowOutro ? ', outro calmo' : ''}',
  );
}

/// La lunghezza un gradino piu' corta: 32, 16, 8, 4, 2 battute. Il cambio
/// sul drop ne ha 10 o 6, e scende sulle stesse.
int _shorter(int bars) => bars > 16
    ? 16
    : bars > 8
    ? 8
    : bars > 4
    ? 4
    : bars ~/ 2;

/// Pianifica il mix fra due brani analizzati, come un DJ.
///
/// Lo stile dipende dalla coppia (vedi [chooseMixStyle]): sedici battute
/// se i tempi sono quasi uguali e i battiti sicuri, otto se si accordano
/// con meno margine, fino a trentadue su un outro calmo, il cambio sul drop,
/// la salita col filtro, due battute in eco se la voce dell'entrante
/// arriva subito. La transizione finisce sempre prima che l'entrante
/// cominci a cantare: due voci insieme sono il mix peggiore che ci sia, in
/// entrambe le direzioni.
///
/// Il mix comincia sull'"1" di una frase dell'uscente (vedi PhraseMap):
/// all'inizio del suo outro, se ce n'e' uno, e sempre dopo l'ultimo verso.
/// L'entrante parte in modo che la fine della sua intro — il suo drop —
/// cada a sua volta su una frase dell'uscente, di solito proprio alla fine
/// del mix. Senza frasi dall'audio, l'outro e' dove la musica scende di
/// almeno 4 dB sotto il tipico del brano, e le frasi sono gruppi di quattro
/// battute. Se la musica finisce prima del mix, il suo ultimo tratto si
/// ripete a tempo.
///
/// Quando i battiti non sono affidabili o i tempi troppo diversi, il cambio
/// secco di [cutStage] o la dissolvenza di [fadeStage]: niente battiti in
/// comune, quindi niente battiti che si accavallano.
///
/// [notBefore] e' per il mix che arriva tardi — l'analisi o il testo del
/// successivo pronti solo dopo il punto scelto: si rifa' il piano da li' in
/// avanti invece di rinunciare. Rinunciare voleva dire lasciar finire il
/// brano, silenzio in coda compreso, e far partire l'altro dal suo
/// silenzio iniziale: i due brani zitti insieme.
BeatMixPlan? planBeatMix({
  required BeatGrid out,
  required BeatGrid incoming,
  double? vocalsEnd,
  double? inVocalsStart,
  List<double> outLines = const [],
  double minConfidence = 0.8,
  bool stems = false,
  double? notBefore,
  int outKeyShift = 0,
}) {
  // Le frasi si cercano una volta: chi esce sulla sua griglia del finale,
  // chi entra su quella dell'inizio, le stesse con cui si mixa.
  final outMap = analyzePhrases(out);
  final inMap = analyzePhrases(incoming);
  BeatMixPlan? plan({required bool echoFirst}) => _planBeatMix(
    out: out,
    incoming: incoming,
    outMap: outMap,
    inMap: inMap,
    vocalsEnd: vocalsEnd,
    inVocalsStart: inVocalsStart,
    outLines: outLines,
    minConfidence: minConfidence,
    stems: stems,
    echoFirst: echoFirst,
    notBefore: notBefore,
    outKeyShift: outKeyShift,
  );
  if (!stems) return plan(echoFirst: false);
  // Prima la mossa che solo gli stem permettono: entrare sull'ultima
  // battuta cantata e mandarla in eco. Se l'entrante canta troppo presto
  // perche' l'eco ci stia, il mix di sempre — che aspetta la fine del
  // verso e si accorcia per non sovrapporre le voci — con la voce spenta
  // solo dove serve davvero.
  final echo = plan(echoFirst: true);
  if (echo?.stems?.echoFrom != null) return echo;
  return plan(echoFirst: false);
}

BeatMixPlan? _planBeatMix({
  required BeatGrid out,
  required BeatGrid incoming,
  required PhraseMap outMap,
  required PhraseMap inMap,
  double? vocalsEnd,
  double? inVocalsStart,
  List<double> outLines = const [],
  double minConfidence = 0.35,
  bool stems = false,
  bool echoFirst = false,
  double? notBefore,
  int outKeyShift = 0,
}) {
  final sure =
      out.confidence >= minConfidence && incoming.confidence >= minConfidence;
  final blend = sure ? tempoBlend(out.bpm, incoming.bpm) : null;
  if (blend == null) {
    return _planCut(
      out: out,
      incoming: incoming,
      outMap: outMap,
      vocalsEnd: vocalsEnd,
      notBefore: notBefore,
    );
  }
  final speed = blend.inc;
  final outSpeed = blend.out;
  // Secondi dell'entrante in secondi dell'uscente, e viceversa: le due
  // misure del mix.
  double inToOut(double x) => x / speed * outSpeed;
  double outToIn(double x) => x / outSpeed * speed;

  final bar = out.barLength;
  final compatible = outSpeed == 1 && (speed - 1).abs() <= 0.04;

  var inStart = incoming.barAtOrAfter(incoming.musicStart - 0.05);
  if (inStart < 0) inStart += incoming.barLength;
  final inFirst = inStart;

  // --- I fatti della coppia, per lo stile ---
  //
  // L'intro dell'entrante: fin dove arriva senza voce, in battute del mix
  // (con doppio o meta' tempo non sono le sue). Se la voce comincia prima
  // della fine dell'intro, l'intro utile finisce li', e un drop dopo la
  // voce non e' un drop su cui cambiare.
  final drop = inMap.introEnd;
  final cleanIntro =
      drop != null &&
      (inVocalsStart == null || inVocalsStart >= drop - incoming.barLength);
  final introUntil = drop == null
      ? inFirst
      : cleanIntro
      ? drop
      : math.max(inFirst, inVocalsStart!);
  final introBars = math.max(
    0,
    ((introUntil - inFirst) / outToIn(bar) + 1e-6).floor(),
  );
  // L'outro dell'uscente, dalle sezioni.
  final outroAt = outMap.outroStart;
  final typical = out.medianLevel;
  final outroLevel = outroAt == null
      ? null
      : out.levelBetween(outroAt, out.musicEnd);
  final lowOutro =
      outroAt != null &&
      outroLevel != null &&
      typical != null &&
      outroLevel <= typical - 4 &&
      (vocalsEnd == null || outroAt >= vocalsEnd - bar);
  final outroBars = outroAt == null
      ? 0
      : ((out.musicEnd - outroAt) / bar + 1e-6).floor();
  // Le tonalita' come si sentono: l'uscente con lo spostamento che ha
  // avuto entrando (resta fino alla sua fine), l'entrante con quello che
  // gli si da' ora, se stridono. La stessa coppia, lo stesso spostamento.
  final outKey = out.key?.transposed(outKeyShift);
  final keyShift = keyShiftFor(outKey, incoming.key, speed: speed);
  final inKey = incoming.key?.transposed(keyShift);
  final keyDistance = switch ((outKey, inKey)) {
    (final a?, final b?) when a.confidence >= 0.05 && b.confidence >= 0.05 =>
      a.distanceTo(b),
    _ => null,
  };
  final style = chooseMixStyle(
    MixFacts(
      phrased: outMap.phrased && inMap.phrased,
      closeTempo: compatible,
      keyDistance: keyDistance,
      keyShift: keyShift,
      lowOutro: lowOutro,
      outroBars: outroBars,
      introBars: introBars,
      dropRise: cleanIntro ? inMap.introRise : null,
    ),
  );
  var kind = style.kind;
  final why = [style.reason];

  var bars = switch (kind) {
    // Trentadue solo se outro e intro le hanno entrambi, e se stanno in un
    // minuto: oltre, anche il blend piu' riuscito si sente lungo.
    MixKind.rolling =>
      outroBars >= 32 && introBars >= 32 && 32 * bar <= 64 ? 32 : 16,
    // Quattro o otto battute d'intro prima del drop, e due dopo: l'uscente
    // sparisce sulla frase nuova.
    MixKind.dropSwap => (introBars >= 8 ? 8 : 4) + 2,
    MixKind.blend => 16,
    _ => 8,
  };
  // Mai oltre la mezza minuta: a 80 BPM sedici battute sono 48 secondi.
  if (kind == MixKind.blend) {
    while (bars > 8 && bars * bar > 32) {
      bars = _shorter(bars);
    }
    if (bars < 16) kind = MixKind.quick;
  }

  // --- Dove parte l'entrante ---
  //
  // Il suo drop deve cadere sull'"1" di una frase dell'uscente. Il mix
  // comincia su una frase e dura un numero di battute multiplo di quattro:
  // basta che l'entrante parta tante battute prima del drop quante ne dura
  // il mix (nel cambio sul drop, quante ne precedono lo scambio). Un'intro
  // piu' lunga del mix si salta in parte, come fa ogni DJ; una piu' corta
  // resta intera, e il drop cade dentro il mix, dopo le sue battute.
  if (cleanIntro) {
    final align = kind == MixKind.dropSwap ? bars - 2 : bars;
    if (introBars >= align) {
      final x = drop - outToIn(align * bar);
      final k = ((x - incoming.firstBar) / incoming.barLength).roundToDouble();
      final snapped = incoming.firstBar + k * incoming.barLength;
      if (snapped >= inFirst - 1e-6) inStart = snapped;
    }
  }

  // Da dove si esce, per un mix lungo [length].
  double pickStart(double length) {
    var start = out.barAtOrBefore(out.musicEnd - length);
    if (outMap.phrased) {
      // L'outro trovato dalle sezioni comincia gia' su un confine: si mixa
      // su una parte fatta per essere lasciata, non sull'ultimo ritornello.
      if (outroAt != null &&
          outroAt + length <= out.musicEnd + 1e-6 &&
          outroAt >= out.musicEnd - 90 &&
          (vocalsEnd == null || outroAt >= vocalsEnd - bar)) {
        start = outroAt;
      }
    } else if (typical != null) {
      // Senza sezioni, l'outro dal volume.
      final from = math.max(vocalsEnd ?? out.musicEnd - 60, out.musicEnd - 60);
      // La prima battuta calma, e calme anche le tre dopo: un outro vero
      // comincia gia' su una frase, e chiedendo la frase qui si partiva a
      // volte ancora dentro l'ultimo ritornello.
      for (
        var b = out.barAtOrAfter(from);
        b + length <= out.musicEnd;
        b += bar
      ) {
        final first = out.levelBetween(b, b + bar);
        final next = out.levelBetween(b, b + 4 * bar);
        if (first != null &&
            next != null &&
            first <= typical - 4 &&
            next <= typical - 4) {
          start = b;
          break;
        }
      }
    }
    if (vocalsEnd != null) {
      final afterVocals = out.barAtOrAfter(vocalsEnd);
      if (afterVocals < start) {
        // Una coda lunga dopo la voce si salta, ma mai piu' di trenta
        // secondi prima della fine: un finale strumentale vero va sentito.
        // Con le frasi, dall'"1" della prima frase dopo la voce.
        if (afterVocals >= out.musicEnd - 30 && start - afterVocals > 8 * bar) {
          final phrase = outMap.atOrAfter(afterVocals);
          start = phrase != null && phrase < start ? phrase : afterVocals;
        }
      } else if (afterVocals > start && !echoFirst) {
        // La voce arriva fin quasi alla fine: si aspetta il verso, e la
        // musica che manca la da' il loop. Con la voce separata non serve:
        // la frase finisce e va in eco sopra la musica che gia' cambia.
        final lastBar = out.barAtOrBefore(out.musicEnd) - bar;
        start = afterVocals < lastBar ? afterVocals : lastBar;
      }
    }
    return start;
  }

  // Sulla frase: il mix comincia sull'"1" di una frase.
  //
  // Con le frasi dall'audio, il confine trovato o la frase da 8 piu' vicini
  // entro due battute, o la frase da 4 entro una (vedi PhraseMap.nearest).
  // Senza, all'inizio di un gruppo di quattro battute contate dal primo
  // battere della musica, se ce n'e' uno a una battuta al massimo. Sempre
  // senza bisogno del loop. Il piu' vicino e non sempre il successivo: il
  // finale calmo trovato dal volume arriva al massimo una battuta dopo la
  // frase vera, e andare avanti ne salterebbe una intera.
  double onPhrase(double start, double length) {
    if (outMap.phrased) {
      bool ok(double p) =>
          p >= out.musicStart &&
          p + length <= out.musicEnd + 1e-6 &&
          (notBefore == null || p >= notBefore);
      // Se vicino non ce n'e' uno che vada bene — di solito perche' il mix
      // finirebbe oltre la musica — l'ultima frase da 8 o l'ultimo confine
      // prima, fino a otto battute: meglio uscire un po' prima che a meta'
      // frase.
      final back = outMap.atOrBefore(start, reach: 8);
      return outMap.nearest(start, ok: ok) ??
          (back != null && ok(back) ? back : start);
    }
    final after = out.phraseAtOrAfter(start);
    final before = after - 4 * bar;
    final phrase = (after - start) <= (start - before) ? after : before;
    if ((phrase - start).abs() <= bar + 1e-6 &&
        phrase >= out.musicStart &&
        phrase + length <= out.musicEnd) {
      return phrase;
    }
    return start;
  }

  var length = bars * bar;
  var start = pickStart(length);
  if (notBefore != null && start < notBefore) {
    start = out.barAtOrAfter(notBefore);
    // Da qui ci stanno meno battute: si accorcia, sedici, otto, quattro.
    final was = kind;
    while (bars > 4 && start + length > out.musicEnd) {
      bars = _shorter(bars);
      kind = MixKind.quick;
      length = bars * bar;
    }
    if (kind != was) why.add('in ritardo: $bars battute');
    // Troppo tardi anche per quattro battute: il cambio secco, in tempo.
    if (start + length > out.musicEnd) {
      return _planCut(
        out: out,
        incoming: incoming,
        outMap: outMap,
        vocalsEnd: vocalsEnd,
        notBefore: notBefore,
      );
    }
  }

  // Con la voce separata, se l'uscente canta fin verso la fine il mix
  // comincia una battuta prima della sua ultima battuta cantata: la frase
  // finisce, torna in eco, e sotto entra l'altro brano. E' il gesto che
  // distingue un mix da una dissolvenza, e senza stem non si poteva fare —
  // la voce in eco si sarebbe portata dietro tutta la musica. Con le frasi
  // il mix comincia invece sull'"1" della frase in cui cade quella battuta,
  // al massimo quattro battute prima: la voce finisce sopra l'entrante che
  // sale, e torna in eco.
  double? echoBar;
  if (echoFirst &&
      vocalsEnd != null &&
      vocalsEnd > out.musicEnd - 45 &&
      vocalsEnd < out.musicEnd - out.beatLength) {
    final last = out.barAtOrBefore(vocalsEnd - 0.05);
    final from = outMap.atOrBefore(last - bar) ?? last - bar;
    if (from >= out.musicStart) {
      start = from;
      echoBar = last;
    }
  }

  if (echoBar == null) start = onPhrase(start, length);

  // Le due voci si scontrano solo se si sovrappongono nel tempo: se
  // l'entrante comincia a cantare mentre l'uscente canta ancora. Prima
  // contava la sola presenza della voce entrante, e "Illegal" — che canta
  // dopo pochi secondi — usciva da "Girl Like Me", che nel mix canta al
  // massimo il primo secondo, con un'eco di due battute invece che con una
  // transizione. Senza il testo dell'uscente non si sa fin dove canta: si
  // resta prudenti.
  final outSingsFor = vocalsEnd == null
      ? double.infinity
      : math.max(0.0, vocalsEnd - start);
  final inSingsAfter = inVocalsStart == null
      ? double.infinity
      : inToOut(inVocalsStart - inStart);
  final outMaySing = inSingsAfter < outSingsFor + out.beatLength;
  // Con la voce separata lo scontro non accorcia il mix: basta spegnere
  // la voce dell'uscente un battito prima che canti l'altra, e la
  // transizione resta lunga. Senza, l'unica via era l'eco di due battute.
  // Il passaggio di voce, per un mix che parte da [from] e dura [len]: la
  // prima fine di riga dell'uscente dopo che l'entrante avrebbe cominciato
  // a cantare, entro due battute — di piu' e all'entrante si toglierebbe
  // troppo — e con almeno una battuta di mix dopo.
  double? exchangeFor(double from, double len) {
    if (!stems || !inSingsAfter.isFinite) return null;
    final ends = [
      for (final l in outLines) l - from,
      if (vocalsEnd != null) vocalsEnd - from,
    ]..sort();
    for (final e in ends) {
      if (e < inSingsAfter) continue;
      if (e > inSingsAfter + 2 * bar || e > len - bar) return null;
      return e;
    }
    return null;
  }

  // Con la voce separata il mix non si accorcia se le voci possono
  // passarsi la mano, o se basta spegnere l'uscente lasciandogli almeno
  // una battuta.
  final duckable =
      stems &&
      (exchangeFor(start, length) != null ||
          inSingsAfter - out.beatLength >= bar);
  if (outMaySing &&
      inVocalsStart != null &&
      inVocalsStart > inStart &&
      !echoFirst &&
      !duckable) {
    final room = inToOut(inVocalsStart - inStart);
    final fit = (room / bar).floor();
    if (fit < 4) {
      kind = MixKind.echo;
      bars = 2;
      why.add("l'entrante canta subito: eco di due battute");
    } else {
      final was = bars;
      while (bars > fit) {
        bars = _shorter(bars);
      }
      if (bars < 4) bars = 4;
      if (bars != was) why.add("accorciato a $bars battute: l'entrante canta");
      if (bars != was || kind == MixKind.blend || kind == MixKind.quick) {
        kind = bars >= 16 ? MixKind.blend : MixKind.quick;
      }
    }
    length = bars * bar;
    start = pickStart(length);
    if (outMap.phrased) start = onPhrase(start, length);
  }
  // Se per arrivare in fondo serve il loop, al massimo otto battute: la
  // stessa battuta ripetuta sedici volte, per mezzo minuto, si nota. E il
  // cambio sul drop vuole l'uscente pieno fino al drop, non una battuta in
  // loop. La salita col filtro il loop lo regge: sotto il passa-alto che
  // sale e' il "loop roll" di un DJ.
  if ((kind == MixKind.blend ||
          kind == MixKind.rolling ||
          kind == MixKind.dropSwap) &&
      start + length > out.musicEnd) {
    bars = 8;
    kind = MixKind.quick;
    length = bars * bar;
    why.add('la musica finisce prima: otto battute col loop');
  }
  if (start < out.musicStart) start = out.musicStart;
  if (notBefore != null && start < notBefore) {
    start = out.barAtOrAfter(notBefore);
  }

  double? loopStart, loopEnd;
  if (kind == MixKind.echo) {
    // L'eco: l'ultimo battito prima del mix, ripetuto.
    loopEnd = start;
    loopStart = start - out.beatLength;
  } else if (start + length > out.musicEnd) {
    loopEnd = out.barAtOrBefore(out.musicEnd);
    loopStart = loopEnd - bar;
    if (loopStart < start) {
      loopStart = null;
      loopEnd = null;
    }
  }

  StemPlan? stemPlan;
  if (stems) {
    // Le due voci: da quando canta l'entrante, a mix iniziato.
    var duckAt = outMaySing
        ? math.max(0.0, inSingsAfter - out.beatLength)
        : double.infinity;
    // Spegnere la voce all'istante zero vuol dire tagliarla a meta' frase:
    // meno di una battuta e si lascia stare. Il mix di sempre si e' gia'
    // accorciato per non sovrapporre le voci.
    if (duckAt < bar) duckAt = double.infinity;
    // Meglio ancora del taglio: l'uscente finisce la riga e la voce passa.
    final exchangeAt = outMaySing ? exchangeFor(start, length) : null;
    if (exchangeAt != null) duckAt = exchangeAt + StemPlan.exchangeFade / 2;
    // L'ultima battuta cantata dall'uscente, se cade nel mix e c'e' posto
    // per ripeterla almeno due volte prima che canti l'altro.
    double? echoFrom;
    var repeats = 0;
    if (vocalsEnd != null && vocalsEnd > start && vocalsEnd < start + length) {
      final from = (echoBar ?? out.barAtOrBefore(vocalsEnd - 0.05)) - start;
      if (from >= 0) {
        // L'eco e' voce dell'uscente: deve finire prima che canti
        // l'entrante, qualunque cosa si decida sullo spegnimento.
        final limit = math.min(length, inSingsAfter - out.beatLength);
        repeats = math.min(3, ((limit - (from + bar)) / bar).floor());
        if (repeats >= 2) echoFrom = from;
      }
    }
    stemPlan = StemPlan(
      duckAt: duckAt,
      echoFrom: echoFrom,
      echoLength: echoFrom == null ? 0 : bar,
      echoRepeats: echoFrom == null ? 0 : repeats,
      exchangeAt: exchangeAt,
      // Il passaggio puo' scivolare fin dove [exchangeFor] l'avrebbe
      // accettato: due battute dopo che l'entrante avrebbe cominciato, e una
      // battuta prima della fine del mix.
      latestDuck: exchangeAt == null
          ? null
          : math.min(inSingsAfter + 2 * bar, length - bar) +
                StemPlan.exchangeFade / 2,
    );
  }

  // Il cambio sul drop: lo scambio sull'"1" del drop, dopo le battute
  // d'intro, e largo un battito.
  final swapAt = kind == MixKind.dropSwap ? (bars - 2) / bars : 0.8;
  final swapWidth = kind == MixKind.dropSwap
      ? 0.5 * out.beatLength / length
      : 0.02;
  // L'eco a tempo: tre quarti di battito nell'uscita in eco — il "dotted
  // eighth" dei DJ, che s'incastra fra i battiti invece di raddoppiarli —
  // mezzo nella salita col filtro, che deve spingere.
  final echoDelay = switch (kind) {
    MixKind.echo => 0.75 * out.beatLength,
    MixKind.filterBuild => 0.5 * out.beatLength,
    _ => null,
  };

  return BeatMixPlan(
    stems: stemPlan,
    kind: kind,
    outStart: start,
    inStart: inStart,
    bars: bars,
    length: length,
    speed: speed,
    outSpeed: outSpeed,
    loopStart: loopStart,
    loopEnd: loopEnd,
    swapAt: swapAt,
    swapWidth: swapWidth,
    echoDelay: echoDelay,
    keyShift: keyShift,
    keyNote: keyShiftNote(outKey, incoming.key, keyShift, speed: speed),
    reason: why.join('; '),
    notes: _phraseNotes(
      outMap: outMap,
      inMap: inMap,
      outStart: start,
      inStart: inStart,
      drop: drop,
      inBar: outToIn(bar),
    ),
    outLevel: out.levelBetween(start, math.min(start + length, out.musicEnd)),
    inLevel: incoming.levelBetween(
      inStart,
      inStart + length / outSpeed * speed,
    ),
    outBeat: out.beatLength,
    inBeat: incoming.beatLength,
  );
}

/// Frasi e sezioni del mix in una riga, per il registro: dove esce
/// l'uscente e che punto e', dove entra l'entrante e dove cade il suo drop,
/// e le sezioni dei due brani.
String _phraseNotes({
  required PhraseMap outMap,
  required PhraseMap inMap,
  required double outStart,
  required double inStart,
  required double? drop,
  required double inBar,
}) {
  final section = outMap.sectionAt(outStart);
  final landing = drop == null || drop < inStart
      ? ''
      : ', drop a ${drop.toStringAsFixed(1)} s che cade a '
            '${((drop - inStart) / inBar).toStringAsFixed(1)} battute nel mix';
  return 'uscita ${outStart.toStringAsFixed(1)} s su ${outMap.levelOf(outStart)}'
      '${section == null ? '' : ' (${section.kind.name})'}; '
      'entrante da ${inStart.toStringAsFixed(1)} s$landing; '
      'uscente: ${outMap.describe()}; entrante: ${inMap.describe()}';
}

/// Il piano senza battiti in comune: la transizione filtrata o la
/// dissolvenza, e da dove parte l'entrante.
///
/// La dissolvenza quando non serve altro: l'uscente finisce gia' sfumando
/// (gli ultimi otto secondi 6 dB sotto il suo tipico) o l'entrante comincia
/// piano. Altrimenti la transizione filtrata, con l'eco d'uscita.
///
/// Il punto di mezzo — lo scambio dei bassi, o il centro della
/// dissolvenza — sta dopo la fine della voce, all'inizio del finale calmo
/// se c'e', altrimenti poco prima che la musica finisca: la coda di
/// silenzio o di sfumatura non si ascolta. Su un battere dell'uscente, o
/// sull'"1" di una sua frase, se della sua griglia ci si fida. Nella
/// transizione filtrata l'entrante parte dal suo primo battere e sale per
/// un numero intero di sue battute, circa quattro secondi e mezzo: cosi'
/// lo scambio cade anche sul suo battere.
BeatMixPlan _planCut({
  required BeatGrid out,
  required BeatGrid incoming,
  required PhraseMap outMap,
  double? vocalsEnd,
  double? notBefore,
}) {
  final outTypical = out.medianLevel;
  final inTypical = incoming.medianLevel;
  final outTail = out.levelBetween(out.musicEnd - 8, out.musicEnd);
  final inHead = incoming.levelBetween(
    incoming.musicStart,
    incoming.musicStart + 8,
  );
  final quietEnd =
      outTypical != null && outTail != null && outTail <= outTypical - 6;
  final quietStart =
      inTypical != null && inHead != null && inHead <= inTypical - 6;
  final fade = quietEnd || quietStart;
  final reason = !fade
      ? 'battiti che non si accordano: transizione filtrata con eco'
      : quietEnd
      ? "battiti che non si accordano, l'uscente finisce sfumando"
      : "battiti che non si accordano, l'entrante comincia piano";

  final target = fade ? fadeLength / 2 : cutLength * cutDrop;
  var before = target;
  var inStart = incoming.musicStart;
  if (!fade && incoming.confidence >= 0.8) {
    inStart = incoming.barAtOrAfter(incoming.musicStart - 0.05);
    if (inStart < 0) inStart += incoming.barLength;
    final bars = math.max(1, (target / incoming.barLength).round());
    before = bars * incoming.barLength;
  }
  final length = fade ? fadeLength : before / cutDrop;

  var drop = out.musicEnd - 0.5;
  final typical = out.medianLevel;
  if (typical != null) {
    final from = math.max(vocalsEnd ?? out.musicEnd - 30, out.musicEnd - 30);
    for (var t = from; t + 1 <= out.musicEnd; t += 0.5) {
      final level = out.levelBetween(t, t + 4);
      if (level != null && level <= typical - 6) {
        drop = t + before;
        break;
      }
    }
  }
  if (vocalsEnd != null && drop < vocalsEnd && vocalsEnd < out.musicEnd) {
    drop = vocalsEnd;
  }
  if (out.confidence >= 0.8) {
    // L'"1" di una frase vicina, se ci sono le frasi; il battere dopo,
    // altrimenti, e se cade oltre la fine della musica quello prima.
    final phrase = outMap.nearest(
      drop,
      ok: (p) =>
          p <= out.musicEnd && (vocalsEnd == null || p >= vocalsEnd - 0.05),
    );
    if (phrase != null) {
      drop = phrase;
    } else {
      final after = out.barAtOrAfter(drop);
      drop = after <= out.musicEnd ? after : out.barAtOrBefore(drop);
    }
  }
  drop = math.min(drop, out.musicEnd);
  if (notBefore != null && drop - before < notBefore) drop = notBefore + before;
  final start = math.max(out.musicStart, drop - before);

  return BeatMixPlan(
    kind: fade ? MixKind.fade : MixKind.cut,
    outStart: start,
    inStart: inStart,
    bars: 0,
    length: length,
    speed: 1,
    matched: false,
    stems: const StemPlan(),
    echoBeat: fade ? null : out.beatLength.clamp(0.3, 0.9).toDouble(),
    // Senza battiti in comune l'entrante suona com'e': la sovrapposizione
    // e' breve, e spostarlo per tutto il brano non varrebbe la pena.
    keyNote: "niente spostamento di tonalita' senza mix a tempo",
    reason: reason,
    notes:
        'centro ${drop.toStringAsFixed(1)} s su ${outMap.levelOf(drop)}; '
        'uscente: ${outMap.describe()}',
    outLevel: out.levelBetween(start, math.min(drop, out.musicEnd)),
    inLevel: incoming.levelBetween(inStart + before, inStart + length),
  );
}
