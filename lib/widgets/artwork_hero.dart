import 'package:flutter/material.dart';

import '../design/spot.dart';

import 'thumbnail.dart';

/// Il tag della copertina che vola fra mini player e player.
///
/// Uno solo: c'e' un solo brano in riproduzione, e la copertina e' sempre
/// la sua.
const nowPlayingArtworkTag = 'now-playing-artwork';

/// La copertina del brano in riproduzione, pronta a volare.
///
/// [enabled] esiste per un caso preciso: con la barra compressa i mini
/// player sono due — quello nella capsula che si ritira e quello dentro la
/// barra — e due Hero con lo stesso tag nella stessa route fanno scattare
/// un'asserzione al primo volo. Il tag lo porta solo quello che si vede.
class ArtworkHero extends StatelessWidget {
  final String url;
  final double radius;
  final Widget child;
  final bool enabled;

  const ArtworkHero({
    super.key,
    required this.url,
    required this.radius,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Hero(
      tag: nowPlayingArtworkTag,
      flightShuttleBuilder: (_, animation, _, _, _) =>
          _Flight(url: url, animation: animation),
      child: child,
    );
  }
}

/// Cosa si vede durante il volo.
///
/// La miniatura, non la copertina in alta risoluzione: quella del player
/// all'apertura spesso non e' ancora arrivata, e il volo mostrerebbe il
/// segnaposto grigio per tutta la sua durata. La miniatura e' gia' in
/// memoria — il mini player l'ha appena disegnata — e a volo finito la
/// grande prende il suo posto.
///
/// Gli angoli passano da quelli del mini player (8) a quelli del player
/// (28): l'animazione va da 0 a 1 all'andata e da 1 a 0 al ritorno, quindi
/// lo stesso conto vale nei due versi.
class _Flight extends StatelessWidget {
  final String url;
  final Animation<double> animation;

  const _Flight({required this.url, required this.animation});

  @override
  Widget build(BuildContext context) {
    // La macchia e' la stessa a ogni misura (stesso seme, la copertina):
    // durante il volo cresce soltanto, e il mini player e il player
    // mostrano davvero la stessa forma.
    return Spot(
      seed: url,
      still: true,
      child: Thumbnail(url: url, fit: BoxFit.cover),
    );
  }
}
