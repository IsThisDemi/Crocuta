import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/widgets/drawer_dismiss.dart';

/// Apre una route con dentro il cassetto, una maniglia in cima e una lista
/// lunga sotto — la forma della schermata in riproduzione.
Future<void> openDrawer(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DrawerDismiss(
                    enabled: true,
                    child: Scaffold(
                      body: Column(
                        children: [
                          const DrawerHandle(
                            child: SizedBox(
                              height: 60,
                              child: Center(child: Text('maniglia')),
                            ),
                          ),
                          Expanded(
                            child: Builder(
                              builder: (context) => ListView(
                                physics: DrawerDismiss.physicsOf(context),
                                children: [
                                  for (var i = 0; i < 60; i++)
                                    SizedBox(
                                      height: 56,
                                      child: Text('riga $i'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
  expect(find.text('riga 0'), findsOneWidget);
}

bool isOpen() => find.text('maniglia').evaluate().isNotEmpty;

void main() {
  testWidgets('tirato giu abbastanza dalla cima, si chiude', (tester) async {
    await openDrawer(tester);

    // Lento: si verifica la soglia di distanza, non quella di velocita'.
    await tester.timedDrag(
      find.text('riga 2'),
      const Offset(0, 260),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    expect(isOpen(), isFalse);
  });

  testWidgets('tirato giu poco, torna su', (tester) async {
    await openDrawer(tester);

    await tester.timedDrag(
      find.text('riga 2'),
      const Offset(0, 70),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    expect(isOpen(), isTrue);
    // Ed e' tornato esattamente al suo posto.
    expect(tester.getTopLeft(find.text('maniglia')).dy, lessThan(40));
  });

  testWidgets('a lista scorsa, tirare giu scorre invece di chiudere', (
    tester,
  ) async {
    await openDrawer(tester);

    // Prima si scende nella lista...
    await tester.timedDrag(
      find.text('riga 3'),
      const Offset(0, -400),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();
    expect(find.text('riga 0'), findsNothing);

    // ...poi si tira giu' meno di quanto si e' sceso: la lista risale, il
    // cassetto non si muove. Come in Apple Music, si stacca solo in cima.
    // Dal centro della lista e non da una riga precisa: dopo la prima
    // scorsa l'inerzia decide quali righe restano a schermo.
    await tester.timedDragFrom(
      tester.getCenter(find.byType(ListView)),
      const Offset(0, 200),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    expect(isOpen(), isTrue);
    expect(tester.getTopLeft(find.text('maniglia')).dy, lessThan(40));
  });

  testWidgets('dalla maniglia si chiude anche a lista scorsa', (tester) async {
    await openDrawer(tester);

    await tester.timedDrag(
      find.text('riga 3'),
      const Offset(0, -400),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    await tester.timedDrag(
      find.text('maniglia'),
      const Offset(0, 260),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();

    expect(isOpen(), isFalse);
  });

  testWidgets("l'app sotto si vede solo mentre lo si trascina", (tester) async {
    await openDrawer(tester);
    final route = ModalRoute.of(tester.element(find.text('riga 0')))!;

    // A riposo e' opaca: la shell sotto e' fuori scena, e con lei i suoi
    // vetri di sistema.
    expect(route.overlayEntries.first.opaque, isTrue);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('riga 2')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();

    // Durante il trascinamento diventa trasparente, cosi' scendendo si vede
    // cosa c'e' sotto.
    expect(route.overlayEntries.first.opaque, isFalse);

    await gesture.up();
    await tester.pumpAndSettle();

    // Tornata su, torna opaca.
    expect(isOpen(), isTrue);
    expect(route.overlayEntries.first.opaque, isTrue);
  });

  testWidgets('chiudendo col trascinamento, la copertina non vola', (
    tester,
  ) async {
    await openDrawer(tester);
    HeroMode mode() => tester.widget<HeroMode>(find.byType(HeroMode));

    // A riposo il volo e' acceso: aprendo e chiudendo col tasto la
    // copertina deve tornare nel mini player.
    expect(mode().enabled, isTrue);

    await tester.timedDrag(
      find.text('riga 2'),
      const Offset(0, 260),
      const Duration(milliseconds: 700),
    );
    await tester.pump();

    // Mentre scende per chiudersi, no: la copertina sta gia' fuori
    // schermo, e la si vedrebbe risalire dal fondo.
    expect(mode().enabled, isFalse);
    await tester.pumpAndSettle();
  });
}
