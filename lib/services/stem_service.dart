import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import 'automix.dart';
import 'heavy_work.dart';
import 'onnx_net.dart';
import 'stem_mix.dart';
import 'stem_separator.dart';
import 'vocal_pause.dart';

/// Il modello di separazione, nelle risorse dell'app.
const stemModelAsset = 'assets/models/voc_ft.onnx';

/// Prepara il tratto del brano uscente per un mix con voce e base separate.
///
/// Solo il tratto che serve, non il brano intero: come in kumone, separare
/// trenta secondi costa una decina di secondi sul Mac, e c'e' tutto il
/// brano per farlo. Il risultato non si conserva: ogni transizione si
/// rifa' da capo, come le altre scelte di AutoMix.
class StemService {
  final Future<File?> Function(String audioId) fileFor;

  StemService({required this.fileFor});

  /// Il file del tratto uscente per [plan], o null se non si riesce.
  ///
  /// Col file torna il piano come l'ha lasciato la voce separata: se lo
  /// spegnimento della voce cadeva a meta' frase, spostato nella pausa piu'
  /// vicina (vedi placeVocalHandover), e la riga del registro che lo dice.
  /// Il tratto e' gia' calcolato col piano nuovo; il tratto dell'entrante va
  /// chiesto con quello.
  Future<({File file, BeatMixPlan plan, String note})?> renderOutgoing(
    String audioId,
    BeatMixPlan plan,
  ) => _render(audioId, plan, incoming: false);

  /// Il file del tratto entrante per il passaggio di voce di [plan].
  Future<File?> renderIncoming(String audioId, BeatMixPlan plan) async =>
      (await _render(audioId, plan, incoming: true))?.file;

  /// La base del brano intero, senza voce, per il karaoke: un wav nella
  /// cartella temporanea, lungo quanto il brano.
  ///
  /// In un isolate a parte, come il mix, ma lanciato a mano: cosi' puo'
  /// raccontare a che punto e' con [onProgress]. Un brano intero richiede
  /// decine di secondi, e aspettare senza sapere quanto si legge come un
  /// blocco.
  Future<File?> renderInstrumental(
    String audioId, {
    void Function(double progress)? onProgress,
  }) => heavyWork(() => _instrumental(audioId, onProgress));

  Future<File?> _instrumental(
    String audioId,
    void Function(double progress)? onProgress,
  ) async {
    final samples = await _decode(audioId, 0, null);
    if (samples == null) return null;
    final model = await rootBundle.load(stemModelAsset);
    final port = ReceivePort();
    final errors = ReceivePort();
    await Isolate.spawn(_instrumentalWorker, (
      port.sendPort,
      TransferableTypedData.fromList([
        model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      ]),
      TransferableTypedData.fromList([samples.$1]),
      TransferableTypedData.fromList([samples.$2]),
    ), onError: errors.sendPort);
    final done = Completer<TransferableTypedData?>();
    final sub = port.listen((msg) {
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is TransferableTypedData && !done.isCompleted) {
        done.complete(msg);
      }
    });
    final errSub = errors.listen((e) {
      if (!done.isCompleted) done.complete(null);
    });
    final sw = Stopwatch()..start();
    final wav = await done.future;
    await sub.cancel();
    await errSub.cancel();
    port.close();
    errors.close();
    if (wav == null) return null;
    debugPrint(
      'karaoke: base di $audioId separata in ${sw.elapsedMilliseconds} ms',
    );
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/karaoke_$audioId.wav');
    await file.writeAsBytes(wav.materialize().asUint8List());
    return file;
  }

  /// Il tratto dell'uscente per il cambio secco, con l'eco d'uscita.
  ///
  /// Niente separazione: solo decodifica e un'eco calcolata, pronta in una
  /// frazione di secondo.
  Future<File?> renderEchoOut(String audioId, BeatMixPlan plan) async {
    final beat = plan.echoBeat;
    if (beat == null) return null;
    final drop = plan.length * cutDrop;
    final samples = await _decode(audioId, plan.outStart, plan.outStart + drop);
    if (samples == null) return null;
    final sw = Stopwatch()..start();
    final wav = await compute(_echoOut, (
      samples.$1,
      samples.$2,
      drop,
      beat,
      plan.length,
    ));
    debugPrint('eco: pronta in ${sw.elapsedMilliseconds} ms');
    final tmp = await getTemporaryDirectory();
    final file = File(
      '${tmp.path}/echo_${audioId}_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(wav);
    return file;
  }

  Future<({File file, BeatMixPlan plan, String note})?> _render(
    String audioId,
    BeatMixPlan plan, {
    required bool incoming,
  }) async {
    final window = incoming ? incomingWindow(plan) : outgoingWindow(plan);
    final samples = await _decode(audioId, window.start, window.end);
    if (samples == null) return null;
    final model = await rootBundle.load(stemModelAsset);
    final modelBytes = TransferableTypedData.fromList([
      model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
    ]);
    final left = TransferableTypedData.fromList([samples.$1]);
    final right = TransferableTypedData.fromList([samples.$2]);
    final sw = Stopwatch()..start();
    // Top-level e con dati trasferibili: una closure qui si porterebbe
    // dietro il servizio, che a un altro isolate non si puo' spedire.
    final (wav, placed, note) = await heavyWork(
      () => Isolate.run(
        () => _separateAndRender(modelBytes, left, right, plan, incoming),
      ),
    );
    debugPrint(
      'stem: ${incoming ? 'entrante' : 'uscente'} '
      '${(window.end - window.start).toStringAsFixed(1)} s separati '
      'in ${sw.elapsedMilliseconds} ms',
    );
    final tmp = await getTemporaryDirectory();
    final file = File(
      '${tmp.path}/stem_${incoming ? 'in' : 'out'}_${audioId}_'
      '${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(wav.materialize().asUint8List());
    return (file: file, plan: placed, note: note);
  }

  /// Il tratto [start, end) del brano, stereo float a [stemRate].
  ///
  /// Con lo stesso lettore nascosto dell'analisi dei battiti, che scrive
  /// su file invece di suonare. Il salto e' preciso al campione (hr-seek):
  /// il tratto deve combaciare con quello che il player sta suonando, o il
  /// cambio di player a inizio mix si sentirebbe.
  Future<(Float32List, Float32List)?> _decode(
    String audioId,
    double start,
    double? end,
  ) async {
    final file = await fileFor(audioId);
    if (file == null) return null;
    final tmp = await getTemporaryDirectory();
    final pcm = File('${tmp.path}/stem_$audioId.pcm');
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
      await native.setProperty('hr-seek', 'yes');
      await native.setProperty('start', start.toStringAsFixed(4));
      if (end != null) {
        await native.setProperty('end', end.toStringAsFixed(4));
      }
      await native.setProperty(
        'af',
        'lavfi=[aresample=$stemRate,'
            'aformat=sample_fmts=flt:channel_layouts=stereo]',
      );
      await player.open(mk.Media(file.path));
      // Un brano intero si decodifica in qualche secondo, un tratto in
      // meno di uno: il margine e' per i telefoni piu' lenti.
      await done.future.timeout(Duration(seconds: end == null ? 120 : 30));
      await sub.cancel();
    } finally {
      await player.dispose();
    }
    if (!pcm.existsSync()) return null;
    final bytes = await pcm.readAsBytes();
    try {
      pcm.deleteSync();
    } catch (_) {}
    // sublistView conta in elementi della sorgente, cioe' byte: fino
    // all'ultimo fotogramma intero, otto byte per due canali float.
    final all = Float32List.sublistView(bytes, 0, bytes.length ~/ 8 * 8);
    final n = all.length ~/ 2;
    final l = Float32List(n), r = Float32List(n);
    for (var i = 0; i < n; i++) {
      l[i] = all[2 * i];
      r[i] = all[2 * i + 1];
    }
    return (l, r);
  }
}

