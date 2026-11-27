import 'package:flutter_test/flutter_test.dart';
import 'package:crocuta/screens/artist_screen.dart';

void main() {
  test('una colonna su telefono', () {
    expect(topSongColumns(430, 5), 1);
  });
  test('cinque brani su una finestra larga: due colonne, non tre', () {
    expect(topSongColumns(1100, 5), 2);
  });
  test('tanti brani su una finestra larga: tre colonne', () {
    expect(topSongColumns(1100, 10), 3);
  });
  test('due colonne a meta\' strada', () {
    expect(topSongColumns(800, 10), 2);
  });
}
