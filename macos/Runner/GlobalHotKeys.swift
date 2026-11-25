import Carbon
import Cocoa

/// Scorciatoie globali: funzionano anche quando Crocuta non e' l'app attiva.
///
/// Con `RegisterEventHotKey` di Carbon, e non con un event tap: il tap
/// chiede il permesso di Accessibilita' (o Monitoraggio input), questo no.
/// E' ancora l'API che usano Rectangle, Raycast e simili.
///
/// Le combinazioni sono tutte ⌃⌥⌘ + tasto, e sono state scelte contro quello
/// che c'e' davvero su questo Mac, non a occhio:
///
/// - ⌃⌥Space e' "Sorgente di input successiva" (attivo di serie), e ⌃Space
///   la precedente: Space con ⌃⌥ e' gia' preso.
/// - ⌃⌥←/→ e ⌃⌥⌘←/→ sono di Rectangle (installato) in entrambi i suoi set
///   di serie: terzi di schermo e schermo precedente/successivo. Con un
///   hot key Carbon vince chi registra per primo, e l'altro tace: le frecce
///   sono escluse, e lo sono anche ⌃←/→ (Spaces) e ⌥⌘←/→ (Spectacle/Chrome).
/// - ⌃⌥⌘ non lo usa di serie ne' macOS ne' quasi nessuna app, e i tasti
///   scelti hanno la stessa posizione sulla tastiera italiana e su quella
///   americana (i codici sono posizionali).
///
/// Risultato:
/// - ⌃⌥⌘Space  play / pausa
/// - ⌃⌥⌘.      brano successivo   (il tasto di ">")
/// - ⌃⌥⌘,      brano precedente   (il tasto di "<")
/// - ⌃⌥⌘M      mini player
///
/// Unica sovrapposizione nota: ⌃⌥⌘, e ⌃⌥⌘. sono anche "Riduci/Aumenta
/// contrasto" nelle scorciatoie di Accessibilita', spente di serie.
///
/// I tasti multimediali F7–F9 non passano di qui: restano a
/// MPRemoteCommandCenter in NowPlayingController.
final class GlobalHotKeys {
  static let shared = GlobalHotKeys()

  private struct HotKey {
    let keyCode: Int
    let name: String
    let action: () -> Void
  }

  /// Firma a quattro lettere che marca i nostri hot key negli eventi.
  private static let signature: OSType = 0x4352_4354  // "CRCT"

  private var hotKeys: [UInt32: HotKey] = [:]
  private var refs: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?

  func register() {
    guard handler == nil else { return }

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed))
    // Una funzione C senza contesto: il singleton fa da contesto.
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        guard let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let err = GetEventParameter(
          event, EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard err == noErr, id.signature == GlobalHotKeys.signature else {
          return OSStatus(eventNotHandledErr)
        }
        GlobalHotKeys.shared.fire(id.id)
        return noErr
      },
      1, &spec, nil, &handler)
    guard status == noErr else {
      NSLog("Crocuta: hot key globali non installate (%d)", status)
      return
    }

    add(kVK_Space, "play/pausa") { NowPlayingController.shared?.send("toggle") }
    add(kVK_ANSI_Period, "successivo") { NowPlayingController.shared?.send("next") }
    add(kVK_ANSI_Comma, "precedente") {
      NowPlayingController.shared?.send("previous")
    }
    add(kVK_ANSI_M, "mini player") { MiniPlayerController.shared.toggle() }
  }

  private func add(_ keyCode: Int, _ name: String, _ action: @escaping () -> Void) {
    let id = UInt32(hotKeys.count + 1)
    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(keyCode), modifiers,
      EventHotKeyID(signature: Self.signature, id: id),
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      // eventHotKeyExistsErr: un'altra app ha gia' la stessa combinazione.
      // Si va avanti con le altre invece di rinunciare a tutte.
      NSLog("Crocuta: hot key %@ non registrata (%d)", name, status)
      return
    }
    refs.append(ref)
    hotKeys[id] = HotKey(keyCode: keyCode, name: name, action: action)
  }

  private func fire(_ id: UInt32) {
    hotKeys[id]?.action()
  }
}
