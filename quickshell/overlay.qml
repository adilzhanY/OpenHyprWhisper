//@ pragma UseQApplication
// OpenHyprWhisper recording overlay - a macOS-style status pill for Hyprland.
//
// Follows the end-4 / illogical-impulse theme automatically:
//   * colors from ~/.local/state/quickshell/user/generated/colors.json
//   * main font from ~/.config/illogical-impulse/config.json
//   * Material 3 expressive animation curves
// Falls back to a neutral dark palette when neither file exists.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // ------------------------------------------------------------------ state
    property string ohwState: "recording"   // recording | transcribing | polishing | done | empty | cancelled | idle
    property double startedAt: Date.now()
    property int elapsed: 0
    property var levels: Array(barCount).fill(0)
    readonly property int barCount: 16
    property bool exiting: false
    property bool shown: false
    Component.onCompleted: shown = true   // flips after Behaviors are active -> slide-in animates

    readonly property bool hasSymbols: Qt.fontFamilies().includes("Material Symbols Rounded")
    readonly property string position: Quickshell.env("OHW_OVERLAY_POSITION") || "bottom"
    readonly property bool atTop: position === "top"

    // "window" mode: attach the pill to the focused window (OpenSuperWhisper's
    // caret-anchoring, approximated with hyprctl window geometry on Wayland).
    // OHW_ANCHOR = "monitorName centerX bottomY" in monitor-local logical px.
    readonly property var anchorParts: (Quickshell.env("OHW_ANCHOR") || "").split(" ")
    readonly property bool windowMode: position === "window" && anchorParts.length === 3
    readonly property string anchorMon: windowMode ? anchorParts[0] : ""
    readonly property real anchorCx: windowMode ? parseInt(anchorParts[1]) : 0
    readonly property real anchorBy: windowMode ? parseInt(anchorParts[2]) : 0

    // ------------------------------------------------------------------ theme
    property var colors: ({})
    property string fontFamily: "sans-serif"
    // surface/on_surface track the active light/dark scheme; the dark values
    // are only a fallback for systems without an end-4 palette
    readonly property color surfaceCol: colors.surface_container_high ?? "#1c1c1e"
    readonly property color textCol: colors.on_surface ?? "#f2f2f7"
    readonly property bool pillIsDark: (surfaceCol.r * 0.299 + surfaceCol.g * 0.587 + surfaceCol.b * 0.114) < 0.5
    readonly property color errBase: colors.error ?? "#ff453a"
    readonly property color dotCol: pillIsDark
        ? Qt.rgba(Math.min(1, errBase.r * 1.35 + 0.25), errBase.g * 1.1 + 0.12, errBase.b * 1.1 + 0.12, 1)
        : errBase
    readonly property color accentCol: colors.primary ?? "#adc6ff"

    // Material 3 expressive curves (matches end-4's Appearance.qml)
    readonly property list<real> curveEnter: [0.38, 1.21, 0.22, 1.00, 1, 1]  // expressiveDefaultSpatial
    readonly property list<real> curveExit: [0.3, 0, 0.8, 0.15, 1, 1]        // emphasizedAccel
    readonly property list<real> curveStd: [0.2, 0, 0, 1, 1, 1]              // standard

    readonly property string stateDir: Quickshell.env("OHW_RUNTIME_DIR") || (Quickshell.env("XDG_RUNTIME_DIR") + "/openhyprwhisper")

    // ------------------------------------------------------------- file watch
    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.ohwState = s.state;
                if (s.state === "recording")
                    root.startedAt = s.startedAt;
            } catch (e) {}
        }
    }

    // Theme files are passed in by ohw only when they exist (env unset or
    // empty = no end-4 on this machine, use the fallback palette silently).
    // When launched directly (tests, qs -p by hand) fall back to the default
    // end-4 locations if the files are there.
    readonly property string themeColorsPath: {
        const env = Quickshell.env("OHW_THEME_COLORS");
        if (env === "") return "";   // set-but-empty: ohw says the file doesn't exist
        return env || (Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json");
    }
    readonly property string themeConfigPath: {
        const env = Quickshell.env("OHW_THEME_CONFIG");
        if (env === "") return "";
        return env || (Quickshell.env("HOME") + "/.config/illogical-impulse/config.json");
    }

    FileView {
        id: colorsFile
        path: root.themeColorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.colors = JSON.parse(text()); } catch (e) {}
        }
    }

    FileView {
        id: iiConfigFile
        path: root.themeConfigPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const f = JSON.parse(text()).appearance?.fonts?.main;
                if (f) root.fontFamily = f;
            } catch (e) {}
        }
    }

    // ------------------------------------------------------------- mic meter
    Process {
        id: meter
        command: [Quickshell.env("OHW_BIN") || (Quickshell.shellDir + "/../bin/ohw"), "meter"]
        running: root.ohwState === "recording"
        onExited: root.levels = Array(root.barCount).fill(0)
        stdout: SplitParser {
            onRead: data => {
                const v = Math.min(1, parseFloat(data));
                if (isNaN(v)) return;
                const next = root.levels.slice(1);
                // one-pole smoothing: the data rate provides the motion, no
                // per-bar Behavior animations needed
                next.push(root.levels[root.barCount - 1] * 0.3 + v * 0.7);
                root.levels = next;
            }
        }
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.ohwState === "recording"
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }

    // backstop: if ohw crashes mid-recording nothing would ever end the pill
    Timer {
        interval: 180000
        running: root.ohwState === "recording"
        onTriggered: root.beginExit()
    }

    // Auto-quit choreography: hold terminal states briefly, then slide out.
    onOhwStateChanged: {
        if (ohwState === "done") quitTimer.restart();
        else if (ohwState === "empty") { quitTimer.interval = 1400; quitTimer.restart(); }
        else if (ohwState === "cancelled" || ohwState === "idle") root.beginExit();
    }
    Timer { id: quitTimer; interval: 900; onTriggered: root.beginExit() }
    Timer { id: killTimer; interval: 260; onTriggered: Qt.quit() }
    function beginExit() { root.exiting = true; killTimer.restart(); }

    // ------------------------------------------------------------------- pill
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.windowMode ? modelData.name === root.anchorMon
                     : Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name === modelData.name
                                               : modelData === Quickshell.screens[0]

            WlrLayershell.namespace: "openhyprwhisper"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // reserve no space ourselves, but respect the bar's exclusive
            // zone so the pill lands above/below it instead of overlapping.
            // window mode positions in absolute monitor coordinates instead,
            // so there it must span the full screen and ignore zones.
            exclusionMode: root.windowMode ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: 0
            // Anchored on all four sides in every mode, so the surface covers the whole
            // usable area and the border glow's halo has room to spill around the pill
            // instead of being clipped into a straight edge by the window bounds. The
            // pill's own y carries the resting gap the margins used to provide.
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}   // fully click-through

            // 12px layer margin + 8px pill offset, as it was before the glow.
            readonly property int edgeGap: 20

            // The same light that sweeps around an end-4 notification when it arrives.
            // Declared before the pill so it paints underneath: only the halo outside the
            // pill should show, never the arc travelling across its face. It tracks the
            // pill's scale and opacity so the two enter and leave as one object.
            BorderGlow {
                id: borderGlow
                anchors.fill: pill
                anchors.margins: -borderGlow.overhang
                radius: pill.radius
                glowColor: root.accentCol
                glowRadius: 18   // the pill is 42px tall; the notification default swamps it
                scale: pill.scale
                opacity: pill.opacity
                // A notification sweeps once on arrival; the pill lives for as long as the
                // recording does, so the light keeps going round until it slides away.
                sweeping: !root.exiting
                loops: Animation.Infinite
            }

            Rectangle {
                id: pill
                x: root.windowMode
                    ? Math.max(8, Math.min(root.anchorCx - width / 2, parent.width - width - 8))
                    : (parent.width - width) / 2
                // window mode: rises out of the focused window's bottom edge
                // (like OpenSuperWhisper's caret card); otherwise slides in
                // from the nearest screen edge
                y: {
                    const hidden = root.exiting || !root.shown;
                    if (root.windowMode) {
                        const rest = Math.max(8, Math.min(root.anchorBy - height - 16, parent.height - height - 8));
                        return hidden ? rest + 28 : rest;
                    }
                    return root.atTop
                        ? (hidden ? -height - 24 : win.edgeGap)
                        : (hidden ? parent.height + 24 : parent.height - height - win.edgeGap);
                }
                opacity: (root.exiting || (root.windowMode && !root.shown)) ? 0 : 1
                width: content.implicitWidth + 40
                height: 42
                radius: height / 2
                color: root.surfaceCol
                border.width: 1
                border.color: Qt.rgba(root.textCol.r, root.textCol.g, root.textCol.b, 0.08)
                scale: (root.exiting || !root.shown) ? (root.windowMode ? 0.6 : 0.92) : 1

                Behavior on y {
                    NumberAnimation {
                        duration: root.exiting ? 240 : 500
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.exiting ? root.curveExit : root.curveEnter
                    }
                }
                Behavior on width {
                    NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveEnter }
                }
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Behavior on scale {
                    NumberAnimation {
                        duration: root.exiting ? 240 : 500
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.exiting ? root.curveExit : root.curveEnter
                    }
                }

                RowLayout {
                    id: content
                    anchors.centerIn: parent
                    spacing: 10

                    // ---------------------------------------- status indicator
                    Item {
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14

                        // expanding "beep" ring while recording
                        Rectangle {
                            id: ring
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            color: "transparent"
                            border.width: 1.5
                            border.color: root.dotCol
                            visible: root.ohwState === "recording"
                            SequentialAnimation {
                                running: ring.visible
                                loops: Animation.Infinite
                                ParallelAnimation {
                                    NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.6; duration: 1100; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: 1100; easing.type: Easing.OutCubic }
                                }
                                PauseAnimation { duration: 250 }
                            }
                        }

                        // the red dot itself, gently breathing
                        Rectangle {
                            id: dot
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            color: root.dotCol
                            visible: root.ohwState === "recording" || root.ohwState === "empty"
                            SequentialAnimation {
                                running: dot.visible && root.ohwState === "recording"
                                loops: Animation.Infinite
                                NumberAnimation { target: dot; property: "scale"; from: 1; to: 1.28; duration: 550; easing.type: Easing.InOutSine }
                                NumberAnimation { target: dot; property: "scale"; from: 1.28; to: 1; duration: 550; easing.type: Easing.InOutSine }
                            }
                        }

                        // spinner while transcribing
                        Canvas {
                            id: spinner
                            anchors.fill: parent
                            visible: root.ohwState === "transcribing" || root.ohwState === "polishing"
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.strokeStyle = root.accentCol;
                                ctx.lineWidth = 2;
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.arc(width / 2, height / 2, width / 2 - 1.5, 0, Math.PI * 1.4);
                                ctx.stroke();
                            }
                            RotationAnimation on rotation {
                                running: spinner.visible; loops: Animation.Infinite
                                from: 0; to: 360; duration: 800
                            }
                            Connections {
                                target: root
                                function onAccentColChanged() { spinner.requestPaint(); }
                            }
                        }

                        // check mark when done
                        Text {
                            anchors.centerIn: parent
                            visible: root.ohwState === "done"
                            text: root.hasSymbols ? "check_circle" : "✓"
                            font.family: root.hasSymbols ? "Material Symbols Rounded" : root.fontFamily
                            font.pixelSize: 16
                            color: root.accentCol
                            scale: visible ? 1 : 0.4
                            Behavior on scale {
                                NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: root.curveEnter }
                            }
                        }
                    }

                    // ------------------------------------------------- label
                    Text {
                        text: {
                            switch (root.ohwState) {
                            case "recording":    return "Recording…";
                            case "transcribing": return "Transcribing…";
                            case "polishing":    return "Polishing…";
                            case "done":         return "Done";
                            case "empty":        return "Nothing heard";
                            default:             return "";
                            }
                        }
                        color: root.textCol
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    // -------------------------------------------- waveform
                    Row {
                        spacing: 2.5
                        visible: root.ohwState === "recording"
                        Layout.alignment: Qt.AlignVCenter
                        Repeater {
                            model: root.barCount
                            Rectangle {
                                required property int index
                                width: 3
                                height: 3 + root.levels[index] * 15
                                radius: 1.5
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(root.textCol.r, root.textCol.g, root.textCol.b,
                                               0.35 + root.levels[index] * 0.65)
                            }
                        }
                    }

                    // ----------------------------------------------- timer
                    Text {
                        visible: root.ohwState === "recording"
                        text: {
                            const m = Math.floor(root.elapsed / 60);
                            const s = root.elapsed % 60;
                            return m + ":" + (s < 10 ? "0" : "") + s;
                        }
                        color: Qt.rgba(root.textCol.r, root.textCol.g, root.textCol.b, 0.6)
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
