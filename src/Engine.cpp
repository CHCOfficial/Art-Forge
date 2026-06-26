#include "ArtForge/Engine.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>

namespace ArtForge {
namespace {

constexpr float kPi = 3.14159265358979323846f;

Palette palette(std::array<float, 4> a,
                std::array<float, 4> b,
                std::array<float, 4> c,
                std::array<float, 4> d)
{
    return Palette{a, b, c, d};
}

float mixFloat(float from, float to, float amount)
{
    return from + (to - from) * amount;
}

std::array<float, 4> mixColor(const std::array<float, 4>& from,
                              const std::array<float, 4>& to,
                              float amount)
{
    return {
        mixFloat(from[0], to[0], amount),
        mixFloat(from[1], to[1], amount),
        mixFloat(from[2], to[2], amount),
        mixFloat(from[3], to[3], amount)
    };
}

Palette mixPalette(const Palette& from, const Palette& to, float amount)
{
    return Palette{
        mixColor(from.a, to.a, amount),
        mixColor(from.b, to.b, amount),
        mixColor(from.c, to.c, amount),
        mixColor(from.d, to.d, amount)
    };
}

Parameters mixParameters(const Parameters& from, const Parameters& to, float amount)
{
    Parameters mixed;
    mixed.flowScale = mixFloat(from.flowScale, to.flowScale, amount);
    mixed.flowStrength = mixFloat(from.flowStrength, to.flowStrength, amount);
    mixed.attractorStrength = mixFloat(from.attractorStrength, to.attractorStrength, amount);
    mixed.attractorA = mixFloat(from.attractorA, to.attractorA, amount);
    mixed.attractorB = mixFloat(from.attractorB, to.attractorB, amount);
    mixed.attractorC = mixFloat(from.attractorC, to.attractorC, amount);
    mixed.reactionAmount = mixFloat(from.reactionAmount, to.reactionAmount, amount);
    mixed.fluidVorticity = mixFloat(from.fluidVorticity, to.fluidVorticity, amount);
    mixed.particleSize = mixFloat(from.particleSize, to.particleSize, amount);
    mixed.trailAmount = mixFloat(from.trailAmount, to.trailAmount, amount);
    mixed.bloom = mixFloat(from.bloom, to.bloom, amount);
    mixed.hueShift = mixFloat(from.hueShift, to.hueShift, amount);
    mixed.audioSensitivity = mixFloat(from.audioSensitivity, to.audioSensitivity, amount);
    mixed.timeScale = mixFloat(from.timeScale, to.timeScale, amount);
    mixed.kaleidoscopeSegments = mixFloat(from.kaleidoscopeSegments, to.kaleidoscopeSegments, amount);
    mixed.layerOpacity = mixFloat(from.layerOpacity, to.layerOpacity, amount);
    mixed.layerBlend = mixFloat(from.layerBlend, to.layerBlend, amount);
    mixed.mutation = mixFloat(from.mutation, to.mutation, amount);
    mixed.palette = mixPalette(from.palette, to.palette, amount);
    return mixed;
}

Preset makePreset(std::string_view name,
                  SymmetryMode symmetry,
                  ParticlePattern particlePattern,
                  BackgroundStyle backgroundStyle,
                  float flowScale,
                  float flowStrength,
                  float attractorStrength,
                  float reactionAmount,
                  float fluidVorticity,
                  float particleSize,
                  float bloom,
                  float hueShift,
                  float segments,
                  Palette paletteValue)
{
    Parameters p;
    p.flowScale = flowScale;
    p.flowStrength = flowStrength;
    p.attractorStrength = attractorStrength;
    p.attractorA = 1.0f + flowScale * 0.17f;
    p.attractorB = 1.3f + flowStrength * 0.31f;
    p.attractorC = 0.5f + reactionAmount * 0.62f;
    p.reactionAmount = reactionAmount;
    p.fluidVorticity = fluidVorticity;
    p.particleSize = particleSize;
    p.trailAmount = 0.42f + bloom * 0.28f;
    p.bloom = bloom;
    p.hueShift = hueShift;
    p.audioSensitivity = 0.42f + reactionAmount * 0.28f;
    p.timeScale = 0.78f + flowStrength * 0.2f;
    p.kaleidoscopeSegments = segments;
    p.layerOpacity = 0.76f + bloom * 0.16f;
    p.layerBlend = 0.25f + reactionAmount * 0.55f;
    p.palette = paletteValue;
    return Preset{name, p, symmetry, particlePattern, backgroundStyle};
}

std::vector<Preset> buildPresets()
{
    return {
        makePreset(
            "Aurora Loom",
            SymmetryMode::Off,
            ParticlePattern::OrbitalBloom,
            BackgroundStyle::DeepSpace,
            2.2f,
            1.05f,
            0.9f,
            0.62f,
            0.35f,
            1.8f,
            0.68f,
            0.08f,
            9.0f,
            palette({0.30f, 0.08f, 0.72f, 1.0f},
                    {0.02f, 0.80f, 1.00f, 1.0f},
                    {1.00f, 0.36f, 0.10f, 1.0f},
                    {0.94f, 0.96f, 0.76f, 1.0f})),
        makePreset(
            "Solar Ink",
            SymmetryMode::Off,
            ParticlePattern::SpiralGalaxy,
            BackgroundStyle::EmberHaze,
            3.8f,
            0.72f,
            1.35f,
            0.38f,
            0.68f,
            1.5f,
            0.82f,
            0.52f,
            14.0f,
            palette({0.08f, 0.05f, 0.12f, 1.0f},
                    {1.00f, 0.50f, 0.05f, 1.0f},
                    {1.00f, 0.08f, 0.02f, 1.0f},
                    {1.00f, 0.92f, 0.64f, 1.0f})),
        makePreset(
            "Chromatic Reef",
            SymmetryMode::Off,
            ParticlePattern::LissajousRibbons,
            BackgroundStyle::QuietOcean,
            1.65f,
            1.38f,
            0.55f,
            0.84f,
            0.28f,
            2.25f,
            0.58f,
            0.22f,
            6.0f,
            palette({0.00f, 0.28f, 0.36f, 1.0f},
                    {0.10f, 0.96f, 0.72f, 1.0f},
                    {0.96f, 0.20f, 0.82f, 1.0f},
                    {0.72f, 0.96f, 1.00f, 1.0f})),
        makePreset(
            "Nocturne Field",
            SymmetryMode::Off,
            ParticlePattern::VortexKnots,
            BackgroundStyle::MistGarden,
            2.95f,
            0.94f,
            1.18f,
            0.48f,
            0.50f,
            1.25f,
            0.74f,
            0.66f,
            5.0f,
            palette({0.02f, 0.03f, 0.08f, 1.0f},
                    {0.20f, 0.32f, 0.95f, 1.0f},
                    {0.75f, 0.10f, 1.00f, 1.0f},
                    {0.82f, 0.93f, 1.00f, 1.0f})),
        makePreset(
            "Prismatic Engine",
            SymmetryMode::Off,
            ParticlePattern::RoseMandala,
            BackgroundStyle::SilkDawn,
            4.6f,
            1.18f,
            0.72f,
            0.78f,
            0.82f,
            1.95f,
            0.88f,
            0.35f,
            18.0f,
            palette({0.18f, 0.00f, 0.22f, 1.0f},
                    {0.95f, 0.12f, 0.34f, 1.0f},
                    {0.05f, 0.90f, 1.00f, 1.0f},
                    {1.00f, 0.96f, 0.36f, 1.0f}))
    };
}

float clamp01(float value)
{
    return std::clamp(value, 0.0f, 1.0f);
}

float smooth01(float value)
{
    value = clamp01(value);
    return value * value * (3.0f - 2.0f * value);
}

float smoother01(float value)
{
    value = clamp01(value);
    return value * value * value * (value * (value * 6.0f - 15.0f) + 10.0f);
}

}

Engine::Engine()
    : rng_(std::random_device{}()),
      presets_(buildPresets())
{
    currentPreset_ = 0;
    parameters_ = presets_[0].parameters;
    transitionStartParameters_ = parameters_;
    transitionTargetParameters_ = parameters_;
    symmetryMode_ = SymmetryMode::Off;
    particlePattern_ = presets_[0].particlePattern;
    previousParticlePattern_ = particlePattern_;
    backgroundStyle_ = presets_[0].backgroundStyle;
    previousBackgroundStyle_ = backgroundStyle_;
    randomSeed_ = randomRange(0.0f, 10000.0f);
    transitionStartSeed_ = randomSeed_;
    transitionTargetSeed_ = randomSeed_;
}

void Engine::tick(double dtSeconds)
{
    const double clampedDelta = std::clamp(dtSeconds, 0.0, 1.0 / 15.0);
    lastDelta_ = paused_ ? 0.0 : clampedDelta;

    if (!paused_) {
        time_ += clampedDelta * static_cast<double>(parameters_.timeScale);
        audioPhase_ += clampedDelta * 0.92;
        if (transitionActive_) {
            transitionElapsed_ += clampedDelta;
            const float linear = static_cast<float>(std::clamp(transitionElapsed_ / transitionDuration_, 0.0, 1.0));
            const float eased = smoother01(linear);
            parameters_ = mixParameters(transitionStartParameters_, transitionTargetParameters_, eased);
            if (linear >= 1.0f) {
                transitionActive_ = false;
                parameters_ = transitionTargetParameters_;
                previousParticlePattern_ = particlePattern_;
                previousBackgroundStyle_ = backgroundStyle_;
                randomSeed_ = transitionTargetSeed_;
            }
        }
    }

    const float phase = static_cast<float>(audioPhase_);
    const float bass = smooth01(0.5f + 0.5f * std::sin(phase * 0.72f));
    const float mid = smooth01(0.5f + 0.5f * std::sin(phase * 1.37f + 1.2f));
    const float shimmer = smooth01(0.5f + 0.5f * std::sin(phase * 2.11f + 2.4f));
    const float syntheticAudio = 0.10f + 0.42f * (bass * 0.58f + mid * 0.28f + shimmer * 0.14f);
    const float target = experimental_.audioReactive ? syntheticAudio : 0.0f;
    const float responseRate = target > audioLevel_ ? 1.8f : 0.85f;
    const float blend = 1.0f - std::exp(-static_cast<float>(clampedDelta) * responseRate);
    audioLevel_ += (target - audioLevel_) * blend;

    ++frameIndex_;
}

void Engine::randomize()
{
    Parameters target = parameters_;
    target.flowScale = randomRange(1.0f, 5.6f);
    target.flowStrength = randomRange(0.55f, 1.6f);
    target.attractorStrength = randomRange(0.35f, 1.65f);
    target.attractorA = randomRange(0.75f, 2.45f);
    target.attractorB = randomRange(0.8f, 2.8f);
    target.attractorC = randomRange(0.35f, 1.5f);
    target.reactionAmount = randomRange(0.25f, 0.95f);
    target.fluidVorticity = randomRange(0.12f, 0.95f);
    target.particleSize = randomRange(1.0f, 2.8f);
    target.trailAmount = randomRange(0.25f, 0.85f);
    target.bloom = randomRange(0.35f, 0.95f);
    target.hueShift = randomRange(0.0f, 1.0f);
    target.audioSensitivity = randomRange(0.25f, 0.85f);
    target.timeScale = randomRange(0.65f, 1.35f);
    target.kaleidoscopeSegments = randomRange(5.0f, 22.0f);
    target.layerOpacity = randomRange(0.66f, 0.96f);
    target.layerBlend = randomRange(0.15f, 0.85f);
    target.mutation = 1.0f;
    target.palette = Palette{
        randomColor(),
        randomColor(),
        randomColor(),
        randomColor()
    };
    symmetryMode_ = SymmetryMode::Off;
    const auto targetPattern = static_cast<ParticlePattern>(static_cast<std::uint32_t>(randomRange(0.0f, 9.99f)));
    const auto targetBackground = static_cast<BackgroundStyle>(static_cast<std::uint32_t>(randomRange(0.0f, 4.99f)));
    beginTransitionTo(target, targetPattern, targetBackground, presets_.size(), randomRange(0.0f, 10000.0f));
}

void Engine::mutate(float amount)
{
    transitionActive_ = false;
    previousParticlePattern_ = particlePattern_;
    previousBackgroundStyle_ = backgroundStyle_;
    const float strength = std::clamp(amount, 0.0f, 1.0f);
    auto nudge = [&](float& value, float minValue, float maxValue) {
        value = std::clamp(value + randomRange(-strength, strength) * (maxValue - minValue) * 0.08f,
                           minValue,
                           maxValue);
    };

    nudge(parameters_.flowScale, 0.8f, 6.0f);
    nudge(parameters_.flowStrength, 0.3f, 1.8f);
    nudge(parameters_.attractorStrength, 0.2f, 1.9f);
    nudge(parameters_.reactionAmount, 0.0f, 1.0f);
    nudge(parameters_.fluidVorticity, 0.0f, 1.0f);
    nudge(parameters_.particleSize, 0.75f, 3.2f);
    nudge(parameters_.bloom, 0.2f, 1.0f);
    nudge(parameters_.hueShift, 0.0f, 1.0f);
    parameters_.mutation = std::clamp(parameters_.mutation + strength * 0.35f, 0.0f, 1.0f);

    for (auto* color : {&parameters_.palette.a, &parameters_.palette.b, &parameters_.palette.c, &parameters_.palette.d}) {
        (*color)[0] = clamp01((*color)[0] + randomRange(-0.06f, 0.06f) * strength);
        (*color)[1] = clamp01((*color)[1] + randomRange(-0.06f, 0.06f) * strength);
        (*color)[2] = clamp01((*color)[2] + randomRange(-0.06f, 0.06f) * strength);
    }

    currentPreset_ = presets_.size();
    randomSeed_ += randomRange(-17.0f, 17.0f);
    transitionStartSeed_ = randomSeed_;
    transitionTargetSeed_ = randomSeed_;
}

void Engine::loadPreset(std::size_t index)
{
    if (index >= presets_.size()) {
        return;
    }

    beginTransitionTo(presets_[index].parameters,
                      presets_[index].particlePattern,
                      presets_[index].backgroundStyle,
                      index,
                      static_cast<float>((index + 1) * 137));
}

void Engine::setSymmetryMode(SymmetryMode mode)
{
    (void)mode;
    symmetryMode_ = SymmetryMode::Off;
}

void Engine::setParticlePattern(ParticlePattern pattern)
{
    transitionActive_ = false;
    previousParticlePattern_ = pattern;
    particlePattern_ = pattern;
}

void Engine::setPaused(bool paused)
{
    paused_ = paused;
}

void Engine::togglePaused()
{
    paused_ = !paused_;
}

void Engine::toggleExperimental(ExperimentalFeature feature)
{
    switch (feature) {
    case ExperimentalFeature::ReactionDiffusion:
        experimental_.reactionDiffusion = !experimental_.reactionDiffusion;
        break;
    case ExperimentalFeature::FluidSwirl:
        experimental_.fluidSwirl = !experimental_.fluidSwirl;
        break;
    case ExperimentalFeature::AudioReactive:
        experimental_.audioReactive = !experimental_.audioReactive;
        break;
    case ExperimentalFeature::HighDensityParticles:
        experimental_.highDensityParticles = !experimental_.highDensityParticles;
        break;
    case ExperimentalFeature::TemporalTrails:
        experimental_.temporalTrails = !experimental_.temporalTrails;
        break;
    case ExperimentalFeature::HalfResolutionPreview:
        experimental_.halfResolutionPreview = !experimental_.halfResolutionPreview;
        break;
    case ExperimentalFeature::MetalFX:
        if (experimental_.metalFXRuntimeAvailable) {
            experimental_.metalFX = !experimental_.metalFX;
        }
        break;
    }
}

void Engine::setMetalFXRuntimeAvailable(bool available, std::string status)
{
    experimental_.metalFXRuntimeAvailable = available;
    experimental_.metalFXStatus = std::move(status);
    if (!available) {
        experimental_.metalFX = false;
    }
}

ShaderUniforms Engine::uniforms(float viewportWidth, float viewportHeight) const
{
    ShaderUniforms u;
    u.viewportWidth = std::max(1.0f, viewportWidth);
    u.viewportHeight = std::max(1.0f, viewportHeight);
    u.time = static_cast<float>(time_);
    u.deltaTime = static_cast<float>(lastDelta_);
    u.frameIndex = frameIndex_;
    u.particleCount = targetParticleCount();
    u.symmetryMode = static_cast<std::uint32_t>(SymmetryMode::Off);
    u.experimentalFlags = experimentalFlags();
    u.particlePattern = static_cast<std::uint32_t>(particlePattern_);
    u.previousParticlePattern = static_cast<std::uint32_t>(previousParticlePattern_);
    u.backgroundStyle = static_cast<std::uint32_t>(backgroundStyle_);
    u.previousBackgroundStyle = static_cast<std::uint32_t>(previousBackgroundStyle_);
    u.flowScale = parameters_.flowScale;
    u.flowStrength = parameters_.flowStrength;
    u.attractorStrength = parameters_.attractorStrength;
    u.attractorA = parameters_.attractorA;
    u.attractorB = parameters_.attractorB;
    u.attractorC = parameters_.attractorC;
    u.reactionAmount = parameters_.reactionAmount;
    u.fluidVorticity = parameters_.fluidVorticity;
    u.particleSize = parameters_.particleSize;
    u.trailAmount = parameters_.trailAmount;
    u.bloom = parameters_.bloom;
    u.hueShift = parameters_.hueShift;
    u.audioLevel = audioLevel_ * parameters_.audioSensitivity;
    u.audioSensitivity = parameters_.audioSensitivity;
    u.timeScale = parameters_.timeScale;
    u.kaleidoscopeSegments = parameters_.kaleidoscopeSegments;
    u.layerOpacity = parameters_.layerOpacity;
    u.layerBlend = parameters_.layerBlend;
    u.randomSeed = randomSeed_;
    u.mutation = parameters_.mutation;
    if (transitionActive_) {
        const float linear = static_cast<float>(std::clamp(transitionElapsed_ / transitionDuration_, 0.0, 1.0));
        u.patternBlend = smoother01(linear);
        u.transitionAmount = u.patternBlend;
    } else {
        u.patternBlend = 1.0f;
        u.transitionAmount = 1.0f;
    }
    u.previousRandomSeed = transitionActive_ ? transitionStartSeed_ : randomSeed_;
    u.targetRandomSeed = transitionTargetSeed_;
    applyPaletteToUniforms(u);
    return u;
}

std::uint32_t Engine::targetParticleCount() const
{
    return experimental_.highDensityParticles ? 1'048'576u : 262'144u;
}

std::span<const Preset> Engine::presets() const
{
    return std::span<const Preset>(presets_.data(), presets_.size());
}

std::size_t Engine::currentPresetIndex() const
{
    return currentPreset_;
}

std::string_view Engine::currentPresetName() const
{
    if (currentPreset_ < presets_.size()) {
        return presets_[currentPreset_].name;
    }
    return "Mutation Lab";
}

SymmetryMode Engine::symmetryMode() const
{
    return SymmetryMode::Off;
}

ParticlePattern Engine::particlePattern() const
{
    return particlePattern_;
}

const ExperimentalOptions& Engine::experimentalOptions() const
{
    return experimental_;
}

bool Engine::isPaused() const
{
    return paused_;
}

float Engine::randomRange(float minValue, float maxValue)
{
    std::uniform_real_distribution<float> distribution(minValue, maxValue);
    return distribution(rng_);
}

std::array<float, 4> Engine::randomColor(float alpha)
{
    const float angle = randomRange(0.0f, kPi * 2.0f);
    const float saturation = randomRange(0.55f, 1.0f);
    const float value = randomRange(0.62f, 1.0f);
    const float r = value * (0.55f + 0.45f * std::sin(angle));
    const float g = value * (0.55f + 0.45f * std::sin(angle + kPi * 2.0f / 3.0f));
    const float b = value * (0.55f + 0.45f * std::sin(angle + kPi * 4.0f / 3.0f));
    return {clamp01(r * saturation), clamp01(g * saturation), clamp01(b * saturation), alpha};
}

void Engine::applyPaletteToUniforms(ShaderUniforms& uniforms) const
{
    std::memcpy(uniforms.paletteA, parameters_.palette.a.data(), sizeof(uniforms.paletteA));
    std::memcpy(uniforms.paletteB, parameters_.palette.b.data(), sizeof(uniforms.paletteB));
    std::memcpy(uniforms.paletteC, parameters_.palette.c.data(), sizeof(uniforms.paletteC));
    std::memcpy(uniforms.paletteD, parameters_.palette.d.data(), sizeof(uniforms.paletteD));
}

std::uint32_t Engine::experimentalFlags() const
{
    std::uint32_t flags = 0;
    if (experimental_.reactionDiffusion) {
        flags |= ExperimentalReactionDiffusion;
    }
    if (experimental_.fluidSwirl) {
        flags |= ExperimentalFluidSwirl;
    }
    if (experimental_.audioReactive) {
        flags |= ExperimentalAudioReactive;
    }
    if (experimental_.highDensityParticles) {
        flags |= ExperimentalHighDensityParticles;
    }
    if (experimental_.temporalTrails) {
        flags |= ExperimentalTemporalTrails;
    }
    if (experimental_.metalFX && experimental_.metalFXRuntimeAvailable) {
        flags |= ExperimentalMetalFX;
    }
    if (experimental_.halfResolutionPreview) {
        flags |= ExperimentalHalfResolutionPreview;
    }
    return flags;
}

void Engine::beginTransitionTo(Parameters targetParameters,
                               ParticlePattern targetPattern,
                               BackgroundStyle targetBackgroundStyle,
                               std::size_t targetPreset,
                               float targetSeed)
{
    transitionStartParameters_ = parameters_;
    transitionTargetParameters_ = std::move(targetParameters);
    transitionStartSeed_ = randomSeed_;
    transitionTargetSeed_ = targetSeed;
    randomSeed_ = targetSeed;
    previousParticlePattern_ = particlePattern_;
    particlePattern_ = targetPattern;
    previousBackgroundStyle_ = backgroundStyle_;
    backgroundStyle_ = targetBackgroundStyle;
    currentPreset_ = targetPreset;
    symmetryMode_ = SymmetryMode::Off;
    transitionElapsed_ = 0.0;
    transitionActive_ = true;
}

}
