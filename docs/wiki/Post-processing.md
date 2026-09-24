# Post-processing

`postprocessing/composer.mojo`. An `EffectComposer` runs passes over the light a frame leaves in a render target and resolves it once at the end. three.js: `EffectComposer` and the passes under `examples/jsm/postprocessing/`.

![Bright spheres bloom over a dark knot as the camera turns](out/postprocessing.png)

`examples/bloom.mojo` draws this picture.

```mojo
var composer = EffectComposer()
composer.add_pass(render_pass())
composer.add_pass(bloom_pass(1.5, 0.4, 0.85))
composer.add_pass(output_pass())
var image = composer.render(renderer, scene, assets, camera)
```

The frame starts cleared to the renderer's background. A render pass draws the scene into it. Every other pass reads the light and writes it back. The frame is resolved through no curve of its own. An `output_pass` is where the renderer's tone mapping curve is applied, as three.js applies it in an `OutputPass` once a composer is in use.

To run the passes on the GPU, give the composer to a `GpuComposer`. Most passes then run as kernels, and the frame stays on the device between them. See [GPU backend](GPU-backend#post-processing-on-the-gpu).

## The passes

| Builder | three.js | Meaning |
|---|---|---|
| `render_pass()` | `RenderPass` | Draw the scene, clearing first. Through the renderer's antialias when that is on. |
| `copy_pass(opacity=1)` | `ShaderPass(CopyShader)` | Scale every channel of every pixel, alpha included. |
| `blur_pass(spread=1)` | `HorizontalBlurShader` then `VerticalBlurShader` | Nine taps across, then nine down, `spread` pixels apart. |
| `bloom_pass(strength=1, radius=0, threshold=0)` | `UnrealBloomPass` | The light above `threshold` blurred at five halved sizes, weighted by `radius`, scaled by `strength` and added back times its own alpha. |
| `film_pass(intensity=0.5, grayscale=False)` | `FilmPass` | Grain from a hash of the pixel and the time, and gray if asked. |
| `dot_screen_pass(center, angle, scale=1)` | `DotScreenPass` | A halftone of dots over a 256-texel grid. |
| `sepia_pass(amount=1)` | `SepiaShader` | An old photograph's tint. |
| `vignette_pass(offset=1, darkness=1)` | `VignetteShader` | Darkened corners. |
| `luminosity_pass()` | `LuminosityShader` | Gray by luminance. |
| `afterimage_pass(damp=0.96)` | `AfterimagePass` | The last frame fading under this one. |
| `output_pass()` | `OutputPass` | The renderer's tone mapping curve, on every pixel that holds light. |
| `fxaa_pass()` | `FXAAPass` | Smooth jagged edges by their luminance. |
| `smaa_pass()` | `SMAAPass` | Smooth jagged edges by their shape, in three stages. |
| `ssaa_render_pass(sample_level=4, unbiased=True)` | `SSAARenderPass` | Draw the scene once per jittered sample and average the samples. |
| `taa_render_pass(sample_level=0, accumulate=False)` | `TAARenderPass` | Draw jittered samples, and accumulate 32 of them over frames when `accumulate` is on. |
| `ssao_pass(kernel_radius=8 m, min_distance=0.005, max_distance=0.1)` | `SSAOPass` | Draw the scene, and darken it where its surfaces are hemmed in. |
| `sao_pass(intensity=0.18, scale=1, kernel_radius=100, blur=True)` | `SAOPass` | Darken the frame by scalable ambient occlusion. |
| `ssr_pass(opacity=0.5, max_distance=180 m, thickness=0.018 m)` | `SSRPass` | Draw the scene, and lay what each surface reflects over it. |
| `outline_pass(selection, edge_strength=3, edge_thickness=1)` | `OutlinePass` | Draw a glowing edge around the objects on the selected layers. |
| `bokeh_pass(focus=1 m, aperture=0.025, max_blur=1)` | `BokehPass` | Blur each pixel by its distance from the focus. |
| `glitch_pass(size=64, seed=0)` | `GlitchPass` | Shift the channels, tear the frame and add snow, at random moments. |
| `halftone_pass(radius=4)` | `HalftonePass` | Redraw each channel as a grid of dots. |
| `mask_pass(selection, inverse=False)` | `MaskPass` | Let the passes after it change only the pixels that the selected objects cover. |
| `clear_mask_pass()` | `ClearMaskPass` | Let the passes after it change every pixel again. |
| `clear_pass(color=transparent black)` | `ClearPass` | Clear the light, the depth and the stencil. |
| `texture_pass(texture, opacity=1)` | `TexturePass` | Draw a texture over the frame. |
| `lut_pass(lut, intensity=1)` | `LUTPass` | Grade the frame through a color lookup table. |
| `render_pixelated_pass(pixel_size=6, normal_edge_strength=0.3, depth_edge_strength=0.4)` | `RenderPixelatedPass` | Draw the scene small and show it in blocks, with its edges drawn. |
| `gtao_pass(radius=0.25 m, blend_intensity=1)` | `GTAOPass` | Darken the frame by ground-truth ambient occlusion. |
| `render_transition_pass(first, second, texture=NO_TEXTURE, mix_ratio=0)` | `RenderTransitionPass` | Draw two sets of layers and mix them, evenly or by a texture. |
| `cube_texture_pass(cube, opacity=1)` | `CubeTexturePass` | Draw a cube texture as the camera sees it. |
| `save_pass()` | `SavePass` | Keep a copy of the frame. |
| `shader_pass(program, input="tDiffuse")` | `ShaderPass` | Run a node program over the screen. |
| `effect_pass(effect)` | `ShaderPass` with one of fifteen shaders | Run a screen shader. Each shader also has a builder of its own. |
| `god_rays_pass(sun, intensity=0.69, fake_sun=False)` | The god-rays example | Lay rays from a sun over the frame. |

Each builder returns a `Pass`. A `Pass` has a `kind`, an `enabled` flag and every setting any kind reads. The effect passes read `strength`, `radius`, `threshold`, `offset`, `scale`, `angle`, `center`, `grayscale` and `time`. The SSAA and TAA passes read `sample_level`, `unbiased`, `accumulate` and `accumulate_index`. The screen-space passes read `ssao`, `sao`, `ssr` and `outline`. See [Screen-space passes](#screen-space-passes).

The bokeh, glitch, halftone and mask passes read `bokeh`, `glitch`, `halftone` and `mask`. The clear pass reads `clear_color`. The texture pass reads `texture` and `strength`. The LUT pass reads `lut` and `strength`. See [More passes](#more-passes).

The pixelated, GTAO, transition, shader, shader effect and god-rays passes read `pixelated`, `gtao`, `transition`, `shader`, `effect` and `god_rays`. The transition pass also reads `first`, `second` and `texture`. The cube texture pass reads `cube` and `strength`. See [Scene, GTAO and shader passes](#scene-gtao-and-shader-passes) and [Shader effects](#shader-effects).

Change a setting after the pass is added, as three.js changes a uniform. A pass that is not enabled is skipped.

The defaults are three.js's. The dot screen's angle is an `Angle`. A bare number does not compile. `tests/compile_fail/` proves it.

## The composer

| Member | three.js | Meaning |
|---|---|---|
| `add_pass(pass)` | `addPass` | Append a pass. |
| `insert_pass(pass, index)` | `insertPass` | Put a pass before the one at `index`. |
| `remove_pass(index)` | `removePass` | Take a pass out. |
| `pass_count() -> Int` | | How many passes there are. |
| `reset()` | `reset` | Forget what every afterimage pass saw and what every TAA pass accumulated. |
| `saved_image(index) -> List[FloatColor]` | `SavePass.renderTarget` | The copy of the frame that the save pass at `index` kept. Empty before the pass runs. |
| `render(renderer, scene, assets, camera, delta_time=0) -> Framebuffer` | `render` | Run every enabled pass in order and return the image. |
| `run_step(index, frame, renderer, scene, assets, camera, delta_time)` | | Run one pass on a frame, less the mask's bookkeeping. It fits the memories first, and refuses an index that names no pass. The GPU composer calls it for a pass with no kernel. |

`delta_time` is how many seconds passed since the last frame. It advances each film pass's grain and each outline pass's pulse. Zero holds them still.

## Validation

`PassKind` is a type. `is_valid` names the thirty-five kinds. `check_pass` refuses any other kind. It refuses a setting that is not finite. It refuses a strength, radius, threshold, offset or scale that is negative. It refuses a bloom radius above one and an afterimage damp above one.

`check_pass` also refuses a sample level outside zero through five. three.js clamps the level; this port refuses it. It refuses an accumulate index outside minus one through 32. `jitter_offsets` refuses a level outside zero through five. `JitteredCamera` refuses an offset that is not finite and an image size that is not positive.

`add_pass` and `insert_pass` call `check_pass`. `render` calls it again on every pass, so a setting changed after the pass was added is checked too. `render` also refuses a frame time that is negative or not finite.

## What each pass works on

A blur, a bloom, a copy and an afterimage work on the premultiplied light, where a sum is a sum. A color transform works on the straight color of each pixel and premultiplies it back, as a shader sees a straight texel. The sepia, the gray, the dot screen, the vignette, the grain and the curve are color transforms. Every pass keeps alpha but the copy, which scales it as three.js's `CopyShader` scales the whole texel.

The exceptions in [More passes](#more-passes) follow their shaders. The bokeh and the halftone are opaque. The glitch adds to alpha, and the texture is drawn over the alpha too.

A tap past the edge of the frame reads the edge pixel, as a clamped texture does. A pixel that holds data rather than light, a normal or a depth, is not tone mapped by the output pass. The other passes treat it as light.

The bloom's five levels are halved as three.js halves them, rounded up, never below one pixel. Its blur kernels are three, five, seven, nine and eleven taps to each side, each with a sigma of its own width. three.js adds the glow with `AdditiveBlending`, which multiplies the color by the glow's alpha. That alpha is the strength times the level weights, so twice the strength gives four times the glow. The bloom keeps the frame's alpha. The dot screen measures its pattern over a fixed 256 by 256 grid, as three.js's pass sets `tSize` once.

## Anti-aliasing

`postprocessing/antialiasing.mojo`. Four passes smooth jagged edges. FXAA and SMAA work on the finished frame. SSAA and TAA draw the scene more than once, each time moved by a fraction of a pixel.

```mojo
var composer = EffectComposer()
composer.add_pass(render_pass())
composer.add_pass(output_pass())
composer.add_pass(smaa_pass())
var image = composer.render(renderer, scene, assets, camera)
```

Put `fxaa_pass` and `smaa_pass` after the `output_pass`, as the three.js examples do. Then they see the light that the curve leaves. Put `ssaa_render_pass` and `taa_render_pass` where a `render_pass` goes. They replace the frame.

### FXAA

`fxaa_pass` is three.js's `FXAAShader`, line for line. It reads the luminance of each pixel and its eight neighbors, with the weights 0.3, 0.59 and 0.11. A pixel whose neighborhood spans less than 0.0312, or less than 0.063 of the brightest, is kept.

Otherwise the pass finds the edge through the pixel. It walks along the edge in six steps of 1, 1.5, 2, 2, 2 and 4 pixels. It guesses 8 more when the edge does not end. The pixel's texture read moves across the edge by the larger of two factors. The subpixel factor grows with the difference between the pixel and its neighborhood. The edge factor grows as the pixel comes nearer to an end of the edge.

### SMAA

`smaa_pass` is three.js's `SMAAPass` in its three stages. Each stage is a function that you can call on its own.

1. `smaa_edges` marks an edge on the left or the top of a pixel. The step to that neighbor must be at least 0.1 in some channel. It must also be at least half the largest step to the four neighbors and to the pixels two to the left and two above.
2. `smaa_weights` walks each edge to its two ends and reads the edges that cross it there. `smaa_area` turns that pattern and the two distances into two weights. A vertical edge is a horizontal edge on the transposed map.
3. `smaa_blend` mixes each pixel toward the neighbor with the largest weight. It raises red, green and blue to 2.2 first and lowers them after, as three.js's WebGL port does.

### SSAA and TAA

`ssaa_render_pass` is three.js's `SSAARenderPass`. It draws the scene once per sample of three.js's jitter patterns: 1, 2, 4, 8, 16 or 32 samples for levels zero through five. Each sample is cleared to the renderer's background and drawn as a render pass draws. The pass adds each sample with a weight of one over the count. With `unbiased` on, the weights spread evenly over a thirty-second about that, as three.js spreads them.

`taa_render_pass` is three.js's `TAARenderPass`. With `accumulate` off, it is an SSAA pass of its level. With `accumulate` on, the first frame is supersampled and held. Each frame then draws two to the level of the 32 samples, and shows their sum over the held frame. When all 32 are in, the pass shows their average and draws no more.

Set `accumulate_index` to minus one, or call `reset`, when the scene or the camera moves. Then the pass starts again. A frame of another size also starts it again.

`JitteredCamera` does the jitter. It wraps any camera and moves its projection, as three.js's `setViewOffset` moves it. An offset of one pixel right moves the picture one pixel left. `jitter_offsets(level)` returns three.js's patterns in pixels.

A pixel of an SSAA frame is data only if it is data in every sample. Its depth is the nearest. A TAA frame keeps the data flags and the depths of its held frame.

### How SMAA differs from three.js

The edges and the blend are three.js's arithmetic. The weights stage computes what three.js reads from two textures, and the results differ a little.

- **The search.** three.js walks two pixels at a time with a bilinear read and decodes the read through a 66 by 33 search texture. This port walks one pixel at a time and stops where SMAA stops: at a crossing edge, or where the edge ends. The walk reaches 15 pixels to the left and 16 to the right, as SMAA's eight steps reach.
- **The area.** three.js reads the area from a 160 by 560 texture. SMAA's `AreaTex.py` script fills that texture. This port computes the area with the script's `area`, `areaortho` and `smootharea` functions, for SMAA 1x with no subpixel offset. The texture holds the area at squared distances and interpolates between them. This port uses the exact distance, and it does not round the area to bytes.
- **The crossing rows.** three.js's WebGL port reads the crossing edges at the right end one row lower than SMAA does. This port reads both ends at the rows SMAA reads.
- **The texel.** Every pass reads the texel as stored, premultiplied. For an opaque pixel that is the straight color.

The diagonal search and the corner detection of full SMAA are not in three.js, and they are not ported.

## Screen-space passes

`postprocessing/screen_space.mojo`. Four passes read the depth that a render leaves beside its light. SSAO and SAO darken the frame where surfaces are hemmed in. SSR lays reflections over the frame. The outline pass draws a glowing edge around chosen objects.

```mojo
var composer = EffectComposer()
composer.add_pass(ssao_pass(Length(0.5, METER)))
composer.add_pass(output_pass())
var image = composer.render(renderer, scene, assets, camera)
```

Put `ssao_pass` and `ssr_pass` where a `render_pass` goes. They draw the frame themselves, as three.js's passes do. Put `sao_pass` and `outline_pass` after a `render_pass`. They draw the depth they need, and change the frame that they are given. Put all four before the `output_pass`.

Each pass keeps its settings in a field of `Pass`: `ssao`, `sao`, `ssr` or `outline`. The fields have three.js's names and defaults. Change a field after the pass is added, as three.js changes a property.

### The depth and the normals

`DepthView` reads a render target's depth through the camera that drew it. The target keeps NDC depth, from minus one to one. `DepthView` keeps the window depth, from zero to one, as a three.js depth texture holds it. A pixel where nothing was drawn has a depth of one.

A target drawn with a [logarithmic](Rasterization#logarithmic-depth) or a [reversed](Rasterization#reversed-depth) depth keeps its mode in `depth_mode`. `DepthView` takes that mode and reads the stored depth back into the same window depth. So SSAO, SAO, SSR and the bokeh pass work in every mode. The outline pass and the SSAA pass compare depths in the mode of the frame.

- `position(u, v, depth)` is three.js's `getViewPosition`. It returns the point in the camera's space.
- `view_z(depth)` is `getViewZ`.
- `linear_depth(view_z)` is `viewZToOrthographicDepth`: zero at the near plane and one at the far plane.
- `depth_at(u, v)` reads the nearest pixel, held at the edges, as a depth texture with `NearestFilter` reads it.
- `normal_at(x, y)` and `normals()` return the view-space normal of a pixel.

The normals come from the frame's normal attachment. The composer draws its frame with one when an SSAO, SAO or SSR pass is on. See [Multiple render targets](Render-target-and-framebuffer#multiple-render-targets). Pass `RenderTarget.normals` as the last argument of `DepthView` to use them. three.js draws the scene again with a `MeshNormalMaterial` to get them.

A pixel with no normal in the attachment takes one from the depth. So does every pixel of a frame without an attachment. The reconstruction is the one in three.js's own `GTAOShader`. On each axis, it takes the neighbor that continues the surface better, and crosses the two slopes. A neighbor past the edge of the frame reads zero, as WebGL's `texelFetch` reads it.

### SSAO

`ssao_pass` is three.js's `SSAOPass`. The pass draws the scene. Then, for each pixel that holds a surface, it tests a kernel of samples in the hemisphere above the surface.

1. `ssao_kernel(size, seed)` is `generateSampleKernel`. Each sample is a random direction above the surface. The `i`th of `n` samples has a length of 0.1 + 0.9 (i / n)².
2. `ssao_noise(seed)` is `generateRandomKernelRotations`. It gives 16 values that repeat over the frame every four pixels. Each value turns the kernel about the normal.
3. `ssao_occlusion` is `SSAOShader`. The kernel is scaled by `kernel_radius` and set on the surface. A sample occludes when the frame's linear depth where it lands is in front of it. The difference must be more than `min_distance` and less than `max_distance`.
4. `ssao_blur` is `SSAOBlurShader`. It averages the five by five pixels around each pixel.

The blurred value multiplies the light of each pixel. Alpha is kept. `kernel_radius` is a `Length`. `min_distance` and `max_distance` are fractions of the camera's near-to-far range, as in three.js.

### SAO

`sao_pass` is three.js's `SAOPass`. `sao_occlusion` is `SAOShader`. Seven samples spiral out from each pixel over four turns. A hash of the pixel and a seed turns the start of the spiral. The seed is three.js's `randomSeed`. The composer draws a new seed every frame from `sao.seed`, as three.js draws one from `Math.random`.

- `sao_sample_occlusion` is `getOcclusion`. It returns the slope toward the sample, less `bias`, over the scaled distance. The result is divided by one plus that distance squared.
- The occlusion is the average of the samples that land on a surface, scaled by `intensity`. A pixel with no such sample keeps its light.
- With `blur` on, `depth_limited_blur` is `DepthLimitedBlurShader`. It blurs down, then across, over `blur_radius` pixels with `blur_std_dev`. `blur_weights` is `BlurShaderUtils.createSampleWeights`. On each side, the blur stops at the first neighbor whose distance differs by more than `blur_depth_cutoff` of the range.

One minus the occlusion multiplies the light of each pixel. `kernel_radius` is in pixels, as in three.js.

### SSR

`ssr_pass` is three.js's `SSRPass`. The pass draws the scene. `ssr_reflections` is `SSRShader`. From each surface, a ray leaves mirrored about the normal. The ray goes out `max_distance` from the surface's plane. It stops at the near plane.

The pass walks the ray across the screen one pixel at a time. The first surface that the ray passes behind is a hit. The surface must be within `thickness` of the ray, or within three pixels' width. With `infinite_thick` on, every surface behind the ray is a hit. A hit surface must face the ray. A hit farther than `max_distance` from the plane ends the walk with no reflection.

The strength of a reflection starts at `opacity`. With `distance_attenuation` on, it fades with the square of the distance. With `fresnel` on, it fades as the view meets the surface square on. With `blur` on, `ssr_blur` is `SSRBlurShader`, applied twice. The pass lays each reflection over the light by its strength, as three.js's `NormalBlending` does.

### Outline

`outline_pass(selection)` is three.js's `OutlinePass`. three.js takes a list of objects. This port takes a set of layers: the objects on those layers are selected. An empty set outlines nothing, as three.js's pass does with no objects.

1. The pass draws the depth of the whole scene. Then it draws the depth of the selected layers alone, through the same camera.
2. `outline_mask` marks the selected pixels. It also marks a selected pixel where something else is in front. three.js compares the selected objects with the depth of the other objects. The whole scene is nearer than a selected surface exactly where another object is in front, so the result is the same.
3. The mask is copied to half the frame's size. The edges are found there, and colored `visible_edge_color` or `hidden_edge_color`.
4. The edges are blurred at half size over `edge_thickness`, and at a quarter size over four texels.
5. The pass adds the narrow blur plus the wide blur times `edge_glow`, scaled by `edge_strength`, to the light outside the selected objects.

With a `pulse_period` above zero, the edge colors pulse. three.js reads the clock. This port reads the time that `delta_time` adds up.

### Outputs

`ScreenSpaceOutput` is a type. It is three.js's `SSAOPass.OUTPUT`, `SAOPass.OUTPUT` and `SSRPass.OUTPUT` in one. Every value applies to the SSAO, SAO and SSR passes.

| Output | three.js | Meaning |
|---|---|---|
| `DEFAULT_OUTPUT` | `Default` | The effect over the frame. |
| `EFFECT_OUTPUT` | `SSAO`, `SAO`, `SSR` | The effect alone, before its blur. |
| `BLUR_OUTPUT` | `Blur` | The effect alone, after its blur. |
| `BEAUTY_OUTPUT` | `Beauty` | The frame as it came in. |
| `DEPTH_OUTPUT` | `Depth` | One minus the linear depth, as gray. |
| `NORMAL_OUTPUT` | `Normal` | The view-space normal, packed from zero to one. |

### Validation of the screen-space passes

`check_ssao`, `check_sao`, `check_ssr` and `check_outline` refuse settings that no pass can use. `check_pass` calls all four, so `add_pass` and `render` call them too.

- Every check refuses a setting that is not finite, and an output that is none of the six.
- `check_ssao` refuses a negative radius or distance, and a kernel of no samples.
- `check_sao` refuses a negative intensity, minimum resolution, blur radius or cutoff. It refuses a scale, kernel radius or deviation that is not positive.
- `check_ssr` refuses an opacity outside zero to one, a negative thickness, and a reach that is not positive.
- `check_outline` refuses a negative color channel, strength, glow or period, and a thickness that is not positive.
- `DepthView` refuses a size that is not positive and a depth of the wrong length. It refuses a list of normals of the wrong length. It refuses a near distance that is not before the far distance, and a projection with no inverse.

### How the screen-space passes differ from three.js

- **The normals.** three.js draws a normal pass. This port reads the normals from the frame's normal attachment, filled in the same pass as the light. Where the attachment has none, it reconstructs them from the depth, as three.js's `GTAOShader` does. There a curved surface shows its triangles, because the depth of a triangle is flat.
- **The randomness.** three.js uses `Math.random`. This port uses `SeededRandom`, so the same seed gives the same frame. The SSAO noise is a random value from minus one to one. three.js puts two random values through simplex noise first.
- **The divisions by zero.** three.js divides zero by zero in three places. SSAO turns the kernel by a noise parallel to the normal. SAO reads a sample at the pixel's own point. SSR reflects from a surface seen edge on. This port gives no occlusion or no reflection there.
- **SSR with no neighbors.** Where no neighbor of a pixel reflects anything, `ssr_blur` gives black. three.js divides by zero there.
- **The outline's alpha.** three.js adds the outline with `AdditiveBlending`, which also adds to alpha. This port keeps alpha, as the bloom does.
- **The effect output of SAO.** three.js's `OUTPUT.SAO` shows the occlusion after its blur. This port shows it before the blur, and `BLUR_OUTPUT` shows it after.

### Not ported in the screen-space passes

- SSR's `selects`, its metalness pass, `bouncing` and `groundReflector`.
- The outline's `usePatternTexture` and `patternTexture`, and its `downSampleRatio`, which is fixed at two as in three.js.
- A pass that the renderer's viewport or scissor narrows. The passes take the camera to fill the whole frame.

`GTAOPass` is ported. See [GTAO](#gtao).

## More passes

`postprocessing/effects.mojo`. Eight more passes blur by depth, glitch, draw a halftone, mask, clear, add a texture and grade through a lookup table. Each is a builder in `postprocessing/composer.mojo`, and each has three.js's defaults.

```mojo
var composer = EffectComposer()
composer.add_pass(clear_pass())
composer.add_pass(mask_pass(Layers(UInt32(2))))
composer.add_pass(texture_pass(texture))
composer.add_pass(clear_mask_pass())
var image = composer.render(renderer, scene, assets, camera)
```

That is three.js's masking example. The texture fills only the pixels that the objects on layer one cover.

### Bokeh

`bokeh_pass` is three.js's `BokehPass`. Put it after a `render_pass`. It draws the scene's depth itself and blurs the frame that it is given.

- `bokeh_blur` is the shader's `dofblur`. The focus plus the view-space z, times `aperture`, is the reach. The reach is clamped to `max_blur` in each direction.
- `bokeh_light` is `BokehShader`. Each pixel is the average of 41 taps. They are the pixel, 16 taps at the full reach, and 8 taps each at 0.9, 0.7 and 0.4 of it. `bokeh_taps` returns their offsets.
- The vertical offsets are scaled by the frame's aspect. The result is opaque, as the shader sets alpha to one.

`focus` is a `Length`. `aperture` is in texture widths per meter. `max_blur` is in texture widths.

### Glitch

`glitch_pass(size, seed)` is three.js's `GlitchPass`. Each frame that `render` draws advances it. The draws come from `SeededRandom`, in three.js's order.

1. `GlitchSettings(size, seed)` is the constructor. It draws the displacement map, then the first trigger from 120 to 240.
2. `glitch_uniforms` is the start of `render`. A frame whose count is a multiple of the trigger is wild: a large shift, a wide tear and a new trigger. With `go_wild` on, every frame is wild.
3. The frames in the first fifth after a wild frame glitch a little. The other frames are not changed.
4. `glitch_light` is `DigitalGlitch`. It tears a row band and a column band, and pushes the frame by the map. It moves red and blue apart and adds snow.

`glitch_heightmap(size, seed)` returns the displacement map. It is read with the nearest texel, held at the edges.

### Halftone

`halftone_pass(radius)` is three.js's `HalftonePass`. Its other settings are the fields of `halftone`, with three.js's names and defaults.

- Each channel has a grid at its own angle: `rotate_r`, `rotate_g` and `rotate_b`. The grid points are `radius` pixels apart.
- `reference_cell` finds the four grid points around a pixel. `scatter` moves each point by a random amount, up to a quarter of the spacing.
- `halftone_sample` averages nine taps around a grid point. That average sizes the dot at the point.
- `dot_radius_distance` measures a pixel against a dot. The shape is `HALFTONE_DOT`, `HALFTONE_ELLIPSE`, `HALFTONE_LINE` or `HALFTONE_SQUARE`.
- `halftone_blend` mixes the halftone with the frame by `blending`. The mode is `HALFTONE_LINEAR`, `HALFTONE_MULTIPLY`, `HALFTONE_ADD`, `HALFTONE_LIGHTER` or `HALFTONE_DARKER`.

With `grayscale` on, the three channels are averaged. With `disable` on, the frame is not changed. The result is opaque.

### Mask and clear mask

`mask_pass(selection, inverse)` is three.js's `MaskPass`. `clear_mask_pass()` is `ClearMaskPass`. Between the two, a pass changes only the pixels inside the mask.

1. The mask pass draws the objects on the selected layers alone, through the same camera.
2. `mask_stencil` writes the render target's stencil buffer. It writes one where an object covers the pixel, and zero at the other pixels. With `inverse` on, it writes zero and one.
3. After each pass, `keep_outside_mask` puts back each pixel whose stencil is not one. `inside_mask` is the test that three.js's mask leaves on: equal to one.
4. The clear mask pass stops the test. A disabled mask pass or clear mask pass does nothing, as in three.js.

The mask pass does not change the light or the depth, as three.js turns off those writes.

### Clear and texture

`clear_pass(color)` is three.js's `ClearPass`. `clear_light` sets the light to the color, the depth to far, and the stencil to zero. The color is in sRGB, and its alpha is three.js's `clearAlpha`.

`texture_pass(texture, opacity)` is three.js's `TexturePass`. The texture is a `TextureId` in the assets that `render` is given. `texture_light` scales the texture by `opacity` and draws it over the frame, alpha included. Below an opacity of one, the frame keeps one minus the scaled alpha of its color. At an opacity of one, the texture replaces the frame. That is `CopyShader` with three.js's premultiplied normal blending, which is on only below an opacity of one.

### LUT

`lut_pass(lut, intensity)` is three.js's `LUTPass`. It grades the frame through a color lookup table, a [3D texture](Textures#3d-textures) in the assets. `read_lut_cube` in `loaders/lut_cube.mojo` reads the table from a `.cube` file, as three.js's `LUTCubeLoader` does.

```mojo
var table = read_lut_cube("grade.cube")
var lut = assets.data_3d_textures.add(table.texture^)
composer.add_pass(render_pass())
composer.add_pass(output_pass())
composer.add_pass(lut_pass(lut, intensity=1.0))
```

Put the LUT pass after the output pass, as three.js's example does. Then the table reads the colors that a display shows.

1. `lut_light` encodes the straight color of each pixel through the sRGB curve. three.js's shader reads the target that `OutputPass` encoded.
2. `lut_color` is `LUTShader`. It pulls the color in by half a texel, so that zero and one land on the centers of the edge texels. It reads the table at that coordinate: red across, green up and blue deep. The table's size is its width, as `lutSize` is.
3. The looked-up color replaces the color by `intensity`, as the shader's `mix` does. Alpha is kept.
4. `lut_light` decodes the result. The encode at the end of the frame gives the numbers that three.js's shader wrote.

`parse_lut_cube(text, texel_type=UNSIGNED_BYTE_TYPE)` reads the text of a `.cube` file. It returns a `LutCube` with `title`, `size`, `domain_min`, `domain_max` and `texture`. These are three.js's `title`, `size`, `domainMin`, `domainMax` and `texture3D`.

- `TITLE "name"` sets the title. `LUT_3D_SIZE n` sets the size, two through 256.
- `DOMAIN_MIN` and `DOMAIN_MAX` are kept. They are not applied, because three.js's `LUTPass` does not apply them.
- Each line of three numbers is one entry. Red changes fastest, then green, then blue. There must be `size` cubed entries.
- A line that starts with `#` is a comment. Another keyword, such as `LUT_3D_INPUT_RANGE`, is skipped, as three.js skips it.
- With `UNSIGNED_BYTE_TYPE`, each number times 255 is cut to a whole byte, as a `Uint8Array` cuts it. With `FLOAT_TYPE`, the numbers are kept as they are.
- The texture is clamped on every axis, `BILINEAR` and `LINEAR`, as three.js sets it.

### Validation of the more passes

`check_bokeh`, `check_glitch` and `check_halftone` refuse settings that no pass can use. `check_pass` calls all three.

- `check_bokeh` refuses a focus, aperture or largest blur that is negative or not finite.
- `check_glitch` refuses a map size outside one through 4096, and a generator state that does not fit 32 bits. It refuses a negative frame count and a trigger that is not positive.
- `check_halftone` refuses a shape or a blending mode that is not named. It refuses a setting that is not finite, and a radius that is not positive. It refuses a negative scatter and a blending outside zero to one.
- `check_pass` refuses a texture pass with `NO_TEXTURE`. `render` refuses a texture id that is not in the assets.
- `check_pass` refuses a LUT pass with `NO_DATA_3D_TEXTURE`, and a negative intensity. `render` refuses a table that is not in the assets. `lut_light` calls the table's `validate`.
- `parse_lut_cube` refuses a texel type that is not named, a file with no `LUT_3D_SIZE`, and a `LUT_1D_SIZE`. It refuses a size outside two through 256.
- `parse_lut_cube` refuses a line that does not hold three finite numbers, and a count of entries that is not `size` cubed. It refuses a domain minimum above its maximum.
- For bytes, `parse_lut_cube` refuses a number outside zero to one. A `Uint8Array` wraps such a number, and three.js does not check it.

`HalftoneShape` and `HalftoneBlending` are types. A bare number does not compile. `tests/compile_fail/` proves it.

### How the more passes differ from three.js

- **The mask selection.** three.js's `MaskPass` takes a scene and a camera. This port takes a set of layers, as the outline pass does, and the composer's camera.
- **The mask coverage.** A pixel is in the mask where a selected object writes its depth. A surface that blends, or that writes no depth, does not add to the mask.
- **Every pass obeys the mask.** In three.js, a clear ignores the stencil test. So a clear pass, and a render pass that clears, clear the whole frame inside a mask. This port keeps the pixels outside the mask for every pass.
- **The bokeh depth.** three.js draws the depth again with a `MeshDepthMaterial`. This port draws the scene as a render pass does, so a surface that blends is not in the depth.
- **The bokeh aspect.** three.js reads the camera's aspect. This port reads the frame's width over its height.
- **The randomness.** three.js uses `Math.random`. This port uses `SeededRandom`, so the same seed gives the same frames.
- **The texel.** The bokeh, glitch and halftone read the light as stored, premultiplied. For an opaque pixel that is the straight color.
- **The LUT's input.** three.js's LUT pass reads whatever the target holds. This frame holds linear light, so the LUT pass encodes it to sRGB first. Before the output pass, three.js's table reads linear light, and this port's table reads encoded color.
- **The `.cube` reader is stricter.** three.js reads each line that matches its pattern and ignores the others. This port refuses a malformed line and a wrong count of entries.

### Not ported in the more passes

- A mask pass with its own scene, and the `clear` flag of a mask pass or a texture pass.
- `HalftonePass.setSize`. The halftone always uses the frame's size.
- The LUT pass's 2D table, which three.js once used for WebGL 1.

`LUT3dlLoader` and `LUTImageLoader` are ported. They read `.3dl` files and image strips into a 3D texture for `lut_pass`. See [More model files](More-model-files#3dl) and [LUT image](More-model-files#lut-image).

## Scene, GTAO and shader passes

`postprocessing/render_passes.mojo`, `postprocessing/gtao.mojo` and `postprocessing/shader_pass.mojo`. Six more passes draw the scene anew, darken it by occlusion, keep a copy of the frame and run a program over it.

```mojo
var composer = EffectComposer()
composer.add_pass(render_pixelated_pass(pixel_size=4))
composer.add_pass(gtao_pass())
composer.add_pass(output_pass())
var image = composer.render(renderer, scene, assets, camera)
```

### Pixelated

`render_pixelated_pass` is three.js's `RenderPixelatedPass`. Put it where a `render_pass` goes. It draws the scene into a target a pixel size smaller each way, with its depth and its normals. `sized_renderer` makes the small renderer with the same settings.

`pixelated_light` shows each drawn texel as a block of pixels, with the nearest texel. `pixelated_strength` is the pass's shader. Where a neighbor is behind the texel, the depth edge darkens it by `depth_edge_strength`. Otherwise, where a neighbor faces another way, the normal edge lightens it by `normal_edge_strength`.

### GTAO

`gtao_pass` is three.js's `GTAOPass`. Put it after a `render_pass`. It draws the depth and the normals itself. The fields of `GtaoSettings` are three.js's parameters, with its defaults.

1. `gtao_occlusion` is `GTAOShader`. It cuts the hemisphere above each surface into three slices, or five for thirty samples or more. In each slice it finds the highest horizon both ways, and it integrates the visible arc against the normal.
2. `gtao_noise` turns the slices from pixel to pixel by a five by five magic square, as `generateMagicSquareNoise` does.
3. `gtao_denoise` is `PoissonDenoiseShader`. It averages sixteen taps on a Poisson disk, each weighed by how like the pixel it is.
4. With the default output, the frame is multiplied by the result, mixed toward one by `blend_intensity`. The other five outputs are the SSAO pass's. See [Outputs](#outputs).

### Transition

`render_transition_pass(first, second, texture, mix_ratio)` is three.js's `RenderTransitionPass`. Put it where a `render_pass` goes. It draws the objects on the `first` layers and then on the `second` layers, through the composer's camera. `transition_pixel` mixes the two views. A `mix_ratio` of one shows the first view, and zero shows the second.

With a texture, a threshold sweeps across the texture's red channel as the ratio moves. `threshold` sets how soft the edge is. Without one, the two views are mixed evenly.

`render_transition(renderer, first_scene, first_camera, second_scene, second_camera, assets, settings, texture)` draws two scenes, each through its own camera, as three.js's pass does. It returns the image.

### Cube texture

`cube_texture_pass(cube, opacity)` is three.js's `CubeTexturePass`. `cube_overlay` reads the cube in the direction of each pixel's ray. The camera's position does not change it. `cube_texture_light` draws it over the frame as the texture pass draws.

### Save and shader

`save_pass()` is three.js's `SavePass`. It keeps a copy of the frame and changes nothing. `EffectComposer.saved_image` returns the copy.

`shader_pass(program, input)` is three.js's `ShaderPass`. The program is a [node program](Node-materials) in the assets' `programs`. Compile a fragment shader against `SCREEN_VERTEX_SHADER` with `compile_shader_material`, or build a `NodeGraph`.

```mojo
var program = compile_shader_material(SCREEN_VERTEX_SHADER, fragment)
program.set_uniform("amount", Float32(0.5))
var id = assets.programs.add(program^)
var step = shader_pass(id)
step.shader.saved = "tSaved"
step.shader.saved_pass = 1
composer.add_pass(step^)
```

- The sampler named `input`, `tDiffuse` by default, reads the frame before the pass.
- The sampler named `shader.saved` reads the image of the save pass at `shader.saved_pass`. Before that pass runs, it reads transparent black.
- Every other sampler reads a texture in the assets.
- `uv` and a varying copied from it are the pixel's texture coordinate. The `time` node reads the pass's `time`, which `delta_time` advances.
- The output node, or else the color node, is the straight color. The opacity node is the alpha. A fragment that the mask node throws away keeps the pixel.

### Validation of the scene and shader passes

- `check_pixelated` refuses a pixel size below one, and an edge strength that is negative or not finite.
- `check_gtao` refuses an output that is not named and a setting that is not finite. It refuses a radius, thickness, scale or phi that is not positive, and a fall-off outside zero to one. It refuses a negative intensity or exponent, fewer than two samples, and a denoise radius below one pixel.
- `check_transition` refuses a setting that is not finite, and a threshold that is not positive.
- `check_shader` refuses `NO_NODES`, and a saved sampler that names no pass.
- `check_pass` refuses a cube texture pass with `NO_CUBE_TEXTURE`, and a transition pass that reads a texture with `NO_TEXTURE`.
- `shader_light` refuses a saved image that is not the frame's size, and a texture that is not in the store. `saved_image` refuses an index that names no save pass.

### How the scene and shader passes differ from three.js

- **The transition's scenes.** three.js's pass takes two scenes and two cameras. The pass takes two sets of layers and the composer's camera. `render_transition` takes two scenes and two cameras.
- **The shader's program.** three.js compiles GLSL for WebGL. The pass runs a node program. GLSL runs through the subset that `compile_shader_material` knows.
- **The GTAO noise.** three.js seeds the denoise's simplex noise from `Math.random`. This port seeds it from `seed`.

## Shader effects

`postprocessing/shaders.mojo`. Fifteen of three.js's screen shaders, each run as a `ShaderPass` runs it, and its god-rays chain.

```mojo
composer.add_pass(render_pass())
composer.add_pass(hue_saturation_pass(hue=0.2, saturation=0.3))
composer.add_pass(god_rays_pass(Vector3(0, 1000, -1000)))
```

`effect_pass(effect)` runs the shader that a `ShaderEffect` names, with three.js's default uniforms. Change the uniforms in the fields of `effect`, an `EffectSettings`.

| Effect | Builder | three.js |
|---|---|---|
| `RGB_SHIFT` | `rgb_shift_pass(amount=0.005, angle=0)` | `RGBShiftShader` |
| `BRIGHTNESS_CONTRAST` | `brightness_contrast_pass(brightness=0, contrast=0)` | `BrightnessContrastShader` |
| `HUE_SATURATION` | `hue_saturation_pass(hue=0, saturation=0)` | `HueSaturationShader` |
| `COLOR_CORRECTION` | `color_correction_pass(pow_rgb, mul_rgb, add_rgb)` | `ColorCorrectionShader` |
| `COLORIFY` | `colorify_pass(color=white)` | `ColorifyShader` |
| `BLEACH_BYPASS` | `bleach_bypass_pass(opacity=1)` | `BleachBypassShader` |
| `TECHNICOLOR` | `technicolor_pass()` | `TechnicolorShader` |
| `SOBEL` | `sobel_pass()` | `SobelOperatorShader` |
| `FREI_CHEN` | `frei_chen_pass()` | `FreiChenShader` |
| `KALEIDO` | `kaleido_pass(sides=6, angle=0)` | `KaleidoShader` |
| `MIRROR` | `mirror_pass(side=MIRROR_RIGHT)` | `MirrorShader` |
| `HORIZONTAL_TILT_SHIFT` and `VERTICAL_TILT_SHIFT` | `tilt_shift_pass(across=True, spread=1/512, focus=0.35)` | `HorizontalTiltShiftShader` and `VerticalTiltShiftShader` |
| `EXPOSURE` | `exposure_pass(exposure=1)` | `ExposureShader` |
| `GAMMA_CORRECTION` | `gamma_correction_pass()` | `GammaCorrectionShader` |

`effect_pixel` is one pixel of any of the fifteen, line for line with its fragment shader. A color transform reads the straight color of the pixel and premultiplies the result. The shift, the edge filters, the kaleidoscope, the mirror and the tilt shifts read their neighbors bilinear, clamped at the edges.

### God rays

`god_rays_pass(sun, intensity, fake_sun)` runs three.js's god-rays example after the scene. The fields of `GodRaysSettings` are the example's values, with its defaults.

1. `god_rays_mask` is `GodRaysDepthMaskShader` on the scene's depth.
2. `god_rays_generate_pixel` is `GodRaysGenerateShader`. Three passes walk the mask toward the sun, at `resolution_scale` of the frame's size. Each step is a sixth of the step before.
3. `god_rays_combine_pixel` is `GodRaysCombineShader`. It adds the rays to the frame. With `fake_sun` on, `fake_sun_color` is `GodRaysFakeSunShader`, a glow where nothing was drawn.

`sun_on_screen` projects the sun through the camera, as the example does.

### Validation of the shader effects

- `check_effect` refuses an effect or a mirror side that is not named, and a uniform that is not finite. It refuses a contrast of one or more, where the shader divides by zero. It refuses a saturation above one and sides that are not positive.
- `check_god_rays` refuses a setting that is not finite, a negative intensity and a filter length that is not positive. It refuses a resolution scale outside above zero to one.

`ShaderEffect` and `MirrorSide` are types. A bare number does not compile. `tests/compile_fail/` proves it.

## Renderer effects

`renderers/stereo_effects.mojo`, `renderers/ascii_effect.mojo` and `renderers/outline_effect.mojo`. Five of three.js's `examples/jsm/effects/`. Each wraps a renderer and draws the scene in its own way.

| Effect | three.js | Meaning |
|---|---|---|
| `StereoEffect()` | `StereoEffect` | Draw the left eye in the left half and the right eye in the right half. |
| `AnaglyphEffect()` | `AnaglyphEffect` | Mix the two eyes through two Dubois matrices, for red and cyan glasses. |
| `ParallaxBarrierEffect()` | `ParallaxBarrierEffect` | Take alternate rows from each eye. |
| `AsciiEffect(characters, resolution=0.15, color, alpha, block, invert)` | `AsciiEffect` | Draw the scene as characters. |
| `OutlineEffect(thickness=0.003, color=black, alpha=1)` | `OutlineEffect` | Draw an ink outline around every mesh. |

```mojo
var effect = OutlineEffect()
var image = effect.render(renderer, scene, assets, camera)
var ascii = AsciiEffect().render(renderer, scene, assets, camera)
print(ascii.text())
```

### Stereo

Each stereo effect makes its two eyes from the camera with a `StereoCamera`. `StereoEffect` draws through an `ArrayCamera`, each eye at half the aspect. `set_eye_separation` changes the distance between the eyes. `AnaglyphEffect` draws each eye into its own target, and `anaglyph_pixel` mixes them. `color_matrix_left` and `color_matrix_right` are the two matrices. `ParallaxBarrierEffect` reads the left eye where `barrier_row_is_left`.

### ASCII

`AsciiEffect.render` draws the scene and calls `asciify`. `asciify` shrinks the image by `resolution`. Each pixel of every other row of the small image becomes one character. `ascii_brightness` is three.js's brightness, and `ascii_index` picks the character. A dark pixel takes a character near the end of the set.

`AsciiImage.text` returns the characters as lines of plain text. `AsciiImage.html` returns the markup that three.js writes into its table cell. With `color` on, each character is a `span` in its color. `block` fills its background, and `alpha` gives it its opacity. An empty character set is three.js's fallback set.

### Outline

`OutlineEffect.render` draws the scene with each mesh outlined. The outline material is three.js's GLSL, compiled by `compile_shader_material`. It draws the back faces, each vertex moved out along its normal in clip space, in one flat color. The rim is then the same width at every distance.

`set_parameters(material, parameters)` gives the meshes of one material their own `OutlineParameters`: `thickness`, `color`, `alpha` and `visible`. This is three.js's `userData.outlineParameters`. `enabled` off draws the scene alone.

The outline meshes, their materials and their programs are added to the scene and the assets. They are taken out again when `render` returns or raises.

### Validation of the renderer effects

- `StereoEffect.render` refuses a renderer narrower than two pixels. `set_eye_separation` refuses a negative separation and keeps the old one.
- `AsciiEffect` refuses a resolution that is not finite, or not above zero and at most one. `asciify` refuses an image that shrinks to nothing.
- `check_outline_parameters` refuses a thickness or an alpha that is not finite, a negative thickness, and an alpha outside zero to one. `set_parameters` refuses a negative material id.

### How the renderer effects differ from three.js

- **The ASCII shrink.** A browser shrinks the canvas by a filter that it picks. This port averages the pixels whose centers fall in each small pixel, weighed by their alpha.
- **The ASCII output.** three.js writes an HTML table into the page. This port returns an `AsciiImage` with its text and its markup.
- **The outline draw.** three.js draws the scene and then the outlines over it. This port draws the scene once with the outline meshes added. The depth test gives the same image for opaque surfaces.
- **What is outlined.** Only the meshes in `Scene.meshes` whose geometry has normals. Instanced, batched and skinned meshes, lines, points and sprites are not outlined.
- **The outline shader.** This port's GLSL knows the built-in matrices only as the steps to `gl_Position`. So the shader reads the model-view-projection matrix and its inverse from two uniforms, set for each mesh.
- **The stereo pair's odd width.** For an odd width, three.js's right viewport is one pixel off the image. This port's is not.

## Not ported

The passes run on the host. `GpuComposer` runs the same composer with the frame on the GPU. See [GPU backend](GPU-backend#post-processing-on-the-gpu).

The SSAA and TAA passes use the renderer's background as their clear color. three.js's passes have their own `clearColor` and `clearAlpha`, and these are not ported. An SSAA or TAA pass moves the camera's projection by the jitter, after the camera's own view offset. three.js adds the jitter to the view offset instead. The two agree when the view's `width` and `height` are the frame's size.
