import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../services/dominant_color.dart';
import '../services/replay.dart';
import '../widgets/thumbnail.dart';
import '../widgets/toast.dart';

/// Il Replay raccontato, come in Apple Music: schede a tutto schermo, una
/// cosa per volta, ognuna da condividere come immagine.
///
/// Ogni scheda e' disegnata su una tela fissa di 360 x 640 punti e poi
/// scalata allo schermo: quello che si vede e' esattamente l'immagine che
/// si condivide, 1080 x 1920, il formato delle storie — su un iPhone come
/// sulla finestra larga del Mac.
Future<void> openReplayStory(BuildContext context, ReplayPeriod period) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => ReplayStoryScreen(period: period),
      transitionsBuilder: (_, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(t),
            child: child,
          ),
        );
      },
    ),
  );
}

/// La tela di ogni scheda, in punti.
const Size _canvas = Size(360, 640);

class ReplayStoryScreen extends ConsumerStatefulWidget {
  final ReplayPeriod period;

  const ReplayStoryScreen({super.key, required this.period});

  @override
  ConsumerState<ReplayStoryScreen> createState() => _ReplayStoryScreenState();
}

class _ReplayStoryScreenState extends ConsumerState<ReplayStoryScreen> {
  final _pages = PageController();
  final _shareKey = GlobalKey();
  int _index = 0;
  ArtworkPalette? _palette;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    final replay = ref.read(replayProvider(widget.period));
    final art = replay.tracks.firstOrNull?.track.thumbnailUrl;
    if (art != null && art.isNotEmpty) {
      unawaited(
        paletteOf(art).then((p) {
          if (mounted) setState(() => _palette = p);
        }),
      );
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta, int count) {
    final next = _index + delta;
    if (next < 0) return;
    if (next >= count) {
      Navigator.of(context).pop();
      return;
    }
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// La scheda che si vede, come PNG da 1080 x 1920, nel foglio di
  /// condivisione di sistema: Messaggi, Instagram, "Salva immagine"...
  Future<void> _share(Rect origin) async {
    final boundary =
        _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(pixelRatio: 1080 / _canvas.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/crocuta-replay-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      showToast("Couldn't Share", icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final replay = ref.watch(replayProvider(widget.period));
    final colors = _ReplayColors.of(_palette, context.colors.accent);
    final cards = <Widget>[
      _CoverCard(replay: replay, period: widget.period, colors: colors),
      _MinutesCard(replay: replay, period: widget.period, colors: colors),
      if (replay.artists.isNotEmpty)
        _TopArtistCard(replay: replay, period: widget.period, colors: colors),
      _TopSongsCard(replay: replay, period: widget.period, colors: colors),
      if (replay.artists.length > 1)
        _TopArtistsCard(replay: replay, period: widget.period, colors: colors),
      if (replay.albums.isNotEmpty)
        _TopAlbumCard(replay: replay, period: widget.period, colors: colors),
      _SummaryCard(replay: replay, period: widget.period, colors: colors),
    ];
    final top = MediaQuery.paddingOf(context).top + topWindowInset(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(1, cards.length),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(-1, cards.length),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Lo sfondo della pagina: la stessa tinta della scheda, sfocata
              // oltre i bordi, perche' sul Mac la scheda non riempie tutto.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.1,
                      colors: [
                        colors.deep.withValues(alpha: 0.9),
                        Colors.black,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: top + 28,
                bottom: bottom + 84,
                child: PageView.builder(
                  controller: _pages,
                  itemCount: cards.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: AspectRatio(
                        aspectRatio: _canvas.width / _canvas.height,
                        child: FittedBox(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: RepaintBoundary(
                              key: i == _index ? _shareKey : null,
                              child: SizedBox.fromSize(
                                size: _canvas,
                                child: cards[i],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Tocco a destra avanti, a sinistra indietro, come le storie;
              // lo scorrimento resta alla PageView sotto.
              Positioned.fill(
                top: top + 28,
                bottom: bottom + 84,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _go(-1, cards.length),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => _go(1, cards.length),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: top + 8,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: i <= _index ? 0.95 : 0.28,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: bottom + 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundButton(
                      icon: Icons.close_rounded,
                      label: 'Close',
                      onTap: (_) => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    _RoundButton(
                      icon: Icons.ios_share_rounded,
                      label: 'Share',
                      wide: true,
                      busy: _sharing,
                      onTap: _share,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool wide;
  final bool busy;
  final void Function(Rect origin) onTap;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.wide = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => Material(
        color: Colors.white.withValues(alpha: wide ? 0.95 : 0.16),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy
              ? null
              : () {
                  final box = context.findRenderObject() as RenderBox;
                  onTap(box.localToGlobal(Offset.zero) & box.size);
                },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 26 : 16,
              vertical: 13,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 20,
                    color: wide ? Colors.black : Colors.white,
                  ),
                if (wide) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: context.texts.titleSmall?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// I colori del Replay, dalla copertina del brano piu' ascoltato.
class _ReplayColors {
  final Color vivid;
  final Color deep;

  const _ReplayColors(this.vivid, this.deep);

  factory _ReplayColors.of(ArtworkPalette? p, Color fallback) {
    final base = p?.vivid ?? p?.backdrop ?? fallback;
    final hsl = HSLColor.fromColor(base);
    final vivid = hsl
        .withSaturation(hsl.saturation.clamp(0.45, 0.9))
        .withLightness(hsl.lightness.clamp(0.42, 0.58))
        .toColor();
    final deep = hsl
        .withSaturation(hsl.saturation.clamp(0.3, 0.8))
        .withLightness(0.1)
        .toColor();
    return _ReplayColors(vivid, deep);
  }
}

String _periodTitle(ReplayPeriod p) {
  final now = DateTime.now();
  return switch (p) {
    ReplayPeriod.week => 'This Week',
    ReplayPeriod.month => '${_monthNames[now.month - 1]} ${now.year}',
    ReplayPeriod.year => '${now.year}',
    ReplayPeriod.allTime => 'All Time',
  };
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _thousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _time(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String _plays(int n) => '${_thousands(n)} play${n == 1 ? '' : 's'}';

/// La base di ogni scheda: il fondo col colore del Replay, la firma in
/// cima e il nome dell'app in fondo, che viaggia con l'immagine.
class _Card extends StatelessWidget {
  final ReplayPeriod period;
  final _ReplayColors colors;
  final Widget child;
  final bool light;

  const _Card({
    required this.period,
    required this.colors,
    required this.child,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? [colors.vivid, Color.lerp(colors.vivid, colors.deep, 0.55)!]
              : [Color.lerp(colors.vivid, colors.deep, 0.35)!, colors.deep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'REPLAY',
                  style: context.texts.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
                const Spacer(),
                Text(
                  _periodTitle(period),
                  style: context.texts.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Expanded(child: child),
            Row(
              children: [
                const _Dots(),
                const SizedBox(width: 6),
                Text(
                  'Crocuta',
                  style: context.texts.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Il segno dell'icona, in piccolo: una C di puntini.
class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(14, 14), painter: _DotsPainter());
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFF2E6D2);
    final c = Offset(size.width * 0.62, size.height / 2);
    for (var ring = 0; ring < 2; ring++) {
      final r = size.width * (0.28 + ring * 0.2);
      for (var i = 0; i < 7; i++) {
        final a = math.pi / 2 + math.pi * i / 6;
        canvas.drawCircle(
          c + Offset(math.cos(a) * r, math.sin(a) * r),
          size.width * (0.075 - ring * 0.02),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}

TextStyle? _eyebrow(BuildContext context) =>
    context.texts.titleMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.8),
      fontWeight: FontWeight.w600,
    );

TextStyle? _headline(BuildContext context, double size) =>
    context.texts.displaySmall?.copyWith(
      color: Colors.white,
      fontSize: size,
      height: 1.02,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    );

/// Una copertina nelle carte del Replay: una macchia, come nel resto
/// dell'app, per dischi e artisti allo stesso modo. Senza ombra: sotto una
/// macchia un'ombra rettangolare disegnerebbe il riquadro che la forma
/// toglie. Le piccole stanno piu' tonde.
class _Cover extends StatelessWidget {
  final String url;
  final double size;

  const _Cover(this.url, {required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: SpotThumbnail(
        url: url,
        hiRes: size > 100,
        wobble: size < 80 ? 0.6 : 1,
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _CoverCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final covers = <String>[
      for (final a in replay.albums) a.album.thumbnailUrl,
      for (final t in replay.tracks) t.track.thumbnailUrl,
    ].where((u) => u.isNotEmpty).toSet().take(4).toList();
    return _Card(
      period: period,
      colors: colors,
      light: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < covers.length; i++)
                    Positioned(
                      left: [8.0, 118.0, 20.0, 128.0][i],
                      top: [10.0, 0.0, 122.0, 114.0][i],
                      child: Transform.rotate(
                        angle: [-0.08, 0.06, 0.05, -0.05][i],
                        child: _Cover(covers[i], size: 112),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text('Replay', style: _headline(context, 64)),
          const SizedBox(height: 6),
          Text(
            'Your ${period == ReplayPeriod.allTime ? 'music, all time' : _periodTitle(period)} in music.',
            style: _eyebrow(context),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _MinutesCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _MinutesCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = replay.seconds ~/ 60;
    Widget stat(String value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.texts.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: _eyebrow(context)?.copyWith(fontSize: 13)),
      ],
    );
    return _Card(
      period: period,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 3),
          Text('You listened for', style: _eyebrow(context)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _thousands(minutes),
              style: _headline(context, 104)?.copyWith(color: colors.vivid),
            ),
          ),
          Text('minutes', style: _headline(context, 40)),
          const Spacer(flex: 2),
          Row(
            children: [
              Expanded(child: stat(_thousands(replay.songs), 'songs')),
              Expanded(child: stat(_thousands(replay.plays), 'plays')),
              Expanded(child: stat(_thousands(replay.artistCount), 'artists')),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TopArtistCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _TopArtistCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final a = replay.artists.first;
    return _Card(
      period: period,
      colors: colors,
      light: true,
      child: Column(
        children: [
          const Spacer(),
          Text('Your top artist', style: _eyebrow(context)),
          const SizedBox(height: 22),
          _Cover(a.artwork, size: 220),
          const SizedBox(height: 24),
          Text(
            a.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: _headline(context, 38),
          ),
          const SizedBox(height: 8),
          Text(
            '${_time(a.seconds)} · ${_plays(a.plays)}',
            style: _eyebrow(context),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TopSongsCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _TopSongsCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      period: period,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 26),
          Text('Your top songs', style: _headline(context, 34)),
          const SizedBox(height: 20),
          for (var i = 0; i < replay.tracks.length && i < 5; i++)
            _RankRow(
              rank: i + 1,
              image: replay.tracks[i].track.thumbnailUrl,
              title: replay.tracks[i].track.title,
              subtitle: replay.tracks[i].track.author,
              accent: colors.vivid,
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TopArtistsCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _TopArtistsCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      period: period,
      colors: colors,
      light: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 26),
          Text('Your top artists', style: _headline(context, 34)),
          const SizedBox(height: 20),
          for (var i = 0; i < replay.artists.length && i < 5; i++)
            _RankRow(
              rank: i + 1,
              image: replay.artists[i].artwork,
              title: replay.artists[i].name,
              subtitle: _time(replay.artists[i].seconds),
              accent: Colors.white,
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TopAlbumCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _TopAlbumCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final a = replay.albums.first;
    return _Card(
      period: period,
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text('Your top album', style: _eyebrow(context)),
          const SizedBox(height: 18),
          _Cover(a.album.thumbnailUrl, size: 308),
          const SizedBox(height: 20),
          Text(
            a.album.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _headline(context, 30),
          ),
          const SizedBox(height: 4),
          Text(
            '${a.album.subtitle} · ${_plays(a.plays)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _eyebrow(context),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// Tutto in una scheda: quella che si condivide di piu'.
class _SummaryCard extends StatelessWidget {
  final ReplaySummary replay;
  final ReplayPeriod period;
  final _ReplayColors colors;

  const _SummaryCard({
    required this.replay,
    required this.period,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final artist = replay.artists.firstOrNull;
    final song = replay.tracks.firstOrNull;
    final label = context.texts.labelMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.7),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    );
    final value = context.texts.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );
    Widget cell(String title, String? image, String text) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: label),
          const SizedBox(height: 8),
          if (image != null) ...[
            _Cover(image, size: 132),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: value,
          ),
        ],
      ),
    );
    return _Card(
      period: period,
      colors: colors,
      light: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 22),
          Text('MINUTES LISTENED', style: label),
          Text(_thousands(replay.seconds ~/ 60), style: _headline(context, 58)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (artist != null)
                cell('Top Artist', artist.artwork, artist.name),
              if (artist != null && song != null) const SizedBox(width: 16),
              if (song != null)
                cell('Top Song', song.track.thumbnailUrl, song.track.title),
            ],
          ),
          const SizedBox(height: 18),
          Text('TOP SONGS', style: label),
          const SizedBox(height: 6),
          for (var i = 0; i < replay.tracks.length && i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${i + 1}  ${replay.tracks[i].track.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final String image;
  final String title;
  final String subtitle;
  final Color accent;

  const _RankRow({
    required this.rank,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              style: context.texts.headlineSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _Cover(image, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
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
