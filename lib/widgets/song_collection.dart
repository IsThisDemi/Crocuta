import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import '../models/track.dart';
import '../shortcuts.dart';
import 'thumbnail.dart';
import 'toast.dart';

/// I pezzi comuni alle pagine di una raccolta di brani tua: i piaciuti e
/// le playlist. Ricerca, "Annulla" dopo aver tolto un brano e la copertina
/// a mosaico; l'ordinamento e i filtri stanno in `library_sort_button.dart`,
/// perche' li usano anche dischi, artisti e scaricati.

/// Avvisa che un brano e' stato tolto, con "Undo" per rimetterlo.
///
void showRemovedSnack({
  required Track track,
  required String from,
  required VoidCallback undo,
}) {
  showToast(
    'Removed from $from',
    icon: Icons.remove_circle_outline_rounded,
    actionLabel: 'Undo',
    onAction: undo,
  );
}

/// La copertina di una playlist: le prime quattro copertine a mosaico.
///
/// Come Apple Music per le playlist senza un'immagine propria. Con meno di
/// quattro dischi diversi il mosaico ripeterebbe la stessa immagine, quindi
/// resta la prima copertina intera; senza brani, una nota su fondo scuro.
class PlaylistMosaic extends StatelessWidget {
  final List<Track> tracks;

  const PlaylistMosaic({super.key, required this.tracks});

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final covers = [
      for (final t in tracks)
        if (t.thumbnailUrl.isNotEmpty && seen.add(t.thumbnailUrl))
          t.thumbnailUrl,
    ];
    // Tutto il mosaico e' una macchia sola, non quattro: il seme e' la
    // prima copertina, che e' anche l'immagine della playlist, quindi la
    // macchia resta la stessa della riga in libreria e del dettaglio.
    return Spot(
      seed: covers.isEmpty ? '' : covers.first,
      rim: Colors.white.withValues(alpha: 0.08),
      child: _tiles(context, covers),
    );
  }

  Widget _tiles(BuildContext context, List<String> covers) {
    if (covers.isEmpty) {
      return ColoredBox(
        color: AppColors.ink600,
        child: LayoutBuilder(
          builder: (context, c) => Icon(
            Icons.music_note_rounded,
            color: context.colors.textMuted,
            size: c.maxWidth * 0.4,
          ),
        ),
      );
    }
    if (covers.length < 4) return Thumbnail(url: covers.first);
    return Column(
      children: [
        for (final row in [covers.sublist(0, 2), covers.sublist(2, 4)])
          Expanded(
            child: Row(
              children: [
                for (final url in row) Expanded(child: Thumbnail(url: url)),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Find in ...": filtra la lista mentre si scrive.
class SongFindField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Il nome della raccolta, per il suggerimento "Find in" seguito dal nome.
  final String collection;

  const SongFindField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.collection,
  });

  /// Sotto questo numero di brani il campo non compare: una lista che sta
  /// tutta in uno schermo si scorre prima di quanto si scriva.
  static const minTracks = 8;

  @override
  Widget build(BuildContext context) {
    // Una riga sottolineata larga quanto la lista, non una capsula grigia
    // centrata: in Macchia i campi sono testo su nero, e la linea si accende
    // del colore del disco quando ci scrivi.
    return SearchFieldShortcuts(
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textAlignVertical: TextAlignVertical.center,
          enableSuggestions: false,
          autocorrect: false,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          style: context.texts.titleMedium,
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            hintText: 'Find in $collection',
            hintStyle: context.texts.titleMedium?.copyWith(
              color: context.colors.textFaint,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 22,
              color: context.colors.accentMuted,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            suffixIcon: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      tooltip: 'Clear',
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
            border: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: context.colors.accent, width: 1.6),
            ),
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }
}
