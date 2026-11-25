import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import 'native_glass.dart';
import '../design/motion.dart';

/// Lo sfondo di vetro di una superficie modale: dialog, sheet, menu.
///
/// Esiste perche' il vetro di sistema e' una *platform view*, e una platform
/// view non si comporta come un widget durante le transizioni di route: la
/// posiziona il compositore nativo, quindi mentre la sheet scorre verso
/// l'alto o il dialog sfuma il riquadro nativo arriva in ritardo e ignora
/// opacita' e scala. Per questo il vetro vero entra **solo a transizione
/// finita**: durante l'animazione si vede il ripiego disegnato da Flutter,
/// che anima correttamente, e lo scambio avviene quando la superficie e'
/// ormai ferma, dove non si nota.
class GlassPanel extends StatefulWidget {
  final double radius;

  /// Quanto materiale si vede. Piu' basso = piu' trasparente.
  final double opacity;

  /// La tinta del ripiego, dove il vetro di sistema non c'e' (Windows, test,
  /// e i fotogrammi di transizione).
  final Color fallbackTint;

  final Widget child;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppRadius.xl,
    this.opacity = 0.72,
    this.fallbackTint = AppColors.ink700,
  });

  @override
  State<GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends State<GlassPanel> {
  Animation<double>? _routeAnimation;
  bool _settled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ModalRoute.of(context)?.animation;
    if (identical(anim, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onStatus);
    _routeAnimation = anim;
    // Fuori da una route modale non c'e' niente da aspettare.
    if (anim == null) {
      _settled = true;
      return;
    }
    anim.addStatusListener(_onStatus);
    _settled = anim.status == AnimationStatus.completed;
  }

  void _onStatus(AnimationStatus status) {
    final settled = status == AnimationStatus.completed;
    if (settled == _settled || !mounted) return;
    setState(() => _settled = settled);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Macchia: menu e fogli sono superfici piene, non vetro. Il velo
    // sfocato al 82% lasciava passare i comandi del player sotto il menu,
    // e le voci si leggevano sopra un'icona fantasma.
    final fallback = ColoredBox(color: widget.fallbackTint);

    return ClipRRect(
      borderRadius: AppRadius.br(widget.radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: _settled
                ? NativeGlass(
                    radius: widget.radius,
                    opacity: widget.opacity,
                    fallback: fallback,
                  )
                : fallback,
          ),
          // Il contorno da 1px: il vetro da solo non basta a separare la
          // superficie dal contenuto quando dietro c'e' una copertina chiara.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.br(widget.radius),
                  border: Border.all(color: AppColors.glassStroke),
                ),
              ),
            ),
          ),
          // Un Material trasparente proprio: dentro showGeneralDialog non ce
          // n'e' nessuno sopra, e senza il testo esce sottolineato di giallo.
          Material(type: MaterialType.transparency, child: widget.child),
        ],
      ),
    );
  }
}

/// Un pulsante di un [showGlassAlert].
class GlassAlertAction<T> {
  final String label;

  /// Cosa restituisce l'alert quando lo si preme.
  final T? value;

  /// L'azione principale: in grassetto, come in iOS, e scelta anche da
  /// Invio sulla tastiera.
  final bool isDefault;

  /// In rosso: cancellare qualcosa.
  final bool isDestructive;

  /// Spento finche' vale false, per esempio con il nome ancora vuoto.
  final ValueListenable<bool>? enabled;

  const GlassAlertAction({
    required this.label,
    this.value,
    this.isDefault = false,
    this.isDestructive = false,
    this.enabled,
  });
}

/// Un alert come quelli di iOS, su vetro di sistema.
///
/// Stretto e centrato, con lo sfondo abbassato: il vecchio dialog si stirava
/// per tutta la finestra del Mac, con il campo di testo lungo due metri e i
/// pulsanti persi in un angolo. Qui titolo e messaggio stanno al centro e i
/// pulsanti occupano tutta la larghezza, divisi da un filo, con l'azione
/// principale in grassetto — la forma che su iPhone si riconosce subito.
///
/// Sul navigator radice, cosi' copre anche tab bar e brano in riproduzione.
Future<T?> showGlassAlert<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  required List<GlassAlertAction<T>> actions,
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: AppMotion.fast,
    // Come iOS: compare da un filo piu' grande e si posa, invece di salire.
    transitionBuilder: (ctx, anim, _, child) {
      final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: t,
        child: ScaleTransition(
          scale: Tween(begin: 1.08, end: 1.0).animate(t),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, _) => _GlassAlert<T>(
      title: title,
      message: message,
      content: content,
      actions: actions,
    ),
  );
}

