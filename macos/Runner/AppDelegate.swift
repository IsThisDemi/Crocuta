import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Chiudere la finestra chiude l'app, tranne quando a nasconderla e' il
    // mini player: li' l'app e' viva, solo piu' piccola.
    return !MiniPlayerController.shared.holdsAppOpen
  }

  // Clic sull'icona nel Dock con la finestra grande nascosta dal mini
  // player: la si riporta. FlutterAppDelegate non lo implementa, quindi
  // niente super.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    return MiniPlayerController.shared.handleReopen()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
