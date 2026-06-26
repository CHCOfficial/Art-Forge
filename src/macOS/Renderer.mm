#import "macOS/Renderer.h"

#include "ArtForge/Engine.hpp"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#if AF_HAVE_METALFX
#import <MetalFX/MetalFX.h>
#endif

#include <algorithm>
#include <cmath>
#include <memory>
#include <random>
#include <string>
#include <vector>

using ArtForge::Engine;
using ArtForge::ExperimentalFeature;
using ArtForge::ParticlePattern;
using ArtForge::ShaderUniforms;

namespace {

struct GPUParticle {
    simd_float4 positionLife;
    simd_float4 velocitySeed;
    simd_float4 style;
};

static_assert(sizeof(GPUParticle) == 48);

ExperimentalFeature featureFromTag(AFExperimentalFeatureTag tag)
{
    switch (tag) {
    case AFExperimentalFeatureReactionDiffusion:
        return ExperimentalFeature::ReactionDiffusion;
    case AFExperimentalFeatureFluidSwirl:
        return ExperimentalFeature::FluidSwirl;
    case AFExperimentalFeatureAudioReactive:
        return ExperimentalFeature::AudioReactive;
    case AFExperimentalFeatureHighDensityParticles:
        return ExperimentalFeature::HighDensityParticles;
    case AFExperimentalFeatureTemporalTrails:
        return ExperimentalFeature::TemporalTrails;
    case AFExperimentalFeatureHalfResolutionPreview:
        return ExperimentalFeature::HalfResolutionPreview;
    case AFExperimentalFeatureMetalFX:
        return ExperimentalFeature::MetalFX;
    }
}

NSString *stringFromView(std::string_view value)
{
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding];
}

NSUInteger alignUp(NSUInteger value, NSUInteger alignment)
{
    return ((value + alignment - 1) / alignment) * alignment;
}

NSString *compactParticleCount(std::uint32_t count)
{
    if (count >= 1'000'000u) {
        return [NSString stringWithFormat:@"%.2fM", static_cast<double>(count) / 1'000'000.0];
    }
    return [NSString stringWithFormat:@"%.0fk", static_cast<double>(count) / 1'000.0];
}

simd_float3 jittered(simd_float3 value, float amount, std::uniform_real_distribution<float>& signedUnit, std::mt19937& rng)
{
    constexpr float patternExpansion = 1.18f;
    return simd_make_float3(value.x * patternExpansion + signedUnit(rng) * amount,
                            value.y * patternExpansion + signedUnit(rng) * amount,
                            value.z * patternExpansion + signedUnit(rng) * amount);
}

simd_float3 initialPatternPosition(ParticlePattern pattern,
                                   float u,
                                   float v,
                                   float seed,
                                   std::uniform_real_distribution<float>& signedUnit,
                                   std::mt19937& rng)
{
    constexpr float pi = 3.14159265358979323846f;
    const float tau = pi * 2.0f;

    switch (pattern) {
    case ParticlePattern::OrbitalBloom: {
        const float angle = u * tau;
        const float petals = 8.0f;
        const float radius = 0.22f + 0.62f * std::pow(std::abs(std::cos(angle * petals)), 1.45f);
        const float z = std::sin(angle * 3.0f + seed * 0.0007f) * 0.34f;
        return jittered(simd_make_float3(std::cos(angle) * radius, std::sin(angle) * radius, z), 0.018f, signedUnit, rng);
    }
    case ParticlePattern::LissajousRibbons: {
        const float phase = u * tau;
        const float lane = (v - 0.5f) * 0.16f;
        simd_float3 p = simd_make_float3(std::sin(phase * 2.0f + lane),
                                         std::sin(phase * 3.0f + pi * 0.5f + lane * 2.0f),
                                         std::cos(phase * 4.0f + lane * 3.0f) * 0.42f);
        return jittered(p * (0.62f + lane), 0.014f, signedUnit, rng);
    }
    case ParticlePattern::RoseMandala: {
        const float angle = u * tau;
        const float petals = 7.0f;
        const float radius = 0.18f + 0.72f * std::abs(std::cos(angle * petals));
        const float z = std::sin(angle * petals * 0.5f + seed * 0.0003f) * 0.28f;
        return jittered(simd_make_float3(std::cos(angle) * radius, std::sin(angle) * radius, z), 0.015f, signedUnit, rng);
    }
    case ParticlePattern::SpiralGalaxy: {
        const float arm = std::floor(u * 4.0f);
        const float local = std::fmod(u * 4.0f, 1.0f);
        const float radius = 0.08f + v * 1.05f;
        const float angle = arm * (pi * 0.5f) + radius * 5.2f + local * 0.28f + seed * 0.0001f;
        const float z = (v - 0.5f) * 0.62f + std::sin(angle * 1.4f) * 0.08f;
        return jittered(simd_make_float3(std::cos(angle) * radius, std::sin(angle) * radius, z), 0.025f, signedUnit, rng);
    }
    case ParticlePattern::VortexKnots: {
        const float knot = std::floor(u * 4.0f);
        const float local = std::fmod(u * 4.0f, 1.0f) * tau;
        const float centerAngle = knot * (pi * 0.5f) + seed * 0.0002f;
        simd_float3 center = simd_make_float3(std::cos(centerAngle) * (0.24f + knot * 0.08f),
                                              std::sin(centerAngle * 0.7f) * (0.24f + knot * 0.06f),
                                              (knot - 1.5f) * 0.20f);
        const float loopRadius = 0.12f + v * 0.14f;
        simd_float3 loop = simd_make_float3(std::cos(local) * loopRadius,
                                            std::sin(local * 2.0f) * loopRadius * 0.65f,
                                            std::sin(local) * loopRadius);
        return jittered(center + loop, 0.018f, signedUnit, rng);
    }
    case ParticlePattern::TorusKnot3D: {
        const float angle = u * tau;
        const float strip = (v - 0.5f) * 0.10f;
        const float core = 0.54f + 0.18f * std::cos(angle * 3.0f);
        const float x = (core + strip * std::cos(angle * 5.0f)) * std::cos(angle * 2.0f);
        const float y = std::sin(angle * 2.0f) * 0.42f + strip * std::sin(angle * 4.0f);
        const float z = std::sin(angle * 3.0f) * 0.28f + strip * std::cos(angle * 4.0f);
        return jittered(simd_make_float3(x, y, z), 0.012f, signedUnit, rng);
    }
    case ParticlePattern::HelixColumn3D: {
        const float height = (v * 2.0f - 1.0f) * 0.82f;
        const float angle = u * tau * 3.25f + height * 1.7f;
        const float radius = 0.32f + 0.08f * std::sin(v * tau * 4.0f + seed * 0.0003f);
        return jittered(simd_make_float3(std::cos(angle) * radius, height, std::sin(angle) * radius), 0.014f, signedUnit, rng);
    }
    case ParticlePattern::SphereLattice3D: {
        const float band = std::floor(v * 14.0f);
        const float y = ((band + 0.5f) / 14.0f) * 2.0f - 1.0f;
        const float radius = std::sqrt(std::max(0.0f, 1.0f - y * y));
        const float angle = (u + std::floor(u * 18.0f) * 0.002f) * tau;
        return jittered(simd_make_float3(std::cos(angle) * radius * 0.74f,
                                          y * 0.74f,
                                          std::sin(angle) * radius * 0.74f),
                        0.010f,
                        signedUnit,
                        rng);
    }
    case ParticlePattern::MobiusRibbon3D: {
        const float angle = u * tau;
        const float strip = (v * 2.0f - 1.0f) * 0.22f;
        const float ring = 0.72f + strip * std::cos(angle * 0.5f);
        const float x = ring * std::cos(angle);
        const float y = strip * std::sin(angle * 0.5f) * 1.35f;
        const float z = ring * std::sin(angle);
        return jittered(simd_make_float3(x, y, z), 0.012f, signedUnit, rng);
    }
    case ParticlePattern::FlowWeave:
    default: {
        const float x = (u * 2.0f - 1.0f) * 1.15f;
        const float lane = std::floor(v * 5.0f);
        const float offset = (lane - 2.0f) * 0.16f;
        const float y = std::sin(x * 4.0f + lane * 0.95f + seed * 0.0002f) * 0.24f + offset;
        const float z = std::sin(x * 2.2f + lane * 0.8f) * 0.32f;
        return jittered(simd_make_float3(x, y, z), 0.018f, signedUnit, rng);
    }
    }
}

NSArray<NSString *> *particlePatternNames()
{
    return @[
        @"Flow Weave",
        @"Orbital Bloom",
        @"Lissajous Ribbons",
        @"Rose Mandala",
        @"Spiral Galaxy",
        @"Vortex Knots",
        @"Torus Knot 3D",
        @"Helix Column 3D",
        @"Sphere Lattice 3D",
        @"Mobius Ribbon 3D"
    ];
}

}

