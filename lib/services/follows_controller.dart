import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist.dart';
import '../providers.dart';

/// Un artista seguito.
class FollowedArtist {
  final String browseId;
  final String name;
  final String? thumbnailUrl;

  const FollowedArtist({
    required this.browseId,
    required this.name,
    this.thumbnailUrl,
  });

  factory FollowedArtist.fromJson(Map<String, dynamic> j) => FollowedArtist(
    browseId: j['browseId'] as String,
    name: (j['name'] as String?) ?? '',
    thumbnailUrl: j['thumbnailUrl'] as String?,
  );
}

/// Un'uscita di un artista che segui.
class NewRelease {
  final AlbumCard album;
  final String artistName;

  /// L'anno dichiarato nel sottotitolo, quando c'e'. Serve a ordinare:
  /// YouTube Music da' l'anno e non la data, quindi e' il massimo della
  /// precisione disponibile.
  final int? year;

  /// Non c'era l'ultima volta che abbiamo guardato.
  final bool isNew;

  /// Il giorno dell'uscita, quando si e' trovato: vedi
  /// YoutubeService.releaseDateOf.
  final DateTime? date;

  const NewRelease({
    required this.album,
    required this.artistName,
    this.year,
    this.isNew = false,
    this.date,
  });

  NewRelease withDate(DateTime? d) => NewRelease(
    album: album,
    artistName: artistName,
    year: year ?? d?.year,
    isNew: isNew,
    date: d,
  );

  /// Quando ordinarla: la data, o in mancanza meta' del suo anno; senza
  /// nemmeno l'anno, in fondo.
  DateTime get sortKey =>
      date ?? (year == null ? DateTime(1900) : DateTime(year!, 7));

  static final _year = RegExp(r'(19|20)\d{2}');

  static int? yearOf(AlbumCard a) {
    final m = _year.firstMatch(a.subtitle);
    return m == null ? null : int.tryParse(m.group(0)!);
  }
}

class FollowsController extends Notifier<List<FollowedArtist>> {
  @override
  List<FollowedArtist> build() => _read();

  List<FollowedArtist> _read() => [
    for (final a in ref.read(storageServiceProvider).followed)
      FollowedArtist.fromJson(a),
  ];

  bool isFollowing(String browseId) => state.any((a) => a.browseId == browseId);

  /// Seguendo si registra cio' che l'artista ha pubblicato finora, ma non
  /// per nasconderlo: serve solo a sapere, la volta dopo, cosa e' comparso
  /// nel frattempo e metterlo davanti.
  Future<void> follow(ArtistPage page) async {
    final storage = ref.read(storageServiceProvider);
    await storage.follow(
      browseId: page.browseId,
      name: page.name,
      thumbnailUrl: page.thumbnailUrl,
    );
    await storage.setSeenReleases(page.browseId, {
      for (final a in [...page.albums, ...page.singles]) a.browseId,
    });
    state = _read();
  }

  Future<void> unfollow(String browseId) async {
    await ref.read(storageServiceProvider).unfollow(browseId);
    state = _read();
  }
}

/// Le ultime uscite degli artisti che segui.
///
/// Mostra le piu' recenti, non solo quelle mai viste. La prima versione
/// faceva il contrario — seguendo un artista si segnava tutto come gia'
/// visto, per non inondare la Home della sua discografia — e il risultato
/// era una sezione che restava vuota finche' quell'artista non pubblicava
/// qualcosa. Mesi, potenzialmente. Una funzione che sembra rotta e' peggio
/// di una che ripete qualcosa che conoscevi.
///
/// Dalla piu' recente, per giorno d'uscita: vedi sotto.
///
/// Costa una richiesta per artista seguito, quindi non si rifa' a ogni
/// apertura.
/// Per quante uscite di ogni artista si cerca la data esatta.
const _datedPerArtist = 6;

final latestReleasesProvider = FutureProvider<List<NewRelease>>((ref) async {
  // Si guarda chi segui, non l'elenco in se': la sincronizzazione ricarica
  // l'elenco a ogni passata — sul Mac ogni volta che la finestra perde il
  // fuoco — e un elenco ricaricato e' un oggetto nuovo anche quando dentro
  // c'e' la stessa gente. Bastava cliccare su un'altra app perche' qui si
  // riscaricasse la pagina di ogni artista seguito, e intanto in Home la
  // sezione spariva. Gli id uguali non cambiano niente.
  ref.watch(followsProvider.select((f) => f.map((a) => a.browseId).join('|')));
  final follows = ref.read(followsProvider);
  if (follows.isEmpty) return const [];

  final storage = ref.read(storageServiceProvider);
  final service = ref.read(youtubeServiceProvider);
  final seenIds = <String>{};
  // Una fila per artista, nell'ordine in cui YouTube Music le restituisce.
  final perArtist = <List<NewRelease>>[];

  for (final artist in follows) {
    try {
      final page = await service.getArtistPage(artist.browseId);
      final known = storage.seenReleases(artist.browseId);
      final mine = <NewRelease>[];
      // Album e singoli alternati, cosi' un artista che pubblica soprattutto
      // singoli non resta indietro rispetto a uno che fa dischi.
      final a = page.albums;
      final si = page.singles;
      for (var i = 0; i < (a.length > si.length ? a.length : si.length); i++) {
        for (final r in [if (i < a.length) a[i], if (i < si.length) si[i]]) {
          // Lo stesso disco puo' comparire sotto due artisti seguiti.
          if (!seenIds.add(r.browseId)) continue;
          mine.add(
            NewRelease(
              album: r,
              artistName: artist.name,
              year: NewRelease.yearOf(r),
              isNew: !known.contains(r.browseId),
            ),
          );
        }
      }
      if (mine.isNotEmpty) perArtist.add(mine);
    } catch (_) {
      // Un artista che non risponde non deve far sparire gli altri.
    }
  }

  // Dalla piu' recente, per data vera. Prima erano a turno fra gli
  // artisti — la piu' recente di ciascuno, poi la seconda — e un disco di
  // tre anni fa di uno finiva davanti al singolo di ieri di un altro.
  //
  // La data esatta la si chiede solo per le prime uscite di ogni artista,
  // che YouTube Music elenca gia' dalla piu' recente: le altre sono
  // comunque vecchie. Una volta trovata resta in memoria.
  final candidates = <String>[
    for (final list in perArtist)
      for (final r in list.take(_datedPerArtist)) r.album.browseId,
  ];
  final dates = <String, DateTime>{};
  final missing = <String>[];
  for (final id in candidates) {
    final known = storage.releaseDate(id);
    if (known != null) {
      dates[id] = known;
    } else {
      missing.add(id);
    }
  }
  final found = <String, DateTime>{};
  for (var i = 0; i < missing.length; i += 6) {
    await Future.wait([
      for (final id in missing.skip(i).take(6))
        service
            .releaseDateOf(id)
            .then<void>((d) {
              if (d != null) found[id] = d;
            })
            .catchError((Object _) {}),
    ]);
  }
  await storage.setReleaseDates(found);
  dates.addAll(found);

  final out = [
    for (final list in perArtist)
      for (final r in list) r.withDate(dates[r.album.browseId]),
  ]..sort((x, y) => y.sortKey.compareTo(x.sortKey));

  await storage.setLastReleaseCheck(DateTime.now());
  return out;
});
