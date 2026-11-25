import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/widgets/top_picks.dart';

Track _t(String id, String author, {String? artistId}) => Track(
  id: id,
  title: id,
  author: author,
  thumbnailUrl: 'art-$id',
  artistId: artistId,
);

void main() {
  test("l'artista principale conta una volta sola, anche in feat", () {
    final picks = topPicks(
      stats: const {
        'a': TrackStats(playCount: 3),
        'b': TrackStats(playCount: 5),
        'c': TrackStats(playCount: 4),
        'd': TrackStats(playCount: 1),
      },
      known: [
        _t('a', 'Yeat', artistId: 'UCyeat'),
        _t('b', 'Yeat & Nettspend'),
        _t('c', 'Nettspend'),
        _t('d', 'Kid Yugi'),
      ],
    );

    expect(picks.map((p) => p.artist), ['Yeat', 'Nettspend']);
    // Yeat: 3 + 5, e il seme e' il suo brano piu' ascoltato.
    expect(picks.first.plays, 8);
    expect(picks.first.seed.id, 'b');
    expect(picks.first.artistId, 'UCyeat');
    // Un solo ascolto non basta per una stazione.
    expect(picks.any((p) => p.artist == 'Kid Yugi'), isFalse);
  });
}
