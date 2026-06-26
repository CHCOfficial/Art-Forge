#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstdlib>
#include <filesystem>
#include <iostream>

namespace {

std::filesystem::path sourceDir()
{
    if (const char* env = std::getenv("ART_FORGE_SOURCE_DIR")) {
        return std::filesystem::path(env);
    }

    return std::filesystem::current_path().parent_path();
}

}

int main()
{
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cerr << "No Metal device available for shader compile test.\n";
            return 1;
        }

        const auto shaderPath = sourceDir() / "resources" / "shaders" / "ArtForge.metal";
        NSString *path = [NSString stringWithUTF8String:shaderPath.string().c_str()];

        NSError *error = nil;
        NSString *source = [NSString stringWithContentsOfFile:path
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
        if (!source) {
            std::cerr << "Unable to read shader source: "
                      << (error ? error.localizedDescription.UTF8String : "unknown error")
                      << '\n';
            return 2;
        }

        id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
        if (!library) {
            std::cerr << "Metal shader compile failed: "
                      << (error ? error.localizedDescription.UTF8String : "unknown error")
                      << '\n';
            return 3;
        }

        NSArray<NSString *> *requiredFunctions = @[
            @"fullscreenVertex",
            @"compositionFragment",
            @"updateParticles",
            @"particleVertex",
            @"particleFragment"
        ];

        for (NSString *name in requiredFunctions) {
            id<MTLFunction> function = [library newFunctionWithName:name];
            if (!function) {
                std::cerr << "Missing Metal function: " << name.UTF8String << '\n';
                return 4;
            }
        }

        std::cout << "Metal shader compile test passed.\n";
        return 0;
    }
}
