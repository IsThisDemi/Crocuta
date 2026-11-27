import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../models/album.dart';
import '../models/artist.dart';
import '../models/explore.dart';
import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/artist_names.dart';
import '../models/track.dart';
import 'stream_resolver.dart';

/// Shared, mutable cookie value read by [_CookieHttpClient] on every
/// request. Updating the login is just a string assignment — the client
/// is never recreated, so in-flight requests can't hit a closed client.
class _CookieState {
  String value = '';
}

/// An [http.BaseClient] that adds a YouTube cookie to every request.
///
/// YouTube serves full-length streams to signed-in sessions; anonymous
/// clients flagged by the anti-bot get ~1 MiB truncated streams (songs
/// stop after ~1 minute).
class _CookieHttpClient extends http.BaseClient {
  final _CookieState state;
  final http.Client _inner = http.Client();

  _CookieHttpClient(this.state);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (state.value.isNotEmpty && !request.headers.containsKey('Cookie')) {
      request.headers['Cookie'] = state.value;
    }
    return _inner.send(request);
  }
}

/// Searches YouTube Music and extracts playable audio streams.
///
/// Search goes through YouTube Music's InnerTube JSON API so that real
/// songs (like on Apple Music/Spotify) come first instead of random
/// videos. Artist/album/playlist pages use the `browse` endpoint and
/// "up next" suggestions use the `next` endpoint. Lyrics come from
/// LRCLIB (free, no key, LRC format with timestamps).
/// A structured search result, split into the sections used by the major
/// music apps: artists, songs, albums and playlists.
class SearchSections {
  final List<Track> songs;
  final List<AlbumCard> artists;
  final List<AlbumCard> albums;
  final List<AlbumCard> playlists;

  /// I video: remix e pezzi usciti solo su YouTube, che fra le canzoni non
  /// ci sono (vedi [Track.isVideo]).
  final List<Track> videos;

  /// Il risultato principale della ricerca e' un video: la pagina li mette
  /// prima delle canzoni, perche' e' li' che sta quello che cercavi.
  final bool topIsVideo;

  const SearchSections({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.videos = const [],
    this.topIsVideo = false,
  });

  bool get isEmpty =>
      songs.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty &&
      playlists.isEmpty &&
      videos.isEmpty;
}

class YouTubeService {
  final _CookieState _cookieState = _CookieState();

  YouTubeService({
    Map<String, Duration>? initialDurationCache,
    Future<void> Function(String id, Duration d)? onDurationResolved,
    Future<void> Function(List<Track> tracks)? onTracksSeen,
    Map<String, String>? initialAudioIds,
    Map<String, Track>? initialSongVersions,
    Future<void> Function(String id, String audioId, Track? song)?
    onAudioIdResolved,
    String? cookie,
  }) : _onDurationResolved = onDurationResolved,
       _onTracksSeen = onTracksSeen,
       _onAudioIdResolved = onAudioIdResolved {
    if (initialDurationCache != null) {
      _durationCache.addAll(initialDurationCache);
    }
    if (initialAudioIds != null) _audioIds.addAll(initialAudioIds);
    if (initialSongVersions != null) _songs.addAll(initialSongVersions);
    _cookieState.value = cookie?.trim() ?? '';
    // The client reads the shared cookie state on every request, so
    // changing the login never requires recreating (and closing) the
    // YoutubeExplode instance — that used to throw ClientClosedException
    // on requests that were in flight when the login changed.
    _yt = yt.YoutubeExplode(
      httpClient: yt.YoutubeHttpClient(_CookieHttpClient(_cookieState)),
    );
  }

  /// The login cookie used for stream requests (nullable when not set).
  String? get cookie => _cookieState.value.isEmpty ? null : _cookieState.value;

  /// Updates the login cookie without touching the underlying client.
  void setCookie(String? value) {
    _cookieState.value = value?.trim() ?? '';
  }

  late final yt.YoutubeExplode _yt;

  /// Resolves and validates playable audio URLs directly via the
  /// InnerTube player endpoints. Every candidate URL is probed with
  /// ranged GETs (offset 0 AND past the ~1 MiB anti-bot window) before
  /// being handed to the player, so flagged/truncating sources fall
  /// through to the next client instead of dying mid-song.
  late final StreamResolver _resolver = StreamResolver(
    cookieProvider: () => cookie,
    potProvider: _potProvider,
    webVisitorDataProvider: _webVdProvider,
  );

  /// Generatore poToken iniettato dopo la creazione del servizio (la
  /// PotService richiede flutter_riverpod e viene collegata dal provider).
  Future<String?> Function(String contentBinding)? _potProvider;
  Future<String?> Function()? _webVdProvider;

  set potProvider(Future<String?> Function(String contentBinding)? fn) =>
      _potProvider = fn;

  set webVisitorDataProvider(Future<String?> Function()? fn) =>
      _webVdProvider = fn;

  /// Accesso al resolver per il preloader (download completo).
  StreamResolver get resolver => _resolver;

  /// Resolves a validated audio source for [videoId] (progressive URL
  /// or HLS manifest), or null when every client fails validation.
  Future<ResolvedStream?> resolveAudio(
    String videoId, {
    int attempt = 0,
    bool preferHls = false,
  }) {
    return _resolver.resolve(videoId, attempt: attempt, preferHls: preferHls);
  }

  /// Lo stream del videoclip [videoId]: muto per la copertina animata, o
  /// con il suo audio per guardarlo.
  Future<ResolvedStream?> resolveVideo(
    String videoId, {
    StreamKind kind = StreamKind.videoOnly,
  }) => _resolver.resolve(videoId, kind: kind);

  /// Il videoclip ufficiale di un brano, o null se non c'e'.
  ///
  /// Se il brano e' gia' un video (un videoclip salvato nei preferiti),
  /// e' lui. Altrimenti lo si cerca col filtro "Videos": solo videoclip
  /// ufficiali (OMV), con lo stesso titolo e lo stesso artista — un video
  /// "slowed + reverb" o un lyric video di un canale qualunque non e' il
  /// videoclip del brano. Le risposte, anche i "non c'e'", si ricordano
  /// per la sessione: la copertina animata lo chiede a ogni apertura.
  Future<String?> musicVideoFor(Track track) async {
    if (_musicVideos.containsKey(track.id)) return _musicVideos[track.id];
    // Un video trovato fra i video e' lui stesso il suo video.
    if (track.isVideo) return _musicVideos[track.id] = track.id;
    try {
      final audio = await audioIdFor(track.id);
      if (audio != track.id) return _musicVideos[track.id] = track.id;
      final artist = primaryArtist(track.author);
      final data = await _post(_musicSearchUrl, {
        'context': _context,
        'query':
            '$artist ${songTitleKey(track.title, artist: artist, raw: true)}',
        'params': _videosFilter,
      });
      final tabs =
          data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      final sections =
          (tabs == null || tabs.isEmpty
                  ? null
                  : (tabs[0]
                        as Map)['tabRenderer']?['content']?['sectionListRenderer']?['contents'])
              as List? ??
          const [];
      final want = songTitleKey(track.title, artist: artist, loose: true);
      final who = _plain(artist);
      for (final section in sections) {
        final items =
            (section as Map)['musicShelfRenderer']?['contents'] as List? ??
            const [];
        for (final item in items) {
          final r = (item as Map)['musicResponsiveListItemRenderer'];
          final id = r?['playlistItemData']?['videoId'] as String?;
          if (r == null || id == null || _musicVideoType(r) != _omv) continue;
          final title = _flexText(r, 0) ?? '';
          final by = _runs(
            ((r['flexColumns'] as List?)?.elementAtOrNull(1)
                as Map?)?['musicResponsiveListItemFlexColumnRenderer']?['text'],
          ).map((m) => (m as Map)['text'] ?? '').join();
          if (songTitleKey(title, artist: artist, loose: true) != want)
            continue;
          if (!_plain(by).contains(who)) continue;
          return _musicVideos[track.id] = id;
        }
      }
      return _musicVideos[track.id] = null;
    } catch (e) {
      developer.log('Videoclip non trovato per ${track.id}: $e');
      return null;
    }
  }

  final Map<String, String?> _musicVideos = {};

  /// Called whenever a duration is resolved, so the caller can persist it.
  final Future<void> Function(String id, Duration d)? _onDurationResolved;

  /// Chiamata con ogni gruppo di brani appena letti dalla rete.
  ///
  /// Cio' che sta nei preferiti e nelle playlist e' una copia scattata il
  /// giorno in cui li hai salvati: quando l'analisi migliora — copertine
  /// quadrate al posto del fotogramma, titoli senza il feat doppio, il
  /// nome completo degli ospiti — quella copia resta indietro per sempre.
  /// Qui i brani passano comunque, quindi aggiornarla non costa nessuna
  /// richiesta in piu'.
  final Future<void> Function(List<Track> tracks)? _onTracksSeen;

  /// Segnala i brani letti e li restituisce, per poterlo infilare in un
  /// `return` senza spezzare il flusso.
  List<Track> _seen(List<Track> tracks) {
    // Un video gia' riconosciuto esce vestito da canzone. Anche verso le
    // copie salvate: senza, ogni volta che un grafico riportava il video,
    // il suo titolo "(Official Video)" tornava a scalzare quello pulito.
    final out = _songs.isEmpty ? tracks : tracks.map(dressed).toList();
    if (out.isNotEmpty) unawaited(_onTracksSeen?.call(out) ?? Future.value());
    return out;
  }

  static const _musicSearchUrl = 'https://music.youtube.com/youtubei/v1/search';
  static const _browseUrl = 'https://music.youtube.com/youtubei/v1/browse';
  static const _playerUrl = 'https://music.youtube.com/youtubei/v1/player';
  static const _nextUrl = 'https://music.youtube.com/youtubei/v1/next';
  static const _suggestUrl =
      'https://suggestqueries-clients6.youtube.com/complete/search';
  static const _lrclibUrl = 'https://lrclib.net/api/search';

