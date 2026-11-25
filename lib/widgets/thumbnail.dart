import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/spot.dart';
import '../services/artwork.dart';

/// Network image with error placeholder, used for YouTube thumbnails.
///
/// When [hiRes] is true the URL is re-targeted to the largest available
/// size (used by the full player so the artwork looks crisp instead of
/// upscaled). Falls back to the original URL if the hi-res size 404s.
class Thumbnail extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final bool hiRes;

  /// Quale parte tenere quando [fit] ritaglia.
  final Alignment alignment;

  const Thumbnail({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.hiRes = false,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _placeholder();
    }
    if (!hiRes) {
      return _image(url);
    }
    final target = hiResArtwork(url) ?? url;
    // Non-terminal errors (e.g. a missing maxresdefault) fall back to the
    // original low-res URL; only a hard failure shows the placeholder.
    return Image.network(
      target,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => _image(url, highQuality: true),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder();
      },
    );
  }

  Widget _image(String src, {bool highQuality = false}) {
    return Image.network(
      src,
      fit: fit,
      alignment: alignment,
      filterQuality: highQuality ? FilterQuality.high : FilterQuality.medium,
      errorBuilder: (_, _, _) => _placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder();
      },
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: Icon(
        Icons.music_note,
        color: Colors.white.withValues(alpha: 0.35),
        size: 28,
      ),
    );
  }
}

/// Una copertina ritagliata a macchia.
///
/// Il seme di default e' l'indirizzo della copertina: lo stesso brano ha lo
/// stesso indirizzo dovunque compaia, quindi la stessa macchia nella lista,
/// nella coda, nel dettaglio dell'album. Un [seed] esplicito serve quando
/// la copertina cambia ma la macchia deve restare (una playlist che si
/// riempie, un mosaico).
///
/// Il filo chiaro attorno tiene leggibile la forma anche sulle copertine
/// scure, che sul fondo nero altrimenti sparirebbero.
class SpotThumbnail extends StatelessWidget {
  final String url;
  final String? seed;

  /// Quanto e' irregolare: sotto i 60px conviene stare attorno a 0.6,
  /// perche' una macchia piccola e molto storta sembra un errore.
  final double wobble;
  final bool hiRes;

  /// L'orologio di una macchia viva (vedi SpotClock); senza, e' ferma.
  final ValueListenable<double>? time;

  const SpotThumbnail({
    super.key,
    required this.url,
    this.seed,
    this.wobble = 1,
    this.hiRes = false,
    this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Spot(
      seed: seed ?? url,
      wobble: wobble,
      rim: Colors.white.withValues(alpha: 0.08),
      time: time,
      child: Thumbnail(url: url, hiRes: hiRes),
    );
  }
}