@interface AFRenderer ()
{
    MTKView *_view;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _library;
    id<MTLRenderPipelineState> _compositionPipeline;
    id<MTLRenderPipelineState> _particlePipeline;
    id<MTLRenderPipelineState> _presentPipeline;
    id<MTLComputePipelineState> _particleComputePipeline;
    id<MTLBuffer> _particleBuffer;
    NSUInteger _particleCapacity;
    CFTimeInterval _lastFrameTime;

    id<MTLTexture> _metalFXInputTexture;
    id<MTLTexture> _metalFXOutputTexture;
    NSUInteger _metalFXInputWidth;
    NSUInteger _metalFXInputHeight;
    NSUInteger _metalFXOutputWidth;
    NSUInteger _metalFXOutputHeight;
    float _mouseSceneX;
    float _mouseSceneY;
    float _mouseInfluence;
    BOOL _hasMouseSample;
    double _smoothedFPS;
    double _smoothedFrameMs;
    double _lastFrameIntervalMs;
    NSUInteger _lastDrawableWidth;
    NSUInteger _lastDrawableHeight;
    NSUInteger _lastRenderWidth;
    NSUInteger _lastRenderHeight;
    BOOL _lastMetalFXActive;
    BOOL _droneMode;
    BOOL _droneForward;
    BOOL _droneBack;
    BOOL _droneLeft;
    BOOL _droneRight;
    BOOL _droneUp;
    BOOL _droneDown;
    simd_float3 _droneCamera;
    simd_float3 _droneVelocity;
    simd_float3 _droneForwardVector;
    simd_float3 _droneRightVector;
    simd_float3 _droneUpVector;
    float _droneYaw;
    float _dronePitch;
    float _droneRoll;
    float _droneYawVelocity;
    float _dronePitchVelocity;
    float _droneThrottle;

    id<MTLBuffer> _laserStatsBuffer;
    simd_float3 _laserOrigin;
    simd_float3 _laserDirection;
    double _laserAge;
    double _laserLastFireTime;
    std::uint32_t _laserSequence;
    BOOL _laserFreshPending;
    NSUInteger _laserShots;
    NSUInteger _laserChunks;
    NSUInteger _laserParticleHits;

#if AF_HAVE_METALFX
    id<MTLFXSpatialScaler> _spatialScaler API_AVAILABLE(macos(13.0));
#endif

    std::unique_ptr<Engine> _engine;
}
@end

@implementation AFRenderer

- (instancetype)initWithView:(MTKView *)view
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _view = view;
    _device = view.device ?: MTLCreateSystemDefaultDevice();
    _view.device = _device;
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _view.framebufferOnly = NO;
    _view.preferredFramesPerSecond = 60;
    _view.clearColor = MTLClearColorMake(0.01, 0.01, 0.018, 1.0);

    _commandQueue = [_device newCommandQueue];
    _engine = std::make_unique<Engine>();

    [self buildPipelines];
    [self detectMetalFXSupport];
    [self ensureParticleBuffer];

    _lastFrameTime = CACurrentMediaTime();
    _smoothedFPS = 60.0;
    _smoothedFrameMs = 1000.0 / 60.0;
    _lastFrameIntervalMs = 1000.0 / 60.0;
    _droneMode = NO;
    _droneCamera = simd_make_float3(0.0f, 0.0f, 3.2f);
    _droneVelocity = simd_make_float3(0.0f, 0.0f, 0.0f);
    _droneYaw = 0.0f;
    _dronePitch = 0.0f;
    _droneRoll = 0.0f;
    _droneYawVelocity = 0.0f;
    _dronePitchVelocity = 0.0f;
    _droneThrottle = 0.0f;
    _droneForwardVector = simd_make_float3(0.0f, 0.0f, -1.0f);
    _droneRightVector = simd_make_float3(1.0f, 0.0f, 0.0f);
    _droneUpVector = simd_make_float3(0.0f, 1.0f, 0.0f);
    _laserOrigin = _droneCamera;
    _laserDirection = _droneForwardVector;
    _laserAge = 10.0;
    _laserLastFireTime = -10.0;
    _laserSequence = 0u;
    _laserFreshPending = NO;
    _laserStatsBuffer = [_device newBufferWithLength:sizeof(std::uint32_t)
                                             options:MTLResourceStorageModeShared];
    _laserStatsBuffer.label = @"Art Forge Laser Stats";
    return self;
}

