import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:yeen_music/main.dart' as app;
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/home_content.dart';
import 'package:yeen_music/screens/library_screen.dart';
import 'package:yeen_music/screens/queue_screen.dart';
import 'package:yeen_music/screens/search_screen.dart';
import 'package:yeen_music/services/storage_service.dart';

/// Smoke test della UI: percorre ogni tab e ogni sotto-schermata della
/// libreria e fallisce se una qualsiasi lancia un'eccezione durante il build.
///
/// Serve a non dover più verificare le schermate a occhio con gli screenshot.
/// Avrebbe intercettato da solo due regressioni reali di questo lavoro:
/// il cast di `getAllPlayStats` che faceva crashare Stats in release, e la
/// mancanza di un antenato `Material` sotto `GlassScaffold`, che rendeva
/// ogni testo nello stile d'errore di Flutter.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  /// Fallisce indicando *dove* si è rotto, invece di un generico test rosso.
  void expectNoError(WidgetTester tester, String where) {
    final e = tester.takeException();
    expect(e, isNull, reason: 'Eccezione in "$where": $e');
  }

  Future<void> pumpApp(WidgetTester tester) async {
    final storage = StorageService();
    await storage.init();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const app.CrocutaApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('ogni tab si disegna senza eccezioni', (tester) async {
    await pumpApp(tester);
    expectNoError(tester, 'avvio');

    // Si tocca l'icona e non l'etichetta. `warnIfMissed: false` perché la
    // tab bar impagina i tab in un FittedBox: i bounds del widget non
    // coincidono con il punto in cui il tap colpisce, e tap() emette un
    // falso positivo. Che il tap arrivi davvero lo dimostra l'assert sotto,
    // che pretende il cambio di schermata.
    const tabs = <(IconData, String, Type)>[
      (Icons.home_rounded, 'Home', HomeContent),
      (Icons.search_rounded, 'Cerca', SearchScreen),
      (Icons.library_music_rounded, 'Libreria', LibraryScreen),
      (Icons.queue_music_rounded, 'Coda', QueueScreen),
    ];

    for (final (icon, label, screen) in tabs) {
      final tab = find.byIcon(icon);
      expect(tab, findsWidgets, reason: 'tab "$label" non trovato');
      await tester.tap(tab.first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectNoError(tester, 'tab $label');

      // Gli altri tab restano montati nell'IndexedStack ma offstage, e i
      // finder di default saltano l'offstage: quindi questo passa solo se
      // il tab selezionato è davvero cambiato.
      expect(
        find.byType(screen),
        findsOneWidget,
        reason: 'il tap su "$label" non ha cambiato schermata',
      );
    }
  });

  testWidgets('il testo ha un antenato Material', (tester) async {
    await pumpApp(tester);

    // Senza un Material sopra, Flutter disegna ogni Text in rosso con la
    // doppia sottolineatura gialla invece di usare il tema. Non lancia
    // eccezioni, quindi va verificato esplicitamente.
    expect(
      find.ancestor(of: find.text('Home'), matching: find.byType(Material)),
      findsWidgets,
      reason:
          'nessun Material sopra la tab bar: i testi useranno lo '
          'stile di errore di Flutter',
    );
  });

  testWidgets('le sotto-schermate della libreria si aprono', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.library_music_rounded).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expectNoError(tester, 'Libreria');

    for (final row in [
      'Preferiti',
      'Playlist',
      'Ascoltati di recente',
      'Statistiche',
    ]) {
      final entry = find.text(row);
      if (entry.evaluate().isEmpty) continue;

      await tester.tap(entry.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectNoError(tester, 'apertura $row');

      final back = find.byTooltip('Indietro');
      expect(back, findsWidgets, reason: 'nessun tasto indietro in "$row"');
      await tester.tap(back.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectNoError(tester, 'ritorno da $row');
    }
  });
}
