import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crocuta/services/youtube_service.dart';

void main() {
  // Registrate da music.youtube.com.
  final moods = File('test/fixtures/moods_and_genres.json').readAsStringSync();
  final chill = File('test/fixtures/category_chill.json').readAsStringSync();

  Future<T> withResponses<T>(Future<T> Function(YouTubeService) run) {
    final client = MockClient((req) async {
      final body = req.body;
      return http.Response(
        body.contains('FEmusic_moods_and_genres_category') ? chill : moods,
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return http.runWithClient(() => run(YouTubeService()), () => client);
  }

  test('umori e generi, ognuno col suo colore', () async {
    final groups = await withResponses((s) => s.getCategories());
    expect(groups.map((g) => g.title), ['Moods & moments', 'Genres']);
    expect(groups.first.items.first.title, 'Chill');
    expect(groups.first.items.first.params, isNotEmpty);
    expect(groups.first.items.first.color, isNot(0xFF3A3A46));
    expect(groups[1].items.length, 25);
  });

  test('una categoria aperta: file di playlist', () async {
    final shelves = await withResponses((s) => s.getCategory('x'));
    expect(shelves.first.$1, 'Coffee shop blends');
    expect(shelves.first.$2.first.title, 'Coffee Shop Blend');
    expect(shelves.first.$2.first.browseId, startsWith('VL'));
  });

  test("le schede dei dischi dicono l'artista, non solo il tipo", () {
    expect(
      YouTubeService.cardSubtitle('Single • Elysia Vale'),
      'Elysia Vale · Single',
    );
    expect(YouTubeService.cardSubtitle('Album • A • 2026'), 'A · 2026 · Album');
    expect(YouTubeService.cardSubtitle('Chart'), 'Chart');
    expect(
      YouTubeService.cardSubtitle('Playlist • YouTube Music'),
      'Playlist · YouTube Music',
    );
  });
}
