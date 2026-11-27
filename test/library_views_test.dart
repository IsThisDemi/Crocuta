import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/services/library_views.dart';

Track _t(String id, {String? albumId, String? album}) => Track(
  id: id,
  title: 'Brano $id',
  author: 'Yeat & Drake',
  thumbnailUrl: 'art-$id',
  albumId: albumId,
  albumName: album,
);

void main() {
  test('dal piu recente; i salvati senza data in fondo, dal piu nuovo', () {
    final favs = [_t('vecchio1'), _t('vecchio2'), _t('a'), _t('b')];
    final out = recentlyAdded(favs, {'a': 100, 'b': 200});
    expect(out.map((t) => t.id), ['b', 'a', 'vecchio2', 'vecchio1']);
  });

  test('un disco per album, solo se si sa quale', () {
    final albums = albumsOf([
      _t('1', albumId: 'MPRE_A', album: 'ADL'),
      _t('2', albumId: 'MPRE_A', album: 'ADL'),
      _t('3'),
      _t('4', albumId: 'MPRE_B', album: 'Lyfestyle'),
    ]);
    expect(albums.map((a) => a.title), ['ADL', 'Lyfestyle']);
    expect(albums.first.browseId, 'MPRE_A');
    // L'artista principale, non la riga col feat.
    expect(albums.first.subtitle, 'Yeat');
  });

  _liked();
}

Track _s(String id, String title, String author, {String? album, int? secs}) =>
    Track(
      id: id,
      title: title,
      author: author,
      thumbnailUrl: '',
      albumName: album,
      duration: secs == null ? null : Duration(seconds: secs),
    );

void _liked() {
  final favs = [
    _s('1', 'Passion', 'PinkPantheress', album: 'Fancy That'),
    _s('2', 'Hatër', 'Yeat', album: 'LYFESTYLE'),
    _s('3', 'Berserker', 'Kid Yugi'),
    _s('4', 'Anemone', 'Yeat', album: 'LYFESTYLE'),
  ];
  final added = {'1': 400, '2': 300, '3': 200, '4': 100};

  test('i piaciuti: dal piu recente, per titolo, per artista, per disco', () {
    List<String> ids(SongSort s) => [
      for (final t in sortSongs(favs, sort: s, addedAt: added)) t.id,
    ];
    expect(ids(SongSort.added), ['1', '2', '3', '4']);
    // Una playlist resta nell'ordine in cui l'hai costruita.
    expect(ids(SongSort.playlist), ['1', '2', '3', '4']);
    expect(ids(SongSort.title), ['4', '3', '2', '1']);
    // Stesso artista: decide il titolo.
    expect(ids(SongSort.artist), ['3', '1', '4', '2']);
    // Senza disco in fondo, non in cima.
    expect(ids(SongSort.album), ['1', '4', '2', '3']);
  });

  test('cercare guarda titolo, artisti e disco, senza maiuscole', () {
    List<String> find(String q) => [
      for (final t in sortSongs(
        favs,
        sort: SongSort.added,
        query: q,
        addedAt: added,
      ))
        t.id,
    ];
    expect(find('yeat'), ['2', '4']);
    expect(find('FANCY'), ['1']);
    expect(find('  berser '), ['3']);
    expect(find('niente'), isEmpty);
  });

  test('il riepilogo dice i minuti solo se li sa tutti', () {
    expect(songsSummary([]), '0 songs');
    expect(songsSummary([favs.first]), '1 song');
    expect(
      songsSummary([
        _s('a', 'A', 'X', secs: 1500),
        _s('b', 'B', 'X', secs: 1620),
      ]),
      '2 songs, 52 minutes',
    );
    expect(
      songsSummary([
        _s('a', 'A', 'X', secs: 3600),
        _s('b', 'B', 'X', secs: 60),
      ]),
      '2 songs, 1 hour, 1 minute',
    );
    expect(
      songsSummary([_s('a', 'A', 'X', secs: 60), favs.first]),
      '2 songs',
    );
  });

  test('un ordinamento salvato che non esiste piu torna al predefinito', () {
    expect(SongSort.byName('album', SongSort.liked), SongSort.album);
    expect(SongSort.byName('boh', SongSort.liked), SongSort.added);
    expect(SongSort.byName(null, SongSort.ofPlaylist), SongSort.playlist);
    // "Recently Added" non e' una voce delle playlist: si torna alla prima.
    expect(SongSort.byName('added', SongSort.ofPlaylist), SongSort.playlist);
  });
}
