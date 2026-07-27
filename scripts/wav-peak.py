#!/usr/bin/env python3
"""Print the peak 100 ms frame RMS of a 16-bit mono WAV file.

Used as a silence gate: real speech peaks well above ambient noise, so a
low peak means the recording is silence and whisper would only hallucinate
("Thank you.", "Subtitles by ...").
"""
import array
import sys
import wave

with wave.open(sys.argv[1], "rb") as w:
    rate = w.getframerate()
    frame = max(1, rate // 10)  # 100 ms
    peak = 0.0
    while True:
        data = w.readframes(frame)
        if len(data) < 4:
            break
        samples = array.array("h")
        samples.frombytes(data[: len(data) // 2 * 2])
        rms = (sum(x * x for x in samples) / len(samples)) ** 0.5
        peak = max(peak, rms)
print(int(peak))
