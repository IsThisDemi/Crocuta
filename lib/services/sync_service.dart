import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'storage_service.dart';
import 'listen_cap.dart';

/// Sincronizza libreria e ascolti fra i tuoi dispositivi, passando da una
/// Web App di Google Apps Script che scrive su un file del tuo Drive.
///
/// Perche' Apps Script: non c'e' niente da pagare ne' da mantenere, gira
/// sul tuo account e i dati restano su Drive tuo. Il limite da conoscere e'
/// che una Web App pubblicata "accessibile a chiunque" e' protetta solo
/// dalla segretezza dell'URL: il segreto condiviso aggiunge una barriera,
/// ma non e' autenticazione vera. Va bene per preferiti e ascolti, non per
/// qualcosa che ti dispiacerebbe far leggere.
///
/// Indirizzo e segreto NON stanno nel codice: ognuno li scrive nelle
/// Impostazioni del proprio dispositivo, e l'app si puo' dare agli amici
/// senza che finiscano tutti sul Drive di chi l'ha compilata. Un `.env`
/// al momento della compilazione (`--dart-define-from-file=.env`) fa solo
/// da valore iniziale, la prima volta che l'app parte.
class SyncService {
  static const _envUrl = String.fromEnvironment('YEEN_SYNC_URL');
  static const _envSecret = String.fromEnvironment('YEEN_SYNC_SECRET');

  /// La configurazione in uso; le Impostazioni e la Libreria la ascoltano.
  static final config = ValueNotifier<SyncConfig>(const SyncConfig('', ''));

  final StorageService _storage;
  final http.Client _client;

  SyncService(this._storage, {http.Client? client})
    : _client = client ?? http.Client();

  /// Spenta finche' non ci sono indirizzo e segreto.
  static bool get isConfigured => config.value.isComplete;

  /// Il segreto in uso: lo usa anche Crocuta Connect per riconoscere i
  /// dispositivi della stessa persona.
  static String get secret => config.value.secret;

  /// Carica la configurazione salvata. La prima volta, se la build porta
  /// un `.env`, lo si adotta e lo si salva: da li' in poi vale quello che
  /// c'e' sul dispositivo, anche con una build che non ne ha.
  static Future<void> load(StorageService storage) async {
    var url = storage.syncUrl;
    var secret = storage.syncSecret;
    if (url == null && secret == null && _envUrl.isNotEmpty) {
      url = _envUrl;
      secret = _envSecret;
      await storage.setSyncConfig(url, secret);
    }
    config.value = SyncConfig(url ?? '', secret ?? '');
  }

  /// Salva una configurazione nuova; vuota spegne la sincronizzazione.
  static Future<void> configure(StorageService storage, SyncConfig c) async {
    await storage.setSyncConfig(c.url, c.secret);
    config.value = c;
  }

  /// Legge il remoto, fonde, riscrive in locale e rimanda su il risultato.
  ///
  /// Una passata sola per entrambe le direzioni: due dispositivi che si
  /// sincronizzano a turno convergono sullo stesso stato, perche' ognuno
  /// carica gia' il risultato della fusione e non solo la propria meta'.
  Future<SyncOutcome> sync() async {
    if (!isConfigured) return SyncOutcome.disabled;
    try {
      final remote = await _pull();
      final merged = _merge(local: _snapshot(), remote: remote);
      await _restore(merged);
      await _push(merged);
      await _storage.setLastSync(DateTime.now());
      return SyncOutcome.done;
    } catch (e) {
      developer.log('sync fallita: $e');
      return SyncOutcome.failed;
    }
  }

  // -------------------------------------------------------------------
  // Trasporto
  // -------------------------------------------------------------------

  Future<Map<String, dynamic>> _pull() async {
    final c = config.value;
    final uri = Uri.parse(
      c.url,
    ).replace(queryParameters: {'secret': c.secret, 'action': 'get'});
    final resp = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('il server ha risposto ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map) throw Exception('risposta non riconosciuta');
    return Map<String, dynamic>.from(body);
  }

  Future<void> _push(Map<String, dynamic> data) async {
    final c = config.value;
    final uri = Uri.parse(c.url);
    // Apps Script risponde con un redirect alla propria origine: il client
    // lo segue da se', ma solo se il corpo e' semplice testo.
    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode({'secret': c.secret, 'action': 'put', 'data': data}),
        )
        .timeout(const Duration(seconds: 20));
    // Si accetta qualunque esito sotto 400, non solo 200: Apps Script
    // risponde alla POST con un redirect verso googleusercontent e una
    // pagina HTML, mentre la scrittura e' gia' avvenuta. Pretendere 200
    // avrebbe fatto fallire una sincronizzazione riuscita.
    if (resp.statusCode >= 400) {
      throw Exception(
        'il server ha rifiutato il salvataggio (${resp.statusCode})',
      );
    }
  }

