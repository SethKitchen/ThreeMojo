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

Each builder returns a `Pass`. A `Pass` has a `kind`, an `enabled` flag and every setting any kind reads: `strength`, `radius`, `threshold`, `offset`, `scale`, `angle`, `center`, `grayscale` and `time`. Change a setting after the pass is added, as three.js changes a uniform. A pass that is not enabled is skipped.

The defaults are three.js's. The dot screen's angle is an `Angle`. A bare number does not compile. `tests/compile_fail/` proves it.

## The composer

| Member | three.js | Meaning |
|---|---|---|
| `add_pass(pass)` | `addPass` | Append a pass. |
| `insert_pass(pass, index)` | `insertPass` | Put a pass before the one at `index`. |
| `remove_pass(index)` | `removePass` | Take a pass out. |
| `pass_count() -> Int` | | How many passes there are. |
| `reset()` | `reset` | Forget what every afterimage pass saw. |
| `render(renderer, scene, assets, camera, delta_time=0) -> Framebuffer` | `render` | Run every enabled pass in order and return the image. |

`delta_time` is how many seconds passed since the last frame. It advances each film pass's grain. Zero holds the grain still.

## Validation

`PassKind` is a type. `is_valid` names the eleven kinds. `check_pass` refuses any other kind. It refuses a setting that is not finite. It refuses a strength, radius, threshold, offset or scale that is negative. It refuses a bloom radius above one and an afterimage damp above one.

`add_pass` and `insert_pass` call `check_pass`. `render` calls it again on every pass, so a setting changed after the pass was added is checked too. `render` also refuses a frame time that is negative or not finite.

## What each pass works on

A blur, a bloom, a copy and an afterimage work on the premultiplied light, where a sum is a sum. A color transform works on the straight color of each pixel and premultiplies it back, as a shader sees a straight texel. The sepia, the gray, the dot screen, the vignette, the grain and the curve are color transforms. Every pass keeps alpha but the copy, which scales it as three.js's `CopyShader` scales the whole texel.

A tap past the edge of the frame reads the edge pixel, as a clamped texture does. A pixel that holds data rather than light, a normal or a depth, is not tone mapped by the output pass. The other passes treat it as light.

The bloom's five levels are halved as three.js halves them, rounded up, never below one pixel. Its blur kernels are three, five, seven, nine and eleven taps to each side, each with a sigma of its own width. The dot screen measures its pattern over a fixed 256 by 256 grid, as three.js's pass sets `tSize` once.

## Not ported

The passes run on the host. The GPU backend draws bytes rather than light and has no target a pass could read. `MaskPass`, `ClearPass`, `GlitchPass`, `SMAAPass`, `SSAOPass`, `BokehPass` and the other passes are not ported.
