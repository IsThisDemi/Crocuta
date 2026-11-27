import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crocuta/widgets/large_title.dart';

import 'package:crocuta/models/artist.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/section_screen.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/widgets/spot_layouts.dart';
import 'package:crocuta/widgets/track_tile.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const singles = SectionLink(
  title: 'Singles & EPs',
  browseId: 'MPAD1',
  params: 'abc%3D',
);

const songs = SectionLink(
  title: 'Top songs',
  browseId: 'VL1',
  params: 'abc%3D',
  songs: true,
);

List<AlbumCard> cards(int n) => [
  for (var i = 0; i < n; i++)
    AlbumCard(
      browseId: 'a$i',
      title: 'Release $i',
      subtitle: '2026',
      thumbnailUrl: '',
    ),
];

List<Track> tracks(int n) => [
  for (var i = 0; i < n; i++)
    Track(id: 't$i', title: 'Song $i', author: 'Yeat', thumbnailUrl: ''),
];

void main() {
  test('due link alla stessa sezione sono lo stesso link', () {
    // E' la chiave di un provider family: con la sola identita' una pagina
    // artista ricaricata rifarebbe una richiesta gia' fatta.
    const a = SectionLink(title: 'Singles', browseId: 'X', params: 'p');
    const b = SectionLink(title: 'Altro nome', browseId: 'X', params: 'p');
    expect(a, b);
    expect(a.hashCode, b.hashCode);

    const diverso = SectionLink(title: 'Singles', browseId: 'X', params: 'q');
    expect(a, isNot(diverso));
  });

  testWidgets('la sezione di copertine e una griglia, non un carosello', (
    tester,
  ) async {
    await capture(
      tester,
      const SectionScreen(link: singles),
      name: 'sezione_griglia',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        sectionProvider(singles).overrideWith((ref) => cards(28)),
      ],
    );

    expect(find.byType(SpotGrid), findsOneWidget);
    // Il titolo grande, nella pagina: quello piccolo in cima e' una
    // seconda copia, che compare solo scorrendo.
    expect(
      find.descendant(
        of: find.byType(LargeTitle),
        matching: find.text('Singles & EPs'),
      ),
      findsOneWidget,
    );

    // Due per riga su un telefono: la seconda accanto alla prima, la terza
    // va a capo sotto la prima. E' la differenza col carosello, dove
    // scorrevano tutte di lato. Le colonne sono sfalsate (il manto), quindi
    // la seconda sta un poco piu' in basso della prima, ma sopra la terza.
    final r0 = tester.getRect(find.text('Release 0'));
    final r1 = tester.getRect(find.text('Release 1'));
    final r2 = tester.getRect(find.text('Release 2'));
    expect(r1.left, greaterThan(r0.right));
    expect(r1.top, greaterThanOrEqualTo(r0.top));
    expect(r1.top, lessThan(r2.top));
    expect(r2.top, greaterThan(r0.bottom));
    expect(r2.left, closeTo(r0.left, 1));
  });

  testWidgets('la sezione di brani e un elenco completo', (tester) async {
    await capture(
      tester,
      const SectionScreen(link: songs),
      name: 'sezione_brani',
      size: const Size(430, 932),
      safeAreaTop: 59,
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        sectionProvider(songs).overrideWith((ref) => tracks(40)),
      ],
    );

    // Il titolo grande, nella pagina: quello piccolo in cima e' una
    // seconda copia, che compare solo scorrendo.
    expect(
      find.descendant(
        of: find.byType(LargeTitle),
        matching: find.text('Top songs'),
      ),
      findsOneWidget,
    );
    expect(find.byType(TrackTile), findsWidgets);
    // In cima ci sono i primi, non i soliti cinque dell'anteprima.
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 6'), findsOneWidget);
  });
}
