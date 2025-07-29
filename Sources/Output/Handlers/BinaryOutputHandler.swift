import Foundation

/// Binary output with JSON headers (pipe-optimised)
public class BinaryAudioOutputHandler: AudioOutputHandler {
  public init() {}

  public func handleAudioPacket(_ packet: AudioPacket) {
    // Write raw binary audio data directly to stdout
    FileHandle.standardOutput.write(packet.data)
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
