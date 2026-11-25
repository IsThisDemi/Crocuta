import Cocoa
import SwiftUI

/// Misure del mini player. La finestra e' quadrata piu' una striscia fissa
/// sotto la copertina, e `MiniPlayerController` ne ricava l'altezza dalla
/// larghezza: per questo stanno qui, condivise fra finestra e vista.
enum MiniPlayerLayout {
  /// Il margine fra il bordo della finestra e la macchia: lascia posto
  /// all'ombra, che segue la forma.
  static let inset: CGFloat = 0.04
  static let cornerRadius: CGFloat = 26

  static let defaultWidth: CGFloat = 248
  static let minWidth: CGFloat = 170
  static let maxWidth: CGFloat = 440

  /// La finestra e' quadrata: la macchia ci sta dentro intera.
  static func height(forWidth width: CGFloat) -> CGFloat { width }
}

enum MiniPlayerAction {
  case togglePlay, next, previous, close, expand
  case seek(Double)
}

/// Lo stato che la vista mostra, scritto da `MiniPlayerController`.
final class MiniPlayerModel: ObservableObject {
  @Published private(set) var title = ""
  @Published private(set) var artist = ""
  @Published private(set) var playing = false
  @Published private(set) var duration: Double = 0
  @Published private(set) var hasTrack = false
  @Published private(set) var artwork: NSImage?
  /// Cambia a ogni copertina: fa da identita' per la dissolvenza.
  @Published private(set) var artworkID = 0
  /// Il colore del brano e un secondo colore della copertina (Macchia).
  @Published private(set) var accent = Color(nsColor: MacchiaColors.fallback)
  @Published private(set) var second: Color?
  /// L'indirizzo della copertina: il seme della macchia, lo stesso che usa
  /// l'app per lo stesso brano.
  @Published private(set) var spotSeed = ""
  @Published var hovering = false
  /// Fuori schermo il TimelineView della barra si ferma.
  @Published var visible = false

  // La posizione arriva ogni ~2 s: la si ancora a un istante e in mezzo la
  // si fa avanzare col tempo, come fa il Centro di Controllo con
  // elapsedPlaybackTime + rate.
  @Published private(set) var anchorPosition: Double = 0
  @Published private(set) var anchorDate = Date()

  var perform: (MiniPlayerAction) -> Void = { _ in }

  func apply(
    title: String, artist: String, playing: Bool, position: Double,
    duration: Double
  ) {
    if self.title != title { self.title = title }
    if self.artist != artist { self.artist = artist }
    if self.playing != playing { self.playing = playing }
    if self.duration != duration { self.duration = duration }
    if !hasTrack { hasTrack = true }
    anchorPosition = position
    anchorDate = Date()
  }

  func clear() {
    title = ""
    artist = ""
    playing = false
    duration = 0
    hasTrack = false
    anchorPosition = 0
    setArtwork(nil)
  }

  func setArtwork(_ image: NSImage?) {
    guard image !== artwork else { return }
    artwork = image
    artworkID += 1
  }

  func setPalette(seed: String, accent: NSColor?, second: NSColor?) {
    spotSeed = seed
    self.accent = Color(nsColor: accent ?? MacchiaColors.fallback)
    self.second = second.map { Color(nsColor: $0) }
  }

  func position(at date: Date) -> Double {
    guard playing else { return anchorPosition }
    let p = anchorPosition + date.timeIntervalSince(anchorDate)
    return duration > 0 ? min(p, duration) : p
  }

  func fraction(at date: Date) -> Double {
    duration > 0 ? min(max(position(at: date) / duration, 0), 1) : 0
  }

  /// La barra si sposta subito: l'aggiornamento di Dart che lo conferma
  /// arriva fino a 2 s dopo, e nel frattempo tornerebbe indietro.
  func seek(toFraction fraction: Double) {
    guard duration > 0 else { return }
    let seconds = fraction * duration
    anchorPosition = seconds
    anchorDate = Date()
    perform(.seek(seconds))
  }
}

