import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import 'glass_surfaces.dart';

/// Dove stanno la riga sollevata e il menu.
typedef LiftedMenuLayout = ({Rect preview, Offset menu, bool below});

/// Calcola la posizione di riga e menu, come fa iOS.
///
/// Il menu va sotto la riga se ci sta, sopra se ci sta li'. Se non ci sta
/// da nessuna parte — una riga a meta' schermo su un telefono basso — e'
/// la riga a salire, quanto basta perche' il menu entri sotto di lei: e'
/// quello che fa iOS, invece di coprire la riga col menu.
LiftedMenuLayout liftedMenuLayout({
  required Size screen,
  required EdgeInsets safe,
  required Rect anchor,
  required Size menu,
  double gap = AppSpacing.xs,
  double margin = AppSpacing.xs,
}) {
  final minTop = safe.top + margin;
  final maxBottom = screen.height - safe.bottom - margin;

  // Allineato al bordo sinistro della riga, ma dentro lo schermo.
  final left = (anchor.left + AppSpacing.md).clamp(
    AppSpacing.xs,
    screen.width - menu.width - AppSpacing.xs,
  );

  if (anchor.bottom + gap + menu.height <= maxBottom) {
    return (
      preview: anchor,
      menu: Offset(left, anchor.bottom + gap),
      below: true,
    );
  }
  if (anchor.top - gap - menu.height >= minTop) {
    return (
      preview: anchor,
      menu: Offset(left, anchor.top - gap - menu.height),
      below: false,
    );
  }
  var shift = maxBottom - (anchor.bottom + gap + menu.height);
  if (anchor.top + shift < minTop) shift = minTop - anchor.top;
  final preview = anchor.shift(Offset(0, shift));
  return (
    preview: preview,
    menu: Offset(left, preview.bottom + gap),
    below: true,
  );
}

/// Il menu della pressione lunga, come in iOS.
///
/// La riga si solleva al suo posto, tutto il resto si sfoca, e il menu
/// compare attaccato a lei. Prima si apriva un foglio dal basso: le azioni
/// c'erano, ma lontane dal dito e senza dire a quale riga si riferivano se
/// non ripetendone titolo e copertina.
///
/// [anchor] e' il rettangolo della riga sullo schermo; [preview] e' cio' che
/// si disegna li' sopra, di solito la riga stessa.
Future<T?> showLiftedMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required Widget preview,
  required List<GlassMenuItem<T>> items,
}) {
  return showGeneralDialog<T>(
    context: context,
    // Sopra la chrome della shell: tab bar e mini player vanno sfocati
    // come il resto.
    useRootNavigator: true,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: AppMotion.base,
    pageBuilder: (ctx, anim, _) => _LiftedMenu<T>(
      anim: anim,
      anchor: anchor,
      preview: preview,
      items: items,
    ),
  );
}

class _LiftedMenu<T> extends StatelessWidget {
  final Animation<double> anim;
  final Rect anchor;
  final Widget preview;
  final List<GlassMenuItem<T>> items;

  const _LiftedMenu({
    required this.anim,
    required this.anchor,
    required this.preview,
    required this.items,
  });

  static const double _rowHeight = 44;
  static const double _width = 250;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final menuSize = Size(
      _width,
      items.length * _rowHeight + AppSpacing.xxs * 2,
    );
    final layout = liftedMenuLayout(
      screen: mq.size,
      safe: mq.padding,
      anchor: anchor,
      menu: menuSize,
    );
    final t = CurvedAnimation(parent: anim, curve: AppMotion.standard);
    final pop = CurvedAnimation(
      parent: anim,
      curve: AppMotion.emphasised,
      reverseCurve: Curves.easeIn,
    );

    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        final rect = Rect.lerp(anchor, layout.preview, v)!;
        return Stack(
          children: [
            // Lo sfondo sfocato e un filo piu' scuro; toccarlo chiude.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18 * v, sigmaY: 18 * v),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.28 * v),
                  ),
                ),
              ),
            ),
            // La riga sollevata: leggermente piu' grande, su un fondo suo
            // e con l'ombra, perche' si stacchi dallo sfocato.
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1 + 0.03 * v,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.br(AppRadius.md),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4 * v),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Material(
                        color: AppColors.ink700.withValues(alpha: v),
                        borderRadius: AppRadius.br(AppRadius.md),
                        clipBehavior: Clip.antiAlias,
                        child: preview,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: layout.menu.dx,
              top: layout.menu.dy + (rect.top - layout.preview.top),
              width: menuSize.width,
              child: FadeTransition(
                opacity: t,
                child: ScaleTransition(
                  // Cresce dal lato della riga, come se ne uscisse.
                  alignment: layout.below
                      ? Alignment.topLeft
                      : Alignment.bottomLeft,
                  scale: Tween(begin: 0.6, end: 1.0).animate(pop),
                  child: GlassPanel(
                    radius: AppRadius.md,
                    fallbackTint: AppColors.ink600,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.xxs),
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: context.colors.glassStroke,
                            ),
                          _Row<T>(
                            item: items[i],
                            height: _rowHeight - (i > 0 ? 0.5 : 0),
                            onTap: () =>
                                Navigator.of(context).pop(items[i].value),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxs),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Una voce: testo a sinistra, icona a destra, come nei menu di iOS.
class _Row<T> extends StatelessWidget {
  final GlassMenuItem<T> item;
  final double height;
  final VoidCallback onTap;

  const _Row({required this.item, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled
        ? context.colors.textFaint
        : item.isDestructive
        ? context.colors.danger
        : context.colors.textStrong;
    return InkWell(
      onTap: item.enabled ? onTap : null,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(item.icon, size: 19, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
