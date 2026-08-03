import QtQuick

/**
 * Glowing border that sweeps around a rounded rect - the same effect the end-4 /
 * illogical-impulse notification popups use when they arrive, ported from React Bits'
 * BorderGlow (reactbits.dev/r/BorderGlow-JS-CSS).
 *
 * The web original follows the pointer: it derives an angle and an edge-proximity from the
 * cursor and lights the arc facing it. It also ships an `animated` mode that fakes a
 * pointer with a scripted sweep, which is the mode that makes sense on something nothing
 * is hovering. The timings below are that mode's, verbatim.
 *
 * Place it over the item being outlined, expanded by overhang on every side:
 *
 *     BorderGlow {
 *         id: glow
 *         anchors.fill: card
 *         anchors.margins: -glow.overhang
 *         radius: card.radius
 *     }
 *
 * Declare it before the card so it paints underneath: only the halo outside the card
 * should show, never the arc travelling across its face.
 */
ShaderEffect {
    id: root

    // Corner radius of the outlined card, not of this (larger) item.
    property real radius: 0
    property color glowColor: "white"
    // Thickness of the bright hairline on the border.
    property real rimWidth: 1.5
    // Falloff scale of the halo past the border.
    property real glowRadius: 26
    // How far this item must overhang the card. Larger than glowRadius because the halo
    // is exponential and still carries a few percent alpha one glowRadius out; anchor the
    // item with `anchors.margins: -overhang` or its rectangle becomes visible.
    property real overhang: glowRadius * 2
    // Half-length of the lit arc as a fraction of the perimeter. 0.5 lights the whole
    // border. Measured in arc length rather than angle, so the lit patch stays the same
    // physical size on a long edge and on an end cap.
    property real coneSpread: 0.10
    // Overall strength, 0-1. Driven by cursor distance in the original.
    property real edgeProximity: 0
    // Where the light sits, as a fraction of the perimeter clockwise from the middle of
    // the right edge. Wraps, so animating past 1 keeps going round.
    property real sweepProgress: 0.306

    // Runs the sweep. Restart it to play the effect again.
    property alias sweeping: sweep.running
    // A notification plays the sweep once on arrival; something long-lived like the
    // recording pill sets Animation.Infinite so the light keeps going round.
    property alias loops: sweep.loops

    readonly property vector2d size: Qt.vector2d(width, height)

    fragmentShader: Qt.resolvedUrl("shaders/borderglow.frag.qsb")
    blending: true
    visible: edgeProximity > 0

    SequentialAnimation {
        id: sweep

        // The light comes up, travels a bit over a full turn - slow to start, coasting
        // through the second half - then dies away while it is still moving.
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "edgeProximity"
                from: 0; to: 1; duration: 500
                easing.type: Easing.OutCubic
            }
            // The original's 110deg -> 465deg, expressed as fractions of the perimeter.
            SequentialAnimation {
                NumberAnimation {
                    target: root; property: "sweepProgress"
                    from: 0.306; to: 0.799; duration: 1500
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: root; property: "sweepProgress"
                    to: 1.292; duration: 2250
                    easing.type: Easing.OutCubic
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 2500 }
                NumberAnimation {
                    target: root; property: "edgeProximity"
                    to: 0; duration: 1500
                    easing.type: Easing.InCubic
                }
            }
        }
    }
}
