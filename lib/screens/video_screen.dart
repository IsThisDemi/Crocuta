import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/track.dart';
import '../providers.dart';
import '../services/stream_proxy.dart';
import '../services/stream_resolver.dart';
import '../widgets/empty_state.dart';

/// Il videoclip del brano, da guardare: a tutto schermo, con il suo audio.
///
/// Come lo switch "Song / Video" di YouTube Music, ma a parte: il brano si
/// mette in pausa e, chiuso il video, riprende da dove era. Il videoclip
/// non e' lo stesso audio del brano — ha intro, scene parlate, a volte un
/// finale diverso —, quindi non lo si mescola alla coda e ad AutoMix.
class VideoScreen extends ConsumerStatefulWidget {
  final Track track;

  const VideoScreen({super.key, required this.track});

  static Future<void> open(BuildContext context, Track track) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoScreen(track: track),
        ),
      );

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  final mk.Player _player = mk.Player();
  late final VideoController _controller = VideoController(_player);

  /// Il brano stava suonando: alla chiusura riparte.
  bool _resume = false;

  /// Preso subito: in dispose `ref` non si puo' piu' usare, e la musica
  /// alla chiusura non ripartiva.
  late final _music = ref.read(playerProvider.notifier);
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    final player = ref.read(playerProvider);
    _resume = player.isPlaying;
    if (_resume) unawaited(_music.toggle());
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final service = ref.read(youtubeServiceProvider);
      final videoId = await service.musicVideoFor(widget.track);
      if (videoId == null) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final proxy = ref.read(streamProxyProvider);
      if (!proxy.isRunning) await proxy.start();
      String proxied(ResolvedStream s, StreamKind kind) => proxy.proxiedUrl(
        s.url,
        userAgent: s.userAgent,
        hls: s.isHls,
        refresh: () async {
          final again = kind == StreamKind.audio
              ? await service.resolveAudio(videoId)
              : await service.resolveVideo(videoId, kind: kind);
          return again == null
              ? null
              : ProxiedStreamSource(again.url, userAgent: again.userAgent);
        },
      );

      // L'immagine fino al 1080 e l'audio del videoclip, due stream che mpv
      // suona insieme: YouTube li unisce in un solo file solo fino al 360,
      // troppo poco a tutto schermo. Senza l'audio separato, il 360.
      final picture = await service.resolveVideo(
        videoId,
        kind: StreamKind.videoHigh,
      );
      final sound = picture == null
          ? null
          : await service.resolveAudio(videoId);
      if (!mounted) return;
      if (picture != null && sound != null) {
        final native = _player.platform;
        if (native is mk.NativePlayer) {
          await native.setProperty(
            'audio-files',
            proxied(sound, StreamKind.audio),
          );
        }
        await _player.open(mk.Media(proxied(picture, StreamKind.videoHigh)));
        return;
      }
      final muxed = await service.resolveVideo(videoId, kind: StreamKind.muxed);
      if (!mounted) return;
      if (muxed == null) {
        setState(() => _missing = true);
        return;
      }
      await _player.open(mk.Media(proxied(muxed, StreamKind.muxed)));
    } catch (e) {
      debugPrint('video: non aperto ($e)');
      if (mounted) setState(() => _missing = true);
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    if (_resume) {
      // Dopo il fotogramma: durante la chiusura i provider non si toccano.
      final music = _music;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(music.toggle());
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          // expand: senza, lo Stack prendeva la misura del solo pulsante di
          // chiusura, e il video — che doveva riempirlo — riempiva un
          // riquadro grande quanto la X.
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: _missing
                    ? const EmptyState(
                        icon: Icons.videocam_off_rounded,
                        title: 'No video for this song',
                        message: 'YouTube has no official music video for it.',
                      )
                    : Video(
                        controller: _controller,
                        controls: AdaptiveVideoControls,
                      ),
              ),
              Positioned(
                // Sotto i semafori della finestra, sul Mac.
                top:
                    MediaQuery.paddingOf(context).top +
                    topWindowInset(context) +
                    AppSpacing.sm,
                left: AppSpacing.sm,
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
