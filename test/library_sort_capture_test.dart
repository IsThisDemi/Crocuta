import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/favorites_screen.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/services/storage_service.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

/// Nove brani: abbastanza perche' compaia "Find in Liked Songs", che con
/// ordinamento e filtri deve convivere.
const _favs = [
  Track(id: 'a', title: 'Corrente', author: 'Marea Bassa', thumbnailUrl: ''),
  Track(
    id: 'b',
    title: 'Luce Radente',
    author: 'Marea Bassa',
    thumbnailUrl: '',
    isExplicit: true,
  ),
  Track(id: 'c', title: 'Campo Lungo', author: 'Vetro', thumbnailUrl: ''),
  Track(id: 'd', title: 'Nebbia', author: 'Terzo Piano', thumbnailUrl: ''),
  Track(id: 'e', title: 'Argine', author: 'The Fiumi', thumbnailUrl: ''),
  Track(id: 'f', title: 'Brina', author: 'Vetro', thumbnailUrl: ''),
  Track(
    id: 'g',
    title: 'Eco',
    author: 'Terzo Piano',
    thumbnailUrl: '',
    isExplicit: true,
  ),
  Track(id: 'h', title: 'Faro', author: 'Marea Bassa', thumbnailUrl: ''),
  Track(id: 'i', title: 'Duna', author: 'Vetro', thumbnailUrl: ''),
];

class _FakeFavorites extends FavoritesController {
  @override
  List<Track> build() => _favs;
}

final _overrides = [
  playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
  favoritesProvider.overrideWith(_FakeFavorites.new),
];

/// Alta abbastanza da avere tutti i brani a schermo, sotto la copertina.
const _tall = Size(900, 2200);

StorageService _storage(WidgetTester t) => ProviderScope.containerOf(
  t.element(find.byType(FavoritesScreen)),
).read(storageServiceProvider);

/// Hive tiene le scatole aperte fra un test e l'altro dello stesso file:
/// senza rimettere la pagina com'era, il filtro acceso da un test si
/// ritrova acceso nel successivo.
void _resetAfter(WidgetTester t) {
  final storage = _storage(t);
  addTearDown(() {
    storage.setLibraryFilters('liked', {});
    storage.setSongSort('liked', 'added');
  });
}

Future<void> _openMenu(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.filter_list_rounded));
  await t.pumpAndSettle();
}

Future<void> _pick(WidgetTester t, String label) async {
  _resetAfter(t);
  await _openMenu(t);
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('cattura: piaciuti col menu di ordinamento aperto', (
    tester,
  ) async {
    await capture(
      tester,
      const FavoritesScreen(),
      name: 'preferiti_ordina_menu',
      overrides: _overrides,
      interact: _openMenu,
    );

    // La voce attiva col verso scritto accanto, poi le altre e i filtri.
    expect(find.text('Recently Added · Newest First'), findsOneWidget);
    for (final label in [
      'Title',
      'Artist',
      'Album',
      'Most Played',
      'Duration',
      'Downloaded Only',
      'Hide Explicit',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Nessun filtro acceso: niente "Clear Filters".
    expect(find.text('Clear Filters'), findsNothing);
  });

  testWidgets('cattura: il menu su una finestra da Mac', (tester) async {
    await capture(
      tester,
      const FavoritesScreen(),
      name: 'preferiti_ordina_menu_mac',
      size: const Size(1280, 860),
      overrides: _overrides,
      interact: (t) async {
        // Con un filtro acceso: il pulsante prende l'accento.
        await _pick(t, 'Hide Explicit');
        await _openMenu(t);
      },
    );
    expect(find.text('Clear Filters'), findsOneWidget);
  });

  testWidgets('scegliere una voce la salva, ritoccarla gira il verso', (
    tester,
  ) async {
    await capture(
      tester,
      const FavoritesScreen(),
      name: 'preferiti_per_titolo',
      size: _tall,
      overrides: _overrides,
      interact: (t) async {
        await _pick(t, 'Title');
        expect(_storage(t).songSort('liked'), 'title');
        await _pick(t, 'Title · A to Z');
        expect(_storage(t).songSort('liked'), 'title:rev');
      },
    );

    // Dalla Z alla A: Nebbia prima di Argine.
    final nebbia = tester.getTopLeft(find.text('Nebbia'));
    final argine = tester.getTopLeft(find.text('Argine'));
    expect(nebbia.dy, lessThan(argine.dy));
  });

  testWidgets(
    'un filtro che svuota la lista lo dice e si spegne con un tocco',
    (tester) async {
      await capture(
        tester,
        const FavoritesScreen(),
        name: 'preferiti_filtro_vuoto',
        size: _tall,
        overrides: _overrides,
        // Nessun brano scaricato: "Downloaded Only" svuota la lista.
        interact: (t) => _pick(t, 'Downloaded Only'),
      );

      expect(find.text('No matching songs'), findsOneWidget);
      expect(_storage(tester).libraryFilters('liked'), {'downloaded'});
      // Il filtro resta nel menu, spuntato, con "Clear Filters" in fondo:
      // due, con il pulsante dello stato vuoto.
      await _openMenu(tester);
      expect(find.text('Clear Filters'), findsNWidgets(2));
      await tester.tapAt(const Offset(5, 2100));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Clear Filters'));
      await tester.pumpAndSettle();
      expect(find.text('No matching songs'), findsNothing);
      expect(find.text('Corrente'), findsOneWidget);
      expect(_storage(tester).libraryFilters('liked'), isEmpty);
    },
  );

  testWidgets('Hide Explicit si somma alla ricerca', (tester) async {
    await capture(
      tester,
      const FavoritesScreen(),
      name: 'preferiti_senza_espliciti',
      size: _tall,
      overrides: _overrides,
      interact: (t) async {
        await _pick(t, 'Hide Explicit');
        await t.enterText(find.byType(TextField), 'marea');
        await t.pumpAndSettle();
      },
    );

    // Di Marea Bassa restano i due non espliciti.
    expect(find.text('Corrente'), findsOneWidget);
    expect(find.text('Faro'), findsOneWidget);
    expect(find.text('Luce Radente'), findsNothing);
  });
}
