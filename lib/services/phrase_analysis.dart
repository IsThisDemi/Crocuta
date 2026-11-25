import 'dart:math' as math;

import 'beat_analysis.dart';

/// Che parte di un brano e' un tratto fra due confini di frase. Grossolana,
/// dal solo volume e dai bassi: a un mix non serve sapere se e' una strofa
/// o un ritornello, serve sapere se e' fatto per entrare (l'intro), per
/// uscire (l'outro), se e' un momento vuoto (il break) o il brano pieno.
enum SectionKind { intro, body, breakdown, outro }

/// Di quanti dB deve salire una sezione piena, rispetto a quella prima,
/// perche' sia un "drop": il momento in cui il brano esplode, dove un DJ fa
/// cadere il cambio dei bassi.
const double dropRiseDb = 4;

/// Un tratto del brano fra due confini di frase.
class Section {
  /// Dove comincia e finisce, in secondi della griglia da cui viene.
  final double start;
  final double end;

  /// Le stesse, in battute dal primo battere della musica.
  final int fromBar;
  final int toBar;

  final SectionKind kind;

  /// Il volume medio, in dB, e di quanto sale rispetto alla sezione prima.
  final double level;
  final double rise;

  const Section({
    required this.start,
    required this.end,
    required this.fromBar,
    required this.toBar,
    required this.kind,
    required this.level,
    required this.rise,
  });

  int get bars => toBar - fromBar;

  bool get isDrop => kind == SectionKind.body && rise >= dropRiseDb;
}

/// Le frasi e le sezioni di un brano, sulla sua griglia dei battiti.
///
/// Un DJ non comincia un mix a caso: lo comincia sull'"1" di una frase, il
/// primo battere di un gruppo di 8, 16 o 32 battute, perche' li' la musica
/// stessa cambia — entra la batteria, parte il ritornello, comincia
/// l'outro. Le due frasi, quella che finisce e quella che comincia,
/// coincidono, e il mix suona come se fosse scritto.
///
/// I confini si trovano con la novelty di Foote: per ogni battuta un
/// vettore di feature (bassi, medi, acuti, attacchi, volume), la matrice di
/// quanto ogni battuta somiglia a ogni altra, e un "kernel a scacchiera"
/// che scorre lungo la diagonale e si accende dove le battute prima si
/// somigliano fra loro, quelle dopo pure, ma le une non somigliano alle
/// altre. Poi ogni picco si porta sulla frase da 8 battute piu' vicina,
/// contata dal primo battere della musica (o con lo sfasamento che mettono
/// d'accordo la maggior parte dei confini: un brano con due battute di
/// pick-up ha le frasi spostate di due).
class PhraseMap {
  /// Il primo battere della musica, da cui si contano le battute.
  final double origin;

  /// Quanto dura una battuta.
  final double bar;

  /// Quante battute intere ci sono fra [origin] e la fine della musica.
  final int bars;

  /// Lo sfasamento delle frasi da 8, in battute da [origin] (0-7).
  final int offset;

  /// I confini trovati, in battute da [origin], in ordine. Il primo e'
  /// sempre 0, l'inizio della musica.
  final List<int> boundaryBars;

  final List<Section> sections;

  /// Se le frasi vengono davvero dall'audio. Falso per le griglie senza
  /// feature: allora il mix usa le frasi da quattro battute di sempre.
  final bool phrased;

  const PhraseMap({
    required this.origin,
    required this.bar,
    required this.bars,
    required this.offset,
    required this.boundaryBars,
    required this.sections,
    required this.phrased,
  });

  /// Nessuna frase: la griglia non ha feature.
  factory PhraseMap.none(BeatGrid g) => PhraseMap(
    origin: g.barAtOrAfter(g.musicStart - 0.05),
    bar: g.barLength,
    bars: 0,
    offset: 0,
    boundaryBars: const [0],
    sections: const [],
    phrased: false,
  );

  double timeOf(int k) => origin + k * bar;

  /// I confini trovati, in secondi.
  List<double> get boundaries => [for (final b in boundaryBars) timeOf(b)];

  /// La battuta (frazionaria) di [t].
  double barOf(double t) => (t - origin) / bar;

  bool _onGrid(double t, int every) {
    final k = barOf(t);
    final r = k.roundToDouble();
    if ((k - r).abs() > 1e-3) return false;
    return (r.toInt() - offset) % every == 0;
  }

