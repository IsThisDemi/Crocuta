import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../design/spot.dart';
import '../services/artwork.dart';
import '../providers.dart';
import '../services/connect.dart';
import 'glass_surfaces.dart';
import 'artwork_backdrop.dart';
import 'content_width.dart';
import 'liquid.dart';
import 'thumbnail.dart';
import 'spot_slider.dart';
import 'toast.dart';

IconData _iconOf(ConnectDevice d) => switch (d.platform) {
  'ios' => Icons.phone_iphone_rounded,
  'macos' => Icons.laptop_mac_rounded,
  'windows' => Icons.desktop_windows_rounded,
  'android' => Icons.phone_android_rounded,
  _ => Icons.devices_other_rounded,
};

/// Il pulsante dei dispositivi: compare solo quando sulla rete c'e' un
/// altro Crocuta, cosi' chi ne ha uno solo non vede un comando inutile.
class ConnectButton extends ConsumerWidget {
  const ConnectButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(connectServiceProvider);
    return ValueListenableBuilder(
      valueListenable: service.devices,
      builder: (context, devices, _) => devices.isEmpty
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Crocuta on your devices',
              icon: Icon(
                Icons.devices_rounded,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              onPressed: () => showConnectSheet(context, ref),
            ),
    );
  }
}

/// I dispositivi, come la lista AirPlay del Centro di Controllo: questo in
/// cima con la spunta, sotto gli altri Crocuta sulla rete. Toccandone uno
/// si apre il suo telecomando, e da li' si sposta la musica.
Future<void> showConnectSheet(BuildContext context, WidgetRef ref) {
  final service = ref.read(connectServiceProvider);
  final nav = Navigator.of(context, rootNavigator: true);
  return showGlassSheet<void>(
    context: context,
    builder: (sheet) => ValueListenableBuilder(
      valueListenable: service.devices,
      builder: (sheet, devices, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.sm,
            ),
            child: Text('Devices', style: sheet.texts.titleLarge),
          ),
          _DeviceRow(
            icon: _selfIcon,
            name: service.name,
            detail: 'This device',
            selected: true,
          ),
          for (final d in devices)
            _DeviceRow(
              icon: _iconOf(d),
              name: d.name,
              detail: 'Crocuta',
              onTap: () {
                Navigator.of(sheet).pop();
                nav.push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => RemoteScreen(device: d),
                  ),
                );
              },
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    ),
  );
}

/// L'icona di questo dispositivo.
IconData get _selfIcon => Platform.isIOS
    ? Icons.phone_iphone_rounded
    : Platform.isWindows
    ? Icons.desktop_windows_rounded
    : Icons.laptop_mac_rounded;

/// Una riga della lista: l'icona in un tondo, il nome, sotto cosa fa; la
/// spunta sul dispositivo in uso, la freccia sugli altri.
class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.detail,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.white.withValues(alpha: 0.12),
              ),
              child: Icon(
                icon,
                size: 21,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    detail,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: accent)
            else
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}

/// Il telecomando di un altro Crocuta, fatto come il player: la copertina
/// sfocata dietro, la copertina grande, la barra nel colore del brano, i
/// glifi nudi e il disco bianco del play. In fondo, come AirPlay, dove
/// sta suonando, e le due mosse: prendere qui la musica, o passargli la
/// tua.
class RemoteScreen extends ConsumerStatefulWidget {
  final ConnectDevice device;

  /// Uno stato gia' pronto, senza connettersi: per le catture di prova.
  @visibleForTesting
  final RemoteState? preview;

