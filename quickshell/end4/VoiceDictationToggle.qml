// OpenHyprWhisper on/off model for end-4/dots-hyprland quick toggles.
// Install to: ~/.config/quickshell/ii/modules/common/models/quickToggles/
//
// Off means off: `ohw disable` stops the whisper and polish daemons and frees
// their VRAM, so nothing of ours stays resident while you are not dictating.
import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io

QuickToggleModel {
    id: root
    name: Translation.tr("Voice dictation")
    icon: "record_voice_over"
    tooltipText: Translation.tr("OpenHyprWhisper - loads the speech models only while on")

    // Nothing to toggle until `ohw` is on PATH
    available: false
    toggled: false

    mainAction: () => {
        if (!root.available) return;
        root.toggled = !root.toggled;
        switchProc.command = ["bash", "-lc", root.toggled ? "ohw enable" : "ohw disable"];
        switchProc.running = true;
    }

    // A login shell so ~/.local/bin is on PATH regardless of how the shell started
    property Process switchProc: Process {
        onExited: stateProc.running = true // trust the switch, not the optimistic guess
    }

    property Process stateProc: Process {
        running: true
        command: ["bash", "-lc", "command -v ohw >/dev/null && ohw enabled"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const out = stateCollector.text.trim();
                root.available = (out === "on" || out === "off");
                root.toggled = (out === "on");
            }
        }
    }

    // Cheap re-check so an `ohw enable/disable` from the terminal shows up here
    property Timer refresh: Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: if (!switchProc.running) stateProc.running = true
    }
}
