

# OpenHyprWhisper

**Dictado de voz global para Hyprland.** Presiona una tecla, habla, presiona de nuevo: tus palabras se escriben en el campo de texto que tenga el foco. Totalmente local y privado: el audio nunca sale de tu máquina.

Inspirado en [OpenSuperWhisper](https://github.com/Starmel/OpenSuperWhisper) para macOS, reconstruido nativamente para el escritorio Hyprland/Wayland.

![recording pill](assets/screenshot.png)

## Características

- **Funciona en todas partes** — navegador, terminal, aplicaciones de chat: cualquier cosa con una entrada de texto enfocada (como espanso, pero para tu voz)
- **Rápido** — whisper.cpp con CUDA/Vulkan; con el daemon en caliente, una frase se transcribe en ~0,2 s
- **Multilingüe** — detección automática de idioma por locución, ideal para habla mixta EN/RU/DE/KK
- **Una píldora de estado elegante** — indicador de grabación animado con forma de onda en vivo, tiempo transcurrido y transiciones de estado, renderizado por Quickshell; fíjalo en un borde de la pantalla o déjalo adjuntar a la ventana enfocada para que aparezca donde estás dictando
- **Selector de micrófono e historial** — `ohw mic` selecciona el dispositivo de entrada, `ohw history` recupera transcripciones pasadas
- **Consciente del tema** — en [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) la píldora sigue tu paleta Material (clara y oscura) y fuente en tiempo real; en otros lugares usa un aspecto oscuro neutro
- **Tres capas de corrección**
  1. *Sugerencia de vocabulario* — sesga la transcripción hacia tu jerga (gratuito)
  2. *Reemplazos* — correcciones deterministas para malentendidos rebeldes como `cloud code → Claude Code` (~10 ms)
  3. *Pulido con LLM* — limpieza opcional con un backend conectable y dos modos: **full** reescribe gramática y puntuación (correos, documentos), **light** solo corrige nombres y marcas para que el texto siga sonando como tú (chat, terminal, prompts de IA). Con el backend local incluido (llama.cpp + Qwen2.5-3B) añade solo ~0,2 s
- **Filtro de silencio** — adiós a las *"Thank you."* alucinadas cuando dejas de grabar sin hablar
- **Local y privado** — sin nube, sin telemetría, sin suscripción

## Cómo funciona

```
keybind → ohw toggle ──► pw-record (16 kHz wav)      ──► pill: "● Recording…" + waveform
keybind → ohw toggle ──► whisper.cpp (CUDA)          ──► pill: "◌ Transcribing…"
                     ──► replacements + LLM polish   ──► pill: "◌ Polishing…" (optional)
                     ──► wtype into focused window   ──► pill: "✓ Done"
```

Un daemon `whisper-server` (opcional, activado por defecto) mantiene el modelo en la VRAM, por lo que la transcripción comienza al instante en lugar de recargar ~600 MB por frase.

## Requisitos

- Hyprland (cualquier compositor Wayland funciona para el núcleo; la superposición usa `wlr-layer-shell`)
- `pipewire`, `wtype` (o `ydotool`), `wl-clipboard`, `curl`, `cmake`, `git`, `python3`
- [Quickshell](https://quickshell.org) — opcional, para la píldora de grabación
- GPU NVIDIA + CUDA, o Vulkan, o un CPU decente

## Instalación

```sh
git clone https://github.com/adilzhanY/OpenHyprWhisper
cd OpenHyprWhisper
./install.sh
```

El instalador compila whisper.cpp con el mejor backend que encuentre (CUDA → Vulkan → CPU), descarga el modelo `large-v3-turbo-q5_0` (~570 MB), enlaza `ohw` en `~/.local/bin`, copia la configuración predeterminada y las reglas de reemplazo, e instala un servicio de usuario de systemd.

Luego añade los atajos. La configuración predeterminada es **mantener presionado el botón central del ratón para grabar**: presiónalo, habla, suélvalo y el texto aparecerá (push-to-talk). `SUPER+Y` funciona como un interruptor de teclado secundario:

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

> Nota: enlazar el botón central sin modificadores intercepta los clics centrales normales (pegar selección principal, cerrar pestañas del navegador, abrir enlaces en una nueva pestaña). Si usas esas funciones, enlaza un botón lateral o del pulgar en su lugar — `mouse:275` o `mouse:276` — o mantén solo el interruptor `SUPER+Y`.

Y mantén el modelo en caliente (recomendado):

```sh
systemctl --user enable --now openhyprwhisper
```

## Uso

| Comando | Acción |
|---|---|
| `ohw start` / `ohw stop` | par para mantener y hablar: enlaza a presión y liberación |
| `ohw toggle` | iniciar grabación / detener, transcribir y escribir |
| `ohw cancel` | descartar la grabación actual (también funciona durante la transcripción) |
| `ohw enable` / `ohw disable` | activar/desactivar el dictado por completo (ver abajo) |
| `ohw switch` | alternar entre ambos — enlázalo a un interruptor de la interfaz |
| `ohw enabled` | imprime `on`/`off`; sale con código 1 si está desactivado |
| `ohw daemon start\|stop\|status` | gestionar el daemon del modelo en caliente |
| `ohw mic` | elegir un micrófono de forma interactiva (o `ohw mic <node-name>`) |
| `ohw history [n]` | mostrar las últimas n transcripciones (predeterminado 20) |
| `ohw setup` | descargar el modelo, verificar dependencias |
| `ohw status` | mostrar estado, información del modelo y del daemon |

## Desactivarlo

Los daemons en caliente son la razón por la que el dictado es rápido, pero ocupan aproximadamente 3 GB de VRAM las 24 horas. Cuando no vayas a dictar durante un tiempo, desactiva todo el sistema:

```sh
ohw disable   # stops whisper-server and the polish llama-server, kills the overlay,
              # and makes the record keybind a no-op until you turn it back on
ohw enable    # everything comes back
```

El interruptor es persistente (`~/.config/openhyprwhisper/disabled`) y también alterna las unidades de systemd, por lo que una máquina apagada permanece apagada tras los reinicios.

### Interruptor rápido para end-4/dots-hyprland

[quickshell/end4](quickshell/end4) añade un botón de **Dictado por voz** a los interruptores rápidos de la barra lateral derecha, junto a Wi-Fi y Bluetooth:

```sh
II=~/.config/quickshell/ii
cp quickshell/end4/VoiceDictationToggle.qml        "$II/modules/common/models/quickToggles/"
cp quickshell/end4/AndroidVoiceDictationToggle.qml "$II/modules/ii/sidebarRight/quickToggles/androidStyle/"
```

Luego registra el tipo en dos archivos originales (se sobrescriben al actualizar dots-hyprland, así que repite esto tras una actualización):

- `modules/ii/sidebarRight/quickToggles/AndroidQuickPanel.qml` — añade `"voiceDictation"` a `availableToggleTypes`
- `modules/ii/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml` — añade un bloque `DelegateChoice { roleValue: "voiceDictation"; AndroidVoiceDictationToggle { … } }`, copiando cualquier opción vecina

Finalmente, añade el botón a tu cuadrícula: abre la barra lateral, haz clic en el lápiz (modo edición) y haz clic en **Dictado por voz**, o añade `{"size": 2, "type": "voiceDictation"}` a `sidebar.quickToggles.android.toggles` en `~/.config/illogical-impulse/config.json`.

## Configuración

**`~/.config/openhyprwhisper/config`** — ver [config.example](config.example):

| Opción | Predeterminado | Significado |
|---|---|---|
| `MODEL` | `large-v3-turbo-q5_0` | cualquier nombre de modelo ggml o ruta absoluta |
| `LANGUAGE` | `auto` | código de idioma, o detección automática por locución |
| `INJECT` | `type` | `type` / `paste` / `clipboard` |
| `OVERLAY_POSITION` | `bottom` | `bottom` / `top` (borde de la pantalla) o `window` (la píldora se adjunta a la ventana enfocada, estilo OpenSuperWhisper) |
| `HISTORY` | `true` | conservar transcripciones para `ohw history` |
| `SILENCE_PEAK` | `300` | umbral del filtro de silencio, `0` desactiva |
| `INITIAL_PROMPT` | vacío | sesgo de vocabulario: nombres, jerga, modismos |
| `POSTPROCESS` | `false` | pulido con LLM activado/desactivado |
| `POSTPROCESS_MODE` | `full` | `full` = corregir todo; `light` = solo corregir nombres, mantener tu redacción |
| `POSTPROCESS_CMD` | script incluido | cualquier comando stdin→stdout |

Cada opción también puede anularse por invocación con una variable de entorno `OHW_*`.

**`~/.config/openhyprwhisper/replacements`** — ver [replacements.example](replacements.example): una regla `mal_oído = corregido` por línea, insensible a mayúsculas/minúsculas, coincidente por límites de palabra.

### Backends de pulido con LLM

La herramienta incluye dos backends:

**Local (recomendado)** — [scripts/polish-local.py](scripts/polish-local.py) se comunica con un LLM pequeño (Qwen2.5-3B) servido por llama.cpp en tu propia GPU/CPU. El pulido en caliente tarda **~0,2 s**, es totalmente fuera de línea y funciona en cualquier idioma. Configúralo:

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

y en la configuración: `POSTPROCESS_CMD="<repo>/scripts/polish-local.py"`.

**Claude CLI (sin configuración)** — [scripts/polish-claude.sh](scripts/polish-claude.sh), el predeterminado, usa la CLI de [Claude Code](https://claude.com/claude-code): no requiere clave API ni descargas adicionales si ya usas Claude, pero cada dictado tiene un sobrecosto de ~5-8 s de CLI/nube.

Cualquier otro comando stdin→stdout también funciona (ollama, un curl a una API, un script sed).

Ejemplo de los dos modos con el mismo dictado:

> raw: `so yeah i was asking cloud code about the elden ring api and it dont work good`
> **light**: `so yeah i was asking Claude Code about the elden ring api and it dont work good`
> **full**: `So yeah, I was asking Claude Code about the Elden Ring API, and it doesn't work well.`

## Temas

La superposición lee en tiempo real:

- `~/.local/state/quickshell/user/generated/colors.json` — paleta Material 3 de end-4; cambia el fondo de pantalla o el modo claro/oscuro y la píldora se recolora al instante
- `~/.config/illogical-impulse/config.json` — `appearance.fonts.main`

La píldora respeta el espacio reservado de tu barra, por lo que nunca se superpone a ella. Las curvas de animación son expresivas de Material 3, coincidiendo con el shell de end-4. Sin end-4 usa una paleta oscura de respaldo.

## Pruebas

```sh
tests/run-tests.sh            # everything
tests/run-tests.sh unit       # text/audio processing only (runs anywhere, incl. CI)
tests/run-tests.sh integration # real pipeline: fake mic -> whisper -> clipboard
tests/run-tests.sh ui         # overlay states/positions on a live Hyprland session
```

El conjunto de pruebas se ejecuta contra una configuración/estado aislado (tu configuración real no se modifica), sintetiza su propio audio a través de un sumidero nulo de PipeWire y omite —nunca falla— las pruebas cuyo hardware no está presente.

## Licencia

MIT