  bool _detected(double t) {
    final k = barOf(t);
    return boundaryBars.any((b) => (b - k).abs() < 1e-3);
  }

  /// Che punto e' [t], per il registro: un confine trovato, l'"1" di una
  /// frase da 8 o da 4, o una battuta qualunque.
  String levelOf(double t) {
    if (!phrased) return 'nessuna analisi delle frasi';
    if (_detected(t)) return 'confine di sezione';
    if (_onGrid(t, 8)) return 'frase da 8';
    if (_onGrid(t, 4)) return 'frase da 4';
    return 'battuta';
  }

  /// Il punto di frase piu' vicino a [t] che vada bene a [ok]: prima un
  /// confine trovato entro due battute, poi l'"1" di una frase da 8 entro
  /// due, poi quello di una frase da 4 entro una. A parita' di distanza, il
  /// prima. Nullo se nessuno va bene: allora resta [t].
  double? nearest(double t, {required bool Function(double) ok}) {
    if (!phrased) return null;
    final k = barOf(t);
    double? pick(Iterable<int> candidates, double reach) {
      final near =
          [
            for (final c in candidates)
              if ((c - k).abs() <= reach + 1e-6 && ok(timeOf(c))) c,
          ]..sort((a, b) {
            final d = (a - k).abs().compareTo((b - k).abs());
            return d != 0 ? d : a.compareTo(b);
          });
      return near.isEmpty ? null : timeOf(near.first);
    }

    Iterable<int> grid(int every) sync* {
      final from = (k - 3).floor(), to = (k + 3).ceil();
      for (var c = from; c <= to; c++) {
        if (c >= 0 && c <= bars && (c - offset) % every == 0) yield c;
      }
    }

    return pick(boundaryBars, 2) ?? pick(grid(8), 2) ?? pick(grid(4), 1);
  }

  /// Il primo punto di frase da [t] in avanti: un confine trovato o l'"1"
  /// di una frase da 8. Nullo oltre l'ultima battuta.
  double? atOrAfter(double t) {
    if (!phrased) return null;
    final k = barOf(t) - 1e-6;
    int? best;
    for (final b in boundaryBars) {
      if (b >= k && (best == null || b < best)) best = b;
    }
    var g = k.ceil();
    while ((g - offset) % 8 != 0) {
      g++;
    }
    if (g <= bars && (best == null || g < best)) best = g;
    return best == null ? null : timeOf(best);
  }

  /// L'ultimo punto di frase da [t] indietro, entro [reach] battute: un
  /// confine trovato o l'"1" di una frase da 8, e se non ce n'e' quello di
  /// una frase da 4 — che entro quattro battute c'e' sempre. Nullo prima
  /// dell'inizio della musica.
  double? atOrBefore(double t, {int reach = 4}) {
    if (!phrased) return null;
    final k = barOf(t) + 1e-6;
    int? best;
    for (final b in boundaryBars) {
      if (b <= k && b >= k - reach && (best == null || b > best)) best = b;
    }
    int? onGrid(int every) {
      var g = k.floor();
      while (g >= 0 && (g - offset) % every != 0) {
        g--;
      }
      return g >= 0 && g >= k - reach ? g : null;
    }

    final g8 = onGrid(8);
    if (g8 != null && (best == null || g8 > best)) best = g8;
    best ??= onGrid(4);
    return best == null ? null : timeOf(best);
  }

  /// La sezione che contiene [t].
  Section? sectionAt(double t) {
    for (final s in sections) {
      if (t >= s.start - 1e-6 && t < s.end - 1e-6) return s;
    }
    return null;
  }

  /// Dove comincia l'outro: la prima delle sezioni calme in fondo al brano.
  /// Nullo se il brano finisce pieno.
  double? get outroStart {
    double? from;
    for (final s in sections.reversed) {
      if (s.kind != SectionKind.outro) break;
      from = s.start;
    }
    return from;
  }

  /// Dove finisce l'intro, cioe' dove entra il brano: la fine delle sezioni
  /// calme dell'inizio, o, se il brano comincia gia' pieno, il primo drop
  /// entro le prime 64 battute. Nullo se non c'e' ne' l'una ne' l'altro.
  double? get introEnd {
    if (sections.isEmpty) return null;
    if (sections.first.kind == SectionKind.intro) {
      for (final s in sections) {
        if (s.kind != SectionKind.intro) return s.start;
      }
      return null;
    }
    for (final s in sections.skip(1)) {
      if (s.fromBar > 64) break;
      if (s.isDrop) return s.start;
    }
    return null;
  }

