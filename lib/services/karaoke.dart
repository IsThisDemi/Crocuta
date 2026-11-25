import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stem_service.dart';

/// Il karaoke, visto da fuori: acceso o no, quanta voce resta, e se la base
/// del brano e' ancora in preparazione.
class KaraokeState {
  final bool enabled;

  /// Quanta voce resta, da 0 (sola base) a 1 (il brano com'e').
  final double voice;

  /// Da 0 a 1 mentre si separa la base del brano in corso; null altrimenti.
  final double? preparing;

  /// Se la base sta suonando davvero, al posto della voce.
  final bool active;

  const KaraokeState({
    this.enabled = false,
    this.voice = 0.15,
    this.preparing,
    this.active = false,
  });

  KaraokeState copyWith({
    bool? enabled,
    double? voice,
    double? preparing,
    bool clearPreparing = false,
    bool? active,
  }) => KaraokeState(
    enabled: enabled ?? this.enabled,
    voice: voice ?? this.voice,
    preparing: clearPreparing ? null : (preparing ?? this.preparing),
    active: active ?? this.active,
  );
}

final karaokeProvider = StateProvider<KaraokeState>(
  (ref) => const KaraokeState(),
);

/// Le basi separate, una per brano, e la fila di chi le prepara.
///
/// Una separazione alla volta: sono pesanti, e due insieme ci
/// metterebbero lo stesso tempo di due in fila, ma consegnando entrambe
/// tardi. Si tengono le ultime tre basi — il brano, il precedente, il
/// successivo — e le altre si cancellano: un brano intero in float pesa
/// qualche decina di MB.
class KaraokeBases {
  final StemService stems;

  KaraokeBases(this.stems);

  final Map<String, File> _ready = {};
  final List<String> _order = [];
  final Map<String, Future<File?>> _jobs = {};

  /// Chi guarda l'avanzamento di ogni lavoro: l'ultimo che l'ha chiesto.
  /// Una base preparata in anticipo, in silenzio, deve poter mostrare a che
  /// punto e' appena ci si arriva.
  final Map<String, void Function(double)> _watch = {};
  Future<void> _queue = Future.value();

  File? readyFor(String audioId) => _ready[audioId];

  /// La base di [audioId]: subito se c'e', altrimenti in fila.
  Future<File?> baseFor(
    String audioId, {
    void Function(double progress)? onProgress,
  }) {
    final done = _ready[audioId];
    if (done != null) return Future.value(done);
    if (onProgress != null) _watch[audioId] = onProgress;
    final running = _jobs[audioId];
    if (running != null) return running;
    final completer = Completer<File?>();
    _jobs[audioId] = completer.future;
    _queue = _queue.then((_) async {
      try {
        final file = await stems.renderInstrumental(
          audioId,
          onProgress: (p) => _watch[audioId]?.call(p),
        );
        if (file != null) _keep(audioId, file);
        completer.complete(file);
      } catch (e) {
        debugPrint('karaoke: base non separata ($e)');
        completer.complete(null);
      } finally {
        _jobs.remove(audioId);
        _watch.remove(audioId);
      }
    });
    return completer.future;
  }

  void _keep(String audioId, File file) {
    _ready[audioId] = file;
    _order
      ..remove(audioId)
      ..add(audioId);
    while (_order.length > 3) {
      final old = _order.removeAt(0);
      final f = _ready.remove(old);
      if (f != null) unawaited(f.delete().then((_) {}, onError: (_) {}));
    }
  }
}
