import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/artist.dart';
import 'package:yeen_music/screens/home_content.dart';
import 'package:yeen_music/services/follows_controller.dart';

NewRelease _r(String id, {DateTime? date, int? year}) => NewRelease(
  album: AlbumCard(browseId: id, title: id, subtitle: '', thumbnailUrl: ''),
  artistName: 'A',
  year: year,
  date: date,
);

void main() {
  test('dalla piu recente per data vera; senza data conta l anno', () {
    final list = [
      _r('vecchio', date: DateTime(2023, 3, 1)),
      _r('ieri', date: DateTime(2026, 10, 11)),
      _r('senza-niente'),
      _r('solo-anno', year: 2025),
      _r('settembre', date: DateTime(2026, 9, 2)),
    ]..sort((x, y) => y.sortKey.compareTo(x.sortKey));
    expect(list.map((r) => r.album.browseId), [
      'ieri',
      'settembre',
      'solo-anno',
      'vecchio',
      'senza-niente',
    ]);
  });

  test('il giorno per le uscite recenti, l anno per le altre', () {
    final now = DateTime(2026, 10, 12);
    expect(
      releaseSubtitle(_r('x', date: DateTime(2026, 10, 9)), now: now),
      'A · Oct 9',
    );
    expect(
      releaseSubtitle(
        _r('x', date: DateTime(2024, 5, 1)).withDate(DateTime(2024, 5, 1)),
        now: now,
      ),
      'A · 2024',
    );
    expect(releaseSubtitle(_r('x'), now: now), 'A');
  });
}
