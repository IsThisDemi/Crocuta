import 'package:flutter/material.dart';

import '../design/app_theme.dart';

/// La luce del brano sul fondo nero: Macchia non stende la copertina
/// sfocata dietro le pagine, la base resta nera e il colore sale da un
/// angolo come una luce. Il player, le pagine di album e playlist, i testi e
/// l'equalizzatore la usano tutti, cosi' "pagina con un colore suo" ha un
/// aspetto solo.
class AccentGlow extends StatelessWidget {
  /// Il colore principale, in alto a sinistra.
  final Color color;

  /// Un secondo colore della copertina, in basso a destra.
  final Color? second;

  const AccentGlow({super.key, required this.color, this.second});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: second ?? color),
      duration: AppMotion.backdrop,
      builder: (context, other, _) => DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.ink900),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.25, -0.55),
                  radius: 1.05,
                  colors: [
                    color.withValues(alpha: 0.30),
                    color.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, 1.0),
                  radius: 0.9,
                  colors: [
                    (other ?? color).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
