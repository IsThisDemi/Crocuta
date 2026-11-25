import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/widgets/glass_surfaces.dart';

void main() {
  testWidgets('il foglio si apre sul navigator radice, non su quello del tab', (
    tester,
  ) async {
    // La shell ha un Navigator per scheda, e disegna tab bar e brano in
    // riproduzione *fuori* da quelli. Un foglio aperto dentro una scheda
    // finiva percio' sotto la chrome, con le ultime voci coperte.
    final inner = GlobalKey<NavigatorState>();
    final root = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        theme: buildAppTheme(),
        home: Navigator(
          key: inner,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showGlassSheet<void>(
                    context: context,
                    builder: (_) => const Text('voce'),
                  ),
                  child: const Text('apri'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(root.currentState!.canPop(), isFalse);

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    expect(find.text('voce'), findsOneWidget);
    // La prova: la route del foglio sta sulla radice. Sul navigator della
    // scheda non c'e' finito niente.
    expect(root.currentState!.canPop(), isTrue);
    expect(inner.currentState!.canPop(), isFalse);
  });
}
