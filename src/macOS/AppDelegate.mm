#import "macOS/AppDelegate.h"

#import "macOS/Renderer.h"

#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AFAppDelegate ()
{
    NSWindow *_window;
    MTKView *_metalView;
    AFRenderer *_renderer;
    NSVisualEffectView *_launchOverlay;
    NSVisualEffectView *_splashCard;
    NSVisualEffectView *_mainMenuCard;
    NSVisualEffectView *_performancePanel;
    NSTextField *_performanceLabel;
    NSMutableArray<NSMenuItem *> *_presetItems;
    NSMutableArray<NSMenuItem *> *_patternItems;
    NSMutableArray<NSMenuItem *> *_experimentalItems;
    NSTimer *_titleTimer;
    BOOL _performanceHUDVisible;
}
@end

@implementation AFAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Art Forge needs a Metal-capable Mac.";
        alert.informativeText = @"No Metal device was found.";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    NSRect frame = NSMakeRect(0.0, 0.0, 1280.0, 820.0);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:NSWindowStyleMaskTitled |
                                                   NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskMiniaturizable |
                                                   NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _window.title = @"Art Forge";
    _window.minSize = NSMakeSize(800.0, 520.0);
    [_window center];

    _metalView = [[MTKView alloc] initWithFrame:frame device:device];
    _metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _renderer = [[AFRenderer alloc] initWithView:_metalView];
    _metalView.delegate = _renderer;

    _window.contentView = _metalView;
    [self buildPerformanceHUD];
    [self buildLaunchExperience];
    [_window makeKeyAndOrderFront:nil];

    [self buildMenus];
    [self refreshMenuState];

    _titleTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                   target:self
                                                 selector:@selector(refreshTitle:)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (NSVisualEffectView *)makeGlassPanel
{
    NSVisualEffectView *panel = [NSVisualEffectView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.material = NSVisualEffectMaterialHUDWindow;
    panel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    panel.state = NSVisualEffectStateActive;
    panel.wantsLayer = YES;
    panel.layer.cornerRadius = 8.0;
    panel.layer.masksToBounds = YES;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.16].CGColor;
    panel.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.035 green:0.035 blue:0.075 alpha:0.62].CGColor;
    return panel;
}

- (NSTextField *)makeLabel:(NSString *)text
                      font:(NSFont *)font
                     alpha:(CGFloat)alpha
                 alignment:(NSTextAlignment)alignment
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = [NSColor colorWithWhite:1.0 alpha:alpha];
    label.alignment = alignment;
    label.maximumNumberOfLines = 0;
    return label;
}

- (NSButton *)makeMenuButtonWithTitle:(NSString *)title
                                action:(SEL)action
                               primary:(BOOL)primary
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:primary ? 15.0 : 13.0 weight:primary ? NSFontWeightSemibold : NSFontWeightMedium];
    button.contentTintColor = [NSColor whiteColor];
    button.alignment = NSTextAlignmentCenter;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 8.0;
    button.layer.masksToBounds = YES;
    button.layer.backgroundColor = primary
        ? [NSColor colorWithCalibratedRed:0.12 green:0.44 blue:0.95 alpha:0.92].CGColor
        : [NSColor colorWithCalibratedRed:0.22 green:0.20 blue:0.34 alpha:0.72].CGColor;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:primary ? 0.34 : 0.18].CGColor;
    [button.heightAnchor constraintEqualToConstant:primary ? 46.0 : 38.0].active = YES;
    return button;
}

- (NSButton *)makePresetOverlayButton:(NSString *)title index:(NSUInteger)index
{
    NSButton *button = [self makeMenuButtonWithTitle:title action:@selector(overlayPreset:) primary:NO];
    button.tag = static_cast<NSInteger>(index);
    return button;
}

