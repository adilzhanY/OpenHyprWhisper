# OpenHyprWhisper

**System-wide voice dictation for Hyprland.** Press a key, speak, press again — your words are typed into whatever text field is focused. Fully local and private: audio never leaves your machine.

Inspired by [OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) for macOS, rebuilt natively for the Hyprland/Wayland desktop.

![recording pill](assets/screenshot.png)

## Features

- **Works everywhere** — browser, terminal, chat apps: anything with a focused text input (like espanso, but for your voice)
- **Fast** — whisper.cpp with CUDA/Vulkan; with the warm daemon a sentence transcribes in ~0.2 s
- **Multilingual** — auto language detection per utterance, great for mixed EN/RU/DE/KK speech
- **A pretty status pill** — animated recording indicator with a live waveform, elapsed time and state transitions, rendered by Quickshell at the bottom (or top) of the screen
- **Theme-aware** — on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) the pill follows your Material palette (light and dark) and font live; falls back to a neutral dark look elsewhere
- **Three correction layers**
  1. *Vocabulary prompt* — bias transcription toward your jargon (free)
  2. *Replacements* — deterministic fixes for stubborn mishearings like `cloud code → Claude Code` (~10 ms)
  3. *LLM polish* — optional cleanup with a pluggable backend and two modes: **full** rewrites grammar and punctuation (emails, documents), **light** only fixes names and brands so the text still sounds like you (chat, terminal, AI prompts). With the bundled local backend (llama.cpp + Qwen2.5-3B) it adds only ~0.2 s
- **Silence gate** — no more hallucinated *"Thank you."* when you stop without speaking
- **Local & private** — no cloud, no telemetry, no subscription

## How it works

```
keybind → ohw toggle ──► pw-record (16 kHz wav)      ──► pill: "● Recording…" + waveform
keybind → ohw toggle ──► whisper.cpp (CUDA)          ──► pill: "◌ Transcribing…"
                     ──► replacements + LLM polish   ──► pill: "◌ Polishing…" (optional)
                     ──► wtype into focused window   ──► pill: "✓ Done"
```

A `whisper-server` daemon (optional, on by default) keeps the model in VRAM, so transcription starts instantly instead of reloading ~600 MB per phrase.

## Requirements

