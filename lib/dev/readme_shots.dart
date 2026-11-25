import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/motion.dart';
import '../models/track.dart';
import '../navigation.dart';
import '../providers.dart';
import '../screens/browse_screens.dart';
import '../screens/eq_screen.dart';
import '../screens/now_playing_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../widgets/word_tab_bar.dart';

/// Le foto del README, fatte dall'app stessa.
///
/// Solo in debug e solo se si avvia con `--dart-define=README_SHOTS=1`: l'app va da sola nelle
/// schermate che servono a tool/make_readme_art.py e si fotografa dal suo
/// albero di widget, senza catturare lo schermo. Cosi' la finestra puo'
/// stare nascosta dietro le altre mentre lavora.
///
/// `README_SHOTS_SET=phone` fotografa le schermate da telefono (la finestra
/// va stretta, 430 punti), `wide` la sola finestra larga.
const String readmeShotsDir = String.fromEnvironment('README_SHOTS');
const String readmeShotsSet = String.fromEnvironment(
  'README_SHOTS_SET',
  defaultValue: 'phone',
);

/// Il brano delle foto (l'inizio del titolo), cercato fra quelli ascoltati
/// e i preferiti.
const String readmeShotsTrack = 'Yeah Glo! (Extended)';
const String readmeShotsArtist = 'GloRilla';

bool get readmeShotsEnabled => kDebugMode && readmeShotsDir.isNotEmpty;

/// Il confine che si fotografa: tutta l'app, sotto il MaterialApp.
final readmeShotsBoundary = GlobalKey();

