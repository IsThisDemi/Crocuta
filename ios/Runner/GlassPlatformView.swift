import Flutter
import UIKit

/// Il Liquid Glass di Apple (`UIGlassEffect`, iOS 26+) dentro una platform
/// view, gemello della versione macOS in `macos/Runner/GlassPlatformView.swift`.
///
/// Sotto iOS 26 ricade su `UIBlurEffect`, così la chrome resta leggibile
/// anche sui sistemi più vecchi invece di sparire.
///
/// Due regole di UIKit che qui non sono facoltative: l'opacità della vista
/// va lasciata a 1, e il raggio degli angoli si dichiara con
/// `cornerConfiguration`. Violarne una fa sembrare rotto il vetro senza
/// nessun errore a schermo.
class GlassPlatformView: NSObject, FlutterPlatformView {
  private let container: UIVisualEffectView

  init(frame: CGRect, args: Any?) {
    let params = args as? [String: Any] ?? [:]
    let radius = params["radius"] as? CGFloat ?? 20

    let capsule = params["capsule"] as? Bool ?? false
    let clear = params["clear"] as? Bool ?? false

    if #available(iOS 26.0, *) {
      // Il vetro "clear" e' quello della lente che Apple mette sotto il
      // dito: quasi niente materiale, solo la rifrazione dei bordi.
      let effect = UIGlassEffect(style: clear ? .clear : .regular)
      if let tint = params["tintArgb"] as? NSNumber {
        effect.tintColor = GlassPlatformView.color(from: tint.uint32Value)
      }
      container = UIVisualEffectView(effect: effect)
      // Da iOS 26 il vetro ignora `layer.cornerRadius` e prende una forma
      // predefinita: il raggio si dichiara con `cornerConfiguration`.
      // Ritagliare il layer, oltre a non servire, tagliava via i riflessi
      // che il materiale disegna appena fuori dai bordi.
      // La capsula segue l'altezza da sola: la lente della barra cresce e
      // si ritrae, e un raggio fisso a meta' animazione non tornerebbe.
      container.cornerConfiguration = capsule
        ? .capsule() : .corners(radius: .fixed(Double(radius)))
    } else {
      container = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemThinMaterialDark)
      )
      container.layer.cornerRadius = radius
      container.layer.cornerCurve = .continuous
      container.clipsToBounds = true
    }

    container.frame = frame

    // NIENTE alpha, al contrario della versione macOS. Apple documenta che
    // un'alpha < 1 su una UIVisualEffectView (o su un suo antenato) obbliga
    // il sistema a comporla in un passaggio fuori schermo, e l'effetto
    // degrada a una velatura piatta: era il motivo per cui su iPhone si
    // vedeva il ripiego invece del vetro. Il grado di trasparenza, se
    // servisse, va messo sul tintColor dell'effetto.

    // Il vetro e' decorazione, non un comando. Senza questo la platform
    // view intercetta i tocchi e il GestureDetector che la sopravanza non
    // riceve piu' il tap: premendo la barra del brano in riproduzione non
    // si apriva il player.
    container.isUserInteractionEnabled = false

    // Sempre la variante scura. Su iOS 26 il vetro si adatta a cio' che ha
    // dietro e sopra una copertina chiara passava al vetro chiaro, anche in
    // un'app scura: la barra e il brano in riproduzione diventavano
    // lattiginosi. Sul Mac lo stesso lo ottiene NSApp.appearance = darkAqua.
    container.overrideUserInterfaceStyle = .dark

    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    super.init()
  }

  private static func color(from argb: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  func view() -> UIView { container }
}

class GlassPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "crocuta/native_glass"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    GlassPlatformView(frame: frame, args: args)
  }

  // Su iOS il protocollo lo vuole non opzionale, al contrario di macOS.
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
