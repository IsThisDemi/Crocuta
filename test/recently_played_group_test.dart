import 'package:flutter_test/flutter_test.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/screens/home_content.dart';

Track _t(String id, {String? album}) => Track(
  id: id,
  title: 'Song $id',
  author: 'Artist',
  thumbnailUrl: '',
  albumId: album,
  albumName: album == null ? null : 'Album $album',
);

void main() {
  test('piu\' brani dello stesso album diventano una voce sola', () {
    final items = groupRecentlyPlayed([
      _t('1', album: 'A'),
      _t('2', album: 'A'),
      _t('3', album: 'A'),
      _t('4', album: 'B'),
      _t('5'),
    ]);
    expect(items, hasLength(3));
    expect(items[0].isAlbum, isTrue);
    expect(items[0].track.id, '1');
    // Un brano solo del suo album resta un brano.
    expect(items[1].isAlbum, isFalse);
    expect(items[1].track.id, '4');
    expect(items[2].track.id, '5');
  });

  test('lo stesso brano ascoltato due volte conta una', () {
    final items = groupRecentlyPlayed([
      _t('1', album: 'A'),
      _t('9'),
      _t('1', album: 'A'),
    ]);
    expect(items.map((i) => i.track.id), ['1', '9']);
    expect(items.first.isAlbum, isFalse);
  });

  test('l\'album prende il posto del suo ascolto piu\' recente', () {
    final items = groupRecentlyPlayed([
      _t('x'),
      _t('1', album: 'A'),
      _t('y'),
      _t('2', album: 'A'),
    ]);
    expect(items.map((i) => i.track.id), ['x', '1', 'y']);
    expect(items[1].isAlbum, isTrue);
  });
}
