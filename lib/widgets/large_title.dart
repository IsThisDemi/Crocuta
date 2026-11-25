import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';

/// Il titolo grande di una pagina principale, che scorrendo si stringe in
/// un titolo piccolo in cima — come in iOS 26.
///
/// In iOS 26 dietro il titolo piccolo non c'e' piu' un pannello: c'e' solo
/// una sfumatura che lo rende leggibile sopra cio' che scorre. Quindi qui
/// niente vetro, e niente platform view in una zona che si ridisegna a ogni
/// fotogramma dello scorrimento.
///
/// La sfumatura ripara anche un difetto che le pagine principali avevano:
/// non hanno una barra in cima, e scorrendo il contenuto passava sotto
/// l'orologio senza niente in mezzo.
///
/// Si usa in coppia con [LargeTitle]: la cornice avvolge la pagina, il
/// titolo sta dentro la lista, dove deve stare a riposo.
class CollapsingTitleFrame extends StatefulWidget {
  /// Il testo del titolo piccolo.
  final String title;

  final Widget child;

  /// Di quanto scendere la riga del titolo piccolo sotto l'area sicura.
  ///
  /// Le pagine di dettaglio hanno a sinistra il tasto indietro di vetro,
  /// che sta [AppSpacing.xs] piu' in basso: il titolo si centra su di lui,
  /// non qualche pixel sopra.
  final double barOffset;

  const CollapsingTitleFrame({
    super.key,
    required this.title,
    required this.child,
    this.barOffset = 0,
  });

  @override
  State<CollapsingTitleFrame> createState() => _CollapsingTitleFrameState();
}

class _CollapsingTitleFrameState extends State<CollapsingTitleFrame> {
  final _titleKey = GlobalKey();

  /// Da 0 (titolo grande visibile) a 1 (titolo grande sparito).
  double _progress = 0;

  /// Altezza della riga del titolo piccolo, sotto la barra di stato.
  static const _barHeight = 44.0;

  /// Su quanti pixel di scorrimento il titolo piccolo compare.
  static const _fade = 18.0;

