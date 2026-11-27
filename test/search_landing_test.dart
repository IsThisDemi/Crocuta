import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/artist.dart';
import 'package:crocuta/models/explore.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/browse_screens.dart';
import 'package:crocuta/screens/search_screen.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/widgets/large_title.dart';
import 'package:crocuta/widgets/track_tile.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

AlbumCard card(String t) => AlbumCard(
  browseId: 'b$t',
  title: t,
  subtitle: 'Playlist',
  thumbnailUrl: '',
);

final page = ExplorePage(
  trending: [
    for (var i = 0; i < 12; i++)
      Track(
        id: 't$i',
        title: 'Hit $i',
        author: 'Artist $i',
        thumbnailUrl: '',
        plays: '${i}00K views',
      ),
  ],
  charts: [card('Trending 20 Italy'), card('Top 100 Italy')],
  globalCharts: [card('Top 100 Global')],
  newReleases: [card('Nuovo album')],
);

// Quante categorie da' davvero YouTube Music: molte piu' di quelle che
// entrano in due righe, e coi colori veri — gialli compresi.
const groups = [
  CategoryGroup(
    title: 'Moods & moments',
    items: [
      BrowseCategory(title: 'Chill', color: 0xFF7E57C2, params: 'c'),
      BrowseCategory(title: 'Workout', color: 0xFFE53935, params: 'w'),
      BrowseCategory(title: 'Commute', color: 0xFFFFCA28, params: 'co'),
      BrowseCategory(title: 'Energize', color: 0xFFFFE082, params: 'e'),
      BrowseCategory(title: 'Focus', color: 0xFFA8C7FA, params: 'f'),
      BrowseCategory(title: 'Feel good', color: 0xFFFF7043, params: 'fg'),
      BrowseCategory(title: 'Party', color: 0xFFEC407A, params: 'p'),
      BrowseCategory(title: 'Sleep', color: 0xFF5C6BC0, params: 's'),
    ],
  ),
  CategoryGroup(
    title: 'Genres',
    items: [
      BrowseCategory(title: 'Hip-Hop', color: 0xFF43A047, params: 'h'),
      BrowseCategory(title: 'Pop', color: 0xFF26C6DA, params: 'po'),
      BrowseCategory(title: 'Rock', color: 0xFF616161, params: 'r'),
      BrowseCategory(
        title: 'Dance & Electronic',
        color: 0xFFD4E157,
        params: 'd',
      ),
      BrowseCategory(title: 'R&B', color: 0xFF8D6E63, params: 'rb'),
      BrowseCategory(title: 'Jazz', color: 0xFFFFA726, params: 'j'),
    ],
  ),
];

List<Override> landingOverrides(List<String> history) => [
  playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
  exploreProvider.overrideWith((ref) => page),
  categoriesProvider.overrideWith((ref) => groups),
  searchHistoryProvider.overrideWith(() => _History(history)),
];

/// Il titolo piccolo in cima: lo stesso testo del grande, dentro la
/// dissolvenza della cornice.
double smallTitleOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(of: find.text('Search'), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

void main() {
  testWidgets('la ricerca vuota mostra recenti, tendenze e classifiche', (
    tester,
  ) async {
    await capture(
      tester,
      const SearchScreen(),
      name: 'ricerca_ingresso',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: landingOverrides(['yeat', 'shiva']),
    );

    // Il titolo grande, come le altre schede, e il campo che dice cosa si
    // cerca e non dove.
    expect(find.byType(LargeTitle), findsOneWidget);
    expect(find.text('Artists, songs, lyrics…'), findsOneWidget);
    expect(find.textContaining('YouTube'), findsNothing);

    // Le ricerche di prima, che stavano in Home: parole sparse in fila,
    // non un elenco, e la piu' recente e' la piu' grande.
    expect(find.text('Recently searched'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('yeat'), findsOneWidget);
    expect(find.text('shiva'), findsOneWidget);
    final yeat = tester.getRect(find.text('yeat'));
    final shiva = tester.getRect(find.text('shiva'));
    expect(shiva.overlaps(yeat), isFalse);
    expect(yeat.height, greaterThan(shiva.height));
    expect(
      find.ancestor(of: find.text('yeat'), matching: find.byType(ListTile)),
      findsNothing,
    );

    // Le categorie, umori e generi alternati: sul telefono due colonne per
    // due righe piene.
    expect(find.text('Browse'), findsOneWidget);
    expect(find.byType(CategoryTile), findsNWidgets(4));
    for (final c in ['Chill', 'Hip-Hop', 'Workout', 'Pop']) {
      expect(find.text(c), findsOneWidget);
    }

    // Il generico utile al posto della pagina vuota.
    expect(find.text('Trending now'), findsOneWidget);
    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('Global charts'), findsOneWidget);
    expect(find.text('New releases'), findsOneWidget);

    // I brani del momento sono righe vere, riproducibili.
    expect(find.byType(TrackTile), findsWidgets);
    expect(find.text('Hit 0'), findsOneWidget);

    // E il vecchio vuoto non c'e' piu'.
    expect(find.text('Listen to your music'), findsNothing);
  });

  testWidgets('appena si scrive, sparisce tutto', (tester) async {
    await capture(
      tester,
      const SearchScreen(),
      name: 'ricerca_digitando',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: landingOverrides(['yeat']),
      interact: (tester) async {
        await tester.enterText(find.byType(TextField), 'pink');
        await tester.pump();
      },
    );

    expect(find.text('Trending now'), findsNothing);
    expect(find.text('Charts'), findsNothing);
    expect(find.text('Recently searched'), findsNothing);
    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('sulla finestra larga: righe piene e bordi allineati', (
    tester,
  ) async {
    await capture(
      tester,
      const SearchScreen(),
      name: 'ricerca_ingresso_larga',
      size: const Size(1400, 880),
      overrides: landingOverrides(['yeat', 'shiva']),
    );

    // Colonna da 1100: cinque colonne, due righe, nessun buco.
    expect(find.byType(CategoryTile), findsNWidgets(10));

    // Il campo (la sua linea sotto, lente compresa) comincia dove
    // cominciano titolo, intestazioni e tessere.
    final left = tester.getTopLeft(find.byType(LargeTitle)).dx;
    expect(tester.getTopLeft(find.byType(TextField)).dx, left);
    expect(tester.getTopLeft(find.byType(CategoryTile).first).dx, left);
    expect(tester.getTopLeft(find.text('yeat')).dx, left);
    expect(
      tester.getTopLeft(find.text('Browse')).dx,
      moreOrLessEquals(left, epsilon: 1),
    );
  });

  testWidgets('scorrendo, il titolo grande si stringe in quello piccolo', (
    tester,
  ) async {
    await capture(
      tester,
      const SearchScreen(),
      name: 'ricerca_scorsa',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: landingOverrides(['yeat', 'shiva']),
      interact: (tester) async {
        expect(smallTitleOpacity(tester), 0);
        await tester.drag(
          find.text('Recently searched'),
          const Offset(0, -400),
        );
      },
    );
    expect(smallTitleOpacity(tester), 1);

    // Il campo e' scorso via ma esiste ancora: ⌘F lo ritrova e lo riporta
    // in vista.
    final offstage = find.byType(TextField, skipOffstage: false);
    expect(offstage, findsOneWidget);
    final field = tester.widget<TextField>(offstage);
    field.focusNode!.requestFocus();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.getTopLeft(find.byType(TextField)).dy, greaterThan(59));
  });
}

class _History extends SearchHistoryController {
  _History(this._items);
  final List<String> _items;

  @override
  List<String> build() => _items;
}
