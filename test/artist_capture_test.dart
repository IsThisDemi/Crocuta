import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' show instantiateImageCodec;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/artist.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/artist_screen.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/widgets/spot_controls.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

/// Mette una vera immagine nella cache, sotto la chiave che usera'
/// `Image.network`.
///
/// Non si passa da un HttpClient finto: `Image.network` completa con
/// dell'I/O vero, e `capture` avanza a tempo finto, quindi la richiesta
/// resta appesa e sullo schermo finisce il segnaposto grigio. La
/// decodifica invece si puo' fare prima, in tempo vero, e infilare gia'
/// pronta — a quel punto il widget la trova senza chiedere niente a
/// nessuno.
Future<void> seedImage(WidgetTester tester, String url, File file) async {
  await tester.runAsync(() async {
    final codec = await instantiateImageCodec(file.readAsBytesSync());
    final frame = await codec.getNextFrame();
    PaintingBinding.instance.imageCache.putIfAbsent(
      NetworkImage(url),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: frame.image)),
      ),
    );
  });
}

Track song(String title, String plays) => Track(
  id: title,
  title: title,
  author: 'PinkPantheress',
  duration: const Duration(minutes: 2, seconds: 26),
  thumbnailUrl: 'https://example.invalid/t.png',
  plays: plays,
);

final page = ArtistPage(
  browseId: 'UC1',
  name: 'PinkPantheress',
  thumbnailUrl: 'https://example.invalid/artist.png',
  monthlyListeners: '83,3 Mln ascoltatori mensili',
  topSongs: [
    song('Stateside + Zara Larsson', '227 Mln'),
    song("Boy's a liar Pt. 2", '510 Mln'),
    song('Girl Like Me', '48 Mln'),
    song('Illegal', '77 Mln'),
  ],
  albums: const [
    AlbumCard(
      browseId: 'a1',
      title: 'Heaven knows',
      subtitle: 'Album · 2023',
      thumbnailUrl: 'https://example.invalid/a.png',
    ),
  ],
);

/// Il nome grande in cima, non le quattro righe di brani che portano lo
/// stesso nome come autore: e' l'unico scritto in corpo da titolo.
final heading = find.byWidgetPredicate(
  (w) =>
      w is Text && w.data == 'PinkPantheress' && (w.style?.fontSize ?? 0) >= 40,
);

/// La foto dell'artista: una macchia, come le copertine.
final photoSpot = find.byType(SpotCover);

/// Legge il canale rosso di una cattura, in coordinate logiche.
///
/// Decodificare e' I/O vero e il test avanza a tempo finto: fuori da
/// runAsync l'attesa non finisce mai.
Future<int Function(int x, int y)> pixelsOf(
  WidgetTester tester,
  String name,
) async {
  late final int width;
  late final ByteData data;
  await tester.runAsync(() async {
    final decoded = await decodeImageFromList(
      File('build/screens/$name.png').readAsBytesSync(),
    );
    width = decoded.width;
    data = (await decoded.toByteData())!;
    decoded.dispose();
  });
  // La cattura e' a pixelRatio 2: si ragiona in coordinate logiche.
  return (x, y) => data.getUint8((((y * 2) * width) + (x * 2)) * 4);
}

