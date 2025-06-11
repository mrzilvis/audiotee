import ArgumentParser
import CoreAudio
import Foundation

struct AudioTee: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Capture system audio and stream to stdout",
    discussion: """
      AudioTee captures system audio using Core Audio taps and streams it as structured output.

      Output formats:
      • json: Base64-encoded audio in JSON messages (safe for terminals)
      • binary: Raw binary audio with JSON metadata headers (efficient for pipes)
      • auto: Automatically choose based on whether stdout is a terminal (default)

      Tap configuration:
      • processes: List of process IDs to tap (empty = all processes)
      • mute: How to handle processes being tapped
      • exclusive: Whether to use exclusive mode

      Examples:
        audiotee                    # Auto format (JSON in terminal, binary when piped)
        audiotee --format=json      # Always use JSON format
        audiotee --format=binary    # Always use binary format
        audiotee --convert-to=16000 # Convert to 16kHz mono for ASR
        audiotee --convert-to=8000  # Convert to 8kHz for telephony
        audiotee --processes 1234   # Only tap process 1234
        audiotee --processes 1234 5678 9012  # Tap multiple processes
        audiotee --mute=muted       # Mute processes being tapped
        audiotee --no-exclusive     # Don't use exclusive mode
      """
  )

  @Option(name: .shortAndLong, help: "Output format")
  var format: OutputFormat = .auto

  @Option(
    name: .long, help: "Process IDs to tap (space-separated for multiple, empty = all processes)")
  var processes: [Int32] = []

  @Option(name: .long, help: "Mute behavior for tapped processes")
  var mute: TapMuteBehavior = .unmuted

  @Flag(name: .long, inversion: .prefixedNo, help: "Use exclusive mode to capture all processes")
  var exclusive: Bool = true

  @Option(
    name: .long,
    help: "Convert audio to specified sample rate (8000, 16000, 22050, 24000, 32000, 44100, 48000)")
  var convertTo: Double?

  @Option(
    name: .long,
    help: "Audio chunk duration in seconds (default: 0.2)")
  var chunkDuration: Double = 0.2

  func run() throws {
    setupSignalHandlers()

    Logger.info("Starting AudioTee...")
    Logger.debug("Using output format: \(format)")

    // Validate chunk duration
    guard chunkDuration > 0 && chunkDuration <= 5.0 else {
      Logger.error(
        "Invalid chunk duration",
        context: ["chunk_duration": String(chunkDuration), "valid_range": "0.0 < duration <= 5.0"])
      throw ExitCode.failure
    }

    let tapConfig = TapConfiguration(
      processes: processes,
      muteBehavior: mute,
      isExclusive: exclusive
    )

    let audioTapManager = AudioTapManager()
    do {
      try audioTapManager.setupAudioTap(with: tapConfig)
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

    guard let deviceID = audioTapManager.getDeviceID() else {
      Logger.error("Failed to get device ID from audio tap manager")
      throw ExitCode.failure
    }

    let outputHandler = createOutputHandler(for: format)
    let recorder = AudioRecorder(
      deviceID: deviceID, outputHandler: outputHandler, convertToSampleRate: convertTo,
      chunkDuration: chunkDuration)
    recorder.startRecording()

    // Run until the run loop is stopped (by signal handler)
    while true {
      let result = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
      if result == CFRunLoopRunResult.stopped || result == CFRunLoopRunResult.finished {
        break
      }
    }

    Logger.info("Shutting down...")
    recorder.stopRecording()
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

  private func createOutputHandler(for format: OutputFormat) -> AudioOutputHandler {
    switch format {
    case .json:
      return JSONAudioOutputHandler()
    case .binary:
      return BinaryAudioOutputHandler()
    case .auto:
      return AutoAudioOutputHandler()
    }
  }
}
