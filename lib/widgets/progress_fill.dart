import 'package:flutter/material.dart';

import '../design/app_theme.dart';

/// Il pulsante stesso come barra di avanzamento: il suo fondo si riempie
/// del colore del brano, da sinistra, man mano che il lavoro va avanti.
///
/// Al posto di fogli e barre a parte: il lavoro l'hai chiesto premendo
/// qui, e qui si vede a che punto e'. Con [progress] nullo non disegna
/// niente.
class ProgressFill extends StatelessWidget {
  final double? progress;
  final ShapeBorder shape;
  final Widget child;

  /// Sopra il figlio invece che sotto: per i pulsanti di vetro, che il
  /// loro fondo se lo disegnano da soli e lo coprirebbero.
  final bool over;

  const ProgressFill({
    super.key,
    required this.progress,
    required this.child,
    this.shape = const StadiumBorder(),
    this.over = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) return child;
    final fill = Positioned.fill(
      child: IgnorePointer(
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: p.clamp(0.0, 1.0)),
              duration: AppMotion.base,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => FractionallySizedBox(
                widthFactor: v,
                heightFactor: 1,
                child: ColoredBox(
                  color: context.colors.accent.withValues(
                    alpha: over ? 0.35 : 0.28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      children: over ? [child, fill] : [fill, child],
    );
  }
}

/// Il lavoro di un pulsante che si riempie: riferisce quanti passi ha
/// fatto su quanti, e si ferma se [cancelled] diventa vero.
typedef FillJob<T> =
    Future<T?> Function(
      void Function(int done, int total) onProgress,
      bool Function() cancelled,
    );

/// Un pulsante che avvia un lavoro lungo e si riempie mentre va. Premuto
/// di nuovo, lo annulla.
class FillJobButton<T> extends StatefulWidget {
  final FillJob<T> job;
  final void Function(T result) onDone;

  /// Il pulsante vero: riceve l'avanzamento (nullo a riposo) e cosa fare
  /// al tocco.
  final Widget Function(
    BuildContext context,
    double? progress,
    VoidCallback onTap,
  )
  builder;

  const FillJobButton({
    super.key,
    required this.job,
    required this.onDone,
    required this.builder,
  });

  @override
  State<FillJobButton<T>> createState() => _FillJobButtonState<T>();
}

class _FillJobButtonState<T> extends State<FillJobButton<T>> {
  double? _progress;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _tap() async {
    if (_progress != null) {
      // Di nuovo durante il lavoro: annulla.
      _cancelled = true;
      setState(() => _progress = null);
      return;
    }
    _cancelled = false;
    setState(() => _progress = 0);
    final result = await widget.job((done, total) {
      if (mounted && !_cancelled && total > 0) {
        setState(() => _progress = done / total);
      }
    }, () => _cancelled);
    if (!mounted || _cancelled) return;
    setState(() => _progress = null);
    if (result != null) widget.onDone(result);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _progress, _tap);
}
