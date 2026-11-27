import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Il Liquid Glass di Apple, dentro una platform view.
///
/// `NSGlassEffectView` su macOS 26, `UIGlassEffect` su iOS 26.
///
/// The open question this answers is whether `NSGlassEffectView` refracts the
/// Flutter content behind it or only the window background: the system glass
/// samples the native view hierarchy, and Flutter draws into its own surface.
/// [fallback] is used wherever the native view is unavailable, so callers can
/// swap the two and compare.
class NativeGlass extends StatelessWidget {
  static const _viewType = 'crocuta/native_glass';

  final double radius;
  final Color? tint;

  /// Quanto materiale si vede. Piu' basso = piu' trasparente.
  final double opacity;

  /// Vetro "clear" di sistema: quasi senza materiale, per la lente che
  /// scorre sotto il dito.
  final bool clear;

  /// Angoli a capsula che seguono l'altezza, per una vista che cambia
  /// misura mentre si anima. Con questo [radius] non conta.
  final bool capsule;

  /// Drawn instead of the platform view off macOS.
  final Widget fallback;

  const NativeGlass({
    super.key,
    required this.fallback,
    this.radius = 20,
    this.tint,
    this.opacity = 1.0,
    this.clear = false,
    this.capsule = false,
  });

  /// Macchia non usa il vetro: la chrome e' nero pieno e il colore lo porta
  /// il brano. Il vetro di sistema resta qui dietro questo interruttore, per
  /// poterlo riaccendere senza riscrivere chi lo usa; spento, ogni chiamante
  /// disegna il suo [fallback], che e' gia' una superficie scura piena.
  static const bool enabled = false;

  static bool get isAvailable {
    if (!enabled) return false;
    if (!Platform.isMacOS && !Platform.isIOS) return false;
    // Nei widget test non esiste un host per le platform view: AppKitView
    // fallisce con MissingPluginException e porta giu' la schermata. Flutter
    // imposta questa variabile quando gira `flutter test`.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!isAvailable) return fallback;

    final params = <String, dynamic>{
      'radius': radius,
      'alpha': opacity,
      'clear': clear,
      'capsule': capsule,
      if (tint != null) 'tintArgb': tint!.toARGB32(),
    };

    // IgnorePointer perche' una platform view partecipa all'arena dei
    // gesti e, essendo disegnata a tutta superficie sotto il contenuto, si
    // prendeva il tocco: su iPhone premere la barra del brano non apriva
    // piu' il player. Il vetro e' uno sfondo, non un comando, quindi va
    // tolto del tutto dal hit testing — qui e, dal lato nativo, con
    // `isUserInteractionEnabled = false`.
    return IgnorePointer(
      child: Platform.isIOS
          ? UiKitView(
              viewType: _viewType,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
            )
          : AppKitView(
              viewType: _viewType,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
            ),
    );
  }
}
