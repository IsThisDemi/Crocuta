import Flutter
import UIKit

/// La finestra, costruita qui e non dallo storyboard: lo storyboard creava
/// un FlutterViewController con un motore suo, mentre il motore c'e' gia'
/// — lo accende l'AppDelegate all'avvio, anche in background.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard
      let windowScene = scene as? UIWindowScene,
      let app = UIApplication.shared.delegate as? AppDelegate
    else { return }
    let controller = FlutterViewController(
      engine: app.engine, nibName: nil, bundle: nil)
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = controller
    self.window = window
    window.makeKeyAndVisible()
    // Gli eventi della scena (primo piano, background) arrivano ai plugin
    // come prima.
    _ = registerSceneLifeCycle(with: app.engine)
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    handle(connectionOptions.urlContexts)
  }

  /// crocuta://listen: l'assistente vocale, gia' in ascolto. Per il tasto
  /// Azione o il tocco sul retro, con un Comando Rapido "Apri URL".
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    handle(URLContexts)
  }

  private func handle(_ contexts: Set<UIOpenURLContext>) {
    guard let url = contexts.first?.url, url.scheme == "crocuta" else { return }
    if url.host == "listen" {
      SiriCatalog.put("listen")
      DispatchQueue.main.async { SiriBridge.shared.poke() }
    }
  }
}
