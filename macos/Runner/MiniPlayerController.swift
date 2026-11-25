import Cocoa
import FlutterMacOS
import SwiftUI

/// Il mini player del Mac, come Finestra ▸ Mini Player di Apple Music.
///
/// E' nativo, non una seconda finestra Flutter: un secondo motore Flutter
/// costa decine di MB e uno stato da tenere in sincronia, mentre tutto quello
/// che serve qui (titolo, artista, copertina, posizione, play) arriva gia'
/// dal canale `demus/now_playing` che alimenta il Centro di Controllo.
/// `NowPlayingController` lo gira anche a noi, e i comandi tornano a Dart
/// dalla stessa strada dei tasti F7–F9 (`demus/remote_commands`): il player
/// non sa nemmeno che il mini player esiste.
///
/// La finestra e' un `NSPanel` *non attivante*, ed e' una scelta voluta: il
/// mini player e' un telecomando che si usa mentre si lavora in un'altra
/// app, e un clic su "avanti" non deve portare Crocuta in primo piano ne'
/// rubare la tastiera al documento su cui si sta scrivendo. Un pannello
/// normale attiverebbe l'app a ogni clic. Il prezzo e' che non riceve tasti
/// finche' non diventa chiave, ma qui non c'e' niente da scrivere.
final class MiniPlayerController: NSObject, NSWindowDelegate, NSMenuItemValidation {
  static let shared = MiniPlayerController()

  private enum Keys {
    static let alwaysOnTop = "miniPlayer.alwaysOnTop"
    static let hidesMainWindow = "miniPlayer.hidesMainWindow"
  }

  /// Nome con cui AppKit salva posizione e misura nelle preferenze.
  private static let frameName = "CrocutaMiniPlayer"

  let model = MiniPlayerModel()

  private var panel: MiniPlayerPanel?
  private var applyTint: ((NSColor?) -> Void)?

  /// Vero solo se la finestra principale l'abbiamo nascosta noi: chiudendo
  /// il mini player si rimette a posto quello che abbiamo tolto, non si
  /// tira fuori una finestra che l'utente aveva messo nel Dock.
  private var hidMainWindow = false

  /// Vero mentre il mini player e' l'unica finestra di Crocuta perche' ha
  /// nascosto lui quella grande. AppKit non conta i pannelli come finestre:
  /// dopo l'orderOut della finestra grande concludeva "chiusa l'ultima
  /// finestra" e, con applicationShouldTerminateAfterLastWindowClosed a
  /// true, chiudeva l'app proprio mentre il mini player si apriva.
  var holdsAppOpen: Bool { hidMainWindow && isVisible }

  private var artworkKey = ""
  private var artworkExpiry: DispatchWorkItem?
  private var keyMonitor: Any?

  var isVisible: Bool { panel?.isVisible == true }

  /// Sopra tutte le finestre, anche delle altre app. Di serie si', come in
  /// Apple Music: un mini player che sparisce dietro al browser non serve.
  var alwaysOnTop: Bool {
    get { UserDefaults.standard.object(forKey: Keys.alwaysOnTop) as? Bool ?? true }
    set {
      UserDefaults.standard.set(newValue, forKey: Keys.alwaysOnTop)
      applyLevel()
    }
  }

  /// Aprire il mini player nasconde la finestra grande, e chiuderlo la
  /// riporta: e' lo scambio che fa Apple Music. Si puo' spegnere per
  /// tenerle entrambe.
  var hidesMainWindow: Bool {
    get {
      UserDefaults.standard.object(forKey: Keys.hidesMainWindow) as? Bool ?? true
    }
    set { UserDefaults.standard.set(newValue, forKey: Keys.hidesMainWindow) }
  }

