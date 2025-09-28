import AudioToolbox
import CoreAudio
import Foundation

/// Microphone recorder using Audio Queue Services for independent microphone input capture
public class MicrophoneRecorder {
  private var audioQueue: AudioQueueRef?
  private var deviceID: AudioObjectID?
  private var outputHandler: AudioOutputHandler
  private var converter: AudioFormatConverter?
  private var finalFormat: AudioStreamBasicDescription!
  private var isRecording = false
  private let chunkDuration: Double
  private let convertToSampleRate: Double?

  // Audio Queue buffers
  private let numberOfBuffers = 3
  private var audioQueueBuffers: [AudioQueueBufferRef?] = []

  public init(
    outputHandler: AudioOutputHandler,
    convertToSampleRate: Double? = nil,
    chunkDuration: Double = 0.2,
    deviceUID: String? = nil
  ) {
    self.outputHandler = outputHandler
    self.convertToSampleRate = convertToSampleRate
    self.chunkDuration = chunkDuration

    // Get input device
    do {
      self.deviceID = try getInputDevice(deviceUID: deviceUID)
    } catch {
      Logger.error("Failed to get input device", context: ["error": String(describing: error)])
      self.deviceID = nil
    }
  }

  deinit {
    stopRecording()
  }

  public func startRecording() throws {
    guard let deviceID = deviceID else {
      throw AudioTeeError.setupFailed
    }

    Logger.debug("Starting microphone recording")

    // Get source format from input device
    let sourceFormat = AudioFormatManager.getDeviceFormat(deviceID: deviceID)

    // Set up conversion if requested
    if let targetSampleRate = convertToSampleRate {
      guard AudioFormatConverter.isValidSampleRate(targetSampleRate) else {
        Logger.error("Invalid sample rate for microphone", context: ["sample_rate": String(targetSampleRate)])
        throw AudioTeeError.setupFailed
      }

      do {
        let converter = try AudioFormatConverter.toSampleRate(targetSampleRate, from: sourceFormat)
        self.converter = converter
        self.finalFormat = converter.targetFormatDescription
        Logger.info("Microphone audio conversion enabled", context: ["target_sample_rate": String(targetSampleRate)])
      } catch {
        Logger.error("Failed to create microphone audio converter", context: ["error": String(describing: error)])
        throw error
      }
    } else {
      self.converter = nil
      self.finalFormat = sourceFormat
    }

    // Log format info and send metadata
    AudioFormatManager.logFormatInfo(finalFormat)
    let metadata = AudioFormatManager.createMetadata(for: finalFormat)
    outputHandler.handleMetadata(metadata)

    // Create Audio Queue for input
    try setupAudioQueue(format: sourceFormat)
    try startAudioQueue()

    isRecording = true
    Logger.info("Microphone recording started successfully")
  }

  public func stopRecording() {
    guard isRecording else { return }

    Logger.debug("Stopping microphone recording")

    if let audioQueue = audioQueue {
      AudioQueueStop(audioQueue, true)
      AudioQueueDispose(audioQueue, true)
      self.audioQueue = nil
    }

    audioQueueBuffers.removeAll()
    isRecording = false

    Logger.info("Microphone recording stopped")
  }

  private func setupAudioQueue(format: AudioStreamBasicDescription) throws {
    var format = format

    // Create input audio queue with callback
    let status = AudioQueueNewInput(
      &format,
      audioQueueInputCallback,
      Unmanaged.passUnretained(self).toOpaque(),
      nil, // Use default run loop
      CFRunLoopMode.commonModes.rawValue,
      0,   // Reserved, must be 0
      &audioQueue
    )

    guard status == noErr, let audioQueue = audioQueue else {
      Logger.error("Failed to create audio queue for microphone", context: ["status": String(status)])
      throw AudioTeeError.setupFailed
    }

    // Set up audio queue buffers
    let bufferByteSize = calculateBufferSize(format: format, duration: chunkDuration)

    for _ in 0..<numberOfBuffers {
      var buffer: AudioQueueBufferRef?
      let bufferStatus = AudioQueueAllocateBuffer(audioQueue, bufferByteSize, &buffer)

      guard bufferStatus == noErr, let buffer = buffer else {
        Logger.error("Failed to allocate audio queue buffer", context: ["status": String(bufferStatus)])
        throw AudioTeeError.setupFailed
      }

      audioQueueBuffers.append(buffer)
    }
  }