- (void)buildLaunchExperience
{
    _launchOverlay = [NSVisualEffectView new];
    _launchOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _launchOverlay.material = NSVisualEffectMaterialUnderWindowBackground;
    _launchOverlay.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _launchOverlay.state = NSVisualEffectStateActive;
    _launchOverlay.wantsLayer = YES;
    _launchOverlay.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.015 green:0.018 blue:0.030 alpha:0.60].CGColor;
    [_metalView addSubview:_launchOverlay positioned:NSWindowAbove relativeTo:nil];

    [NSLayoutConstraint activateConstraints:@[
        [_launchOverlay.leadingAnchor constraintEqualToAnchor:_metalView.leadingAnchor],
        [_launchOverlay.trailingAnchor constraintEqualToAnchor:_metalView.trailingAnchor],
        [_launchOverlay.topAnchor constraintEqualToAnchor:_metalView.topAnchor],
        [_launchOverlay.bottomAnchor constraintEqualToAnchor:_metalView.bottomAnchor]
    ]];

    [self buildSplashCard];
    [self buildMainMenuCard];
    _mainMenuCard.hidden = YES;
    _mainMenuCard.alphaValue = 0.0;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.35;
        self->_splashCard.animator.alphaValue = 1.0;
    } completionHandler:^{
        [self performSelector:@selector(showMainMenuAfterSplash) withObject:nil afterDelay:1.05];
    }];
}

- (void)buildSplashCard
{
    _splashCard = [self makeGlassPanel];
    _splashCard.alphaValue = 0.0;
    [_launchOverlay addSubview:_splashCard];

    NSTextField *eyebrow = [self makeLabel:@"PROCEDURAL MOTION STUDIO"
                                      font:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightSemibold]
                                     alpha:0.70
                                 alignment:NSTextAlignmentCenter];
    NSTextField *title = [self makeLabel:@"Art Forge"
                                    font:[NSFont systemFontOfSize:56.0 weight:NSFontWeightBold]
                                   alpha:0.96
                               alignment:NSTextAlignmentCenter];
    NSTextField *subtitle = [self makeLabel:@"Particles / Fields / Shaders / Motion"
                                       font:[NSFont systemFontOfSize:17.0 weight:NSFontWeightMedium]
                                      alpha:0.82
                                  alignment:NSTextAlignmentCenter];

    [_splashCard addSubview:eyebrow];
    [_splashCard addSubview:title];
    [_splashCard addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [_splashCard.centerXAnchor constraintEqualToAnchor:_launchOverlay.centerXAnchor],
        [_splashCard.centerYAnchor constraintEqualToAnchor:_launchOverlay.centerYAnchor],
        [_splashCard.widthAnchor constraintEqualToConstant:520.0],

        [eyebrow.topAnchor constraintEqualToAnchor:_splashCard.topAnchor constant:32.0],
        [eyebrow.leadingAnchor constraintEqualToAnchor:_splashCard.leadingAnchor constant:30.0],
        [eyebrow.trailingAnchor constraintEqualToAnchor:_splashCard.trailingAnchor constant:-30.0],

        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:12.0],
        [title.leadingAnchor constraintEqualToAnchor:_splashCard.leadingAnchor constant:30.0],
        [title.trailingAnchor constraintEqualToAnchor:_splashCard.trailingAnchor constant:-30.0],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:_splashCard.leadingAnchor constant:30.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:_splashCard.trailingAnchor constant:-30.0],
        [subtitle.bottomAnchor constraintEqualToAnchor:_splashCard.bottomAnchor constant:-32.0]
    ]];
}

