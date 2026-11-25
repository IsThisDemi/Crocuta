import 'package:flutter/material.dart';

import '../design/app_theme.dart';

/// A section heading with an optional trailing action.
///
/// Replaces four near-identical private `_SectionTitle` / `_SectionHeader`
/// classes that had drifted apart in home_content, stats, search and the
/// old liquid.dart.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Trailing widget used when [actionLabel] is not enough.
  final Widget? trailing;

  /// Dove porta il titolo, quando la sezione ne ha una versione completa.
  ///
  /// Con questa il titolo diventa toccabile e gli spunta accanto una
  /// freccia, come in Apple Music: e' l'affordance piu' leggera che si
  /// possa mettere, e occupa lo spazio di un carattere invece che di un
  /// pulsante "See All" appeso a destra.
  final VoidCallback? onTitleTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xl,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onTitleTap != null)
                  _TappableTitle(title: title, onTap: onTitleTap!)
                else
                  // Su una riga: se non ci sta si stringe un poco, invece
                  // di andare a capo o perdere la fine ("New from artists
                  // you fo...").
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: sectionTitleStyle(context),
                    ),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: context.texts.bodySmall),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Il titolo con la freccia, toccabile tutto insieme.
class _TappableTitle extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _TappableTitle({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        // Il bersaglio comprende la freccia e lo spazio fra le due, non il
        // solo testo: una freccia da dodici pixel presa da sola sarebbe
        // difficile da centrare col dito.
        behavior: HitTestBehavior.opaque,
        // Su una riga, freccia compresa: se non ci sta si stringe un poco
        // invece di perdere la fine del titolo.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, style: sectionTitleStyle(context)),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: context.colors.accentMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il titolo di una sezione: stretto e pesante come il titolo di pagina, a
/// meta' misura. Fra le sezioni deve leggersi la struttura della pagina,
/// non una fila di etichette tutte uguali al testo delle righe.
TextStyle? sectionTitleStyle(BuildContext context) =>
    context.texts.headlineMedium?.copyWith(fontSize: 30, height: 1.05);
