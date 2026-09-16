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
| `lit` | Whether the lights reach this surface. |
| `emissive` | Light the surface gives off, linear. |
| `emissive_map` | The `TextureId` that multiplies `emissive`, or `NO_TEXTURE`. |

`texture`, `blend`, `lit` and `emissive_map` are per-triangle state. All three corners must agree, and the value must be a named one. `check_triangle_state` refuses anything else.

## Functions

| Function | Meaning |
|---|---|
| `rasterize(triangle, framebuffer, color)` | Fill a flat triangle. |
| `rasterize_depth(...)` | Fill with a depth test. |
| `rasterize_shaded(a, b, c, target, mode, textures, lighting, first_row, last_row)` | Fill one shaded triangle. |
| `rasterize_all(corners, target, mode, textures, lighting, workers)` | Fill a whole list, on one or more threads. |
| `check_triangle_state(a, b, c)` | Refuse corners that disagree, or hold a value neither backend knows. |
| `mip_level(du, dv, width, height)` | The mip level for a texture footprint. |

## Coverage

Vertices snap to a 1/16 pixel grid. The edge function is then exact integer arithmetic. The top-left rule gives a pixel on a shared edge to exactly one triangle. See [Why coverage uses fixed point](Why-coverage-uses-fixed-point).

## Depth

Depth is interpolated linearly in screen space. A fragment is kept when it is nearer than what is there. An opaque fragment writes its depth. A blended fragment tests depth and does not write it.

## Clipping

`clip_depth(a, b, c, near, far)` cuts a triangle against the near and far planes in camera space. It returns zero, one or two triangles. Every varying is interpolated to the cut, including the world position.

## Culling

The material's `side` decides which faces are drawn. `FRONT_SIDE` culls faces that point away from the camera. A mesh with a negative world determinant has its winding reversed, and the culler reads the determinant.

## Interpolation

Color, normal, texture coordinates and world position are interpolated with perspective correction. Each corner's value is weighted by `inv_w`, and the sum is divided by the interpolated `inv_w`. See [Why interpolation is perspective-correct](Why-interpolation-is-perspective-correct).

## Shading

At each fragment the interpolated normal is normalized again, and `Lighting.intensity_at` sums every light. The material color, the sampled texel and the light multiply. The emissive term, times its own map, is then added. The lights do not touch it. An unlit triangle skips the lights. See [Why shading is per fragment](Why-shading-is-per-fragment).

## Transparency

`rasterize_shaded` blends a `BLEND` fragment over what is there, in premultiplied linear light. The caller owns the draw order. `Renderer.prepare` sorts.

## Errors

- A mode that is none of the three raises.
- Corners that disagree about blend, texture, lit or emissive map raise.
- An emissive map that reads its alpha as coverage raises under `SHADE_TEXTURE`, on both backends.
- A blend value that is neither `OPAQUE` nor `BLEND` raises, on every worker count, whether or not the triangle is visible.
- A texture the store lacks raises when a fragment samples it.
