import 'package:flutter_test/flutter_test.dart';
import 'package:crocuta/services/sync_service.dart';

Map<String, dynamic> _track(String id, {String title = 't'}) => {
  'id': id,
  'title': title,
  'author': 'a',
  'thumbnailUrl': 'https://yt3.googleusercontent.com/$id',
};

Map<String, dynamic> _side({
  List<String> favs = const [],
  Map<String, int> favMarks = const {},
  Map<String, int> favGraves = const {},
  List<Map<String, dynamic>> playlists = const [],
  Map<String, int> plMarks = const {},
  Map<String, int> plGraves = const {},
  Map<String, dynamic> stats = const {},
  List<Map<String, dynamic>> followed = const [],
  Map<String, int> arMarks = const {},
  Map<String, int> arGraves = const {},
}) => {
  'favorites': [for (final id in favs) _track(id)],
  'recent': <dynamic>[],
  'playlists': playlists,
  'followed': followed,
  'stats': stats,
  'marks': {
    'fav': favMarks,
    'recent': <String, int>{},
    'pl': plMarks,
    'artist': arMarks,
  },
  'graves': {
    'fav': favGraves,
    'recent': <String, int>{},
    'pl': plGraves,
    'artist': arGraves,
  },
};

List<String> _ids(Map<String, dynamic> out, String key) => [
  for (final t in out[key] as List) (t as Map)['id'] as String,
];

void main() {
  test('i preferiti dei due dispositivi si uniscono', () {
    final out = SyncService.mergeForTest(
      local: _side(favs: ['a'], favMarks: {'a': 100}),
      remote: _side(favs: ['b'], favMarks: {'b': 200}),
    );
    expect(_ids(out, 'favorites').toSet(), {'a', 'b'});
  });

  test('una cancellazione piu\' recente vince sull\'aggiunta', () {
    // Il caso che rompe le sincronizzazioni ingenue: il dispositivo
    // rimasto indietro ha ancora il preferito e lo rimanderebbe su.
    final out = SyncService.mergeForTest(
      local: _side(favs: ['a'], favMarks: {'a': 100}),
      remote: _side(favGraves: {'a': 300}),
    );
    expect(_ids(out, 'favorites'), isEmpty);
  });

  test('una riaggiunta dopo la cancellazione vince a sua volta', () {
    final out = SyncService.mergeForTest(
      local: _side(favs: ['a'], favMarks: {'a': 500}),
      remote: _side(favGraves: {'a': 300}),
    );
    expect(_ids(out, 'favorites'), ['a']);
  });

  test('la fusione e\' stabile: rifarla non cambia il risultato', () {
    // Due dispositivi che si sincronizzano a turno devono convergere,
    // non oscillare.
    final first = SyncService.mergeForTest(
      local: _side(favs: ['a'], favMarks: {'a': 100}),
      remote: _side(favs: ['b'], favMarks: {'b': 200}, favGraves: {'c': 50}),
    );
    final second = SyncService.mergeForTest(local: first, remote: first);
    expect(_ids(second, 'favorites').toSet(), _ids(first, 'favorites').toSet());
    expect(second['graves'], first['graves']);
  });

  test('di una playlist vince la versione piu\' recente, intera', () {
    final out = SyncService.mergeForTest(
      local: _side(
        playlists: [
          {
            'id': 'p1',
            'name': 'Vecchia',
            'tracks': [_track('a')],
          },
        ],
        plMarks: {'p1': 100},
      ),
      remote: _side(
        playlists: [
          {
            'id': 'p1',
            'name': 'Nuova',
            'tracks': [_track('a'), _track('b')],
          },
        ],
        plMarks: {'p1': 900},
      ),
    );
    final pls = out['playlists'] as List;
    expect(pls, hasLength(1));
    expect((pls.first as Map)['name'], 'Nuova');
    expect(((pls.first as Map)['tracks'] as List), hasLength(2));
  });

  test('una playlist cancellata non torna', () {
    final out = SyncService.mergeForTest(
      local: _side(
        playlists: [
          {'id': 'p1', 'name': 'x', 'tracks': <dynamic>[]},
        ],
        plMarks: {'p1': 100},
      ),
      remote: _side(plGraves: {'p1': 400}),
    );
    expect(out['playlists'], isEmpty);
  });

  test('le statistiche prendono il massimo, non la somma', () {
    // Sommare conterebbe due volte gli ascolti gia' sincronizzati, e il
    // numero crescerebbe da solo a ogni passata.
    final out = SyncService.mergeForTest(
      local: _side(
        stats: {
          'a': {'count': 5, 'totalSeconds': 300, 'lastPlayed': 10},
        },
      ),
      remote: _side(
        stats: {
          'a': {'count': 3, 'totalSeconds': 900, 'lastPlayed': 99},
        },
      ),
    );
    final a = (out['stats'] as Map)['a'] as Map;
    expect(a['count'], 5);
    expect(a['totalSeconds'], 900);
    expect(a['lastPlayed'], 99);
  });

  test('senza configurazione resta spenta', () {
    expect(SyncService.isConfigured, isFalse);
  });

  test('gli artisti seguiti si uniscono, e smettere di seguire vince', () {
    final out = SyncService.mergeForTest(
      local: _side(
        followed: [
          {'browseId': 'UC1', 'name': 'Uno'},
        ],
        arMarks: {'UC1': 100},
      ),
      remote: _side(
        followed: [
          {'browseId': 'UC2', 'name': 'Due'},
        ],
        arMarks: {'UC2': 200},
        arGraves: {'UC1': 300},
      ),
    );
    final ids = [
      for (final a in out['followed'] as List) (a as Map)['browseId'],
    ];
    expect(ids, ['UC2']);
  });

  test(
    "gli ascolti dei due dispositivi si uniscono, senza contarli due volte",
    () {
      final mac = {
        ..._side(),
        'log': {
          'a': [
            [100, 200],
            [300, 180],
          ],
        },
        'statTracks': {'a': _track('a', title: 'dal Mac')},
      };
      final phone = {
        ..._side(),
        'log': {
          // Lo stesso ascolto delle 300, gia' tornato da Drive, e uno nuovo.
          'a': [
            [300, 180],
            [500, 60],
          ],
          'b': [
            [400, 120],
          ],
        },
        'statTracks': {'b': _track('b', title: 'dal telefono')},
      };

      final once = SyncService.mergeForTest(local: mac, remote: phone);
      final log = once['log'] as Map;
      expect(log['a'], [
        [100, 200],
        [300, 180],
        [500, 60],
      ]);
      expect(log['b'], [
        [400, 120],
      ]);
      // Il Mac ora sa che brano e' quello ascoltato sul telefono.
      expect((once['statTracks'] as Map).keys, containsAll(['a', 'b']));

      // Una seconda passata con quello che e' gia' su Drive non aggiunge
      // niente: e' il difetto che una somma avrebbe avuto.
      final twice = SyncService.mergeForTest(local: once, remote: once);
      expect(twice['log'], once['log']);
    },
  );

  test('un dispositivo vecchio, senza registro, non lo cancella', () {
    final withLog = {
      ..._side(),
      'log': {
        'a': [
          [100, 200],
        ],
      },
    };
    final out = SyncService.mergeForTest(local: withLog, remote: _side());
    expect((out['log'] as Map)['a'], [
      [100, 200],
    ]);
  });
}
