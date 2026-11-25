import 'package:flutter/services.dart';

import '../models/track.dart';

/// Bridges player state to the iOS lock screen / Control Center
/// ("Now Playing") and forwards remote commands back into the app.
///
/// On platforms without the native side (macOS/Windows) every call is a
/// silent no-op.
class NowPlayingService {
  static const _channel = MethodChannel('demus/now_playing');
  static const _remote = MethodChannel('demus/remote_commands');

  /// Invoked when the user hits play/pause/skip/seek on the lock screen
  /// or in Control Center. `position` is in seconds (only for `seek`).
  void Function(String command, double? position)? onRemoteCommand;

  bool _listening = false;

  /// Registers the listener for remote commands coming from iOS.
  void listen() {
    if (_listening) return;
    _listening = true;
    _remote.setMethodCallHandler((call) async {
      final args = call.arguments as Map?;
      final position = args?['position'] as double?;
      onRemoteCommand?.call(call.method, position);
    });
  }

  /// Pushes the current playback state to the OS.
  Future<void> update({
    required Track track,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    try {
      await _channel.invokeMethod('update', {
        'title': track.title,
        'artist': track.author,
        'artworkUrl': track.thumbnailUrl,
        'position': position.inMilliseconds / 1000.0,
        'duration': duration.inMilliseconds / 1000.0,
        'playing': isPlaying,
      });
    } catch (_) {
      // Not iOS: nothing to sync.
    }
  }

  /// Clears the Now Playing info (e.g. when playback stops).
  Future<void> clear() async {
    try {
      await _channel.invokeMethod('clear');
    } catch (_) {
      // Not iOS: nothing to clear.
    }
  }

  void dispose() {
    _remote.setMethodCallHandler(null);
    _listening = false;
  }
}
