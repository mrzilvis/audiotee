# AudioTee

AudioTee captures your Mac's system audio output and writes chunks of it to `stdout`, either in base64-encoded JSON (good for humans and easy on terminals) or binary (good for other programs). It uses the [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) API introduced in macOS 14.2 (released in December 2023). You can do whatever you want with this audio - stream it somewhere else, save it to disk, visualize it, etc.

By default, it taps the audio output from **all** running process and selects the most appropriate audio chunk output format to use based on the presence of a tty. Tap output is forced to `mono` (not configurable) and preserves your output device's sample rate unless you pass a `--convert-to` flag. Only the default output device is currently supported.

My original (and so far only) use case is streaming audio to a parent process which communicates with a realtime ASR service, so AudioTee makes some design decisions you might not agree with. Open an issue or a PR and we can talk about changing them. I'm also no Swift developer, so contributions improving codebase idioms and general hygiene are welcome.

Recording system audio is harder than it should be on macOS, and folks often wrestle with outdated advice and poorly documented APIs. It's a boring problem which stands in the way of lots of fun applications. There's more code here than you need to solve this problem yourself: the main classes of interest are probably `Core/AudioTapManager` and `Core/AudioRecorder`. Everything's wired together in `CLI/AudioTee`. The rest is just CLI configuration support, output formatting logic, and some utility functions you could probably live without.

## Requirements

- macOS 14.2 or later
- Swift 5.9 or later (no need for XCode)
- System audio recording permissions (see below)

## Quick start

```bash
git clone git@github.com:makeusabrew/audiotee.git
cd audiotee
swift run
```

## Build

```bash
# omit '-c release' to get a debug build
swift build -c release
```

## Usage

### Basic usage

Replace the path below with `.build/<arch>/<target>/audiotee`, e.g. `build/arm64-apple-macosx/release/audiotee` for a release build on Apple Silicon.

```bash
# Auto-detect output format (JSON in terminal, binary when piped)
./audiotee

# Always use JSON format (terminal-safe)
./audiotee --format json

# Always use binary format (pipe-optimised)
./audiotee --format binary
```

### Audio conversion

```bash
# Convert to 16kHz mono (useful for ASR services)
./audiotee --convert-to 16000

# Other supported sample rates: 22050, 24000, 32000, 44100, 48000
./audiotee --convert-to 44100
```

### Tap configuration

For now, only a subset of the `CATapDescription` (https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) interface is exposed. PRs welcome.

```bash
# Tap all system audio (default)
./audiotee

# Tap everything *except* a specific process (by PID)
./audiotee --processes 1234

# Tap only a specific process (by PID)
./audiotee --processes 1234 --no-exclusive

# Exclude multiple specific processes
./audiotee --processes 1234 5678 9012

# Tap multiple specific processes
./audiotee --processes 1234 5678 9012 --no-exclusive
```

```bash
# Mute processes being tapped (so they don't play through speakers)
./audiotee --mute muted

# Custom chunk duration (default 0.2 seconds, max 5.0)
./audiotee --chunk-duration 0.1
```

## Output Formats

AudioTee supports two output formats optimised for different use cases:

### JSON Format (`--format json` or auto in terminal)

JSON messages to stdout, one per line. Audio data is base64-encoded for terminal safety.

### Binary Format (`--format binary` or auto when piped)

JSON metadata lines followed by raw binary audio data. More efficient for piping to other processes.

## Protocol

### Message Types

All messages follow this envelope structure:

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "...",
  "data": { ... }
}
```

#### 1. Metadata Message

Sent once at startup to describe the audio format:

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "metadata",
  "data": {
    "sample_rate": 48000,
    "channels_per_frame": 1,
    "bits_per_channel": 32,
    "is_float": true,
    "capture_mode": "audio",
    "device_name": null,
    "device_uid": null,
    "encoding": "pcm_f32le"
  }
}
```

#### 2. Stream Start Message

Indicates audio data will follow:

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "stream_start",
  "data": null
}
```

#### 3. Audio Data Messages

**JSON format:**

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "audio",
  "data": {
    "timestamp": "2024-03-21T15:30:45.123Z",
    "duration": 0.2,
    "peak_amplitude": 0.45,
    "audio_data": "base64_encoded_raw_audio..."
  }
}
```

**Binary format:**

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "audio",
  "data": {
    "timestamp": "2024-03-21T15:30:45.123Z",
    "duration": 0.2,
    "peak_amplitude": 0.45,
    "audio_length": 9600
  }
}
```

_Followed immediately by 9600 bytes of raw binary audio data_

#### 4. Stream Stop Message

Sent when recording stops:

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "stream_stop",
  "data": null
}
```

#### 5. Log Messages

Info, error, and debug messages (useful for monitoring):

```json
{
  "timestamp": "2024-03-21T15:30:45.123Z",
  "message_type": "info",
  "data": {
    "message": "Starting AudioTee...",
    "context": { "output_format": "auto" }
  }
}
```

### Consuming Output

**JSON Format:**

1. Parse each line as JSON using the envelope structure
2. Use `metadata` message to understand the audio format
3. For `audio` messages, decode `audio_data` from base64 to get raw PCM data
4. Handle the format specified in metadata (may be converted if `--convert-to` was used)

**Binary Format:**

1. Parse JSON metadata lines using the envelope structure
2. Use `metadata` message to understand the audio format
3. For `audio` messages, read `audio_length` bytes of raw binary data after the JSON line
4. Handle the format specified in metadata (may be converted if `--convert-to` was used)

**Note**: binary is actually a mixed mode; JSON during boot, JSON packet header information preceding each binary chunk.

## Command Line Options

- `--format, -f`: Output format (`json`, `binary`, `auto`) [default: `auto`]
- `--processes`: Process IDs to tap (space-separated, empty = all processes)
- `--mute`: Mute behavior (`unmuted`, `muted`) [default: `unmuted`]
- `--exclusive/--no-exclusive`: Use exclusive mode [default: `--exclusive`]
- `--convert-to`: Convert to sample rate (8000, 16000, 22050, 24000, 32000, 44100, 48000)
- `--chunk-duration`: Audio chunk duration in seconds [default: 0.2, max: 5.0]

## Permissions

There is no provision in the code to pre-emptively check for the required `NSAudioCaptureUsageDescription` permission,
so you'll be prompted the first time AudioTee tries to record anything. If you want to probe and request permissions ahead of time, check out [AudioCap's clever TCC probing approach](https://github.com/insidegui/AudioCap/blob/main/AudioCap/ProcessTap/AudioRecordingPermission.swift).

## References

- [Apple Core Audio Taps Documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [AudioCap Implementation](https://github.com/insidegui/AudioCap)

## License

### The MIT License

Copyright (C) 2025 Nick Payne.
