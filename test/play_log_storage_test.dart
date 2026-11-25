import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/services/storage_service.dart';

void main() {
  test('il registro va e torna dalla forma della sincronizzazione', () async {
    final dir = await Directory.systemTemp.createTemp('log');
    final storage = StorageService();
    await storage.init(path: dir.path);

    const local = Track(id: 'a', title: 'Mio', author: 'x', thumbnailUrl: '');
    await storage.recordPlay(
      'a',
      listenDuration: const Duration(seconds: 90),
      track: local,
    );
    final mine = storage.playLogByTrack['a']!.single;

    await storage.replacePlayLog({
      'a': [
        mine,
        [mine[0] + 1000, 30],
      ],
      'b': [
        [mine[0] - 1000, 45],
      ],
    });
    final log = storage.playLog;
    expect(log.length, 3);
    // In ordine di tempo, come se fossero stati registrati qui.
    expect(log.map((e) => e.$1), ['b', 'a', 'a']);
    expect(log.first.$3, 45);

    await storage.addStatTracks({
      'a': const Track(
        id: 'a',
        title: 'Altro',
        author: 'x',
        thumbnailUrl: '',
      ).toJson(),
      'b': const Track(
        id: 'b',
        title: 'Nuovo',
        author: 'y',
        thumbnailUrl: '',
      ).toJson(),
    });
    // Quello noto qui resta com'e'; quello nuovo arriva.
    expect(storage.statTracks['a']!.title, 'Mio');
    expect(storage.statTracks['b']!.title, 'Nuovo');
  });
}
