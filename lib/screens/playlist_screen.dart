import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/detail_scaffold.dart';
import 'media_detail_page.dart';

/// A playlist from YouTube Music (distinct from the user's own playlists).
/// Thin adapter over [MediaDetailPage].
class PlaylistScreen extends ConsumerWidget {
  final String browseId;
  final String title;

  const PlaylistScreen({super.key, required this.browseId, this.title = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistPageProvider(browseId));

    return DetailScaffold(
      body: playlist.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Could not load the playlist',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (p) => MediaDetailPage(
          detail: MediaDetail(
            title: p.title == 'Playlist' ? title : p.title,
            imageUrl: p.thumbnailUrl,
            tracks: p.tracks,
            meta: const ['Playlist'],
            footnote: [
              '${p.tracks.length} song${p.tracks.length == 1 ? '' : 's'}',
            ],
          ),
        ),
      ),
    );
  }
}
