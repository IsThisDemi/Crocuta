import 'package:flutter/material.dart';

/// Centra il contenuto e ne limita la larghezza.
///
/// Il layout e' nato per il telefono: su una finestra da 1600px senza un
/// vincolo i bottoni diventano larghi mezzo schermo e le righe lasciano un
/// vuoto enorme a destra. Le app musicali di Apple tengono il contenuto in
/// una colonna centrata e lasciano respirare i margini.
class ContentWidth extends StatelessWidget {
  final Widget child;

  /// Larghezza massima. Il default va bene per liste e per il player;
  /// le griglie possono chiedere di piu'.
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = 620});

  /// Piu' generosa, per griglie e caroselli.
  static const double wide = 1100;

  /// Lo spazio fra la colonna e il bordo, per lato, su una larghezza
  /// disponibile di [available].
  static double inset(double available, {double maxWidth = wide}) =>
      available > maxWidth ? (available - maxWidth) / 2 : 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Di quanto un carosello puo' allargarsi oltre la colonna, per lato.
///
/// Apple Music fa partire i caroselli allineati al testo ma li lascia
/// correre fino al bordo della finestra: si vede che continuano. Chiusi
/// nella colonna da 1100 px, su un monitor largo si fermavano con un taglio
/// netto a meta' copertina e mezzo schermo vuoto accanto.
///
/// Funziona solo se la lista verticale e' larga quanto la finestra e la
/// colonna la fanno i singoli blocchi (vedi [ContentWidth.inset]): un
/// carosello che sborda da un genitore piu' stretto si vedrebbe, ma non si
/// potrebbe toccare ne' scorrere fuori dal genitore.
class RailBleed extends InheritedWidget {
  final double inset;

  const RailBleed({super.key, required this.inset, required super.child});

  /// Zero fuori da una pagina che lo prevede: il carosello resta com'era.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailBleed>()?.inset ?? 0;

  @override
  bool updateShouldNotify(RailBleed old) => old.inset != inset;
}

/// Una lista verticale larga quanto la finestra, con i blocchi centrati
/// nella colonna e i caroselli liberi di arrivare ai bordi.
///
/// Larga tutta la finestra anche per un'altra ragione: con la colonna
/// attorno alla lista, la rotella del mouse sui margini laterali non
/// scorreva la pagina, perche' li' la lista non c'era.
///
/// [builder] riceve una funzione che chiude un blocco nella colonna: i
/// caroselli non ci vanno, il resto si'.
class BleedListFrame extends StatelessWidget {
  final double maxWidth;
  final Widget Function(BuildContext context, Widget Function(Widget) column)
  builder;

  const BleedListFrame({
    super.key,
    required this.builder,
    this.maxWidth = ContentWidth.wide,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final inset = ContentWidth.inset(box.maxWidth, maxWidth: maxWidth);
        // Larga tutta la colonna, non quanto il blocco: ContentWidth centra,
        // e un titolo lasciato alla sua misura finiva al centro della
        // pagina invece che sul bordo sinistro del testo.
        Widget column(Widget child) => ContentWidth(
          maxWidth: maxWidth,
          child: SizedBox(width: double.infinity, child: child),
        );
        return RailBleed(
          inset: inset,
          child: Builder(builder: (context) => builder(context, column)),
        );
      },
    );
  }
}
