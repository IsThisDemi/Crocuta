import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/artist.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/screens/replay_story.dart';
import 'package:crocuta/services/replay.dart';

import 'support/capture.dart';

ReplaySummary _replay() {
  Track t(int i) => Track(
    id: 'id$i',
    title: 'A Very Long Song Title Number $i (feat. Somebody Else)',
    author: 'Artist With A Long Name $i',
    thumbnailUrl: 'https://example.com/$i.jpg',
  );
  return ReplaySummary(
    plays: 1622,
    seconds: 83700,
    songs: 485,
    tracks: [for (var i = 0; i < 8; i++) ReplayTrack(t(i), 60 - i, 4000 - i)],
    artists: [
      for (var i = 0; i < 6; i++)
        ReplayArtist(
          name: 'passengerprincess and a long name $i',
          artwork: 'https://example.com/a$i.jpg',
          plays: 60 - i,
          seconds: 4000 - i * 100,
        ),
    ],
    albums: [
      for (var i = 0; i < 3; i++)
        ReplayAlbum(
          AlbumCard(
            browseId: 'b$i',
            title: 'An Album With A Title That Goes On And On $i',
            subtitle: 'Artist $i',
            thumbnailUrl: 'https://example.com/al$i.jpg',
          ),
          20 - i,
        ),
    ],
  );
}

void main() {
  testWidgets('il Replay: tutte le schede, senza straripare', (tester) async {
    await capture(
      tester,
      const ReplayStoryScreen(period: ReplayPeriod.month),
      name: 'replay',
      overrides: [replayProvider.overrideWith((ref, p) => _replay())],
      interact: (t) async {
        // Si scorre fino all'ultima: ogni scheda viene costruita e
        // disposta, e un testo che straripa fa fallire il test.
        for (var i = 0; i < 6; i++) {
          await t.tap(find.byType(PageView), warnIfMissed: false);
          await t.tapAt(const Offset(380, 400));
          await t.pumpAndSettle();
        }
      },
    );
    expect(find.text('Share'), findsOneWidget);
  });
}
