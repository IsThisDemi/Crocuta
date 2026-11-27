import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import 'spotify_api.dart' show SpotifyTrack;

/// Una playlist della libreria Apple Music, coi suoi brani in ordine.
typedef AppleMusicPlaylist = ({
  String id,
  String name,
  List<SpotifyTrack> tracks,
});

/// La libreria Apple Music da importare: i brani, dal piu' recente, e le
/// playlist.
///
/// I brani sono [SpotifyTrack] perche' l'import e' quello di Spotify (vedi
/// spotify_import.dart): cambia solo da dove si legge. La chiave di ogni
/// brano e' il suo id persistente di Apple, cosi' lo stesso brano in tre
/// playlist si cerca una volta sola.
class AppleMusicLibrary {
  final List<SpotifyTrack> songs;
  final List<AppleMusicPlaylist> playlists;

  /// Da dove viene, detto all'utente: "the Music app", "Library.xml".
  final String origin;

  const AppleMusicLibrary({
    required this.songs,
    required this.playlists,
    required this.origin,
  });

  bool get isEmpty => songs.isEmpty && playlists.isEmpty;
}

/// Il file non e' una libreria che si sa leggere.
class AppleMusicFormatException implements Exception {
  final String message;

  const AppleMusicFormatException(this.message);

  @override
  String toString() => message;
}

/// Legge il file scelto: l'esportazione di Musica o di iTunes ("Esporta
/// libreria…" o "Esporta playlist…", in XML), o l'elenco JSON del lettore
/// web che usava il vecchio strumento a riga di comando.
AppleMusicLibrary parseAppleMusicFile(String text, {String name = 'file'}) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    return _fromWebJson(trimmed, name);
  }
  if (trimmed.startsWith('<')) return _fromPlist(trimmed, name);
  throw const AppleMusicFormatException(
    'This is not a Music library file. In Music choose File › Library › '
    'Export Library…, and open the .xml file it saves.',
  );
}

// ---------------------------------------------------------------------------
// L'XML di Musica e iTunes
// ---------------------------------------------------------------------------

AppleMusicLibrary _fromPlist(String text, String name) {
  final Object? root;
  try {
    final doc = XmlDocument.parse(text);
    final top = doc.rootElement.childElements.firstOrNull;
    root = top == null ? null : _plistValue(top);
  } on XmlException {
    throw const AppleMusicFormatException(
      'The file could not be read: it is not a complete XML file.',
    );
  }
  if (root is! Map<String, Object?> || root['Tracks'] is! Map) {
    throw const AppleMusicFormatException(
      'This XML file has no songs in it. In Music choose File › Library › '
      'Export Library…, and open the file it saves.',
    );
  }

  final byId = <String, SpotifyTrack>{};
  final added = <String, int>{};
  for (final entry in (root['Tracks'] as Map).entries) {
    final t = entry.value;
    if (t is! Map<String, Object?>) continue;
    if (!_isSong(t)) continue;
    final title = (t['Name'] as String?)?.trim() ?? '';
    if (title.isEmpty) continue;
    final id = (t['Persistent ID'] as String?) ?? '${entry.key}';
    final artist = (t['Artist'] as String?) ?? (t['Album Artist'] as String?);
    final track = SpotifyTrack(
      id: 'am:$id',
      name: title,
      artists: [if (artist != null && artist.trim().isNotEmpty) artist.trim()],
      album: t['Album'] as String?,
      durationMs: (t['Total Time'] as num?)?.toInt(),
      addedAt: t['Date Added'] as DateTime?,
    );
    byId['${entry.key}'] = track;
    added['${entry.key}'] = track.addedAt?.millisecondsSinceEpoch ?? 0;
  }

  final playlists = <AppleMusicPlaylist>[];
  for (final p in (root['Playlists'] as List?) ?? const []) {
    if (p is! Map<String, Object?>) continue;
    // La libreria intera, Musica, Film, Podcast, le cartelle, quelle
    // nascoste: non sono playlist fatte da qualcuno.
    if (p['Master'] == true ||
        p['Distinguished Kind'] != null ||
        p['Folder'] == true ||
        p['Visible'] == false) {
      continue;
    }
    final items = <SpotifyTrack>[];
    for (final i in (p['Playlist Items'] as List?) ?? const []) {
      final t = i is Map ? byId['${i['Track ID']}'] : null;
      if (t != null) items.add(t);
    }
    if (items.isEmpty) continue;
    playlists.add((
      id: 'am:${p['Playlist Persistent ID'] ?? p['Playlist ID']}',
      name: (p['Name'] as String?) ?? 'Playlist',
      tracks: items,
    ));
  }

  // Un'esportazione di una sola playlist ha anche i suoi brani in Tracks:
  // allora quelli non sono "la libreria", e fra i preferiti non vanno.
  final onlyPlaylist =
      playlists.length == 1 &&
      root['Playlists'] is List &&
      !(root['Playlists'] as List).any((p) => p is Map && p['Master'] == true);
  final songs = onlyPlaylist
      ? <SpotifyTrack>[]
      : (byId.entries.toList()
              ..sort((a, b) => added[b.key]!.compareTo(added[a.key]!)))
            .map((e) => e.value)
            .toList();
  return AppleMusicLibrary(songs: songs, playlists: playlists, origin: name);
}

