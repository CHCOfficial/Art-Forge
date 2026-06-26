#import "macOS/AppDelegate.h"

#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[])
{
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AFAppDelegate *delegate = [AFAppDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application activateIgnoringOtherApps:YES];
        [application run];
    }

    return 0;
}

