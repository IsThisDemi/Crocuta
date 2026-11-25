import AppKit
import Foundation

/// Cio' che app e widget del Mac si passano: il brano in corso, e i
/// comandi dei pulsanti.
///
/// Non un App Group come sull'iPhone: l'app del Mac e' firmata ad-hoc,
/// senza profilo, e un App Group senza profilo macOS non lo concede. Si
/// usa una cartella fuori dai contenitori, che l'app puo' scrivere e il
/// widget leggere per un'eccezione della sandbox limitata a lei. Fuori dai
/// contenitori di proposito: leggere quello di un'altra app fa chiedere a
/// macOS un permesso, che un widget non ha modo di chiedere.
enum CrocutaShared {
  /// La cartella, relativa alla home: la stessa scritta nelle eccezioni
  /// della sandbox di app e widget.
  static let folder = "Library/Application Support/Crocuta Widget"

  /// La home vera: in sandbox NSHomeDirectory() e' quella del contenitore.
  static var realHome: URL {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
      return URL(fileURLWithPath: String(cString: dir))
    }
    return FileManager.default.homeDirectoryForCurrentUser
  }

  static var directory: URL { realHome.appendingPathComponent(folder, isDirectory: true) }
  static var infoURL: URL { directory.appendingPathComponent("now_playing.json") }
  static var artworkURL: URL { directory.appendingPathComponent("now_playing.jpg") }

  struct NowPlaying: Codable, Equatable {
    var title: String
    var artist: String
    var playing: Bool
    var artworkURL: String
  }

  static func load() -> NowPlaying? {
    guard let data = try? Data(contentsOf: infoURL) else { return nil }
    return try? JSONDecoder().decode(NowPlaying.self, from: data)
  }

  static func save(_ info: NowPlaying) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(info) else { return }
    try? data.write(to: infoURL, options: .atomic)
  }

  static func clear() {
    try? FileManager.default.removeItem(at: infoURL)
  }

  static func artwork() -> NSImage? { NSImage(contentsOf: artworkURL) }

  static func saveArtwork(_ image: NSImage) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let side = 400
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
      try? data.write(to: artworkURL, options: .atomic)
    }
  }

  /// I comandi dei pulsanti, come notifiche di sistema: il widget, in
  /// sandbox, puo' mandarle, e l'app le ascolta. Sul Mac i comandi di un
  /// widget girano nel widget, non nell'app.
  static func notificationName(_ command: String) -> String {
    "com.personal.demusLike.widget.\(command)"
  }

  static let commands = ["toggle", "next", "previous"]

  static func post(_ command: String) {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(notificationName(command) as CFString),
      nil, nil, true)
  }
}
