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
| `render_triangles(corners, width, height, background, mode, textures, lighting, fog, tone_mapping, exposure, lines, draws, scissor, points, cubes, backdrop, transmission) -> Framebuffer` | One-shot: draw and read back. |
| `flatten(corners) -> List[Float32]` | The corner buffer the kernel reads, one lane per varying. |
| `flatten_lights(lighting) -> List[Float32]` | The light buffer: the camera's position, the one direction toward it, its up axis, the ambient term, the light probes, then each directional, point, hemisphere, spot and rect area light, then the LTC tables when there is a rect area light, then the shadow maps, then the spot light maps. |
| `flatten_fog(fog) -> List[Float32]` | The fog buffer, six floats. The kind crosses as a kernel argument. |
| `flatten_textures(store)` | Every texture in one buffer, with a descriptor table. |
| `triangle_state(corners) -> List[Int32]` | Texture, blend, material kind, emissive map and alpha map per triangle. |

## GpuRenderer

Hold one across frames. The device buffers survive between draws.

| Member | Meaning |
|---|---|
| `GpuRenderer(width, height)` | Create the context and the buffers. Raises without a GPU. |
| `set_textures(store, cubes=CubeTextureStore())` | Upload every texture, then every cube texture's six faces and its [PMREM](Textures#pmrem) after them, seven rows a cube. All or nothing. |
| `draw(corners, background, mode, lighting, fog, tone_mapping, exposure, lines, draws, scissor, points, backdrop, line_width, transmission)` | Rasterize into the device target. `transmission` is what `Renderer.transmission_target` returns, or an empty target when nothing transmits. `backdrop` is what `Renderer.backdrop` returns, or none: the scene's image background, painted before anything is drawn. `scissor` is a `Rect` the draw may touch, or none for the whole target. A pixel outside it is neither cleared nor drawn, so the target keeps it between draws; see [Renderer](Renderer#viewport-and-scissor). Pass `Lighting(scene, visible=camera.visible_layers())` and `FogView(scene.fog, view)`, the values `Renderer.render` uses. `lines` are two corners a segment, `points` are one corner a [point](Points-and-sprites), and `draws` is the order, all from `Renderer.prepare_frame`. An empty order draws every triangle, then every segment, then every point. The kernel tone maps each pixel as `RenderTarget.resolve` does. |
| `read_back() -> Framebuffer` | Copy color and depth to the host. |

`draw` checks every triangle's state, every segment's state, every point's state and every draw's run on the host before it launches. It checks every texture id, the alpha test, the tone mapping curve and the exposure the same way. The kernel cannot raise.

An alpha map must be `LINEAR` and `IGNORED`. `draw` asks that of the descriptors it uploaded, as the CPU asks it of the store.

`set_textures` builds the new buffers first and replaces the old ones together with the count. A failed upload leaves the previous upload whole.

An antialiased frame is drawn at `Renderer.supersampled()`'s size and shrunk with `render.antialias.downsample`. Pass that renderer's `render_scale` as the draw's `line_width`, or every line thins out when the frame is averaged down. The CPU renderer resolves in linear light instead, which the GPU cannot do while it returns bytes; see [Renderer](Renderer#anti-aliasing). A texture's `anisotropy` crosses in the descriptor table, and the kernel takes the same taps the host takes; see [Textures](Textures#anisotropy).

## Parity with the CPU

Coverage is integer arithmetic and matches the CPU exactly. Shading is floating point and matches within one level per channel, because the device fuses multiply and add. `tests/test_gpu.mojo` holds both backends to those standards on hand-built triangles and on whole prepared scenes.

The kernel calls the same functions as the CPU for the fill rule, texture wrapping and texel blending. It shares the light falloff, the spot light's rim and the Blinn-Phong highlight. It shares the fog factor, the normal and depth packing, and the tone mapping curves too. See [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code).

The state table carries `STATE_PER_TRIANGLE` entries per triangle, twenty-one at present. `triangle_state` writes them from the first corner, in this order:

| Column | Entry |
|---|---|
| 0 to 6 | The texture, the blend policy, the material kind, the emissive map, the alpha map, the gradient map and the matcap. |
| 7 and 8 | The table row of the env map's first face, or -1 for none, and the `Combine` value. |
| 9 to 12 | The roughness, metalness, normal and bump maps. |
| 13 | One if the shadows fall on the triangle, zero if not. |
| 14 and 15 | The packed depth, color and stencil state: `RasterState.ops_word` and `RasterState.stencil_word`. |
| 16 and 17 | The ambient occlusion map and the light map. |
| 18 | The specular map. |
| 19 and 20 | The transmission map and the thickness map. |

Each map column holds a texture id, or `NO_TEXTURE` for none. The `STATE_` constants in `render/gpu.mojo` name every column. A `TOON` triangle's ramp is the gradient map column. The kernel reads the ramp's top row straight out of the texel buffer, with the host's own `toon_index`.

The depth, color and stencil state rides the triangle, segment and point tables as two integers, `RasterState.ops_word` and `RasterState.stencil_word`. The kernel unpacks them and calls `test_fragment`, the function the host's target calls. It keeps the stencil as one local number per pixel, cleared to zero at the start of the launch. See [Materials](Materials#depth-color-and-stencil).

The kernel tracks whether each pixel holds data rather than light, as the host's target does. It keeps the fog and the curve off those pixels.

A transmissive triangle reads the [transmission target](Materials#transmission) from the backdrop buffer. The kernel has no argument to spare, because Metal binds at most thirty-one and it has thirty-one. So `draw` writes the target after the backdrop's own pixels: a header of `TRANSMISSION_HEADER` floats, then the mip chain as floats. The header is the world-to-target matrix, the width, the height and the level count. `flatten_transmission` lays it out.

The kernel calls `volume_refraction`, the host's own function, over a source that reads the chain with `_sample_at`. The host draws the transmission pass: pass `Renderer.transmission_target(scene, assets, camera)` as `draw`'s `transmission`.

The light buffer begins with three floats of camera position at `LIGHTS_EYE`, then three at `LIGHTS_TOWARD`. Those three hold the zero vector for a converging projection, and one unit direction for a parallel one. The kernel passes both to `toward_eye_at`, the host's own function. The camera's own up axis follows at `LIGHTS_UP`, for the frame a `MATCAP` surface is looked up in.

The scale every lit sum takes is at `LIGHTS_SCALE` and the count of rect area lights at `LIGHTS_RECT_COUNT`. The light probes' 27 coefficients follow at `LIGHTS_PROBE`; see [Lights](Lights#light-probes). The lights follow at `LIGHTS_FIRST`. The rect area lights come last among them, then the LTC tables when there is one, then the shadow maps, then the spot light maps. See [Lights](Lights#rect-area), [Lights](Lights#shadows) and [Lights](Lights#spot-light-maps).

## Teardown

`__deinit__` waits for the queue, releases every buffer, and then releases the context. That order prevents a hang under CUDA. See [The CUDA teardown hang](The-CUDA-teardown-hang).

## Coverage

The coverage tool excludes this module. A kernel has no `stderr` for the probes to write to. The parity tests cover it instead.

## Performance

`make bench` compares the two backends. On an Apple M-series GPU the kernel wins by three to seven times from 640 by 480 up. The numbers include allocation and the copy back.
