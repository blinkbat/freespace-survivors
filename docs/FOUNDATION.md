# Technical provenance

This prototype uses the adjacent `zig-soulslike` project as its technical foundation, with local adaptations rather than runtime imports from that repository.

- `build.zig` and `build.zig.zon`: Zig 0.14.1 module setup, pinned raylib-zig dependency, and separate check/test/build steps.
- `src/mesh.zig`: pared-down adaptation of `src/gfx/gfx.zig`'s Builder: C-allocator vertex streams, flat face normals, quad triangulation, box winding, ownership transfer to raylib Mesh, and shader assignment. The C allocator matters because raylib frees the uploaded CPU buffers.
- `src/render.zig`: adapts the depth-only shadow framebuffer, sun camera, raylib matrix ordering, high texture-slot binding, and shader-driven model pipeline.
- `src/shaders.zig`: uses that pipeline's vertex position/normal/color conventions; space materials and lighting are local implementations.
- Camera: retains the sibling's immediate obstruction shortening principle, implemented for 3D structures rather than ground terrain.
- Scripts and shot mode retain the sibling's check-before-build and capture-before-swap workflow.

No Descent, Nintendo, or poncle source code or assets are used. Reference-source algorithms informed design only. All models and surface patterns are built procedurally here.

The retro filter shader, fifteen intensity controls, default values, and PS1/CRT/VHS/Game Boy presets are adapted from `../zig-soulslike/src/gfx/shaders.zig` (`retroFS`) and `../zig-soulslike/src/gfx/gfx.zig` (`Retro`). They live locally in `src/retro.zig`; this project has no runtime or build dependency on sibling source files. The menu adapts them to the existing keyboard/controller/mouse navigation and persisted settings.
