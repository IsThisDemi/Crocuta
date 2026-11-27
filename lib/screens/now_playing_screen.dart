import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../design/spot.dart';
import '../providers.dart';
import '../services/mini_player_window.dart';
import '../services/karaoke.dart';
import '../services/player_state.dart';
import '../services/sleep_timer.dart';
import '../widgets/airplay_button.dart';
import '../widgets/artwork_hero.dart';
import '../widgets/album_link.dart';
import '../widgets/artist_links.dart';
import '../widgets/glass_surfaces.dart';
import '../widgets/progress_fill.dart';
import '../widgets/content_width.dart';
import '../widgets/drawer_dismiss.dart';
import '../widgets/spot_slider.dart';
import '../widgets/accent_glow.dart';
import '../widgets/seek_bar.dart';
import '../widgets/spot_controls.dart';
import '../widgets/section_header.dart';
import 'queue_screen.dart';
import '../widgets/thumbnail.dart';
import '../widgets/track_tile.dart';
import 'eq_screen.dart';
import 'lyrics_screen.dart';
import '../models/track.dart';
import 'video_screen.dart';
import '../widgets/motion_cover.dart';
import '../widgets/player_keys.dart';
import '../widgets/connect_views.dart';

/// Cosa occupa la parte alta del player.
enum _Pane { artwork, lyrics, queue }

class NowPlayingScreen extends ConsumerStatefulWidget {
  /// Il pannello aperto all'arrivo: 'lyrics' o 'queue'. Serve alle foto
  /// del README (lib/dev/readme_shots.dart); di norma si apre sulla
  /// copertina.
  final String? initialPane;

  const NowPlayingScreen({super.key, this.initialPane});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  /// Testo e coda si aprono qui dentro, al posto della copertina, come in
  /// Apple Music. Prima erano pagine a parte: si usciva dal player per
  /// leggere il testo, e per tornare ai comandi bisognava riaprirlo.
  late _Pane _pane = switch (widget.initialPane) {
    'lyrics' => _Pane.lyrics,
    'queue' => _Pane.queue,
    _ => _Pane.artwork,
  };

  void _toggle(_Pane pane) =>
      setState(() => _pane = _pane == pane ? _Pane.artwork : pane);

  /// Da questa larghezza testo e coda non prendono il posto della
  /// copertina ma le si affiancano, come Apple Music sul Mac: sotto, in
  /// una finestra larga, il pannello era una colonna da telefono in mezzo
  /// a due fasce vuote, e i comandi sparivano per lasciargli il posto.
  static const double _wideMin = 900;

  /// Quanto ci mette la colonna del player a scivolare di lato.
  static const Duration _slide = Duration(milliseconds: 480);

  @override
  Widget build(BuildContext context) {
    // Solo i campi che questa schermata disegna davvero.
    //
    // Prima osservava l'intero stato del player, e la posizione cambia
    // cinque-dieci volte al secondo: l'albero intero — sfondo sfocato
    // compreso — si ricostruiva a quel ritmo. Durante un trascinamento a
    // 60fps vuol dire una ricostruzione ogni sei-dodici fotogrammi, che si
    // sente come una serie di scatti regolari mentre si scorre. La barra di
    // avanzamento la posizione se la osserva da se'.
    // Shuffle, ripeti e AutoMix non stanno piu' qui: li osserva il
    // pulsante "…" che li mostra, e cambiarli non ricostruisce il player.
    final (track, error, isLoading, isPlaying) = ref.watch(
      playerProvider.select(
        (s) => (s.current, s.error, s.isLoading, s.isPlaying),
      ),
    );

    if (track == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Now playing')),
        body: const Center(child: Text('Nothing is playing.')),
      );
    }

    final notifier = ref.read(playerProvider.notifier);
    final paneOpen = _pane != _Pane.artwork;