  static const _context = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20240801.01.00',
      // Lingua inglese, paese invariato: 'hl' decide in che lingua YouTube
      // Music scrive riproduzioni, ascoltatori mensili e sottotitoli, 'gl'
      // decide *quale* musica ti mostra. Cambiare anche il secondo
      // sposterebbe classifiche e uscite su un altro mercato.
      'hl': 'en',
      'gl': 'IT',
    },
  };

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------

  /// Searches YouTube Music and splits the results into the sections used by
  /// major music apps: artists, songs, albums and playlists.
  Future<SearchSections> search(String query) async {
    // I video a parte, col filtro "Videos", insieme alla ricerca di tutto:
    // quella ne porta uno o due fra le canzoni, il filtro una ventina.
    final moreVideos = searchVideos(query).catchError((Object e) {
      developer.log('Video della ricerca non letti: $e');
      return <Track>[];
    });
    final data = await _post(_musicSearchUrl, {
      'context': _context,
      'query': query,
    });
    final tabs =
        data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
    final content = tabs == null || tabs.isEmpty
        ? null
        : (tabs[0] as Map)['tabRenderer']?['content'] as Map?;
    final sections =
        content?['sectionListRenderer']?['contents'] as List? ?? const [];

    final songs = <Track>[];
    final artists = <AlbumCard>[];
    final albums = <AlbumCard>[];
    final playlists = <AlbumCard>[];
    final videos = <Track>[];
    var topIsVideo = false;
    final seen = <String>{};

    void addCard(List<AlbumCard> list, AlbumCard card) {
      if (seen.add(card.browseId)) list.add(card);
    }

    for (final section in sections) {
      final s = section as Map;

      // The "top result" card: for artist queries it IS the artist (the
      // shelf carries the name, browseId and thumbnail; items are top songs).
      final card = s['musicCardShelfRenderer'];
      if (card != null) {
        // Il risultato principale puo' essere anche un brano o un video da
        // suonare: allora ha un watchEndpoint e non un browseEndpoint, e
        // prima si buttava via — per "ninja gaiden deko" era proprio il
        // video che si cercava.
        final watched = _cardTrack(card as Map);
        if (watched != null) {
          if (watched.isVideo) {
            videos.add(watched);
            topIsVideo = true;
          } else {
            songs.add(watched);
          }
          continue;
        }
        final browseId =
            card['onTap']?['browseEndpoint']?['browseId'] as String?;
        final cardTitle = _text(card['title']);
        if (browseId != null &&
            cardTitle != null &&
            cardTitle.trim().isNotEmpty) {
          // Shelf thumbnail, falling back to the first item's thumbnail.
          String? itemThumb;
          final cardItems = card['contents'] as List? ?? const [];
          for (final ci in cardItems) {
            final r = (ci as Map)['musicResponsiveListItemRenderer'];
            if (r != null) {
              itemThumb = _itemThumb(r);
              break;
            }
          }
          final thumb = _thumbUrl(card['thumbnail']) ?? itemThumb ?? '';
          if (seen.add(browseId)) {
            artists.insert(
              0,
              AlbumCard(
                browseId: browseId,
                title: cardTitle,
                subtitle: 'Artist',
                thumbnailUrl: thumb,
              ),
            );
          }
        }
        continue;
      }

      final itemSection = s['itemSectionRenderer'];
      if (itemSection == null) continue;
      final items = itemSection['contents'] as List? ?? const [];
      for (final item in items) {
        final r = (item as Map)['musicResponsiveListItemRenderer'];
        if (r == null) continue;

        final flex = r['flexColumns'] as List? ?? const [];
        final title = _flexText(r, 0) ?? '';
        final subtitleRuns = flex.length > 1
            ? _runs(
                (flex[1]
                    as Map)['musicResponsiveListItemFlexColumnRenderer']?['text'],
              )
            : const <dynamic>[];

        // The first meaningful run of the second column is the item type:
        // "Brano", "Artista", "Album", "Playlist", "Video", …
        String? type;
        for (final run in subtitleRuns) {
          final t = (run as Map)['text'] as String?;
          if (t != null && t.trim() != '•' && t.trim().isNotEmpty) {
            type = t.trim();
            break;
          }
        }
        final typeLower = (type ?? '').toLowerCase();

        final videoId = r['playlistItemData']?['videoId'] as String?;
        final browseId =
            r['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;

        // Il tipo arriva tradotto: con hl='en' e' "Song", non "Brano".
        // Si accettano entrambe le lingue perche' costa niente e una
        // risposta in italiano — una cache, un ripiego — non deve far
        // sparire in silenzio meta' dei risultati.
        if ((typeLower.contains('song') || typeLower.contains('brano')) &&
            videoId != null) {
          // Second column is "Brano • Artista • Album • Anno": each run may
          // carry a browseEndpoint. The first navigable one is the artist
          // (author+artistId), the second is the album (albumName+albumId).
          String? author;
          String? artistId;
          String? albumName;
          String? albumId;
          var artistSeen = false;
          for (final run in subtitleRuns) {
            final rowRun = run as Map;
            final text = rowRun['text'] as String?;
            final bid =
                rowRun['navigationEndpoint']?['browseEndpoint']?['browseId']
                    as String?;
            if (text != null && text.trim() != '•' && text.trim().isNotEmpty) {
              if (bid != null && !artistSeen) {
                author = text.trim();
                artistId = bid;
                artistSeen = true;
              } else if (bid != null && artistSeen && albumId == null) {
                albumName = text.trim();
                albumId = bid;
              } else if (author == null) {
                author = text.trim();
              }
            }
          }
          _noteIfSong(r, videoId);
          songs.add(
            Track(
              id: videoId,
              title: _cleanTitle(title),
              author: author ?? 'Unknown',
              duration: _durationFromCache(videoId),
              thumbnailUrl:
                  _itemThumb(r) ??
                  'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
              artistId: artistId,
              albumId: albumId,
              albumName: albumName,
              isExplicit: _isExplicit(r),
            ),
          );
        } else if (typeLower.startsWith('video') && videoId != null) {
          final v = _videoRow(r, videoId);
          if (v != null) videos.add(v);
        } else if ((typeLower.contains('artist') ||
                typeLower.contains('artista')) &&
            browseId != null) {
          addCard(
            artists,
            AlbumCard(
              browseId: browseId,
              title: title,
              subtitle: 'Artist',
              thumbnailUrl: _itemThumb(r) ?? '',
            ),
          );
        } else if (typeLower.contains('album') && browseId != null) {
          addCard(
            albums,
            AlbumCard(
              browseId: browseId,
              title: title,
              subtitle: _joinedRuns(subtitleRuns) ?? '',
              thumbnailUrl: _itemThumb(r) ?? '',
            ),
          );
        } else if (typeLower.contains('playlist') && browseId != null) {
          addCard(
            playlists,
            AlbumCard(
              browseId: browseId,
              title: title,
              subtitle: _joinedRuns(subtitleRuns) ?? '',
              thumbnailUrl: _itemThumb(r) ?? '',
            ),
          );
        }
      }
    }

    // Prima quelli della ricerca di tutto, nel suo ordine, poi gli altri
    // del filtro; uno solo per id.
    // Quelli gia' presenti prendono dal filtro la durata, che la ricerca
    // di tutto non scrive.
    final at = {for (final (i, v) in videos.indexed) v.id: i};
    for (final v in await moreVideos) {
      final i = at[v.id];
      if (i != null) {
        if (videos[i].duration == null && v.duration != null) {
          videos[i] = videos[i].copyWith(duration: v.duration);
        }
        continue;
      }
      if (videos.length >= _maxSearchVideos) continue;
      at[v.id] = videos.length;
      videos.add(v);
    }

    // Non vestiti da canzone come gli altri (vedi [_seen]): qui si cercava
    // proprio il video, e nella fila dei video deve restare lui.
    if (videos.isNotEmpty) {
      unawaited(_onTracksSeen?.call(videos) ?? Future.value());
    }
    return SearchSections(
      songs: songs,
      artists: artists,
      albums: albums,
      playlists: playlists,
      videos: videos,
      topIsVideo: topIsVideo,
    );
  }

  /// Quanti video mostra la ricerca: una fila che scorre, non una pagina.
  static const _maxSearchVideos = 12;

  /// I video per [query], dal filtro "Videos" di YouTube Music.
  Future<List<Track>> searchVideos(String query) async {
    final data = await _post(_musicSearchUrl, {
      'context': _context,
      'query': query,
      'params': _videosFilter,
    });
    final tabs =
        data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
    final sections =
        (tabs == null || tabs.isEmpty
                ? null
                : (tabs[0]
                      as Map)['tabRenderer']?['content']?['sectionListRenderer']?['contents'])
            as List? ??
        const [];
    final out = <Track>[];
    for (final section in sections) {
      final items =
          (section as Map)['musicShelfRenderer']?['contents'] as List? ??
          const [];
      for (final item in items) {
        final r = (item as Map)['musicResponsiveListItemRenderer'];
        final id = r?['playlistItemData']?['videoId'] as String?;
        if (r == null || id == null) continue;
        final v = _videoRow(r as Map, id);
        if (v != null) out.add(v);
      }
    }
    return out;
  }

  /// Una riga video: il titolo nella prima colonna, nella seconda il
  /// canale (o l'artista, per i videoclip ufficiali), le visualizzazioni e
  /// la durata — "Video • De'Ko • 153K views" nella ricerca di tutto,
  /// "De'Ko • 153K views • 2:08" col filtro.
  Track? _videoRow(Map r, String videoId) {
    final title = _flexText(r, 0);
    if (title == null || title.trim().isEmpty) return null;
    final flex = r['flexColumns'] as List? ?? const [];
    final runs = [
      for (var c = 1; c < flex.length; c++)
        ..._runs(
          (flex[c]
              as Map)['musicResponsiveListItemFlexColumnRenderer']?['text'],
        ),
    ];
    return _videoTrack(
      videoId,
      title: title,
      runs: runs,
      thumbnail: _itemThumb(r),
      explicit: _isExplicit(r),
      official: _musicVideoType(r) == _omv,
    );
  }

  /// Il brano o il video del riquadro del risultato principale, se e' uno
  /// da suonare e non un artista o un album da aprire.
  Track? _cardTrack(Map card) {
    final watch = card['onTap']?['watchEndpoint'] as Map?;
    final videoId = watch?['videoId'] as String?;
    final title = _text(card['title']);
    if (videoId == null || title == null || title.trim().isEmpty) return null;
    final type =
        watch?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType']
            as String?;
    final runs = (card['subtitle']?['runs'] as List?) ?? const [];
    final thumb = _thumbUrl(card['thumbnail']);
    if (type == _atv) {
      _audioIds.putIfAbsent(videoId, () => videoId);
      final v = _videoTrack(
        videoId,
        title: title,
        runs: runs,
        thumbnail: thumb,
        official: true,
      );
      return v == null
          ? null
          : Track(
              id: v.id,
              title: v.title,
              author: v.author,
              duration: v.duration,
              thumbnailUrl: v.thumbnailUrl,
              artistId: v.artistId,
            );
    }
    return _videoTrack(
      videoId,
      title: title,
      runs: runs,
      thumbnail: thumb,
      official: type == _omv,
    );
  }

  /// Un [Track] video dai pezzi di testo sotto il titolo: la parola "Video"
  /// e i punti si saltano, il primo nome (con la sua pagina, se ce l'ha) e'
  /// chi l'ha pubblicato, poi visualizzazioni e durata.
  Track? _videoTrack(
    String videoId, {
    required String title,
    required List<dynamic> runs,
    String? thumbnail,
    bool explicit = false,

    /// Un videoclip ufficiale: chi l'ha pubblicato e' l'artista, e la sua
    /// pagina si apre. Il canale di chi ha caricato un video qualunque non
    /// e' una pagina d'artista.
    bool official = false,
  }) {
    String? author, artistId, views;
    Duration? duration;
    for (final run in runs) {
      final m = run as Map;
      final text = (m['text'] as String? ?? '').trim();
      if (text.isEmpty || text == '•') continue;
      final low = text.toLowerCase();
      if (author == null &&
          (low == 'video' || low == 'song' || low == 'brano')) {
        continue;
      }
      if (RegExp(r'^\d+(:\d{2}){1,2}$').hasMatch(text)) {
        duration = _parseDuration(text);
      } else if (RegExp(
        r'(views|visualizzazioni|plays|riproduzioni)$',
      ).hasMatch(low)) {
        views = text;
      } else if (author == null) {
        author = text;
        if (official) {
          artistId =
              m['navigationEndpoint']?['browseEndpoint']?['browseId']
                  as String?;
        }
      }
    }
    if (duration != null) _durationCache.putIfAbsent(videoId, () => duration!);
    return Track(
      id: videoId,
      title: _cleanTitle(title),
      author: author ?? 'Unknown',
      duration: duration ?? _durationFromCache(videoId),
      thumbnailUrl:
          thumbnail ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      artistId: artistId,
      plays: views,
      isExplicit: explicit,
      isVideo: true,
    );
  }

  // ---------------------------------------------------------------------
  // La canzone, non il videoclip
  // ---------------------------------------------------------------------

  /// Il filtro "Songs" della ricerca: solo brani, niente video.
  static const _songsFilter = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';

  /// Il filtro "Videos" della ricerca di YouTube Music: lo stesso schema di
  /// quello delle canzoni, verificato su una richiesta vera.
  static const _videosFilter = 'EgWKAQIQAWoKEAkQChAFEAMQBA==';

  /// Per ogni id gia' controllato, l'id da cui prendere l'audio: lui stesso
  /// se e' una canzone, la sua versione canzone se e' un videoclip.
  final Map<String, String> _audioIds = {};

  /// Per ogni videoclip con una versione canzone, i dati di quella: titolo,
  /// interpreti, copertina, album, durata. Con l'id del videoclip, cosi' si
  /// possono stendere sopra il brano salvato senza che cambi identita'.
  final Map<String, Track> _songs = {};

  final Map<String, Future<String>> _audioIdsInflight = {};
  final Future<void> Function(String id, String audioId, Track? song)?
  _onAudioIdResolved;

  /// L'id dell'audio gia' noto, senza chiedere niente alla rete.
  String knownAudioId(String videoId) => _audioIds[videoId] ?? videoId;

  /// [track] vestito da canzone, se e' un videoclip gia' riconosciuto.
  ///
  /// Non solo l'audio: anche titolo e copertina. "Sfera Ebbasta - Lontano
  /// (Official Video)" con un fotogramma tagliato a quadrato diventa
  /// "Lontano" con la copertina del disco — e la durata vera, che e' quella
  /// dell'audio che suonera'.
  Track dressed(Track track) {
    final song = _songs[track.id];
    return song == null ? track : track.refreshedFrom(song);
  }

  /// La versione canzone di [track], cercandola se non la si conosce.
  ///
  /// Nulla se non e' un videoclip, o se una canzone uguale non c'e'. Per la
  /// pulizia della libreria: un brano gia' controllato non costa niente.
  Future<Track?> songVersionFor(Track track) async {
    if (_songs[track.id] != null) return dressed(track);
    final known = _audioIds[track.id];
    if (known == track.id) return null;
    // Un abbinamento ricordato prima che si salvassero anche i dati della
    // canzone: si rifa', una volta, per averli.
    if (known != null) _audioIds.remove(track.id);
    await audioIdFor(track.id);
    return _songs[track.id] == null ? null : dressed(track);
  }

  /// Da dove prendere l'audio di [videoId].
  ///
  /// YouTube Music ha due versioni di quasi ogni brano: la canzone (ATV,
  /// l'audio del disco) e il video — il videoclip (OMV) o il caricamento di
  /// un canale (UGC, i vari "Official Audio") — con intro, scene parlate ed
  /// effetti che sul disco non ci sono. Grafici, playlist degli utenti e
  /// radio portano spesso il video: "Romeo" di PinkPantheress nei preferiti
  /// era "Romeo (Official Video)". L'app web lo risolve con lo switch
  /// Song/Video, ma la controparte arriva solo a chi ha fatto l'accesso:
  /// qui la si cerca fra i brani con lo stesso titolo e artista.
  ///
  /// L'id del brano non cambia: preferiti, playlist e statistiche restano
  /// suoi, cambia solo da dove arriva il suono. Se qualcosa va storto si
  /// suona quello che c'e', come prima; e solo le risposte certe si
  /// ricordano, cosi' un errore di rete non resta scritto per sempre.
  Future<String> audioIdFor(String videoId) {
    final known = _audioIds[videoId];
    if (known != null) return Future.value(known);
    return _audioIdsInflight[videoId] ??= _lookupAudioId(videoId)
        .timeout(const Duration(seconds: 6), onTimeout: () => videoId)
        // Graffe, non freccia: la freccia restituirebbe il valore rimosso,
        // cioe' questa stessa future, e whenComplete la aspetterebbe —
        // una future che aspetta se stessa non finisce mai.
        .whenComplete(() {
          _audioIdsInflight.remove(videoId);
        });
  }

  Future<String> _lookupAudioId(String videoId) async {
    try {
      final data = await _post(_nextUrl, {
        'context': _context,
        'videoId': videoId,
        'isAudioOnly': true,
      });
      final contents =
          data['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents']
              as List? ??
          const [];
      Map? me;
      for (final item in contents) {
        final r = (item as Map)['playlistPanelVideoRenderer'];
        if (r != null && r['videoId'] == videoId) me = r;
      }
      if (me == null) return videoId;
      final type =
          me['navigationEndpoint']?['watchEndpoint']?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType'];
      if (type != _omv && type != _ugc) {
        await _rememberAudioId(videoId, videoId, null);
        return videoId;
      }
      final title = _runsText(me['title']) ?? '';
      final byline = me['shortBylineText'] ?? me['longBylineText'];
      final artist =
          (byline?['runs'] as List?)?.first?['text'] as String? ?? '';
      final song = await _songVersionOf(title, artist);
      developer.log('Video $videoId "$title" -> canzone ${song?.id ?? '-'}');
      if (song == null) {
        await _rememberAudioId(videoId, videoId, null);
        return videoId;
      }
      // I dati della canzone, ma con l'id del video: e' quello che hanno
      // i brani salvati, ed e' quello che deve restare.
      final dressing = song.copyWith(id: videoId);
      await _rememberAudioId(videoId, song.id, dressing);
      // Le copie salvate si rivestono subito, non al prossimo avvio.
      unawaited(_onTracksSeen?.call([dressing]) ?? Future.value());
      return song.id;
    } catch (e) {
      developer.log('Versione canzone non trovata per $videoId: $e');
      return videoId;
    }
  }

  Future<void> _rememberAudioId(String id, String audioId, Track? song) async {
    _audioIds[id] = audioId;
    if (song != null) _songs[id] = song;
    await _onAudioIdResolved?.call(id, audioId, song);
  }

  Future<Track?> _songVersionOf(String title, String artist) async {
    final (candidates, rows) = await _searchSongs(
      '$artist ${songTitleKey(title, artist: artist, raw: true)}',
    );
    final picked = pickSongVersion(title, artist, candidates);
    return picked == null ? null : rows[picked];
  }

  /// Il brano di YouTube Music che corrisponde a uno di un altro catalogo,
  /// per importare una libreria (Apple Music): null se non c'e' con
  /// sicurezza. Vedi [pickCatalogSong] per cosa conta come "lo stesso".
  Future<Track?> findCatalogSong(
    String title,
    String artist, {
    Duration? duration,
    String? query,
  }) async {
    final (candidates, rows) = await _searchSongs(
      query ?? '${primaryArtist(artist)} ${stripFeaturing(title)}',
    );
    final picked = pickCatalogSong(title, artist, duration, [
      for (final c in candidates)
        (candidate: c, duration: rows[c.id]?.duration),
    ]);
    return picked == null ? null : rows[picked];
  }

  /// Le canzoni di una ricerca col filtro Songs, nell'ordine di YouTube
  /// Music: per scegliere a mano quando il confronto automatico non basta.
  Future<List<Track>> searchSongs(String query) async {
    final (candidates, rows) = await _searchSongs(query);
    return [for (final c in candidates) rows[c.id]!];
  }

  /// Le righe "canzone" di una ricerca col filtro Songs.
  Future<(List<SongCandidate>, Map<String, Track>)> _searchSongs(
    String query,
  ) async {
    final data = await _post(_musicSearchUrl, {
      'context': _context,
      'query': query,
      'params': _songsFilter,
    });
    final tabs =
        data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
    final sections =
        (tabs == null || tabs.isEmpty
                ? null
                : (tabs[0]
                      as Map)['tabRenderer']?['content']?['sectionListRenderer']?['contents'])
            as List? ??
        const [];
    final candidates = <SongCandidate>[];
    final rows = <String, Track>{};
    for (final section in sections) {
      final items =
          (section as Map)['musicShelfRenderer']?['contents'] as List? ??
          const [];
      for (final item in items) {
        final r = (item as Map)['musicResponsiveListItemRenderer'];
        final id = r?['playlistItemData']?['videoId'] as String?;
        if (r == null || id == null) continue;
        if (_musicVideoType(r) != _atv) continue;
        final song = _songRow(r, id);
        rows[id] = song;
        candidates.add((id: id, title: song.title, artists: song.author));
      }
    }
    return (candidates, rows);
  }

  /// Il titolo senza gli ospiti: "After the Storm (feat. Tyler, The
  /// Creator)" diventa "After the Storm".
  ///
  /// Apple li scrive nel titolo, YouTube Music spesso solo fra gli
  /// interpreti: confrontando i titoli interi lo stesso brano non si
  /// riconoscerebbe.
  static String stripFeaturing(String title) => title
      .replaceAll(
        RegExp(
          r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+(feat\.?|ft\.?)\s.*$', caseSensitive: false), '')
      .trim();

  /// Il primo interprete: "Yeat & BNYX®" -> "Yeat".
  static String primaryArtist(String artist) => artist
      .split(RegExp(r'\s*(?:,|&|\bx\b|\bfeat\.?|\bwith\b)\s*'))
      .first
      .trim();

  /// Quale candidato e' lo stesso brano di un altro catalogo.
  ///
  /// Stesso titolo (senza ospiti ne' edizioni come "Radio Edit"), stesso
  /// primo interprete, e — quando entrambi la dicono — durata entro
  /// [tolerance]: e' la durata a scartare live, versioni estese e remix
  /// con lo stesso nome. Prima il titolo esatto, poi quello senza edizione.
  static String? pickCatalogSong(
    String title,
    String artist,
    Duration? duration,
    List<({SongCandidate candidate, Duration? duration})> candidates, {
    Duration tolerance = const Duration(seconds: 10),
  }) {
    final who = _plain(primaryArtist(artist));
    bool closeEnough(Duration? d) =>
        duration == null || d == null || (d - duration).abs() <= tolerance;
    for (final loose in [false, true]) {
      final want = songTitleKey(stripFeaturing(title), loose: loose);
      if (want.isEmpty) return null;
      for (final (:candidate, duration: d) in candidates) {
        final key = songTitleKey(stripFeaturing(candidate.title), loose: loose);
        if (key != want) continue;
        // In tutti e due i versi: "Marina and The Diamonds" su Apple e'
        // "MARINA" su YouTube Music, lo stesso artista rinominato. Il verso
        // inverso vale solo per nomi non cortissimi, e la durata controlla.
        final theirs = _plain(primaryArtist(candidate.artists));
        final sameArtist =
            who.isEmpty ||
            _plain(candidate.artists).contains(who) ||
            (theirs.length >= 4 && who.contains(theirs) && d != null);
        if (!sameArtist) continue;
        if (!closeEnough(d)) continue;
        return candidate.id;
      }
    }
    return null;
  }

  /// Una riga della ricerca "Songs": "Titolo" e sotto
  /// "Interpreti • Album • 2:35", ogni nome col suo collegamento.
  Track _songRow(Map r, String id) {
    final flex = r['flexColumns'] as List? ?? const [];
    final runs = flex.length > 1
        ? _runs(
            (flex[1]
                as Map)['musicResponsiveListItemFlexColumnRenderer']?['text'],
          )
        : const <dynamic>[];
    // I pezzi separati da " • ": il primo sono gli interpreti (anche piu'
    // run, "A & B"), poi l'album, per ultima la durata.
    final parts = <List<Map>>[[]];
    for (final run in runs) {
      final m = run as Map;
      if ((m['text'] as String?)?.trim() == '•') {
        parts.add([]);
      } else {
        parts.last.add(m);
      }
    }
    String? idOf(Map run) =>
        run['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
    String? artistId;
    String? albumId;
    String? albumName;
    for (final run in parts.first) {
      artistId ??= idOf(run);
    }
    for (final part in parts.skip(1)) {
      for (final run in part) {
        final bid = idOf(run);
        if (bid != null && bid.startsWith('MPRE')) {
          albumId = bid;
          albumName = (run['text'] as String?)?.trim();
        }
      }
    }
    final last = parts.length > 1
        ? parts.last.map((m) => m['text'] ?? '').join().trim()
        : null;
    final author = parts.first.map((m) => m['text'] ?? '').join().trim();
    return Track(
      id: id,
      title: _cleanTitle(_flexText(r, 0)),
      author: author.isEmpty ? 'Unknown' : author,
      duration: _parseDuration(last),
      thumbnailUrl:
          _itemThumb(r) ?? 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      artistId: artistId,
      albumId: albumId,
      albumName: albumName,
      isExplicit: _isExplicit(r),
    );
  }

  static const _omv = 'MUSIC_VIDEO_TYPE_OMV';
  static const _ugc = 'MUSIC_VIDEO_TYPE_UGC';
  static const _atv = 'MUSIC_VIDEO_TYPE_ATV';

  /// Il tipo di una riga di lista, dal pulsante play sulla copertina.
  String? _musicVideoType(Map r) =>
      r['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType']
          as String?;

  /// Una riga che si dichiara canzone non ha bisogno di controlli: lo si
  /// segna subito, e il suo primo play non costa nessuna richiesta.
  void _noteIfSong(Map r, String videoId) {
    if (_musicVideoType(r) == _atv)
      _audioIds.putIfAbsent(videoId, () => videoId);
  }

  /// La canzone che corrisponde al videoclip, fra i risultati di ricerca.
  ///
  /// Lo stesso titolo, tolto cio' che descrive il video, e lo stesso
  /// artista. Uguale e non "simile": "Romeo + Rachel Chinouriri" e' un
  /// altro brano, e suonare la versione sbagliata sarebbe peggio del video.
  static String? pickSongVersion(
    String videoTitle,
    String artist,
    List<SongCandidate> candidates,
  ) {
    final who = _plain(artist);
    // Prima il titolo identico; solo se non c'e', la stessa canzone in una
    // sua edizione — "Vento di passione (Radio edit)" di Mina, che del
    // videoclip ha perfino la durata. Nell'ordine inverso, dove ci sono
    // sia "Romeo" sia "Romeo (Radio Edit)", vincerebbe quella tagliata.
    for (final loose in [false, true]) {
      final want = songTitleKey(videoTitle, artist: artist, loose: loose);
      for (final c in candidates) {
        if (songTitleKey(c.title, artist: artist, loose: loose) != want) {
          continue;
        }
        if (!_plain(c.artists).contains(who)) continue;
        return c.id;
      }
    }
    return null;
  }

  /// Il titolo senza cio' che descrive il video: "(Official Video)",
  /// "[4K]", "Lyric Video", e il nome dell'artista davanti quando il
  /// canale lo scrive come "Artista - Titolo".
  ///
  /// Con [raw] resta leggibile, per la ricerca; senza, e' ridotto a lettere
  /// e cifre minuscole, per il confronto.
  static String songTitleKey(
    String title, {
    String artist = '',
    bool raw = false,
    bool loose = false,
  }) {
    var t = title.replaceAll(
      RegExp(
        r'\s*[\(\[][^\)\]]*\b(video|visuali[sz]er|lyrics?|audio|official|mv|4k|hd|clip)\b[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );
    // Con [loose] cade anche l'edizione: e' la stessa canzone, accorciata
    // per la radio o presa dal singolo. Non "remix", "live", "sped up":
    // quelle sono un'altra cosa da sentire.
    if (loose) {
      t = t.replaceAll(
        RegExp(
          r'\s*[\(\[]\s*(radio edit|radio version|single version|album version)\s*[\)\]]',
          caseSensitive: false,
        ),
        '',
      );
    }
    if (artist.isNotEmpty) {
      t = t.replaceFirst(
        RegExp(
          '^\\s*${RegExp.escape(artist)}\\s*[-–—:]\\s*',
          caseSensitive: false,
        ),
        '',
      );
    }
    return raw ? t.trim() : _plain(t);
  }

  static String _plain(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  // Cache of video durations, populated lazily (the search API omits them)
  // and persisted through [_onDurationResolved] so it survives restarts.
  final Map<String, Duration> _durationCache = {};

  Duration? _durationFromCache(String videoId) => _durationCache[videoId];

  /// Fetches missing durations for [tracks] and returns an updated list.
  ///
  /// The YTM search API omits durations, so we resolve them from the video
  /// pages after the list is shown. Requests are issued in small batches (3
  /// at a time) with a short pause between batches: firing 10 parallel
  /// requests at once trips YouTube's rate limiting on the device, which
  /// left music-type tracks stuck at "--:--" while direct video lookups
  /// still worked.
  Future<List<Track>> enrichDurations(List<Track> tracks) async {
    final missing = tracks
        .where((t) => t.duration == null)
        .where((t) => !_durationCache.containsKey(t.id))
        .take(15)
        .toList();
    const batchSize = 3;
    for (var i = 0; i < missing.length; i += batchSize) {
      final batch = missing.sublist(
        i,
        (i + batchSize).clamp(0, missing.length),
      );
      await Future.wait(
        batch.map((t) async {
          try {
            final v = await _yt.videos.get(t.id);
            final d = v.duration;
            if (d != null) {
              _durationCache[t.id] = d;
              await _onDurationResolved?.call(t.id, d);
            }
          } catch (e) {
            developer.log('Durata non disponibile per ${t.id}: $e');
          }
        }),
      );
      if (i + batchSize < missing.length) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }
    // Unico punto di uscita di ricerca, brani dell'artista e coda radio:
    // segnalarli qui li copre tutti e tre.
    return _seen(
      tracks.map((t) {
        final d = _durationCache[t.id];
        return d != null ? t.copyWith(duration: d) : t;
      }).toList(),
    );
  }

  /// Finds REPLACEMENT videoIds for [track]: Google flagga i singoli
  /// videoId (serve solo ~1 MiB oppure 403 da byte 0) in modo VARYING e
  /// temporaneo; ogni brano ha pero' quasi sempre altre copie (album,
  /// audio-only, video ufficiali...) alcune delle quali servono l'intero
  /// stream. Misurato sul campo: la stessa canzone (anche lo stesso
  /// artista) ha copie INTEGRE e copie TAGLIATE contemporaneamente.
  Future<List<Track>> alternateVideos(Track track) async {
    try {
      final sections = await search('${track.author} ${track.title}');
      return sections.songs.where((t) => t.id != track.id).take(4).toList();
    } catch (e) {
      developer.log('ALTERNATE errore per ${track.title}: $e');
      return const [];
    }
  }

  /// Returns YouTube search suggestions for [query].
  Future<List<String>> getSuggestions(String query) async {
    final uri = Uri.parse(_suggestUrl).replace(
      queryParameters: {
        'client': 'youtube',
        'ds': 'yt',
        'hl': 'en',
        'gl': 'IT',
        'q': query,
      },
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return const [];

    // The endpoint replies in JSONP form: window.google.ac.h([...]).
    var body = resp.body.trim();
    const prefix = 'window.google.ac.h(';
    if (body.startsWith(prefix)) {
      body = body.substring(prefix.length);
      if (body.endsWith(')')) body = body.substring(0, body.length - 1);
    }

    final decoded = jsonDecode(body) as List<dynamic>;
    final suggestions = decoded.length > 1 ? decoded[1] as List? : null;
    if (suggestions == null) return const [];
    return suggestions
        .map((s) => s is List && s.isNotEmpty ? s[0].toString() : null)
        .whereType<String>()
        .toList();
  }

  // ---------------------------------------------------------------------
  // Pages: artist / album / playlist
  // ---------------------------------------------------------------------

  /// Fetches an artist page (top songs + album/single/playlist carousels).
  Future<ArtistPage> getArtistPage(String browseId) async {
    final data = await _browse(browseId);

    final header =
        data['header']?['musicImmersiveHeaderRenderer'] ?? data['header'];
    final name = _runsText(header?['title']);
    final thumbUrl = _thumbUrl(header?['thumbnail']);

    // "49,7 Mln ascoltatori mensili": e' l'unico numero che dice quanto e'
    // grande un artista, e ce l'abbiamo gia' in mano.
    final monthlyListeners = _runsText(header?['monthlyListenerCount']);

    final sections = _sections(data);
    final topSongs = <Track>[];
    final albums = <AlbumCard>[];
    final singles = <AlbumCard>[];
    final playlists = <AlbumCard>[];
    final similar = <AlbumCard>[];
    SectionLink? topSongsMore;
    SectionLink? albumsMore;
    SectionLink? singlesMore;

    for (final section in sections) {
      final shelf = section['musicShelfRenderer'];
      if (shelf != null) {
        topSongsMore ??= _moreLink(
          shelf,
          _runsText(shelf['title']) ?? 'Top songs',
          songs: true,
        );
        final items = shelf['contents'] as List? ?? const [];
        for (final item in items) {
          final r = (item as Map)['musicResponsiveListItemRenderer'];
          if (r == null) continue;
          final videoId = r['playlistItemData']?['videoId'] as String?;
          if (videoId == null) continue;
          final fixed = r['fixedColumns'] as List? ?? const [];
          final durText = _runsText(
            fixed.isNotEmpty
                ? ((fixed[0]
                      as Map)['musicResponsiveListItemFixedColumnRenderer']?['text'])
                : null,
          );
          topSongs.add(
            Track(
              id: videoId,
              title: _cleanTitle(_flexText(r, 0)),
              // La colonna 1 nomina davvero chi suona, ospiti compresi; il
              // nome della pagina li perdeva tutti tranne il principale.
              author: _flexTextFull(r, 1) ?? name ?? 'Unknown',
              duration: _parseDuration(durText),
              // La copertina della riga, non il fotogramma del video: qui
              // ogni brano viene da un disco diverso, quindi ce l'ha propria.
              thumbnailUrl:
                  _itemThumb(r) ??
                  'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
              artistId: browseId,
              albumName: _albumNameFrom(r),
              plays: _playsFrom(r),
              isExplicit: _isExplicit(r),
            ),
          );
        }
        continue;
      }

      final carousel = section['musicCarouselShelfRenderer'];
      if (carousel == null) continue;
      final carTitle = _runsText(
        carousel['header']?['musicCarouselShelfBasicHeaderRenderer']?['title'],
      );
      final items = carousel['contents'] as List? ?? const [];
      final cards = <AlbumCard>[];
      // Il tipo di pagina a cui puntano le schede, non il titolo della
      // sezione: "Ai fan potrebbe anche piacere" cambia con la lingua,
      // mentre MUSIC_PAGE_TYPE_ARTIST no.
      var pageType = '';
      for (final item in items) {
        final row = (item as Map)['musicTwoRowItemRenderer'];
        if (row == null) continue;
        final nav = row['navigationEndpoint'];
        final browseId = nav?['browseEndpoint']?['browseId'] as String?;
        if (browseId == null) continue;
        pageType =
            nav?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType']
                as String? ??
            pageType;
        cards.add(
          AlbumCard(
            browseId: browseId,
            title: _runsText(row['title']) ?? '',
            subtitle: _runsText(row['subtitle']) ?? '',
            thumbnailUrl: _thumbUrl(row['thumbnailRenderer']) ?? '',
          ),
        );
      }
      final lower = (carTitle ?? '').toLowerCase();
      final header =
          carousel['header']?['musicCarouselShelfBasicHeaderRenderer'];
      if (pageType.contains('ARTIST')) {
        similar.addAll(cards);
      } else if (lower.contains('album')) {
        albums.addAll(cards);
        albumsMore ??= _moreLink(header, carTitle ?? 'Albums');
        // Niente confronto su 'ep' nudo: serviva quando la sezione si
        // chiamava "Singoli ed EP", ma entrambe le lingue dicono gia'
        // "single"/"singol", e in inglese due lettere cosi' comuni
        // pescherebbero titoli di sezione che non c'entrano.
      } else if (lower.contains('single') || lower.contains('singol')) {
        singles.addAll(cards);
        singlesMore ??= _moreLink(header, carTitle ?? 'Singles');
      } else if (lower.contains('playlist')) {
        playlists.addAll(cards);
      }
    }

    // The artist browse response omits durations — resolve them lazily.
    final enriched = await enrichDurations(topSongs);

    return ArtistPage(
      browseId: browseId,
      name: name ?? 'Artist',
      thumbnailUrl: thumbUrl,
      topSongs: enriched,
      albums: albums,
      singles: singles,
      playlists: playlists,
      similar: similar,
      monthlyListeners: monthlyListeners,
      topSongsMore: topSongsMore,
      albumsMore: albumsMore,
      singlesMore: singlesMore,
    );
  }

  /// Finds the album containing [videoId] by browsing the artist's albums.
  /// Returns (browseId, title) or null if not found.
  Future<(String, String)?> getAlbumForSong(String videoId) async {
    // Prima si scaricava la pagina dell'artista e poi OGNI suo album e
    // singolo, cercando il brano dentro ciascuno: decine di richieste, e
    // impossibile senza un artistId — che i brani della radio non hanno,
    // ed e' il motivo per cui li' l'album non compariva mai. La coda
    // watch-next porta gia' il collegamento nel byline del brano stesso.
    try {
      final data = await _post(_nextUrl, {
        'context': _context,
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'isAudioOnly': true,
      });
      final contents =
          data['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents']
              as List? ??
          const [];
      for (final item in contents) {
        final r = (item as Map)['playlistPanelVideoRenderer'];
        if (r == null) continue;
        final id =
            r['videoId'] as String? ??
            r['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
        if (id != videoId) continue;
        return _albumFromByline(r['longBylineText']);
      }
    } catch (e) {
      developer.log('getAlbumForSong fallito: $e');
    }
    return null;
  }

  /// Fetches an album page with its track list.
  /// Il giorno in cui e' uscito un album o un singolo.
  ///
  /// La pagina artista da' al massimo l'anno, e ai singoli nemmeno quello.
  /// La data esatta c'e' nel brano: la pubblicazione del suo primo pezzo
  /// sul canale dell'artista, che e' il giorno dell'uscita. Due richieste —
  /// la pagina del disco e il player del primo brano — quindi chi la usa
  /// la conserva.
  Future<DateTime?> releaseDateOf(String albumBrowseId) async {
    final album = await getAlbumPage(albumBrowseId);
    final first = album.tracks.firstOrNull;
    if (first == null) return null;
    final data = await _post(_playerUrl, {
      'context': _context,
      'videoId': first.id,
    });
    final raw =
        data['microformat']?['microformatDataRenderer']?['publishDate'] ??
        data['microformat']?['microformatDataRenderer']?['uploadDate'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  Future<Album> getAlbumPage(String browseId) async {
    final data = await _browse(browseId);

    final mf = data['microformat']?['microformatDataRenderer'];
    final title = _text(mf?['title']) ?? 'Album';
    final description = (mf?['description'] as String?) ?? '';
    final descParts = description
        .split('•')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    // description looks like "Album • Tame Impala": artist is the last part.
    final artist = descParts.isNotEmpty ? descParts.last : '';
    var thumbUrl = _thumbUrl(mf?['thumbnail']) ?? '';

    // Header detail (year, track count)
    final headerSec =
        data['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0]?['musicResponsiveHeaderRenderer'];
    final subtitle = _runsJoined(headerSec?['subtitle']);
    // "14 brani • 1 ora e 1 minuto": la durata totale c'e' gia', scritta e
    // tradotta da YouTube Music. Mostravamo solo il conteggio dei brani,
    // che e' la meta' meno interessante delle due.
    final secondLine = _runsJoined(headerSec?['secondSubtitle']);
    String? year;
    String? kind;
    if (subtitle != null) {
      final parts = subtitle.split('•').map((s) => s.trim()).toList();
      if (parts.first.isNotEmpty) kind = parts.first;
      if (parts.length > 1) year = parts[1];
    }
    if (headerSec != null && thumbUrl.isEmpty) {
      thumbUrl = _thumbUrl(headerSec?['thumbnail']) ?? '';
    }

    // Tracks
    final shelf =
        data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']?[0]?['musicShelfRenderer'];
    final tracks = _tracksFromShelf(
      shelf,
      fallbackArtist: artist,
      artistId: null,
      // Ogni traccia del disco ha la copertina del disco.
      fallbackThumb: thumbUrl.isEmpty ? null : thumbUrl,
    );

    // L'id dell'artista, quando il byline lo collega: con questo il nome
    // sulla pagina dell'album apre la pagina giusta invece di doverla
    // cercare per nome.
    final artistLink =
        _artistFromByline(headerSec?['subtitle']) ??
        _artistFromByline(headerSec?['straplineTextOne']);

    return Album(
      browseId: browseId,
      title: title,
      artist: artistLink?.$2 ?? artist,
      artistId: artistLink?.$1,
      year: year,
      kind: kind,
      summary: secondLine,
      thumbnailUrl: thumbUrl,
      tracks: _seen(tracks),
      shelves: _albumShelves(data),
    );
  }

  /// Gli scaffali in fondo alla pagina di un album, dovunque stiano.
  ///
  /// Si cercano in tutta la risposta e non a un percorso fisso: la pagina
  /// album e' a due colonne, e gli scaffali stanno nella seconda, dietro
  /// l'elenco dei brani.
  List<(String, List<AlbumCard>)> _albumShelves(Map<String, dynamic> data) {
    final out = <(String, List<AlbumCard>)>[];
    void visit(dynamic node) {
      if (node is Map) {
        final shelf = node['musicCarouselShelfRenderer'];
        if (shelf is Map) {
          final title = _runsText(
            shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title'],
          );
          final cards = <AlbumCard>[];
          for (final item in shelf['contents'] as List? ?? const []) {
            final card = _cardFrom(
              (item as Map)['musicTwoRowItemRenderer'],
              '',
            );
            if (card != null) cards.add(card);
          }
          if (title != null && cards.isNotEmpty) out.add((title, cards));
          return;
        }
        node.values.forEach(visit);
      } else if (node is List) {
        node.forEach(visit);
      }
    }

    visit(data['contents']);
    return out;
  }

  /// Fetches a playlist page with its track list.
  Future<Playlist> getPlaylistPage(String browseId) async {
    final data = await _browse(browseId);
    final mf = data['microformat']?['microformatDataRenderer'];
    final title = _text(mf?['title']) ?? 'Playlist';
    final thumbUrl = _thumbUrl(mf?['thumbnail']) ?? '';

    final shelf =
        data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']?[0]?['musicPlaylistShelfRenderer'];

    final tracks = <Track>[];
    final items = shelf?['contents'] as List? ?? const [];
    for (final item in items) {
      final r = (item as Map)['musicResponsiveListItemRenderer'];
      if (r == null) continue;
      final videoId = r['playlistItemData']?['videoId'] as String?;
      if (videoId == null) continue;
      tracks.add(
        _trackFromItem(
          r,
          videoId,
          fallbackArtist: '',
          fallbackThumb: thumbUrl.isEmpty ? null : thumbUrl,
        ),
      );
    }

    return Playlist(
      browseId: browseId,
      title: title,
      thumbnailUrl: thumbUrl,
      tracks: _seen(tracks),
    );
  }

  /// Fetches suggested songs for a video: the "up next" queue panel when
  /// present, otherwise a fallback search by artist.
  Future<List<Track>> getUpNext(String videoId, {String? artist}) async {
    final tracks = <Track>[];
    try {
      // Il solo videoId non basta: l'endpoint `next` restituisce la coda
      // solo se gli si chiede esplicitamente la radio costruita attorno a
      // quel brano. Senza playlistId tornava vuoto e scattava sempre il
      // ripiego, che cerca per nome dell'artista — ed e' il motivo per cui
      // fra i "suggeriti" comparivano brani con lo stesso TITOLO di artisti
      // diversi invece di brani affini.
      final data = await _post(_nextUrl, {
        'context': _context,
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
        'params': 'wAEB',
      });
      final contents =
          data['contents']?['singleColumnMusicWatchNextResultsRenderer']?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents']
              as List? ??
          const [];
      for (final item in contents) {
        // Guardia per SINGOLO elemento. Prima il try avvolgeva l'intero
        // ciclo: bastava una voce con un campo in un formato inatteso per
        // far abortire il parsing e restituire solo i brani gia' accumulati.
        // La radio ne manda 50 e ne arrivava uno.
        try {
          final r = (item as Map)['playlistPanelVideoRenderer'];
          if (r == null) continue;
          final vidRaw =
              r['videoId'] as String? ??
              r['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
          if (vidRaw == null || vidRaw == videoId) continue;
          final vid = vidRaw; // skip the current song
          final thumbs = r['thumbnail']?['thumbnails'];
          final thumb = thumbs is List && thumbs.isNotEmpty
              ? (thumbs.last as Map)['url'] as String?
              : null;
          // Durata: il pannello watch-next espone lengthSeconds (int) oppure
          // un testo "3:32" in timeText/lengthText. Senza, resta --:--.
          // Qui il pannello non manda `lengthSeconds`: la durata arriva come
          // `lengthText`, che e' un nodo di testo InnerTube (runs/simpleText),
          // non una stringa. Il cast diretto a String lanciava.
          Duration? dur;
          final lenSec = r['lengthSeconds'];
          if (lenSec is num && lenSec > 0) {
            dur = Duration(seconds: lenSec.toInt());
          } else {
            dur = _parseDuration(
              _plainText(r['lengthText']) ?? _plainText(r['timeText']),
            );
          }
          // L'album e' gia' qui dentro: prenderlo adesso evita di doverlo
          // cercare dopo con una richiesta in piu'.
          final album = _albumFromByline(r['longBylineText']);
          tracks.add(
            Track(
              id: vid,
              title: _cleanTitle(_runsText(r['title'])),
              author: _runsText(r['longBylineText']) ?? 'Unknown',
              albumId: album?.$1,
              albumName: album?.$2,
              isExplicit: _isExplicit(r as Map),
              duration: dur,
              thumbnailUrl:
                  thumb ?? 'https://img.youtube.com/vi/$vid/hqdefault.jpg',
            ),
          );
        } catch (e) {
          developer.log('getUpNext: elemento ignorato: $e');
        }
      }
    } catch (e) {
      developer.log('getUpNext queue fallito: $e');
    }

    // Fallback: songs by the same artist.
    if (tracks.isEmpty && artist != null && artist.trim().isNotEmpty) {
      try {
        developer.log('getUpNext: coda vuota, ripiego sulla ricerca artista');
        final name = artist.trim().toLowerCase();
        final byArtist = (await search(artist.trim())).songs;
        // Si tengono solo i brani DI quell'artista. Senza filtro la ricerca
        // restituiva qualunque cosa avesse un titolo simile al suo nome.
        final own = byArtist.where(
          (t) => t.id != videoId && t.author.toLowerCase().contains(name),
        );
        tracks.addAll(
          own.isNotEmpty ? own : byArtist.where((t) => t.id != videoId),
        );
      } catch (e) {
        developer.log('getUpNext search fallito: $e');
      }
    }
    // Shyness guardia: anche se lengthSeconds è assente, riempi le durate
    // mancanti in background dal video page (stesso percorso di search/favorites).
    return enrichDurations(tracks);
  }

  // ---------------------------------------------------------------------
  // Lyrics (LRCLIB for synced LRC, Genius as free fallback)
  // ---------------------------------------------------------------------

  /// Fetches lyrics for a track. Returns null when not found.
  ///
  /// Tries LRCLIB first (free, no key, synced LRC timestamps); when the
  /// song is missing there it falls back to Genius (free web scraping),
  /// which returns plain-text lyrics.
  Future<Lyrics?> getLyrics({
    required String title,
    required String artist,
  }) async {
    try {
      final lrc = await _lrclibLyrics(title: title, artist: artist);
      if (lrc != null) return lrc;
    } catch (e) {
      developer.log('LRCLIB fallito: $e');
    }
    try {
      return await _geniusLyrics(title: title, artist: artist);
    } catch (e) {
      developer.log('Genius fallito: $e');
      return null;
    }
  }

  Future<Lyrics?> _lrclibLyrics({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.parse(
      _lrclibUrl,
    ).replace(queryParameters: {'track_name': title, 'artist_name': artist});
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final list = jsonDecode(resp.body) as List;
    if (list.isEmpty) return null;

    for (final entry in list) {
      final e = entry as Map;
      final raw = e['syncedLyrics'] as String? ?? e['plainLyrics'] as String?;
      if (raw == null || raw.isEmpty) continue;
      return Lyrics.parse(
        raw,
        title: e['trackName'] as String? ?? title,
        artist: e['artistName'] as String? ?? artist,
      );
    }
    return null;
  }

  static const _geniusSearchUrl = 'https://genius.com/api/search/multi';
  static const _browserUA =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// Fetches plain-text lyrics from Genius (free, unofficial web scraping).
  Future<Lyrics?> _geniusLyrics({
    required String title,
    required String artist,
  }) async {
    final searchUri = Uri.parse(
      _geniusSearchUrl,
    ).replace(queryParameters: {'q': '$title $artist'});
    final searchResp = await http
        .get(
          searchUri,
          headers: {'User-Agent': _browserUA, 'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 10));
    if (searchResp.statusCode != 200) return null;

    final data = jsonDecode(searchResp.body) as Map;
    final sections = (data['response']?['sections'] as List?) ?? const [];

    // Pick the best song hit: exact artist match wins, else the first song.
    String? path;
    String? bestTitle;
    String? bestArtist;
    var bestScore = -1;
    for (final sec in sections) {
      final type = (sec as Map)['type'];
      if (type != 'song' && type != 'top_hit') continue;
      final hits = (sec['hits'] as List?) ?? const [];
      for (final h in hits) {
        final r = (h as Map)['result'] as Map;
        final t = (r['title'] as String?) ?? '';
        final a = (r['primary_artist']?['name'] as String?) ?? '';
        final p = r['path'] as String?;
        if (p == null) continue;
        var score = 0;
        if (a.toLowerCase().contains(artist.toLowerCase()) ||
            artist.toLowerCase().contains(a.toLowerCase())) {
          score += 2;
        }
        if (t.toLowerCase().contains(title.toLowerCase()) ||
            title.toLowerCase().contains(t.toLowerCase())) {
          score += 1;
        }
        if (score > bestScore) {
          bestScore = score;
          path = p;
          bestTitle = t;
          bestArtist = a;
        }
      }
    }
    if (path == null || bestScore < 0) return null;

    final pageResp = await http
        .get(
          Uri.parse('https://genius.com$path'),
          headers: {'User-Agent': _browserUA, 'Accept': 'text/html'},
        )
        .timeout(const Duration(seconds: 12));
    if (pageResp.statusCode != 200) return null;

    final html = _geniusLyricsHtml(pageResp.body);
    if (html == null) return null;
    final text = _stripHtml(html);
    if (text.isEmpty) return null;

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return Lyrics(
      title: bestTitle ?? title,
      artist: bestArtist ?? artist,
      lines: [for (final l in lines) LyricsLine(time: Duration.zero, text: l)],
    );
  }

  /// Extracts the lyrics HTML from a Genius song page's preloaded state
  /// (`window.__PRELOADED_STATE__ = JSON.parse('...')`).
  String? _geniusLyricsHtml(String pageBody) {
    const marker = '__PRELOADED_STATE__';
    final markerIdx = pageBody.indexOf(marker);
    if (markerIdx < 0) return null;
    const open = "JSON.parse('";
    final start = pageBody.indexOf(open, markerIdx);
    if (start < 0) return null;
    final jsonStart = start + open.length;
    final end = pageBody.indexOf("');", jsonStart);
    if (end < 0) return null;
    final raw = pageBody.substring(jsonStart, end);

    try {
      final jsonText = _jsUnescape(raw);
      final pre = jsonDecode(jsonText) as Map<String, dynamic>;
      return (pre['songPage']?['lyricsData']?['body']?['html'] as String?);
    } catch (e) {
      developer.log('Genius preloaded state non decodificabile: $e');
      return null;
    }
  }

  /// Unescapes a JavaScript single-quoted string literal.
  String _jsUnescape(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == r'\' && i + 1 < s.length) {
        final n = s[i + 1];
        if (n == 'n') {
          b.write('\n');
          i++;
        } else if (n == 't') {
          b.write('\t');
          i++;
        } else if (n == 'r') {
          b.write('\r');
          i++;
        } else if (n == r'\') {
          b.write(r'\');
          i++;
        } else if (n == '"') {
          b.write('"');
          i++;
        } else if (n == "'") {
          b.write("'");
          i++;
        } else if (n == 'u' && i + 5 < s.length) {
          b.writeCharCode(int.parse(s.substring(i + 2, i + 6), radix: 16));
          i += 5;
        } else {
          b.write(n);
          i++;
        }
      } else {
        b.write(c);
      }
    }
    return b.toString();
  }

  /// Converts the Genius lyrics HTML (with <br> and <a> tags) to plain text.
  String _stripHtml(String html) {
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    text = _htmlUnescape(text);
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Decodes the HTML entities Genius emits (&quot;, &#x27;, &amp;, …).
  String _htmlUnescape(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '&') {
        final semi = s.indexOf(';', i);
        if (semi > i && semi - i <= 10) {
          final ent = s.substring(i + 1, semi);
          String? rep;
          if (ent == 'quot') {
            rep = '"';
          } else if (ent == 'amp') {
            rep = '&';
          } else if (ent == 'apos' || ent == '#39') {
            rep = "'";
          } else if (ent == 'lt') {
            rep = '<';
          } else if (ent == 'gt') {
            rep = '>';
          } else if (ent == 'nbsp') {
            rep = ' ';
          } else if (ent == 'hellip') {
            rep = '…';
          } else if (ent == 'mdash') {
            rep = '—';
          } else if (ent == 'ndash') {
            rep = '–';
          } else if (ent == 'rsquo') {
            rep = '’';
          } else if (ent == 'lsquo') {
            rep = '‘';
          } else if (ent == 'ldquo') {
            rep = '“';
          } else if (ent == 'rdquo') {
            rep = '”';
          } else if (ent.startsWith('#x')) {
            final cp = int.tryParse(ent.substring(2), radix: 16);
            if (cp != null) rep = String.fromCharCode(cp);
          } else if (ent.startsWith('#')) {
            final cp = int.tryParse(ent.substring(1));
            if (cp != null) rep = String.fromCharCode(cp);
          }
          if (rep != null) {
            b.write(rep);
            i = semi;
            continue;
          }
        }
      }
      b.write(c);
    }
    return b.toString();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// L'album citato nel byline di un brano, come (browseId, titolo).
  ///
  /// YouTube Music scrive il byline come "Artista • Album • Anno" e mette il
  /// collegamento sul pezzo giusto: si riconosce dal pageType dell'endpoint,
  /// non dalla posizione, che cambia quando un campo manca.
  (String, String)? _albumFromByline(dynamic node) =>
      _linkFromRuns(node, 'ALBUM');

  /// L'artista collegato in un byline, come (browseId, nome).
  (String, String)? _artistFromByline(dynamic node) =>
      _linkFromRuns(node, 'ARTIST');

  /// Il primo run che punta a una pagina del tipo dato.
  ///
  /// Si riconosce dal pageType dell'endpoint e non dalla posizione, che
  /// cambia quando un campo manca.
  (String, String)? _linkFromRuns(dynamic node, String pageTypeFragment) {
    for (final run in _runs(node)) {
      final endpoint = (run as Map)['navigationEndpoint']?['browseEndpoint'];
      if (endpoint == null) continue;
      final pageType =
          endpoint['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType']
              as String?;
      if (pageType == null || !pageType.contains(pageTypeFragment)) continue;
      final id = endpoint['browseId'] as String?;
      final title = run['text'] as String?;
      if (id != null && title != null && title.trim().isNotEmpty) {
        return (id, title.trim());
      }
    }
    return null;
  }

  /// Le riproduzioni dichiarate da una riga, quando ci sono.
  ///
  /// Si cerca la colonna per contenuto e non per indice: nelle playlist la
  /// terza colonna e' il nome dell'album, e scriverlo al posto di un numero
  /// sarebbe peggio che non scrivere niente.
  static final _playsRe = RegExp(
    r'riprodu|ascolt|visualizzaz|plays|views',
    caseSensitive: false,
  );

  String? _playsFrom(Map r) {
    final flex = r['flexColumns'] as List? ?? const [];
    for (var i = 1; i < flex.length; i++) {
      final t = _flexText(r, i);
      if (t == null) continue;
      if (_playsRe.hasMatch(t) && RegExp(r'\d').hasMatch(t)) return t;
    }
    return null;
  }

  /// Il nome dell'album citato in una riga, quando la riga lo porta.
  String? _albumNameFrom(Map r) {
    final flex = r['flexColumns'] as List? ?? const [];
    for (var i = 2; i < flex.length; i++) {
      final t = _flexText(r, i);
      if (t == null || t.isEmpty) continue;
      if (_playsRe.hasMatch(t)) continue;
      return t;
    }
    return null;
  }

  /// Se la riga porta il bollino di contenuto esplicito.
  bool _isExplicit(Map r) {
    for (final b in (r['badges'] as List?) ?? const []) {
      final icon =
          (b as Map)['musicInlineBadgeRenderer']?['icon']?['iconType']
              as String?;
      if (icon != null && icon.contains('EXPLICIT')) return true;
    }
    return false;
  }

  /// Il titolo pronto da mostrare.
  ///
  /// Normalizzato qui, dove il brano nasce, e non nei trenta punti che lo
  /// disegnano: cosi' vale anche per i preferiti salvati, per i metadati
  /// mandati al sistema e per la ricerca dei testi, che su un titolo
  /// raddoppiato trovava meno riscontri.
  String _cleanTitle(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return 'Unknown';
    return ArtistNames.dedupeFeatGroups(t);
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
  ) async {
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('YouTube Music answered with code ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// I `params` non sono facoltativi per gusto: le sezioni complete della
  /// pagina artista non si servono col solo browseId, e senza tornano
  /// indietro vuote invece di dare errore.
  Future<Map<String, dynamic>> _browse(String browseId, {String? params}) =>
      _post(_browseUrl, {
        'context': _context,
        'browseId': browseId,
        if (params != null) 'params': params,
      });

  /// Il "mostra tutto" di uno scaffale, quando c'e'.
  ///
  /// Il bottone sta in due posti diversi a seconda del tipo di scaffale:
  /// `moreContentButton` sui caroselli di copertine, `bottomEndpoint` sullo
  /// scaffale dei brani. Sono due nomi per la stessa cosa.
  SectionLink? _moreLink(dynamic node, String title, {bool songs = false}) {
    final endpoint =
        node?['moreContentButton']?['buttonRenderer']?['navigationEndpoint'] ??
        node?['bottomEndpoint'];
    final browse = endpoint?['browseEndpoint'];
    final id = browse?['browseId'] as String?;
    if (id == null) return null;
    return SectionLink(
      title: title,
      browseId: id,
      params: browse?['params'] as String?,
      songs: songs,
    );
  }

  /// Cosa mostrare a chi apre la ricerca senza aver ancora scritto.
  ///
  /// Due richieste, non una: "in tendenza" e le nuove uscite stanno in
  /// `FEmusic_explore`, le classifiche in `FEmusic_charts`. Partono insieme
  /// perche' una non dipende dall'altra, e una delle due che fallisce non
  /// deve portarsi via anche il contenuto dell'altra.
  ///
  /// Le classifiche del paese escono gia' giuste senza chiedere niente:
  /// e' il `gl` del contesto a deciderlo. Quelle mondiali invece vogliono
  /// il paese scelto a mano, e non come `params`: il menu dei paesi e' un
  /// form, e si compila con `formData.selectedValues`. Il codice del
  /// mondo e' `ZZ` — sta scritto, in chiaro, dentro la chiave base64
  /// dell'opzione "Global" del menu, accanto a `IT` di quella italiana.
  Future<ExplorePage> getExplore() async {
    final results = await Future.wait([
      _browse('FEmusic_explore').catchError((_) => <String, dynamic>{}),
      _browse('FEmusic_charts').catchError((_) => <String, dynamic>{}),
      _charts('ZZ').catchError((_) => <String, dynamic>{}),
    ]);

    final trending = <Track>[];
    final newReleases = <AlbumCard>[];
    final charts = <AlbumCard>[];
    final globalCharts = <AlbumCard>[];

    // Si riconoscono dal contenuto, non dal titolo della sezione: "In
    // tendenza" cambia con la lingua, mentre un videoId o un
    // MUSIC_PAGE_TYPE_PLAYLIST no. E la lingua l'abbiamo appena cambiata.
    for (final section in _sections(results[0])) {
      final items =
          section['musicCarouselShelfRenderer']?['contents'] as List? ??
          const [];
      for (final item in items) {
        final map = item as Map;
        final row = map['musicResponsiveListItemRenderer'];
        if (row != null) {
          final videoId = row['playlistItemData']?['videoId'] as String?;
          if (videoId != null) {
            trending.add(
              _withPlaysSplit(_trackFromItem(row, videoId, fallbackArtist: '')),
            );
          }
          continue;
        }
        final card = _cardFrom(map['musicTwoRowItemRenderer'], 'ALBUM');
        if (card != null) newReleases.add(card);
      }
    }

    for (final (i, into) in [(1, charts), (2, globalCharts)]) {
      for (final section in _sections(results[i])) {
        final items =
            section['musicCarouselShelfRenderer']?['contents'] as List? ??
            const [];
        for (final item in items) {
          final card = _cardFrom(
            (item as Map)['musicTwoRowItemRenderer'],
            'PLAYLIST',
          );
          if (card != null) into.add(card);
        }
      }
    }

    // "In tendenza" su YouTube Music sono quasi tutti videoclip: titoli come
    // "Sfera Ebbasta - Lontano (Official Video)" su un fotogramma. Si
    // rivestono da canzone i primi, quelli che la pagina mostra, tutti
    // insieme e con un tetto: una ricerca lenta non deve tenere ferma la
    // pagina, al peggio quel brano resta com'era.
    final withDurations = await enrichDurations(trending);
    final shown = withDurations.take(8).toList();
    final dressedShown = await Future.wait([
      for (final t in shown)
        songVersionFor(t).then((s) => s ?? t).catchError((_) => t),
    ]).timeout(const Duration(seconds: 5), onTimeout: () => shown);

    return ExplorePage(
      trending: [...dressedShown, ...withDurations.skip(8)],
      charts: charts,
      globalCharts: globalCharts,
      newReleases: newReleases,
    );
  }

  /// Umori e generi, con il loro colore.
  Future<List<CategoryGroup>> getCategories() async {
    final data = await _browse('FEmusic_moods_and_genres');
    final out = <CategoryGroup>[];
    for (final section in _sections(data)) {
      final grid = section['gridRenderer'];
      if (grid == null) continue;
      final items = <BrowseCategory>[];
      for (final item in (grid['items'] as List?) ?? const []) {
        final b = (item as Map)['musicNavigationButtonRenderer'];
        final params =
            b?['clickCommand']?['browseEndpoint']?['params'] as String?;
        final title = _runsText(b?['buttonText']);
        if (params == null || title == null) continue;
        items.add(
          BrowseCategory(
            title: title,
            color: b['solid']?['leftStripeColor'] as int? ?? 0xFF3A3A46,
            params: params,
          ),
        );
      }
      if (items.isEmpty) continue;
      out.add(
        CategoryGroup(
          title:
              _runsText(grid['header']?['gridHeaderRenderer']?['title']) ?? '',
          items: items,
        ),
      );
    }
    return out;
  }

  /// Le playlist di una categoria, nelle file in cui YouTube Music le
  /// raggruppa: "Coffee shop blends", "Unwind + explore".
  Future<List<(String, List<AlbumCard>)>> getCategory(String params) async {
    final data = await _browse(
      'FEmusic_moods_and_genres_category',
      params: params,
    );
    final out = <(String, List<AlbumCard>)>[];
    for (final section in _sections(data)) {
      final shelf =
          section['musicCarouselShelfRenderer'] ?? section['gridRenderer'];
      if (shelf == null) continue;
      final cards = <AlbumCard>[
        for (final item
            in (shelf['contents'] ?? shelf['items']) as List? ?? const [])
          ?_cardFrom((item as Map)['musicTwoRowItemRenderer'], 'PLAYLIST'),
      ];
      if (cards.isEmpty) continue;
      final title =
          _runsText(
            shelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title'],
          ) ??
          _runsText(shelf['header']?['gridHeaderRenderer']?['title']) ??
          '';
      out.add((title, cards));
    }
    return out;
  }

  /// Le classifiche di un paese. `ZZ` e' il mondo.
  Future<Map<String, dynamic>> _charts(String country) => _post(_browseUrl, {
    'context': _context,
    'browseId': 'FEmusic_charts',
    'formData': {
      'selectedValues': [country],
    },
  });

  /// Separa l'artista dal conteggio, quando arrivano nella stessa colonna.
  ///
  /// Le righe di "in tendenza" scrivono "Geolier • 3,1 Mln views" tutto
  /// dentro la colonna dell'autore, mentre altrove il conteggio ha una
  /// colonna sua. Lasciato com'e' finirebbe a schermo come nome
  /// dell'artista; separato diventa anche un dato che la riga sa gia'
  /// mostrare.
  static final _playsTail = RegExp(
    r'^[\d.,]+\s*\S*\s*(?:views|plays|visualizzazioni|riproduzioni)\b',
    caseSensitive: false,
  );

  Track _withPlaysSplit(Track t) {
    final parts = t.author.split(' • ');
    if (parts.length < 2) return t;
    final tail = parts.last.trim();
    if (!_playsTail.hasMatch(tail)) return t;
    return t.copyWith(
      author: parts.sublist(0, parts.length - 1).join(' • ').trim(),
      plays: t.plays ?? tail,
    );
  }

  /// Una scheda, ma solo se punta al tipo di pagina chiesto.
  ///
  /// Il filtro non e' pignoleria: gli scaffali dei video portano schede che
  /// non hanno nessun browseId — si aprono su un watch endpoint — e
  /// finirebbero nella griglia come riquadri che non si possono toccare.
  AlbumCard? _cardFrom(dynamic row, String pageType) {
    final nav = row?['navigationEndpoint']?['browseEndpoint'];
    final id = nav?['browseId'] as String?;
    if (id == null) return null;
    final type =
        nav?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType']
            as String? ??
        '';
    if (!type.contains(pageType)) return null;
    return AlbumCard(
      browseId: id,
      title: _runsText(row['title']) ?? '',
      subtitle: cardSubtitle(_runsJoined(row['subtitle']) ?? ''),
      thumbnailUrl: _thumbUrl(row['thumbnailRenderer']) ?? '',
    );
  }

  /// Il sottotitolo di una scheda, intero e con l'artista davanti.
  ///
  /// Si leggeva solo il primo pezzo, e per un disco il primo pezzo e' il
  /// tipo: le uscite nuove della ricerca dicevano "Single" e basta, senza
  /// l'artista. YouTube scrive "Single • Elysia Vale"; qui diventa
  /// "Elysia Vale · Single", perche' chi l'ha fatto e' la cosa che si cerca.
  static String cardSubtitle(String raw) {
    final parts = raw
        .split('•')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return parts.join();
    const kinds = {'album', 'single', 'ep'};
    if (kinds.contains(parts.first.toLowerCase())) {
      return [...parts.skip(1), parts.first].join(' · ');
    }
    return parts.join(' · ');
  }

  /// Una sezione completa fatta di copertine: tutti i singoli, tutti gli
  /// album. Torna una griglia invece di un carosello.
  Future<List<AlbumCard>> getSectionGrid(
    String browseId, {
    String? params,
  }) async {
    final data = await _browse(browseId, params: params);
    final sections = _sections(data);
    final out = <AlbumCard>[];
    for (final section in sections) {
      final items =
          (section['gridRenderer']?['items'] ??
                  section['musicCarouselShelfRenderer']?['contents'])
              as List? ??
          const [];
      for (final item in items) {
        final row = (item as Map)['musicTwoRowItemRenderer'];
        final id =
            row?['navigationEndpoint']?['browseEndpoint']?['browseId']
                as String?;
        if (id == null) continue;
        out.add(
          AlbumCard(
            browseId: id,
            title: _runsText(row['title']) ?? '',
            subtitle: _runsText(row['subtitle']) ?? '',
            thumbnailUrl: _thumbUrl(row['thumbnailRenderer']) ?? '',
          ),
        );
      }
    }
    return out;
  }

  /// Una sezione completa fatta di brani: i "top songs" per intero.
  ///
  /// Dietro c'e' una playlist, ma non la si puo' passare a
  /// [getPlaylistPage]: quella legge il layout a due colonne, mentre con i
  /// `params` la stessa richiesta torna a colonna singola.
  Future<List<Track>> getSectionSongs(String browseId, {String? params}) async {
    final data = await _browse(browseId, params: params);
    final tracks = <Track>[];
    for (final section in _sections(data)) {
      final items =
          (section['musicPlaylistShelfRenderer']?['contents'] ??
                  section['musicShelfRenderer']?['contents'])
              as List? ??
          const [];
      for (final item in items) {
        final r = (item as Map)['musicResponsiveListItemRenderer'];
        if (r == null) continue;
        final videoId = r['playlistItemData']?['videoId'] as String?;
        if (videoId == null) continue;
        tracks.add(_trackFromItem(r, videoId, fallbackArtist: ''));
      }
    }
    return enrichDurations(tracks);
  }

  /// The section list of a browse response (both layouts).
  List<Map> _sections(Map<String, dynamic> data) {
    final contents = data['contents'];
    final single =
        contents?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
    if (single is List) return single.cast<Map>();
    return const [];
  }

  List<Track> _tracksFromShelf(
    dynamic shelf, {
    String? artistId,
    String fallbackArtist = '',
    String? fallbackThumb,
  }) {
    final tracks = <Track>[];
    final items = shelf?['contents'] as List? ?? const [];
    for (final item in items) {
      final r = (item as Map)['musicResponsiveListItemRenderer'];
      if (r == null) continue;
      final videoId = r['playlistItemData']?['videoId'] as String?;
      if (videoId == null) continue;
      tracks.add(
        _trackFromItem(
          r,
          videoId,
          fallbackArtist: fallbackArtist,
          artistId: artistId,
          fallbackThumb: fallbackThumb,
        ),
      );
    }
    return tracks;
  }

  Track _trackFromItem(
    Map r,
    String videoId, {
    required String fallbackArtist,
    String? artistId,
    String? fallbackThumb,
  }) {
    _noteIfSong(r, videoId);
    final artist = _flexTextFull(r, 1) ?? fallbackArtist;

    // Duration lives in fixedColumns (e.g. "4:59").
    final fixed = r['fixedColumns'] as List? ?? const [];
    final durText = _runsText(
      fixed.isNotEmpty
          ? ((fixed[0]
                as Map)['musicResponsiveListItemFixedColumnRenderer']?['text'])
          : null,
    );

    return Track(
      id: videoId,
      title: _cleanTitle(_flexText(r, 0)),
      author: artist.isEmpty ? 'Unknown' : artist,
      duration: _parseDuration(durText),
      // La copertina del brano, poi quella della pagina, e solo per ultimo
      // il fotogramma del video. Quel fotogramma e' 16:9: ritagliato in un
      // quadrato mostra una scena del videoclip con le bande nere, non la
      // copertina — ed era quello che si vedeva in ogni album, perche' li'
      // le tracce non portano una copertina propria (ce l'ha il disco).
      thumbnailUrl:
          _itemThumb(r) ??
          fallbackThumb ??
          'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      artistId: artistId,
      plays: _playsFrom(r),
      isExplicit: _isExplicit(r),
    );
  }

  /// First text run of the given flex column (0 = title, 1 = subtitle).
  String? _flexText(Map r, int index) {
    final flex = r['flexColumns'] as List? ?? const [];
    if (flex.length <= index) return null;
    return _runsText(
      ((flex[index]
          as Map)['musicResponsiveListItemFlexColumnRenderer']?['text']),
    );
  }

  /// Una colonna letta per intero, non solo il suo primo run.
  ///
  /// Serve per gli interpreti: "Shiva e Kid Yugi" arriva come tre run
  /// ("Shiva", " e ", "Kid Yugi") perche' i nomi sono collegati uno per uno,
  /// e prendendo solo il primo di un brano in feat restava un nome solo.
  String? _flexTextFull(Map r, int index) {
    final flex = r['flexColumns'] as List? ?? const [];
    if (flex.length <= index) return null;
    return _runsJoined(
      ((flex[index]
          as Map)['musicResponsiveListItemFlexColumnRenderer']?['text']),
    );
  }

  /// Joins the "text" fields of a "runs" array.
  List<dynamic> _runs(dynamic node) {
    if (node is! Map) return const [];
    final runs = node['runs'];
    if (runs is! List) return const [];
    return runs;
  }

  /// Extracts the first "text" from a runs node (or null).
  /// Il testo di un nodo InnerTube, in qualunque delle tre forme in cui
  /// arriva: stringa nuda, `{runs: [...]}` oppure `{simpleText: ...}`.
  /// Le tre convivono nella stessa risposta, quindi leggerne una sola
  /// significa lanciare sulle altre due.
  String? _plainText(dynamic node) {
    if (node is String) return node;
    final fromRuns = _runsText(node);
    if (fromRuns != null) return fromRuns;
    if (node is Map) return node['simpleText'] as String?;
    return null;
  }

  String? _runsText(dynamic node) {
    final runs = _runs(node);
    if (runs.isEmpty) return null;
    return (runs.first as Map)['text'] as String?;
  }

  /// Text from either a plain string or a "runs" node.
  String? _text(dynamic node) {
    if (node is String) return node;
    return _runsText(node);
  }

  /// Joins all run texts of a "runs" node (e.g. "Album • 2025").
  String? _runsJoined(dynamic node) {
    final runs = _runs(node);
    if (runs.isEmpty) return null;
    return runs.map((r) => (r as Map)['text'] as String? ?? '').join();
  }

  /// Joins a runs list into "Text • Text" form.
  String? _joinedRuns(List<dynamic> runs) {
    if (runs.isEmpty) return null;
    final parts = runs
        .map((r) => (r as Map)['text'] as String? ?? '')
        .where((t) => t.trim().isNotEmpty && t.trim() != '•')
        .toList();
    return parts.isEmpty ? null : parts.join(' • ');
  }

  /// Thumbnail URL of a musicResponsiveListItemRenderer (or null).
  String? _itemThumb(Map r) {
    final thumbs =
        r['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
            as List?;
    if (thumbs is List && thumbs.isNotEmpty) {
      return (thumbs.last as Map)['url'] as String?;
    }
    return null;
  }

  /// Last thumbnail URL from a thumbnail renderer node.
  String? _thumbUrl(dynamic node) {
    final thumbs = node?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty) {
      return (thumbs.last as Map)['url'] as String?;
    }
    return null;
  }

  /// Parses "4:59" or "1:02:33" into a Duration.
  Duration? _parseDuration(String? text) {
    if (text == null) return null;
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    final nums = parts.map((p) => p!).toList();
    if (nums.length == 3) {
      return Duration(hours: nums[0], minutes: nums[1], seconds: nums[2]);
    }
    if (nums.length == 2) {
      return Duration(minutes: nums[0], seconds: nums[1]);
    }
    return null;
  }

  void dispose() {
    _resolver.dispose();
    _yt.close();
  }
}

/// Un risultato della ricerca "Songs", ridotto a cio' che serve per
/// riconoscere la versione canzone di un videoclip.
typedef SongCandidate = ({String id, String title, String artists});
