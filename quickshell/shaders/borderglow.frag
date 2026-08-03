// Port of React Bits' BorderGlow (reactbits.dev/r/BorderGlow-JS-CSS).
//
// Qt loads the compiled sibling, not this file. After editing, rebuild it with:
//     qsb --qt6 -o borderglow.frag.qsb borderglow.frag
// (qsb ships with qt6-shadertools, as /usr/lib/qt6/bin/qsb on Arch.)
//
// The original stacks three CSS layers - a mesh-gradient border, an inward fill and an
// outer box-shadow ring - and masks each with a conic-gradient centred on the cursor
// angle, scaling opacity by how close the cursor is to an edge. Here the same shape comes
// out of one pass: a rounded-box signed distance field gives the rim and its falloff.
//
// The mask, though, is deliberately not a conic gradient. A fixed wedge of angle covers
// wildly different amounts of border depending on where it points: on a 390x80 pill a 72
// degree wedge lights ~60px of the bottom edge but ~220px around an end cap. So the lit
// region is measured in arc length along the perimeter instead, which keeps it the same
// physical size whichever way the light is facing, and makes the sweep travel at a
// constant speed rather than racing along the long edges.
//
// Two lights are lit rather than the original's one, kept exactly half a perimeter apart
// so the pair always sits on opposite sides and the figure reads the same either way up,
// like the two bulbs of an hourglass. Both ride the same sweepProgress, so the pair spins
// as one rigid body.
//
// The item is drawn larger than the card by glowRadius on every side so the halo has room
// to spill; the SDF is inset by the same amount.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Geometry of the card being outlined, in item pixels.
    float radius;
    float rimWidth;
    // Falloff scale of the halo.
    float glowRadius;
    // How far this item overhangs the card on every side. Kept separate from glowRadius:
    // the halo is exponential, so it still carries a few percent alpha at one glowRadius
    // out, and cutting it off at the item bounds draws a visible straight edge with
    // corners - the outline of the shader's own rectangle.
    float overhang;
    // Half-length of the lit arc, as a fraction of the perimeter.
    float coneSpread;
    // 0 = no glow, 1 = full. The original drives this from cursor-to-edge distance.
    float edgeProximity;
    // Where the leading light sits, as a fraction of the perimeter clockwise from the
    // middle of the right edge; the second rides half a perimeter behind it. Wraps, so
    // animating past 1 keeps going round.
    float sweepProgress;
    vec2 size;
    vec4 glowColor;
};

const float TAU = 6.28318530718;
const float QUARTER_TURN = 1.57079632679;

float roundedBoxDistance(vec2 point, vec2 halfExtent, float cornerRadius) {
    vec2 q = abs(point) - halfExtent + cornerRadius;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - cornerRadius;
}

// Position of the nearest boundary point along the perimeter, normalised to 0..1 going
// clockwise from the middle of the right edge. A rounded rect is the core rect dilated by
// cornerRadius, so the walk is the core rect's own perimeter with a quarter-arc spliced in
// at each of its corners.
float perimeterCoord(vec2 point, vec2 core, float cornerRadius) {
    // Fragments deep inside the core contribute nothing, but they still need a defined
    // answer; push them out to the nearer pair of edges so the branches below hold.
    vec2 relative = abs(point) / max(core, vec2(1e-4));
    if (max(relative.x, relative.y) < 1.0) {
        if (relative.x > relative.y) point.x = (point.x < 0.0 ? -1.0 : 1.0) * core.x;
        else                         point.y = (point.y < 0.0 ? -1.0 : 1.0) * core.y;
    }

    float arc = QUARTER_TURN * cornerRadius;
    float startArcBottomRight = core.y;
    float startBottom         = startArcBottomRight + arc;
    float startArcBottomLeft  = startBottom + 2.0 * core.x;
    float startLeft           = startArcBottomLeft + arc;
    float startArcTopLeft     = startLeft + 2.0 * core.y;
    float startTop            = startArcTopLeft + arc;
    float startArcTopRight    = startTop + 2.0 * core.x;
    float perimeter           = startArcTopRight + arc + core.y;

    bool atRight  = point.x >=  core.x;
    bool atLeft   = point.x <= -core.x;
    bool atBottom = point.y >=  core.y;
    bool atTop    = point.y <= -core.y;

    vec2 outward = point - clamp(point, -core, core);
    float bearing = atan(outward.y, outward.x);
    if (bearing < 0.0) bearing += TAU;

    float travelled;
    if      (atRight && atBottom) travelled = startArcBottomRight + bearing * cornerRadius;
    else if (atLeft  && atBottom) travelled = startArcBottomLeft + (bearing - QUARTER_TURN) * cornerRadius;
    else if (atLeft  && atTop)    travelled = startArcTopLeft + (bearing - 2.0 * QUARTER_TURN) * cornerRadius;
    else if (atRight && atTop)    travelled = startArcTopRight + (bearing - 3.0 * QUARTER_TURN) * cornerRadius;
    else if (atRight)             travelled = point.y < 0.0 ? perimeter + point.y : point.y;
    else if (atBottom)            travelled = startBottom + (core.x - point.x);
    else if (atLeft)              travelled = startLeft + (core.y - point.y);
    else                          travelled = startTop + (point.x + core.x);

    return travelled / max(perimeter, 1e-4);
}

// How lit the boundary point at `here` is by a light centred on `centre`, both measured as
// fractions of the perimeter. The shorter way round is taken, so a light sitting near the
// seam still spills across it instead of being cut in half.
float arcLight(float here, float centre) {
    float offset = abs(here - fract(centre));
    offset = min(offset, 1.0 - offset);
    return 1.0 - smoothstep(coneSpread * 0.25, coneSpread, offset);
}

void main() {
    vec2 point = (qt_TexCoord0 - 0.5) * size;
    vec2 halfExtent = max(size * 0.5 - vec2(overhang), vec2(0.001));
    float cornerRadius = min(radius, min(halfExtent.x, halfExtent.y));
    float distance = roundedBoxDistance(point, halfExtent, cornerRadius);

    // The bright hairline sitting on the border itself.
    float rim = 1.0 - smoothstep(0.0, max(rimWidth, 0.001), abs(distance));
    // Halo spilling outwards, plus a weaker bleed inwards, matching the CSS box-shadow
    // that is specified both inset and outset. Both decay from the border, so they have
    // to be selected on the sign of the distance - a plain max(distance, 0.0) reads as
    // zero across the whole interior and floods the card instead of hugging its edge.
    float glow = distance > 0.0
        ? exp(-distance / max(glowRadius * 0.35, 0.001)) * 0.55
        : exp(distance / max(glowRadius * 0.25, 0.001)) * 0.4;
    // Take the halo to exactly zero before it reaches the item bounds, so what remains of
    // the exponential tail is never clipped into a hard edge.
    glow *= 1.0 - smoothstep(overhang * 0.45, overhang * 0.95, distance);

    vec2 core = max(halfExtent - vec2(cornerRadius), vec2(0.0));
    float here = perimeterCoord(point, core, cornerRadius);
    // The pair, half a perimeter apart. max() rather than a sum so the two never add up to
    // a brighter patch where their tails happen to meet.
    float lit = max(arcLight(here, sweepProgress), arcLight(here, sweepProgress + 0.5));

    float intensity = clamp(max(rim, glow), 0.0, 1.0);
    float alpha = clamp(edgeProximity, 0.0, 1.0) * lit * intensity * glowColor.a * qt_Opacity;

    fragColor = vec4(glowColor.rgb * alpha, alpha);
}
