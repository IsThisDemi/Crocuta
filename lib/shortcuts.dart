import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'services/voice_assistant.dart';

/// Desktop keyboard shortcuts, installed above the Navigator so they work on
/// every screen.
///
/// The awkward one is Space: it has to pause playback, except while the user
/// is typing in the search box, where it must type a space. Two defences,
/// because either alone eventually fails:
///
/// 1. [SearchFieldShortcuts] shadows the movement keys for the subtree that
///    owns the text field — the idiomatic, local fix.
/// 2. [_isEditing] refuses to act whenever focus sits inside any editable
///    text, which covers fields added later (the playlist rename dialog, a
///    future settings screen) without each one remembering to opt in.
class AppShortcuts extends ConsumerWidget {
  final Widget child;

  const AppShortcuts({super.key, required this.child});

  static const _step = Duration(seconds: 10);
  static const _volumeStep = 5.0;

  /// True when the focused widget is a text field.
  static bool _isEditing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Harmless on iOS, but an external iPad keyboard should not silently
    // inherit a desktop key map.
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return child;
    }

    void guarded(VoidCallback action) {
      if (_isEditing()) return;
      action();
    }

    final player = ref.read(playerProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            guarded(player.toggle),

        const SingleActivator(LogicalKeyboardKey.arrowRight): () => guarded(() {
          final s = ref.read(playerProvider);
          final target = s.position + _step;
          player.seek(target > s.duration ? s.duration : target);
        }),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => guarded(() {
          final target = ref.read(playerProvider).position - _step;
          player.seek(target < Duration.zero ? Duration.zero : target);
        }),

        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () =>
            guarded(player.next),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () =>
            guarded(player.previous),

        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            guarded(() => player.adjustVolume(_volumeStep)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            guarded(() => player.adjustVolume(-_volumeStep)),

        // ⌘F works even while typing: it means "take me to search".
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          ref.read(navTabProvider.notifier).select(NavTabController.search);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(searchFocusProvider).requestFocus();
          });
        },

        // ⌘K: l'assistente vocale.
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            voiceRequests.value++,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            voiceRequests.value++,

        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () =>
            guarded(() {
              final track = ref.read(playerProvider).current;
              if (track != null) {
                ref.read(favoritesProvider.notifier).toggle(track);
              }
            }),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            guarded(player.toggleShuffle),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
            guarded(player.toggleRepeat),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// Shadows the keys [AppShortcuts] claims, for the subtree containing a text
/// field. An inner Shortcuts wins over an outer one for the focused subtree,
/// and [DoNothingAndStopPropagationIntent] keeps the key from bubbling up.
class SearchFieldShortcuts extends StatelessWidget {
  final Widget child;

  const SearchFieldShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space):
            DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            DoNothingAndStopPropagationIntent(),
      },
      child: child,
    );
  }
}
