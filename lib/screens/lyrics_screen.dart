import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/accent.dart';
import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/lyrics.dart';
import '../providers.dart';
import '../services/artwork.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/content_width.dart';
import '../widgets/artwork_backdrop.dart';

class LyricsScreen extends ConsumerWidget {
  final String title;
  final String artist;

  const LyricsScreen({super.key, required this.title, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerProvider.select((s) => s.current));
    final art = track?.thumbnailUrl ?? '';
    final backdrop = ref.watch(backdropColorProvider(art));
    return AccentScope(
      // Stessa tinta del player: sono due facciate dello stesso brano, e
      // una delle due era rimasta su fondo nero piatto.
      artworkUrl: art,
      child: GlassScaffold(
        background: ArtworkBackdrop(
          artUrl: hiResArtwork(art) ?? art,
          baseColor: backdrop.valueOrNull ?? Colors.black,
          palette: ref.watch(artworkPaletteProvider(art)).valueOrNull,
          trackId: track?.id ?? '',
        ),
        statusBarStyle: GlassStatusBarStyle.light,
        topEdgeFade: hasStatusBarFade,
        topEdgeFadeExtent: statusBarOnlyFade,
        appBar: const AppTopBar(title: 'Lyrics'),
        body: Material(
          type: MaterialType.transparency,
          child: LyricsView(title: title, artist: artist),
        ),
      ),
    );
  }
}

/// Il testo sincronizzato, senza pagina attorno: il verso in corso al
/// centro, gli altri sfumati, tocca un verso per saltarci.
///
/// Sta da solo perche' il brano in riproduzione lo mostra al posto della
/// copertina, come Apple Music, invece di aprire una pagina a parte.
class LyricsView extends ConsumerStatefulWidget {
  final String title;
  final String artist;

  /// Lo spazio sopra il primo verso. Di norma quello della barra di vetro;
  /// dentro il player la barra non c'e' e basta un filo.
  final double? topInset;

  /// Il corpo dei versi. 26 punti in una colonna da telefono; nel player
  /// a due colonne, su una finestra larga, il testo ha meta' finestra e
  /// lo si legge da piu' lontano: li' va piu' grande, come Apple Music sul
  /// Mac.
  final double fontSize;

  /// Quanto puo' essere larga la colonna dei versi.
  final double maxWidth;

  const LyricsView({
    super.key,
    required this.title,
    required this.artist,
    this.topInset,
    this.fontSize = 26,
    this.maxWidth = 620,
  });

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  /// Una chiave per verso, per poterlo centrare chiedendolo al framework
  /// invece di calcolarne la posizione a mano.
  final _keys = <int, GlobalKey>{};

  int _activeIndex = -1;
  List<LyricsLine> _lines = const [];

  /// Stai scorrendo tu il testo.
  ///
  /// Come in Apple: finche' scorri, i versi tornano tutti nitidi e il
  /// testo smette di inseguire il brano — altrimenti ti strapperebbe via
  /// dal verso che stai cercando. Tre secondi dopo che ti sei fermato,
  /// riprende a seguire.
  bool _browsing = false;
  Timer? _resume;

  @override
  void dispose() {
    _resume?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    final byUser =
        (n is ScrollStartNotification && n.dragDetails != null) ||
        (n is ScrollUpdateNotification && n.dragDetails != null);
    if (byUser) {
      _resume?.cancel();
      if (!_browsing) setState(() => _browsing = true);
    } else if (n is ScrollEndNotification && _browsing) {
      _resume?.cancel();
      _resume = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _browsing = false);
        _centre(_activeIndex);
      });
    }
    return false;
  }

  /// Il verso in corso: l'ultimo il cui istante e' gia' passato.
  int _indexAt(Duration position) {
    var current = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= position) current = i;
    }
    return current;
  }

  void _syncTo(Duration position) {
    final next = _indexAt(position);
    if (next == _activeIndex) return;
    setState(() => _activeIndex = next);
    // Dopo il fotogramma, non dentro: cambiando verso attivo cambiano corpo
    // e numero di righe, quindi calcolare subito lo scorrimento lo calcola
    // sulla geometria vecchia e il verso finisce fuori centro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_browsing) _centre(next);
    });
  }

  /// Porta il verso attivo al centro della parte leggibile.
  ///
  /// `ensureVisible` con alignment 0.5 lo mette al centro del viewport; il
  /// viewport pero' passa anche sotto la barra in alto, quindi senza
  /// scomputarla il verso finirebbe piu' in basso del centro che si vede.
  void _centre(int index) {
    final key = _keys[index];
    final ctx = key?.currentContext;
    // Nessun ScrollController: `ensureVisible` risale da sola allo
    // Scrollable che contiene il verso. Tenerne uno significava poterlo
    // lasciare scollegato — ed e' successo: la guardia `hasClients` era
    // sempre falsa e il testo smetteva di seguire il brano, in silenzio.
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      duration: AppMotion.base,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(
      lyricsProvider('${widget.title}|${widget.artist}'),
    );
    // Fuori da build: aggiornare l'indice mentre si costruisce significava
    // chiamare setState dentro build, cosa che Flutter vieta e che qui
    // reggeva solo per fortuna.
    ref.listen<Duration>(
      playerProvider.select((s) => s.position),
      (_, p) => _syncTo(p),
    );

    return lyrics.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const _Empty(message: 'Lyrics unavailable.'),
      data: (data) {
        if (data == null || data.lines.isEmpty) {
          return const _Empty(message: 'No lyrics for this song.');
        }
        if (!identical(_lines, data.lines)) {
          _lines = data.lines;
          _keys.clear();
          // Al primo caricamento il verso in corso puo' essere a meta'
          // brano: va portato al centro subito, non al verso dopo.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncTo(ref.read(playerProvider).position);
          });
        }
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: _LyricsList(
            lines: data.lines,
            activeIndex: _activeIndex,
            browsing: _browsing,
            keys: _keys,
            topInset: widget.topInset ?? topBarInset(context),
            fontSize: widget.fontSize,
            maxWidth: widget.maxWidth,
            onTapLine: (i) {
              // Toccare un verso e' anche smettere di cercare: si torna
              // a seguire subito, da li'.
              _resume?.cancel();
              setState(() => _browsing = false);
              ref.read(playerProvider.notifier).seek(data.lines[i].time);
            },
          ),
        );
      },
    );
  }
}

