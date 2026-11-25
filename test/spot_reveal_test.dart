import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/design/motion.dart';

/// Le pagine si aprono dentro una macchia che parte dal punto toccato.
void main() {
  testWidgets('a meta\' apertura la pagina e\' ritagliata a macchia', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: buildAppTheme(),
        builder: (context, child) => TapOriginTracker(child: child!),
        home: const Scaffold(body: Center(child: Text('home'))),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('page')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final clip = find.ancestor(
      of: find.text('page'),
      matching: find.byType(ClipPath),
    );
    expect(clip, findsWidgets);
    expect(lastTapPosition, const Offset(100, 100));

    await tester.pumpAndSettle();
    // A fine corsa il ritaglio sparisce: la pagina e' intera.
    expect(
      find.ancestor(of: find.text('page'), matching: find.byType(ClipPath)),
      findsNothing,
    );
  });
}