/// Il mini player e' una macchia: la finestra non ha un rettangolo, ha la
/// forma della copertina del brano (la stessa macchia che ha nell'app), e
/// galleggia sulla scrivania. Titolo e artista stanno centrati in basso, su
/// un velo scuro dentro la macchia; col mouse sopra compaiono i comandi.
struct MiniPlayerView: View {
  @ObservedObject var model: MiniPlayerModel
  let menu: () -> NSMenu?

  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// I secondi passati col mini player in vista: nascosto si ferma, e la
  /// macchia riparte dalla posa in cui era invece di saltare.
  private func liveTime(at date: Date) -> Double {
    MiniPlayerClock.shared.time(at: date, running: model.visible && !reduceMotion)
  }

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      let inset = side * MiniPlayerLayout.inset
      let spot = side - inset * 2
      // La macchia respira sempre, come tutte quelle dell'app: un
      // fotogramma ogni 1/30 di secondo basta a un movimento cosi' lento, e
      // nascosta o col movimento ridotto l'orologio si ferma dov'e'.
      TimelineView(
        .animation(minimumInterval: 1.0 / 30, paused: !model.visible || reduceMotion)
      ) { context in
      let shape = SpotShape(
        seed: model.spotSeed.isEmpty ? "crocuta" : model.spotSeed,
        time: liveTime(at: context.date))
      ZStack {
        // Sotto a tutto, larga quanto la finestra: dove non c'e' un comando
        // si trascina. Dentro la macchia ritagliata la vista AppKit non
        // riceveva i clic, e la finestra non si spostava.
        WindowDragHandle(menu: menu)
          .frame(width: side, height: side)
          .position(x: side / 2, y: side / 2)

        ZStack {
          artworkImage
            .id(model.artworkID)
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            .allowsHitTesting(false)

          // Il velo per il testo: dal centro in giu', sempre piu' scuro.
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0.38),
              .init(color: .black.opacity(0.55), location: 0.7),
              .init(color: .black.opacity(0.82), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
          )
          .allowsHitTesting(false)

          if model.hovering {
            Color.black.opacity(0.3).allowsHitTesting(false).transition(.opacity)
          }

          info(width: spot)

          if model.hovering {
            controls(size: spot).transition(.opacity)
            corners.transition(.opacity)
          }
        }
        .frame(width: spot, height: spot)
        .contentShape(shape)
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.7).allowsHitTesting(false))
        .position(x: side / 2, y: side / 2)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .animation(.easeOut(duration: 0.4), value: model.spotSeed)
      }
    }
    .animation(.easeOut(duration: 0.18), value: model.hovering)
    .environment(\.colorScheme, .dark)
  }

  @ViewBuilder private var artworkImage: some View {
    if let image = model.artwork {
      Color.clear.overlay(
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fill)
      )
    } else {
      ZStack {
        model.accent.opacity(0.35)
        Image(systemName: "music.note")
          .font(.system(size: 48, weight: .regular))
          .foregroundStyle(.white.opacity(0.4))
      }
    }
  }

  /// Indietro, play, avanti: al centro della macchia.
  private func controls(size: CGFloat) -> some View {
    HStack(spacing: size * 0.06) {
      TransportButton(symbol: "backward.fill", size: max(16, size * 0.085)) {
        model.perform(.previous)
      }
      SpotPlayButton(playing: model.playing, accent: model.accent, size: size * 0.26) {
        model.perform(.togglePlay)
      }
      TransportButton(symbol: "forward.fill", size: max(16, size * 0.085)) {
        model.perform(.next)
      }
    }
    .offset(y: -size * 0.06)
  }

  /// Chiudi e torna all'app grande: in alto al centro, dove la macchia e'
  /// piena (gli angoli della finestra sono vuoti).
  private var corners: some View {
    VStack {
      HStack(spacing: 8) {
        CornerButton(symbol: "xmark", help: "Close Mini Player") {
          model.perform(.close)
        }
        CornerButton(
          symbol: "arrow.up.left.and.arrow.down.right",
          help: "Show Main Window"
        ) {
          model.perform(.expand)
        }
      }
      .padding(.top, 18)
      Spacer()
    }
  }

  /// Titolo e artista centrati in basso, e sotto un filo di avanzamento
  /// corto: la macchia in basso si stringe, un filo largo uscirebbe.
  private func info(width: CGFloat) -> some View {
    TimelineView(
      .animation(minimumInterval: 0.5, paused: !model.playing || !model.visible)
    ) { context in
      let now = context.date
      VStack(spacing: 2) {
        Spacer()
        Text(model.hasTrack ? model.title : "Not Playing")
          .font(MacchiaFont.font(size: max(15, width * 0.085), weight: 700, width: 75))
          .foregroundStyle(.white)
          .lineLimit(1)
          .allowsHitTesting(false)
        Group {
          if model.hovering && model.duration > 0 {
            Text(
              Self.format(model.position(at: now)) + "  /  "
                + Self.format(model.duration)
            )
            .monospacedDigit()
          } else {
            Text(model.artist).lineLimit(1)
          }
        }
        .font(MacchiaFont.font(size: max(11.5, width * 0.055), weight: 600, width: 90))
        .foregroundStyle(model.accent)
        .allowsHitTesting(false)
        ProgressBar(
          accent: model.accent,
          fraction: model.fraction(at: now),
          thick: model.hovering,
          enabled: model.duration > 0,
          onSeek: model.seek(toFraction:)
        )
        .frame(width: width * 0.46)
        .padding(.top, 4)
      }
      .padding(.horizontal, width * 0.16)
      .padding(.bottom, width * 0.1)
    }
  }

  private static func format(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}

