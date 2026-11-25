import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:yeen_music/models/artist.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/services/spotify_api.dart';
import 'package:yeen_music/services/spotify_auth.dart';
import 'package:yeen_music/services/spotify_import.dart';

// Niente rete vera: Spotify e' un MockClient, YouTube Music un catalogo
// finto.

Track _y(String id, String title, String author, [int? secs]) => Track(
  id: id,
  title: title,
  author: author,
  thumbnailUrl: '',
  duration: secs == null ? null : Duration(seconds: secs),
);

SpotifyTrack _s(
  String id,
  String name,
  List<String> artists, {
  int? ms,
  String? added,
}) => SpotifyTrack(
  id: id,
  name: name,
  artists: artists,
  durationMs: ms,
  addedAt: added == null ? null : DateTime.parse(added),
);

http.Response _json(Object body, [int status = 200, Map<String, String>? h]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?h},
    );

void main() {
  group('PKCE', () {
    test('il vettore di prova di RFC 7636 (appendice B)', () {
      expect(
        pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('il verifier: 64 caratteri non riservati, ogni volta diverso', () {
      final a = pkceVerifier();
      expect(a.length, 64);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(a), isTrue);
      expect(pkceVerifier(), isNot(a));
    });

    test("l'indirizzo di consenso ha tutto quello che Spotify chiede", () {
      final url = spotifyAuthorizeUrl(
        clientId: 'abc',
        challenge: 'ch',
        state: 'st',
      );
      expect(url.host, 'accounts.spotify.com');
      expect(url.path, '/authorize');
      expect(url.queryParameters, {
        'client_id': 'abc',
        'response_type': 'code',
        'redirect_uri': 'http://127.0.0.1:8888/callback',
        'code_challenge_method': 'S256',
        'code_challenge': 'ch',
        'state': 'st',
        'scope':
            'user-library-read playlist-read-private '
            'playlist-read-collaborative user-follow-read',
      });
    });
  });

  group('ritorno da Spotify', () {
    test('le altre pagine non sono il ritorno', () {
      expect(
        parseSpotifyRedirect(
          'https://accounts.spotify.com/login',
          expectedState: 's',
        ),
        isNull,
      );
      // Stesso host, porta diversa.
      expect(
        parseSpotifyRedirect(
          'http://127.0.0.1:9999/callback?code=x&state=s',
          expectedState: 's',
        ),
        isNull,
      );
    });

    test('il codice, e gli errori', () {
      final ok = parseSpotifyRedirect(
        'http://127.0.0.1:8888/callback?code=AQB&state=s',
        expectedState: 's',
      )!;
      expect(ok.code, 'AQB');
      expect(ok.error, isNull);

      final wrongState = parseSpotifyRedirect(
        'http://127.0.0.1:8888/callback?code=AQB&state=other',
        expectedState: 's',
      )!;
      expect(wrongState.code, isNull);
      expect(wrongState.error, isNotNull);

      final denied = parseSpotifyRedirect(
        'http://127.0.0.1:8888/callback?error=access_denied&state=s',
        expectedState: 's',
      )!;
      expect(denied.error, contains('not allowed'));
    });
  });

  group('token', () {
    final now = DateTime(2026, 11, 18, 12);

    test('lo scambio del codice manda verifier e Client ID, niente segreto', () async {
      late Map<String, String> sent;
      final auth = SpotifyAuth(
        clientId: 'cid',
        now: () => now,
        client: MockClient((req) async {
          expect(req.url.toString(), 'https://accounts.spotify.com/api/token');
          expect(req.headers['authorization'], isNull);
          sent = Uri.splitQueryString(req.body);
          return _json({
            'access_token': 'A1',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'refresh_token': 'R1',
            'scope': 'user-library-read',
          });
        }),
      );
      final t = await auth.exchangeCode('CODE', 'VERIFIER');
      expect(sent, {
        'grant_type': 'authorization_code',
        'code': 'CODE',
        'redirect_uri': 'http://127.0.0.1:8888/callback',
        'client_id': 'cid',
        'code_verifier': 'VERIFIER',
      });
      expect(t.accessToken, 'A1');
      expect(t.refreshToken, 'R1');
      expect(t.expiresAt, now.add(const Duration(hours: 1)));
      // E si rilegge uguale da quello che si salva.
      final back = SpotifyTokens.fromJson(t.toJson());
      expect(back.refreshToken, 'R1');
      expect(back.expiresAt, t.expiresAt);
    });

    test('rinnovando senza refresh token nuovo resta il vecchio', () async {
      final auth = SpotifyAuth(
        clientId: 'cid',
        now: () => now,
        client: MockClient((req) async {
          expect(Uri.splitQueryString(req.body), {
            'grant_type': 'refresh_token',
            'refresh_token': 'R1',
            'client_id': 'cid',
          });
          return _json({'access_token': 'A2', 'expires_in': 3600});
        }),
      );
      final t = await auth.refresh(
        SpotifyTokens(accessToken: 'A1', refreshToken: 'R1', expiresAt: now),
      );
      expect(t.accessToken, 'A2');
      expect(t.refreshToken, 'R1');
    });

    test('un refresh token revocato chiede di ricollegarsi', () async {
      final auth = SpotifyAuth(
        clientId: 'cid',
        client: MockClient(
          (_) async => _json({'error': 'invalid_grant'}, 400),
        ),
      );
      await expectLater(
        auth.refresh(
          SpotifyTokens(accessToken: 'A', refreshToken: 'R', expiresAt: now),
        ),
        throwsA(
          isA<SpotifyAuthException>().having((e) => e.needsLogin, 'login', true),
        ),
      );
    });

    test('scaduto: un rinnovo solo anche per due richieste insieme', () async {
      var refreshes = 0;
      final saved = <String>[];
      final session = SpotifySession(
        auth: SpotifyAuth(
          clientId: 'cid',
          now: () => now,
          client: MockClient((_) async {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return _json({'access_token': 'A2', 'expires_in': 3600});
          }),
        ),
        tokens: SpotifyTokens(
          accessToken: 'A1',
          refreshToken: 'R1',
          // Fra trenta secondi: dentro il margine di un minuto.
          expiresAt: now.add(const Duration(seconds: 30)),
        ),
        onTokens: (t) async => saved.add(t.accessToken),
      );
      final both = await Future.wait([
        session.accessToken(),
        session.accessToken(),
      ]);
      expect(both, ['A2', 'A2']);
      expect(refreshes, 1);
      expect(saved, ['A2']);
      // Ora e' valido: niente rinnovo.
      expect(await session.accessToken(), 'A2');
      expect(refreshes, 1);
    });
  });

  group('API', () {
    SpotifyApi api(
      Future<http.Response> Function(http.Request) handler, {
      List<Duration>? slept,
      List<bool>? forced,
    }) => SpotifyApi(
      client: MockClient(handler),
      accessToken: ({bool force = false}) async {
        forced?.add(force);
        return force ? 'fresh' : 'tok';
      },
      sleep: (d) async => slept?.add(d),
    );

    test('i piaciuti, pagina dopo pagina seguendo next', () async {
      final seen = <String>[];
      final songs = await api((req) async {
        seen.add(req.url.toString());
        expect(req.headers['authorization'], 'Bearer tok');
        if (req.url.queryParameters['offset'] == null) {
          return _json({
            'total': 3,
            'next': 'https://api.spotify.com/v1/me/tracks?offset=2&limit=2',
            'items': [
              {
                'added_at': '2026-10-01T10:00:00Z',
                'track': {
                  'type': 'track',
                  'id': 't1',
                  'name': 'Hope',
                  'duration_ms': 110000,
                  'artists': [
                    {'name': 'XXXTENTACION'},
                  ],
                  'album': {'name': '?'},
                },
              },
              // Un brano tolto dal catalogo: niente oggetto.
              {'added_at': '2026-09-01T10:00:00Z', 'track': null},
            ],
          });
        }
        return _json({
          'total': 3,
          'next': null,
          'items': [
            {
              'added_at': '2026-08-01T10:00:00Z',
              'track': {
                'type': 'track',
                'id': 't3',
                'name': 'Passion',
                'artists': [
                  {'name': 'PinkPantheress'},
                ],
              },
            },
          ],
        });
      }).likedSongs();
      expect(seen.first, 'https://api.spotify.com/v1/me/tracks?limit=50');
      expect(songs.map((s) => s.id), ['t1', 't3']);
      expect(songs.first.duration, const Duration(seconds: 110));
      expect(songs.first.artist, 'XXXTENTACION');
      expect(songs.first.addedAt, DateTime.utc(2026, 10, 1, 10));
    });

    test('playlist: /items, il campo nuovo item e quello vecchio track', () async {
      final songs = await api((req) async {
        expect(req.url.path, '/v1/playlists/p1/items');
        return _json({
          'next': null,
          'items': [
            {
              'item': {
                'type': 'track',
                'id': 'a',
                'name': 'Uno',
                'artists': [
                  {'name': 'X'},
                ],
              },
            },
            {
              'track': {
                'type': 'track',
                'id': 'b',
                'name': 'Due',
                'artists': [
                  {'name': 'Y'},
                ],
              },
            },
            // Un episodio di podcast: non e' un brano.
            {
              'item': {'type': 'episode', 'id': 'e', 'name': 'Puntata'},
            },
            // Un file locale: senza id, lo riconosce il nome.
            {
              'is_local': true,
              'item': {
                'type': 'track',
                'id': null,
                'is_local': true,
                'name': 'Demo',
                'artists': [
                  {'name': 'Me'},
                ],
              },
            },
          ],
        });
      }).playlistTracks('p1');
      expect(songs.map((s) => s.name), ['Uno', 'Due', 'Demo']);
      expect(songs.last.id, isNull);
      expect(songs.last.key, 'local:demo|me');
    });

    test('429: aspetta Retry-After e riprova', () async {
      var calls = 0;
      final slept = <Duration>[];
      final n = await api((req) async {
        if (calls++ == 0) return _json({}, 429, {'retry-after': '3'});
        return _json({'total': 42, 'items': []});
      }, slept: slept).likedCount();
      expect(n, 42);
      expect(slept, [const Duration(seconds: 4)]);
    });

    test('401: un token nuovo, una volta', () async {
      var calls = 0;
      final forced = <bool>[];
      final me = await api((req) async {
        calls++;
        if (req.headers['authorization'] == 'Bearer tok') {
          return _json({}, 401);
        }
        return _json({'id': 'u1', 'display_name': 'Alex'});
      }, forced: forced).me();
      expect(me.name, 'Alex');
      expect(calls, 2);
      expect(forced, [false, true]);
    });

    test('403 arriva come forbidden', () async {
      await expectLater(
        api((_) async => _json({
          'error': {'status': 403, 'message': 'Forbidden'},
        }, 403)).playlistTracks('x'),
        throwsA(isA<SpotifyApiException>().having((e) => e.forbidden, 'f', true)),
      );
    });

    test('playlist della libreria: items.total, o tracks.total delle vecchie', () async {
      final list = await api((_) async => _json({
        'next': null,
        'items': [
          {
            'id': 'p1',
            'name': 'Gym',
            'owner': {'id': 'me', 'display_name': 'Alex'},
            'items': {'total': 12},
            'images': [
              {'url': 'big', 'width': 640},
              {'url': 'mid', 'width': 300},
              {'url': 'small', 'width': 60},
            ],
          },
          {
            'id': 'p2',
            'name': 'Today’s Top Hits',
            'owner': {'id': 'spotify', 'display_name': 'Spotify'},
            'tracks': {'total': 50},
            'images': [],
          },
        ],
      })).playlists();
      expect(list.map((p) => p.total), [12, 50]);
      expect(list.first.imageUrl, 'mid');
      expect(list.first.readableBy('me'), isTrue);
      expect(list.last.readableBy('me'), isFalse);
      final s = SpotifySource.playlist(list.last, 'me');
      expect(s.restricted, isTrue);
    });

    test('artisti seguiti: a cursore, dentro artists', () async {
      final artists = await api((req) async {
        if (req.url.queryParameters['after'] == null) {
          expect(req.url.queryParameters['type'], 'artist');
          return _json({
            'artists': {
              'items': [
                {'id': 'a1', 'name': 'Yeat'},
              ],
              'next':
                  'https://api.spotify.com/v1/me/following?type=artist&after=a1&limit=50',
              'cursors': {'after': 'a1'},
            },
          });
        }
        return _json({
          'artists': {
            'items': [
              {'id': 'a2', 'name': 'MARINA'},
            ],
            'next': null,
          },
        });
      }).followedArtists();
      expect(artists.map((a) => a.name), ['Yeat', 'MARINA']);
    });

    test('un next fuori da api.spotify.com non si segue (il token resta li)', () async {
      var calls = 0;
      final albums = await api((_) async {
        calls++;
        return _json({
          'next': 'https://evil.example.com/steal',
          'items': [
            {
              'added_at': '2026-01-01T00:00:00Z',
              'album': {
                'id': 'al1',
                'name': 'Currents',
                'artists': [
                  {'name': 'Tame Impala'},
                ],
                'total_tracks': 13,
              },
            },
          ],
        });
      }).savedAlbums();
      expect(calls, 1);
      expect(albums.single.name, 'Currents');
      expect(albums.single.totalTracks, 13);
    });
  });

  group('da Spotify a YouTube Music', () {
    test('il titolo senza le aggiunte da catalogo', () {
      expect(spotifyPlainTitle('Heroes - 2017 Remaster'), 'Heroes');
      expect(spotifyPlainTitle('Let It Be - Remastered 2009'), 'Let It Be');
      expect(spotifyPlainTitle('Romeo - Radio Edit'), 'Romeo');
      expect(spotifyPlainTitle('Song (Remastered)'), 'Song');
      // Live e remix sono un'altra cosa da sentire.
      expect(spotifyPlainTitle('Song - Live at Wembley'), 'Song - Live at Wembley');
      expect(spotifyPlainTitle('Song - Remix'), 'Song - Remix');
    });

    test('le ricerche: primo interprete, poi tutti', () {
      expect(
        spotifySongQueries(
          _s('1', 'After the Storm (feat. Tyler, The Creator)', [
            'Kali Uchis',
            'Tyler, The Creator',
          ]),
        ),
        ['Kali Uchis After the Storm', 'Kali Uchis Tyler, The Creator After the Storm'],
      );
      expect(spotifySongQueries(_s('2', 'Hope', ['XXXTENTACION'])), [
        'XXXTENTACION Hope',
      ]);
    });

    test('il brano giusto: titolo, interprete, durata', () {
      final t = _s('1', 'Heroes - 2017 Remaster', ['David Bowie'], ms: 371000);
      expect(
        pickSpotifyMatch(t, [
          _y('live', 'Heroes (Live)', 'David Bowie', 400),
          _y('short', 'Heroes', 'David Bowie', 211), // la versione singolo
          _y('ok', 'Heroes', 'David Bowie', 370),
        ]),
        'ok',
      );
      expect(
        pickSpotifyMatch(t, [_y('other', 'Heroes', 'Someone Else', 371)]),
        isNull,
      );
    });

    test('il disco: stesso titolo, anche con edizione diversa', () {
      final album = SpotifySource(
        kind: SpotifySourceKind.album,
        id: 'al',
        name: 'Currents (Deluxe Edition)',
        subtitle: 'Tame Impala',
      );
      expect(
        pickAlbumMatch(album, const [
          AlbumCard(
            browseId: 'MPREwrong',
            title: 'Currents',
            subtitle: 'Album • Someone • 2015',
            thumbnailUrl: '',
          ),
          AlbumCard(
            browseId: 'MPREok',
            title: 'Currents',
            subtitle: 'Album • Tame Impala • 2015',
            thumbnailUrl: '',
          ),
        ]),
        'MPREok',
      );
    });

    test("l'artista: lo stesso nome, non uno che gli somiglia", () {
      const cards = [
        AlbumCard(
          browseId: 'UC1',
          title: 'Marina and the Diamonds',
          subtitle: 'Artist',
          thumbnailUrl: '',
        ),
        AlbumCard(
          browseId: 'UC2',
          title: 'MARINA',
          subtitle: 'Artist',
          thumbnailUrl: '',
        ),
      ];
      expect(pickArtistMatch('Marina', cards), 'UC2');
      expect(pickArtistMatch('Grimes', cards), isNull);
    });

    test('un brano ritrovato torna al suo posto nella playlist', () {
      final a = _y('a', 'A', 'X');
      final b = _y('b', 'B', 'X');
      final c = _y('c', 'C', 'X');
      final d = _y('d', 'D', 'X');
      final mine = _y('m', 'Mio', 'X');
      // Su Spotify: a b c d. In Crocuta c'erano a d, piu' uno aggiunto a
      // mano in fondo; ora si sono trovati b e c.
      expect(
        mergeIntoPlaylist([a, d, mine], [a, b, c, d], {'b', 'c'}).map((t) => t.id),
        ['a', 'b', 'c', 'd', 'm'],
      );
      // Il primo della playlist va in testa.
      expect(
        mergeIntoPlaylist([b], [a, b], {'a'}).map((t) => t.id),
        ['a', 'b'],
      );
    });
  });

  group('import', () {
    late _FakeCatalog catalog;
    late _FakeSink sink;
    late Map<String, List<SpotifyTrack>> spotify;
    late List<String> saved;

    final liked = SpotifySource.liked(3);
    const gym = SpotifySource(
      kind: SpotifySourceKind.playlist,
      id: 'gym',
      name: 'Gym',
      count: 3,
    );
    const theirs = SpotifySource(
      kind: SpotifySourceKind.playlist,
      id: 'top',
      name: 'Top Hits',
      restricted: true,
    );
    final album = SpotifySource(
      kind: SpotifySourceKind.album,
      id: 'cur',
      name: 'Currents',
      subtitle: 'Tame Impala',
      addedAt: DateTime.utc(2026, 9, 15),
    );
    const artist = SpotifySource(
      kind: SpotifySourceKind.artist,
      id: 'yeat',
      name: 'Yeat',
    );

    setUp(() {
      catalog = _FakeCatalog();
      sink = _FakeSink();
      saved = [];
      spotify = {
        liked.key: [
          _s('t1', 'Hope', ['XXXTENTACION'], added: '2026-10-01T00:00:00Z'),
          _s('t2', 'Nope', ['Nobody'], added: '2026-09-01T00:00:00Z'),
          _s('t3', 'Passion', ['PinkPantheress'], added: '2026-08-01T00:00:00Z'),
        ],
        gym.key: [
          _s('t3', 'Passion', ['PinkPantheress']),
          _s('t4', 'ON NOTHING', ['Yeat']),
          _s('t2', 'Nope', ['Nobody']),
        ],
      };
      catalog.songs = {
        't1': _y('y1', 'Hope', 'XXXTENTACION'),
        't3': _y('y3', 'Passion', 'PinkPantheress'),
        't4': _y('y4', 'ON NOTHING', 'Yeat'),
      };
      catalog.albums = {
        album.key: (
          browseId: 'MPREcur',
          title: 'Currents',
          tracks: [_y('c1', 'Let It Happen', 'Tame Impala')],
        ),
      };
      catalog.artists = {
        artist.key: (
          browseId: 'UCyeat',
          name: 'Yeat',
          thumbnailUrl: null,
          releases: ['MPRE1'],
        ),
      };
    });

    SpotifyImporter importer({List<Duration>? slept}) => SpotifyImporter(
      catalog: catalog,
      sink: sink,
      readTracks: (s) async {
        if (s.restricted) {
          throw const SpotifyApiException(403, 'Forbidden');
        }
        return spotify[s.key]!;
      },
      save: (state) async => saved.add(state.encode()),
      sleep: (d) async => slept?.add(d),
      concurrency: 2,
      pause: Duration.zero,
    );

    SpotifyImportState fresh() => SpotifyImportState(
      sources: [liked, gym, theirs, album, artist],
      startedAt: 1,
    );

    test('tutto: piaciuti, playlist, disco, artista, con i non trovati', () async {
      final state = fresh();
      final phases = <SpotifyImportPhase>{};
      await importer().run(state, onProgress: (p) => phases.add(p.phase));

      expect(phases, containsAll(SpotifyImportPhase.values));
      expect(state.finished, isTrue);
      // Ogni brano cercato una volta sola, anche se sta in due raccolte.
      expect(catalog.songCalls..sort(), ['t1', 't2', 't3', 't4']);

      // Piaciuti e disco insieme, per data di Spotify: il disco salvato
      // a meta' settembre sta fra Hope (ottobre) e Passion (agosto).
      expect(sink.liked.single.map((t) => t.id), ['y1', 'c1', 'y3']);
      expect(sink.playlists, {
        'Gym': ['y3', 'y4'],
      });
      expect(sink.followed.single.browseId, 'UCyeat');

      expect(state.unreadable.keys, [theirs.key]);
      expect(state.missing.single.track.id, 't2');
      expect(state.missing.single.sources, ['Liked Songs', 'Gym']);
      expect(saved, isNotEmpty);
    });

    test('si riprende da dove si era fermato, senza rifare le ricerche', () async {
      final first = fresh();
      // Fermato dopo due brani.
      await importer().run(
        first,
        onProgress: (_) {},
        cancelled: () => catalog.songCalls.length >= 2,
      );
      expect(first.finished, isFalse);
      expect(sink.liked, isEmpty);

      // Riaperta l'app: lo stato torna dal salvataggio.
      final resumed = SpotifyImportState.decode(saved.last)!;
      final before = catalog.songCalls.length;
      await importer().run(resumed, onProgress: (_) {});
      final searchedAgain = catalog.songCalls.skip(before).toSet();
      expect(searchedAgain.intersection(first.songs.keys.toSet()), isEmpty);
      expect(resumed.finished, isTrue);
      expect(sink.playlists.length, 1);

      // Un altro giro a import finito non crea niente di nuovo.
      await importer().run(resumed, onProgress: (_) {});
      expect(sink.liked.length, 1);
      expect(sink.created, 1);
      expect(sink.followed.length, 1);
    });

    test('429: aspetta e riprova; se non smette, si ferma e salva', () async {
      final slept = <Duration>[];
      catalog.limitedFor = 2;
      final state = fresh();
      await importer(slept: slept).run(state, onProgress: (_) {});
      expect(state.finished, isTrue);
      // Ognuno dei due lavoratori ha preso un 429 e ha aspettato.
      expect(slept.where((d) => d > Duration.zero), [
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ]);

      catalog.limitedFor = 1000;
      final other = SpotifyImportState(sources: [liked], startedAt: 1);
      await expectLater(
        importer().run(other, onProgress: (_) {}),
        throwsA(isA<SpotifyRateLimited>()),
      );
      // Letti i brani, nessuno segnato come "non trovato" per colpa del 429.
      expect(other.tracks[liked.key], hasLength(3));
      expect(other.songs, isEmpty);
      expect(SpotifyImportState.decode(saved.last)!.tracks, hasLength(1));
    });

    test('riprovare i non trovati li mette al loro posto', () async {
      final state = fresh();
      await importer().run(state, onProgress: (_) {});
      expect(state.missing, hasLength(1));

      catalog.songs['t2'] = _y('y2', 'Nope', 'Nobody');
      state.forgetMissing();
      await importer().run(state, onProgress: (_) {});
      expect(state.missing, isEmpty);
      expect(sink.liked.last.map((t) => t.id), ['y2']);
      // In fondo a Gym, dove sta su Spotify, nella stessa playlist.
      expect(sink.created, 1);
      expect(sink.playlists['Gym'], ['y3', 'y4', 'y2']);
    });

    test('un brano scelto a mano entra dove stava', () async {
      final state = fresh();
      await importer().run(state, onProgress: (_) {});
      state.songs['t2'] = _y('manual', 'Nope (Live)', 'Nobody');
      state.manual.add('t2');
      await importer().apply(state);
      expect(sink.liked.last.map((t) => t.id), ['manual']);
      expect(sink.playlists['Gym'], ['y3', 'y4', 'manual']);
      // "Riprova" non lo rimette in discussione.
      state.forgetMissing();
      expect(state.songs['t2']?.id, 'manual');
    });

    test('lo stato si salva e si rilegge uguale', () async {
      final state = fresh();
      await importer().run(state, onProgress: (_) {});
      final back = SpotifyImportState.decode(state.encode())!;
      expect(back.encode(), state.encode());
      expect(back.finished, isTrue);
      expect(back.sources.map((s) => s.key), state.sources.map((s) => s.key));
      expect(back.sources[3].addedAt!.isAtSameMomentAs(album.addedAt!), isTrue);
      expect(back.albums[album.key]!.tracks.single.id, 'c1');
      expect(SpotifyImportState.decode('not json'), isNull);
    });
  });
}

class _FakeCatalog implements SpotifyCatalog {
  Map<String, Track> songs = {};
  Map<String, AlbumMatch> albums = {};
  Map<String, ArtistMatch> artists = {};
  final songCalls = <String>[];

  /// Quante ricerche rispondono 429 prima di funzionare.
  int limitedFor = 0;

  @override
  Future<Track?> findSong(SpotifyTrack track) async {
    if (limitedFor > 0) {
      limitedFor--;
      throw Exception('YouTube Music answered with code 429');
    }
    songCalls.add(track.id!);
    return songs[track.id];
  }

  @override
  Future<AlbumMatch?> findAlbum(SpotifySource album) async =>
      albums[album.key];

  @override
  Future<ArtistMatch?> findArtist(SpotifySource artist) async =>
      artists[artist.key];
}

class _FakeSink implements SpotifyLibrarySink {
  final liked = <List<Track>>[];
  final playlists = <String, List<String>>{};
  final ids = <String, String>{};
  final followed = <ArtistMatch>[];
  int created = 0;

  @override
  Future<void> addLiked(List<Track> newestFirst) async =>
      liked.add(newestFirst);

  @override
  Future<String> createPlaylist(String name, List<Track> tracks) async {
    created++;
    playlists[name] = [for (final t in tracks) t.id];
    final id = 'pl_$created';
    ids[id] = name;
    return id;
  }

  @override
  Future<bool> addToPlaylist(
    String id,
    List<Track> ordered,
    Set<String> fresh,
  ) async {
    final name = ids[id]!;
    final current = [
      for (final i in playlists[name]!)
        ordered.firstWhere((t) => t.id == i, orElse: () => _y(i, i, '')),
    ];
    playlists[name] = [
      for (final t in mergeIntoPlaylist(current, ordered, fresh)) t.id,
    ];
    return true;
  }

  @override
  Future<void> follow(ArtistMatch artist) async => followed.add(artist);
}