void main() {
  final photo = File('test/fixtures/photo.png');

  // Il binding non esiste finche' non parte il primo testWidgets, quindi
  // la cache si svuota dentro il tearDown, non nominandola qui fuori.
  tearDown(() => PaintingBinding.instance.imageCache.clear());

  testWidgets("l'intestazione artista e' senza barra, con foto e nome", (
    tester,
  ) async {
    // L'aggancio documentato di Flutter per le immagini di rete nei test:
    // HttpOverrides.global da solo non basta, il binding di test ne mette
    // uno suo che risponde 400 a tutto.
    await seedImage(tester, 'https://example.invalid/artist.png', photo);

    await capture(
      tester,
      const ArtistScreen(browseId: 'UC1', name: 'PinkPantheress'),
      name: 'artista',
      safeAreaTop: 59,
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('UC1').overrideWith((ref) => Future.value(page)),
      ],
    );

    // Il titolo della barra non c'e' piu': la barra non c'e' piu'.
    expect(find.text('Artista'), findsNothing);
    expect(heading, findsOneWidget);
    expect(photoSpot, findsOneWidget);

    // Il play e' la macchia senza testo; casuale e segui sono parole.
    expect(find.text('Play'), findsNothing);
    expect(find.byType(SpotPlayButton), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);

    // Il tasto indietro resta raggiungibile, e non copre il nome.
    final back = find.byIcon(Icons.arrow_back_ios_new_rounded);
    expect(back, findsOneWidget);
    expect(tester.getRect(back).overlaps(tester.getRect(heading)), isFalse);
  });

  testWidgets('sul telefono la foto sta sopra e il nome sotto', (tester) async {
    await seedImage(tester, 'https://example.invalid/artist.png', photo);

    await capture(
      tester,
      const ArtistScreen(browseId: 'UC1', name: 'PinkPantheress'),
      name: 'artista_misure',
      safeAreaTop: 59,
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('UC1').overrideWith((ref) => Future.value(page)),
      ],
    );

    final spot = tester.getRect(photoSpot);
    final name = tester.getRect(heading);

    // La macchia sotto l'area sicura, non dietro il notch.
    expect(spot.top, greaterThanOrEqualTo(59));
    // Il nome sotto la foto, non sovrapposto come una didascalia.
    expect(name.top, greaterThanOrEqualTo(spot.bottom));
    // Tutti e due allineati al margine della pagina, non centrati.
    expect(spot.left, closeTo(20, 1));
    expect(name.left, closeTo(20, 1));
    // E il nome sta nello schermo.
    expect(name.right, lessThanOrEqualTo(430 - 20 + 1));
  });

  testWidgets('la foto si dipinge davvero dentro la macchia', (tester) async {
    await seedImage(tester, 'https://example.invalid/artist.png', photo);

    await capture(
      tester,
      const ArtistScreen(browseId: 'UC1', name: 'PinkPantheress'),
      name: 'artista_macchia',
      safeAreaTop: 59,
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('UC1').overrideWith((ref) => Future.value(page)),
      ],
    );

    // Sui pixel e non sull'albero: un ritaglio che non dipinge, o il
    // segnaposto grigio al posto della foto, nell'albero non si vedono.
    final read = await pixelsOf(tester, 'artista_macchia');
    final spot = tester.getRect(photoSpot);

    // La fixture e' chiara (rosso sopra 200): al centro della macchia c'e'.
    expect(
      read(spot.center.dx.round(), spot.center.dy.round()),
      greaterThan(150),
      reason: 'al centro della macchia la foto c\'e\'',
    );
    // A sinistra della macchia, nel margine, il fondo resta scuro.
    expect(
      read(6, spot.center.dy.round()),
      lessThan(80),
      reason: 'fuori dalla macchia la foto non esce',
    );
  });

  testWidgets('su finestra larga il nome sta accanto alla foto', (
    tester,
  ) async {
    await seedImage(tester, 'https://example.invalid/artist.png', photo);

    // Piu' larga della colonna (1100): l'intestazione resta nella colonna.
    await capture(
      tester,
      const ArtistScreen(browseId: 'UC1', name: 'PinkPantheress'),
      name: 'artista_largo',
      size: const Size(1440, 900),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('UC1').overrideWith((ref) => Future.value(page)),
      ],
    );

    final spot = tester.getRect(photoSpot);
    final name = tester.getRect(heading);

    // Il nome a sinistra, la foto alla sua destra, sulla stessa fascia.
    expect(name.right, lessThanOrEqualTo(spot.left));
    expect(name.top, lessThan(spot.bottom));
    expect(name.bottom, greaterThan(spot.top));

    // Il nome allineato al bordo sinistro della colonna (170 + 20), e la
    // foto (satelliti compresi) dentro il bordo destro (1440 - 170 - 20).
    expect(name.left, closeTo(190, 1));
    expect(spot.right, lessThanOrEqualTo(1250 + 1));

    // Il nome in grande davvero: e' il titolo della pagina.
    final text = tester.widget<Text>(heading);
    expect(text.style!.fontSize, greaterThanOrEqualTo(56));
  });
}
