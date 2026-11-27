import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../models/track.dart';
import '../navigation.dart';
import '../providers.dart';
import '../screens/video_screen.dart';
import 'glass_surfaces.dart';
import 'lifted_menu.dart';
import 'thumbnail.dart';
import 'toast.dart';

/// One entry in the track menu.
class TrackMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  /// Disabled entries stay visible and greyed out rather than disappearing:
  /// a menu whose height changes from row to row is disorienting, and a
  /// track's album id is often filled in moments later by background
  /// enrichment, so the same row can legitimately become actionable.
  final bool enabled;

  final bool isDestructive;

  const TrackMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.enabled = true,
    this.isDestructive = false,
  });
}

/// Builds the standard action list for [track].
///
/// Both presentations render from this one list, so they cannot drift apart.
List<TrackMenuAction> buildTrackMenuActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  List<TrackMenuAction> extra = const [],
}) {
  final player = ref.read(playerProvider.notifier);
  final favorites = ref.read(favoritesProvider.notifier);
  final downloads = ref.watch(downloadsProvider);
  final isFavorite = ref.read(favoritesProvider).any((t) => t.id == track.id);

  // Captured before any sheet opens: inside a modal route, Navigator.of
  // resolves to the sheet, which is about to be popped.
  final nav = Navigator.of(context, rootNavigator: false);

  return [
    // Un video della ricerca si ascolta come una canzone; guardarlo e' la
    // prima cosa che ci si aspetta di trovare qui.
    if (track.isVideo)
      TrackMenuAction(
        icon: Icons.smart_display_rounded,
        label: 'Watch video',
        onSelected: () => VideoScreen.open(nav.context, track),
      ),
    TrackMenuAction(
      icon: Icons.radio_rounded,
      label: 'Start radio',
      onSelected: () => player.startRadio(track),
    ),
    TrackMenuAction(
      icon: Icons.playlist_play_rounded,
      label: 'Play next',
      onSelected: () => player.playNext(track),
    ),
    TrackMenuAction(
      icon: Icons.queue_music_rounded,
      label: 'Add to queue',
      onSelected: () => player.addToQueue(track),
    ),
    TrackMenuAction(
      icon: Icons.library_add_rounded,
      label: 'Add to playlist…',
      onSelected: () => _pickPlaylist(nav.context, ref, track),
    ),
    TrackMenuAction(
      icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      label: isFavorite ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      onSelected: () => favorites.toggle(track),
    ),
    TrackMenuAction(
      icon: downloads.has(track.id)
          ? Icons.download_done_rounded
          : downloads.isDownloading(track.id)
          ? Icons.downloading_rounded
          : Icons.download_rounded,
      label: downloads.has(track.id)
          ? 'Remove download'
          : downloads.isDownloading(track.id)
          ? 'Downloading…'
          : 'Download',
      enabled: !downloads.isDownloading(track.id),
      onSelected: () async {
        final notifier = ref.read(downloadsProvider.notifier);
        if (downloads.has(track.id)) {
          await notifier.remove(track.id);
          return;
        }
        // Il riscontro serve: scaricare puo' durare, e senza un messaggio
        // sembra che il comando non abbia fatto niente.
        showToast('Downloading…', icon: Icons.downloading_rounded);
        final ok = await notifier.download(track);
        if (ok) {
          showToast('Downloaded', icon: Icons.download_done_rounded);
        } else {
          showToast('Download Failed', icon: Icons.error_outline_rounded);
        }
      },
    ),
    TrackMenuAction(
      icon: Icons.person_rounded,
      label: 'Go to artist',
      enabled: track.artistId != null,
      onSelected: () => openArtist(nav.context, track.artistId!, track.author),
    ),
    TrackMenuAction(
      icon: Icons.album_rounded,
      label: 'Go to album',
      enabled: track.albumId != null,
      onSelected: () =>
          openAlbum(nav.context, track.albumId!, title: track.albumName ?? ''),
    ),
    TrackMenuAction(
      icon: Icons.link_rounded,
      label: 'Copy link',
      onSelected: () async {
        await Clipboard.setData(ClipboardData(text: track.ytmUrl));
        showToast('Link Copied', icon: Icons.link_rounded);
      },
    ),
    ...extra,
  ];
}