  /// Di quanto sale il brano dove finisce l'intro, in dB.
  double? get introRise {
    final e = introEnd;
    if (e == null) return null;
    return sectionAt(e)?.rise;
  }

  /// Le sezioni in una riga, per il registro: `intro@0.5 body@32.5(+6) ...`.
  String describe() {
    if (!phrased) return 'senza frasi';
    final parts = [
      for (final s in sections)
        '${s.kind.name}@${s.start.toStringAsFixed(1)}'
            '${s.rise >= 1 ? '(+${s.rise.toStringAsFixed(0)})' : ''}',
    ];
    return 'frasi da 8 sfasate di $offset, ${parts.join(' ')}';
  }
}

/// Le frasi e le sezioni di [g]. Senza feature, nessuna.
PhraseMap analyzePhrases(BeatGrid g) {
  final none = PhraseMap.none(g);
  if (g.features.isEmpty || g.musicEnd <= g.musicStart) return none;
  final origin = none.origin;
  final bar = g.barLength;
  final n = ((g.musicEnd - origin) / bar).floor();
  // Meno di sedici battute: niente frasi da cercare.
  if (n < 16) return none;
  final feats = barFeatures(g, origin: origin, bars: n);
  final novelty = footeNovelty(feats);
  final peaks = pickBoundaries(novelty);
  final offset = phraseOffset(peaks, novelty);
  final bounds = snapBoundaries(peaks, offset: offset, bars: n);

  final levels = <double>[];
  final lows = <double>[];
  final starts = <double>[];
  final ends = <double>[];
  for (var i = 0; i < bounds.length; i++) {
    final a = bounds[i];
    final b = i + 1 < bounds.length ? bounds[i + 1] : n;
    levels.add(
      g.levelBetween(origin + a * bar, origin + b * bar) ??
          _bandLevel(feats.sublist(a, b)),
    );
    var low = 0.0;
    for (var k = a; k < b; k++) {
      low += feats[k][0];
    }
    lows.add(low / (b - a));
    starts.add(a / n);
    ends.add(b / n);
  }
  final typical = g.medianLevel ?? _median(levels);
  final typicalLow = _median([for (final f in feats) f[0]]);
  final kinds = labelSections(
    levels,
    lows,
    typical: typical,
    typicalLow: typicalLow,
    starts: starts,
    ends: ends,
  );
  return PhraseMap(
    origin: origin,
    bar: bar,
    bars: n,
    offset: offset,
    boundaryBars: bounds,
    phrased: true,
    sections: [
      for (var i = 0; i < bounds.length; i++)
        Section(
          fromBar: bounds[i],
          toBar: i + 1 < bounds.length ? bounds[i + 1] : n,
          start: origin + bounds[i] * bar,
          end: origin + (i + 1 < bounds.length ? bounds[i + 1] : n) * bar,
          kind: kinds[i],
          level: levels[i],
          rise: i == 0 ? 0 : levels[i] - levels[i - 1],
        ),
    ],
  );
}

/// Un vettore per battuta: le [BeatGrid.featureDims] feature del brano, e
/// il volume secondo per secondo se c'e', in media sulla battuta (pesata
/// per quanto di ogni fotogramma ci cade dentro).
List<List<double>> barFeatures(
  BeatGrid g, {
  required double origin,
  required int bars,
}) {
  const dims = BeatGrid.featureDims;
  const rate = BeatGrid.featureRate;
  final frames = g.features.length ~/ dims;
  final bar = g.barLength;
  // La media di una serie a passo [step] fra [from] e [to], per colonna.
  double mean(double from, double to, int count, double Function(int) at) {
    var sum = 0.0, weight = 0.0;
    final a = math.max(0, from.floor()), b = math.min(count, to.ceil());
    for (var i = a; i < b; i++) {
      final w = math.min(to, i + 1.0) - math.max(from, i.toDouble());
      if (w <= 0) continue;
      sum += at(i) * w;
      weight += w;
    }
    return weight == 0 ? -100 : sum / weight;
  }

  return [
    for (var k = 0; k < bars; k++)
      [
        for (var d = 0; d < dims; d++)
          mean(
            (origin + k * bar) * rate,
            (origin + (k + 1) * bar) * rate,
            frames,
            (i) => g.features[i * dims + d],
          ),
        if (g.energy.isNotEmpty)
          mean(
            origin + k * bar,
            origin + (k + 1) * bar,
            g.energy.length,
            (i) => g.energy[i],
          ),
      ],
  ];
}

