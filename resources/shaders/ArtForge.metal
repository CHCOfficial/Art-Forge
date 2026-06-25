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
    uint reservedB;

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
    float reservedFloatA;
    float reservedFloatB;

    float4 paletteA;
    float4 paletteB;
    float4 paletteC;
    float4 paletteD;
};

struct GPUParticle {
    float2 position;
    float2 velocity;
    float life;
    float seed;
    float hue;
    float size;
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

float2 forceToward(float2 p, float2 target, float strength)
{
    float2 delta = target - p;
    return delta * strength / (0.08 + dot(delta, delta));
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

float3 project3DPoint(float3 p, constant ShaderUniforms& uniforms, float seedOffset)
{
    float yaw = 0.62 + sin(uniforms.time * 0.10 + uniforms.randomSeed * 0.013 + seedOffset) * 0.18;
    float pitch = -0.34 + cos(uniforms.time * 0.08 + seedOffset * 1.7) * 0.12;
    float3 q = rotate3DPoint(p, yaw, pitch);
    float perspective = 1.0 / max(0.95, 1.75 - q.z * 0.48);
    return float3(q.x * perspective, q.y * perspective, q.z);
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

float2 patternSpawnPositionForPattern(uint pattern, uint id, float seed, constant ShaderUniforms& uniforms)
{
    float u = hash11(seed + float(id) * 0.131 + uniforms.randomSeed);
    float v = hash11(seed * 1.713 + float(id) * 0.071);
    float t = uniforms.time;
    float tau = 6.2831853;

    if (pattern == ParticlePatternOrbitalBloom) {
        float angle = u * tau;
        float petals = 8.0;
        float radius = 0.22 + 0.62 * pow(abs(cos(angle * petals)), 1.45);
        return float2(cos(angle), sin(angle)) * radius;
    }

    if (pattern == ParticlePatternLissajousRibbons) {
        float phase = u * tau;
        float lane = (v - 0.5) * 0.16;
        return float2(sin(phase * 2.0 + lane),
                      sin(phase * 3.0 + 1.5708 + lane * 2.0)) * (0.62 + lane);
    }

    if (pattern == ParticlePatternRoseMandala) {
        float angle = u * tau;
        float petals = 7.0;
        float radius = 0.18 + 0.72 * abs(cos(angle * petals));
        return float2(cos(angle), sin(angle)) * radius;
    }

    if (pattern == ParticlePatternSpiralGalaxy) {
        float arm = floor(u * 4.0);
        float local = fract(u * 4.0);
        float radius = 0.08 + v * 1.05;
        float angle = arm * 1.5707963 + radius * 5.2 + local * 0.28 + t * 0.10;
        return float2(cos(angle), sin(angle)) * radius;
    }

    if (pattern == ParticlePatternVortexKnots) {
        float knot = floor(u * 4.0);
        float local = fract(u * 4.0) * tau;
        float centerAngle = knot * 1.5707963 + t * 0.12;
        float2 center = float2(cos(centerAngle) * (0.24 + knot * 0.08),
                              sin(centerAngle * 0.7) * (0.24 + knot * 0.06));
        float loopRadius = 0.12 + v * 0.14;
        return center + float2(cos(local) * loopRadius, sin(local * 2.0) * loopRadius * 0.65);
    }

    if (pattern == ParticlePatternTorusKnot3D) {
        return project3DPoint(torusKnotShape(u, v), uniforms, seed).xy;
    }

    if (pattern == ParticlePatternHelixColumn3D) {
        return project3DPoint(helixColumnShape(u, v, seed * 0.0001), uniforms, seed + 1.0).xy;
    }

    if (pattern == ParticlePatternSphereLattice3D) {
        return project3DPoint(sphereLatticeShape(u, v), uniforms, seed + 2.0).xy;
    }

    if (pattern == ParticlePatternMobiusRibbon3D) {
        return project3DPoint(mobiusRibbonShape(u, v), uniforms, seed + 3.0).xy;
    }

    float x = (u * 2.0 - 1.0) * 1.15;
    float lane = floor(v * 5.0);
    float offset = (lane - 2.0) * 0.16;
    float y = sin(x * 4.0 + lane * 0.95 + t * 0.22) * 0.24 + offset;
    return float2(x, y);
}

float2 patternSpawnPosition(uint id, float seed, constant ShaderUniforms& uniforms)
{
    return patternSpawnPositionForPattern(uniforms.particlePattern, id, seed, uniforms) * PatternExpansion;
}

float2 particlePatternForceForPattern(uint pattern, float2 p, GPUParticle particle, constant ShaderUniforms& uniforms)
{
    float t = uniforms.time;
    float seed = particle.seed * 0.013 + uniforms.randomSeed * 0.001;
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
        float phase = seed + hash11(particle.seed) * 6.2831853;
        float track = t * 0.16 + phase;
        float lane = (hash11(particle.seed + 4.0) - 0.5) * 0.18;
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
        float arm = floor(hash11(particle.seed) * 4.0);
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
        float u = fract(hash11(particle.seed + 1.7) + t * 0.010);
        float v = hash11(particle.seed + 8.3);
        float3 projected = project3DPoint(torusKnotShape(u, v), uniforms, seed);
        float2 delta = projected.xy - p;
        float2 orbit = safeNormalize(float2(-delta.y, delta.x));
        float depth = smoothstep(-0.65, 0.65, projected.z);
        return forceToward(p, projected.xy, 2.35) + orbit * (0.08 + depth * 0.10);
    }

    if (pattern == ParticlePatternHelixColumn3D) {
        float u = fract(hash11(particle.seed + 2.9) + t * 0.018);
        float v = hash11(particle.seed + 11.7);
        float phase = t * 0.16 + seed * 0.1;
        float3 projected = project3DPoint(helixColumnShape(u, v, phase), uniforms, seed + 1.0);
        float3 next = project3DPoint(helixColumnShape(fract(u + 0.006), v, phase), uniforms, seed + 1.0);
        float2 rail = safeNormalize(next.xy - projected.xy);
        return forceToward(p, projected.xy, 2.05) + rail * 0.16 + float2(-projected.y, projected.x) * 0.035;
    }

    if (pattern == ParticlePatternSphereLattice3D) {
        float u = fract(hash11(particle.seed + 4.1) + t * 0.006);
        float v = hash11(particle.seed + 16.9);
        float3 projected = project3DPoint(sphereLatticeShape(u, v), uniforms, seed + 2.0);
        float3 next = project3DPoint(sphereLatticeShape(fract(u + 0.006), v), uniforms, seed + 2.0);
        float2 track = safeNormalize(next.xy - projected.xy);
        return forceToward(p, projected.xy, 1.95) + track * 0.13 + float2(-projected.y, projected.x) * 0.04;
    }

    if (pattern == ParticlePatternMobiusRibbon3D) {
        float u = fract(hash11(particle.seed + 5.6) + t * 0.008);
        float v = hash11(particle.seed + 21.4);
        float3 projected = project3DPoint(mobiusRibbonShape(u, v), uniforms, seed + 3.0);
        float3 next = project3DPoint(mobiusRibbonShape(fract(u + 0.005), v), uniforms, seed + 3.0);
        float2 ribbon = safeNormalize(next.xy - projected.xy);
        float depth = smoothstep(-0.65, 0.65, projected.z);
        return forceToward(p, projected.xy, 2.18) + ribbon * (0.12 + depth * 0.06);
    }

    float lane = floor(hash11(particle.seed + 2.0) * 5.0);
    float targetY = sin(p.x * 4.0 + lane * 0.95 + t * 0.22 + seed * 0.1) * 0.24 + (lane - 2.0) * 0.16;
    float2 target = float2(p.x, targetY);
    return forceToward(p, target, 1.52) + float2(0.16, 0.0) + tangent * 0.04;
}

float2 particlePatternForce(float2 p, GPUParticle particle, constant ShaderUniforms& uniforms)
{
    float blend = smoothstep(0.0, 1.0, clamp(uniforms.patternBlend, 0.0, 1.0));
    float2 patternSpacePosition = p / PatternExpansion;
    float2 previousForce = particlePatternForceForPattern(uniforms.previousParticlePattern, patternSpacePosition, particle, uniforms);
    float2 currentForce = particlePatternForceForPattern(uniforms.particlePattern, patternSpacePosition, particle, uniforms);
    return mix(previousForce, currentForce, blend) * PatternExpansion;
}

float particleDepthCueForPattern(uint pattern, GPUParticle particle, constant ShaderUniforms& uniforms)
{
    float t = uniforms.time;
    float seed = particle.seed * 0.013 + uniforms.randomSeed * 0.001;

    if (pattern == ParticlePatternTorusKnot3D) {
        float u = fract(hash11(particle.seed + 1.7) + t * 0.010);
        float v = hash11(particle.seed + 8.3);
        return smoothstep(-0.65, 0.65, project3DPoint(torusKnotShape(u, v), uniforms, seed).z);
    }

    if (pattern == ParticlePatternHelixColumn3D) {
        float u = fract(hash11(particle.seed + 2.9) + t * 0.018);
        float v = hash11(particle.seed + 11.7);
        return smoothstep(-0.65, 0.65, project3DPoint(helixColumnShape(u, v, t * 0.16 + seed * 0.1), uniforms, seed + 1.0).z);
    }

    if (pattern == ParticlePatternSphereLattice3D) {
        float u = fract(hash11(particle.seed + 4.1) + t * 0.006);
        float v = hash11(particle.seed + 16.9);
        return smoothstep(-0.65, 0.65, project3DPoint(sphereLatticeShape(u, v), uniforms, seed + 2.0).z);
    }

    if (pattern == ParticlePatternMobiusRibbon3D) {
        float u = fract(hash11(particle.seed + 5.6) + t * 0.008);
        float v = hash11(particle.seed + 21.4);
        return smoothstep(-0.65, 0.65, project3DPoint(mobiusRibbonShape(u, v), uniforms, seed + 3.0).z);
    }

    return 0.5;
}

float particleDepthCue(GPUParticle particle, constant ShaderUniforms& uniforms)
{
    float blend = smoothstep(0.0, 1.0, clamp(uniforms.patternBlend, 0.0, 1.0));
    float previousDepth = particleDepthCueForPattern(uniforms.previousParticlePattern, particle, uniforms);
    float currentDepth = particleDepthCueForPattern(uniforms.particlePattern, particle, uniforms);
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
    float2 q = applySymmetry(p, uniforms);
    float t = uniforms.time;
    float slowTime = t * 0.36;
    float audio = min(uniforms.audioLevel, 0.45);
    float audioGlow = smoothstep(0.02, 0.45, audio);
    q *= 1.0 + audioGlow * 0.035;

    float swirl = length(q) * uniforms.fluidVorticity;
    if ((uniforms.experimentalFlags & ExperimentalFluidSwirl) != 0u) {
        float angle = swirl * 3.2 + sin(slowTime * 0.28 + length(q) * 5.2) * 0.18;
        float s = sin(angle);
        float c = cos(angle);
        q = float2(c * q.x - s * q.y, s * q.x + c * q.y);
    }

    float field = fbm(q * uniforms.flowScale + float2(slowTime * 0.12, -slowTime * 0.08));
    float veins = sin((q.x + field) * 9.0 + slowTime * 0.62) *
                  sin((q.y - field) * 7.5 - slowTime * 0.46);
    float rings = sin((length(q) * (12.0 + audioGlow * 0.8)) - slowTime * 0.55 + field * 4.6 + audioGlow * 0.16);
    float reactionSignal = abs(veins * rings);
    float reactionAA = max(0.035, fwidth(reactionSignal) * 2.5);
    float reaction = smoothstep(0.16 - reactionAA, 0.82 + reactionAA, reactionSignal);

    if ((uniforms.experimentalFlags & ExperimentalReactionDiffusion) == 0u) {
        reaction *= 0.35;
    }

    float attractor = sin(q.x * uniforms.attractorA * 3.0 + cos(q.y * uniforms.attractorB + slowTime));
    attractor += cos(q.y * uniforms.attractorC * 3.6 - sin(q.x * 2.3 - slowTime * 0.7));
    attractor = 0.5 + 0.25 * attractor;

    float mixValue = field * 0.42 + reaction * uniforms.reactionAmount * 0.55 + attractor * 0.28 + uniforms.hueShift;
    float3 color = paletteColor(mixValue, uniforms);
    float3 secondary = paletteColor(mixValue + 0.32 + audioGlow * 0.035, uniforms);
    color = mix(color, secondary, uniforms.layerBlend * reaction);

    float glow = pow(max(0.0, reaction), 2.5) * uniforms.bloom * (1.0 + audioGlow * 0.32);
    color += glow * uniforms.paletteD.rgb;
    color += audioGlow * 0.055 * paletteColor(field + slowTime * 0.04, uniforms);

    float vignette = smoothstep(1.42, 0.18, length(p));
    float base = 0.035 + uniforms.trailAmount * 0.06;
    color = color * (base + uniforms.layerOpacity * vignette);
    color = pow(max(color, float3(0.0)), float3(0.82));
    return float4(color, 1.0);
}

kernel void updateParticles(device GPUParticle *particles [[buffer(0)]],
                            constant ShaderUniforms& uniforms [[buffer(1)]],
                            uint id [[thread_position_in_grid]])
{
    if (id >= uniforms.particleCount) {
        return;
    }

    GPUParticle particle = particles[id];
    float dt = clamp(uniforms.deltaTime, 0.0, 1.0 / 20.0);
    float2 p = particle.position;
    float t = uniforms.time;

    float local = fbm(p * uniforms.flowScale + particle.seed * 0.001 + float2(t * 0.12, -t * 0.08));
    float angle = local * 12.56637 + uniforms.attractorStrength * atan2(p.y, p.x);
    float2 flow = float2(cos(angle), sin(angle)) * uniforms.flowStrength;

    float2 attractor = float2(
        sin(uniforms.attractorA * p.y * 3.0 + t * 0.7 + particle.seed),
        cos(uniforms.attractorB * p.x * 3.0 - t * 0.6 + particle.seed * 0.71)
    );

    float2 tangent = float2(-p.y, p.x) / max(0.12, length(p));
    float fluid = ((uniforms.experimentalFlags & ExperimentalFluidSwirl) != 0u) ? uniforms.fluidVorticity : 0.08;
    float audioKick = ((uniforms.experimentalFlags & ExperimentalAudioReactive) != 0u) ? smoothstep(0.02, 0.45, min(uniforms.audioLevel, 0.45)) : 0.0;
    float2 pattern = particlePatternForce(p, particle, uniforms);
    float2 cursor = mouseForce(p, uniforms);
    float2 acceleration = flow * 0.10 +
                          attractor * uniforms.attractorStrength * 0.055 +
                          tangent * fluid * 0.12 +
                          pattern * 1.22 +
                          cursor;
    acceleration += normalize(p + 0.001) * (audioKick * 0.16);

    particle.velocity = particle.velocity * (0.935 - uniforms.trailAmount * 0.01) + acceleration * dt;
    float speed = length(particle.velocity);
    if (speed > 1.12) {
        particle.velocity = particle.velocity / speed * 1.12;
    }
    p += particle.velocity * dt;
    particle.life -= dt * (0.045 + hash11(particle.seed) * 0.075);
    float cursorGlow = uniforms.mouseActive == 0u ? 0.0 : exp(-dot(p - float2(uniforms.mouseX, uniforms.mouseY), p - float2(uniforms.mouseX, uniforms.mouseY)) / 0.18) * uniforms.mouseStrength;
    particle.hue = fract(particle.hue + dt * (0.035 + audioKick * 0.012 + cursorGlow * 0.08));

    if (length(p) > 1.72 || particle.life <= 0.0) {
        p = patternSpawnPosition(id, particle.seed + float(uniforms.frameIndex) * 0.013, uniforms);
        float2 restartTangent = float2(-p.y, p.x) / max(0.04, length(p));
        particle.velocity = restartTangent * (0.025 + 0.04 * hash11(particle.seed + 9.0));
        particle.life = 0.55 + hash11(particle.seed + float(uniforms.frameIndex)) * 0.95;
        particle.seed += 17.31;
        particle.hue = hash11(particle.seed);
    }

    particle.position = p;
    particles[id] = particle;
}

vertex ParticleOut particleVertex(device const GPUParticle *particles [[buffer(0)]],
                                  constant ShaderUniforms& uniforms [[buffer(1)]],
                                  uint vertexID [[vertex_id]])
{
    GPUParticle particle = particles[vertexID];
    float aspect = uniforms.viewportWidth / max(1.0, uniforms.viewportHeight);
    float2 p = particle.position;
    p = applySymmetry(p, uniforms);
    float2 clip = float2(p.x / max(0.01, aspect), p.y);

    ParticleOut out;
    out.position = float4(clip, 0.0, 1.0);
    float audioSize = smoothstep(0.02, 0.45, min(uniforms.audioLevel, 0.45));
    float cursorPulse = 0.0;
    if (uniforms.mouseActive != 0u) {
        float2 mouseDelta = p - float2(uniforms.mouseX, uniforms.mouseY);
        cursorPulse = exp(-dot(mouseDelta, mouseDelta) / 0.075) * uniforms.mouseStrength;
    }
    float depthCue = particleDepthCue(particle, uniforms);
    float depthSize = mix(0.76, 1.24, depthCue);
    out.pointSize = max(1.0, uniforms.particleSize * particle.size * depthSize * (1.0 + audioSize * 0.35 + cursorPulse * 0.95));
    float intensity = smoothstep(0.0, 1.0, particle.life) * (0.58 + uniforms.bloom * 0.65) * mix(0.76, 1.24, depthCue);
    float3 color = paletteColor(particle.hue + uniforms.hueShift, uniforms) * intensity;
    color *= mix(0.78, 1.22, depthCue);
    color = mix(color, uniforms.paletteD.rgb * (intensity + 0.55), cursorPulse * 0.35);
    out.color = float4(color, (0.45 + intensity * 0.32 + cursorPulse * 0.22) * mix(0.86, 1.14, depthCue));
    out.seed = particle.seed;
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
