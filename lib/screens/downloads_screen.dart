import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../models/track.dart';
import '../services/player_state.dart';
import '../design/chrome.dart';
import '../providers.dart';
import '../services/library_sort.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_sort_button.dart';
import '../widgets/sub_page.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_tile.dart';

/// I brani tenuti sul dispositivo.
///
/// Suonano senza rete e partono all'istante, perche' il player legge il
/// file locale prima di rivolgersi a Google.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  static const title = 'Downloads';

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

/// Si ordinano come i piaciuti. "Recently Added" e' l'ordine in cui li hai
/// scaricati, dal piu' recente: l'elenco cresce in coda e non ha date. Dei
/// filtri resta solo "Hide Explicit": "Downloaded Only" qui sarebbe tutto.
class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  static const _filters = [SongFilter.clean];

  late final _store = LibraryViewStore(
    ref.read(storageServiceProvider),
    'downloads',
    options: SortKey.downloads,
    filters: _filters,
    songs: true,
  );
  late LibraryView _view = _store.load();
  final _shown = Memo<List<Track>>();

  void _setView(LibraryView view) {
    setState(() => _view = view);
    _store.save(view);
  }

  @override
  Widget build(BuildContext context) {
    // Solo l'elenco: l'avanzamento di un download in corso cambia lo stato
    // molte volte al secondo, e l'elenco no.
    final all = ref.watch(downloadsProvider.select((d) => d.tracks));
    final stats = _view.sort == SortKey.plays ? ref.watch(statsProvider) : null;
    final tracks = _shown(
      (all, _view, stats),
      () => sortTracks(
        all,
        _view,
        plays: {
          for (final e in (stats ?? const {}).entries) e.key: e.value.playCount,
        },
      ),
    );
    final player = ref.watch(playerProvider);

    return SubPage(
      title: DownloadsScreen.title,
      actions: [
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              // Filtrati, si dice quanti se ne vedono su quanti: un numero
              // solo sembrerebbe quelli che hai.
              tracks.length == all.length
                  ? '${all.length} song${all.length == 1 ? '' : 's'}'
                  : '${tracks.length} of ${all.length}',
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
        if (all.length > 1 || _view.isCustom(SortKey.downloads))
          LibrarySortButton(
            view: _view,
            options: SortKey.downloads,
            filters: _filters,
            onChanged: _setView,
          ),
      ],
      child: Column(
        children: [
          // L'interruttore sta qui e non in una pagina impostazioni: e' il
          // posto dove il concetto vive, ed e' dove lo si cerca.
          SwitchListTile.adaptive(
            value: ref.watch(autoPreloadProvider),
            onChanged: (v) => ref.read(autoPreloadProvider.notifier).set(v),
            title: Text(
              'Preload the next song',
              style: context.texts.bodyLarge,
            ),
            subtitle: Text(
              'Downloads it while you listen, so it starts instantly. '
              'Off, only what you pick is downloaded.',
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(context, all, tracks, player)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<Track> all,
    List<Track> tracks,
    PlayerState player,
  ) {
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.download_rounded,
        title: 'Nothing downloaded',
        message:
            'Long-press a song and choose Download: it stays here, '
            'ready even without a connection.',
      );
    }
    if (tracks.isEmpty) {
      return FilteredEmptyState(
        view: _view,
        collection: DownloadsScreen.title,
        onClear: () => _setView(_view.withoutFilters),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: listBottomPadding(context, ref)),
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        final isCurrent = player.current?.id == track.id;
        return TrackTile(
          track: track,
          isCurrent: isCurrent,
          isPlaying: isCurrent && player.isPlaying,
          // La coda e' la lista come la vedi: ordinata e filtrata.
          onTap: () =>
              ref.read(playerProvider.notifier).playTrack(track, queue: tracks),
          extraMenuActions: [
            TrackMenuAction(
              icon: Icons.delete_outline_rounded,
              label: 'Remove download',
              isDestructive: true,
              onSelected: () =>
                  ref.read(downloadsProvider.notifier).remove(track.id),
            ),
          ],
        );
      },
    );
  }
}
