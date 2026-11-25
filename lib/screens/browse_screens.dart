import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_theme.dart';
import '../design/chrome.dart';
import '../models/artist.dart';
import '../models/explore.dart';
import '../navigation.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sub_page.dart';
import '../widgets/spot_layouts.dart';
import '../design/spot.dart';

/// Una categoria: un grappolo di copertine a macchia, prese dalle sue
/// playlist, col nome sotto in grande.
///
/// YouTube Music per le categorie da' solo nome e colore, niente immagine:
/// le copertine sono quelle delle prime playlist della categoria, dalla
/// stessa richiesta che serve comunque ad aprirla, fatta prima. Il colore
/// di YouTube non riempie piu' la tessera — Macchia e' nera, e il colore
/// pieno lo ha solo l'accento — ma resta come bagliore dietro il grappolo:
/// abbastanza per distinguere a colpo d'occhio Chill da Workout.
class CategoryTile extends ConsumerWidget {
  final BrowseCategory category;

  const CategoryTile({super.key, required this.category});

  /// Il contrasto minimo del bianco dietro il nome: la soglia del testo
  /// grande e in grassetto.
  static const minContrast = 3.2;

  /// Quanto scurisce, in fondo a sinistra, il velo dietro il nome.
  ///
  /// E' il valore piu' debole che il velo ha dove sta il testo — al
  /// massimo e' piu' scuro — e su questo si misura il contrasto.
  static const scrimUnderTitle = 0.22;

  /// Il velo nero come lo vede il testo, da comporre sopra un colore.
  static const _scrim = Color.fromRGBO(0, 0, 0, scrimUnderTitle);

  /// Il colore della tessera visto dietro il nome, velo compreso.
  static Color underTitle(Color tone) => Color.alphaBlend(_scrim, tone);

  /// Il colore di YouTube reso vivace, come le tessere di Apple Music:
  /// (in alto a sinistra, in basso a destra).
  ///
  /// Prima si scuriva tutta la tessera finche' il bianco non arrivava a
  /// 3,2:1, e i gialli e gli arancioni ("Commute", "Energize") diventavano
  /// verde oliva e senape: un giallo saturo e' chiarissimo, e scurito resta
  /// giallo spento, non diventa un giallo scuro. Adesso:
  ///
  /// - i gialli girano verso l'arancione, che scurito resta caldo e acceso;
  /// - la saturazione si alza, perche' i colori di YouTube sono spesso
  ///   pastello, e un pastello scurito va verso il grigio;
  /// - la luce si ferma a meta', e si abbassa solo quanto serve al testo,
  ///   misurando il contrasto vero e non la "luce" HSL;
  /// - il nome ha dietro un velo scuro leggero in basso a sinistra, che
  ///   porta il contrasto dove serve senza spegnere tutta la tessera;
  /// - il fondo della sfumatura e' la stessa tinta piu' profonda, appena
  ///   girata verso il rosso, non la stessa tinta verso il grigio.
  ///
  /// I grigi restano grigi: alzarne la saturazione inventerebbe un colore.
  static (Color, Color) tones(int color) {
    var hsl = HSLColor.fromColor(Color(color));
    final grey = hsl.saturation < 0.12;
    if (!grey) {
      hsl = hsl
          .withHue(_awayFromYellow(hsl.hue))
          .withSaturation(hsl.saturation.clamp(0.62, 0.88));
    }
    hsl = hsl.withLightness(hsl.lightness.clamp(0.0, 0.56));
    while (hsl.lightness > 0.05 &&
        _contrastOnWhite(underTitle(hsl.toColor())) < minContrast) {
      hsl = hsl.withLightness(hsl.lightness - 0.01);
    }
    // Le tinte calde scendono verso il rosso, come una brace; le altre
    // restano dove sono, piu' profonde: un blu che gira verso il ciano o
    // un verde verso il giallo si schiarirebbero invece di scendere.
    final warm = !grey && hsl.hue < 45;
    final bottom = hsl
        .withHue(warm ? (hsl.hue - 8).clamp(0.0, 360.0) : hsl.hue)
        .withSaturation(grey ? hsl.saturation : 0.92)
        .withLightness((hsl.lightness - 0.14).clamp(0.05, 1.0));
    return (hsl.toColor(), bottom.toColor());
  }

