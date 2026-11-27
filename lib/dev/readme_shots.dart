import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import '../services/mix_info.dart';
import '../screens/browse_screens.dart';
import '../screens/eq_screen.dart';
import '../screens/now_playing_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/video_screen.dart';
import '../widgets/spot_slider.dart';
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

  // Non per il README: i video nella ricerca e la sala del videoclip. La
  // misura della finestra la decide chi lancia l'app (vedi
  // CROCUTA_WINDOW_SIZE in MainFlutterWindow.swift): larga e' la sala, a
  // misura di telefono la colonna.
  if (readmeShotsSet == 'video') {
    final search = ref.read(searchProvider.notifier);
    select(NavTabController.search);
    await search.search('ninja gaiden deko itsoktocry');
    await settle(7000);
    await shot('v_search_top');
    final videos = ref.read(searchProvider).videos;
    await search.search('$readmeShotsArtist $readmeShotsTrack');
    await settle(7000);
    await shot('v_search_after');
    if (videos.isEmpty) {
      debugPrint('readme: nessun video trovato');
      debugPrint('readme: fatto');
      return;
    }
    // Il primo che si apre davvero: senza l'accesso a YouTube quelli con
    // un limite d'eta' (il videoclip ufficiale, qui) non si aprono.
    final service = ref.read(youtubeServiceProvider);
    var pick = videos.first;
    for (final v in videos.take(5)) {
      if (await service.resolveAudio(v.id) != null) {
        pick = v;
        break;
      }
    }
    debugPrint('readme: video ${pick.id} ${pick.title}');
    // Uno che non si apre: la pagina dev'essere il player, copertina e
    // comandi, senza scritte.
    if (pick.id != videos.first.id) {
      unawaited(
        VideoScreen.open(rootNavigatorKey.currentContext!, videos.first),
      );
      await settle(9000);
      await shot('v_missing');
      root().pop();
      await settle(1000);
    }
    // Il video come brano in ascolto, seguito dalla coda di prima: cosi' la
    // sala ha un "dopo" da proporre.
    player.debugStageForShots(pick, Duration.zero);
    await settle(1000);
    unawaited(VideoScreen.open(rootNavigatorKey.currentContext!, pick));
    await settle(1200);
    await shot('v_loading');
    await settle(12000);
    await shot('v_full');
    // Un mouse che passa: i comandi tornano.
    final g = GestureBinding.instance;
    final size = rootNavigatorKey.currentContext!.size!;
    final at = Offset(size.width / 2, size.height / 2);
    g.handlePointerEvent(
      PointerAddedEvent(
        pointer: 970,
        position: at,
        kind: PointerDeviceKind.mouse,
      ),
    );
    g.handlePointerEvent(
      PointerHoverEvent(
        pointer: 970,
        position: at + const Offset(4, 4),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await settle(1200);
    await shot('v_chrome');
    g.handlePointerEvent(
      PointerRemovedEvent(
        pointer: 970,
        position: at,
        kind: PointerDeviceKind.mouse,
      ),
    );
    // Alla fine: il prossimo, col conto alla rovescia.
    final seek = VideoScreen.debugSeek;
    if (seek != null) {
      final total = pick.duration ?? const Duration(minutes: 2);
      await seek(total - const Duration(seconds: 2));
      await settle(5000);
      await shot('v_end');
    }
    root().pop();
    await settle(800);
    debugPrint('readme: fatto');
    return;
  }

  // Non per il README: la barra di avanzamento presa col mouse mentre il
  // brano suona (muto), piu' volte, per vedere se a volte non risponde.
  if (readmeShotsSet == 'seek') {
    final g = GestureBinding.instance;
    await player.setVolume(0);
    await player.resumeSession();
    await settle(8000);
    root().push(PlayerRoute<void>(builder: (_) => const NowPlayingScreen()));
    await settle(3000);
    Rect? seekRect() {
      Rect? hit;
      for (final e in _findAll<SpotSlider>()) {
        if ((e.widget as SpotSlider).seed != 'seek') continue;
        final box = e.renderObject;
        if (box is! RenderBox || !box.attached) continue;
        hit = box.localToGlobal(Offset.zero) & box.size;
      }
      return hit;
    }

    var id = 1500;
    const mouse = PointerDeviceKind.mouse;
    for (var k = 0; k < 8; k++) {
      final r = seekRect();
      if (r == null) {
        debugPrint('readme: seek nessuna barra');
        break;
      }
      final before = ref.read(playerProvider).position;
      final to = k.isEven ? 0.25 + 0.05 * k : 0.7 - 0.05 * k;
      final a = Offset(r.left + r.width * (to - 0.1), r.center.dy);
      final b = Offset(r.left + r.width * to, r.center.dy);
      id++;
      g.handlePointerEvent(
        PointerAddedEvent(pointer: id, position: a, kind: mouse),
      );
      g.handlePointerEvent(
        PointerHoverEvent(pointer: id, position: a, kind: mouse),
      );
      g.handlePointerEvent(
        PointerDownEvent(
          pointer: id,
          position: a,
          kind: mouse,
          buttons: kPrimaryMouseButton,
        ),
      );
      if (k % 3 != 2) {
        var last = a;
        for (var i = 1; i <= 8; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final q = Offset.lerp(a, b, i / 8)!;
          g.handlePointerEvent(
            PointerMoveEvent(
              pointer: id,
              position: q,
              delta: q - last,
              kind: mouse,
              buttons: kPrimaryMouseButton,
            ),
          );
          last = q;
        }
      }
      final at = k % 3 != 2 ? b : a;
      g.handlePointerEvent(
        PointerUpEvent(pointer: id, position: at, kind: mouse),
      );
      await settle(1500);
      final after = ref.read(playerProvider).position;
      final dur = ref.read(playerProvider).duration;
      debugPrint(
        'readme: seek $k ${k % 3 != 2 ? 'trascina' : 'clic'} a '
        '${(at.dx - r.left) / r.width} -> prima $before dopo $after di $dur '
        'mixing ${ref.read(playerProvider).mixing}',
      );
      g.handlePointerEvent(
        PointerRemovedEvent(pointer: id, position: at, kind: mouse),
      );
      await settle(2500);
    }
    await player.toggle();
    root().pop();
    debugPrint('readme: fatto');
    return;
  }

  // Non per il README: le barre (avanzamento e volume) a riposo, col mouse
  // sopra e tenute col dito, con eventi di puntatore finti.
  if (readmeShotsSet == 'sliders') {
    final g = GestureBinding.instance;
    Rect? rectOf(String seed) {
      // L'ultima: quella della pagina in cima (la tana sotto ha la sua).
      Rect? hit;
      for (final e in _findAll<SpotSlider>()) {
        if ((e.widget as SpotSlider).seed != seed) continue;
        final box = e.renderObject;
        if (box is! RenderBox || !box.attached) continue;
        hit = box.localToGlobal(Offset.zero) & box.size;
      }
      debugPrint('readme: barra $seed $hit');
      return hit;
    }

    var id = 1200;
    Future<void> hold(Rect r, double from, double to, String name) async {
      id++;
      final a = Offset(r.left + r.width * from, r.center.dy);
      final b = Offset(r.left + r.width * to, r.center.dy);
      const touch = PointerDeviceKind.touch;
      g.handlePointerEvent(
        PointerAddedEvent(pointer: id, position: a, kind: touch),
      );
      g.handlePointerEvent(
        PointerDownEvent(pointer: id, position: a, kind: touch),
      );
      // Col delta: e' lui che il riconoscitore del trascinamento somma.
      var last = a;
      for (var i = 1; i <= 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        final q = Offset.lerp(a, b, i / 10)!;
        g.handlePointerEvent(
          PointerMoveEvent(
            pointer: id,
            position: q,
            delta: q - last,
            kind: touch,
          ),
        );
        last = q;
      }
      await settle(600);
      await shot(name);
      g.handlePointerEvent(
        PointerUpEvent(pointer: id, position: b, kind: touch),
      );
      await settle(600);
    }

    Future<void> hover(Rect r, String name) async {
      id++;
      final at = Offset(r.left + r.width * 0.3, r.center.dy);
      const mouse = PointerDeviceKind.mouse;
      g.handlePointerEvent(
        PointerAddedEvent(pointer: id, position: at, kind: mouse),
      );
      g.handlePointerEvent(
        PointerHoverEvent(pointer: id, position: at, kind: mouse),
      );
      await settle(700);
      await shot(name);
      g.handlePointerEvent(
        PointerRemovedEvent(pointer: id, position: at, kind: mouse),
      );
      await settle(400);
    }

    final volume = ref.read(playerProvider).volume;
    root().push(PlayerRoute<void>(builder: (_) => const NowPlayingScreen()));
    await settle(3500);
    await shot('s_flat');
    player.debugMixForShots();
    ref.read(mixPlanProvider.notifier).state = null;
    await settle(1500);
    await shot('s_rest');
    final seek = rectOf('seek');
    final vol = rectOf('volume');
    if (seek != null) {
      await hover(seek, 's_hover_seek');
      final f =
          ref.read(playerProvider).position.inMilliseconds /
          math.max(1, ref.read(playerProvider).duration.inMilliseconds);
      await hold(seek, f, f + 0.15, 's_drag_seek');
      await hold(seek, 0.9, 0.99, 's_drag_end');
    }
    if (vol != null) {
      await hover(vol, 's_hover_volume');
      await hold(
        vol,
        math.min(0.97, volume / 100),
        math.min(0.97, volume / 100) - 0.25,
        's_drag_volume',
      );
      // Il volume si salva: si rimette quello di prima.
      ref.read(playerProvider.notifier).setVolume(volume);
    }
    // Il mix: prima il segno di dove partira', poi in corso. Il brano
    // torna dov'era: le prese di prima l'hanno spostato.
    if (star != null) player.debugStageForShots(star, at);
    player.debugMixForShots();
    await settle(1500);
    await shot('s_mix_upcoming');
    for (final p in [0.2, 0.5, 0.8]) {
      player.debugMixForShots(progress: p);
      await settle(1200);
      await shot('s_mix_${(p * 100).round()}');
    }
    player.debugMixForShots(progress: null);
    ref.read(mixPlanProvider.notifier).state = null;
    root().pop();
    await settle(900);

    select(NavTabController.library);
    await settle(800);
    tab(
      NavTabController.library,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await settle(2500);
    final el = _findAll<SpotSlider>().firstOrNull;
    if (el != null) {
      await Scrollable.ensureVisible(el, alignment: 0.5);
      await settle(900);
      await shot('s_settings');
    }
    tab(NavTabController.library).pop();
    select(NavTabController.home);
    await settle(1500);
    await shot('s_home');
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

/// Tutti gli elementi dell'albero con un widget di tipo [T].
List<Element> _findAll<T extends Widget>() {
  final hits = <Element>[];
  void visit(Element e) {
    if (e.widget is T) hits.add(e);
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return hits;
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
