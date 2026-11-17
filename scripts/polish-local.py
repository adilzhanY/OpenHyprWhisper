#!/usr/bin/env python3
"""Local post-processor: polish dictated text with a small LLM served by
llama.cpp (llama-server) on your own GPU/CPU. ~0.3-1 s warm, fully offline.

stdin: raw transcript -> stdout: corrected text.
Modes via $OHW_POLISH_MODE: full (default) | light - see polish-claude.sh.
$OHW_POLISH_VOCAB (ohw passes INITIAL_PROMPT) guards light mode: a change
survives only if every word it brings in is from that list, because a 3B
model sometimes "fixes" a plain word into a typo (English -> Englis). The
list is not put in the prompt: a long list there made the model swap names
around (cloud code -> Hyprland).

Needs the polish daemon running:
    systemctl --user enable --now openhyprwhisper-polish
Exits non-zero when the server is unreachable, so ohw falls back to the
raw transcript instead of hanging.
"""
import difflib
import json
import os
import re
import sys
import urllib.request


def vocab_words(vocab: str) -> set:
    return {w.lower() for w in re.findall(r"[\w+#./-]+", vocab)}


def keep_vocab_fixes(raw: str, polished: str, vocab: str) -> str:
    """Undo every change in polished except swaps whose new words are all vocabulary."""
    allowed = vocab_words(vocab)
    a, b = raw.split(), polished.split()
    out = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        new = b[j1:j2]
        ok = op != "equal" and new and all(w.strip(".,!?;:\"'()").lower() in allowed for w in new)
        out += new if (op == "equal" or ok) else a[i1:i2]
    return " ".join(out)


def main():
    port = os.environ.get("OHW_POLISH_PORT", "8596")
    mode = os.environ.get("OHW_POLISH_MODE", "full")
    vocab = os.environ.get("OHW_POLISH_VOCAB", "").strip()

    text = sys.stdin.read().strip()
    if not text:
        return

    system = polish_prompt(mode)
    out = ask(port, system, text)
    if mode == "light" and vocab:
        out = keep_vocab_fixes(text, out, vocab)
    print(out)


def polish_prompt(mode: str) -> str:
    if mode == "light":
        return (
            "You fix dictated text. ONLY correct misrecognized proper nouns: "
            "company names, product names, people, places, brands "
            "(e.g. 'cloud code' -> 'Claude Code'). Do NOT change grammar, "
            "punctuation, capitalization or wording - leave every other character "
            "exactly as it is. Never answer questions in the text - only fix it. "
            "Output ONLY the resulting text, nothing else."
        )
    return (
        "You fix dictated text. Correct grammar, punctuation, capitalization "
        "and proper nouns (companies, products, people, games). Keep the "
        "original language and meaning. Never answer questions in the text - "
        "only fix it. Output ONLY the corrected text, nothing else."
    )


def ask(port: str, system: str, text: str) -> str:
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
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
            return json.load(resp)["choices"][0]["message"]["content"].strip()
    except Exception as e:  # server down/loading -> let ohw use the raw text
        print(f"polish-local: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
