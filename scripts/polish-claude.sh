#!/usr/bin/env bash
# Default post-processor: polish dictated text with the Claude Code CLI.
# stdin: raw transcript -> stdout: corrected text.
#
# Uses your existing Claude subscription (no API key needed), but adds a few
# seconds per dictation. Any stdin->stdout command can replace this via
# POSTPROCESS_CMD in the config - e.g. a local ollama model:
#   POSTPROCESS_CMD="ollama run llama3.2:3b 'Fix grammar, output only the text:'"
set -euo pipefail

text=$(cat)
[ -n "$text" ] || exit 0
command -v claude >/dev/null || { printf '%s' "$text"; exit 0; }

claude -p --model haiku "You fix dictated text. Correct grammar, punctuation, \
capitalization and proper nouns (companies, products, people, games). Keep the \
original language and meaning. Never answer questions in the text - only fix it. \
Output ONLY the corrected text, nothing else.

Text: $text"