/// Barra sottile, piu' spessa col mouse; trascinandola si cerca nel brano.
private struct ProgressBar: View {
  let accent: Color
  let fraction: Double
  let thick: Bool
  let enabled: Bool
  let onSeek: (Double) -> Void

  @State private var dragFraction: Double?

  var body: some View {
    GeometryReader { geo in
      let width = max(geo.size.width, 1)
      let shown = dragFraction ?? fraction
      let height: CGFloat = (thick || dragFraction != nil) ? 6 : 3
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.16))
        Capsule()
          .fill(accent)
          .frame(width: max(height, width * shown))
      }
      .frame(height: height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard enabled else { return }
            dragFraction = min(max(value.location.x / width, 0), 1)
          }
          .onEnded { value in
            guard enabled else { return }
            onSeek(min(max(value.location.x / width, 0), 1))
            dragFraction = nil
          }
      )
      .animation(.easeOut(duration: 0.15), value: height)
    }
    .frame(height: 14)
  }
}

/// Indietro / play / avanti sopra la copertina: simboli pieni, bianchi,
/// senza fondo, come in Apple Music.
private struct TransportButton: View {
  let symbol: String
  let size: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .frame(width: size + 20, height: size + 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
  }
}

/// I pulsantini negli angoli: chiudi e torna all'app grande. Fanno le veci
/// dei semafori, che in una finestra senza barra del titolo non ci sono.
private struct CornerButton: View {
  let symbol: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 22, height: 22)
        .background(Circle().fill(.black.opacity(0.35)))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .help(help)
  }
}

private struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.86 : 1)
      .opacity(configuration.isPressed ? 0.7 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// Una vista AppKit vera sotto al contenuto, che sposta la finestra quando
/// la si trascina e apre il menu col clic destro. Serve una vista apposta
/// perche' il pannello non ha barra del titolo, e il trascinamento "da
/// sfondo" di AppKit prenderebbe anche la barra di avanzamento.
private struct WindowDragHandle: NSViewRepresentable {
  let menu: () -> NSMenu?

  func makeNSView(context: Context) -> DragView {
    let view = DragView()
    view.menuProvider = menu
    return view
  }

  func updateNSView(_ view: DragView, context: Context) {
    view.menuProvider = menu
  }

  final class DragView: NSView {
    var menuProvider: (() -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
  }
}


/// Lo sfondo del mini player in Macchia: nero, con la luce del colore del
/// brano che sale da in alto a sinistra e un secondo colore della copertina
/// in basso a destra. E' `AccentGlow` dell'app.
struct MiniPlayerBackdrop: View {
  let accent: Color
  let second: Color?

  var body: some View {
    ZStack {
      Color.black
      RadialGradient(
        colors: [accent.opacity(0.32), accent.opacity(0.08), .clear],
        center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 260)
      RadialGradient(
        colors: [(second ?? accent).opacity(0.18), .clear],
        center: UnitPoint(x: 1, y: 1), startRadius: 0, endRadius: 200)
    }
    .animation(.easeInOut(duration: 0.7), value: accent)
    .allowsHitTesting(false)
    .ignoresSafeArea()
  }
}

/// Il tasto play: una macchia piena del colore del brano col simbolo nero,
/// come in ogni pagina dell'app. Sempre la stessa forma.
private struct SpotPlayButton: View {
  let playing: Bool
  let accent: Color
  var size: CGFloat = 56
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        SpotShape(seed: "crocuta-play", wobble: 0.9).fill(accent)
        Image(systemName: playing ? "pause.fill" : "play.fill")
          .font(.system(size: size * 0.4, weight: .bold))
          .contentTransition(.symbolEffect(.replace))
          .foregroundStyle(.black)
      }
      .frame(width: size, height: size)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
  }
}

