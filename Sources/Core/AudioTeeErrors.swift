import Foundation

// MARK: - Core AudioTee Errors

public enum AudioTeeError: Error {
  case setupFailed
  case tapCreationFailed(OSStatus)
  case aggregateDeviceCreationFailed(OSStatus)
  case tapAssignmentFailed(OSStatus)
  case pidTranslationFailed([Int32])
  case bufferOverflow(requested: Int, available: Int)
}

// MARK: - Audio Format Conversion Errors

public enum AudioConverterError: Error {
  case invalidFormat
  case creationFailed
}
