import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/design/app_theme.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/media_detail_page.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/widgets/empty_state.dart';
import 'package:crocuta/widgets/spot_controls.dart';
import 'package:crocuta/widgets/track_tile.dart';

import 'support/fake_player.dart';

const _tracks = [
  Track(id: 'a', title: 'Primo brano', author: 'Tizio', thumbnailUrl: ''),
  Track(id: 'b', title: 'Secondo brano', author: 'Caio', thumbnailUrl: ''),
];

void main() {
  Future<void> pump(
    WidgetTester tester,
    MediaDetail detail, {
    PlayerState state = const PlayerState(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith(() => FakePlayer(state))],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: MediaDetailPage(detail: detail)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('mostra intestazione, azioni e una riga per traccia', (
    tester,
  ) async {
    await pump(
      tester,
      const MediaDetail(
        title: 'Disco di prova',
        imageUrl: '',
        tracks: _tracks,
        meta: ['Album', '2024'],
        footnote: ['2 songs, 5 minutes'],
      ),
    );

    // Una colonna sola anche sulla finestra larga: la testa e' una fascia
    // in cima alla lista. Due titoli: quello grande e quello piccolo,
    // ancora trasparente, che compare in cima scorrendo.
    expect(find.text('Disco di prova'), findsNWidgets(2));
    expect(find.text('Album · 2024'), findsOneWidget);
    // Il play e' la macchia senza testo; il casuale e' una parola.
    expect(find.text('Play'), findsNothing);
    expect(find.byType(SpotPlayButton), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.byType(TrackTile), findsNWidgets(2));
    // La fascia: copertina e titolo affiancati, la scaletta sotto, larga
    // quanto la pagina e non stretta in una colonna accanto alla testa.
    final title = tester.getRect(find.text('Disco di prova').first);
    final play = tester.getRect(find.byType(SpotPlayButton));
    final firstRow = tester.getRect(find.byType(TrackTile).first);
    expect(firstRow.top, greaterThanOrEqualTo(play.bottom));
    expect(firstRow.left, lessThan(title.left));
    // Il riepilogo in fondo, dopo l'ultimo brano.
    await tester.scrollUntilVisible(
      find.text('2 songs, 5 minutes'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('2 songs, 5 minutes'), findsOneWidget);
  });

  testWidgets('su telefono la testa sta sopra la scaletta', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      const MediaDetail(title: 'Disco di prova', imageUrl: '', tracks: _tracks),
    );

    // Due volte: il titolo grande e quello piccolo, ancora trasparente,
    // che compare in cima scorrendo.
    expect(find.text('Disco di prova'), findsNWidgets(2));
    expect(find.byType(SpotPlayButton), findsOneWidget);
    // Tutto in colonna: il primo brano sotto il play.
    final play = tester.getRect(find.byType(SpotPlayButton));
    final firstRow = tester.getRect(find.byType(TrackTile).first);
    expect(firstRow.top, greaterThanOrEqualTo(play.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un album numera le tracce invece di ripetere la copertina', (
    tester,
  ) async {
    await pump(
      tester,
      const MediaDetail(
        title: 'Disco',
        imageUrl: '',
        tracks: _tracks,
        numbered: true,
      ),
    );

    // Ogni riga dell'album ripeteva la stessa copertina: il numero invece
    // dice dove sei nel disco.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      tester.widgetList<TrackTile>(find.byType(TrackTile)).map((t) => t.number),
      [1, 2],
    );
  });

  testWidgets('una playlist tiene le copertine', (tester) async {
    await pump(
      tester,
      const MediaDetail(title: 'Mista', imageUrl: '', tracks: _tracks),
    );

    // In una playlist le copertine sono diverse fra loro e dicono qualcosa.
    expect(
      tester.widgetList<TrackTile>(find.byType(TrackTile)).map((t) => t.number),
      [null, null],
    );
  });

  testWidgets(
    'il brano in riproduzione prende le barrette al posto del numero',
    (tester) async {
      await pump(
        tester,
        const MediaDetail(
          title: 'Disco',
          imageUrl: '',
          tracks: _tracks,
          numbered: true,
        ),
        state: PlayerState(queue: _tracks, currentIndex: 0, isPlaying: true),
      );

      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets('i pezzi di metadati vuoti o nulli spariscono', (tester) async {
    // Gli album senza anno passano null, e le playlist non hanno artista.
    await pump(
      tester,
      const MediaDetail(
        title: 'Senza metadati',
        imageUrl: '',
        tracks: _tracks,
        meta: [null, '', '2 songs'],
      ),
    );

    // La riga di metadati deve essere esattamente "2 brani": i pezzi null e
    // vuoti spariscono senza lasciare separatori orfani (" • • 2 brani").
    // Si guarda solo quel Text: cercare "•" in tutta la pagina lo trova
    // comunque, perché TrackTile lo usa per separare artista e durata.
    final meta = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((d) => d.contains('songs'));

    expect(meta, isNotEmpty);
    expect(meta.single, '2 songs');
  });

  testWidgets('una raccolta vuota mostra l\'empty state e nessuna azione', (
    tester,
  ) async {
    await pump(
      tester,
      const MediaDetail(title: 'Vuoto', imageUrl: '', tracks: []),
    );

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byType(SpotPlayButton), findsNothing);
    expect(find.text('Shuffle'), findsNothing);
    expect(find.byType(TrackTile), findsNothing);
  });

  testWidgets('la traccia in riproduzione è evidenziata', (tester) async {
    await pump(
      tester,
      const MediaDetail(title: 'Disco', imageUrl: '', tracks: _tracks),
      state: const PlayerState(
        queue: _tracks,
        currentIndex: 1,
        isPlaying: true,
      ),
    );

    final rows = tester.widgetList<TrackTile>(find.byType(TrackTile)).toList();
    expect(rows[0].isCurrent, isFalse);
    expect(rows[1].isCurrent, isTrue);
    expect(rows[1].isPlaying, isTrue);
  });

  testWidgets("in un album l'artista si ripete solo se cambia", (tester) async {
    await pump(
      tester,
      const MediaDetail(
        title: 'Disco',
        imageUrl: '',
        numbered: true,
        artist: 'Tizio',
        tracks: [
          Track(
            id: 'a',
            title: 'Da solo',
            author: 'Tizio',
            thumbnailUrl: '',
            plays: '992K plays',
            duration: Duration(minutes: 2, seconds: 29),
          ),
          Track(
            id: 'b',
            title: 'Con ospite',
            author: 'Tizio & Caio',
            thumbnailUrl: '',
          ),
        ],
      ),
    );

    // "Tizio" c'e' una volta sola: sotto il titolo del disco, non nella
    // riga del brano che e' suo e basta.
    expect(find.text('Tizio'), findsOneWidget);
    expect(find.text('Tizio & Caio'), findsOneWidget);
    // Riproduzioni e durata, a destra.
    expect(find.text('992K'), findsOneWidget);
    expect(find.text('2:29'), findsOneWidget);
  });
}
