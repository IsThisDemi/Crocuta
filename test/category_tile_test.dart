import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/explore.dart';
import 'package:crocuta/screens/browse_screens.dart';

double contrastOnWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

void main() {
  // I colori veri di YouTube Music: Energize, Chill, Commute, un rosso, un
  // viola, un grigio.
  const energize = 0xFFFFE082;
  const chill = 0xFFA8C7FA;
  const commute = 0xFFFFCA28;
  const red = 0xFFE53935;
  const purple = 0xFF7E57C2;
  const grey = 0xFF616161;

  test('il bianco si legge su ogni tessera, anche sul giallo pastello', () {
    for (final c in [energize, chill, commute, red, purple, grey]) {
      final (top, bottom) = CategoryTile.tones(c);
      // Si misura dove sta il nome: sul colore col velo sopra.
      for (final tone in [top, bottom]) {
        expect(
          contrastOnWhite(CategoryTile.underTitle(tone)),
          greaterThanOrEqualTo(CategoryTile.minContrast),
          reason: c.toRadixString(16),
        );
      }
    }
  });

  test('i colori restano vivaci: niente senape, niente grigio', () {
    for (final c in [chill, red, purple]) {
      final top = HSLColor.fromColor(CategoryTile.tones(c).$1);
      // La tinta resta la sua...
      final src = HSLColor.fromColor(Color(c)).hue;
      expect((top.hue - src).abs(), lessThan(4), reason: c.toRadixString(16));
      // ...e satura, non spenta verso il grigio.
      expect(top.saturation, greaterThanOrEqualTo(0.6));
    }

    // I gialli diventano arancioni, accesi e non oliva: la tinta sta
    // nell'arancione e la luce non scende fino al marrone.
    for (final c in [energize, commute]) {
      final (t, b) = CategoryTile.tones(c);
      final top = HSLColor.fromColor(t);
      expect(top.hue, inInclusiveRange(24, 40), reason: c.toRadixString(16));
      expect(top.saturation, greaterThanOrEqualTo(0.6));
      expect(top.lightness, greaterThanOrEqualTo(0.42));
      // Il fondo della sfumatura e' la stessa tinta piu' profonda.
      final bottom = HSLColor.fromColor(b);
      expect(bottom.lightness, lessThan(top.lightness));
      expect(bottom.saturation, greaterThanOrEqualTo(top.saturation));
    }

    // Un grigio resta grigio: non ci si inventa un colore.
    final g = HSLColor.fromColor(CategoryTile.tones(grey).$1);
    expect(g.saturation, lessThan(0.12));
  });

  group('la griglia della ricerca mostra solo righe piene', () {
    final items = [
      for (var i = 0; i < 14; i++)
        BrowseCategory(title: 'Cat $i', color: 0xFF7E57C2, params: 'p$i'),
    ];

    for (final (width, columns) in [(430.0, 2), (1000.0, 4), (1100.0, 5)]) {
      testWidgets('larga $width: $columns colonne, due righe', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CategoryGrid(items: items, rows: 2),
                ),
              ),
            ),
          ),
        );
        expect(find.byType(CategoryTile), findsNWidgets(columns * 2));
      });
    }

    testWidgets('con poche categorie, le righe intere che si riempiono', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CategoryGrid(items: items.take(8).toList(), rows: 2),
              ),
            ),
          ),
        ),
      );
      // Cinque colonne e otto categorie: una riga intera, non 5 + 3.
      expect(find.byType(CategoryTile), findsNWidgets(5));
    });
  });
}
