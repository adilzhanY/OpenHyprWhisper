#!/usr/bin/env python3
"""Read s16le mono PCM from stdin, print a normalized RMS level per frame.

Used by the Quickshell overlay to draw the live waveform while recording.
Output: one float per line in [0, 1], ~30 lines/second.
"""
import array
import sys

RATE = 8000
FPS = 30
CHUNK = (RATE // FPS) * 2        # bytes per frame, always sample-aligned
NOISE_FLOOR = 250                # ignore ambient hiss
CEIL = 12000                     # RMS value mapped to 1.0

buf = sys.stdin.buffer
out = sys.stdout
try:
    while True:
        data = b""
        while len(data) < CHUNK:            # pipes may return short reads
            part = buf.read(CHUNK - len(data))
            if not part:
                sys.exit(0)
            data += part
        samples = array.array("h")
        samples.frombytes(data)
        rms = (sum(x * x for x in samples) / len(samples)) ** 0.5
        level = max(0.0, min(1.0, (rms - NOISE_FLOOR) / (CEIL - NOISE_FLOOR)))
        out.write(f"{level:.3f}\n")
        out.flush()
except BrokenPipeError:
    pass
