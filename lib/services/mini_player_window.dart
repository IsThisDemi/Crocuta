import 'dart:io' show Platform;
import 'dart:typed_data';

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

  /// La musica del brano in ascolto, per la macchia del mini player che
  /// si muove con lei come quelle dell'app (vedi BeatPulse): i colpi di
  /// basso, quelli di rullante e l'energia, [rate] valori al secondo dal
  /// secondo zero del brano. Si manda una volta per brano: la finestra li
  /// legge da se' alla sua posizione, anche con l'app nascosta, quando
  /// Flutter non disegna e non saprebbe dirle niente.
  static Future<void> setMusic({
    required double rate,
    required Float32List pulse,
    required Float32List snap,
    required Float32List energy,
  }) => _call('music', {
    'rate': rate,
    'pulse': pulse,
    'snap': snap,
    'energy': energy,
  });

  /// Il brano e' cambiato e la sua musica non c'e' ancora: la macchia
  /// respira soltanto.
  static Future<void> clearMusic() => _call('music', null);

  /// Quanto si muove la macchia con la musica: lo slider delle
  /// Impostazioni, 0-2.
  static Future<void> setMusicIntensity(double value) =>
      _call('musicIntensity', value);

  static Future<void> _call(String method, [Object? args]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Nei test e nei build senza il lato nativo: niente finestra.
    } on PlatformException {
      // Idem: un mini player che non si apre non deve rompere altro.
    }
  }
}
