import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// A single EQ band: center frequency (Hz) and current gain in dB.
class EqBand {
  final double frequency;
  final double gain;

  const EqBand({required this.frequency, this.gain = 0});

  /// "32", "1K", "16K": come le scrive l'equalizzatore di Musica sul Mac.
  String get label => frequency >= 1000
      ? '${(frequency / 1000).toStringAsFixed(0)}K'
      : frequency.toStringAsFixed(0);

  EqBand copyWith({double? gain}) =>
      EqBand(frequency: frequency, gain: gain ?? this.gain);
}

/// Un preset: un guadagno per banda. [custom] se l'hai salvato tu.
class EqPreset {
  final String name;
  final List<double> gains;
  final bool custom;

  const EqPreset({
    required this.name,
    required this.gains,
    this.custom = false,
  });

  Map<String, dynamic> toJson() => {'name': name, 'gains': gains};

  factory EqPreset.fromJson(Map<String, dynamic> j) => EqPreset(
    name: j['name'] as String? ?? 'Custom',
    gains: [
      for (final g in (j['gains'] as List? ?? const [])) (g as num).toDouble(),
    ],
    custom: true,
  );
}

/// Le dieci bande dell'equalizzatore di Apple, un'ottava l'una.
///
/// Erano cinque, con una sola banda per tutti i bassi a 60 Hz: il sub e il
/// corpo di una cassa si muovevano insieme, e non si poteva togliere il
/// rimbombo senza togliere anche la botta.
const eqFrequencies = <double>[
  32,
  64,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// I preset, con i nomi e la forma di quelli di Apple Music.
///
/// I valori sono ricostruiti sulle curve di iTunes, dove si potevano
/// leggere banda per banda; Apple non li pubblica, quindi sono una buona
/// approssimazione, non una copia al decimo di decibel.
const List<EqPreset> eqPresets = [
  EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqPreset(name: 'Acoustic', gains: [5, 5, 4, 1, 2, 2, 3.5, 4, 3.5, 2]),
  EqPreset(
    name: 'Bass Booster',
    gains: [5.5, 4.5, 3.5, 2.5, 1.5, 0, 0, 0, 0, 0],
  ),
  EqPreset(
    name: 'Bass Reducer',
    gains: [-5.5, -4.5, -3.5, -2.5, -1.5, 0, 0, 0, 0, 0],
  ),
  EqPreset(
    name: 'Classical',
    gains: [5, 4, 3.5, 3, -1.5, -1.5, 0, 2.5, 3.5, 4],
  ),
  EqPreset(name: 'Dance', gains: [3.5, 6.5, 5, 0, 2, 3.5, 5, 4.5, 3.5, 0]),
  EqPreset(name: 'Deep', gains: [5, 3.5, 1.5, 1, 3, 2.5, 1.5, -2, -3.5, -4.5]),
  EqPreset(name: 'Electronic', gains: [4.5, 4, 1.5, 0, -2, 2, 1, 1.5, 4, 5]),
  EqPreset(name: 'Hip-Hop', gains: [5, 4.5, 1.5, 3, -1, -1, 1.5, -0.5, 2, 3]),
  EqPreset(name: 'Jazz', gains: [4, 3, 1.5, 2, -1.5, -1.5, 0, 1.5, 3, 3.5]),
  EqPreset(
    name: 'Late Night',
    gains: [4.5, 3, 2, 0, -1.5, -1.5, 0, 1, 2.5, 3.5],
  ),
  EqPreset(name: 'Latin', gains: [4.5, 3, 0, 0, -1.5, -1.5, -1.5, 0, 3, 4.5]),
  EqPreset(name: 'Loudness', gains: [6, 4, 0, 0, -2, 0, -1, -5, 5, 1]),
  EqPreset(name: 'Lounge', gains: [-3, -1.5, -0.5, 1.5, 4, 2.5, 0, -1.5, 2, 1]),
  EqPreset(name: 'Piano', gains: [3, 2, 0, 2.5, 3, 1.5, 3.5, 4.5, 3, 3.5]),
  EqPreset(name: 'Pop', gains: [-1.5, -1, 0, 2, 4, 4, 2, 0, -1, -1.5]),
  EqPreset(name: 'R&B', gains: [2.5, 7, 5.5, 1.5, -2.5, -1.5, 2.5, 3, 3, 4]),
  EqPreset(name: 'Rock', gains: [5, 4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4.5]),
  EqPreset(
    name: 'Small Speakers',
    gains: [5.5, 4, 3.5, 2.5, 1, 0, -1, -2, -3, -3.5],
  ),
  EqPreset(
    name: 'Spoken Word',
    gains: [-3.5, -0.5, 0, 0.5, 3.5, 4.5, 5, 4.5, 2.5, 0],
  ),
  EqPreset(
    name: 'Treble Booster',
    gains: [0, 0, 0, 0, 0, 1, 2.5, 3.5, 4.5, 5.5],
  ),
  EqPreset(
    name: 'Treble Reducer',
    gains: [0, 0, 0, 0, 0, -1, -2.5, -3.5, -4.5, -5.5],
  ),
  EqPreset(
    name: 'Vocal Booster',
    gains: [-1.5, -3, -3, 1.5, 3.5, 3.5, 3, 1.5, 0, -1.5],
  ),
];

/// Porta le vecchie impostazioni a cinque bande sulle dieci nuove.
///
/// Ogni banda nuova prende il valore della vecchia piu' vicina in ottave:
/// la curva che avevi resta la stessa, solo disegnata piu' fitta. Senza,
/// l'aggiornamento avrebbe azzerato l'equalizzatore di chi l'aveva
/// regolato.
List<double> gainsFromFiveBands(List<double> old) {
  const oldFreqs = [60.0, 250.0, 1000.0, 4000.0, 12000.0];
  double octaves(double a, double b) => (math.log(a / b) / math.ln2).abs();
  return [
    for (final f in eqFrequencies)
      old[List.generate(5, (i) => i).reduce(
        (a, b) => octaves(f, oldFreqs[a]) <= octaves(f, oldFreqs[b]) ? a : b,
      )],
  ];
}

/// Lo stato dell'equalizzatore.
class EqState {
  final List<EqBand> bands;

  /// Guadagno applicato prima delle bande, in dB. Serve a lasciare spazio
  /// quando si alza qualcosa: sei decibel sui bassi sopra un master gia'
  /// al massimo fanno saturare i picchi, e si sente gracchiare.
  final double preamp;

  /// Spento, l'audio passa com'e', ma le regolazioni restano: e' il modo
  /// di confrontare con e senza, invece di doverle rifare.
  final bool enabled;

  final List<EqPreset> customPresets;

  const EqState(
    this.bands, {
    this.preamp = 0,
    this.enabled = true,
    this.customPresets = const [],
  });

  EqState.flat()
    : bands = [for (final f in eqFrequencies) EqBand(frequency: f)],
      preamp = 0,
      enabled = true,
      customPresets = const [];

  List<double> get gains => [for (final b in bands) b.gain];

  bool get isFlat => bands.every((b) => b.gain == 0);

  /// L'audio arriva al player cosi' com'e'.
  bool get isBypassed => !enabled || (isFlat && preamp == 0);

  List<EqPreset> get allPresets => [...eqPresets, ...customPresets];

  /// Il preset che corrisponde alle bande, o null se non ce n'e' uno.
  EqPreset? get activePreset {
    for (final p in allPresets) {
      if (p.gains.length != bands.length) continue;
      var match = true;
      for (var i = 0; i < bands.length; i++) {
        if ((p.gains[i] - bands[i].gain).abs() > 0.01) {
          match = false;
          break;
        }
      }
      if (match) return p;
    }
    return null;
  }

  EqState copyWith({
    List<EqBand>? bands,
    double? preamp,
    bool? enabled,
    List<EqPreset>? customPresets,
  }) => EqState(
    bands ?? this.bands,
    preamp: preamp ?? this.preamp,
    enabled: enabled ?? this.enabled,
    customPresets: customPresets ?? this.customPresets,
  );

  /// La catena di filtri per libmpv. Vuota se non c'e' niente da fare.
  ///
  /// Solo le bande: il preamplificatore non e' un filtro, lo applica il
  /// player al suo volume. Il filtro `volume`, nudo o dentro `lavfi`, in
  /// questo libmpv non esiste e rifiutava la catena intera — "Audio filter
  /// initialized failed", e il brano non suonava piu'.
  ///
  /// Bande di un'ottava (`t=o:w=1`), come un equalizzatore grafico: prima
  /// era un Q fisso, che su bande a due ottave di distanza lasciava buchi
  /// fra l'una e l'altra.
  String get filterChain {
    if (!enabled || isFlat) return '';
    final graph = [
      for (final b in bands)
        if (b.gain != 0)
          'equalizer=f=${b.frequency.toStringAsFixed(0)}:t=o:w=1'
              ':g=${b.gain.toStringAsFixed(1)}',
    ];
    return '@eq:lavfi=[${graph.join(',')}]';
  }
}

/// Applies the equalizer to the libmpv audio chain via the `af` property.
class EqController extends Notifier<EqState> {
  @override
  EqState build() {
    final storage = ref.read(storageServiceProvider);
    final saved = storage.eqGains;
    final gains = switch (saved.length) {
      10 => saved,
      5 => gainsFromFiveBands(saved),
      _ => List<double>.filled(eqFrequencies.length, 0),
    };

    // The filter can only be pushed once the player exists, which it does
    // not yet while this notifier is being built.
    Future.microtask(_apply);
    return EqState(
      [
        for (var i = 0; i < eqFrequencies.length; i++)
          EqBand(frequency: eqFrequencies[i], gain: gains[i]),
      ],
      preamp: storage.eqPreamp,
      enabled: storage.eqEnabled,
      customPresets: [for (final p in storage.eqPresets) EqPreset.fromJson(p)],
    );
  }

  /// Equalizer settings used to reset on every launch along with shuffle,
  /// repeat and crossfade.
  void _save() {
    final storage = ref.read(storageServiceProvider);
    unawaited(storage.saveEqGains(state.gains));
    unawaited(storage.saveEqPreamp(state.preamp));
    unawaited(storage.saveEqEnabled(state.enabled));
  }

  Future<void> _set(EqState next) async {
    state = next;
    _save();
    await _apply();
  }

  Future<void> setBand(int index, double gain) {
    final bands = [...state.bands];
    bands[index] = bands[index].copyWith(gain: gain);
    return _set(state.copyWith(bands: bands));
  }

  Future<void> setPreamp(double db) => _set(state.copyWith(preamp: db));

  Future<void> setEnabled(bool on) => _set(state.copyWith(enabled: on));

  Future<void> applyPreset(EqPreset preset) {
    if (preset.gains.length != state.bands.length) return Future.value();
    // Scegliere un preset e' voler sentire l'equalizzatore: se era spento
    // si riaccende, altrimenti il tocco non farebbe niente di udibile.
    return _set(
      state.copyWith(
        enabled: true,
        bands: [
          for (var i = 0; i < state.bands.length; i++)
            state.bands[i].copyWith(gain: preset.gains[i]),
        ],
      ),
    );
  }

  Future<void> reset() => _set(
    EqState.flat().copyWith(
      customPresets: state.customPresets,
      enabled: state.enabled,
    ),
  );

  /// Salva le bande attuali come preset tuo. Un nome gia' usato lo
  /// sostituisce, invece di creare due voci uguali nel menu.
  Future<void> savePreset(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final mine = [
      for (final p in state.customPresets)
        if (p.name != trimmed) p,
      EqPreset(name: trimmed, gains: state.gains, custom: true),
    ];
    state = state.copyWith(customPresets: mine);
    await _savePresets();
  }

  Future<void> deletePreset(String name) async {
    state = state.copyWith(
      customPresets: [
        for (final p in state.customPresets)
          if (p.name != name) p,
      ],
    );
    await _savePresets();
  }

  Future<void> _savePresets() => ref.read(storageServiceProvider).saveEqPresets(
    [for (final p in state.customPresets) p.toJson()],
  );

  /// Riapplica l'EQ al player attivo. Serve dopo uno scambio di player
  /// durante il crossfade: il filtro era impostato su quello uscente.
  Future<void> reapply() => _apply();

  /// La catena la costruisce il player, che ci mette anche AutoMix e la
  /// applica a entrambi i suoi player: qui basta dirgli che e' cambiata.
  Future<void> _apply() async {
    try {
      await ref.read(playerProvider.notifier).refreshFilters();
    } catch (e) {
      // EQ is best-effort; never break playback for it.
    }
  }
}
