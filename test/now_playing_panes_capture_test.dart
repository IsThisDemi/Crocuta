import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/lyrics.dart';
import 'package:crocuta/models/track.dart';
import 'package:crocuta/providers.dart';
import 'package:crocuta/screens/now_playing_screen.dart';
import 'package:crocuta/services/karaoke.dart';
import 'package:crocuta/services/player_state.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _track = Track(
  id: 'xyz',
  title: 'Corrente Ascensionale',
  author: 'Marea Bassa',
  thumbnailUrl: '',
);

const _next = [
  Track(
    id: 'a',
    title: 'Vento di Terra',
    author: 'Marea Bassa',
    thumbnailUrl: '',
  ),
  Track(id: 'b', title: 'Scogliera', author: 'Onde Corte', thumbnailUrl: ''),
  Track(id: 'c', title: 'Faro Spento', author: 'Marea Bassa', thumbnailUrl: ''),
];

final _lyrics = Lyrics(
  title: _track.title,
  artist: _track.author,
  lines: [
    for (var i = 0; i < 14; i++)
      LyricsLine(
        time: Duration(seconds: i * 6),
        text: 'Verso numero ${i + 1} del brano',
      ),
  ],
);

final _overrides = [
  playerProvider.overrideWith(
    () => FakePlayer(
      const PlayerState(
        queue: [_track, ..._next],
        currentIndex: 0,
        isPlaying: true,
        position: Duration(seconds: 32),
        duration: Duration(minutes: 2),
      ),
    ),
  ),
  backdropColorProvider(
    '',
  ).overrideWith((ref) async => const Color(0xFF1E4D6B)),
  upNextProvider('xyz|Marea Bassa').overrideWith((ref) async => <Track>[]),
  lyricsProvider(
    'Corrente Ascensionale|Marea Bassa',
  ).overrideWith((ref) async => _lyrics),
];

void main() {
  for (final pane in ['Lyrics', 'Queue', 'Equalizer']) {
    testWidgets('cattura: player con $pane', (tester) async {
      await capture(
        tester,
        const NowPlayingScreen(),
        name: 'player_${pane.toLowerCase()}',
        overrides: _overrides,
        interact: (tester) async {
          await tester.tap(find.byTooltip(pane));
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
        },
      );
    });
  }

  // Su una finestra larga testo e coda si affiancano al player invece di
  // prenderne il posto: a sinistra copertina e comandi, a destra il
  // pannello a tutta altezza.
  for (final pane in ['Lyrics', 'Queue']) {
    testWidgets('cattura: player largo con $pane', (tester) async {
      await capture(
        tester,
        const NowPlayingScreen(),
        name: 'player_${pane.toLowerCase()}_largo',
        size: const Size(1400, 880),
        overrides: _overrides,
        interact: (tester) async {
          await tester.tap(find.byTooltip(pane));
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
        },
      );
      // La colonna del player e' scivolata a sinistra, il pannello sta a
      // destra di lei: non sopra, non al centro.
      final art = tester.getRect(find.byTooltip('Previous'));
      final panel = tester.getRect(
        find.text(
          pane == 'Lyrics' ? 'Verso numero 1 del brano' : 'Vento di Terra',
        ),
      );
      expect(art.center.dx, lessThan(700));
      expect(panel.left, greaterThan(art.right));
    });
  }

  // Gli interruttori accesi si vedono nel pulsante "…", e il menu li
  // elenca tutti con il loro stato.
  testWidgets('cattura: menu degli interruttori', (tester) async {
    await capture(
      tester,
      const NowPlayingScreen(),
      name: 'player_menu',
      overrides: [
        // Il primo e' il player: qui ne serve uno con gli interruttori
        // accesi, e due override dello stesso provider non sono ammessi.
        ..._overrides.skip(1),
        playerProvider.overrideWith(
          () => FakePlayer(
            const PlayerState(
              queue: [_track, ..._next],
              currentIndex: 0,
              isPlaying: true,
              shuffle: true,
              repeat: RepeatMode.one,
              position: Duration(seconds: 32),
              duration: Duration(minutes: 2),
            ),
          ),
        ),
      ],
      interact: (tester) async {
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
        expect(find.byIcon(Icons.repeat_one), findsOneWidget);
        await tester.tap(find.byTooltip('More'));
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
    expect(find.text('Shuffle: on'), findsOneWidget);
    expect(find.text('Repeat: this song'), findsOneWidget);
    expect(find.text('AutoMix: off'), findsOneWidget);
    expect(find.text('Endless queue: off'), findsOneWidget);
    expect(find.text('Sleep timer…'), findsOneWidget);
  });

  // Il karaoke mentre prepara la base: il microfono si riempie.
  testWidgets('cattura: karaoke in preparazione', (tester) async {
    await capture(
      tester,
      const NowPlayingScreen(),
      name: 'player_sing_preparing',
      overrides: [
        ..._overrides,
        karaokeProvider.overrideWith(
          (ref) => const KaraokeState(enabled: true, preparing: 0.45),
        ),
      ],
      interact: (tester) async {
        await tester.tap(find.byTooltip('Lyrics'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
      },
    );
  });
}
