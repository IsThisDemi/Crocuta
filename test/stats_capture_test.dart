import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/providers.dart';
import 'package:yeen_music/screens/stats_screen.dart';

import 'support/capture.dart';
import 'support/fake_player.dart';

// Nomi inventati. Le copertine puntano a un URL che in test non risolve:
// serve proprio a verificare che il ripiego con l'iniziale regga, invece
// di lasciare un buco nella riga.
const _tracks = [
  Track(
    id: 'a',
    title: 'Corrente Ascensionale',
    author: 'Marea Bassa',
    thumbnailUrl: 'https://example.invalid/a.jpg',
  ),
  Track(
    id: 'b',
    title: 'Luce Radente',
    author: 'Marea Bassa',
    thumbnailUrl: 'https://example.invalid/b.jpg',
  ),
  Track(
    id: 'c',
    title: 'Campo Lungo',
    author: 'Vetro Sottile',
    thumbnailUrl: 'https://example.invalid/c.jpg',
  ),
  // Senza copertina: deve cadere sull'iniziale.
  Track(id: 'd', title: 'Nebbia', author: 'Terzo Piano', thumbnailUrl: ''),
];

const _stats = {
  'a': TrackStats(playCount: 12, totalSeconds: 2700),
  'b': TrackStats(playCount: 5, totalSeconds: 1200),
  'c': TrackStats(playCount: 9, totalSeconds: 2100),
  'd': TrackStats(playCount: 3, totalSeconds: 600),
};

class _FakeStats extends StatsController {
  @override
  Map<String, TrackStats> build() => _stats;
}

class _FakeRecents extends RecentlyPlayedController {
  @override
  List<Track> build() => _tracks;
}

void main() {
  testWidgets('cattura: statistiche', (tester) async {
    await capture(
      tester,
      const StatsScreen(),
      name: 'stats',
      overrides: [
        // listBottomPadding osserva il player, che senza questo aprirebbe
        // libmpv e fallirebbe con "MediaKit.ensureInitialized".
        playerProvider.overrideWith(FakePlayer.new),
        statsProvider.overrideWith(_FakeStats.new),
        recentlyPlayedProvider.overrideWith(_FakeRecents.new),
      ],
    );
  });
}
