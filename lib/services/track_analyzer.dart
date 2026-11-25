import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import 'beat_analysis.dart';
import 'beat_net.dart';
import 'heavy_work.dart';
import 'key_analysis.dart';
import 'onnx_net.dart';
import 'storage_service.dart';

/// Il modello dei battiti, scaricato da tool/fetch_models.sh.
const beatModelAsset = 'assets/models/beat_this.onnx';

/// Analizza i brani per AutoMix: tempo, battiti, inizio e fine veri.
///
/// L'audio si decodifica con un player mpv nascosto che invece di suonare
/// scrive su file (`ao=pcm`), mono a 22 kHz. Battiti e battute li trova
/// Beat This! (vedi beat_net.dart), in un isolate che tiene il modello
/// caricato fra un brano e l'altro: caricarlo costa piu' che usarlo.
/// Inizio e fine della musica, volume e tonalita' restano quelli di
/// sempre, sulla meta' dei campioni.
///
/// Solo brani gia' su disco: il successivo lo scarica gia' il preloader, e
/// analizzare uno stream vorrebbe dire scaricarlo due volte.
class TrackAnalyzer {
  final StorageService storage;
  final Future<File?> Function(String audioId) fileFor;

  TrackAnalyzer({required this.storage, required this.fileFor});

  final Map<String, BeatGrid> _grids = {};
  final Map<String, Future<BeatGrid?>> _inflight = {};

  /// Una coda: un'analisi alla volta, anche se le chiedono in due.
  Future<void> _queue = Future.value();

  /// La griglia gia' nota, senza fare niente.
  ///
  /// [minVersion] dice quanto nuova deve essere. Il mix vuole l'ultima,
  /// con le feature delle frasi; al riordino bastano tempo e tonalita', che
  /// ci sono gia' dalla 3, e rifare l'analisi di tutta una playlist per
  /// riordinarla costerebbe minuti.
  BeatGrid? known(String audioId, {int minVersion = beatGridVersion}) {
    final mem = _grids[audioId];
    if (mem != null && mem.version >= minVersion) return mem;
    final json = storage.beatGridJson(audioId);
    // Le analisi di prima non avevano la rete dei battiti, o le feature
    // per le frasi: si rifanno, costano un paio di secondi a brano, in
    // sottofondo.
    if (json == null || (json['v'] as num? ?? 1) < minVersion) return null;
    return _grids[audioId] = BeatGrid.fromJson(json);
  }

  /// La griglia di [audioId], analizzandolo se serve e se e' su disco.
  Future<BeatGrid?> gridFor(
    String audioId, {
    int minVersion = beatGridVersion,
  }) {
    final hit = known(audioId, minVersion: minVersion);
    if (hit != null) return Future.value(hit);
    return _inflight[audioId] ??= _enqueue(audioId).whenComplete(() {
      _inflight.remove(audioId);
    });
  }