- Hyprland (any Wayland compositor works for the core; the overlay uses `wlr-layer-shell`)
- `pipewire`, `wtype` (or `ydotool`), `wl-clipboard`, `curl`, `cmake`, `git`, `python3`
- [Quickshell](https://quickshell.org) — optional, for the recording pill
- NVIDIA GPU + CUDA, or Vulkan, or a decent CPU

## Install

```sh
git clone https://github.com/adilzhanY/OpenHyprWhisper
cd OpenHyprWhisper
./install.sh
```

The installer builds whisper.cpp with the best backend it finds (CUDA → Vulkan → CPU), downloads the `large-v3-turbo-q5_0` model (~570 MB), links `ohw` into `~/.local/bin`, copies the default config and replacement rules, and installs a systemd user service.

Then add keybinds. The default setup is **hold the middle mouse button to record** — press it, speak, release it, and the text appears (push-to-talk). `SUPER+Y` works as a secondary keyboard toggle:

```ini
# hyprland.conf
# primary: hold middle mouse button (press = record, release = transcribe & type)
bind = , mouse:274, exec, ohw start
bindr = , mouse:274, exec, ohw stop
# secondary: keyboard toggle
bind = SUPER, Y, exec, ohw toggle
bind = SUPER SHIFT, Y, exec, ohw cancel
```

```lua
-- Hyprland >= 0.55 Lua config
-- primary: hold middle mouse button
hl.bind("mouse:274", hl.dsp.exec_cmd("ohw start"), { description = "Dictation: hold to record" })
hl.bind("mouse:274", hl.dsp.exec_cmd("ohw stop"), { release = true })
-- secondary: keyboard toggle
hl.bind("SUPER + Y", hl.dsp.exec_cmd("ohw toggle"), { description = "Dictation: toggle" })
hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd("ohw cancel"), { description = "Dictation: cancel" })
```

> Note: binding the bare middle button consumes normal middle-clicks (primary-selection paste, closing browser tabs, opening links in a new tab). If you use those, bind a side/thumb button instead — `mouse:275` or `mouse:276` — or keep only the `SUPER+Y` toggle.

And keep the model warm (recommended):

```sh
systemctl --user enable --now openhyprwhisper
```

## Usage

| Command | Action |
|---|---|
| `ohw start` / `ohw stop` | hold-to-talk pair: bind to press and release |
| `ohw toggle` | start recording / stop, transcribe and type |
| `ohw cancel` | discard the current recording (works mid-transcription too) |
| `ohw daemon start\|stop\|status` | manage the warm-model daemon |
| `ohw setup` | download the model, check dependencies |
| `ohw status` | show state, model and daemon info |

## Configuration

**`~/.config/openhyprwhisper/config`** — see [config.example](config.example):

| Option | Default | Meaning |
|---|---|---|
| `MODEL` | `large-v3-turbo-q5_0` | any ggml model name or absolute path |
| `LANGUAGE` | `auto` | language code, or auto-detect per utterance |
| `INJECT` | `type` | `type` / `paste` / `clipboard` |
| `OVERLAY_POSITION` | `bottom` | `bottom` or `top` |
| `SILENCE_PEAK` | `300` | silence gate threshold, `0` disables |
| `INITIAL_PROMPT` | empty | vocabulary bias: names, jargon, slang |
| `POSTPROCESS` | `false` | LLM polish on/off |
| `POSTPROCESS_MODE` | `full` | `full` = fix everything; `light` = only fix names, keep your wording |
| `POSTPROCESS_CMD` | bundled script | any stdin→stdout command |

Every option can also be overridden per invocation with an `OHW_*` environment variable.

**`~/.config/openhyprwhisper/replacements`** — see [replacements.example](replacements.example): one `misheard = corrected` rule per line, case-insensitive, word-boundary matched.

### LLM polish backends

Two backends ship with the tool:

**Local (recommended)** — [scripts/polish-local.py](scripts/polish-local.py) talks to a small LLM (Qwen2.5-3B) served by llama.cpp on your own GPU/CPU. Warm polish takes **~0.2 s**, fully offline, works in any language. Set it up:

```sh
# build llama.cpp next to whisper.cpp (CUDA/Vulkan auto-detected like the main build)
cmake -S vendor/llama.cpp -B vendor/llama.cpp/build -DGGML_CUDA=1 -DCMAKE_BUILD_TYPE=Release
cmake --build vendor/llama.cpp/build -j --target llama-server
# download the model (~1.9 GB)
curl -L -o ~/.local/share/openhyprwhisper/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf \
  https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf
# rerun ./install.sh to install the daemon, then:
systemctl --user enable --now openhyprwhisper-polish
```

and in the config: `POSTPROCESS_CMD="<repo>/scripts/polish-local.py"`.

**Claude CLI (zero setup)** — [scripts/polish-claude.sh](scripts/polish-claude.sh), the default, uses the [Claude Code](https://claude.com/claude-code) CLI: no API key or extra downloads if you already use Claude, but each dictation pays ~5-8 s of CLI/cloud overhead.

Any other stdin→stdout command works too (ollama, an API curl, a sed script).

Example of the two modes on the same dictation:

> raw: `so yeah i was asking cloud code about the elden ring api and it dont work good`
> **light**: `so yeah i was asking Claude Code about the elden ring api and it dont work good`
> **full**: `So yeah, I was asking Claude Code about the Elden Ring API, and it doesn't work well.`

## Theming

The overlay reads, live:

- `~/.local/state/quickshell/user/generated/colors.json` — end-4's Material 3 palette; switch wallpaper or light/dark mode and the pill recolors instantly
- `~/.config/illogical-impulse/config.json` — `appearance.fonts.main`

The pill respects your bar's reserved space, so it never overlaps it. Animation curves are Material 3 expressive, matching end-4's shell. Without end-4 it uses a dark fallback palette.

## License

MIT
