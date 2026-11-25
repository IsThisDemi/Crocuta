import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import 'content_width.dart';
import 'thumbnail.dart';

/// Una voce del manto: copertina, didascalia, cosa fa il tocco.
class CoatItem {
  final String imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CoatItem({
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.onLongPress,
  });
}

/// Le copertine disposte come le macchie di un manto.
///
/// Due file sfalsate di mezza colonna, con macchie di misure diverse: la
/// seconda fila si incastra negli spazi della prima invece di starle sotto
/// in righe e colonne. E' la sezione che dice "Macchia" appena si apre la
/// Home, quindi la disposizione e' fissa (le misure seguono un ritmo, non il
/// caso) e cambia solo la larghezza delle colonne.
///
/// Se le colonne a misura piena non ci stanno — il telefono — il manto
/// scorre di lato invece di rimpicciolirsi.
class SpotCoat extends StatelessWidget {
  final List<CoatItem> items;

  /// La larghezza di una colonna sotto la quale il manto smette di
  /// stringersi e comincia a scorrere.
  final double minColumn;

  /// Quella oltre la quale non si allarga piu': su un monitor grande nove
  /// copertine larghe trecento pixel diventano un muro.
  final double maxColumn;

  const SpotCoat({
    super.key,
    required this.items,
    this.minColumn = 138,
    this.maxColumn = 230,
  });

  /// Il ritmo delle misure: grande, piccola, media... mai due uguali vicine.
  static const _sizes = [1.0, 0.74, 0.9, 0.68, 0.96, 0.8, 0.7, 0.92, 0.78];

  /// Quanto ogni macchia scende dalla cima della sua fila, in frazioni della
  /// colonna: le piccole stanno piu' in basso, cosi' le didascalie non
  /// formano una riga dritta.
  static const _drop = [0.0, 0.16, 0.04, 0.2, 0.0, 0.1, 0.18, 0.02, 0.12];

  static const double _caption = 50;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final top = (items.length + 1) ~/ 2;
    final bleed = AppSpacing.gutter + RailBleed.of(context);

    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - bleed * 2;
        final fit = avail / (top + 0.5);
        final col = fit.clamp(minColumn, maxColumn).toDouble();
        final scrolls = fit < minColumn;
        final width = col * (top + 0.5);

        // Prima fila sulle colonne intere, seconda a meta' fra due.
        final placed = <({Offset at, double size, CoatItem item})>[];
        var rowOneBottom = 0.0;
        for (var i = 0; i < items.length; i++) {
          final first = i < top;
          final k = first ? i : i - top;
          final size = col * 0.88 * _sizes[i % _sizes.length];
          final cx = (first ? k + 0.5 : k + 1.0) * col;
          final dy = col * _drop[i % _drop.length];
          placed.add((
            at: Offset(cx - size / 2, dy),
            size: size,
            item: items[i],
          ));
          if (first) {
            rowOneBottom = math.max(rowOneBottom, dy + size + _caption);
          }
        }
        // La seconda fila sale un poco dentro la prima: e' l'incastro.
        final rowTwoTop = rowOneBottom - col * 0.14;
        var height = rowOneBottom;
        for (var i = top; i < placed.length; i++) {
          final p = placed[i];
          placed[i] = (
            at: p.at.translate(0, rowTwoTop),
            size: p.size,
            item: p.item,
          );
          height = math.max(height, p.at.dy + rowTwoTop + p.size + _caption);
        }

        final coat = SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final p in placed)
                Positioned(
                  left: p.at.dx - (col - p.size) / 2,
                  top: p.at.dy,
                  width: col,
                  child: _CoatSpot(item: p.item, size: p.size),
                ),
            ],
          ),
        );

        final padded = Padding(
          padding: EdgeInsets.symmetric(horizontal: bleed),
          child: coat,
        );
        if (!scrolls) return Align(alignment: Alignment.topLeft, child: padded);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: padded,
        );
      },
    );
  }
}

class _CoatSpot extends StatefulWidget {
  final CoatItem item;
  final double size;

  const _CoatSpot({required this.item, required this.size});

  @override
  State<_CoatSpot> createState() => _CoatSpotState();
}

