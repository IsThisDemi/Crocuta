import Cocoa
import FlutterMacOS

/// Hosts Apple's real `NSGlassEffectView` (macOS 26+) inside a Flutter
/// platform view.
///
/// This exists to settle a question empirically rather than by argument: the
/// system glass samples the *native* view hierarchy behind it, and Flutter
/// draws its interface into its own surface. Whether that means the effect
/// refracts the app's content or just the window background is not something
/// worth guessing about — so this makes it possible to look.
///
/// Falls back to `NSVisualEffectView` (the pre-26 material) when the system
/// is older, so the spike still renders something sensible.
/// Costruisce la vista nativa. Su macOS la factory restituisce
/// direttamente un NSView: il protocollo FlutterPlatformView e' solo iOS.
class GlassPlatformView: NSObject {
  private let container: NSView

  init(frame: CGRect, args: Any?) {
    let params = args as? [String: Any] ?? [:]
    let radius = params["radius"] as? CGFloat ?? 28

    let capsule = params["capsule"] as? Bool ?? false

    if #available(macOS 26.0, *) {
      let glass = capsule
        ? CapsuleGlassView(frame: frame) : NSGlassEffectView(frame: frame)
      glass.cornerRadius = radius
      // Il vetro "clear" e' quello della lente che Apple mette sotto il
      // dito: quasi niente materiale, solo la rifrazione dei bordi.
      if params["clear"] as? Bool == true { glass.style = .clear }
      if let tint = params["tintArgb"] as? NSNumber {
        glass.tintColor = GlassPlatformView.color(from: tint.uint32Value)
      }
      container = glass
    } else {
      let fallback = NSVisualEffectView(frame: frame)
      fallback.material = .hudWindow
      fallback.blendingMode = .withinWindow
      fallback.state = .active
      fallback.wantsLayer = true
      fallback.layer?.cornerRadius = radius
      container = fallback
    }

    // NIENTE alphaValue, come sulla gemella iOS. Abbassare l'opacita' di
    // una vista a effetto la obbliga a comporsi in un passaggio fuori
    // schermo, e il materiale si appiattisce: il vetro perde la rifrazione
    // e resta una velatura. Era il motivo per cui il nostro sembrava
    // spento accanto a quello di Apple Music. Se servisse smorzarlo, la
    // leva giusta e' il tintColor dell'effetto, non l'opacita'.

    container.autoresizingMask = [.width, .height]
    super.init()
  }

  private static func color(from argb: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }

  var view: NSView { container }
}

/// Vetro a capsula: il raggio segue l'altezza a ogni layout.
///
/// Serve alla lente della barra, che cresce e si ritrae mentre la si
/// trascina: un raggio fisso, scelto per una sola altezza, a meta'
/// animazione sarebbe troppo grande o troppo piccolo. Su iOS lo stesso
/// lo fa `cornerConfiguration = .capsule()`.
@available(macOS 26.0, *)
private class CapsuleGlassView: NSGlassEffectView {
  override func layout() {
    super.layout()
    cornerRadius = bounds.height / 2
  }
}

class GlassPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "yeen/native_glass"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?)
    -> NSView
  {
    GlassPlatformView(frame: .zero, args: args).view
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  /// True when the system can actually provide Liquid Glass.
  static var isSupported: Bool {
    if #available(macOS 26.0, *) { return true }
    return false
  }
}
