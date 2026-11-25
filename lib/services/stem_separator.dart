import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// La rete che separa: riceve lo spettrogramma di un blocco di mix e
/// restituisce quello della sola voce, stessa forma.
///
/// Un'interfaccia e non ONNX Runtime diretto: il calcolo attorno (FFT,
/// blocchi, ricostruzione) e' la parte in cui e' facile sbagliare di un
/// campione, e cosi' si verifica con una rete finta, senza il modello.
abstract interface class SpectrogramNet {
  /// [spec] e' `[4, dimF, dimT]` in ordine C: reale e immaginaria del
  /// canale sinistro, poi del destro.
  Float32List run(Float32List spec);
}

/// I parametri di un modello MDX-Net di UVR. Devono combaciare con la forma
/// del file .onnx: sbagliarne uno e la rete rifiuta l'ingresso.
class MdxConfig {
  final int nFft;
  final int hop;
  final int dimF;
  final int dimT;

  /// Di quanto alzare la voce stimata: il modello la restituisce appena
  /// piu' bassa del vero, e senza la base ne conserverebbe un'eco.
  final double compensate;

  const MdxConfig({
    required this.nFft,
    required this.hop,
    required this.dimF,
    required this.dimT,
    required this.compensate,
  });

  /// UVR-MDX-NET Voc_FT: voce, 3072 bande su una finestra di 7680.
  static const vocFt = MdxConfig(
    nFft: 7680,
    hop: 1024,
    dimF: 3072,
    dimT: 256,
    compensate: 1.021,
  );

  /// I campioni di un blocco: tanti quanti ne coprono [dimT] finestre.
  int get chunk => hop * (dimT - 1);

  /// Quanto si scarta ai due bordi di ogni blocco, dove la finestra non ha
  /// abbastanza contesto e la stima peggiora.
  int get trim => nFft ~/ 2;

  /// I campioni buoni di ogni blocco: i blocchi si accavallano di [trim]
  /// per parte e si tiene solo il centro.
  int get step => chunk - 2 * trim;
}

/// Voce e base di un tratto di brano, stereo a canali separati.
typedef Stems = ({
  Float32List vocalsL,
  Float32List vocalsR,
  Float32List baseL,
  Float32List baseR,
});

/// Separa voce e base come fa UVR con i modelli MDX-Net.
///
/// Per ogni blocco: spettrogramma (Hann periodica, riflessione ai bordi),
/// solo le prime [MdxConfig.dimF] bande alla rete, voce ricostruita con la
/// somma sovrapposta delle finestre. La base e' il mix meno la voce: cosi'
/// voce piu' base rifanno il brano esatto, e dove la rete sbaglia l'errore
/// finisce in una delle due invece di sparire.
class StemSeparator {
  final SpectrogramNet net;
  final MdxConfig cfg;

  late final FFT _fft = FFT(cfg.nFft);
  late final Float64List _window = _hann(cfg.nFft);

  StemSeparator(this.net, [this.cfg = MdxConfig.vocFt]);

  static Float64List _hann(int n) => Float64List.fromList([
    for (var i = 0; i < n; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / n),
  ]);

