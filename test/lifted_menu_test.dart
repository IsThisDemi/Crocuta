import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/widgets/glass_surfaces.dart';
import 'package:yeen_music/widgets/lifted_menu.dart';

void main() {
  const screen = Size(430, 932);
  const safe = EdgeInsets.only(top: 62, bottom: 34);
  const menu = Size(250, 360);

  test('con spazio sotto, il menu sta sotto e la riga non si muove', () {
    const row = Rect.fromLTWH(0, 200, 430, 64);
    final l = liftedMenuLayout(
      screen: screen,
      safe: safe,
      anchor: row,
      menu: menu,
    );
    expect(l.preview, row);
    expect(l.below, isTrue);
    expect(l.menu.dy, greaterThan(row.bottom));
  });

  test('in fondo allo schermo, il menu sale sopra la riga', () {
    const row = Rect.fromLTWH(0, 800, 430, 64);
    final l = liftedMenuLayout(
      screen: screen,
      safe: safe,
      anchor: row,
      menu: menu,
    );
    expect(l.preview, row);
    expect(l.below, isFalse);
    expect(l.menu.dy + menu.height, lessThan(row.top));
  });

  test('senza posto ne sopra ne sotto, e la riga a salire', () {
    const small = Size(430, 700);
    const row = Rect.fromLTWH(0, 330, 430, 64);
    final l = liftedMenuLayout(
      screen: small,
      safe: safe,
      anchor: row,
      menu: menu,
    );
    expect(l.preview.top, lessThan(row.top));
    expect(l.preview.height, row.height);
    // Il menu entra tutto, sotto la riga, dentro l'area sicura.
    expect(l.menu.dy, greaterThan(l.preview.bottom));
    expect(l.menu.dy + menu.height, lessThanOrEqualTo(small.height - 34));
  });

  testWidgets('scegliere una voce la restituisce e chiude', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                picked = await showLiftedMenu<String>(
                  context: context,
                  anchor: const Rect.fromLTWH(0, 100, 400, 60),
                  preview: const Text('Riga'),
                  items: const [
                    GlassMenuItem(
                      value: 'next',
                      icon: Icons.playlist_play_rounded,
                      label: 'Play next',
                    ),
                    GlassMenuItem(
                      value: 'album',
                      icon: Icons.album_rounded,
                      label: 'Go to album',
                      enabled: false,
                    ),
                  ],
                );
              },
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.text('Riga'), findsOneWidget);

    // Una voce spenta non fa niente.
    await tester.tap(find.text('Go to album'));
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsOneWidget);

    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    expect(picked, 'next');
    expect(find.text('Play next'), findsNothing);
  });
}