- (void)buildMainMenuCard
{
    _mainMenuCard = [self makeGlassPanel];
    [_launchOverlay addSubview:_mainMenuCard];

    NSTextField *eyebrow = [self makeLabel:@"ART FORGE"
                                      font:[NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightSemibold]
                                     alpha:0.62
                                 alignment:NSTextAlignmentCenter];
    NSTextField *title = [self makeLabel:@"Choose Your Forge"
                                    font:[NSFont systemFontOfSize:36.0 weight:NSFontWeightBold]
                                   alpha:0.96
                               alignment:NSTextAlignmentCenter];
    NSTextField *subtitle = [self makeLabel:@"Start from a live preset, randomize the system, or jump straight into the canvas."
                                       font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightRegular]
                                      alpha:0.74
                                  alignment:NSTextAlignmentCenter];

    NSButton *startButton = [self makeMenuButtonWithTitle:@"Start Forging" action:@selector(startFromOverlay:) primary:YES];
    NSButton *randomButton = [self makeMenuButtonWithTitle:@"Randomize Scene" action:@selector(overlayRandomize:) primary:NO];
    NSButton *hudButton = [self makeMenuButtonWithTitle:@"Toggle Performance HUD" action:@selector(togglePerformanceHUD:) primary:NO];
    NSButton *supportButton = [self makeMenuButtonWithTitle:@"Buy Me a Coffee" action:@selector(openSupportLink:) primary:NO];
    NSButton *quitButton = [self makeMenuButtonWithTitle:@"Quit" action:@selector(overlayQuit:) primary:NO];

    NSTextField *actionsLabel = [self makeLabel:@"Actions"
                                           font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold]
                                          alpha:0.68
                                      alignment:NSTextAlignmentLeft];
    NSTextField *presetLabel = [self makeLabel:@"Presets"
                                          font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold]
                                         alpha:0.74
                                     alignment:NSTextAlignmentLeft];

    NSStackView *buttonStack = [NSStackView stackViewWithViews:@[startButton, randomButton, hudButton, supportButton, quitButton]];
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    buttonStack.spacing = 10.0;
    buttonStack.distribution = NSStackViewDistributionFill;
    buttonStack.alignment = NSLayoutAttributeWidth;

    NSMutableArray<NSView *> *presetButtons = [NSMutableArray array];
    NSArray<NSString *> *presetNames = [_renderer presetNames];
    for (NSUInteger index = 0; index < presetNames.count; ++index) {
        [presetButtons addObject:[self makePresetOverlayButton:presetNames[index] index:index]];
    }
    NSStackView *presetStack = [NSStackView stackViewWithViews:presetButtons];
    presetStack.translatesAutoresizingMaskIntoConstraints = NO;
    presetStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    presetStack.spacing = 8.0;
    presetStack.alignment = NSLayoutAttributeWidth;

    NSTextField *hint = [self makeLabel:@"Tip: reopen this screen from Composition > Show Main Menu"
                                   font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]
                                  alpha:0.54
                              alignment:NSTextAlignmentCenter];

    [_mainMenuCard addSubview:eyebrow];
    [_mainMenuCard addSubview:title];
    [_mainMenuCard addSubview:subtitle];
    [_mainMenuCard addSubview:actionsLabel];
    [_mainMenuCard addSubview:buttonStack];
    [_mainMenuCard addSubview:presetLabel];
    [_mainMenuCard addSubview:presetStack];
    [_mainMenuCard addSubview:hint];

    for (NSView *view in buttonStack.arrangedSubviews) {
        [view.widthAnchor constraintEqualToAnchor:buttonStack.widthAnchor].active = YES;
    }
    for (NSView *view in presetStack.arrangedSubviews) {
        [view.widthAnchor constraintEqualToAnchor:presetStack.widthAnchor].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [_mainMenuCard.centerXAnchor constraintEqualToAnchor:_launchOverlay.centerXAnchor],
        [_mainMenuCard.centerYAnchor constraintEqualToAnchor:_launchOverlay.centerYAnchor],
        [_mainMenuCard.widthAnchor constraintEqualToConstant:640.0],

        [eyebrow.topAnchor constraintEqualToAnchor:_mainMenuCard.topAnchor constant:26.0],
        [eyebrow.leadingAnchor constraintEqualToAnchor:_mainMenuCard.leadingAnchor constant:34.0],
        [eyebrow.trailingAnchor constraintEqualToAnchor:_mainMenuCard.trailingAnchor constant:-34.0],

        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:8.0],
        [title.leadingAnchor constraintEqualToAnchor:_mainMenuCard.leadingAnchor constant:34.0],
        [title.trailingAnchor constraintEqualToAnchor:_mainMenuCard.trailingAnchor constant:-34.0],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:_mainMenuCard.leadingAnchor constant:60.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:_mainMenuCard.trailingAnchor constant:-60.0],

        [actionsLabel.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:28.0],
        [actionsLabel.leadingAnchor constraintEqualToAnchor:_mainMenuCard.leadingAnchor constant:42.0],
        [actionsLabel.widthAnchor constraintEqualToConstant:235.0],

        [buttonStack.topAnchor constraintEqualToAnchor:actionsLabel.bottomAnchor constant:10.0],
        [buttonStack.leadingAnchor constraintEqualToAnchor:actionsLabel.leadingAnchor],
        [buttonStack.widthAnchor constraintEqualToConstant:235.0],

        [presetLabel.topAnchor constraintEqualToAnchor:actionsLabel.topAnchor],
        [presetLabel.leadingAnchor constraintEqualToAnchor:buttonStack.trailingAnchor constant:44.0],
        [presetLabel.trailingAnchor constraintEqualToAnchor:_mainMenuCard.trailingAnchor constant:-42.0],

        [presetStack.topAnchor constraintEqualToAnchor:presetLabel.bottomAnchor constant:9.0],
        [presetStack.leadingAnchor constraintEqualToAnchor:presetLabel.leadingAnchor],
        [presetStack.trailingAnchor constraintEqualToAnchor:presetLabel.trailingAnchor],

        [hint.topAnchor constraintEqualToAnchor:presetStack.bottomAnchor constant:22.0],
        [hint.leadingAnchor constraintEqualToAnchor:_mainMenuCard.leadingAnchor constant:34.0],
        [hint.trailingAnchor constraintEqualToAnchor:_mainMenuCard.trailingAnchor constant:-34.0],
        [hint.bottomAnchor constraintEqualToAnchor:_mainMenuCard.bottomAnchor constant:-24.0],

        [buttonStack.bottomAnchor constraintLessThanOrEqualToAnchor:hint.topAnchor constant:-22.0]
    ]];
}

