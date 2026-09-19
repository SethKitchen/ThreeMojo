# Render target and framebuffer

`render/target.mojo`, `render/framebuffer.mojo` and `render/tonemap.mojo`. A `RenderTarget` is the workspace: premultiplied linear RGBA and depth, at float precision. A `Framebuffer` is the result: bytes and depth. `resolve` turns the first into the second once, through a tone mapping curve when one is asked for.

![ACES tone mapping holds a bright sphere as exposure rises](out/exposure.png)

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
| `write(x, y, color, data=False)` | Replace a pixel. |
| `blend(x, y, color)` | Source-over in premultiplied linear light. |
| `is_data(x, y) -> Bool` | Whether the pixel holds data rather than light. |
| `test_depth(x, y, z) -> Bool` | Keep and record `z` when it is nearer. |
| `depth_passes(x, y, z) -> Bool` | Compare without recording. |
| `claim_depth(x, y, z)` | Record without comparing, for a late depth write. |
| `set_scissor(rect)` | Draw only inside `rect` from now on. Every test and write outside it does nothing. |
| `clear_inside(rect, clear)` | Reset the pixels inside `rect` and leave the rest. |
| `depth_at(x, y)`, `color_at(x, y)` | Read a pixel. |
| `shown(x, y, tone_mapping=NO_TONE_MAPPING, exposure=1.0) -> Color` | One pixel as it will resolve. |
| `resolve(workers=1, tone_mapping=NO_TONE_MAPPING, exposure=1.0) -> Framebuffer` | Unpremultiply, tone map and encode every pixel. |

Nothing is clamped before `resolve`. Overexposed light survives every step.

`set_scissor` is three.js's scissor with the test on. A fragment outside it is neither depth tested nor written, as a GPU discards it before the depth test. `clear_inside` is what a clear under that scissor does. The two are what let several viewports share one target; see [Renderer](Renderer#viewport-and-scissor). The rectangle's corner counts up from the bottom left, as three.js's does.

`claim_depth` is the other half of a late depth write. A fragment an alpha test can throw away tests with `depth_passes` and claims only once it survives. See [Rasterization](Rasterization#depth).

Pass `data=True` to `write` when the color is not light. A normal material, a depth material and the `SHADE_UV` view all do. `resolve` encodes such a pixel without tone mapping it. See [Why a normal is not a color](Why-a-normal-is-not-a-color).

A write replaces the pixel, so the pixel takes the fragment's answer about what it holds. A blend mixes into what is there, and a mixture with light in it is light. Only light blends, because the rasterizers refuse a blended data triangle. So `blend` takes no flag and always leaves the pixel holding light.

A blend whose effective alpha is zero changes nothing at all. Source-over hides nothing and adds nothing there, so it adds no color, no depth and no answer about what the pixel holds. It used to take the data flag before it read the alpha. An invisible fragment could then put the tone mapping curve back onto a normal's bytes. The rule applies to `blend` alone. A `write` at alpha zero still replaces the pixel.

## Tone mapping

`resolve` can compress the light into what a display can show instead of clamping it. Pass one of the seven curves and an exposure. The curve is applied to each pixel's straight color, after the unpremultiply and before the sRGB encode. Alpha is left alone.

three.js: `WebGLRenderer.toneMapping` and `toneMappingExposure`.

| Curve | Meaning |
|---|---|
| `NO_TONE_MAPPING` | Clamp and nothing else. The exposure is not applied. The default. |
| `LINEAR_TONE_MAPPING` | Scale by the exposure and clamp. |
| `REINHARD_TONE_MAPPING` | `c / (1 + c)`. Nothing reaches white. |
| `CINEON_TONE_MAPPING` | The Hejl and Burgess-Dawson filmic curve. |
| `ACES_FILMIC_TONE_MAPPING` | Hill's fit of the ACES transform, brightened as three.js brightens it. |
| `AGX_TONE_MAPPING` | Blender's AgX through rec. 2020, as Filament and three.js carry it. |
| `NEUTRAL_TONE_MAPPING` | The Khronos PBR neutral curve. |

`tone_map(color, mode, exposure)` is the function itself. The GPU kernel calls the same one. `ToneMapping` is a type. `is_valid` names the seven. A bare integer does not compile.

`check_tone_mapping(mode, exposure)` refuses any other value, and an exposure that is negative or not finite. `resolve`, `shown`, `Renderer.set_tone_mapping` and `GpuRenderer.draw` all call it.

The curve is applied once, to the composited light of each pixel. three.js applies it to each fragment before blending. On an opaque pixel that no fog reaches, the two orders agree up to rounding. A fogged pixel differs: the fog is mixed in linear light before the curve here, and after the encode in three.js. A translucent pixel differs by design. A pixel that holds data is not tone mapped at all.

Bit-for-bit equality with another implementation is not promised, because `exp2` of `log2` rounds differently from a `pow`. The background is light in the target and goes through the curve too. The `SHADE_UV` view is never tone mapped. See [Renderer](Renderer#tone-mapping).

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
