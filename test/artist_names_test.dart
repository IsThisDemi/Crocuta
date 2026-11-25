import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/artist_names.dart';

void main() {
  group('dedupeFeatGroups', () {
    test('toglie il gruppo ripetuto che arriva da YouTube Music', () {
      // Titoli reali: il gruppo e' scritto due volte, la seconda con "e"
      // al posto della virgola.
      expect(
        ArtistNames.dedupeFeatGroups(
          'CLUB TEST (con IvanBi, Diss Gacha) (con IvanBi e Diss Gacha)',
        ),
        'CLUB TEST (con IvanBi, Diss Gacha)',
      );
      expect(
        ArtistNames.dedupeFeatGroups(
          'A.D.H.D. (con Datkid, Melons) (con Datkid e Melons)',
        ),
        'A.D.H.D. (con Datkid, Melons)',
      );
    });

    test('non tocca un titolo con un gruppo solo', () {
      const one = 'Pura Purissima (con Nerissima Serpe)';
      expect(ArtistNames.dedupeFeatGroups(one), one);
      expect(ArtistNames.dedupeFeatGroups('MUSICA TRAP'), 'MUSICA TRAP');
    });

    test('non perde nessun nome', () {
      // Il secondo gruppo nomina qualcuno che il primo non nomina: va
      // tenuto, altrimenti un artista sparirebbe dal titolo.
      const both = 'Brano (con Tizio, Caio) (feat. Sempronio)';
      expect(ArtistNames.dedupeFeatGroups(both), both);
    });

    test('toglie anche un gruppo contenuto in uno precedente', () {
      expect(
        ArtistNames.dedupeFeatGroups('Brano (con Tizio, Caio) (feat. Tizio)'),
        'Brano (con Tizio, Caio)',
      );
    });

    test('ignora maiuscole e forma del separatore', () {
      expect(
        ArtistNames.dedupeFeatGroups(
          'Brano (feat. Tizio & Caio) (CON caio, TIZIO)',
        ),
        'Brano (feat. Tizio & Caio)',
      );
    });

    test('non lascia spazi doppi', () {
      final out = ArtistNames.dedupeFeatGroups(
        'Brano (con Tizio) (con Tizio) finale',
      );
      expect(out, 'Brano (con Tizio) finale');
      expect(out.contains('  '), isFalse);
    });

    test('gli ospiti restano leggibili dopo la pulizia', () {
      // La deduplica non deve rendere invisibile un artista a chi legge il
      // titolo per costruire i collegamenti.
      final clean = ArtistNames.dedupeFeatGroups(
        'CLUB TEST (con IvanBi, Diss Gacha) (con IvanBi e Diss Gacha)',
      );
      expect(ArtistNames.featuredFromTitle(clean), ['IvanBi', 'Diss Gacha']);
    });
  });
}
