import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_theme.dart';

/// L'icona dell'app, disegnata qui: la C fatta di macchie.
///
/// E' lo stesso disegno di tool/make_icons.py — tre anelli di macchie sugli
/// stessi tredici raggi, grandi sul dorso della C e piccole alle punte, con
/// gli stessi numeri — ma senza il fondo dell'icona, e con le macchie nel
/// colore del brano. Cosi' anche il marchio, accanto al nome nella tana,
/// cambia con la musica come tutto il resto.
class CrocutaMark extends StatelessWidget {
  final double size;

  const CrocutaMark({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return Semantics(
      label: 'Crocuta',
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(accent),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color accent;

  _MarkPainter(this.accent);

  // Gli stessi numeri di tool/make_icons.py.
  static const _rings = [0.335, 0.255, 0.175];
  static const _rays = 13;
  static const _gap = 58 * math.pi / 180;
  static const _shift = 0.055;
  static const _spotMax = 0.038;
  static const _spotMin = 0.013;

  @override
  void paint(Canvas canvas, Size size) {
    final n = size.width;

    // Solo le macchie, senza fondo: sono loro a prendere il colore del
    // brano, e accanto al nome bastano a dire che e' Crocuta.
    final spot = Paint()..color = accent;
    final cx = n * (0.5 + _shift), cy = n * 0.5;
    for (var ring = 0; ring < _rings.length; ring++) {
      final radius = _rings[ring] * n;
      final weight = 1 - ring / _rings.length * 0.55;
      for (var k = 0; k < _rays; k++) {
        final a = _gap + (2 * math.pi - 2 * _gap) * k / (_rays - 1);
        final back = math.cos((a - math.pi) / (math.pi - _gap) * math.pi / 2);
        final s =
            (_spotMin +
                (_spotMax - _spotMin) *
                    math.pow(back.clamp(0.0, 1.0), 1.1) *
                    weight) *
            n;
        canvas.drawCircle(
          Offset(cx + radius * math.cos(a), cy - radius * math.sin(a)),
          s,
          spot,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.accent != accent;
}
