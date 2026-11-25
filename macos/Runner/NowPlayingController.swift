import Cocoa
import FlutterMacOS
import MediaPlayer
import WidgetKit

/// Bridges the Flutter player to the macOS "Now Playing" system: the Control
/// Centre widget, the menu bar module, and the F7/F8/F9 media keys.
///
/// Ported from `ios/Runner/NowPlayingController.swift`, which it mirrors
/// channel for channel, so the Dart side needs no changes at all:
///
/// - Dart -> native: `demus/now_playing`, methods `update` / `clear`.
/// - native -> Dart: `demus/remote_commands`, methods `play`, `pause`,
///   `toggle`, `next`, `previous`, `seek` (with `position` in seconds).
///
/// Three deliberate differences from the iOS version:
///
/// 1. `NSImage` instead of `UIImage`.
/// 2. No audio session setup: `AVAudioSession` does not exist on macOS
///    (leaving the call in is a compile error), and libmpv drives CoreAudio
///    itself.
/// 3. `playbackState` is set explicitly on every update. This is the one
///    that actually matters: iOS infers the state from
///    `MPNowPlayingInfoPropertyPlaybackRate`, macOS does not, and without it
///    the system keeps routing the media keys to Music.app — which is why so
///    many macOS ports of this look correct and do nothing.
class NowPlayingController: NSObject {
  private let remoteChannel: FlutterMethodChannel
  private var pendingArtworkURL: String?
  private var lastNowPlayingInfo: [String: Any]?

  /// L'ultimo stato passato al widget: si riscrive solo quando cambia,
  /// non a ogni secondo di posizione.
  private var lastWidgetInfo: CrocutaShared.NowPlaying?

  /// L'istanza registrata: il mini player e le scorciatoie globali mandano
  /// i loro comandi a Dart da qui, per la stessa strada dei tasti F7–F9.
  private(set) static var shared: NowPlayingController?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "demus/now_playing",
      binaryMessenger: messenger
    )
    let remote = FlutterMethodChannel(
      name: "demus/remote_commands",
      binaryMessenger: messenger
    )
    let instance = NowPlayingController(
      channel: channel,
      remoteChannel: remote
    )
    shared = instance
    channel.setMethodCallHandler(instance.handle)
    instance.setupRemoteCommands()
    instance.listenToWidget()
  }

  /// I pulsanti del widget arrivano come notifiche di sistema: sul Mac il
  /// comando gira nel widget, che all'app puo' solo mandare un segnale.
  private func listenToWidget() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    for command in CrocutaShared.commands {
      CFNotificationCenterAddObserver(
        center, observer,
        { _, observer, name, _, _ in
          guard let observer, let name else { return }
          let me = Unmanaged<NowPlayingController>.fromOpaque(observer)
            .takeUnretainedValue()
          let full = name.rawValue as String
          guard let command = full.split(separator: ".").last else { return }
          DispatchQueue.main.async { me.send(String(command)) }
        },
        CrocutaShared.notificationName(command) as CFString,
        nil, .deliverImmediately)
    }
  }

  init(channel: FlutterMethodChannel, remoteChannel: FlutterMethodChannel) {
    self.remoteChannel = remoteChannel
    super.init()
  }

  // MARK: - Method channel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      updateNowPlaying(args)
      // Gli stessi dati vanno al mini player: niente canale in piu' da Dart.
      MiniPlayerController.shared.nowPlayingDidUpdate(args)
      result(nil)
    case "clear":
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      MPNowPlayingInfoCenter.default().playbackState = .stopped
      CrocutaShared.clear()
      lastWidgetInfo = nil
      WidgetCenter.shared.reloadAllTimelines()
      lastNowPlayingInfo = nil
      pendingArtworkURL = nil
      MiniPlayerController.shared.nowPlayingDidClear()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Now Playing info

  private func updateNowPlaying(_ args: [String: Any]) {
    let playing = args["playing"] as? Bool == true

    var info: [String: Any] = [:]
    info[MPMediaItemPropertyTitle] = args["title"] as? String ?? ""
    info[MPMediaItemPropertyArtist] = args["artist"] as? String ?? ""
    info[MPMediaItemPropertyAlbumTitle] = "Crocuta"
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
      args["position"] as? Double ?? 0
    info[MPMediaItemPropertyPlaybackDuration] =
      args["duration"] as? Double ?? 0
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

    // Keep the artwork that was already fetched, if any.
    if let artwork = lastNowPlayingInfo?[MPMediaItemPropertyArtwork] {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    lastNowPlayingInfo = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    // macOS will not claim the media keys without this.
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused

    let artworkURL = args["artworkUrl"] as? String ?? ""
    let widgetInfo = CrocutaShared.NowPlaying(
      title: args["title"] as? String ?? "",
      artist: args["artist"] as? String ?? "",
      playing: playing,
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
    _ urlString: String, completion: @escaping (NSImage) -> Void
  ) {
    guard let url = URL(string: urlString) else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data = data, let image = NSImage(data: data) else { return }
      DispatchQueue.main.async { completion(image) }
    }.resume()
  }

  // MARK: - Remote commands (media keys / Control Centre)

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

  func send(_ command: String, _ args: [String: Any] = [:]) {
    remoteChannel.invokeMethod(command, arguments: args)
  }
}