- (void)showMainMenuAfterSplash
{
    _mainMenuCard.hidden = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.32;
        self->_splashCard.animator.alphaValue = 0.0;
        self->_mainMenuCard.animator.alphaValue = 1.0;
    } completionHandler:^{
        self->_splashCard.hidden = YES;
    }];
}

- (void)buildPerformanceHUD
{
    _performanceHUDVisible = YES;
    _performancePanel = [NSVisualEffectView new];
    _performancePanel.translatesAutoresizingMaskIntoConstraints = NO;
    _performancePanel.material = NSVisualEffectMaterialHUDWindow;
    _performancePanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _performancePanel.state = NSVisualEffectStateActive;
    _performancePanel.wantsLayer = YES;
    _performancePanel.layer.cornerRadius = 8.0;
    _performancePanel.layer.masksToBounds = YES;

    _performanceLabel = [NSTextField labelWithString:@""];
    _performanceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _performanceLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightMedium];
    _performanceLabel.textColor = [NSColor colorWithWhite:1.0 alpha:0.92];
    _performanceLabel.maximumNumberOfLines = 0;
    _performanceLabel.lineBreakMode = NSLineBreakByClipping;

    [_performancePanel addSubview:_performanceLabel];
    [_metalView addSubview:_performancePanel];

    [NSLayoutConstraint activateConstraints:@[
        [_performancePanel.trailingAnchor constraintEqualToAnchor:_metalView.trailingAnchor constant:-14.0],
        [_performancePanel.topAnchor constraintEqualToAnchor:_metalView.topAnchor constant:14.0],
        [_performancePanel.widthAnchor constraintGreaterThanOrEqualToConstant:245.0],
        [_performanceLabel.leadingAnchor constraintEqualToAnchor:_performancePanel.leadingAnchor constant:12.0],
        [_performanceLabel.trailingAnchor constraintEqualToAnchor:_performancePanel.trailingAnchor constant:-12.0],
        [_performanceLabel.topAnchor constraintEqualToAnchor:_performancePanel.topAnchor constant:10.0],
        [_performanceLabel.bottomAnchor constraintEqualToAnchor:_performancePanel.bottomAnchor constant:-10.0]
    ]];

    _performanceLabel.stringValue = [_renderer performanceHUDText];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    [_titleTimer invalidate];
}

