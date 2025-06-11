import Foundation

/// Base64-encoded JSON output (terminal-safe)
public class JSONAudioOutputHandler: AudioOutputHandler {
  public init() {}

  public func handleAudioPacket(_ packet: AudioPacket) {
    let jsonPacket = JSONAudioPacket(from: packet)
    Logger.writeMessage(.audio, data: jsonPacket)
  }

  public func handleMetadata(_ metadata: AudioStreamMetadata) {
    Logger.writeMessage(.metadata, data: metadata)
  }

  public func handleStreamStart() {
    Logger.writeMessage(.streamStart, data: Optional<String>.none)
  }

  public func handleStreamStop() {
    Logger.writeMessage(.streamStop, data: Optional<String>.none)
  }
}
