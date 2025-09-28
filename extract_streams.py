#!/usr/bin/env python3
"""
Extract individual streams from AudioTee dual-stream output
"""

import struct
import sys

def extract_streams(input_file, system_output=None, mic_output=None):
    system_file = open(system_output, 'wb') if system_output else None
    mic_file = open(mic_output, 'wb') if mic_output else None

    with open(input_file, 'rb') as f:
        packet_count = {'system': 0, 'mic': 0}

        while True:
            # Read header (13 bytes total)
            header = f.read(13)
            if len(header) < 13:
                break

            # Parse header: StreamID (1), Timestamp (8), PacketSize (4)
            stream_id, timestamp_us, packet_size = struct.unpack('<BQL', header)

            # Read audio data
            audio_data = f.read(packet_size)
            if len(audio_data) < packet_size:
                break

            # Write to appropriate stream file
            if stream_id == 0 and system_file:  # System audio
                system_file.write(audio_data)
                packet_count['system'] += 1
            elif stream_id == 1 and mic_file:   # Microphone
                mic_file.write(audio_data)
                packet_count['mic'] += 1

    if system_file:
        system_file.close()
        print(f"Extracted {packet_count['system']} system audio packets to {system_output}")

    if mic_file:
        mic_file.close()
        print(f"Extracted {packet_count['mic']} microphone packets to {mic_output}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 extract_streams.py <input_file> [system_output.pcm] [mic_output.pcm]")
        sys.exit(1)

    input_file = sys.argv[1]
    system_output = sys.argv[2] if len(sys.argv) > 2 else "system_extracted.pcm"
    mic_output = sys.argv[3] if len(sys.argv) > 3 else "mic_extracted.pcm"

    extract_streams(input_file, system_output, mic_output)