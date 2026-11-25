import AppIntents
import SwiftUI
import WidgetKit

/// Il brano in riproduzione, sulla schermata Home e su quella di blocco.
///
/// I dati li scrive l'app nel contenitore condiviso a ogni cambio di brano
/// o di play/pausa, e chiede al sistema di ridisegnare: il widget non
/// aggiorna nulla da se'. I pulsanti sono comandi di riproduzione, che il
/// sistema esegue nell'app.
struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let info: CrocutaShared.NowPlaying?
  let artwork: UIImage?
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
  let image: UIImage?
  var radius: CGFloat = 10

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
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
  /// Falso in CarPlay e in StandBy: li' il sistema toglie lo sfondo, e con
  /// lui la copertina sfocata. Allora la copertina diventa il widget.
  @Environment(\.showsWidgetContainerBackground) private var showsBackground

  var body: some View {
    if showsBackground { standard } else { bare }
  }

  /// In auto: la copertina grande, il titolo sopra, il play in un angolo,
  /// da prendere al volo.
  private var bare: some View {
    ZStack(alignment: .bottomLeading) {
      Cover(image: entry.artwork, radius: 18)
      LinearGradient(
        colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom
      )
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 1) {
          Text(entry.info?.title ?? "Nothing playing")
            .font(.subheadline.weight(.semibold)).lineLimit(1)
          Text(entry.info?.artist ?? "Crocuta")
            .font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        Spacer(minLength: 4)
        if let info = entry.info { PlayButton(playing: info.playing, size: 18) }
      }
      .padding(10)
    }
  }

  private var standard: some View {
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

/// Sulla schermata di blocco: una riga, come i widget di sistema.
struct RectangularView: View {
  let entry: NowPlayingEntry

  var body: some View {
    HStack(spacing: 8) {
      if let info = entry.info {
        Image(systemName: info.playing ? "waveform" : "pause.fill")
          .font(.caption)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.info?.title ?? "Nothing playing")
          .font(.headline).lineLimit(1)
        Text(entry.info?.artist ?? "Crocuta")
          .font(.caption).lineLimit(1)
      }
    }
  }
}

struct CircularView: View {
  let entry: NowPlayingEntry

  var body: some View {
    ZStack {
      AccessoryWidgetBackground()
      PlayButton(playing: entry.info?.playing ?? false, size: 18)
    }
  }
}

struct CrocutaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: NowPlayingEntry

  var body: some View {
    switch family {
    case .systemMedium: MediumView(entry: entry)
    case .accessoryRectangular: RectangularView(entry: entry)
    case .accessoryCircular: CircularView(entry: entry)
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
              Image(uiImage: art).resizable().aspectRatio(contentMode: .fill)
                .blur(radius: 30).opacity(0.55)
            }
          }
        }
        .foregroundStyle(.white)
    }
    .configurationDisplayName("Now Playing")
    .description("The song playing in Crocuta, with play and skip.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular,
    ])
  }
}

// MARK: - Play

/// Il widget "Play": un tocco e parte quello che hai scelto — i preferiti,
/// una playlist intelligente, una tua playlist, o la ripresa.
///
/// Pensato per CarPlay, dove da iOS 26 compaiono i widget piccoli
/// dell'iPhone: un'app CarPlay vera richiede un permesso che Apple concede
/// solo agli account a pagamento, e cosi' la schermata dei widget in auto
/// diventa la plancia della musica. Un widget per ogni cosa che vuoi avere
/// a portata di dito.
struct PlayEntry: TimelineEntry {
  let date: Date
  let target: PlayTarget
}

struct PlayProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> PlayEntry {
    PlayEntry(date: .now, target: PlayTarget.builtIn[0])
  }

  func snapshot(for configuration: PlayTargetConfig, in context: Context) async -> PlayEntry {
    PlayEntry(date: .now, target: configuration.target ?? PlayTarget.builtIn[0])
  }

  func timeline(for configuration: PlayTargetConfig, in context: Context) async -> Timeline<PlayEntry> {
    Timeline(
      entries: [PlayEntry(date: .now, target: configuration.target ?? PlayTarget.builtIn[0])],
      policy: .never)
  }
}

extension PlayTarget {
  /// I colori delle playlist intelligenti nell'app; il viola di Crocuta
  /// per le tue playlist.
  var colors: [Color] {
    switch id {
    case "favorites": return [Color(red: 0.93, green: 0.28, blue: 0.6), Color(red: 0.55, green: 0.36, blue: 0.96)]
    case "smart:onRepeat": return [Color(red: 1, green: 0.37, blue: 0.38), Color(red: 1, green: 0.6, blue: 0.4)]
    case "smart:recentlyLiked": return [Color(red: 0.93, green: 0.28, blue: 0.6), Color(red: 0.55, green: 0.36, blue: 0.96)]
    case "smart:lateNight": return [Color(red: 0.12, green: 0.23, blue: 0.54), Color(red: 0.49, green: 0.23, blue: 0.93)]
    case "smart:forgotten": return [Color(red: 0.05, green: 0.65, blue: 0.64), Color(red: 0.13, green: 0.77, blue: 0.37)]
    case "resume": return [Color(white: 0.25), Color(white: 0.12)]
    default: return [Color(red: 0.48, green: 0.36, blue: 1), Color(red: 0.29, green: 0.2, blue: 0.8)]
    }
  }
}

struct PlayView: View {
  let entry: PlayEntry
  @Environment(\.showsWidgetContainerBackground) private var showsBackground

  var body: some View {
    // Tutto il widget e' il pulsante: in auto non si mira.
    Button(intent: PlayTargetIntent(target: entry.target)) {
      ZStack(alignment: .topLeading) {
        // Senza sfondo di sistema (CarPlay, StandBy) il colore lo porta il
        // widget stesso.
        if !showsBackground {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(
              colors: entry.target.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        VStack(alignment: .leading) {
          Image(systemName: entry.target.symbol).font(.title2.weight(.semibold))
          Spacer(minLength: 0)
          Text(entry.target.name).font(.headline).lineLimit(2)
          Label("Play", systemImage: "play.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(showsBackground ? 0 : 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .buttonStyle(.plain)
  }
}

struct CrocutaPlayWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "CrocutaPlay", intent: PlayTargetConfig.self, provider: PlayProvider()) {
      entry in
      PlayView(entry: entry)
        .containerBackground(for: .widget) {
          LinearGradient(
            colors: entry.target.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .foregroundStyle(.white)
    }
    .configurationDisplayName("Play")
    .description("Liked Songs, a smart playlist or one of yours, with one tap.")
    .supportedFamilies([.systemSmall])
  }
}

@main
struct CrocutaWidgetBundle: WidgetBundle {
  var body: some Widget {
    CrocutaNowPlayingWidget()
    CrocutaPlayWidget()
  }
}
