import QtQuick

/**
 * A pair of lights that spin around the border of a rounded rect, based on the effect the
 * end-4 / illogical-impulse notification popups use when they arrive, itself ported from
 * React Bits' BorderGlow (reactbits.dev/r/BorderGlow-JS-CSS).
 *
 * The two lights are held exactly half a perimeter apart, so they always face each other
 * across the card - the hourglass figure - and spin as one.
 *
 * The web original follows the pointer: it derives an angle and an edge-proximity from the
 * cursor and lights the arc facing it. It also ships an `animated` mode that fakes a
 * pointer with a scripted sweep, which is the mode that makes sense on something nothing
 * is hovering. end-4's notifications use that mode's timings verbatim: one accelerating
 * lap that dies away on its own, sized for a card that is on screen for a few seconds.
 * The recording pill instead stays up for as long as the recording lasts, so here the
 * lights fade in once and then circle at a steady speed until they are switched off.
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
 * should show, never the arcs travelling across its face.
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
    // Half-length of each lit arc as a fraction of the perimeter. Since there are two of
    // them, 0.25 lights the whole border. Measured in arc length rather than angle, so a
    // lit patch stays the same physical size on a long edge and on an end cap.
    property real coneSpread: 0.10
    // Overall strength, 0-1. Driven by cursor distance in the original.
    property real edgeProximity: 0
    // Where the leading light sits, as a fraction of the perimeter clockwise from the
    // middle of the right edge; the other rides half a perimeter behind it. Wraps, so
    // animating past 1 keeps going round.
    property real sweepProgress: 0

    // Milliseconds for one full trip around the border. Higher is slower.
    property int sweepDuration: 8000
    // Runs the light. Clearing it leaves the glow where it stopped rather than fading it
    // out - the pill takes both of them off screen together with its own opacity.
    property bool sweeping: false

    readonly property vector2d size: Qt.vector2d(width, height)

    fragmentShader: Qt.resolvedUrl("shaders/borderglow.frag.qsb")
    blending: true
    visible: edgeProximity > 0

    // Comes up once, then holds: nothing here ever takes the light back down, so it
    // keeps going for as long as whatever it is outlining is on screen.
    NumberAnimation on edgeProximity {
        running: root.sweeping
        from: 0; to: 1; duration: 700
        easing.type: Easing.OutCubic
    }

    // Constant speed, and the shader wraps sweepProgress, so the end of one lap hands
    // over to the start of the next with no seam and no pause.
    NumberAnimation on sweepProgress {
        running: root.sweeping
        loops: Animation.Infinite
        from: 0; to: 1; duration: root.sweepDuration
    }
}