- (NSArray<NSString *> *)presetNames
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (const auto& preset : _engine->presets()) {
        [names addObject:stringFromView(preset.name)];
    }
    return names;
}

- (NSArray<NSString *> *)particlePatternNames
{
    return particlePatternNames();
}

- (void)loadPresetAtIndex:(NSUInteger)index
{
    _engine->loadPreset(index);
}

- (void)randomizeComposition
{
    _engine->randomize();
}

- (void)mutateComposition
{
    _engine->mutate(0.55f);
}

- (void)setParticlePatternIndex:(NSInteger)index
{
    _engine->setParticlePattern(static_cast<ParticlePattern>(std::clamp<NSInteger>(index, 0, 9)));
    [self resetParticleBuffer];
}

- (void)togglePaused
{
    _engine->togglePaused();
}

- (void)updateDroneBasis
{
    const float cp = std::cos(_dronePitch);
    _droneForwardVector = simd_normalize(simd_make_float3(std::sin(_droneYaw) * cp,
                                                          std::sin(_dronePitch),
                                                          -std::cos(_droneYaw) * cp));
    const simd_float3 worldUp = simd_make_float3(0.0f, 1.0f, 0.0f);
    simd_float3 baseRight = simd_normalize(simd_cross(_droneForwardVector, worldUp));
    simd_float3 baseUp = simd_normalize(simd_cross(baseRight, _droneForwardVector));
    const float cr = std::cos(_droneRoll);
    const float sr = std::sin(_droneRoll);
    _droneRightVector = simd_normalize(baseRight * cr + baseUp * sr);
    _droneUpVector = simd_normalize(baseUp * cr - baseRight * sr);
}

- (void)toggleDroneMode
{
    [self setDroneModeEnabled:!_droneMode];
}

- (void)setDroneModeEnabled:(BOOL)enabled
{
    _droneMode = enabled;
    _mouseInfluence = 0.0f;
    if (!enabled) {
        _droneForward = NO;
        _droneBack = NO;
        _droneLeft = NO;
        _droneRight = NO;
        _droneUp = NO;
        _droneDown = NO;
        _droneVelocity = simd_make_float3(0.0f, 0.0f, 0.0f);
        _droneYawVelocity = 0.0f;
        _dronePitchVelocity = 0.0f;
        _droneThrottle = 0.0f;
        _droneRoll = 0.0f;
    }
    [self updateDroneBasis];
}

- (BOOL)isDroneModeEnabled
{
    return _droneMode;
}

- (void)setDroneMovementForward:(BOOL)forward
                           back:(BOOL)back
                           left:(BOOL)left
                          right:(BOOL)right
                             up:(BOOL)up
                           down:(BOOL)down
{
    _droneForward = forward;
    _droneBack = back;
    _droneLeft = left;
    _droneRight = right;
    _droneUp = up;
    _droneDown = down;
}

- (void)applyDroneMouseDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY
{
    if (!_droneMode) {
        return;
    }

    constexpr float sensitivity = 0.00042f;
    _droneYawVelocity += static_cast<float>(deltaX) * sensitivity;
    _dronePitchVelocity -= static_cast<float>(deltaY) * sensitivity;
    _droneYawVelocity = std::clamp(_droneYawVelocity, -0.065f, 0.065f);
    _dronePitchVelocity = std::clamp(_dronePitchVelocity, -0.048f, 0.048f);
}

- (void)fireDroneLaser
{
    if (!_droneMode) {
        return;
    }

    const CFTimeInterval now = CACurrentMediaTime();
    if (now - _laserLastFireTime < 0.13) {
        return;
    }

    _laserLastFireTime = now;
    _laserAge = 0.0;
    _laserFreshPending = YES;
    ++_laserSequence;
    ++_laserShots;
    _laserOrigin = _droneCamera + _droneForwardVector * 0.10f;
    _laserDirection = simd_normalize(_droneForwardVector);
    _droneVelocity -= _droneForwardVector * 0.045f;
}

- (void)updateLaserWithDelta:(double)frameDelta
{
    _laserAge += std::clamp(frameDelta, 0.0, 0.25);
}

