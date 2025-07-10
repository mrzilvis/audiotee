import CoreAudio
import Foundation

public class AudioBuffer {
  private var buffer: [UInt8]
  private var writeIndex: Int = 0
  private var readIndex: Int = 0
  private var availableBytes: Int = 0
  private let maxBufferSize: Int
  
  // Pre-calculated values for efficiency
  private let bytesPerChunk: Int
  private let chunkDuration: Double

  public init(format: AudioStreamBasicDescription, chunkDuration: Double = 0.2) {
    
    // Pre-calculate chunk parameters
    let bytesPerFrame = Int(format.mBytesPerFrame)
    let samplesPerChunk = Int(format.mSampleRate * chunkDuration)
    self.bytesPerChunk = samplesPerChunk * bytesPerFrame
    self.chunkDuration = Double(samplesPerChunk) / format.mSampleRate

    // Calculate max buffer size to hold ~10 seconds of audio, way more than the maximum we allow
    let bytesPerSecond = Int(format.mSampleRate) * bytesPerFrame
    self.maxBufferSize = bytesPerSecond * 10
    
    // Pre-allocate ring buffer
    self.buffer = Array(repeating: 0, count: maxBufferSize)
  }

  public func append(_ data: Data) {
    guard availableBytes + data.count <= maxBufferSize else {
      Logger.error("Audio buffer overflow", context: [
        "requested": String(data.count),
        "available": String(maxBufferSize - availableBytes)
      ])
      return
    }
    
    // Simple, clean, fast enough
    for byte in data {
      buffer[writeIndex] = byte
      writeIndex = (writeIndex + 1) % maxBufferSize
    }
    
    availableBytes += data.count
  }

  public func processChunks() -> [AudioPacket] {
    var packets: [AudioPacket] = []

    while let packet = nextChunk() {
      packets.append(packet)
    }

    return packets
  }

  public func flushRemaining() -> AudioPacket? {
    guard availableBytes > 0 else { return nil }

    // Create Data from remaining bytes
    var remainingData = Data(capacity: availableBytes)
    for _ in 0..<availableBytes {
      remainingData.append(buffer[readIndex])
      readIndex = (readIndex + 1) % maxBufferSize
    }
    
    availableBytes = 0

    let packet = AudioPacket(
      timestamp: Date(),
      duration: 0.0,  // Unknown duration for final chunk
      peakAmplitude: 0.0,
      rawAudioData: remainingData
    )

    return packet
  }

  private func nextChunk() -> AudioPacket? {
    // Check if we have enough data for a complete chunk
    guard availableBytes >= bytesPerChunk else { return nil }

    // Extract chunk data - bounds-checked but still efficient
    var chunkData = Data(capacity: bytesPerChunk)
    
    for _ in 0..<bytesPerChunk {
      chunkData.append(buffer[readIndex])
      readIndex = (readIndex + 1) % maxBufferSize
    }
    
    availableBytes -= bytesPerChunk

    let packet = AudioPacket(
      timestamp: Date(),
      duration: chunkDuration,
      peakAmplitude: 0.0,  // No analysis in raw mode
      rawAudioData: chunkData
    )

    return packet
  }
}
