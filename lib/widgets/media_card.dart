import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/spot.dart';
import 'artwork_pressable.dart';
import 'content_width.dart';
import 'thumbnail.dart';

/// A square (or circular) artwork card with a title and optional subtitle.
///
/// One widget for every horizontal rail in the app: recently played,
/// favourites, search results for albums and playlists, artist carousels.
/// Each of those used to ship its own copy with slightly different sizes,
/// radii and shadows.
class MediaCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final double width;

  /// Gli artisti si centrano sotto la loro macchia, come le foto tonde di
  /// prima; la forma e' una macchia per tutti.
  final bool circle;

  /// Una copertina disegnata al posto dell'immagine: quella delle playlist
  /// intelligenti, che un'immagine sola non ce l'hanno.
  final Widget? cover;

  /// Il seme della macchia, quando non basta [imageUrl]: una copertina
  /// disegnata deve avere la stessa macchia che ha nella sua pagina.
  final String? seed;

  const MediaCard({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.width = 134,
    this.circle = false,
    this.cover,
    this.seed,
  });

  @override
  Widget build(BuildContext context) {
    // Copertine e artisti sono tutti macchie: niente piu' cerchi e
    // quadrati arrotondati. Il seme e' l'indirizzo dell'immagine, come in
    // [SpotThumbnail], quindi la scheda ha la stessa macchia della riga e
    // del dettaglio; la stessa forma va al velo del mouse.
    // Le copertine disegnate ([cover]) spesso non hanno indirizzo: senza
    // un [seed] prendono il titolo, se no tutte avrebbero la stessa macchia.
    final seed = this.seed ?? (imageUrl.isEmpty ? title : imageUrl);
    final shape = SpotBorder(seed: seed);

    return SizedBox(
      width: width,
      // La reazione la fa la sola copertina, sulla sua forma: un InkWell
      // accendeva un riquadro attorno a copertina e titolo, quadrato anche
      // sotto la foto tonda di un artista.
      child: ArtworkPressable(
        onTap: onTap,
        onLongPress: onLongPress,
        builder: (context, state) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: circle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Niente ombra: un'ombra rettangolare dietro una macchia si
              // vede come un riquadro che con la forma non c'entra.
              SpotMotionBuilder(
                builder: (context, t) => PressableArtwork(
                  state: state,
                  shape: shape.copyWith(time: t),
                  child: SizedBox.square(
                    dimension: width,
                    child: Spot(
                      seed: seed,
                      rim: Colors.white.withValues(alpha: 0.08),
                      child: cover ?? Thumbnail(url: imageUrl),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                style: context.texts.titleSmall,
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: circle ? TextAlign.center : TextAlign.start,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.accentMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal rail of [MediaCard]s with the app's standard gutters.
class MediaCardRail extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final double height;

  const MediaCardRail({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    // Alta abbastanza per un titolo su DUE righe piu' il sottotitolo.
    //
    // Con 196 ci stava solo un titolo di una riga: bastava una classifica
    // che si chiama "Daily Top Music Videos - Italy" per sfondare di sei
    // pixel. Il conto e': 4 di margine + 134 di copertina + 8 + due righe
    // di titolo + una di sottotitolo + 4.
    this.height = 212,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Comincia allineato al testo della colonna, ma scorre fino al
        // bordo della finestra quando la pagina lo permette (RailBleed).
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter + RailBleed.of(context),
        ),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: itemBuilder,
      ),
    );
  }
}
