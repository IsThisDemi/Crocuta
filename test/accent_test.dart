import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/accent.dart';
import 'package:crocuta/design/app_theme.dart';

// I colori hanno canali a 8 bit, quindi il giro Color -> HSL -> Color -> HSL
// non restituisce mai il valore esatto del clamp: 0.72 torna come 0.7216.
// Si verifica il limite con la tolleranza di un gradino di quantizzazione.
const _eps = 1 / 255;

void main() {
  test('senza copertina resta il viola di marca', () {
    expect(toneMapAccent(null), AppColors.irisBright);
  });

  test('una tinta scura e satura viene schiarita fino a leggersi', () {
    // Tipico output di dominantColorOf: scuro e saturo, inservibile
    // in primo piano su uno sfondo quasi nero.
    const darkTeal = Color(0xFF0A3D3A);
    final mapped = HSLColor.fromColor(toneMapAccent(darkTeal));

    expect(mapped.lightness, greaterThanOrEqualTo(0.55 - _eps));
    expect(mapped.lightness, lessThanOrEqualTo(0.72 + _eps));
    // La tinta non deve cambiare: è ancora il colore della copertina.
    expect(mapped.hue, closeTo(HSLColor.fromColor(darkTeal).hue, 1.0));
  });

  test('una copertina beige resta smorzata ma leggibile', () {
    // Saturazione 0.24: poca, ma una tinta c'è. Va tenuta, non sostituita.
    const beige = Color(0xFFD8CFC0);
    final mapped = HSLColor.fromColor(toneMapAccent(beige));
    expect(mapped.lightness, lessThanOrEqualTo(0.72 + _eps));
    expect(toneMapAccent(beige), isNot(AppColors.irisBright));
  });

  test('la saturazione viene contenuta nella banda utile', () {
    const neon = Color(0xFF00FF66);
    final mapped = HSLColor.fromColor(toneMapAccent(neon));
    expect(mapped.saturation, lessThanOrEqualTo(0.85 + _eps));
    expect(mapped.saturation, greaterThanOrEqualTo(0.35 - _eps));
  });

  test('una copertina in scala di grigi non si inventa una tinta', () {
    // Senza il controllo sulla saturazione d'origine, il clamp a 0.35
    // trasformava un grigio neutro in un rosa polveroso. Il risultato non
    // deve avere tinta: si verifica la saturazione, non un colore preciso.
    for (final grey in [
      const Color(0xFF4A4A4A),
      const Color(0xFF000000),
      const Color(0xFFFFFFFF),
      const Color(0xFF808080),
    ]) {
      final out = HSLColor.fromColor(toneMapAccent(grey));
      expect(
        out.saturation,
        lessThan(0.15),
        reason:
            'il grigio ${grey.toARGB32().toRadixString(16)} ha prodotto una tinta',
      );
    }
  });

  test('una tinta blu viene schiarita, non sostituita col viola', () {
    // Un blu scuro alla stessa lightness di un rosso ha luminanza relativa
    // molto piu' bassa: falliva il controllo di contrasto e veniva
    // scartato, e la pagina tornava al viola di marca.
    const darkBlue = Color(0xFF151928);
    final out = toneMapAccent(darkBlue);
    expect(out, isNot(AppColors.irisBright));
    expect(
      HSLColor.fromColor(out).hue,
      closeTo(HSLColor.fromColor(darkBlue).hue, 2.0),
    );
  });

  test("ogni accento si legge sulla tela dell'app", () {
    // La regola che conta: qualunque copertina entri, quello che esce deve
    // stare a 4.5:1 su ink800. Si passano tutte le tinte a passi di 15
    // gradi, a varie saturazioni e luminosita'.
    for (var h = 0.0; h < 360; h += 15) {
      for (final s in [0.2, 0.4, 0.7, 1.0]) {
        for (final l in [0.05, 0.15, 0.4, 0.75, 0.95]) {
          final raw = HSLColor.fromAHSL(1, h, s, l).toColor();
          final out = toneMapAccent(raw);
          expect(
            contrastOnCanvas(out),
            greaterThanOrEqualTo(4.5),
            reason: 'H=$h S=$s L=$l -> #${out.toARGB32().toRadixString(16)}',
          );
        }
      }
    }
  });
}
