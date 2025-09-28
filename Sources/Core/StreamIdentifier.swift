import Foundation

/// Stream identifier for distinguishing different audio sources
public enum StreamIdentifier: UInt8 {
  case systemAudio = 0
  case microphone = 1
  // Future: case lineInput = 2, case bluetoothInput = 3, etc.
}

/// Binary stream header format: [StreamID:1byte][Timestamp:8bytes][PacketSize:4bytes]
public struct StreamHeader {
  public let streamId: StreamIdentifier
  public let timestamp: UInt64  // Unix timestamp in microseconds
  public let packetSize: UInt32

  public init(streamId: StreamIdentifier, timestamp: Date, packetSize: UInt32) {
    self.streamId = streamId
    // Convert Date to microseconds since Unix epoch
    self.timestamp = UInt64(timestamp.timeIntervalSince1970 * 1_000_000)
    self.packetSize = packetSize
  }

  /// Serialize header to binary data (little-endian)
  public func serialize() -> Data {
    var data = Data()
    data.append(streamId.rawValue)
    data.append(withUnsafeBytes(of: timestamp.littleEndian) { Data($0) })
    data.append(withUnsafeBytes(of: packetSize.littleEndian) { Data($0) })
    return data
  }

  /// Total header size in bytes
  public static let headerSize = 13  // 1 + 8 + 4
}

/// Enhanced AudioPacket that includes stream identification
public struct StreamAudioPacket {
  public let streamId: StreamIdentifier
  public let timestamp: Date
  public let duration: Double
  public let data: Data

  public init(
    streamId: StreamIdentifier,
    timestamp: Date,
    duration: Double,
    data: Data
  ) {
    self.streamId = streamId
    self.timestamp = timestamp
    self.duration = duration
    self.data = data
  }

  /// Convert to regular AudioPacket (for backward compatibility)
  public var audioPacket: AudioPacket {
    return AudioPacket(timestamp: timestamp, duration: duration, data: data)
  }
}