// MARK: - Macchia

/// Il generatore della macchia: lo stesso mulberry32 di `SpotRandom` in
/// lib/design/spot.dart, con lo stesso seme (FNV-1a dell'indirizzo della
/// copertina). Solo cosi' la copertina ha la stessa forma nel mini player e
/// nell'app.
struct SpotRandom {
  private var a: UInt32

  init(seed: UInt32) { a = seed }

  static func seed(_ s: String) -> UInt32 {
    var h: UInt32 = 0x811c_9dc5
    for c in s.utf16 {
      h ^= UInt32(c)
      h = h &* 0x0100_0193
    }
    return h
  }

  mutating func nextDouble() -> Double {
    a = a &+ 0x6D2B_79F5
    var t = a
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4_294_967_296.0
  }

  mutating func nextInt(_ max: Int) -> Int { Int(nextDouble() * Double(max)) }
}

/// La macchia: sei-otto punti attorno al centro, uniti da una curva chiusa
/// e stirati fino a toccare i lati. E' `spotPath` di lib/design/spot.dart.
struct SpotShape: Shape {
  let seed: String
  var wobble: Double = 1
  /// L'istante, in secondi, per una macchia viva: ogni punto ondeggia col
  /// suo ritmo, come `spotPath(time:)` in lib/design/spot.dart. Senza, la
  /// forma e' ferma.
  var time: Double? = nil

  func path(in rect: CGRect) -> Path {
    var rnd = SpotRandom(seed: SpotRandom.seed(seed))
    let n = 6 + rnd.nextInt(3)
    let step = 2 * Double.pi / Double(n)
    let start = rnd.nextDouble() * step
    let w = min(max(wobble, 0), 1)
    var angles: [Double] = []
    var radii: [Double] = []
    for i in 0..<n {
      angles.append(start + Double(i) * step + (rnd.nextDouble() - 0.5) * step * 0.45 * w)
      radii.append(1 - rnd.nextDouble() * 0.24 * w)
    }
    if let time {
      let amp = max(w, 0.5)
      for i in 0..<n {
        let phase = rnd.nextDouble() * 2 * Double.pi
        let freq = 0.55 + rnd.nextDouble() * 0.5
        func wave(_ f: Double, _ ph: Double) -> Double { sin(time * f + ph) - sin(ph) }
        radii[i] *= 1 + 0.065 * amp * wave(freq, phase)
        angles[i] += 0.09 * amp * wave(freq * 0.73, phase * 1.7)
      }
    }
    let pts = (0..<n).map { CGPoint(x: cos(angles[$0]) * radii[$0], y: sin(angles[$0]) * radii[$0]) }
    var path = Path()
    path.move(to: pts[0])
    for i in 0..<n {
      let p0 = pts[(i - 1 + n) % n]
      let p1 = pts[i]
      let p2 = pts[(i + 1) % n]
      let p3 = pts[(i + 2) % n]
      let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
      let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
      path.addCurve(to: p2, control1: c1, control2: c2)
    }
    path.closeSubpath()
    let b = path.boundingRect
    guard b.width > 0, b.height > 0 else { return Path(ellipseIn: rect) }
    let t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
      .scaledBy(x: rect.width / b.width, y: rect.height / b.height)
      .translatedBy(x: -b.minX, y: -b.minY)
    return path.applying(t)
  }
}

/// Outfit, il carattere dei titoli dell'app, preso dagli asset di Flutter
/// dentro il bundle: cosi' il mini player non ne porta una copia sua.
enum MacchiaFont {
  private static let registered: Bool = {
    let url = Bundle.main.bundleURL
      .appendingPathComponent(
        "Contents/Frameworks/App.framework/Resources/flutter_assets/assets/fonts/Outfit-Variable.ttf"
      )
    return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }()

  static func font(size: CGFloat, weight: CGFloat, width: CGFloat) -> Font {
    _ = registered
    let axes: [NSNumber: NSNumber] = [
      NSNumber(value: 0x7767_6874): NSNumber(value: Double(weight)),  // wght
    ]
    let desc = CTFontDescriptorCreateWithAttributes(
      [
        kCTFontFamilyNameAttribute: "Outfit",
        kCTFontVariationAttribute: axes,
      ] as CFDictionary)
    let ct = CTFontCreateWithFontDescriptor(desc, size, nil)
    return Font(ct)
  }
}

