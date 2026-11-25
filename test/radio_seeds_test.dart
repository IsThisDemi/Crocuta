import 'package:flutter_test/flutter_test.dart';

import 'package:yeen_music/models/track.dart';
import 'package:yeen_music/services/radio_seeds.dart';

Track t(String id) => Track(id: id, title: id, author: 'x', thumbnailUrl: '');

void main() {
  final queue = [t('a'), t('b'), t('c'), t('r1'), t('r2'), t('r3')];
  const radio = {'r1', 'r2', 'r3'};

  test('prima la raccolta, dal brano piu\' vicino a quello in corso', () {
    // In corso r2: la radio non riparte da r2 (un simile del simile), ma
    // da c, l'ultimo della raccolta.
    expect(
      pickRadioSeed(
        queue: queue,
        current: 4,
        radioIds: radio,
        liked: const {},
        used: const {},
      )!.id,
      'c',
    );
    expect(
      pickRadioSeed(
        queue: queue,
        current: 4,
        radioIds: radio,
        liked: const {},
        used: const {'c'},
      )!.id,
      'b',
    );
  });

  test(
    'finita la raccolta, solo i brani della radio ascoltati fino in fondo',
    () {
      const used = {'a', 'b', 'c'};
      // r2 saltato, r1 ascoltato: si riparte da r1.
      expect(
        pickRadioSeed(
          queue: queue,
          current: 4,
          radioIds: radio,
          liked: const {'r1'},
          used: used,
        )!.id,
        'r1',
      );
      // Nessuno ascoltato fino in fondo: nessun punto di partenza.
      expect(
        pickRadioSeed(
          queue: queue,
          current: 4,
          radioIds: radio,
          liked: const {},
          used: used,
        ),
        isNull,
      );
    },
  );

  test('dalla radio si scartano i brani in coda e quelli sentiti da poco', () {
    final pool = [t('x'), t('a'), t('y'), t('x'), t('z')];
    final out = freshRadio(pool, inQueue: {'a'}, recentlyHeard: {'z'});
    expect([for (final x in out) x.id], ['x', 'y']);
  });

  test('ascoltato fino in fondo: 80%, o a mezzo minuto dalla fine', () {
    const len = Duration(minutes: 3);
    expect(listenedThrough(const Duration(seconds: 150), len), isTrue);
    expect(listenedThrough(const Duration(seconds: 20), len), isFalse);
    // Con AutoMix il brano esce 25 secondi prima: vale lo stesso.
    expect(listenedThrough(const Duration(seconds: 155), len), isTrue);
  });
}
