import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'stream_resolver.dart';

/// Result of a completed preload.
class PreloadedSong {
  final File file;

  /// True when the bytes were already in cache before this call.
  final bool fromCache;

  /// How long the download took (0 when cached).
  final Duration elapsed;

  const PreloadedSong(this.file, this.fromCache, this.elapsed);
}

/// Scarica un brano INTERO in un file locale, ricucendo le finestre di
/// distribuzione di Google (ogni URL appena emesso serve circa il suo primo
/// MiB, e un URL nuovo riparte dal proprio byte zero).
///
/// I file stanno in due cartelle, e la differenza conta:
///
/// - `songcache/` e' la scorta opportunistica, riempita mandando avanti il
///   brano successivo e sfrattata quando supera il tetto. Serve a far
///   partire il brano dopo senza attesa.
/// - `downloads/` sono i brani che hai scelto tu. Non vengono mai sfrattati
///   e restano disponibili senza rete.
///
/// Entrambe le cartelle vengono lette prima di andare in rete. Fino a ieri
/// non lo erano: si scaricavano gigabyte che nessuno riapriva mai.
class SongPreloader {
  final StreamResolver resolver;
  final http.Client _http = http.Client();
  final Map<String, Future<File?>> _inflight = {};

  SongPreloader({required this.resolver});

  Directory? _cache;
  Directory? _downloads;

