import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// La finestra dell'app sul Mac: per ora solo il tutto schermo, che il
/// videoclip accende e spegne (macos/Runner/MainFlutterWindow.swift).
/// Altrove non fa niente.
class AppWindow {
  AppWindow._();

  static const _channel = MethodChannel('crocuta/window');

  static bool get supportsFullScreen => Platform.isMacOS;

  static Future<bool> isFullScreen() async {
    if (!supportsFullScreen) return false;
    try {
      return await _channel.invokeMethod<bool>('isFullScreen') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setFullScreen(bool on) async {
    if (!supportsFullScreen) return;
    try {
      await _channel.invokeMethod<void>('setFullScreen', on);
    } on MissingPluginException {
      // Nei test: niente finestra.
    } on PlatformException {
      // Una finestra che non va a tutto schermo non deve rompere il video.
    }
  }
}
