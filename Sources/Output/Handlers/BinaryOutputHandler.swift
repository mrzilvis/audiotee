import Foundation

/// Binary output with JSON headers (pipe-optimised)
public class BinaryAudioOutputHandler: AudioOutputHandler {
  public init() {}

  public func handleAudioPacket(_ packet: AudioPacket) {
    // Create metadata without the audio data
    let metadata = BinaryPacketHeader(from: packet)

    // Write JSON metadata line
    Logger.writeMessage(.audio, data: metadata)

    // Write raw binary audio data directly to stdout
    FileHandle.standardOutput.write(packet.rawAudioData)
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
