# Rasterization

`render/rasterizer.mojo`, `render/fillrule.mojo` and `renderers/clip.mojo`. The rasterizer fills screen-space triangles into a `RenderTarget`. It decides coverage in fixed point, tests depth, interpolates with perspective correction, and shades every fragment.

three.js has no software rasterizer. This is the part of the port that replaces the GPU pipeline.

## RasterVertex

One corner as the rasterizer wants it:

| Field | Meaning |
|---|---|
| `x`, `y` | Pixel coordinates. |
| `z` | Depth in normalized device space. |
| `inv_w` | One over the clip-space `w`. |
| `color` | The material color, linear, with opacity in alpha. |
| `normal` | The world-space normal. |
| `u`, `v` | Texture coordinates. |
| `world` | The world-space position, for point lights. |
| `texture` | A `TextureId`, or `NO_TEXTURE`. |
| `blend` | `OPAQUE` or `BLEND`. |
| `kind` | The material kind: `LAMBERT`, `PHONG`, `BASIC`, `NORMALS` or `DEPTH`. |
| `specular` | How much a `PHONG` surface sends to the camera, linear. |
| `shininess` | How tight its highlight is. |
| `alpha_map` | The `TextureId` whose green channel thins the surface, or `NO_TEXTURE`. |
| `alpha_test` | The alpha a fragment must reach to be drawn. |
| `emissive` | Light the surface gives off, linear. |
| `emissive_map` | The `TextureId` that multiplies `emissive`, or `NO_TEXTURE`. |
| `view_depth` | The camera-space depth in meters, for the fog. See [Fog](Fog#depth). |

`texture`, `blend`, `kind`, `emissive_map`, `alpha_map`, `alpha_test` and `shininess` are per-triangle state. All three corners must agree, and the value must be a named one. `check_triangle_state` refuses anything else.

A `NORMALS` corner carries its normal in view space, not world space. The normal is shown rather than lit.

## Functions

| Function | Meaning |
|---|---|
| `rasterize(triangle, framebuffer, color)` | Fill a flat triangle. |
| `rasterize_depth(...)` | Fill with a depth test. |
| `rasterize_shaded(a, b, c, target, mode, textures, lighting, first_row, last_row, fog)` | Fill one shaded triangle. |
| `rasterize_all(corners, target, mode, textures, lighting, workers, fog)` | Fill a whole list, on one or more threads. |
| `check_triangle_state(a, b, c)` | Refuse corners that disagree, or hold a value neither backend knows. |
| `mip_level(du, dv, width, height)` | The mip level for a texture footprint. |
| `data_color(r, g, b, a)` | Three channels of data as the light that resolves to their bytes. |
| `packed_normal(normal)` | A unit normal mapped into zero to one per axis. |
| `packed_depth(z)` | An NDC depth as the gray a `DEPTH` material shows. |
| `check_alpha_map(texture)` | Refuse an alpha map that is not stored as data. |
| `check_gradient_map(texture)` | Refuse a toon ramp that is not stored as data. |
| `gradient_ramp(texture)` | A gradient map's top row as tones, left to right. |
| `matcap_uv(toward_eye, up, normal)` | Where a `MATCAP` surface is looked up in its image. |
| `matcap_fallback(v)` | three.js's gray gradient, for a matcap surface with no image. |
| `interpolate_alpha(a, b, c, share_b, share_c)` | An alpha across a triangle, in difference form. |

## Coverage

Vertices snap to a 1/16 pixel grid. The edge function is then exact integer arithmetic. The top-left rule gives a pixel on a shared edge to exactly one triangle. See [Why coverage uses fixed point](Why-coverage-uses-fixed-point).

## Depth

Depth is interpolated linearly in screen space. A fragment is kept when it is nearer than what is there. An opaque fragment writes its depth. A blended fragment tests depth and does not write it.

An alpha-tested fragment writes its depth *late*. It tests without claiming, and claims with `claim_depth` once it survives the test. A fragment the test throws away leaves the depth alone, so the hole shows what is behind it. A GPU does the same for a shader that can discard.

## Clipping

`clip_depth(a, b, c, near, far)` cuts a triangle against the near and far planes in camera space. It returns zero, one or two triangles. Every varying is interpolated to the cut, including the world position.

## Culling

The material's `side` decides which faces are drawn. `FRONT_SIDE` culls faces that point away from the camera. A mesh with a negative world determinant has its winding reversed, and the culler reads the determinant.

## Interpolation

Color, normal, texture coordinates and world position are interpolated with perspective correction. Each corner's value is weighted by `inv_w`, and the sum is divided by the interpolated `inv_w`. See [Why interpolation is perspective-correct](Why-interpolation-is-perspective-correct).

## Shading

At each fragment the interpolated normal is normalized again, and `Lighting.intensity_at` sums every light. The material color, the sampled texel and the light multiply. A `PHONG` triangle then adds its highlight, which `Lighting.specular_at` sums. The texture does not tint it. The emissive term, times its own map, is added next, and the lights do not touch it.

A `BASIC` triangle skips all of this. See [Why shading is per fragment](Why-shading-is-per-fragment).

## Data

A `NORMALS` or `DEPTH` triangle writes data rather than light. The fragment discards what the color and the texture said about red, green and blue. It keeps what they said about alpha, so a map cuts a depth out.

`data_color` quantizes the three channels to bytes without the sRGB curve, then decodes those bytes back into the linear buffer. `resolve` encodes them and gives the same bytes. The target records that the pixel holds data, and keeps the tone mapping off it. The `SHADE_UV` debug view writes its coordinates the same way. See [Why a normal is not a color](Why-a-normal-is-not-a-color).

Neither the emissive term nor the fog reaches such a fragment.

## Fog

After the lights and the emissive term, the fragment is mixed toward the fog color by its camera-space depth. The `fog` argument is a `FogView`. The default, `FogView.none()`, changes nothing. `SHADE_UV` is never fogged, and nor is a `NORMALS` or `DEPTH` triangle. See [Fog](Fog).

## Alpha

The alpha map's green channel multiplies the fragment's alpha, three.js's `alphamap_fragment`. The map must be `LINEAR` and `IGNORED`: its green is a coverage, not a color. `check_alpha_map` refuses anything else, on both backends, before the first fragment.

A fragment whose alpha then falls below `alpha_test` is thrown away, three.js's `alphatest_fragment`. The comparison is strict. A test of zero throws nothing away. `SHADE_LIT` ignores the map and keeps the test. `SHADE_UV` ignores both.

`interpolate_alpha` reaches that comparison. The three barycentric weights are rounded floats, so they sum to one only up to rounding. `a * sa + b * sb + c * sc` for three alphas of one can give 0.99999994. A test of one then throws away a surface that is opaque everywhere.

The difference form, `a + sb * (b - a) + sc * (c - a)`, returns a constant exactly. Alpha alone uses it: alpha reaches a strict threshold, and red, green and blue reach a quantization that a last bit cannot move. Both backends call this one function.

## Toon shading

A `TOON` triangle reads its light from `Lighting.toon_at` rather than from `intensity_at`. Its ramp is read once per triangle by `gradient_ramp`, not once per fragment. The top row is the whole lookup table, and it is the same for every pixel. An empty ramp means the triangle named none, and three.js's fallback applies.

Both backends read the same bytes. The host reads texel (x, 0) of the gradient map. The kernel reads the same byte of the same row out of its texel buffer. So a ramp of three tones cannot step at one coordinate on one side and another on the other. See [Materials](Materials#toon).

## Matcap shading

A `MATCAP` triangle is unlit. Its light comes from an image, looked up by which way the surface is turned in the camera's frame. That light multiplies the surface color exactly as arriving light does. `matcap_uv` builds that frame and both backends call it.

The direction toward the camera is measured from where the camera stands, under either projection. The image is read at its full-size level and never down a mip chain. See [Materials](Materials#matcap).

## Threads

`rasterize_all` splits the image into horizontal bands and runs one task per band. A band owns its rows outright, so no two threads touch the same pixel and the depth test needs no atomics.

The tasks come from `TaskGroup`. Mojo 1.1 moved that behind an underscore. `std.runtime` keeps only `parallelism_level` and `initialize_runtime` in public view, and nothing public in `std` runs work on a thread pool. So `from std.runtime._asyncrt import TaskGroup` is the one place this project reaches past a leading underscore, and it is what pins the toolchain to an exact version. Mojo 1.0 has no `_asyncrt` and 1.1 has no `asyncrt`, so one source cannot serve both.

## Transparency

`rasterize_shaded` blends a `BLEND` fragment over what is there, in premultiplied linear light. The caller owns the draw order. `Renderer.prepare` sorts.

A `NORMALS` or `DEPTH` triangle cannot blend. One pixel holds its own bytes or the scene's light, and a mixture of the two is neither. `check_triangle_state` refuses the pair, on both backends and on every worker count. So `RenderTarget.blend` can say a mixture is always light. See [Materials](Materials#what-they-refuse).

## Errors

- A mode that is none of the three raises.
- Corners that disagree about blend, texture, kind, emissive map, gradient map, matcap or shininess raise.
- A negative or non-finite shininess raises, on every worker count.
- A material kind that is none of the seven raises, on every worker count.
- An emissive map that reads its alpha as coverage raises under `SHADE_TEXTURE`, on both backends.
- A blend value that is neither `OPAQUE` nor `BLEND` raises, on every worker count, whether or not the triangle is visible.
- A `NORMALS` or `DEPTH` triangle whose blend is `BLEND` raises, on every worker count.
- A texture the store lacks raises when a fragment samples it.
- An alpha map that `SHADE_TEXTURE` would open raises unless it is `LINEAR` and `IGNORED`.
- A gradient map raises unless it is `LINEAR`, `IGNORED` and holds texels. Asked under every mode that lights the surface, because `SHADE_LIT` reads one too.
- A gradient map on a kind that is not `TOON` raises, and so do corners that disagree about one.
- A matcap raises unless it is `IGNORED`. A matcap on a kind that is not `MATCAP` raises, and so do corners that disagree about one.
- An alpha test outside zero to one, or not finite, raises on every worker count.
- A fog view that `FogView.validate` refuses raises before any fragment is drawn, on every worker count.