  Future<Directory> _dir({bool permanent = false}) async {
    final cached = permanent ? _downloads : _cache;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(
      base.path + (permanent ? '/downloads' : '/songcache'),
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (permanent) {
      _downloads = dir;
    } else {
      _cache = dir;
    }
    return dir;
  }

  /// Tetto della scorta opportunistica.
  ///
  /// Era 2 GB, da quando nessuno rileggeva quei file: una libreria intera
  /// accumulata per niente. Ora che serve solo a mandare avanti il brano
  /// successivo, mezzo giga e' gia' abbondante — e cio' che vuoi tenere
  /// davvero lo scarichi, e finisce nell'altra cartella.
  static const int maxCacheBytes = 512 * 1024 * 1024;

  /// Il file locale di un brano, se c'e' ed e' integro.
  ///
  /// Prima i download scelti da te, poi la scorta. E' il metodo che il
  /// player chiama prima di rivolgersi alla rete.
  Future<File?> fileFor(String videoId) async {
    for (final permanent in [true, false]) {
      final dir = await _dir(permanent: permanent);
      final f = File(dir.path + '/' + videoId + '.audio');
      if (_isComplete(f, File(dir.path + '/' + videoId + '.len'))) return f;
    }
    return null;
  }

  /// Un file vale solo se il `.len` accanto dichiara la sua stessa
  /// dimensione: le versioni vecchie potevano lasciare troncature (~1 MiB,
  /// il famigerato taglio a 1:04) e venivano riusate all'infinito.
  bool _isComplete(File audio, File len) {
    if (!audio.existsSync() || !len.existsSync()) return false;
    if (audio.lengthSync() <= 4096) return false;
    return int.tryParse(len.readAsStringSync().trim()) == audio.lengthSync();
  }

  /// Gli id dei brani scaricati apposta.
  Future<Set<String>> downloadedIds() async {
    final dir = await _dir(permanent: true);
    return {
      for (final f in dir.listSync())
        if (f is File && f.path.endsWith('.audio'))
          f.uri.pathSegments.last.replaceAll('.audio', ''),
    };
  }

  /// Cancella un download scelto. La scorta non si tocca: quella si sfratta
  /// da sola.
  Future<void> removeDownload(String videoId) async {
    final dir = await _dir(permanent: true);
    for (final ext in ['.audio', '.len']) {
      final f = File(dir.path + '/' + videoId + ext);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Total size of the cached audio files.
  Future<int> cacheSizeBytes({bool permanent = false}) async {
    final dir = await _dir(permanent: permanent);
    var total = 0;
    for (final f in dir.listSync()) {
      if (f is File) total += f.lengthSync();
    }
    return total;
  }

  /// Evicts the least recently used songs until the cache fits its budget.
  ///
  /// Nothing ever deleted these files, so a few hundred tracks at 4-10 MB
  /// each quietly grew to gigabytes inside the sandbox container, where the
  /// user would never find them.
  ///
  /// [keepId] is never evicted — that would pull the file out from under the
  /// track currently playing.
  Future<void> prune({int? maxBytes, String? keepId}) async {
    final limit = maxBytes ?? maxCacheBytes;
    try {
      final dir = await _dir();
      final songs = <File>[];
      var total = 0;
      for (final f in dir.listSync()) {
        if (f is File && f.path.endsWith('.audio')) {
          songs.add(f);
          total += f.lengthSync();
        }
      }
      if (total <= limit) return;

      songs.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );

      // Drop to 90% of the budget rather than exactly to it, so the next
      // launch does not immediately prune again for the sake of one file.
      final target = (limit * 0.9).round();
      for (final f in songs) {
        if (total <= target) break;
        final id = f.uri.pathSegments.last.replaceAll('.audio', '');
        if (id == keepId || _inflight.containsKey(id)) continue;
        final size = f.lengthSync();
        try {
          f.deleteSync();
          File(dir.path + '/' + id + '.len').deleteSync();
        } catch (_) {
          continue;
        }
        total -= size;
      }
    } catch (_) {
      // Housekeeping is best-effort: never let it break playback.
    }
  }

  /// Returns the cached local file, downloading it when missing.
  /// Returns null when even the first window cannot be fetched.
  Future<PreloadedSong?> ensureDownloaded(
    String videoId, {
    void Function(double progress)? onProgress,

    /// true lo mette fra i download scelti, che non vengono mai sfrattati.
    bool permanent = false,
  }) async {
    final dir = await _dir(permanent: permanent);
    final dest = File(dir.path + '/' + videoId + '.audio');
    final lenFile = File(dir.path + '/' + videoId + '.len');

    // Cache hit SOLO se il lato file corrisponde alla dimensione attesa:
    // le vecchie versioni potevano salvare file parziali (~1 MiB = il
    // famigerato taglio a 1:04) e venivano riusati all'infinito.
    if (_isComplete(dest, lenFile)) {
      // Mark it as freshly used: prune() evicts by modification time, and
      // without this touch the cache would be FIFO by download date, quietly
      // throwing out the song you replay every day in favour of one you
      // heard once.
      try {
        dest.setLastModifiedSync(DateTime.now());
      } catch (_) {}
      return PreloadedSong(dest, true, Duration.zero);
    }
    // Cache priva di metadati o corrotta: elimina e riscarica.
    if (dest.existsSync()) {
      try {
        dest.deleteSync();
        if (lenFile.existsSync()) lenFile.deleteSync();
      } catch (_) {}
    }

    final existing = _inflight[videoId];
    if (existing != null) {
      try {
        final f = await existing;
        if (f != null && f.existsSync()) {
          return PreloadedSong(f, false, Duration.zero);
        }
      } catch (_) {}
    }

    // Se il brano e' gia' nella scorta, un download scelto e' solo uno
    // spostamento: scaricarlo di nuovo sarebbe banda buttata.
    if (permanent) {
      final cached = await _dir();
      final from = File(cached.path + '/' + videoId + '.audio');
      final fromLen = File(cached.path + '/' + videoId + '.len');
      if (_isComplete(from, fromLen)) {
        try {
          from.renameSync(dest.path);
          fromLen.renameSync(lenFile.path);
          return PreloadedSong(dest, true, Duration.zero);
        } catch (_) {}
      }
    }

    final task = _download(videoId, dest, onProgress);
    _inflight[videoId] = task;
    try {
      final f = await task;
      if (f == null) return null;
      return PreloadedSong(f, false, Duration.zero);
    } finally {
      _inflight.remove(videoId);
    }
  }

  Future<File?> _download(
    String videoId,
    File dest,
    void Function(double progress)? onProgress,
  ) async {
    final sw = Stopwatch()..start();
    var attempt = 0;
    // HLS first: i segmenti sono immuni al taglio progressivo da ~1 MiB,
    // quindi il file in cache è sempre completo. Ripiega sul progressivo
    // solo se l'HLS non è offerto/non scaricabile.
    var rs = await resolver.resolve(videoId, attempt: attempt, preferHls: true);
    rs ??= await resolver.resolve(
      videoId,
      attempt: ++attempt,
      preferHls: false,
    );
    if (rs == null) debugPrint('PRELOAD: resolve NULL per ' + videoId);
    if (rs != null && rs.isHls) debugPrint('PRELOAD: solo HLS, non gestito');
    if (rs == null || rs.isHls) return null;
    debugPrint(
      'PRELOAD inizio: ' +
          videoId +
          ' via ' +
          rs.clientName +
          ' limited=' +
          rs.limited.toString(),
    );

    final tmp = File(dest.path + '.part');
    final dir = dest.parent;
    final sink = tmp.openWrite();
    var pos = 0; // offset ASSOLUTO nel file: mai ri-partire da 0 con un URL
    // fresco, altrimenti si scaricherebbe di nuovo l'inizio.
    int? total;
    var refreshes = 0;
    const maxChunk = 2097152;
    ResolvedStream cur = rs;

    try {
      while (refreshes <= 8) {
        if (total != null && pos >= total) break;
        final want = (total == null ? maxChunk : total - pos).clamp(
          1,
          maxChunk,
        );

        final res = await _get(cur.url, cur.userAgent, pos, pos + want - 1);
        if (res.total != null && res.total! > 0) total = res.total;

        if (res.body.isEmpty) {
          // Finestra/URL esaurito: risolvi un URL FRESH e riprova allo
          // STESSO offset assoluto. Se anche il nuovo rifiuta il range,
          // la sessione è limitata: abort pulito (null), niente file
          // corrotti con l'inizio duplicato.
          refreshes++;
          attempt++;
          final r2 = await resolver.resolve(
            videoId,
            attempt: attempt,
            preferHls: false,
          );
          if (r2 == null || r2.isHls) {
            if (refreshes >= 3 && pos < 4096) break; // niente dati: abort
            continue;
          }
          cur = r2;
          continue;
        }

        sink.add(res.body);
        pos += res.body.length;
        final t = total;
        if (t != null && t > 0 && onProgress != null) onProgress(pos / t);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      debugPrint('PRELOAD errore: ' + e.toString());
      await sink.close().catchError((_) {});
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }

    // Completeness check: se conosciamo il totale e mancano byte, il file
    // NON va in cache (si fermerebbe a meta' durante la riproduzione).
    if (total != null && pos < total) {
      debugPrint(
        'PRELOAD incompleto: ' +
            pos.toString() +
            '/' +
            total.toString() +
            'B, scarto',
      );
      if (tmp.existsSync()) tmp.deleteSync();
      return null;
    }

    if (pos < 4096) {
      debugPrint('PRELOAD: troppo poco dati (' + pos.toString() + 'B), null');
      if (tmp.existsSync()) tmp.deleteSync();
      return null;
    }
    if (tmp.existsSync()) tmp.renameSync(dest.path);
    // NB: percorso coerente con la lettura (<id>.len, NON .audio.len)
    File(dir.path + '/' + videoId + '.len').writeAsStringSync(pos.toString());
    sw.stop();
    debugPrint(
      'PRELOAD ok: ' +
          videoId +
          ' ' +
          pos.toString() +
          'B in ' +
          sw.elapsed.inSeconds.toString() +
          's (' +
          refreshes.toString() +
          ' finestre)',
    );
    return dest;
  }

  Future<_Range> _get(String url, String ua, int s, int e) async {
    final req = http.Request('GET', Uri.parse(url));
    req.headers['Range'] = 'bytes=' + s.toString() + '-' + e.toString();
    req.headers['User-Agent'] = ua;
    final streamed = await _http.send(req).timeout(const Duration(seconds: 25));
    if (streamed.statusCode != 200 && streamed.statusCode != 206) {
      await streamed.stream.drain<void>().catchError((_) {});
      return _Range.empty();
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
    var last = DateTime.now().millisecondsSinceEpoch;
    final start0 = last;
    try {
      await for (final chunk in streamed.stream) {
        body.addAll(chunk);
        last = DateTime.now().millisecondsSinceEpoch;
        if (last - start0 > 60000 ||
            DateTime.now().millisecondsSinceEpoch - last > 10000) {
          break;
        }
      }
    } catch (_) {}
    return _Range(body, streamed.contentLength, total);
  }

  /// Best-effort background warmup of the next track in queue.
  void warmup(String videoId) {
    ensureDownloaded(videoId).catchError((_) => null);
  }

  void dispose() => _http.close();
}

class _Range {
  final List<int> body;
  final int? declaredLength;
  final int? total;
  const _Range(this.body, this.declaredLength, this.total);
  static _Range empty() => const _Range(<int>[], null, null);
}
