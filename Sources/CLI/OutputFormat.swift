enum OutputFormat: String, CaseIterable {
  case json = "json"
  case binary = "binary"
  case auto = "auto"

  var description: String {
    switch self {
    case .json:
      return "Base64-encoded JSON (terminal-safe)"
    case .binary:
      return "Binary with JSON headers (pipe-optimised)"
    case .auto:
      return "Auto-detect based on TTY (default)"
    }
  }
}
