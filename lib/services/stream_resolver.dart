import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// A resolved, validated playable source for one video.
class ResolvedStream {
  /// Direct media URL (progressive googlevideo URL or HLS m3u8 manifest).
  final String url;

  /// User-Agent that must accompany every request to [url].
  final String userAgent;

  /// True when [url] is an HLS playlist instead of a progressive stream.
  final bool isHls;

  /// InnerTube client the URL came from (for logs).
  final String clientName;

  /// L'itag e il bitrate del formato scelto, quando lo stream e'
  /// progressivo. Servono a sapere cosa si sta ascoltando davvero: senza,
  /// "prendiamo il migliore" e' un'affermazione che non si puo' verificare.
  final int? itag;
  final int? bitrate;

  /// True when Google flagged the URL: it serves only a window near
  /// its beginning (~1 MiB) and 403s beyond. Such streams are still
  /// usable because every freshly issued URL has a fresh window — the
  /// proxy stitches them together mid-song via its refresh callback.
  final bool limited;

  const ResolvedStream({
    required this.url,
    this.itag,
    this.bitrate,
    required this.userAgent,
    required this.isHls,
    required this.clientName,
    this.limited = false,
  });
}

/// Cosa si chiede al resolver: l'audio del brano (il caso di sempre), il
/// solo video muto per la copertina animata, o il videoclip con il suo
/// audio da guardare.
enum StreamKind { audio, videoOnly, videoHigh, muxed }

/// Result of one ranged GET probe.
class _ProbeResult {
  final int status;
  final List<int> body;
  final int? totalFromContentRange;
  _ProbeResult(this.status, this.body, this.totalFromContentRange);
}

/// One InnerTube player client we can ask for streams.
class _ClientSpec {
  final String name;
  final Map<String, dynamic> payload;
  final String endpoint;
  final String userAgent;
  final bool sendsCookie;

  /// I client web accettano (e spesso pretendono) context.client.visitorData:
  /// senza quell'ID di sessione molte risposte player sono UNPLAYABLE.
  final bool wantsVisitorData;

  /// Invia anche la firma SAPISIDHASH: i client che NON la supportano
  /// (es. ANDROID_VR) rispondono HTTP 400 se inviata.
  final bool sendsAuth;

  const _ClientSpec(
    this.name,
    this.payload,
    this.endpoint,
    this.userAgent, {
    this.sendsCookie = false,
    this.wantsVisitorData = false,
    this.sendsAuth = false,
  });
}

/// Resolves YouTube audio streams directly through InnerTube player
/// endpoints and validates every candidate URL with real ranged GETs
/// before handing it to the player.
///
/// Why not youtube_explode_dart for streams anymore: its getManifest
/// discards a whole client when a HEAD probe of the FIRST format (often
/// a video itag) gets 403, and HEAD is not how Google enforces its
/// anti-bot limits anyway. Enforcement happens on ranged GETs of the
/// media itself: flagged URLs serve roughly the first MiB (~1 minute of
/// audio) or answer 403 from byte zero.
///
/// So every candidate here is probed with the very kind of request the
/// player will make later: a small range at offset 0 and another past
/// the 1 MiB soft-block window. Only URLs serving both reach playback,
/// which turns "song dies after ~1:04" into an immediate fallback to
/// the next client/format instead of a dead player mid-song.
class StreamResolver {
  /// Current login cookie (re-read on every call so logins apply live).
  final String? Function() cookieProvider;

  /// Generatore di PO Token (BotGuard via WebView nascosta). [binding] è
  /// visitorData per le richieste player, videoId per gli URL media.
  final Future<String?> Function(String binding)? potProvider;

  /// VisitorData DELLA SESSIONE CHE GENERA I TOKEN: i pot sono vincolati
  /// al visitorData della webview, quindi le richieste web devono usare
  /// lo stesso, non quello recuperato via HTTP da Dart.
  final Future<String?> Function()? webVisitorDataProvider;

  final http.Client _http = http.Client();

  StreamResolver({
    required this.cookieProvider,
    this.potProvider,
    this.webVisitorDataProvider,
  });

  /// ID di sessione che YouTube assegna a ogni browser reale e che i
  /// client web includono in ogni richiesta player. Cache ~6 ore.
  String? _visitorData;
  DateTime? _visitorDataAt;

