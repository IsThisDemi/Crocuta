// ignore_for_file: implementation_imports
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

import 'beat_net.dart';
import 'stem_separator.dart';

/// Il modello di separazione su ONNX Runtime.
///
/// I tensori si scrivono e si leggono direttamente in memoria nativa. Il
/// pacchetto li converte in liste Dart annidate, una per dimensione: con
/// tre milioni di valori a blocco la conversione costava piu' della rete,
/// e un Float32List piatto veniva perfino preso per double.
///
/// Da usare in un isolate: ONNX Runtime va inizializzato in quello in cui
/// gira, e un blocco richiede qualche centinaio di millisecondi di calcolo
/// che sul thread dell'interfaccia sarebbero scatti.
class OnnxSpectrogramNet implements SpectrogramNet {
  final OrtSession _session;
  final MdxConfig cfg;
  final String _input;

  OnnxSpectrogramNet._(this._session, this.cfg)
    : _input = _session.inputNames.first;

  /// Carica il modello dai suoi byte.
  factory OnnxSpectrogramNet.fromBytes(
    Uint8List model, [
    MdxConfig cfg = MdxConfig.vocFt,
    String? coremlUnits,
    int? threads,
  ]) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      // Circa meta' dei core, per quello che CoreML lascia alla CPU e per
      // Windows, dove la rete gira tutta li': il brano intanto suona e
      // l'interfaccia si muove.
      ..setIntraOpNumThreads(
        threads ?? (Platform.numberOfProcessors ~/ 2).clamp(2, 8),
      )
      // Un blocco alla volta, sempre: con la dimensione lasciata libera
      // CoreML rifiutava il modello ("unbounded dimension") e la
      // separazione girava tutta sulla CPU, spesso troppo tardi per il mix.
      ..addFreeDimensionOverrideByName('batch_size', 1);
    // Su Mac e iPhone il modello gira con CoreML, sulla GPU: con ONNX
    // Runtime 1.30 e' quattro-cinque volte piu' veloce della CPU (M5 Pro,
    // 30 s di audio: 2,1 s invece di 9,9), con la stessa identica voce. Il
    // Neural Engine da solo, per questo modello, e' lento quanto la CPU:
    // "ALL" lascia a CoreML la scelta, e sceglie la GPU.
    final units =
        coremlUnits ?? (Platform.isMacOS || Platform.isIOS ? 'ALL' : null);
    if (units != null) {
      try {
        options.appendProvider('CoreML', {
          'ModelFormat': 'MLProgram',
          'MLComputeUnits': units,
        });
      } catch (e) {
        // Un sistema senza CoreML adatto: la stessa separazione, sulla CPU.
        debugPrint('stem: CoreML non disponibile ($e), uso la CPU');
      }
    }
    return OnnxSpectrogramNet._(OrtSession.fromBuffer(model, options), cfg);
  }

  @override
  Float32List run(Float32List spec) {
    final shape = [1, 4, cfg.dimF, cfg.dimT];
    final count = spec.length;
    final data = calloc<ffi.Float>(count);
    data.asTypedList(count).setAll(0, spec);
    final input = _tensor(data, count, shape);
    final runOptions = OrtRunOptions();
    try {
      final outputs = _session.run(runOptions, {_input: input});
      final out = outputs.first!;
      try {
        final pp = calloc<ffi.Pointer<ffi.Void>>();
        final status = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
            .asFunction<
              bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtValue>,
                ffi.Pointer<ffi.Pointer<ffi.Void>>,
              )
            >()(out.ptr, pp);
        OrtStatus.checkOrtStatus(status);
        final result = Float32List.fromList(
          pp.value.cast<ffi.Float>().asTypedList(count),
        );
        calloc.free(pp);
        return result;
      } finally {
        for (final o in outputs) {
          o?.release();
        }
      }
    } finally {
      runOptions.release();
      // Rilascia anche [data]: il tensore la possiede.
      input.release();
    }
  }

  static OrtValueTensor _tensor(
    ffi.Pointer<ffi.Float> data,
    int count,
    List<int> shape,
  ) {
    final api = OrtEnv.instance.ortApiPtr.ref;
    final shapePtr = calloc<ffi.Int64>(shape.length);
    shapePtr.asTypedList(shape.length).setAll(0, shape);
    final infoPtr = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
    var status =
        api.AllocatorGetInfo.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtAllocator>,
            ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>,
          )
        >()(OrtAllocator.instance.ptr, infoPtr);
    OrtStatus.checkOrtStatus(status);
    final valuePtr = calloc<ffi.Pointer<bg.OrtValue>>();
    status =
        api.CreateTensorWithDataAsOrtValue.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtMemoryInfo>,
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<ffi.Int64>,
            int,
            int,
            ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
          )
        >()(
          infoPtr.value,
          data.cast(),
          count * 4,
          shapePtr,
          shape.length,
          ONNXTensorElementDataType.float.value,
          valuePtr,
        );
    OrtStatus.checkOrtStatus(status);
    final tensor = OrtValueTensor(valuePtr.value, data.cast());
    calloc.free(shapePtr);
    calloc.free(infoPtr);
    calloc.free(valuePtr);
    return tensor;
  }

  void release() => _session.release();
}

