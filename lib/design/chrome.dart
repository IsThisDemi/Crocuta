import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'tokens.dart';
import '../widgets/word_tab_bar.dart';

/// Altezza occupata in basso dalla navigazione e dal mini player.
///
/// Le schermate spinte (artista, album, playlist) non sanno nulla della
/// chrome della shell che sta sopra di loro: senza questo margine le ultime
/// righe di una lista restano coperte. Con la tana a sinistra (finestra
/// larga) in basso non c'e' niente da scansare.
double bottomChromeInset(BuildContext context, WidgetRef ref) {
  // Sul navigator radice la chrome non viene disegnata affatto: il margine
  // sarebbe solo spazio morto in fondo alla lista.
  if (ChromeAbsent.of(context)) return 0;
  if (ChromeLayout.isRail(context)) return 0;
  final hasTrack = ref.watch(playerProvider.select((s) => s.current != null));
  // Il giro di copertina e satelliti e, con un brano, titolo e filo;
  // l'area sicura sotto e' parte della barra.
  return WordTabBar.heightFor(hasTrack: hasTrack) +
      MediaQuery.paddingOf(context).bottom;
}

/// Che forma ha preso la shell: tana a sinistra o barra in basso.
class ChromeLayout extends InheritedWidget {
  final bool rail;

  const ChromeLayout({super.key, required this.rail, required super.child});

  static bool isRail(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeLayout>()?.rail ?? false;

  @override
  bool updateShouldNotify(ChromeLayout oldWidget) => oldWidget.rail != rail;
}

/// Comodo per i `padding` delle liste.
double listBottomPadding(BuildContext context, WidgetRef ref) =>
    bottomChromeInset(context, ref) + AppSpacing.md;

/// Segnala che sotto non c'e' nessuna chrome da scansare.
///
/// Speculare a [WindowInsetApplied]: le schermate spinte sul navigator
/// radice (player, coda aperta da li', testi) coprono tab bar e mini
/// player, quindi le liste non devono lasciare spazio per loro.
class ChromeAbsent extends InheritedWidget {
  const ChromeAbsent({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeAbsent>() != null;

  @override
  bool updateShouldNotify(ChromeAbsent oldWidget) => false;
}

/// Segnala che il margine per i semafori e' gia' stato applicato piu' in
/// alto nell'albero.
///
/// Serve perche' le schermate spinte si raggiungono da due strade diverse:
/// album e artista stanno dentro un tab (quindi gia' dentro il margine della
/// shell), mentre player, testi ed equalizzatore vivono sul navigator radice
/// e il margine devono mettercelo loro. Senza questo segnale le prime
/// finirebbero con il doppio dello spazio.
class WindowInsetApplied extends InheritedWidget {
  const WindowInsetApplied({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowInsetApplied>() != null;

  @override
  bool updateShouldNotify(WindowInsetApplied oldWidget) => false;
}

/// Da passare a `GlassScaffold.topEdgeFadeExtent` sulle pagine con la barra
/// di vetro in cima.
///
/// La sfumatura del pacchetto, fuori da una `GlassPage`, e' un gradiente di
/// colore pieno dipinto *sopra* il contenuto, e di norma copre barra di
/// stato piu' barra (`appBarHeight`, 44 di default, piu' 20). Il vetro di
/// sistema allora rifrangeva un velo scuro invece di cio' che scorre, e
/// sembrava opaco. Togliendo l'altezza della barra resta la sola barra di
/// stato: l'ora si legge ancora sopra una copertina chiara, e sotto il
/// vetro passa il contenuto vero.
const double statusBarOnlyFade = -44;

/// Se la sfumatura in cima serve: solo dove c'e' una barra di stato.
///
/// Sul Mac non c'e' un orologio da rendere leggibile, e la sfumatura
/// restava li' come una striscia nera sul bordo della finestra, proprio
/// dove lo sfondo sfocato dovrebbe arrivare fino in cima.
bool get hasStatusBarFade => Platform.isIOS || Platform.isAndroid;

/// Altezza della barra superiore di vetro.
///
/// Sta qui e non nel widget perche' la barra galleggia sopra il contenuto:
/// le pagine che ci scorrono sotto devono sapere quanto spazio lasciare,
/// altrimenti la prima cosa che disegnano finisce dietro il vetro.
const double topBarHeight = 52;

/// Quanto deve rientrare dall'alto il contenuto di una pagina con la barra.
///
/// Comprende l'area sicura: la barra stessa sta dentro una `SafeArea`,
/// quindi su iPhone scende sotto il notch, e un rientro che non lo contasse
/// lascerebbe il contenuto piu' in alto della barra — infilato dietro.
/// Su macOS quel valore e' zero e a scansare i semafori ci pensa
/// [topWindowInset], che e' il motivo per cui li' il conto tornava lo
/// stesso e il difetto si vedeva solo sul telefono.
double topBarInset(BuildContext context) =>
    MediaQuery.paddingOf(context).top +
    AppSpacing.xs +
    topWindowInset(context) +
    topBarHeight +
    AppSpacing.sm;

/// Quanto rientrare dall'alto quando la pagina comincia da se'.
///
/// E' l'area sicura del telefono piu' lo spazio dei semafori della finestra:
/// il margine che serve a una schermata che non ha nessuna barra sopra di
/// se'.
///
/// Zero quando quel margine l'ha gia' messo qualcun altro. Serve a una
/// schermata che vive in due posti: la coda e' radice di una scheda — e li'
/// il margine se lo mette lei — ma si apre anche dal brano in riproduzione
/// dentro una `SubPage`, che ha gia' la sua barra e il suo rientro.
/// Sommandoli, la coda si apriva con duecento pixel di vuoto sopra il
/// titolo.
double topContentInset(BuildContext context) {
  if (TopInsetApplied.of(context)) return 0;
  return MediaQuery.paddingOf(context).top + topWindowInset(context);
}

/// Segnala che il rientro superiore e' gia' stato applicato piu' in alto.
class TopInsetApplied extends InheritedWidget {
  const TopInsetApplied({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopInsetApplied>() != null;

  @override
  bool updateShouldNotify(TopInsetApplied oldWidget) => false;
}

/// Spazio da lasciare in cima su macOS.
///
/// La finestra usa `fullSizeContentView`: il contenuto arriva al bordo
/// superiore e i semafori ci galleggiano sopra, quindi senza questo margine
/// il primo titolo finisce sotto i pulsanti della finestra.
///
/// Restituisce 0 quando un antenato lo ha gia' applicato.
double topWindowInset(BuildContext context) {
  if (!Platform.isMacOS) return 0;
  if (WindowInsetApplied.of(context)) return 0;
  return 28;
}