  // -------------------------------------------------------------------
  // Istantanea locale
  // -------------------------------------------------------------------

  Map<String, dynamic> _snapshot() => {
    'version': 1,
    'favorites': [for (final t in _storage.favorites) t.toJson()],
    'recent': [for (final t in _storage.recentlyPlayed) t.toJson()],
    'playlists': _storage.playlists,
    'followed': _storage.followed,
    'stats': _storage.getAllPlayStats(),
    'log': _storage.playLogByTrack,
    'statTracks': _storage.statTracksJson,
    'marks': {
      'fav': _storage.marks('fav'),
      'recent': _storage.marks('recent'),
      'pl': _storage.marks('pl'),
      'artist': _storage.marks('artist'),
    },
    'graves': {
      'fav': _storage.graves('fav'),
      'recent': _storage.graves('recent'),
      'pl': _storage.graves('pl'),
      'artist': _storage.graves('artist'),
    },
  };

  // -------------------------------------------------------------------
  // Fusione
  // -------------------------------------------------------------------

  static Map<String, int> _ts(Map<String, dynamic> side, String box, String k) {
    final b = (side[box] as Map?) ?? const {};
    final inner = (b[k] as Map?) ?? const {};
    return {
      for (final e in inner.entries)
        e.key.toString(): (e.value as num?)?.toInt() ?? 0,
    };
  }

