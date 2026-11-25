import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three bars bouncing to suggest playback.
///
/// This is what finally gives `TrackTile.isPlaying` something to do: the flag
/// was declared and passed by five call sites but never read in `build`, so a
/// list gave no sign of which row was actually sounding.
///
/// One controller drives a CustomPainter, and `TickerMode` (which `Offstage`
/// and `IndexedStack` set for you) stops it whenever the row is not visible.
class EqualizerBars extends StatefulWidget {
  final Color color;
  final double size;

  /// Paused rows keep the bars but hold them still.
  final bool animating;

  const EqualizerBars({
    super.key,
    required this.color,
    this.size = 16,
    this.animating = true,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animating) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.animating && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animating && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _BarsPainter(t: _c.value, color: widget.color),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double t;
  final Color color;

  _BarsPainter({required this.t, required this.color});

  // Offset phases so the bars never move in lockstep.
  static const _phases = [0.0, 0.35, 0.7];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.2;

    final gap = size.width * 0.4;
    for (var i = 0; i < _phases.length; i++) {
      final wave = (math.sin((t + _phases[i]) * 2 * math.pi) + 1) / 2;
      final h = size.height * (0.28 + 0.62 * wave);
      final x = paint.strokeWidth / 2 + i * gap;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t || old.color != color;
}