/// I colori del brano per il mini player: lo stesso conto di
/// `toneMapAccent` (lib/design/accent.dart) sul colore piu' vivo della
/// copertina, e un secondo colore diverso per la luce in basso.
enum MacchiaColors {
  static let fallback = NSColor(srgbRed: 0.62, green: 0.55, blue: 1.0, alpha: 1)

  static func palette(of image: CGImage) -> (accent: NSColor, second: NSColor?) {
    let side = 32
    var px = [UInt8](repeating: 0, count: side * side * 4)
    guard
      let ctx = CGContext(
        data: &px, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return (fallback, nil) }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

    var weight: [Int: Double] = [:]
    var sum: [Int: (Double, Double, Double, Double)] = [:]
    for i in stride(from: 0, to: px.count, by: 4) {
      let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
      let mx = max(r, g, b) / 255, mn = min(r, g, b) / 255
      let sat = mx == 0 ? 0 : (mx - mn) / mx
      let light = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      guard light > 0.15, light < 0.95, sat > 0.25 else { continue }
      let key = (Int(r) >> 4) << 8 | (Int(g) >> 4) << 4 | (Int(b) >> 4)
      weight[key, default: 0] += sat * sat
      let s = sum[key] ?? (0, 0, 0, 0)
      sum[key] = (s.0 + r, s.1 + g, s.2 + b, s.3 + 1)
    }
    let ranked = weight.sorted { $0.value > $1.value }.compactMap { e -> NSColor? in
      guard let s = sum[e.key], s.3 > 0 else { return nil }
      return NSColor(
        srgbRed: s.0 / s.3 / 255, green: s.1 / s.3 / 255, blue: s.2 / s.3 / 255, alpha: 1)
    }
    guard let vivid = ranked.first else { return (neutral, nil) }
    let second = ranked.dropFirst().first { c in
      let dh = abs(c.hueComponent - vivid.hueComponent) * 360
      return min(dh, 360 - dh) > 28
    }
    return (toneMap(vivid), second.map(toneMap))
  }

  static let neutral = NSColor(srgbRed: 0xD5 / 255.0, green: 0xD5 / 255.0, blue: 0xDE / 255.0, alpha: 1)

  /// Satura e schiarisce finche' si legge sul nero, come toneMapAccent.
  static func toneMap(_ c: NSColor) -> NSColor {
    guard let rgb = c.usingColorSpace(.sRGB) else { return neutral }
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    // Da HSB a HSL per fare lo stesso conto dell'app.
    var l = b * (1 - s / 2)
    var sl = (l == 0 || l == 1) ? 0 : (b - l) / min(l, 1 - l)
    if sl < 0.15 { return neutral }
    sl = min(max(sl, 0.35), 0.85)
    l = min(max(l, 0.55), 0.72)
    func color(_ l: CGFloat) -> NSColor {
      let bb = l + sl * min(l, 1 - l)
      let ss = bb == 0 ? 0 : 2 * (1 - l / bb)
      return NSColor(hue: h, saturation: ss, brightness: bb, alpha: 1)
    }
    var out = color(l)
    while contrast(out) < 4.5 && l < 0.92 {
      l = min(l + 0.03, 0.92)
      out = color(l)
    }
    return contrast(out) >= 4.5 ? out : neutral
  }

  private static func contrast(_ c: NSColor) -> CGFloat {
    func lum(_ c: NSColor) -> CGFloat {
      let s = c.usingColorSpace(.sRGB) ?? c
      func ch(_ v: CGFloat) -> CGFloat {
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * ch(s.redComponent) + 0.7152 * ch(s.greenComponent)
        + 0.0722 * ch(s.blueComponent)
    }
    let a = lum(c), b: CGFloat = lum(NSColor(white: 0.043, alpha: 1))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}


/// L'orologio delle macchie vive del mini player: avanza solo mentre si
/// suona, e riparte da dove si era fermato.
final class MiniPlayerClock {
  static let shared = MiniPlayerClock()
  private var accumulated: Double = 0
  private var runningSince: Date?

  func time(at date: Date, running: Bool) -> Double {
    if running {
      if runningSince == nil { runningSince = date }
      return accumulated + date.timeIntervalSince(runningSince!)
    }
    if let since = runningSince {
      accumulated += date.timeIntervalSince(since)
      runningSince = nil
    }
    return accumulated
  }
}
