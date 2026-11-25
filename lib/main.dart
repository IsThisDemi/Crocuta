import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'design/app_theme.dart';
import 'design/chrome.dart';
import 'providers.dart';
import 'services/library_tidy.dart';
import 'screens/app_shell.dart';
import 'shortcuts.dart';
import 'services/siri_service.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/connect.dart';
import 'widgets/toast.dart';
import 'design/motion.dart';
import 'navigation.dart';
import 'services/voice_assistant.dart';
import 'widgets/voice_sheet.dart';
import 'design/spot.dart';
import 'design/text_pulse.dart';
import 'design/accent.dart';
import 'dev/readme_demo.dart';
import 'dev/readme_shots.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit (libmpv) — required before creating any Player.
  MediaKit.ensureInitialized();

  // Preload the Liquid Glass shaders (non-blocking async I/O).
  await LiquidGlassWidgets.initialize();

  final storage = StorageService();
  if (readmeShotsEnabled) {
    // Le foto del README su una libreria finta: la vera non si apre.
    await openReadmeDemoStorage(storage);
  } else {
    await storage.init();
  }
  await SyncService.load(storage);
  // Prima che il servizio legga gli abbinamenti: la regola che riconosce
  // le versioni canzone e' cambiata (v2: anche le radio edit), e i video
  // che la vecchia aveva scartato vanno riprovati.
  await storage.retireUnmatchedBefore(2);

  runApp(
    LiquidGlassWidgets.wrap(
      child: ProviderScope(
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const CrocutaApp(),
      ),
      brightnessResolver: Theme.maybeBrightnessOf,
      theme: buildGlassTheme(),
    ),
  );
}

class CrocutaApp extends StatelessWidget {
  const CrocutaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crocuta',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Niente barre di scorrimento, in tutta l'app: sul desktop comparivano
      // sul bordo di ogni lista e rompevano l'immersione — copertine e
      // velature che arrivano al bordo, e una striscia grigia sopra. Si
      // scorre lo stesso, col trackpad, la rotella o trascinando.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      // builder sits above the Navigator, so the shortcuts apply on every
      // route, including the full-screen player and the lyrics.
      // L'orologio delle macchie vive, uno per tutta l'app (vedi
      // SpotMotionHost): qui, sotto il MaterialApp, perche' deve sapere se
      // il movimento ridotto e' attivo, e sopra ogni pagina e foglio.
      builder: (context, child) => _ReadmeShotsBoundary(
        child: TapOriginTracker(
          child: Consumer(
            builder: (context, ref, child) => SpotMotionHost(
              // Le macchie si muovono col brano in ascolto, quanto dicono
              // le Impostazioni.
              beat: ref.read(playerProvider.notifier).beatPulse,
              intensity: ref.watch(spotsMusicProvider),
              child: TextPulse(
                enabled: ref.watch(textPulseProvider),
                child: child!,
              ),
            ),
            // Il colore del brano in ascolto per tutto cio' che si apre sopra
            // le pagine — menu, fogli, avvisi, il player — che vive sul
            // navigatore radice, fuori dalla shell e dal suo AccentScope. Senza,
            // i menu del player avevano le icone del viola di ripiego.
            child: Consumer(
              builder: (context, ref, child) => AccentScope(
                artworkUrl: ref.watch(
                  playerProvider.select((s) => s.current?.thumbnailUrl ?? ''),
                ),
                child: child!,
              ),
              child: AppShortcuts(
                child: ToastHost(
                  child: _SnackBarHost(child: child ?? const SizedBox.shrink()),
                ),
              ),
            ),
          ),
        ),
      ),
      home: const _SessionGate(child: SheetUnderlay(child: AppShell())),
    );
  }
}