- (void)buildMenus
{
    _presetItems = [NSMutableArray array];
    _patternItems = [NSMutableArray array];
    _experimentalItems = [NSMutableArray array];

    NSMenu *mainMenu = [NSMenu new];
    NSApp.mainMenu = mainMenu;

    NSMenuItem *appItem = [NSMenuItem new];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Art Forge"];
    appItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"About Art Forge"
                       action:@selector(showAbout:)
                keyEquivalent:@""].target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Art Forge"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];

    NSMenuItem *fileItem = [NSMenuItem new];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;
    NSMenuItem *exportItem = [fileMenu addItemWithTitle:@"Export 4K PNG..."
                                                 action:@selector(exportPNG:)
                                          keyEquivalent:@"e"];
    exportItem.target = self;

    NSMenuItem *compositionItem = [NSMenuItem new];
    [mainMenu addItem:compositionItem];
    NSMenu *compositionMenu = [[NSMenu alloc] initWithTitle:@"Composition"];
    compositionItem.submenu = compositionMenu;

    NSMenuItem *randomizeItem = [compositionMenu addItemWithTitle:@"Randomize"
                                                           action:@selector(randomize:)
                                                    keyEquivalent:@"r"];
    randomizeItem.target = self;

    NSMenuItem *mutateItem = [compositionMenu addItemWithTitle:@"Mutate"
                                                        action:@selector(mutate:)
                                                 keyEquivalent:@"m"];
    mutateItem.target = self;

    NSMenuItem *pauseItem = [compositionMenu addItemWithTitle:@"Pause / Resume"
                                                       action:@selector(togglePause:)
                                                keyEquivalent:@"p"];
    pauseItem.target = self;

    NSMenuItem *mainMenuItem = [compositionMenu addItemWithTitle:@"Show Main Menu"
                                                          action:@selector(showMainMenu:)
                                                   keyEquivalent:@"0"];
    mainMenuItem.target = self;

    [compositionMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *presetRoot = [compositionMenu addItemWithTitle:@"Presets"
                                                        action:nil
                                                 keyEquivalent:@""];
    NSMenu *presetMenu = [[NSMenu alloc] initWithTitle:@"Presets"];
    presetRoot.submenu = presetMenu;
    NSArray<NSString *> *presetNames = [_renderer presetNames];
    for (NSUInteger index = 0; index < presetNames.count; ++index) {
        NSMenuItem *item = [presetMenu addItemWithTitle:presetNames[index]
                                                 action:@selector(loadPreset:)
                                          keyEquivalent:@""];
        item.target = self;
        item.tag = static_cast<NSInteger>(index);
        [_presetItems addObject:item];
    }

    NSMenuItem *patternRoot = [compositionMenu addItemWithTitle:@"Particle Patterns"
                                                         action:nil
                                                  keyEquivalent:@""];
    NSMenu *patternMenu = [[NSMenu alloc] initWithTitle:@"Particle Patterns"];
    patternRoot.submenu = patternMenu;
    NSArray<NSString *> *patternNames = [_renderer particlePatternNames];
    for (NSInteger index = 0; index < static_cast<NSInteger>(patternNames.count); ++index) {
        NSMenuItem *item = [patternMenu addItemWithTitle:patternNames[static_cast<NSUInteger>(index)]
                                                  action:@selector(setParticlePattern:)
                                           keyEquivalent:@""];
        item.target = self;
        item.tag = index;
        [_patternItems addObject:item];
    }

    NSMenuItem *experimentalItem = [NSMenuItem new];
    [mainMenu addItem:experimentalItem];
    NSMenu *experimentalMenu = [[NSMenu alloc] initWithTitle:@"Experimental"];
    experimentalItem.submenu = experimentalMenu;

    [self addExperimentalMenuItem:@"Reaction-Diffusion Field"
                          feature:AFExperimentalFeatureReactionDiffusion
                             menu:experimentalMenu];
    [self addExperimentalMenuItem:@"Fluid Swirl"
                          feature:AFExperimentalFeatureFluidSwirl
                             menu:experimentalMenu];
    [self addExperimentalMenuItem:@"Audio-Reactive Modulation"
                          feature:AFExperimentalFeatureAudioReactive
                             menu:experimentalMenu];
    [self addExperimentalMenuItem:@"High-Density Particles"
                          feature:AFExperimentalFeatureHighDensityParticles
                             menu:experimentalMenu];
    [self addExperimentalMenuItem:@"Temporal Trail Bias"
                          feature:AFExperimentalFeatureTemporalTrails
                             menu:experimentalMenu];
    [experimentalMenu addItem:[NSMenuItem separatorItem]];
    [self addExperimentalMenuItem:@"Half-Resolution Preview"
                          feature:AFExperimentalFeatureHalfResolutionPreview
                             menu:experimentalMenu];
    [self addExperimentalMenuItem:@"MetalFX Spatial Upscaling (Mac)"
                          feature:AFExperimentalFeatureMetalFX
                             menu:experimentalMenu];

    NSMenuItem *metalFXStatusItem = [experimentalMenu addItemWithTitle:@"MetalFX Status..."
                                                                action:@selector(showMetalFXStatus:)
                                                         keyEquivalent:@""];
    metalFXStatusItem.target = self;
}

