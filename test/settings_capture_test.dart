import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/settings_screen.dart';
import 'package:crocuta/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

void main() {
  testWidgets('cattura: impostazioni', (tester) async {
    await capture(
      tester,
      const SettingsScreen(),
      name: 'settings',
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(const PlayerState(automix: true)),
        ),
      ],
    );
    expect(find.text('Animated Covers'), findsOneWidget);
    expect(find.text('Spots Follow the Music'), findsOneWidget);
    // Piu' giu' della prima schermata, da quando Aspetto ha tre righe.
    await tester.scrollUntilVisible(
      find.text('Crocuta Connect'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Crocuta Connect'), findsOneWidget);
  });
}