  /// I gialli (fra 38 e 62 gradi) verso l'arancione, fra 26 e 38; i
  /// verde lime (fra 62 e 125) verso il verde pieno, fra 100 e 125.
  ///
  /// Il giallo e' l'unica tinta che non sopporta di essere scurita: a
  /// meta' luce e' gia' senape, e il lime e' gia' oliva. L'arancione e il
  /// verde accanto invece reggono, e nella griglia si leggono ancora come
  /// "il caldo" e "il fresco" che YouTube voleva dire.
  static double _awayFromYellow(double hue) {
    if (hue >= 38 && hue < 62) return 26 + (hue - 38) * 12 / 24;
    if (hue >= 62 && hue < 125) return 100 + (hue - 62) * 25 / 63;
    return hue;
  }

  static double _contrastOnWhite(Color c) =>
      1.05 / (c.computeLuminance() + 0.05);

  /// Quante copertine nel grappolo.
  static const covers = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (tone, _) = tones(category.color);
    final shelves = ref.watch(categoryProvider(category.params)).valueOrNull;
    final urls = <String>[
      for (final (_, cards) in shelves ?? const <(String, List<AlbumCard>)>[])
        for (final c in cards)
          if (c.thumbnailUrl.isNotEmpty) c.thumbnailUrl,
    ].take(covers).toList();

    return _CategoryCluster(
      title: category.title,
      tone: tone,
      urls: urls,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CategoryScreen(category: category)),
      ),
    );
  }
}

class _CategoryCluster extends StatefulWidget {
  final String title;
  final Color tone;
  final List<String> urls;
  final VoidCallback onTap;

  const _CategoryCluster({
    required this.title,
    required this.tone,
    required this.urls,
    required this.onTap,
  });

  @override
  State<_CategoryCluster> createState() => _CategoryClusterState();
}

