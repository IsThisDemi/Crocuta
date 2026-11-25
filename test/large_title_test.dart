import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/design/chrome.dart';
import 'package:yeen_music/widgets/large_title.dart';

Future<void> pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 59);
  tester.view.viewPadding = const FakeViewPadding(top: 59);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CollapsingTitleFrame(
          title: 'Library',
          child: SafeArea(
            bottom: false,
            child: Builder(
              // Lo stesso margine in cima delle pagine vere: sul Mac, dove
              // girano i test, i 28 pixel dei semafori.
              builder: (context) => ListView(
                padding: EdgeInsets.only(top: topWindowInset(context)),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: LargeTitle('Library'),
                  ),
                  for (var i = 0; i < 60; i++)
                    SizedBox(height: 56, child: Text('riga $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// L'opacita' della riga col titolo piccolo.
double smallTitleOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(
        of: find.text('Library').last,
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  testWidgets('a riposo il titolo piccolo non si vede', (tester) async {
    await pumpPage(tester);
    await tester.pump();
    // Due "Library": il grande nella lista e il piccolo in cima.
    expect(find.text('Library'), findsNWidgets(2));
    expect(smallTitleOpacity(tester), 0);
  });

  testWidgets('scorrendo, il grande se ne va e compare il piccolo', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.drag(find.text('riga 2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(smallTitleOpacity(tester), 1);
  });

  testWidgets('a meta strada il piccolo e a meta, non a scatto', (
    tester,
  ) async {
    await pumpPage(tester);
    // Quanto il grande stia sotto la riga del piccolo dipende dal suo
    // corpo, che il design cambia: si scorre a passi di tre pixel finche'
    // il piccolo non comincia a vedersi. La dissolvenza dura 18 pixel,
    // quindi al primo passo che lo accende dev'essere ancora a meta'.
    for (var i = 0; i < 40 && smallTitleOpacity(tester) == 0; i++) {
      await tester.drag(find.text('riga 2'), const Offset(0, -3));
      await tester.pumpAndSettle();
    }
    final o = smallTitleOpacity(tester);
    expect(o, greaterThan(0));
    expect(o, lessThan(1));
  });
}
