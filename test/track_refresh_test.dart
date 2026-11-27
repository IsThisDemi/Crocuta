import 'package:flutter_test/flutter_test.dart';
import 'package:crocuta/models/track.dart';

const _old = Track(
  id: 'x',
  title: 'CLUB TEST (con IvanBi, Diss Gacha) (con IvanBi e Diss Gacha)',
  author: 'Sala',
  duration: Duration(minutes: 2, seconds: 14),
  thumbnailUrl: 'https://img.youtube.com/vi/x/hqdefault.jpg',
  albumId: 'MPREb_vecchio',
);

void main() {
  test('prende il nuovo dove c\'e\'', () {
    const fresh = Track(
      id: 'x',
      title: 'CLUB TEST (con IvanBi, Diss Gacha)',
      author: 'Sala, IvanBi e Diss Gacha',
      thumbnailUrl: 'https://yt3.googleusercontent.com/quadrata',
      plays: '3,8 Mln riproduzioni',
    );
    final out = _old.refreshedFrom(fresh);
    expect(out.title, 'CLUB TEST (con IvanBi, Diss Gacha)');
    expect(out.author, 'Sala, IvanBi e Diss Gacha');
    expect(out.thumbnailUrl, contains('yt3.googleusercontent'));
    expect(out.plays, '3,8 Mln riproduzioni');
  });

  test('tiene il vecchio dove il nuovo non ha niente', () {
    // Un risultato di ricerca non porta l'id dell'album ne' la durata:
    // sostituire cancellerebbe dati che avevamo gia'.
    const fresh = Track(
      id: 'x',
      title: 'CLUB TEST',
      author: 'Sala',
      thumbnailUrl: 'https://yt3.googleusercontent.com/quadrata',
    );
    final out = _old.refreshedFrom(fresh);
    expect(out.albumId, 'MPREb_vecchio');
    expect(out.duration, const Duration(minutes: 2, seconds: 14));
  });

  test('una copertina di ripiego non scalza quella vera', () {
    const good = Track(
      id: 'x',
      title: 't',
      author: 'a',
      thumbnailUrl: 'https://yt3.googleusercontent.com/quadrata',
    );
    const withFallback = Track(
      id: 'x',
      title: 't',
      author: 'a',
      thumbnailUrl: 'https://img.youtube.com/vi/x/hqdefault.jpg',
    );
    expect(
      good.refreshedFrom(withFallback).thumbnailUrl,
      contains('yt3.googleusercontent'),
    );
    // Al contrario invece si aggiorna: meglio una copertina vera.
    expect(
      withFallback.refreshedFrom(good).thumbnailUrl,
      contains('yt3.googleusercontent'),
    );
  });

  test('un brano diverso non viene toccato', () {
    const other = Track(id: 'y', title: 'altro', author: 'b', thumbnailUrl: '');
    expect(_old.refreshedFrom(other).title, _old.title);
  });
}