  Future<BeatGrid?> _enqueue(String audioId) {
    final c = Completer<BeatGrid?>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await _analyze(audioId));
      } catch (e) {
        debugPrint('analisi di $audioId fallita: $e');
        c.complete(null);
      }
    });
    return c.future;
  }

  Future<BeatGrid?> _analyze(String audioId) async {
    final file = await fileFor(audioId);
    if (file == null) return null;
    final tmp = await getTemporaryDirectory();
    final pcm = File('${tmp.path}/analysis_$audioId.pcm');
    final player = mk.Player();
    try {
      final native = player.platform;
      if (native is! mk.NativePlayer) return null;
      final done = Completer<void>();
      final sub = player.stream.completed.listen((c) {
        if (c && !done.isCompleted) done.complete();
      });
      await native.setProperty('ao', 'pcm');
      await native.setProperty('ao-pcm-file', pcm.path);
      await native.setProperty('ao-pcm-waveheader', 'no');
      await native.setProperty(
        'af',
        'lavfi=[aresample=$beatNetRate,'
            'aformat=sample_fmts=s16:channel_layouts=mono]',
      );
      await player.open(mk.Media(file.path));
      await done.future.timeout(const Duration(seconds: 30));
      await sub.cancel();
    } finally {
      await player.dispose();
    }
    if (!pcm.existsSync()) return null;
    final bytes = await pcm.readAsBytes();
    try {
      pcm.deleteSync();
    } catch (_) {}
    final samples = Int16List.sublistView(bytes, 0, bytes.length ~/ 2 * 2);
    final sw = Stopwatch()..start();
    final grid = await heavyWork(
      () => (_worker ??= _BeatWorker.start()).analyze(samples),
    );
    debugPrint(
      'battiti: $audioId in ${sw.elapsedMilliseconds} ms, '
      '${grid.bpm.toStringAsFixed(1)} BPM fiducia '
      '${grid.confidence.toStringAsFixed(2)}, finale '
      '${grid.ending?.bpm.toStringAsFixed(1)} BPM fiducia '
      '${grid.ending?.confidence.toStringAsFixed(2)}',
    );
    // L'inviluppo in un file suo, la griglia senza nella scatola: vedi
    // BeatGrid.envelope.
    final json = grid.toJson();
    final env = json.remove('env');
    if (env is String) {
      try {
        final f = await _envelopeFile(audioId);
        await f.writeAsString(env);
      } catch (e) {
        debugPrint('inviluppo di $audioId non salvato: $e');
      }
    }
    final kept = BeatGrid.fromJson(json);
    _grids[audioId] = kept;
    await storage.saveBeatGrid(audioId, json);
    return kept;
  }

  Directory? _envelopeDir;

  Future<File> _envelopeFile(String audioId) async {
    final dir = _envelopeDir ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/envelopes',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$audioId.env');
  }

  /// L'inviluppo di [audioId] per le macchie (vedi [BeatGrid.envelope]),
  /// se il brano e' stato analizzato dalla versione 5 in poi.
  Future<List<double>?> envelopeFor(String audioId) async {
    try {
      final f = await _envelopeFile(audioId);
      if (!f.existsSync()) return null;
      return decodeFeatures(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  _BeatWorker? _worker;
}

/// L'isolate dei battiti: il modello si carica una volta, alla prima
/// analisi, e resta pronto per le successive.
class _BeatWorker {
  final Future<SendPort> _port;

  _BeatWorker._(this._port);

  static _BeatWorker start() {
    final ready = Completer<SendPort>();
    () async {
      final model = await rootBundle.load(beatModelAsset);
      final inbox = ReceivePort();
      await Isolate.spawn(_beatWorkerMain, (
        inbox.sendPort,
        TransferableTypedData.fromList([
          model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
        ]),
      ));
      ready.complete(await inbox.first as SendPort);
    }().catchError((Object e) {
      if (!ready.isCompleted) ready.completeError(e);
    });
    return _BeatWorker._(ready.future);
  }

  Future<BeatGrid> analyze(Int16List samples) async {
    final port = await _port;
    final reply = ReceivePort();
    port.send((TransferableTypedData.fromList([samples]), reply.sendPort));
    final msg = await reply.first;
    reply.close();
    if (msg is String) throw Exception(msg);
    return BeatGrid.fromJson((msg as Map).cast<String, dynamic>());
  }
}

void _beatWorkerMain((SendPort, TransferableTypedData) args) {
  final (main, model) = args;
  final bytes = model.materialize().asUint8List();
  // Sul Mac e su Windows il modello resta caricato, con blocchi da trenta
  // secondi. Su iPhone blocchi da quindici, sulla CPU, e il modello si
  // libera dopo ogni brano: la memoria che ONNX Runtime tiene per i calcoli
  // non torna al sistema finche' la sessione vive, e iOS chiudeva l'app.
  final phone = Platform.isIOS || Platform.isAndroid;
  OnnxBeatNet open() => phone
      ? OnnxBeatNet.fromBytes(bytes, frames: beatNetChunkSmall, coreml: false)
      : OnnxBeatNet.fromBytes(bytes);
  final kept = phone ? null : open();
  final inbox = ReceivePort();
  main.send(inbox.sendPort);
  inbox.listen((msg) {
    final (data, reply) = msg as (TransferableTypedData, SendPort);
    final net = kept ?? open();
    try {
      final pcm = data.materialize().asInt16List();
      reply.send(analyzeTrack(pcm, net).toJson());
    } catch (e) {
      reply.send('$e');
    } finally {
      if (kept == null) net.release();
    }
  });
}

/// Un brano intero, da campioni mono a [beatNetRate].
///
/// La rete trova battiti e battere; da quelli una griglia per l'inizio e
/// una per il finale, ciascuna sul suo minuto e un quarto. Il resto —
/// dove comincia e finisce la musica, il volume, la tonalita' — lo fa
/// l'analisi di sempre sulla meta' dei campioni. Una griglia che la rete
/// non riesce a fare resta quella classica, con fiducia zero: si mixa
/// senza battiti in comune.
@visibleForTesting
BeatGrid analyzeTrack(Int16List pcm, BeatLogitsNet net) {
  final half = Int16List(pcm.length ~/ 2);
  for (var i = 0; i < half.length; i++) {
    half[i] = (pcm[2 * i] + pcm[2 * i + 1]) ~/ 2;
  }
  final base = analyzeBeats(half).withKey(estimateKey(half, analysisRate));
  final mono = Float32List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    mono[i] = pcm[i] / 32768;
  }
  final found = trackBeats(mono, net);
  const window = 75.0;
  final head = fitGrid(
    found.beats,
    found.downbeats,
    from: base.musicStart,
    to: base.musicStart + window,
  );
  final tail = fitGrid(
    found.beats,
    found.downbeats,
    from: base.musicEnd - window,
    to: base.musicEnd,
  );
  return BeatGrid(
    bpm: head?.bpm ?? base.bpm,
    firstBeat: head?.firstBeat ?? base.firstBeat,
    downbeat: head?.downbeat ?? base.downbeat,
    musicStart: base.musicStart,
    musicEnd: base.musicEnd,
    confidence: head?.confidence ?? 0,
    energy: base.energy,
    features: base.features,
    envelope: base.envelope,
    key: base.key,
    ending: (
      bpm: tail?.bpm ?? base.bpm,
      firstBeat: tail?.firstBeat ?? base.firstBeat,
      downbeat: tail?.downbeat ?? base.downbeat,
      confidence: tail?.confidence ?? 0,
    ),
    version: beatGridVersion,
  );
}