  Future<String?> _ensureVisitorData(String cookie) async {
    final cached = _visitorData;
    if (cached != null &&
        _visitorDataAt != null &&
        DateTime.now().difference(_visitorDataAt!) < const Duration(hours: 6)) {
      return cached;
    }
    try {
      // La homepage contiene lo ytcfg con VISITOR_DATA (quote escapate).
      final resp = await _http
          .get(
            Uri.parse('https://www.youtube.com/'),
            headers: {
              'User-Agent': _safariUa,
              'Accept-Language': 'it,it;q=0.9,en;q=0.8',
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
          )
          .timeout(const Duration(seconds: 15));
      final m = RegExp(r'visitorData\\?":\\?"([^"\\]+)').firstMatch(resp.body);
      if (m != null) {
        _visitorData = m.group(1);
        _visitorDataAt = DateTime.now();
        developer.log('VISITORDATA ok (${_visitorData!.length} char)');
        return _visitorData;
      }
      developer.log('VISITORDATA non trovata in sw.js_data');
    } catch (e) {
      developer.log('VISITORDATA errore: $e');
    }
    return _visitorData;
  }

  /// Copia profonda del payload con visitorData injectato se richiesto.
  Map<String, dynamic> _payloadFor(_ClientSpec spec, String? visitorData) {
    final p = jsonDecode(jsonEncode(spec.payload)) as Map<String, dynamic>;
    if (spec.wantsVisitorData &&
        visitorData != null &&
        visitorData.isNotEmpty) {
      ((p['context'] as Map)['client'] as Map)['visitorData'] = visitorData;
    }
    return p;
  }

  /// signatureTimestamp dal player JS: il browser lo manda sempre nel
  /// playbackContext delle richieste player web.
  int? _sigTimestamp;

  Future<int?> _ensureSignatureTimestamp(String cookie) async {
    if (_sigTimestamp != null) return _sigTimestamp;
    try {
      final home = await _http
          .get(
            Uri.parse('https://www.youtube.com/'),
            headers: {
              'User-Agent': _safariUa,
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
          )
          .timeout(const Duration(seconds: 15));
      final m = RegExp(r'"PLAYER_JS_URL":"([^"]+)"').firstMatch(home.body);
      if (m == null) return null;
      final jsUrl = m.group(1)!.startsWith('http')
          ? m.group(1)!
          : 'https://www.youtube.com${m.group(1)}';
      final js = await _http
          .get(Uri.parse(jsUrl), headers: {'User-Agent': _safariUa})
          .timeout(const Duration(seconds: 15));
      final sm = RegExp(r'signatureTimestamp\s*=\s*(\d+)').firstMatch(js.body);
      if (sm != null) {
        _sigTimestamp = int.tryParse(sm.group(1)!);
        developer.log('SIGTS=$_sigTimestamp');
      }
    } catch (_) {}
    return _sigTimestamp;
  }

  /// Quanto e' forte ogni brano rispetto al riferimento di YouTube, in dB:
  /// +5 vuol dire cinque decibel sopra. YouTube lo usa per abbassare i
  /// brani troppo forti; qui serve ad AutoMix, perche' una transizione fra
  /// un brano masterizzato forte e uno piano e' un salto di volume anche
  /// con la dissolvenza piu' morbida.
  final Map<String, double> loudnessDb = {};

  void _noteLoudness(String videoId, Map data, Map sd) {
    num? value = data['playerConfig']?['audioConfig']?['loudnessDb'] as num?;
    if (value == null) {
      for (final f in (sd['adaptiveFormats'] as List? ?? const [])) {
        if (f is Map &&
            (f['mimeType'] as String? ?? '').startsWith('audio/') &&
            f['loudnessDb'] is num) {
          value = f['loudnessDb'] as num;
          break;
        }
      }
    }
    if (value != null) loudnessDb[videoId] = value.toDouble();
  }

  /// Header che yt-dlp invia su OGNI richiesta InnerTube e noi OMEttiamo
  /// (la causa di "Sign in to confirm you're not a bot" sui client nativi):
  /// X-YouTube-Client-Name/Version + soprattutto X-Goog-Visitor-Id, che è
  /// l'ID di sessione anti-bot. yt-dlp lo mette sempre (generate_api_headers).
  /// Numeri INNERTUBE_CONTEXT_CLIENT_NAME: WEB=1, MWEB=2, ANDROID=3, IOS=5,
  /// TVHTML5=7, ANDROID_VR=28, WEB_REMIX=67, VISIONOS=101.
  Map<String, String> _ytHeaders(_ClientSpec spec, String? visitorData) {
    final client = (spec.payload['context'] as Map)['client'] as Map;
    final version = client['clientVersion'] as String?;
    final name = switch (spec.name) {
      'VISIONOS' => '101',
      'WEB_REMIX' => '67',
      'ANDROID_VR' || 'ANDROID_VR_LOGGED' => '28',
      'TVHTML5' => '7',
      'IOS' => '5',
      'ANDROID' || 'ANDROID_SDKLESS' => '3',
      _ => '1', // WEB / WEB_SAFARI
    };
    return {
      'X-YouTube-Client-Name': name,
      'X-YouTube-Client-Version': version ?? '',
      if (visitorData != null && visitorData.isNotEmpty)
        'X-Goog-Visitor-Id': visitorData,
    };
  }

  /// Origine dell'endpoint (per Referer/X-Origin dei client web).
  String _originOf(String endpoint) =>
      Uri.parse(endpoint).resolve('/').toString().replaceAll(RegExp(r'/$'), '');

  static const _wwwPlayer =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';
  static const _musicPlayer =
      'https://music.youtube.com/youtubei/v1/player?prettyPrint=false';

  static const _iosUa =
      'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
  static const _androidUa =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  static const _browserUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Safari/605.1.15';

  /// UA Safari "puro": con questo User-Agent il client WEB risponde con
  /// manifest HLS che NON richiedono poToken per il GVS (policy yt-dlp
  /// StreamingProtocol.HLS required=false per i client web).
  static const _safariUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 '
      'Safari/605.1.15,gzip(gfe)';

  /// UA del client TV (Cobalt): senza poToken quando la sessione è
  /// autenticata (yt-dlp: client 'tv').
  static const _tvUa =
      'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold '
      '(unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)';

  /// UA del client VISIONOS (yt-dlp 2026): serve gli stream COMPLETI anche
  /// su video music flaggati dove IOS/ANDROID danno solo ~1 MiB e 403.
  static const _visionosUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  // Client contexts mirror yt-dlp definitions (versions identical to those
  // proven to work today). ORDINE = priorità secondo misure reali: il
  // client VISIONOS di yt-dlp serve gli stream musicali INTERI (verificato
  // scaricando 'Crash Out' di Tinashe a 3.07 MiB) anche quando IOS/ANDROID
  // danno solo ~1 MiB. Più sotto, la scala PO-Token di yt-dlp (luglio 2026):
  //   1. VISIONOS     -> serve stream completi (verificato sul campo)
  //   2. ANDROID_VR   -> poToken NON richiesto
  //   3. WEB_SAFARI   -> HLS senza poToken (richiede sessione fidata)
  //   4. TVHTML5      -> senza poToken quando autenticati
  //   5. WEB_REMIX    -> sessione browser YTM autenticata
  //   6. IOS          -> richiede poToken: ultimo tentativo
  //   7. ANDROID_SDKLESS -> richiede poToken
  static const List<_ClientSpec> _clients = [
    // yt-dlp 2026.08.19 client 'visionos': clientName VISIONOS / version
    // 1.02, device Vision Pro. Nessuna policy player/GVS richiesta — va
    // senza poToken. Servi' la canzone intera quando gli altri client no.
    const _ClientSpec(
      'VISIONOS',
      {
        'context': {
          'client': {
            'clientName': 'VISIONOS',
            'clientVersion': '1.02',
            'deviceMake': 'Apple',
            'deviceModel': 'RealityDevice17,1',
            'userAgent': _visionosUa,
            'osName': 'visionOS',
            'osVersion': '26.5.23O471',
          },
        },
      },
      _wwwPlayer,
      _visionosUa,
    ),
    _ClientSpec(
      'ANDROID_VR',
      {
        'context': {
          'client': {
            'clientName': 'ANDROID_VR',
            'clientVersion': '1.62.27',
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 3',
            'osName': 'Android',
            'osVersion': '12',
            'androidSdkVersion': '32',
            'hl': 'it',
            'gl': 'IT',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
      },
      _wwwPlayer,
      _androidUa,
    ),
    // Stesso client MA con il cookie: la risposta "Accedi per confermare"
    // suggerisce che una sessione autenticata sblocca ANDROID_VR.
    const _ClientSpec(
      'ANDROID_VR_LOGGED',
      {
        'context': {
          'client': {
            'clientName': 'ANDROID_VR',
            'clientVersion': '1.62.27',
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 3',
            'osName': 'Android',
            'osVersion': '12',
            'androidSdkVersion': '32',
            'hl': 'it',
            'gl': 'IT',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
      },
      _wwwPlayer,
      _androidUa,
      sendsCookie: true,
    ),
    _ClientSpec(
      'WEB_SAFARI',
      {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20260708.00.00',
            'hl': 'it',
            'gl': 'IT',
          },
        },
      },
      _wwwPlayer,
      _safariUa,
      sendsCookie: true,
      wantsVisitorData: true,
      sendsAuth: true,
    ),
    _ClientSpec(
      'TVHTML5',
      {
        'context': {
          'client': {
            'clientName': 'TVHTML5',
            'clientVersion': '7.20260707.07.00',
            'hl': 'it',
            'gl': 'IT',
          },
        },
      },
      _wwwPlayer,
      _tvUa,
      sendsCookie: true,
      wantsVisitorData: true,
      sendsAuth: true,
    ),
    // Signed-in browser session (YouTube Music). Only tried when a
    // cookie is configured.
    _ClientSpec(
      'WEB_REMIX',
      {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240801.01.00',
            'hl': 'it',
            'gl': 'IT',
          },
        },
      },
      _musicPlayer,
      _browserUa,
      sendsCookie: true,
      wantsVisitorData: true,
      sendsAuth: true,
    ),
    _ClientSpec(
      'IOS',
      {
        'context': {
          'client': {
            'clientName': 'IOS',
            'clientVersion': '20.10.4',
            'deviceMake': 'Apple',
            'deviceModel': 'iPhone16,2',
            'userAgent': _iosUa,
            'hl': 'it',
            'gl': 'IT',
            'platform': 'MOBILE',
            'osName': 'IOS',
            'osVersion': '18.1.0.22B83',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          },
        },
      },
      _wwwPlayer,
      _iosUa,
    ),
    _ClientSpec(
      'ANDROID_SDKLESS',
      {
        'context': {
          'client': {
            'clientName': 'ANDROID',
            'clientVersion': '20.10.38',
            'userAgent': _androidUa,
            'hl': 'it',
            'gl': 'IT',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
            'osName': 'Android',
            'osVersion': '11',
          },
        },
      },
      _wwwPlayer,
      _androidUa,
    ),
    // WEB_SAFARI anonimo (senza cookie): sessione pulita della sola
    // webview + suo visitorData + pot = il profilo di un browser fresco.
    const _ClientSpec(
      'WEB_SAFARI_ANON',
      {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20260708.00.00',
            'hl': 'it',
            'gl': 'IT',
          },
        },
      },
      _wwwPlayer,
      _safariUa,
      wantsVisitorData: true,
    ),
  ];

