import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Il mini player del Mac, la finestrina che resta sopra le altre app.
///
/// La finestra e' nativa (macos/Runner/MiniPlayerController.swift) e prende
/// i dati dallo stesso `demus/now_playing` del Centro di Controllo: da qui
/// la si apre e la si chiude soltanto. Altrove non esiste, e ogni chiamata
/// non fa niente.
class MiniPlayerWindow {
  MiniPlayerWindow._();

  static const _channel = MethodChannel('crocuta/mini_player');

  static bool get isSupported => Platform.isMacOS;

  /// Apre il mini player, o lo chiude se e' gia' aperto (come ⌥⌘M).
  static Future<void> toggle() => _call('toggle');

  static Future<void> show() => _call('show');

  static Future<void> hide() => _call('hide');

  static Future<void> _call(String method) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Nei test e nei build senza il lato nativo: niente finestra.
    } on PlatformException {
      // Idem: un mini player che non si apre non deve rompere altro.
    }
  }
}
