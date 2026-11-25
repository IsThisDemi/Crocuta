import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/spotify_import_screen.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/services/spotify_api.dart';
import 'package:yeen_music/services/spotify_import.dart';
import 'package:yeen_music/services/spotify_import_controller.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

/// Il controller con una vista fissa: la pagina si guarda senza Spotify.
class _Fixed extends SpotifyImportController {
  final SpotifyImportView view;

  _Fixed(this.view);

  @override
  SpotifyImportView build() => view;
}

Future<void> _shot(WidgetTester tester, String name, SpotifyImportView v) =>
    capture(
      tester,
      const SpotifyImportScreen(),
      name: name,
      size: const Size(430, 1600),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        spotifyImportProvider.overrideWith(() => _Fixed(v)),
      ],
    );

final _library = SpotifyLibrary(
  user: const SpotifyUser(id: 'me', name: 'Alex'),
  liked: SpotifySource.liked(812),
  playlists: [
    const SpotifySource(
      kind: SpotifySourceKind.playlist,
      id: 'p1',
      name: 'Gym',
      subtitle: 'Alex',
      count: 54,
    ),
    const SpotifySource(
      kind: SpotifySourceKind.playlist,
      id: 'p2',
      name: 'Today’s Top Hits',
      subtitle: 'Spotify',
      count: 50,
      restricted: true,
    ),
  ],
  albums: const [
    SpotifySource(
      kind: SpotifySourceKind.album,
      id: 'a1',
      name: 'Currents',
      subtitle: 'Tame Impala',
      count: 13,
    ),
  ],
  artists: const [
    SpotifySource(kind: SpotifySourceKind.artist, id: 'r1', name: 'Yeat'),
  ],
);

SpotifyImportState _job() {
  final liked = SpotifySource.liked(3);
  return SpotifyImportState(
    sources: [liked],
    startedAt: 1,
    tracks: {
      liked.key: const [
        SpotifyTrack(id: 't1', name: 'Hope', artists: ['XXXTENTACION']),
        SpotifyTrack(id: 't2', name: 'Rare Demo', artists: ['Nobody']),
      ],
    },
    songs: {
      't1': const Track(
        id: 'y1',
        title: 'Hope',
        author: 'XXXTENTACION',
        thumbnailUrl: '',
      ),
      't2': null,
    },
    applied: {
      liked.key: {'t1'},
    },
  );
}

void main() {
  testWidgets('cattura: import da Spotify, istruzioni', (tester) async {
    await _shot(tester, 'spotify_setup', const SpotifyImportView());
    expect(find.text('Connect to Spotify'), findsOneWidget);
    expect(find.text('http://127.0.0.1:8888/callback'), findsOneWidget);
  });

  testWidgets('cattura: import da Spotify, scelta', (tester) async {
    await _shot(
      tester,
      'spotify_choose',
      SpotifyImportView(
        clientId: '0123456789abcdef0123456789abcdef',
        connected: true,
        library: _library,
        selected: {
          for (final s in _library.all)
            if (!s.restricted) s.key,
        },
      ),
    );
    expect(find.text('Import 4 Items'), findsOneWidget);
    expect(find.text('Liked Songs'), findsOneWidget);
  });

  testWidgets('cattura: import da Spotify, avanzamento', (tester) async {
    await _shot(
      tester,
      'spotify_progress',
      SpotifyImportView(
        connected: true,
        running: true,
        job: _job(),
        progress: SpotifyImportProgress(
          phase: SpotifyImportPhase.matching,
          done: 120,
          total: 812,
          current: 'Hope — XXXTENTACION',
          waitingUntil: DateTime(2026, 11, 18, 14, 32),
        ),
      ),
    );
    expect(find.text('120 of 812 songs · 1 found'), findsOneWidget);
  });

  testWidgets('cattura: import da Spotify, riepilogo', (tester) async {
    await _shot(
      tester,
      'spotify_summary',
      SpotifyImportView(connected: true, job: _job()),
    );
    expect(find.text('Songs Not Found (1)'.toUpperCase()), findsOneWidget);
    expect(find.text('Rare Demo'), findsOneWidget);
  });
}