class _CoatSpotState extends State<_CoatSpot> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scale = _down ? 0.96 : (_hover ? 1.04 : 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        onLongPress: item.onLongPress,
        onSecondaryTap: item.onLongPress,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: scale,
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              child: SizedBox.square(
                dimension: widget.size,
                child: SpotThumbnail(url: item.imageUrl),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            CoatCaption(title: item.title, subtitle: item.subtitle),
          ],
        ),
      ),
    );
  }
}

/// La didascalia sotto una macchia: titolo chiaro, riga sotto nel colore
/// del brano spento. Centrata, perche' la macchia non ha un bordo sinistro
/// a cui allinearsi.
class CoatCaption extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextAlign align;

  const CoatCaption({
    super.key,
    required this.title,
    this.subtitle,
    this.align = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: context.texts.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.accentMuted,
            ),
          ),
      ],
    );
  }
}

/// Un grappolo: tre copertine come tre macchie vicine, una grande e due
/// piccole. E' la faccia di una raccolta — un mix, una stazione, una
/// playlist — che non ha una copertina sua ma e' fatta di altre.
class SpotCluster extends StatelessWidget {
  final List<String> urls;
  final double size;

  /// Un segno al centro della macchia grande (l'icona di un mix).
  final Widget? badge;

  const SpotCluster({
    super.key,
    required this.urls,
    required this.size,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final u = [...urls.where((x) => x.isNotEmpty)];
    String at(int i) => u.isEmpty ? '' : u[i % u.length];
    final big = size * 0.74;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (u.length > 1)
            Positioned(
              right: 0,
              top: 0,
              width: size * 0.42,
              height: size * 0.42,
              child: SpotThumbnail(url: at(1)),
            ),
          if (u.length > 2)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.04,
              width: size * 0.28,
              height: size * 0.28,
              child: SpotThumbnail(url: at(2)),
            ),
          Positioned(
            left: 0,
            bottom: 0,
            width: big,
            height: big,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SpotThumbnail(url: at(0)),
                if (badge != null) Center(child: badge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una griglia lunga (gli album della libreria, le uscite) disposta come un
/// manto: le colonne dispari scendono di mezza macchia e le macchie cambiano
/// un poco misura, cosi' seicento album non diventano un foglio a quadretti.
/// Resta una griglia — si scorre e si cerca con l'occhio per colonne — ma
/// non si legge piu' come una tabella.
class SpotGrid extends StatelessWidget {
  final int itemCount;
  final CoatItem Function(int index) itemAt;
  final EdgeInsets padding;

  /// La larghezza a cui puntano le colonne.
  final double targetColumn;

  const SpotGrid({
    super.key,
    required this.itemCount,
    required this.itemAt,
    this.padding = EdgeInsets.zero,
    this.targetColumn = 150,
  });

  static const _sizes = [1.0, 0.86, 0.94, 0.8, 0.97, 0.88];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final inner = box.maxWidth - padding.horizontal;
        final columns = (inner / targetColumn).floor().clamp(2, 7);
        const gap = AppSpacing.lg;
        final tile = (inner - gap * (columns - 1)) / columns;
        final drop = tile * 0.32;
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: AppSpacing.sm,
            mainAxisExtent: tile + 56 + drop,
          ),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            final col = i % columns;
            final f = _sizes[(i + col) % _sizes.length];
            final item = itemAt(i);
            return Padding(
              padding: EdgeInsets.only(
                top: col.isOdd ? drop : 0,
                bottom: col.isOdd ? 0 : drop,
              ),
              child: _GridSpot(item: item, size: tile * f, width: tile),
            );
          },
        );
      },
    );
  }
}

class _GridSpot extends StatefulWidget {
  final CoatItem item;
  final double size;
  final double width;

  const _GridSpot({
    required this.item,
    required this.size,
    required this.width,
  });

  @override
  State<_GridSpot> createState() => _GridSpotState();
}

class _GridSpotState extends State<_GridSpot> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        onLongPress: item.onLongPress,
        onSecondaryTap: item.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // La macchia sta in basso a sinistra del suo quadrato: le
            // didascalie restano allineate fra loro anche se le macchie
            // cambiano misura.
            SizedBox(
              width: widget.width,
              height: widget.width,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: AnimatedScale(
                  scale: _hover ? 1.04 : 1,
                  duration: AppMotion.fast,
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: SpotThumbnail(url: item.imageUrl),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            CoatCaption(
              title: item.title,
              subtitle: item.subtitle,
              align: TextAlign.start,
            ),
          ],
        ),
      ),
    );
  }
}
