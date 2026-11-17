#!/usr/bin/env python3
"""Parakeet TDT speech-to-text server that answers like whisper-server.

`ohw` talks to it exactly as it talks to whisper-server: GET /health, and
POST /inference with a multipart "file" (16 kHz mono wav), answered with the
plain text. Fields whisper-server knows (language, prompt, temperature) are
accepted and ignored: Parakeet detects the language itself and takes no prompt.

Run with the Python of a venv that has torch, transformers and soundfile:
    python parakeet-server.py --model /path/to/parakeet-ultra --port 8595
"""
import argparse
import email.parser
import email.policy
import io
import sys
import warnings
from http.server import BaseHTTPRequestHandler, HTTPServer

import numpy as np
import soundfile as sf
import torch
from transformers import AutoProcessor, ParakeetForTDT

MAX_BODY = 64 * 1024 * 1024  # a 120 s wav is under 4 MB; refuse anything absurd

ap = argparse.ArgumentParser()
ap.add_argument("--model", required=True, help="local folder with config, weights and processor_config.json")
ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--port", type=int, default=8595)
args = ap.parse_args()

device = "cuda" if torch.cuda.is_available() else "cpu"
proc = AutoProcessor.from_pretrained(args.model)
model = ParakeetForTDT.from_pretrained(args.model).to(device).eval()
# The default length cap already scales with the audio; the advice to set max_new_tokens is noise
warnings.filterwarnings("ignore", message=".*max_length.*")


def run(audio) -> str:
    inputs = proc(audio, sampling_rate=16000, return_tensors="pt").to(device)
    with torch.inference_mode():
        out = model.generate(**inputs)
    seq = out.sequences if hasattr(out, "sequences") else out
    return proc.batch_decode(seq, skip_special_tokens=True)[0].strip()


def transcribe(wav_bytes: bytes) -> str:
    audio, sr = sf.read(io.BytesIO(wav_bytes), dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        raise ValueError(f"expected 16 kHz audio, got {sr} Hz")
    return run(audio)


run(np.zeros(16000, dtype="float32"))  # warm the CUDA kernels so the first dictation is not the slow one
print(f"parakeet-server: {args.model} on {device}, port {args.port}", file=sys.stderr, flush=True)


def wav_from_multipart(content_type: str, body: bytes) -> bytes:
    msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + body
    )
    for part in msg.iter_parts():
        if part.get_param("name", header="content-disposition") == "file":
            return part.get_payload(decode=True)
    raise ValueError("no 'file' field in the form")


class Handler(BaseHTTPRequestHandler):
    def reply(self, code: int, text: str):
        data = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, '{"status":"ok"}')
        else:
            self.reply(404, "not found")

    def do_POST(self):
        if self.path != "/inference":
            return self.reply(404, "not found")
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= MAX_BODY:
            return self.reply(413, "bad body size")
        try:
            wav = wav_from_multipart(self.headers.get("Content-Type", ""), self.rfile.read(length))
            self.reply(200, transcribe(wav) + "\n")
        except Exception as e:  # one bad request must not kill the warm server
            print(f"parakeet-server: {e!r}", file=sys.stderr, flush=True)
            self.reply(500, str(e))

    def log_message(self, *_):  # keep the journal quiet; errors are printed above
        pass


HTTPServer((args.host, args.port), Handler).serve_forever()
