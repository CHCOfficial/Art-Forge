#pragma once

#include <cstdint>

namespace ArtForge {

enum class SymmetryMode : std::uint32_t {
    Off = 0,
    Mirror = 1,
    Radial = 2,
    Kaleidoscope = 3
};

enum class ParticlePattern : std::uint32_t {
    FlowWeave = 0,
    OrbitalBloom = 1,
    LissajousRibbons = 2,
    RoseMandala = 3,
    SpiralGalaxy = 4,
    VortexKnots = 5,
    TorusKnot3D = 6,
    HelixColumn3D = 7,
    SphereLattice3D = 8,
    MobiusRibbon3D = 9
};

enum ExperimentalFlags : std::uint32_t {
    ExperimentalReactionDiffusion = 1u << 0u,
    ExperimentalFluidSwirl = 1u << 1u,
    ExperimentalAudioReactive = 1u << 2u,
    ExperimentalHighDensityParticles = 1u << 3u,
    ExperimentalTemporalTrails = 1u << 4u,
    ExperimentalMetalFX = 1u << 5u,
    ExperimentalHalfResolutionPreview = 1u << 6u
};

struct alignas(16) ShaderUniforms {
    float viewportWidth = 1.0f;
    float viewportHeight = 1.0f;
    float time = 0.0f;
    float deltaTime = 0.0f;

    std::uint32_t frameIndex = 0;
    std::uint32_t particleCount = 0;
    std::uint32_t symmetryMode = 0;
    std::uint32_t experimentalFlags = 0;

    std::uint32_t particlePattern = 0;
    std::uint32_t mouseActive = 0;
    std::uint32_t previousParticlePattern = 0;
    std::uint32_t reservedB = 0;

    float flowScale = 2.0f;
    float flowStrength = 1.0f;
    float attractorStrength = 0.8f;
    float attractorA = 1.2f;

    float attractorB = 1.5f;
    float attractorC = 0.7f;
    float reactionAmount = 0.5f;
    float fluidVorticity = 0.35f;

    float particleSize = 1.8f;
    float trailAmount = 0.5f;
    float bloom = 0.65f;
    float hueShift = 0.0f;

    float audioLevel = 0.0f;
    float audioSensitivity = 0.4f;
    float timeScale = 1.0f;
    float kaleidoscopeSegments = 8.0f;

    float layerOpacity = 0.82f;
    float layerBlend = 0.5f;
    float randomSeed = 1.0f;
    float mutation = 0.0f;

    float mouseX = 0.0f;
    float mouseY = 0.0f;
    float mouseStrength = 0.0f;
    float mouseRadius = 0.28f;

    float patternBlend = 1.0f;
    float transitionAmount = 1.0f;
    float reservedFloatA = 0.0f;
    float reservedFloatB = 0.0f;

    float paletteA[4] = {0.45f, 0.20f, 0.80f, 1.0f};
    float paletteB[4] = {0.15f, 0.70f, 1.00f, 1.0f};
    float paletteC[4] = {1.00f, 0.35f, 0.15f, 1.0f};
    float paletteD[4] = {0.95f, 0.95f, 0.80f, 1.0f};
};

static_assert(sizeof(ShaderUniforms) % 16 == 0);

}
