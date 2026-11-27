import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/spotify_import_screen.dart';
import 'package:crocuta/services/apple_music_import_controller.dart';
import 'package:crocuta/services/apple_music_library.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/services/spotify_import.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

/// Una libreria esportata da Musica (File › Libreria › Esporta libreria…),
/// ridotta: due brani, un podcast, la libreria intera, una lista di
/// sistema, una cartella e una playlist vera.
const _libraryXml = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Major Version</key><integer>1</integer>
	<key>Tracks</key>
	<dict>
		<key>101</key>
		<dict>
			<key>Track ID</key><integer>101</integer>
			<key>Name</key><string>Hope</string>
			<key>Artist</key><string>XXXTENTACION</string>
			<key>Album</key><string>?</string>
			<key>Total Time</key><integer>110000</integer>
			<key>Date Added</key><date>2023-05-01T10:00:00Z</date>
			<key>Persistent ID</key><string>AAAA000000000001</string>
			<key>Track Type</key><string>Remote</string>
		</dict>
		<key>102</key>
		<dict>
			<key>Track ID</key><integer>102</integer>
			<key>Name</key><string>Ninja Gaiden</string>
			<key>Artist</key><string>Deko &amp; itsoktocry</string>
			<key>Total Time</key><integer>150000</integer>
			<key>Date Added</key><date>2024-02-10T10:00:00Z</date>
			<key>Persistent ID</key><string>AAAA000000000002</string>
		</dict>
		<key>103</key>
		<dict>
			<key>Track ID</key><integer>103</integer>
			<key>Name</key><string>Some Podcast Episode</string>
			<key>Podcast</key><true/>
			<key>Persistent ID</key><string>AAAA000000000003</string>
		</dict>
	</dict>
	<key>Playlists</key>
	<array>
		<dict>
			<key>Name</key><string>Library</string>
			<key>Master</key><true/>
			<key>Playlist Persistent ID</key><string>BBBB000000000001</string>
			<key>Playlist Items</key>
			<array>
				<dict><key>Track ID</key><integer>101</integer></dict>
				<dict><key>Track ID</key><integer>102</integer></dict>
			</array>
		</dict>
		<dict>
			<key>Name</key><string>Music</string>
			<key>Distinguished Kind</key><integer>4</integer>
			<key>Playlist Persistent ID</key><string>BBBB000000000002</string>
			<key>Playlist Items</key>
			<array><dict><key>Track ID</key><integer>101</integer></dict></array>
		</dict>
		<dict>
			<key>Name</key><string>Folder</string>
			<key>Folder</key><true/>
			<key>Playlist Persistent ID</key><string>BBBB000000000003</string>
		</dict>
		<dict>
			<key>Name</key><string>Gym</string>
			<key>Playlist Persistent ID</key><string>BBBB000000000004</string>
			<key>Smart Info</key><data>AQEAAwAAAAI=</data>
			<key>Playlist Items</key>
			<array>
				<dict><key>Track ID</key><integer>102</integer></dict>
				<dict><key>Track ID</key><integer>103</integer></dict>
				<dict><key>Track ID</key><integer>101</integer></dict>
			</array>
		</dict>
	</array>
</dict>
</plist>
''';

/// Un'esportazione di una sola playlist: niente libreria intera.
const _playlistXml = '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>Tracks</key>
	<dict>
		<key>7</key>
		<dict>
			<key>Name</key><string>Hope</string>
			<key>Artist</key><string>XXXTENTACION</string>
			<key>Persistent ID</key><string>AAAA000000000001</string>
		</dict>
	</dict>
	<key>Playlists</key>
	<array>
		<dict>
			<key>Name</key><string>Late Night</string>
			<key>Playlist Persistent ID</key><string>CCCC000000000001</string>
			<key>Playlist Items</key>
			<array><dict><key>Track ID</key><integer>7</integer></dict></array>
		</dict>
	</array>
</dict>
</plist>
''';

/// Il controller con l'import salvato in memoria, senza lo storage.
class _Mem extends AppleMusicImportController {
  String? job;

  @override
  String? get savedJob => job;

  @override
  Future<void> saveJob(String? json) async => job = json;
}

/// La pagina con una vista fissa.
class _Fixed extends AppleMusicImportController {
  final SpotifyImportView view;

  _Fixed(this.view);

  @override
  SpotifyImportView build() => view;
}

