import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/playlists_screen.dart';
import 'package:crocuta/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

Track _t(String id, String title) => Track(
  id: id,
  title: title,
  author: 'Marea Bassa',
  duration: const Duration(minutes: 3),
  thumbnailUrl: '',
);

/// Lascia finire le scritture su disco partite nel tempo finto del test.
///
/// Hive scrive nel tempo vero, ma il seguito delle sue attese gira in
/// quello finto: servono tutti e due, a turno, finche' la catena si esaurisce.
Future<void> _flush(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'nella playlist un brano si toglie scorrendo e Annulla lo rimette al suo posto',
    (tester) async {
      await capture(
        tester,
        const PlaylistsScreen(),
        name: 'playlist_pagina',
        overrides: [
          playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        ],
        interact: (t) async {
          final container = ProviderScope.containerOf(
            t.element(find.byType(PlaylistsScreen)),
          );
          final playlists = container.read(playlistsProvider.notifier);
          await t.runAsync(() async {
            await playlists.create('Notturno');
            for (final (id, title) in [
              ('a', 'Primo'),
              ('b', 'Secondo'),
              ('c', 'Terzo'),
            ]) {
              await playlists.addTrack(0, _t(id, title));
            }
          });
          await t.pumpAndSettle();
          await t.tap(find.text('Notturno'));
          await t.pumpAndSettle();

          // Niente pulsante "togli" su ogni riga, e il riepilogo in fondo.
          expect(find.byIcon(Icons.remove_circle_outline_rounded), findsNothing);
          expect(find.text('3 songs, 9 minutes'), findsOneWidget);

          await t.drag(find.text('Secondo'), const Offset(-400, 0));
          // La riga esce nel tempo finto del test, ma il disco scrive in
          // quello vero: l'"Undo" arriva solo dopo la scrittura.
          await t.pumpAndSettle();
          await _flush(t);
          expect(find.text('Secondo'), findsNothing);
          expect(
            container.read(playlistsProvider).first.tracks.map((t) => t.id),
            ['a', 'c'],
          );

          await t.tap(find.text('Undo'));
          await _flush(t);
          expect(
            container.read(playlistsProvider).first.tracks.map((t) => t.id),
            ['a', 'b', 'c'],
          );
        },
      );
    },
  );
}
