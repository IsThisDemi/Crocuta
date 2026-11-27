import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/services/library_tidy.dart';
import 'package:crocuta/services/storage_service.dart';
import 'package:crocuta/services/youtube_service.dart';

const _video = Track(
  id: 'vid',
  title: 'Sfera Ebbasta - Lontano (Official Video)',
  author: 'Sfera Ebbasta',
  thumbnailUrl: 'https://i.ytimg.com/vi/vid/hq720.jpg',
);

const _song = Track(
  id: 'song',
  title: 'Paris Hilton',
  author: 'Nettspend',
  thumbnailUrl: 'https://lh3.googleusercontent.com/cover=w544',
);

class _Fake extends YouTubeService {
  final asked = <String>[];

  @override
  Future<Track?> songVersionFor(Track track) async {
    asked.add(track.id);
    if (track.id != 'vid') return null;
    return track.refreshedFrom(
      const Track(
        id: 'vid',
        title: 'Lontano',
        author: 'Sfera Ebbasta',
        thumbnailUrl: 'https://lh3.googleusercontent.com/lontano=w544',
        albumName: 'Famoso',
      ),
    );
  }
}

void main() {
  test('riconosce un video salvato', () {
    expect(looksLikeVideo(_video), isTrue);
    expect(looksLikeVideo(_song), isFalse);
    expect(
      looksLikeVideo(_song.copyWith(title: 'LOCO (Official Audio)')),
      isTrue,
    );
  });

  test(
    'i video in libreria diventano canzoni, le canzoni non si toccano',
    () async {
      final dir = await Directory.systemTemp.createTemp('tidy');
      final storage = StorageService();
      await storage.init(path: dir.path);
      await storage.addFavorite(_video);
      await storage.addFavorite(_song);
      await storage.addRecentlyPlayed(_video);

      final service = _Fake();
      var changed = false;
      final fixed = await tidyLibrary(
        storage: storage,
        service: service,
        onChanged: () => changed = true,
        pause: Duration.zero,
      );
      expect(changed, isTrue);
      expect(fixed, 1);
      expect(service.asked, ['vid'], reason: 'una canzone non si controlla');

      final fav = storage.favorites.firstWhere((t) => t.id == 'vid');
      expect(fav.title, 'Lontano');
      expect(fav.thumbnailUrl, contains('lontano'));
      expect(storage.recentlyPlayed.first.title, 'Lontano');
    },
  );
}
