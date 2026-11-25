import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/design/tokens.dart';
import 'package:yeen_music/widgets/artwork_backdrop.dart';

/// Il contrasto WCAG fra due colori.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Lo sfondo sotto i metadati dopo il velo, mescolato in sRGB come fa
/// l'app vera.
Color veiled(Color lightest) => Color.lerp(
  ArtworkBackdrop.predictedBackground(lightest),
  Colors.black,
  ArtworkBackdrop.scrimFor(lightest),
)!;

void main() {
  test('una copertina scura resta com era', () {
    expect(ArtworkBackdrop.scrimFor(const Color(0xFF1A1A2E)), 0);
  });

  test('su una copertina chiara i metadati tornano leggibili', () {
    // La fascia piu' chiara di "early life crisis", letta dalla copertina.
    const lightest = Color(0xFF8C8C7D);
    final before = ArtworkBackdrop.predictedBackground(lightest);
    expect(contrast(AppColors.text2, before), lessThan(2.5));
    expect(
      contrast(AppColors.text2, veiled(lightest)),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('anche su una copertina quasi bianca', () {
    expect(
      contrast(AppColors.text2, veiled(const Color(0xFFF4F4F4))),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('il velo e quello che serve, non di piu', () {
    // Il tentativo rifiutato spegneva la pagina quasi al nero. Su quella
    // copertina il velo giusto sta attorno a meta': abbastanza per leggere,
    // poco abbastanza da lasciare il colore.
    final a = ArtworkBackdrop.scrimFor(const Color(0xFF8C8C7D));
    expect(a, inInclusiveRange(0.4, 0.6));
  });

  test('la tinta della pagina resta la sua', () {
    const lilac = Color(0xFFB4A0D2);
    final src = HSVColor.fromColor(ArtworkBackdrop.predictedBackground(lilac));
    final out = HSVColor.fromColor(veiled(lilac));
    expect((out.hue - src.hue).abs(), lessThan(3));
    expect(out.saturation, closeTo(src.saturation, 0.03));
  });

  test('il velo cresce con la luminosita, senza salti', () {
    var last = -1.0;
    for (var v = 0; v <= 255; v += 5) {
      final a = ArtworkBackdrop.scrimFor(Color.fromARGB(255, v, v, v));
      expect(a, greaterThanOrEqualTo(last));
      last = a;
    }
  });

  // Lo sfondo vivo del player: piu' colore, ma i metadati devono restare
  // leggibili quanto sullo sfondo quieto.
  group('sfondo vivo', () {
    test('il velo non e mai meno di quello quieto', () {
      for (var v = 0; v <= 255; v += 15) {
        final c = Color.fromARGB(255, v, v, v);
        expect(
          ArtworkBackdrop.vividScrimFor(c),
          greaterThanOrEqualTo(ArtworkBackdrop.scrimFor(c)),
        );
      }
      // E il gradiente all'altezza del testo non e' piu' leggero di
      // quello su cui scrimFor fa i conti (18%).
      expect(ArtworkBackdrop.vividGradientAtText, greaterThanOrEqualTo(0.18));
    });

    test('i colori della trama reggono i metadati', () {
      for (final base in const [
        Color(0xFF1E4D6B),
        Color(0xFFE8D020), // giallo: il caso piu' chiaro a parita' di HSL
        Color(0xFFFF2D55),
        Color(0xFF30D158),
      ]) {
        for (final c in ArtworkBackdrop.vividColors(base, null)) {
          // Sotto il testo la trama ha sopra il velo minimo e il
          // gradiente, mescolati in sRGB come fa l'app.
          final under = Color.lerp(
            Color.lerp(c, Colors.black, ArtworkBackdrop.vividScrimFor(null))!,
            Colors.black,
            ArtworkBackdrop.vividGradientAtText,
          )!;
          expect(
            contrast(AppColors.text2, under),
            greaterThanOrEqualTo(4.5),
            reason: '$c da $base',
          );
        }
      }
    });

    test('una copertina grigia non si tinge', () {
      for (final c in ArtworkBackdrop.vividColors(
        const Color(0xFF6E6E6E),
        null,
      )) {
        expect(HSLColor.fromColor(c).saturation, lessThan(0.08));
      }
    });
  });
}
