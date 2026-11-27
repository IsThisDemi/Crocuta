import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/models/artist.dart';
import 'package:crocuta/screens/artist_screen.dart';
import 'package:crocuta/screens/media_detail_page.dart';
import 'package:crocuta/screens/now_playing_screen.dart';
import 'package:crocuta/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

// Nomi inventati: servono solo a riempire il layout.
const _track = Track(
  id: 'xyz',
  title: 'Corrente Ascensionale',
  author: 'Marea Bassa',
  duration: Duration(minutes: 3, seconds: 42),
  thumbnailUrl: '',
  albumName: 'Nebbia in Pianura',
  // Con l'id l'album e' un collegamento: la cattura mostra lo stato acceso,
  // non quello spento di quando non si sa ancora quale sia.
  albumId: 'MPREb_finto',
);

const _state = PlayerState(
  queue: [_track],
  currentIndex: 0,
  isPlaying: true,
  position: Duration(minutes: 1, seconds: 18),
  duration: Duration(minutes: 3, seconds: 42),
);

void main() {
  testWidgets('cattura: schermata di riproduzione', (tester) async {
    await capture(
      tester,
      const NowPlayingScreen(),
      name: 'now_playing',
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(_state)),
        // Niente rete nei test: colore di sfondo e suggeriti finti.
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
        upNextProvider(
          'xyz|Marea Bassa',
        ).overrideWith((ref) async => <Track>[]),
      ],
    );
  });

  testWidgets('cattura: pagina album', (tester) async {
    await capture(
      tester,
      const MediaDetailPage(
        detail: MediaDetail(
          title: 'Nebbia in Pianura',
          imageUrl: 'x',
          numbered: true,
          artist: 'Marea Bassa',
          meta: ['Album', '2024'],
          footnote: ['3 songs, 10 minutes'],
          tracks: [
            Track(
              id: 'a',
              title: 'Corrente Ascensionale',
              author: 'Marea Bassa',
              duration: Duration(minutes: 3, seconds: 42),
              thumbnailUrl: 'x',
              plays: '3,080 Mln riproduzioni',
            ),
            Track(
              id: 'b',
              title: 'Luce Radente',
              author: 'Marea Bassa',
              duration: Duration(minutes: 4, seconds: 5),
              thumbnailUrl: 'x',
              plays: '4,180 Mln riproduzioni',
            ),
            Track(
              id: 'c',
              title: 'Campo Lungo',
              author: 'Marea Bassa & Vento Forte',
              isExplicit: true,
              duration: Duration(minutes: 2, seconds: 58),
              thumbnailUrl: 'x',
              plays: '5,280 Mln riproduzioni',
            ),
          ],
        ),
      ),
      name: 'album',
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(
            const PlayerState(
              queue: [
                Track(
                  id: 'b',
                  title: 'Luce Radente',
                  author: 'Marea Bassa',
                  thumbnailUrl: 'x',
                ),
              ],
              currentIndex: 0,
              isPlaying: true,
            ),
          ),
        ),
        // Copertina immaginaria di un verde-acqua scuro: l'accento della
        // pagina deve derivare da qui, non restare viola.
        backdropColorProvider(
          'x',
        ).overrideWith((ref) async => const Color(0xFF0A3D3A)),
      ],
    );
  });

  testWidgets('cattura: pagina artista', (tester) async {
    const artist = ArtistPage(
      browseId: 'AR1',
      name: 'Marea Bassa',
      thumbnailUrl: 'x',
      topSongs: [
        Track(
          id: 'a',
          title: 'Corrente Ascensionale',
          author: 'Marea Bassa',
          duration: Duration(minutes: 3, seconds: 42),
          thumbnailUrl: 'x',
          plays: '1,2 Mln riproduzioni',
        ),
        Track(
          id: 'b',
          title: 'Luce Radente',
          author: 'Marea Bassa',
          duration: Duration(minutes: 4, seconds: 5),
          thumbnailUrl: 'x',
          plays: '212K riproduzioni',
        ),
      ],
      albums: [
        AlbumCard(
          browseId: 'AL1',
          title: 'Nebbia in Pianura',
          subtitle: '2024',
          thumbnailUrl: 'x',
        ),
        AlbumCard(
          browseId: 'AL2',
          title: 'Campo Lungo',
          subtitle: '2022',
          thumbnailUrl: 'x',
        ),
      ],
      singles: [
        AlbumCard(
          browseId: 'S1',
          title: 'Riva',
          subtitle: '2025',
          thumbnailUrl: 'x',
        ),
      ],
    );

    await capture(
      tester,
      const ArtistScreen(browseId: 'AR1', name: 'Marea Bassa'),
      name: 'artista',
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('AR1').overrideWith((ref) async => artist),
        backdropColorProvider(
          'x',
        ).overrideWith((ref) async => const Color(0xFF6B1E3F)),
      ],
    );
  });

  testWidgets('cattura: pagina artista senza foto', (tester) async {
    // Artisti senza immagine esistono davvero: l'intestazione non deve
    // riservare 300px di vuoto.
    const artist = ArtistPage(
      browseId: 'AR2',
      name: 'Sonda Verticale',
      topSongs: [
        Track(
          id: 'a',
          title: 'Primo Passo',
          author: 'Sonda Verticale',
          duration: Duration(minutes: 3),
          thumbnailUrl: '',
          plays: '73K riproduzioni',
        ),
        Track(
          id: 'b',
          title: 'Secondo Tempo',
          author: 'Sonda Verticale',
          duration: Duration(minutes: 3, seconds: 20),
          thumbnailUrl: '',
          plays: '17K riproduzioni',
        ),
      ],
    );

    await capture(
      tester,
      const ArtistScreen(browseId: 'AR2', name: 'Sonda Verticale'),
      name: 'artista_senza_foto',
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('AR2').overrideWith((ref) async => artist),
      ],
    );
  });

  testWidgets('cattura: pagina artista su finestra desktop', (tester) async {
    // Le altre catture sono a misura iPhone. Su Mac la finestra e' molto
    // piu' larga e il layout, nato per il telefono, si comporta diversamente.
    const artist = ArtistPage(
      browseId: 'AR3',
      name: 'Marea Bassa',
      thumbnailUrl: 'x',
      topSongs: [
        Track(
          id: 'a',
          title: 'Corrente Ascensionale',
          author: 'Marea Bassa',
          duration: Duration(minutes: 3, seconds: 42),
          thumbnailUrl: 'x',
          plays: '1,2 Mln riproduzioni',
        ),
      ],
      albums: [
        AlbumCard(
          browseId: 'AL1',
          title: 'Nebbia in Pianura',
          subtitle: '2025',
          thumbnailUrl: 'x',
        ),
      ],
      singles: [
        AlbumCard(
          browseId: 'S1',
          title: 'Riva',
          subtitle: '2025',
          thumbnailUrl: 'x',
        ),
      ],
    );

    await capture(
      tester,
      const ArtistScreen(browseId: 'AR3', name: 'Marea Bassa'),
      name: 'artista_desktop',
      size: const Size(1600, 1100),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        artistPageProvider('AR3').overrideWith((ref) async => artist),
        backdropColorProvider(
          'x',
        ).overrideWith((ref) async => const Color(0xFF6B1E3F)),
      ],
    );
  });

  testWidgets('cattura: riproduzione su finestra bassa', (tester) async {
    // Finestra larga e bassa: il player deve restare tutto in una schermata,
    // con la copertina che si rimpicciolisce invece di sfondare.
    await capture(
      tester,
      const NowPlayingScreen(),
      name: 'now_playing_basso',
      size: const Size(1100, 620),
      overrides: [
        playerProvider.overrideWith(() => FakePlayer(_state)),
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
        upNextProvider(
          'xyz|Marea Bassa',
        ).overrideWith((ref) async => <Track>[]),
      ],
    );
  });

  testWidgets('cattura: riproduzione con titolo lungo', (tester) async {
    // Titolo che va a capo su due righe piu' feat nel titolo: e' la
    // combinazione che in uso reale sfondava il blocco di 6 pixel.
    const long = Track(
      id: 'xyz',
      title: 'CLUB TEST (con IvanBi, Diss Gacha, Marea Bassa e Vetro Sottile)',
      author: 'IvanBi, Diss Gacha, Marea Bassa',
      duration: Duration(minutes: 3, seconds: 42),
      thumbnailUrl: '',
      albumName: 'Nebbia in Pianura Padana Occidentale',
    );
    await capture(
      tester,
      const NowPlayingScreen(),
      name: 'now_playing_titolo_lungo',
      size: const Size(390, 780),
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(
            const PlayerState(
              queue: [long],
              currentIndex: 0,
              isPlaying: true,
              position: Duration(minutes: 1, seconds: 18),
              duration: Duration(minutes: 3, seconds: 42),
            ),
          ),
        ),
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
        upNextProvider(
          'xyz|IvanBi, Diss Gacha, Marea Bassa',
        ).overrideWith((ref) async => <Track>[]),
      ],
    );
  });
}
