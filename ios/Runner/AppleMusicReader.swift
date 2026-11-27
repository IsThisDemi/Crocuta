import Flutter
import MediaPlayer

/// Legge la libreria musicale dell'iPhone per l'import da Apple Music (vedi
/// lib/services/apple_music_library.dart).
///
/// Con MediaPlayer: il sistema chiede il permesso la prima volta
/// (NSAppleMusicUsageDescription). Con "Sincronizza libreria" attivo ci
/// sono anche i brani aggiunti da Apple Music. Gli id sono gli "id
/// persistenti" in esadecimale, come nel Library.xml esportato da Musica.
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
      MPMediaLibrary.requestAuthorization { status in
        guard status == .authorized else {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "denied",
                message: "Crocuta is not allowed to read your music library.",
                details: nil
              ))
          }
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let reply = read()
          DispatchQueue.main.async { result(reply) }
        }
      }
    }
  }

  static func hex(_ id: MPMediaEntityPersistentID) -> String {
    String(format: "%016llX", id)
  }

  static func read() -> [String: Any] {
    var songs: [[String: Any]] = []
    for item in MPMediaQuery.songs().items ?? [] {
      songs.append([
        "id": hex(item.persistentID),
        "title": item.title ?? "",
        "artist": item.artist ?? item.albumArtist ?? "",
        "album": item.albumTitle ?? "",
        "ms": Int(item.playbackDuration * 1000),
        "added": Int(item.dateAdded.timeIntervalSince1970 * 1000),
      ])
    }
    var playlists: [[String: Any]] = []
    for case let p as MPMediaPlaylist in MPMediaQuery.playlists().collections ?? [] {
      // Le Genius sono fatte dal sistema, non da qualcuno.
      if p.playlistAttributes.contains(.genius) { continue }
      let items = p.items.map { hex($0.persistentID) }
      if items.isEmpty { continue }
      playlists.append([
        "id": hex(p.persistentID),
        "name": p.name ?? "Playlist",
        "items": items,
      ])
    }
    return ["songs": songs, "playlists": playlists]
  }
}
