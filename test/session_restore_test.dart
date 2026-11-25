import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/services/storage_service.dart';

const _queue = [
  Track(id: 'a', title: 'Primo', author: 'Tizio', thumbnailUrl: ''),
  Track(id: 'b', title: 'Secondo', author: 'Caio', thumbnailUrl: ''),
];

void main() {
  late Directory dir;
  late StorageService storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('demus_test');
    storage = StorageService();
    await storage.init(path: dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('la sessione salvata torna indietro identica', () async {
    await storage.saveQueue(_queue);
    await storage.savePlaybackSession(
      index: 1,
      position: const Duration(seconds: 90),
      duration: const Duration(seconds: 210),
      shuffle: true,
      repeat: 'all',
      crossfade: const Duration(seconds: 5),
      radio: true,
    );

    expect(storage.savedQueue.map((t) => t.id), ['a', 'b']);

    final s = storage.playbackSession;
    expect(s['index'], 1);
    expect(s['positionMs'], 90000);
    expect(s['durationMs'], 210000);
    expect(s['shuffle'], true);
    expect(s['repeat'], 'all');
    expect(s['crossfadeMs'], 5000);
    expect(s['radio'], true);
  });

  test('senza sessione salvata non si ripristina nulla', () {
    // Il caso del primo avvio: deve restare vuoto, non esplodere.
    expect(storage.savedQueue, isEmpty);
    expect(storage.playbackSession, isEmpty);
  });

  test('svuotare la sessione cancella anche la coda', () async {
    await storage.saveQueue(_queue);
    await storage.savePlaybackSession(
      index: 0,
      position: Duration.zero,
      duration: Duration.zero,
      shuffle: false,
      repeat: 'off',
      crossfade: Duration.zero,
      radio: false,
    );

    await storage.clearPlaybackSession();

    expect(storage.playbackSession, isEmpty);
    // Una coda orfana farebbe riapparire il mini player con un brano che
    // l'utente aveva appena rimosso.
    expect(storage.savedQueue, isEmpty);
  });

  test('i guadagni dell\'equalizzatore sopravvivono al riavvio', () async {
    await storage.saveEqGains([3, -2, 0, 1.5, 6]);
    expect(storage.eqGains, [3, -2, 0, 1.5, 6]);
  });
}