Future<void> runReadmeShots(WidgetRef ref) async {
  if (!readmeShotsEnabled) return;
  // L'app e' nel sandbox e non scrive fuori dal suo contenitore: le foto
  // vanno nella sua cartella temporanea, e da li' le prende chi l'ha
  // lanciata (~/Library/Containers/<bundle>/Data/tmp/readme_shots).
  final out = Directory('${Directory.systemTemp.path}/readme_shots')
    ..createSync(recursive: true);
  debugPrint('readme: cartella ${out.path}');

  Future<void> settle([int ms = 2500]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> shot(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final box =
        readmeShotsBoundary.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (box == null) return;
    final image = await box.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('readme: $name');
  }

  NavigatorState root() => rootNavigatorKey.currentState!;
  NavigatorState tab(int i) => tabNavigatorKeys[i].currentState!;
  void select(int i) => ref.read(navTabProvider.notifier).select(i);

  // Le copertine e la sessione ripristinata hanno bisogno di qualche
  // secondo per arrivare.
  await settle(6000);

  // Sempre lo stesso brano, qualunque cosa si stia ascoltando: le foto del
  // README devono andare d'accordo fra loro, e l'accento viene da lui. A un
  // minuto: a pochi secondi dall'inizio il testo mostra i crediti, e la
  // barra d'avanzamento e' vuota.
  const at = Duration(seconds: 62);
  final player = ref.read(playerProvider.notifier);
  // Prima di tutto: niente di quello che succede qui finisce nella sessione
  // salvata, nemmeno se il brano non si trova o una foto sposta il punto.
  player.debugStopPersisting();
  final storage = ref.read(storageServiceProvider);
  bool isStar(Track t) =>
      t.title.startsWith(readmeShotsTrack) && t.author == readmeShotsArtist;
  var star = [
    ...storage.recentlyPlayed,
    ...storage.favorites,
  ].where(isStar).firstOrNull;
  // Uscito dalla cronologia: lo si cerca, come farebbe chiunque.
  if (star == null) {
    try {
      final found = await ref
          .read(youtubeServiceProvider)
          .search('$readmeShotsTrack $readmeShotsArtist');
      star = found.songs.where(isStar).firstOrNull;
    } catch (e) {
      debugPrint('readme: ricerca fallita: $e');
    }
  }
  if (star != null) {
    player.debugStageForShots(star, at);
  } else {
    debugPrint('readme: "$readmeShotsTrack" non trovato');
    await player.seek(at);
  }
  await settle(3000);

  // Non per il README: la pagina di tutte le categorie, per guardare le
  // tessere Browse quando si ritoccano.
  if (readmeShotsSet == 'browse') {
    select(NavTabController.search);
    tab(
      NavTabController.search,
    ).push(MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()));
    await settle(8000);
    await shot('browse');
    debugPrint('readme: fatto');
    return;
  }

  // Non per il README: la barra delle schede a meta' viaggio e il filo di
  // avanzamento preso e trascinato, con eventi di puntatore finti (il
  // mouse vero resta dov'e').
  if (readmeShotsSet == 'tabs') {
    select(NavTabController.home);
    await settle(1500);
    await shot('tabs_idle');
    select(NavTabController.library);
    for (var i = 1; i <= 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 95));
      await shot('tabs_mid$i');
    }
    await settle(1200);
    await shot('tabs_end');

    // Il dito: giu' su Home, striscia su Search e poi su Library, su;
    // poi tenuto premuto sulla copertina e trascinato a destra.
    final bar = _find<WordTabBar>();
    if (bar != null) {
      final box = bar.renderObject! as RenderBox;
      final c = box.localToGlobal(
        Offset(
          box.size.width / 2,
          box.size.height - WordTabBar.orbitHeight / 2,
        ),
      );
      final g = GestureBinding.instance;
      var id = 900;
      Future<void> stroke(
        List<Offset> path, {
        int holdMs = 0,
        String? shotAt,
      }) async {
        id++;
        g.handlePointerEvent(
          PointerAddedEvent(
            pointer: id,
            position: path.first,
            kind: PointerDeviceKind.touch,
          ),
        );
        g.handlePointerEvent(
          PointerDownEvent(
            pointer: id,
            position: path.first,
            kind: PointerDeviceKind.touch,
          ),
        );
        if (holdMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: holdMs));
        }
        var last = path.first;
        for (final p in path.skip(1)) {
          for (var i = 1; i <= 8; i++) {
            final q = Offset.lerp(last, p, i / 8)!;
            await Future<void>.delayed(const Duration(milliseconds: 25));
            g.handlePointerEvent(
              PointerMoveEvent(
                pointer: id,
                position: q,
                kind: PointerDeviceKind.touch,
              ),
            );
          }
          last = p;
        }
        await settle(450);
        if (shotAt != null) await shot(shotAt);
        g.handlePointerEvent(
          PointerUpEvent(
            pointer: id,
            position: last,
            kind: PointerDeviceKind.touch,
          ),
        );
      }

      await stroke([
        c + const Offset(-150, 12),
        c + const Offset(-86, -14),
        c + const Offset(86, -14),
        c + const Offset(150, 12),
      ], shotAt: 'tabs_slide');
      await settle(1200);
      await shot('tabs_slid');
      // Un mouse che passa sopra il giro: la lente.
      const mouse = 990;
      final hoverAt = c + const Offset(70, -10);
      g.handlePointerEvent(
        PointerAddedEvent(
          pointer: mouse,
          position: hoverAt,
          kind: PointerDeviceKind.mouse,
        ),
      );
      g.handlePointerEvent(
        PointerHoverEvent(
          pointer: mouse,
          position: hoverAt,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await settle(500);
      await shot('tabs_hover');
      g.handlePointerEvent(
        PointerRemovedEvent(
          pointer: mouse,
          position: hoverAt,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await settle(400);
      await stroke(
        [c, c + const Offset(90, 0)],
        holdMs: 700,
        shotAt: 'tabs_drag',
      );
      await settle(800);
      await shot('tabs_after');
    } else {
      debugPrint('readme: barra non trovata');
    }
    debugPrint('readme: fatto');
    return;
  }

  if (readmeShotsSet == 'wide') {
    select(NavTabController.home);
    await settle();
    await shot('wide');
    debugPrint('readme: fatto');
    return;
  }

  select(NavTabController.home);
  await settle();
  await shot('home');

  select(NavTabController.search);
  await settle();
  await shot('search');

  select(NavTabController.library);
  await settle(800);
  tab(
    NavTabController.library,
  ).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen()));
  await settle();
  await shot('stats');
  tab(NavTabController.library).pop();
  await settle(800);
  tab(
    NavTabController.library,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  await settle();
  await shot('settings');
  tab(NavTabController.library).pop();
  select(NavTabController.home);
  await settle(800);

  for (final pane in [null, 'lyrics', 'queue']) {
    root().push(
      PlayerRoute<void>(builder: (_) => NowPlayingScreen(initialPane: pane)),
    );
    await settle(3500);
    await shot(pane ?? 'player');
    if (pane == null) {
      showEqSheet(rootNavigatorKey.currentContext!);
      await settle();
      await shot('eq');
      root().pop();
      await settle(800);
    }
    root().pop();
    await settle(900);
  }
  debugPrint('readme: fatto');
}

/// Il primo elemento dell'albero con un widget di tipo [T].
Element? _find<T extends Widget>() {
  Element? hit;
  void visit(Element e) {
    if (hit != null) return;
    if (e.widget is T) {
      hit = e;
      return;
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return hit;
}
