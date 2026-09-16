# Render target and framebuffer

`render/target.mojo` and `render/framebuffer.mojo`. A `RenderTarget` is the workspace: premultiplied linear RGBA and depth, at float precision. A `Framebuffer` is the result: bytes and depth. `resolve` turns the first into the second once.

three.js: `WebGLRenderTarget` and the canvas. A render target cannot be used as a texture yet.

## Color and FloatColor

`Color(r, g, b, a=255)` is four bytes, as authored in sRGB. `Color(hex=0xFF8000)` builds one from a 24-bit value, and `hex()` gives it back. A value outside 24 bits raises.

`FloatColor(r, g, b, a)` is four floats in linear light. It is also three.js's `Color`, with an alpha added. Each setter and getter keeps its three.js default color space. Hex is sRGB, decoded on the way in and encoded on the way out. HSL is the linear working space, unless you pass `space=SRGB`.

| Constructor or method | Meaning |
|---|---|
| `FloatColor(srgb=color)` | Decode an sRGB color to linear. Alpha is not decoded. |
| `FloatColor(of=color)` | Divide each byte by 255 without decoding. |
| `FloatColor(hex=0xFF8000)` | Decode a 24-bit sRGB value. three.js's `setHex`. |
| `FloatColor(hue=h, saturation=s, lightness=l, space=LINEAR)` | A color from HSL in the linear working space. three.js's `setHSL`. Pass `space=SRGB` to describe an sRGB color, decoded. The hue wraps. The other two clamp. |
| `encode() -> Color` | Encode linear light to sRGB bytes, clamped. |
| `hex() -> Int` | The encoded color as a 24-bit value. three.js's `getHex`. |
| `hsl(space=LINEAR) -> HSL` | Hue, saturation and lightness of the linear channels. three.js's `getHSL`. Pass `space=SRGB` for those of the encoded color. |
| `quantize() -> Color` | Bytes without the transfer function, for data. |
| `premultiplied()`, `unpremultiplied()` | Convert between straight and premultiplied alpha. |
| `scaled(factor)` | Multiply every channel. |
| `lerp(other, alpha)` | Move toward `other`, every channel. three.js's `lerp`. |
| `lerp_hsl(other, alpha)` | Move toward `other` in linear HSL. The hue goes the long way, as in three.js. |
| `offset_hsl(h, s, l)` | Add to the linear hue, saturation and lightness. three.js's `offsetHSL`. |
| `multiply(other)`, `add(other)` | Red, green and blue only. Alpha is kept. |
| `a == b` | Every channel equal. three.js's `equals`. |

`HSL(hue, saturation, lightness)` holds the three floats `hsl()` returns. A gray has a hue and a saturation of zero. A half-lightness gray is linear 0.5, which encodes to 188. In sRGB it is the gray that `0x808080` decodes to. CSS color names and strings are not ported.

## RenderTarget

| Member | Meaning |
|---|---|
| `RenderTarget(width, height, clear)` | A target cleared to a color. |
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
| `Framebuffer(width, height, clear)` | An image cleared to a color, with infinite depth. |
| `get_pixel(x, y) -> Color`, `set_pixel(x, y, color)` | Read and write a pixel. |
| `depth_at(x, y) -> Float32` | The depth, or infinity where nothing was drawn. |
| `test_depth(x, y, z) -> Bool` | The depth test, for the flat rasterizer. |
| `CHANNELS` | Four. |

The pixel layout is row-major RGBA from the top, the same as a `Texture`. An image this renderer produces can be fed back in as a texture.

Every accessor raises for a coordinate outside the image.

## Why

See [Why color is linear](Why-color-is-linear).
