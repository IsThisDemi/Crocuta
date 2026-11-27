import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../design/spot.dart';
import '../dev/readme_shots.dart';
import '../models/track.dart';
import '../providers.dart';
import '../services/app_window.dart';
import '../services/stream_proxy.dart';
import '../services/stream_resolver.dart';
import '../widgets/accent_glow.dart';
import '../widgets/airplay_button.dart';
import '../widgets/artist_links.dart';
import '../widgets/drawer_dismiss.dart';
import '../widgets/player_keys.dart';
import '../widgets/spot_controls.dart';
import '../widgets/spot_slider.dart';
import '../widgets/thumbnail.dart';

/// Il videoclip, a tutto schermo.
///
/// Il video riempie lo schermo intero, com'e', senza ritagli. Sopra, gli
/// stessi comandi del player — il titolo grande, gli interpreti nel colore
/// del brano, la barra, i glifi e il play a macchia, la fila di
/// macchioline — che spariscono da soli mentre il video va e tornano col
/// mouse o con un tocco. Prima che il video arrivi, e quando un brano non
/// ce l'ha, la pagina e' il player: la luce del brano sul nero e la
/// copertina a macchia coi suoi satelliti.
///
/// Si va avanti nella coda: alla fine del video compare il prossimo che ha
/// un videoclip, con un conto alla rovescia, e si continua a guardare. La
/// musica resta ferma intanto, ma la coda la segue: chiuso il video, si
/// riprende dal brano di cui si stava guardando il video.
///
/// Il videoclip non e' lo stesso audio del brano — ha intro, scene
/// parlate, a volte un finale diverso —, quindi lo suona un player suo,
/// fuori da AutoMix.
class VideoScreen extends ConsumerStatefulWidget {
  final Track track;

  const VideoScreen({super.key, required this.track});

  /// Per le prove automatiche (lib/dev/readme_shots.dart): sposta il
  /// video aperto, per arrivare alla fine senza aspettarla.
  static Future<void> Function(Duration to)? debugSeek;

  static Future<void> open(BuildContext context, Track track) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, _, _) => VideoScreen(track: track),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            child: child,
          ),
        ),
      );

  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

enum _Phase { loading, playing, missing, ended }

/// Il prossimo brano della coda che ha un videoclip.
typedef _Next = ({int index, Track track, String videoId});

class _VideoScreenState extends ConsumerState<VideoScreen> {
  final mk.Player _player = mk.Player();
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription<Object?>> _subs = [];

  /// Preso subito: in dispose `ref` non si puo' piu' usare, e la musica
  /// alla chiusura non ripartiva.
  late final _music = ref.read(playerProvider.notifier);

  /// Il brano stava suonando: alla chiusura riparte.
  bool _resume = false;

  late Track _track = widget.track;

  /// Dove sta [_track] nella coda del player, se ci sta: solo allora si
  /// puo' andare avanti nella coda.
  int? _index;

  _Phase _phase = _Phase.loading;
  _Next? _next;

  /// Ogni brano aperto ne prende uno nuovo: le risposte lente di quello di
  /// prima non devono finire sullo schermo di questo.
  int _loadToken = 0;

  /// I comandi in vista. Spariscono da soli dopo qualche secondo mentre il
  /// video va; in pausa restano.
  final ValueNotifier<bool> _chrome = ValueNotifier(true);
  Timer? _hideTimer;

  /// Il conto alla rovescia per il prossimo video, a fine video.
  final ValueNotifier<int> _countdown = ValueNotifier(0);
  Timer? _countTimer;
  static const int _countFrom = 6;

  /// La finestra l'abbiamo messa noi a tutto schermo: alla chiusura si
  /// rimette com'era.
  bool _wentFullScreen = false;
  bool _fullScreen = false;

  bool get _hasVideo => _phase == _Phase.playing || _phase == _Phase.ended;

