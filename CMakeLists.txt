cmake_minimum_required(VERSION 3.24)

project(ArtForge
    VERSION 0.1.0
    DESCRIPTION "A real-time procedural generative art studio"
    LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

set(ART_FORGE_SOURCES
    src/Engine.cpp
    src/macOS/AppDelegate.mm
    src/macOS/Renderer.mm
    src/main.mm)

set(ART_FORGE_RESOURCES
    resources/shaders/ArtForge.metal
    resources/AppIcon.icns)

add_executable(ArtForge MACOSX_BUNDLE
    ${ART_FORGE_SOURCES}
    ${ART_FORGE_RESOURCES})

target_include_directories(ArtForge PRIVATE include src)

target_compile_options(ArtForge PRIVATE
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
    $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Wpedantic>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-Wall -Wextra>)

find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(UNIFORM_TYPE_IDENTIFIERS_FRAMEWORK UniformTypeIdentifiers REQUIRED)
find_library(METALFX_FRAMEWORK MetalFX)

target_link_libraries(ArtForge PRIVATE
    ${COCOA_FRAMEWORK}
    ${METAL_FRAMEWORK}
    ${METALKIT_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
    ${UNIFORM_TYPE_IDENTIFIERS_FRAMEWORK})

if(METALFX_FRAMEWORK)
    target_compile_definitions(ArtForge PRIVATE AF_HAVE_METALFX=1)
    target_link_options(ArtForge PRIVATE "LINKER:-weak_framework,MetalFX")
endif()

set_source_files_properties(${ART_FORGE_RESOURCES}
    PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/Shaders")

set_source_files_properties(resources/AppIcon.icns
    PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")

set_target_properties(ArtForge PROPERTIES
    OUTPUT_NAME "Art Forge"
    MACOSX_BUNDLE_GUI_IDENTIFIER "studio.codex.artforge"
    MACOSX_BUNDLE_BUNDLE_NAME "Art Forge"
    MACOSX_BUNDLE_ICON_FILE "AppIcon.icns"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/resources/Info.plist.in")
