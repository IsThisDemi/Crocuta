import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../models/track.dart';
import '../providers.dart';
import '../services/library_sort.dart';
import '../services/library_views.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_sort_button.dart';
import '../widgets/song_collection.dart';
import 'media_detail_page.dart';

/// I brani piaciuti, come una playlist di Apple Music.
///
/// Non sono i "preferiti fra i salvati": sono tutto quello a cui si e'
/// messo il cuore, cioe' la libreria dei brani. Per questo la pagina e'
/// quella di una raccolta — copertina, Riproduci e Casuale, riepilogo in
/// fondo — e non un elenco con un cuore acceso su ogni riga, che su una
/// pagina dove sono tutti piaciuti non diceva niente.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  static const title = 'Liked Songs';

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final _search = TextEditingController();
  String _query = '';

  late final _store = LibraryViewStore(
    ref.read(storageServiceProvider),
    'liked',
    options: SortKey.liked,
    filters: SongFilter.values,
    songs: true,
  );
  late LibraryView _view = _store.load();

  /// La lista ordinata, rifatta solo quando cambia qualcosa che conta: la
  /// pagina si ricostruisce anche a ogni cambio di brano, per il colore, e
  /// riordinare 842 brani li' sarebbe lavoro buttato.
  final _shown = Memo<List<Track>>();

  @override
  void initState() {
    super.initState();
    // Una volta all'apertura, non a ogni ricostruzione: dentro build si
    // registrava di nuovo a ogni fotogramma in cui la lista cambiava.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(favoritesProvider).any((t) => t.duration == null)) {
        ref.read(favoritesProvider.notifier).enrichDurations();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setView(LibraryView view) {
    setState(() => _view = view);
    _store.save(view);
  }

  Future<void> _remove(Track track) async {
    final undo = await ref.read(favoritesProvider.notifier).remove(track);
    showRemovedSnack(track: track, from: FavoritesScreen.title, undo: undo);
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    // La pagina prende la faccia del brano che suona: la sua copertina
    // sfocata dietro, come in un album, e il suo colore nel cuore e nei
    // pulsanti. Senza niente in riproduzione, quella del primo piaciuto.
    final playing = ref.watch(
      playerProvider.select((s) => s.current?.thumbnailUrl),
    );
    final face = playing ?? favorites.firstOrNull?.thumbnailUrl ?? '';
    // Gli ascolti e gli scaricati si guardano solo quando servono: senza,
    // ogni ascolto registrato e ogni avanzamento di un download
    // ricostruirebbero la pagina per niente.
    final stats = _view.sort == SortKey.plays ? ref.watch(statsProvider) : null;
    final downloads = _view.filters.contains(SongFilter.downloaded)
        ? ref.watch(downloadsProvider.select((d) => d.tracks))
        : null;
    final tracks = _shown(
      (favorites, _view, _query, stats, downloads),
      () => sortTracks(
        favorites,
        _view,
        query: _query,
        addedAt: ref.read(storageServiceProvider).marks('fav'),
        plays: {
          for (final e in (stats ?? const {}).entries) e.key: e.value.playCount,
        },
        downloaded: {for (final t in downloads ?? const <Track>[]) t.id},
      ),
    );
    final filtered = _view.filters.isNotEmpty;

    return DetailScaffold(
      actions: [
        if (favorites.length > 1 || _view.isCustom(SortKey.liked))
          LibrarySortButton(
            view: _view,
            options: SortKey.liked,
            filters: SongFilter.values,
            onChanged: _setView,
            glass: true,
          ),
      ],
      body: favorites.isEmpty
          ? const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'No liked songs yet',
              message: 'Tap the heart on a song to add it here.',
            )
          : MediaDetailPage(
              detail: MediaDetail(
                title: FavoritesScreen.title,
                imageUrl: face,
                cover: const LikedSongsCover(),
                tracks: tracks,
                meta: const ['Playlist'],
                // Il riepilogo e' di tutta la raccolta anche mentre si cerca:
                // sotto una ricerca, "3 songs" sembrerebbe quanti ne hai.
                // Con un filtro acceso si dice anche quanti se ne vedono, e
                // perche'.
                footnote: [
                  songsSummary(favorites),
                  if (filtered && _query.trim().isEmpty)
                    'Showing ${tracks.length}: '
                        '${[for (final f in _view.filters) f.label].join(', ')}',
                ],
                onSwipeRemove: _remove,
                tools: favorites.length < SongFindField.minTracks
                    ? null
                    : SongFindField(
                        controller: _search,
                        collection: FavoritesScreen.title,
                        onChanged: (q) => setState(() => _query = q),
                      ),
                empty: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: filtered
                      ? FilteredEmptyState(
                          view: _view,
                          collection: FavoritesScreen.title,
                          query: _query,
                          onClear: () => _setView(_view.withoutFilters),
                        )
                      : EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No results',
                          message: 'Nothing in Liked Songs matches "$_query".',
                        ),
                ),
              ),
            ),
    );
  }
}

/// La copertina dei brani piaciuti: il cuore su un fondo a colore pieno.
///
/// Come la copertina di "Favorite Songs" in Apple Music, che e' una stella
/// su un rosa pieno: una raccolta che non e' un disco ha bisogno di una
/// faccia sua. Il colore e' l'accento della pagina, cioe' quello del brano
/// che suona: cambia con lui, mentre il cuore resta.
class LikedSongsCover extends StatelessWidget {
  const LikedSongsCover({super.key});

  @override
  Widget build(BuildContext context) {
    final coral = context.colors.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(coral, Colors.white, 0.18)!,
            coral,
            Color.lerp(coral, Colors.black, 0.35)!,
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Icon(
          Icons.favorite_rounded,
          color: Colors.white,
          size: c.maxWidth * 0.42,
        ),
      ),
    );
  }
}
