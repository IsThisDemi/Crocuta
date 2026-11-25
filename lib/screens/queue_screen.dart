import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/player_state.dart';
import '../widgets/content_width.dart';
import '../design/app_theme.dart';
import '../providers.dart';
import '../design/chrome.dart';
import '../widgets/empty_state.dart';
import '../widgets/equalizer_bars.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_tile.dart';
import '../widgets/progress_fill.dart';
import '../widgets/toast.dart';
import '../widgets/large_title.dart';
import '../widgets/spot_controls.dart';
import '../widgets/section_header.dart';

/// La coda, con la forma di quella di Apple Music.
///
/// In cima il brano che suona e le tre modalita' che decidono cosa viene
/// dopo; sotto, solo cio' che deve ancora suonare. Prima era un elenco unico
/// dal primo brano all'ultimo: quelli gia' ascoltati stavano in mezzo a
/// quelli da ascoltare, e con una coda lunga il brano in corso finiva
/// fuori schermo — proprio la riga che serve per orientarsi.
class QueueScreen extends ConsumerStatefulWidget {
  /// Dentro il player, al posto della copertina. Li' brano in corso e
  /// barre di sistema li ha gia' il player attorno: la coda mostra le
  /// modalita' e cio' che viene prima e dopo.
  final bool embedded;

  const QueueScreen({super.key, this.embedded = false});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// La cronologia sta chiusa: e' la parte che si guarda di rado.
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final queue = player.queue;
    final current = player.currentIndex;
    final notifier = ref.read(playerProvider.notifier);

    // I brani dopo quello in corso, e quelli prima. Senza brano in corso
    // (coda ripristinata e mai avviata) e' tutto "dopo".
    final start = current < 0 ? 0 : current + 1;
    final upcoming = start < queue.length
        ? queue.sublist(start)
        : const <Track>[];
    final history = current > 0 ? queue.sublist(0, current) : const <Track>[];