  private func startAudioQueue() throws {
    guard let audioQueue = audioQueue else {
      throw AudioTeeError.setupFailed
    }

    // Enqueue initial buffers
    for buffer in audioQueueBuffers {
      guard let buffer = buffer else { continue }
      let status = AudioQueueEnqueueBuffer(audioQueue, buffer, 0, nil)
      if status != noErr {
        Logger.error("Failed to enqueue audio buffer", context: ["status": String(status)])
        throw AudioTeeError.setupFailed
      }
    }

    // Start the audio queue
    let status = AudioQueueStart(audioQueue, nil)
    guard status == noErr else {
      Logger.error("Failed to start audio queue", context: ["status": String(status)])
      throw AudioTeeError.setupFailed
    }
  }

  private func calculateBufferSize(format: AudioStreamBasicDescription, duration: Double) -> UInt32 {
    let frameCount = UInt32(format.mSampleRate * duration)
    return frameCount * format.mBytesPerFrame
  }

  // MARK: - Audio Queue Callback

  private let audioQueueInputCallback: AudioQueueInputCallback = {
    (inUserData, inAQ, inBuffer, inStartTime, inNumberPacketDescriptions, inPacketDescs) in

    let recorder = Unmanaged<MicrophoneRecorder>.fromOpaque(inUserData!).takeUnretainedValue()
    recorder.processAudioBuffer(inBuffer)

    // Re-enqueue the buffer for continuous recording
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
  }

  private func processAudioBuffer(_ buffer: AudioQueueBufferRef) {
    let dataSize = buffer.pointee.mAudioDataByteSize
    Logger.debug("Audio callback triggered", context: ["data_size": String(dataSize)])

    guard dataSize > 0 else {
      Logger.debug("Empty audio buffer received")
      return
    }

    // Create audio data from buffer
    let audioData = Data(bytes: buffer.pointee.mAudioData, count: Int(dataSize))
    Logger.debug("Processing audio data", context: ["bytes": String(audioData.count)])

    // Create audio packet
    let packet = AudioPacket(
      timestamp: Date(),
      duration: chunkDuration,
      data: audioData
    )

    // Apply conversion if needed
    let processedPacket = converter?.transform(packet) ?? packet

    // Send to output handler - check if it supports stream packets
    if let streamHandler = outputHandler as? StreamBinaryOutputHandler {
      // Create stream packet with microphone stream ID
      let streamPacket = StreamAudioPacket(
        streamId: .microphone,
        timestamp: processedPacket.timestamp,
        duration: processedPacket.duration,
        data: processedPacket.data
      )
      streamHandler.handleStreamAudioPacket(streamPacket)
    } else {
      // Regular output handler - just send the processed packet
      outputHandler.handleAudioPacket(processedPacket)
    }
  }

  // MARK: - Device Utilities

  private func getInputDevice(deviceUID: String?) throws -> AudioObjectID {
    if let deviceUID = deviceUID {
      // Find specific device by UID
      return try getDeviceByUID(deviceUID)
    } else {
      // Get default input device
      return try getDefaultInputDevice()
    }
  }

  private func getDefaultInputDevice() throws -> AudioObjectID {
    var address = getPropertyAddress(selector: kAudioHardwarePropertyDefaultInputDevice)
    var deviceID: AudioObjectID = 0
    var size = UInt32(MemoryLayout<AudioObjectID>.size)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr && deviceID != kAudioObjectUnknown else {
      Logger.error("Failed to get default input device", context: ["status": String(status)])
      throw AudioTeeError.setupFailed
    }

    Logger.debug("Found default input device", context: ["device_id": String(deviceID)])
    return deviceID
  }

  private func getDeviceByUID(_ uid: String) throws -> AudioObjectID {
    // This would require implementing device enumeration by UID
    // For now, fall back to default input device
    Logger.warning("Device UID selection not yet implemented, using default input device")
    return try getDefaultInputDevice()
  }
}