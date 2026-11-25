import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/app_shell.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/widgets/den_rail.dart';
import 'package:yeen_music/widgets/spot_controls.dart';
import 'package:yeen_music/widgets/word_tab_bar.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _track = Track(
  id: 'abc123',
  title: 'Where Do We Go',
  author: 'Ayra Starr',
  thumbnailUrl: '',
);

final _playing = [
  playerProvider.overrideWith(
    () => FakePlayer(
      const PlayerState(
        queue: [_track],
        currentIndex: 0,
        isPlaying: true,
        position: Duration(seconds: 50),
        duration: Duration(seconds: 200),
      ),
    ),
  ),
];

/// La shell di Macchia ha due forme: la tana a sinistra quando c'e'
/// spazio, le parole in basso sul telefono. Mai tutte e due.
void main() {
  testWidgets('finestra larga: la tana a sinistra, niente barra in basso', (
    tester,
  ) async {
    await capture(
      tester,
      const AppShell(),
      name: 'macchia_shell_largo',
      size: const Size(1300, 820),
      overrides: _playing,
    );
    expect(find.byType(DenRail), findsOneWidget);
    expect(find.byType(WordTabBar), findsNothing);
    // Il brano in ascolto sta in fondo alla tana.
    expect(
      find.descendant(
        of: find.byType(DenRail),
        matching: find.text('Where Do We Go'),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(find.byType(DenRail)).left, 0);
  });

  testWidgets('telefono: le parole in basso col mini player sopra', (
    tester,
  ) async {
    await capture(
      tester,
      const AppShell(),
      name: 'macchia_shell_telefono',
      overrides: _playing,
    );
    expect(find.byType(DenRail), findsNothing);
    expect(find.byType(WordTabBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WordTabBar),
        matching: find.byType(SpotPlayButton),
      ),
      findsOneWidget,
    );
    final bar = tester.getRect(find.byType(WordTabBar));
    expect(bar.bottom, 932);
    for (final word in ['Home', 'Search', 'Library', 'Queue']) {
      expect(
        find.descendant(of: find.byType(WordTabBar), matching: find.text(word)),
        findsOneWidget,
      );
    }
  });

  testWidgets('toccare una parola cambia sezione', (tester) async {
    await capture(
      tester,
      const AppShell(),
      name: 'macchia_shell_libreria',
      overrides: _playing,
      interact: (t) async {
        await t.tap(
          find.descendant(
            of: find.byType(WordTabBar),
            matching: find.text('Library'),
          ),
        );
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(container.read(navTabProvider), 2);
  });
}
