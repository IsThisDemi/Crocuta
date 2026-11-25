import AppIntents
import Flutter
import Foundation

// MARK: - Il catalogo

/// L'elenco delle cose che Siri puo' nominare, piu' la casella della posta.
///
/// Sta in `UserDefaults` e non in memoria per un motivo preciso: gli App
/// Intents possono girare in un processo che non e' quello dell'app, e
/// possono girare quando l'app non c'e' affatto. Una variabile statica
/// sarebbe vuota proprio nel caso che conta — "riproduci X" a telefono in
/// tasca, con Crocuta chiusa da ieri.
enum SiriCatalog {
  private static let indexKey = "yeen.siri.index"
  private static let commandKey = "yeen.siri.command"

  struct Song: Codable {
    let id: String
    let title: String
    let artist: String
  }

  struct Named: Codable {
    let id: String
    let name: String
  }

  struct Index: Codable {
    var songs: [Song] = []
    var artists: [Named] = []
    var playlists: [Named] = []
  }

  /// Scritto da Dart a ogni cambiamento della libreria.
  static func save(_ json: String) {
    UserDefaults.standard.set(json, forKey: indexKey)
  }

  static func load() -> Index {
    guard
      let json = UserDefaults.standard.string(forKey: indexKey),
      let data = json.data(using: .utf8),
      let index = try? JSONDecoder().decode(Index.self, from: data)
    else { return Index() }
    return index
  }

  /// Un intent non esegue niente: deposita qui e se ne va.
  static func put(_ action: String, _ value: String? = nil) {
    var command = ["action": action]
    if let value { command["value"] = value }
    UserDefaults.standard.set(command, forKey: commandKey)
  }

  /// Legge e cancella. Il "e cancella" e' la parte importante: e' cio' che
  /// garantisce che lo stesso comando non venga eseguito due volte quando
  /// Dart lo ritira sia sul risveglio sia sul messaggio di sveglia.
  static func takeCommand() -> [String: String]? {
    guard
      let command = UserDefaults.standard.dictionary(forKey: commandKey)
        as? [String: String]
    else { return nil }
    UserDefaults.standard.removeObject(forKey: commandKey)
    return command
  }
}

/// Confronto come lo farebbe una persona: senza accenti, senza maiuscole.
/// Siri trascrive "Perche'" in mille modi diversi.
private func fuzzyMatch(_ haystack: String, _ needle: String) -> Bool {
  let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
  return haystack.range(of: needle, options: options) != nil
}

// MARK: - Le entita'

/// Un brano della tua libreria.
///
/// Siri non accetta testo libero nelle frasi: genera una frase per ogni
/// valore che l'app dichiara. Questa entita' *e'* l'elenco dei valori, ed
/// e' il motivo per cui "riproduci X su Crocuta" funziona per la roba
/// tua e non per il catalogo intero di YouTube Music.
struct YeenSong: AppEntity {
  let id: String
  let title: String
  let artist: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Brano" }
  static var defaultQuery = YeenSongQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
  }
}

struct YeenSongQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [YeenSong] {
    SiriCatalog.load().songs
      .filter { identifiers.contains($0.id) }
      .map { YeenSong(id: $0.id, title: $0.title, artist: $0.artist) }
  }

  func entities(matching string: String) async throws -> [YeenSong] {
    SiriCatalog.load().songs
      .filter { fuzzyMatch($0.title, string) || fuzzyMatch($0.artist, string) }
      .map { YeenSong(id: $0.id, title: $0.title, artist: $0.artist) }
  }

  /// Quelli che Siri propone e indicizza per primi. L'ordine arriva gia'
  /// giusto da Dart — preferiti, poi playlist, poi recenti — quindi qui si
  /// taglia e basta.
  func suggestedEntities() async throws -> [YeenSong] {
    SiriCatalog.load().songs
      .prefix(50)
      .map { YeenSong(id: $0.id, title: $0.title, artist: $0.artist) }
  }
}

/// Un artista che segui.
struct YeenArtist: AppEntity {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Artista" }
  static var defaultQuery = YeenArtistQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

struct YeenArtistQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [YeenArtist] {
    SiriCatalog.load().artists
      .filter { identifiers.contains($0.id) }
      .map { YeenArtist(id: $0.id, name: $0.name) }
  }

  func entities(matching string: String) async throws -> [YeenArtist] {
    SiriCatalog.load().artists
      .filter { fuzzyMatch($0.name, string) }
      .map { YeenArtist(id: $0.id, name: $0.name) }
  }

  func suggestedEntities() async throws -> [YeenArtist] {
    SiriCatalog.load().artists.map { YeenArtist(id: $0.id, name: $0.name) }
  }
}

