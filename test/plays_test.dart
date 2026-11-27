import 'package:flutter_test/flutter_test.dart';
import 'package:crocuta/models/track.dart';

Track _t(String? plays) =>
    Track(id: 'x', title: 't', author: 'a', thumbnailUrl: '', plays: plays);

void main() {
  test('la parola finale sparisce, il numero resta', () {
    // Stringhe reali restituite da YouTube Music con hl=it.
    expect(_t('3,8 Mln riproduzioni').playsShort, '3,8 Mln');
    expect(_t('12 Mln riproduzioni').playsShort, '12 Mln');
    expect(_t('1,2 Mln di riproduzioni').playsShort, '1,2 Mln');
    expect(_t('987 mila riproduzioni').playsShort, '987 mila');
    expect(_t('4.1M plays').playsShort, '4.1M');
  });

  test('senza dato non si mostra niente', () {
    expect(_t(null).playsShort, isNull);
    expect(_t('').playsShort, isNull);
  });

  test('una stringa senza la parola resta intera', () {
    // Meglio mostrarla com'e' che restituire il vuoto.
    expect(_t('7 Mln').playsShort, '7 Mln');
  });
}
