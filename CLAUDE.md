# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AudioTee is a Swift CLI tool that captures macOS system audio using Core Audio taps and optionally microphone input, streaming raw PCM audio data to stdout. It supports dual parallel recording with stream identification headers. It's designed to be executed as a child process by host programs that need access to system audio and/or microphone input, with the original use case being streaming audio to real-time ASR services.

## Build and Development Commands

```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Run directly
swift run

# Run with arguments
swift run audiotee --sample-rate 16000 --stereo

# Run with microphone input
swift run audiotee --microphone --mic-sample-rate 16000

# Run microphone only (no system audio)
swift run audiotee --microphone --no-system-audio

# Clean build artifacts
swift package clean
```

The built executable will be located at `.build/<arch>/<target>/audiotee` (e.g., `.build/arm64-apple-macosx/release/audiotee`).

## Core Architecture

### Key Components

- **Sources/main.swift**: Entry point - imports and calls `AudioTee.main()`
- **Sources/CLI/AudioTee.swift**: Main application logic, argument parsing, and dual recording orchestration
- **Sources/Core/AudioTapManager.swift**: Manages Core Audio tap creation and aggregate device setup
- **Sources/Core/AudioRecorder.swift**: Handles audio recording from the aggregate device (system audio)
- **Sources/Core/MicrophoneRecorder.swift**: Handles microphone input using Audio Queue Services
- **Sources/Core/AudioFormatConverter.swift**: Converts between audio formats and sample rates
- **Sources/Core/StreamIdentifier.swift**: Defines stream IDs and binary header format for multi-stream output

### Audio Pipeline

**System Audio Path (Core Audio Taps):**
1. **Tap Creation**: `AudioTapManager` creates a system audio tap using `CATapDescription` and `AudioHardwareCreateProcessTap`
2. **Aggregate Device**: Creates an aggregate device and assigns the tap to it using `AudioHardwareCreateAggregateDevice`
3. **Recording**: `AudioRecorder` records from the aggregate device using Audio Unit I/O procedures

**Microphone Path (Audio Queue Services):**
1. **Device Selection**: `MicrophoneRecorder` gets default input device or user-specified device
2. **Audio Queue Setup**: Creates `AudioQueueRef` for input recording with callback-based processing
3. **Recording**: Continuous recording via audio queue buffers and callback function

**Common Processing:**
4. **Format Conversion**: Optional conversion to different sample rates (8kHz-48kHz) with automatic 16-bit conversion
5. **Stream Identification**: Binary headers tag each audio packet with stream ID (0=system, 1=microphone)
6. **Output**: Raw PCM data or stream-tagged data to stdout, logs to stderr

### Process Filtering

- `--include-processes`: Only tap specified PIDs (empty = all processes)
- `--exclude-processes`: Tap all except specified PIDs
- Process IDs are translated to Core Audio objects via `translatePIDsToProcessObjects`

### Audio Formats

- **Default**: Preserves device sample rate and 32-bit float depth
- **With conversion**: 16-bit signed integers at specified sample rate
- **Channels**: Mono by default, stereo with `--stereo` flag (system audio only)
- **Output Modes**:
  - **Legacy**: Raw PCM data to stdout (default for system-only recording)
  - **Stream Headers**: Binary packets with format `[StreamID:1byte][Timestamp:8bytes][PacketSize:4bytes][AudioData]`
- **Chunk Duration**: 200ms default, configurable per stream

### Microphone Recording Options

- `--microphone`: Enable microphone as separate stream (auto-enables stream headers)
- `--mic-sample-rate`: Independent sample rate for microphone (different from system audio)
- `--mic-device`: Specify input device UID (defaults to system default microphone)
- `--no-system-audio`: Record only microphone input (disable system audio tap)
- `--stream-headers`: Explicitly enable binary stream identification headers

## Platform Requirements

- macOS 14.2+ (uses Core Audio taps API)
- Swift 5.9+
- Audio recording permissions (`NSAudioCaptureUsageDescription`)

## Important Implementation Notes

- All audio data goes to stdout, all logs/metadata to stderr
- Graceful shutdown on SIGINT/SIGTERM via CFRunLoop
- Error handling for PID translation failures and permission issues
- No provision for pre-emptive permission checking - users are prompted on first run
- Sample rate conversion automatically reduces bit depth from 32-bit float to 16-bit signed