#include <metal_stdlib>
using namespace metal;

enum ExperimentalFlags : uint {
    ExperimentalReactionDiffusion = 1u << 0u,
    ExperimentalFluidSwirl = 1u << 1u,
    ExperimentalAudioReactive = 1u << 2u,
    ExperimentalHighDensityParticles = 1u << 3u,
    ExperimentalTemporalTrails = 1u << 4u,
    ExperimentalMetalFX = 1u << 5u,
    ExperimentalHalfResolutionPreview = 1u << 6u
};

enum ParticlePattern : uint {
    ParticlePatternFlowWeave = 0u,
    ParticlePatternOrbitalBloom = 1u,
    ParticlePatternLissajousRibbons = 2u,
    ParticlePatternRoseMandala = 3u,
    ParticlePatternSpiralGalaxy = 4u,
    ParticlePatternVortexKnots = 5u,
    ParticlePatternTorusKnot3D = 6u,
    ParticlePatternHelixColumn3D = 7u,
    ParticlePatternSphereLattice3D = 8u,
    ParticlePatternMobiusRibbon3D = 9u
};

enum BackgroundStyle : uint {
    BackgroundStyleDeepSpace = 0u,
    BackgroundStyleMistGarden = 1u,
    BackgroundStyleSilkDawn = 2u,
    BackgroundStyleQuietOcean = 3u,
    BackgroundStyleEmberHaze = 4u
};

struct ShaderUniforms {
    float viewportWidth;
    float viewportHeight;
    float time;
    float deltaTime;

    uint frameIndex;
    uint particleCount;
    uint symmetryMode;
    uint experimentalFlags;

    uint particlePattern;
    uint mouseActive;
    uint previousParticlePattern;
    uint droneMode;

    uint backgroundStyle;
    uint previousBackgroundStyle;
    uint backgroundReservedA;
    uint backgroundReservedB;

    float flowScale;
    float flowStrength;
    float attractorStrength;
    float attractorA;

    float attractorB;
    float attractorC;
    float reactionAmount;
    float fluidVorticity;

    float particleSize;
    float trailAmount;
    float bloom;
    float hueShift;

    float audioLevel;
    float audioSensitivity;
    float timeScale;
    float kaleidoscopeSegments;

    float layerOpacity;
    float layerBlend;
    float randomSeed;
    float mutation;

    float mouseX;
    float mouseY;
    float mouseStrength;
    float mouseRadius;

    float patternBlend;
    float transitionAmount;
    float previousRandomSeed;
    float targetRandomSeed;

    float droneCameraX;
    float droneCameraY;
    float droneCameraZ;
    float droneYaw;

    float droneForwardX;
    float droneForwardY;
    float droneForwardZ;
    float dronePitch;

    float droneRightX;
    float droneRightY;
    float droneRightZ;
    float droneFov;

    float droneUpX;
    float droneUpY;
    float droneUpZ;
    float droneReserved;

    uint laserActive;
    uint laserFresh;
    uint laserSequence;
    uint laserReserved;

    float laserOriginX;
    float laserOriginY;
    float laserOriginZ;
    float laserAge;

    float laserDirectionX;
    float laserDirectionY;
    float laserDirectionZ;
    float laserRange;

    float laserRadius;
    float laserStrength;
    float laserVisual;
    float laserReservedFloat;

    float4 paletteA;
    float4 paletteB;
    float4 paletteC;
    float4 paletteD;
};

struct GPUParticle {
    float4 positionLife;
    float4 velocitySeed;
    float4 style;
};

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

struct ParticleOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float seed;
};

constant float PatternExpansion = 1.18;

float hash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float2 hash21(float p)
{
    return fract(sin(float2(p * 127.1, p * 311.7)) * 43758.5453);
}