- (void)updateDroneCameraWithDelta:(double)frameDelta
{
    if (!_droneMode) {
        return;
    }

    const float dt = static_cast<float>(std::clamp(frameDelta, 0.0, 1.0 / 12.0));
    const float frameScale = dt * 60.0f;

    _droneYaw += _droneYawVelocity * frameScale;
    _dronePitch += _dronePitchVelocity * frameScale;
    _dronePitch = std::clamp(_dronePitch, -1.28f, 1.28f);
    _droneYawVelocity *= std::exp(-9.0f * dt);
    _dronePitchVelocity *= std::exp(-10.5f * dt);

    const float lateralIntent = (_droneRight ? 1.0f : 0.0f) - (_droneLeft ? 1.0f : 0.0f);
    const float targetRoll = std::clamp(-lateralIntent * 0.28f - _droneYawVelocity * 2.4f, -0.42f, 0.42f);
    _droneRoll += (targetRoll - _droneRoll) * std::min(1.0f, dt * 5.5f);
    [self updateDroneBasis];

    simd_float3 thrust = simd_make_float3(0.0f, 0.0f, 0.0f);
    if (_droneForward) {
        thrust += _droneForwardVector;
    }
    if (_droneBack) {
        thrust -= _droneForwardVector * 0.72f;
    }
    if (_droneRight) {
        thrust += _droneRightVector * 0.82f;
    }
    if (_droneLeft) {
        thrust -= _droneRightVector * 0.82f;
    }
    if (_droneUp) {
        thrust += simd_make_float3(0.0f, 1.0f, 0.0f) * 0.82f;
    }
    if (_droneDown) {
        thrust -= simd_make_float3(0.0f, 1.0f, 0.0f) * 0.82f;
    }

    const float lengthSquared = thrust.x * thrust.x + thrust.y * thrust.y + thrust.z * thrust.z;
    if (lengthSquared > 0.0001f) {
        thrust /= std::sqrt(lengthSquared);
    }
    _droneThrottle += ((lengthSquared > 0.0001f ? 1.0f : 0.0f) - _droneThrottle) * std::min(1.0f, dt * 3.8f);
    _droneVelocity += thrust * (2.65f * dt);
    _droneVelocity -= _droneVelocity * (1.25f * dt);

    const float speed = simd_length(_droneVelocity);
    const float maxSpeed = 2.15f;
    if (speed > maxSpeed) {
        _droneVelocity = _droneVelocity / speed * maxSpeed;
    }

    _droneCamera += _droneVelocity * dt;
    _droneCamera.x = std::clamp(_droneCamera.x, -4.0f, 4.0f);
    _droneCamera.y = std::clamp(_droneCamera.y, -3.0f, 3.0f);
    _droneCamera.z = std::clamp(_droneCamera.z, -4.0f, 4.0f);
}

- (void)toggleExperimentalFeature:(AFExperimentalFeatureTag)feature
{
    const auto beforeCount = _engine->targetParticleCount();
    _engine->toggleExperimental(featureFromTag(feature));
    if (beforeCount != _engine->targetParticleCount()) {
        [self ensureParticleBuffer];
    }
}

- (BOOL)isPresetActive:(NSUInteger)index
{
    return _engine->currentPresetIndex() == index;
}

- (BOOL)isParticlePatternActive:(NSInteger)index
{
    return static_cast<NSInteger>(_engine->particlePattern()) == index;
}

- (BOOL)isExperimentalFeatureEnabled:(AFExperimentalFeatureTag)feature
{
    const auto& options = _engine->experimentalOptions();
    switch (feature) {
    case AFExperimentalFeatureReactionDiffusion:
        return options.reactionDiffusion;
    case AFExperimentalFeatureFluidSwirl:
        return options.fluidSwirl;
    case AFExperimentalFeatureAudioReactive:
        return options.audioReactive;
    case AFExperimentalFeatureHighDensityParticles:
        return options.highDensityParticles;
    case AFExperimentalFeatureTemporalTrails:
        return options.temporalTrails;
    case AFExperimentalFeatureHalfResolutionPreview:
        return options.halfResolutionPreview;
    case AFExperimentalFeatureMetalFX:
        return options.metalFX;
    }
}

- (BOOL)isExperimentalFeatureAvailable:(AFExperimentalFeatureTag)feature
{
    if (feature == AFExperimentalFeatureMetalFX) {
        return _engine->experimentalOptions().metalFXRuntimeAvailable;
    }
    return YES;
}

- (NSString *)metalFXStatus
{
    const auto& status = _engine->experimentalOptions().metalFXStatus;
    return [NSString stringWithUTF8String:status.c_str()];
}

- (NSString *)statusLine
{
    const double particles = static_cast<double>(_engine->targetParticleCount()) / 1'000'000.0;
    NSString *preset = stringFromView(_engine->currentPresetName());
    NSString *mode = @"Direct";
    const auto& options = _engine->experimentalOptions();
    if (options.metalFX && options.metalFXRuntimeAvailable) {
        mode = options.halfResolutionPreview ? @"MetalFX 0.5x" : @"MetalFX 0.7x";
    }
    if (_droneMode) {
        mode = [mode stringByAppendingString:@" + Drone"];
    }
    NSString *pause = _engine->isPaused() ? @" - Paused" : @"";
    NSArray<NSString *> *patterns = particlePatternNames();
    NSInteger patternIndex = static_cast<NSInteger>(_engine->particlePattern());
    NSString *pattern = (patternIndex >= 0 && patternIndex < static_cast<NSInteger>(patterns.count)) ? patterns[static_cast<NSUInteger>(patternIndex)] : @"Pattern";
    return [NSString stringWithFormat:@"Art Forge - %@ - %@ - %.2fM particles - %@%@",
                                      preset,
                                      pattern,
                                      particles,
                                      mode,
                                      pause];
}

- (NSString *)performanceHUDText
{
    NSArray<NSString *> *patterns = particlePatternNames();
    NSInteger patternIndex = static_cast<NSInteger>(_engine->particlePattern());
    NSString *pattern = (patternIndex >= 0 && patternIndex < static_cast<NSInteger>(patterns.count)) ? patterns[static_cast<NSUInteger>(patternIndex)] : @"Pattern";
    const auto& options = _engine->experimentalOptions();
    NSString *mode = @"Direct";
    if (_lastMetalFXActive) {
        mode = options.halfResolutionPreview ? @"MetalFX Spatial 50%" : @"MetalFX Spatial 70%";
    }
    const double renderScale = _lastDrawableWidth > 0 ? (static_cast<double>(_lastRenderWidth) / static_cast<double>(_lastDrawableWidth)) : 1.0;
    NSString *mouse = _mouseInfluence > 0.05f ? @"active" : @"idle";
    NSString *drone = _droneMode ? @"on" : @"off";
    NSString *audio = options.audioReactive ? @"on" : @"off";
    NSString *density = options.highDensityParticles ? @"high" : @"standard";

    return [NSString stringWithFormat:
            @"PERFORMANCE\n"
             "FPS        %5.1f\n"
             "Frame      %5.2f ms\n"
             "Particles  %@ (%@)\n"
             "Preview    %@\n"
             "Render     %zux%zu -> %zux%zu\n"
             "Scale      %.2fx\n"
             "Pattern    %@\n"
             "Drone      %@  xyz %.1f %.1f %.1f\n"
             "Laser      %zu shots  %zu chunks  %zu hits\n"
             "Mouse      %@\n"
             "Audio      %@",
             _smoothedFPS,
             _smoothedFrameMs,
             compactParticleCount(_engine->targetParticleCount()),
             density,
             mode,
             _lastRenderWidth,
             _lastRenderHeight,
             _lastDrawableWidth,
             _lastDrawableHeight,
             renderScale,
             pattern,
             drone,
             _droneCamera.x,
             _droneCamera.y,
             _droneCamera.z,
             _laserShots,
             _laserChunks,
             _laserParticleHits,
             mouse,
             audio];
}

