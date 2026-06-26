#include "ArtForge/Engine.hpp"

#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <string_view>

namespace {

int failures = 0;

void expect(bool condition, std::string_view message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

bool approx(float a, float b, float tolerance = 0.0001f)
{
    return std::fabs(a - b) <= tolerance;
}

std::filesystem::path sourceDir()
{
    if (const char* env = std::getenv("ART_FORGE_SOURCE_DIR")) {
        return std::filesystem::path(env);
    }

    return std::filesystem::current_path().parent_path();
}

std::string readText(const std::filesystem::path& path)
{
    std::ifstream input(path);
    std::ostringstream output;
    output << input.rdbuf();
    return output.str();
}

bool contains(std::string_view haystack, std::string_view needle)
{
    return haystack.find(needle) != std::string_view::npos;
}

void testDefaultEngineState()
{
    ArtForge::Engine engine;
    const auto presets = engine.presets();
    expect(presets.size() == 5, "engine exposes the curated preset set");
    expect(engine.currentPresetIndex() == 0, "engine starts on the first preset");
    expect(engine.currentPresetName() == "Aurora Loom", "first preset is Aurora Loom");
    expect(engine.symmetryMode() == ArtForge::SymmetryMode::Off, "symmetry is always off by default");
    expect(engine.particlePattern() == presets[0].particlePattern, "initial particle pattern matches preset");
    expect(engine.targetParticleCount() == 262'144u, "default particle count is standard density");

    const auto uniforms = engine.uniforms(0.0f, 0.0f);
    expect(approx(uniforms.viewportWidth, 1.0f), "uniform viewport width clamps to at least one pixel");
    expect(approx(uniforms.viewportHeight, 1.0f), "uniform viewport height clamps to at least one pixel");
    expect(uniforms.symmetryMode == static_cast<std::uint32_t>(ArtForge::SymmetryMode::Off),
           "uniform symmetry is off");
    expect(uniforms.backgroundStyle == static_cast<std::uint32_t>(presets[0].backgroundStyle),
           "initial background style matches preset");
    expect(uniforms.previousBackgroundStyle == uniforms.backgroundStyle,
           "initial previous background is stable");
    expect(approx(uniforms.transitionAmount, 1.0f), "initial scene is fully settled");
    expect(approx(uniforms.previousRandomSeed, uniforms.randomSeed),
           "settled scene exposes one stable random seed");
    expect(approx(uniforms.targetRandomSeed, uniforms.randomSeed),
           "initial target seed matches current seed");
}

void testPresetTransitionUsesStableSeeds()
{
    ArtForge::Engine engine;
    const auto presets = engine.presets();
    const auto before = engine.uniforms(1280.0f, 720.0f);

    engine.loadPreset(2);
    auto start = engine.uniforms(1280.0f, 720.0f);
    expect(engine.currentPresetIndex() == 2, "loading a preset selects it immediately for UI state");
    expect(approx(start.transitionAmount, 0.0f), "preset transition starts at zero blend");
    expect(start.previousParticlePattern == static_cast<std::uint32_t>(presets[0].particlePattern),
           "transition remembers outgoing particle pattern");
    expect(start.particlePattern == static_cast<std::uint32_t>(presets[2].particlePattern),
           "transition targets incoming particle pattern");
    expect(start.previousBackgroundStyle == static_cast<std::uint32_t>(presets[0].backgroundStyle),
           "transition remembers outgoing background style");
    expect(start.backgroundStyle == static_cast<std::uint32_t>(presets[2].backgroundStyle),
           "transition targets incoming background style");
    expect(approx(start.previousRandomSeed, before.randomSeed),
           "transition keeps outgoing seed stable");
    expect(approx(start.randomSeed, 411.0f),
           "transition switches incoming seed immediately so the target image is stable");
    expect(approx(start.targetRandomSeed, start.randomSeed),
           "target seed is exposed for tests and future shader work");

    float previousBlend = start.transitionAmount;
    for (int frame = 0; frame < 60; ++frame) {
        engine.tick(1.0 / 60.0);
        const auto current = engine.uniforms(1280.0f, 720.0f);
        expect(current.transitionAmount + 0.0001f >= previousBlend,
               "transition blend is monotonic");
        expect(approx(current.previousRandomSeed, before.randomSeed),
               "outgoing seed remains stable throughout transition");
        expect(approx(current.randomSeed, start.randomSeed),
               "incoming seed remains stable throughout transition");
        previousBlend = current.transitionAmount;
    }

    for (int frame = 0; frame < 180; ++frame) {
        engine.tick(1.0 / 60.0);
    }
    const auto settled = engine.uniforms(1280.0f, 720.0f);
    expect(approx(settled.transitionAmount, 1.0f), "transition settles at full blend");
    expect(settled.previousParticlePattern == settled.particlePattern,
           "settled transition collapses previous particle pattern to current");
    expect(settled.previousBackgroundStyle == settled.backgroundStyle,
           "settled transition collapses previous background to current");
    expect(approx(settled.previousRandomSeed, settled.randomSeed),
           "settled transition collapses previous seed to current");
}

void testInvalidPresetAndMutationInvariants()
{
    ArtForge::Engine engine;
    const auto initial = engine.uniforms(640.0f, 480.0f);
    engine.loadPreset(999);
    expect(engine.currentPresetIndex() == 0, "invalid preset index is ignored");
    const auto afterInvalid = engine.uniforms(640.0f, 480.0f);
    expect(afterInvalid.particlePattern == initial.particlePattern,
           "invalid preset keeps particle pattern unchanged");
    expect(afterInvalid.backgroundStyle == initial.backgroundStyle,
           "invalid preset keeps background style unchanged");

    engine.mutate(0.75f);
    const auto mutated = engine.uniforms(640.0f, 480.0f);
    expect(engine.currentPresetIndex() == engine.presets().size(),
           "mutation moves UI state into the mutation lab");
    expect(approx(mutated.transitionAmount, 1.0f),
           "mutation is an immediate nudge, not a preset transition");
    expect(approx(mutated.previousRandomSeed, mutated.randomSeed),
           "mutation keeps settled seed fields coherent");
}

void testExperimentalFeatureFlags()
{
    ArtForge::Engine engine;
    auto uniforms = engine.uniforms(100.0f, 100.0f);
    expect((uniforms.experimentalFlags & ArtForge::ExperimentalAudioReactive) == 0u,
           "audio-reactive modulation remains opt-in");
    expect((uniforms.experimentalFlags & ArtForge::ExperimentalTemporalTrails) != 0u,
           "temporal trails are enabled by default");

    engine.toggleExperimental(ArtForge::ExperimentalFeature::HighDensityParticles);
    expect(engine.targetParticleCount() == 1'048'576u,
           "high-density particles switch to the million-particle target");

    engine.toggleExperimental(ArtForge::ExperimentalFeature::AudioReactive);
    uniforms = engine.uniforms(100.0f, 100.0f);
    expect((uniforms.experimentalFlags & ArtForge::ExperimentalAudioReactive) != 0u,
           "audio-reactive flag appears after explicit toggle");

    engine.setMetalFXRuntimeAvailable(false, "not available");
    engine.toggleExperimental(ArtForge::ExperimentalFeature::MetalFX);
    uniforms = engine.uniforms(100.0f, 100.0f);
    expect((uniforms.experimentalFlags & ArtForge::ExperimentalMetalFX) == 0u,
           "MetalFX cannot enable when runtime support is unavailable");
}

void testRandomizeRanges()
{
    ArtForge::Engine engine;
    engine.randomize();
    const auto uniforms = engine.uniforms(1920.0f, 1080.0f);
    expect(engine.currentPresetIndex() == engine.presets().size(),
           "randomize moves UI state into the mutation lab");
    expect(uniforms.symmetryMode == static_cast<std::uint32_t>(ArtForge::SymmetryMode::Off),
           "randomize still keeps symmetry off");
    expect(uniforms.particlePattern <= static_cast<std::uint32_t>(ArtForge::ParticlePattern::MobiusRibbon3D),
           "randomize selects a known particle pattern");
    expect(uniforms.backgroundStyle <= static_cast<std::uint32_t>(ArtForge::BackgroundStyle::EmberHaze),
           "randomize selects a known background style");
    expect(approx(uniforms.transitionAmount, 0.0f),
           "randomize starts a smooth transition");
    expect(!approx(uniforms.previousRandomSeed, uniforms.randomSeed),
           "randomize exposes distinct outgoing and incoming seeds during transition");
}

void testShaderUniformContract()
{
    using ArtForge::ShaderUniforms;
    expect(alignof(ShaderUniforms) == 16, "ShaderUniforms is 16-byte aligned");
    expect(sizeof(ShaderUniforms) % 16 == 0, "ShaderUniforms size stays 16-byte padded");
    expect(offsetof(ShaderUniforms, backgroundStyle) == 48,
           "background style row follows particle pattern row");
    expect(offsetof(ShaderUniforms, flowScale) == 64,
           "flow parameters follow background style row");
    expect(offsetof(ShaderUniforms, previousRandomSeed) ==
               offsetof(ShaderUniforms, patternBlend) + sizeof(float) * 2,
           "seed fields remain adjacent to transition fields");
    expect(offsetof(ShaderUniforms, paletteA) % 16 == 0,
           "palette data starts on a 16-byte boundary");
}

void testShaderSourceGuards()
{
    const auto shaderPath = sourceDir() / "resources" / "shaders" / "ArtForge.metal";
    const std::string shader = readText(shaderPath);
    expect(!shader.empty(), "shader source can be read by tests");
    expect(contains(shader, "float previousRandomSeed;"),
           "Metal uniform contract includes previousRandomSeed");
    expect(contains(shader, "backgroundForStyle(uniforms.previousBackgroundStyle, uv, p, uniforms, uniforms.previousRandomSeed)"),
           "background crossfade evaluates outgoing style with outgoing seed");
    expect(contains(shader, "backgroundForStyle(uniforms.backgroundStyle, uv, p, uniforms, uniforms.randomSeed)"),
           "background crossfade evaluates incoming style with incoming seed");
    expect(contains(shader, "project3DPointWithSeed"),
           "3D projection helpers support explicit scene seeds");
    expect(!contains(shader, "reservedFloatA"),
           "old anonymous transition reserved field has been removed");
}

}

int main()
{
    testDefaultEngineState();
    testPresetTransitionUsesStableSeeds();
    testInvalidPresetAndMutationInvariants();
    testExperimentalFeatureFlags();
    testRandomizeRanges();
    testShaderUniformContract();
    testShaderSourceGuards();

    if (failures != 0) {
        std::cerr << failures << " test assertion(s) failed.\n";
        return 1;
    }

    std::cout << "All Art Forge engine tests passed.\n";
    return 0;
}
