import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/library_screen.dart';
import 'package:yeen_music/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _recents = [
  Track(
    id: 'a',
    title: 'Corrente Ascensionale',
    author: 'Marea Bassa',
    thumbnailUrl: '',
  ),
  Track(
    id: 'b',
    title: 'Luce Radente',
    author: 'Marea Bassa',
    thumbnailUrl: '',
  ),
  Track(
    id: 'c',
    title: 'Campo Lungo',
    author: 'Vetro Sottile',
    thumbnailUrl: '',
  ),
  Track(id: 'd', title: 'Nebbia', author: 'Terzo Piano', thumbnailUrl: ''),
];

const _favs = [
  Track(
    id: 'a',
    title: 'Corrente Ascensionale',
    author: 'Marea Bassa',
    thumbnailUrl: '',
  ),
];

class _FakeRecents extends RecentlyPlayedController {
  @override
  List<Track> build() => _recents;
}

class _FakeFavorites extends FavoritesController {
  @override
  List<Track> build() => _favs;
}

void main() {
  testWidgets('cattura: libreria', (tester) async {
    await capture(
      tester,
      const LibraryScreen(),
      name: 'libreria',
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        recentlyPlayedProvider.overrideWith(_FakeRecents.new),
        favoritesProvider.overrideWith(_FakeFavorites.new),
      ],
    );
  });

  testWidgets('cattura: libreria su finestra larga', (tester) async {
    await capture(
      tester,
      const LibraryScreen(),
      name: 'libreria_larga',
      size: const Size(1800, 900),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        recentlyPlayedProvider.overrideWith(_FakeRecents.new),
        favoritesProvider.overrideWith(_FakeFavorites.new),
      ],
    );

    // Il contenuto deve restare in una colonna, non correre da bordo a bordo.
    // La voce e' una parola grande con il conteggio accanto, in un unico
    // Text.rich: si cerca il testo dentro.
    final row = tester.getRect(
      find.textContaining('Liked songs', findRichText: true),
    );
    expect(row.left, greaterThan(200), reason: 'la colonna non e\' centrata');
  });
}
