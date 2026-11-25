import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../providers.dart';
import '../services/mini_player_window.dart';
import 'artwork_hero.dart';
import 'crocuta_mark.dart';
import 'mini_player.dart';
import 'seek_bar.dart';
import 'spot_controls.dart';
import 'album_link.dart';
import 'artist_links.dart';

/// Una destinazione della navigazione: la parola che la nomina.
class DenDestination {
  final String label;
  final IconData icon;

  const DenDestination(this.label, this.icon);
}

/// La "tana": la colonna a sinistra della finestra larga.
///
/// Sostituisce la tab bar di vetro sul Mac. Le destinazioni sono parole
/// grandi e strette, non icone: con lo spazio di una finestra si puo'
/// nominare dove si va, e la parola attiva — chiara, con la sua macchia del
/// colore del brano accanto — dice dove sei meglio di una pillola grigia
/// sotto un'icona. In fondo, il brano in ascolto: la copertina a macchia con
/// i suoi satelliti, il titolo e i comandi, sempre a portata invece che in
/// una capsula sopra la barra.
class DenRail extends ConsumerWidget {
  static const double width = 264;

  final List<DenDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  const DenRail({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(playerProvider.select((s) => s.current != null));
    // I semafori della finestra stanno qui sopra, nella tana.
    final top = MediaQuery.paddingOf(context).top + topWindowInsetFor(context);

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.ink800,
          border: Border(
            right: BorderSide(color: AppColors.outlineVariant, width: 1),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, top + 18, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Il marchio e il nome: l'icona dell'app nei colori del brano.
              Row(
                children: [
                  const CrocutaMark(size: 34),
                  const SizedBox(width: 10),
                  Text(
                    'Crocuta',
                    style: context.texts.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              for (var i = 0; i < destinations.length; i++)
                _Word(
                  label: destinations[i].label,
                  active: i == selected,
                  onTap: () => onSelected(i),
                ),
              const Spacer(),
              if (hasTrack) const _DockedPlayer(),
            ],
          ),
        ),
      ),
    );
  }

  /// Lo spazio per i semafori sul Mac.
  static double topWindowInsetFor(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.macOS ? 22 : 0;
}

class _Word extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Word({required this.label, required this.active, required this.onTap});

  @override
  State<_Word> createState() => _WordState();
}

class _WordState extends State<_Word> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = widget.active
        ? colors.textStrong
        : _hover
        ? colors.textStrong.withValues(alpha: 0.8)
        : colors.accentMuted.withValues(alpha: 0.72);

    return Semantics(
      button: true,
      selected: widget.active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                // La macchia del brano accanto alla parola attiva. Lo spazio
                // c'e' anche quando manca, cosi' le parole non ballano.
                SizedBox(
                  width: 22,
                  child: AnimatedScale(
                    scale: widget.active ? 1 : 0,
                    duration: AppMotion.base,
                    curve: AppMotion.emphasised,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(
                        dimension: 11,
                        child: LiveSpotDot(color: colors.accent),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.fast,
                    style: context.texts.displaySmall!.copyWith(
                      fontSize: 32,
                      height: 1.12,
                      color: color,
                    ),
                    child: Text(widget.label, maxLines: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Il brano in ascolto, in fondo alla tana.
class _DockedPlayer extends ConsumerWidget {
  const _DockedPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerProvider.select((s) => s.current));
    if (track == null) return const SizedBox.shrink();
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isLoading = ref.watch(playerProvider.select((s) => s.isLoading));
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffle));
    final player = ref.read(playerProvider.notifier);
    final colors = context.colors;

    // La copertina lascia a destra lo spazio per i satelliti.
    const cover = 150.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => MiniPlayer.open(context),
            child: ArtworkHero(
              url: track.thumbnailUrl,
              radius: AppRadius.xs,
              child: SpotCover(
                url: track.thumbnailUrl,
                size: cover,
                satellites: 3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        // Album e interpreti si aprono da qui, come nel player grande e
        // nello stesso ordine: titolo, dove sta, di chi e'. Prima erano
        // solo scritti, e per andare all'artista bisognava aprire il player.
        const SizedBox(height: 2),
        AlbumLink(track: track),
        const SizedBox(height: 2),
        ArtistLinks(
          track: track,
          align: TextAlign.start,
          style: context.texts.bodyMedium?.copyWith(color: colors.accentMuted),
        ),
        const SizedBox(height: 6),
        // La barra di avanzamento senza i margini propri dello Slider, che
        // qui la staccherebbero dal titolo allineato a sinistra.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 0),
          child: SeekBar(dense: true),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Icon(
              icon: Icons.shuffle_rounded,
              tooltip: 'Shuffle',
              active: shuffle,
              onPressed: player.toggleShuffle,
            ),
            _Icon(
              icon: Icons.fast_rewind_rounded,
              tooltip: 'Previous',
              onPressed: player.previous,
            ),
            SpotPlayButton(
              playing: isPlaying,
              loading: isLoading,
              onPressed: player.toggle,
              size: 54,
            ),
            _Icon(
              icon: Icons.fast_forward_rounded,
              tooltip: 'Next',
              onPressed: player.next,
            ),
            if (MiniPlayerWindow.isSupported)
              const _Icon(
                icon: Icons.picture_in_picture_alt_rounded,
                tooltip: 'Mini Player (⌥⌘M)',
                onPressed: MiniPlayerWindow.toggle,
              )
            else
              _Icon(
                icon: Icons.open_in_full_rounded,
                tooltip: 'Now Playing',
                onPressed: () => MiniPlayer.open(context),
              ),
          ],
        ),
      ],
    );
  }
}

class _Icon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const _Icon({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Quattro icone e il play in 212px: i tasti di Material (48, o 40
    // compatti) non ci starebbero, quindi un tasto su misura.
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 40,
          child: Icon(
            icon,
            size: 22,
            color: active ? colors.accent : colors.textStrong,
          ),
        ),
      ),
    );
  }
}
