import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/services/smart_playlists.dart';

Track t(String id) => Track(id: id, title: id, author: 'x', thumbnailUrl: '');

void main() {
  final now = DateTime(2026, 9, 25, 12);
  final tracks = {
    for (final id in ['a', 'b', 'c', 'd']) id: t(id),
  };

  test('On Repeat: i piu\' ascoltati del mese, almeno due volte', () {
    final log = <Play>[
      for (var i = 0; i < 3; i++) ('a', now.subtract(Duration(days: i)), 180),
      for (var i = 0; i < 5; i++) ('b', now.subtract(Duration(days: i)), 180),
      ('c', now.subtract(const Duration(days: 2)), 180), // una volta sola
      for (var i = 0; i < 9; i++)
        ('d', now.subtract(const Duration(days: 45)), 180),
    ];
    expect([for (final x in onRepeat(log, tracks, now: now)) x.id], ['b', 'a']);
  });

  test('Late Night: solo fra le 22 e le 4', () {
    final log = <Play>[
      ('a', DateTime(2026, 9, 1, 23), 100),
      ('a', DateTime(2026, 9, 2, 2), 100),
      ('b', DateTime(2026, 9, 1, 15), 100),
      ('b', DateTime(2026, 9, 2, 16), 100),
    ];
    expect([for (final x in lateNight(log, tracks)) x.id], ['a']);
  });

  test('Recently Liked: gli ultimi aggiunti, dal piu\' recente', () {
    final favs = [t('a'), t('b'), t('c')];
    final added = {
      'a': now.subtract(const Duration(days: 90)).millisecondsSinceEpoch,
      'b': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      'c': now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
    };
    // Pochi nel mese: gli ultimi aggiunti comunque.
    expect(
      [for (final x in recentlyLiked(favs, added, now: now)) x.id],
      ['b', 'c', 'a'],
    );
  });

  test('Forgotten: preferiti non ascoltati da due mesi', () {
    final favs = [t('a'), t('b'), t('c'), t('d')];
    final lastPlayed = {
      'a': now.subtract(const Duration(days: 100)),
      'b': now.subtract(const Duration(days: 3)),
    };
    final added = {
      'c': now.subtract(const Duration(days: 200)).millisecondsSinceEpoch,
      'd': now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
    };
    // c aggiunto 200 giorni fa e mai ascoltato: il piu' dimenticato. d e'
    // nuovo, b ascoltato da poco.
    expect(
      [for (final x in forgotten(favs, lastPlayed, added, now: now)) x.id],
      ['c', 'a'],
    );
  });
}
