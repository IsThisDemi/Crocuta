import Cocoa
import FlutterMacOS

/// Le prove automatiche (lib/dev/readme_shots.dart) su un Mac dove qualcuno
/// lavora. Con `CROCUTA_HIDDEN_WINDOW=1`, e solo nelle build di debug, la
/// finestra c'e' e disegna ma e' trasparente, non prende clic e non va in
/// primo piano; l'app non e' nel Dock, non registra le scorciatoie globali
/// e non scrive in "In riproduzione": accanto alla Crocuta vera, aperta,
/// non le toglie niente. L'app si fotografa da sola dal suo albero di
/// widget. `CROCUTA_WINDOW_SIZE=430x932` fissa la misura della finestra.
enum CrocutaDebug {
  static let hiddenWindow: Bool = {
    #if DEBUG
      return ProcessInfo.processInfo.environment["CROCUTA_HIDDEN_WINDOW"] == "1"
    #else
      return false
    #endif
  }()

  static var windowSize: NSSize? {
    guard hiddenWindow,
      let raw = ProcessInfo.processInfo.environment["CROCUTA_WINDOW_SIZE"]
    else { return nil }
    let parts = raw.split(separator: "x").compactMap { Double($0) }
    guard parts.count == 2 else { return nil }
    return NSSize(width: parts[0], height: parts[1])
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // L'interfaccia e' sempre scura, e il vetro di sistema deve saperlo:
    // senza, NSGlassEffectView segue l'aspetto del Mac, e con il Mac in
    // chiaro rende la sua variante chiara sotto scritte che disegnamo
    // bianche. Su iOS lo stesso lo dichiara UIUserInterfaceStyle nel plist.
    NSApp.appearance = NSAppearance(named: .darkAqua)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // macOS has no FlutterImplicitEngineDelegate hook like iOS: this is the
    // registration point. Gives the app the Control Centre "Now Playing"
    // widget and the F7/F8/F9 media keys.
    NowPlayingController.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    // Il mini player nativo (Finestra ▸ Mini Player, ⌥⌘M) e le scorciatoie
    // globali ⌃⌥⌘: entrambi parlano a Dart tramite NowPlayingController.
    MiniPlayerController.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    if !CrocutaDebug.hiddenWindow { GlobalHotKeys.shared.register() }
    // La libreria dell'app Musica, per l'import da Apple Music.
    AppleMusicReader.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    // Il riconoscimento vocale dell'assistente interno, col microfono del
    // Mac e non quello degli AirPods.
    VoiceRecognizer.register(
      messenger: flutterViewController.engine.binaryMessenger
    )

    // La finestra a tutto schermo e ritorno, per il videoclip (vedi
    // AppWindow in lib/services/app_window.dart).
    let windowChannel = FlutterMethodChannel(
      name: "crocuta/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      let full = self.styleMask.contains(.fullScreen)
      switch call.method {
      case "isFullScreen":
        result(full)
      case "setFullScreen":
        let want = call.arguments as? Bool ?? !full
        if want != full { self.toggleFullScreen(nil) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Platform view che ospita NSGlassEffectView: serve a verificare sul
    // campo se il vetro di sistema rifrange il contenuto Flutter o solo lo
    // sfondo della finestra.
    let glassRegistrar = flutterViewController.engine.registrar(
      forPlugin: "GlassPlatformView"
    )
    glassRegistrar.register(
      GlassPlatformViewFactory(messenger: glassRegistrar.messenger),
      withId: GlassPlatformViewFactory.viewType
    )
    // Il pulsante AirPlay di sistema, per il player.
    glassRegistrar.register(
      RoutePickerViewFactory(),
      withId: RoutePickerViewFactory.viewType
    )

    // Barra del titolo trasparente e contenuto a tutta finestra, come fa
    // Apple Music: l'interfaccia arriva fino al bordo superiore e i semafori
    // galleggiano sopra. Il lato Flutter lascia il margine per non finirci
    // sotto (vedi AppTopBar / AppShell).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    if CrocutaDebug.hiddenWindow {
      self.alphaValue = 0
      self.ignoresMouseEvents = true
      self.hasShadow = false
      self.setFrameAutosaveName("")
      NSApp.setActivationPolicy(.accessory)
      if let size = CrocutaDebug.windowSize {
        // Dopo l'avvio: la misura salvata dall'ultima volta arriva dopo
        // awakeFromNib e la scavalcherebbe.
        for delay in [0.0, 0.5, 1.5] {
          DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.setContentSize(size)
          }
        }
      }
    }

    super.awakeFromNib()
  }
}
