import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/app_theme.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/widgets/mini_player.dart';

import 'support/fake_player.dart';

const _track = Track(
  id: 'abc123',
  title: 'Titolo di prova',
  author: 'Artista di prova',
  thumbnailUrl: '',
);

void main() {
  Future<void> pumpMiniPlayer(WidgetTester tester, PlayerState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith(() => FakePlayer(state))],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: MiniPlayer()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mostra titolo, artista e i comandi', (tester) async {
    await pumpMiniPlayer(
      tester,
      const PlayerState(
        queue: [_track],
        currentIndex: 0,
        isPlaying: true,
        position: Duration(seconds: 50),
        duration: Duration(seconds: 200),
      ),
    );

    expect(find.text('Titolo di prova'), findsOneWidget);
    expect(find.text('Artista di prova'), findsOneWidget);
    // In riproduzione il comando deve offrire la pausa, non il play.
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
  });

  testWidgets('senza brano corrente non disegna nulla', (tester) async {
    await pumpMiniPlayer(tester, const PlayerState());
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Titolo di prova'), findsNothing);
  });
}
