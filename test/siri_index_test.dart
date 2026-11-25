import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/services/follows_controller.dart';
import 'package:yeen_music/services/siri_service.dart';

Track song(String id, {String title = 'Brano', String artist = 'Tizio'}) =>
    Track(id: id, title: title, author: artist, thumbnailUrl: '');

List<String> idsOf(Map<String, dynamic> index) => [
  for (final s in index['songs'] as List) (s as Map)['id'] as String,
];

void main() {
  group("l'indice pubblicato a Siri", () {
    test('mette i preferiti per primi, poi playlist, poi recenti', () {
      final index = SiriService.buildIndex(
        favorites: [song('fav')],
        playlists: [
          UserPlaylist(name: 'Mia', tracks: [song('pl')]),
        ],
        recents: [song('rec')],
        artists: const [],
      );

      // L'ordine non e' estetico: in coda si taglia, e il taglio deve
      // colpire cio' che e' meno probabile tu chieda a voce.
      expect(idsOf(index), ['fav', 'pl', 'rec']);
    });

    test('non ripete un brano che sta in piu'
        r' posti', () {
      final index = SiriService.buildIndex(
        favorites: [song('x')],
        playlists: [
          UserPlaylist(name: 'Mia', tracks: [song('x'), song('y')]),
        ],
        recents: [song('x')],
        artists: const [],
      );

      expect(idsOf(index), ['x', 'y']);
    });

    test('taglia al tetto, tenendo la testa della lista', () {
      final index = SiriService.buildIndex(
        favorites: [for (var i = 0; i < 10; i++) song('f$i')],
        playlists: const [],
        recents: [song('tardi')],
        artists: const [],
        maxSongs: 3,
      );

      expect(idsOf(index), ['f0', 'f1', 'f2']);
      expect(idsOf(index), isNot(contains('tardi')));
    });

    test('scarta i titoli vuoti: Siri non puo'
        r' pronunciarli', () {
      final index = SiriService.buildIndex(
        favorites: [
          song('vuoto', title: '   '),
          song('pieno'),
        ],
        playlists: const [],
        recents: const [],
        artists: const [],
      );

      expect(idsOf(index), ['pieno']);
    });

    test('esclude le playlist vuote, che non si possono riprodurre', () {
      final index = SiriService.buildIndex(
        favorites: const [],
        playlists: [
          const UserPlaylist(name: 'Vuota'),
          UserPlaylist(name: 'Piena', tracks: [song('a')]),
        ],
        recents: const [],
        artists: const [],
      );

      final playlists = index['playlists'] as List;
      expect(playlists, hasLength(1));
      expect((playlists.single as Map)['name'], 'Piena');
      // L'id e' la posizione nell'elenco vero, non nell'elenco filtrato:
      // e' con quello che Dart va a ripescare la playlist da riprodurre.
      expect((playlists.single as Map)['id'], '1');
    });

    test('pubblica gli artisti seguiti con il loro browseId', () {
      final index = SiriService.buildIndex(
        favorites: const [],
        playlists: const [],
        recents: const [],
        artists: const [
          FollowedArtist(browseId: 'UC123', name: 'Yeat'),
          FollowedArtist(browseId: 'UC456', name: '  '),
        ],
      );

      final artists = index['artists'] as List;
      expect(artists, hasLength(1));
      expect((artists.single as Map)['id'], 'UC123');
      expect((artists.single as Map)['name'], 'Yeat');
    });
  });
}
