import Foundation

public struct AudioPacket {
  public let timestamp: Date
  public let duration: Double
  public let rawAudioData: Data

  public init(
    timestamp: Date,
    duration: Double,
    rawAudioData: Data
  ) {
    self.timestamp = timestamp
    self.duration = duration
    self.rawAudioData = rawAudioData
  }
}
