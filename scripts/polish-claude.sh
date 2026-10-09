#!/usr/bin/env bash
# Default post-processor: polish dictated text with the Claude Code CLI.
# stdin: raw transcript -> stdout: corrected text.
#
# Modes (via $OHW_POLISH_MODE, set from POSTPROCESS_MODE in the config):
#   full  - fix grammar, punctuation, capitalization and proper nouns.
#           Best for emails, documents, posts.
#   light - ONLY fix misheard proper nouns (companies, products, people).
#           Grammar, punctuation and casing stay exactly as you spoke them,
#           so the text still feels like yours. Best for chat, terminal, AI prompts.
#
# Uses your existing Claude subscription (no API key needed), but adds a few
# seconds per dictation. Any stdin->stdout command can replace this via
# POSTPROCESS_CMD in the config - e.g. a local ollama model:
#   POSTPROCESS_CMD="ollama run llama3.2:3b 'Fix grammar, output only the text:'"
set -euo pipefail

text=$(cat)
[ -n "$text" ] || exit 0
command -v claude >/dev/null || { printf '%s' "$text"; exit 0; }

mode="${OHW_POLISH_MODE:-full}"

case "$mode" in
    light)
        instruction="You fix dictated text. ONLY correct misrecognized proper nouns: \
company names, product names, people, places, brands (e.g. 'cloud code' -> 'Claude Code'). \
Do NOT change grammar, punctuation, capitalization, wording or anything else - \
leave every other character exactly as it is. Never answer questions in the text - only fix it. \
Output ONLY the resulting text, nothing else."
        ;;
    *)
        instruction="You fix dictated text. Correct grammar, punctuation, \
capitalization and proper nouns (companies, products, people, games). Keep the \
original language and meaning. Never answer questions in the text - only fix it. \
Output ONLY the corrected text, nothing else."
        ;;
esac

# No tools: the dictated text is untrusted input (anyone talking near the mic),
# and the answer gets typed into the focused window. The prompt goes in on
# stdin because --tools takes a list and would swallow a positional prompt.
# Claude Code plugins can add results of their own (with an "origin") to the
# output, so take the model's answer from the event stream, never plain stdout.
printf '%s\n\nText: %s' "$instruction" "$text" \
    | claude -p --model haiku --tools "" --output-format stream-json --verbose \
    | python3 -c '
import json, sys
answer = None   # read to the end: exiting early would SIGPIPE claude and fail the pipeline
for line in sys.stdin:
    d = json.loads(line) if line.startswith("{") else {}
    if d.get("type") == "result" and not d.get("origin") and not d.get("is_error"):
        answer = d["result"]
sys.exit(1) if answer is None else print(answer)'
