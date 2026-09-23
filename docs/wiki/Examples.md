# Examples

`examples/`. Each example is one program that renders one image or animation into `out/`. `make animation` renders them all.

Run one by hand:

```bash
mkdir -p out
.venv/bin/mojo run -I . examples/cubes.mojo out/cubes.png
```

| Example | Output | Page |
|---|---|---|
| `triangle.mojo` | `triangle.png` | The smallest program that draws. |
| `spin.mojo` | `spin.png` | [Image files](Image-files) |
| `cube.mojo` | `cube.png` | [Why a software rasterizer](Why-a-software-rasterizer) |
| `cubes.mojo` | `cubes.png` | [Scene graph](Scene-graph) |
| `uv.mojo` | `uv.png` | [Why interpolation is perspective-correct](Why-interpolation-is-perspective-correct) |
| `textured.mojo` | `textured.png` | [Textures](Textures) |
| `glass.mojo` | `glass.png` | [Why transparency is sorted](Why-transparency-is-sorted) |
| `floor.mojo` | `floor.png` | [Why mipmaps](Why-mipmaps) |
| `photo.mojo` | `photo.png` | A decoded PNG on a cube. The README figure. |
| `lamps.mojo` | `lamps.png` | [Lights](Lights) |
| `first_scene.mojo` | `first_scene.png` | [Render your first scene](Tutorial-Render-your-first-scene) |
| `lit_scene.mojo` | `lit_scene.png` | [Light, texture and animate](Tutorial-Light-texture-and-animate) |
| `rotations.mojo` | `rotations.png` | [Rotations](Rotations) |
| `ortho.mojo` | `cameras.png` | [Cameras](Cameras) |
| `stereo.mojo` | `stereo.png` | [Cameras](Cameras#stereocamera) |
| `geometry.mojo` | `geometry.png` | [Geometry](Geometry) |
| `instances.mojo` | `instances.png` | [Meshes and assets](Meshes-and-assets) |
| `raycast.mojo` | `raycast.png` | [Raycasting](Raycasting) |
| `curves.mojo` | `curves.png` | [Curves and paths](Curves) |
| `lines.mojo` | `lines.png` | [Lines](Lines) |
| `sprites.mojo` | `sprites.png` | [Points and sprites](Points-and-sprites) |
| `television.mojo` | `television.png` | [Textures](Textures#from-a-render) |
| `mirror.mojo` | `mirror.png` | [Textures](Textures#cube-textures) |
| `outlines.mojo` | `helpers.png` | [Helpers](Helpers) |
| `keyframes.mojo` | `keyframes.png` | [Animation](Animation) |
| `skinning.mojo` | `skinning.png` | [Skinning](Skinning) |
| `phong.mojo` | `phong.png` | [Materials](Materials) |
| `physical.mojo` | `physical.png` | [Materials](Materials#standard-and-physical) |
| `fog.mojo` | `fog.png` | [Fog](Fog) |
| `culling.mojo` | `culling.png` | [Renderer](Renderer) |
| `split.mojo` | `split.png` | [Renderer](Renderer#viewport-and-scissor) |
| `clipping.mojo` | `clipping.png` | [Rasterization](Rasterization) |
| `gpu_backend.mojo` | `gpu_backend.png` | [GPU backend](GPU-backend) |
| `exposure.mojo` | `exposure.png` | [Render target and framebuffer](Render-target-and-framebuffer) |
| `model.mojo` | `model.png` | [Model files](Model-files) |
| `orbit.mojo` | `math.png` | [Math](Math) |
| `clock.mojo` | `units.png` | [Units](Units) |
| `chain.mojo` | `chain.png` | [Why the scene graph is an array](Why-the-scene-graph-is-an-array) |
| `additive.mojo` | `additive.png` | [Why color is linear](Why-color-is-linear) |
| `normals.mojo` | `normals.png` | [Why a normal is not a color](Why-a-normal-is-not-a-color) |
| `fragments.mojo` | `fragments.png` | [Why shading is per fragment](Why-shading-is-per-fragment) |
| `edges.mojo` | `coverage.png` | [Why coverage uses fixed point](Why-coverage-uses-fixed-point) |

`photo.mojo` takes the image path first: `examples/photo.mojo assets/brick.png out/photo.png`.

`viewer.mojo` writes no file. It opens a window in the terminal, and `make viewer` runs it. See [Windowing and controls](Windowing-and-controls).

Animated outputs are APNG files. A browser or VS Code plays them. A viewer that does not know APNG shows the first frame.

## Benchmarks

| Program | Shows |
|---|---|
| `bench/raster_bench.mojo` | CPU against GPU rasterization across image sizes. |
| `bench/scene_bench.mojo` | Each stage of the CPU renderer, one worker and every core. |
| `tools/bench_examples.py` | Every example against three.js, and the Mojo 1.0 probe. |

The recorded tables live on [Benchmarks](Benchmarks). The refresh command is in [How to measure examples](How-to-measure-examples).

## Tools

| Program | Shows |
|---|---|
| `tools/gpu_status.mojo` | Whether an accelerator is present. |
| `tools/doc_lint.mojo` | Whether the documentation follows the writing rules. |
