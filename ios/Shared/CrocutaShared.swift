import AppIntents
import Foundation
import UIKit
import WidgetKit

/// Cio' che app e widget si passano: il brano in corso, in un contenitore
/// condiviso (App Group).
///
/// Il nome del contenitore non e' scritto qui una volta per tutte: AltStore,
/// rifirmando con il tuo Apple ID, gli aggiunge il tuo team, e un nome
/// fisso non esisterebbe piu'. App e widget lo leggono entrambi dal
/// proprio profilo di firma, dove AltStore ha messo quello vero.
enum CrocutaShared {
  /// Il nome dichiarato, prima che AltStore lo cambi: vale in Xcode e nel
  /// simulatore, dove il profilo non c'e'.
  static let declaredGroup = "group.dev.riccardo.demuslike"

  static let groupID: String = {
    if let url = Bundle.main.url(
      forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url),
      let group = appGroup(inProvision: data)
    {
      return group
    }
    return declaredGroup
  }()

  /// Il primo App Group nel profilo: un plist dentro una busta firmata, da
  /// cui basta ritagliare la parte in XML.
  static func appGroup(inProvision data: Data) -> String? {
    guard
      let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
    else { return nil }
    let xml = data.subdata(in: start.lowerBound..<end.upperBound)
    guard
      let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil)
        as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any],
      let groups = entitlements["com.apple.security.application-groups"] as? [String]
    else { return nil }
    return groups.first
  }

  static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
  }

  static var infoURL: URL? { container?.appendingPathComponent("now_playing.json") }
  static var artworkURL: URL? { container?.appendingPathComponent("now_playing.jpg") }

  struct NowPlaying: Codable, Equatable {
    var title: String
    var artist: String
    var playing: Bool
    var artworkURL: String
  }

  static func load() -> NowPlaying? {
    guard let url = infoURL, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(NowPlaying.self, from: data)
  }

  static func save(_ info: NowPlaying) {
    guard let url = infoURL, let data = try? JSONEncoder().encode(info) else { return }
    try? data.write(to: url, options: .atomic)
  }

  static func artwork() -> UIImage? {
    guard let url = artworkURL else { return nil }
    return UIImage(contentsOfFile: url.path)
  }

  static func saveArtwork(_ image: UIImage) {
    guard let url = artworkURL else { return }
    // Piccola: un widget non e' mai piu' grande di cosi', e il sistema ne
    // limita la memoria.
    let side: CGFloat = 400
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    let scaled = renderer.image { _ in
      image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    if let data = scaled.jpegData(compressionQuality: 0.85) {
      try? data.write(to: url, options: .atomic)
    }
  }

  /// Chi esegue i comandi nell'app. Nel widget resta vuoto: i comandi di
  /// riproduzione il sistema li esegue nel processo dell'app.
  nonisolated(unsafe) static var perform: ((String) -> Void)?

  /// Chi fa partire qualcosa nell'app (una playlist, i preferiti): passa
  /// dalla casella dei comandi Siri. Vuoto nel widget, come [perform].
  nonisolated(unsafe) static var command: ((String, String?) -> Void)?

  static var playlistsURL: URL? { container?.appendingPathComponent("playlists.json") }

  /// Le tue playlist, per sceglierne una nel widget "Play": le scrive
  /// l'app insieme all'indice di Siri.
  static func savePlaylists(_ list: [PlayTarget.Stored]) {
    guard let url = playlistsURL, let data = try? JSONEncoder().encode(list) else { return }
    try? data.write(to: url, options: .atomic)
  }

  static func loadPlaylists() -> [PlayTarget.Stored] {
    guard let url = playlistsURL, let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([PlayTarget.Stored].self, from: data)) ?? []
  }
}

/// Cosa puo' far partire il widget "Play": i preferiti mescolati, una
/// playlist intelligente, una delle tue playlist, o la ripresa.
struct PlayTarget: AppEntity {
  /// Codificato come lo capisce Dart: "favorites", "smart:onRepeat",
  /// "playlist:3", "resume".
  let id: String
  let name: String

  struct Stored: Codable {
    let id: String
    let name: String
  }

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Music" }
  static var defaultQuery = PlayTargetQuery()

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

  static let builtIn: [PlayTarget] = [
    PlayTarget(id: "favorites", name: "Liked Songs"),
    PlayTarget(id: "smart:onRepeat", name: "On Repeat"),
    PlayTarget(id: "smart:recentlyLiked", name: "Recently Liked"),
    PlayTarget(id: "smart:lateNight", name: "Late Night"),
    PlayTarget(id: "smart:forgotten", name: "Forgotten Favorites"),
    PlayTarget(id: "resume", name: "Resume"),
  ]

  static func all() -> [PlayTarget] {
    builtIn + CrocutaShared.loadPlaylists().map { PlayTarget(id: "playlist:\($0.id)", name: $0.name) }
  }

  /// Il comando per Dart: azione e valore, come quelli di Siri.
  var command: (String, String?) {
    let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
    return (parts[0], parts.count > 1 ? parts[1] : nil)
  }

  /// L'icona: la stessa delle playlist intelligenti nell'app.
  var symbol: String {
    switch id {
    case "favorites": return "heart.fill"
    case "smart:onRepeat": return "repeat"
    case "smart:recentlyLiked": return "heart.circle.fill"
    case "smart:lateNight": return "moon.stars.fill"
    case "smart:forgotten": return "clock.arrow.circlepath"
    case "resume": return "play.fill"
    default: return "music.note.list"
    }
  }
}

struct PlayTargetQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [PlayTarget] {
    PlayTarget.all().filter { identifiers.contains($0.id) }
  }

  func suggestedEntities() async throws -> [PlayTarget] { PlayTarget.all() }

  func defaultResult() async -> PlayTarget? { PlayTarget.builtIn.first }
}

/// Fa partire quello che il widget "Play" ha scelto. AudioPlaybackIntent:
/// gira nell'app, anche a telefono bloccato o in CarPlay, senza aprirla.
struct PlayTargetIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play"

  @Parameter(title: "What")
  var target: PlayTarget

  init() {}
  init(target: PlayTarget) { self.target = target }

  func perform() async throws -> some IntentResult {
    let (action, value) = target.command
    await MainActor.run { CrocutaShared.command?(action, value) }
    return .result()
  }
}

/// La scelta nel widget: cosa fa partire.
struct PlayTargetConfig: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Play"
  static let description = IntentDescription("Starts your music with one tap.")

  @Parameter(title: "What")
  var target: PlayTarget?
}

/// Play/pausa dal widget. AudioPlaybackIntent: il sistema lo esegue
/// nell'app, che e' quella che suona, e non nel widget.
struct TogglePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"

  func perform() async throws -> some IntentResult {
    await MainActor.run { CrocutaShared.perform?("toggle") }
    return .result()
  }
}

struct NextTrackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Next Song"

  func perform() async throws -> some IntentResult {
    await MainActor.run { CrocutaShared.perform?("next") }
    return .result()
  }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Previous Song"

  func perform() async throws -> some IntentResult {
    await MainActor.run { CrocutaShared.perform?("previous") }
    return .result()
  }
}
