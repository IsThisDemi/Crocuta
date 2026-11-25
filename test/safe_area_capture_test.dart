import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/widgets/liquid.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/favorites_screen.dart';
import 'package:yeen_music/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _tracks = [
  Track(
    id: 'a',
    title: 'Corrente Ascensionale',
    author: 'Marea Bassa',
    duration: Duration(minutes: 3, seconds: 42),
    thumbnailUrl: '',
  ),
  Track(
    id: 'b',
    title: 'Luce Radente',
    author: 'Marea Bassa',
    duration: Duration(minutes: 4, seconds: 5),
    thumbnailUrl: '',
  ),
  Track(
    id: 'c',
    title: 'Campo Lungo',
    author: 'Vetro Sottile',
    duration: Duration(minutes: 2, seconds: 58),
    thumbnailUrl: '',
  ),
];

class _FakeFavorites extends FavoritesController {
  @override
  List<Track> build() => _tracks;
}

void main() {
  testWidgets('il contenuto sta sotto la barra anche col notch', (
    tester,
  ) async {
    // Il caso che sul Mac non si vede: li' l'area sicura in cima e' zero e
    // il conto torna lo stesso.
    const notch = 59.0;
    await capture(
      tester,
      const FavoritesScreen(),
      name: 'preferiti_notch',
      safeAreaTop: notch,
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        favoritesProvider.overrideWith(_FakeFavorites.new),
      ],
    );

    // La copertina deve cominciare sotto il tasto indietro, non dietro:
    // la pagina ora e' quella di una raccolta, senza barra in cima.
    final cover = tester.getRect(find.byType(LikedSongsCover));
    final back = tester.getRect(find.byType(GlassCircleIconButton).first);
    expect(back.top, greaterThanOrEqualTo(notch));
    expect(
      cover.top,
      greaterThan(back.bottom),
      reason: 'la copertina finisce dietro il tasto indietro',
    );
  });
}
