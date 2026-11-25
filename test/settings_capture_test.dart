import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/settings_screen.dart';
import 'package:yeen_music/services/player_state.dart';

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
    expect(find.text('Crocuta Connect'), findsOneWidget);
  });
}
