# Post-processing

`postprocessing/composer.mojo`. An `EffectComposer` runs passes over the light a frame leaves in a render target and resolves it once at the end. three.js: `EffectComposer` and the passes under `examples/jsm/postprocessing/`.

```mojo
var composer = EffectComposer()
composer.add_pass(render_pass())
composer.add_pass(bloom_pass(1.5, 0.4, 0.85))
composer.add_pass(output_pass())
var image = composer.render(renderer, scene, assets, camera)
```

The frame starts cleared to the renderer's background. A render pass draws the scene into it. Every other pass reads the light and writes it back. The frame is resolved through no curve of its own. An `output_pass` is where the renderer's tone mapping curve is applied, as three.js applies it in an `OutputPass` once a composer is in use.

## The passes

| Builder | three.js | Meaning |
|---|---|---|
| `render_pass()` | `RenderPass` | Draw the scene, clearing first. Through the renderer's antialias when that is on. |
| `copy_pass(opacity=1)` | `ShaderPass(CopyShader)` | Scale every channel of every pixel, alpha included. |
| `blur_pass(spread=1)` | `HorizontalBlurShader` then `VerticalBlurShader` | Nine taps across, then nine down, `spread` pixels apart. |
| `bloom_pass(strength=1, radius=0, threshold=0)` | `UnrealBloomPass` | The light above `threshold` blurred at five halved sizes, weighted by `radius`, scaled by `strength` and added back. |
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

Each builder returns a `Pass`. A `Pass` has a `kind`, an `enabled` flag and every setting any kind reads. The effect passes read `strength`, `radius`, `threshold`, `offset`, `scale`, `angle`, `center`, `grayscale` and `time`. The SSAA and TAA passes read `sample_level`, `unbiased`, `accumulate` and `accumulate_index`. Change a setting after the pass is added, as three.js changes a uniform. A pass that is not enabled is skipped.

The defaults are three.js's. The dot screen's angle is an `Angle`. A bare number does not compile. `tests/compile_fail/` proves it.

## The composer

| Member | three.js | Meaning |
|---|---|---|
| `add_pass(pass)` | `addPass` | Append a pass. |
| `insert_pass(pass, index)` | `insertPass` | Put a pass before the one at `index`. |
| `remove_pass(index)` | `removePass` | Take a pass out. |
| `pass_count() -> Int` | | How many passes there are. |
| `reset()` | `reset` | Forget what every afterimage pass saw and what every TAA pass accumulated. |
| `render(renderer, scene, assets, camera, delta_time=0) -> Framebuffer` | `render` | Run every enabled pass in order and return the image. |

`delta_time` is how many seconds passed since the last frame. It advances each film pass's grain. Zero holds the grain still.

## Validation

`PassKind` is a type. `is_valid` names the fifteen kinds. `check_pass` refuses any other kind. It refuses a setting that is not finite. It refuses a strength, radius, threshold, offset or scale that is negative. It refuses a bloom radius above one and an afterimage damp above one.

`check_pass` also refuses a sample level outside zero through five. three.js clamps the level; this port refuses it. It refuses an accumulate index outside minus one through 32. `jitter_offsets` refuses a level outside zero through five. `JitteredCamera` refuses an offset that is not finite and an image size that is not positive.

`add_pass` and `insert_pass` call `check_pass`. `render` calls it again on every pass, so a setting changed after the pass was added is checked too. `render` also refuses a frame time that is negative or not finite.

## What each pass works on

A blur, a bloom, a copy and an afterimage work on the premultiplied light, where a sum is a sum. A color transform works on the straight color of each pixel and premultiplies it back, as a shader sees a straight texel. The sepia, the gray, the dot screen, the vignette, the grain and the curve are color transforms. Every pass keeps alpha but the copy, which scales it as three.js's `CopyShader` scales the whole texel.

A tap past the edge of the frame reads the edge pixel, as a clamped texture does. A pixel that holds data rather than light, a normal or a depth, is not tone mapped by the output pass. The other passes treat it as light.

The bloom's five levels are halved as three.js halves them, rounded up, never below one pixel. Its blur kernels are three, five, seven, nine and eleven taps to each side, each with a sigma of its own width. The dot screen measures its pattern over a fixed 256 by 256 grid, as three.js's pass sets `tSize` once.

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

## Not ported

The passes run on the host. The GPU backend draws bytes rather than light and has no target a pass could read. `MaskPass`, `ClearPass`, `GlitchPass`, `SSAOPass`, `BokehPass` and the other passes are not ported.

The SSAA and TAA passes use the renderer's background as their clear color. three.js's passes have their own `clearColor` and `clearAlpha`, and these are not ported. An SSAA pass jitters the camera with no view offset of its own, because the cameras here have none.