- (void)addExperimentalMenuItem:(NSString *)title
                        feature:(AFExperimentalFeatureTag)feature
                           menu:(NSMenu *)menu
{
    NSMenuItem *item = [menu addItemWithTitle:title
                                       action:@selector(toggleExperimental:)
                                keyEquivalent:@""];
    item.target = self;
    item.tag = feature;
    [_experimentalItems addObject:item];
}

- (void)refreshMenuState
{
    for (NSMenuItem *item in _presetItems) {
        item.state = [_renderer isPresetActive:static_cast<NSUInteger>(item.tag)] ? NSControlStateValueOn : NSControlStateValueOff;
    }

    for (NSMenuItem *item in _patternItems) {
        item.state = [_renderer isParticlePatternActive:item.tag] ? NSControlStateValueOn : NSControlStateValueOff;
    }

    for (NSMenuItem *item in _experimentalItems) {
        AFExperimentalFeatureTag feature = static_cast<AFExperimentalFeatureTag>(item.tag);
        item.enabled = [_renderer isExperimentalFeatureAvailable:feature];
        item.state = [_renderer isExperimentalFeatureEnabled:feature] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)refreshTitle:(NSTimer *)timer
{
    (void)timer;
    _window.title = [_renderer statusLine];
    _performanceLabel.stringValue = [_renderer performanceHUDText];
    [self refreshMenuState];
}

- (void)hideLaunchOverlay
{
    if (!_launchOverlay || _launchOverlay.hidden) {
        return;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.28;
        self->_launchOverlay.animator.alphaValue = 0.0;
    } completionHandler:^{
        self->_launchOverlay.hidden = YES;
        self->_launchOverlay.alphaValue = 1.0;
    }];
}