  @override
  void initState() {
    super.initState();
    final player = ref.read(playerProvider);
    _resume = player.isPlaying;
    if (_resume) unawaited(_music.toggle());
    if (player.current?.id == _track.id) _index = player.currentIndex;
    // Le prove automatiche girano su un Mac dove qualcuno lavora: muto.
    if (readmeShotsEnabled) unawaited(_player.setVolume(0));
    if (kDebugMode) VideoScreen.debugSeek = (d) => _player.seek(d);
    unawaited(
      AppWindow.isFullScreen().then((full) {
        if (mounted) setState(() => _fullScreen = full);
      }),
    );
    _subs
      ..add(
        _player.stream.playing.listen((playing) {
          if (playing) {
            _scheduleHide();
          } else {
            _showChrome(hold: true);
          }
        }),
      )
      ..add(
        _player.stream.completed.listen((done) {
          if (done && _phase == _Phase.playing) _onEnded();
        }),
      );
    unawaited(_load(_track));
  }

  // ---------------------------------------------------------------------
  // Caricare
  // ---------------------------------------------------------------------

  Future<void> _load(Track track) async {
    final token = ++_loadToken;
    _countTimer?.cancel();
    setState(() {
      _track = track;
      _phase = _Phase.loading;
      _next = null;
    });
    _showChrome(hold: true);
    try {
      final service = ref.read(youtubeServiceProvider);
      final videoId = await service.musicVideoFor(track);
      debugPrint('video: ${track.id} -> $videoId');
      if (token != _loadToken || !mounted) return;
      if (videoId == null || !await _open(videoId, token)) {
        // Niente video, o uno che non si apre (un limite d'eta' senza
        // l'accesso a YouTube): resta la copertina, come nel player.
        if (token == _loadToken && mounted) {
          setState(() => _phase = _Phase.missing);
          unawaited(_findNext(token));
        }
        return;
      }
      if (token != _loadToken || !mounted) return;
      setState(() => _phase = _Phase.playing);
      _scheduleHide();
      unawaited(_findNext(token));
    } catch (e) {
      debugPrint('video: non aperto ($e)');
      if (token == _loadToken && mounted) {
        setState(() => _phase = _Phase.missing);
      }
    }
  }

  /// Apre il video [videoId]: l'immagine fino al 1080 e il suo audio, due
  /// stream che mpv suona insieme — YouTube li unisce in un solo file solo
  /// fino al 360, troppo poco a tutto schermo. Senza l'audio separato, il
  /// 360.
  Future<bool> _open(String videoId, int token) async {
    final service = ref.read(youtubeServiceProvider);
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

    final picture = await service.resolveVideo(
      videoId,
      kind: StreamKind.videoHigh,
    );
    final sound = picture == null ? null : await service.resolveAudio(videoId);
    debugPrint(
      'video: $videoId immagine ${picture != null}, audio ${sound != null}',
    );
    if (token != _loadToken || !mounted) return false;
    final native = _player.platform;
    if (picture != null && sound != null) {
      if (native is mk.NativePlayer) {
        // Come elemento solo: impostata intera, la lista si spezza sui ":"
        // e "http://127.0.0.1:porta" non e' piu' un indirizzo — il video
        // restava muto.
        await native.command(['change-list', 'audio-files', 'clr', '']);
        await native.command([
          'change-list',
          'audio-files',
          'append',
          proxied(sound, StreamKind.audio),
        ]);
      }
      await _player.open(mk.Media(proxied(picture, StreamKind.videoHigh)));
      return true;
    }
    final muxed = await service.resolveVideo(videoId, kind: StreamKind.muxed);
    debugPrint('video: $videoId unico ${muxed != null}');
    if (token != _loadToken || !mounted || muxed == null) return false;
    if (native is mk.NativePlayer) {
      await native.command(['change-list', 'audio-files', 'clr', '']);
    }
    await _player.open(mk.Media(proxied(muxed, StreamKind.muxed)));
    return true;
  }

  /// Il prossimo brano della coda con un videoclip, fra i cinque dopo
  /// questo: chi non ce l'ha si salta.
  Future<void> _findNext(int token) async {
    final from = _index;
    if (from == null) return;
    final queue = ref.read(playerProvider).queue;
    final service = ref.read(youtubeServiceProvider);
    for (var i = from + 1; i < queue.length && i <= from + 5; i++) {
      final id = await service.musicVideoFor(queue[i]);
      if (token != _loadToken || !mounted) return;
      if (id != null) {
        setState(() => _next = (index: i, track: queue[i], videoId: id));
        return;
      }
    }
  }

