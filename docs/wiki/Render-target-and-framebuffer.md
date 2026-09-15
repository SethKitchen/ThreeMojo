# Render target and framebuffer

`render/target.mojo` and `render/framebuffer.mojo`. A `RenderTarget` is the workspace: premultiplied linear RGBA and depth, at float precision. A `Framebuffer` is the result: bytes and depth. `resolve` turns the first into the second once.

three.js: `WebGLRenderTarget` and the canvas. A render target cannot be used as a texture yet.

## Color and FloatColor

`Color(r, g, b, a=255)` is four bytes, as authored in sRGB.

`FloatColor(r, g, b, a)` is four floats in linear light.

| Constructor or method | Meaning |
|---|---|
| `FloatColor(srgb=color)` | Decode an sRGB colour to linear. Alpha is not decoded. |
| `FloatColor(of=color)` | Divide each byte by 255 without decoding. |
| `encode() -> Color` | Encode linear light to sRGB bytes, clamped. |
| `quantize() -> Color` | Bytes without the transfer function, for data. |
| `premultiplied()`, `unpremultiplied()` | Convert between straight and premultiplied alpha. |
| `scaled(factor)` | Multiply every channel. |

## RenderTarget

| Member | Meaning |
|---|---|
| `RenderTarget(width, height, clear)` | A target cleared to a colour. |
| `write(x, y, color)` | Replace a pixel. |
| `blend(x, y, color)` | Source-over in premultiplied linear light. |
| `test_depth(x, y, z) -> Bool` | Keep and record `z` when it is nearer. |
| `depth_passes(x, y, z) -> Bool` | Compare without recording. |
| `depth_at(x, y)`, `color_at(x, y)` | Read a pixel. |
| `shown(x, y) -> Color` | One pixel as it will resolve. |
| `resolve(workers=1) -> Framebuffer` | Unpremultiply and encode every pixel. |

Nothing is clamped before `resolve`. Overexposed light survives every step.

## Framebuffer

| Member | Meaning |
|---|---|
| `Framebuffer(width, height, clear)` | An image cleared to a colour, with infinite depth. |
| `get_pixel(x, y) -> Color`, `set_pixel(x, y, color)` | Read and write a pixel. |
| `depth_at(x, y) -> Float32` | The depth, or infinity where nothing was drawn. |
| `test_depth(x, y, z) -> Bool` | The depth test, for the flat rasterizer. |
| `CHANNELS` | Four. |

The pixel layout is row-major RGBA from the top, the same as a `Texture`. An image this renderer produces can be fed back in as a texture.

Every accessor raises for a coordinate outside the image.

## Why

See [Why colour is linear](Why-colour-is-linear).
