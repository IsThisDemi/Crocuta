import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/lyrics.dart';
import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/lyrics_screen.dart';
import 'package:yeen_music/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _track = Track(
  id: 'xyz',
  title: 'Corrente Ascensionale',
  author: 'Marea Bassa',
  thumbnailUrl: '',
);

/// Versi inventati, uno volutamente lungo: con l'altezza di riga fissa di
/// prima veniva tagliato a meta'.
final _lyrics = Lyrics(
  title: _track.title,
  artist: _track.author,
  lines: [
    for (var i = 0; i < 14; i++)
      LyricsLine(
        time: Duration(seconds: i * 6),
        text: i == 5
            ? 'Un verso lungo che non sta su una riga sola e deve andare a '
                  'capo senza farsi tagliare via la seconda meta\''
            : 'Verso numero ${i + 1} del brano',
      ),
  ],
);

void main() {
  testWidgets('cattura: testi con il verso in corso al centro', (tester) async {
    await capture(
      tester,
      const LyricsScreen(title: 'Corrente Ascensionale', artist: 'Marea Bassa'),
      name: 'testi',
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(
            const PlayerState(
              queue: [_track],
              currentIndex: 0,
              isPlaying: true,
              // Sul verso lungo, quello che prima si tagliava.
              position: Duration(seconds: 32),
              duration: Duration(minutes: 2),
            ),
          ),
        ),
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
        lyricsProvider(
          'Corrente Ascensionale|Marea Bassa',
        ).overrideWith((ref) async => _lyrics),
      ],
    );
  });
}
