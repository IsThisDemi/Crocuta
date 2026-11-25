import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/app_theme.dart';

/// The app canvas.
///
/// Glass refracts and blurs whatever sits behind it, so the previous flat
/// black `Wallpaper` gave the chrome nothing to sample and made glass bars
/// look dead — easy to misread as a shader bug.
///
/// The artwork colour shapes the page through [accent], not by drawing the
/// cover itself. A blurred copy of the cover used to sit behind the content,
/// but `ImageFiltered` blurs only within its child's bounds and clips the
/// rest, so a dark cover left a hard-edged rectangle parked behind the list
/// that did not scroll with it. The wash carries the colour just as well.
class AppBackground extends StatelessWidget {
  /// Kept so callers can stay unchanged; only the colour is used now.
  final String? artworkUrl;

  /// Accent override; defaults to the live theme accent.
  final Color? accent;

  /// Strength of the accent wash. Deliberately low: this sits under content
  /// and must never fight with text contrast.
  final double washOpacity;

  final Widget? child;

  const AppBackground({
    super.key,
    this.artworkUrl,
    this.accent,
    this.washOpacity = 0.10,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? context.colors.accent;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base ramp. Slightly lighter at the top so chrome docked at the
        // bottom sits on the darkest part of the canvas.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.ink800, AppColors.ink900],
              stops: [0.0, 0.55],
            ),
          ),
        ),

        // Accent wash, applied over the artwork so the page reads as one
        // colour field rather than an image with a header.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.05),
              radius: 1.25,
              colors: [
                tint.withValues(alpha: washOpacity),
                Colors.transparent,
              ],
            ),
          ),
        ),

        ?child,
      ],
    );
  }
}
