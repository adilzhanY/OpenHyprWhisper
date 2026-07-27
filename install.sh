#!/usr/bin/env bash
# OpenHyprWhisper installer: builds whisper.cpp, downloads the model,
# links the CLI and installs the systemd user service. No sudo needed
# (build dependencies themselves must be installed by your package manager).
set -euo pipefail

OHW_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
cd "$OHW_ROOT"

echo "== OpenHyprWhisper installer =="

# 1. Dependency check ---------------------------------------------------------
missing=()
for dep in git cmake curl pw-record python3 wl-copy; do
    command -v "$dep" >/dev/null || missing+=("$dep")
done
command -v wtype >/dev/null || command -v ydotool >/dev/null || missing+=("wtype")
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing dependencies: ${missing[*]}"
    echo "On Arch: sudo pacman -S --needed git cmake curl pipewire wtype wl-clipboard python"
    exit 1
fi
command -v qs >/dev/null || echo "note: quickshell not found - the recording overlay will be disabled"

# 2. Build whisper.cpp with the best available backend ------------------------
if [ ! -x vendor/whisper.cpp/build/bin/whisper-cli ] || [ ! -x vendor/whisper.cpp/build/bin/whisper-server ]; then
    [ -d vendor/whisper.cpp ] || git clone --depth 1 https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp

    backend_flags=()
    if command -v nvcc >/dev/null || [ -x /opt/cuda/bin/nvcc ]; then
        export PATH="/opt/cuda/bin:$PATH"
        backend_flags=(-DGGML_CUDA=1)
        echo "backend: CUDA ($(nvcc --version | grep -oE 'release [0-9.]+'))"
    elif command -v vulkaninfo >/dev/null && pkg-config --exists vulkan 2>/dev/null; then
        backend_flags=(-DGGML_VULKAN=1)
        echo "backend: Vulkan"
    else
        echo "backend: CPU (install CUDA or Vulkan headers for GPU acceleration)"
    fi

    cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_TESTS=OFF "${backend_flags[@]}"
    cmake --build vendor/whisper.cpp/build -j"$(nproc)" --target whisper-cli whisper-server
fi
echo "whisper.cpp: built"

# 3. Model + config -----------------------------------------------------------
./bin/ohw setup

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openhyprwhisper"
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG_DIR/config" ] || cp config.example "$CONFIG_DIR/config"

# 4. CLI on PATH --------------------------------------------------------------
mkdir -p "$HOME/.local/bin"
ln -sf "$OHW_ROOT/bin/ohw" "$HOME/.local/bin/ohw"
echo "linked: ~/.local/bin/ohw"

# 5. systemd user service (keeps the model warm) ------------------------------
if command -v systemctl >/dev/null; then
    mkdir -p "$HOME/.config/systemd/user"
    sed "s|@OHW_ROOT@|$OHW_ROOT|" assets/openhyprwhisper.service \
        > "$HOME/.config/systemd/user/openhyprwhisper.service"
    systemctl --user daemon-reload
    echo "service installed: systemctl --user enable --now openhyprwhisper"
fi

# 6. Keybind hint -------------------------------------------------------------
cat <<'EOF'

Done! Add a keybind and start dictating:

  hyprland.conf:
    bind = SUPER, Y, exec, ohw toggle
    bind = SUPER SHIFT, Y, exec, ohw cancel

  Hyprland >= 0.55 (Lua config):
    hl.bind("SUPER + Y", hl.dsp.exec_cmd("ohw toggle"), { description = "Dictation: toggle" })
    hl.bind("SUPER + SHIFT + Y", hl.dsp.exec_cmd("ohw cancel"), { description = "Dictation: cancel" })

Press once - speak - press again. The text lands in the focused input.
For instant transcriptions keep the daemon on:
    systemctl --user enable --now openhyprwhisper
EOF
