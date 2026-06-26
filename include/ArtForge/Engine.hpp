#pragma once

#include "ArtForge/ShaderTypes.hpp"

#include <array>
#include <cstdint>
#include <random>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace ArtForge {

struct Palette {
    std::array<float, 4> a;
    std::array<float, 4> b;
    std::array<float, 4> c;
    std::array<float, 4> d;
};

struct Parameters {
    float flowScale = 2.2f;
    float flowStrength = 1.0f;
    float attractorStrength = 0.9f;
    float attractorA = 1.35f;
    float attractorB = 1.85f;
    float attractorC = 0.72f;
    float reactionAmount = 0.55f;
    float fluidVorticity = 0.42f;
    float particleSize = 1.7f;
    float trailAmount = 0.55f;
    float bloom = 0.72f;
    float hueShift = 0.0f;
    float audioSensitivity = 0.5f;
    float timeScale = 1.0f;
    float kaleidoscopeSegments = 9.0f;
    float layerOpacity = 0.86f;
    float layerBlend = 0.5f;
    float mutation = 0.0f;
    Palette palette {
        {0.40f, 0.12f, 0.92f, 1.0f},
        {0.05f, 0.78f, 1.00f, 1.0f},
        {1.00f, 0.31f, 0.10f, 1.0f},
        {0.95f, 0.95f, 0.74f, 1.0f}
    };
};

struct ExperimentalOptions {
    bool reactionDiffusion = true;
    bool fluidSwirl = true;
    bool audioReactive = false;
    bool highDensityParticles = false;
    bool temporalTrails = true;
    bool halfResolutionPreview = false;
    bool metalFX = false;
    bool metalFXRuntimeAvailable = false;
    std::string metalFXStatus = "MetalFX support has not been checked yet.";
};

enum class ExperimentalFeature {
    ReactionDiffusion,
    FluidSwirl,
    AudioReactive,
    HighDensityParticles,
    TemporalTrails,
    HalfResolutionPreview,
    MetalFX
};

struct Preset {
    std::string_view name;
    Parameters parameters;
    SymmetryMode symmetry;
    ParticlePattern particlePattern;
    BackgroundStyle backgroundStyle;
};

class Engine {
public:
    Engine();

    void tick(double dtSeconds);
    void randomize();
    void mutate(float amount);
    void loadPreset(std::size_t index);
    void setSymmetryMode(SymmetryMode mode);
    void setParticlePattern(ParticlePattern pattern);
    void setPaused(bool paused);
    void togglePaused();
    void toggleExperimental(ExperimentalFeature feature);
    void setMetalFXRuntimeAvailable(bool available, std::string status);

    [[nodiscard]] ShaderUniforms uniforms(float viewportWidth, float viewportHeight) const;
    [[nodiscard]] std::uint32_t targetParticleCount() const;
    [[nodiscard]] std::span<const Preset> presets() const;
    [[nodiscard]] std::size_t currentPresetIndex() const;
    [[nodiscard]] std::string_view currentPresetName() const;
    [[nodiscard]] SymmetryMode symmetryMode() const;
    [[nodiscard]] ParticlePattern particlePattern() const;
    [[nodiscard]] const ExperimentalOptions& experimentalOptions() const;
    [[nodiscard]] bool isPaused() const;

private:
    [[nodiscard]] float randomRange(float minValue, float maxValue);
    [[nodiscard]] std::array<float, 4> randomColor(float alpha = 1.0f);
    void applyPaletteToUniforms(ShaderUniforms& uniforms) const;
    [[nodiscard]] std::uint32_t experimentalFlags() const;
    void beginTransitionTo(Parameters targetParameters,
                           ParticlePattern targetPattern,
                           BackgroundStyle targetBackgroundStyle,
                           std::size_t targetPreset,
                           float targetSeed);

    Parameters parameters_;
    Parameters transitionStartParameters_;
    Parameters transitionTargetParameters_;
    ExperimentalOptions experimental_;
    SymmetryMode symmetryMode_ = SymmetryMode::Off;
    ParticlePattern particlePattern_ = ParticlePattern::OrbitalBloom;
    ParticlePattern previousParticlePattern_ = ParticlePattern::OrbitalBloom;
    BackgroundStyle backgroundStyle_ = BackgroundStyle::DeepSpace;
    BackgroundStyle previousBackgroundStyle_ = BackgroundStyle::DeepSpace;
    std::size_t currentPreset_ = 0;
    double time_ = 0.0;
    double audioPhase_ = 0.0;
    double lastDelta_ = 0.0;
    double transitionElapsed_ = 1.0;
    double transitionDuration_ = 1.65;
    float audioLevel_ = 0.0f;
    std::uint32_t frameIndex_ = 0;
    bool paused_ = false;
    float randomSeed_ = 1.0f;
    float transitionStartSeed_ = 1.0f;
    float transitionTargetSeed_ = 1.0f;
    bool transitionActive_ = false;
    std::mt19937 rng_;
    std::vector<Preset> presets_;
};

}