/// La novelty di Foote fra una battuta e la precedente, per ogni battuta.
///
/// Ogni feature si misura in "quanto si muove nel brano": divisa per la sua
/// deviazione standard, ma mai per meno di [floor] dB — un brano piatto ha
/// variazioni di mezzo decibel che, ingrandite, sembrerebbero sezioni.
/// Poi, per ogni battuta i, il kernel a scacchiera largo [halfWidth]
/// battute per parte: la distanza media fra le battute prima e quelle
/// dopo, meno la distanza media dentro ciascuno dei due blocchi, pesate da
/// una gaussiana che conta di piu' le battute vicine al confine. Il
/// risultato e' zero dove il brano continua com'era, e cresce dove cambia.
List<double> footeNovelty(
  List<List<double>> bars, {
  int halfWidth = 8,
  double floor = 1.5,
}) {
  final n = bars.length;
  final out = List<double>.filled(n, 0);
  if (n < 4) return out;
  final d = bars.first.length;
  final z = List.generate(n, (_) => List<double>.filled(d, 0));
  for (var j = 0; j < d; j++) {
    var mean = 0.0;
    for (final b in bars) {
      mean += b[j];
    }
    mean /= n;
    var v = 0.0;
    for (final b in bars) {
      v += (b[j] - mean) * (b[j] - mean);
    }
    final scale = math.max(math.sqrt(v / n), floor);
    for (var i = 0; i < n; i++) {
      z[i][j] = (bars[i][j] - mean) / scale;
    }
  }
  final dist = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      var s = 0.0;
      for (var j = 0; j < d; j++) {
        final x = z[a][j] - z[b][j];
        s += x * x;
      }
      dist[a][b] = dist[b][a] = math.sqrt(s);
    }
  }
  for (var i = 2; i <= n - 2; i++) {
    final w = math.min(halfWidth, math.min(i, n - i));
    final sigma = math.max(1.0, w / 2);
    // Il peso di una battuta a [k] battute dal confine (mezza battuta in
    // piu': il confine sta fra due battute).
    double g(int k) => math.exp(-0.5 * math.pow((k + 0.5) / sigma, 2));
    var cross = 0.0, cw = 0.0, within = 0.0, ww = 0.0;
    for (var a = i - w; a < i; a++) {
      final ga = g(i - 1 - a);
      for (var b = i; b < i + w; b++) {
        final wt = ga * g(b - i);
        cross += wt * dist[a][b];
        cw += wt;
      }
      for (var a2 = a + 1; a2 < i; a2++) {
        final wt = ga * g(i - 1 - a2);
        within += wt * dist[a][a2];
        ww += wt;
      }
    }
    for (var b = i; b < i + w; b++) {
      for (var b2 = b + 1; b2 < i + w; b2++) {
        final wt = g(b - i) * g(b2 - i);
        within += wt * dist[b][b2];
        ww += wt;
      }
    }
    out[i] = cross / cw - (ww == 0 ? 0 : within / ww);
  }
  return out;
}

/// I picchi della novelty: le battute dove il brano cambia davvero.
///
/// Un picco e' il massimo nel raggio di [radius] battute — due confini a
/// meno di quattro battute non sono due sezioni — e supera sia [minNovelty]
/// (un cambio vero, non il respiro di un brano piatto) sia [relative] del
/// picco piu' alto (in un brano molto contrastato, i cambi minori non sono
/// sezioni).
List<int> pickBoundaries(
  List<double> novelty, {
  double minNovelty = 1.0,
  double relative = 0.3,
  int radius = 3,
}) {
  final n = novelty.length;
  if (n == 0) return const [];
  final top = novelty.reduce(math.max);
  final threshold = math.max(minNovelty, relative * top);
  return [
    for (var i = 1; i < n; i++)
      if (novelty[i] >= threshold &&
          [
            for (
              var j = math.max(0, i - radius);
              j <= math.min(n - 1, i + radius);
              j++
            )
              if (j != i) j,
          ].every(
            (j) =>
                novelty[i] > novelty[j] || (novelty[i] == novelty[j] && i < j),
          ))
        i,
  ];
}

