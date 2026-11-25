import '../models/track.dart';

enum RepeatMode { off, all, one }

/// Immutable snapshot of the player's state.
class PlayerState {
  final List<Track> queue;
  final int currentIndex; // -1 when nothing is loaded
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final RepeatMode repeat;
  final String? error;

  /// Crossfade duration (0 = disabled).
  final Duration crossfadeDuration;

  /// AutoMix: transizioni scelte brano per brano, al posto della
  /// dissolvenza a durata fissa. Quando e' acceso [crossfadeDuration] non
  /// conta.
  final bool automix;

  /// Una transizione di AutoMix in corso: due brani suonano insieme, e la
  /// barra mostra il mix invece del tempo del brano che finisce.
  final bool mixing;

  /// Output volume, 0-100. Persisted only in memory; the crossfade fades
  /// back to this rather than to a hardcoded 100, which used to reset the
  /// user's volume on every track change.
  final double volume;

  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.error,
    this.crossfadeDuration = Duration.zero,
    this.automix = false,
    this.mixing = false,
    this.volume = 100,
  });

  Track? get current => currentIndex >= 0 && currentIndex < queue.length
      ? queue[currentIndex]
      : null;

  PlayerState copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    RepeatMode? repeat,
    String? error,
    bool clearError = false,
    Duration? crossfadeDuration,
    bool? automix,
    bool? mixing,
    double? volume,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      error: clearError ? null : (error ?? this.error),
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      automix: automix ?? this.automix,
      mixing: mixing ?? this.mixing,
      volume: volume ?? this.volume,
    );
  }
}
