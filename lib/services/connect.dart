import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers.dart';
import 'sync_service.dart';

/// Crocuta Connect: i tuoi Crocuta sulla rete di casa si vedono, e da uno
/// si comanda l'altro — o gli si passa la musica.
///
/// Ogni Crocuta aperto tiene un piccolo server WebSocket e si annuncia con
/// Bonjour, come fanno le stampanti e gli altoparlanti AirPlay; gli altri
/// lo trovano da soli, senza indirizzi da scrivere. Niente server esterni:
/// tutto resta fra i tuoi dispositivi.
///
/// Si riconoscono dal segreto della sincronizzazione, quello scritto nelle
/// Impostazioni: solo chi ha lo stesso segreto puo' comandare. Uno
/// sconosciuto sulla stessa Wi-Fi vede che c'e' un Crocuta, ma non lo
/// tocca. Senza sincronizzazione il segreto e' vuoto, e si riconoscono fra
/// loro solo i Crocuta che non l'hanno configurata.
const _serviceType = '_crocuta._tcp';

/// La prova di conoscere il segreto, senza mandarlo in chiaro sulla rete.
/// Letto a ogni stretta di mano, cosi' un segreto cambiato vale subito.
String _token() => sha256
    .convert(utf8.encode('crocuta-connect:${SyncService.secret}'))
    .toString();

/// Un altro Crocuta sulla rete.
class ConnectDevice {
  final String id;
  final String name;

  /// "macos", "ios", "windows": per l'icona.
  final String platform;

  /// Gli indirizzi a cui provare, dal piu' probabile. Un Mac col cavo di un
  /// iPhone, un bridge Thunderbolt o una VPN annuncia anche indirizzi che
  /// dagli altri dispositivi non si raggiungono (169.254...): prendere il
  /// primo della lista faceva fallire il collegamento a caso.
  final List<String> hosts;
  final int port;

  const ConnectDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.hosts,
    required this.port,
  });

  String get host => hosts.first;
}

/// Come e' andato un collegamento a un altro Crocuta.
enum ConnectResult {
  ok,

  /// Nessun indirizzo ha risposto.
  unreachable,

  /// Ha risposto, ma con un altro segreto: non e' un dispositivo tuo, o
  /// la sincronizzazione e' configurata diversa.
  notYours,
}

/// Gli indirizzi in ordine di speranza: prima quelli di una rete di casa,
/// poi il resto, per ultimi i link-local e il nome .local, che il sistema
/// risolve da se'.
List<String> connectHosts(Iterable<String> addresses, String? hostname) {
  int rank(String a) {
    if (a.contains(':')) return 4; // IPv6: senza zona spesso non va
    if (a.startsWith('127.')) return 9;
    if (a.startsWith('169.254.')) return 3;
    if (a.startsWith('192.168.') || a.startsWith('10.')) return 0;
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(a);
    if (m != null) {
      final b = int.parse(m.group(1)!);
      if (b >= 16 && b <= 31) return 0;
    }
    return 1;
  }

  final list = addresses.toSet().where((a) => rank(a) < 9).toList()
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  if (hostname != null && hostname.isNotEmpty) list.add(hostname);
  return list;
}

/// Cosa sta suonando su un altro dispositivo, visto dal telecomando.
class RemoteState {
  final String device;
  final Track? track;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final List<Track> upcoming;

  /// Quando e' arrivato: la posizione avanza da sola fra un aggiornamento e
  /// l'altro, e la barra la stima invece di scattare ogni secondo.
  final DateTime at;

  const RemoteState({
    required this.device,
    this.track,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100,
    this.upcoming = const [],
    required this.at,
  });

  Duration get livePosition {
    if (!playing) return position;
    final p = position + DateTime.now().difference(at);
    return p > duration && duration > Duration.zero ? duration : p;
  }

  static RemoteState fromJson(Map m) => RemoteState(
    device: m['device'] as String? ?? '',
    track: m['track'] == null
        ? null
        : Track.fromJson(Map<String, dynamic>.from(m['track'] as Map)),
    playing: m['playing'] == true,
    position: Duration(milliseconds: (m['position'] as num?)?.toInt() ?? 0),
    duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
    volume: (m['volume'] as num?)?.toDouble() ?? 100,
    upcoming: [
      for (final t in (m['upcoming'] as List? ?? const []))
        Track.fromJson(Map<String, dynamic>.from(t as Map)),
    ],
    at: DateTime.now(),
  );
}