- (BOOL)exportPNGToURL:(NSURL *)url
                 width:(NSUInteger)width
                height:(NSUInteger)height
                 error:(NSError **)error
{
    width = std::max<NSUInteger>(width, 64);
    height = std::max<NSUInteger>(height, 64);

    MTLTextureDescriptor *textureDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    textureDescriptor.storageMode = MTLStorageModePrivate;

    id<MTLTexture> targetTexture = [_device newTextureWithDescriptor:textureDescriptor];
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    ShaderUniforms uniforms = _engine->uniforms(static_cast<float>(width), static_cast<float>(height));
    [self encodeSceneToTexture:targetTexture
                 commandBuffer:commandBuffer
                       uniforms:uniforms
                updateParticles:NO];

    const NSUInteger bytesPerPixel = 4;
    const NSUInteger tightBytesPerRow = width * bytesPerPixel;
    const NSUInteger bytesPerRow = alignUp(tightBytesPerRow, 256);
    const NSUInteger byteCount = bytesPerRow * height;
    id<MTLBuffer> readbackBuffer = [_device newBufferWithLength:byteCount
                                                        options:MTLResourceStorageModeShared];

    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder copyFromTexture:targetTexture
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(width, height, 1)
                        toBuffer:readbackBuffer
               destinationOffset:0
          destinationBytesPerRow:bytesPerRow
        destinationBytesPerImage:byteCount];
    [blitEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    if (commandBuffer.error) {
        if (error) {
            *error = commandBuffer.error;
        }
        return NO;
    }

    NSMutableData *rgbaData = [NSMutableData dataWithLength:tightBytesPerRow * height];
    const auto *source = static_cast<const std::uint8_t *>(readbackBuffer.contents);
    auto *destination = static_cast<std::uint8_t *>(rgbaData.mutableBytes);
    for (NSUInteger row = 0; row < height; ++row) {
        const std::uint8_t *sourceRow = source + row * bytesPerRow;
        std::uint8_t *destinationRow = destination + row * tightBytesPerRow;
        for (NSUInteger column = 0; column < width; ++column) {
            const NSUInteger offset = column * bytesPerPixel;
            destinationRow[offset + 0] = sourceRow[offset + 2];
            destinationRow[offset + 1] = sourceRow[offset + 1];
            destinationRow[offset + 2] = sourceRow[offset + 0];
            destinationRow[offset + 3] = sourceRow[offset + 3];
        }
    }

    NSBitmapImageRep *bitmap =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
                                                pixelsWide:width
                                                pixelsHigh:height
                                             bitsPerSample:8
                                           samplesPerPixel:4
                                                  hasAlpha:YES
                                                  isPlanar:NO
                                            colorSpaceName:NSDeviceRGBColorSpace
                                              bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                                               bytesPerRow:tightBytesPerRow
                                              bitsPerPixel:32];
    std::memcpy(bitmap.bitmapData, rgbaData.bytes, rgbaData.length);

    NSData *pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [pngData writeToURL:url options:NSDataWritingAtomic error:error];
}