/// Chiede un nome: "New Playlist", "Rename Playlist", "Save Preset".
///
/// Restituisce il testo senza spazi ai bordi, o null se si annulla. Il
/// pulsante di conferma resta spento finche' il campo e' vuoto: premere
/// "Create" e non veder succedere niente era il comportamento di prima.
Future<String?> showGlassTextPrompt({
  required BuildContext context,
  required String title,
  String? message,
  String hint = '',
  String initial = '',
  required String confirmLabel,

  /// Per indirizzi e codici: niente maiuscola iniziale, niente correzioni
  /// ne' suggerimenti, che li rovinerebbero.
  bool verbatim = false,
}) async {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  final filled = ValueNotifier(initial.trim().isNotEmpty);
  controller.addListener(
    () => filled.value = controller.text.trim().isNotEmpty,
  );

  final ok = await showGlassAlert<bool>(
    context: context,
    title: title,
    message: message,
    content: Builder(
      builder: (ctx) => GlassAlertField(
        controller: controller,
        hint: hint,
        verbatim: verbatim,
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(ctx).pop(true);
        },
      ),
    ),
    actions: [
      const GlassAlertAction(label: 'Cancel', value: false),
      GlassAlertAction(
        label: confirmLabel,
        value: true,
        isDefault: true,
        enabled: filled,
      ),
    ],
  );
  final text = controller.text.trim();
  // Dopo la transizione di uscita, non subito: il campo e' ancora a schermo
  // mentre l'alert sfuma, e un controller gia' chiuso lo farebbe lanciare.
  Future<void>.delayed(AppMotion.base, () {
    controller.dispose();
    filled.dispose();
  });
  return ok == true && text.isNotEmpty ? text : null;
}

/// Chiede conferma prima di un'azione che non si annulla.
Future<bool> showGlassConfirm({
  required BuildContext context,
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showGlassAlert<bool>(
    context: context,
    title: title,
    message: message,
    actions: [
      const GlassAlertAction(label: 'Cancel', value: false),
      GlassAlertAction(
        label: confirmLabel,
        value: true,
        isDefault: !destructive,
        isDestructive: destructive,
      ),
    ],
  );
  return ok == true;
}

/// Il campo di testo di un alert, come quello di iOS.
///
/// Un rettangolino pieno e basso, senza il contorno colorato del tema: su
/// vetro, un bordo d'accento acceso attorno a un campo largo tutto l'alert
/// era la cosa piu' vistosa della finestra.
class GlassAlertField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final bool verbatim;

  const GlassAlertField({
    super.key,
    required this.controller,
    this.hint = '',
    this.onSubmitted,
    this.verbatim = false,
  });

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      autofocus: true,
      textCapitalization: verbatim
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      autocorrect: !verbatim,
      enableSuggestions: !verbatim,
      keyboardType: verbatim ? TextInputType.url : null,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      style: context.texts.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 10,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
  }
}

