import Foundation

/// Enhanced output handler that supports multiple audio streams with binary headers
/// Format: [StreamID:1byte][Timestamp:8bytes][PacketSize:4bytes][AudioData:PacketSize bytes]
public class StreamBinaryOutputHandler: AudioOutputHandler {
  private let enableStreamHeaders: Bool

  public init(enableStreamHeaders: Bool = true) {
    self.enableStreamHeaders = enableStreamHeaders
  }

  public func handleAudioPacket(_ packet: AudioPacket) {
    // Backward compatibility - treat regular AudioPacket as system audio
    handleStreamAudioPacket(StreamAudioPacket(
      streamId: .systemAudio,
      timestamp: packet.timestamp,
      duration: packet.duration,
      data: packet.data
    ))
  }

  /// Handle audio packet with stream identification
  public func handleStreamAudioPacket(_ packet: StreamAudioPacket) {
    if enableStreamHeaders {
      // Write header + data
      let header = StreamHeader(
        streamId: packet.streamId,
        timestamp: packet.timestamp,
        packetSize: UInt32(packet.data.count)
      )

      FileHandle.standardOutput.write(header.serialize())
      FileHandle.standardOutput.write(packet.data)
    } else {
      // Legacy mode - just write raw audio data
      FileHandle.standardOutput.write(packet.data)
    }
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

/// Protocol extension to support stream-aware output handlers
public protocol StreamAudioOutputHandler: AudioOutputHandler {
  func handleStreamAudioPacket(_ packet: StreamAudioPacket)
}