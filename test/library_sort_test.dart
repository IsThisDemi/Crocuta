import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/artist.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/services/follows_controller.dart';
import 'package:crocuta/services/library_sort.dart';

Track _s(
  String id,
  String title,
  String author, {
  String? album,
  int? secs,
  bool explicit = false,
}) => Track(
  id: id,
  title: title,
  author: author,
  thumbnailUrl: '',
  albumName: album,
  duration: secs == null ? null : Duration(seconds: secs),
  isExplicit: explicit,
);

List<String> _ids(List<Track> ts) => [for (final t in ts) t.id];

LibraryView _v(SortKey k, {bool rev = false, Set<SongFilter> f = const {}}) =>
    LibraryView(k, reversed: rev, filters: f);

void main() {
  group('testi', () {
    test('senza maiuscole ne accenti, numeri in ordine naturale', () {
      final words = [
        'Zeta',
        'écoute',
        'beta',
        'Eagle',
        'fade',
        'Track 10',
        'track 2',
      ];
      expect([...words]..sort(compareText), [
        'beta',
        'Eagle',
        'écoute',
        'fade',
        'track 2',
        'Track 10',
        'Zeta',
      ]);
    });

    test('"The" davanti a un artista non conta, se dopo c e altro', () {
      final names = ['The Weeknd', 'Travis Scott', 'The', 'Weezer', 'Theo'];
      expect([...names]..sort(compareArtists), [
        'The',
        'Theo',
        'Travis Scott',
        'The Weeknd',
        'Weezer',
      ]);
    });
  });

  group('brani', () {
    final songs = [
      _s('1', 'Passion', 'PinkPantheress', album: 'Fancy That', secs: 200),
      _s('2', 'Hatër', 'Yeat', album: 'LYFESTYLE', secs: 150, explicit: true),
      _s('3', 'Berserker', 'Kid Yugi'),
      _s('4', 'Anemone', 'Yeat', album: 'LYFESTYLE', secs: 180),
      _s('5', 'Ébano', 'The Kid LAROI', album: 'Ébano', secs: 90),
    ];
    final added = {'1': 500, '2': 400, '3': 300, '4': 200, '5': 100};

    test('Recently Added dal piu nuovo, e girato dal piu vecchio', () {
      expect(_ids(sortTracks(songs, _v(SortKey.added), addedAt: added)), [
        '1',
        '2',
        '3',
        '4',
        '5',
      ]);
      expect(
        _ids(sortTracks(songs, _v(SortKey.added, rev: true), addedAt: added)),
        ['5', '4', '3', '2', '1'],
      );
      // Senza date conta la posizione: l'ultimo aggiunto e' l'ultimo.
      expect(_ids(sortTracks(songs, _v(SortKey.added))), [
        '5',
        '4',
        '3',
        '2',
        '1',
      ]);
    });

    test('titolo con gli accenti al loro posto, e al contrario', () {
      expect(_ids(sortTracks(songs, _v(SortKey.title))), [
        '4',
        '3',
        '5',
        '2',
        '1',
      ]);
      expect(_ids(sortTracks(songs, _v(SortKey.title, rev: true))), [
        '1',
        '2',
        '5',
        '3',
        '4',
      ]);
    });

    test('artista senza "The", poi disco, poi titolo', () {
      // The Kid LAROI sta alla K, prima di Kid Yugi.
      expect(_ids(sortTracks(songs, _v(SortKey.artist))), [
        '5',
        '3',
        '1',
        '4',
        '2',
      ]);
    });

    test('senza disco in fondo, in tutti e due i versi', () {
      expect(_ids(sortTracks(songs, _v(SortKey.album))), [
        '5',
        '1',
        '4',
        '2',
        '3',
      ]);
      expect(_ids(sortTracks(songs, _v(SortKey.album, rev: true))), [
        '4',
        '2',
        '1',
        '5',
        '3',
      ]);
    });

    test('piu ascoltati in cima; a parita decide il titolo', () {
      final plays = {'3': 9, '1': 4, '4': 4};
      expect(_ids(sortTracks(songs, _v(SortKey.plays), plays: plays)), [
        '3',
        '4',
        '1',
        '5',
        '2',
      ]);
      expect(
        _ids(sortTracks(songs, _v(SortKey.plays, rev: true), plays: plays)),
        ['5', '2', '4', '1', '3'],
      );
    });

    test('durata dalla piu corta; senza durata in fondo', () {
      expect(_ids(sortTracks(songs, _v(SortKey.duration))), [
        '5',
        '2',
        '4',
        '1',
        '3',
      ]);
      expect(_ids(sortTracks(songs, _v(SortKey.duration, rev: true))), [
        '1',
        '4',
        '2',
        '5',
        '3',
      ]);
    });

    test('stabile: a parita di tutto resta l ordine di partenza', () {
      final same = [
        for (var i = 0; i < 40; i++) _s('$i', 'Uguale', 'Stesso', album: 'X'),
      ];
      for (final k in [SortKey.title, SortKey.artist, SortKey.album]) {
        expect(_ids(sortTracks(same, _v(k))), _ids(same), reason: k.name);
        expect(
          _ids(sortTracks(same, _v(k, rev: true))),
          _ids(same),
          reason: '${k.name} girato',
        );
      }
    });

    test('Hide Explicit toglie gli espliciti', () {
      final out = sortTracks(
        songs,
        _v(SortKey.added, f: {SongFilter.clean}),
        addedAt: added,
      );
      expect(_ids(out), ['1', '3', '4', '5']);
    });

    test('Downloaded Only lascia gli scaricati, e si somma alla ricerca', () {
      final view = _v(SortKey.title, f: {SongFilter.downloaded});
      expect(_ids(sortTracks(songs, view, downloaded: {'2', '4', '9'})), [
        '4',
        '2',
      ]);
      expect(
        _ids(sortTracks(songs, view, query: 'hater', downloaded: {'2', '4'})),
        ['2'],
      );
      expect(sortTracks(songs, view), isEmpty);
    });

    test('cercare ignora maiuscole e accenti', () {
      expect(_ids(sortTracks(songs, _v(SortKey.title), query: 'EBANO')), ['5']);
      expect(_ids(sortTracks(songs, _v(SortKey.title), query: 'lyfe')), [
        '4',
        '2',
      ]);
    });

    test('ordine della playlist, e al contrario', () {
      expect(_ids(sortTracks(songs, _v(SortKey.playlist))), _ids(songs));
      expect(
        _ids(sortTracks(songs, _v(SortKey.playlist, rev: true))),
        _ids(songs).reversed,
      );
    });
  });

  group('vista', () {
    test('toccare la voce attiva gira il verso, un altra riparte', () {
      final v = LibraryView.initial(SortKey.liked);
      expect(v.isCustom(SortKey.liked), isFalse);
      final flipped = v.pick(SortKey.added);
      expect(flipped.reversed, isTrue);
      expect(flipped.direction, 'Oldest First');
      expect(flipped.isCustom(SortKey.liked), isTrue);
      final byTitle = flipped.pick(SortKey.title);
      expect(byTitle.reversed, isFalse);
      expect(byTitle.direction, 'A to Z');
    });

    test('i filtri si accendono, si spengono e restano cambiando voce', () {
      final v = LibraryView.initial(
        SortKey.liked,
      ).toggle(SongFilter.clean).pick(SortKey.artist);
      expect(v.filters, {SongFilter.clean});
      expect(v.toggle(SongFilter.clean).filters, isEmpty);
      expect(v.withoutFilters.filters, isEmpty);
      expect(v.withoutFilters.sort, SortKey.artist);
    });

    test(
      'si salva e si rilegge; i valori vecchi o estranei tornano di serie',
      () {
        final v = _v(SortKey.plays, rev: true, f: {SongFilter.downloaded});
        final back = LibraryView.decode(
          v.encodeSort,
          v.encodeFilters,
          options: SortKey.liked,
          allowed: SongFilter.values,
        );
        expect(back, v);
        // Quello che salvava la versione di prima.
        expect(
          LibraryView.decode('artist', const [], options: SortKey.liked),
          _v(SortKey.artist),
        );
        expect(
          LibraryView.decode('boh:rev', const ['boh'], options: SortKey.liked),
          _v(SortKey.added),
        );
        // Un filtro che la pagina non offre non si accende.
        expect(
          LibraryView.decode(
            'title',
            const ['downloaded'],
            options: SortKey.downloads,
            allowed: const [SongFilter.clean],
          ).filters,
          isEmpty,
        );
      },
    );

    test('Memo ricalcola solo quando cambia la chiave', () {
      final memo = Memo<int>();
      var runs = 0;
      final list = [1, 2];
      int compute() => ++runs;
      memo((list, _v(SortKey.title)), compute);
      memo((list, _v(SortKey.title)), compute);
      expect(runs, 1);
      memo(([1, 2], _v(SortKey.title)), compute);
      expect(runs, 2, reason: 'una lista nuova e una lista cambiata');
      memo(([1, 2], _v(SortKey.title, rev: true)), compute);
      expect(runs, 3);
    });
  });

  group('dischi', () {
    AlbumCard a(String id, String title, String artist) => AlbumCard(
      browseId: id,
      title: title,
      subtitle: artist,
      thumbnailUrl: '',
    );
    final albums = [
      a('A', 'Lyfestyle', 'Yeat'),
      a('B', 'After Hours', 'The Weeknd'),
      a('C', 'Fancy That', 'PinkPantheress'),
      a('D', '2093', 'Yeat'),
    ];

    test('di serie come arrivano, girati al contrario', () {
      expect(sortAlbums(albums, _v(SortKey.added)), albums);
      expect(sortAlbums(albums, _v(SortKey.added, rev: true)), albums.reversed);
    });

    test('per titolo e per artista senza "The"', () {
      expect(
        [for (final x in sortAlbums(albums, _v(SortKey.title))) x.browseId],
        ['D', 'B', 'C', 'A'],
      );
      expect(
        [for (final x in sortAlbums(albums, _v(SortKey.artist))) x.browseId],
        ['C', 'B', 'D', 'A'],
      );
    });

    test('per anno dal piu nuovo, senza anno in fondo', () {
      final years = {'A': 2025, 'B': 2020, 'D': 2025};
      expect(
        [
          for (final x in sortAlbums(albums, _v(SortKey.year), years: years))
            x.browseId,
        ],
        ['D', 'A', 'B', 'C'],
      );
      expect(
        [
          for (final x in sortAlbums(
            albums,
            _v(SortKey.year, rev: true),
            years: years,
          ))
            x.browseId,
        ],
        ['B', 'D', 'A', 'C'],
      );
      expect(yearsCoverEnough(albums, years), isTrue);
      expect(yearsCoverEnough(albums, {'A': 2025}), isFalse);
      expect(yearsCoverEnough(const [], const {}), isFalse);
    });
  });

  group('artisti', () {
    const artists = [
      FollowedArtist(browseId: 'w', name: 'The Weeknd'),
      FollowedArtist(browseId: 'a', name: 'ANNA'),
      FollowedArtist(browseId: 'k', name: 'kid yugi'),
      FollowedArtist(browseId: 'y', name: 'Yeat'),
    ];

    test('per nome senza "The" e senza maiuscole', () {
      expect(
        [for (final x in sortArtists(artists, _v(SortKey.name))) x.browseId],
        ['a', 'k', 'w', 'y'],
      );
      expect(
        [
          for (final x in sortArtists(artists, _v(SortKey.name, rev: true)))
            x.browseId,
        ],
        ['y', 'w', 'k', 'a'],
      );
    });

    test('dall ultimo seguito; i senza data in fondo, dal piu nuovo', () {
      final at = {'a': 100, 'y': 300};
      expect(
        [
          for (final x in sortArtists(
            artists,
            _v(SortKey.followed),
            followedAt: at,
          ))
            x.browseId,
        ],
        ['y', 'a', 'k', 'w'],
      );
      expect(
        [
          for (final x in sortArtists(
            artists,
            _v(SortKey.followed, rev: true),
            followedAt: at,
          ))
            x.browseId,
        ],
        ['w', 'k', 'a', 'y'],
      );
    });
  });

  group('playlist', () {
    final pls = [
      UserPlaylist(name: 'notte', createdAt: DateTime(2026, 1)),
      UserPlaylist(name: 'Allenamento', createdAt: DateTime(2026, 3)),
      UserPlaylist(name: 'Èstate', createdAt: DateTime(2026, 2)),
    ];
    const ids = ['p0', 'p1', 'p2'];

    List<int> order(LibraryView v, {Map<String, int> updated = const {}}) => [
      for (final (i, _) in sortPlaylists(pls, v, ids: ids, updatedAt: updated))
        i,
    ];

    test('dalla piu recente, con la posizione vera', () {
      expect(order(_v(SortKey.added)), [1, 2, 0]);
      expect(order(_v(SortKey.added, rev: true)), [0, 2, 1]);
    });

    test('per ultima modifica; senza modifica conta la creazione', () {
      final updated = {'p0': DateTime(2026, 6).millisecondsSinceEpoch};
      expect(order(_v(SortKey.updated), updated: updated), [0, 1, 2]);
    });

    test('per nome, senza maiuscole ne accenti', () {
      expect(order(_v(SortKey.name)), [1, 2, 0]);
      expect(order(_v(SortKey.name, rev: true)), [0, 2, 1]);
    });
  });
}