/// Una delle tue playlist.
struct YeenPlaylist: AppEntity {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Playlist" }
  static var defaultQuery = YeenPlaylistQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

struct YeenPlaylistQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [YeenPlaylist] {
    SiriCatalog.load().playlists
      .filter { identifiers.contains($0.id) }
      .map { YeenPlaylist(id: $0.id, name: $0.name) }
  }

  func entities(matching string: String) async throws -> [YeenPlaylist] {
    SiriCatalog.load().playlists
      .filter { fuzzyMatch($0.name, string) }
      .map { YeenPlaylist(id: $0.id, name: $0.name) }
  }

  func suggestedEntities() async throws -> [YeenPlaylist] {
    SiriCatalog.load().playlists.map { YeenPlaylist(id: $0.id, name: $0.name) }
  }
}

// MARK: - Gli intent

/// Quello che ogni intent fa: deposita e sveglia.
///
/// Non tocca il player, perche' il player e' Dart e Dart potrebbe non
/// esistere ancora: ritira il comando appena e' pronto.
///
/// Sono tutti AudioPlaybackIntent, e non piu' intent che aprono l'app:
/// aprirla non si puo' a telefono bloccato ne' in CarPlay, e Siri
/// rispondeva "c'e' stato un problema ad avviare Crocuta". Un comando di
/// riproduzione invece il sistema lo esegue nell'app in background,
/// avviandola se serve — e il motore Flutter ora parte con lei (vedi
/// AppDelegate).
private func dispatch(_ action: String, _ value: String? = nil) {
  SiriCatalog.put(action, value)
  DispatchQueue.main.async { SiriBridge.shared.poke() }
}

struct PlaySongIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Riproduci un brano"
  static var description = IntentDescription("Riproduce un brano della tua libreria.")

  @Parameter(title: "Brano")
  var song: YeenSong

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("song", song.id)
    return .result(dialog: "Riproduco \(song.title).")
  }
}

struct PlayArtistIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Riproduci un artista"
  static var description = IntentDescription(
    "Riproduce i brani migliori di un artista che segui, mescolati."
  )

  @Parameter(title: "Artista")
  var artist: YeenArtist

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("artist", artist.id)
    return .result(dialog: "Ecco \(artist.name).")
  }
}

struct PlayPlaylistIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Riproduci una playlist"
  static var description = IntentDescription("Riproduce una delle tue playlist.")

  @Parameter(title: "Playlist")
  var playlist: YeenPlaylist

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("playlist", playlist.id)
    return .result(dialog: "Riproduco \(playlist.name).")
  }
}

struct PlayFavoritesIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Riproduci i preferiti"
  static var description = IntentDescription("Riproduce i tuoi preferiti, mescolati.")

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("favorites")
    return .result(dialog: "Riproduco i tuoi preferiti.")
  }
}

/// L'unico punto in cui il testo e' libero.
///
/// La frase parlata non porta il valore — quello Siri non lo permette — ma
/// niente vieta a Siri di *chiederlo* subito dopo. Due passaggi invece di
/// uno, ed e' l'unico modo di arrivare a un brano che non hai in libreria.
struct SearchAndPlayIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Cerca e riproduci"
  static var description = IntentDescription(
    "Cerca su YouTube Music e riproduce il primo risultato."
  )

  @Parameter(title: "Cosa cercare", requestValueDialog: "Cosa vuoi ascoltare?")
  var query: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("search", query)
    return .result(dialog: "Cerco \(query).")
  }
}

/// "Avvia la radio di X": parte il brano e poi i simili.
struct StartRadioIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Avvia una radio"
  static var description = IntentDescription(
    "Fa partire un brano della tua libreria e poi i brani simili."
  )

  @Parameter(title: "Brano")
  var song: YeenSong

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("radio", song.id)
    return .result(dialog: "Radio di \(song.title).")
  }
}

/// Le playlist intelligenti, per nome.
enum SmartMix: String, AppEnum {
  case onRepeat, recentlyLiked, lateNight, forgotten

  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Playlist" }
  static var caseDisplayRepresentations: [SmartMix: DisplayRepresentation] = [
    .onRepeat: DisplayRepresentation(
      title: "On Repeat", synonyms: ["i piu' ascoltati", "i brani in loop"]),
    .recentlyLiked: DisplayRepresentation(
      title: "Recently Liked", synonyms: ["gli ultimi preferiti"]),
    .lateNight: DisplayRepresentation(
      title: "Late Night", synonyms: ["la musica della notte"]),
    .forgotten: DisplayRepresentation(
      title: "Forgotten Favorites", synonyms: ["i preferiti dimenticati"]),
  ]
}

struct PlaySmartMixIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Riproduci una playlist intelligente"
  static var description = IntentDescription(
    "On Repeat, Recently Liked, Late Night o Forgotten Favorites."
  )

  @Parameter(title: "Playlist")
  var mix: SmartMix

  func perform() async throws -> some IntentResult & ProvidesDialog {
    dispatch("smart", mix.rawValue)
    return .result(dialog: "Ecco la tua playlist.")
  }
}

