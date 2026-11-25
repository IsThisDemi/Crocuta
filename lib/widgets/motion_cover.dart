import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../design/app_theme.dart';
import '../models/track.dart';
import '../providers.dart';
import '../services/stream_proxy.dart';

/// La copertina animata: un tratto del videoclip, muto e in loop, sopra la
/// copertina ferma.
///
/// Come il Canvas di Spotify e le copertine animate di Apple Music, ma dal
/// videoclip vero, che YouTube ha per quasi ogni brano. Un tratto di
/// dodici secondi preso da un terzo del video, dove di solito si e' gia'
/// oltre l'intro parlata: in loop, e' un'atmosfera, non un video da
/// seguire — per quello c'e' il tasto Video. Compare con una dissolvenza
/// solo quando il primo fotogramma e' pronto: fino ad allora, e se il
/// brano non ha un videoclip, resta [cover].
class MotionCover extends ConsumerStatefulWidget {
  final Track track;
  final Widget cover;

  const MotionCover({super.key, required this.track, required this.cover});

  @override
  ConsumerState<MotionCover> createState() => _MotionCoverState();
}

class _MotionCoverState extends ConsumerState<MotionCover>
    with WidgetsBindingObserver {
  mk.Player? _player;
  VideoController? _controller;
  bool _ready = false;
  int _token = 0;

  /// Da dove nel video, e quanto dura il tratto in loop.
  static const _from = 0.33;
  static const _loop = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MotionCover old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      _stop();
      unawaited(_load());
    }
  }

  /// In background non si decodifica un video che nessuno vede.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = _player;
    if (p == null) return;
    unawaited(state == AppLifecycleState.resumed ? p.play() : p.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  void _stop() {
    _token++;
    final p = _player;
    _player = null;
    _controller = null;
    if (mounted && _ready) setState(() => _ready = false);
    _ready = false;
    if (p != null) unawaited(p.dispose());
  }

  Future<void> _load() async {
    if (!ref.read(motionCoverProvider)) return;
    // Nei test niente rete.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    final token = ++_token;
    bool stale() => !mounted || token != _token;
    try {
      final service = ref.read(youtubeServiceProvider);
      final videoId = await service.musicVideoFor(widget.track);
      if (videoId == null || stale()) return;
      final stream = await service.resolveVideo(videoId);
      if (stream == null || stale()) return;
      final proxy = ref.read(streamProxyProvider);
      if (!proxy.isRunning) await proxy.start();
      final url = stream.isHls
          ? stream.url
          : proxy.proxiedUrl(
              stream.url,
              userAgent: stream.userAgent,
              refresh: () async {
                final again = await service.resolveVideo(videoId);
                return again == null
                    ? null
                    : ProxiedStreamSource(
                        again.url,
                        userAgent: again.userAgent,
                      );
              },
            );
      if (stale()) return;

      final player = mk.Player();
      final controller = VideoController(player);
      final native = player.platform;
      if (native is mk.NativePlayer) {
        // Muto davvero: niente traccia audio, non solo volume a zero, cosi'
        // non apre nemmeno un'uscita audio accanto a quella del brano.
        await native.setProperty('aid', 'no');
        await native.setProperty('loop-file', 'inf');
      }
      await player.setVolume(0);
      _player = player;
      _controller = controller;
      await player.open(mk.Media(url), play: false);
      // Il tratto: da un terzo del video, dodici secondi.
      final length = await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 15));
      if (stale()) return;
      final start = length * _from;
      if (native is mk.NativePlayer) {
        final a = start.inMilliseconds / 1000;
        final b = (start + _loop).inMilliseconds / 1000;
        await native.setProperty('ab-loop-a', a.toStringAsFixed(2));
        await native.setProperty('ab-loop-b', b.toStringAsFixed(2));
      }
      await player.seek(start);
      await player.play();
      await controller.waitUntilFirstFrameRendered;
      if (stale()) return;
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('copertina animata: niente ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Spenta dal menu: via il video, resta la copertina.
    ref.listen<bool>(motionCoverProvider, (_, on) {
      if (on) {
        unawaited(_load());
      } else {
        _stop();
      }
    });
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.cover,
        if (controller != null)
          AnimatedOpacity(
            duration: AppMotion.slow,
            opacity: _ready ? 1 : 0,
            child: Video(
              controller: controller,
              fit: BoxFit.cover,
              controls: NoVideoControls,
              fill: Colors.transparent,
            ),
          ),
      ],
    );
  }
}
