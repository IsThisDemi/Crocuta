import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// La Web API di Spotify, per leggere una libreria: solo le chiamate che
/// servono all'import, e solo in lettura.
///
/// Scritta sulle regole del 2026 per le app in "development mode", che e'
/// quella che ognuno si crea per conto suo: le playlist danno i brani da
/// `/playlists/{id}/items` (non piu' `/tracks`), ogni voce li porta in
/// `item` (non piu' `track`, che si legge ancora se c'e'), e solo per le
/// playlist tue o in cui collabori — per le altre Spotify risponde 403.

/// Un brano di Spotify, quanto basta per ritrovarlo su YouTube Music.
class SpotifyTrack {
  /// Null per i file locali, che Spotify elenca ma non conosce.
  final String? id;
  final String name;
  final List<String> artists;
  final String? album;
  final int? durationMs;

  /// Quando e' stato aggiunto alla raccolta da cui viene.
  final DateTime? addedAt;

  const SpotifyTrack({
    this.id,
    required this.name,
    required this.artists,
    this.album,
    this.durationMs,
    this.addedAt,
  });

  /// La chiave per non cercare due volte lo stesso brano, che puo' stare
  /// fra i piaciuti e in tre playlist. I file locali non hanno id: li
  /// riconosce il nome.
  String get key =>
      id ?? 'local:${name.toLowerCase()}|${artists.join(',').toLowerCase()}';

