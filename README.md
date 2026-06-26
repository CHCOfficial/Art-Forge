# Art Forge

Art Forge is a native C++/Metal generative art application for macOS. It renders dense procedural compositions from GPU particles, flow fields, strange-attractor-style motion, procedural shader layers, mutation controls, presets, and experimental renderer options.

<img width="3394" height="1908" alt="SCR-20260626-fefo" src="https://github.com/user-attachments/assets/9a83d8e1-b357-4788-9b09-2d18f0b76e9c" />


<img width="2536" height="1614" alt="SCR-20260622-ouvo" src="https://github.com/user-attachments/assets/2b19ed11-6c8d-4296-83f9-df14cf9a2f4e" />


<img width="3428" height="1956" alt="SCR-20260622-otfx" src="https://github.com/user-attachments/assets/a0d8a195-c957-41ff-8fe7-bdd82e2e5f15" />


<img width="3426" height="1940" alt="SCR-20260622-otkm" src="https://github.com/user-attachments/assets/d713ff2e-45cf-4eb1-b102-7bbc8266e1c4" />


<img width="3428" height="1956" alt="SCR-20260622-otng" src="https://github.com/user-attachments/assets/33b08f1b-93aa-4640-b43c-636d5f1ea25f" />


<img width="3424" height="1952" alt="SCR-20260622-otqn" src="https://github.com/user-attachments/assets/38e4a5a1-fe5e-48ca-a572-69d4d5c18830" />


<img width="3426" height="1956" alt="SCR-20260622-otst" src="https://github.com/user-attachments/assets/a9e71ac0-40b4-479e-bdec-0a6ad3b4f999" />

## Build

```sh
cmake -S . -B build
cmake --build build
open "build/Art Forge.app"
```

## Tests

```sh
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
```

The test suite covers engine defaults, preset transition stability, experimental feature flags, shader uniform layout, shader source guards, and Metal runtime shader compilation.

## Current Controls

- The app opens with a splash screen and in-app main menu over the live canvas.
- `Composition > Show Main Menu` reopens the in-app menu.
- `File > Export PNG...` saves a high-resolution still.
- `Composition > Presets` loads curated looks.
- Preset changes morph smoothly instead of snapping between scenes.
- Presets now use subtle procedural backgrounds, including deep space with stars, nebula haze, aurora-like structures, shooting stars, mist, silk dawn, ocean, and ember haze environments.
- `Composition > Randomize` creates a fresh parameter set.
- `Composition > Mutate` nudges the current look without replacing it.
- `Composition > Particle Patterns` switches the GPU particles between flow weave, orbital bloom, Lissajous ribbons, rose mandala, spiral galaxy, vortex knot paths, and projected 3D forms including torus knots, helix columns, sphere lattices, and Mobius ribbons.
- `Composition > Drone Mode` enters a first-person drone inside the particle field. Use `W/A/S/D` for thrust, mouse movement to steer, `Space` or `E` to rise, `Q` or `C` to descend, click to fire the laser, and `Esc` to exit.
- Laser shots light up the beam path, scatter nearby particles into an explosion chunk, and the HUD tracks shots, chunks, and particle hits for the current session.
- Move the mouse over the canvas to push, swirl, brighten, and slightly enlarge nearby particles.
- The top-right HUD shows FPS, frame time, particle density, preview scale, active pattern, drone state, mouse state, and audio-reactive state.
- `Experimental` contains advanced toggles, including high-density particles, fluid swirl, reaction-diffusion fields, opt-in audio-reactive modulation, half-resolution preview, and MetalFX spatial upscaling when supported by the Mac.

## Notes

The app weak-links MetalFX and detects support at runtime. On unsupported systems the MetalFX menu remains visible but disabled, so the same build can still run without the framework being available at launch.

## License

This project can be reused, modified, distributed, or sold as long as the credit and BuyMeACoffee link are retained appropriately:

Credit: chcofficial  
Support link: https://buymeacoffee.com/chcofficial

See [LICENSE](LICENSE) for the full terms.