class _CategoryClusterState extends State<_CategoryCluster> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    // Il tono di YouTube e' scurito per reggere il bianco sopra: per il
    // bagliore e per il nome sotto il mouse lo si riaccende un poco.
    final lit = Color.lerp(tone, Colors.white, 0.3)!;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = CategoryGrid.clusterFor(box.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: box.maxWidth,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Il bagliore: il colore della categoria che trapela
                      // da dietro le copertine e sfuma nel nero.
                      Positioned(
                        left: -size * 0.3,
                        top: -size * 0.3,
                        width: size * 1.6,
                        height: size * 1.6,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _hover ? 1 : 0.75,
                            duration: AppMotion.fast,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    lit.withValues(alpha: 0.55),
                                    lit.withValues(alpha: 0.16),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 0.45, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        width: size,
                        height: size,
                        child: AnimatedScale(
                          scale: _hover ? 1.06 : 1,
                          alignment: Alignment.bottomLeft,
                          duration: AppMotion.fast,
                          curve: Curves.easeOutCubic,
                          child: widget.urls.isEmpty
                              ? _Placeholder(seed: widget.title, color: tone)
                              : SpotCluster(urls: widget.urls, size: size),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CategoryGrid.titleGap),
                AnimatedSlide(
                  offset: Offset(_hover ? 0.03 : 0, 0),
                  duration: AppMotion.fast,
                  curve: Curves.easeOutCubic,
                  child: AnimatedDefaultTextStyle(
                    duration: AppMotion.fast,
                    style: context.texts.headlineSmall!.copyWith(
                      fontSize: CategoryGrid.titleSize,
                      height: 1.1,
                      color: _hover ? lit : context.colors.textStrong,
                    ),
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Finche' le copertine non arrivano: una macchia del colore della
/// categoria, smorzata, dove andra' quella grande del grappolo.
class _Placeholder extends StatelessWidget {
  final String seed;
  final Color color;

  const _Placeholder({required this.seed, required this.color});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.74,
      heightFactor: 0.74,
      alignment: Alignment.bottomLeft,
      child: SpotMotionBuilder(
        builder: (context, t) => DecoratedBox(
          decoration: ShapeDecoration(
            color: color.withValues(alpha: 0.5),
            shape: SpotBorder(seed: seed, wobble: 0.8, time: t),
          ),
        ),
      ),
    );
  }
}

/// Una griglia di tessere che si adatta alla larghezza.
///
/// Non scorre da sola: sta dentro le liste della pagina, che scorrono loro.
class CategoryGrid extends StatelessWidget {
  final List<BrowseCategory> items;

  /// Se dato, la griglia mostra solo righe piene: tante colonne quante ne
  /// entrano, per questo numero di righe, e le categorie che avanzano
  /// restano nella pagina di tutte le categorie.
  ///
  /// Nella pagina della ricerca otto tessere fisse su cinque colonne
  /// lasciavano una seconda riga con due buchi: il numero giusto dipende
  /// dalla larghezza, quindi lo sceglie la griglia e non chi la usa.
  final int? rows;

  const CategoryGrid({super.key, required this.items, this.rows});

  /// Quante colonne entrano in una larghezza: tessere da circa 200 pixel,
  /// mai meno di due — sul telefono — e mai piu' di sei.
  static int columnsFor(double width) => (width / 200).floor().clamp(2, 6);

  /// Il lato del grappolo in una tessera larga [tile].
  static double clusterFor(double tile) => (tile * 0.62).clamp(84.0, 132.0);

  static const titleGap = 10.0;
  static const titleSize = 22.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = columnsFor(box.maxWidth);
          const gap = AppSpacing.md;
          final tile = (box.maxWidth - gap * (columns - 1)) / columns;
          var shown = items;
          if (rows case final rows?) {
            final fit = items.length.clamp(0, columns * rows);
            // Solo righe intere; se non ne basta neanche una, si mostra
            // quello che c'e' piuttosto che niente.
            shown = items
                .take(fit < columns ? fit : fit - fit % columns)
                .toList();
          }
          return GridView.builder(
            shrinkWrap: true,
            // Il bagliore dietro i grappoli esce dalle tessere: tagliato al
            // bordo della griglia si vedrebbe uno spigolo dritto.
            clipBehavior: Clip.none,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: gap,
              mainAxisSpacing: AppSpacing.lg,
              // Grappolo, spazio, nome: niente di piu', il resto e' nero.
              mainAxisExtent: clusterFor(tile) + titleGap + titleSize * 1.1 + 4,
            ),
            itemCount: shown.length,
            itemBuilder: (_, i) => CategoryTile(category: shown[i]),
          );
        },
      ),
    );
  }
}

/// Tutte le categorie, a gruppi.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(categoriesProvider);
    return SubPage(
      title: 'Browse Categories',
      child: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load the categories',
        ),
        data: (groups) => ListView(
          padding: EdgeInsets.only(bottom: listBottomPadding(context, ref)),
          children: [
            for (final g in groups) ...[
              SectionHeader(title: g.title),
              CategoryGrid(items: g.items),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una categoria aperta: le sue playlist, a file.
class CategoryScreen extends ConsumerWidget {
  final BrowseCategory category;

  const CategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelves = ref.watch(categoryProvider(category.params));
    return SubPage(
      title: category.title,
      child: shelves.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load this category',
        ),
        data: (shelves) => shelves.isEmpty
            ? const EmptyState(
                icon: Icons.queue_music_rounded,
                title: 'Nothing here',
              )
            : ListView(
                padding: EdgeInsets.only(
                  bottom: listBottomPadding(context, ref),
                ),
                children: [
                  for (final (title, cards) in shelves) ...[
                    SectionHeader(title: title),
                    MediaCardRail(
                      itemCount: cards.length,
                      itemBuilder: (_, i) => MediaCard(
                        imageUrl: cards[i].thumbnailUrl,
                        title: cards[i].title,
                        subtitle: cards[i].subtitle,
                        onTap: () => openPlaylist(
                          context,
                          cards[i].browseId,
                          cards[i].title,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
