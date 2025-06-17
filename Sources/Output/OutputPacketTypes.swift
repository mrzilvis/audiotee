import Foundation

/// JSON-serializable version of AudioPacket with base64-encoded audio data
public struct JSONAudioPacket: Codable {
  public let timestamp: Date
  public let duration: Double
  public let peakAmplitude: Float
  public let audioData: String  // base64 encoded audio data

  public enum CodingKeys: String, CodingKey {
    case timestamp
    case duration
    case peakAmplitude = "peak_amplitude"
    case audioData = "audio_data"
  }

  public init(from packet: AudioPacket) {
    self.timestamp = packet.timestamp
    self.duration = packet.duration
    self.peakAmplitude = packet.peakAmplitude
    self.audioData = packet.rawAudioData.base64EncodedString()
  }
}

/// Metadata-only packet for binary output (without base64 audio data)
public struct BinaryPacketHeader: Codable {
  public let timestamp: Date
  public let duration: Double
  public let peakAmplitude: Float
  public let audioLength: Int  // Length of raw audio data in bytes

  public enum CodingKeys: String, CodingKey {
    case timestamp
    case duration
    case peakAmplitude = "peak_amplitude"
    case audioLength = "audio_length"
  }

  public init(from packet: AudioPacket) {
    self.timestamp = packet.timestamp
    self.duration = packet.duration
    self.peakAmplitude = packet.peakAmplitude
    self.audioLength = packet.rawAudioData.count
  }
}
