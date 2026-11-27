import Cocoa
import FlutterMacOS
import iTunesLibrary

/// Legge la libreria dell'app Musica per l'import da Apple Music (vedi
/// lib/services/apple_music_library.dart).
///
/// Con iTunesLibrary, in sola lettura: serve l'autorizzazione
/// com.apple.security.assets.music.read-only, e il sistema chiede il
/// permesso la prima volta (NSAppleMusicUsageDescription). Gli id sono gli
/// "id persistenti" in esadecimale, come nel Library.xml esportato da
/// Musica: lo stesso brano ha lo stesso id letto da qui o dal file.
enum AppleMusicReader {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "crocuta/apple_music",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "readLibrary" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Migliaia di brani: fuori dal thread principale.
      DispatchQueue.global(qos: .userInitiated).async {
        let reply: Any
        do {
          reply = try read()
        } catch {
          reply = FlutterError(
            code: "unavailable",
            message: "The Music library could not be read: "
              + error.localizedDescription,
            details: nil
          )
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  static func hex(_ id: NSNumber) -> String {
    String(format: "%016llX", id.uint64Value)
  }

  static func read() throws -> [String: Any] {
    let library = try ITLibrary(apiVersion: "1.1")
    var songs: [[String: Any]] = []
    for item in library.allMediaItems where item.mediaKind == .kindSong {
      songs.append([
        "id": hex(item.persistentID),
        "title": item.title,
        "artist": item.artist?.name ?? item.album.albumArtist ?? "",
        "album": item.album.title ?? "",
        "ms": item.totalTime,
        "added": item.addedDate.map { Int($0.timeIntervalSince1970 * 1000) }
          ?? 0,
      ])
    }
    var playlists: [[String: Any]] = []
    for p in library.allPlaylists {
      // La libreria intera, le liste di sistema, le cartelle, le nascoste:
      // non sono playlist fatte da qualcuno.
      if p.isPrimary || p.distinguishedKind != .kindNone || p.kind == .folder
        || !p.isVisible
      {
        continue
      }
      let items = p.items
        .filter { $0.mediaKind == .kindSong }
        .map { hex($0.persistentID) }
      if items.isEmpty { continue }
      playlists.append([
        "id": hex(p.persistentID),
        "name": p.name,
        "items": items,
      ])
    }
    return ["songs": songs, "playlists": playlists]
  }
}
