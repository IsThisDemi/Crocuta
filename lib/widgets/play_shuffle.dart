import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../models/track.dart';
import '../providers.dart';

/// I due comandi "Riproduci" e "Casuale" di una raccolta.
///
/// Uno solo per album e playlist: ognuna ne aveva una copia, ed erano gia'
/// leggermente diverse fra loro. La pagina artista invece usa tre cerchi
/// senza etichetta, perche' li' la coppia rubava l'occhio alla foto.
///
/// "Riproduci" pieno d'accento, "Casuale" in grigio di vetro. Prima erano
/// tutti e due a fondo traslucido con il testo in accento: sopra una
/// copertina scura l'accento chiaro su un velo dello stesso colore si
/// leggeva poco (azzurrino su azzurrino), e i due comandi pesavano uguale
/// quando uno dei due e' chiaramente quello principale. La coppia non si
/// stira: ha una larghezza sua e resta centrata, invece di seguire la
/// finestra, cosi' non pesa piu' della copertina che la sovrasta.
class PlayShuffleButtons extends ConsumerWidget {
  final List<Track> tracks;

  const PlayShuffleButtons({super.key, required this.tracks});

  static const _maxWidth = 460.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final player = ref.read(playerProvider.notifier);

    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Row(
          children: [
            Expanded(
              child: _TintedButton(
                primary: true,
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                onPressed: () {
                  player.setShuffle(false);
                  player.playTrack(tracks.first, queue: tracks);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _TintedButton(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle',
                onPressed: () {
                  player.setShuffle(true);
                  final start = tracks[Random().nextInt(tracks.length)];
                  player.playTrack(start, queue: tracks);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TintedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Il comando principale: pieno d'accento invece che grigio.
  final bool primary;

  const _TintedButton({
    this.primary = false,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    // L'accento e' garantito chiaro (contrasto >= 4.5 sulla tela scura, vedi
    // toneMapAccent), quindi sopra ci va il testo scuro, non il bianco.
    final background = primary ? accent : Colors.white.withValues(alpha: 0.10);
    final foreground = primary ? AppColors.ink900 : context.colors.textStrong;
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: AppRadius.shape(AppRadius.pill),
          textStyle: context.texts.titleMedium,
        ),
      ),
    );
  }
}
