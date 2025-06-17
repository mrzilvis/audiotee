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

      Process filtering:
      • include-processes: Only tap specified process IDs (empty = all processes)
      • exclude-processes: Tap all processes except specified ones
      • mute: How to handle processes being tapped

      Examples:
        audiotee                              # Auto format, tap all processes
        audiotee --format=json                # Always use JSON format
        audiotee --format=binary              # Always use binary format
        audiotee --convert-to=16000           # Convert to 16kHz mono for ASR
        audiotee --convert-to=8000            # Convert to 8kHz for telephony
        audiotee --include-processes 1234     # Only tap process 1234
        audiotee --include-processes 1234 5678 9012  # Tap only these processes
        audiotee --exclude-processes 1234 5678       # Tap everything except these
        audiotee --mute                       # Mute processes being tapped
      """
  )

  @Option(name: .shortAndLong, help: "Output format")
  var format: OutputFormat = .auto

  @Option(
    name: .long, help: "Process IDs to include (space-separated, empty = all processes)")
  var includeProcesses: [Int32] = []

  @Option(
    name: .long, help: "Process IDs to exclude (space-separated)")
  var excludeProcesses: [Int32] = []

  @Flag(name: .long, help: "Mute processes being tapped")
  var mute: Bool = false

  @Option(
    name: .long,
    help: "Convert audio to specified sample rate (8000, 16000, 22050, 24000, 32000, 44100, 48000)")
  var convertTo: Double?

  @Option(
    name: .long,
    help: "Audio chunk duration in seconds (default: 0.2)")
  var chunkDuration: Double = 0.2

  func validate() throws {
    if !includeProcesses.isEmpty && !excludeProcesses.isEmpty {
      throw ValidationError("Cannot specify both --include-processes and --exclude-processes")
    }
  }

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

    // Convert include/exclude processes to TapConfiguration format
    let (processes, isExclusive) = convertProcessFlags()

    let tapConfig = TapConfiguration(
      processes: processes,
      muteBehavior: mute ? .muted : .unmuted,
      isExclusive: isExclusive
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
