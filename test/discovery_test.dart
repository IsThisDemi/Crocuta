import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/services/discovery.dart';

Track t(String id, [String artist = 'x']) =>
    Track(id: id, title: id, author: artist, thumbnailUrl: '');

void main() {
  test('Discover: solo brani mai sentiti, prima quelli in piu\' radio', () {
    final radios = [
      [t('a', 'A'), t('n1', 'N1'), t('n2', 'N2')],
      [t('n2', 'N2'), t('b', 'B'), t('n3', 'N3')],
    ];
    final out = pickDiscover(radios, {'a', 'b'});
    expect([for (final x in out) x.id], ['n2', 'n1', 'n3']);
  });

  test('Discover: al massimo due brani per artista', () {
    final radios = [
      [for (var i = 0; i < 5; i++) t('s$i', 'Stesso')],
    ];
    expect(pickDiscover(radios, {}).length, 2);
  });

  test('Daily Mix: conosciuti e nuovi alternati', () {
    final mix = buildMix(
      seeds: [t('k1'), t('k2')],
      radios: [
        [t('n1'), t('k3'), t('n2')],
      ],
      heard: {'k1', 'k2', 'k3'},
    );
    expect([for (final x in mix) x.id], ['k1', 'n1', 'k2', 'n2', 'k3']);
  });

  test('gli artisti dei mix: i piu\' ascoltati, coi loro brani migliori', () {
    final tracks = {
      'a1': t('a1', 'Alfa'),
      'a2': t('a2', 'Alfa, Ospite'),
      'b1': t('b1', 'Beta'),
    };
    final out = mixArtists({'a1': 5, 'a2': 9, 'b1': 3}, tracks);
    expect(out.first.$1, 'Alfa');
    expect([for (final x in out.first.$2) x.id], ['a2', 'a1']);
    expect(out[1].$1, 'Beta');
  });

  test('Discover Weekly cambia il lunedi\'', () {
    expect(weekKey(DateTime(2026, 9, 28)), weekKey(DateTime(2026, 10, 4)));
    expect(
      weekKey(DateTime(2026, 9, 27)),
      isNot(weekKey(DateTime(2026, 9, 28))),
    );
  });
}