/// "Riprendi la musica": riparte da dove eri.
struct ResumeIntent: AudioPlaybackIntent {
  static var title: LocalizedStringResource = "Riprendi"
  static var description = IntentDescription("Riprende la musica da dove eri.")

  func perform() async throws -> some IntentResult {
    dispatch("resume")
    return .result()
  }
}

// MARK: - Le frasi

/// Ogni frase deve contenere il nome dell'app: e' una regola di Apple, non
/// una scelta di stile. Il massimo e' dieci scorciatoie; qui sono otto.
struct YeenShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlaySongIntent(),
      phrases: [
        "Riproduci \(\.$song) su \(.applicationName)",
        "Metti \(\.$song) su \(.applicationName)",
        "Ascolta \(\.$song) su \(.applicationName)",
        "Fammi sentire \(\.$song) su \(.applicationName)",
      ],
      shortTitle: "Riproduci brano",
      systemImageName: "music.note"
    )
    AppShortcut(
      intent: PlayArtistIntent(),
      phrases: [
        "Riproduci \(\.$artist) su \(.applicationName)",
        "Metti \(\.$artist) su \(.applicationName)",
        "Ascolta \(\.$artist) su \(.applicationName)",
      ],
      shortTitle: "Riproduci artista",
      systemImageName: "music.mic"
    )
    AppShortcut(
      intent: PlayPlaylistIntent(),
      phrases: [
        "Riproduci la playlist \(\.$playlist) su \(.applicationName)",
        "Metti la playlist \(\.$playlist) su \(.applicationName)",
      ],
      shortTitle: "Riproduci playlist",
      systemImageName: "music.note.list"
    )
    AppShortcut(
      intent: PlayFavoritesIntent(),
      phrases: [
        "Riproduci i preferiti su \(.applicationName)",
        "Riproduci i miei preferiti su \(.applicationName)",
        "Metti i preferiti su \(.applicationName)",
        "Metti i miei preferiti su \(.applicationName)",
        "Ascolta i miei preferiti su \(.applicationName)",
        "Riproduci la mia musica su \(.applicationName)",
        "Metti qualcosa su \(.applicationName)",
        "Fammi sentire qualcosa su \(.applicationName)",
      ],
      shortTitle: "Riproduci i preferiti",
      systemImageName: "heart.fill"
    )
    AppShortcut(
      intent: SearchAndPlayIntent(),
      phrases: [
        "Cerca su \(.applicationName)",
        "Cerca musica su \(.applicationName)",
      ],
      shortTitle: "Cerca e riproduci",
      systemImageName: "magnifyingglass"
    )
    AppShortcut(
      intent: StartRadioIntent(),
      phrases: [
        "Avvia la radio di \(\.$song) su \(.applicationName)",
        "Radio di \(\.$song) su \(.applicationName)",
      ],
      shortTitle: "Avvia una radio",
      systemImageName: "dot.radiowaves.left.and.right"
    )
    AppShortcut(
      intent: PlaySmartMixIntent(),
      phrases: [
        "Metti \(\.$mix) su \(.applicationName)",
        "Riproduci \(\.$mix) su \(.applicationName)",
      ],
      shortTitle: "Playlist intelligente",
      systemImageName: "sparkles"
    )
    AppShortcut(
      intent: ResumeIntent(),
      phrases: [
        "Riprendi la musica su \(.applicationName)",
        "Continua su \(.applicationName)",
      ],
      shortTitle: "Riprendi",
      systemImageName: "play.fill"
    )
  }
}

// MARK: - Il canale

/// Il lato nativo di `lib/services/siri_service.dart`.
final class SiriBridge {
  static let shared = SiriBridge()

  private var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "yeen/siri", binaryMessenger: messenger)
    shared.channel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "publish":
        if let args = call.arguments as? [String: Any],
          let index = args["index"] as? String
        {
          SiriCatalog.save(index)
          // Le playlist anche al widget "Play", che sta in un altro
          // processo e UserDefaults dell'app non li vede.
          if let data = index.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(SiriCatalog.Index.self, from: data)
          {
            CrocutaShared.savePlaylists(
              decoded.playlists.map { PlayTarget.Stored(id: $0.id, name: $0.name) })
          }
          // Senza, Siri non sa quali brani, artisti e playlist esistono, e
          // le frasi con un nome dentro — "Riproduci Hope su Crocuta" —
          // non scattano mai: le genera per i valori che l'app dichiara.
          YeenShortcuts.updateAppShortcutParameters()
        }
        result(nil)
      case "takeCommand":
        result(SiriCatalog.takeCommand())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// "C'e' posta." Il contenuto lo va a prendere Dart, cosi' la casella
  /// resta l'unica copia del comando.
  func poke() {
    channel?.invokeMethod("poke", arguments: nil)
  }
}
