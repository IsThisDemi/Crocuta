import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/content_width.dart';
import '../widgets/large_title.dart';
import '../widgets/liquid.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/track.dart';
import '../providers.dart';
import '../services/library_views.dart';
import '../services/sync_service.dart';
import '../widgets/spot_layouts.dart';
import '../design/spot.dart';
import '../widgets/section_header.dart';
import '../widgets/sub_page.dart';
import '../widgets/thumbnail.dart';
import 'albums_screen.dart';
import 'artists_screen.dart';
import 'downloads_screen.dart';
import 'favorites_screen.dart';
import 'playlists_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import '../widgets/toast.dart';

/// The "Libreria" tab: one entry point for everything the user owns.
///
/// Replaces four separate bottom tabs (Preferiti, Playlist, Stats — plus the
/// recents that were stranded on Home). The shape follows Apple Music: a
/// short list of destination rows first, then the recently played below,
/// rather than a grid of equally-weighted cards.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final playlists = ref.watch(playlistsProvider);
    final downloads = ref.watch(downloadsProvider);
    final follows = ref.watch(followsProvider);
    final added = ref.watch(recentlyAddedProvider);
    final albums = ref.watch(libraryAlbumsProvider);

    // Non si avvolge piu' qui: ogni pagina si porta il proprio titolo
    // nella barra di vetro, perche' solo lei sa cosa scriverci accanto —
    // il numero di brani, il pulsante per creare una playlist.
    void push(Widget page) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    final lastSync = ref.watch(lastSyncProvider);

    // La cornice sta fuori dalla SafeArea: deve vedere l'area sicura vera
    // per mettere il titolo piccolo sotto l'orologio, e dentro la SafeArea
    // quel margine risulterebbe gia' consumato.
    return CollapsingTitleFrame(
      title: 'Library',
      child: SafeArea(
        bottom: false,
        // Colonna centrata: su una finestra larga il contenuto si stirava
        // da bordo a bordo, con meta' schermo vuoto a destra.
        child: ContentWidth(
          maxWidth: ContentWidth.wide,
          child: ListView(
            padding: EdgeInsets.only(
              top: topWindowInset(context),
              bottom: listBottomPadding(context, ref),
            ),
            children: [
              // Il titolo con l'azione accanto, non dentro l'elenco: la
              // sincronizzazione e' una cosa che si fa, non un posto dove si
              // va, e messa per prima fra le destinazioni rompeva il ritmo
              // della lista proprio alla prima riga — due righe di testo dove
              // le altre ne hanno una, senza conteggio ne' freccia.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(child: const LargeTitle('Library')),
                    ValueListenableBuilder(
                      valueListenable: SyncService.config,
                      builder: (context, config, _) => config.isComplete
                          ? _SyncButton(
                              lastSync: lastSync,
                              onTap: () => runSync(ref),
                            )
                          : const SizedBox.shrink(),
                    ),
                    // Statistiche e impostazioni accanto al titolo, non fra
                    // le righe: non sono cose che hai salvato, e in mezzo a
                    // Brani, Album e Artisti si leggevano come una
                    // categoria della libreria. In Apple Music stanno
                    // dietro l'icona in alto a destra.
                    // `native: false` perche' stanno dentro una lista che
                    // scorre: un vetro di sistema per tasto, spostato a ogni
                    // fotogramma, su iPhone costa.
                    const SizedBox(width: AppSpacing.xs),
                    GlassCircleIconButton(
                      icon: Icons.bar_chart_rounded,
                      tooltip: 'Stats',
                      native: false,
                      onPressed: () => push(const StatsScreen()),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    GlassCircleIconButton(
                      icon: Icons.settings_rounded,
                      tooltip: 'Settings',
                      native: false,
                      onPressed: () => push(const SettingsScreen()),
                    ),
                  ],
                ),
              ),

              // Le raccolte come parole grandi, ognuna col suo conto e un
              // grappolo delle sue copertine: si riconosce da lontano dove
              // stanno i preferiti e dove gli album, senza icone.
              _WordRow(
                label: 'Liked songs',
                count: favorites.length,
                covers: [for (final t in favorites.take(12)) t.thumbnailUrl],
                onTap: () => push(const FavoritesScreen()),
              ),
              _WordRow(
                label: 'Playlists',
                count: playlists.length,
                covers: [
                  for (final p in playlists.take(3))
                    if (p.tracks.isNotEmpty) p.tracks.first.thumbnailUrl,
                ],
                onTap: () => push(const PlaylistsScreen()),
              ),
              _WordRow(
                label: 'Artists',
                count: follows.length,
                covers: [for (final a in follows.take(3)) a.thumbnailUrl ?? ''],
                onTap: () => push(const ArtistsScreen()),
              ),
              _WordRow(
                label: 'Albums',
                count: albums.length,
                covers: [for (final a in albums.take(12)) a.thumbnailUrl],
                onTap: () => push(const AlbumsScreen()),
              ),
              _WordRow(
                label: 'Downloads',
                count: downloads.tracks.length,
                covers: [
                  for (final t in downloads.tracks.take(12)) t.thumbnailUrl,
                ],
                onTap: () => push(const DownloadsScreen()),
              ),

              // Gli ultimi aggiunti a manto, come "Listen again" in Home.
              if (added.isNotEmpty) ...[
                const SectionHeader(title: 'Recently added'),
                SpotCoat(
                  items: [
                    for (final t in _distinctCovers(added).take(9))
                      CoatItem(
                        imageUrl: t.thumbnailUrl,
                        title: t.title,
                        subtitle: t.author,
                        onTap: () => ref
                            .read(playerProvider.notifier)
                            .playTrack(t, queue: added.take(12).toList()),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full list of recently played tracks, pushed from the library.
class RecentsScreen extends ConsumerWidget {
  final List<Track> tracks;

  const RecentsScreen({super.key, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SubPage(
      title: 'Recently played',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: AppSpacing.huge),
              itemCount: tracks.length,
              itemBuilder: (_, i) => ListTile(
                leading: SizedBox(
                  width: 48,
                  height: 48,
                  child: SpotThumbnail(
                    url: tracks[i].thumbnailUrl,
                    wobble: 0.6,
                  ),
                ),
                title: Text(tracks[i].title, maxLines: 1),
                subtitle: Text(tracks[i].author, maxLines: 1),
                // Tutta la lista in coda, come le altre sezioni.
                onTap: () => ref
                    .read(playerProvider.notifier)
                    .playTrack(tracks[i], queue: tracks),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Il pulsante della sincronizzazione, accanto al titolo.
///
/// Sta qui e non fra le destinazioni perche' e' un'azione: l'elenco sotto
/// dice dove puoi andare, questo dice cosa puoi fare. Quando e' riuscita
/// l'ultima volta lo racconta il suggerimento, invece di occupare una
/// seconda riga sempre visibile per un dato che si guarda una volta ogni
/// tanto.
class _SyncButton extends StatefulWidget {
  final DateTime? lastSync;
  final Future<SyncOutcome> Function() onTap;

  const _SyncButton({required this.lastSync, required this.onTap});

  @override
  State<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<_SyncButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await widget.onTap();
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == SyncOutcome.failed) {
      showToast('Sync Failed', icon: Icons.cloud_off_rounded);
    }
  }

  String get _tooltip {
    if (_busy) return 'Syncing…';
    final at = widget.lastSync;
    if (at == null) return 'Sync — never synced';
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'Synced just now';
    if (ago.inHours < 1) return 'Synced ${ago.inMinutes} min ago';
    if (ago.inDays < 1) return 'Synced ${ago.inHours} h ago';
    return 'Synced ${ago.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    // Lo stato scritto, non solo nel suggerimento: un'icona da sola non
    // diceva ne' cosa fosse ne' se avesse funzionato, e il suggerimento su
    // un telefono non si vede mai.
    // Una macchia con la nuvola, come statistiche e impostazioni accanto:
    // lo stato (quando, se sta sincronizzando) sta nel suggerimento, e la
    // nuvola dice da sola se e' andata.
    return Stack(
      alignment: Alignment.center,
      children: [
        GlassCircleIconButton(
          icon: Icons.cloud_done_rounded,
          tooltip: _tooltip,
          onPressed: _busy ? null : _run,
        ),
        if (_busy)
          IgnorePointer(
            child: SizedBox.square(
              dimension: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.accent,
              ),
            ),
          ),
      ],
    );
  }
}

/// Una raccolta della libreria: la parola grande, il conto piccolo accanto
/// e un grappolo delle sue copertine a destra.
class _WordRow extends StatefulWidget {
  final String label;
  final int count;
  final List<String> covers;
  final VoidCallback onTap;

  const _WordRow({
    required this.label,
    required this.count,
    required this.covers,
    required this.onTap,
  });

  @override
  State<_WordRow> createState() => _WordRowState();
}

class _WordRowState extends State<_WordRow> {
  bool _hover = false;

  /// Le copertine senza doppioni (tre brani dello stesso album sono una
  /// copertina sola); se non ce n'e' nessuna, tre macchie del colore del
  /// brano, cosi' la colonna resta allineata.
  Widget _covers(BuildContext context, double size) {
    final seen = <String>{};
    final urls = [
      for (final c in widget.covers)
        if (c.isNotEmpty && seen.add(c)) c,
    ].take(3).toList();
    if (urls.isNotEmpty) return SpotCluster(urls: urls, size: size);
    final c = context.colors.accentMuted;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          for (final (i, f) in [(0, 0.7), (1, 0.4), (2, 0.26)].indexed)
            Positioned(
              left: i == 0 ? 0 : null,
              right: i == 0 ? null : (i == 1 ? 0 : size * 0.02),
              top: i == 1 ? 0 : null,
              bottom: i == 1 ? null : (i == 2 ? size * 0.04 : 0),
              width: size * f.$2,
              height: size * f.$2,
              child: SpotMotionBuilder(
                builder: (context, t) => DecoratedBox(
                  decoration: ShapeDecoration(
                    color: c.withValues(alpha: 0.5 - i * 0.12),
                    shape: SpotBorder(
                      seed: '${widget.label}#$i',
                      time: t,
                      music: SpotMotion.musicOf(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              // Il grappolo prima della parola, come l'icona di una voce:
              // a destra, staccato da tutta la larghezza della pagina,
              // non si capiva di quale parola fosse.
              AnimatedScale(
                scale: _hover ? 1.06 : 1,
                duration: AppMotion.fast,
                child: _covers(context, wide ? 78 : 58),
              ),
              SizedBox(width: wide ? AppSpacing.lg : AppSpacing.md),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: widget.label,
                    children: [
                      if (widget.count > 0)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.top,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, top: 4),
                            child: Text(
                              '${widget.count}',
                              style: context.texts.titleMedium?.copyWith(
                                color: colors.accentMuted,
                                fontFeatures: AppTypography.tabular,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.displayMedium?.copyWith(
                    fontSize: wide ? 52 : 38,
                    height: 1.05,
                    color: _hover ? colors.accent : colors.textStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un brano per copertina: tre brani dello stesso album aggiunti insieme
/// non devono riempire il manto della stessa immagine.
List<Track> _distinctCovers(List<Track> tracks) {
  final seen = <String>{};
  return [
    for (final t in tracks)
      if (t.thumbnailUrl.isEmpty || seen.add(t.thumbnailUrl)) t,
  ];
}
