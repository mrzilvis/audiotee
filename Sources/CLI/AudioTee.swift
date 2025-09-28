import CoreAudio
import Foundation

struct AudioTee {
  var includeProcesses: [Int32] = []
  var excludeProcesses: [Int32] = []
  var mute: Bool = false
  var stereo: Bool = false
  var sampleRate: Double?
  var chunkDuration: Double = 0.2

  // Microphone recording options
  var microphoneEnabled: Bool = false
  var microphoneSampleRate: Double?
  var microphoneDeviceUID: String?
  var noSystemAudio: Bool = false
  var enableStreamHeaders: Bool = false

  init() {}

  static func main() {
    let parser = SimpleArgumentParser(
      programName: "audiotee",
      abstract: "Capture system audio and stream to stdout",
      discussion: """
        AudioTee captures system audio using Core Audio taps and optionally microphone input,
        streaming both as structured output with stream identification.

        Process filtering:
        • include-processes: Only tap specified process IDs (empty = all processes)
        • exclude-processes: Tap all processes except specified ones
        • mute: How to handle processes being tapped

        Microphone recording:
        • microphone: Enable microphone recording as separate stream
        • mic-sample-rate: Independent sample rate for microphone
        • no-system-audio: Record only microphone (disable system audio tap)
        • stream-headers: Enable binary stream headers for multi-stream output

        Examples:
          audiotee                              # System audio only
          audiotee --microphone                 # System audio + microphone with headers
          audiotee --microphone --stream-headers # Explicit stream headers
          audiotee --microphone --no-system-audio # Microphone only
          audiotee --sample-rate 48000 --microphone --mic-sample-rate 16000 # Different rates
          audiotee --include-processes 1234 --microphone  # Specific process + mic
        """
    )

    // Configure arguments
    parser.addArrayOption(
      name: "include-processes",
      help: "Process IDs to include (space-separated, empty = all processes)")
    parser.addArrayOption(
      name: "exclude-processes", help: "Process IDs to exclude (space-separated)")
    parser.addFlag(name: "mute", help: "Mute processes being tapped")
    parser.addFlag(name: "stereo", help: "Records in stereo")
    parser.addOption(
      name: "sample-rate",
      help: "Target sample rate (8000, 16000, 22050, 24000, 32000, 44100, 48000)")
    parser.addOption(
      name: "chunk-duration", help: "Audio chunk duration in seconds", defaultValue: "0.2")

    // Microphone recording arguments
    parser.addFlag(name: "microphone", help: "Enable microphone recording as separate stream")
    parser.addOption(
      name: "mic-sample-rate",
      help: "Microphone sample rate (8000, 16000, 22050, 24000, 32000, 44100, 48000)")
    parser.addOption(name: "mic-device", help: "Microphone device UID (default: system default)")
    parser.addFlag(name: "no-system-audio", help: "Record only microphone (disable system audio tap)")
    parser.addFlag(name: "stream-headers", help: "Enable binary stream headers (auto-enabled with --microphone)")

    // Parse arguments
    do {
      try parser.parse()

      var audioTee = AudioTee()

      // Extract values
      audioTee.includeProcesses = try parser.getArrayValue("include-processes", as: Int32.self)
      audioTee.excludeProcesses = try parser.getArrayValue("exclude-processes", as: Int32.self)
      audioTee.mute = parser.getFlag("mute")
      audioTee.stereo = parser.getFlag("stereo")
      audioTee.sampleRate = try parser.getOptionalValue("sample-rate", as: Double.self)
      audioTee.chunkDuration = try parser.getValue("chunk-duration", as: Double.self)

      // Microphone options
      audioTee.microphoneEnabled = parser.getFlag("microphone")
      audioTee.microphoneSampleRate = try parser.getOptionalValue("mic-sample-rate", as: Double.self)
      audioTee.microphoneDeviceUID = try parser.getOptionalValue("mic-device", as: String.self)
      audioTee.noSystemAudio = parser.getFlag("no-system-audio")
      // Enable stream headers if explicitly requested, or if both system audio and microphone are enabled
      audioTee.enableStreamHeaders = parser.getFlag("stream-headers") ||
        (audioTee.microphoneEnabled && !audioTee.noSystemAudio)

      // Validate
      try audioTee.validate()

      // Run
      try audioTee.run()

    } catch ArgumentParserError.helpRequested {
      parser.printHelp()
      exit(0)
    } catch ArgumentParserError.validationFailed(let message) {
      print("Error: \(message)", to: &standardError)
      exit(1)
    } catch let error as ArgumentParserError {
      print("Error: \(error.description)", to: &standardError)
      parser.printHelp()
      exit(1)
    } catch {
      print("Error: \(error)", to: &standardError)
      exit(1)
    }
  }

  func validate() throws {
    if !includeProcesses.isEmpty && !excludeProcesses.isEmpty {
      throw ArgumentParserError.validationFailed(
        "Cannot specify both --include-processes and --exclude-processes")
    }

    if noSystemAudio && !microphoneEnabled {
      throw ArgumentParserError.validationFailed(
        "--no-system-audio requires --microphone to be enabled")
    }

    if !microphoneEnabled && (microphoneSampleRate != nil || microphoneDeviceUID != nil) {
      throw ArgumentParserError.validationFailed(
        "Microphone options require --microphone to be enabled")
    }
  }