float hash12(float2 p)
{
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash12(i);
    float b = hash12(i + float2(1.0, 0.0));
    float c = hash12(i + float2(0.0, 1.0));
    float d = hash12(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p)
{
    float value = 0.0;
    float amplitude = 0.5;
    float2 shift = float2(19.13, 47.91);
    for (int i = 0; i < 5; ++i) {
        value += amplitude * noise(p);
        p = p * 2.02 + shift;
        amplitude *= 0.5;
    }
    return value;
}

float3 paletteColor(float t, constant ShaderUniforms& uniforms)
{
    float3 a = uniforms.paletteA.rgb;
    float3 b = uniforms.paletteB.rgb;
    float3 c = uniforms.paletteC.rgb;
    float3 d = uniforms.paletteD.rgb;
    return a + b * cos(6.2831853 * (c * t + d + uniforms.hueShift));
}

float2 applySymmetry(float2 p, constant ShaderUniforms& uniforms)
{
    if (uniforms.symmetryMode == 1u) {
        p.x = abs(p.x);
        p.y = abs(p.y) * sign(sin(uniforms.time * 0.17 + p.x * 2.0));
        return p;
    }

    if (uniforms.symmetryMode == 2u || uniforms.symmetryMode == 3u) {
        float radius = length(p);
        float angle = atan2(p.y, p.x);
        float segments = max(2.0, uniforms.kaleidoscopeSegments);
        float wedge = 6.2831853 / segments;
        angle = fmod(angle + wedge * 0.5, wedge) - wedge * 0.5;
        if (uniforms.symmetryMode == 3u) {
            angle = abs(angle);
        }
        p = float2(cos(angle), sin(angle)) * radius;
    }

    return p;
}

float2 safeNormalize(float2 value)
{
    return value / max(0.001, length(value));
}

float3 safeNormalize3(float3 value)
{
    return value / max(0.001, length(value));
}

float2 forceToward(float2 p, float2 target, float strength)
{
    float2 delta = target - p;
    return delta * strength / (0.08 + dot(delta, delta));
}

float3 forceToward3(float3 p, float3 target, float strength)
{
    float3 delta = target - p;
    return delta * strength / (0.10 + dot(delta, delta));
}

float calmVignette(float2 p)
{
    return smoothstep(1.75, 0.18, length(p));
}

float starLayer(float2 uv, float scale, float threshold, float seed, constant ShaderUniforms& uniforms)
{
    float2 grid = uv * scale + float2(seed * 17.13, seed * 9.71);
    float2 cell = floor(grid);
    float2 local = fract(grid) - 0.5;
    float h = hash12(cell + float2(seed, seed * 1.7));
    float keep = step(threshold, h);
    float size = mix(0.010, 0.044, hash12(cell + float2(43.7, seed)) * hash12(cell + float2(seed, 91.3)));
    float core = exp(-dot(local, local) / max(0.00008, size * size));
    float twinkle = 0.82 + 0.18 * sin(uniforms.time * 0.45 + h * 47.0 + seed * 5.0);
    return keep * core * twinkle;
}

float shootingStar(float2 uv, float seed, constant ShaderUniforms& uniforms)
{
    float cycle = fract(uniforms.time * 0.055 + seed);
    float active = smoothstep(0.035, 0.13, cycle) * (1.0 - smoothstep(0.58, 0.76, cycle));
    float yA = mix(0.18, 0.72, hash11(seed * 31.0));
    float yB = mix(0.08, 0.56, hash11(seed * 53.0));
    float2 start = float2(-0.22, yA);
    float2 end = float2(1.24, yB);
    float2 head = mix(start, end, smoothstep(0.02, 0.74, cycle));
    float2 dir = safeNormalize(end - start);
    float2 rel = uv - head;
    float along = dot(rel, dir);
    float across = dot(rel, float2(-dir.y, dir.x));
    float tail = smoothstep(-0.52, -0.025, along) * (1.0 - smoothstep(-0.015, 0.06, along));
    float streak = exp(-abs(across) * 170.0) * tail;
    float headGlow = exp(-dot(rel, rel) * 1300.0);
    return active * (streak + headGlow * 0.55);
}

float auroraCurtain(float2 p, float seed, constant ShaderUniforms& uniforms)
{
    float drift = uniforms.time * 0.035;
    float wave = sin(p.x * 2.1 + drift + seed) * 0.18 +
                 sin(p.x * 4.7 - drift * 0.65 + seed * 2.0) * 0.055;
    float noiseBand = fbm(float2(p.x * 0.9 + seed, p.y * 0.65 - drift));
    float center = 0.28 + wave + (noiseBand - 0.5) * 0.16;
    float band = exp(-pow((p.y - center) * 2.1, 2.0));
    float curtain = pow(smoothstep(0.22, 0.92, fbm(float2(p.x * 2.3 + seed, p.y * 1.2 + drift))), 1.7);
    float upperFade = smoothstep(-0.55, 0.52, p.y) * (1.0 - smoothstep(1.10, 1.55, p.y));
    return band * curtain * upperFade;
}

float softDust(float2 uv, float scale, float threshold, float seed)
{
    float2 grid = uv * scale + float2(seed * 4.0, seed * 11.0);
    float2 cell = floor(grid);
    float2 local = fract(grid) - 0.5;
    float h = hash12(cell + float2(seed));
    float speck = exp(-dot(local, local) * 95.0);
    return step(threshold, h) * speck;
}

float3 deepSpaceBackground(float2 uv, float2 p, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float seed = sceneSeed * 0.013;
    float3 color = mix(float3(0.006, 0.009, 0.024), float3(0.025, 0.030, 0.062), uv.y);
    color += float3(0.012, 0.017, 0.038) * smoothstep(-0.95, 0.88, p.x + p.y * 0.25);

    float nebulaA = smoothstep(0.45, 0.92, fbm(p * 0.82 + float2(seed, -seed * 0.4) + float2(uniforms.time * 0.006, -uniforms.time * 0.004)));
    float nebulaB = smoothstep(0.36, 0.86, fbm(p * 1.55 + float2(-seed * 0.7, seed) + float2(-uniforms.time * 0.004, uniforms.time * 0.005)));
    color += nebulaA * float3(0.060, 0.125, 0.185) * 0.50;
    color += nebulaB * float3(0.105, 0.060, 0.155) * 0.32;

    float auroraA = auroraCurtain(p, seed + 1.7, uniforms);
    float auroraB = auroraCurtain(float2(p.x * 0.92 - 0.32, p.y - 0.22), seed + 5.3, uniforms);
    color += auroraA * float3(0.030, 0.220, 0.185) * 0.36;
    color += auroraB * float3(0.120, 0.075, 0.240) * 0.24;

    float stars = starLayer(uv, 82.0, 0.982, seed + 2.0, uniforms) * 0.38;
    stars += starLayer(uv, 156.0, 0.992, seed + 8.0, uniforms) * 0.65;
    stars += starLayer(uv, 250.0, 0.997, seed + 19.0, uniforms) * 0.55;
    color += stars * float3(0.88, 0.94, 1.0);

    float meteor = shootingStar(uv, seed * 0.11 + 0.18, uniforms) +
                   shootingStar(uv + float2(0.0, 0.19), seed * 0.07 + 0.64, uniforms) * 0.72;
    color += meteor * float3(0.36, 0.72, 1.0) * 0.42;

    float vignette = calmVignette(p);
    return color * (0.68 + vignette * 0.34);
}

float3 mistGardenBackground(float2 uv, float2 p, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float t = uniforms.time * 0.018;
    float3 color = mix(float3(0.018, 0.024, 0.026), float3(0.050, 0.068, 0.060), uv.y);
    float fogA = fbm(p * 0.92 + float2(t, -t * 0.7));
    float fogB = fbm(p * 1.85 + float2(-t * 1.4, t * 0.5) + 9.1);
    float valley = smoothstep(0.95, -0.28, abs(p.y + 0.28 + sin(p.x * 1.6) * 0.08));
    color += fogA * float3(0.040, 0.062, 0.056) * 0.36;
    color += fogB * valley * float3(0.070, 0.105, 0.086) * 0.18;
    color += softDust(uv, 120.0, 0.992, 4.0 + sceneSeed * 0.01) * float3(0.38, 0.48, 0.42) * 0.045;
    return color * (0.72 + calmVignette(p) * 0.30);
}

float3 silkDawnBackground(float2 uv, float2 p, constant ShaderUniforms& uniforms, float sceneSeed)
{
    (void)sceneSeed;
    float t = uniforms.time * 0.018;
    float3 low = float3(0.060, 0.047, 0.075);
    float3 high = float3(0.180, 0.118, 0.145);
    float3 color = mix(low, high, smoothstep(0.0, 1.0, uv.y));
    float diagonal = dot(p, safeNormalize(float2(0.86, 0.38)));
    float fold = sin(diagonal * 5.4 + fbm(p * 1.12 + t) * 2.8 + t * 2.0) * 0.5 + 0.5;
    float sheen = pow(fold, 3.0) * smoothstep(-1.12, 0.92, p.x - p.y * 0.42);
    color += sheen * float3(0.170, 0.112, 0.090) * 0.20;
    color += fbm(p * 2.6 - float2(t * 0.9, t * 0.2)) * float3(0.055, 0.050, 0.070) * 0.10;
    return color * (0.74 + calmVignette(p) * 0.28);
}

float3 quietOceanBackground(float2 uv, float2 p, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float t = uniforms.time * 0.030;
    float3 color = mix(float3(0.006, 0.023, 0.034), float3(0.020, 0.074, 0.085), uv.y);
    float swell = sin((p.y + fbm(p * 0.74 + t)) * 5.4 + t * 2.2) * 0.5 + 0.5;
    float causticA = abs(sin(p.x * 8.0 + fbm(p * 1.7 + float2(t, -t)) * 5.4));
    float causticB = abs(sin((p.x + p.y * 0.32) * 11.0 - t * 2.8));
    float caustic = pow(causticA * causticB, 5.5) * smoothstep(-0.35, 0.92, p.y);
    color += swell * float3(0.012, 0.060, 0.070) * 0.23;
    color += caustic * float3(0.115, 0.220, 0.205) * 0.16;
    color += softDust(uv, 96.0, 0.986, 8.0 + sceneSeed * 0.02) * float3(0.12, 0.36, 0.34) * 0.045;
    return color * (0.70 + calmVignette(p) * 0.32);
}

float3 emberHazeBackground(float2 uv, float2 p, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float t = uniforms.time * 0.014;
    float3 color = mix(float3(0.018, 0.014, 0.015), float3(0.055, 0.035, 0.027), uv.y);
    float smoke = fbm(p * 0.95 + float2(-t, t * 0.55));
    float smokeDetail = fbm(p * 2.1 + float2(t * 0.7, -t));
    color += smoke * float3(0.055, 0.043, 0.040) * 0.30;
    color += smoothstep(0.42, 0.88, smokeDetail) * float3(0.090, 0.044, 0.024) * 0.12;

    float2 emberCenterA = float2(-0.58 + sin(t * 1.7) * 0.10, -0.34);
    float2 emberCenterB = float2(0.52 + cos(t * 1.3) * 0.08, 0.08);
    float glow = exp(-dot(p - emberCenterA, p - emberCenterA) * 1.9) * 0.28;
    glow += exp(-dot(p - emberCenterB, p - emberCenterB) * 3.2) * 0.18;
    color += glow * float3(0.35, 0.145, 0.045);
    color += softDust(uv, 140.0, 0.994, 12.0 + sceneSeed * 0.01) * float3(1.0, 0.44, 0.16) * 0.10;
    return color * (0.70 + calmVignette(p) * 0.31);
}

float3 backgroundForStyle(uint style, float2 uv, float2 p, constant ShaderUniforms& uniforms, float sceneSeed)
{
    if (style == BackgroundStyleMistGarden) {
        return mistGardenBackground(uv, p, uniforms, sceneSeed);
    }
    if (style == BackgroundStyleSilkDawn) {
        return silkDawnBackground(uv, p, uniforms, sceneSeed);
    }
    if (style == BackgroundStyleQuietOcean) {
        return quietOceanBackground(uv, p, uniforms, sceneSeed);
    }
    if (style == BackgroundStyleEmberHaze) {
        return emberHazeBackground(uv, p, uniforms, sceneSeed);
    }
    return deepSpaceBackground(uv, p, uniforms, sceneSeed);
}

float3 rotate3DPoint(float3 p, float yaw, float pitch)
{
    float cy = cos(yaw);
    float sy = sin(yaw);
    float3 q = float3(cy * p.x + sy * p.z, p.y, -sy * p.x + cy * p.z);

    float cp = cos(pitch);
    float sp = sin(pitch);
    return float3(q.x, cp * q.y - sp * q.z, sp * q.y + cp * q.z);
}

float3 project3DPointWithSeed(float3 p, constant ShaderUniforms& uniforms, float seedOffset, float sceneSeed)
{
    float yaw = 0.62 + sin(uniforms.time * 0.10 + sceneSeed * 0.013 + seedOffset) * 0.18;
    float pitch = -0.34 + cos(uniforms.time * 0.08 + seedOffset * 1.7) * 0.12;
    float3 q = rotate3DPoint(p, yaw, pitch);
    float perspective = 1.0 / max(0.95, 1.75 - q.z * 0.48);
    return float3(q.x * perspective, q.y * perspective, q.z);
}

float3 project3DPoint(float3 p, constant ShaderUniforms& uniforms, float seedOffset)
{
    return project3DPointWithSeed(p, uniforms, seedOffset, uniforms.randomSeed);
}

float3 torusKnotShape(float u, float v)
{
    float angle = u * 6.2831853;
    float strip = (v - 0.5) * 0.10;
    float core = 0.54 + 0.18 * cos(angle * 3.0);
    return float3((core + strip * cos(angle * 5.0)) * cos(angle * 2.0),
                  sin(angle * 2.0) * 0.42 + strip * sin(angle * 4.0),
                  sin(angle * 3.0) * 0.28 + strip * cos(angle * 4.0));
}

float3 helixColumnShape(float u, float v, float phase)
{
    float height = (v * 2.0 - 1.0) * 0.82;
    float angle = u * 20.420352 + height * 1.7 + phase;
    float radius = 0.32 + 0.08 * sin(v * 25.132741 + phase);
    return float3(cos(angle) * radius, height, sin(angle) * radius);
}

float3 sphereLatticeShape(float u, float v)
{
    float band = floor(v * 14.0);
    float y = ((band + 0.5) / 14.0) * 2.0 - 1.0;
    float radius = sqrt(max(0.0, 1.0 - y * y));
    float snappedU = floor(u * 24.0) / 24.0;
    float angle = mix(u, snappedU, 0.72) * 6.2831853;
    return float3(cos(angle) * radius * 0.74, y * 0.74, sin(angle) * radius * 0.74);
}

float3 mobiusRibbonShape(float u, float v)
{
    float angle = u * 6.2831853;
    float strip = (v * 2.0 - 1.0) * 0.22;
    float ring = 0.72 + strip * cos(angle * 0.5);
    return float3(ring * cos(angle),
                  strip * sin(angle * 0.5) * 1.35,
                  ring * sin(angle));
}

float3 patternShape3DForPattern(uint pattern, float u, float v, float seed, constant ShaderUniforms& uniforms, float sceneSeed)
{
    (void)sceneSeed;
    float t = uniforms.time;
    float tau = 6.2831853;

    if (pattern == ParticlePatternOrbitalBloom) {
        float angle = u * tau;
        float petals = 8.0;
        float radius = 0.22 + 0.62 * pow(abs(cos(angle * petals)), 1.45);
        float z = sin(angle * 3.0 + seed * 0.0007 + t * 0.12) * 0.34;
        return float3(cos(angle) * radius, sin(angle) * radius, z);
    }

    if (pattern == ParticlePatternLissajousRibbons) {
        float phase = u * tau;
        float lane = (v - 0.5) * 0.16;
        return float3(sin(phase * 2.0 + lane),
                      sin(phase * 3.0 + 1.5708 + lane * 2.0),
                      cos(phase * 4.0 + lane * 3.0 + t * 0.08) * 0.42) * (0.62 + lane);
    }

    if (pattern == ParticlePatternRoseMandala) {
        float angle = u * tau;
        float petals = 7.0;
        float radius = 0.18 + 0.72 * abs(cos(angle * petals));
        float z = sin(angle * petals * 0.5 + seed * 0.0003) * 0.28;
        return float3(cos(angle) * radius, sin(angle) * radius, z);
    }

    if (pattern == ParticlePatternSpiralGalaxy) {
        float arm = floor(u * 4.0);
        float local = fract(u * 4.0);
        float radius = 0.08 + v * 1.05;
        float angle = arm * 1.5707963 + radius * 5.2 + local * 0.28 + t * 0.10;
        float z = (v - 0.5) * 0.62 + sin(angle * 1.4) * 0.08;
        return float3(cos(angle) * radius, sin(angle) * radius, z);
    }

    if (pattern == ParticlePatternVortexKnots) {
        float knot = floor(u * 4.0);
        float local = fract(u * 4.0) * tau;
        float centerAngle = knot * 1.5707963 + t * 0.12;
        float3 center = float3(cos(centerAngle) * (0.24 + knot * 0.08),
                              sin(centerAngle * 0.7) * (0.24 + knot * 0.06),
                              (knot - 1.5) * 0.20);
        float loopRadius = 0.12 + v * 0.14;
        return center + float3(cos(local) * loopRadius,
                               sin(local * 2.0) * loopRadius * 0.65,
                               sin(local) * loopRadius);
    }

    if (pattern == ParticlePatternTorusKnot3D) {
        return torusKnotShape(u, v);
    }

    if (pattern == ParticlePatternHelixColumn3D) {
        return helixColumnShape(u, v, seed * 0.0001 + t * 0.08);
    }

    if (pattern == ParticlePatternSphereLattice3D) {
        return sphereLatticeShape(u, v);
    }

    if (pattern == ParticlePatternMobiusRibbon3D) {
        return mobiusRibbonShape(u, v);
    }

    float x = (u * 2.0 - 1.0) * 1.15;
    float lane = floor(v * 5.0);
    float offset = (lane - 2.0) * 0.16;
    float y = sin(x * 4.0 + lane * 0.95 + t * 0.22) * 0.24 + offset;
    float z = sin(x * 2.2 + lane * 0.8 + t * 0.10) * 0.32;
    return float3(x, y, z);
}

float3 patternSpawnPositionForPattern3D(uint pattern, uint id, float seed, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float u = hash11(seed + float(id) * 0.131 + sceneSeed);
    float v = hash11(seed * 1.713 + float(id) * 0.071);
    return patternShape3DForPattern(pattern, u, v, seed, uniforms, sceneSeed) * PatternExpansion;
}

float2 patternSpawnPositionForPattern(uint pattern, uint id, float seed, constant ShaderUniforms& uniforms)
{
    return project3DPointWithSeed(patternSpawnPositionForPattern3D(pattern, id, seed, uniforms, uniforms.randomSeed) / PatternExpansion,
                                  uniforms,
                                  seed,
                                  uniforms.randomSeed).xy * PatternExpansion;
}

float2 patternSpawnPosition(uint id, float seed, constant ShaderUniforms& uniforms)
{
    return patternSpawnPositionForPattern(uniforms.particlePattern, id, seed, uniforms);
}

float3 patternSpawnPosition3D(uint id, float seed, constant ShaderUniforms& uniforms)
{
    return patternSpawnPositionForPattern3D(uniforms.particlePattern, id, seed, uniforms, uniforms.randomSeed);
}

float2 particlePatternForceForPattern(uint pattern, float2 p, GPUParticle particle, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float t = uniforms.time;
    float seed = particle.velocitySeed.w * 0.013 + sceneSeed * 0.001;
    float2 radial = safeNormalize(p);
    float2 tangent = float2(-radial.y, radial.x);
    float radius = length(p);

    if (pattern == ParticlePatternOrbitalBloom) {
        float petals = 5.0 + floor(fmod(uniforms.kaleidoscopeSegments, 7.0));
        float angle = atan2(p.y, p.x);
        float flowerRadius = 0.24 + 0.66 * pow(abs(cos(angle * petals - t * 0.18 + seed)), 1.45);
        float radialPull = (flowerRadius - radius) * 2.45;
        return radial * radialPull + tangent * (0.46 + 0.12 * sin(seed + t * 0.31));
    }

    if (pattern == ParticlePatternLissajousRibbons) {
        float phase = seed + hash11(particle.velocitySeed.w) * 6.2831853;
        float track = t * 0.16 + phase;
        float lane = (hash11(particle.velocitySeed.w + 4.0) - 0.5) * 0.18;
        float2 target = float2(sin(track * 2.0 + lane),
                               sin(track * 3.0 + 1.5708 + lane * 2.0)) * (0.58 + lane);
        return forceToward(p, target, 1.38) + tangent * 0.06;
    }

    if (pattern == ParticlePatternRoseMandala) {
        float angle = atan2(p.y, p.x);
        float petals = max(5.0, floor(uniforms.kaleidoscopeSegments * 0.55));
        float rose = cos(petals * angle + t * 0.12 + seed * 0.1);
        float targetRadius = 0.16 + 0.76 * abs(rose);
        float2 target = float2(cos(angle), sin(angle)) * targetRadius;
        return forceToward(p, target, 1.65) + tangent * (0.08 + 0.05 * rose);
    }

    if (pattern == ParticlePatternSpiralGalaxy) {
        float arm = floor(hash11(particle.velocitySeed.w) * 4.0);
        float armOffset = arm * 1.5707963;
        float spiralAngle = radius * 5.2 + armOffset + t * 0.13;
        float2 armDirection = float2(cos(spiralAngle), sin(spiralAngle));
        float desiredRadius = clamp(radius, 0.08, 1.05);
        float2 target = armDirection * desiredRadius;
        return forceToward(p, target, 1.12) + tangent * (0.52 / (0.34 + radius));
    }

    if (pattern == ParticlePatternVortexKnots) {
        float2 bestDelta = float2(0.0);
        float bestDistance = 1000.0;
        for (uint i = 0u; i < 4u; ++i) {
            float fi = float(i);
            float angle = t * (0.13 + fi * 0.03) + seed * 0.25 + fi * 1.5707963;
            float2 center = float2(cos(angle * 1.3 + fi), sin(angle * 0.9 - fi)) * (0.28 + 0.16 * fi);
            float2 delta = center - p;
            float d = dot(delta, delta);
            if (d < bestDistance) {
                bestDistance = d;
                bestDelta = delta;
            }
        }
        float2 knotTangent = float2(-bestDelta.y, bestDelta.x) / max(0.03, length(bestDelta));
        return bestDelta * 1.85 / (0.16 + bestDistance) + knotTangent * 0.34;
    }

    if (pattern == ParticlePatternTorusKnot3D) {
        float u = fract(hash11(particle.velocitySeed.w + 1.7) + t * 0.010);
        float v = hash11(particle.velocitySeed.w + 8.3);
        float3 projected = project3DPointWithSeed(torusKnotShape(u, v), uniforms, seed, sceneSeed);
        float2 delta = projected.xy - p;
        float2 orbit = safeNormalize(float2(-delta.y, delta.x));
        float depth = smoothstep(-0.65, 0.65, projected.z);
        return forceToward(p, projected.xy, 2.35) + orbit * (0.08 + depth * 0.10);
    }

    if (pattern == ParticlePatternHelixColumn3D) {
        float u = fract(hash11(particle.velocitySeed.w + 2.9) + t * 0.018);
        float v = hash11(particle.velocitySeed.w + 11.7);
        float phase = t * 0.16 + seed * 0.1;
        float3 projected = project3DPointWithSeed(helixColumnShape(u, v, phase), uniforms, seed + 1.0, sceneSeed);
        float3 next = project3DPointWithSeed(helixColumnShape(fract(u + 0.006), v, phase), uniforms, seed + 1.0, sceneSeed);
        float2 rail = safeNormalize(next.xy - projected.xy);
        return forceToward(p, projected.xy, 2.05) + rail * 0.16 + float2(-projected.y, projected.x) * 0.035;
    }

    if (pattern == ParticlePatternSphereLattice3D) {
        float u = fract(hash11(particle.velocitySeed.w + 4.1) + t * 0.006);
        float v = hash11(particle.velocitySeed.w + 16.9);
        float3 projected = project3DPointWithSeed(sphereLatticeShape(u, v), uniforms, seed + 2.0, sceneSeed);
        float3 next = project3DPointWithSeed(sphereLatticeShape(fract(u + 0.006), v), uniforms, seed + 2.0, sceneSeed);
        float2 track = safeNormalize(next.xy - projected.xy);
        return forceToward(p, projected.xy, 1.95) + track * 0.13 + float2(-projected.y, projected.x) * 0.04;
    }

    if (pattern == ParticlePatternMobiusRibbon3D) {
        float u = fract(hash11(particle.velocitySeed.w + 5.6) + t * 0.008);
        float v = hash11(particle.velocitySeed.w + 21.4);
        float3 projected = project3DPointWithSeed(mobiusRibbonShape(u, v), uniforms, seed + 3.0, sceneSeed);
        float3 next = project3DPointWithSeed(mobiusRibbonShape(fract(u + 0.005), v), uniforms, seed + 3.0, sceneSeed);
        float2 ribbon = safeNormalize(next.xy - projected.xy);
        float depth = smoothstep(-0.65, 0.65, projected.z);
        return forceToward(p, projected.xy, 2.18) + ribbon * (0.12 + depth * 0.06);
    }

    float lane = floor(hash11(particle.velocitySeed.w + 2.0) * 5.0);
    float targetY = sin(p.x * 4.0 + lane * 0.95 + t * 0.22 + seed * 0.1) * 0.24 + (lane - 2.0) * 0.16;
    float2 target = float2(p.x, targetY);
    return forceToward(p, target, 1.52) + float2(0.16, 0.0) + tangent * 0.04;
}

float2 particlePatternForce(float2 p, GPUParticle particle, constant ShaderUniforms& uniforms)
{
    float blend = clamp(uniforms.patternBlend, 0.0, 1.0);
    float2 patternSpacePosition = p / PatternExpansion;
    float2 previousForce = particlePatternForceForPattern(uniforms.previousParticlePattern,
                                                          patternSpacePosition,
                                                          particle,
                                                          uniforms,
                                                          uniforms.previousRandomSeed);
    float2 currentForce = particlePatternForceForPattern(uniforms.particlePattern,
                                                         patternSpacePosition,
                                                         particle,
                                                         uniforms,
                                                         uniforms.randomSeed);
    return mix(previousForce, currentForce, blend) * PatternExpansion;
}

float particleDepthCueForPattern(uint pattern, GPUParticle particle, constant ShaderUniforms& uniforms, float sceneSeed)
{
    float t = uniforms.time;
    float seed = particle.velocitySeed.w * 0.013 + sceneSeed * 0.001;

    if (pattern == ParticlePatternTorusKnot3D) {
        float u = fract(hash11(particle.velocitySeed.w + 1.7) + t * 0.010);
        float v = hash11(particle.velocitySeed.w + 8.3);
        return smoothstep(-0.65, 0.65, project3DPointWithSeed(torusKnotShape(u, v), uniforms, seed, sceneSeed).z);
    }

    if (pattern == ParticlePatternHelixColumn3D) {
        float u = fract(hash11(particle.velocitySeed.w + 2.9) + t * 0.018);
        float v = hash11(particle.velocitySeed.w + 11.7);
        return smoothstep(-0.65, 0.65, project3DPointWithSeed(helixColumnShape(u, v, t * 0.16 + seed * 0.1), uniforms, seed + 1.0, sceneSeed).z);
    }

    if (pattern == ParticlePatternSphereLattice3D) {
        float u = fract(hash11(particle.velocitySeed.w + 4.1) + t * 0.006);
        float v = hash11(particle.velocitySeed.w + 16.9);
        return smoothstep(-0.65, 0.65, project3DPointWithSeed(sphereLatticeShape(u, v), uniforms, seed + 2.0, sceneSeed).z);
    }

    if (pattern == ParticlePatternMobiusRibbon3D) {
        float u = fract(hash11(particle.velocitySeed.w + 5.6) + t * 0.008);
        float v = hash11(particle.velocitySeed.w + 21.4);
        return smoothstep(-0.65, 0.65, project3DPointWithSeed(mobiusRibbonShape(u, v), uniforms, seed + 3.0, sceneSeed).z);
    }

    return 0.5;
}

float particleDepthCue(GPUParticle particle, constant ShaderUniforms& uniforms)
{
    float blend = clamp(uniforms.patternBlend, 0.0, 1.0);
    float previousDepth = particleDepthCueForPattern(uniforms.previousParticlePattern,
                                                     particle,
                                                     uniforms,
                                                     uniforms.previousRandomSeed);
    float currentDepth = particleDepthCueForPattern(uniforms.particlePattern,
                                                    particle,
                                                    uniforms,
                                                    uniforms.randomSeed);
    return mix(previousDepth, currentDepth, blend);
}

float2 mouseForce(float2 p, constant ShaderUniforms& uniforms)
{
    if (uniforms.mouseActive == 0u || uniforms.mouseStrength <= 0.001) {
        return float2(0.0);
    }

    float2 mouse = float2(uniforms.mouseX, uniforms.mouseY);
    float2 delta = p - mouse;
    float distanceSquared = dot(delta, delta);
    float radius = max(0.08, uniforms.mouseRadius);
    float influence = exp(-distanceSquared / (radius * radius)) * uniforms.mouseStrength;
    float2 away = safeNormalize(delta);
    float2 swirl = float2(-away.y, away.x);
    return away * influence * 1.25 + swirl * influence * 0.72;
}

vertex FullscreenOut fullscreenVertex(uint vertexID [[vertex_id]])
{
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    FullscreenOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 compositionFragment(FullscreenOut in [[stage_in]],
                                    constant ShaderUniforms& uniforms [[buffer(0)]])
{
    float2 uv = in.uv;
    float aspect = uniforms.viewportWidth / max(1.0, uniforms.viewportHeight);
    float2 p = (uv * 2.0 - 1.0) * float2(aspect, 1.0);
    float transition = clamp(uniforms.transitionAmount, 0.0, 1.0);
    float3 previousBackground = backgroundForStyle(uniforms.previousBackgroundStyle, uv, p, uniforms, uniforms.previousRandomSeed);
    float3 currentBackground = backgroundForStyle(uniforms.backgroundStyle, uv, p, uniforms, uniforms.randomSeed);
    float3 color = mix(previousBackground, currentBackground, transition);

    float slowTime = uniforms.time * 0.08;
    float2 ambienceP = p * (0.62 + uniforms.flowScale * 0.045) + float2(slowTime, -slowTime * 0.7);
    float ambience = smoothstep(0.35, 0.92, fbm(ambienceP));
    float3 paletteTint = mix(uniforms.paletteA.rgb, uniforms.paletteB.rgb, 0.32 + uniforms.layerBlend * 0.28);
    color += paletteTint * ambience * uniforms.layerOpacity * 0.018;

    float vignette = calmVignette(p);
    color *= 0.88 + vignette * 0.12;

    if (uniforms.droneMode != 0u) {
        float2 centered = uv - 0.5;
        float reticle = exp(-abs(length(centered) - 0.030) * 220.0);
        reticle += exp(-abs(centered.x) * 360.0) * smoothstep(0.055, 0.020, abs(centered.y));
        reticle += exp(-abs(centered.y) * 360.0) * smoothstep(0.055, 0.020, abs(centered.x));
        color += reticle * float3(0.08, 0.55, 0.95) * 0.22;

        float laser = clamp(uniforms.laserVisual, 0.0, 1.0);
        if (uniforms.laserActive != 0u && laser > 0.001) {
            float beamCore = exp(-abs(centered.x) * 210.0) * smoothstep(0.58, 0.02, abs(centered.y));
            float beamGlow = exp(-abs(centered.x) * 34.0) * smoothstep(0.56, 0.00, abs(centered.y));
            float muzzle = exp(-dot(centered, centered) * 920.0);
            color += laser * (beamCore * float3(0.35, 0.96, 1.25) + beamGlow * float3(0.12, 0.32, 0.95) + muzzle * float3(1.0, 0.22, 0.88));
        }
    }

    color = pow(max(color, float3(0.0)), float3(0.82));
    return float4(color, 1.0);
}

kernel void updateParticles(device GPUParticle *particles [[buffer(0)]],
                            constant ShaderUniforms& uniforms [[buffer(1)]],
                            device atomic_uint *laserHits [[buffer(2)]],
                            uint id [[thread_position_in_grid]])
{
    if (id >= uniforms.particleCount) {
        return;
    }

    GPUParticle particle = particles[id];
    float dt = clamp(uniforms.deltaTime, 0.0, 1.0 / 20.0);
    float3 p = particle.positionLife.xyz;
    float3 velocity = particle.velocitySeed.xyz;
    float seed = particle.velocitySeed.w;
    float2 p2 = p.xy;
    float t = uniforms.time;

    float local = fbm(p2 * uniforms.flowScale + seed * 0.001 + float2(t * 0.12, -t * 0.08));
    float angle = local * 12.56637 + uniforms.attractorStrength * atan2(p2.y, p2.x);
    float2 flow = float2(cos(angle), sin(angle)) * uniforms.flowStrength;

    float2 attractor = float2(
        sin(uniforms.attractorA * p2.y * 3.0 + t * 0.7 + seed),
        cos(uniforms.attractorB * p2.x * 3.0 - t * 0.6 + seed * 0.71)
    );

    float2 tangent = float2(-p2.y, p2.x) / max(0.12, length(p2));
    float fluid = ((uniforms.experimentalFlags & ExperimentalFluidSwirl) != 0u) ? uniforms.fluidVorticity : 0.08;
    float audioKick = ((uniforms.experimentalFlags & ExperimentalAudioReactive) != 0u) ? smoothstep(0.02, 0.45, min(uniforms.audioLevel, 0.45)) : 0.0;
    float blend = clamp(uniforms.patternBlend, 0.0, 1.0);
    float3 previousTarget = patternShape3DForPattern(uniforms.previousParticlePattern,
                                                     particle.style.z,
                                                     particle.style.w,
                                                     seed,
                                                     uniforms,
                                                     uniforms.previousRandomSeed) * PatternExpansion;
    float3 currentTarget = patternShape3DForPattern(uniforms.particlePattern,
                                                    particle.style.z,
                                                    particle.style.w,
                                                    seed,
                                                    uniforms,
                                                    uniforms.randomSeed) * PatternExpansion;
    float3 target = mix(previousTarget, currentTarget, blend);
    float3 pattern = forceToward3(p, target, uniforms.droneMode != 0u ? 1.85 : 1.52);
    float2 cursor = uniforms.droneMode != 0u ? float2(0.0) : mouseForce(p2, uniforms);
    float3 radial = safeNormalize3(p + float3(0.001));
    float3 orbit = safeNormalize3(cross(radial, float3(0.0, 1.0, 0.0)) + float3(tangent * 0.35, 0.0));
    float3 acceleration = float3(flow * 0.10 +
                                 attractor * uniforms.attractorStrength * 0.055 +
                                 tangent * fluid * 0.12 +
                                 cursor,
                                 sin(local * 6.2831853 + seed) * 0.035);
    acceleration += pattern * 1.30 + orbit * (0.06 + fluid * 0.07);
    acceleration += radial * (audioKick * 0.16);

    if (uniforms.laserFresh != 0u && uniforms.droneMode != 0u) {
        float3 laserOrigin = float3(uniforms.laserOriginX, uniforms.laserOriginY, uniforms.laserOriginZ);
        float3 laserDirection = safeNormalize3(float3(uniforms.laserDirectionX, uniforms.laserDirectionY, uniforms.laserDirectionZ));
        float3 toParticle = p - laserOrigin;
        float along = dot(toParticle, laserDirection);
        float3 closest = toParticle - laserDirection * along;
        float distanceToBeam = length(closest);
        float radius = max(0.025, uniforms.laserRadius);
        float inRange = step(0.04, along) * step(along, uniforms.laserRange);
        float core = smoothstep(radius, radius * 0.18, distanceToBeam) * inRange;
        if (core > 0.001) {
            float3 scatter = safeNormalize3(closest + laserDirection * 0.18 +
                                            (hash21(seed + float(uniforms.laserSequence)).xyx - 0.5) * 0.18);
            velocity += scatter * (uniforms.laserStrength * core * (0.22 + hash11(seed + 3.0) * 0.28));
            acceleration += scatter * (uniforms.laserStrength * core);
            particle.style.x = fract(0.52 + core * 0.18 + hash11(seed + 7.0) * 0.12);
            particle.positionLife.w = max(particle.positionLife.w, 0.72 + core * 0.35);
            atomic_fetch_add_explicit(laserHits, 1u, memory_order_relaxed);
        }
    }

    velocity = velocity * (0.935 - uniforms.trailAmount * 0.01) + acceleration * dt;
    float speed = length(velocity);
    if (speed > 1.12) {
        velocity = velocity / speed * 1.12;
    }
    p += velocity * dt;
    particle.positionLife.w -= dt * (0.045 + hash11(seed) * 0.075);
    float cursorGlow = uniforms.mouseActive == 0u ? 0.0 : exp(-dot(p.xy - float2(uniforms.mouseX, uniforms.mouseY), p.xy - float2(uniforms.mouseX, uniforms.mouseY)) / 0.18) * uniforms.mouseStrength;
    particle.style.x = fract(particle.style.x + dt * (0.035 + audioKick * 0.012 + cursorGlow * 0.08));

    if (length(p) > 2.65 || particle.positionLife.w <= 0.0) {
        p = patternSpawnPosition3D(id, seed + float(uniforms.frameIndex) * 0.013, uniforms);
        float3 restartTangent = safeNormalize3(cross(safeNormalize3(p + float3(0.001)), float3(0.0, 1.0, 0.0)) + float3(0.08, 0.0, 0.0));
        velocity = restartTangent * (0.025 + 0.04 * hash11(seed + 9.0));
        particle.positionLife.w = 0.55 + hash11(seed + float(uniforms.frameIndex)) * 0.95;
        seed += 17.31;
        particle.velocitySeed.w = seed;
        particle.style.x = hash11(seed);
    }

    particle.positionLife.xyz = p;
    particle.velocitySeed.xyz = velocity;
    particles[id] = particle;
}

vertex ParticleOut particleVertex(device const GPUParticle *particles [[buffer(0)]],
                                  constant ShaderUniforms& uniforms [[buffer(1)]],
                                  uint vertexID [[vertex_id]])
{
    GPUParticle particle = particles[vertexID];
    float aspect = uniforms.viewportWidth / max(1.0, uniforms.viewportHeight);
    float3 worldPosition = particle.positionLife.xyz;
    float2 p;
    float2 clip;
    float depthCue = 0.5;
    float visibility = 1.0;
    float perspectiveSize = 1.0;

    if (uniforms.droneMode != 0u) {
        float3 camera = float3(uniforms.droneCameraX, uniforms.droneCameraY, uniforms.droneCameraZ);
        float3 forward = safeNormalize3(float3(uniforms.droneForwardX, uniforms.droneForwardY, uniforms.droneForwardZ));
        float3 right = safeNormalize3(float3(uniforms.droneRightX, uniforms.droneRightY, uniforms.droneRightZ));
        float3 up = safeNormalize3(float3(uniforms.droneUpX, uniforms.droneUpY, uniforms.droneUpZ));
        float3 relative = worldPosition - camera;
        float viewZ = dot(relative, forward);
        float viewX = dot(relative, right);
        float viewY = dot(relative, up);
        float nearFade = smoothstep(0.04, 0.22, viewZ);
        float farFade = smoothstep(7.5, 2.2, viewZ);
        visibility = nearFade * farFade;
        float f = 1.0 / tan(max(0.35, uniforms.droneFov) * 0.5);
        float safeZ = max(0.05, viewZ);
        clip = float2((viewX * f) / (safeZ * max(0.01, aspect)), (viewY * f) / safeZ);
        if (viewZ <= 0.04 || abs(clip.x) > 1.35 || abs(clip.y) > 1.35) {
            visibility = 0.0;
        }
        p = clip * float2(aspect, 1.0);
        depthCue = clamp(1.0 - viewZ / 6.2, 0.0, 1.0);
        perspectiveSize = clamp(1.65 / safeZ, 0.22, 4.8);
    } else {
        float3 projected = project3DPoint(worldPosition / PatternExpansion, uniforms, particle.velocitySeed.w * 0.001) * float3(PatternExpansion, PatternExpansion, 1.0);
        p = applySymmetry(projected.xy, uniforms);
        clip = float2(p.x / max(0.01, aspect), p.y);
        depthCue = smoothstep(-0.72, 0.72, projected.z);
    }

    ParticleOut out;
    out.position = float4(clip, 0.0, 1.0);
    float audioSize = smoothstep(0.02, 0.45, min(uniforms.audioLevel, 0.45));
    float cursorPulse = 0.0;
    if (uniforms.mouseActive != 0u) {
        float2 mouseDelta = p - float2(uniforms.mouseX, uniforms.mouseY);
            cursorPulse = exp(-dot(mouseDelta, mouseDelta) / 0.075) * uniforms.mouseStrength;
    }
    float depthSize = mix(0.76, 1.24, depthCue);
    out.pointSize = max(0.0, uniforms.particleSize * particle.style.y * depthSize * perspectiveSize * visibility * (1.0 + audioSize * 0.35 + cursorPulse * 0.95));
    float intensity = smoothstep(0.0, 1.0, particle.positionLife.w) * (0.58 + uniforms.bloom * 0.65) * mix(0.76, 1.24, depthCue) * visibility;
    float3 color = paletteColor(particle.style.x + uniforms.hueShift, uniforms) * intensity;
    color *= mix(0.78, 1.22, depthCue);
    if (uniforms.laserActive != 0u && uniforms.droneMode != 0u && uniforms.laserVisual > 0.001) {
        float3 laserOrigin = float3(uniforms.laserOriginX, uniforms.laserOriginY, uniforms.laserOriginZ);
        float3 laserDirection = safeNormalize3(float3(uniforms.laserDirectionX, uniforms.laserDirectionY, uniforms.laserDirectionZ));
        float3 toParticle = worldPosition - laserOrigin;
        float along = dot(toParticle, laserDirection);
        float beamDistance = length(toParticle - laserDirection * along);
        float beamGlow = smoothstep(uniforms.laserRadius * 3.6, 0.0, beamDistance) *
                         step(0.0, along) *
                         step(along, uniforms.laserRange) *
                         uniforms.laserVisual;
        color += beamGlow * float3(0.25, 0.92, 1.35);
        out.pointSize += beamGlow * 2.8;
    }
    color = mix(color, uniforms.paletteD.rgb * (intensity + 0.55), cursorPulse * 0.35);
    out.color = float4(color, (0.45 + intensity * 0.32 + cursorPulse * 0.22) * mix(0.86, 1.14, depthCue));
    out.color.a *= visibility;
    out.seed = particle.velocitySeed.w;
    return out;
}

fragment float4 particleFragment(ParticleOut in [[stage_in]],
                                 float2 pointCoord [[point_coord]],
                                 constant ShaderUniforms& uniforms [[buffer(0)]])
{
    float2 centered = pointCoord * 2.0 - 1.0;
    float d = dot(centered, centered);
    float alpha = smoothstep(1.0, 0.05, d);
    float rim = exp(-d * (3.0 + uniforms.bloom * 3.5));
    float3 color = in.color.rgb * (rim + alpha * 0.65);
    return float4(color, in.color.a * alpha);
}

fragment float4 presentFragment(FullscreenOut in [[stage_in]],
                                texture2d<float> sourceTexture [[texture(0)]])
{
    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);
    return sourceTexture.sample(linearSampler, float2(in.uv.x, 1.0 - in.uv.y));
}
