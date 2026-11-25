import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/media_detail_page.dart';
import '../services/library_views.dart';
import '../services/smart_playlists.dart';
import 'detail_scaffold.dart';
import 'empty_state.dart';
import 'sub_page.dart';
import 'thumbnail.dart';
import '../design/app_theme.dart';
import 'spot_layouts.dart';
import 'content_width.dart';

/// La copertina di una playlist intelligente: i primi quattro brani a
/// mosaico, sotto un velo del suo colore, e l'icona. Il nome sta sotto,
/// come per ogni card: scritto anche sopra si leggeva due volte.
///
/// Il colore dice che tipo di playlist e' — e resta lo stesso da un giorno
/// all'altro —, il mosaico che cosa c'e' dentro oggi.
class SmartCover extends StatelessWidget {
  final SmartPlaylist playlist;

  const SmartCover({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final kind = playlist.kind;
    final art = [for (final t in playlist.tracks.take(4)) t.thumbnailUrl];
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            GridView.count(
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < 4; i++)
                  i < art.length
                      ? Thumbnail(url: art[i])
                      : const ColoredBox(color: Colors.black),
              ],
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    for (final c in playlist.colors) c.withValues(alpha: 0.82),
                  ],
                ),
              ),
            ),
            // Al centro: la copertina e' una macchia, e nell'angolo in alto
            // a sinistra il suo bordo tagliava l'icona a meta'.
            Center(
              child: Icon(kind.icon, color: Colors.white, size: side * 0.26),
            ),
          ],
        );
      },
    );
  }
}

/// Le playlist intelligenti in fila, come le "Made for You" di Apple.
/// Non disegna niente se non ce n'e' nessuna.
class SmartPlaylistRail extends ConsumerWidget {
  const SmartPlaylistRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(smartPlaylistsProvider);
    if (lists.isEmpty) return const SizedBox.shrink();
    // Ogni mix e' un grappolo delle sue copertine, con l'icona del tipo
    // (scoperta, ripeti, preferiti) sulla macchia grande.
    return SizedBox(
      height: 236,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter + RailBleed.of(context),
        ),
        itemCount: lists.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.lg),
        itemBuilder: (context, i) {
          final list = lists[i];
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SmartPlaylistScreen(id: list.id),
                ),
              ),
              child: SizedBox(
                width: 176,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SpotCluster(
                      size: 176,
                      urls: [
                        for (final t in list.tracks.take(3)) t.thumbnailUrl,
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    CoatCaption(
                      title: list.title,
                      subtitle: '${list.tracks.length} songs',
                      align: TextAlign.start,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Una playlist intelligente aperta: come una playlist, ma in sola lettura
/// — si rifa' da sola, e un brano tolto a mano tornerebbe al prossimo
/// ascolto.
class SmartPlaylistScreen extends ConsumerWidget {
  final String id;

  const SmartPlaylistScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref
        .watch(smartPlaylistsProvider)
        .where((p) => p.id == id)
        .firstOrNull;
    if (list == null) {
      return const SubPage(
        child: EmptyState(
          icon: Icons.auto_awesome_rounded,
          title: 'Nothing here yet',
          message: 'Keep listening: this playlist fills up on its own.',
        ),
      );
    }
    return DetailScaffold(
      body: MediaDetailPage(
        detail: MediaDetail(
          title: list.title,
          // Il colore della pagina dal primo brano, come le playlist.
          imageUrl: list.tracks.first.thumbnailUrl,
          cover: SmartCover(playlist: list),
          tracks: list.tracks,
          meta: const ['Smart Playlist'],
          footnote: [list.subtitle, '${list.tracks.length} songs'],
        ),
      ),
    );
  }
}