  /// Ordered candidates for [attempt]: higher values rotate the list so
  /// retries naturally try different clients.
  List<_ClientSpec> _candidates(int attempt, bool hasCookie) {
    final base = hasCookie
        ? _clients // tutti (i sendsCookie vengono saltati se no cookie)
        : [
            _clients[0], // VISIONOS
            _clients[1], // ANDROID_VR
            _clients[6], // IOS
            _clients[7], // ANDROID_SDKLESS
            _clients[8], // WEB_SAFARI_ANON
          ];
    return [
      for (var i = 0; i < base.length; i++) base[(i + attempt) % base.length],
    ];
  }

  /// Resolves an audio source for [videoId].
  ///
  /// Two passes: first STRICT (URL must serve ranges well beyond the
  /// ~1 MiB anti-bot window), then LENIENT (URL serves at least the
  /// first window; marked [ResolvedStream.limited] and stitched by the
  /// proxy via its refresh callback). Returns null only when not even
  /// the initial window can be read from any client.
  Future<ResolvedStream?> resolve(
    String videoId, {
    int attempt = 0,
    bool preferHls = false,
    StreamKind kind = StreamKind.audio,
  }) async {
    for (final lenient in [false, true]) {
      final cookie = cookieProvider()?.trim() ?? '';
      final hasCookie = cookie.isNotEmpty;
      for (final spec in _candidates(attempt, hasCookie)) {
        if (spec.sendsCookie && !hasCookie) continue;
        try {
          final resolved = await _resolveWithClient(
            spec,
            videoId,
            cookie,
            preferHls: preferHls || kind == StreamKind.muxed,
            lenient: lenient,
            kind: kind,
          );
          if (resolved != null) return resolved;
        } catch (e) {
          developer.log('RESOLVE ' + spec.name + ' fallito: ' + e.toString());
        }
      }
    }
    return null;
  }