class _GlassAlert<T> extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? content;
  final List<GlassAlertAction<T>> actions;

  const _GlassAlert({
    required this.title,
    required this.message,
    required this.content,
    required this.actions,
  });

  /// La larghezza di un alert di iOS, anche su una finestra da 1600px.
  static const width = 300.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hairline = Colors.white.withValues(alpha: 0.12);
    // Due pulsanti affiancati; di piu', uno sotto l'altro, come fa iOS.
    final sideBySide = actions.length <= 2;

    Widget button(GlassAlertAction<T> a) => _AlertButton<T>(action: a);

    return Padding(
      // Sopra la tastiera, quando c'e': senza, su iPhone il campo del nome
      // finiva sotto i tasti mentre lo si scriveva.
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Center(
        child: SizedBox(
          width: math.min(width, mq.size.width - AppSpacing.xl * 2),
          child: GlassPanel(
            radius: AppRadius.xl,
            fallbackTint: AppColors.ink700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: context.texts.headlineSmall,
                      ),
                      if (message != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: context.texts.bodyMedium?.copyWith(
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                      if (content != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        content!,
                      ],
                    ],
                  ),
                ),
                Divider(height: 0.5, thickness: 0.5, color: hairline),
                if (sideBySide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0)
                            VerticalDivider(
                              width: 0.5,
                              thickness: 0.5,
                              color: hairline,
                            ),
                          Expanded(child: button(actions[i])),
                        ],
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0)
                      Divider(height: 0.5, thickness: 0.5, color: hairline),
                    button(actions[i]),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertButton<T> extends StatelessWidget {
  final GlassAlertAction<T> action;

  const _AlertButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled ?? const AlwaysStoppedAnimation(true);
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, on, _) {
        final color = !on
            ? context.colors.textMuted.withValues(alpha: 0.5)
            : action.isDestructive
            ? context.colors.danger
            : context.colors.accent;
        return InkWell(
          onTap: on ? () => Navigator.of(context).pop(action.value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Text(
              action.label,
              textAlign: TextAlign.center,
              style: context.texts.titleMedium?.copyWith(
                color: color,
                fontWeight: action.isDefault
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Una bottom sheet su vetro di sistema.
///
/// Staccata dai bordi invece che incollata in basso: una platform view non si
/// lascia ritagliare in modo affidabile a meta' (angoli superiori tondi,
/// inferiori dritti), e la superficie flottante e' anche la forma che usa
/// oggi Apple — coerente con la chrome a pillola del resto dell'app.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Sul navigator radice, non su quello della scheda.
    //
    // Tab bar e brano in riproduzione li disegna la shell, fuori dai
    // navigator delle schede: un foglio aperto dentro una scheda finiva
    // *sotto* di loro, con le ultime voci coperte. Sulla radice invece
    // copre tutto, che e' cio' che ci si aspetta da una superficie modale.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    isScrollControlled: true,
    // Sale con la molla dei fogli di iOS, non con la curva di Material.
    sheetAnimationStyle: AnimationStyle(
      duration: AppSprings.present.settle,
      curve: AppSprings.present,
      reverseDuration: AppSprings.dismiss.settle,
      reverseCurve: AppSprings.dismiss.flipped,
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        MediaQuery.of(ctx).padding.bottom + AppSpacing.sm,
      ),
      child: GlassPanel(
        radius: 30,
        fallbackTint: AppColors.ink800,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            // Scrollabile: con molte playlist il contenuto supera l'altezza
            // concessa e una Column non scorre, sborda.
            Flexible(child: SingleChildScrollView(child: builder(ctx))),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    ),
  );
}

/// In cima al foglio, al posto della barretta grigia: una macchiolina del
/// colore del brano, viva come tutte le altre. Dice comunque "si tira giu'".
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final color = context.colors.accentMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: SizedBox(
        width: 30,
        height: 10,
        child: SpotMotionBuilder(
          builder: (context, t) => DecoratedBox(
            decoration: ShapeDecoration(
              color: color,
              shape: SpotBorder(seed: 'sheet-handle', wobble: 0.7, time: t),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una voce del menu al puntatore.
class GlassMenuItem<T> {
  final T value;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDestructive;

  const GlassMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
    this.isDestructive = false,
  });
}

/// Il menu contestuale al puntatore, su vetro di sistema.
///
/// Non si puo' ottenere da [showMenu]: quello disegna la propria superficie
/// come un Material opaco e non accetta uno sfondo, quindi il pannello va
/// costruito a mano su una route trasparente.
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<GlassMenuItem<T>> items,
}) {
  // Macchia: niente pannello. Ogni voce e' un pallino a macchia con
  // l'icona nel colore del brano, e la parola accanto; la pagina sotto si
  // scurisce perche' le parole si leggano. I pallini compaiono uno dopo
  // l'altro, dal punto toccato.
  return showGeneralDialog<T>(
    context: context,
    // Come il foglio: sopra la chrome della shell, non sotto.
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, anim, _) => CustomSingleChildLayout(
      delegate: _MenuLayout(globalPosition),
      child: IntrinsicWidth(
        // Scorrevole: con molte voci (i preset dell'equalizzatore, le
        // playlist) il menu supera lo schermo.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, item) in items.indexed)
                _MenuEntrance(
                  animation: anim,
                  index: i,
                  count: items.length,
                  child: _MenuRow<T>(
                    item: item,
                    onTap: () => Navigator.of(ctx).pop(item.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: AppMotion.standard),
      child: child,
    ),
  );
}

/// Ogni voce arriva un attimo dopo la precedente, scendendo appena e
/// crescendo dal suo pallino.
class _MenuEntrance extends StatelessWidget {
  final Animation<double> animation;
  final int index;
  final int count;
  final Widget child;

  const _MenuEntrance({
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index / (count + 2)).clamp(0.0, 0.7);
    final t = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.25),
          end: Offset.zero,
        ).animate(t),
        child: child,
      ),
    );
  }
}

class _MenuRow<T> extends StatefulWidget {
  final GlassMenuItem<T> item;
  final VoidCallback onTap;

  const _MenuRow({required this.item, required this.onTap});

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

/// Una voce del menu: l'icona nel colore del brano, la parola col
/// carattere dei titoli, e col mouse sopra un fondo morbido del colore del
/// brano. Le voci distruttive in rosso.
class _MenuRowState<T> extends State<_MenuRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = context.colors;
    final tint = !item.enabled
        ? colors.textFaint
        : item.isDestructive
        ? colors.danger
        : colors.accent;
    final lit = _hover && item.enabled;

    return MouseRegion(
      cursor: item.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.enabled ? widget.onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // Il pallino: scuro con l'icona del colore del brano; col
              // mouse sopra si riempie del colore e l'icona diventa nera.
              AnimatedScale(
                scale: lit ? 1.12 : 1,
                duration: AppMotion.fast,
                curve: Curves.easeOutBack,
                child: SpotMotionBuilder(
                  builder: (context, t) => AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 42,
                    height: 42,
                    decoration: ShapeDecoration(
                      color: lit ? tint : AppColors.ink700,
                      shape: SpotBorder(
                        seed: 'menu-${item.icon.codePoint}',
                        wobble: 0.8,
                        time: t,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: lit ? 0 : 0.1),
                        ),
                      ),
                    ),
                    child: Icon(
                      item.icon,
                      size: 20,
                      color: lit ? AppColors.ink900 : tint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: AppMotion.fast,
                  style: context.texts.titleMedium!.copyWith(
                    color: !item.enabled
                        ? colors.textFaint
                        : item.isDestructive
                        ? colors.danger
                        : (lit ? tint : colors.textStrong),
                    shadows: const [
                      Shadow(color: Color(0xCC000000), blurRadius: 10),
                    ],
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiene il pannello sotto il puntatore, ma dentro lo schermo.
class _MenuLayout extends SingleChildLayoutDelegate {
  final Offset target;

  const _MenuLayout(this.target);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        math.min(340, constraints.maxWidth - AppSpacing.md),
        constraints.maxHeight - AppSpacing.md,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double fit(double wanted, double available, double extent) {
      final limit = math.max(AppSpacing.xs, available - extent - AppSpacing.xs);
      return wanted.clamp(AppSpacing.xs, limit);
    }

    return Offset(
      fit(target.dx, size.width, childSize.width),
      fit(target.dy, size.height, childSize.height),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) => oldDelegate.target != target;
}

/// Un pulsante che apre [showGlassMenu] ancorato sotto di se'.
///
/// Sostituisce [PopupMenuButton], che disegna una superficie Material propria
/// e non accetta uno sfondo di vetro.
class GlassMenuButton<T> extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final Color? color;
  final List<GlassMenuItem<T>> Function(BuildContext ctx) itemBuilder;
  final ValueChanged<T> onSelected;

  const GlassMenuButton({
    super.key,
    required this.icon,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: () async {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        // Ancorato all'angolo in basso a sinistra del pulsante, come fa il
        // menu di sistema; il delegate lo riporta dentro lo schermo se il
        // pulsante sta sul bordo.
        final anchor = box.localToGlobal(Offset(0, box.size.height));
        final items = itemBuilder(context);
        if (items.isEmpty) return;
        final selected = await showGlassMenu<T>(
          context: context,
          globalPosition: anchor,
          items: items,
        );
        if (selected != null) onSelected(selected);
      },
    );
  }
}
