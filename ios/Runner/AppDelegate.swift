import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Il motore Flutter, acceso all'avvio dell'app e non all'apertura della
  /// finestra.
  ///
  /// Prima lo creava la finestra, dallo storyboard. Ma un comando Siri o
  /// un pulsante del widget — in auto, col telefono in tasca — avviano
  /// l'app in background, senza finestra: il motore non c'era, Dart non
  /// partiva, e il comando restava li'. Ora c'e' sempre, e la finestra,
  /// quando arriva, usa questo invece di crearne un secondo (due motori
  /// vorrebbero dire due player).
  lazy var engine = FlutterEngine(name: "crocuta")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    let messenger = engine.binaryMessenger
    // Lock screen / Control Center "Now Playing" controls.
    NowPlayingController.register(messenger: messenger)
    // Siri: indice della libreria in uscita, comandi degli App Intents in
    // entrata (vedi YeenIntents.swift).
    SiriBridge.register(messenger: messenger)
    // Il riconoscimento vocale dell'assistente interno.
    VoiceRecognizer.register(messenger: messenger)
    // I pulsanti del widget che fanno partire qualcosa: passano dalla
    // stessa casella dei comandi Siri, che Dart ritira quando e' pronto.
    CrocutaShared.command = { action, value in
      SiriCatalog.put(action, value)
      SiriBridge.shared.poke()
    }

    let registrar = engine.registrar(forPlugin: "CrocutaViews")!
    // Liquid Glass di sistema per la chrome (tab bar, mini player, barre).
    registrar.register(
      GlassPlatformViewFactory(messenger: registrar.messenger()),
      withId: GlassPlatformViewFactory.viewType
    )
    // Il pulsante AirPlay di sistema, per il player.
    registrar.register(
      RoutePickerViewFactory(),
      withId: RoutePickerViewFactory.viewType
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
