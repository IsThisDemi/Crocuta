import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';

/// Il mix AutoMix in corso: chi esce, chi entra e a che punto e'.
///
/// Sta fuori da PlayerState di proposito: l'avanzamento cambia decine di
/// volte al secondo, e dentro lo stato del player farebbe ricostruire
/// chiunque lo osservi. Qui lo guarda solo chi disegna il mix.
class MixInfo {
  final Track from;
  final Track to;

  /// Da 0 (tutto l'uscente) a 1 (tutto l'entrante).
  final double progress;

  const MixInfo({required this.from, required this.to, required this.progress});
}

final mixInfoProvider = StateProvider<MixInfo?>((ref) => null);
