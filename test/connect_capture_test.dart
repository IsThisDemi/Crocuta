import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/services/connect.dart';
import 'package:yeen_music/services/player_state.dart';
import 'package:yeen_music/widgets/connect_views.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

const _mac = ConnectDevice(
  id: 'm',
  name: 'MacBook Pro di Alex',
  platform: 'macos',
  hosts: const ['192.168.1.10'],
  port: 5000,
);

const _song = Track(
  id: 's',
  title: 'Crash Out',
  author: 'Tinashe',
  thumbnailUrl: '',
  duration: Duration(minutes: 3, seconds: 10),
);

void main() {
  testWidgets('cattura: telecomando', (tester) async {
    await capture(
      tester,
      RemoteScreen(
        device: _mac,
        preview: RemoteState(
          device: _mac.name,
          track: _song,
          playing: true,
          position: const Duration(seconds: 64),
          duration: const Duration(minutes: 3, seconds: 10),
          volume: 60,
          at: DateTime.now(),
        ),
      ),
      name: 'connect_remote',
      overrides: [
        playerProvider.overrideWith(
          () => FakePlayer(const PlayerState(queue: [_song], currentIndex: 0)),
        ),
        backdropColorProvider(
          '',
        ).overrideWith((ref) async => const Color(0xFF3B2A5A)),
      ],
    );
    expect(find.text('Play Here'), findsOneWidget);
  });

  testWidgets('cattura: foglio dei dispositivi', (tester) async {
    await capture(
      tester,
      Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => showConnectSheet(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
      name: 'connect_sheet',
      overrides: [
        connectServiceProvider.overrideWith((ref) {
          final s = ConnectService(ref);
          s.devices.value = const [_mac];
          return s;
        }),
      ],
      interact: (tester) async {
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
    expect(find.text('This device'), findsOneWidget);
  });
}