/// Opens the track menu.
///
/// The presentation follows the *gesture*, not the platform: a secondary tap
/// (right click, Control-click, two-finger trackpad click) passes a
/// [globalPosition] and gets a menu at the pointer; a long press passes none
/// and gets a bottom sheet. Both work everywhere.
Future<void> showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  Offset? globalPosition,
  List<TrackMenuAction> extra = const [],
  Rect? anchor,
  Widget? preview,
}) async {
  final actions = buildTrackMenuActions(context, ref, track, extra: extra);
  final menuItems = [
    for (final a in actions)
      GlassMenuItem(
        value: a,
        icon: a.icon,
        label: a.label,
        enabled: a.enabled,
        isDestructive: a.isDestructive,
      ),
  ];

  // Pressione lunga su una riga: la riga si solleva e il menu le sta
  // attaccato, come in iOS.
  if (anchor != null && preview != null) {
    final selected = await showLiftedMenu<TrackMenuAction>(
      context: context,
      anchor: anchor,
      preview: preview,
      items: menuItems,
    );
    selected?.onSelected();
    return;
  }

  if (globalPosition != null) {
    final selected = await showGlassMenu<TrackMenuAction>(
      context: context,
      globalPosition: globalPosition,
      items: menuItems,
    );
    selected?.onSelected();
    return;
  }

  if (!context.mounted) return;
  final selected = await showGlassSheet<TrackMenuAction>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(track: track),
        const Divider(height: 1),
        for (final a in actions)
          ListTile(
            enabled: a.enabled,
            leading: Icon(
              a.icon,
              color: a.isDestructive ? sheetContext.colors.danger : null,
            ),
            title: Text(
              a.label,
              style: a.isDestructive
                  ? TextStyle(color: sheetContext.colors.danger)
                  : null,
            ),
            onTap: () => Navigator.of(sheetContext).pop(a),
          ),
      ],
    ),
  );
  selected?.onSelected();
}

class _SheetHeader extends StatelessWidget {
  final Track track;

  const _SheetHeader({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          // Piccola, quindi poco storta: la stessa macchia della riga.
          SizedBox.square(
            dimension: 44,
            child: SpotThumbnail(url: track.thumbnailUrl, wobble: 0.6),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium,
                ),
                Text(
                  track.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Second step of "Aggiungi a playlist…".
Future<void> _pickPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final playlists = ref.read(playlistsProvider);

  if (playlists.isEmpty) {
    showToast(
      'No Playlists Yet — Create One in Library',
      icon: Icons.queue_music_rounded,
    );
    return;
  }

  if (!context.mounted) return;
  final index = await showGlassSheet<int>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Text('Add to playlist', style: sheetContext.texts.titleLarge),
            ],
          ),
        ),
        for (var i = 0; i < playlists.length; i++)
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: Text(playlists[i].name),
            subtitle: Text(
              '${playlists[i].tracks.length} song${playlists[i].tracks.length == 1 ? '' : 's'}',
            ),
            onTap: () => Navigator.of(sheetContext).pop(i),
          ),
      ],
    ),
  );

  if (index == null) return;
  await ref.read(playlistsProvider.notifier).addTrack(index, track);
  showToast(
    'Added to ${playlists[index].name}',
    icon: Icons.playlist_add_check_rounded,
  );
}

/// Wraps any widget so that a long press or a secondary tap opens the menu.
class TrackContextMenuRegion extends ConsumerWidget {
  final Widget child;
  final Track track;
  final List<TrackMenuAction> extraActions;

  /// Set when the caller wants to keep its own long-press behaviour.
  final VoidCallback? onLongPress;

  const TrackContextMenuRegion({
    super.key,
    required this.child,
    required this.track,
    this.extraActions = const [],
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (d) => showTrackMenu(
        context,
        ref,
        track,
        globalPosition: d.globalPosition,
        extra: extraActions,
      ),
      onLongPress:
          onLongPress ??
          () {
            HapticFeedback.mediumImpact();
            final box = context.findRenderObject() as RenderBox?;
            showTrackMenu(
              context,
              ref,
              track,
              extra: extraActions,
              anchor: box == null || !box.hasSize
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
              preview: child,
            );
          },
      child: child,
    );
  }
}
