/// Cover-art helpers: YouTube returns low-resolution thumbnails by default
/// (search results ship `=w120-h120` or `hqdefault.jpg`), but the same
/// images are available at much larger sizes. These helpers re-target the
/// URL so the player can show a crisp, near-lossless artwork (Apple Music
/// style) instead of an upscaled blurry one.
library;

/// Rebuilds [url] pointing at a high-resolution version of the same cover.
///
/// Handles the two shapes YouTube uses:
///  * `googleusercontent.com/...=w120-h120-l90-rj` (YT Music covers) — rewrites
///    the width/height params to ~1024px, keeping every other param (`-l90-rj`).
///  * `img.youtube.com/vi/<id>/hqdefault.jpg` and similar precanned thumbs —
///    swapped for the largest YouTube provides (`maxresdefault.jpg`),
///    falling back to `mqdefault`/`hqdefault` when the premium size is absent.
///
/// Nil when [url] is empty.
String? hiResArtwork(String url) {
  if (url.isEmpty) return null;

  // 1) googleusercontent covers: replace the "<w>-h<h>" size.
  final gmc = RegExp(r'(=w)(\w+)(-h)(\w+)(-[a-z0-9]+)?').firstMatch(url);
  if (gmc != null) {
    final suffix = gmc.group(5) ?? '';
    return url.replaceRange(gmc.start, gmc.end, '=w1024-h1024$suffix');
  }

  // 2) img.youtube.com/vi/.../xxxdefault.jpg
  final yt = RegExp(r'(/vi/[a-zA-Z0-9_-]+/)mq?hqdefault\.jpg').firstMatch(url);
  if (yt != null) {
    final base = url.substring(0, yt.start + yt.group(1)!.length);
    // maxresdefault.jpg is 1280x720 and square-cropped by BoxFit.cover;
    // not guaranteed on every video, so the widget falls back if it 404s.
    return '$base/maxresdefault.jpg';
  }
  if (url.contains('/vi/') && url.contains('default.jpg')) {
    return url;
  }

  return url;
}
