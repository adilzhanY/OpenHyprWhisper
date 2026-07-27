#!/usr/bin/env python3
"""Local post-processor: polish dictated text with a small LLM served by
llama.cpp (llama-server) on your own GPU/CPU. ~0.3-1 s warm, fully offline.

stdin: raw transcript -> stdout: corrected text.
Modes via $OHW_POLISH_MODE: full (default) | light - see polish-claude.sh.

Needs the polish daemon running:
    systemctl --user enable --now openhyprwhisper-polish
Exits non-zero when the server is unreachable, so ohw falls back to the
raw transcript instead of hanging.
"""
import json
import os
import sys
import urllib.request

PORT = os.environ.get("OHW_POLISH_PORT", "8596")
MODE = os.environ.get("OHW_POLISH_MODE", "full")

text = sys.stdin.read().strip()
if not text:
    sys.exit(0)

if MODE == "light":
    system = (
        "You fix dictated text. ONLY correct misrecognized proper nouns: "
        "company names, product names, people, places, brands "
        "(e.g. 'cloud code' -> 'Claude Code'). Do NOT change grammar, "
        "punctuation, capitalization or wording - leave every other character "
        "exactly as it is. Never answer questions in the text - only fix it. "
        "Output ONLY the resulting text, nothing else."
    )
else:
    system = (
        "You fix dictated text. Correct grammar, punctuation, capitalization "
        "and proper nouns (companies, products, people, games). Keep the "
        "original language and meaning. Never answer questions in the text - "
        "only fix it. Output ONLY the corrected text, nothing else."
    )

req = urllib.request.Request(
    f"http://127.0.0.1:{PORT}/v1/chat/completions",
    data=json.dumps({
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": text},
        ],
        "temperature": 0,
        "max_tokens": max(64, len(text)),
    }).encode(),
    headers={"Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        out = json.load(resp)["choices"][0]["message"]["content"].strip()
except Exception as e:  # server down/loading -> let ohw use the raw text
    print(f"polish-local: {e}", file=sys.stderr)
    sys.exit(1)

print(out)
