import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/widgets/artist_links.dart';

Track t(String title, String author) =>
    Track(id: 'x', title: title, author: author, thumbnailUrl: '');

void main() {
  test('divide gli artisti sui separatori usati da YouTube Music', () {
    expect(ArtistLinks.splitArtists('Tizio, Caio & Sempronio'), [
      'Tizio',
      'Caio',
      'Sempronio',
    ]);
    expect(ArtistLinks.splitArtists('Tizio feat. Caio'), ['Tizio', 'Caio']);
    expect(ArtistLinks.splitArtists('Tizio ft Caio'), ['Tizio', 'Caio']);
  });

  test('non spezza nomi che contengono x o and', () {
    // "x" e "and" separano solo se circondati da spazi.
    expect(ArtistLinks.splitArtists('Maxwell'), ['Maxwell']);
    expect(ArtistLinks.splitArtists('Portishead'), ['Portishead']);
    expect(ArtistLinks.splitArtists('Tizio x Caio'), ['Tizio', 'Caio']);
  });

  test('trova gli ospiti nel titolo', () {
    // Caso reale: il campo artista ha solo l'interprete principale, gli
    // ospiti stanno fra parentesi nel titolo.
    expect(
      ArtistLinks.featuredFromTitle('CLUB TEST (con IvanBi, Diss Gacha)'),
      ['IvanBi', 'Diss Gacha'],
    );
    expect(ArtistLinks.featuredFromTitle('Brano (feat. Tizio)'), ['Tizio']);
  });

  test('unisce artista e ospiti senza ripetizioni', () {
    // Il titolo di questo brano ripete lo stesso gruppo due volte: i nomi
    // devono comparire una volta sola.
    final names = ArtistLinks.allArtists(
      t('CLUB TEST (con IvanBi, Diss Gacha) (con IvanBi e Diss Gacha)', 'Sala'),
    );
    expect(names, ['Sala', 'IvanBi', 'Diss Gacha']);
  });

  test('un titolo senza parentesi non aggiunge nulla', () {
    expect(ArtistLinks.allArtists(t('Brano semplice', 'Tizio')), ['Tizio']);
  });
}