/// Nell'isolate: separa, e per l'uscente misura la voce e sposta il suo
/// spegnimento nella pausa piu' vicina prima di calcolare il tratto — la
/// voce sola c'e' solo qui, e il tratto va calcolato col piano giusto. Il
/// piano torna indietro, con la riga del registro; per l'entrante torna
/// com'era.
(TransferableTypedData, BeatMixPlan, String) _separateAndRender(
  TransferableTypedData model,
  TransferableTypedData left,
  TransferableTypedData right,
  BeatMixPlan plan,
  bool incoming,
) {
  final net = OnnxSpectrogramNet.fromBytes(model.materialize().asUint8List());
  try {
    final stems = StemSeparator(net).separate(
      left.materialize().asFloat32List(),
      right.materialize().asFloat32List(),
    );
    var placed = plan;
    var note = '';
    if (!incoming) {
      // Il tratto separato comincia a outgoingWindow(plan).start, che col
      // loop dell'eco puo' stare prima del mix: la voce del mix comincia
      // a outStart, come la legge renderOutgoing.
      final env = vocalEnvelope(
        stems.vocalsL,
        stems.vocalsR,
        from: plan.outStart - outgoingWindow(plan).start,
        length: plan.length,
        rate: stemRate,
      );
      (plan: placed, note: note) = placeVocalHandover(plan, env);
    }
    return (
      TransferableTypedData.fromList([
        wavFloat32(
          incoming
              ? renderIncoming(stems, placed)
              : renderOutgoing(stems, placed),
        ),
      ]),
      placed,
      note,
    );
  } finally {
    net.release();
  }
}

/// Il lavoro del karaoke, nell'isolate: separa il brano intero e rimanda
/// l'avanzamento, poi il wav della sola base.
void _instrumentalWorker(
  (
    SendPort,
    TransferableTypedData,
    TransferableTypedData,
    TransferableTypedData,
  )
  args,
) {
  final (port, model, left, right) = args;
  final net = OnnxSpectrogramNet.fromBytes(model.materialize().asUint8List());
  try {
    var last = -1.0;
    final stems = StemSeparator(net).separate(
      left.materialize().asFloat32List(),
      right.materialize().asFloat32List(),
      onBlock: (p) {
        // Un messaggio ogni due punti percentuali: di piu' non si vede.
        if (p - last < 0.02 && p < 1) return;
        last = p;
        port.send(p);
      },
    );
    final n = stems.baseL.length;
    final interleaved = Float32List(n * 2);
    for (var i = 0; i < n; i++) {
      interleaved[2 * i] = stems.baseL[i];
      interleaved[2 * i + 1] = stems.baseR[i];
    }
    port.send(TransferableTypedData.fromList([wavFloat32(interleaved)]));
  } finally {
    net.release();
  }
}

Uint8List _echoOut((Float32List, Float32List, double, double, double) a) {
  final (l, r, drop, beat, length) = a;
  return wavFloat32(
    renderEchoOut(l, r, drop: drop, beat: beat, length: length),
  );
}
