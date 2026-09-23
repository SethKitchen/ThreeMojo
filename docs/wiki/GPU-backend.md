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
| `render_triangles(corners, width, height, background, mode, textures, lighting, fog, tone_mapping, exposure, lines, draws, scissor, points, cubes, backdrop, transmission, programs) -> Framebuffer` | One-shot: draw and read back. |
| `flatten(corners) -> List[Float32]` | The corner buffer the kernel reads, one lane per varying. |
| `flatten_lights(lighting) -> List[Float32]` | The light buffer: the camera's position, the one direction toward it, its up axis, the ambient term, the light probes, then each directional, point, hemisphere, spot and rect area light, then the LTC tables when there is a rect area light, then the shadow maps, then the spot light maps. |
| `flatten_fog(fog) -> List[Float32]` | The fog buffer, six floats. The kind crosses as a kernel argument. |
| `flatten_programs(programs) -> List[Float32]` | Every [node program](Node-materials), end to end, as it follows the fog in the fog buffer. |
| `program_starts(programs) -> List[Int]` | Where each node program starts in the fog buffer. |
| `flatten_textures(store)` | Every texture in one buffer, with a descriptor table. See [Texture table](#texture-table). |
| `triangle_state(corners) -> List[Int32]` | Texture, blend, material kind, emissive map and alpha map per triangle. |

## GpuRenderer

Hold one across frames. The device buffers survive between draws.

| Member | Meaning |
|---|---|
| `GpuRenderer(width, height)` | Create the context and the buffers. Raises without a GPU. |
| `set_textures(store, cubes=CubeTextureStore())` | Upload every texture, then every cube texture's six faces and its [PMREM](Textures#pmrem) after them, seven rows a cube. All or nothing. |
| `draw(corners, background, mode, lighting, fog, tone_mapping, exposure, lines, draws, scissor, points, backdrop, line_width, transmission, programs)` | Rasterize into the device target. `programs` is `Frame.programs` from `Renderer.prepare_frame`: the node programs, with the frame's time and view. `transmission` is what `Renderer.transmission_target` returns, or an empty target when nothing transmits. `backdrop` is what `Renderer.backdrop` returns, or none: the scene's image background, painted before anything is drawn. `scissor` is a `Rect` the draw may touch, or none for the whole target. A pixel outside it is neither cleared nor drawn, so the target keeps it between draws; see [Renderer](Renderer#viewport-and-scissor). Pass `Lighting(scene, visible=camera.visible_layers())` and `FogView(scene.fog, view)`, the values `Renderer.render` uses. `lines` are two corners a segment, `points` are one corner a [point](Points-and-sprites), and `draws` is the order, all from `Renderer.prepare_frame`. An empty order draws every triangle, then every segment, then every point. The kernel tone maps each pixel as `RenderTarget.resolve` does. |
| `read_back() -> Framebuffer` | Copy color and depth to the host. |
| `read_back_target(type=UNSIGNED_BYTE_TARGET, outputs=color_only()) -> RenderTarget` | Copy the light before the tone mapping, the normal, the depth and the data flag into a host target. See [Float render targets](Render-target-and-framebuffer#float-render-targets) and [Multiple render targets](Render-target-and-framebuffer#multiple-render-targets). |

`draw` checks every triangle's state, every segment's state, every point's state and every draw's run on the host before it launches. It checks every texture id, the alpha test, the tone mapping curve and the exposure the same way. The kernel cannot raise.

An alpha map must be `LINEAR` and `IGNORED`. `draw` asks that of the descriptors it uploaded, as the CPU asks it of the store.

`set_textures` builds the new buffers first and replaces the old ones together with the count. A failed upload leaves the previous upload whole.

An antialiased frame is drawn at `Renderer.supersampled()`'s size and shrunk with `render.antialias.downsample`. Pass that renderer's `render_scale` as the draw's `line_width`, or every line thins out when the frame is averaged down. The CPU renderer resolves in linear light instead, which the GPU cannot do while it returns bytes; see [Renderer](Renderer#anti-aliasing). A texture's `anisotropy` crosses in the descriptor table, and the kernel takes the same taps the host takes; see [Textures](Textures#anisotropy).

## Parity with the CPU

Coverage is integer arithmetic and matches the CPU exactly. Shading is floating point and matches within one level per channel, because the device fuses multiply and add. `tests/test_gpu.mojo` holds both backends to those standards on hand-built triangles and on whole prepared scenes.

The kernel calls the same functions as the CPU for the fill rule, texture wrapping and texel blending. It shares the light falloff, the spot light's rim and the Blinn-Phong highlight. It shares the fog factor, the normal and depth packing, and the tone mapping curves too. See [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code).

The state table carries `STATE_PER_TRIANGLE` entries per triangle, thirty-four at present. `triangle_state` writes them from the first corner, in this order:

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
| 21 and 22 | The depth packing's value, and one if the fog veils the triangle, zero if not. |
| 23 to 27 | The sheen color, sheen roughness, iridescence, iridescence thickness and anisotropy maps. See [Materials](Materials#sheen). |
| 28 | Where the triangle's node program starts in the fog buffer, or -1 for none. |
| 29 to 33 | The specular intensity, specular color, clearcoat, clearcoat roughness and clearcoat normal maps. See [Materials](Materials#specular-and-clearcoat-maps). |

Each map column holds a texture id, or `NO_TEXTURE` for none. The `STATE_` constants in `render/gpu.mojo` name every column. A `TOON` triangle's ramp is the gradient map column. The kernel reads the ramp's top row straight out of the texel buffer, with the host's own `toon_index`.

The depth, color and stencil state rides the triangle, segment and point tables as two integers, `RasterState.ops_word` and `RasterState.stencil_word`. The kernel unpacks them and calls `test_fragment`, the function the host's target calls. It keeps the stencil as one local number per pixel, cleared to zero at the start of the launch. See [Materials](Materials#depth-color-and-stencil).

The kernel tracks whether each pixel holds data rather than light, as the host's target does. It keeps the fog and the curve off those pixels.

A transmissive triangle reads the [transmission target](Materials#transmission) from the backdrop buffer. The kernel has no argument to spare, because Metal binds at most thirty-one and it has thirty-one. So `draw` writes the target after the backdrop's own pixels: a header of `TRANSMISSION_HEADER` floats, then the mip chain as floats. The header is the world-to-target matrix, the width, the height and the level count. `flatten_transmission` lays it out.

A [node material](Node-materials) reads its program from the fog buffer, after the fog's six floats. `draw` writes every program there, end to end, and grows the buffer to fit. The state column 28 holds where the triangle's program starts. The kernel runs `run_nodes`, the host's own interpreter, over a source that reads that buffer and samples with `_sample_slot`.

The kernel calls `volume_refraction`, the host's own function, over a source that reads the chain with `_sample_at`. The host draws the transmission pass: pass `Renderer.transmission_target(scene, assets, camera)` as `draw`'s `transmission`.

The light buffer begins with three floats of camera position at `LIGHTS_EYE`, then three at `LIGHTS_TOWARD`. Those three hold the zero vector for a converging projection, and one unit direction for a parallel one. The kernel passes both to `toward_eye_at`, the host's own function. The camera's own up axis follows at `LIGHTS_UP`, for the frame a `MATCAP` surface is looked up in.

The scale every lit sum takes is at `LIGHTS_SCALE` and the count of rect area lights at `LIGHTS_RECT_COUNT`. The light probes' 27 coefficients follow at `LIGHTS_PROBE`; see [Lights](Lights#light-probes). The lights follow at `LIGHTS_FIRST`. The rect area lights come last among them, then the LTC tables when there is one, then the shadow maps, then the spot light maps. See [Lights](Lights#rect-area), [Lights](Lights#shadows) and [Lights](Lights#spot-light-maps).

### Texture table

The texture table holds `TABLE_COLUMNS` entries per texture, seventeen at present. Each map has its own transform and channel, and the table carries them. The lanes and the state columns do not change: a triangle names its maps by id, and each id has one row.

| Column | Entry |
|---|---|
| 0 to 9 | The byte offset, the width, the height, the wrap mode, the filter, the color space, the level count, the alpha mode, the anisotropy and the texel type. |
| 10 to 15 | From `TABLE_PLACEMENT`: the six numbers of `Texture.placement`, as their `Float32` bits. |
| 16 | The channel: `UV_CHANNEL_0` or `UV_CHANNEL_1`. |

`_placement` reads a row back as a `UvPlacement`. The kernel places each map's pair with `UvPlacement.place`, the function the host calls. So both backends sample each map at the same coordinate. The table is the cheapest exact layout. It adds seven numbers per texture, where a matrix per map per triangle adds 132 per triangle.

The kernel also adds the [geometric roughness](Materials#geometric-roughness) with `geometry_roughness`, the host's function. It interpolates the normal at the pixel one to the right and at the pixel one up, as the host does. `LIGHTS_UP` and `LIGHTS_BACK` turn the change into view space.

## Post-processing on the GPU

`GpuComposer` runs an [`EffectComposer`](Post-processing) with the frame on the device. The frame stays on the device between passes. It crosses the bus only for a pass that has no kernel.

```mojo
var device = GpuComposer(renderer.width, renderer.height)
var image = device.render(composer, renderer, scene, assets, camera)
```

The device frame holds four floats per pixel, one data byte, the depth and the stencil. The four floats are premultiplied light, or the data itself, straight, where the pixel holds data, as a host frame holds them.

Before a pass that reads the frame as light, one kernel premultiplies the data pixels, and after it the same kernel stores them straight again. `EffectComposer.run_step` does the same on the host. `render` puts the cleared frame on the device once and reads it back once at the end. The host resolves it through no curve, as `EffectComposer.render` does.

| Member | Meaning |
|---|---|
| `GpuComposer(width, height)` | Create the context and the device frame. Raises without a GPU. |
| `render(composer, renderer, scene, assets, camera, delta_time=0.0) -> Framebuffer` | Run every enabled pass in order. Raises everything `EffectComposer.render` raises, and raises if the renderer is another size. |
| `upload(frame)` and `download(frame)` | Copy a `RenderTarget` to the device frame and back. |
| `round_trips` | How many passes of the last `render` ran on the host. |
| `runs_on_device(kind) -> Bool` | Whether a kind of pass has a kernel. |

These passes run as kernels:

- Copy, blur, bloom, film, dot screen, sepia, vignette, luminosity, afterimage and output.
- FXAA, glitch, halftone, clear, texture and LUT.
- Bokeh. The host draws the depth, and the device blurs the light.

These passes use the fallback. The composer reads the frame back, runs `EffectComposer.run_step` on the host, and puts the frame back:

- Render, SSAA, TAA, SSAO, SAO, SSR, outline and mask. Each draws the scene. The GPU rasterizer resolves to bytes, and a pass needs the light.
- SMAA. Its three stages walk rows and columns of edges, and the port keeps them on the host.

A mask works on the device. Before each pass inside a mask, a kernel copies the frame aside. After the pass, a kernel puts back each pixel that `inside_mask` refuses.

### Shared arithmetic

Each kernel calls the per-pixel function that the host pass calls. Examples are `copy_pixel`, `blur_pixel`, `bloom_glow`, `fxaa_pixel`, `glitch_pixel`, `halftone_pixel` and `lut_pixel`. A pass that reads its neighbors reads a `LightView`. The host builds one over a list, and a kernel builds one over a device buffer. Both read through the same `tap` and `sample`.

The LUT kernel reads a `DecodedVolume` through `filter_volume`, the function `Data3DTexture.sample` calls. The host decodes the table and uploads it for each LUT pass.

The host computes these values once per frame and passes them to the kernel:

- The sine and the cosine of the dot screen's angle and of the glitch's shift.
- The glitch's uniforms and its displacement map.
- The texture pass's texel at each pixel center, which does not depend on the frame.

The afterimage's trail stays in the composer on the host. Both backends then share it, and `reset` clears it. The GPU composer uploads the trail and reads the result back for each afterimage pass.

### Parity of the passes

`tests/test_gpu.mojo` runs each pass on both backends after a render pass and compares the images. The images agree within one level per channel. The film, glitch and halftone passes read a sine hash, and they agree within two levels. A device `sin` can differ from the host's in the last place, and the hash magnifies the difference. Each test also checks `round_trips`, so a pass with a kernel cannot fall back to the host without a failure.

## Teardown

`GpuRenderer.__deinit__` and `GpuComposer.__deinit__` wait for the queue, release every buffer, and then release the context. That order prevents a hang under CUDA. See [The CUDA teardown hang](The-CUDA-teardown-hang).

## Coverage

The coverage tool excludes this module. A kernel has no `stderr` for the probes to write to. The parity tests cover it instead.

## Performance

`make bench` compares the two backends. On an Apple M-series GPU the kernel wins by three to seven times from 640 by 480 up. The numbers include allocation and the copy back.
