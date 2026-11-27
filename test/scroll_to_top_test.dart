import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/navigation.dart';

void main() {
  testWidgets('porta in cima la lista verticale, non le file orizzontali', (
    tester,
  ) async {
    final root = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyedSubtree(
            key: root,
            // La forma della Home: una lista verticale che contiene file
            // orizzontali di schede.
            child: ListView(
              children: [
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < 20; i++)
                        SizedBox(width: 100, child: Text('scheda $i')),
                    ],
                  ),
                ),
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 56, child: Text('riga $i')),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('riga 3'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('riga 0'), findsNothing);

    final moved = scrollFirstListToTop(root.currentContext!);
    await tester.pumpAndSettle();

    expect(moved, isTrue);
    expect(find.text('riga 0'), findsOneWidget);
  });

  testWidgets('gia in cima non fa niente', (tester) async {
    final root = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyedSubtree(
            key: root,
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 56, child: Text('riga $i')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(scrollFirstListToTop(root.currentContext!), isFalse);
  });
}