/// Il nome scelto nelle Impostazioni, se c'e'.
String? _customName;

/// Il nome con cui questo dispositivo si presenta agli altri: quello
/// scelto, o il nome del computer. Su iPhone il nome del sistema non si
/// puo' leggere e arrivava "localhost": allora "iPhone".
String _deviceName() {
  final custom = _customName?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  var host = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '');
  host = host.replaceAll('-', ' ');
  if (host.isEmpty || host == 'localhost') {
    host = Platform.isIOS
        ? 'iPhone'
        : Platform.isAndroid
        ? 'Android'
        : 'Crocuta';
  }
  return host;
}

String get _platform => Platform.isIOS
    ? 'ios'
    : Platform.isMacOS
    ? 'macos'
    : Platform.isWindows
    ? 'windows'
    : Platform.isAndroid
    ? 'android'
    : 'other';

/// Il lato server: questo Crocuta, comandabile dagli altri.
class ConnectService {
  final Ref _ref;
  ConnectService(this._ref);

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  final _clients = <WebSocket>{};
  Timer? _push;
  ProviderSubscription<Object?>? _playerSub;
  late final String _id = _selfId();

  /// I dispositivi trovati, per id. Chi li mostra ascolta [devices].
  final _found = <String, ConnectDevice>{};
  final devices = ValueNotifier<List<ConnectDevice>>(const []);

