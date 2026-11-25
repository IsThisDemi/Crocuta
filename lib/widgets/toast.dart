import 'dart:async';

import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import 'glass_surfaces.dart';

/// Un avviso breve, come quelli di iOS: una capsula di vetro che scende
/// dall'alto, dice una cosa e se ne va.
///
/// Prima erano SnackBar di Material, rettangoli scuri che comparivano in
/// basso sopra il mini player — dove l'occhio non li aspetta e dove
/// coprivano i controlli. In alto, al centro, piccola: e' dove iOS e macOS
/// mettono "Copiato", "Sincronizzato", AirPods collegati.
///
/// Senza context: la si chiama anche dopo un'attesa, quando la pagina che
/// l'ha chiesta potrebbe non esserci piu'. La disegna [ToastHost].
void showToast(
  String message, {
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _toast.value = _Toast(
    message: message,
    icon: icon,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

class _Toast {
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  _Toast({required this.message, this.icon, this.actionLabel, this.onAction});
}

final _toast = ValueNotifier<_Toast?>(null);

/// Dove si disegnano gli avvisi: sopra tutta l'app, sotto nessun'altra
/// cosa.
class ToastHost extends StatefulWidget {
  final Widget child;

  const ToastHost({super.key, required this.child});

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 220),
  );
  _Toast? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _toast.addListener(_onToast);
  }

  @override
  void dispose() {
    _toast.removeListener(_onToast);
    _hide?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _onToast() async {
    final next = _toast.value;
    if (next == null) return;
    _hide?.cancel();
    // Uno nuovo mentre c'e' gia' l'altro: il vecchio sale via, il nuovo
    // scende. Due capsule impilate non le fa nessuno.
    if (_shown != null && _anim.value > 0) await _anim.reverse();
    if (!mounted) return;
    setState(() => _shown = next);
    unawaited(_anim.forward(from: 0));
    // Con un pulsante resta di piu': bisogna leggere e decidere.
    _hide = Timer(
      Duration(milliseconds: next.actionLabel == null ? 2200 : 4500),
      _dismiss,
    );
  }

  Future<void> _dismiss() async {
    _hide?.cancel();
    if (!mounted || _shown == null) return;
    await _anim.reverse();
    if (!mounted) return;
    setState(() => _shown = null);
    _toast.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = _shown;
    final top = MediaQuery.paddingOf(context).top + topWindowInset(context);
    return Stack(
      children: [
        widget.child,
        if (t != null)
          Positioned(
            top: top + AppSpacing.sm,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Center(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  // Scende con una molla leggera, sale via dritta.
                  final v = _anim.status == AnimationStatus.reverse
                      ? Curves.easeIn.transform(_anim.value)
                      : Curves.easeOutBack.transform(_anim.value);
                  return Opacity(
                    opacity: _anim.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -24 * (1 - v)),
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * v.clamp(0.0, 1.1),
                        child: child,
                      ),
                    ),
                  );
                },
                child: GestureDetector(
                  // Spinta in su, come le notifiche di iOS.
                  onVerticalDragUpdate: (d) {
                    if (d.delta.dy < -4) _dismiss();
                  },
                  child: _ToastPill(toast: t, onAction: _act),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _act() {
    _shown?.onAction?.call();
    _dismiss();
  }
}

class _ToastPill extends StatelessWidget {
  final _Toast toast;
  final VoidCallback onAction;

  const _ToastPill({required this.toast, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final label = toast.actionLabel;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, minHeight: 46),
      child: GlassPanel(
        radius: 23,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            toast.icon == null ? 20 : 14,
            11,
            label == null ? 20 : 8,
            11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (toast.icon != null) ...[
                Icon(toast.icon, size: 19, color: Colors.white),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  toast.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const StadiumBorder(),
                    textStyle: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