  /// Fonde due istantanee.
  ///
  /// La regola e' sempre la stessa: per ogni voce vince la data piu'
  /// recente fra "aggiunta" e "cancellata", da qualunque dispositivo
  /// arrivi. E' per questo che le cancellazioni sono registrate: senza,
  /// bastava che un dispositivo non avesse mai saputo della rimozione
  /// perche' la rimandasse su e il preferito tornasse da solo.
  static Map<String, dynamic> _merge({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
  }) {
    final out = <String, dynamic>{'version': 1};

    for (final kind in ['fav', 'recent']) {
      final key = kind == 'fav' ? 'favorites' : 'recent';
      final marks = _maxOf(
        _ts(local, 'marks', kind),
        _ts(remote, 'marks', kind),
      );
      final graves = _maxOf(
        _ts(local, 'graves', kind),
        _ts(remote, 'graves', kind),
      );

      final byId = <String, Track>{};
      for (final side in [remote, local]) {
        for (final raw in (side[key] as List?) ?? const []) {
          final t = Track.fromJson(Map<String, dynamic>.from(raw as Map));
          // Il locale passa per secondo e quindi vince sulle copie, ma solo
          // fondendosi: una copertina di ripiego non scalza quella vera.
          byId[t.id] = byId[t.id]?.refreshedFrom(t) ?? t;
        }
      }

      final alive = <String>[];
      for (final id in byId.keys) {
        final added = marks[id] ?? 0;
        final removed = graves[id];
        if (removed != null && removed >= added) continue;
        alive.add(id);
      }
      alive.sort((a, b) => (marks[b] ?? 0).compareTo(marks[a] ?? 0));

      final kept = kind == 'recent' ? alive.take(30).toList() : alive;
      out[key] = [for (final id in kept) byId[id]!.toJson()];
      _put(out, 'marks', kind, {for (final id in kept) id: marks[id] ?? 0});
      _put(out, 'graves', kind, graves);
    }

    // Playlist: per ognuna vince la versione con la data piu' recente,
    // intera. Fondere i brani di due versioni diverse della stessa playlist
    // produrrebbe un ordine che nessuno dei due ha scelto.
    final plMarks = _maxOf(
      _ts(local, 'marks', 'pl'),
      _ts(remote, 'marks', 'pl'),
    );
    final plGraves = _maxOf(
      _ts(local, 'graves', 'pl'),
      _ts(remote, 'graves', 'pl'),
    );
    final pls = <String, Map<String, dynamic>>{};
    for (final side in [local, remote]) {
      final sideMarks = _ts(side, 'marks', 'pl');
      for (final raw in (side['playlists'] as List?) ?? const []) {
        final pl = Map<String, dynamic>.from(raw as Map);
        final id = pl['id'] as String?;
        if (id == null) continue;
        final mine = sideMarks[id] ?? 0;
        final best = pls[id];
        if (best == null || mine >= (plMarks[id] ?? 0)) {
          if (best == null || mine > ((best['_ts'] as int?) ?? -1)) {
            pls[id] = {...pl, '_ts': mine};
          }
        }
      }
    }
    final livePls = <Map<String, dynamic>>[];
    for (final e in pls.entries) {
      final removed = plGraves[e.key];
      if (removed != null && removed >= (plMarks[e.key] ?? 0)) continue;
      livePls.add({...e.value}..remove('_ts'));
    }
    out['playlists'] = livePls;
    _put(out, 'marks', 'pl', {
      for (final pl in livePls) pl['id'] as String: plMarks[pl['id']] ?? 0,
    });
    _put(out, 'graves', 'pl', plGraves);

    // Artisti seguiti: presenza e basta, nessun contenuto da fondere.
    // Vale la stessa regola: vince la data piu' recente fra seguito e
    // smesso di seguire.
    final arMarks = _maxOf(
      _ts(local, 'marks', 'artist'),
      _ts(remote, 'marks', 'artist'),
    );
    final arGraves = _maxOf(
      _ts(local, 'graves', 'artist'),
      _ts(remote, 'graves', 'artist'),
    );
    final artists = <String, Map<String, dynamic>>{};
    for (final side in [remote, local]) {
      for (final raw in (side['followed'] as List?) ?? const []) {
        final a = Map<String, dynamic>.from(raw as Map);
        final id = a['browseId'] as String?;
        if (id != null) artists[id] = a;
      }
    }
    final liveArtists = <Map<String, dynamic>>[];
    for (final e in artists.entries) {
      final removed = arGraves[e.key];
      if (removed != null && removed >= (arMarks[e.key] ?? 0)) continue;
      liveArtists.add(e.value);
    }
    out['followed'] = liveArtists;
    _put(out, 'marks', 'artist', {
      for (final a in liveArtists)
        a['browseId'] as String: arMarks[a['browseId']] ?? 0,
    });
    _put(out, 'graves', 'artist', arGraves);

    // Com'erano fatti i brani ascoltati: senza, un ascolto fatto
    // sull'altro dispositivo contava nel totale ma non in classifica.
    final statTracks = {
      ...((remote['statTracks'] as Map?) ?? const {}),
      ...((local['statTracks'] as Map?) ?? const {}),
    };
    // Il tetto di ogni ascolto, dalla durata del brano. Anche qui e non
    // solo quando si registra: la fusione tiene il valore piu' alto dei
    // due dispositivi, e un ascolto sbagliato rimasto sull'altro tornerebbe
    // a ogni passata.
    int capOf(String id) {
      final t = statTracks[id];
      return listenCap(t is Map ? (t['duration'] as num?)?.toInt() : null);
    }

    // Statistiche: si tiene il valore piu' alto per ogni campo.
    //
    // Non e' la somma, di proposito: sommare due dispositivi che si sono
    // gia' sincronizzati conterebbe due volte gli stessi ascolti, e il
    // numero crescerebbe da solo a ogni passata. Il massimo sottostima
    // quando ascolti lo stesso brano su due dispositivi senza
    // sincronizzare in mezzo, ed e' un errore che non si accumula.
    final stats = <String, Map<String, dynamic>>{};
    for (final side in [local, remote]) {
      final raw = (side['stats'] as Map?) ?? const {};
      for (final e in raw.entries) {
        final id = e.key.toString();
        final v = Map<String, dynamic>.from(e.value as Map);
        final cur = stats[id];
        final count = _maxInt(cur?['count'], v['count']);
        final total = _maxInt(cur?['totalSeconds'], v['totalSeconds']);
        final ceiling = count * capOf(id);
        stats[id] = {
          'count': count,
          'totalSeconds': total > ceiling ? ceiling : total,
          'lastPlayed': _maxInt(cur?['lastPlayed'], v['lastPlayed']),
        };
      }
    }
    out['stats'] = stats;

    // Il registro dei singoli ascolti: qui si puo' unire, non solo prendere
    // il massimo. Un ascolto e' un brano partito in un certo secondo, e lo
    // stesso ascolto che torna indietro da Drive e' lo stesso, non un
    // altro: l'unione non conta mai due volte, per quante passate si
    // facciano. Due dispositivi che fanno partire lo stesso brano nello
    // stesso secondo sono l'unico caso che si perde.
    final log = <String, Map<int, int>>{};
    for (final side in [local, remote]) {
      final raw = (side['log'] as Map?) ?? const {};
      for (final e in raw.entries) {
        final byTime = log.putIfAbsent(e.key.toString(), () => {});
        for (final pair in (e.value as List?) ?? const []) {
          final p = pair as List;
          if (p.length < 2) continue;
          final at = (p[0] as num).toInt();
          final cap = capOf(e.key.toString());
          final raw = (p[1] as num).toInt();
          final secs = raw > cap ? cap : raw;
          byTime[at] = _maxInt(byTime[at], secs);
        }
      }
    }
    out['log'] = {
      for (final e in log.entries)
        e.key: [
          for (final at in (e.value.keys.toList()..sort())) [at, e.value[at]],
        ],
    };

    out['statTracks'] = statTracks;
    return out;
  }

