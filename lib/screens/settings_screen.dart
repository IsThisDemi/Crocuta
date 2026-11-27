import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../providers.dart';
import '../services/connect.dart';
import '../services/discovery_controller.dart';
import '../services/spotify_import_controller.dart';
import '../services/sync_service.dart';
import '../widgets/content_width.dart';
import '../widgets/glass_surfaces.dart';
import '../widgets/sub_page.dart';
import '../widgets/toast.dart';
import 'spotify_import_screen.dart';
import '../design/spot.dart';
import '../widgets/spot_slider.dart';

/// Le impostazioni, in un posto solo.
///
/// Prima stavano dove la funzione vive — il precaricamento fra i download,
/// la copertina animata in un menu sulla copertina — e restano anche li';
/// qui si trovano tutte insieme, per chi le cerca come si cerca in ogni
/// app: dalla Libreria, in fondo.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _cacheBytes;
  int? _downloadBytes;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    try {
      final preloader = ref.read(songPreloaderProvider);
      final cache = await preloader.cacheSizeBytes();
      final downloads = await preloader.cacheSizeBytes(permanent: true);
      if (!mounted) return;
      setState(() {
        _cacheBytes = cache;
        _downloadBytes = downloads;
      });
    } catch (_) {
      // Senza cartelle (nei test) resta "…".
    }
  }

  static String _size(int? bytes) {
    if (bytes == null) return '…';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _clearCache() async {
    final player = ref.read(playerProvider);
    // Il brano in corso resta: gli si toglierebbe il file da sotto.
    final keep = player.current == null
        ? null
        : await ref.read(youtubeServiceProvider).audioIdFor(player.current!.id);
    await ref.read(songPreloaderProvider).prune(maxBytes: 0, keepId: keep);
    await _measure();
    showToast('Cache Cleared', icon: Icons.check_circle_rounded);
  }

  Future<void> _refreshDiscovery() async {
    setState(() => _refreshing = true);
    await ref.read(discoveryProvider.notifier).refresh(force: true);
    if (!mounted) return;
    setState(() => _refreshing = false);
    showToast('Your Mixes Are Updated', icon: Icons.explore_rounded);
  }

  Future<void> _setConnect(bool on) async {
    await ref.read(storageServiceProvider).setConnectEnabled(on);
    final connect = ref.read(connectServiceProvider);
    await (on ? connect.start() : connect.stop());
    if (mounted) setState(() {});
  }

  /// Il nome con cui gli altri dispositivi vedono questo in Connect.
  Future<void> _rename() async {
    final connect = ref.read(connectServiceProvider);
    final name = await showGlassTextPrompt(
      context: context,
      title: 'Device Name',
      message: 'How your other devices see this one in Crocuta Connect.',
      initial: connect.name,
      confirmLabel: 'Save',
    );
    if (name == null) return;
    await connect.rename(name);
    if (mounted) setState(() {});
  }

  Future<void> _syncNow() async {
    final outcome = await runSync(ref);
    if (outcome == SyncOutcome.failed) {
      showToast('Sync Failed', icon: Icons.cloud_off_rounded);
    } else {
      showToast('Library Synced', icon: Icons.cloud_done_rounded);
    }
  }

  /// Chiede l'indirizzo dello script, o il codice copiato da un altro
  /// dispositivo, e prova subito una passata: se lo script non risponde
  /// si torna a com'era, invece di lasciare una sincronizzazione che
  /// fallira' in silenzio a ogni avvio.
  Future<void> _setUpSync() async {
    final text = await showGlassTextPrompt(
      context: context,
      title: 'Set Up Sync',
      message:
          'Paste the web app URL of your Google Apps Script, or the setup '
          'code from another device with Crocuta.',
      hint: 'https://script.google.com/…/exec',
      confirmLabel: 'Connect',
      verbatim: true,
    );
    if (text == null || !mounted) return;
    final storage = ref.read(storageServiceProvider);

    var config = SyncConfig.fromSetupCode(text);
    if (config == null) {
      final uri = Uri.tryParse(text);
      if (uri == null || uri.scheme != 'https' || !uri.path.endsWith('/exec')) {
        showToast(
          'Not a Script URL or Setup Code',
          icon: Icons.error_outline_rounded,
        );
        return;
      }
      // Un segreto nuovo, lungo e casuale: lo script lo adotta alla prima
      // richiesta, e gli altri dispositivi lo ricevono col codice.
      final rnd = Random.secure();
      final secret = [
        for (var i = 0; i < 24; i++)
          rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      config = SyncConfig(text, secret);
    }

    final before = SyncService.config.value;
    await SyncService.configure(storage, config);
    final outcome = await runSync(ref);
    if (outcome != SyncOutcome.done) {
      await SyncService.configure(storage, before);
      showToast("Couldn't Reach the Script", icon: Icons.cloud_off_rounded);
      return;
    }
    showToast('Sync Is On', icon: Icons.cloud_done_rounded);
  }

  Future<void> _copySetupCode(SyncConfig config) async {
    await Clipboard.setData(ClipboardData(text: config.setupCode));
    showToast('Setup Code Copied', icon: Icons.key_rounded);
  }

  Future<void> _turnOffSync() async {
    final ok = await showGlassConfirm(
      context: context,
      title: 'Turn Off Sync?',
      message:
          'This device stops syncing. Your library stays here, and the copy '
          'on your Drive stays there.',
      confirmLabel: 'Turn Off',
      destructive: true,
    );
    if (!ok) return;
    await SyncService.configure(
      ref.read(storageServiceProvider),
      const SyncConfig('', ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final automix = ref.watch(playerProvider.select((s) => s.automix));
    final radio = ref.watch(radioProvider);
    final preload = ref.watch(autoPreloadProvider);
    final motion = ref.watch(motionCoverProvider);
    final spotsMusic = ref.watch(spotsMusicProvider);
    final textPulse = ref.watch(textPulseProvider);
    final connect = ref.read(connectServiceProvider);
    final connectOn = ref.read(storageServiceProvider).connectEnabled;
    final lastSync = ref.watch(lastSyncProvider);
    final spotify = ref.watch(spotifyImportProvider);
    // Verde di sistema e non l'accento della copertina. L'accento e' tarato
    // per essere chiaro (testo e icone sul fondo scuro), quindi su una
    // copertina poco satura usciva un azzurrino o un grigio: acceso e
    // spento si distinguevano a fatica. Il verde e' quello degli
    // interruttori di iOS e macOS in modalita' scura, e dice "acceso"
    // qualunque cosa stia suonando.
    Widget toggle(bool value, ValueChanged<bool> onChanged) => Switch.adaptive(
      value: value,
      activeTrackColor: context.colors.accent,
      onChanged: onChanged,
    );

    return SubPage(
      title: 'Settings',
      // Il titolo allineato alle righe, che qui stanno in una colonna
      // piu' stretta delle altre pagine.
      maxWidth: 620,
      child: ContentWidth(
        child: ListView(
          padding: EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: listBottomPadding(context, ref),
          ),
          children: [
            _Group(
              header: 'Playback',
              footer:
                  'AutoMix blends each song into the next on the beat, like '
                  'a DJ, keeping the vocals apart. The endless queue keeps '
                  'going with similar songs once an album or playlist ends.',
              rows: [
                _Row(
                  icon: Icons.multitrack_audio_rounded,
                  color: const Color(0xFF8B5CF6),
                  title: 'AutoMix',
                  trailing: toggle(
                    automix,
                    (_) => ref.read(playerProvider.notifier).toggleAutomix(),
                  ),
                ),
                _Row(
                  icon: Icons.all_inclusive_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Endless Queue',
                  trailing: toggle(
                    radio,
                    (v) => ref.read(radioProvider.notifier).set(v),
                  ),
                ),
                _Row(
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFF22C55E),
                  title: 'Preload Next Song',
                  trailing: toggle(
                    preload,
                    (v) => ref.read(autoPreloadProvider.notifier).set(v),
                  ),
                ),
              ],
            ),
            _Group(
              header: 'Appearance',
              footer:
                  'Animated Covers loops a silent clip of the music video in '
                  'the player, when the song has one. With Spots Follow the '
                  'Music the spots swell with the bass and the drums of the '
                  'song playing: slide it all the way left to turn it off. '
                  'Each song is analyzed once, a few seconds after it '
                  'starts. Pulsing Text makes every text bounce too, just '
                  'for fun.',
              rows: [
                _Row(
                  icon: Icons.motion_photos_on_rounded,
                  color: const Color(0xFFEC4899),
                  title: 'Animated Covers',
                  trailing: toggle(
                    motion,
                    (v) => ref.read(motionCoverProvider.notifier).set(v),
                  ),
                ),
                _Row(
                  icon: Icons.graphic_eq_rounded,
                  color: const Color(0xFFF97316),
                  title: 'Spots Follow the Music',
                  value: spotsMusic <= 0
                      ? 'Off'
                      : '${(spotsMusic * 100).round()}%',
                  trailing: SizedBox(
                    width: 150,
                    child: SpotSlider(
                      seed: 'spots-music',
                      height: 32,
                      value: spotsMusic,
                      max: SpotsMusicController.max,
                      divisions: 8,
                      semanticLabel: 'Spots follow the music',
                      onChanged: (v) => ref
                          .read(spotsMusicProvider.notifier)
                          .set(v, persist: false),
                      onChangeEnd: (v) =>
                          ref.read(spotsMusicProvider.notifier).set(v),
                    ),
                  ),
                ),
                _Row(
                  icon: Icons.text_fields_rounded,
                  color: const Color(0xFFEAB308),
                  title: 'Pulsing Text',
                  trailing: toggle(
                    textPulse,
                    (v) => ref.read(textPulseProvider.notifier).set(v),
                  ),
                ),
              ],
            ),
            _Group(
              header: 'Discovery',
              footer:
                  'Discover Weekly changes on Mondays, the Daily Mixes every '
                  'day. Rebuild them now from what you play.',
              rows: [
                _Row(
                  icon: Icons.explore_rounded,
                  color: const Color(0xFF06B6D4),
                  title: 'Refresh My Mixes',
                  onTap: _refreshing ? null : _refreshDiscovery,
                  trailing: _refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ],
            ),
            _Group(
              header: 'Devices',
              footer:
                  'Your devices with Crocuta see each other on this network: '
                  'control one from another, or move the music between them.',
              rows: [
                _Row(
                  icon: Icons.devices_rounded,
                  color: const Color(0xFF3B82F6),
                  title: 'Crocuta Connect',
                  trailing: toggle(connectOn, _setConnect),
                ),
                _Row(
                  icon: Icons.badge_rounded,
                  color: const Color(0xFF64748B),
                  title: 'Name',
                  value: connect.name,
                  onTap: _rename,
                ),
              ],
            ),
            _Group(
              header: 'Library',
              footer:
                  'Bring your Liked Songs, playlists, saved albums and '
                  'followed artists over from Spotify.',
              rows: [
                _Row(
                  icon: Icons.download_rounded,
                  color: const Color(0xFF1DB954),
                  title: 'Import from Spotify',
                  // Un import in corso o fermo si vede anche da qui: si
                  // puo' lasciare la pagina mentre lavora.
                  value: switch (spotify) {
                    SpotifyImportView(running: true, :final progress?)
                        when progress.total > 0 =>
                      '${progress.done}/${progress.total}',
                    SpotifyImportView(running: true) => 'Importing…',
                    SpotifyImportView(:final job?) when !job.finished =>
                      'Paused',
                    _ => null,
                  },
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textFaint,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SpotifyImportScreen(),
                    ),
                  ),
                ),
              ],
            ),
            _Group(
              header: 'Storage',
              footer:
                  'Cached songs start instantly and are removed on their own '
                  'past 512 MB. Downloads stay until you remove them.',
              rows: [
                _Row(
                  icon: Icons.cached_rounded,
                  color: const Color(0xFF94A3B8),
                  title: 'Cached Songs',
                  value: _size(_cacheBytes),
                ),
                _Row(
                  icon: Icons.download_rounded,
                  color: const Color(0xFF10B981),
                  title: 'Downloads',
                  value: _size(_downloadBytes),
                ),
                _Row(
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFFEF4444),
                  title: 'Clear Cache',
                  destructive: true,
                  onTap: (_cacheBytes ?? 0) == 0 ? null : _clearCache,
                ),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: SyncService.config,
              builder: (context, config, _) => config.isComplete
                  ? _Group(
                      header: 'Sync',
                      footer:
                          '${lastSync == null ? 'Never synced.' : 'Last synced ${_ago(lastSync)}.'} '
                          'To sync another device, copy the setup code and '
                          'paste it in Settings there.',
                      rows: [
                        _Row(
                          icon: Icons.cloud_sync_rounded,
                          color: const Color(0xFF0EA5E9),
                          title: 'Sync Now',
                          onTap: _syncNow,
                        ),
                        _Row(
                          icon: Icons.key_rounded,
                          color: const Color(0xFF64748B),
                          title: 'Copy Setup Code',
                          onTap: () => _copySetupCode(config),
                        ),
                        _Row(
                          icon: Icons.cloud_off_rounded,
                          color: const Color(0xFFEF4444),
                          title: 'Turn Off Sync',
                          destructive: true,
                          onTap: _turnOffSync,
                        ),
                      ],
                    )
                  : _Group(
                      header: 'Sync',
                      footer:
                          'Keep your library and listening history the same '
                          'on all your devices, through a small Google Apps '
                          'Script on your own Drive.',
                      rows: [
                        _Row(
                          icon: Icons.cloud_sync_rounded,
                          color: const Color(0xFF0EA5E9),
                          title: 'Set Up Sync',
                          onTap: _setUpSync,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime at) {
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours} h ago';
    return '${ago.inDays} d ago';
  }
}

/// Un gruppo come nelle Impostazioni di iOS e macOS: il titoletto sopra,
/// le righe in un riquadro arrotondato con i separatori, la spiegazione
/// sotto, in piccolo — non sotto ogni riga.
class _Group extends StatelessWidget {
  final String header;
  final String? footer;
  final List<Widget> rows;

  const _Group({required this.header, this.footer, required this.rows});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Il gruppo si annuncia come le sezioni delle altre pagine, non
          // con un'etichetta maiuscola grigia: le impostazioni sono una
          // pagina dell'app, non un pannello di sistema.
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, 0, 4),
            child: Text(header, style: context.texts.headlineSmall),
          ),
          // Niente riquadro grigio: le righe stanno sul nero, separate da
          // un filo.
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    rows[i],
                    // Il separatore parte dopo l'icona, come in iOS.
                    if (i < rows.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 64),
                        child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                6,
                AppSpacing.md,
                0,
              ),
              child: Text(
                footer!,
                style: context.texts.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Una riga: l'icona bianca in un quadratino colorato, il titolo, e a
/// destra un interruttore, un valore o la freccia se porta da qualche
/// parte.
class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    this.trailing,
    this.value,
    this.onTap,
    this.destructive = false,
  });

  Widget _title(BuildContext context, Color muted) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.texts.bodyLarge?.copyWith(
      color: destructive
          ? (onTap == null ? muted : context.colors.danger)
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          child: Row(
            children: [
              // L'icona dentro una macchia del suo colore, come ogni altra
              // cosa colorata dell'app.
              SpotMotionBuilder(
                builder: (context, t) => Container(
                  width: 34,
                  height: 34,
                  decoration: ShapeDecoration(
                    color: color,
                    shape: SpotBorder(
                      seed: title,
                      wobble: 0.7,
                      time: t,
                      music: SpotMotion.musicOf(context),
                    ),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Senza valore il titolo prende la riga, e l'interruttore resta
              // sul bordo destro; col valore si dividono lo spazio, e il
              // valore si accorcia coi puntini — un nome di dispositivo
              // puo' essere lungo.
              if (value == null)
                Expanded(child: _title(context, muted))
              else ...[
                Flexible(child: _title(context, muted)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: context.texts.bodyLarge?.copyWith(color: muted),
                  ),
                ),
              ],
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
