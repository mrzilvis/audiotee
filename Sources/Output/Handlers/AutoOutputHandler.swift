import Foundation

/// Auto-detecting output handler based on TTY
public class AutoAudioOutputHandler: AudioOutputHandler {
  private let handler: AudioOutputHandler

  public init() {
    // Auto-detect based on whether stdout is a terminal
    if isatty(STDOUT_FILENO) != 0 {
      handler = JSONAudioOutputHandler()
    } else {
      handler = BinaryAudioOutputHandler()
    }
  }

  public func handleAudioPacket(_ packet: AudioPacket) {
    handler.handleAudioPacket(packet)
  }

  public func handleMetadata(_ metadata: AudioStreamMetadata) {
    handler.handleMetadata(metadata)
  }

  public func handleStreamStart() {
    handler.handleStreamStart()
  }

  public func handleStreamStop() {
    handler.handleStreamStop()
  }
}
