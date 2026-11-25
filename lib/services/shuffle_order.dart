import 'dart:math' as math;

/// Rimescola cio' che deve ancora suonare, come Apple Music: la coda
/// cambia ordine davvero, cosi' "Playing Next" mostra l'ordine in cui i
/// brani suoneranno, e ognuno passa una volta sola.
///
/// Quelli della radio ([isRadio]) restano in fondo, nel loro ordine: la
/// radio continua una raccolta, non ci si mescola dentro.
List<T> shuffleUpcoming<T>(
  List<T> upcoming, {
  required bool Function(T) isRadio,
  math.Random? random,
}) {
  final own = [
    for (final t in upcoming)
      if (!isRadio(t)) t,
  ]..shuffle(random);
  return [
    ...own,
    for (final t in upcoming)
      if (isRadio(t)) t,
  ];
}

/// Rimette cio' che deve ancora suonare nell'ordine della raccolta, quando
/// si spegne lo shuffle. [originalIndex] dice dov'era ogni brano (null se
/// non c'era: aggiunto dopo, o dalla radio), e quelli restano in fondo
/// nell'ordine in cui sono.
List<T> unshuffleUpcoming<T>(
  List<T> upcoming, {
  required int? Function(T) originalIndex,
}) {
  final known = [
    for (final t in upcoming)
      if (originalIndex(t) != null) t,
  ]..sort((a, b) => originalIndex(a)!.compareTo(originalIndex(b)!));
  return [
    ...known,
    for (final t in upcoming)
      if (originalIndex(t) == null) t,
  ];
}