  // MARK: - Registrazione

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "crocuta/mini_player",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "toggle":
        shared.toggle()
        result(nil)
      case "show":
        shared.show()
        result(nil)
      case "hide":
        shared.hide()
        result(nil)
      case "isVisible":
        result(shared.isVisible)
      case "music":
        shared.model.music = Self.musicTrack(call.arguments)
        result(nil)
      case "musicIntensity":
        shared.model.musicIntensity = (call.arguments as? Double) ?? 1
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    shared.model.perform = { action in shared.perform(action) }
    shared.installKeyMonitor()
    // Il menu del xib e' gia' caricato, ma l'app non ha ancora finito di
    // partire: al giro dopo NSApp.windowsMenu e' di sicuro al suo posto.
    DispatchQueue.main.async { shared.installMenuItems() }
  }

  /// La musica del brano da `MiniPlayerWindow.setMusic`: tre Float32List
  /// e la loro frequenza. Nil (brano cambiato, musica non ancora pronta)
  /// e la macchia respira soltanto.
  private static func musicTrack(_ args: Any?) -> SpotMusicTrack? {
    guard let a = args as? [String: Any], let rate = a["rate"] as? Double else { return nil }
    func floats(_ key: String) -> [Float]? {
      guard let d = a[key] as? FlutterStandardTypedData else { return nil }
      return d.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    guard let pulse = floats("pulse"), let snap = floats("snap"), let energy = floats("energy")
    else { return nil }
    return SpotMusicTrack(rate: rate, pulse: pulse, snap: snap, energy: energy)
  }

  // MARK: - Dati da Now Playing

  /// Chiamato da `NowPlayingController` a ogni `update` di Dart. Gli
  /// aggiornamenti arrivano ogni ~2 s (piu' i cambi di brano e di stato):
  /// la barra in mezzo la fa scorrere la vista per conto suo.
  func nowPlayingDidUpdate(_ args: [String: Any]) {
    model.apply(
      title: args["title"] as? String ?? "",
      artist: args["artist"] as? String ?? "",
      playing: args["playing"] as? Bool == true,
      position: args["position"] as? Double ?? 0,
      duration: args["duration"] as? Double ?? 0
    )
    loadArtwork(args["artworkUrl"] as? String ?? "")
  }

  func nowPlayingDidClear() {
    model.clear()
    artworkKey = ""
    artworkExpiry?.cancel()
    applyTint?(nil)
  }

  // MARK: - Mostrare e nascondere

  func toggle() {
    isVisible ? hide() : show()
  }

  func show() {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    applyLevel()
    model.visible = true
    // Se compare gia' sotto il puntatore non arriva nessun mouseEntered.
    model.hovering = panel.frame.contains(NSEvent.mouseLocation)
    // orderFrontRegardless: dalla scorciatoia globale l'app non e' attiva,
    // e orderFront da solo non porterebbe la finestra sopra le altre app.
    panel.orderFrontRegardless()
    panel.invalidateShadow()

    if hidesMainWindow, let main = mainWindow, main.isVisible,
      !main.isMiniaturized
    {
      main.orderOut(nil)
      hidMainWindow = true
    }
  }

  /// Chiude il mini player. Se aveva nascosto la finestra grande la
  /// riporta, salvo `restoreMain: false` (chi chiama la mostra da se').
  func hide(restoreMain: Bool = true) {
    guard let panel, panel.isVisible else { return }
    panel.orderOut(nil)
    model.visible = false
    model.hovering = false
    let restore = hidMainWindow && restoreMain
    hidMainWindow = false
    if restore { showMainWindow() }
  }

  /// Torna all'app grande, come il pulsante con le frecce di Apple Music.
  func expandToMainWindow() {
    hide(restoreMain: false)
    showMainWindow()
  }

  /// Clic sull'icona nel Dock mentre la finestra grande e' nascosta da noi:
  /// la si riporta (il mini player resta). Senza, il clic non farebbe
  /// niente, perche' una finestra tolta con orderOut per AppKit non e'
  /// ridotta a icona ne' chiusa: semplicemente non c'e'.
  func handleReopen() -> Bool {
    guard hidMainWindow, let main = mainWindow, !main.isVisible else {
      return true
    }
    hidMainWindow = false
    showMainWindow()
    return false
  }

  private var mainWindow: NSWindow? {
    NSApp.windows.first { $0 is MainFlutterWindow }
  }

  private func showMainWindow() {
    guard let main = mainWindow else { return }
    if main.isMiniaturized { main.deminiaturize(nil) }
    main.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }

  private func applyLevel() {
    guard let panel else { return }
    let onTop = alwaysOnTop
    panel.level = onTop ? .floating : .normal
    // Sopra tutto vuol dire anche su ogni scrivania e sopra le app a tutto
    // schermo; sotto, il mini player e' una finestra come le altre.
    panel.collectionBehavior =
      onTop
      ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      : [.managed, .ignoresCycle]
  }

  // MARK: - Azioni dalla vista

  private func perform(_ action: MiniPlayerAction) {
    switch action {
    case .togglePlay: send("toggle")
    case .next: send("next")
    case .previous: send("previous")
    case .seek(let seconds): send("seek", ["position": seconds])
    case .close: hide()
    case .expand: expandToMainWindow()
    }
  }

  private func send(_ command: String, _ args: [String: Any] = [:]) {
    NowPlayingController.shared?.send(command, args)
  }

  // MARK: - Finestra

  private func makePanel() -> MiniPlayerPanel {
    let width = MiniPlayerLayout.defaultWidth
    let panel = MiniPlayerPanel(
      contentRect: NSRect(
        x: 0, y: 0, width: width,
        height: MiniPlayerLayout.height(forWidth: width)),
      // Senza barra del titolo: niente semafori, solo vetro. .resizable
      // da' comunque i bordi per ridimensionare, con le proporzioni
      // tenute da windowWillResize.
      styleMask: [.borderless, .nonactivatingPanel, .resizable],
      backing: .buffered,
      defer: false
    )
    // I pannelli di serie spariscono quando l'app passa in secondo piano:
    // proprio il momento in cui un mini player serve.
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // Detto esplicitamente, anche se e' il valore di partenza: una finestra
    // trasparente lascia passare i clic dove il sistema non vede pixel suoi,
    // e con la macchia disegnata da SwiftUI su un fondo vuoto li lasciava
    // passare tutti — trascinando il mini player si spostavano le finestre
    // sotto. Impostato a mano, la finestra riceve il mouse ovunque.
    panel.ignoresMouseEvents = false
    // Il trascinamento lo fa WindowDragHandle, solo dove serve: col
    // trascinamento "da sfondo" di AppKit anche la barra di avanzamento
    // sposterebbe la finestra invece di cercare nel brano, perche' per
    // AppKit la vista SwiftUI e' tutta sfondo.
    panel.isMovableByWindowBackground = false
    panel.isExcludedFromWindowsMenu = true
    panel.animationBehavior = .utilityWindow
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.minSize = NSSize(
      width: MiniPlayerLayout.minWidth,
      height: MiniPlayerLayout.height(forWidth: MiniPlayerLayout.minWidth))
    panel.maxSize = NSSize(
      width: MiniPlayerLayout.maxWidth,
      height: MiniPlayerLayout.height(forWidth: MiniPlayerLayout.maxWidth))
    panel.delegate = self
    panel.onCancel = { [weak self] in self?.hide() }

    let host = MiniPlayerHostingView(
      rootView: MiniPlayerView(
        model: model,
        menu: { [weak self] in self?.makeContextMenu() }
      )
    )
    host.model = model
    // La misura la decide la finestra (vedi windowWillResize), non SwiftUI:
    // con le opzioni di serie la vista spingerebbe la sua misura ideale
    // nella finestra come vincoli, e le due si contenderebbero il frame.
    host.sizingOptions = []
    panel.contentView = makeBackground(containing: host)

    placeInitially(panel)
    panel.setFrameAutosaveName(Self.frameName)
    return panel
  }

  /// Il vetro sotto a tutto: NSGlassEffectView su macOS 26, il materiale
  /// HUD prima. Raggio grande, e la copertina dentro usa quello concentrico
  /// (raggio esterno meno margine), come vuole Liquid Glass.
  private func makeBackground(containing content: NSView) -> NSView {
    // Macchia: la finestra non ha un fondo. La forma la disegna la vista
    // (la macchia della copertina), il resto e' trasparente e l'ombra di
    // sistema segue i pixel pieni, quindi la macchia.
    content.translatesAutoresizingMaskIntoConstraints = false
    let base = NSView()
    base.addSubview(content)
    pin(content, to: base)
    return base
  }

  /// NSGlassEffectView promette solo di mettere contentView "dentro il
  /// vetro", non dove ne' quanto grande: i vincoli lo tengono a filo. Se la
  /// vista non fosse ancora nella sua gerarchia, attivarli farebbe cadere
  /// l'app (nessun antenato comune): allora si ripiega sull'autoresizing.
  private func pin(_ view: NSView, to container: NSView) {
    guard view.isDescendant(of: container) else {
      view.translatesAutoresizingMaskIntoConstraints = true
      view.frame = container.bounds
      view.autoresizingMask = [.width, .height]
      return
    }
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }

  /// Maschera ad angoli tondi per il materiale pre-26: con le capInsets si
  /// stira a qualsiasi misura senza ridisegnarla.
  private static func roundedMask(radius: CGFloat) -> NSImage {
    let side = radius * 2 + 1
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) {
      rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(
      top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }

  /// La posizione salvata, se c'e' ed e' ancora su uno schermo; se no in
  /// alto a destra, dove Apple Music apre il suo.
  private func placeInitially(_ panel: NSPanel) {
    if panel.setFrameUsingName(Self.frameName) {
      var frame = panel.frame
      frame.size = clampedSize(width: frame.width)
      frame.origin.y += panel.frame.height - frame.height
      let onScreen = NSScreen.screens.contains {
        $0.visibleFrame.intersects(frame)
      }
      if onScreen {
        panel.setFrame(frame, display: false)
        return
      }
    }
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let size = panel.frame.size
    let visible = screen.visibleFrame
    panel.setFrameOrigin(
      NSPoint(
        x: visible.maxX - size.width - 24,
        y: visible.maxY - size.height - 24))
  }

  private func clampedSize(width: CGFloat) -> NSSize {
    let w = min(max(width, MiniPlayerLayout.minWidth), MiniPlayerLayout.maxWidth)
    return NSSize(width: w, height: MiniPlayerLayout.height(forWidth: w))
  }

  // MARK: - NSWindowDelegate

  /// La finestra e' quadrata (la macchia ci sta dentro): l'altezza si
  /// ricava dalla larghezza. Se si trascina un bordo orizzontale, comanda
  /// l'altezza.
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let extra = MiniPlayerLayout.height(forWidth: 0)
    let byWidth = frameSize.width
    let byHeight = frameSize.height - extra
    let current = sender.frame.width
    let width =
      abs(byWidth - current) >= abs(byHeight - current) ? byWidth : byHeight
    return clampedSize(width: width)
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    panel?.invalidateShadow()
  }

  // MARK: - Menu

  private func installMenuItems() {
    guard
      let menu = NSApp.windowsMenu
        ?? NSApp.mainMenu?.item(withTitle: "Window")?.submenu,
      !menu.items.contains(where: { $0.action == #selector(menuToggle(_:)) })
    else { return }

    let mini = NSMenuItem(
      title: "Mini Player", action: #selector(menuToggle(_:)),
      keyEquivalent: "m")
    mini.keyEquivalentModifierMask = [.command, .option]
    mini.target = self

    let onTop = NSMenuItem(
      title: "Keep Mini Player on Top",
      action: #selector(menuToggleAlwaysOnTop(_:)), keyEquivalent: "")
    onTop.target = self

    // Subito dopo Minimizza / Zoom, prima di "Porta tutto in primo piano".
    let zoom = menu.items.firstIndex {
      $0.action == #selector(NSWindow.performZoom(_:))
    }
    var index = zoom.map { $0 + 1 } ?? menu.items.count
    for item in [NSMenuItem.separator(), mini, onTop] {
      menu.insertItem(item, at: index)
      index += 1
    }
  }

  /// ⌥⌘M dentro l'app. Lo si prende prima che arrivi a finestre e menu: il
  /// menu Finestra di sistema puo' avere "Riduci tutto" come alternativa
  /// nascosta di Minimizza proprio su ⌥⌘M, e la vista Flutter si prende
  /// tutti i tasti con ⌘ prima del menu. Cosi' vale sempre, da qualsiasi
  /// finestra di Crocuta, e una volta sola.
  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        .subtracting([.capsLock, .numericPad, .function])
      guard mods == [.command, .option],
        event.charactersIgnoringModifiers?.lowercased() == "m"
      else { return event }
      self?.toggle()
      return nil
    }
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    func item(_ title: String, _ action: Selector) {
      let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
      i.target = self
      menu.addItem(i)
    }
    item("Show Main Window", #selector(menuExpand(_:)))
    menu.addItem(.separator())
    item("Keep on Top", #selector(menuToggleAlwaysOnTop(_:)))
    item("Hide Main Window While Open", #selector(menuToggleHidesMain(_:)))
    menu.addItem(.separator())
    item("Close Mini Player", #selector(menuClose(_:)))
    return menu
  }

  @objc private func menuToggle(_ sender: Any?) { toggle() }
  @objc private func menuExpand(_ sender: Any?) { expandToMainWindow() }
  @objc private func menuClose(_ sender: Any?) { hide() }
  @objc private func menuToggleAlwaysOnTop(_ sender: Any?) {
    alwaysOnTop.toggle()
  }
  @objc private func menuToggleHidesMain(_ sender: Any?) {
    hidesMainWindow.toggle()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(menuToggle(_:)):
      menuItem.state = isVisible ? .on : .off
    case #selector(menuToggleAlwaysOnTop(_:)):
      menuItem.state = alwaysOnTop ? .on : .off
    case #selector(menuToggleHidesMain(_:)):
      menuItem.state = hidesMainWindow ? .on : .off
    default:
      break
    }
    return true
  }

  // MARK: - Copertina

  /// La copertina la scarica il mini player per conto suo, piu' grande di
  /// quella del Centro di Controllo: l'URL che arriva da Dart e' spesso la
  /// miniatura da 120 px dei risultati di ricerca, che a 260 pt su Retina
  /// e' una macchia. Se la versione grande non c'e' si scende alla
  /// successiva, fino all'URL originale.
  private func loadArtwork(_ url: String) {
    guard url != artworkKey else { return }
    artworkKey = url
    artworkExpiry?.cancel()
    guard !url.isEmpty else {
      model.setArtwork(nil)
      applyTint?(nil)
      return
    }
    // La copertina vecchia resta finche' arriva la nuova (di solito un
    // attimo, e cosi' non lampeggia il segnaposto a ogni brano), ma non
    // oltre un secondo: se il download fallisce, meglio il segnaposto che
    // la copertina del brano prima.
    let expiry = DispatchWorkItem { [weak self] in
      self?.model.setArtwork(nil)
      self?.applyTint?(nil)
    }
    artworkExpiry = expiry
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: expiry)
    fetchArtwork(MiniPlayerArtwork.candidates(for: url), key: url)
  }

  private func fetchArtwork(_ candidates: [URL], key: String) {
    guard let url = candidates.first else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      let image = (200..<300).contains(status) ? data.flatMap(NSImage.init(data:)) : nil
      let prepared = image.flatMap { MiniPlayerArtwork.prepare($0, from: url) }
      DispatchQueue.main.async {
        guard let self, self.artworkKey == key else { return }
        guard let prepared else {
          self.fetchArtwork(Array(candidates.dropFirst()), key: key)
          return
        }
        self.artworkExpiry?.cancel()
        self.model.setArtwork(prepared.image)
        self.model.setPalette(seed: key, accent: prepared.accent, second: prepared.second)
        // Cambiata la macchia, l'ombra va ricalcolata: AppKit la ricava dai
        // pixel della finestra solo quando glielo si chiede.
        for delay in [0.05, 0.5] {
          DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.panel?.invalidateShadow()
          }
        }
      }
    }.resume()
  }
}

/// Il pannello: puo' diventare chiave (per Esc) senza mai attivare l'app.
final class MiniPlayerPanel: NSPanel {
  var onCancel: (() -> Void)?

  /// Lo spostamento si fa qui, sugli eventi della finestra, e non in una
  /// vista: la finestra e' una macchia, e una volta che SwiftUI ha preso il
  /// clic segue il mouse da solo, senza che i movimenti passino di qui.
  /// Quindi al clic si guarda cosa succede prima di consegnarlo: se il
  /// pulsante si rilascia subito era un clic, e va alla vista com'era; se
  /// il mouse si muove, e' uno spostamento della finestra, e la vista non
  /// ne sa niente. Dalla barra di avanzamento invece si cerca nel brano.
  override func sendEvent(_ event: NSEvent) {
    guard event.type == .leftMouseDown, !onProgressBar(event.locationInWindow)
    else {
      super.sendEvent(event)
      return
    }
    let start = NSEvent.mouseLocation
    let origin = frame.origin
    var moving = false
    while let next = nextEvent(
      matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
      inMode: .eventTracking, dequeue: true)
    {
      if next.type == .leftMouseUp {
        if !moving {
          // Era un clic: lo si consegna intero, pressione e rilascio.
          super.sendEvent(event)
          super.sendEvent(next)
        }
        return
      }
      let now = NSEvent.mouseLocation
      if !moving, hypot(now.x - start.x, now.y - start.y) > 3 { moving = true }
      if moving {
        setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
      }
    }
  }

  /// La barra di avanzamento: centrata, in basso nella macchia (vedi
  /// MiniPlayerView.info).
  private func onProgressBar(_ p: NSPoint) -> Bool {
    let w = frame.width, h = frame.height
    return p.x > w * 0.24 && p.x < w * 0.76 && p.y > h * 0.07 && p.y < h * 0.2
  }

  // Un pannello senza bordo di serie non diventa mai chiave.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// La vista SwiftUI dentro al pannello, con due ritocchi che SwiftUI da
/// sola non da'.
final class MiniPlayerHostingView: NSHostingView<MiniPlayerView> {
  weak var model: MiniPlayerModel?
  private var hoverArea: NSTrackingArea?

  /// Il primo clic deve gia' premere il pulsante: l'app di solito non e'
  /// attiva quando si usa il mini player, e senza questo il primo clic
  /// andrebbe solo a "svegliare" la finestra.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override var mouseDownCanMoveWindow: Bool { false }

  /// Il passaggio del mouse lo si segue qui con .activeAlways, perche' deve
  /// funzionare anche quando Crocuta e' in secondo piano, cioe' quasi
  /// sempre; .onHover di SwiftUI non lo garantisce in una finestra non
  /// chiave di un'app inattiva.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    if event.trackingArea === hoverArea { model?.hovering = true }
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    if event.trackingArea === hoverArea { model?.hovering = false }
  }
}

/// Copertina pronta per il mini player: URL piu' grandi da provare,
/// bande nere tolte, colore medio per il vetro.
enum MiniPlayerArtwork {
  struct Prepared {
    let image: NSImage
    let accent: NSColor
    let second: NSColor?
  }

  /// Gli URL da provare in ordine, l'originale per ultimo. Stesse due forme
  /// di `hiResArtwork` in lib/services/artwork.dart.
  static func candidates(for raw: String) -> [URL] {
    var urls: [String] = []
    let full = NSRange(raw.startIndex..., in: raw)
    // Copertine di YouTube Music: "=w120-h120-l90-rj" -> 600 px.
    if let re = try? NSRegularExpression(pattern: "=w\\d+-h\\d+"),
      re.firstMatch(in: raw, range: full) != nil
    {
      urls.append(
        re.stringByReplacingMatches(
          in: raw, range: full, withTemplate: "=w600-h600"))
    }
    // Miniature dei video: maxresdefault e' 16:9 pieno, senza bande.
    if let re = try? NSRegularExpression(
      pattern: "(/vi/[A-Za-z0-9_-]+/)(?:mq|hq|sd)?default\\.jpg"),
      re.firstMatch(in: raw, range: full) != nil
    {
      urls.append(
        re.stringByReplacingMatches(
          in: raw, range: full, withTemplate: "$1maxresdefault.jpg"))
    }
    urls.append(raw)
    var seen = Set<String>()
    return urls.filter { seen.insert($0).inserted }.compactMap(URL.init(string:))
  }

  /// Gira fuori dal main thread (dentro il completamento di URLSession).
  static func prepare(_ image: NSImage, from url: URL) -> Prepared? {
    guard var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }
    // YouTube rifiuta maxresdefault con un'immagine grigia 120x90 e 404,
    // gia' scartata; ma hqdefault e' 4:3 con il video 16:9 in mezzo e due
    // bande nere sopra e sotto. Riempendo il quadrato si vedrebbero: si
    // tiene solo la fascia 16:9 centrale.
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    if url.path.contains("/vi/"), abs(w / h - 4.0 / 3.0) < 0.02 {
      let band = (w * 9 / 16).rounded()
      let crop = CGRect(x: 0, y: ((h - band) / 2).rounded(), width: w, height: band)
      if let cropped = cg.cropping(to: crop) { cg = cropped }
    }
    let result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    let palette = MacchiaColors.palette(of: cg)
    return Prepared(image: result, accent: palette.accent, second: palette.second)
  }
}
