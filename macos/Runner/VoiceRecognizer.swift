import AVFoundation
import Speech

#if os(iOS)
  import Flutter
#else
  import CoreAudio
  import FlutterMacOS
#endif

/// Il riconoscimento vocale dell'assistente interno, su iPhone e Mac.
///
/// Nostro e non del pacchetto speech_to_text, per due cose che il pacchetto
/// sbagliava:
///
/// - usava il microfono degli AirPods. Aperto quello, il sistema passa gli
///   AirPods in modalita' chiamata (HFP): mono, ovattati, "come in
///   chiamata". Qui si ascolta col microfono del Mac o dell'iPhone, e gli
///   AirPods restano in alta qualita'.
/// - teneva il microfono aperto per sempre, anche finito di ascoltare: un
///   AVAudioEngine creato all'inizio e mai liberato. Qui il motore nasce a
///   ogni ascolto e muore subito dopo.
///
/// Stesso file nei due progetti (ios/Runner e macos/Runner): le differenze
/// sono la sessione audio di iOS e la scelta del microfono sul Mac.
final class VoiceRecognizer: NSObject {
  static let shared = VoiceRecognizer()

  private var channel: FlutterMethodChannel?
  private var engine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "crocuta/voice", binaryMessenger: messenger)
    shared.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "authorize":
        shared.authorize(result)
      case "start":
        let args = call.arguments as? [String: Any]
        shared.start(locale: args?["locale"] as? String, result: result)
      case "stop":
        shared.request?.endAudio()
        shared.teardown(keepTask: true)
        result(nil)
      case "cancel":
        shared.task?.cancel()
        shared.teardown(keepTask: false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Permessi

  private func authorize(_ result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { result(false) }
        return
      }
      #if os(iOS)
        AVAudioApplication.requestRecordPermission { ok in
          DispatchQueue.main.async { result(ok) }
        }
      #else
        AVCaptureDevice.requestAccess(for: .audio) { ok in
          DispatchQueue.main.async { result(ok) }
        }
      #endif
    }
  }

  // MARK: - Ascolto

  private func start(locale: String?, result: @escaping FlutterResult) {
    teardown(keepTask: false)
    let loc = locale.map { Locale(identifier: $0) } ?? Locale.current
    guard let recognizer = SFSpeechRecognizer(locale: loc) ?? SFSpeechRecognizer(),
      recognizer.isAvailable
    else {
      result(FlutterError(code: "unavailable", message: "speech not available", details: nil))
      return
    }
    self.recognizer = recognizer

    do {
      #if os(iOS)
        // Registrazione col microfono dell'iPhone: niente .allowBluetooth,
        // che sceglierebbe quello degli AirPods e li metterebbe in
        // modalita' chiamata. L'uscita resta sulle cuffie (A2DP).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playAndRecord, mode: .measurement,
          options: [.allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true)
      #endif

      let engine = AVAudioEngine()
      let input = engine.inputNode
      #if os(macOS)
        if let mic = Self.builtInMicrophone(), let unit = input.audioUnit {
          var device = mic
          AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
      #endif

      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      request.taskHint = .search
      if recognizer.supportsOnDeviceRecognition {
        request.requiresOnDeviceRecognition = true
      }

      let format = input.outputFormat(forBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
        request.append(buffer)
        self?.reportLevel(buffer)
      }
      engine.prepare()
      try engine.start()
      self.engine = engine
      self.request = request

      task = recognizer.recognitionTask(with: request) { [weak self] res, error in
        guard let self else { return }
        if let res {
          let text = res.bestTranscription.formattedString
          let isFinal = res.isFinal
          DispatchQueue.main.async {
            self.channel?.invokeMethod("result", arguments: ["text": text, "final": isFinal])
          }
          if isFinal { DispatchQueue.main.async { self.teardown(keepTask: false) } }
        } else if let error {
          DispatchQueue.main.async {
            self.channel?.invokeMethod("error", arguments: error.localizedDescription)
            self.teardown(keepTask: false)
          }
        }
      }
      result(true)
    } catch {
      teardown(keepTask: false)
      result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
    }
  }

  /// Ferma il microfono e lo libera. Con [keepTask] il riconoscimento
  /// finisce di elaborare quello che ha gia' sentito e manda il risultato.
  private func teardown(keepTask: Bool) {
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      engine.reset()
    }
    engine = nil
    if !keepTask {
      task = nil
      request = nil
    }
  }

  private var lastLevel = Date.distantPast

  private func reportLevel(_ buffer: AVAudioPCMBuffer) {
    let now = Date()
    guard now.timeIntervalSince(lastLevel) > 0.05,
      let data = buffer.floatChannelData?[0]
    else { return }
    lastLevel = now
    let n = Int(buffer.frameLength)
    guard n > 0 else { return }
    var sum: Float = 0
    for i in 0..<n { sum += data[i] * data[i] }
    let rms = sqrt(sum / Float(n))
    // Da circa -50 dB (silenzio) a -10 dB (voce vicina), in 0-1.
    let db = 20 * log10(max(rms, 1e-6))
    let level = max(0, min(1, (db + 50) / 40))
    DispatchQueue.main.async {
      self.channel?.invokeMethod("level", arguments: Double(level))
    }
  }

  #if os(macOS)
    /// Il microfono del Mac, se c'e': quello che non mette gli AirPods in
    /// modalita' chiamata.
    static func builtInMicrophone() -> AudioDeviceID? {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
      var size: UInt32 = 0
      guard
        AudioObjectGetPropertyDataSize(
          AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
      else { return nil }
      var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
      guard
        AudioObjectGetPropertyData(
          AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
      else { return nil }
      for id in ids where hasInput(id) {
        var transport: UInt32 = 0
        var tsize = UInt32(MemoryLayout<UInt32>.size)
        var taddr = AudioObjectPropertyAddress(
          mSelector: kAudioDevicePropertyTransportType,
          mScope: kAudioObjectPropertyScopeGlobal,
          mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(id, &taddr, 0, nil, &tsize, &transport) == noErr,
          transport == kAudioDeviceTransportTypeBuiltIn
        {
          return id
        }
      }
      return nil
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
      var size: UInt32 = 0
      return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
  #endif
}