    // Niente SafeArea: il rientro in cima lo da' topContentInset, che sa
    // anche quando qualcun altro l'ha gia' messo. Dentro la SubPage aperta
    // dal brano in riproduzione una SafeArea sommava la propria altezza a
    // quella della barra di vetro, e la coda si apriva con duecento pixel
    // di vuoto sopra il titolo.
    final embedded = widget.embedded;
    return Padding(
      // Dentro il player la lista sfuma in cima: si scende un poco, cosi'
      // le modalita' stanno nel tratto pieno e non sotto la sfumatura.
      padding: EdgeInsets.only(
        top: embedded ? AppSpacing.xl : topContentInset(context),
      ),
      // Colonna centrata: su una finestra larga il contenuto si stirava
      // da bordo a bordo, con meta' schermo vuoto a destra.
      child: ContentWidth(
        maxWidth: ContentWidth.wide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(child: LargeTitle('Queue')),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${queue.length} song${queue.length == 1 ? '' : 's'}',
                        style: context.texts.titleMedium?.copyWith(
                          color: context.colors.accentMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (queue.isEmpty)
              const Expanded(
                child: EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'The queue is empty',
                  message: 'Search for a song and hit play.',
                ),
              )
            else
              Expanded(
                child: ReorderableListView.builder(
                  padding: EdgeInsets.only(
                    bottom: embedded
                        ? AppSpacing.lg
                        : listBottomPadding(context, ref),
                  ),
                  // Su desktop la maniglia serve: senza, trascinare una
                  // riga e scorrere l'elenco sarebbero lo stesso gesto.
                  buildDefaultDragHandles: false,
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!embedded)
                        if (player.current case final now?)
                          _NowPlaying(track: now, isPlaying: player.isPlaying),
                      // Le modalita' anche dentro il player: li' gli
                      // interruttori sono passati nel menu "…", e questo e'
                      // il posto dove servono, come nella coda di Apple
                      // Music — si vede subito l'effetto sull'elenco sotto.
                      _Modes(player: player),
                      if (history.isNotEmpty) ...[
                        _HistoryToggle(
                          count: history.length,
                          open: _showHistory,
                          onTap: () =>
                              setState(() => _showHistory = !_showHistory),
                        ),
                        if (_showHistory)
                          for (var i = 0; i < history.length; i++)
                            TrackTile(
                              track: history[i],
                              enableSwipeActions: false,
                              onTap: () => notifier.playAt(i),
                            ),
                      ],
                      _SectionTitle(
                        upcoming.isEmpty ? 'Nothing up next' : 'Up next',
                        // A caso l'ordine non conta: il prossimo lo sceglie
                        // la sorte, non la lista.
                        trailing: upcoming.length > 2 && !player.shuffle
                            ? const _SmartReorderButton()
                            : null,
                      ),
                    ],
                  ),
                  // Gli indici della lista contano da dopo il brano in
                  // corso; la coda vera li vuole assoluti. Lo stesso scarto
                  // su origine e destinazione, quindi la convenzione di
                  // ReorderableListView resta quella che resolveMove sa
                  // gia' leggere.
                  onReorder: (from, to) =>
                      notifier.moveInQueue(start + from, start + to),
                  itemCount: upcoming.length,
                  itemBuilder: (context, j) {
                    final i = start + j;
                    final track = queue[i];
                    return TrackTile(
                      key: ValueKey('${track.id}_$i'),
                      track: track,
                      // Nella coda "aggiungi alla coda" duplicherebbe il
                      // brano, e il trascinamento di lato si confonderebbe
                      // con quello per riordinare.
                      enableSwipeActions: false,
                      onTap: () => notifier.playAt(i),
                      extraMenuActions: [
                        TrackMenuAction(
                          icon: Icons.remove_circle_outline_rounded,
                          label: 'Remove from queue',
                          isDestructive: true,
                          onSelected: () => notifier.removeFromQueue(i),
                        ),
                      ],
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: context.colors.textFaint,
                            ),
                            tooltip: 'Remove from queue',
                            onPressed: () => notifier.removeFromQueue(i),
                          ),
                          ReorderableDragStartListener(
                            index: j,
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: context.colors.textFaint,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Il brano che suona, in cima.
class _NowPlaying extends StatelessWidget {
  final Track track;
  final bool isPlaying;

  const _NowPlaying({required this.track, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    // Il brano che suona come la cosa piu' grande della coda: la sua
    // macchia con i satelliti e il titolo grande. E' il punto da cui si
    // legge tutto quello che viene sotto.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 34),
            child: SpotCover(url: track.thumbnailUrl, size: 112, satellites: 3),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    EqualizerBars(
                      color: context.colors.accent,
                      animating: isPlaying,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isPlaying ? 'Now playing' : 'Paused',
                      style: context.texts.labelLarge?.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.headlineMedium,
                ),
                Text(
                  track.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium?.copyWith(
                    color: context.colors.accentMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shuffle, Repeat e Autoplay, come le tre capsule della coda di Apple.
///
/// Stanno qui oltre che nel player perche' e' qui che si decide cosa viene
/// dopo: guardando la coda si vede anche l'effetto di ognuna.
class _Modes extends ConsumerWidget {
  final PlayerState player;

  const _Modes({required this.player});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(playerProvider.notifier);
    final radio = ref.watch(radioProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter - 6,
        0,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      // Una riga sola, che si stringe se non ci sta: e' una frase,
      // "shuffle, repeat, autoplay", e a capo su un telefono stretto
      // diventava una parola sola sotto le altre due.
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.xs,
            children: [
              _ModePill(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle',
                active: player.shuffle,
                onTap: notifier.toggleShuffle,
              ),
              _ModePill(
                icon: player.repeat == RepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                label: player.repeat == RepeatMode.one
                    ? 'Repeat one'
                    : 'Repeat',
                active: player.repeat != RepeatMode.off,
                onTap: notifier.toggleRepeat,
              ),
              // L'infinito: quando la coda finisce, continua con brani simili
              // invece di fermarsi.
              _ModePill(
                icon: Icons.all_inclusive_rounded,
                label: 'Autoplay',
                active: radio,
                onTap: ref.read(radioProvider.notifier).toggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModePill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Una parola che si accende: spenta e' grigia, accesa prende il colore
    // del brano e la sua macchiolina davanti. Niente capsule: le tre
    // modalita' si leggono come una frase, "shuffle, repeat, autoplay".
    final colors = context.colors;
    final fg = active ? colors.accent : colors.textFaint;
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          textStyle: context.texts.headlineSmall?.copyWith(fontSize: 22),
        ),
        icon: Icon(icon, size: 22, color: fg),
        label: Text(label),
      ),
    );
  }
}

class _HistoryToggle extends StatelessWidget {
  final int count;
  final bool open;
  final VoidCallback onTap;

  const _HistoryToggle({
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Text('History', style: sectionTitleStyle(context)),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$count',
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.textMuted,
                fontFeatures: AppTypography.tabular,
              ),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: AppMotion.fast,
              child: Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const _SectionTitle(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(child: Text(text, style: sectionTitleStyle(context))),
          ?trailing,
        ],
      ),
    );
  }
}

/// Riordina cio' che viene dopo, per tempo e tonalita': con AutoMix ogni
/// passaggio scorre meglio. Il brano in corso resta dov'e'. Mentre analizza
/// il pulsante si riempie; premuto di nuovo, annulla.
class _SmartReorderButton extends ConsumerWidget {
  const _SmartReorderButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FillJobButton<bool>(
      job: (onProgress, cancelled) => ref
          .read(playerProvider.notifier)
          .smartReorderUpcoming(onProgress: onProgress, cancelled: cancelled),
      onDone: (done) {
        if (!done) return;
        showToast(
          'Queue Reordered for Smooth Transitions',
          icon: Icons.auto_awesome_rounded,
        );
      },
      builder: (context, progress, onTap) => ProgressFill(
        progress: progress,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: context.colors.accent,
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
          label: Text(progress == null ? 'Smart Reorder' : 'Analyzing…'),
          onPressed: onTap,
        ),
      ),
    );
  }
}