- (void)showMainMenu:(id)sender
{
    (void)sender;
    _splashCard.hidden = YES;
    _splashCard.alphaValue = 0.0;
    _mainMenuCard.hidden = NO;
    _mainMenuCard.alphaValue = 1.0;
    _launchOverlay.hidden = NO;
    _launchOverlay.alphaValue = 0.0;
    [_metalView addSubview:_launchOverlay positioned:NSWindowAbove relativeTo:nil];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.20;
        self->_launchOverlay.animator.alphaValue = 1.0;
    } completionHandler:nil];
}

- (void)startFromOverlay:(id)sender
{
    (void)sender;
    [self hideLaunchOverlay];
}

- (void)overlayRandomize:(id)sender
{
    (void)sender;
    [_renderer randomizeComposition];
    [self refreshMenuState];
    [self hideLaunchOverlay];
}

- (void)overlayPreset:(NSButton *)sender
{
    [_renderer loadPresetAtIndex:static_cast<NSUInteger>(sender.tag)];
    [self refreshMenuState];
    [self hideLaunchOverlay];
}

- (void)togglePerformanceHUD:(id)sender
{
    (void)sender;
    _performanceHUDVisible = !_performanceHUDVisible;
    _performancePanel.hidden = !_performanceHUDVisible;
}

- (void)openSupportLink:(id)sender
{
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://buymeacoffee.com/chcofficial"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)overlayQuit:(id)sender
{
    (void)sender;
    [NSApp terminate:nil];
}

- (void)showAbout:(id)sender
{
    (void)sender;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Art Forge";
    alert.informativeText = @"A procedural C++/Metal generative art studio with GPU particles, shader layers, mutation controls, PNG export, and experimental MetalFX support.\n\nCredit / support: https://buymeacoffee.com/chcofficial";
    [alert runModal];
}

- (void)exportPNG:(id)sender
{
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"png"]];
    panel.nameFieldStringValue = @"Art Forge Export.png";
    panel.title = @"Export 4K PNG";
    panel.message = @"Exports the current composition at 3840 x 2160.";

    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }

        NSError *error = nil;
        BOOL success = [self->_renderer exportPNGToURL:panel.URL
                                                 width:3840
                                                height:2160
                                                 error:&error];
        if (!success) {
            NSAlert *alert = [NSAlert alertWithError:error ?: [NSError errorWithDomain:@"ArtForge"
                                                                                  code:1
                                                                              userInfo:@{NSLocalizedDescriptionKey: @"PNG export failed."}]];
            [alert beginSheetModalForWindow:self->_window completionHandler:nil];
        }
    }];
}

- (void)randomize:(id)sender
{
    (void)sender;
    [_renderer randomizeComposition];
    [self refreshMenuState];
}

- (void)mutate:(id)sender
{
    (void)sender;
    [_renderer mutateComposition];
    [self refreshMenuState];
}

- (void)togglePause:(id)sender
{
    (void)sender;
    [_renderer togglePaused];
    [self refreshMenuState];
}

- (void)loadPreset:(NSMenuItem *)sender
{
    [_renderer loadPresetAtIndex:static_cast<NSUInteger>(sender.tag)];
    [self refreshMenuState];
}

- (void)setParticlePattern:(NSMenuItem *)sender
{
    [_renderer setParticlePatternIndex:sender.tag];
    [self refreshMenuState];
}

- (void)toggleExperimental:(NSMenuItem *)sender
{
    [_renderer toggleExperimentalFeature:static_cast<AFExperimentalFeatureTag>(sender.tag)];
    [self refreshMenuState];
}

- (void)showMetalFXStatus:(id)sender
{
    (void)sender;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"MetalFX Status";
    alert.informativeText = [_renderer metalFXStatus];
    [alert beginSheetModalForWindow:_window completionHandler:nil];
}

@end