/// Lo sfasamento delle frasi da 8 battute che mette d'accordo i confini.
///
/// Ogni confine vota per il suo resto modulo 8, col peso della sua novelty
/// (e meta' voto ai due resti accanto: un confine trovato una battuta in
/// la' e' comune). Lo zero — frasi contate dal primo battere della musica,
/// come sono scritti quasi tutti i brani — parte col voto del picco piu'
/// forte: un confine solo non lo sposta, per spostarlo servono almeno due
/// confini d'accordo. A parita', il resto piu' piccolo: nessun caso.
int phraseOffset(List<int> peaks, List<double> novelty) {
  if (peaks.isEmpty) return 0;
  final top = peaks.map((p) => novelty[p]).reduce(math.max);
  var best = 0;
  var bestScore = -double.infinity;
  for (var o = 0; o < 8; o++) {
    var score = o == 0 ? top : 0.0;
    for (final p in peaks) {
      final r = (p - o) % 8;
      score +=
          novelty[p] *
          (r == 0
              ? 1
              : (r == 1 || r == 7)
              ? 0.4
              : 0);
    }
    if (score > bestScore + 1e-9) {
      bestScore = score;
      best = o;
    }
  }
  return best;
}

/// I confini portati sulle frasi: sull'"1" di una frase da 8 se ce n'e'
/// uno entro due battute, di una da 4 entro una, altrimenti dove sono. Lo
/// zero c'e' sempre; due confini a meno di quattro battute si tengono il
/// primo.
List<int> snapBoundaries(
  List<int> peaks, {
  required int offset,
  required int bars,
}) {
  int? nearestOn(int p, int every, int reach) {
    final down = p - (p - offset) % every;
    final up = down + every;
    final q = (p - down) <= (up - p) ? down : up;
    return (q - p).abs() <= reach ? q : null;
  }

  final set = <int>{0};
  for (final p in peaks) {
    final q = nearestOn(p, 8, 2) ?? nearestOn(p, 4, 1) ?? p;
    if (q > 0 && q < bars) set.add(q);
  }
  final sorted = set.toList()..sort();
  final out = <int>[];
  for (final b in sorted) {
    if (out.isEmpty || b - out.last >= 4) out.add(b);
  }
  return out;
}

/// Il tipo di ogni sezione, dal suo volume e dai suoi bassi.
///
/// Calma e' una sezione almeno 3 dB sotto il volume tipico del brano, o
/// coi bassi 8 dB sotto i soliti (la cassa che sparisce si sente anche a
/// volume pieno). Le sezioni calme dell'inizio, fino a meta' brano, sono
/// l'intro; quelle della fine, da meta' in poi, l'outro; le altre calme
/// sono break; il resto e' il brano pieno. [starts] e [ends] dicono dove
/// cade ogni sezione, in frazione del brano.
List<SectionKind> labelSections(
  List<double> levels,
  List<double> lows, {
  required double typical,
  required double typicalLow,
  required List<double> starts,
  required List<double> ends,
}) {
  final n = levels.length;
  final kinds = List<SectionKind>.filled(n, SectionKind.body);
  bool quiet(int i) => levels[i] <= typical - 3 || lows[i] <= typicalLow - 8;
  var intro = 0;
  while (intro < n - 1 && quiet(intro) && starts[intro] < 0.5) {
    kinds[intro] = SectionKind.intro;
    intro++;
  }
  var outro = n;
  while (outro - 1 > intro && quiet(outro - 1) && ends[outro - 1] > 0.5) {
    outro--;
    kinds[outro] = SectionKind.outro;
  }
  for (var i = intro; i < outro; i++) {
    if (quiet(i)) kinds[i] = SectionKind.breakdown;
  }
  return kinds;
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Il volume di un tratto dalle sole tre bande, quando manca quello
/// secondo per secondo.
double _bandLevel(List<List<double>> bars) {
  var p = 0.0;
  for (final b in bars) {
    for (var j = 0; j < 3; j++) {
      p += math.pow(10, b[j] / 10);
    }
  }
  return 10 * math.log(p / math.max(1, bars.length) + 1e-12) / math.ln10;
}
