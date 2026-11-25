import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../widgets/glass_surfaces.dart';
import '../providers.dart';
import '../design/chrome.dart';
import '../widgets/detail_scaffold.dart';
import 'media_detail_page.dart';
import '../widgets/sub_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/thumbnail.dart';
import '../widgets/song_collection.dart';
import '../widgets/library_sort_button.dart';
import '../services/library_sort.dart';
import '../services/library_views.dart';
import '../models/track.dart';
import '../widgets/liquid.dart';
import '../widgets/progress_fill.dart';
import '../widgets/section_header.dart';
import '../widgets/smart_playlist_views.dart';
import '../widgets/toast.dart';

/// User playlists screen: shows all user-created playlists and allows
/// creating, viewing, renaming and deleting them.
///
/// Le tue playlist si ordinano come in Apple: dalla piu' recente, per
/// ultima modifica o per nome. Le intelligenti in cima restano come sono,
/// perche' l'ordine lo decide chi le fa.
class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  late final _store = LibraryViewStore(
    ref.read(storageServiceProvider),
    'playlists',
    options: SortKey.playlists,
  );
  late LibraryView _view = _store.load();
  final _sorted = Memo<List<(int, UserPlaylist)>>();

  void _setView(LibraryView view) {
    setState(() => _view = view);
    _store.save(view);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    // Il controller ricarica la lista a ogni modifica: una lista nuova e'
    // il segnale che date e nomi possono essere cambiati.
    final sorted = _sorted((playlists, _view), () {
      final storage = ref.read(storageServiceProvider);
      return sortPlaylists(
        playlists,
        _view,
        ids: [for (final p in storage.playlists) p['id'] as String?],
        updatedAt: storage.marks('pl'),
      );
    });

    return SubPage(
      title: 'Playlists',
      actions: [
        if (playlists.length > 1 || _view.isCustom(SortKey.playlists))
          LibrarySortButton(
            view: _view,
            options: SortKey.playlists,
            onChanged: _setView,
          ),
        IconButton(
          icon: const Icon(Icons.add_rounded, size: 26),
          tooltip: 'New playlist',
          onPressed: () => _showCreateDialog(context, ref),
        ),
      ],
      // In cima le playlist intelligenti, che si fanno da sole; sotto le
      // tue. Un'unica lista, cosi' scorrono insieme.
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: listBottomPadding(context, ref)),
        itemCount: sorted.length + 1,
        itemBuilder: (context, row) {
          if (row == 0) {
            final smart = ref.watch(smartPlaylistsProvider).isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (smart) ...[
                  const SectionHeader(title: 'Made for You'),
                  const SmartPlaylistRail(),
                  if (playlists.isNotEmpty)
                    const SectionHeader(title: 'Your Playlists'),
                ],
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xl),
                    child: EmptyState(
                      icon: Icons.queue_music_rounded,
                      title: 'No playlists yet',
                      message: 'Tap + to create one.',
                    ),
                  ),
              ],
            );
          }
          // La posizione vera, non quella a schermo: aprire, rinominare e
          // cancellare indirizzano la playlist per posizione.
          final (i, pl) = sorted[row - 1];
          return _PlaylistTile(
            playlist: pl,
            index: i,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PlaylistDetailScreen(index: i),
              ),
            ),
            onDelete: () => _confirmDelete(context, ref, i, pl.name),
            onRename: () => _showRenameDialog(context, ref, i, pl.name),
          );
        },
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final name = await showGlassTextPrompt(
      context: context,
      title: 'New Playlist',
      message: 'Enter a name for this playlist.',
      hint: 'Title',
      confirmLabel: 'Create',
    );
    if (name != null) await ref.read(playlistsProvider.notifier).create(name);
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    int index,
    String currentName,
  ) async {
    final name = await showGlassTextPrompt(
      context: context,
      title: 'Rename Playlist',
      hint: 'Title',
      initial: currentName,
      confirmLabel: 'Save',
    );
    if (name != null && name != currentName) {
      await ref.read(playlistsProvider.notifier).rename(index, name);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int index,
    String name,
  ) async {
    final ok = await showGlassConfirm(
      context: context,
      title: 'Delete "$name"?',
      message: 'This playlist will be removed from your library.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await ref.read(playlistsProvider.notifier).delete(index);
  }
}

class _PlaylistTile extends StatelessWidget {
  final UserPlaylist playlist;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _PlaylistTile({
    required this.playlist,
    required this.index,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // La macchia del primo brano, la stessa del mosaico nella pagina
      // della playlist; vuota, una macchia scura seminata dal nome.
      leading: SizedBox.square(
        dimension: 52,
        child: playlist.tracks.isNotEmpty
            ? SpotThumbnail(
                url: playlist.tracks.first.thumbnailUrl,
                wobble: 0.6,
              )
            : Spot(
                seed: playlist.name,
                wobble: 0.6,
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.08),
                  child: const Center(
                    child: Icon(Icons.library_music, color: Colors.white38),
                  ),
                ),
              ),
      ),
      title: Text(
        playlist.name,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${playlist.tracks.length} song${playlist.tracks.length == 1 ? '' : 's'}',
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
      trailing: GlassMenuButton<String>(
        icon: Icons.more_vert,
        color: context.colors.textMuted,
        onSelected: (v) {
          if (v == 'rename') onRename();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          GlassMenuItem(
            value: 'rename',
            icon: Icons.edit_rounded,
            label: 'Rinomina',
          ),
          GlassMenuItem(
            value: 'delete',
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            isDestructive: true,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Una playlist tua, con la stessa pagina dei brani piaciuti: copertina a
/// mosaico, ordinamento, ricerca, e i brani si tolgono scorrendo a
/// sinistra con "Annulla" invece che con un pulsante su ogni riga.
class _PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int index;
  const _PlaylistDetailScreen({required this.index});

  @override
  ConsumerState<_PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<_PlaylistDetailScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// Dove si ricorda l'ordinamento: l'id della playlist, che non cambia se
  /// la rinomini o se un'altra davanti a lei viene cancellata.
  late final String? _sortKey = ref
      .read(storageServiceProvider)
      .playlistId(widget.index);

  late final _store = LibraryViewStore(
    ref.read(storageServiceProvider),
    _sortKey,
    options: SortKey.ofPlaylist,
    songs: true,
  );
  late LibraryView _view = _store.load();
  final _shown = Memo<List<Track>>();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setView(LibraryView view) {
    setState(() => _view = view);
    _store.save(view);
  }

  /// Riordina la playlist per tempo e tonalita', perche' con AutoMix ogni
  /// passaggio scorra. Salva il nuovo ordine, e l'"Annulla" rimette il
  /// vecchio.
  Future<void> _applyReorder(List<Track> tracks, List<Track> ordered) async {
    final playlists = ref.read(playlistsProvider.notifier);
    await playlists.setTracks(widget.index, ordered);
    // Il nuovo ordine e' l'ordine della playlist: e' quello da vedere.
    _setView(LibraryView.initial(SortKey.ofPlaylist));
    showToast(
      'Reordered for Smooth Transitions',
      icon: Icons.auto_awesome_rounded,
      actionLabel: 'Undo',
      onAction: () => playlists.setTracks(widget.index, tracks),
    );
  }

  Future<void> _remove(String name, Track track) async {
    final undo = await ref
        .read(playlistsProvider.notifier)
        .removeWithUndo(widget.index, track);
    showRemovedSnack(track: track, from: name, undo: undo);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final index = widget.index;

    // The playlist is addressed by index, so it can vanish under us if it is
    // deleted while this page is open.
    if (index >= playlists.length) {
      return const SubPage(
        child: EmptyState(
          icon: Icons.playlist_remove_rounded,
          title: 'Playlist deleted',
        ),
      );
    }

    final pl = playlists[index];
    final stats = _view.sort == SortKey.plays ? ref.watch(statsProvider) : null;
    final tracks = _shown(
      (pl.tracks, _view, _query, stats),
      () => sortTracks(
        pl.tracks,
        _view,
        query: _query,
        plays: {
          for (final e in (stats ?? const {}).entries) e.key: e.value.playCount,
        },
      ),
    );

    return DetailScaffold(
      actions: [
        if (pl.tracks.length > 2)
          // Si riempie del colore del brano mentre analizza: i brani non
          // sul dispositivo vanno scaricati, e su una playlist lunga ci
          // vuole qualche minuto. Premuto di nuovo, annulla.
          FillJobButton<List<Track>>(
            job: (onProgress, cancelled) => ref
                .read(playerProvider.notifier)
                .smartOrderOf(
                  pl.tracks,
                  onProgress: onProgress,
                  cancelled: cancelled,
                ),
            onDone: (ordered) => _applyReorder(pl.tracks, ordered),
            builder: (context, progress, onTap) => ProgressFill(
              progress: progress,
              shape: const CircleBorder(),
              over: true,
              child: GlassCircleIconButton(
                icon: Icons.auto_awesome_rounded,
                tooltip: progress == null
                    ? 'Smart Reorder: by tempo and key'
                    : 'Analyzing… tap to cancel',
                onPressed: onTap,
              ),
            ),
          ),
        if (pl.tracks.length > 1)
          LibrarySortButton(
            view: _view,
            options: SortKey.ofPlaylist,
            onChanged: _setView,
            glass: true,
          ),
      ],
      body: MediaDetailPage(
        detail: MediaDetail(
          title: pl.name,
          // Il colore della pagina dal primo brano, come prima; la faccia
          // invece e' il mosaico dei primi quattro dischi.
          imageUrl: pl.tracks.isEmpty ? '' : pl.tracks.first.thumbnailUrl,
          cover: PlaylistMosaic(tracks: pl.tracks),
          tracks: tracks,
          meta: const ['Playlist'],
          // Di tutta la playlist anche mentre si cerca.
          footnote: [songsSummary(pl.tracks)],
          onSwipeRemove: (track) => _remove(pl.name, track),
          tools: pl.tracks.length < SongFindField.minTracks
              ? null
              : SongFindField(
                  controller: _search,
                  collection: pl.name,
                  onChanged: (q) => setState(() => _query = q),
                ),
          empty: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: pl.tracks.isEmpty
                ? const EmptyState(
                    icon: Icons.music_note_rounded,
                    title: 'No songs yet',
                    message: 'Add songs from any song menu.',
                  )
                : EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No results',
                    message: 'Nothing in ${pl.name} matches "$_query".',
                  ),
          ),
        ),
      ),
    );
  }
}