  /// [onBlock], se c'e', riceve l'avanzamento da 0 a 1 dopo ogni blocco:
  /// su un brano intero la separazione dura decine di secondi.
  Stems separate(
    Float32List left,
    Float32List right, {
    void Function(double progress)? onBlock,
  }) {
    final n = left.length;
    final c = cfg;
    // Silenzio di [trim] davanti e dietro, e in fondo quanto basta a
    // chiudere l'ultimo blocco: ogni campione vero cade nel centro buono
    // di qualche blocco.
    final pad = c.step - n % c.step;
    final total = c.trim + n + pad + c.trim;
    // In singola precisione come l'ingresso, che non ne ha di piu': in
    // doppia, un brano intero occupava centinaia di MB per niente.
    final l = Float32List(total)..setRange(c.trim, c.trim + n, left);
    final r = Float32List(total)..setRange(c.trim, c.trim + n, right);

    final vl = Float32List(n);
    final vr = Float32List(n);
    for (var start = 0; start < n + pad; start += c.step) {
      final spec = Float32List(4 * c.dimF * c.dimT);
      _stft(l, start, spec, 0);
      _stft(r, start, spec, 2);
      final out = net.run(spec);
      final ol = _istft(out, 0);
      final or = _istft(out, 2);
      // Il centro del blocco, [trim, chunk - trim), va a [start, ...).
      for (var i = 0; i < c.step; i++) {
        final at = start + i;
        if (at >= n) break;
        vl[at] = ol[c.trim + i] * c.compensate;
        vr[at] = or[c.trim + i] * c.compensate;
      }
      onBlock?.call(math.min(1.0, (start + c.step) / (n + pad)));
    }
    // A mano e non con una lista intermedia: quella teneva un oggetto per
    // campione, e su un brano intero erano milioni.
    final bl = Float32List(n);
    final br = Float32List(n);
    for (var i = 0; i < n; i++) {
      bl[i] = left[i] - vl[i];
      br[i] = right[i] - vr[i];
    }
    return (vocalsL: vl, vocalsR: vr, baseL: bl, baseR: br);
  }

  /// Lo spettrogramma del blocco che parte da [start], nei canali
  /// [channel] (reale) e [channel] + 1 (immaginaria) di [spec].
  void _stft(Float32List x, int start, Float32List spec, int channel) {
    final c = cfg;
    final half = c.nFft ~/ 2;
    final frame = Float64List(c.nFft);
    final plane = c.dimF * c.dimT;
    for (var t = 0; t < c.dimT; t++) {
      // Finestra centrata sul campione t*hop del blocco, riflettendo ai
      // bordi del blocco come torch.stft(center=True, pad_mode=reflect).
      for (var k = 0; k < c.nFft; k++) {
        final at = _reflect(t * c.hop + k - half, c.chunk);
        frame[k] = x[start + at] * _window[k];
      }
      final bins = _fft.realFft(frame);
      for (var f = 0; f < c.dimF; f++) {
        final z = bins[f];
        spec[channel * plane + f * c.dimT + t] = z.x;
        spec[(channel + 1) * plane + f * c.dimT + t] = z.y;
      }
    }
  }

  /// L'indice [i] riflesso dentro [0, n), senza ripetere il bordo.
  static int _reflect(int i, int n) {
    if (i < 0) return -i;
    if (i >= n) return 2 * (n - 1) - i;
    return i;
  }

  /// Il blocco ricostruito dai canali [channel]/[channel] + 1 di [spec].
  Float64List _istft(Float32List spec, int channel) {
    final c = cfg;
    final half = c.nFft ~/ 2;
    final bins = half + 1;
    final plane = c.dimF * c.dimT;
    final length = c.nFft + c.hop * (c.dimT - 1);
    final y = Float64List(length);
    final norm = Float64List(length);
    final halfSpec = Float64x2List(bins);
    for (var t = 0; t < c.dimT; t++) {
      // Le bande oltre dimF la rete non le vede: restano a zero, cioe'
      // nella voce non c'e' niente sopra ~22 kHz.
      for (var f = 0; f < bins; f++) {
        halfSpec[f] = f < c.dimF
            ? Float64x2(
                spec[channel * plane + f * c.dimT + t],
                spec[(channel + 1) * plane + f * c.dimT + t],
              )
            : Float64x2.zero();
      }
      final frame = _fft.realInverseFft(halfSpec.createConjugates(c.nFft));
      final at = t * c.hop;
      for (var k = 0; k < c.nFft; k++) {
        final w = _window[k];
        y[at + k] += frame[k] * w;
        norm[at + k] += w * w;
      }
    }
    // Tolta la mezza finestra aggiunta davanti dal centrare, e divisa la
    // somma delle finestre: senza, il volume ondeggerebbe al passo di hop.
    final out = Float64List(c.chunk);
    for (var i = 0; i < c.chunk; i++) {
      final w = norm[half + i];
      out[i] = w > 1e-8 ? y[half + i] / w : 0;
    }
    return out;
  }
}
