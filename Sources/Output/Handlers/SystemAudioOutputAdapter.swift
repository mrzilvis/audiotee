import Foundation

/// Adapter to bridge existing AudioRecorder with the new stream-aware output system
/// Converts regular AudioPackets to StreamAudioPackets tagged as system audio
public class SystemAudioOutputAdapter: AudioOutputHandler {
  private let streamHandler: StreamBinaryOutputHandler

  public init(streamHandler: StreamBinaryOutputHandler) {
    self.streamHandler = streamHandler
  }

  public func handleAudioPacket(_ packet: AudioPacket) {
    // Convert regular AudioPacket to StreamAudioPacket tagged as system audio
    let streamPacket = StreamAudioPacket(
      streamId: .systemAudio,
      timestamp: packet.timestamp,
      duration: packet.duration,
      data: packet.data
    )

    streamHandler.handleStreamAudioPacket(streamPacket)
  }

  public func handleMetadata(_ metadata: AudioStreamMetadata) {
    streamHandler.handleMetadata(metadata)
  }

  public func handleStreamStart() {
    streamHandler.handleStreamStart()
  }

  public func handleStreamStop() {
    streamHandler.handleStreamStop()
  }
}