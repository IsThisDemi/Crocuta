import Cocoa
import FlutterMacOS

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
    GlobalHotKeys.shared.register()
    // Il riconoscimento vocale dell'assistente interno, col microfono del
    // Mac e non quello degli AirPods.
    VoiceRecognizer.register(
      messenger: flutterViewController.engine.binaryMessenger
    )

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

    super.awakeFromNib()
  }
}