class _LyricsList extends StatelessWidget {
  final List<LyricsLine> lines;
  final int activeIndex;
  final bool browsing;
  final Map<int, GlobalKey> keys;
  final double topInset;
  final double fontSize;
  final double maxWidth;
  final void Function(int) onTapLine;

  const _LyricsList({
    required this.lines,
    required this.activeIndex,
    required this.browsing,
    required this.keys,
    required this.topInset,
    required this.fontSize,
    required this.maxWidth,
    required this.onTapLine,
  });

  @override
  Widget build(BuildContext context) {
    // Una Column dentro uno scroll, non una ListView ad altezza fissa: i
    // versi vanno a capo, e con `itemExtent` quelli lunghi venivano tagliati.
    // Un testo sta in un centinaio di righe, costruirle tutte non pesa — e
    // in cambio `ensureVisible` funziona anche su un verso lontano, che con
    // una lista pigra non sarebbe ancora stato costruito.
    // Piu' stretta delle liste, non piu' larga: una riga di testo lunga
    // due monitor e' illeggibile, e questa pagina e' solo testo.
    return ContentWidth(
      maxWidth: maxWidth,
      child: SingleChildScrollView(
        // In cima lo spazio della barra di vetro, che galleggia sul testo: con
        // meno, i primi versi restavano dietro. In fondo abbastanza perche'
        // anche l'ultimo verso possa arrivare al centro.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          topInset,
          AppSpacing.lg,
          AppSpacing.huge * 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              _Line(
                key: keys.putIfAbsent(i, GlobalKey.new),
                text: lines[i].text,
                active: i == activeIndex,
                fontSize: fontSize,
                // Quanto e' lontano dal verso in corso: piu' e' lontano,
                // piu' e' sfocato. Da fermi, non mentre scorri tu.
                distance: browsing || activeIndex < 0
                    ? 0
                    : (i - activeIndex).abs(),
                onTap: () => onTapLine(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String text;
  final bool active;
  final int distance;
  final double fontSize;
  final VoidCallback onTap;

  const _Line({
    super.key,
    required this.text,
    required this.active,
    required this.distance,
    required this.fontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Tutti i versi allo stesso corpo, come in Apple. Prima il verso in
    // corso passava da 17 a 26 punti: cambiava il numero di righe, tutto il
    // testo sotto si spostava, e la pagina scattava a ogni verso. Ora cambia
    // solo quanto si vede, non quanto spazio prende.
    final blur = distance == 0 ? 0.0 : (distance.clamp(1, 4) * 1.1);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: blur),
            duration: AppMotion.slow,
            curve: Curves.easeOut,
            builder: (context, sigma, child) => sigma < 0.05
                ? child!
                : ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: child,
                  ),
            child: AnimatedDefaultTextStyle(
              duration: AppMotion.base,
              curve: Curves.easeOut,
              style: TextStyle(
                fontFamily: AppTypography.display,
                fontSize: fontSize,
                height: 1.18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                // Il verso in corso nel colore del brano, gli altri spenti:
                // sul fondo nero di Macchia l'accento si legge, e lega il
                // testo alla copertina e al tasto play.
                color: active
                    ? context.colors.accent
                    : Colors.white.withValues(alpha: 0.30),
              ),
              child: Text(text),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;

  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodyLarge?.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
