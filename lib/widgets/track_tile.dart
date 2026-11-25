import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../models/track.dart';
import '../providers.dart';
import 'equalizer_bars.dart';
import 'thumbnail.dart';
import 'track_context_menu.dart';
import 'toast.dart';

String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final h = d.inHours;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  // Senza lo zero davanti ai minuti: "2:55", non "02:55".
  if (h > 0) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
  return '${d.inMinutes}:$s';
}

/// A row for a single track.
///
/// Content rows stay opaque: in this design language glass is reserved for
/// chrome, so a list scrolling under the tab bar reads cleanly.
class TrackTile extends ConsumerWidget {
  final Track track;
  final VoidCallback? onTap;

  /// Invoked when the artist name is tapped (artist page navigation).
  final VoidCallback? onArtistTap;

  /// Long-press callback (for context menu).
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool isCurrent;
  final bool isPlaying;

  /// Extra entries appended to the context menu, e.g. "Rimuovi dalla coda".
  final List<TrackMenuAction> extraMenuActions;

  /// Lists that genuinely should not offer the menu can opt out.
  final bool enableContextMenu;

  /// Scorrere la riga di lato: a destra "riproduci dopo", a sinistra
  /// "aggiungi alla coda". Spento dove non ha senso — nella coda stessa,
  /// aggiungere alla coda duplicherebbe il brano che stai guardando.
  final bool enableSwipeActions;

  /// Quando c'e', scorrere a sinistra toglie il brano dalla raccolta invece
  /// di aggiungerlo alla coda, e la riga se ne va davvero.
  final VoidCallback? onSwipeRemove;

  /// Il numero della traccia al posto della copertina.
  ///
  /// Solo negli album: li' ogni riga ripeteva la stessa identica copertina,
  /// cioe' un quadrato che non diceva niente ripetuto quattordici volte.
  /// Apple ci mette il numero, che invece dice dove sei nel disco.
  final int? number;

  /// L'artista del disco, nelle righe di un album.
  ///
  /// La riga allora si fa come in Apple: il titolo, e sotto gli interpreti
  /// solo quando non sono gli stessi del disco — in "early life crisis"
  /// ogni riga ripeteva "Nettspend", e l'unica informazione vera era
  /// l'ospite di "pain talk". Riproduzioni e durata vanno a destra.
  final String? albumArtist;

