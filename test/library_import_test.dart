import 'package:flutter_test/flutter_test.dart';

import 'package:crocuta/models/track.dart';
import 'package:crocuta/services/library_import.dart';
import 'package:crocuta/services/library_views.dart';

Track _t(String id, String title, String author) =>
    Track(id: id, title: title, author: author, thumbnailUrl: '');

void main() {
  final crocuta = [
    _t('p', 'Passion', 'PinkPantheress'),
    _t('y', 'ON NOTHING', 'Yeat'),
  ];
  final dates = {'p': 5000000, 'y': 6000000};

  test('niente doppioni: stesso id, stesso brano con id diverso, ripetuti', () {
    final plan = planLibraryImport(
      existing: crocuta,
      existingAddedAt: dates,
      incoming: [
        _t('y', 'ON NOTHING', 'Yeat'), // stesso id
        // Lo stesso brano, preso dal videoclip.
        _t('p-video', 'Passion (Official Video)', 'PinkPantheress'),
        _t('a', 'After the Storm (feat. Tyler)', 'Kali Uchis'),
        _t('a2', 'After The Storm', 'Kali Uchis, Tyler'), // ripetuto
        _t('b', 'Homewrecker', 'MARINA'),
      ],
      now: 9000000,
    );
    expect(plan.tracks.map((t) => t.id), ['a', 'b']);
  });

  test('gli importati vengono dopo quelli di Crocuta, nel loro ordine', () {
    final plan = planLibraryImport(
      existing: crocuta,
      existingAddedAt: dates,
      incoming: [
        _t('a', 'Primo', 'X'),
        _t('b', 'Secondo', 'X'),
        _t('c', 'Terzo', 'X'),
      ],
      now: 9000000,
    );
    // Tutti prima del piu' vecchio di Crocuta, e in ordine decrescente.
    expect(plan.addedAt, [4999000, 4998000, 4997000]);

    final all = [...plan.tracks.reversed, ...crocuta];
    final merged = {
      ...dates,
      for (var i = 0; i < plan.tracks.length; i++)
        plan.tracks[i].id: plan.addedAt[i],
    };
    expect(recentlyAdded(all, merged).map((t) => t.id), [
      'y',
      'p',
      'a',
      'b',
      'c',
    ]);
  });

  test('senza piaciuti su Crocuta si parte da adesso', () {
    final plan = planLibraryImport(
      existing: const [],
      existingAddedAt: const {},
      incoming: [_t('a', 'Primo', 'X')],
      now: 9000000,
    );
    expect(plan.addedAt, [8999000]);
  });

  test('i piaciuti senza data restano sopra gli importati, nel loro ordine', () {
    final existing = [
      _t('nuovo', 'Nuovo', 'X'),
      _t('vecchio1', 'Vecchio uno', 'X'),
      _t('vecchio2', 'Vecchio due', 'X'),
    ];
    final plan = planLibraryImport(
      existing: existing,
      existingAddedAt: {'nuovo': 5000000},
      incoming: [_t('a', 'Importato', 'Y')],
      now: 9000000,
    );
    final merged = {
      'nuovo': 5000000,
      ...plan.datedExisting,
      'a': plan.addedAt.single,
    };
    final all = [...existing, ...plan.tracks];
    expect(recentlyAdded(all, merged).map((t) => t.id), [
      'nuovo',
      // Nell'ordine in cui "Recently Added" li mostrava gia'.
      'vecchio2',
      'vecchio1',
      'a',
    ]);
  });
}
