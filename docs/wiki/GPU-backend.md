# GPU backend

`render/gpu.mojo`. `GpuRenderer` runs the rasterizer as a kernel with one thread per pixel. It consumes the same `RasterVertex` list as the CPU rasterizer and produces the same image.

![An icosahedron turns. Both backends draw this picture.](out/gpu_backend.png)

three.js has no equivalent. Mojo's GPU support is compute only, so this is a compute kernel and not a graphics pipeline.

## Requirements

MAX 26.6.0 and an accelerator. See [How to use the GPU backend](How-to-use-the-GPU-backend). `render/gpu.mojo` is the only module that imports MAX.

## Functions

| Function | Meaning |
|---|---|
| `available() -> Bool` | Whether a GPU is present. |
| `render_triangles(corners, width, height, background, mode, textures, lighting, fog, tone_mapping, exposure) -> Framebuffer` | One-shot: draw and read back. |
| `flatten(corners) -> List[Float32]` | The corner buffer the kernel reads, one lane per varying. |
| `flatten_lights(lighting) -> List[Float32]` | The light buffer: the camera's position, the one direction toward it, its up axis, the ambient term, then each directional, point, hemisphere and spot light. |
| `flatten_fog(fog) -> List[Float32]` | The fog buffer, six floats. The kind crosses as a kernel argument. |
| `flatten_textures(store)` | Every texture in one buffer, with a descriptor table. |
| `triangle_state(corners) -> List[Int32]` | Texture, blend, material kind, emissive map and alpha map per triangle. |

## GpuRenderer

Hold one across frames. The device buffers survive between draws.

| Member | Meaning |
|---|---|
| `GpuRenderer(width, height)` | Create the context and the buffers. Raises without a GPU. |
| `set_textures(store)` | Upload every texture. All or nothing. |
| `draw(corners, background, mode, lighting, fog, tone_mapping, exposure)` | Rasterize into the device target. Pass `Lighting(scene, visible=camera.visible_layers())` and `FogView(scene.fog, view)`, the values `Renderer.render` uses. The kernel tone maps each pixel as `RenderTarget.resolve` does. |
| `read_back() -> Framebuffer` | Copy color and depth to the host. |

`draw` checks every triangle's state, every texture id, the alpha test, the tone mapping curve and the exposure on the host before it launches. The kernel cannot raise.

An alpha map must be `LINEAR` and `IGNORED`. `draw` asks that of the descriptors it uploaded, as the CPU asks it of the store.

`set_textures` builds the new buffers first and replaces the old ones together with the count. A failed upload leaves the previous upload whole.

## Parity with the CPU

Coverage is integer arithmetic and matches the CPU exactly. Shading is floating point and matches within one level per channel, because the device fuses multiply and add. `tests/test_gpu.mojo` holds both backends to those standards on hand-built triangles and on whole prepared scenes.

The kernel calls the same functions as the CPU for the fill rule, texture wrapping and texel blending. It shares the light falloff, the spot light's rim and the Blinn-Phong highlight. It shares the fog factor, the normal and depth packing, and the tone mapping curves too. See [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code).

The state table carries seven entries per triangle. They are its texture, its blend policy, its material kind, its emissive map, its alpha map, its gradient map and its matcap. A `TOON` triangle's ramp rides the last of those. The kernel reads its top row straight out of the texel buffer, with the host's own `toon_index`.

The kernel tracks whether each pixel holds data rather than light, as the host's target does. It keeps the fog and the curve off those pixels.

The light buffer begins with three floats of camera position at `LIGHTS_EYE`, then three at `LIGHTS_TOWARD`. Those three hold the zero vector for a converging projection, and one unit direction for a parallel one. The kernel passes both to `toward_eye_at`, the host's own function. The camera's own up axis follows at `LIGHTS_UP`, for the frame a `MATCAP` surface is looked up in. The lights follow at `LIGHTS_FIRST`.

## Teardown

`__deinit__` waits for the queue, releases every buffer, and then releases the context. That order prevents a hang under CUDA. See [The CUDA teardown hang](The-CUDA-teardown-hang).

## Coverage

The coverage tool excludes this module. A kernel has no `stderr` for the probes to write to. The parity tests cover it instead.

## Performance

`make bench` compares the two backends. On an Apple M-series GPU the kernel wins by three to seven times from 640 by 480 up. The numbers include allocation and the copy back.