  /// Riproduzioni e durata a destra, in colonne allineate, invece della
  /// durata in coda agli interpreti: la disposizione delle pagine di una
  /// raccolta — album, playlist, brani piaciuti — perche' si somiglino.
  final bool columns;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.onArtistTap,
    this.onLongPress,
    this.trailing,
    this.isCurrent = false,
    this.isPlaying = false,
    this.extraMenuActions = const [],
    this.enableContextMenu = true,
    this.number,
    this.albumArtist,
    this.enableSwipeActions = true,
    this.onSwipeRemove,
    this.columns = false,
  });

  /// Stesso nome, a meno di maiuscole e spazi.
  static bool _sameArtist(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.colors.accent;
    final album = albumArtist;
    final faint = context.texts.bodySmall?.copyWith(
      color: context.colors.textFaint,
      fontFeatures: AppTypography.tabular,
    );
    final titleText = Text(
      track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.texts.titleMedium?.copyWith(
        color: isCurrent ? accent : null,
        fontWeight: FontWeight.w700,
      ),
    );
    final artistText = GestureDetector(
      onTap: onArtistTap,
      child: Text(
        track.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // Gli interpreti nel colore del disco spento, come sotto le
        // copertine: la riga si legge in due toni, il brano e di chi e'.
        style: context.texts.bodyMedium?.copyWith(
          color: context.colors.accentMuted,
          fontWeight: onArtistTap != null ? FontWeight.w600 : null,
        ),
      ),
    );

    final leading = number != null
        ? SizedBox(
            width: 34,
            height: 52,
            child: Center(
              // Il brano che suona prende le barrette al posto del numero:
              // la riga dice che e' questa.
              child: isCurrent
                  ? EqualizerBars(color: accent, animating: isPlaying)
                  : Text(
                      '$number',
                      style: context.texts.titleLarge?.copyWith(
                        color: context.colors.accentMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
          )
        : SizedBox.square(
            dimension: 56,
            // Una macchia piccola sta piu' tonda (wobble 0.6): a 56px una
            // forma molto storta si legge come un errore. Il seme e'
            // l'indirizzo della copertina, come in [SpotThumbnail], cosi' la
            // riga ha la stessa macchia della coda e del dettaglio.
            child: Spot(
              seed: track.thumbnailUrl,
              wobble: 0.6,
              // Il brano in ascolto ha il contorno nel colore del brano.
              rim: isCurrent ? accent : Colors.white.withValues(alpha: 0.08),
              rimWidth: isCurrent ? 2.5 : 1.2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Thumbnail(url: track.thumbnailUrl),
                  if (isCurrent)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: EqualizerBars(
                          color: accent,
                          animating: isPlaying,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );

    final title = album == null
        ? titleText
        : Row(
            children: [
              Flexible(child: titleText),
              // Nell'album il bollino segue il titolo: sotto, la riga degli
              // interpreti di solito non c'e'.
              if (track.isExplicit) ...[
                const SizedBox(width: AppSpacing.xs),
                const _ExplicitBadge(),
              ],
            ],
          );

    final Widget? subtitle = album == null
        ? Row(
            children: [
              // Il bollino sta davanti agli interpreti, non accanto al
              // titolo: li' competerebbe con il nome del brano.
              if (track.isExplicit) ...[
                const _ExplicitBadge(),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Flexible(child: artistText),
              if (!columns)
                Text('  ·  ${formatDuration(track.duration)}', style: faint),
            ],
          )
        : _sameArtist(track.author, album)
        ? null
        : artistText;

    // Le riproduzioni in colonna a destra: dentro la riga dei metadati si
    // contenderebbero lo spazio con il nome degli artisti.
    final Widget end =
        trailing ??
        (album == null && !columns
            ? _Plays(track: track)
            // La durata sopra, chiara e col carattere dei titoli, e sotto gli
            // ascolti nel colore del brano: la stessa struttura di titolo e
            // artista a sinistra.
            : SizedBox(
                width: 78,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatDuration(track.duration),
                      style: context.texts.titleLarge?.copyWith(
                        color: context.colors.textStrong.withValues(alpha: 0.9),
                        fontFeatures: AppTypography.tabular,
                      ),
                    ),
                    // Senza ascolti la riga sotto resta vuota: cosi' la
                    // durata sta sempre all'altezza del titolo.
                    if (track.playsShort == null)
                      const SizedBox(height: 20)
                    else
                      _Plays(track: track),
                  ],
                ),
              ));

    final tile = _TrackRow(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: leading,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          if (subtitle != null) ...[const SizedBox(height: 2), subtitle],
        ],
      ),
      trailing: end,
    );

    final withMenu = enableContextMenu
        // Wrapping here means every list in the app gets the menu at once,
        // instead of eight call sites each remembering to add it.
        ? TrackContextMenuRegion(
            track: track,
            extraActions: extraMenuActions,
            onLongPress: onLongPress,
            child: tile,
          )
        : tile;

    if (!enableSwipeActions) return withMenu;
    return _Swipe(track: track, onRemove: onSwipeRemove, child: withMenu);
  }
}

/// Le due azioni a scorrimento, come in Apple Music.
///
/// La riga non se ne va: `confirmDismiss` esegue l'azione e risponde di no,
/// cosi' torna al suo posto. Dismissible e' fatto per togliere, ma qui la
/// sua fisica serve solo a dare al gesto soglia e ritorno elastico.
///
/// La chiave non deve essere unica nella lista: il Dismissible e' l'unico
/// figlio di questa riga, quindi non ha fratelli con cui confondersi —
/// anche quando lo stesso brano compare due volte.
class _Swipe extends ConsumerWidget {
  final Track track;
  final Widget child;
  final VoidCallback? onRemove;

