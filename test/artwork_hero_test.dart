import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/widgets/artwork_hero.dart';

Widget art({bool enabled = true}) => ArtworkHero(
  url: '',
  radius: 8,
  enabled: enabled,
  child: const SizedBox.square(dimension: 40),
);

/// Una pagina con dei mini player, e un pulsante che apre il "player".
Widget app(List<Widget> minis) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Column(
        children: [
          ...minis,
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Center(
                    child: ArtworkHero(
                      url: '',
                      radius: 28,
                      child: const SizedBox.square(dimension: 300),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('apri'),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('spento, non porta il tag', (tester) async {
    await tester.pumpWidget(MaterialApp(home: art(enabled: false)));
    expect(find.byType(Hero), findsNothing);
  });

  testWidgets('la copertina vola dal mini player al player', (tester) async {
    await tester.pumpWidget(app([art()]));
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // A meta' volo la copertina sta fra le due misure: e' in viaggio, non
    // e' ne' la miniatura ne' la copertina grande.
    final flying = tester.getSize(
      find
          .descendant(
            of: find.byType(Overlay),
            matching: find.byType(ClipPath),
          )
          .last,
    );
    expect(flying.width, greaterThan(40));
    expect(flying.width, lessThan(300));

    await tester.pumpAndSettle();
  });

  testWidgets('due mini player, uno solo col tag: il volo parte', (
    tester,
  ) async {
    // Con la barra compressa i mini player sono due. Questo e' il caso
    // giusto: il tag lo porta uno solo.
    await tester.pumpWidget(app([art(), art(enabled: false)]));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('due mini player col tag: e il motivo per cui ne serve uno', (
    tester,
  ) async {
    await tester.pumpWidget(app([art(), art()]));
    await tester.tap(find.text('apri'));
    await tester.pump();
    // Flutter rifiuta due Hero con lo stesso tag nella stessa route.
    expect(tester.takeException(), isNotNull);
  });
}