    final artwork = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        // In pausa la copertina si ritira un poco e torna grande quando
        // riparte, come in Apple Music: lo stato si legge da lontano, senza
        // cercare il tasto. Durante il caricamento resta grande, altrimenti
        // fra un brano e l'altro pulserebbe.
        child: AnimatedScale(
          scale: isPlaying || isLoading ? 1.0 : 0.84,
          duration: const Duration(milliseconds: 450),
          curve: isPlaying || isLoading
              ? Curves.easeOutBack
              : Curves.easeOutCubic,
          // La copertina e' una macchia, con attorno le macchie dei suoi
          // colori. Si tiene un margine a destra e in basso a sinistra per
          // i satelliti, che escono dal riquadro.
          child: LayoutBuilder(
            builder: (context, box) {
              final side = math.min(box.maxWidth * 0.84, box.maxHeight * 0.94);
              return Center(
                child: ArtworkHero(
                  url: track.thumbnailUrl,
                  radius: 28,
                  child: SpotCover(
                    url: track.thumbnailUrl,
                    size: side,
                    // Il videoclip in loop, muto, quando c'e'. Tenendo
                    // premuto: spegnerlo, o guardare il video vero.
                    child: GestureDetector(
                      onLongPressStart: (d) =>
                          _coverMenu(context, track, d.globalPosition),
                      onSecondaryTapDown: (d) =>
                          _coverMenu(context, track, d.globalPosition),
                      child: MotionCover(
                        track: track,
                        cover: Thumbnail(
                          url: track.thumbnailUrl,
                          fit: BoxFit.cover,
                          hiRes: true,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final linkStyle = context.texts.bodyLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.85),
    );
    final details = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      // Il cuore accanto al titolo, come la stella di Apple Music: e' un
      // giudizio su questo brano, e sta con il suo nome. Da solo in cima,
      // all'angolo opposto della freccia, sembrava un comando della pagina.
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(fontSize: 40, height: 1.0),
                ),
                const SizedBox(height: 4),
                // Fra titolo e interpreti: l'album e' un dato del brano, non di
                // chi lo suona. Dall'alto si legge il titolo, dove sta, e di chi e'.
                AlbumLink(track: track, style: linkStyle),
                const SizedBox(height: 4),
                // Gli interpreti nel colore del brano, spento: il Builder
                // legge l'accento dell'AccentScope del player, che sta sotto
                // il contesto di questa schermata.
                Builder(
                  builder: (context) => ArtistLinks(
                    track: track,
                    style: linkStyle?.copyWith(
                      color: context.colors.accentMuted,
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      error,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const _FavButton(),
          // Gli interruttori (shuffle, AutoMix, coda infinita, ripeti,
          // timer) in un menu accanto al cuore, come il "…" di Apple
          // Music: erano una fila di cinque icone sopra il play, e con le
          // altre due file il player ne mostrava quindici. Quelli accesi
          // restano in vista, piccoli, dentro il pulsante.
          const _MoreButton(),
        ],
      ),
    );

    // Con testo o coda aperti la copertina diventa una riga, come in Apple
    // Music: resta chiaro cosa suona, e tutto lo spazio va al pannello.
    final Widget top = switch (_pane) {
      _Pane.artwork => Column(
        children: [
          const SizedBox(height: 8),
          Expanded(child: artwork),
          const SizedBox(height: 28),
          details,
        ],
      ),
      _Pane.lyrics || _Pane.queue => Column(
        children: [
          _CompactHeader(
            onTap: () => setState(() => _pane = _Pane.artwork),
            sing: _pane == _Pane.lyrics,
          ),
          if (_pane == _Pane.lyrics) const _SingBar(),
          Expanded(child: _EdgeFade(child: _paneView(track, _pane))),
        ],
      ),
    };

    // In un Builder: il colore del brano lo mette l'AccentScope qui sotto,
    // e il contesto della schermata sta sopra di lui. Letto da li', gli
    // interruttori accesi restavano sul viola di marca a ogni brano.
    final controls = Builder(
      builder: (context) {
        return Column(
          children: [
            const SizedBox(height: 16),
            const SeekBar(),
            const SizedBox(height: 10),
            // Precedente e successivo come glifi grandi, senza cerchio.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PlayerGlyph(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Previous',
                  onTap: notifier.previous,
                ),
                const SizedBox(width: 20),
                SpotPlayButton(
                  loading: isLoading,
                  playing: isPlaying,
                  onPressed: notifier.toggle,
                  size: 74,
                ),
                const SizedBox(width: 20),
                PlayerGlyph(
                  icon: Icons.skip_next_rounded,
                  tooltip: 'Next',
                  onTap: notifier.next,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Il volume sotto il play, come in Apple Music: sul Mac e sul
            // telefono con le cuffie e' il comando che si cerca piu' spesso
            // dopo il play, e prima stava solo nei tasti della tastiera.
            const _VolumeBar(),
            const SizedBox(height: 10),
            // Row 3: la fila in fondo di Apple Music — testo, uscita audio,
            // coda — piu' l'equalizzatore, che e' un'impostazione del suono
            // come l'uscita. Stanno sempre allo stesso posto, aperti o chiusi.
            _PaneBar(
              pane: _pane,
              onLyrics: () => _toggle(_Pane.lyrics),
              onQueue: () => _toggle(_Pane.queue),
              // Un foglio sopra il player, non una pagina: si regola il suono
              // senza perdere di vista il brano, e si chiude con un gesto.
              onEq: () => showEqSheet(context),
              // Il videoclip vero, da guardare: il brano si ferma e riparte
              // alla chiusura.
              onVideo: () => VideoScreen.open(context, track),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );

    // Esc chiude, come un foglio sul Mac: sul desktop la barretta si clicca,
    // ma la mano sta gia' sulla tastiera.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: DrawerDismiss(
          child: AccentScope(
            // Come album e artista: il colore lo detta la copertina in
            // ascolto. Senza questo la schermata restava sul viola di
            // marca mentre lo sfondo seguiva gia' l'artwork.
            artworkUrl: track.thumbnailUrl,
            child: Scaffold(
              // Apple Music style: blurred cover spanning the whole background,
              // dimmed for legibility, plus a coloful gradient that adapts to the
              // artwork as the track changes.
              body: Stack(
                fit: StackFit.expand,
                children: [
                  // Nero, con il colore del brano che sale da dietro la
                  // copertina. Era la copertina sfocata a tutto schermo:
                  // in Macchia la base e' nera e il colore e' una luce, non
                  // un muro, cosi' le macchie si staccano dal fondo.
                  Builder(
                    builder: (context) => AccentGlow(
                      color: context.colors.accent,
                      second: ref
                          .watch(artworkPaletteProvider(track.thumbnailUrl))
                          .valueOrNull
                          ?.swatches
                          .skip(1)
                          .firstOrNull,
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      // I semafori della finestra galleggiano sopra il contenuto:
                      // senza questo margine la barra del player ci finisce sotto.
                      padding: EdgeInsets.only(top: topWindowInset(context)),
                      child: Column(
                        children: [
                          // Sul telefono la barretta ha la sua riga; sul
                          // desktop galleggia sopra (vedi sotto) e non ruba
                          // altezza a comandi e copertina.
                          if (!_GrabberState._desktop)
                            const DrawerHandle(child: _Grabber()),
                          Expanded(
                            // Il player occupa esattamente una schermata: i
                            // suggeriti stanno sotto e si raggiungono scorrendo.
                            // L'altezza qui e' fissata (non un minimo) perche' la
                            // copertina possa usare Expanded per prendersi lo
                            // spazio che avanza: dentro uno scroll l'altezza
                            // sarebbe illimitata e Expanded non avrebbe nulla da
                            // cui partire.
                            child: LayoutBuilder(
                              builder: (context, constraints) => SingleChildScrollView(
                                // Con testo o coda aperti scorre il pannello,
                                // non il player: due scroll uno dentro
                                // l'altro si contenderebbero lo stesso gesto.
                                physics: paneOpen
                                    ? const NeverScrollableScrollPhysics()
                                    : DrawerDismiss.physicsOf(context),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      // Una schermata sola finche' c'e'
                                      // spazio, ma con un minimo: sotto, il
                                      // blocco fisso (titolo su due righe,
                                      // artisti, album, seek e comandi) non si
                                      // comprime oltre e sfondava. Con il
                                      // minimo se ne occupa lo scroll che gia'
                                      // avvolge tutto.
                                      // 480 e non 560: sotto, in una finestra
                                      // del Mac non altissima, la fila in
                                      // fondo finiva oltre il bordo. La
                                      // copertina si stringe per fare posto.
                                      height: constraints.maxHeight < _minHeight
                                          ? _minHeight
                                          : constraints.maxHeight,
                                      child: constraints.maxWidth >= _wideMin
                                          ? _wide(
                                              constraints.maxWidth,
                                              track: track,
                                              player: Column(
                                                children: [
                                                  const SizedBox(height: 8),
                                                  Expanded(child: artwork),
                                                  const SizedBox(height: 28),
                                                  details,
                                                  controls,
                                                ],
                                              ),
                                            )
                                          : ContentWidth(
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: AnimatedSwitcher(
                                                      duration: AppMotion.base,
                                                      switchInCurve:
                                                          Curves.easeOutCubic,
                                                      switchOutCurve:
                                                          Curves.easeInCubic,
                                                      layoutBuilder:
                                                          (current, previous) =>
                                                              Stack(
                                                                fit: StackFit
                                                                    .expand,
                                                                children: [
                                                                  ...previous,
                                                                  ?current,
                                                                ],
                                                              ),
                                                      child: KeyedSubtree(
                                                        key: ValueKey(_pane),
                                                        child: top,
                                                      ),
                                                    ),
                                                  ),
                                                  controls,
                                                ],
                                              ),
                                            ),
                                    ),
                                    // Fuori dal riquadro alto una schermata:
                                    // si raggiungono scorrendo. Con un
                                    // pannello aperto no: non si scorre.
                                    if (!paneOpen) ...[
                                      _SuggestedSection(
                                        videoId: track.id,
                                        artist: track.author,
                                      ),
                                      const SizedBox(height: 40),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Sul desktop la barretta galleggia in cima, sopra il
                  // player a tutto schermo: compare col mouse vicino.
                  if (_GrabberState._desktop)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _Grabber(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// L'altezza sotto cui il player smette di stare in una schermata e
  /// comincia a scorrere: quella del blocco fisso (titolo, barra, comandi,
  /// fila in fondo) con una copertina piccola.
  static const double _minHeight = 480;

  /// Testo o coda del brano [track], come pannello del player. Con
  /// [width] e' la colonna di destra del player largo.
  Widget _paneView(Track track, _Pane pane, {double? width}) {
    if (pane == _Pane.queue) return const QueueScreen(embedded: true);
    return LyricsView(
      // Un brano nuovo e' un testo nuovo: senza chiave lo stato (verso
      // attivo, scorrimento) passava da uno all'altro.
      key: ValueKey(track.id),
      title: track.title,
      artist: track.author,
      topInset: AppSpacing.xl,
      // Nella colonna larga il corpo di Apple Music sul Mac: il testo si
      // legge da piu' lontano, e lo spazio c'e'.
      fontSize: width == null ? 26 : (width >= 600 ? 32 : 28),
      maxWidth: width == null ? 620 : 760,
    );
  }

  /// Il player su una finestra larga: con testo o coda aperti la colonna
  /// del player (copertina, titolo, barra, comandi) scivola a sinistra e
  /// il pannello prende il resto, a tutta altezza. Chiuso, la colonna
  /// torna al centro e la pagina e' identica a quella stretta.
  ///
  /// La colonna resta intera, non diventa la riga compatta del telefono:
  /// su un Mac lo spazio c'e', e il testo si segue meglio con la
  /// copertina e i comandi accanto.
  Widget _wide(double width, {required Track track, required Widget player}) {
    final open = _pane != _Pane.artwork;
    final margin = math.max(AppSpacing.lg, width * 0.04);
    final closedWidth = math.min(620.0, width);
    final openWidth = (width * 0.4).clamp(380.0, 560.0);
    final panelLeft = margin + openWidth + AppSpacing.xl;
    final panelWidth = width - panelLeft - margin;
    return Stack(
      children: [
        // Scivola invece di saltare: si vede dove va la copertina, e il
        // pannello entra nello spazio che lei lascia.
        AnimatedPositioned(
          duration: _slide,
          curve: Curves.easeInOutCubic,
          top: 0,
          bottom: 0,
          left: open ? margin : (width - closedWidth) / 2,
          width: open ? openWidth : closedWidth,
          child: player,
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: panelLeft,
          width: panelWidth,
          // Lo switcher tiene il pannello vecchio finche' sfuma, e poi lo
          // toglie: un testo nascosto non deve restare a inseguire il brano.
          child: AnimatedSwitcher(
            duration: _slide,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: !open
                ? const SizedBox.expand(key: ValueKey('none'))
                : KeyedSubtree(
                    key: ValueKey(_pane),
                    child: Column(
                      children: [
                        // Il microfono del karaoke: nella colonna stretta
                        // sta nella riga del brano, qui in cima al testo.
                        if (_pane == _Pane.lyrics) ...[
                          const Padding(
                            padding: EdgeInsets.only(top: AppSpacing.sm),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _SingToggle(),
                            ),
                          ),
                          const _SingBar(),
                        ],
                        Expanded(
                          child: _EdgeFade(
                            child: _paneView(track, _pane, width: panelWidth),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _coverMenu(
    BuildContext context,
    Track track,
    Offset position,
  ) async {
    final animated = ref.read(motionCoverProvider);
    final picked = await showGlassMenu<String>(
      context: context,
      globalPosition: position,
      items: [
        GlassMenuItem(
          value: 'video',
          icon: Icons.smart_display_rounded,
          label: 'Watch video',
        ),
        GlassMenuItem(
          value: 'motion',
          icon: animated
              ? Icons.motion_photos_off_rounded
              : Icons.motion_photos_on_rounded,
          label: animated
              ? 'Turn off animated cover'
              : 'Turn on animated cover',
        ),
      ],
    );
    if (!context.mounted) return;
    switch (picked) {
      case 'video':
        await VideoScreen.open(context, track);
      case 'motion':
        await ref.read(motionCoverProvider.notifier).set(!animated);
    }
  }
}

IconData _repeatIcon(RepeatMode mode) => switch (mode) {
  RepeatMode.off => Icons.repeat,
  RepeatMode.all => Icons.repeat,
  RepeatMode.one => Icons.repeat_one,
};

/// La barretta in cima, come Apple Music: al posto della freccia e del
/// titolo "Now playing", che dicevano con due oggetti quello che la forma
/// del cassetto dice da sola.
///
/// Sul telefono si trascina giu' (lo fa DrawerDismiss) o si tocca. Sul
/// desktop, dove una schermata non si trascina, e' un pulsante, e non si
/// vede: il player resta a tutto schermo, pulito, e la barretta compare
/// solo col mouse nella fascia in alto — come i comandi di un video. Un
/// clic chiude; Esc fa lo stesso.
class _Grabber extends StatefulWidget {
  const _Grabber();

  @override
  State<_Grabber> createState() => _GrabberState();
}

class _GrabberState extends State<_Grabber> {
  bool _hover = false;

  /// Il mouse nella fascia in alto: solo allora, sul desktop, si vede.
  bool _near = false;

  static final bool _desktop = !(Platform.isIOS || Platform.isAndroid);

  @override
  Widget build(BuildContext context) {
    final grabber = _pill(context);
    if (!_desktop) return grabber;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => _near = true),
      onExit: (_) => setState(() => _near = false),
      child: SizedBox(
        width: double.infinity,
        child: AnimatedOpacity(
          duration: AppMotion.base,
          opacity: _near ? 1 : 0,
          child: IgnorePointer(ignoring: !_near, child: grabber),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context) {
    // A destra il pulsante dei dispositivi (Crocuta Connect), che c'e' solo
    // quando in rete c'e' un altro Crocuta.
    return Stack(
      alignment: Alignment.center,
      children: [
        _bar(context),
        const Positioned(right: 4, child: ConnectButton()),
      ],
    );
  }

  Widget _bar(BuildContext context) {
    return Center(
      child: Tooltip(
        message: 'Close',
        waitDuration: const Duration(milliseconds: 600),
        child: Semantics(
          button: true,
          label: 'Close player',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              // Piu' grande della barretta: si prende senza mirare.
              child: SizedBox(
                width: 96,
                // Sul desktop una fascia piu' alta, che il mouse trova
                // senza cercarla.
                height: _desktop ? 44 : 28,
                child: Center(
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: _hover ? 44 : 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: _hover ? 0.75 : 0.4,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Il brano in una riga, sopra testo e coda. Toccarla riporta la copertina.
/// Il cuore del brano in riproduzione: un'icona nuda accanto al titolo,
/// non un cerchio di vetro.
class _FavButton extends ConsumerWidget {
  const _FavButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerProvider.select((s) => s.current));
    if (track == null) return const SizedBox.shrink();
    final isFav = ref.watch(
      favoritesProvider.select((f) => f.any((t) => t.id == track.id)),
    );
    return IconButton(
      tooltip: isFav ? 'Remove from Liked Songs' : 'Add to Liked Songs',
      onPressed: () => ref.read(favoritesProvider.notifier).toggle(track),
      icon: AnimatedSwitcher(
        duration: AppMotion.fast,
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(isFav),
          size: 26,
          color: isFav
              ? context.colors.favorite
              : Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _CompactHeader extends ConsumerWidget {
  final VoidCallback onTap;

  /// Col testo aperto: accanto al cuore il microfono del karaoke, come in
  /// Apple Music Sing, che sta proprio li'.
  final bool sing;

  const _CompactHeader({required this.onTap, this.sing = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerProvider.select((s) => s.current));
    if (track == null) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 56,
                  child: Thumbnail(url: track.thumbnailUrl, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (sing) const _SingToggle(),
            const _FavButton(),
            // Anche qui: con testo o coda aperti, sul telefono, gli
            // interruttori non devono sparire.
            const _MoreButton(),
          ],
        ),
      ),
    );
  }
}

/// Il microfono del karaoke, come Apple Music Sing.
class _SingToggle extends ConsumerWidget {
  const _SingToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Toggle(
      icon: Icons.mic_none_rounded,
      activeIcon: Icons.mic_rounded,
      tooltip: 'Sing: lower the vocals',
      active: ref.watch(karaokeProvider.select((k) => k.enabled)),
      progress: ref.watch(karaokeProvider.select((k) => k.preparing)),
      onTap: () => ref
          .read(playerProvider.notifier)
          .setKaraoke(!ref.read(karaokeProvider).enabled),
    );
  }
}

/// Sotto l'intestazione, col karaoke acceso e la base pronta: quanta voce
/// resta.
class _SingBar extends ConsumerWidget {
  const _SingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(karaokeProvider);
    final accent = context.colors.accent;
    Widget child;
    if (!k.enabled) {
      child = const SizedBox.shrink();
    } else if (k.preparing != null) {
      // Mentre si prepara, a dirlo e' il microfono che si riempie.
      child = const SizedBox.shrink();
    } else {
      child = Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(
          children: [
            Icon(Icons.mic_off_rounded, size: 16, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SpotSlider(
                  seed: 'voice',
                  height: 36,
                  value: k.voice,
                  label: (v) => '${(v * 100).round()}%',
                  semanticLabel: 'Voice',
                  onChanged: ref.read(playerProvider.notifier).setKaraokeVoice,
                ),
              ),
            ),
            Icon(
              Icons.mic_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      );
    }
    return AnimatedSize(
      duration: AppMotion.base,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// Sfuma testo e coda verso i bordi invece di tagliarli di netto, come fa
/// Apple: si capisce che il pannello continua sopra e sotto.
class _EdgeFade extends StatelessWidget {
  final Widget child;

  const _EdgeFade({required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, 0.06, 0.9, 1],
      ).createShader(rect),
      child: child,
    );
  }
}

/// La fila in fondo al player: testo, equalizzatore, uscita audio, coda.
class _PaneBar extends StatelessWidget {
  final _Pane pane;
  final VoidCallback onLyrics;
  final VoidCallback onEq;
  final VoidCallback onQueue;
  final VoidCallback onVideo;

  const _PaneBar({
    required this.pane,
    required this.onLyrics,
    required this.onEq,
    required this.onQueue,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    // Macchia: ogni comando e' una macchiolina scura viva con l'icona nel
    // colore del brano; il pannello aperto si riempie del colore del brano.
    // Il nome compare col mouse sopra.
    // Su una riga sola, sempre: in una finestra stretta la fila si
    // rimpicciolisce invece di andare a capo e spingere giu' il player.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerKey(
              icon: Icons.lyrics_rounded,
              label: 'Lyrics',
              active: pane == _Pane.lyrics,
              onTap: onLyrics,
            ),
            PlayerKey(
              icon: Icons.tune_rounded,
              label: 'Equalizer',
              onTap: onEq,
            ),
            PlayerKey(
              icon: Icons.smart_display_rounded,
              label: 'Watch video',
              onTap: onVideo,
            ),
            if (AirPlayButton.isSupported) const PlayerKey.airplay(),
            if (MiniPlayerWindow.isSupported)
              const PlayerKey(
                icon: Icons.picture_in_picture_alt_rounded,
                label: 'Mini',
                tooltip: 'Mini Player (⌥⌘M)',
                onTap: MiniPlayerWindow.toggle,
              ),
            PlayerKey(
              icon: Icons.queue_music_rounded,
              label: 'Queue',
              active: pane == _Pane.queue,
              onTap: onQueue,
            ),
          ],
        ),
      ),
    );
  }
}

/// Un interruttore del player: un'icona nuda. Acceso, dietro compare un
/// tondo tenue nel colore del brano e l'icona prende quel colore; col
/// mouse sopra, un alone appena accennato dice che si puo' premere.
class _Toggle extends StatefulWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  /// Mentre prepara qualcosa (la base del karaoke): il tondo si riempie
  /// del colore del brano, da sinistra, invece di una barra a parte.
  final double? progress;

  const _Toggle({
    required this.icon,
    this.activeIcon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.progress,
  });

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    final active = widget.active;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        selected: active,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: widget.onTap,
            child: SpotMotionBuilder(
              builder: (context, _) => ProgressFill(
                progress: widget.progress,
                shape: const CircleBorder(),
                child: AnimatedScale(
                  scale: _down ? 0.88 : 1,
                  duration: AppMotion.fast,
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 40,
                    height: 40,
                    // Attivo: una macchia viva del colore del brano, come il
                    // segno della sezione nella navigazione. Mentre si
                    // prepara il fondo pieno lo disegna ProgressFill.
                    decoration: ShapeDecoration(
                      shape: SpotBorder(
                        seed: 'toggle-${widget.icon.codePoint}',
                        wobble: 0.8,
                        time: SpotMotion.of(context)?.value,
                        music: SpotMotion.musicOf(context),
                      ),
                      color: widget.progress != null
                          ? Colors.white.withValues(alpha: 0.06)
                          : active
                          ? accent.withValues(alpha: _hover ? 0.32 : 0.24)
                          : Colors.white.withValues(alpha: _hover ? 0.08 : 0),
                    ),
                    child: Icon(
                      active ? (widget.activeIcon ?? widget.icon) : widget.icon,
                      size: 22,
                      color: active
                          ? accent
                          : Colors.white.withValues(alpha: _hover ? 0.95 : 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestedSection extends ConsumerWidget {
  final String videoId;
  final String artist;

  const _SuggestedSection({required this.videoId, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(upNextProvider('$videoId|$artist'));

    return suggestions.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (tracks) {
        if (tracks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Suggested songs'),
            for (final t in tracks.take(6))
              TrackTile(
                track: t,
                onTap: () => ref.read(playerProvider.notifier).playTrack(t),
              ),
          ],
        );
      },
    );
  }
}

/// Le voci del menu "…".
enum _More { shuffle, repeat, automix, radio, sleep }

/// Il pulsante "…" accanto al cuore: apre il menu degli interruttori.
///
/// Spento e' un tondo tenue con i tre puntini, come in Apple Music. Con
/// qualcosa acceso si allunga in una capsula che mostra, piccole e nel
/// colore del brano, le icone di cio' che e' attivo: shuffle o ripeti
/// accesi cambiano cosa suonera' dopo, e nasconderli del tutto in un menu
/// li renderebbe una sorpresa. Cosi' si vedono senza che servano cinque
/// pulsanti.
class _MoreButton extends ConsumerStatefulWidget {
  const _MoreButton();

  @override
  ConsumerState<_MoreButton> createState() => _MoreButtonState();
}

class _MoreButtonState extends ConsumerState<_MoreButton> {
  bool _hover = false;
  bool _down = false;

  /// Quanto e' largo il menu, a occhio: serve ad allinearne il bordo
  /// destro al pulsante invece di farlo uscire verso destra. Se sbaglia,
  /// il menu lo riporta comunque dentro lo schermo.
  static const double _menuWidth = 250;

  @override
  Widget build(BuildContext context) {
    final (shuffle, repeat, automix) = ref.watch(
      playerProvider.select((s) => (s.shuffle, s.repeat, s.automix)),
    );
    final radio = ref.watch(radioProvider);
    final sleep = ref.watch(sleepTimerProvider) != null;
    final accent = context.colors.accent;
    final on = <(IconData, String)>[
      if (shuffle) (Icons.shuffle_rounded, 'shuffle'),
      if (automix) (Icons.multitrack_audio_rounded, 'AutoMix'),
      if (radio) (Icons.all_inclusive_rounded, 'endless queue'),
      if (repeat != RepeatMode.off) (_repeatIcon(repeat), 'repeat'),
      if (sleep) (Icons.bedtime_rounded, 'sleep timer'),
    ];
    return Tooltip(
      message: 'More',
      child: Semantics(
        button: true,
        label: on.isEmpty
            ? 'More'
            : 'More, on: ${on.map((e) => e.$2).join(', ')}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: _open,
            // Un margine attorno: il tondo e' piccolo, ma si prende senza
            // mirare, come gli altri pulsanti da 40.
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: AnimatedScale(
                scale: _down ? 0.9 : 1,
                duration: AppMotion.fast,
                child: AnimatedSize(
                  duration: AppMotion.base,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerRight,
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    height: 32,
                    padding: EdgeInsets.only(left: on.isEmpty ? 0 : 10),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      // Macchia: il gruppo non ha un fondo suo, sta sul
                      // nero come le altre icone del player; col mouse
                      // sopra un velo leggero dice che si puo' premere.
                      color: Colors.white.withValues(alpha: _hover ? 0.1 : 0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (icon, _) in on) ...[
                          Icon(icon, size: 15, color: accent),
                          const SizedBox(width: 5),
                        ],
                        SizedBox(
                          width: 32,
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 22,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final player = ref.read(playerProvider);
    final radio = ref.read(radioProvider);
    final timer = ref.read(sleepTimerProvider);
    final left = timer?.minutesLeft(DateTime.now());
    // Sotto il pulsante, col bordo destro allineato al suo.
    final corner = box.localToGlobal(Offset(box.size.width, box.size.height));
    // Ogni voce dice com'e' adesso, con le stesse parole che i
    // pulsanti avevano nel suggerimento: toccarla cambia lo stato.
    final picked = await showGlassMenu<_More>(
      context: context,
      globalPosition: Offset(corner.dx - _menuWidth, corner.dy),
      items: [
        GlassMenuItem(
          value: _More.shuffle,
          icon: Icons.shuffle_rounded,
          label: player.shuffle ? 'Shuffle: on' : 'Shuffle: off',
        ),
        GlassMenuItem(
          value: _More.repeat,
          icon: _repeatIcon(player.repeat),
          label: switch (player.repeat) {
            RepeatMode.off => 'Repeat: off',
            RepeatMode.all => 'Repeat: whole queue',
            RepeatMode.one => 'Repeat: this song',
          },
        ),
        GlassMenuItem(
          value: _More.automix,
          icon: Icons.multitrack_audio_rounded,
          label: player.automix ? 'AutoMix: on' : 'AutoMix: off',
        ),
        GlassMenuItem(
          value: _More.radio,
          icon: Icons.all_inclusive_rounded,
          label: radio ? 'Endless queue: on' : 'Endless queue: off',
        ),
        GlassMenuItem(
          value: _More.sleep,
          icon: timer == null ? Icons.bedtime_outlined : Icons.bedtime_rounded,
          label: timer == null
              ? 'Sleep timer…'
              : timer.endOfTrack
              ? 'Sleep timer: end of song'
              : 'Sleep timer: $left min',
        ),
      ],
    );
    if (!mounted || picked == null) return;
    final notifier = ref.read(playerProvider.notifier);
    switch (picked) {
      case _More.shuffle:
        notifier.toggleShuffle();
      case _More.repeat:
        notifier.toggleRepeat();
      case _More.automix:
        notifier.toggleAutomix();
      case _More.radio:
        ref.read(radioProvider.notifier).toggle();
      case _More.sleep:
        await _showSleepSheet(context, ref);
    }
  }
}

/// Il volume, sotto il play: la stessa barra dell'avanzamento, senza la
/// testa finche' non la si tocca e spenta a riposo, perche' non rubi la
/// scena ai comandi. Col mouse sopra si ingrossa e si accende.
///
/// Osserva solo il volume: il player sopra non si ricostruisce a ogni
/// passo del trascinamento.
class _VolumeBar extends ConsumerStatefulWidget {
  const _VolumeBar();

  @override
  ConsumerState<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends ConsumerState<_VolumeBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(playerProvider.select((s) => s.volume));
    final value = (_dragging ?? volume).clamp(0.0, 100.0);
    final quiet = Colors.white.withValues(alpha: 0.6);
    final notifier = ref.read(playerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Icon(
            value == 0 ? Icons.volume_mute_rounded : Icons.volume_down_rounded,
            size: 18,
            color: quiet,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SpotSlider(
                seed: 'volume',
                value: value,
                max: 100,
                headAtRest: false,
                // Spento a riposo, nel colore del brano solo mentre lo
                // si tocca: a volume pieno era una seconda barra colorata
                // lunga quanto l'avanzamento, e le due si contendevano lo
                // sguardo. Quella che conta e' il brano.
                idleColor: context.colors.accentMuted,
                label: (v) => '${v.round()}%',
                semanticLabel: 'Volume',
                // Il volume cambia mentre si trascina, a differenza
                // dell'avanzamento: si regola a orecchio.
                onChanged: (v) {
                  setState(() => _dragging = v);
                  notifier.setVolume(v);
                },
                onChangeEnd: (v) {
                  notifier.setVolume(v);
                  setState(() => _dragging = null);
                },
              ),
            ),
          ),
          Icon(Icons.volume_up_rounded, size: 18, color: quiet),
        ],
      ),
    );
  }
}

Future<void> _showSleepSheet(BuildContext context, WidgetRef ref) async {
  final timer = ref.read(sleepTimerProvider);
  final left = timer?.minutesLeft(DateTime.now());
  const options = [5, 15, 30, 45, 60];

  // Macchia: i tempi sono parole grandi da toccare, in fila, non righe di
  // una lista con un cronometro ripetuto davanti a ognuna. Quello scelto
  // ha il colore del brano e la sua macchiolina.
  await showGlassSheet<void>(
    context: context,
    builder: (sheet) {
      void close() => Navigator.of(sheet).pop();
      final notifier = ref.read(sleepTimerProvider.notifier);
      final colors = sheet.colors;

      Widget choice(String label, bool active, VoidCallback onTap) =>
          _SleepChoice(label: label, active: active, onTap: onTap);

      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sleep timer', style: sheet.texts.headlineMedium),
            const SizedBox(height: 2),
            Text(
              timer == null
                  ? 'The music stops on its own, fading out.'
                  : timer.endOfTrack
                  ? 'Stops at the end of this song.'
                  : 'Stops in $left min.',
              style: sheet.texts.titleMedium?.copyWith(
                color: colors.accentMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                for (final m in options)
                  choice(
                    m == 60 ? '1 h' : '$m min',
                    timer != null &&
                        !timer.endOfTrack &&
                        left != null &&
                        left <= m &&
                        left >
                            (options.indexOf(m) == 0
                                ? 0
                                : options[options.indexOf(m) - 1]),
                    () {
                      notifier.setMinutes(m);
                      close();
                    },
                  ),
                choice('End of song', timer?.endOfTrack == true, () {
                  notifier.setEndOfTrack();
                  close();
                }),
              ],
            ),
            if (timer != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () {
                  notifier.cancel();
                  close();
                },
                style: TextButton.styleFrom(
                  foregroundColor: colors.danger,
                  textStyle: sheet.texts.titleMedium,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.close_rounded, size: 20),
                label: const Text('Turn off timer'),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Una durata del timer, come parola grande.
class _SleepChoice extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SleepChoice({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SleepChoice> createState() => _SleepChoiceState();
}

class _SleepChoiceState extends State<_SleepChoice> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lit = widget.active || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.active) ...[
                SizedBox.square(
                  dimension: 11,
                  child: LiveSpotDot(color: colors.accent),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: context.texts.headlineMedium?.copyWith(
                  fontSize: 32,
                  color: lit ? colors.accent : colors.textStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