  const _Swipe({required this.track, required this.child, this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.colors.accent;
    return Dismissible(
      key: ValueKey('swipe-${track.id}'),
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
        DismissDirection.endToStart: 0.28,
      },
      background: _SwipeBackground(
        color: accent,
        icon: Icons.playlist_play_rounded,
        label: 'Play next',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: onRemove != null
          ? _SwipeBackground(
              color: context.colors.danger,
              icon: Icons.heart_broken_rounded,
              label: 'Remove',
              alignment: Alignment.centerRight,
            )
          : _SwipeBackground(
              color: context.colors.radio,
              icon: Icons.queue_music_rounded,
              label: 'Add to queue',
              alignment: Alignment.centerRight,
            ),
      // Togliere va solo a sinistra, e la riga esce davvero: chi la toglie
      // la leva anche dalla lista nello stesso fotogramma.
      onDismissed: (_) => onRemove?.call(),
      confirmDismiss: (direction) async {
        if (onRemove != null && direction == DismissDirection.endToStart) {
          return true;
        }
        final player = ref.read(playerProvider.notifier);
        final next = direction == DismissDirection.startToEnd;
        if (next) {
          player.playNext(track);
        } else {
          player.addToQueue(track);
        }
        // La riga torna indietro subito: senza un riscontro l'azione
        // sembrerebbe non essere successa.
        HapticFeedback.mediumImpact();
        showToast(
          next ? 'Playing Next' : 'Added to Queue',
          icon: next ? Icons.playlist_play_rounded : Icons.playlist_add_rounded,
        );
        return false;
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final start = alignment == Alignment.centerLeft;
    return ColoredBox(
      color: color.withValues(alpha: 0.9),
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!start) Text(label, style: context.texts.titleSmall),
              if (!start) const SizedBox(width: AppSpacing.xs),
              Icon(icon, color: Colors.white),
              if (start) const SizedBox(width: AppSpacing.xs),
              if (start) Text(label, style: context.texts.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il numero di riproduzioni del brano, quando YouTube Music lo dichiara.
class _Plays extends StatelessWidget {
  final Track track;

  const _Plays({required this.track});

  @override
  Widget build(BuildContext context) {
    final plays = track.playsShort;
    if (plays == null) return const SizedBox.shrink();
    final color = context.colors.accentMuted;
    // Gli ascolti nel colore del brano, con il piccolo triangolo del play
    // davanti: si capisce cosa conta quel numero senza scriverlo.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_arrow_rounded, size: 16, color: color),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            plays,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleMedium?.copyWith(
              color: color,
              fontFeatures: AppTypography.tabular,
            ),
          ),
        ),
      ],
    );
  }
}

/// Il bollino di contenuto esplicito.
///
/// Un glifo, non la parola: e' la convenzione di ogni app musicale, e in
/// una riga alta quaranta punti una parola intera non ci sta.
class _ExplicitBadge extends StatelessWidget {
  const _ExplicitBadge();

  @override
  Widget build(BuildContext context) {
    final color = context.colors.accentMuted;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'E',
        style: context.texts.labelSmall?.copyWith(
          fontSize: 10,
          height: 1,
          letterSpacing: 0,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

/// La riga di un brano: niente fondo, niente separatori, niente riquadro
/// al passaggio del mouse. Col mouse sopra la copertina si ingrandisce un
/// poco e titolo e artista scivolano appena a destra: la riga si sporge
/// verso di te. Premendo, la copertina si stringe.
class _TrackRow extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget leading;
  final Widget body;
  final Widget trailing;

  const _TrackRow({
    required this.onTap,
    required this.onLongPress,
    required this.leading,
    required this.body,
    required this.trailing,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    const d = Duration(milliseconds: 200);
    const curve = Curves.easeOutCubic;
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 9,
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: _down ? 0.92 : (_hover ? 1.1 : 1),
                duration: d,
                curve: curve,
                child: widget.leading,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSlide(
                  offset: Offset(_hover ? 0.012 : 0, 0),
                  duration: d,
                  curve: curve,
                  child: widget.body,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