/// Beat This! su ONNX Runtime: un blocco di spettrogramma alla volta.
///
/// La dimensione dei fotogrammi e' fissata a [frames]: nel modello e'
/// libera, e CoreML un ingresso senza limite lo rifiuta. Sul Mac gira con
/// CoreML; altrove, e se CoreML non va, sulla CPU — un blocco da trenta
/// secondi in circa tre decimi di secondo.
class OnnxBeatNet implements BeatLogitsNet {
  final OrtSession _session;

  @override
  final int frames;

  OnnxBeatNet._(this._session, this.frames);

  /// [coreml] falso su iPhone: la compilazione per CoreML di questo modello
  /// ha un picco di memoria che, sommato al resto dell'app, faceva chiudere
  /// Crocuta da iOS. Sulla CPU un brano costa qualche secondo.
  factory OnnxBeatNet.fromBytes(
    Uint8List model, {
    int frames = beatNetChunk,
    bool coreml = true,
  }) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads((Platform.numberOfProcessors ~/ 2).clamp(2, 8))
      ..addFreeDimensionOverrideByName('frames', frames);
    if (coreml && (Platform.isMacOS || Platform.isIOS)) {
      try {
        options.appendProvider('CoreML', {
          'ModelFormat': 'MLProgram',
          'MLComputeUnits': 'ALL',
        });
      } catch (e) {
        debugPrint('battiti: CoreML non disponibile ($e), uso la CPU');
      }
    }
    return OnnxBeatNet._(OrtSession.fromBuffer(model, options), frames);
  }

  @override
  ({Float32List beat, Float32List downbeat}) run(Float32List spect) {
    final count = spect.length;
    final data = calloc<ffi.Float>(count);
    data.asTypedList(count).setAll(0, spect);
    final input = OnnxSpectrogramNet._tensor(data, count, [
      1,
      frames,
      count ~/ frames,
    ]);
    final runOptions = OrtRunOptions();
    try {
      final outputs = _session.run(runOptions, {'spectrogram': input});
      try {
        Float32List read(OrtValue? v) {
          final pp = calloc<ffi.Pointer<ffi.Void>>();
          final status = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
              .asFunction<
                bg.OrtStatusPtr Function(
                  ffi.Pointer<bg.OrtValue>,
                  ffi.Pointer<ffi.Pointer<ffi.Void>>,
                )
              >()(v!.ptr, pp);
          OrtStatus.checkOrtStatus(status);
          final r = Float32List.fromList(
            pp.value.cast<ffi.Float>().asTypedList(frames),
          );
          calloc.free(pp);
          return r;
        }

        return (beat: read(outputs[0]), downbeat: read(outputs[1]));
      } finally {
        for (final o in outputs) {
          o?.release();
        }
      }
    } finally {
      runOptions.release();
      input.release();
    }
  }

  void release() => _session.release();
}
