import 'artist_names.dart';

/// A single playable track (a YouTube video used as an audio source).
class Track {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final bool isLive;

  /// YouTube Music browseId of the artist (for artist-page navigation).
  final String? artistId;

  /// YouTube Music browseId of the album (for album-page navigation).
  final String? albumId;

  /// Display name of the album (shown under the artist in the player).
  final String? albumName;

  /// Contenuto esplicito. YouTube Music lo dichiara con un badge su ogni
  /// riga, e lo dichiara spesso: sull'album che ho controllato, 14 tracce
  /// su 14.
  final bool isExplicit;

  /// Le riproduzioni, come le scrive YouTube Music ("3,8 Mln riproduzioni").
  /// Si tiene la stringa e non un numero: arriva gia' abbreviata e tradotta,
  /// e riformattarla a mano vorrebbe dire rifare quel lavoro peggio.
  final String? plays;

  /// Un video e non una canzone: un remix, un pezzo uscito solo su
  /// YouTube, trovato fra i video della ricerca. Si ascolta e si salva come
  /// ogni altro brano; in piu' lo si puo' guardare, ed e' lui stesso il suo
  /// video (vedi YouTubeService.musicVideoFor).
  final bool isVideo;

  const Track({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    this.isLive = false,
    this.artistId,
    this.albumId,
    this.albumName,
    this.plays,
    this.isExplicit = false,
    this.isVideo = false,
  });

  /// Le riproduzioni senza la parola finale: "3,8 Mln riproduzioni" ->
  /// "3,8 Mln". In una riga di elenco la parola occupa il triplo del
  /// numero e non aggiunge niente, visto che la colonna e' sempre quella.
  String? get playsShort {
    final raw = plays;
    if (raw == null || raw.isEmpty) return null;
    final cut = raw.split(
      RegExp(
        r'\s+(?:di\s+)?(?:riproduzioni|visualizzazioni|plays|views)',
        caseSensitive: false,
      ),
    );
    final head = cut.first.trim();
    return head.isEmpty ? raw : head;
  }

  /// Questa copia aggiornata con quella appena letta dalla rete.
  ///
  /// Non e' una sostituzione: un risultato di ricerca non porta l'id
  /// dell'album, e rimpiazzare cancellerebbe un dato che avevamo. Si
  /// prende il nuovo dove c'e', si tiene il vecchio dove manca.
  Track refreshedFrom(Track fresh) {
    if (fresh.id != id) return this;
    return Track(
      id: id,
      title: fresh.title,
      author: fresh.author,
      duration: fresh.duration ?? duration,
      // Una copertina di ripiego non deve scalzarne una vera: certi
      // percorsi ricadono ancora sul fotogramma del video, e accettarlo
      // peggiorerebbe una riga che era gia' a posto.
      thumbnailUrl: fresh._isFallbackArt && !_isFallbackArt
          ? thumbnailUrl
          : fresh.thumbnailUrl,
      isExplicit: fresh.isExplicit || isExplicit,
      isLive: fresh.isLive,
      artistId: fresh.artistId ?? artistId,
      albumId: fresh.albumId ?? albumId,
      albumName: fresh.albumName ?? albumName,
      plays: fresh.plays ?? plays,
      isVideo: fresh.isVideo || isVideo,
    );
  }

  bool get _isFallbackArt =>
      thumbnailUrl.isEmpty || thumbnailUrl.contains('img.youtube.com/vi/');

  String get url => 'https://www.youtube.com/watch?v=$id';

  /// Link shared with other people: a music.youtube.com URL opens in the
  /// YouTube Music app when it is installed, unlike the www.youtube.com one.
  String get ytmUrl => 'https://music.youtube.com/watch?v=$id';

  Track copyWith({
    String? id,
    String? title,
    String? author,
    Duration? duration,
    String? thumbnailUrl,
    bool? isLive,
    String? artistId,
    String? albumId,
    String? plays,
    bool? isExplicit,
    String? albumName,
    bool? isVideo,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      isLive: isLive ?? this.isLive,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      plays: plays ?? this.plays,
      isExplicit: isExplicit ?? this.isExplicit,
      isVideo: isVideo ?? this.isVideo,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'duration': duration?.inSeconds,
    'thumbnailUrl': thumbnailUrl,
    'isLive': isLive,
    'artistId': artistId,
    'albumId': albumId,
    'albumName': albumName,
    'plays': plays,
    'isExplicit': isExplicit,
    if (isVideo) 'isVideo': true,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    // Ripulito anche in lettura, non solo quando il brano arriva dalla
    // rete: i preferiti salvati prima portano ancora il gruppo di feat
    // scritto due volte, e riscriverli tutti su disco per questo sarebbe
    // sproporzionato.
    title: ArtistNames.dedupeFeatGroups(json['title'] as String),
    author: json['author'] as String,
    duration: json['duration'] != null
        ? Duration(seconds: json['duration'] as int)
        : null,
    thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
    isLive: json['isLive'] as bool? ?? false,
    artistId: json['artistId'] as String?,
    albumId: json['albumId'] as String?,
    albumName: json['albumName'] as String?,
    plays: json['plays'] as String?,
    isExplicit: json['isExplicit'] as bool? ?? false,
    isVideo: json['isVideo'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
