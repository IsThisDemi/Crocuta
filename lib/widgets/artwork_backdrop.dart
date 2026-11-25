import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../design/accent.dart';
import '../design/tokens.dart';
import '../services/dominant_color.dart';
import 'accent_glow.dart';

/// Lo sfondo di una pagina che prende il colore da una copertina.
///
/// Era la copertina sfocata a tutto schermo, alla Apple Music; in Macchia e'
/// il nero con la luce della copertina ([AccentGlow]). Il nome e i
/// parametri restano perche' lo usano piu' pagine.
///
/// [baseColor] e' il colore dominante della copertina e riempie le zone che
/// l'immagine non copre; il gradiente scuro sotto serve alla leggibilita' del
/// testo, e l'insieme sfuma quando cambia brano (la chiave e' [trackId]).
///
/// Sta in un file suo perche' lo usano due schermate: il player e i testi.
/// Erano due pagine dello stesso brano e una sola aveva lo sfondo.
class ArtworkBackdrop extends StatelessWidget {
  final String artUrl;
  final Color baseColor;
  final String trackId;

  /// L'analisi della copertina: luminosita' media e colore medio. Nulla
  /// finche' non e' pronta, e allora niente velo in piu'.
  final ArtworkPalette? palette;

  /// La versione viva, solo per il player: i colori della copertina
  /// saturi e in lento movimento, invece della copertina sfocata quasi
  /// nera. Le altre pagine (album, equalizzatore, Connect, testi) restano
  /// sullo sfondo quieto: li' il contenuto e' una lista da leggere, e uno
  /// sfondo che si muove la disturberebbe.
  final bool vivid;

  /// Solo per [vivid]: se lo sfondo si muove. In pausa si ferma dov'e',
  /// come la copertina che si ritira: anche lo sfondo dice che la musica
  /// e' ferma, e non si spende un fotogramma per niente.
  final bool animate;

  const ArtworkBackdrop({
    super.key,
    required this.artUrl,
    required this.baseColor,
    required this.trackId,
    this.palette,
    this.vivid = false,
    this.animate = true,
  });

  /// Il contrasto minimo del grigio dei metadati (`AppColors.text2`) sullo
  /// sfondo. Un filo sopra i 4,5:1 del testo piccolo: lo sfocato non e'
  /// uniforme, e dove e' piu' chiaro della media il margine lo tiene sopra.
  static const double targetContrast = 4.8;

  /// Quanto nero c'e' gia', all'altezza dei metadati, dal gradiente qui
  /// sotto (0 in cima, 22% a meta').
  static const double _gradientAtText = 0.18;

  /// Il colore dello sfondo dove sta il testo, stimato.
  ///
  /// La fascia piu' chiara della copertina, scurita dal gradiente che a
  /// quell'altezza vale circa il 18%. Il velo del colore dominante (55%) qui
  /// non entra, di proposito: misurato sullo screenshot della pagina vera,
  /// lo sfondo sotto il titolo era a luminanza 0,14-0,21, e una stima che
  /// comprende il dominante scuro dava 0,044 — tre, cinque volte meno. Senza,
  /// la stima da' 0,16, dentro quell'intervallo. E' anche la stima prudente:
  /// se sbaglia, sbaglia verso un velo un po' piu' forte, mai verso testo
  /// illeggibile.
  ///
  /// I conti sono in sRGB, ed e' verificato: nell'app vera, sul Mac, un
  /// bianco con sopra il 50% di nero viene #7f7f7f. In luce lineare
  /// sarebbe venuto #bcbcbc.
  static Color predictedBackground(Color lightest) =>
      Color.lerp(lightest, Colors.black, _gradientAtText)!;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Il velo nero minimo perche' i metadati restino leggibili.
  ///
  /// Nero e non un'altra tinta: calcolato giusto, un velo nero al 45-55%
  /// lascia la pagina del suo colore, solo piu' profonda — lavanda resta
  /// lavanda. E' stato il conto sbagliato, non il nero, a spegnerla. E una
  /// copertina gia' scura da' zero: la pagina resta com'era.
  static double scrimFor(Color lightest) {
    final bg = predictedBackground(lightest);
    if (_contrast(AppColors.text2, bg) >= targetContrast) return 0;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final veiled = Color.lerp(bg, Colors.black, mid)!;
      if (_contrast(AppColors.text2, veiled) >= targetContrast) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hi;
  }

  /// Quanto nero aggiunge, all'altezza dei metadati, il gradiente della
  /// versione viva. Mai meno di [_gradientAtText]: e' su quel valore che
  /// [scrimFor] fa i suoi conti, e se qui ce ne fosse meno il velo
  /// calcolato non basterebbe piu'.
  static const double vividGradientAtText = 0.26;

  /// La luminanza massima di un colore della trama.
  static const double _meshMaxLuminance = 0.07;

  /// Il velo uniforme della versione viva: quello che serve ai metadati,
  /// con un minimo. Senza minimo una copertina scura e satura (un blu
  /// elettrico) lasciava i grigi al limite; un 12% non si vede come
  /// "scuro", ma tiene il bianco nitido.
  static double vividScrimFor(Color? lightest) =>
      math.max(0.12, lightest == null ? 0 : scrimFor(lightest));

  /// I colori della trama viva, dal colore dominante e dall'analisi.
  ///
  /// La tinta e la saturazione vengono dalla copertina, la luce no: e'
  /// quella che decide se il testo si legge. Ogni colore ha una
  /// luminosita' HSL indicativa, ma il tetto vero e' la luminanza
  /// ([_meshMaxLuminance]): a pari luminosita' HSL un verde o un ciano
  /// saturi sono due volte piu' chiari di un blu, e un tetto solo in HSL
  /// lasciava i grigi dei metadati sotto 4,5:1 (lo verifica
  /// backdrop_scrim_test). Una copertina grigia resta grigia: forzarle la
  /// saturazione la tingeva del rosso di tinta zero.
  static List<Color> vividColors(Color base, ArtworkPalette? palette) {
    final vivid = palette?.vivid ?? base;
    final light = palette?.lightest ?? vivid;
    Color tone(Color c, double lightness, [double shift = 0]) {
      final h = HSLColor.fromColor(c);
      final sat = h.saturation < 0.08
          ? h.saturation
          : (h.saturation * 1.4).clamp(0.5, 0.9);
      final hue = h.withHue((h.hue + shift) % 360).withSaturation(sat);
      var l = lightness;
      // Si scurisce finche' la luminanza non rientra: la tinta resta.
      while (l > 0.05 &&
          hue.withLightness(l).toColor().computeLuminance() >
              _meshMaxLuminance) {
        l -= 0.01;
      }
      return hue.withLightness(l).toColor();
    }

    return [
      tone(base, 0.16),
      tone(vivid, 0.30),
      tone(base, 0.26, -25),
      tone(vivid, 0.24, 30),
      tone(light, 0.28, 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // In Macchia lo sfondo di una pagina con un colore suo e' il nero con
    // la luce della copertina: la stessa del player. Gli helper sopra
    // (velo, sfondo previsto) restano per chi li usa da fuori.
    return AccentGlow(
      color: toneMapAccent(palette?.vivid ?? baseColor),
      second: palette?.swatches.skip(1).firstOrNull,
    );
  }
}
