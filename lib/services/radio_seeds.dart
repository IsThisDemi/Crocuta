import '../models/track.dart';

/// Da quale brano la radio chiede i simili.
///
/// Prima era sempre il brano in riproduzione: dopo il primo giro, un brano
/// arrivato dalla radio stessa, e poi un simile del simile. Una catena che
/// ad ogni passo si allontanava, e in mezz'ora si era su un altro genere.
/// Ora la radio resta ancorata a dove e' partita:
///
/// 1. prima i brani che non vengono dalla radio — il brano da cui l'hai
///    avviata, o la raccolta che stavi ascoltando —, dal piu' vicino al
///    brano in corso andando indietro: gli ultimi sono l'umore di adesso;
/// 2. finiti quelli, i brani della radio che hai ascoltato fino in fondo
///    ([liked]): la radio si allarga seguendo cio' che ti e' piaciuto, non
///    cio' che e' capitato. Uno saltato non guida niente.
///
/// Ogni brano fa da punto di partenza una volta sola ([used]). Null se
/// non ne resta nessuno.
Track? pickRadioSeed({
  required List<Track> queue,
  required int current,
  required Set<String> radioIds,
  required Set<String> liked,
  required Set<String> used,
}) {
  final upTo = current.clamp(0, queue.length - 1);
  for (final fromRadio in [false, true]) {
    for (var i = upTo; i >= 0; i--) {
      final t = queue[i];
      if (used.contains(t.id)) continue;
      final isRadio = radioIds.contains(t.id);
      if (isRadio != fromRadio) continue;
      if (isRadio && !liked.contains(t.id)) continue;
      return t;
    }
  }
  return null;
}

/// I brani della radio di un punto di partenza che si possono ancora
/// aggiungere: non gia' in coda, non ascoltati di recente, senza doppioni.
List<Track> freshRadio(
  List<Track> pool, {
  required Set<String> inQueue,
  required Set<String> recentlyHeard,
}) {
  final seen = <String>{};
  return [
    for (final t in pool)
      if (!inQueue.contains(t.id) &&
          !recentlyHeard.contains(t.id) &&
          seen.add(t.id))
        t,
  ];
}

/// Se un brano della radio e' stato ascoltato "fino in fondo": almeno
/// l'80% — o fino a mezzo minuto dalla fine, che con AutoMix e' dove il
/// brano dopo comincia gia'.
bool listenedThrough(Duration listened, Duration? length) {
  if (length == null || length <= Duration.zero) {
    return listened >= const Duration(minutes: 2);
  }
  return listened >= length * 0.8 ||
      listened >= length - const Duration(seconds: 30);
}
