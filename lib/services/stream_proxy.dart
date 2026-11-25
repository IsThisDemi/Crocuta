import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

/// A (re-)resolved upstream source handed back by a refresh callback.
class ProxiedStreamSource {
  final String url;
  final String? userAgent;
  const ProxiedStreamSource(this.url, {this.userAgent});
}

/// Local HTTP proxy that feeds the player (libmpv) from a YouTube
/// stream URL, adding the headers YouTube requires (Range and the
/// User-Agent bound to the InnerTube client that produced the URL).
///
/// Stream URLs are registered under a short numeric id
/// (http://127.0.0.1:PORT/s/1) because libmpv/ffmpeg fails on very
/// long URLs (YouTube stream URLs are ~3000 characters).
///
/// Anti-bot hardening. Google flags some issued URLs and enforces it
/// on ranged GETs of the media itself. Measured behaviour of a flagged
/// URL: spans up to ~768 KiB inside the served window return 206, a
/// full 1 MiB request or anything beyond ~1 MiB gets 403. Crucially,
/// every freshly-issued URL comes with a FRESH window starting at its
/// own byte 0, and issuing new URLs is not rate-limited.
///
/// The proxy therefore STITCHES windows: it serves libmpv one
/// continuous byte range while internally rotating URLs through the
/// [refresh] callback whenever the current one runs dry, resuming at
/// the exact global byte reached. Adaptive slice size keeps healthy
/// unflagged URLs at one upstream request per response.
///
/// Responses are buffered fully before being sent (windows <=1 MiB)
/// so truncated upstream data never reaches the player mid-body.
class StreamProxy {
  HttpServer? _server;
  final _client = http.Client();

  final Map<int, _Entry> _entries = {};
  int _nextId = 1;

  int get port => _server?.port ?? 0;

  bool get isRunning => _server != null;

