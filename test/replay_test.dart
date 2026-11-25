import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/services/replay.dart';

Track _t(String id, String author, {String? album, String? artistId}) => Track(
  id: id,
  title: 'Brano $id',
  author: author,
  thumbnailUrl: 'art-$id',
  albumId: album == null ? null : 'MPRE_$album',
  albumName: album,
  artistId: artistId,
);

void main() {
  // Mercoledi' 23 settembre 2026, a meta' giornata.
  final now = DateTime(2026, 9, 23, 14);

  test('i periodi cominciano a mezzanotte: lunedi, il primo, gennaio', () {
    expect(ReplayPeriod.week.start(now), DateTime(2026, 9, 21));
    expect(ReplayPeriod.month.start(now), DateTime(2026, 9));
    expect(ReplayPeriod.year.start(now), DateTime(2026));
    expect(ReplayPeriod.allTime.start(now), isNull);
  });

  final tracks = {
    'a': _t('a', 'Yeat', album: 'ADL', artistId: 'UCyeat'),
    'b': _t('b', 'Yeat & Drake', album: 'ADL'),
    'c': _t('c', 'Nettspend'),
  };
  final log = [
    ('a', DateTime(2026, 9, 22, 10), 200), // questa settimana
    ('a', DateTime(2026, 9, 22, 11), 200),
    ('c', DateTime(2026, 9, 22, 12), 900), // un solo ascolto, ma lungo
    ('b', DateTime(2026, 9, 2), 180), // questo mese, non questa settimana
    ('c', DateTime(2025, 12, 31), 100), // l'anno scorso
  ];

  ReplaySummary replay(
    ReplayPeriod p, {
    Map<String, String> photos = const {},
  }) => buildReplay(
    period: p,
    now: now,
    allTime: const {
      'a': TrackStats(playCount: 40, totalSeconds: 8000),
      'c': TrackStats(playCount: 5, totalSeconds: 1000),
    },
    log: log,
    tracks: tracks,
    artistPhotos: photos,
  );

  test('la settimana conta solo i suoi ascolti, per tempo ascoltato', () {
    final w = replay(ReplayPeriod.week);
    expect(w.plays, 3);
    expect(w.seconds, 1300);
    expect(w.songs, 2);
    // c: un ascolto da 900 s batte a: due da 200.
    expect(w.tracks.map((t) => t.track.id), ['c', 'a']);
  });

  test('il mese include la settimana e il resto del mese', () {
    final m = replay(ReplayPeriod.month);
    expect(m.plays, 4);
    // Yeat conta a e b insieme ("Yeat & Drake" e' suo).
    final yeat = m.artists.firstWhere((a) => a.name == 'Yeat');
    expect(yeat.plays, 3);
    expect(yeat.artistId, 'UCyeat');
    expect(m.albums.single.album.title, 'ADL');
    expect(m.albums.single.plays, 3);
  });

  test("sempre legge i totali, non il registro", () {
    final all = replay(ReplayPeriod.allTime);
    expect(all.plays, 45);
    expect(all.seconds, 9000);
    expect(all.tracks.first.track.id, 'a');
  });

  test('la foto di un artista seguito vince sulla copertina', () {
    final m = replay(ReplayPeriod.month, photos: {'Yeat': 'faccia'});
    expect(m.artists.firstWhere((a) => a.name == 'Yeat').artwork, 'faccia');
    expect(m.artists.firstWhere((a) => a.name == 'Nettspend').artwork, 'art-c');
  });

  test('dice da quando conta', () {
    expect(replay(ReplayPeriod.year).countingSince, DateTime(2025, 12, 31));
  });

  test('sempre: i totali gonfiati da un altro dispositivo non contano', () {
    // Hope, come arrivava dalla sincronizzazione: 29 ascolti e il tetto
    // pieno, 29 x (110 + 30) s, dal PC che contava anche le pause. Il
    // registro ne ha 19 per 981 s: saltati, pezzi, un paio interi.
    final hope = Track(
      id: 'h',
      title: 'Hope',
      author: 'XXXTENTACION',
      thumbnailUrl: 'art-h',
      duration: const Duration(seconds: 110),
    );
    final hopeLog = [
      for (var i = 0; i < 19; i++)
        ('h', DateTime(2026, 9, 20, 10, i), i < 9 ? 109 : 0),
    ];
    final r = buildReplay(
      period: ReplayPeriod.allTime,
      now: now,
      allTime: const {'h': TrackStats(playCount: 29, totalSeconds: 4060)},
      log: hopeLog,
      tracks: {'h': hope},
    );
    expect(r.tracks.single.plays, 29);
    // 981 s registrati + 10 ascolti vecchi alla media del registro.
    expect(r.tracks.single.seconds, 981 + (10 * 981 / 19).round());
    expect(r.seconds, lessThan(4060 ~/ 2));
  });

  test('sempre, senza registro: al massimo la durata per ascolto', () {
    final t = Track(
      id: 'x',
      title: 'X',
      author: 'Y',
      thumbnailUrl: '',
      duration: const Duration(seconds: 100),
    );
    final r = buildReplay(
      period: ReplayPeriod.allTime,
      now: now,
      allTime: const {'x': TrackStats(playCount: 10, totalSeconds: 1300)},
      log: const [],
      tracks: {'x': t},
    );
    expect(r.tracks.single.seconds, 1000);
  });

  test('il conto degli artisti e\' di tutti, non della classifica', () {
    final many = {for (var i = 0; i < 30; i++) 't$i': _t('t$i', 'Artista $i')};
    final r = buildReplay(
      period: ReplayPeriod.allTime,
      now: now,
      allTime: {
        for (var i = 0; i < 30; i++)
          't$i': TrackStats(playCount: 1, totalSeconds: 100 + i),
      },
      log: const [],
      tracks: many,
    );
    expect(r.artists.length, 12);
    expect(r.artistCount, 30);
    expect(r.songs, 30);
  });
}
