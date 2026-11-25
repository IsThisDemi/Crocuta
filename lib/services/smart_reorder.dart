import 'dart:math' as math;

import 'key_analysis.dart';

/// Com'e' fatto un brano per chi lo mixa: il tempo e la tonalita'.
class MixTraits {
  final double bpm;
  final MusicalKey? key;

  const MixTraits(this.bpm, [this.key]);
}

/// Quanto costa passare da [a] a [b], 0-1: meta' il tempo, meta' la
/// tonalita'.
///
/// Il tempo si confronta anche a doppio e a meta': un brano a 87 e uno a 174
/// battono insieme. Otto per cento di differenza e' gia' il massimo: oltre,
/// AutoMix non li porta piu' a tempo. La tonalita' conta sulla ruota di
/// Camelot, e poco quando la stima e' incerta: una tonalita' sbagliata non
/// deve spostare un brano in fondo alla playlist.
double transitionCost(MixTraits a, MixTraits b) {
  var d = double.infinity;
  for (final f in const [1.0, 2.0, 0.5]) {
    d = math.min(d, (math.log(b.bpm * f / a.bpm)).abs());
  }
  final tempo = (d / math.log(1.08)).clamp(0.0, 1.0);
  final ka = a.key, kb = b.key;
  double key;
  if (ka == null || kb == null) {
    key = 0.5;
  } else {
    final trust = math.min(ka.confidence, kb.confidence);
    // Sotto una fiducia di 0,05 la tonalita' vale quasi nulla; da 0,15 in
    // su vale per intero.
    final w = ((trust - 0.05) / 0.1).clamp(0.0, 1.0);
    key = 0.5 + (ka.distanceTo(kb) - 0.5) * w;
  }
  return 0.55 * tempo + 0.45 * key;
}

/// L'ordine in cui suonare [traits] perche' i passaggi scorrano: indici
/// nella lista di partenza.
///
/// Il primo resta il primo — e' il brano con cui hai scelto di aprire. Poi
/// si va ogni volta al brano piu' vicino fra quelli rimasti, e il percorso
/// si migliora invertendo tratti finche' c'e' guadagno (2-opt): lo stesso
/// metodo del commesso viaggiatore, che qui e' la stessa domanda. I brani
/// senza analisi ([traits] nullo) restano in fondo, nell'ordine in cui
/// erano.
List<int> smartOrder(List<MixTraits?> traits) {
  final known = [
    for (var i = 0; i < traits.length; i++)
      if (traits[i] != null) i,
  ];
  final unknown = [
    for (var i = 0; i < traits.length; i++)
      if (traits[i] == null) i,
  ];
  if (known.length < 3) return [...known, ...unknown];

  double cost(int a, int b) => transitionCost(traits[a]!, traits[b]!);

  // Il piu' vicino, a ogni passo.
  final path = [known.first];
  final left = known.sublist(1).toSet();
  while (left.isNotEmpty) {
    final from = path.last;
    var best = left.first;
    for (final c in left) {
      if (cost(from, c) < cost(from, best)) best = c;
    }
    path.add(best);
    left.remove(best);
  }

  // 2-opt su un percorso aperto, primo brano fermo: si inverte il tratto
  // [i, j] se i due passaggi nuovi costano meno dei due vecchi.
  var improved = true;
  var rounds = 0;
  while (improved && rounds++ < 50) {
    improved = false;
    for (var i = 1; i < path.length - 1; i++) {
      for (var j = i + 1; j < path.length; j++) {
        final before =
            cost(path[i - 1], path[i]) +
            (j + 1 < path.length ? cost(path[j], path[j + 1]) : 0);
        final after =
            cost(path[i - 1], path[j]) +
            (j + 1 < path.length ? cost(path[i], path[j + 1]) : 0);
        if (after + 1e-9 < before) {
          final rev = path.sublist(i, j + 1).reversed.toList();
          path.setRange(i, j + 1, rev);
          improved = true;
        }
      }
    }
  }
  return [...path, ...unknown];
}

/// Il costo totale dei passaggi in un ordine: per i test e per dire di
/// quanto e' migliorato.
double pathCost(List<MixTraits?> traits, List<int> order) {
  var sum = 0.0;
  for (var i = 1; i < order.length; i++) {
    final a = traits[order[i - 1]], b = traits[order[i]];
    if (a != null && b != null) sum += transitionCost(a, b);
  }
  return sum;
}
