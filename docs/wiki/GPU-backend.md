# GPU backend

`render/gpu.mojo`. `GpuRenderer` runs the rasterizer as a kernel with one thread per pixel. It consumes the same `RasterVertex` list as the CPU rasterizer and produces the same image.

three.js has no equivalent. Mojo's GPU support is compute only, so this is a compute kernel and not a graphics pipeline.

## Requirements

MAX 26.5.0 and an accelerator. See [How to use the GPU backend](How-to-use-the-GPU-backend). `render/gpu.mojo` is the only module that imports MAX.

## Functions

| Function | Meaning |
|---|---|
| `available() -> Bool` | Whether a GPU is present. |
| `render_triangles(corners, width, height, background, mode, textures, lighting, fog) -> Framebuffer` | One-shot: draw and read back. |
| `flatten(corners) -> List[Float32]` | The corner buffer the kernel reads, sixteen floats per vertex. |
| `flatten_lights(lighting) -> List[Float32]` | The light buffer: the ambient term, then each directional, point, hemisphere and spot light. |
| `flatten_fog(fog) -> List[Float32]` | The fog buffer, ten floats. The kind crosses as a kernel argument. |
| `flatten_textures(store)` | Every texture in one buffer, with a descriptor table. |
| `triangle_state(corners) -> List[Int32]` | Texture, blend and lit per triangle. |

## GpuRenderer

Hold one across frames. The device buffers survive between draws.

| Member | Meaning |
|---|---|
| `GpuRenderer(width, height)` | Create the context and the buffers. Raises without a GPU. |
| `set_textures(store)` | Upload every texture. All or nothing. |
| `draw(corners, background, mode, lighting, fog)` | Rasterize into the device target. Pass `Lighting(scene, visible=camera.visible_layers())` and `FogView(scene.fog, view)`, the values `Renderer.render` uses. |
| `read_back() -> Framebuffer` | Copy color and depth to the host. |

`draw` checks every triangle's state and every texture id on the host before it launches. The kernel cannot raise.

`set_textures` builds the new buffers first and replaces the old ones together with the count. A failed upload leaves the previous upload whole.

## Parity with the CPU

Coverage is integer arithmetic and matches the CPU exactly. Shading is floating point and matches within one level per channel, because the device fuses multiply and add. `tests/test_gpu.mojo` holds both backends to those standards on hand-built triangles and on whole prepared scenes.

The kernel calls the same functions as the CPU for the fill rule, texture wrapping and texel blending. It shares the light falloff, the spot light's rim and the fog factor too. See [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code).

## Teardown

`__deinit__` waits for the queue, releases every buffer, and then releases the context. That order prevents a hang under CUDA. See [The CUDA teardown hang](The-CUDA-teardown-hang).

## Coverage

The coverage tool excludes this module. A kernel has no `stderr` for the probes to write to. The parity tests cover it instead.

## Performance

`make bench` compares the two backends. On an Apple M-series GPU the kernel wins by three to seven times from 640 by 480 up. The numbers include allocation and the copy back.