  const RemoteScreen({super.key, required this.device, this.preview});

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen> {
  late final ConnectRemote _remote = ConnectRemote(widget.device);
  Timer? _tick;
  ConnectResult? _failed;
  double? _seeking;
  double? _volume;

  @override
  void initState() {
    super.initState();
    if (widget.preview case final p?) {
      _remote.state.value = p;
      return;
    }
    _remote.connect().then((r) {
      if (r != ConnectResult.ok && mounted) setState(() => _failed = r);
    });
    // La barra avanza da sola fra un aggiornamento e l'altro.
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_remote.close());
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  /// Cosa dire quando non va: irraggiungibile, o un altro segreto — un
  /// dispositivo con la sincronizzazione configurata diversa, che vede
  /// questo sulla rete ma non puo' comandarlo.
  String _message(ConnectResult r) => r == ConnectResult.notYours
      ? '${widget.device.name} uses a different sync. Set up the same '
            'sync on both devices to connect them.'
      : 'Couldn\'t reach ${widget.device.name}.';

  Future<void> _move({required bool here}) async {
    final nav = Navigator.of(context);
    final service = ref.read(connectServiceProvider);
    final r = here
        ? await service.takeFrom(widget.device)
        : await service.giveTo(widget.device);
    final ok = r == ConnectResult.ok;
    showToast(switch (r) {
      ConnectResult.ok when here => 'Playing on This Device',
      ConnectResult.ok => 'Playing on ${widget.device.name}',
      ConnectResult.notYours => 'Different Sync on ${widget.device.name}',
      ConnectResult.unreachable => 'Couldn\'t Reach ${widget.device.name}',
    }, icon: ok ? Icons.devices_rounded : Icons.error_outline_rounded);
    if (ok && here) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _remote.state,
      builder: (context, s, _) {
        final track = s?.track;
        final art = track?.thumbnailUrl ?? '';
        final backdrop = ref.watch(backdropColorProvider(art));
        return AccentScope(
          artworkUrl: art,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (track != null)
                  ArtworkBackdrop(
                    artUrl: hiResArtwork(art) ?? art,
                    baseColor: backdrop.valueOrNull ?? Colors.black,
                    palette: ref.watch(artworkPaletteProvider(art)).valueOrNull,
                    trackId: track.id,
                  ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(top: topWindowInset(context)),
                    child: s == null ? _waiting(context) : _player(context, s),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _waiting(BuildContext context) => Column(
    children: [
      _topBar(context),
      Expanded(
        child: Center(
          child: _failed != null
              ? Text(
                  _message(_failed!),
                  textAlign: TextAlign.center,
                  style: context.texts.bodyLarge,
                )
              : const CircularProgressIndicator(),
        ),
      ),
    ],
  );

  Widget _topBar(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Close',
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 30,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );

  Widget _player(BuildContext context, RemoteState s) {
    final track = s.track;
    final accent = context.colors.accent;
    final pos = s.livePosition;
    final total = s.duration.inMilliseconds.toDouble();
    final muted = Colors.white.withValues(alpha: 0.7);
    final hasMusic = ref.read(playerProvider).current != null;
    return Column(
      children: [
        _topBar(context),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              // La copertina del brano che suona dall'altra parte, con
              // la stessa macchia che ha sul dispositivo. Senza ombra:
              // dietro una macchia un'ombra rettangolare si vede come un
              // riquadro.
              child: AspectRatio(
                aspectRatio: 1,
                child: track == null
                    ? Spot(
                        seed: '',
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      )
                    : SpotThumbnail(url: track.thumbnailUrl, hiRes: true),
              ),
            ),
          ),
        ),
        ContentWidth(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text(
                  track?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.headlineSmall,
                ),
                Text(
                  track?.author ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyLarge?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
                SpotSlider(
                  seed: 'seek',
                  style: SpotSliderStyle.wave,
                  value: (_seeking ?? pos.inMilliseconds.toDouble()).clamp(
                    0,
                    total <= 0 ? 1 : total,
                  ),
                  max: total <= 0 ? 1 : total,
                  label: (v) => _fmt(Duration(milliseconds: v.round())),
                  semanticLabel: 'Position',
                  onChanged: total <= 0
                      ? null
                      : (v) => setState(() => _seeking = v),
                  onChangeEnd: (v) {
                    _remote.command('seek', {'ms': v.round()});
                    setState(() => _seeking = null);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(pos),
                      style: context.texts.bodySmall?.copyWith(color: muted),
                    ),
                    Text(
                      '-${_fmt(s.duration - pos)}',
                      style: context.texts.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _glyph(Icons.skip_previous_rounded, 'Previous', 'previous'),
                    const SizedBox(width: 20),
                    SolidPlayButton(
                      isLoading: false,
                      isPlaying: s.playing,
                      onPressed: () => _remote.command('toggle'),
                    ),
                    const SizedBox(width: 20),
                    _glyph(Icons.skip_next_rounded, 'Next', 'next'),
                  ],
                ),
                const SizedBox(height: 14),
                // Il volume, la stessa barra spenta finche' non la si tocca.
                Row(
                  children: [
                    Icon(Icons.volume_mute_rounded, size: 18, color: muted),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SpotSlider(
                          seed: 'volume',
                          value: (_volume ?? s.volume).clamp(0, 100),
                          max: 100,
                          headAtRest: false,
                          idleColor: context.colors.accentMuted,
                          label: (v) => '${v.round()}%',
                          semanticLabel: 'Volume',
                          onChanged: (v) {
                            setState(() => _volume = v);
                            _remote.command('volume', {'v': v});
                          },
                          onChangeEnd: (_) => setState(() => _volume = null),
                        ),
                      ),
                    ),
                    Icon(Icons.volume_up_rounded, size: 18, color: muted),
                  ],
                ),
                const SizedBox(height: 16),
                // Dove sta suonando, come l'etichetta AirPlay di Apple
                // Music, e le due mosse.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_iconOf(widget.device), size: 16, color: accent),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Capsule(
                        icon: Icons.south_rounded,
                        label: 'Play Here',
                        onTap: track == null ? null : () => _move(here: true),
                      ),
                    ),
                    if (hasMusic) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _Capsule(
                          icon: Icons.north_rounded,
                          label: 'Play Mine There',
                          onTap: () => _move(here: false),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _glyph(IconData icon, String tooltip, String command) => IconButton(
    tooltip: tooltip,
    iconSize: 44,
    color: Colors.white,
    icon: Icon(icon),
    onPressed: () => _remote.command(command),
  );
}

/// Una capsula di vetro chiaro, come i pulsanti dei fogli di Apple.
class _Capsule extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Capsule({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: onTap == null ? 0.06 : 0.14),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