/// Un brano di musica: non un podcast, un film, una puntata, un audiolibro,
/// un memo vocale.
bool _isSong(Map<String, Object?> t) {
  for (final k in const ['Podcast', 'Movie', 'TV Show', 'Audiobook']) {
    if (t[k] == true) return false;
  }
  final kind = ((t['Kind'] as String?) ?? '').toLowerCase();
  if (kind.contains('audiobook') || kind.contains('voice memo')) return false;
  return true;
}

/// Un valore di un plist XML: dict, array, stringhe, numeri, date, vero e
/// falso. I dati binari (le regole delle playlist intelligenti) non servono.
Object? _plistValue(XmlElement e) {
  switch (e.name.local) {
    case 'dict':
      final out = <String, Object?>{};
      String? key;
      for (final c in e.childElements) {
        if (c.name.local == 'key') {
          key = c.innerText;
        } else if (key != null) {
          out[key] = _plistValue(c);
          key = null;
        }
      }
      return out;
    case 'array':
      return [for (final c in e.childElements) _plistValue(c)];
    case 'string':
      return e.innerText;
    case 'integer':
      return int.tryParse(e.innerText.trim());
    case 'real':
      return double.tryParse(e.innerText.trim());
    case 'date':
      return DateTime.tryParse(e.innerText.trim());
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// L'elenco del lettore web (il vecchio tool/import_apple_music.dart)
// ---------------------------------------------------------------------------

AppleMusicLibrary _fromWebJson(String text, String name) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    throw const AppleMusicFormatException('The file is not valid JSON.');
  }
  final list = data is List
      ? data
      : data is Map && data['songs'] is List
      ? data['songs'] as List
      : null;
  if (list == null) {
    throw const AppleMusicFormatException(
      'This JSON file is not a list of songs.',
    );
  }
  final songs = <SpotifyTrack>[];
  for (final s in list) {
    if (s is! Map) continue;
    final title = (s['name'] ?? s['title']) as String?;
    final artist = s['artist'] as String?;
    if (title == null || title.trim().isEmpty) continue;
    final id = s['id']?.toString() ?? '$title|$artist';
    songs.add(
      SpotifyTrack(
        id: 'am:$id',
        name: title.trim(),
        artists: [
          if (artist != null && artist.trim().isNotEmpty) artist.trim(),
        ],
        album: s['album'] as String?,
        durationMs: (s['ms'] as num?)?.toInt(),
      ),
    );
  }
  if (songs.isEmpty) {
    throw const AppleMusicFormatException('There are no songs in this file.');
  }
  // Gia' dal piu' recente, come lo da' il lettore web.
  return AppleMusicLibrary(songs: songs, playlists: const [], origin: name);
}

// ---------------------------------------------------------------------------
// La libreria dell'app Musica, letta dal sistema (Mac e iPhone)
// ---------------------------------------------------------------------------

/// Legge la libreria dell'app Musica di questo Mac o iPhone: sul Mac con
/// iTunesLibrary, sull'iPhone con MediaPlayer (vedi AppleMusicReader.swift).
/// Il sistema chiede il permesso la prima volta.
class AppleMusicReader {
  static const _channel = MethodChannel('crocuta/apple_music');

  static bool get isSupported => Platform.isMacOS || Platform.isIOS;

  /// Lancia [AppleMusicFormatException] col motivo, detto all'utente.
  static Future<AppleMusicLibrary> read() async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>('readLibrary');
    } on PlatformException catch (e) {
      throw AppleMusicFormatException(switch (e.code) {
        'denied' =>
          'Crocuta is not allowed to read your music library. Allow it in '
              'Settings › Privacy & Security › Media & Apple Music, then try '
              'again.',
        _ => e.message ?? 'The Music library could not be read.',
      });
    }
    return appleMusicFromNative(raw ?? const {});
  }
}

/// I dati del lato nativo: brani {id, title, artist, album, ms, added} e
/// playlist {id, name, items: [id dei brani]}.
AppleMusicLibrary appleMusicFromNative(Map<Object?, Object?> raw) {
  final byId = <String, SpotifyTrack>{};
  final order = <SpotifyTrack>[];
  for (final s in (raw['songs'] as List?) ?? const []) {
    if (s is! Map) continue;
    final title = (s['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) continue;
    final artist = (s['artist'] as String?)?.trim() ?? '';
    final added = (s['added'] as num?)?.toInt();
    final t = SpotifyTrack(
      id: 'am:${s['id']}',
      name: title,
      artists: [if (artist.isNotEmpty) artist],
      album: s['album'] as String?,
      durationMs: (s['ms'] as num?)?.toInt(),
      addedAt: added == null || added <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(added),
    );
    byId['${s['id']}'] = t;
    order.add(t);
  }
  order.sort(
    (a, b) => (b.addedAt?.millisecondsSinceEpoch ?? 0).compareTo(
      a.addedAt?.millisecondsSinceEpoch ?? 0,
    ),
  );
  final playlists = <AppleMusicPlaylist>[
    for (final p in (raw['playlists'] as List?) ?? const [])
      if (p is Map)
        (
          id: 'am:${p['id']}',
          name: (p['name'] as String?) ?? 'Playlist',
          tracks: [
            for (final i in (p['items'] as List?) ?? const []) ?byId['$i'],
          ],
        ),
  ];
  return AppleMusicLibrary(
    songs: order,
    playlists: [
      for (final p in playlists)
        if (p.tracks.isNotEmpty) p,
    ],
    origin: Platform.isIOS ? 'the Music app on this iPhone' : 'the Music app',
  );
}