  static int _maxInt(dynamic a, dynamic b) {
    final x = (a as num?)?.toInt() ?? 0;
    final y = (b as num?)?.toInt() ?? 0;
    return x > y ? x : y;
  }

  static Map<String, int> _maxOf(Map<String, int> a, Map<String, int> b) {
    final out = {...a};
    for (final e in b.entries) {
      if ((out[e.key] ?? 0) < e.value) out[e.key] = e.value;
    }
    return out;
  }

  static void _put(
    Map<String, dynamic> out,
    String box,
    String kind,
    Map<String, int> v,
  ) {
    final b = Map<String, dynamic>.from((out[box] as Map?) ?? {});
    b[kind] = v;
    out[box] = b;
  }

  // -------------------------------------------------------------------
  // Scrittura locale
  // -------------------------------------------------------------------

  Future<void> _restore(Map<String, dynamic> data) async {
    await _storage.replaceFavorites([
      for (final raw in (data['favorites'] as List?) ?? const [])
        Track.fromJson(Map<String, dynamic>.from(raw as Map)),
    ]);
    await _storage.replaceRecentlyPlayed([
      for (final raw in (data['recent'] as List?) ?? const [])
        Track.fromJson(Map<String, dynamic>.from(raw as Map)),
    ]);
    await _storage.savePlaylists([
      for (final raw in (data['playlists'] as List?) ?? const [])
        Map<String, dynamic>.from(raw as Map),
    ]);
    await _storage.saveFollowed([
      for (final raw in (data['followed'] as List?) ?? const [])
        Map<String, dynamic>.from(raw as Map),
    ]);
    await _storage.replaceAllPlayStats({
      for (final e in ((data['stats'] as Map?) ?? const {}).entries)
        e.key.toString(): Map<String, dynamic>.from(e.value as Map),
    });
    final log = {
      for (final e in ((data['log'] as Map?) ?? const {}).entries)
        e.key.toString(): [
          for (final p in (e.value as List?) ?? const [])
            [((p as List)[0] as num).toInt(), (p[1] as num).toInt()],
        ],
    };
    // Si riscrive solo se l'altro dispositivo ha portato qualcosa: la
    // fusione contiene sempre almeno tutto il locale, quindi a parita' di
    // numero e' lo stesso registro, e riscriverlo a ogni passata — sul Mac
    // a ogni cambio di finestra — sarebbe lavoro buttato.
    final merged = log.values.fold<int>(0, (n, l) => n + l.length);
    if (merged != _storage.playLogLength) await _storage.replacePlayLog(log);
    await _storage.addStatTracks({
      for (final e in ((data['statTracks'] as Map?) ?? const {}).entries)
        e.key.toString(): Map<String, dynamic>.from(e.value as Map),
    });
    for (final kind in ['fav', 'recent', 'pl', 'artist']) {
      await _storage.setMarks(kind, _ts(data, 'marks', kind));
      await _storage.setGraves(kind, _ts(data, 'graves', kind));
    }
  }

  /// Esposta per i test: la fusione e' la parte che vale la pena provare.
  static Map<String, dynamic> mergeForTest({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
  }) => _merge(local: local, remote: remote);
}

enum SyncOutcome { done, failed, disabled }

/// Dove sta lo script e con quale segreto gli si parla.
class SyncConfig {
  final String url;
  final String secret;

  const SyncConfig(this.url, this.secret);

  bool get isComplete => url.isNotEmpty && secret.isNotEmpty;

  /// Il codice da incollare sull'altro dispositivo: indirizzo e segreto in
  /// una riga sola, cosi' sul telefono non si ricopia un URL lungo a mano.
  String get setupCode =>
      'crocuta:${base64Url.encode(utf8.encode(jsonEncode({'u': url, 's': secret})))}';

  /// Il contrario di [setupCode]; `null` se il testo non e' un codice.
  static SyncConfig? fromSetupCode(String text) {
    final t = text.trim();
    // Il prefisso senza badare alle maiuscole: le tastiere dei telefoni
    // mettono la maiuscola a inizio frase. Il resto no: e' base64.
    if (!t.toLowerCase().startsWith('crocuta:')) return null;
    try {
      final m = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(t.substring(8)))),
      );
      if (m is! Map || m['u'] is! String || m['s'] is! String) return null;
      return SyncConfig(m['u'] as String, m['s'] as String);
    } catch (_) {
      return null;
    }
  }
}