  String _selfId() {
    final storage = _ref.read(storageServiceProvider);
    final known = storage.connectId;
    if (known != null) return known;
    final r = Random.secure();
    final id = List.generate(
      8,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    unawaited(storage.setConnectId(id));
    return id;
  }

  /// Il nome con cui gli altri vedono questo dispositivo.
  String get name => _deviceName();

  bool get running => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final storage = _ref.read(storageServiceProvider);
    if (!storage.connectEnabled) return;
    _customName = storage.connectName;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      server.listen(_onRequest, onError: (_) {});
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: _deviceName(),
          type: _serviceType,
          port: server.port,
          attributes: {'id': _id, 'platform': _platform},
        ),
      );
      _broadcast = broadcast;
      await broadcast.initialize();
      await broadcast.start();
      debugPrint('connect: annunciato su ${server.port} come ${_deviceName()}');
      await _discover();
      // Lo stato a chi comanda: a ogni cambio del player, e ogni secondo
      // mentre suona, per la posizione.
      _playerSub = _ref.listen(
        playerProvider,
        (_, _) => _schedulePush(),
        fireImmediately: false,
      );
      _push = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_clients.isNotEmpty) _sendState();
      });
    } catch (e) {
      debugPrint('connect: non avviato ($e)');
    }
  }

  Future<void> _discover() async {
    final discovery = BonsoirDiscovery(type: _serviceType);
    _discovery = discovery;
    await discovery.initialize();
    discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          event.service.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent():
          final s = event.service;
          final id = s.attributes['id'];
          final hosts = connectHosts([
            ...s.hostAddresses,
            ?s.hostAddress,
          ], s.hostname);
          if (id == null || id == _id || hosts.isEmpty) return;
          _found[id] = ConnectDevice(
            id: id,
            name: s.name,
            platform: s.attributes['platform'] ?? 'other',
            hosts: hosts,
            port: s.port,
          );
          devices.value = _found.values.toList();
        case BonsoirDiscoveryServiceLostEvent():
          final id = event.service.attributes['id'];
          if (id != null && _found.remove(id) != null) {
            devices.value = _found.values.toList();
          }
        default:
      }
    });
    await discovery.start();
  }

  Timer? _debounce;
  void _schedulePush() {
    if (_clients.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _sendState);
  }

  Map<String, Object?> _state() {
    final s = _ref.read(playerProvider);
    final start = s.currentIndex + 1;
    return {
      't': 'state',
      'device': _deviceName(),
      'track': s.current?.toJson(),
      'playing': s.isPlaying,
      'position': s.position.inMilliseconds,
      'duration': s.duration.inMilliseconds,
      'volume': s.volume,
      'upcoming': [
        if (start < s.queue.length)
          for (final t in s.queue.skip(start).take(30)) t.toJson(),
      ],
    };
  }

  void _sendState() {
    final msg = jsonEncode(_state());
    for (final c in _clients.toList()) {
      try {
        c.add(msg);
      } catch (_) {}
    }
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    var trusted = false;
    ws.listen(
      (raw) async {
        final m = jsonDecode(raw as String) as Map;
        if (!trusted) {
          // Il primo messaggio e' la stretta di mano: senza il segreto
          // giusto si chiude, e basta.
          if (m['t'] == 'hello' && m['token'] == _token()) {
            trusted = true;
            _clients.add(ws);
            ws.add(jsonEncode(_state()));
          } else {
            await ws.close(4001, 'unauthorized');
          }
          return;
        }
        await _command(ws, m);
      },
      onDone: () => _clients.remove(ws),
      onError: (_) => _clients.remove(ws),
    );
  }

  Future<void> _command(WebSocket ws, Map m) async {
    final player = _ref.read(playerProvider.notifier);
    switch (m['do']) {
      case 'toggle':
        await player.toggle();
      case 'next':
        await player.next();
      case 'previous':
        await player.previous();
      case 'seek':
        await player.seek(Duration(milliseconds: (m['ms'] as num).toInt()));
      case 'volume':
        await player.setVolume((m['v'] as num).toDouble());
      case 'playAt':
        final s = _ref.read(playerProvider);
        final i = s.currentIndex + 1 + (m['i'] as num).toInt();
        if (i < s.queue.length) await player.playAt(i);
      // "Riproduci qui", chiesto dall'altro: gli si manda la coda e il
      // punto, e ci si ferma. Suonera' lui.
      case 'take':
        final s = _ref.read(playerProvider);
        ws.add(
          jsonEncode({
            't': 'handoff',
            'queue': [for (final t in s.queue) t.toJson()],
            'index': s.currentIndex,
            'position': s.position.inMilliseconds,
          }),
        );
        if (s.isPlaying) await player.toggle();
      // "Riproduci su questo": l'altro ci passa la sua musica.
      case 'play':
        await _playHandoff(m);
    }
  }

  /// Fa partire qui una coda arrivata da un altro dispositivo, dal punto in
  /// cui era.
  Future<void> _playHandoff(Map m) async {
    final queue = [
      for (final t in (m['queue'] as List? ?? const []))
        Track.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
    final index = (m['index'] as num?)?.toInt() ?? 0;
    if (index < 0 || index >= queue.length) return;
    await _ref
        .read(playerProvider.notifier)
        .playTrack(
          queue[index],
          queue: queue,
          startAt: Duration(
            milliseconds: (m['position'] as num?)?.toInt() ?? 0,
          ),
        );
  }

  /// Cambia il nome con cui questo dispositivo si presenta: si salva, e
  /// l'annuncio riparte col nome nuovo.
  Future<void> rename(String name) async {
    await _ref.read(storageServiceProvider).setConnectName(name);
    _customName = name;
    if (_server == null) return;
    await stop();
    await start();
  }

  /// Passa la musica di qui a [device]: la manda, e qui si ferma.
  Future<ConnectResult> giveTo(ConnectDevice device) async {
    final s = _ref.read(playerProvider);
    if (s.current == null) return ConnectResult.unreachable;
    final remote = ConnectRemote(device);
    try {
      final r = await remote.connect();
      if (r != ConnectResult.ok) return r;
      remote.send({
        't': 'cmd',
        'do': 'play',
        'queue': [for (final t in s.queue) t.toJson()],
        'index': s.currentIndex,
        'position': s.position.inMilliseconds,
      });
      if (s.isPlaying) await _ref.read(playerProvider.notifier).toggle();
      return ConnectResult.ok;
    } catch (e) {
      debugPrint('connect: passaggio non riuscito ($e)');
      return ConnectResult.unreachable;
    } finally {
      unawaited(Future.delayed(const Duration(seconds: 2), remote.close));
    }
  }

  /// Prende qui la musica di [device]: lui si ferma, qui riparte dal
  /// punto in cui era.
  Future<ConnectResult> takeFrom(ConnectDevice device) async {
    final remote = ConnectRemote(device);
    try {
      final r = await remote.connect();
      if (r != ConnectResult.ok) return r;
      final handoff = remote.handoffs.first.timeout(const Duration(seconds: 8));
      remote.send({'t': 'cmd', 'do': 'take'});
      await _playHandoff(await handoff);
      return ConnectResult.ok;
    } catch (e) {
      debugPrint('connect: presa non riuscita ($e)');
      return ConnectResult.unreachable;
    } finally {
      unawaited(remote.close());
    }
  }

  /// Spento dalle impostazioni: sparisce dalla rete, chi lo comandava
  /// viene staccato, e non cerca piu' gli altri.
  Future<void> stop() async {
    _playerSub?.close();
    _playerSub = null;
    _push?.cancel();
    _push = null;
    _debounce?.cancel();
    for (final c in _clients.toList()) {
      unawaited(c.close());
    }
    _clients.clear();
    await _broadcast?.stop();
    _broadcast = null;
    await _discovery?.stop();
    _discovery = null;
    await _server?.close(force: true);
    _server = null;
    _found.clear();
    devices.value = const [];
  }

  void dispose() {
    _push?.cancel();
    _debounce?.cancel();
    unawaited(_broadcast?.stop() ?? Future.value());
    unawaited(_discovery?.stop() ?? Future.value());
    unawaited(_server?.close(force: true) ?? Future.value());
    devices.dispose();
  }
}

