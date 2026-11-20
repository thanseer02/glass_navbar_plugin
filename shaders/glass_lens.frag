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
uniform vec4 uAccentColor;
uniform vec4 uBarTint;
uniform float uPressProgress;
uniform vec2 uTouchDotPos;
uniform float uTouchDotRadius;

uniform sampler2D uTexture;

out vec4 fragColor;

// Signed Distance Function for a rounded rectangle
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Approximate normal gradient from SDF
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

    vec4 origBg = texture(uTexture, uv);

    if (dist <= 1.5) {
        // Inside or near lens boundary
        vec2 normP = p / max(uLensHalfSize, vec2(1.0));
        float distNorm = clamp(length(normP), 0.0, 1.0);

        // Convex glass refraction: stronger distortion near edges, minimal at center
        vec2 normal = calcNormal(p, uLensHalfSize, uCornerRadius);
        float edgeFactor = smoothstep(-uCornerRadius * 1.5, 0.0, dist);
        float refractionOffsetMag = (distNorm * 0.5 + pow(edgeFactor, 2.5) * 0.5) * uRefraction * 18.0 * uPressProgress;

        // Magnification (zoom towards lens center)
        vec2 magOffset = -p * (uMagnification - 1.0) * (1.0 - pow(distNorm, 3.0) * 0.6) * uPressProgress;
        vec2 totalOffset = (magOffset - normal * refractionOffsetMag) / uResolution;

        // Chromatic aberration: sample R, G, B with slight channel divergence
        vec2 caDir = normalize(p + vec2(0.0001));
        vec2 caOffset = caDir * (uChromaticAberration * 4.0 * edgeFactor * uPressProgress) / uResolution;

        vec4 sampleR = texture(uTexture, uv + totalOffset + caOffset);
        vec4 sampleG = texture(uTexture, uv + totalOffset);
        vec4 sampleB = texture(uTexture, uv + totalOffset - caOffset);

        vec4 refractedColor = vec4(sampleR.r, sampleG.g, sampleB.b, (sampleR.a + sampleG.a + sampleB.a) / 3.0);

        // Turn content inside the lens into accent color where content exists
        float contentMask = clamp(refractedColor.a * 1.5, 0.0, 1.0);
        vec3 tintedContent = mix(refractedColor.rgb, uAccentColor.rgb, uPressProgress * 0.95);
        vec3 resultRgb = mix(refractedColor.rgb, tintedContent, contentMask);

        // Specular highlight at the rim and inner glow
        float edgeDist = abs(dist);
        float rimWidth = max(uEdgeHighlightWidth, 1.0);
        float rim = smoothstep(rimWidth, 0.0, edgeDist) * uEdgeHighlightIntensity;

        // Subtle top specular shine
        float topShine = smoothstep(4.0, 0.0, abs(dist)) * smoothstep(0.0, -1.0, normal.y) * 0.45;

        // Subtle inner glow
        float innerGlow = smoothstep(-16.0, 0.0, dist) * 0.12 * uPressProgress;

        resultRgb += vec3(rim + topShine + innerGlow);

        // Touch dot: small translucent grey circle at finger position
        if (uPressProgress > 0.01 && uTouchDotRadius > 0.0) {
            float touchDist = length(fragCoord - uTouchDotPos);
            float touchAlpha = smoothstep(uTouchDotRadius, uTouchDotRadius - 1.5, touchDist) * 0.22 * uPressProgress;
            resultRgb = mix(resultRgb, vec3(0.85), touchAlpha);
        }

        // Blend lens edge smoothly with background
        float lensAlpha = smoothstep(1.5, -0.5, dist);
        fragColor = mix(origBg, vec4(resultRgb, max(refractedColor.a, lensAlpha * 0.15)), lensAlpha);
    } else {
        fragColor = origBg;
    }
}