  /// Firma SAPISIDHASH: identica a quella che il browser YouTube invia
  /// con le richieste InnerTube autenticate. Senza di essa Google vede
  /// "cookie valido ma richiesta non da browser" e blocca lo stream.
  Map<String, String> _authHeaders(String cookie, String endpoint) {
    final m = RegExp(r'SAPISID=([^;]+)').firstMatch(cookie);
    if (m == null || m.group(1)!.isEmpty) return const {};
    final origin = Uri.parse(
      endpoint,
    ).resolve('/').toString().replaceAll(RegExp(r'/$'), '');
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest = sha1.convert(utf8.encode('$ts ${m.group(1)} $origin'));
    return {
      'Authorization': 'SAPISIDHASH ${ts}_$digest',
      'X-Origin': origin,
      'Origin': origin,
      'Referer': '$origin/',
    };
  }

  Future<ResolvedStream?> _resolveWithClient(
    _ClientSpec spec,
    String videoId,
    String cookie, {
    required bool preferHls,
    required bool lenient,
    StreamKind kind = StreamKind.audio,
  }) async {
    String? playerPot;
    // VisitorData per TUTTI i client: serve l'header X-Goog-Visitor-Id che
    // yt-dlp manda sempre (senza, Google risponde "Sign in to confirm you're
    // not a bot" anche ai client nativi). Per i web si usa quello della
    // WEBVIEW (il pot è legato a quella sessione); per i nativi basta quello
    // recuperato dalla homepage.
    if (spec.wantsVisitorData) {
      final wvd = await webVisitorDataProvider?.call();
      if (wvd != null && wvd.isNotEmpty) {
        _visitorData = wvd;
        _visitorDataAt = DateTime.now();
      }
    }
    await _ensureVisitorData(cookie);
    if (spec.wantsVisitorData &&
        _visitorData != null &&
        _visitorData!.isNotEmpty) {
      playerPot = await potProvider?.call(_visitorData!);
      developer.log(
        'RESOLVE ${spec.name}: playerPot=${playerPot != null ? "ok" : "no"}',
      );
    }
    int? sts;
    if (spec.wantsVisitorData) sts = await _ensureSignatureTimestamp(cookie);
    final body = <String, dynamic>{
      ..._payloadFor(spec, _visitorData),
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      if (sts != null)
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            'signatureTimestamp': sts,
          },
        },
      if (playerPot != null && playerPot.isNotEmpty)
        'serviceIntegrityDimensions': {'poToken': playerPot},
    };
    final resp = await _http
        .post(
          Uri.parse(spec.endpoint),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': spec.userAgent,
            ..._ytHeaders(spec, _visitorData),
            if (spec.sendsCookie && cookie.isNotEmpty) 'Cookie': cookie,
            if (spec.sendsAuth && cookie.isNotEmpty)
              ..._authHeaders(cookie, spec.endpoint),
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      developer.log(
        'RESOLVE ' + spec.name + ': player HTTP ' + resp.statusCode.toString(),
      );
      return null;
    }
    final data = jsonDecode(resp.body) as Map;
    final status = data['playabilityStatus']?['status']?.toString();
    if (status != 'OK') {
      developer.log(
        'RESOLVE ' +
            spec.name +
            ': playability ' +
            (status ?? '?') +
            ' ' +
            (data['playabilityStatus']?['reason']?.toString() ?? ''),
      );
      return null;
    }
    final sd = data['streamingData'] as Map? ?? {};
    final hlsUrl = sd['hlsManifestUrl'] as String?;
    _noteLoudness(videoId, data, sd);

    // HLS manifest: segmented delivery is immune to the progressive-URL
    // truncation, so when preferred (retries) it goes first.
    if (preferHls && hlsUrl != null) {
      final ok = await _probeHls(hlsUrl, spec.userAgent);
      if (ok) {
        developer.log('RESOLVE scelto: ' + spec.name + ' HLS');
        return ResolvedStream(
          url: hlsUrl,
          userAgent: spec.userAgent,
          isHls: true,
          clientName: spec.name,
        );
      }
    }

    // Per il video: H.264 in mp4, che ogni dispositivo decodifica in
    // hardware, e non piu' alto di quanto serva. La copertina animata e'
    // un riquadro: 480 righe bastano, e sono un decimo dei byte del 1080.
    bool wanted(Map f) {
      final mime = f['mimeType'] as String? ?? '';
      final height = (f['height'] as num?)?.toInt() ?? 0;
      return switch (kind) {
        StreamKind.audio => mime.startsWith('audio/'),
        StreamKind.videoOnly =>
          mime.startsWith('video/mp4') &&
              mime.contains('avc1') &&
              height <= 480,
        // Da guardare a tutto schermo: fino al 1080.
        StreamKind.videoHigh =>
          mime.startsWith('video/mp4') &&
              mime.contains('avc1') &&
              height <= 1080,
        StreamKind.muxed => mime.startsWith('video/mp4'),
      };
    }

    final formats =
        (sd[kind == StreamKind.muxed ? 'formats' : 'adaptiveFormats']
                    as List? ??
                const [])
            .whereType<Map>()
            .where(wanted)
            .where((f) => f['url'] is String)
            .map(
              (f) => (
                url: f['url'] as String,
                bitrate: (f['bitrate'] as num?)?.toInt() ?? 0,
                itag: (f['itag'] as num?)?.toInt() ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

    // PO Token legato al video per gli URL media (GVS): i client web
    // lo pretendono, altrimenti servono solo ~1 MiB e poi 403.
    String? gvsPot;
    if (spec.wantsVisitorData && formats.isNotEmpty) {
      gvsPot = await potProvider?.call(videoId);
      developer.log(
        'RESOLVE ${spec.name}: gvsPot=${gvsPot != null ? "ok" : "no"}',
      );
    }

    for (final f in formats) {
      final url = (gvsPot == null || gvsPot.isEmpty)
          ? f.url
          : Uri.parse(f.url)
                .replace(
                  queryParameters: {
                    ...Uri.parse(f.url).queryParameters,
                    'pot': gvsPot,
                  },
                )
                .toString();
      final total = lenient
          ? await validateInitialWindow(url, spec.userAgent)
          : await validateProgressive(url, spec.userAgent);
      if (total != null) {
        // URL progressivo limitato ma il client offre HLS? L'HLS è
        // IMMUNE dal taglio dei ~1 MiB: preferiscilo SEMPRE prima di
        // accettare uno stream che morirà a metà canzone.
        if (lenient &&
            hlsUrl != null &&
            await _probeHls(hlsUrl, spec.userAgent)) {
          developer.log(
            'RESOLVE scelto: ${spec.name} HLS (al posto del progressivo limitato)',
          );
          return ResolvedStream(
            url: hlsUrl,
            userAgent: spec.userAgent,
            isHls: true,
            clientName: spec.name,
          );
        }
        developer.log(
          'RESOLVE scelto: ' +
              spec.name +
              ' itag=' +
              f.itag.toString() +
              ' bitrate=' +
              f.bitrate.toString() +
              ' size=' +
              total.toString() +
              (gvsPot != null ? ' POT' : '') +
              (lenient ? ' LIMITED (finestra ~1MiB, stitching attivo)' : ''),
        );
        return ResolvedStream(
          url: url,
          userAgent: spec.userAgent,
          isHls: false,
          clientName: spec.name,
          limited: lenient,
          itag: f.itag,
          bitrate: f.bitrate,
        );
      }
    }

    // Progressive failed but HLS exists: last chance within this client.
    if (!preferHls && hlsUrl != null) {
      final ok = await _probeHls(hlsUrl, spec.userAgent);
      if (ok) {
        developer.log('RESOLVE scelto: ' + spec.name + ' HLS (fallback)');
        return ResolvedStream(
          url: hlsUrl,
          userAgent: spec.userAgent,
          isHls: true,
          clientName: spec.name,
        );
      }
    }
    return null;
  }

  /// LENIENT check: only verifies the URL serves its initial window
  /// (first 64 KiB). Used as fallback when no strictly-valid URL
  /// exists; the proxy then stitches limited windows mid-song.
  Future<int?> validateInitialWindow(String url, String ua) async {
    try {
      final head = await rangedGet(url, ua, 0, 65535);
      if (head == null) return null;
      if ((head.status != 200 && head.status != 206) ||
          head.body.length < 1024) {
        return null;
      }
      return head.totalFromContentRange ?? head.body.length;
    } catch (_) {
      return null;
    }
  }

  /// Validates a progressive URL exactly like the player will use it:
  /// a small range at 0 and — the part that catches flagged URLs — a
  /// second range beyond the ~1 MiB soft-block window. Returns the
  /// total size in bytes, or null when any probe fails.
  Future<int?> validateProgressive(String url, String ua) async {
    try {
      final head = await rangedGet(url, ua, 0, 65535);
      if (head == null) return null;
      if ((head.status != 200 && head.status != 206) ||
          head.body.length < 1024) {
        return null;
      }
      final total = head.totalFromContentRange ?? head.body.length;
      // Second probe past the soft-block window (~1 MiB).
      int offset;
      if (total > 2 * 1048576 + 131072) {
        offset = 2 * 1048576;
      } else if (total > 262144) {
        offset = total - 65536;
      } else {
        offset = -1; // tiny file: first probe already covered it all
      }
      if (offset >= 0) {
        final tail = await rangedGet(url, ua, offset, offset + 65535);
        if (tail == null) return null;
        if ((tail.status != 200 && tail.status != 206) ||
            tail.body.length < 1024) {
          developer.log('RESOLVE probe oltre 1MiB fallita (URL flagged)');
          return null;
        }
      }
      return total;
    } catch (e) {
      developer.log('RESOLVE probe eccezione: ' + e.toString());
      return null;
    }
  }

  Future<bool> _probeHls(String url, String ua) async {
    try {
      final resp = await _http
          .get(Uri.parse(url), headers: {'User-Agent': ua})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final body = resp.body;
      return body.contains('#EXTM3U') && body.contains('#EXTINF');
    } catch (_) {
      return false;
    }
  }

  /// Diagnosi completa eseguita SUL DEVICE: per ogni client InnerTube
  /// riporta playability, formati, sonde range (0-64K / oltre 1 MiB /
  /// fine file) e test HLS con segmenti fino a superare il confine 1 MiB.
  Future<List<String>> diagnose(String videoId) async {
    final out = <String>[];
    final cookie = cookieProvider()?.trim() ?? '';
    final hasCookie = cookie.isNotEmpty;
    out.add('cookie: ${hasCookie ? "presente" : "ASSENTE"}');
    String? vd = await _ensureVisitorData(cookie);
    out.add(
      'visitorData: ${vd != null ? "ok (${vd.length} char)" : "NON DISPONIBILE"}',
    );
    out.add('');

    for (final spec in _clients) {
      if (spec.sendsCookie && !hasCookie) {
        out.add('── ${spec.name}: SKIP (richiede cookie)');
        continue;
      }
      try {
        String? playerPot;
        int? sts;
        if (spec.wantsVisitorData) {
          final wvd = await webVisitorDataProvider?.call();
          if (wvd != null && wvd.isNotEmpty) {
            vd = wvd;
            _visitorData = wvd;
            _visitorDataAt = DateTime.now();
            out.add('   visitorData dalla WEBVIEW (${wvd.length} char)');
          }
          if (vd != null && vd.isNotEmpty) {
            playerPot = await potProvider?.call(vd);
          }
          out.add(
            '   potPlayer: ${playerPot != null ? "ALLEGATO" : "MANCANTE"}',
          );
          sts = await _ensureSignatureTimestamp(cookie);
        }
        final resp = await _http
            .post(
              Uri.parse(spec.endpoint),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': spec.userAgent,
                ..._ytHeaders(spec, vd),
                if (spec.wantsVisitorData) ...{
                  'Referer': '${_originOf(spec.endpoint)}/',
                  'X-Origin': _originOf(spec.endpoint),
                },
                if (spec.sendsCookie && cookie.isNotEmpty) 'Cookie': cookie,
                if (spec.sendsAuth && cookie.isNotEmpty)
                  ..._authHeaders(cookie, spec.endpoint),
              },
              body: jsonEncode({
                ..._payloadFor(spec, vd),
                'videoId': videoId,
                'contentCheckOk': true,
                'racyCheckOk': true,
                if (sts != null)
                  'playbackContext': {
                    'contentPlaybackContext': {
                      'html5Preference': 'HTML5_PREF_WANTS',
                      'signatureTimestamp': sts,
                    },
                  },
                if (playerPot != null && playerPot.isNotEmpty)
                  'serviceIntegrityDimensions': {'poToken': playerPot},
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) {
          out.add('── ${spec.name}: HTTP ${resp.statusCode}');
          continue;
        }
        final data = jsonDecode(resp.body) as Map;
        final st = data['playabilityStatus']?['status'];
        final reason = data['playabilityStatus']?['reason'] ?? '';
        if (st != 'OK') {
          out.add('── ${spec.name}: $st ($reason)');
          continue;
        }
        final sd = data['streamingData'] as Map? ?? {};
        final audio =
            ((sd['adaptiveFormats'] ?? []) as List)
                .whereType<Map>()
                .where(
                  (f) =>
                      (f['mimeType'] as String? ?? '').startsWith('audio/') &&
                      f['url'] is String,
                )
                .toList()
              ..sort(
                (a, b) => ((b['bitrate'] as num?) ?? 0).compareTo(
                  ((a['bitrate'] as num?) ?? 0),
                ),
              );
        final hls = sd['hlsManifestUrl'] as String?;
        out.add(
          '── ${spec.name}: OK · ${audio.length} audio · '
          'hls=${hls != null ? "SÌ" : "no"} · '
          'potPlayer=${playerPot != null ? "sì" : "NO"}',
        );

        if (audio.isNotEmpty) {
          final f = audio.first;
          final clen = int.tryParse('${f['contentLength']}') ?? 0;
          final url = f['url'] as String;
          out.add(
            '   top itag=${f['itag']} bitrate=${f['bitrate']} '
            'size=$clen',
          );
          String? gvsPot;
          if (spec.wantsVisitorData) {
            gvsPot = await potProvider?.call(videoId);
            out.add('   potGVS: ${gvsPot != null ? "ok" : "NO"}');
          }
          final urlWithPot = (gvsPot == null || gvsPot.isEmpty)
              ? url
              : Uri.parse(url)
                    .replace(
                      queryParameters: {
                        ...Uri.parse(url).queryParameters,
                        'pot': gvsPot,
                      },
                    )
                    .toString();
          final p0 = await rangedGet(urlWithPot, spec.userAgent, 0, 65535);
          out.add(
            '   probe 0-64K: ${p0?.status} '
            '${p0?.body.length ?? 0}B',
          );
          final p1 = await rangedGet(
            urlWithPot,
            spec.userAgent,
            1048576,
            1114111,
          );
          out.add(
            '   probe OLTRE-1MiB: ${p1?.status} '
            '${p1?.body.length ?? 0}B',
          );
          if (clen > 131072) {
            final off = clen - 65536;
            final p2 = await rangedGet(
              urlWithPot,
              spec.userAgent,
              off,
              clen - 1,
            );
            out.add(
              '   probe FINE-FILE: ${p2?.status} '
              '${p2?.body.length ?? 0}B',
            );
          }
        }

        if (hls != null) {
          try {
            final m3u8 = await _http
                .get(Uri.parse(hls), headers: {'User-Agent': spec.userAgent})
                .timeout(const Duration(seconds: 12));
            if (m3u8.statusCode == 200 && m3u8.body.contains('#EXTM3U')) {
              final segs = m3u8.body
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
                  .toList();
              out.add('   m3u8 OK: ${segs.length} segmenti');
              var cum = 0;
              String? fail;
              for (var i = 0; i < segs.length && cum < 1300000; i++) {
                final s = segs[i].trim();
                final u = s.startsWith('http')
                    ? s
                    : hls.substring(0, hls.lastIndexOf('/') + 1) + s;
                try {
                  final r = await _http.get(
                    Uri.parse(u),
                    headers: {'User-Agent': spec.userAgent},
                  );
                  if (r.statusCode != 200 && r.statusCode != 206) {
                    fail = 'segmento $i (~$cum B): ${r.statusCode}';
                    break;
                  }
                  cum += r.bodyBytes.length;
                } catch (e) {
                  fail = 'segmento $i: errore $e';
                  break;
                }
              }
              if (fail != null) {
                out.add('   HLS: $fail');
              } else {
                out.add('   HLS: $cum B scaricati — OLTRE 1MiB ✓');
              }
            } else {
              out.add('   m3u8: HTTP ${m3u8.statusCode}');
            }
          } catch (e) {
            out.add('   m3u8 errore: $e');
          }
        }
      } catch (e) {
        out.add('── ${spec.name}: ERRORE $e');
      }
      out.add('');
    }
    return out;
  }

  /// GET of a byte range, body buffered (probes are <= ~64 KiB).
  Future<_ProbeResult?> rangedGet(
    String url,
    String ua,
    int start,
    int end,
  ) async {
    final resp = await _http
        .get(
          Uri.parse(url),
          headers: {
            'Range': 'bytes=' + start.toString() + '-' + end.toString(),
            'User-Agent': ua,
          },
        )
        .timeout(const Duration(seconds: 10));
    // http.Response buffers the body already; probes ask for <=64 KiB
    // ranges so this stays small.
    final body = resp.bodyBytes;
    int? total;
    final cr = resp.headers['content-range'];
    if (cr != null) {
      final m = RegExp(r'/([0-9]+)[ ]*$').firstMatch(cr);
      if (m != null) total = int.tryParse(m.group(1)!);
    }
    return _ProbeResult(resp.statusCode, body, total);
  }

  void dispose() => _http.close();
}
