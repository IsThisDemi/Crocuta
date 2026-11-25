import AVKit
import Flutter
import UIKit

/// Il pulsante AirPlay di sistema, dentro una platform view.
///
/// `AVRoutePickerView` e' interfaccia di Apple: apre il suo pannello per
/// scegliere dove suonare — cassa, TV, cuffie — e sposta l'uscita audio
/// dell'app intera, quindi anche quella di libmpv. Non serve nessuna
/// autorizzazione: e' lo stesso pulsante che usano le app di sistema.
///
/// Al contrario del vetro, qui il tocco deve arrivare: e' un pulsante.
final class RoutePickerView: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView

  init(frame: CGRect, args: Any?) {
    picker = AVRoutePickerView(frame: frame)
    let params = args as? [String: Any] ?? [:]
    picker.tintColor = RoutePickerView.color(params["tint"]) ?? .white
    picker.activeTintColor = RoutePickerView.color(params["activeTint"]) ?? .systemBlue
    // Solo audio: senza, il pannello metterebbe in cima le TV per i video.
    picker.prioritizesVideoDevices = false
    picker.backgroundColor = .clear
    super.init()
  }

  func view() -> UIView { picker }

  private static func color(_ value: Any?) -> UIColor? {
    guard let n = value as? NSNumber else { return nil }
    let argb = n.uint32Value
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}

final class RoutePickerViewFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "yeen/route_picker"

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    RoutePickerView(frame: frame, args: args)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
