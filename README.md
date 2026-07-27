# OpenHyprWhisper

**System-wide voice dictation for Hyprland.** Press a key, speak, press again — your words are typed into whatever text field is focused. Fully local and private: audio never leaves your machine.

Inspired by [OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) for macOS, rebuilt natively for the Hyprland/Wayland desktop.

![recording pill](assets/screenshot.png)

## Features

- **Works everywhere** — browser, terminal, chat apps: anything with a focused text input (like espanso, but for your voice)
- **Fast** — whisper.cpp with CUDA/Vulkan; with the warm daemon a sentence transcribes in ~0.2 s
- **A pretty status pill** — animated recording indicator with live waveform, elapsed time and state transitions, rendered by Quickshell
- **Theme-aware** — on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) the pill follows your Material palette and font live; falls back to a neutral dark look elsewhere
- **Multilingual** — auto language detection per utterance (great for mixed EN/RU/DE/KK speech)
- **Optional LLM polish** — fix grammar, punctuation and proper nouns after transcription (`POSTPROCESS="true"`); pluggable backend, defaults to the Claude Code CLI, works with local models too
- **Replacements** — deterministic corrections for words the model consistently mishears
- **Local & private** — no cloud, no telemetry, no subscription

## How it works

```
keybind → ohw toggle ──► pw-record (16 kHz wav)      ──► overlay pill: "● Recording…"
keybind → ohw toggle ──► whisper.cpp (CUDA)          ──► overlay pill: "◌ Transcribing…"
                     ──► wtype into focused window   ──► overlay pill: "✓ Done"
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

The installer builds whisper.cpp with the best backend it finds (CUDA → Vulkan → CPU), downloads the `large-v3-turbo-q5_0` model (~570 MB), links `ohw` into `~/.local/bin` and installs a systemd user service.

Then add keybinds:

```ini
# hyprland.conf
bind = SUPER, Y, exec, ohw toggle
bind = SUPER SHIFT, Y, exec, ohw cancel
```

```lua
-- Hyprland >= 0.55 Lua config
hl.bind("SUPER + Y", hl.dsp.exec_cmd("ohw toggle"), { description = "Dictation: toggle" })
hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd("ohw cancel"), { description = "Dictation: cancel" })
```

And keep the model warm (recommended):

```sh
systemctl --user enable --now openhyprwhisper
```

## Usage

| Command | Action |
|---|---|
| `ohw toggle` | start recording / stop, transcribe and type |
| `ohw cancel` | discard the current recording |
| `ohw daemon start\|stop\|status` | manage the warm-model daemon |
| `ohw setup` | download the model, check dependencies |
| `ohw status` | show state, model and daemon info |

## Configuration

`~/.config/openhyprwhisper/config` (see [config.example](config.example)):
model, language (`auto` by default), inject mode (`type` / `paste` / `clipboard`),
trailing space, daemon port, audio source, max recording length, vocabulary prompt.

`~/.config/openhyprwhisper/replacements` (see [replacements.example](replacements.example)):
deterministic fixes for words the model consistently mishears, e.g.
`cloud code = Claude Code`. Case-insensitive, word-boundary matched.

## Theming

The overlay reads, live:

- `~/.local/state/quickshell/user/generated/colors.json` — end-4's Material 3 palette (switch wallpaper → the pill recolors)
- `~/.config/illogical-impulse/config.json` — `appearance.fonts.main`

Without end-4 it uses a dark macOS-like pill. Animation curves are Material 3 expressive, matching end-4's shell.

## License

MIT
