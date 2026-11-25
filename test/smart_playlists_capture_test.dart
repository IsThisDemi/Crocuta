import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/services/library_views.dart';
import 'package:yeen_music/services/smart_playlists.dart';
import 'package:yeen_music/widgets/smart_playlist_views.dart';

import 'support/capture.dart';

final _songs = [
  for (var i = 0; i < 12; i++)
    Track(id: 's$i', title: 'Brano $i', author: 'Artista', thumbnailUrl: ''),
];

final _lists = [for (final k in SmartKind.values) SmartPlaylist(k, _songs)];

void main() {
  testWidgets('cattura: la fila Made for You', (tester) async {
    await capture(
      tester,
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(height: 240, child: SmartPlaylistRail()),
      ),
      name: 'smart_rail',
      size: const Size(640, 260),
      overrides: [smartPlaylistsProvider.overrideWithValue(_lists)],
    );
    expect(find.text('On Repeat'), findsWidgets);
    expect(find.text('Late Night'), findsWidgets);
  });
}
