import AppIntents
import AppKit
import SwiftUI
import WidgetKit

struct TogglePlaybackIntent: AppIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  func perform() async throws -> some IntentResult {
    CrocutaShared.post("toggle")
    return .result()
  }
}

struct NextTrackIntent: AppIntent {
  static let title: LocalizedStringResource = "Next Song"
  func perform() async throws -> some IntentResult {
    CrocutaShared.post("next")
    return .result()
  }
}

struct PreviousTrackIntent: AppIntent {
  static let title: LocalizedStringResource = "Previous Song"
  func perform() async throws -> some IntentResult {
    CrocutaShared.post("previous")
    return .result()
  }
}

/// Il brano in riproduzione, sulla scrivania e nel Centro Notifiche del Mac.
///
/// Gemello di quello dell'iPhone (ios/CrocutaWidget). I dati li scrive
/// l'app nella cartella condivisa a ogni cambio di brano o di play/pausa,
/// e chiede al sistema di ridisegnare. I pulsanti mandano il comando
/// all'app con una notifica di sistema: sul Mac girano nel widget.
struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let info: CrocutaShared.NowPlaying?
  let artwork: NSImage?
}

struct NowPlayingProvider: TimelineProvider {
  func placeholder(in context: Context) -> NowPlayingEntry {
    NowPlayingEntry(
      date: .now,
      info: .init(title: "Song", artist: "Artist", playing: true, artworkURL: ""),
      artwork: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    completion(current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    // .never: aggiorna l'app, quando cambia qualcosa.
    completion(Timeline(entries: [current()], policy: .never))
  }

  private func current() -> NowPlayingEntry {
    NowPlayingEntry(date: .now, info: CrocutaShared.load(), artwork: CrocutaShared.artwork())
  }
}

/// La copertina, o un riquadro scuro con la nota se non c'e'.
struct Cover: View {
  let image: NSImage?
  var radius: CGFloat = 10

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
      } else {
        ZStack {
          Color.white.opacity(0.08)
          Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

struct PlayButton: View {
  let playing: Bool
  var size: CGFloat = 20

  var body: some View {
    Button(intent: TogglePlaybackIntent()) {
      Image(systemName: playing ? "pause.fill" : "play.fill")
        .font(.system(size: size, weight: .semibold))
        .frame(width: size * 1.8, height: size * 1.8)
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.plain)
  }
}

struct SmallView: View {
  let entry: NowPlayingEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top) {
        Cover(image: entry.artwork).frame(width: 64, height: 64)
        Spacer(minLength: 0)
        if let info = entry.info { PlayButton(playing: info.playing, size: 18) }
      }
      Spacer(minLength: 0)
      Text(entry.info?.title ?? "Nothing playing")
        .font(.subheadline.weight(.semibold)).lineLimit(2)
      Text(entry.info?.artist ?? "Crocuta")
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
  }
}

struct MediumView: View {
  let entry: NowPlayingEntry

  var body: some View {
    HStack(spacing: 14) {
      Cover(image: entry.artwork, radius: 12).frame(width: 118, height: 118)
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.info?.title ?? "Nothing playing")
          .font(.headline).lineLimit(2)
        Text(entry.info?.artist ?? "Crocuta")
          .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength: 0)
        if let info = entry.info {
          HStack(spacing: 18) {
            Button(intent: PreviousTrackIntent()) {
              Image(systemName: "backward.fill").font(.title3)
            }
            .buttonStyle(.plain)
            PlayButton(playing: info.playing, size: 22)
            Button(intent: NextTrackIntent()) {
              Image(systemName: "forward.fill").font(.title3)
            }
            .buttonStyle(.plain)
          }
        }
      }
      Spacer(minLength: 0)
    }
  }
}

struct CrocutaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: NowPlayingEntry

  var body: some View {
    switch family {
    case .systemMedium: MediumView(entry: entry)
    default: SmallView(entry: entry)
    }
  }
}

struct CrocutaNowPlayingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CrocutaNowPlaying", provider: NowPlayingProvider()) { entry in
      CrocutaWidgetView(entry: entry)
        .containerBackground(for: .widget) {
          // La copertina sfocata dietro, come il player: il widget ha il
          // colore del brano.
          ZStack {
            Color.black
            if let art = entry.artwork {
              Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                .blur(radius: 30).opacity(0.55)
            }
          }
        }
        .foregroundStyle(.white)
    }
    .configurationDisplayName("Now Playing")
    .description("The song playing in Crocuta, with play and skip.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct CrocutaWidgetBundle: WidgetBundle {
  var body: some Widget {
    CrocutaNowPlayingWidget()
  }
}
