import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/app_theme.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/services/player_controller.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/widgets/track_tile.dart';

/// Registra le due azioni invece di aprire libmpv.
class RecordingPlayer extends PlayerController {
  final calls = <String>[];

  @override
  PlayerState build() => const PlayerState();

  @override
  void playNext(Track track) => calls.add('next:${track.id}');

  @override
  void addToQueue(Track track) => calls.add('queue:${track.id}');
}

const song = Track(id: 's1', title: 'Hatër', author: 'Yeat', thumbnailUrl: '');

void main() {
  late RecordingPlayer player;

  Future<void> pump(WidgetTester tester, {bool swipe = true}) async {
    player = RecordingPlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith(() => player)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              children: [
                TrackTile(
                  track: song,
                  enableContextMenu: false,
                  enableSwipeActions: swipe,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a destra: riproduci dopo, e la riga resta', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Hatër'), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(player.calls, ['next:s1']);
    // Non e' stata tolta: torna al suo posto.
    expect(find.text('Hatër'), findsOneWidget);
  });

  testWidgets('a sinistra: aggiungi alla coda', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Hatër'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(player.calls, ['queue:s1']);
    expect(find.text('Hatër'), findsOneWidget);
  });

  testWidgets('uno scorrimento corto non fa niente', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Hatër'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(player.calls, isEmpty);
  });

  testWidgets('spento, lo scorrimento non fa niente', (tester) async {
    await pump(tester, swipe: false);
    await tester.drag(find.text('Hatër'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(player.calls, isEmpty);
  });
}