- (void)drawInMTKView:(MTKView *)view
{
    @autoreleasepool {
        CFTimeInterval now = CACurrentMediaTime();
        const double frameDelta = now - _lastFrameTime;
        _engine->tick(frameDelta);
        [self updateDroneCameraWithDelta:frameDelta];
        [self updateLaserWithDelta:frameDelta];
        _lastFrameTime = now;

        [self ensureParticleBuffer];

        id<CAMetalDrawable> drawable = view.currentDrawable;
        if (!drawable) {
            return;
        }

        const CGSize drawableSize = view.drawableSize;
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        NSUInteger renderWidth = static_cast<NSUInteger>(drawableSize.width);
        NSUInteger renderHeight = static_cast<NSUInteger>(drawableSize.height);
        BOOL usedMetalFX = NO;

        if ([self prepareMetalFXForOutputWidth:static_cast<NSUInteger>(drawableSize.width)
                                        height:static_cast<NSUInteger>(drawableSize.height)]) {
            usedMetalFX = YES;
            renderWidth = _metalFXInputWidth;
            renderHeight = _metalFXInputHeight;
            ShaderUniforms uniforms = [self uniformsForRenderWidth:static_cast<float>(_metalFXInputWidth)
                                                            height:static_cast<float>(_metalFXInputHeight)
                                                  mouseAspectWidth:static_cast<float>(drawableSize.width)
                                               mouseAspectHeight:static_cast<float>(drawableSize.height)
                                                      includeMouse:YES];
            [self encodeSceneToTexture:_metalFXInputTexture
                         commandBuffer:commandBuffer
                               uniforms:uniforms
                        updateParticles:YES];

#if AF_HAVE_METALFX
            if (@available(macOS 13.0, *)) {
                _spatialScaler.colorTexture = _metalFXInputTexture;
                _spatialScaler.outputTexture = _metalFXOutputTexture;
                _spatialScaler.inputContentWidth = _metalFXInputWidth;
                _spatialScaler.inputContentHeight = _metalFXInputHeight;
                [_spatialScaler encodeToCommandBuffer:commandBuffer];
            }
#endif

            [self encodePresentTexture:_metalFXOutputTexture
                         commandBuffer:commandBuffer
                            toDrawable:drawable];
        } else {
            ShaderUniforms uniforms = [self uniformsForRenderWidth:static_cast<float>(drawableSize.width)
                                                            height:static_cast<float>(drawableSize.height)
                                                  mouseAspectWidth:static_cast<float>(drawableSize.width)
                                               mouseAspectHeight:static_cast<float>(drawableSize.height)
                                                      includeMouse:YES];
            [self encodeSceneToTexture:drawable.texture
                         commandBuffer:commandBuffer
                               uniforms:uniforms
                        updateParticles:YES];
        }

        [self updatePerformanceWithFrameDelta:frameDelta
                                  renderWidth:renderWidth
                                 renderHeight:renderHeight
                                drawableWidth:static_cast<NSUInteger>(drawableSize.width)
                               drawableHeight:static_cast<NSUInteger>(drawableSize.height)
                                      metalFX:usedMetalFX];
        _laserFreshPending = NO;
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    (void)view;
    (void)size;
    _metalFXInputTexture = nil;
    _metalFXOutputTexture = nil;
#if AF_HAVE_METALFX
    if (@available(macOS 13.0, *)) {
        _spatialScaler = nil;
    }
#endif
}

- (ShaderUniforms)uniformsForRenderWidth:(float)width
                                  height:(float)height
                        mouseAspectWidth:(float)mouseAspectWidth
                      mouseAspectHeight:(float)mouseAspectHeight
                            includeMouse:(BOOL)includeMouse
{
    ShaderUniforms uniforms = _engine->uniforms(width, height);
    uniforms.droneMode = _droneMode ? 1u : 0u;
    uniforms.droneCameraX = _droneCamera.x;
    uniforms.droneCameraY = _droneCamera.y;
    uniforms.droneCameraZ = _droneCamera.z;
    uniforms.droneYaw = _droneYaw;
    uniforms.droneForwardX = _droneForwardVector.x;
    uniforms.droneForwardY = _droneForwardVector.y;
    uniforms.droneForwardZ = _droneForwardVector.z;
    uniforms.dronePitch = _dronePitch;
    uniforms.droneRightX = _droneRightVector.x;
    uniforms.droneRightY = _droneRightVector.y;
    uniforms.droneRightZ = _droneRightVector.z;
    uniforms.droneFov = 1.05f;
    uniforms.droneUpX = _droneUpVector.x;
    uniforms.droneUpY = _droneUpVector.y;
    uniforms.droneUpZ = _droneUpVector.z;
    const BOOL laserVisible = _laserAge < 0.24;
    uniforms.laserActive = (_droneMode && laserVisible) ? 1u : 0u;
    uniforms.laserFresh = (_droneMode && _laserFreshPending) ? 1u : 0u;
    uniforms.laserSequence = _laserSequence;
    uniforms.laserOriginX = _laserOrigin.x;
    uniforms.laserOriginY = _laserOrigin.y;
    uniforms.laserOriginZ = _laserOrigin.z;
    uniforms.laserAge = static_cast<float>(_laserAge);
    uniforms.laserDirectionX = _laserDirection.x;
    uniforms.laserDirectionY = _laserDirection.y;
    uniforms.laserDirectionZ = _laserDirection.z;
    uniforms.laserRange = 5.5f;
    uniforms.laserRadius = 0.11f;
    uniforms.laserStrength = 3.8f;
    uniforms.laserVisual = _droneMode ? std::clamp(1.0f - static_cast<float>(_laserAge / 0.24), 0.0f, 1.0f) : 0.0f;

    if (_droneMode) {
        _mouseInfluence *= 0.70f;
        uniforms.mouseStrength = 0.0f;
        uniforms.mouseActive = 0u;
        return uniforms;
    }

    if (!includeMouse || !_view.window) {
        _mouseInfluence *= 0.82f;
        uniforms.mouseStrength = _mouseInfluence;
        uniforms.mouseActive = _mouseInfluence > 0.01f ? 1u : 0u;
        uniforms.mouseX = _mouseSceneX;
        uniforms.mouseY = _mouseSceneY;
        return uniforms;
    }

    NSRect bounds = _view.bounds;
    NSPoint windowPoint = _view.window.mouseLocationOutsideOfEventStream;
    NSPoint viewPoint = [_view convertPoint:windowPoint fromView:nil];
    const BOOL inside = NSPointInRect(viewPoint, bounds);

    const float targetInfluence = inside ? 1.0f : 0.0f;
    _mouseInfluence += (targetInfluence - _mouseInfluence) * (inside ? 0.24f : 0.10f);

    if (inside && bounds.size.width > 1.0 && bounds.size.height > 1.0) {
        const float aspect = mouseAspectWidth / std::max(1.0f, mouseAspectHeight);
        const float normalizedX = static_cast<float>(viewPoint.x / bounds.size.width);
        float normalizedY = static_cast<float>(viewPoint.y / bounds.size.height);
        if (_view.isFlipped) {
            normalizedY = 1.0f - normalizedY;
        }
        const float targetX = ((normalizedX * 2.0f) - 1.0f) * aspect;
        const float targetY = (normalizedY * 2.0f) - 1.0f;
        if (!_hasMouseSample) {
            _mouseSceneX = targetX;
            _mouseSceneY = targetY;
            _hasMouseSample = YES;
        } else {
            _mouseSceneX += (targetX - _mouseSceneX) * 0.35f;
            _mouseSceneY += (targetY - _mouseSceneY) * 0.35f;
        }
    }

    uniforms.mouseX = _mouseSceneX;
    uniforms.mouseY = _mouseSceneY;
    uniforms.mouseStrength = _mouseInfluence;
    uniforms.mouseRadius = 0.30f;
    uniforms.mouseActive = _mouseInfluence > 0.01f ? 1u : 0u;
    return uniforms;
}

- (void)updatePerformanceWithFrameDelta:(double)frameDelta
                            renderWidth:(NSUInteger)renderWidth
                           renderHeight:(NSUInteger)renderHeight
                          drawableWidth:(NSUInteger)drawableWidth
                         drawableHeight:(NSUInteger)drawableHeight
                                metalFX:(BOOL)metalFX
{
    const double frameMs = std::clamp(frameDelta * 1000.0, 0.0, 250.0);
    const double fps = frameDelta > 0.0001 ? std::min(999.0, 1.0 / frameDelta) : 0.0;
    const double blend = 0.08;
    _lastFrameIntervalMs = frameMs;
    _smoothedFrameMs = _smoothedFrameMs * (1.0 - blend) + frameMs * blend;
    _smoothedFPS = _smoothedFPS * (1.0 - blend) + fps * blend;
    _lastRenderWidth = renderWidth;
    _lastRenderHeight = renderHeight;
    _lastDrawableWidth = drawableWidth;
    _lastDrawableHeight = drawableHeight;
    _lastMetalFXActive = metalFX;
}


- (void)buildPipelines
{
    NSError *error = nil;
    NSURL *shaderURL = [[NSBundle mainBundle] URLForResource:@"ArtForge"
                                               withExtension:@"metal"
                                                subdirectory:@"Shaders"];
    NSString *shaderSource = shaderURL ? [NSString stringWithContentsOfURL:shaderURL
                                                                   encoding:NSUTF8StringEncoding
                                                                      error:&error] : nil;
    if (!shaderSource) {
        NSLog(@"Art Forge: failed to load shader source: %@", error);
        return;
    }

    _library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!_library) {
        NSLog(@"Art Forge: failed to compile Metal library: %@", error);
        return;
    }

    id<MTLFunction> fullscreenVertex = [_library newFunctionWithName:@"fullscreenVertex"];
    id<MTLFunction> compositionFragment = [_library newFunctionWithName:@"compositionFragment"];
    id<MTLFunction> particleVertex = [_library newFunctionWithName:@"particleVertex"];
    id<MTLFunction> particleFragment = [_library newFunctionWithName:@"particleFragment"];
    id<MTLFunction> presentFragment = [_library newFunctionWithName:@"presentFragment"];
    id<MTLFunction> updateParticles = [_library newFunctionWithName:@"updateParticles"];

    MTLRenderPipelineDescriptor *compositionDescriptor = [MTLRenderPipelineDescriptor new];
    compositionDescriptor.label = @"Composition Pipeline";
    compositionDescriptor.vertexFunction = fullscreenVertex;
    compositionDescriptor.fragmentFunction = compositionFragment;
    compositionDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _compositionPipeline = [_device newRenderPipelineStateWithDescriptor:compositionDescriptor error:&error];
    if (!_compositionPipeline) {
        NSLog(@"Art Forge: failed to create composition pipeline: %@", error);
    }

    MTLRenderPipelineDescriptor *particleDescriptor = [MTLRenderPipelineDescriptor new];
    particleDescriptor.label = @"Particle Pipeline";
    particleDescriptor.vertexFunction = particleVertex;
    particleDescriptor.fragmentFunction = particleFragment;
    particleDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassPoint;
    particleDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    particleDescriptor.colorAttachments[0].blendingEnabled = YES;
    particleDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    particleDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    particleDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    particleDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    particleDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    particleDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _particlePipeline = [_device newRenderPipelineStateWithDescriptor:particleDescriptor error:&error];
    if (!_particlePipeline) {
        NSLog(@"Art Forge: failed to create particle pipeline: %@", error);
    }

    MTLRenderPipelineDescriptor *presentDescriptor = [MTLRenderPipelineDescriptor new];
    presentDescriptor.label = @"MetalFX Present Pipeline";
    presentDescriptor.vertexFunction = fullscreenVertex;
    presentDescriptor.fragmentFunction = presentFragment;
    presentDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _presentPipeline = [_device newRenderPipelineStateWithDescriptor:presentDescriptor error:&error];
    if (!_presentPipeline) {
        NSLog(@"Art Forge: failed to create present pipeline: %@", error);
    }

    _particleComputePipeline = [_device newComputePipelineStateWithFunction:updateParticles error:&error];
    if (!_particleComputePipeline) {
        NSLog(@"Art Forge: failed to create particle compute pipeline: %@", error);
    }
}

