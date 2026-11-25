import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../services/library_sort.dart';
import '../services/storage_service.dart';
import 'empty_state.dart';
import 'glass_surfaces.dart';
import 'liquid.dart';

/// Dove una pagina della libreria ricorda come l'avevi lasciata.
///
/// Le raccolte di brani ([songs]) tengono l'ordinamento in `song_sort`,
/// dove i piaciuti e le playlist lo salvavano gia': chi aveva scelto
/// "Artist" lo ritrova. Dischi, artisti e playlist in `library_sort`. I
/// filtri, per tutte, in `library_filters`. Senza [page] — una playlist
/// che non ha ancora un id — la vista vale finche' la pagina e' aperta.
class LibraryViewStore {
  final StorageService storage;
  final String? page;
  final List<SortKey> options;
  final List<SongFilter> filters;
  final bool songs;

  const LibraryViewStore(
    this.storage,
    this.page, {
    required this.options,
    this.filters = const [],
    this.songs = false,
  });

  LibraryView load() {
    final key = page;
    if (key == null) return LibraryView.initial(options);
    return LibraryView.decode(
      songs ? storage.songSort(key) : storage.librarySort(key),
      filters.isEmpty ? const {} : storage.libraryFilters(key),
      options: options,
      allowed: filters,
    );
  }

  void save(LibraryView view) {
    final key = page;
    if (key == null) return;
    songs
        ? storage.setSongSort(key, view.encodeSort)
        : storage.setLibrarySort(key, view.encodeSort);
    if (filters.isNotEmpty) storage.setLibraryFilters(key, view.encodeFilters);
  }
}

enum _Clear { filters }

/// "Sort By" e i filtri: un solo pulsante in alto a destra, con il menu di
/// vetro dell'app.
///
/// Nel menu prima le voci d'ordinamento — la spunta su quella attiva, con
/// il verso scritto accanto ("Title · A to Z") — poi i filtri, con la
/// spunta se accesi. Toccare la voce attiva gira il verso, come le colonne
/// di Musica sul Mac.
///
/// Quando la vista non e' quella di serie il pulsante prende il colore
/// d'accento: una lista filtrata, o in un ordine che non ti aspetti, non
/// deve sembrare una libreria a cui mancano dei brani.
class LibrarySortButton extends StatelessWidget {
  final LibraryView view;
  final List<SortKey> options;
  final List<SongFilter> filters;
  final ValueChanged<LibraryView> onChanged;

  /// Un cerchio di vetro, come gli altri pulsanti delle pagine di una
  /// raccolta; `false` per stare dentro la capsula di [SubPage], che il
  /// vetro ce l'ha gia'.
  final bool glass;

  const LibrarySortButton({
    super.key,
    required this.view,
    required this.options,
    required this.onChanged,
    this.filters = const [],
    this.glass = false,
  });

  static const double _menuWidth = 250;

  static const _icons = {
    SortKey.added: Icons.schedule_rounded,
    SortKey.updated: Icons.update_rounded,
    SortKey.followed: Icons.person_add_alt_rounded,
    SortKey.playlist: Icons.format_list_numbered_rounded,
    SortKey.title: Icons.sort_by_alpha_rounded,
    SortKey.name: Icons.sort_by_alpha_rounded,
    SortKey.artist: Icons.person_rounded,
    SortKey.album: Icons.album_rounded,
    SortKey.plays: Icons.bar_chart_rounded,
    SortKey.duration: Icons.timer_outlined,
    SortKey.year: Icons.calendar_today_rounded,
  };

  static const _filterIcons = {
    SongFilter.downloaded: Icons.download_done_rounded,
    SongFilter.clean: Icons.explicit_outlined,
  };

  String get _tooltip {
    final sort = 'Sort by ${view.sort.label}, ${view.direction}';
    if (view.filters.isEmpty) return sort;
    return '$sort · ${[for (final f in view.filters) f.label].join(', ')}';
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Sotto il pulsante, col bordo destro circa al suo: il pulsante sta
    // sul bordo destro, e il menu lo tiene dentro lo schermo da solo.
    final corner = box.localToGlobal(Offset(box.size.width, box.size.height));
    final picked = await showGlassMenu<Object>(
      context: context,
      globalPosition: Offset(corner.dx - _menuWidth, corner.dy + 6),
      items: [
        for (final s in options)
          GlassMenuItem(
            value: s,
            icon: s == view.sort ? Icons.check_rounded : _icons[s]!,
            label: s == view.sort ? '${s.label} · ${view.direction}' : s.label,
          ),
        for (final f in filters)
          GlassMenuItem(
            value: f,
            icon: view.filters.contains(f)
                ? Icons.check_rounded
                : _filterIcons[f]!,
            label: f.label,
          ),
        if (view.filters.isNotEmpty)
          const GlassMenuItem(
            value: _Clear.filters,
            icon: Icons.filter_alt_off_rounded,
            label: 'Clear Filters',
          ),
      ],
    );
    switch (picked) {
      case SortKey s:
        onChanged(view.pick(s));
      case SongFilter f:
        onChanged(view.toggle(f));
      case _Clear.filters:
        onChanged(view.withoutFilters);
    }
  }

  @override
  Widget build(BuildContext context) {
    // L'icona dice cosa c'e' dentro: le frecce dove si ordina e basta,
    // l'imbuto a righe dove si puo' anche filtrare.
    final icon = filters.isEmpty
        ? Icons.swap_vert_rounded
        : Icons.filter_list_rounded;
    final tint = view.isCustom(options) ? context.colors.accent : null;
    if (glass) {
      return Builder(
        builder: (context) => GlassCircleIconButton(
          icon: icon,
          iconColor: tint,
          tooltip: _tooltip,
          onPressed: () => _open(context),
        ),
      );
    }
    return Builder(
      builder: (context) => IconButton(
        icon: Icon(icon, size: 24, color: tint),
        tooltip: _tooltip,
        onPressed: () => _open(context),
      ),
    );
  }
}

/// Lo stato vuoto di una lista svuotata dai filtri: dice quali filtri sono
/// accesi e li spegne con un tocco. Senza, "nessun brano" su una libreria
/// di ottocento si legge come una libreria persa.
class FilteredEmptyState extends StatelessWidget {
  final LibraryView view;

  /// Il nome della raccolta: "Liked Songs", "Downloads".
  final String collection;

  /// La ricerca in corso, se c'e': i filtri e la ricerca si sommano.
  final String query;
  final VoidCallback onClear;

  const FilteredEmptyState({
    super.key,
    required this.view,
    required this.collection,
    required this.onClear,
    this.query = '',
  });

  @override
  Widget build(BuildContext context) {
    final names = [for (final f in view.filters) f.label].join(', ');
    final q = query.trim();
    return EmptyState(
      icon: Icons.filter_list_off_rounded,
      title: 'No matching songs',
      message:
          'Filters on: $names.\n'
          'Nothing in $collection${q.isEmpty ? '' : ' matching "$q"'} '
          'gets through.',
      actionLabel: 'Clear Filters',
      onAction: onClear,
    );
  }
}
