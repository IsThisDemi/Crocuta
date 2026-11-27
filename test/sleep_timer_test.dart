import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/providers.dart';
import 'package:crocuta/services/player_controller.dart';
import 'package:crocuta/services/player_state.dart';
import 'package:crocuta/services/sleep_timer.dart';

class RecordingPlayer extends PlayerController {
  int fades = 0;

  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> fadeOutAndPause({
    Duration fade = const Duration(seconds: 8),
  }) async => fades++;
}

void main() {
  test('i minuti rimasti si arrotondano per eccesso', () {
    final now = DateTime(2026, 9, 23, 22);
    int? left(Duration d) => SleepTimer.at(now.add(d)).minutesLeft(now);

    expect(left(const Duration(minutes: 15)), 15);
    // "1 min" fino all'ultimo secondo, mai "0 min" a musica accesa.
    expect(left(const Duration(seconds: 59)), 1);
    expect(left(const Duration(seconds: 1)), 1);
    expect(left(Duration.zero), 0);
  });

  testWidgets('scaduti i minuti, sfuma e mette in pausa', (tester) async {
    final player = RecordingPlayer();
    final c = ProviderContainer(
      overrides: [playerProvider.overrideWith(() => player)],
    );
    addTearDown(c.dispose);

    c.read(sleepTimerProvider.notifier).setMinutes(5);
    expect(c.read(sleepTimerProvider)?.endsAt, isNotNull);

    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(player.fades, 0);

    await tester.pump(const Duration(seconds: 2));
    expect(player.fades, 1);
    // Scattato, il timer non c'e' piu'.
    expect(c.read(sleepTimerProvider), isNull);
  });

  testWidgets('fine brano: lo chiede al player, che sa quando finisce', (
    tester,
  ) async {
    final player = RecordingPlayer();
    final c = ProviderContainer(
      overrides: [playerProvider.overrideWith(() => player)],
    );
    addTearDown(c.dispose);
    c.read(playerProvider);

    c.read(sleepTimerProvider.notifier).setEndOfTrack();
    expect(player.pauseAtEndOfTrack, isTrue);
    expect(c.read(sleepTimerProvider)?.endOfTrack, isTrue);

    // Quando il player si ferma, il timer si spegne da se'.
    player.onPausedAtEndOfTrack?.call();
    expect(c.read(sleepTimerProvider), isNull);
  });

  testWidgets('annullare spegne tutto, anche la fine brano', (tester) async {
    final player = RecordingPlayer();
    final c = ProviderContainer(
      overrides: [playerProvider.overrideWith(() => player)],
    );
    addTearDown(c.dispose);
    c.read(playerProvider);

    final timer = c.read(sleepTimerProvider.notifier);
    timer.setEndOfTrack();
    timer.cancel();
    expect(player.pauseAtEndOfTrack, isFalse);

    timer.setMinutes(1);
    timer.cancel();
    await tester.pump(const Duration(minutes: 2));
    expect(player.fades, 0, reason: 'un timer annullato non deve scattare');
  });

  testWidgets('cambiare modo sostituisce il precedente', (tester) async {
    final player = RecordingPlayer();
    final c = ProviderContainer(
      overrides: [playerProvider.overrideWith(() => player)],
    );
    addTearDown(c.dispose);
    c.read(playerProvider);

    final timer = c.read(sleepTimerProvider.notifier);
    timer.setMinutes(1);
    timer.setEndOfTrack();
    await tester.pump(const Duration(minutes: 2));

    // Il timer a minuti non scatta piu': ora vale la fine del brano.
    expect(player.fades, 0);
    expect(player.pauseAtEndOfTrack, isTrue);
  });
}
