#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform vec2 uLensCenter;
uniform vec2 uLensHalfSize;
uniform float uCornerRadius;
uniform float uMagnification;
uniform float uRefraction;
uniform float uChromaticAberration;
uniform float uEdgeHighlightWidth;
uniform float uEdgeHighlightIntensity;
uniform float uPressProgress;
uniform vec2 uTouchDotPos;
uniform float uTouchDotRadius;

// Sampler 0: Layer A = Inactive (grey) icons + labels
uniform sampler2D uInactive;
// Sampler 1: Layer B = Active (accent/red) icons + labels
uniform sampler2D uActive;

out vec4 fragColor;

// Signed Distance Function for a rounded rectangle (lens capsule)
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Precise analytical normal gradient from SDF for smooth refraction vector
vec2 calcNormal(vec2 p, vec2 b, float r) {
    float h = 1.0;
    float dx = sdRoundedBox(p + vec2(h, 0.0), b, r) - sdRoundedBox(p - vec2(h, 0.0), b, r);
    float dy = sdRoundedBox(p + vec2(0.0, h), b, r) - sdRoundedBox(p - vec2(0.0, h), b, r);
    return normalize(vec2(dx, dy));
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;

    vec2 p = fragCoord - uLensCenter;
    float dist = sdRoundedBox(p, uLensHalfSize, uCornerRadius);

    // Hard-edged SDF mask with 1px smooth anti-aliasing (strictly 0 outside, 1 inside)
    // dist < 0 inside lens, > 0 outside
    float lensMask = smoothstep(0.5, -0.5, dist) * step(0.001, uPressProgress);

    // Sample Layer A (Inactive/grey) exactly at unrefracted uv
    vec4 inactiveSample = texture(uInactive, uv);

    // Normalized distance from center to capsule boundary (0.0 at center, 1.0 at rim)
    vec2 normP = p / max(uLensHalfSize, vec2(1.0));
    float distNorm = clamp(length(normP), 0.0, 1.0);

    // Convex glass refraction: zero in center, progressive curvature towards the perimeter
    vec2 normal = calcNormal(p, uLensHalfSize, uCornerRadius);
    float edgeFactor = smoothstep(-uCornerRadius * 1.5, 0.0, dist);
    float refractionOffsetMag = (distNorm * 0.4 + pow(edgeFactor, 2.2) * 0.6) * uRefraction * 16.0 * uPressProgress;

    // Magnification (zoom inwards towards lens center)
    vec2 magOffset = -p * (uMagnification - 1.0) * (1.0 - pow(distNorm, 3.0) * 0.5) * uPressProgress;
    vec2 totalOffset = (magOffset - normal * refractionOffsetMag) / uResolution;

    // Chromatic aberration at the rim: divergence along radius/edge
    vec2 caDir = normalize(p + vec2(0.0001));
    vec2 caOffset = caDir * (uChromaticAberration * 4.5 * edgeFactor * uPressProgress) / uResolution;

    // Sample Layer B (Active/accent red) with chromatic aberration channels
    vec4 sampleR = texture(uActive, uv + totalOffset + caOffset);
    vec4 sampleG = texture(uActive, uv + totalOffset);
    vec4 sampleB = texture(uActive, uv + totalOffset - caOffset);

    // Recombined refracted Active Layer B
    vec4 refractedActive = vec4(sampleR.r, sampleG.g, sampleB.b, (sampleR.a + sampleG.a + sampleB.a) / 3.0);

    // Specular highlight at the rim & top specular shine
    float edgeDist = abs(dist);
    float rimWidth = max(uEdgeHighlightWidth, 1.0);
    float rim = smoothstep(rimWidth, 0.0, edgeDist) * uEdgeHighlightIntensity * uPressProgress;
    float topShine = smoothstep(3.5, 0.0, edgeDist) * smoothstep(0.1, -1.0, normal.y) * 0.4 * uPressProgress;
    float innerGlow = smoothstep(-uCornerRadius * 0.8, 0.0, dist) * 0.12 * uPressProgress;

    vec3 rimLight = vec3(rim + topShine + innerGlow);

    // Touch dot: translucent circle inside the lens tracking the finger
    float touchAlpha = 0.0;
    if (uTouchDotRadius > 0.0) {
        float touchDist = length(fragCoord - uTouchDotPos);
        touchAlpha = smoothstep(uTouchDotRadius, uTouchDotRadius - 1.5, touchDist) * 0.25 * uPressProgress;
    }

    // CRITICAL: STRICT REPLACEMENT
    // Outside lens: 100% inactiveSample (Layer A).
    // Inside lens: 100% refractedActive (Layer B) - Layer A contributes ZERO.
    vec4 contentColor = mix(inactiveSample, refractedActive, lensMask);

    // Add optical glass highlights and touch indicator inside lens
    vec3 finalRgb = contentColor.rgb + (rimLight * lensMask);
    if (touchAlpha > 0.0) {
        finalRgb = mix(finalRgb, vec3(0.9), touchAlpha * lensMask);
    }

    float finalAlpha = max(contentColor.a, (rim * 0.8 + touchAlpha * 0.5) * lensMask);

    fragColor = vec4(finalRgb, finalAlpha);
}