  /// Gli interpreti come una riga sola, come li scrive Apple: "A, B".
  String get artist => artists.join(', ');

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// Da un oggetto "track" della API, con la data della voce che lo
  /// contiene. Null per gli episodi di podcast e le voci vuote (brani
  /// tolti dal catalogo).
  static SpotifyTrack? fromApi(Object? raw, {String? addedAt}) {
    if (raw is! Map) return null;
    if ((raw['type'] as String?) case final t? when t != 'track') return null;
    final name = (raw['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return SpotifyTrack(
      id: raw['is_local'] == true ? null : raw['id'] as String?,
      name: name,
      artists: [
        for (final a in raw['artists'] as List? ?? const [])
          if ((a as Map)['name'] case final String n when n.trim().isNotEmpty)
            n.trim(),
      ],
      album: (raw['album'] as Map?)?['name'] as String?,
      durationMs: (raw['duration_ms'] as num?)?.toInt(),
      addedAt: addedAt == null ? null : DateTime.tryParse(addedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'artists': artists,
    if (album != null) 'album': album,
    if (durationMs != null) 'ms': durationMs,
    if (addedAt != null) 'added': addedAt!.millisecondsSinceEpoch,
  };

  factory SpotifyTrack.fromJson(Map<String, dynamic> j) => SpotifyTrack(
    id: j['id'] as String?,
    name: j['name'] as String,
    artists: [for (final a in j['artists'] as List? ?? const []) a as String],
    album: j['album'] as String?,
    durationMs: j['ms'] as int?,
    addedAt: j['added'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(j['added'] as int),
  );
}

/// Una playlist della libreria, senza i brani.
class SpotifyPlaylist {
  final String id;
  final String name;
  final String? imageUrl;
  final String ownerId;
  final String ownerName;
  final int total;
  final bool collaborative;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.ownerId,
    required this.ownerName,
    required this.total,
    this.collaborative = false,
  });

  /// Se Spotify ne dara' i brani: solo per le tue e quelle in cui
  /// collabori.
  bool readableBy(String userId) => collaborative || ownerId == userId;

  static SpotifyPlaylist? fromApi(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final owner = raw['owner'] as Map? ?? const {};
    // `items` e' il campo nuovo, `tracks` quello vecchio: stessa forma.
    final count = (raw['items'] ?? raw['tracks']) as Map?;
    return SpotifyPlaylist(
      id: raw['id'] as String,
      name: (raw['name'] as String?)?.trim() ?? 'Playlist',
      imageUrl: _image(raw['images']),
      ownerId: (owner['id'] as String?) ?? '',
      ownerName:
          (owner['display_name'] as String?) ?? (owner['id'] as String?) ?? '',
      total: (count?['total'] as num?)?.toInt() ?? 0,
      collaborative: raw['collaborative'] == true,
    );
  }
}

/// Un disco salvato.
class SpotifyAlbum {
  final String id;
  final String name;
  final List<String> artists;
  final String? imageUrl;
  final int totalTracks;
  final DateTime? addedAt;

  const SpotifyAlbum({
    required this.id,
    required this.name,
    required this.artists,
    this.imageUrl,
    this.totalTracks = 0,
    this.addedAt,
  });

  static SpotifyAlbum? fromApi(Object? item) {
    if (item is! Map) return null;
    final raw = item['album'];
    if (raw is! Map || raw['id'] is! String) return null;
    return SpotifyAlbum(
      id: raw['id'] as String,
      name: (raw['name'] as String?)?.trim() ?? '',
      artists: [
        for (final a in raw['artists'] as List? ?? const [])
          if ((a as Map)['name'] case final String n) n,
      ],
      imageUrl: _image(raw['images']),
      totalTracks: (raw['total_tracks'] as num?)?.toInt() ?? 0,
      addedAt: DateTime.tryParse((item['added_at'] as String?) ?? ''),
    );
  }
}

/// Un artista seguito.
class SpotifyArtist {
  final String id;
  final String name;
  final String? imageUrl;

  const SpotifyArtist({required this.id, required this.name, this.imageUrl});

  static SpotifyArtist? fromApi(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return SpotifyArtist(
      id: raw['id'] as String,
      name: (raw['name'] as String?)?.trim() ?? '',
      imageUrl: _image(raw['images']),
    );
  }
}

class SpotifyUser {
  final String id;
  final String name;

  const SpotifyUser({required this.id, required this.name});
}

/// L'immagine piu' piccola che basti per una miniatura: Spotify le da'
/// dalla piu' grande, e la piu' grande e' 640 px.
String? _image(Object? images) {
  if (images is! List || images.isEmpty) return null;
  final sorted = [
    for (final i in images)
      if (i is Map && i['url'] is String) i,
  ];
  if (sorted.isEmpty) return null;
  sorted.sort(
    (a, b) => ((a['width'] as num?) ?? 0).compareTo((b['width'] as num?) ?? 0),
  );
  return (sorted.firstWhere(
        (i) => ((i['width'] as num?) ?? 300) >= 200,
        orElse: () => sorted.last,
      )['url']
      as String);
}

class SpotifyApiException implements Exception {
  final int status;
  final String message;

  const SpotifyApiException(this.status, this.message);

  /// 403: playlist non tua (o utente non aggiunto in User Management).
  bool get forbidden => status == 403;

  @override
  String toString() => message;
}

/// Il client della API, con i token di [accessToken].
class SpotifyApi {
  final http.Client client;
  final Future<String> Function({bool force}) accessToken;
  final Future<void> Function(Duration) sleep;

  /// Quante volte si riprova dopo un 429 o un errore del server.
  final int maxRetries;

  SpotifyApi({
    required this.client,
    required this.accessToken,
    Future<void> Function(Duration)? sleep,
    this.maxRetries = 5,
  }) : sleep = sleep ?? Future<void>.delayed;

  static const _host = 'api.spotify.com';

  static Uri _url(String path, [Map<String, String>? query]) =>
      Uri.https(_host, '/v1$path', query);

  /// Una GET, con i ripieghi che la API chiede: 401 si rinnova il token
  /// una volta; 429 si aspetta quanto dice Retry-After; 5xx si riprova
  /// con attese crescenti.
  Future<Map<String, dynamic>> getJson(Uri url) async {
    var refreshed = false;
    var force = false;
    for (var attempt = 0; ; attempt++) {
      final token = await accessToken(force: force);
      force = false;
      final http.Response resp;
      try {
        resp = await client.get(
          url,
          headers: {'Authorization': 'Bearer $token'},
        );
      } on Exception {
        if (attempt >= maxRetries) rethrow;
        await sleep(_backoff(attempt));
        continue;
      }
      switch (resp.statusCode) {
        case 200:
          return jsonDecode(utf8.decode(resp.bodyBytes))
              as Map<String, dynamic>;
        case 401 when !refreshed:
          refreshed = true;
          force = true;
          continue;
        case 429 when attempt < maxRetries:
          final after = int.tryParse(resp.headers['retry-after'] ?? '');
          await sleep(
            after == null ? _backoff(attempt) : Duration(seconds: after + 1),
          );
          continue;
        case 500 || 502 || 503 || 504 when attempt < maxRetries:
          await sleep(_backoff(attempt));
          continue;
      }
      throw SpotifyApiException(resp.statusCode, _message(resp));
    }
  }

  static Duration _backoff(int attempt) =>
      Duration(seconds: 2 << attempt.clamp(0, 5));

  static String _message(http.Response resp) {
    String? detail;
    try {
      final j = jsonDecode(resp.body);
      if (j is Map && j['error'] is Map) {
        detail = (j['error'] as Map)['message'] as String?;
      }
    } catch (_) {}
    return switch (resp.statusCode) {
      401 => 'The Spotify login expired. Connect again.',
      403 =>
        'Spotify refused the request${detail == null ? '' : ' ($detail)'}. '
            'If this is your first time, check that your Spotify account is '
            'added in User Management of your app.',
      429 => 'Spotify is limiting requests right now. Try again later.',
      _ =>
        'Spotify answered with code ${resp.statusCode}'
            '${detail == null ? '' : ': $detail'}.',
    };
  }

  /// Tutte le pagine di una lista, seguendo `next`. [page] tira fuori le
  /// voci e il link alla pagina dopo da ogni risposta.
  Future<List<T>> _collect<T>(
    Uri first,
    ({List items, String? next}) Function(Map<String, dynamic>) page,
    T? Function(Object? item) parse, {
    void Function(int done, int? total)? onPage,
  }) async {
    final out = <T>[];
    Uri? url = first;
    while (url != null) {
      final json = await getJson(url);
      final p = page(json);
      for (final item in p.items) {
        final v = parse(item);
        if (v != null) out.add(v);
      }
      onPage?.call(out.length, (json['total'] as num?)?.toInt());
      final next = p.next == null ? null : Uri.tryParse(p.next!);
      // Il token va solo a Spotify: un `next` altrove non si segue.
      url = next != null && next.host == _host ? next : null;
    }
    return out;
  }

  static ({List items, String? next}) _paging(Map<String, dynamic> j) =>
      (items: j['items'] as List? ?? const [], next: j['next'] as String?);

  Future<SpotifyUser> me() async {
    final j = await getJson(_url('/me'));
    final id = j['id'] as String? ?? '';
    return SpotifyUser(id: id, name: (j['display_name'] as String?) ?? id);
  }

  /// Quanti brani piaciuti, senza scaricarli.
  Future<int> likedCount() async {
    final j = await getJson(_url('/me/tracks', {'limit': '1'}));
    return (j['total'] as num?)?.toInt() ?? 0;
  }

  /// I brani piaciuti, dal piu' recente.
  Future<List<SpotifyTrack>> likedSongs({
    void Function(int done, int? total)? onPage,
  }) => _collect(
    _url('/me/tracks', {'limit': '50'}),
    _paging,
    (i) => i is Map
        ? SpotifyTrack.fromApi(i['track'], addedAt: i['added_at'] as String?)
        : null,
    onPage: onPage,
  );

  /// Le playlist della libreria: tue, seguite, collaborative.
  Future<List<SpotifyPlaylist>> playlists() => _collect(
    _url('/me/playlists', {'limit': '50'}),
    _paging,
    SpotifyPlaylist.fromApi,
  );

  /// I brani di una playlist, nel suo ordine.
  Future<List<SpotifyTrack>> playlistTracks(
    String id, {
    void Function(int done, int? total)? onPage,
  }) => _collect(
    _url('/playlists/$id/items', {'limit': '50', 'additional_types': 'track'}),
    _paging,
    (i) => i is Map
        ? SpotifyTrack.fromApi(
            i['item'] ?? i['track'],
            addedAt: i['added_at'] as String?,
          )
        : null,
    onPage: onPage,
  );

  /// I dischi salvati, dal piu' recente.
  Future<List<SpotifyAlbum>> savedAlbums() => _collect(
    _url('/me/albums', {'limit': '50'}),
    _paging,
    SpotifyAlbum.fromApi,
  );

  /// Gli artisti seguiti. Questa lista va a cursore, e sta dentro
  /// `artists`.
  Future<List<SpotifyArtist>> followedArtists() => _collect(
    _url('/me/following', {'type': 'artist', 'limit': '50'}),
    (j) => _paging(j['artists'] as Map<String, dynamic>? ?? const {}),
    SpotifyArtist.fromApi,
  );
}