  func run() throws {
    setupSignalHandlers()

    Logger.info("Starting AudioTee...")

    // Validate chunk duration
    guard chunkDuration > 0 && chunkDuration <= 5.0 else {
      Logger.error(
        "Invalid chunk duration",
        context: ["chunk_duration": String(chunkDuration), "valid_range": "0.0 < duration <= 5.0"])
      throw ExitCode.failure
    }

    // Create shared output handler (stream-aware or legacy)
    let outputHandler: AudioOutputHandler
    if enableStreamHeaders {
      outputHandler = StreamBinaryOutputHandler(enableStreamHeaders: true)
    } else {
      outputHandler = BinaryAudioOutputHandler()
    }

    // Variables to hold recorders and tap manager
    var systemRecorder: AudioRecorder?
    var microphoneRecorder: MicrophoneRecorder?
    var audioTapManager: AudioTapManager?

    // Set up system audio recording (unless disabled)
    if !noSystemAudio {
      Logger.info("Setting up system audio recording...")

      let (processes, isExclusive) = convertProcessFlags()
      let tapConfig = TapConfiguration(
        processes: processes,
        muteBehavior: mute ? .muted : .unmuted,
        isExclusive: isExclusive,
        isMono: !stereo
      )

      audioTapManager = AudioTapManager()
      do {
        try audioTapManager!.setupAudioTap(with: tapConfig)
      } catch AudioTeeError.pidTranslationFailed(let failedPIDs) {
        Logger.error(
          "Failed to translate process IDs to audio objects",
          context: [
            "failed_pids": failedPIDs.map(String.init).joined(separator: ", "),
            "suggestion": "Check that the process IDs exist and are running",
          ])
        throw ExitCode.failure
      } catch {
        Logger.error(
          "Failed to setup audio tap", context: ["error": String(describing: error)])
        throw ExitCode.failure
      }

      guard let deviceID = audioTapManager!.getDeviceID() else {
        Logger.error("Failed to get device ID from audio tap manager")
        throw ExitCode.failure
      }

      // Create system audio recorder with stream-aware output handler
      if let streamHandler = outputHandler as? StreamBinaryOutputHandler {
        systemRecorder = AudioRecorder(
          deviceID: deviceID,
          outputHandler: SystemAudioOutputAdapter(streamHandler: streamHandler),
          convertToSampleRate: sampleRate,
          chunkDuration: chunkDuration)
      } else {
        systemRecorder = AudioRecorder(
          deviceID: deviceID, outputHandler: outputHandler, convertToSampleRate: sampleRate,
          chunkDuration: chunkDuration)
      }

      systemRecorder?.startRecording()
      Logger.info("System audio recording started")
    }

    // Set up microphone recording (if enabled)
    if microphoneEnabled {
      Logger.info("Setting up microphone recording...")

      microphoneRecorder = MicrophoneRecorder(
        outputHandler: outputHandler,
        convertToSampleRate: microphoneSampleRate,
        chunkDuration: chunkDuration,
        deviceUID: microphoneDeviceUID
      )

      do {
        try microphoneRecorder?.startRecording()
        Logger.info("Microphone recording started")
      } catch {
        Logger.error("Failed to start microphone recording", context: ["error": String(describing: error)])
        throw ExitCode.failure
      }
    }

    // Ensure at least one recording source is active
    if systemRecorder == nil && microphoneRecorder == nil {
      Logger.error("No recording sources enabled")
      throw ExitCode.failure
    }

    // Run until the run loop is stopped (by signal handler)
    while true {
      let result = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
      if result == CFRunLoopRunResult.stopped || result == CFRunLoopRunResult.finished {
        break
      }
    }

    Logger.info("Shutting down...")
    systemRecorder?.stopRecording()
    microphoneRecorder?.stopRecording()
  }

  private func setupSignalHandlers() {
    signal(SIGINT) { _ in
      Logger.info("Received SIGINT, initiating graceful shutdown...")
      CFRunLoopStop(CFRunLoopGetMain())
    }
    signal(SIGTERM) { _ in
      Logger.info("Received SIGTERM, initiating graceful shutdown...")
      CFRunLoopStop(CFRunLoopGetMain())
    }
  }

  private func convertProcessFlags() -> ([Int32], Bool) {
    if !includeProcesses.isEmpty {
      // Include specific processes only
      return (includeProcesses, false)
    } else if !excludeProcesses.isEmpty {
      // Exclude specific processes (tap everything except these)
      return (excludeProcesses, true)
    } else {
      // Default: tap everything
      return ([], true)
    }
  }
}

// Helper for stderr output
var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    let data = Data(string.utf8)
    self.write(data)
  }
}

// Exit code handling
enum ExitCode: Error {
  case failure
}

extension ExitCode {
  var code: Int32 {
    switch self {
    case .failure:
      return 1
    }
  }
}
