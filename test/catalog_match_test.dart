import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/services/youtube_service.dart';

({SongCandidate candidate, Duration? duration}) _c(
  String id,
  String title,
  String artists, [
  int? secs,
]) => (
  candidate: (id: id, title: title, artists: artists),
  duration: secs == null ? null : Duration(seconds: secs),
);

String? _pick(String title, String artist, int? secs, List<dynamic> cs) =>
    YouTubeService.pickCatalogSong(
      title,
      artist,
      secs == null ? null : Duration(seconds: secs),
      cs.cast(),
    );

void main() {
  test('gli ospiti nel titolo non contano', () {
    expect(
      YouTubeService.stripFeaturing(
        'After the Storm (feat. Tyler, The Creator & Bootsy Collins)',
      ),
      'After the Storm',
    );
    expect(YouTubeService.stripFeaturing('OMG feat. Wiz Khalifa'), 'OMG');
    expect(YouTubeService.stripFeaturing('Romeo (with X)'), 'Romeo');
    // "Feather" contiene "feat": non va toccato.
    expect(YouTubeService.stripFeaturing('Feather'), 'Feather');
  });

  test('il primo interprete', () {
    expect(YouTubeService.primaryArtist('Yeat & BNYX®'), 'Yeat');
    expect(
      YouTubeService.primaryArtist('BEYOND BORDERs, Hatsune Miku, Grimes'),
      'BEYOND BORDERs',
    );
    expect(YouTubeService.primaryArtist('Kid Yugi'), 'Kid Yugi');
  });

  test('lo stesso brano anche col feat solo da una parte', () {
    expect(
      _pick('After the Storm (feat. Tyler, The Creator & Bootsy Collins)',
          'Kali Uchis', 207, [
        _c('x', 'After The Storm', 'Kali Uchis, Tyler, The Creator', 208),
      ]),
      'x',
    );
  });

  test('la durata scarta live e versioni estese con lo stesso nome', () {
    expect(
      _pick('ADHD', 'HXG', 150, [
        _c('live', 'ADHD', 'HXG', 230),
        _c('ok', 'ADHD', 'HXG', 151),
      ]),
      'ok',
    );
    expect(_pick('ADHD', 'HXG', 150, [_c('live', 'ADHD', 'HXG', 230)]), isNull);
  });

  test('un altro artista con lo stesso titolo non e\' lo stesso brano', () {
    expect(
      _pick('Passion', 'PinkPantheress', 138, [
        _c('no', 'Passion', 'Someone Else', 138),
      ]),
      isNull,
    );
  });

  test('prima il titolo esatto, poi quello senza "Radio Edit"', () {
    expect(
      _pick('Romeo', 'PinkPantheress', 120, [
        _c('radio', 'Romeo (Radio Edit)', 'PinkPantheress', 118),
        _c('esatto', 'Romeo', 'PinkPantheress', 121),
      ]),
      'esatto',
    );
    expect(
      _pick('Romeo', 'PinkPantheress', 120, [
        _c('radio', 'Romeo (Radio Edit)', 'PinkPantheress', 118),
      ]),
      'radio',
    );
  });

  test('titoli in cirillico e maiuscole diverse', () {
    expect(
      _pick('Силиконовый Гном', 'Мэйби Бэйби', 212, [
        _c('ok', 'СИЛИКОНОВЫЙ ГНОМ', 'Мэйби Бэйби', 213),
      ]),
      'ok',
    );
  });

  test('un artista rinominato: MARINA e\' Marina and The Diamonds', () {
    expect(
      _pick('Homewrecker', 'Marina and The Diamonds', 202, [
        _c('ok', 'Homewrecker', 'MARINA', 203),
      ]),
      'ok',
    );
    // Senza durata da controllare, il verso inverso non basta.
    expect(
      _pick('Homewrecker', 'Marina and The Diamonds', 202, [
        _c('ok', 'Homewrecker', 'MARINA'),
      ]),
      isNull,
    );
  });
}
