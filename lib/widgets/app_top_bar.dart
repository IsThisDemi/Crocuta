import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import 'liquid.dart';
import 'sub_page.dart';

/// L'intestazione delle pagine che non hanno un titolo grande, come
/// equalizzatore e testi.
///
/// Non piu' una barra di vetro larga tutta la finestra: lo stesso schema
/// delle altre pagine a titolo grande quando sono scorse — il tasto
/// indietro tondo a sinistra, il titolo piccolo al centro, i comandi in una
/// capsula a destra. Una barra da bordo a bordo era l'unico elemento
/// dell'app che non seguiva la colonna del contenuto, e su un Mac largo
/// diventava una striscia di 1360 px sopra una pagina di 600.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Azioni a destra del titolo.
  final List<Widget> actions;

  /// Di norma torna indietro; si può sovrascrivere.
  final VoidCallback? onBack;

  const AppTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.onBack,
  });

  static const double _barHeight = topBarHeight;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight + AppSpacing.sm);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xs + topWindowInset(context),
          AppSpacing.gutter,
          0,
        ),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              GlassCircleIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // Dall'altra parte qualcosa di largo quanto il tasto
              // indietro anche senza comandi, perche' il titolo resti al
              // centro della finestra e non del posto che avanza.
              if (actions.isEmpty)
                const SizedBox(width: 44)
              else
                GlassActions(actions: actions),
            ],
          ),
        ),
      ),
    );
  }
}