  @override
  void initState() {
    super.initState();
    // Anche a pagina ferma, non solo allo scorrimento: una lista che torna
    // a una posizione salvata parte gia' scorsa, e il titolo piccolo deve
    // esserci subito invece che al primo movimento.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  bool _scheduled = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    // Dopo il fotogramma, non subito. La notifica parte quando la lista ha
    // cambiato posizione ma prima che si sia ridisposta, quindi misurando
    // qui il titolo risulta sempre dove stava al fotogramma prima: durante
    // un trascinamento restava fermo, e dopo l'ultimo movimento non
    // arrivava piu' nessuna misura a correggerlo — il titolo piccolo si
    // bloccava a meta'. Una sola misura per fotogramma, anche se le
    // notifiche sono di piu'.
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _measure();
      });
    }
    return false;
  }

  /// Si misura il titolo grande invece di dedurlo dalla posizione della
  /// lista: ogni pagina ha il suo margine in cima, e un conto a mano per
  /// ciascuna si sfalserebbe alla prima modifica.
  void _measure() {
    final frame = context.findRenderObject() as RenderBox?;
    final title = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (frame == null || title == null || !title.attached) {
      // Il titolo e' uscito dalla lista (ricostruito altrove): e' ben oltre.
      if (_progress != 1 && title == null && mounted) {
        setState(() => _progress = 1);
      }
      return;
    }
    final titleBottom = title
        .localToGlobal(Offset(0, title.size.height), ancestor: frame)
        .dy;
    final barBottom = topContentInset(context) + widget.barOffset + _barHeight;
    // Zero finche' il fondo del titolo grande sta sotto la riga del
    // piccolo; pieno quando ci e' passato sotto di [_fade] pixel. Contando
    // da prima — com'era alla prima stesura — il piccolo si vedeva gia' a
    // pagina ferma, perche' a riposo il grande sta appena sotto la riga.
    final p = ((barBottom - titleBottom) / _fade).clamp(0.0, 1.0);
    if (p != _progress) setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    final top = topContentInset(context) + widget.barOffset;
    return _LargeTitleScope(
      titleKey: _titleKey,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + _barHeight + AppSpacing.lg,
            child: IgnorePointer(
              child: Opacity(
                opacity: _progress,
                child: _ScrollEdge(
                  // Nero pieno fino al fondo della riga del titolo, e solo
                  // sotto la sfumatura: prima il pieno finiva a due terzi,
                  // e le righe della lista si leggevano dietro le lettere.
                  solid:
                      (top + _barHeight) / (top + _barHeight + AppSpacing.lg),
                  child: Padding(
                    padding: EdgeInsets.only(top: top),
                    child: SizedBox(
                      height: _barHeight,
                      // Margine ai lati quanto il tasto indietro e il suo
                      // bordo, su entrambi i lati per restare centrato: un
                      // titolo lungo si tronca invece di passarci sotto.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 72),
                        child: Center(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.headlineSmall?.copyWith(
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeTitleScope extends InheritedWidget {
  final GlobalKey titleKey;

  const _LargeTitleScope({required this.titleKey, required super.child});

  @override
  bool updateShouldNotify(_LargeTitleScope old) => false;
}

/// Il titolo grande, da mettere in cima alla lista della pagina.
class LargeTitle extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  const LargeTitle(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_LargeTitleScope>();
    return Text(
      text,
      key: scope?.titleKey,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      // Macchia: il titolo di pagina e' la cosa piu' grande della
      // schermata dopo le copertine, stretto e pesante. Sul telefono un
      // poco meno, perche' "Library" stia in una riga accanto ai comandi.
      style:
          style ??
          context.texts.displayLarge?.copyWith(
            fontSize: MediaQuery.sizeOf(context).width >= 700 ? 64 : 46,
            height: 1.0,
          ),
    );
  }
}

/// Il bordo di scorrimento di iOS 26 dietro il titolo piccolo.
///
/// Prima era una tenda nera dal 90% a zero: il titolo si leggeva, ma la
/// cima della pagina diventava una fascia buia che tagliava via il colore
/// del disco. iOS 26 li' sfoca, e sfoca sempre meno scendendo.
///
/// Una sfocatura che sfuma non esiste gia' fatta: la si ottiene impilando
/// strati sempre piu' corti, ognuno con una sfocatura leggera. In cima si
/// sommano tutti, in fondo ne resta uno, e un bordo netto di uno strato
/// cosi' tenue non si vede. Sopra, un velo scuro solo accennato, perche'
/// il titolo resti leggibile anche su una copertina chiara.
class _ScrollEdge extends StatelessWidget {
  final Widget child;

  /// Fin dove, in frazione dell'altezza, il nero e' pieno.
  final double solid;

  const _ScrollEdge({required this.child, this.solid = 0.66});

  @override
  Widget build(BuildContext context) {
    // Macchia: niente sfocatura, il nero della pagina che sale. Sulla base
    // nera una fascia sfocata si vedeva come una striscia lattiginosa;
    // il nero pieno che sfuma e' lo stesso trattamento della barra in basso.
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                AppColors.ink900,
                AppColors.ink900,
                Color(0x00000000),
              ],
              stops: [0, solid.clamp(0.0, 1.0), 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// La misura piu' grande, fra [largest] e [smallest], a cui [text] sta in
/// [lines] righe larghe [maxWidth]. Se non ci sta nemmeno alla piu'
/// piccola, quella: il chiamante decide se tagliare o lasciare andare a
/// capo.
double fitTitleSize(
  String text,
  TextStyle style, {
  required double maxWidth,
  required double largest,
  required double smallest,
  int lines = 2,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return largest;
  for (var size = largest; size > smallest; size -= 1) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      maxLines: lines,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    final fits = !tp.didExceedMaxLines;
    tp.dispose();
    if (fits) return size;
  }
  return smallest;
}