  /// Starts the proxy on an ephemeral localhost port.
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  /// Registers [streamUrl] and returns a short localhost URL for it.
  ///
  /// [userAgent]: UA required by the client that produced the URL.
  /// [hls]: target is an m3u8 playlist whose segment URIs are rewritten
  /// to go through the proxy as well.
  /// [refresh]: called whenever the current upstream runs dry; must
  /// return a fresh source for the SAME media (its serving window then
  /// restarts at byte 0).
  String proxiedUrl(
    String streamUrl, {
    String? userAgent,
    bool hls = false,
    Future<ProxiedStreamSource?> Function()? refresh,
  }) {
    final id = _nextId++;
    _entries[id] = _Entry(
      url: streamUrl,
      userAgent: userAgent,
      hls: hls,
      refresh: refresh,
    );
    return 'http://127.0.0.1:' + port.toString() + '/s/' + id.toString();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length != 2 || segments[0] != 's') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final id = int.tryParse(segments[1]);
      final entry = id == null ? null : _entries[id];
      developer.log(
        'PROXY: richiesta ' +
            request.uri.path +
            ' range=' +
            (request.headers.value(HttpHeaders.rangeHeader) ?? '-'),
      );
      if (entry == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      if (entry.hls) {
        await _servePlaylist(response, entry);
      } else {
        await _serveChunk(request, response, entry);
      }
    } catch (e) {
      developer.log('PROXY: errore ' + e.toString());
      try {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
      } catch (_) {}
    }
  }

  // -----------------------------------------------------------------
  // Progressive streams with window stitching
  // -----------------------------------------------------------------

  Future<void> _serveChunk(
    HttpRequest request,
    HttpResponse response,
    _Entry entry,
  ) async {
    final window = _windowFor(
      request.headers.value(HttpHeaders.rangeHeader),
      entry.total,
    );

    final buffer = <int>[];
    var pos = window.start;
    var refreshesUsed = 0;
    int? learnedTotal;
    String? contentType;

    // ADAPTIVE stitch loop. Measured Google cap on flagged URLs:
    // spans <=~768 KiB inside the window work, full 1 MiB gets 403,
    // beyond the window it is 403 too. Healthy URLs finish in ONE big
    // request; limited ones rotate through fresh windows.
    const maxSub = 786432; // 768 KiB
    var remaining = window.end - pos + 1;
    var tryLen = remaining.clamp(0, maxSub);

    for (var round = 0; round < 40 && pos <= window.end; round++) {
      var innerStart = pos - entry.segStart;
      if (innerStart < 0) innerStart = 0;
      final innerEnd = innerStart + tryLen - 1;

      final result = await _fetchRange(
        entry.url,
        entry.userAgent,
        innerStart,
        innerEnd,
      );

      if (result.total != null && result.total! > 0) {
        learnedTotal = result.total;
      }
      if (result.contentType != null) contentType = result.contentType;

      final got = result.body.length;
      if (got > 0) {
        buffer.addAll(result.body);
        pos += got;
      }
      if (pos > window.end) break;

      remaining = window.end - pos + 1;
      if (got == tryLen && got > 0) {
        // Full success: keep asking big.
        tryLen = remaining.clamp(0, maxSub);
        continue;
      }
      if (got > 0) {
        // Truncated mid-request: keep bytes, shrink next slice.
        tryLen = remaining.clamp(0, 262144);
      }

      // No data -> current window is exhausted/flagged: rotate URL.
      if (refreshesUsed >= 12) break;
      refreshesUsed++;
      developer.log(
        'PROXY: finestra esaurita a pos=' +
            pos.toString() +
            ', refresh n.' +
            refreshesUsed.toString(),
      );
      final fresh = await _maybeRefresh(entry);
      if (!fresh) break;
      entry.segStart = pos;
      tryLen = remaining.clamp(0, 262144);
    }

    if (buffer.isEmpty) {
      developer.log(
        'PROXY: finestra ' +
            window.start.toString() +
            '-' +
            window.end.toString() +
            ' non servibile',
      );
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }

    if (learnedTotal != null && learnedTotal > 0) entry.total = learnedTotal;

    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      contentType ?? 'application/octet-stream',
    );
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ' +
          window.start.toString() +
          '-' +
          (window.start + buffer.length - 1).toString() +
          '/' +
          (entry.total ?? 0).toString(),
    );
    response.headers.set(
      HttpHeaders.contentLengthHeader,
      buffer.length.toString(),
    );
    response.add(buffer);
    await response.close();
  }

  /// One ranged GET against an absolute inner range of the current
  /// URL. Returns whatever arrived plus bookkeeping fields.
  Future<_RangeResult> _fetchRange(
    String url,
    String? ua,
    int innerStart,
    int innerEnd,
  ) async {
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['Range'] =
          'bytes=' + innerStart.toString() + '-' + innerEnd.toString();
      if (ua != null) req.headers[HttpHeaders.userAgentHeader] = ua;
      final streamed = await _client
          .send(req)
          .timeout(const Duration(seconds: 25));

      if (streamed.statusCode != 200 && streamed.statusCode != 206) {
        developer.log(
          'PROXY: upstream HTTP ' +
              streamed.statusCode.toString() +
              ' su ' +
              innerStart.toString() +
              '-' +
              innerEnd.toString(),
        );
        await streamed.stream.drain<void>().catchError((_) {});
        return _RangeResult.empty();
      }

      int? total;
      final cr = streamed.headers['content-range'];
      if (cr != null) {
        final slash = cr.lastIndexOf('/');
        if (slash >= 0 && slash + 1 < cr.length) {
          total = int.tryParse(cr.substring(slash + 1).trim());
        }
      }

      final body = <int>[];
      var lastByteAt = DateTime.now().millisecondsSinceEpoch;
      final startedAt = lastByteAt;
      try {
        await for (final chunk in streamed.stream) {
          body.addAll(chunk);
          lastByteAt = DateTime.now().millisecondsSinceEpoch;
          // Stall guards: 45s total per request or 10s without bytes.
          if (lastByteAt - startedAt > 45000 ||
              DateTime.now().millisecondsSinceEpoch - lastByteAt > 10000) {
            break;
          }
        }
      } catch (_) {
        // connection cut mid-body: keep what arrived (partial)
      }
      return _RangeResult(
        body,
        streamed.contentLength,
        total,
        streamed.headers['content-type'],
      );
    } catch (e) {
      developer.log(
        'PROXY: eccezione range ' +
            innerStart.toString() +
            '-' +
            innerEnd.toString() +
            ': ' +
            e.toString(),
      );
      return _RangeResult.empty();
    }
  }

  // -----------------------------------------------------------------
  // HLS playlists
  // -----------------------------------------------------------------

  Future<void> _servePlaylist(HttpResponse response, _Entry entry) async {
    for (var attemptNo = 0; attemptNo < 3; attemptNo++) {
      final body = await _fetchPlaylistBody(entry);
      if (body != null) {
        final rewritten = _rewriteHls(body, entry);
        final bytes = rewritten.codeUnits;
        response.statusCode = HttpStatus.ok;
        response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/vnd.apple.mpegurl',
        );
        response.headers.set(
          HttpHeaders.contentLengthHeader,
          bytes.length.toString(),
        );
        response.add(bytes);
        await response.close();
        return;
      }
      final refreshed = await _maybeRefresh(entry);
      if (!refreshed) break;
    }
    response.statusCode = HttpStatus.badGateway;
    await response.close();
  }

  Future<String?> _fetchPlaylistBody(_Entry entry) async {
    try {
      final resp = await _client
          .get(
            Uri.parse(entry.url),
            headers: {
              if (entry.userAgent != null)
                HttpHeaders.userAgentHeader: entry.userAgent!,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      if (!resp.body.contains('#EXTM3U')) return null;
      return resp.body;
    } catch (e) {
      developer.log('PROXY: playlist non scaricabile: ' + e.toString());
      return null;
    }
  }

  /// Rewrites an HLS playlist so every segment URI goes through us.
  String _rewriteHls(String playlist, _Entry entry) {
    final out = <String>[];
    final nl = String.fromCharCode(10);
    for (final line in playlist.split(nl)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('http')) {
        out.add(proxiedUrl(trimmed, userAgent: entry.userAgent));
        continue;
      }
      if (trimmed.contains('URI="')) {
        out.add(
          trimmed.replaceAllMapped(RegExp('URI="[^"]*"'), (m) {
            final raw = m.group(0)!;
            final uri = raw.substring(5, raw.length - 1);
            final resolved = uri.startsWith('http')
                ? uri
                : Uri.parse(entry.url).resolve(uri).toString();
            return 'URI="' +
                proxiedUrl(resolved, userAgent: entry.userAgent) +
                '"';
          }),
        );
        continue;
      }
      out.add(line);
    }
    return out.join(nl);
  }

  // -----------------------------------------------------------------
  // Refresh plumbing
  // -----------------------------------------------------------------

  Future<bool> _maybeRefresh(_Entry entry) async {
    if (entry.refresh == null) return false;
    try {
      final fresh = await entry.refresh!().timeout(const Duration(seconds: 70));
      if (fresh == null || fresh.url.isEmpty) return false;
      entry.refreshCount++;
      developer.log('PROXY: refresh URL n.' + entry.refreshCount.toString());
      entry.url = fresh.url;
      if (fresh.userAgent != null) entry.userAgent = fresh.userAgent;
      return true;
    } catch (e) {
      developer.log('PROXY: refresh fallito: ' + e.toString());
      return false;
    }
  }

  // -----------------------------------------------------------------
  // Range math (regex-free)
  // -----------------------------------------------------------------

  _Window _windowFor(String? header, int? total) {
    const maxWindow = 1048576; // 1 MiB
    var start = 0;
    int? end;

    final parsed = _parseBytes(header);
    if (parsed != null) {
      start = parsed.$1;
      end = parsed.$2;
    }
    if (end == null) {
      end = start + maxWindow - 1;
    }
    if (end - start + 1 > maxWindow) {
      end = start + maxWindow - 1;
    }
    if (total != null && total > 0 && end >= total) {
      end = total - 1;
    }
    if (end < start) end = start;
    return _Window(start, end);
  }

  (int, int?)? _parseBytes(String? header) {
    if (header == null) return null;
    var h = header.trim();
    if (h.length < 6) return null;
    h = h.substring(0, 6).toLowerCase() == 'bytes=' ? h.substring(6) : '';
    if (h.isEmpty) return null;
    final dash = h.indexOf('-');
    if (dash < 0) return null;
    final startTxt = h.substring(0, dash).trim();
    final endTxt = h.substring(dash + 1).trim();
    final start = startTxt.isEmpty ? 0 : int.tryParse(startTxt);
    if (start == null) return null;
    final end = endTxt.isEmpty ? null : int.tryParse(endTxt);
    return (start, end);
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _entries.clear();
    _client.close();
  }
}

class _Entry {
  String url;
  String? userAgent;
  final bool hls;
  final Future<ProxiedStreamSource?> Function()? refresh;

  /// How many times this entry has been refreshed (for logs).
  int refreshCount = 0;

  /// Global offset where the CURRENT url's serving window begins.
  /// After every refresh it becomes the global position reached,
  /// because a fresh URL serves again from its own byte 0.
  int segStart = 0;

  int? total;

  _Entry({required this.url, required this.hls, this.userAgent, this.refresh});
}

class _Window {
  final int start;
  final int end;
  const _Window(this.start, this.end);
}

class _RangeResult {
  final List<int> body;
  final int? declaredLength;
  final int? total;
  final String? contentType;
  const _RangeResult(
    this.body,
    this.declaredLength,
    this.total, [
    this.contentType,
  ]);
  static _RangeResult empty() => const _RangeResult(<int>[], null, null);
}
