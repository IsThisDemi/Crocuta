import 'dart:async';

/// Un lavoro pesante alla volta: l'analisi dei battiti e la separazione
/// della voce non girano mai insieme.
///
/// Sono le due reti neurali dell'app, e su iPhone ciascuna occupa qualche
/// centinaio di megabyte mentre lavora. Insieme, col resto dell'app,
/// superavano il limite di memoria di iOS, che chiudeva Crocuta pochi
/// secondi dopo l'avvio di un brano con AutoMix acceso. In fila ci mettono
/// lo stesso tempo, e il mix e' comunque pronto minuti prima che serva.
Future<T> heavyWork<T>(Future<T> Function() job) {
  final done = Completer<T>();
  _queue = _queue.then((_) async {
    try {
      done.complete(await job());
    } catch (e, st) {
      done.completeError(e, st);
    }
  });
  return done.future;
}

Future<void> _queue = Future.value();
