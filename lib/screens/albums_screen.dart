import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist.dart';
import '../providers.dart';
import '../services/library_sort.dart';
import '../services/library_views.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_sort_button.dart';
import '../widgets/sub_page.dart';
import 'section_screen.dart';

/// I dischi dei brani che hai salvato, dal piu' recente; o per titolo,
/// artista e — se si conosce — anno.
class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  late final _store = LibraryViewStore(
    ref.read(storageServiceProvider),
    'albums',
    options: SortKey.albums,
  );
  late LibraryView _view = _store.load();

  /// Gli anni noti, rifatti solo quando cambiano i dischi.
  final _years = Memo<Map<String, int>>();
  final _sorted = Memo<List<AlbumCard>>();

  void _setView(LibraryView view) {
    setState(() => _view = view);
    _store.save(view);
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(libraryAlbumsProvider);
    final years = _years(albums, () {
      final storage = ref.read(storageServiceProvider);
      return {
        for (final a in albums)
          if (storage.releaseDate(a.browseId) case final d?) a.browseId: d.year,
      };
    });
    // "Year" solo se l'anno si conosce per buona parte dei dischi; una
    // scelta salvata che non vale piu' torna a quella di serie.
    final options = [
      for (final k in SortKey.albums)
        if (k != SortKey.year || yearsCoverEnough(albums, years)) k,
    ];
    final view = options.contains(_view.sort)
        ? _view
        : LibraryView.initial(options);
    final sorted = _sorted((
      albums,
      view,
      years,
    ), () => sortAlbums(albums, view, years: years));

    return SubPage(
      title: 'Albums',
      actions: [
        if (albums.length > 1)
          LibrarySortButton(view: view, options: options, onChanged: _setView),
      ],
      child: albums.isEmpty
          ? const EmptyState(
              icon: Icons.album_rounded,
              title: 'No albums yet',
              message: 'Like a song: its album shows up here.',
            )
          : AlbumCardGrid(cards: sorted),
    );
  }
}