- (void)detectMetalFXSupport
{
#if AF_HAVE_METALFX
    if (@available(macOS 13.0, *)) {
        if (NSClassFromString(@"MTLFXSpatialScalerDescriptor") &&
            [MTLFXSpatialScalerDescriptor supportsDevice:_device]) {
            _engine->setMetalFXRuntimeAvailable(true, "MetalFX spatial scaler is available on this Mac.");
            return;
        }
        _engine->setMetalFXRuntimeAvailable(false, "MetalFX is present, but this GPU does not report spatial-scaler support.");
        return;
    }
    _engine->setMetalFXRuntimeAvailable(false, "MetalFX requires macOS 13 or newer.");
#else
    _engine->setMetalFXRuntimeAvailable(false, "This build was compiled without the MetalFX SDK.");
#endif
}

- (void)ensureParticleBuffer
{
    const NSUInteger targetCount = _engine->targetParticleCount();
    if (_particleBuffer && _particleCapacity == targetCount) {
        return;
    }

    std::vector<GPUParticle> particles(targetCount);
    std::mt19937 rng(static_cast<std::uint32_t>(targetCount ^ 0xA7F047u));
    std::uniform_real_distribution<float> unit(0.0f, 1.0f);
    std::uniform_real_distribution<float> signedUnit(-1.0f, 1.0f);
    const ParticlePattern pattern = _engine->particlePattern();

    for (NSUInteger index = 0; index < targetCount; ++index) {
        const float seed = unit(rng) * 10000.0f;
        GPUParticle& particle = particles[index];
        const float anchorU = unit(rng);
        const float anchorV = unit(rng);
        const simd_float3 position = initialPatternPosition(pattern, anchorU, anchorV, seed, signedUnit, rng);
        particle.positionLife = simd_make_float4(position.x, position.y, position.z, 0.65f + unit(rng) * 0.35f);
        particle.velocitySeed = simd_make_float4(signedUnit(rng) * 0.012f,
                                                 signedUnit(rng) * 0.012f,
                                                 signedUnit(rng) * 0.012f,
                                                 seed);
        particle.style = simd_make_float4(unit(rng),
                                          0.55f + unit(rng) * 1.45f,
                                          anchorU,
                                          anchorV);
    }

    _particleBuffer = [_device newBufferWithBytes:particles.data()
                                           length:particles.size() * sizeof(GPUParticle)
                                          options:MTLResourceStorageModeShared];
    _particleBuffer.label = @"Art Forge Particle Buffer";
    _particleCapacity = targetCount;
}

- (void)resetParticleBuffer
{
    _particleBuffer = nil;
    _particleCapacity = 0;
    [self ensureParticleBuffer];
}

