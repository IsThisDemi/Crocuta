import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';

/// The "nothing here yet" placeholder.
///
/// Replaces seven hand-rolled variants that each picked their own icon size,
/// spacing and opacity.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Una macchia spenta del colore del brano con l'icona dentro,
            // e una piccola accanto: lo stesso segno delle copertine, vuoto.
            SizedBox(
              width: 118,
              height: 100,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: 92,
                    height: 92,
                    child: SpotMotionBuilder(
                      builder: (context, t) => DecoratedBox(
                        decoration: ShapeDecoration(
                          color: context.colors.accentMuted.withValues(
                            alpha: 0.22,
                          ),
                          shape: SpotBorder(
                            seed: title,
                            time: t,
                            music: SpotMotion.musicOf(context),
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 40,
                          color: context.colors.accent,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    width: 26,
                    height: 26,
                    child: SpotMotionBuilder(
                      builder: (context, t) => DecoratedBox(
                        decoration: ShapeDecoration(
                          color: context.colors.accent.withValues(alpha: 0.5),
                          shape: SpotBorder(
                            seed: '$title#2',
                            time: t,
                            music: SpotMotion.musicOf(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.headlineMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
