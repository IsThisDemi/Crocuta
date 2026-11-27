import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/services/youtube_service.dart';

void main() {
  // I risultati veri della ricerca "Songs" per "PinkPantheress Romeo".
  const romeo = <SongCandidate>[
    (id: 'yyJNQ5zcZuI', title: 'Romeo', artists: 'PinkPantheress'),
    (
      id: 'a9GKynNFdX4',
      title: 'Romeo + Rachel Chinouriri (feat. Rachel Chinouriri)',
      artists: 'PinkPantheress',
    ),
    (
      id: 'sKRu1gJTshs',
      title: 'Romeo + Ravyn Lenae (feat. Ravyn Lenae)',
      artists: 'PinkPantheress',
    ),
  ];

  test('il videoclip di Romeo trova la canzone, non un remix', () {
    expect(
      YouTubeService.pickSongVersion(
        'Romeo (Official Video)',
        'PinkPantheress',
        romeo,
      ),
      'yyJNQ5zcZuI',
    );
  });

  test("toglie cio' che descrive il video, e l'artista davanti", () {
    for (final t in [
      'Romeo (Official Video)',
      'Romeo [Official Music Video]',
      'Romeo (Lyric Video)',
      'Romeo (Visualizer)',
      'PinkPantheress - Romeo (Official 4K Video)',
      'Romeo',
    ]) {
      expect(
        YouTubeService.songTitleKey(t, artist: 'PinkPantheress'),
        'romeo',
        reason: t,
      );
    }
  });

  test('lascia stare le parentesi che fanno parte del titolo', () {
    expect(
      YouTubeService.songTitleKey('Pain (feat. Someone)'),
      isNot(YouTubeService.songTitleKey('Pain')),
    );
  });

  test("se manca l'identica, va bene la radio edit dello stesso artista", () {
    const mina = <SongCandidate>[
      (id: 'radio', title: 'Vento di passione (Radio edit)', artists: 'Mina'),
      (
        id: 'pino',
        title: 'Vento di passione',
        artists: 'Pino Daniele & Giorgia',
      ),
      (id: 'live', title: 'Vento Di Passione (Live)', artists: 'Lina Sastri'),
    ];
    expect(
      YouTubeService.pickSongVersion(
        'Mina - Vento di passione (Official Video)',
        'Mina',
        mina,
      ),
      'radio',
    );
    // Dove c'e' l'identica, vince lei.
    expect(
      YouTubeService.pickSongVersion(
        'Romeo (Official Video)',
        'PinkPantheress',
        [
          (id: 'edit', title: 'Romeo (Radio Edit)', artists: 'PinkPantheress'),
          ...romeo,
        ],
      ),
      'yyJNQ5zcZuI',
    );
    // Un live resta un'altra cosa.
    expect(
      YouTubeService.pickSongVersion(
        'Romeo (Official Video)',
        'PinkPantheress',
        [(id: 'live', title: 'Romeo (Live)', artists: 'PinkPantheress')],
      ),
      isNull,
    );
  });

  test('un artista diverso non vale, anche con lo stesso titolo', () {
    expect(
      YouTubeService.pickSongVersion(
        'Romeo (Official Video)',
        'Petey Pablo',
        romeo,
      ),
      isNull,
    );
  });

  test('nessuna canzone uguale: resta il video', () {
    expect(
      YouTubeService.pickSongVersion(
        'Romeo (Live at Glastonbury)',
        'PinkPantheress',
        romeo,
      ),
      isNull,
    );
  });

  group('con le risposte vere di YouTube', () {
    // Registrate da music.youtube.com: la coda "next" del videoclip di
    // Romeo e la ricerca "Songs" che ne segue.
    final next = File('test/fixtures/next_romeo_video.json').readAsStringSync();
    final songs = File(
      'test/fixtures/search_songs_romeo.json',
    ).readAsStringSync();

    Future<(String, List<String>)> resolve(String id) {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.path.split('/').last);
        return http.Response(
          req.url.path.endsWith('/next') ? next : songs,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      return http.runWithClient(() async {
        final saved = <String, String>{};
        final s = YouTubeService(
          onAudioIdResolved: (id, audio, _) async => saved[id] = audio,
        );
        final audio = await s.audioIdFor(id);
        expect(saved[id], audio, reason: 'la risposta certa si ricorda');
        return (audio, asked);
      }, () => client);
    }

    test('il videoclip suona la canzone', () async {
      final (audio, asked) = await resolve('X18av7mN7Rw');
      expect(audio, 'yyJNQ5zcZuI');
      expect(asked, ['next', 'search']);
    });

    test('il video si presenta come la canzone', () async {
      final seen = <Track>[];
      final client = MockClient(
        (req) async => http.Response(
          req.url.path.endsWith('/next') ? next : songs,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final s = YouTubeService(onTracksSeen: (t) async => seen.addAll(t));
      const video = Track(
        id: 'X18av7mN7Rw',
        title: 'Romeo (Official Video)',
        author: 'PinkPantheress',
        thumbnailUrl: 'https://i.ytimg.com/vi/X18av7mN7Rw/hq720.jpg',
        duration: Duration(minutes: 3, seconds: 10),
      );
      final song = await http.runWithClient(
        () => s.songVersionFor(video),
        () => client,
      );
      expect(song, isNotNull);
      expect(song!.id, video.id, reason: "l'identita' del brano resta");
      expect(song.title, 'Romeo');
      expect(song.albumName, 'Fancy That');
      expect(song.duration, const Duration(minutes: 2, seconds: 35));
      expect(song.thumbnailUrl, isNot(contains('i.ytimg.com/vi/')));
      // Le copie salvate vengono rivestite subito.
      expect(seen.map((t) => t.title), contains('Romeo'));
    });

    test("una volta saputo, non si chiede piu' niente", () async {
      final s = YouTubeService(initialAudioIds: {'X18av7mN7Rw': 'yyJNQ5zcZuI'});
      final client = MockClient((_) async => fail('nessuna richiesta'));
      final audio = await http.runWithClient(
        () => s.audioIdFor('X18av7mN7Rw'),
        () => client,
      );
      expect(audio, 'yyJNQ5zcZuI');
    });

    test('se la rete non risponde, suona quello che c e', () async {
      final saved = <String, String>{};
      final client = MockClient((_) async => http.Response('', 500));
      final s = YouTubeService(
        onAudioIdResolved: (id, audio, _) async => saved[id] = audio,
      );
      final audio = await http.runWithClient(
        () => s.audioIdFor('X18av7mN7Rw'),
        () => client,
      );
      expect(audio, 'X18av7mN7Rw');
      expect(saved, isEmpty, reason: 'un errore non si ricorda');
    });
  });
}
