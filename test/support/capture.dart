import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/app_theme.dart';
import 'package:crocuta/widgets/app_background.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/services/storage_service.dart';
import 'package:crocuta/widgets/toast.dart';

/// Renders a screen off-screen and writes what it actually looks like to a
/// PNG, so a layout can be inspected instead of guessed at.
///
/// Widget tests normally assert on the widget tree, which says nothing about
/// whether text is readable against its background. This paints real pixels.
Future<void> capture(
  WidgetTester tester,
  Widget screen, {
  required String name,
  List<Override> overrides = const [],
  Size size = const Size(430, 932), // iPhone 17 logical size
  Duration settle = const Duration(milliseconds: 600),

  /// Eseguito dopo il primo assestamento, per catturare uno stato che serve
  /// un gesto per raggiungere — tipicamente una superficie modale.
  Future<void> Function(WidgetTester tester)? interact,

  /// L'area sicura in cima, in pixel. Di norma zero, come una finestra
  /// desktop; passarla simula il notch dell'iPhone. Serve: una cattura
  /// senza area sicura non puo' mostrare un contenuto che finisce dietro
  /// la barra solo sul telefono, ed e' successo.
  double safeAreaTop = 0,
}) async {
  // storageServiceProvider esplode di proposito se non viene sovrascritto
  // ("Overridden in main()"). Senza questo ogni cattura usciva come lo
  // schermo d'errore rosso di Flutter, facendo sembrare rotta l'app quando
  // a mancare era il test.
  // testWidgets esegue il corpo in una zona a tempo finto: l'I/O reale non
  // si completa mai e l'await resta appeso per sempre. Hive apre file veri,
  // quindi va fatto dentro runAsync.
  late final StorageService storage;
  late final Directory hiveDir;
  await tester.runAsync(() async {
    hiveDir = await Directory.systemTemp.createTemp('crocuta_capture');
    storage = StorageService();
    await storage.init(path: hiveDir.path);
  });
  addTearDown(() {
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  if (safeAreaTop > 0) {
    tester.view.padding = FakeViewPadding(top: safeAreaTop);
    tester.view.viewPadding = FakeViewPadding(top: safeAreaTop);
  }
  addTearDown(tester.view.reset);

  final key = GlobalKey();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        ...overrides,
      ],
      // Il confine sta FUORI dal MaterialApp, non attorno alla sola schermata:
      // dialog, sheet e menu vivono nell'Overlay del Navigator, quindi un
      // confine su `home` li lascerebbe fuori dall'immagine.
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          // Le schermate dei tab non portano uno Scaffold: nell'app vivono
          // dentro il Material della shell, perche' GlassScaffold non ne
          // inserisce nessuno. Senza, un ListTile qui asserisce "No Material
          // widget found" per un motivo che l'app non ha.
          // AppBackground perche' nell'app la tela la mette la shell: senza,
          // una schermata di tab veniva catturata su fondo bianco e non si
          // poteva giudicare nulla del contrasto.
          // Uno Scaffold radice trasparente attorno al Navigator, come
          // quello dell'app, e sopra gli avvisi: senza, "Undo" non
          // comparirebbe e non si potrebbe toccare.
          builder: (context, child) => ToastHost(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: false,
              body: child,
            ),
          ),
          home: Material(
            type: MaterialType.transparency,
            child: AppBackground(child: screen),
          ),
        ),
      ),
    ),
  );

  // Images and async providers need a beat; pumpAndSettle would hang on the
  // screens that animate forever (the equalizer bars), so pump by hand.
  for (var i = 0; i < 12; i++) {
    await tester.pump(settle ~/ 12);
  }

  if (interact != null) {
    await interact(tester);
    for (var i = 0; i < 12; i++) {
      await tester.pump(settle ~/ 12);
    }
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Anche la codifica PNG e la scrittura su disco sono I/O reale.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final outDir = Directory('build/screens')..createSync(recursive: true);
    File(
      '${outDir.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
