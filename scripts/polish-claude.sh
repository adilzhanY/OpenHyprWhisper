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

claude -p --model haiku "$instruction

Text: $text"
