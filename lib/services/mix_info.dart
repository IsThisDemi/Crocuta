import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import 'automix.dart' show MixStage, highpassOff, lowpassOpen;

/// Il mix AutoMix in corso: chi esce, chi entra e a che punto e'.
///
/// Sta fuori da PlayerState di proposito: l'avanzamento cambia decine di
/// volte al secondo, e dentro lo stato del player farebbe ricostruire
/// chiunque lo osservi. Qui lo guarda solo chi disegna il mix.
class MixInfo {
  final Track from;
  final Track to;

  /// Da 0 (tutto l'uscente) a 1 (tutto l'entrante).
  final double progress;

  const MixInfo({required this.from, required this.to, required this.progress});
}

final mixInfoProvider = StateProvider<MixInfo?>((ref) => null);

/// Bassi, medi e acuti di un brano nel tempo, 0-1, a [rate] valori al
/// secondo (vedi services/waveform.dart, bandsOf).
typedef MixBands = ({List<double> low, List<double> mid, List<double> high});

/// Il mix AutoMix che verra': dove parte nel brano in ascolto, quanto
/// dura, le onde e le bande dei due brani, e cosa fa AutoMix istante per
/// istante. La barra di avanzamento lo mostra prima che arrivi (le due onde
/// come si intrecceranno), e durante il mix ci disegna i due brani con
/// bassi, medi e acuti come li lascia passare.
class MixPlanInfo {
  /// Il brano uscente a cui vale: finito il mix, il piano e' vecchio.
  final String fromId;
  final Track to;

  /// Da dove parte nell'uscente e quanto dura, in secondi dell'uscente.
  final double outStart;
  final double length;

  /// Da dove parte l'entrante, e quanti suoi secondi passano per ogni
  /// secondo dell'uscente (i due possono suonare a velocita' diverse).
  final double inStart;
  final double inPerOut;

  /// L'onda dell'entrante (vedi waveformOf), a [waveRate] valori al
  /// secondo: per l'anteprima del mix sulla barra.
  final List<double> toWave;
  final double waveRate;

  /// Le bande dei due brani, a [bandRate] valori al secondo.
  final MixBands? fromBands;
  final MixBands? toBands;
  final double bandRate;

  /// Cosa fa AutoMix ai due brani lungo il mix — volume, bassi, medi,
  /// acuti, filtri, eco —, campionato a passi uguali dall'inizio alla fine.
  final List<MixStage> outStages;
  final List<MixStage> inStages;

  /// Dove la voce dell'uscente e' spenta, e dove passa all'entrante, in
  /// frazioni del mix: nulli se le voci non si incontrano.
  final double? voiceOff;
  final double? voiceSwap;

  const MixPlanInfo({
    required this.fromId,
    required this.to,
    required this.outStart,
    required this.length,
    required this.inStart,
    required this.inPerOut,
    required this.toWave,
    required this.waveRate,
    required this.fromBands,
    required this.toBands,
    required this.bandRate,
    required this.outStages,
    required this.inStages,
    this.voiceOff,
    this.voiceSwap,
  });

  /// Lo stadio a [u] (0-1) del mix, fra un campione e l'altro il piu'
  /// vicino.
  static MixStage stageAt(List<MixStage> stages, double u) {
    if (stages.isEmpty) return MixStage.flat;
    final i = (u * (stages.length - 1)).round().clamp(0, stages.length - 1);
    return stages[i];
  }
}

final mixPlanProvider = StateProvider<MixPlanInfo?>((ref) => null);

/// Quanto si sentono bassi, medi e acuti di un brano in uno stadio del mix,
/// 0-1: il volume, l'equalizzatore e i filtri insieme. Per la barra, che li
/// disegna; il suono vero lo fanno i filtri di mpv.
extension MixStageAudible on MixStage {
  ({double low, double mid, double high}) get audible {
    double lin(double db) => math.pow(10, db / 20).toDouble();
    double cut(double from, double to, double at) =>
        (math.log(at / from) / math.log(to / from)).clamp(0.0, 1.0);
    // Il passa-alto si mangia i bassi fino a 300 Hz; il passa-basso gli
    // acuti da 16 kHz in giu', e sotto i 2,5 kHz anche i medi.
    final hp = highpass <= highpassOff ? 0.0 : cut(highpassOff, 300, highpass);
    final lpHigh = lowpass >= lowpassOpen ? 0.0 : cut(lowpassOpen, 2000, lowpass);
    final lpMid = lowpass >= 2500 ? 0.0 : cut(2500, 300, lowpass);
    return (
      low: (volume * lin(low) * (1 - hp)).clamp(0.0, 1.0),
      mid: (volume * lin(mid) * (1 - lpMid)).clamp(0.0, 1.0),
      high: (volume * lin(high) * (1 - lpHigh)).clamp(0.0, 1.0),
    );
  }
}
