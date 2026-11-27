import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/search_screen.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/widgets/video_card.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

/// I video nella ricerca: una categoria a parte, prima dei brani quando il
/// risultato principale e' un video.
class _Fixed extends SearchController {
  final SearchResult result;
  _Fixed(this.result);
  @override
  SearchResult build() => result;
}

Track video(int i) => Track(
  id: 'v$i',
  title: i == 0
      ? 'deko x itsoktocry - NINJA GAIDEN 忍者龍剣伝'
      : 'Remix numero $i (slowed + reverb)',
  author: i == 0 ? "De'Ko" : 'Canale $i',
  thumbnailUrl: '',
  duration: Duration(seconds: 128 + i * 7),
  plays: '${153 - i}K views',
  isVideo: true,
);

Track song(int i) => Track(
  id: 's$i',
  title: 'Canzone $i',
  author: 'Artista $i',
  thumbnailUrl: '',
);

void main() {
  for (final top in [true, false]) {
    testWidgets('ricerca con i video ${top ? 'in cima' : 'dopo i brani'}', (
      tester,
    ) async {
      final result = SearchResult(
        query: 'ninja gaiden deko',
        tracks: [for (var i = 0; i < 4; i++) song(i)],
        videos: [for (var i = 0; i < 6; i++) video(i)],
        topIsVideo: top,
      );
      await capture(
        tester,
        const SearchScreen(),
        name: top ? 'search-videos-top' : 'search-videos-after',
        overrides: [
          searchProvider.overrideWith(() => _Fixed(result)),
          playerProvider.overrideWith(() => FakePlayer(const PlayerState())),
        ],
      );
      expect(find.text('Videos'), findsOneWidget);
      expect(find.byType(VideoCard), findsWidgets);
      final videosY = tester.getTopLeft(find.text('Videos')).dy;
      final songsY = tester.getTopLeft(find.text('Songs')).dy;
      expect(videosY < songsY, top);
    });
  }

  test('un video salvato resta un video', () {
    final v = video(0);
    final back = Track.fromJson(v.toJson());
    expect(back.isVideo, isTrue);
    expect(Track.fromJson(song(0).toJson()).isVideo, isFalse);
    expect(song(0).toJson().containsKey('isVideo'), isFalse);
  });
}