/// Il telecomando: una connessione a un altro Crocuta.
class ConnectRemote {
  final ConnectDevice device;
  ConnectRemote(this.device);

  WebSocket? _ws;
  final state = ValueNotifier<RemoteState?>(null);
  final _handoffs = StreamController<Map>.broadcast();
  Stream<Map> get handoffs => _handoffs.stream;

  /// Si collega al primo indirizzo che risponde e aspetta la conferma:
  /// il primo stato arriva solo se il segreto e' giusto. Prima si dava per
  /// fatto appena aperta la connessione, anche quando l'altro la chiudeva
  /// subito per un segreto diverso.
  Future<ConnectResult> connect() async {
    WebSocket? ws;
    for (final host in device.hosts) {
      try {
        ws = await WebSocket.connect(
          'ws://${host.contains(':') ? '[$host]' : host}:${device.port}/',
        ).timeout(const Duration(milliseconds: 2500));
        debugPrint('connect: collegato a ${device.name} su $host');
        break;
      } catch (e) {
        debugPrint('connect: ${device.name} non risponde su $host ($e)');
      }
    }
    if (ws == null) return ConnectResult.unreachable;
    final socket = ws;
    _ws = socket;
    final confirmed = Completer<ConnectResult>();
    socket.add(jsonEncode({'t': 'hello', 'token': _token()}));
    socket.listen(
      (raw) {
        final m = jsonDecode(raw as String) as Map;
        switch (m['t']) {
          case 'state':
            state.value = RemoteState.fromJson(m);
            if (!confirmed.isCompleted) confirmed.complete(ConnectResult.ok);
          case 'handoff':
            _handoffs.add(m);
        }
      },
      onDone: () {
        state.value = null;
        if (!confirmed.isCompleted) {
          confirmed.complete(
            socket.closeCode == 4001
                ? ConnectResult.notYours
                : ConnectResult.unreachable,
          );
        }
      },
      onError: (_) {
        state.value = null;
        if (!confirmed.isCompleted) {
          confirmed.complete(ConnectResult.unreachable);
        }
      },
    );
    return confirmed.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => ConnectResult.unreachable,
    );
  }

  void send(Map<String, Object?> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  void command(String what, [Map<String, Object?> extra = const {}]) =>
      send({'t': 'cmd', 'do': what, ...extra});

  Future<void> close() async {
    await _ws?.close();
    await _handoffs.close();
  }
}

final connectServiceProvider = Provider<ConnectService>((ref) {
  final service = ConnectService(ref);
  ref.onDispose(service.dispose);
  return service;
});