- (BOOL)prepareMetalFXForOutputWidth:(NSUInteger)outputWidth height:(NSUInteger)outputHeight
{
    const auto& options = _engine->experimentalOptions();
    if (!options.metalFX || !options.metalFXRuntimeAvailable || outputWidth < 128 || outputHeight < 128) {
        return NO;
    }

#if AF_HAVE_METALFX
    if (!@available(macOS 13.0, *)) {
        return NO;
    }

    const float scale = options.halfResolutionPreview ? 0.5f : 0.7f;
    const NSUInteger inputWidth = std::max<NSUInteger>(64, static_cast<NSUInteger>(std::floor(outputWidth * scale)));
    const NSUInteger inputHeight = std::max<NSUInteger>(64, static_cast<NSUInteger>(std::floor(outputHeight * scale)));

    if (_spatialScaler &&
        _metalFXInputTexture &&
        _metalFXOutputTexture &&
        _metalFXInputWidth == inputWidth &&
        _metalFXInputHeight == inputHeight &&
        _metalFXOutputWidth == outputWidth &&
        _metalFXOutputHeight == outputHeight) {
        return YES;
    }

    _metalFXInputTexture = nil;
    _metalFXOutputTexture = nil;
    _spatialScaler = nil;

    MTLFXSpatialScalerDescriptor *descriptor = [MTLFXSpatialScalerDescriptor new];
    descriptor.colorTextureFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.outputTextureFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.inputWidth = inputWidth;
    descriptor.inputHeight = inputHeight;
    descriptor.outputWidth = outputWidth;
    descriptor.outputHeight = outputHeight;
    descriptor.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;

    _spatialScaler = [descriptor newSpatialScalerWithDevice:_device];
    if (!_spatialScaler) {
        _engine->setMetalFXRuntimeAvailable(false, "MetalFX scaler creation failed for the current drawable size.");
        return NO;
    }

    MTLTextureDescriptor *inputDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:inputWidth
                                                          height:inputHeight
                                                       mipmapped:NO];
    inputDescriptor.storageMode = MTLStorageModePrivate;
    inputDescriptor.usage = _spatialScaler.colorTextureUsage | MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    _metalFXInputTexture = [_device newTextureWithDescriptor:inputDescriptor];
    _metalFXInputTexture.label = @"MetalFX Input Texture";

    MTLTextureDescriptor *outputDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:outputWidth
                                                          height:outputHeight
                                                       mipmapped:NO];
    outputDescriptor.storageMode = MTLStorageModePrivate;
    outputDescriptor.usage = _spatialScaler.outputTextureUsage | MTLTextureUsageShaderRead;
    _metalFXOutputTexture = [_device newTextureWithDescriptor:outputDescriptor];
    _metalFXOutputTexture.label = @"MetalFX Output Texture";

    _metalFXInputWidth = inputWidth;
    _metalFXInputHeight = inputHeight;
    _metalFXOutputWidth = outputWidth;
    _metalFXOutputHeight = outputHeight;
    return YES;
#else
    return NO;
#endif
}

- (void)encodeSceneToTexture:(id<MTLTexture>)targetTexture
               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                     uniforms:(const ShaderUniforms&)uniforms
              updateParticles:(BOOL)updateParticles
{
    if (updateParticles && _particleComputePipeline) {
        if (!_laserStatsBuffer) {
            _laserStatsBuffer = [_device newBufferWithLength:sizeof(std::uint32_t)
                                                     options:MTLResourceStorageModeShared];
            _laserStatsBuffer.label = @"Art Forge Laser Stats";
        }
        if (uniforms.laserFresh != 0u) {
            *static_cast<std::uint32_t *>(_laserStatsBuffer.contents) = 0u;
        }

        id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
        computeEncoder.label = @"Update Particles";
        [computeEncoder setComputePipelineState:_particleComputePipeline];
        [computeEncoder setBuffer:_particleBuffer offset:0 atIndex:0];
        [computeEncoder setBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [computeEncoder setBuffer:_laserStatsBuffer offset:0 atIndex:2];

        const NSUInteger threadsPerGroup = std::min<NSUInteger>(_particleComputePipeline.maxTotalThreadsPerThreadgroup, 256);
        MTLSize threads = MTLSizeMake(uniforms.particleCount, 1, 1);
        MTLSize threadgroup = MTLSizeMake(threadsPerGroup, 1, 1);
        [computeEncoder dispatchThreads:threads threadsPerThreadgroup:threadgroup];
        [computeEncoder endEncoding];

        if (uniforms.laserFresh != 0u) {
            __weak AFRenderer *weakSelf = self;
            id<MTLBuffer> statsBuffer = _laserStatsBuffer;
            [commandBuffer addCompletedHandler:^(__unused id<MTLCommandBuffer> completedBuffer) {
                AFRenderer *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                const std::uint32_t hitCount = *static_cast<const std::uint32_t *>(statsBuffer.contents);
                if (hitCount > 0u) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        strongSelf->_laserParticleHits += hitCount;
                        strongSelf->_laserChunks += 1u;
                    });
                }
            }];
        }
    }

    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = targetTexture;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.002, 0.003, 0.008, 1.0);

    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    renderEncoder.label = @"Render Art Forge Scene";
    [renderEncoder setViewport:MTLViewport{0.0, 0.0, static_cast<double>(targetTexture.width), static_cast<double>(targetTexture.height), 0.0, 1.0}];

    if (_compositionPipeline) {
        [renderEncoder setRenderPipelineState:_compositionPipeline];
        [renderEncoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }

    if (_particlePipeline && _particleBuffer) {
        [renderEncoder setRenderPipelineState:_particlePipeline];
        [renderEncoder setVertexBuffer:_particleBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [renderEncoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypePoint
                           vertexStart:0
                           vertexCount:uniforms.particleCount];
    }

    [renderEncoder endEncoding];
}

- (void)encodePresentTexture:(id<MTLTexture>)sourceTexture
               commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  toDrawable:(id<CAMetalDrawable>)drawable
{
    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = drawable.texture;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    renderEncoder.label = @"Present MetalFX Texture";
    [renderEncoder setRenderPipelineState:_presentPipeline];
    [renderEncoder setFragmentTexture:sourceTexture atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [renderEncoder endEncoding];
}

@end