/// Lo Scaffold radice, trasparente, che serve solo a mostrare le SnackBar.
///
/// ScaffoldMessenger le disegna soltanto nello Scaffold piu' esterno, e
/// l'app non ne aveva uno: le pagine usano GlassScaffold, che Scaffold non
/// e'. Cosi' "Playing next", "Sync failed" o l'"Undo" dopo aver tolto un
/// brano restavano in coda senza comparire — e saltavano fuori tutte
/// insieme aprendo il player, l'unica schermata con uno Scaffold vero.
///
/// Sta sopra il Navigator, quindi vale per ogni pagina, e solleva la
/// SnackBar sopra tab bar e mini player, che altrimenti la coprirebbero.
class _SnackBarHost extends ConsumerWidget {
  final Widget child;

  const _SnackBarHost({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        snackBarTheme: theme.snackBarTheme.copyWith(
          insetPadding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            bottomChromeInset(context, ref) + AppSpacing.xs,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // La tastiera la gestiscono le pagine: qui ridimensionare sposterebbe
        // l'intera app, tab bar compresa.
        resizeToAvoidBottomInset: false,
        body: child,
      ),
    );
  }
}

/// Restores the last playback session on launch and saves it on the way out.
///
/// Deliberately here, wrapping [MaterialApp.home], rather than inside the
/// shell: the shell is the part of the app most likely to be restructured,
/// and this hook must not disappear with it.
class _SessionGate extends ConsumerStatefulWidget {
  final Widget child;

  const _SessionGate({required this.child});

  @override
  ConsumerState<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<_SessionGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();

    voiceRequests.addListener(_openVoice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerProvider.notifier).restoreSession();
      // Siri: pubblica l'indice della libreria e ritira l'eventuale
      // comando lasciato da un App Intent mentre l'app era spenta.
      ref.read(siriServiceProvider).start();
      // Crocuta Connect: questo dispositivo si annuncia sulla rete di casa e
      // cerca gli altri.
      unawaited(ref.read(connectServiceProvider).start());
      // Bounded cache housekeeping, off the critical path.
      unawaited(ref.read(songPreloaderProvider).prune());
      // I video salvati in libreria rivestiti da canzone, in sottofondo.
      ref.read(libraryTidyProvider);
      // Una passata all'avvio, cosi' quello che hai aggiunto sull'altro
      // dispositivo e' gia' li' quando apri la libreria. Silenziosa: se
      // non e' configurata o la rete manca, non succede niente.
      unawaited(runSync(ref));
    });

    _lifecycle = AppLifecycleListener(
      // "Riproduci X su Crocuta" con l'app gia' aperta ci riporta qui:
      // il comando e' stato depositato un istante fa e va ritirato ora.
      onResume: () =>
          unawaited(ref.read(siriServiceProvider).takePendingCommand()),
      onInactive: _save,
      onHide: _save,
      onPause: _save,
      // The reliable hook for ⌘Q and closing the window on macOS.
      onExitRequested: () async {
        _save();
        return ui.AppExitResponse.exit;
      },
    );
  }

  void _save() {
    ref.read(playerProvider.notifier).persistNow();
    // E una quando l'app si ferma: e' il momento in cui quello che hai
    // fatto qui deve partire verso gli altri dispositivi.
    unawaited(runSync(ref));
  }

  void _openVoice() {
    final context = rootNavigatorKey.currentContext;
    if (context != null) unawaited(showVoiceSheet(context));
  }

  @override
  void dispose() {
    voiceRequests.removeListener(_openVoice);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// In debug, con `--dart-define=README_SHOTS=...`, avvolge l'app nel
/// confine che lib/dev/readme_shots.dart fotografa e lancia il giro delle
/// schermate. Altrimenti non fa niente.
class _ReadmeShotsBoundary extends ConsumerStatefulWidget {
  final Widget child;

  const _ReadmeShotsBoundary({required this.child});

  @override
  ConsumerState<_ReadmeShotsBoundary> createState() =>
      _ReadmeShotsBoundaryState();
}

class _ReadmeShotsBoundaryState extends ConsumerState<_ReadmeShotsBoundary> {
  @override
  void initState() {
    super.initState();
    if (readmeShotsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => runReadmeShots(ref));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!readmeShotsEnabled) return widget.child;
    return RepaintBoundary(key: readmeShotsBoundary, child: widget.child);
  }
}