void main() {
  group('il file esportato da Musica', () {
    test('brani dal piu\' recente, solo le playlist fatte da qualcuno', () {
      final lib = parseAppleMusicFile(_libraryXml, name: 'Library.xml');
      expect(lib.songs.map((t) => t.name), ['Ninja Gaiden', 'Hope']);
      final hope = lib.songs[1];
      expect(hope.key, 'am:AAAA000000000001');
      expect(hope.artists, ['XXXTENTACION']);
      expect(hope.durationMs, 110000);
      expect(lib.songs.first.artists, ['Deko & itsoktocry']);
      expect(lib.playlists.map((p) => p.name), ['Gym']);
      // Nell'ordine della playlist, senza il podcast.
      expect(lib.playlists.single.tracks.map((t) => t.name), [
        'Ninja Gaiden',
        'Hope',
      ]);
      expect(lib.playlists.single.id, 'am:BBBB000000000004');
    });

    test('una playlist sola diventa una playlist, non i preferiti', () {
      final lib = parseAppleMusicFile(_playlistXml);
      expect(lib.songs, isEmpty);
      expect(lib.playlists.single.name, 'Late Night');
      expect(lib.playlists.single.tracks.single.name, 'Hope');
    });

    test("l'elenco JSON del lettore web del vecchio strumento", () {
      final lib = parseAppleMusicFile(
        '[{"id":"i.1","name":"Hope","artist":"XXXTENTACION","ms":110000},'
        '{"id":"i.2","name":"Rare Demo","artist":"Nobody"}]',
      );
      expect(lib.songs.map((t) => t.name), ['Hope', 'Rare Demo']);
      expect(lib.songs.first.key, 'am:i.1');
      expect(lib.playlists, isEmpty);
    });

    test('un file che non e\' una libreria lo dice', () {
      expect(
        () => parseAppleMusicFile('hello'),
        throwsA(isA<AppleMusicFormatException>()),
      );
      expect(
        () => parseAppleMusicFile('<plist><dict></dict></plist>'),
        throwsA(isA<AppleMusicFormatException>()),
      );
    });
  });

  test("la libreria letta dall'app Musica, coi suoi id", () {
    final lib = appleMusicFromNative({
      'songs': [
        {
          'id': 'AAAA000000000001',
          'title': 'Hope',
          'artist': 'XXXTENTACION',
          'ms': 110000,
          'added': 1000,
        },
        {
          'id': 'AAAA000000000002',
          'title': 'Ninja Gaiden',
          'artist': 'Deko',
          'added': 5000,
        },
      ],
      'playlists': [
        {
          'id': 'BBBB000000000004',
          'name': 'Gym',
          'items': ['AAAA000000000002', 'MISSING', 'AAAA000000000001'],
        },
        {'id': 'E', 'name': 'Empty', 'items': <String>[]},
      ],
    });
    expect(lib.songs.map((t) => t.name), ['Ninja Gaiden', 'Hope']);
    // Gli stessi id dell'XML: un import si riprende da qui anche se era
    // partito da un file.
    expect(lib.songs.last.key, 'am:AAAA000000000001');
    expect(lib.playlists.single.id, 'am:BBBB000000000004');
    expect(lib.playlists.single.tracks.length, 2);
  });

  test(
    'il controller legge un file e da\' i brani alle raccolte scelte',
    () async {
      final container = ProviderContainer(
        overrides: [appleMusicImportProvider.overrideWith(_Mem.new)],
      );
      addTearDown(container.dispose);
      final ctrl = container.read(appleMusicImportProvider.notifier);
      await ctrl.loadFile('Library.xml', () async => _libraryXml);
      final view = container.read(appleMusicImportProvider);
      expect(view.error, isNull);
      expect(view.connected, isTrue);
      expect(view.library!.liked.count, 2);
      expect(view.library!.playlists.single.name, 'Gym');
      // Di serie tutto.
      expect(view.selected, {for (final s in view.library!.all) s.key});
      final songs = await ctrl.readTracks(view.library!.liked);
      expect(songs.map((t) => t.name), ['Ninja Gaiden', 'Hope']);
      final gym = await ctrl.readTracks(view.library!.playlists.single);
      expect(gym.length, 2);

      await ctrl.loadFile('notes.txt', () async => 'hello');
      expect(container.read(appleMusicImportProvider).error, contains('File'));
    },
  );

  testWidgets('cattura: import da Apple Music, da dove leggere', (
    tester,
  ) async {
    await capture(
      tester,
      const AppleMusicImportScreen(),
      name: 'apple_music_setup',
      size: const Size(430, 1300),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        appleMusicImportProvider.overrideWith(
          () => _Fixed(const SpotifyImportView()),
        ),
      ],
    );
    expect(find.text('Import from Apple Music'), findsWidgets);
    expect(find.text('Open a Library File…'), findsOneWidget);
  });

  testWidgets('cattura: import da Apple Music, scelta', (tester) async {
    final library = libraryViewOf(
      parseAppleMusicFile(_libraryXml, name: 'Library.xml'),
    );
    await capture(
      tester,
      const AppleMusicImportScreen(),
      name: 'apple_music_choose',
      size: const Size(430, 1100),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        appleMusicImportProvider.overrideWith(
          () => _Fixed(
            SpotifyImportView(
              connected: true,
              library: library,
              selected: {for (final s in library.all) s.key},
            ),
          ),
        ),
      ],
    );
    expect(find.text('Library Songs'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Import 2 Items'), findsOneWidget);
    expect(find.textContaining('Read from Library.xml.'), findsOneWidget);
  });

  test('nessuna raccolta di Spotify per Apple Music', () {
    final view = libraryViewOf(parseAppleMusicFile(_libraryXml));
    expect(view.albums, isEmpty);
    expect(view.artists, isEmpty);
    expect(view.liked.kind, SpotifySourceKind.liked);
  });
}
