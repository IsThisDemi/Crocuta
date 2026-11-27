import AVKit
import Cocoa
import FlutterMacOS

/// Il pulsante AirPlay di sistema su macOS: stesso `AVRoutePickerView`
/// di iOS, qui come NSView. Sceglie l'uscita audio dell'app — un
/// altoparlante AirPlay, un'altra scheda audio — e libmpv la segue.
final class RoutePickerViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "crocuta/route_picker"

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let picker = AVRoutePickerView(frame: .zero)
    let params = args as? [String: Any] ?? [:]
    if let tint = color(params["tint"]) {
      picker.setRoutePickerButtonColor(tint, for: .normal)
    }
    if let active = color(params["activeTint"]) {
      picker.setRoutePickerButtonColor(active, for: .active)
    }
    picker.isRoutePickerButtonBordered = false
    return picker
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  private func color(_ value: Any?) -> NSColor? {
    guard let n = value as? NSNumber else { return nil }
    let argb = n.uint32Value
    return NSColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