  // ---------------------------------------------------------------------
  // Andare avanti
  // ---------------------------------------------------------------------

  void _onEnded() {
    setState(() => _phase = _Phase.ended);
    _showChrome(hold: true);
    if (_next == null) return;
    _countdown.value = _countFrom;
    _countTimer?.cancel();
    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _countdown.value -= 1;
      if (_countdown.value <= 0) {
        t.cancel();
        _playNext();
      }
    });
  }

  void _playNext() {
    final next = _next;
    if (next == null) return;
    _jumpTo(next.index, next.track);
  }

  /// Passa al video del brano [index] della coda, e la coda lo segue.
  void _jumpTo(int index, Track track) {
    _countTimer?.cancel();
    _music.cueAt(index);
    _index = index;
    unawaited(_player.stop());
    unawaited(_load(track));
  }

  /// Il glifo "precedente": all'inizio del video se ne e' gia' visto un
  /// pezzo, se no il video del brano prima nella coda.
  void _previous() {
    final from = _index;
    if (_hasVideo && _player.state.position > const Duration(seconds: 3)) {
      unawaited(_player.seek(Duration.zero));
      _showChrome();
      return;
    }
    if (from == null || from == 0) return;
    final queue = ref.read(playerProvider).queue;
    if (from - 1 < queue.length) _jumpTo(from - 1, queue[from - 1]);
  }

  void _replay() {
    _countTimer?.cancel();
    setState(() => _phase = _Phase.playing);
    unawaited(_player.seek(Duration.zero).then((_) => _player.play()));
  }

  void _cancelNext() {
    _countTimer?.cancel();
    setState(() => _next = null);
  }

  // ---------------------------------------------------------------------
  // Comandi
  // ---------------------------------------------------------------------

  void _showChrome({bool hold = false}) {
    _chrome.value = true;
    if (hold) {
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3200), () {
      if (_player.state.playing && _phase == _Phase.playing) {
        _chrome.value = false;
      }
    });
  }

  /// Un tocco sullo schermo: se i comandi sono nascosti li mostra, se no
  /// mette in pausa o riparte — come sulla TV.
  void _tapScreen() {
    if (!_chrome.value) {
      _showChrome();
      return;
    }
    _togglePlay();
  }

  void _togglePlay() {
    switch (_phase) {
      case _Phase.ended:
        _replay();
      case _Phase.playing:
        unawaited(_player.playOrPause());
        _showChrome();
      case _Phase.missing:
        _listenToSong();
      case _Phase.loading:
        break;
    }
  }

  /// Torna al brano: chiude il video e lo fa suonare.
  void _listenToSong() {
    if (_index != null) {
      _resume = true;
    } else {
      final music = _music;
      final track = _track;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(music.playTrack(track));
      });
    }
    _close();
  }

  void _seekBy(int seconds) {
    if (!_hasVideo) return;
    final to = _player.state.position + Duration(seconds: seconds);
    final end = _player.state.duration;
    unawaited(
      _player.seek(to < Duration.zero ? Duration.zero : (to > end ? end : to)),
    );
    _showChrome();
  }

  void _toggleMute() {
    final to = _player.state.volume > 0 ? 0.0 : 100.0;
    unawaited(
      _player.setVolume(to).then((_) {
        if (mounted) setState(() {});
      }),
    );
    _showChrome();
  }

  Future<void> _toggleFullScreen() async {
    final on = !_fullScreen;
    await AppWindow.setFullScreen(on);
    if (!mounted) return;
    setState(() {
      _fullScreen = on;
      _wentFullScreen = on;
    });
    _showChrome();
  }

  /// Esc: prima esce dal tutto schermo, poi chiude.
  void _escape() {
    if (_fullScreen && _wentFullScreen) {
      unawaited(_toggleFullScreen());
      return;
    }
    _close();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  void dispose() {
    _hideTimer?.cancel();
    _countTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _chrome.dispose();
    _countdown.dispose();
    if (kDebugMode) VideoScreen.debugSeek = null;
    if (_wentFullScreen) unawaited(AppWindow.setFullScreen(false));
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

  // ---------------------------------------------------------------------
  // Disegno
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final second = ref
        .watch(artworkPaletteProvider(_track.thumbnailUrl))
        .valueOrNull
        ?.swatches
        .skip(1)
        .firstOrNull;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
        const SingleActivator(LogicalKeyboardKey.keyK): _togglePlay,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.keyL): () => _seekBy(10),
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.keyN): _playNext,
        if (AppWindow.supportsFullScreen)
          const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullScreen,
      },
      child: Focus(
        autofocus: true,
        // Come il player: sul telefono si tira giu' e si chiude, dalla
        // barretta o da un punto qualunque dello schermo.
        child: DrawerDismiss(
          child: AccentScope(
            artworkUrl: _track.thumbnailUrl,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: MouseRegion(
                onHover: (_) => _showChrome(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Prima del video, e senza: la luce del brano sul nero,
                    // come nel player.
                    AnimatedOpacity(
                      opacity: _hasVideo ? 0 : 1,
                      duration: const Duration(milliseconds: 600),
                      child: Builder(
                        builder: (context) => AccentGlow(
                          color: context.colors.accent,
                          second: second,
                        ),
                      ),
                    ),
                    // Il video, a tutto schermo e intero. Sul telefono in
                    // verticale, dove sopra e sotto avanza nero, sta sopra i
                    // comandi invece che dietro.
                    AnimatedOpacity(
                      opacity: _hasVideo ? 1 : 0,
                      duration: const Duration(milliseconds: 600),
                      child: Padding(
                        padding: _Chrome.videoInset(context),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _tapScreen,
                          onDoubleTap: AppWindow.supportsFullScreen
                              ? _toggleFullScreen
                              : null,
                          child: Video(
                            controller: _controller,
                            controls: NoVideoControls,
                            fit: BoxFit.contain,
                            fill: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    if (!_hasVideo) _CoverStage(track: _track),
                    if (_phase == _Phase.ended && _next != null)
                      _UpNext(
                        next: _next!,
                        countdown: _countdown,
                        onPlay: _playNext,
                        onCancel: _cancelNext,
                      ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _chrome,
                      builder: (context, chrome, _) {
                        final show = chrome || !_hasVideo;
                        return IgnorePointer(
                          ignoring: !show,
                          child: AnimatedOpacity(
                            opacity: show ? 1 : 0,
                            duration: const Duration(milliseconds: 320),
                            child: _Chrome(
                              track: _track,
                              player: _player,
                              phase: _phase,
                              overVideo: _hasVideo,
                              muted: _player.state.volume == 0,
                              fullScreen: _fullScreen,
                              hasNext: _next != null,
                              onClose: _close,
                              onPlay: _togglePlay,
                              onPrevious: _previous,
                              onNext: _playNext,
                              onMute: _toggleMute,
                              onSong: _listenToSong,
                              onFullScreen: _toggleFullScreen,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Pezzi
// -------------------------------------------------------------------------

/// Senza video: la copertina a macchia coi suoi satelliti, come nel player,
/// nello spazio sopra i comandi.
class _CoverStage extends StatelessWidget {
  final Track track;

  const _CoverStage({required this.track});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          32,
          topWindowInset(context) + 44,
          32,
          _Chrome.heightFor(context),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final side = math.min(box.maxWidth * 0.8, box.maxHeight * 0.92);
            return Center(
              child: SpotCover(
                url: track.thumbnailUrl,
                size: side,
                hiRes: true,
                child: Thumbnail(
                  url: track.thumbnailUrl,
                  fit: BoxFit.cover,
                  hiRes: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// I comandi sopra il video, gli stessi del player: in alto la barretta
/// per chiudere, in basso titolo e interpreti, la barra, i glifi col play
/// a macchia e la fila di macchioline. Sopra il video una sfumatura nera
/// dal basso, perche' si leggano su qualunque immagine.
class _Chrome extends StatelessWidget {
  final Track track;
  final mk.Player player;
  final _Phase phase;
  final bool overVideo;
  final bool muted;
  final bool fullScreen;
  final bool hasNext;
  final VoidCallback onClose;
  final VoidCallback onPlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onMute;
  final VoidCallback onSong;
  final VoidCallback onFullScreen;

  const _Chrome({
    required this.track,
    required this.player,
    required this.phase,
    required this.overVideo,
    required this.muted,
    required this.fullScreen,
    required this.hasNext,
    required this.onClose,
    required this.onPlay,
    required this.onPrevious,
    required this.onNext,
    required this.onMute,
    required this.onSong,
    required this.onFullScreen,
  });

  /// Quanto spazio prendono i comandi in basso: la copertina sta sopra.
  static double heightFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 700 ? 300 : 330;

  /// Il telefono in verticale: lo schermo e' piu' alto che largo.
  static bool portrait(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < 700 && size.height > size.width;
  }

  /// Dove sta il video: tutto lo schermo, o sul telefono in verticale lo
  /// spazio fra la barretta e i comandi.
  static EdgeInsets videoInset(BuildContext context) {
    if (!portrait(context)) return EdgeInsets.zero;
    final safe = MediaQuery.paddingOf(context);
    return EdgeInsets.only(
      top: safe.top + topWindowInset(context) + 44,
      bottom: heightFor(context) + safe.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final title = Text(
      track.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.texts.displaySmall?.copyWith(
        fontSize: wide ? 40 : 32,
        height: 1.0,
        color: Colors.white,
      ),
    );
    final artists = ArtistLinks(
      track: track,
      align: TextAlign.start,
      style: context.texts.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: context.colors.accentMuted,
      ),
    );

    final transport = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PlayerGlyph(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous',
          onTap: onPrevious,
        ),
        const SizedBox(width: 20),
        StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, snap) => SpotPlayButton(
            size: 74,
            loading: phase == _Phase.loading,
            playing: phase == _Phase.playing && (snap.data ?? false),
            onPressed: onPlay,
          ),
        ),
        const SizedBox(width: 20),
        Opacity(
          opacity: hasNext ? 1 : 0.35,
          child: PlayerGlyph(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next video (N)',
            onTap: onNext,
          ),
        ),
      ],
    );

    final keys = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerKey(
              icon: Icons.music_note_rounded,
              label: 'Listen to the song',
              onTap: onSong,
            ),
            PlayerKey(
              icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: muted ? 'Unmute' : 'Mute',
              tooltip: muted ? 'Unmute (M)' : 'Mute (M)',
              active: muted,
              onTap: onMute,
            ),
            if (AirPlayButton.isSupported) const PlayerKey.airplay(),
            if (AppWindow.supportsFullScreen)
              PlayerKey(
                icon: fullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                label: fullScreen ? 'Exit full screen' : 'Full screen',
                tooltip: fullScreen
                    ? 'Exit full screen (F)'
                    : 'Full screen (F)',
                active: fullScreen,
                onTap: onFullScreen,
              ),
          ],
        ),
      ),
    );

    final bottom = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 4), artists],
            ),
          ),
          const SizedBox(height: 16),
          _VideoSeekBar(player: player, track: track, enabled: overVideo),
          const SizedBox(height: 10),
          transport,
          const SizedBox(height: 10),
          keys,
        ],
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (overVideo && !portrait(context))
          // Solo in basso e solo quanto serve: il video resta il video.
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Container(
                height: heightFor(context) + 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.92),
                    ],
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(
            children: [
              SizedBox(height: topWindowInset(context)),
              DrawerHandle(child: _Grabber(onTap: onClose)),
              const Spacer(),
              Center(child: bottom),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// La barretta in cima, come nel player: si clicca per chiudere.
class _Grabber extends StatefulWidget {
  final VoidCallback onTap;

  const _Grabber({required this.onTap});

  @override
  State<_Grabber> createState() => _GrabberState();
}

class _GrabberState extends State<_Grabber> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close (Esc)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: 96,
            height: 36,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.fast,
                width: _hover ? 44 : 38,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _hover ? 0.7 : 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La barra del player (widgets/seek_bar.dart) sul tempo del video: lo
/// stesso filo nel colore del brano, il tempo passato e quello che manca.
class _VideoSeekBar extends ConsumerStatefulWidget {
  final mk.Player player;
  final Track track;
  final bool enabled;

  const _VideoSeekBar({
    required this.player,
    required this.track,
    required this.enabled,
  });

  @override
  ConsumerState<_VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends ConsumerState<_VideoSeekBar> {
  double? _dragging;

  static String _fmt(Duration d) {
    final s = d.inSeconds.abs();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    // L'onda c'e' solo se il video e' il brano stesso (un video della
    // ricerca): un videoclip ha il suo audio, con intro e scene in piu', e
    // l'onda della canzone non ci cadrebbe sopra.
    final shown = ref.watch(waveformProvider);
    final wave = widget.track.isVideo && shown?.trackId == widget.track.id
        ? shown!.levels
        : null;
    final numeric = context.texts.bodySmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.6),
      fontFeatures: AppTypography.tabular,
    );
    return StreamBuilder<Duration>(
      stream: p.stream.position,
      initialData: p.state.position,
      builder: (context, snap) {
        final total = widget.enabled
            ? p.state.duration.inMilliseconds.toDouble()
            : 0.0;
        final live = (snap.data ?? Duration.zero).inMilliseconds
            .toDouble()
            .clamp(0.0, total <= 0 ? 0.0 : total);
        final value = _dragging ?? live;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SpotSlider(
                seed: 'seek',
                style: SpotSliderStyle.wave,
                wave: wave,
                value: total <= 0 ? 0 : value,
                max: total <= 0 ? 1 : total,
                label: (v) => _fmt(Duration(milliseconds: v.round())),
                semanticLabel: 'Position',
                semanticValue: (v) => _fmt(Duration(milliseconds: v.round())),
                onChanged: total <= 0
                    ? null
                    : (v) => setState(() => _dragging = v),
                onChangeEnd: (v) {
                  unawaited(p.seek(Duration(milliseconds: v.round())));
                  setState(() => _dragging = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    total <= 0
                        ? '--:--'
                        : _fmt(Duration(milliseconds: value.round())),
                    style: numeric,
                  ),
                  Text(
                    total <= 0
                        ? '--:--'
                        : '-${_fmt(Duration(milliseconds: (total - value).round()))}',
                    style: numeric,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A fine video, il prossimo: la sua copertina a macchia al centro, con
/// attorno un filo nel colore del brano che segue la macchia e si chiude
/// mentre conta i secondi. Toccandola parte subito; la macchiolina con la
/// X lo ferma.
class _UpNext extends StatelessWidget {
  final _Next next;
  final ValueListenable<int> countdown;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  const _UpNext({
    required this.next,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final url = next.track.thumbnailUrl;
    final accent = context.colors.accent;
    final safe = MediaQuery.paddingOf(context);
    // Nello spazio sopra i comandi, che restano in vista: titolo e barra
    // del video appena finito non devono finirgli sotto.
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Padding(
        padding: EdgeInsets.only(
          top: safe.top + topWindowInset(context) + 44,
          bottom: _Chrome.heightFor(context) + safe.bottom,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Up next',
                  style: context.texts.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                GestureDetector(
                  onTap: onPlay,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SizedBox.square(
                      dimension: 168,
                      child: ValueListenableBuilder<int>(
                        valueListenable: countdown,
                        builder: (context, left, child) => SpotMotionBuilder(
                          builder: (context, t) => CustomPaint(
                            foregroundPainter: _SpotRing(
                              seed: url,
                              time: t,
                              fraction: 1 - left / _VideoScreenState._countFrom,
                              color: accent,
                            ),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Spot(
                            seed: url,
                            child: Thumbnail(url: url, hiRes: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    next.track.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.headlineSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  next.track.author,
                  style: context.texts.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.colors.accentMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PlayerKey(
                  icon: Icons.close_rounded,
                  label: 'Stay here',
                  onTap: onCancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Il conto alla rovescia attorno alla copertina: un filo che segue la
/// macchia, come l'avanzamento attorno alla copertina nella barra delle
/// schede del telefono.
class _SpotRing extends CustomPainter {
  final String seed;
  final double? time;
  final double fraction;
  final Color color;

  _SpotRing({
    required this.seed,
    required this.time,
    required this.fraction,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = spotPath((Offset.zero & size).deflate(2), seed, time: time);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawPath(path, base);
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null) return;
    canvas.drawPath(
      metric.extractPath(0, metric.length * fraction.clamp(0.0, 1.0)),
      base
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpotRing old) =>
      old.fraction != fraction || old.time != time || old.color != color;
}
