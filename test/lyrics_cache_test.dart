import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/lyrics.dart';
import 'package:yeen_music/services/storage_service.dart';

void main() {
  test(
    'un testo salvato torna uguale, anche senza tempi e in ordine',
    () async {
      final dir = await Directory.systemTemp.createTemp('lyrics_cache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = StorageService();
      await storage.init(path: dir.path);

      // Da Genius: tutte le righe a zero. Rileggerle da un LRC le avrebbe
      // riordinate a caso; il salvataggio deve tenerle come sono.
      final plain = Lyrics(
        title: 'Vento di Terra',
        artist: 'Onde Corte',
        lines: [
          for (var i = 0; i < 30; i++)
            LyricsLine(time: Duration.zero, text: 'riga $i'),
        ],
      );
      final synced = Lyrics.parse(
        '[00:12.30]prima\n[00:15.00]seconda',
        title: 'Faro',
        artist: 'Marea',
      );

      await storage.saveLyrics('Vento di Terra|Onde Corte', plain.toJson());
      await storage.saveLyrics('Faro|Marea', synced.toJson());

      final back = Lyrics.fromJson(
        storage.cachedLyrics('Vento di Terra|Onde Corte')!,
      );
      expect(
        [for (final l in back.lines) l.text],
        [for (var i = 0; i < 30; i++) 'riga $i'],
      );

      final backSynced = Lyrics.fromJson(storage.cachedLyrics('Faro|Marea')!);
      expect(backSynced.isSynced, isTrue);
      expect(
        backSynced.lines.first.time,
        const Duration(seconds: 12, milliseconds: 300),
      );
      expect(backSynced.lines.last.text, 'seconda');

      expect(storage.cachedLyrics('Mai|Sentito'), isNull);
    },
  );
}
