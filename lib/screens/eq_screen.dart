import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    hide GlassButton, GlassMenuItem;

import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../providers.dart';
import '../services/artwork.dart';
import '../services/eq_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/artwork_backdrop.dart';
import '../widgets/content_width.dart';
import '../widgets/glass_surfaces.dart';
import '../design/spot.dart';

/// L'equalizzatore, come quello di Musica sul Mac: acceso o spento, un
/// menu di preset, il preamplificatore e dieci bande.
///
/// I cursori sono verticali perche' e' la forma che ha un equalizzatore:
/// si leggono come una curva sola, e la curva e' disegnata per davvero,
/// dagli stessi numeri che mettono i pallini dove sono.
class EqScreen extends ConsumerWidget {
  const EqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(eqProvider);
    final notifier = ref.read(eqProvider.notifier);
    final track = ref.watch(playerProvider.select((s) => s.current));
    final art = track?.thumbnailUrl ?? '';
    final backdrop = ref.watch(backdropColorProvider(art));

    return AccentScope(
      // Come il player e i testi: la pagina prende il colore del brano che
      // si sta ascoltando, che e' esattamente quello che si sta regolando.
      artworkUrl: art,
      child: GlassScaffold(
        background: ArtworkBackdrop(
          artUrl: hiResArtwork(art) ?? art,
          baseColor: backdrop.valueOrNull ?? Colors.black,
          palette: ref.watch(artworkPaletteProvider(art)).valueOrNull,
          trackId: track?.id ?? '',
        ),
        statusBarStyle: GlassStatusBarStyle.light,
        topEdgeFade: hasStatusBarFade,
        topEdgeFadeExtent: statusBarOnlyFade,
        appBar: AppTopBar(
          title: 'Equalizer',
          actions: [
            // Spegnere non cancella niente: e' il confronto al volo con e
            // senza, che prima si poteva fare solo azzerando tutto.
            // Verde come gli interruttori delle impostazioni: acceso deve
            // leggersi acceso anche quando l'accento della copertina e'
            // un grigio chiaro.
            Switch.adaptive(
              value: eq.enabled,
              activeTrackColor: context.colors.accent,
              onChanged: notifier.setEnabled,
            ),
          ],
        ),
        body: Material(
          type: MaterialType.transparency,
          // Colonna centrata: su una finestra larga i fader si stiravano a
          // tutto schermo e l'equalizzatore diventava illeggibile.
          child: ContentWidth(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                topBarInset(context),
                AppSpacing.md,
                listBottomPadding(context, ref),
              ),
              children: const [EqPanel()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Il contenuto dell'equalizzatore senza pagina attorno: preset, curva e
/// due righe di aiuto. Lo usano la pagina e il foglio che il player apre
/// sopra di se'.
class EqPanel extends ConsumerWidget {
  const EqPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(eqProvider);
    final notifier = ref.read(eqProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetBar(eq: eq),
        const SizedBox(height: AppSpacing.sm),
        AnimatedOpacity(
          duration: AppMotion.fast,
          // Spento resta visibile, ma si vede che non agisce.
          opacity: eq.enabled ? 1 : 0.4,
          // Il grafico sta sul nero del foglio, senza cornice: era un
          // riquadro dentro il riquadro.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: EqGraph(
              preamp: eq.preamp,
              gains: eq.gains,
              labels: [for (final b in eq.bands) b.label],
              onPreamp: notifier.setPreamp,
              onBand: notifier.setBand,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Drag a band to adjust it, double-tap to reset it. '
          'Lower the preamp if boosted bands start to distort.',
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.textFaint,
          ),
        ),
      ],
    );
  }
}

/// L'equalizzatore come foglio di vetro sopra il player: si regola il suono
/// guardando ancora il brano, senza cambiare pagina.
Future<void> showEqSheet(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    // Il foglio sta sul navigator radice, fuori dall'AccentScope del
    // player: senza ridarglielo i controlli tornerebbero al colore di marca.
    builder: (sheet) => Consumer(
      builder: (context, ref, _) {
        final art =
            ref.watch(playerProvider.select((s) => s.current))?.thumbnailUrl ??
            '';
        final eq = ref.watch(eqProvider);
        return AccentScope(
          artworkUrl: art,
          child: Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Equalizer',
                          style: context.texts.headlineMedium,
                        ),
                      ),
                      Switch.adaptive(
                        value: eq.enabled,
                        activeTrackColor: context.colors.accent,
                        onChanged: ref.read(eqProvider.notifier).setEnabled,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const EqPanel(),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Il menu dei preset, e cosa fare con le regolazioni che non sono un
/// preset: salvarle.
class _PresetBar extends ConsumerWidget {
  final EqState eq;

  const _PresetBar({required this.eq});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(eqProvider.notifier);
    final active = eq.activePreset;

    Future<void> openMenu(BuildContext anchor) async {
      final box = anchor.findRenderObject() as RenderBox;
      final picked = await showGlassMenu<EqPreset>(
        context: context,
        globalPosition: box.localToGlobal(box.size.bottomLeft(Offset.zero)),
        items: [
          for (final p in eq.allPresets)
            GlassMenuItem(
              value: p,
              icon: p.name == active?.name
                  ? Icons.check_rounded
                  : p.custom
                  ? Icons.person_rounded
                  : Icons.graphic_eq_rounded,
              label: p.name,
            ),
        ],
      );
      if (picked != null) await notifier.applyPreset(picked);
    }

    return Row(
      children: [
        Builder(
          // Il preset come parola nel colore del brano, non una capsula.
          builder: (anchor) => Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: AppRadius.br(AppRadius.md),
              onTap: () => openMenu(anchor),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      active?.name ?? 'Custom',
                      style: context.texts.headlineSmall?.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 24,
                      color: context.colors.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (active == null)
          TextButton.icon(
            onPressed: () => _askName(context, notifier),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Save Preset'),
            style: TextButton.styleFrom(foregroundColor: context.colors.accent),
          )
        else if (active.custom)
          TextButton.icon(
            onPressed: () => notifier.deletePreset(active.name),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
          ),
      ],
    );
  }

  Future<void> _askName(BuildContext context, EqController notifier) async {
    final name = await showGlassTextPrompt(
      context: context,
      title: 'Save Preset',
      message: 'Enter a name for this preset.',
      hint: 'Name',
      confirmLabel: 'Save',
    );
    if (name != null) await notifier.savePreset(name);
  }
}

/// Il preamplificatore e le dieci bande, in un disegno solo.
///
/// Un componente unico e non undici Slider: con gli Slider la corsa del
/// pallino rientrava dal bordo del raggio del suo alone (18 px) mentre la
/// curva dietro rientrava del raggio del pallino (9): la linea passava
/// qualche pixel sopra i pallini, e il +6 sembrava un +7. Qui pallini e
/// curva escono dalla stessa funzione, e coincidono per costruzione.
class EqGraph extends StatefulWidget {
  final double preamp;
  final List<double> gains;
  final List<String> labels;
  final ValueChanged<double> onPreamp;
  final void Function(int band, double gain) onBand;

  const EqGraph({
    super.key,
    required this.preamp,
    required this.gains,
    required this.labels,
    required this.onPreamp,
    required this.onBand,
  });

  /// Escursione, in dB, di bande e preamplificatore.
  static const double range = 12;

  /// Altezza della corsa.
  static const double height = 220;

  /// Il pallino non esce dal disegno: la corsa rientra del suo raggio.
  static const double knob = 8;

  /// Da gain a y, e ritorno. Le usano il disegno e il tocco, cosi' non
  /// possono divergere.
  static double yOf(double gain) {
    final t = (gain + range) / (range * 2);
    return height - knob - t * (height - knob * 2);
  }

  static double gainAt(double y) {
    final t = (height - knob - y) / (height - knob * 2);
    final g = (t * range * 2 - range).clamp(-range, range);
    // Mezzo decibel: sotto non si sente, e agganciare aiuta a tornare
    // esattamente a zero.
    return (g * 2).roundToDouble() / 2;
  }

  @override
  State<EqGraph> createState() => _EqGraphState();
}

class _EqGraphState extends State<EqGraph> {
  /// La colonna presa all'inizio del gesto: trascinando si resta su quella
  /// anche se il dito scivola di lato, come su un mixer vero.
  int? _column;
  double? _lastTapX;

  /// Colonna 0 il preamplificatore, 1..10 le bande.
  int get _columns => widget.gains.length + 1;

  int _columnAt(double x, double width) =>
      (x / (width / _columns)).floor().clamp(0, _columns - 1);

  void _set(int column, double gain) {
    final current = column == 0 ? widget.preamp : widget.gains[column - 1];
    if (current == gain) return;
    // Uno scatto leggero a ogni mezzo decibel e piu' marcato sullo zero:
    // si sente quando si e' tornati piatti senza guardare.
    if (gain == 0) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    if (column == 0) {
      widget.onPreamp(gain);
    } else {
      widget.onBand(column - 1, gain);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final colW = width / _columns;
        return Column(
          children: [
            Semantics(
              label: 'Equalizer',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (d) {
                  _column = _columnAt(d.localPosition.dx, width);
                  _set(_column!, EqGraph.gainAt(d.localPosition.dy));
                },
                onVerticalDragUpdate: (d) {
                  if (_column != null) {
                    _set(_column!, EqGraph.gainAt(d.localPosition.dy));
                  }
                },
                onVerticalDragEnd: (_) => _column = null,
                onDoubleTapDown: (d) => _lastTapX = d.localPosition.dx,
                onDoubleTap: () {
                  if (_lastTapX == null) return;
                  _set(_columnAt(_lastTapX!, width), 0);
                },
                child: SizedBox(
                  height: EqGraph.height,
                  width: width,
                  child: SpotMotionBuilder(
                    builder: (context, t) => CustomPaint(
                      painter: _GraphPainter(
                        preamp: widget.preamp,
                        gains: widget.gains,
                        accent: accent,
                        active: _column,
                        time: t,
                        music: SpotMotion.musicOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                for (var c = 0; c < _columns; c++)
                  SizedBox(
                    width: colW,
                    child: _Label(
                      top: c == 0 ? 'Pre' : widget.labels[c - 1],
                      value: c == 0 ? widget.preamp : widget.gains[c - 1],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String top;
  final double value;

  const _Label({required this.top, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Column(
      children: [
        Text(
          top,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: context.texts.labelSmall?.copyWith(
            color: context.colors.textMuted,
            letterSpacing: 0,
          ),
        ),
        Text(
          '${value > 0 ? '+' : ''}$v',
          maxLines: 1,
          style: context.texts.labelSmall?.copyWith(
            letterSpacing: 0,
            fontFeatures: AppTypography.tabular,
            color: value == 0
                ? context.colors.textFaint
                : context.colors.accent,
          ),
        ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  final double preamp;
  final List<double> gains;
  final Color accent;
  final int? active;

  /// L'orologio delle macchie: i cursori sono macchioline vive.
  final double? time;

  /// La musica in ascolto: anche i cursori si muovono con lei.
  final SpotMusic music;

  const _GraphPainter({
    required this.preamp,
    required this.gains,
    required this.accent,
    this.active,
    this.time,
    this.music = silentMusic,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final columns = gains.length + 1;
    final colW = size.width / columns;
    double xOf(int c) => colW * c + colW / 2;
    final zeroY = EqGraph.yOf(0);

    // Lo zero, da una parte all'altra delle bande: senza non si capisce
    // cosa e' alzato e cosa abbassato.
    canvas.drawLine(
      Offset(colW, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
    // Il preamplificatore sta a parte, come sul Mac: agisce su tutto, non
    // e' un punto della curva.
    canvas.drawLine(
      Offset(colW, 4),
      Offset(colW, size.height - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );

    // La curva e la velatura, dagli stessi punti dei pallini.
    final points = [
      for (var i = 0; i < gains.length; i++)
        Offset(xOf(i + 1), EqGraph.yOf(gains[i])),
    ];
    final path = Path()..moveTo(colW, points.first.dy);
    path.lineTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    path.lineTo(size.width, points.last.dy);
    canvas.drawPath(
      Path.from(path)
        ..lineTo(size.width, zeroY)
        ..lineTo(colW, zeroY)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.24),
            accent.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Corse e pallini.
    for (var c = 0; c < columns; c++) {
      final gain = c == 0 ? preamp : gains[c - 1];
      final x = xOf(c);
      final y = EqGraph.yOf(gain);
      canvas.drawLine(
        Offset(x, EqGraph.knob),
        Offset(x, size.height - EqGraph.knob),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.09)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      if (gain != 0) {
        canvas.drawLine(
          Offset(x, zeroY),
          Offset(x, y),
          Paint()
            ..color = accent
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
      // Il cursore e' una macchiolina viva del colore del brano, come
      // ogni comando dell'app; quella che stai trascinando si gonfia.
      final r = EqGraph.knob + (c == active ? 6 : 3);
      canvas.drawPath(
        spotPath(
          swollenRect(
            Rect.fromCircle(center: Offset(x, y), radius: r),
            music.pulse,
          ),
          'eq#$c',
          wobble: 0.8,
          time: time == null ? null : time! * 1.6,
          music: music,
        ),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.preamp != preamp ||
      old.accent != accent ||
      old.active != active ||
      old.time != time ||
      old.music != music ||
      !_same(old.gains, gains);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
