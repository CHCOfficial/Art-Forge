# Art Forge

Art Forge is a native C++/Metal generative art application for macOS. It renders dense procedural compositions from GPU particles, flow fields, strange-attractor-style motion, procedural shader layers, mutation controls, presets, and experimental renderer options.

## Build

```sh
cmake -S . -B build
cmake --build build
open "build/Art Forge.app"
```

## Current Controls

- The app opens with a splash screen and in-app main menu over the live canvas.
- `Composition > Show Main Menu` reopens the in-app menu.
- `File > Export PNG...` saves a high-resolution still.
- `Composition > Presets` loads curated looks.
- Preset changes morph smoothly instead of snapping between scenes.
- `Composition > Randomize` creates a fresh parameter set.
- `Composition > Mutate` nudges the current look without replacing it.
- `Composition > Particle Patterns` switches the GPU particles between flow weave, orbital bloom, Lissajous ribbons, rose mandala, spiral galaxy, vortex knot paths, and projected 3D forms including torus knots, helix columns, sphere lattices, and Mobius ribbons.
- Move the mouse over the canvas to push, swirl, brighten, and slightly enlarge nearby particles.
- The top-right HUD shows FPS, frame time, particle density, preview scale, active pattern, mouse state, and audio-reactive state.
- `Experimental` contains advanced toggles, including high-density particles, fluid swirl, reaction-diffusion fields, opt-in audio-reactive modulation, half-resolution preview, and MetalFX spatial upscaling when supported by the Mac.

## Notes

The app weak-links MetalFX and detects support at runtime. On unsupported systems the MetalFX menu remains visible but disabled, so the same build can still run without the framework being available at launch.

## License

This project can be reused, modified, distributed, or sold as long as the credit and BuyMeACoffee link are retained appropriately:

Credit: chcofficial  
Support link: https://buymeacoffee.com/chcofficial

See [LICENSE](LICENSE) for the full terms.
