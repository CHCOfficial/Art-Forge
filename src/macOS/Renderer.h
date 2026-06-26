#pragma once

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AFExperimentalFeatureTag) {
    AFExperimentalFeatureReactionDiffusion = 0,
    AFExperimentalFeatureFluidSwirl = 1,
    AFExperimentalFeatureAudioReactive = 2,
    AFExperimentalFeatureHighDensityParticles = 3,
    AFExperimentalFeatureTemporalTrails = 4,
    AFExperimentalFeatureHalfResolutionPreview = 5,
    AFExperimentalFeatureMetalFX = 6
};

@interface AFRenderer : NSObject <MTKViewDelegate>

- (instancetype)initWithView:(MTKView *)view;

- (NSArray<NSString *> *)presetNames;
- (NSArray<NSString *> *)particlePatternNames;
- (void)loadPresetAtIndex:(NSUInteger)index;
- (void)randomizeComposition;
- (void)mutateComposition;
- (void)setParticlePatternIndex:(NSInteger)index;
- (void)togglePaused;
- (void)toggleDroneMode;
- (void)setDroneModeEnabled:(BOOL)enabled;
- (void)setDroneMovementForward:(BOOL)forward
                           back:(BOOL)back
                           left:(BOOL)left
                          right:(BOOL)right
                             up:(BOOL)up
                           down:(BOOL)down;
- (void)applyDroneMouseDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY;
- (void)fireDroneLaser;
- (void)toggleExperimentalFeature:(AFExperimentalFeatureTag)feature;

- (BOOL)isPresetActive:(NSUInteger)index;
- (BOOL)isParticlePatternActive:(NSInteger)index;
- (BOOL)isDroneModeEnabled;
- (BOOL)isExperimentalFeatureEnabled:(AFExperimentalFeatureTag)feature;
- (BOOL)isExperimentalFeatureAvailable:(AFExperimentalFeatureTag)feature;
- (NSString *)metalFXStatus;
- (NSString *)statusLine;
- (NSString *)performanceHUDText;

- (BOOL)exportPNGToURL:(NSURL *)url
                 width:(NSUInteger)width
                height:(NSUInteger)height
                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
