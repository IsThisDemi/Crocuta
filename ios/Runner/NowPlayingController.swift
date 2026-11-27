import Flutter
import UIKit
import MediaPlayer
import WidgetKit

/// Bridges the Flutter player to the iOS lock screen / Control Center
/// "Now Playing" widget.
///
/// - Dart -> native: `crocuta/now_playing` channel, methods `update` / `clear`.
/// - native -> Dart: `crocuta/remote_commands` channel, methods `play`, `pause`,
///   `toggle`, `next`, `previous`, `seek` (with `position` in seconds).
class NowPlayingController: NSObject {
  private let remoteChannel: FlutterMethodChannel
  private var pendingArtworkURL: String?
  private var lastNowPlayingInfo: [String: Any]?

  /// L'ultimo stato passato al widget: si riscrive, e si chiede al sistema
  /// di ridisegnarlo, solo quando cambia davvero — la posizione arriva ogni
  /// secondo, il widget non la mostra.
  private var lastWidgetInfo: CrocutaShared.NowPlaying?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "crocuta/now_playing",
      binaryMessenger: messenger
    )
    let remote = FlutterMethodChannel(
      name: "crocuta/remote_commands",
      binaryMessenger: messenger
    )
    let instance = NowPlayingController(
      channel: channel,
      remoteChannel: remote
    )
    channel.setMethodCallHandler(instance.handle)
    instance.setupAudioSession()
    instance.setupRemoteCommands()
    // I pulsanti del widget: il sistema esegue i loro comandi qui, nell'app,
    // e passano dallo stesso canale del blocco schermo.
    CrocutaShared.perform = { [weak instance] command in
      instance?.send(command)
    }
  }

  init(channel: FlutterMethodChannel, remoteChannel: FlutterMethodChannel) {
    self.remoteChannel = remoteChannel
    super.init()
  }

  // MARK: - FlutterPlugin

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      updateNowPlaying(args)
      // Mentre suona, la sessione audio dev'essere attiva. Chiudendo un
      // player (a fine mix AutoMix ne chiude due) mpv la disattivava per
      // tutta l'app, e CarPlay rispondeva mettendo in pausa il brano
      // nuovo. mpv ora non lo fa piu' (patch in tool/libmpv); questo e'
      // il paracadute, per chiunque altro la rilasci.
      if args["playing"] as? Bool == true {
        try? AVAudioSession.sharedInstance().setActive(true)
      }
      result(nil)
    case "restoreSession":
      // Dopo il riconoscimento vocale, che lascia la sessione in
      // registrazione o la spegne: di nuovo riproduzione, e accesa.
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try? AVAudioSession.sharedInstance().setActive(true)
      result(nil)
    case "clear":
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      if let url = CrocutaShared.infoURL { try? FileManager.default.removeItem(at: url) }
      lastWidgetInfo = nil
      WidgetCenter.shared.reloadAllTimelines()
      lastNowPlayingInfo = nil
      pendingArtworkURL = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Now Playing info

  private func updateNowPlaying(_ args: [String: Any]) {
    var info: [String: Any] = [:]
    info[MPMediaItemPropertyTitle] = args["title"] as? String ?? ""
    info[MPMediaItemPropertyArtist] = args["artist"] as? String ?? ""
    info[MPMediaItemPropertyAlbumTitle] = "Crocuta"
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      args["position"] as? Double ?? 0
    info[MPMediaItemPropertyPlaybackDuration] =
      args["duration"] as? Double ?? 0
    info[MPNowPlayingInfoPropertyPlaybackRate] =
      (args["playing"] as? Bool == true) ? 1.0 : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

    // Keep the artwork that was already fetched, if any.
    if let artwork = lastNowPlayingInfo?[MPMediaItemPropertyArtwork] {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    lastNowPlayingInfo = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    let artworkURL = args["artworkUrl"] as? String ?? ""
    let widgetInfo = CrocutaShared.NowPlaying(
      title: args["title"] as? String ?? "",
      artist: args["artist"] as? String ?? "",
      playing: args["playing"] as? Bool == true,
      artworkURL: artworkURL
    )
    if widgetInfo != lastWidgetInfo {
      lastWidgetInfo = widgetInfo
      CrocutaShared.save(widgetInfo)
      WidgetCenter.shared.reloadAllTimelines()
    }
    if artworkURL != pendingArtworkURL {
      pendingArtworkURL = artworkURL
      loadArtwork(artworkURL) { [weak self] image in
        guard let self = self,
          self.pendingArtworkURL == artworkURL
        else { return }
        CrocutaShared.saveArtwork(image)
        WidgetCenter.shared.reloadAllTimelines()
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        if var current = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          current[MPMediaItemPropertyArtwork] = artwork
          self.lastNowPlayingInfo = current
          MPNowPlayingInfoCenter.default().nowPlayingInfo = current
        }
      }
    }
  }

  private func loadArtwork(
    _ urlString: String, completion: @escaping (UIImage) -> Void
  ) {
    guard let url = URL(string: urlString) else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data = data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async { completion(image) }
    }.resume()
  }

  // MARK: - Remote commands (lock screen / Control Center)

  private func setupRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.addTarget { [weak self] _ in
      self?.send("play")
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.send("pause")
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.send("toggle")
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      self?.send("next")
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      self?.send("previous")
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.send("seek", ["position": e.positionTime])
      return .success
    }
  }

  private func send(_ command: String, _ args: [String: Any] = [:]) {
    remoteChannel.invokeMethod(command, arguments: args)
  }

  // MARK: - Audio session

  private func setupAudioSession() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)
  }
}
