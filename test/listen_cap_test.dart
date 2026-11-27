import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/services/storage_service.dart';
import 'package:crocuta/services/sync_service.dart';

void main() {
  // Il caso vero: un ascolto da 39 ore di un brano da 3 minuti, contato
  // dall'orologio con una notte di pausa dentro.
  const yFiDat = 'yfidat';
  const song = 3 * 60;
  const bogus = 39 * 3600 + 60;

  test('i dati gia\' salvati tornano sotto la durata del brano', () async {
    final dir = await Directory.systemTemp.createTemp('listens');
    addTearDown(() => dir.deleteSync(recursive: true));

    // Com'era l'archivio prima della correzione.
    Hive.init(dir.path);
    final log = await Hive.openBox('play_log');
    await log.addAll([
      [yFiDat, 1000, bogus],
      ['altro', 2000, 150],
    ]);
    final stats = await Hive.openBox('stats');
    await stats.put('plays', {
      yFiDat: {'count': 1, 'totalSeconds': bogus, 'lastPlayed': 1},
      'altro': {'count': 1, 'totalSeconds': 150, 'lastPlayed': 1},
    });
    final durations = await Hive.openBox('durations');
    await durations.put(yFiDat, song);
    await Hive.close();

    final storage = StorageService();
    await storage.init(path: dir.path);

    final fixed = storage.getPlayStats(yFiDat);
    expect(fixed['totalSeconds'], song + 30);
    expect(fixed['count'], 1);
    // Il brano giusto resta com'era.
    expect(storage.getPlayStats('altro')['totalSeconds'], 150);
    expect(storage.playLog.firstWhere((r) => r.$1 == yFiDat).$3, song + 30);

    // E un ascolto nuovo, anche se arrivasse sbagliato, non passa il tetto.
    await storage.recordPlay(
      yFiDat,
      listenDuration: const Duration(hours: 5),
      track: const Track(
        id: yFiDat,
        title: 'Y FI DAT',
        author: 'Central Cee',
        thumbnailUrl: '',
        duration: Duration(seconds: song),
      ),
    );
    expect(storage.getPlayStats(yFiDat)['totalSeconds'], 2 * (song + 30));
  });

  test('la sincronizzazione non riporta indietro l\'ascolto sbagliato', () {
    // Il Mac ha gia' corretto, l'altro dispositivo no: la fusione prende il
    // valore piu' alto, quindi il tetto deve valere anche li'.
    final track = {'id': yFiDat, 'duration': song};
    final out = SyncService.mergeForTest(
      local: {
        'stats': {
          yFiDat: {'count': 1, 'totalSeconds': song + 30, 'lastPlayed': 5},
        },
        'log': {
          yFiDat: [
            [1000, song + 30],
          ],
        },
        'statTracks': {yFiDat: track},
      },
      remote: {
        'stats': {
          yFiDat: {'count': 1, 'totalSeconds': bogus, 'lastPlayed': 5},
        },
        'log': {
          yFiDat: [
            [1000, bogus],
          ],
        },
        'statTracks': {yFiDat: track},
      },
    );
    expect((out['stats'] as Map)[yFiDat]['totalSeconds'], song + 30);
    expect((out['log'] as Map)[yFiDat], [
      [1000, song + 30],
    ]);
  });
}
