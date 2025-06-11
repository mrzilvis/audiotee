import Foundation

public struct AudioPacket {
  public let timestamp: Date
  public let duration: Double
  public let peakAmplitude: Float  // useful for level monitoring
  public let rawAudioData: Data

  public init(
    timestamp: Date,
    duration: Double,
    peakAmplitude: Float,
    rawAudioData: Data
  ) {
    self.timestamp = timestamp
    self.duration = duration
    self.peakAmplitude = peakAmplitude
    self.rawAudioData = rawAudioData
  }
}
