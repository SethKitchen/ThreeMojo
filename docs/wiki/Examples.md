# Examples

`examples/`. Each example is one program that renders one image or animation into `out/`. `make animation` renders them all.

Run one by hand:

```bash
mkdir -p out
.venv/bin/mojo run -I . examples/cubes.mojo out/cubes.png
```

| Example | Output | Shows |
|---|---|---|
| `triangle.mojo` | `triangle.png` | One flat triangle. The smallest program that draws. |
| `spin.mojo` | `spin.png` | A turning triangle. The first animation. |
| `cube.mojo` | `cube.png` | A cube through a model matrix, with culling and depth. |
| `cubes.mojo` | `cubes.png` | Two cubes on a scene graph. A small one orbits behind a large one. |
| `uv.mojo` | `uv.png` | Perspective-correct against affine interpolation, two frames. |
| `textured.mojo` | `textured.png` | Two checkerboard cubes, nearest and bilinear. |
| `glass.mojo` | `glass.png` | Three translucent panes over a solid cube, sorted and blended. |
| `floor.mojo` | `floor.png` | A floor to the horizon, mipmapped on one side. |
| `photo.mojo` | `photo.png` | A decoded PNG on a cube, with the camera on an orbiting node. |
| `lamps.mojo` | `lamps.png` | Three colored lights and a point light on a coarse sphere. |
| `first_scene.mojo` | `first_scene.png` | The [first tutorial](Tutorial-Render-your-first-scene). |
| `lit_scene.mojo` | `lit_scene.png` | The [second tutorial](Tutorial-Light-texture-and-animate). |

`photo.mojo` takes the image path first: `examples/photo.mojo assets/brick.png out/photo.png`.

Animated outputs are APNG files. A browser or VS Code plays them. A viewer that does not know APNG shows the first frame.

## Benchmarks

| Program | Shows |
|---|---|
| `bench/raster_bench.mojo` | CPU against GPU rasterization across image sizes. |
| `bench/scene_bench.mojo` | Each stage of the CPU renderer, one worker and every core. |

## Tools

| Program | Shows |
|---|---|
| `tools/gpu_status.mojo` | Whether an accelerator is present. |
| `tools/doc_lint.mojo` | Whether the documentation follows the writing rules. |
