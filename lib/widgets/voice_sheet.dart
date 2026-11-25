import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../services/voice_assistant.dart';
import '../design/spot.dart';
import 'glass_surfaces.dart';

/// Apre l'assistente vocale, gia' in ascolto.
///
/// Un pannello in basso: una macchia viva che si gonfia con la voce, la
/// frase che si scrive mentre la dici, poi la risposta, e si chiude da
/// solo. Toccare la macchia smette di ascoltare ed esegue subito; toccare
/// fuori annulla.
Future<void> showVoiceSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final assistant = container.read(voiceAssistantProvider.notifier);
  unawaited(assistant.listen());
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (_, anim, _, child) {
      final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      );
    },
    pageBuilder: (_, _, _) => const _VoicePanel(),
  );
  // Chiuso mentre ascoltava: si annulla e la musica riparte.
  final phase = container.read(voiceAssistantProvider).phase;
  if (phase == VoicePhase.listening) await assistant.cancel();
}

class _VoicePanel extends ConsumerStatefulWidget {
  const _VoicePanel();

  @override
  ConsumerState<_VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends ConsumerState<_VoicePanel> {
  Timer? _close;

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(voiceAssistantProvider);
    ref.listen(voiceAssistantProvider.select((v) => v.phase), (_, phase) {
      if (phase == VoicePhase.done || phase == VoicePhase.failed) {
        _close?.cancel();
        _close = Timer(
          Duration(milliseconds: phase == VoicePhase.done ? 1400 : 2600),
          () {
            if (mounted) Navigator.of(context).maybePop();
          },
        );
      }
    });

    final accent = context.colors.accent;
    final listening = s.phase == VoicePhase.listening;
    final working = s.phase == VoicePhase.working;
    final failed = s.phase == VoicePhase.failed;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final heard = s.heard.isEmpty
        ? (listening ? 'Listening…' : '')
        : '“${s.heard}”';

    final colors = context.colors;
    final spotColor = failed ? colors.danger : accent;

    // Macchia: niente sfera luminosa. A sinistra una macchia viva del colore
    // del brano, che si gonfia con la voce e gira piu' svelta mentre
    // cerca; a destra quello che stai dicendo, grande, col carattere dei
    // titoli, e sotto gli esempi come parole.
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: GlassPanel(
            radius: 30,
            fallbackTint: AppColors.ink800,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 26, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: listening
                        ? () => ref
                              .read(voiceAssistantProvider.notifier)
                              .stopAndRun()
                        : null,
                    child: _VoiceSpot(
                      color: spotColor,
                      level: listening ? s.level : (working ? 0.3 : 0),
                      fast: working,
                      icon: failed
                          ? Icons.mic_off_rounded
                          : working
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_rounded,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          child: Text(
                            heard.isEmpty ? ' ' : heard,
                            key: ValueKey(heard),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.headlineMedium?.copyWith(
                              fontSize: 30,
                              height: 1.05,
                              color: s.heard.isEmpty
                                  ? colors.textStrong.withValues(alpha: 0.55)
                                  : colors.textStrong,
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          alignment: Alignment.topLeft,
                          child: s.reply.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    s.reply,
                                    style: context.texts.titleMedium?.copyWith(
                                      color: failed
                                          ? colors.danger
                                          : colors.accentMuted,
                                    ),
                                  ),
                                ),
                        ),
                        if (listening) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 14,
                            runSpacing: 2,
                            children: [
                              for (final example in const [
                                'play Hope by XXXTentacion',
                                'something by Yeat',
                                'my liked songs',
                              ])
                                Text(
                                  '“$example”',
                                  style: context.texts.titleSmall?.copyWith(
                                    color: colors.accentMuted.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La macchia della voce: viva come tutte, si gonfia col volume di quello
/// che dici, e mentre l'assistente lavora ondeggia piu' svelta. Due gocce
/// piccole le stanno accanto, come i satelliti delle copertine.
class _VoiceSpot extends StatelessWidget {
  final Color color;
  final double level;
  final bool fast;
  final IconData icon;

  const _VoiceSpot({
    required this.color,
    required this.level,
    required this.fast,
    required this.icon,
  });

  static const double _size = 92;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 18,
      height: _size + 10,
      child: SpotMotionBuilder(
        builder: (context, t) {
          final speed = fast ? 4.0 : 2.2;
          final time = t == null ? null : t * speed;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: 0,
                top: 0,
                width: 20,
                height: 20,
                child: AnimatedScale(
                  scale: 0.8 + level * 0.8,
                  duration: const Duration(milliseconds: 140),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: color.withValues(alpha: 0.7),
                      shape: SpotBorder(seed: 'voice#1', time: time),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                bottom: 0,
                width: 11,
                height: 11,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: color.withValues(alpha: 0.5),
                    shape: SpotBorder(seed: 'voice#2', time: time),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 4,
                width: _size,
                height: _size,
                child: AnimatedScale(
                  scale: 0.9 + level * 0.32,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: color,
                      shape: SpotBorder(seed: 'voice', time: time),
                    ),
                    child: Icon(icon, size: 36, color: AppColors.ink900),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
