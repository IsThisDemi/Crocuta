import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// I due colori che si ricavano da una copertina.
///
/// Servono per due lavori opposti, e usarne uno solo per entrambi era il
/// motivo per cui certe copertine finivano sul viola di marca.
class ArtworkPalette {
  /// Scuro e saturo: sta dietro al contenuto, sfocato, e deve restare
  /// indietro.
  final Color? backdrop;

  /// Il colore piu' vivo della copertina, ignorando il quasi-nero e il
  /// quasi-bianco. Su una copertina scura la massa dominante e' lo sfondo,
  /// quindi [backdrop] tornava nero e l'accento non aveva nessuna tinta da
  /// cui partire.
  final Color? vivid;

  /// La fascia orizzontale piu' chiara della copertina, come media sRGB.
  ///
  /// Serve a prevedere quanto sara' chiaro lo sfondo sfocato sotto il testo.
  /// Non la media dell'immagine intera: lo sfocato stende la copertina su
  /// tutto lo schermo, e in cima alla pagina c'e' la parte alta del disegno.
  /// Su "early life crisis" la media mescolava il muro azzurro in alto con la
  /// felpa scura in basso, e stimava uno sfondo sei volte piu' scuro di
  /// quello misurato sotto il titolo. Il caso peggiore invece regge dovunque
  /// stia il testo.
  ///
  /// In sRGB perche' e' li' che Flutter sfoca e mescola. [backdrop] non
  /// serve, e' scelto apposta scuro.
  final Color? lightest;

  /// Fino a quattro tinte diverse della copertina, dalla piu' presente.
  ///
  /// Sono le macchie "satellite" attorno alla copertina nel player: devono
  /// sembrare cadute dalla copertina stessa, quindi colori suoi e diversi
  /// fra loro, non quattro sfumature dello stesso rosa.
  final List<Color> swatches;

  const ArtworkPalette({
    this.backdrop,
    this.vivid,
    this.lightest,
    this.swatches = const [],
  });

  static const empty = ArtworkPalette();
}

/// Il colore dominante di una copertina, tarato per lo sfondo sfocato.
Future<Color?> dominantColorOf(String url) async =>
    (await paletteOf(url)).backdrop;

/// Estrae entrambi i colori in un solo passaggio.
///
/// Un solo scaricamento: la copertina cambia a ogni brano e questo sta sul
/// percorso caldo, quindi due estrazioni separate significherebbero due
/// richieste HTTP per ogni traccia.
Future<ArtworkPalette> paletteOf(String url) async {
  try {
    final resp = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return ArtworkPalette.empty;

    final codec = await ui.instantiateImageCodec(
      resp.bodyBytes,
      targetWidth: 48,
      targetHeight: 48,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    if (data == null) return ArtworkPalette.empty;

    // Bucket histogram: 4 bits per channel → 4096 buckets.
    const shift = 4;
    final weights = <int, double>{};
    final vividWeights = <int, double>{};
    final counts = <int, int>{};
    final sums = <int, List<double>>{};

    final bytes = data.buffer.asUint8List();
    // Sei fasce orizzontali di otto righe: l'immagine arriva a 48x48.
    const bands = 6, side = 48;
    final br = List.filled(bands, 0), bg = List.filled(bands, 0);
    final bb = List.filled(bands, 0), bn = List.filled(bands, 0);
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      final r = bytes[i].toDouble();
      final g = bytes[i + 1].toDouble();
      final b = bytes[i + 2].toDouble();
      final band = ((i ~/ 4) ~/ side * bands ~/ side).clamp(0, bands - 1);
      br[band] += bytes[i];
      bg[band] += bytes[i + 1];
      bb[band] += bytes[i + 2];
      bn[band]++;
      final key =
          ((r.toInt() >> (8 - shift)) << (shift * 2)) |
          ((g.toInt() >> (8 - shift)) << shift) |
          (b.toInt() >> (8 - shift));

      final lightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      final maxC = [r, g, b].reduce((a, b) => a > b ? a : b) / 255;
      final minC = [r, g, b].reduce((a, b) => a < b ? a : b) / 255;
      final saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
      // Prefer darker, saturated buckets so the backdrop looks rich.
      final w = (1 - lightness) * (0.35 + saturation);

      // Per l'accento conta il colore, non la massa: il quasi-nero e il
      // quasi-bianco non sono tinte, e vanno esclusi invece di vincere
      // perche' occupano meta' immagine.
      if (lightness > 0.15 && lightness < 0.95 && saturation > 0.25) {
        vividWeights[key] = (vividWeights[key] ?? 0) + saturation * saturation;
      }

      weights[key] = (weights[key] ?? 0) + w;
      counts[key] = (counts[key] ?? 0) + 1;
      final s = sums.putIfAbsent(key, () => [0, 0, 0]);
      s[0] += r;
      s[1] += g;
      s[2] += b;
    }

    Color? pick(Map<int, double> scores) {
      int? bestKey;
      var bestW = -1.0;
      scores.forEach((k, v) {
        if (v > bestW) {
          bestW = v;
          bestKey = k;
        }
      });
      if (bestKey == null) return null;
      final sum = sums[bestKey]!;
      final n = counts[bestKey]!;
      return Color.fromARGB(
        255,
        (sum[0] / n).round().clamp(0, 255),
        (sum[1] / n).round().clamp(0, 255),
        (sum[2] / n).round().clamp(0, 255),
      );
    }

    Color average(int key) {
      final sum = sums[key]!;
      final n = counts[key]!;
      return Color.fromARGB(
        255,
        (sum[0] / n).round().clamp(0, 255),
        (sum[1] / n).round().clamp(0, 255),
        (sum[2] / n).round().clamp(0, 255),
      );
    }

    // Le tinte: i secchi piu' pesanti fra quelli colorati, scartando chi e'
    // troppo vicino (in tinta e luce) a uno gia' preso.
    final swatches = <Color>[];
    final ranked =
        (vividWeights.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .map((e) => average(e.key));
    for (final c in ranked) {
      final h = HSLColor.fromColor(c);
      final close = swatches.any((o) {
        final ho = HSLColor.fromColor(o);
        final dh = (h.hue - ho.hue).abs();
        final hue = dh > 180 ? 360 - dh : dh;
        return hue < 28 && (h.lightness - ho.lightness).abs() < 0.22;
      });
      if (!close) swatches.add(c);
      if (swatches.length == 4) break;
    }

    return ArtworkPalette(
      swatches: swatches,
      backdrop: pick(weights),
      vivid: pick(vividWeights),
      lightest: () {
        Color? best;
        var bestLum = -1.0;
        for (var k = 0; k < bands; k++) {
          if (bn[k] == 0) continue;
          final c = Color.fromARGB(
            255,
            br[k] ~/ bn[k],
            bg[k] ~/ bn[k],
            bb[k] ~/ bn[k],
          );
          final l = c.computeLuminance();
          if (l > bestLum) {
            bestLum = l;
            best = c;
          }
        }
        return best;
      }(),
    );
  } catch (_) {
    return ArtworkPalette.empty;
  }
}
