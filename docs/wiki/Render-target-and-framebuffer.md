# Render target and framebuffer

`render/target.mojo`, `render/framebuffer.mojo` and `render/tonemap.mojo`. A `RenderTarget` is the workspace: premultiplied linear RGBA and depth, at float precision. A `Framebuffer` is the result: bytes and depth. `resolve` turns the first into the second once, through a tone mapping curve when one is asked for.

![ACES tone mapping holds a bright sphere as exposure rises](out/exposure.png)

three.js: `WebGLRenderTarget` and the canvas. A render target can be read back as a texture; see [Textures](Textures#from-a-render). A target can keep light above one; see [Float render targets](#float-render-targets). A target can also keep a normal beside the light in the same pass; see [Multiple render targets](#multiple-render-targets).

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
| `RenderTarget(width, height, clear, type=UNSIGNED_BYTE_TARGET, outputs=color_only())` | A target cleared to a color. See [Float render targets](#float-render-targets) and [Multiple render targets](#multiple-render-targets). |
| `write(x, y, color, data=False, normal=Vector3(0, 0, 0))` | Replace a pixel. The normal attachment keeps `normal`. |
| `blend(x, y, color)` | Source-over in premultiplied linear light. |
| `is_data(x, y) -> Bool` | Whether the pixel holds data rather than light. |
| `test_depth(x, y, z) -> Bool` | Keep and record `z` when it is nearer. |
| `depth_passes(x, y, z) -> Bool` | Compare without recording. |
| `claim_depth(x, y, z)` | Record without comparing, for a late depth write. |
| `set_scissor(rect)` | Draw only inside `rect` from now on. Every test and write outside it does nothing. |
| `clear_inside(rect, clear)` | Reset the pixels inside `rect`, stencil included, and leave the rest. |
| `test_fragment(x, y, z, state) -> FragmentTest` | Run the stencil and the depth tests without writing. |
| `keep_stencil(x, y, test)` | Write the stencil value a test returned. |
| `depth_at(x, y)`, `color_at(x, y)`, `stencil_at(x, y)` | Read a pixel. |
| `shown(x, y, tone_mapping=NO_TONE_MAPPING, exposure=1.0) -> Color` | One pixel as it will resolve. |
| `resolve(workers=1, tone_mapping=NO_TONE_MAPPING, exposure=1.0) -> Framebuffer` | Unpremultiply, tone map and encode every pixel. |
| `texture(wrap=CLAMP, filter=BILINEAR, mipmapped=True, alpha=COVERAGE, workers=1, tone_mapping=NO_TONE_MAPPING, exposure=1.0) -> Texture` | `resolve`, then the image as a texture a later draw can sample. three.js's `WebGLRenderTarget.texture`. |
| `depth_texture(wrap=CLAMP, type=UNSIGNED_BYTE_TARGET) -> Texture` | The depth as it stands, as a gray texture. three.js's `DepthTexture`. Pass `type=FLOAT_TARGET` for the depth itself. |
| `count() -> Int` | How many color attachments the target has. three.js's `count`. |
| `attachment(index) -> FloatImage` | One color attachment, as the target's type stores it. |
| `attachment_texture(index, wrap=CLAMP, filter=BILINEAR, mipmapped=False) -> Texture` | One color attachment as a float texture. three.js's `textures[index]`. |
| `has_normals() -> Bool`, `normal_at(x, y) -> Vector3` | Whether the target has a normal attachment, and the normal at a pixel. |

Nothing is clamped before `resolve`. Overexposed light survives every step.

`set_scissor` is three.js's scissor with the test on. A fragment outside it is neither depth tested nor written, as a GPU discards it before the depth test. `clear_inside` is what a clear under that scissor does. The two are what let several viewports share one target; see [Renderer](Renderer#viewport-and-scissor). The rectangle's corner counts up from the bottom left, as three.js's does.

The target holds an eight-bit stencil buffer beside the depth. It starts at zero, and `clear_inside` clears it to zero with the frame, as three.js clears it. Only a primitive whose state has `stencil_write` on reads it or writes it. `test_fragment` runs the stencil and the depth tests in OpenGL's order and writes nothing. The rasterizer writes the stencil, the depth and the color once the fragment survives its alpha test.

The kernel keeps the stencil as one local number per pixel, because one launch draws the whole frame. See [Materials](Materials#depth-color-and-stencil).

`claim_depth` is the other half of a late depth write. A fragment an alpha test can throw away tests with `depth_passes` and claims only once it survives. See [Rasterization](Rasterization#depth).

Pass `data=True` to `write` when the color is not light. A normal material, a depth material and the `SHADE_UV` view all do. `resolve` encodes such a pixel without tone mapping it. See [Why a normal is not a color](Why-a-normal-is-not-a-color).

A write replaces the pixel, so the pixel takes the fragment's answer about what it holds. A blend mixes into what is there, and a mixture with light in it is light. Only light blends, because the rasterizers refuse a blended data triangle. So `blend` takes no flag and always leaves the pixel holding light.

A blend whose effective alpha is zero changes nothing at all. Source-over hides nothing and adds nothing there, so it adds no color, no depth and no answer about what the pixel holds. It used to take the data flag before it read the alpha. An invisible fragment could then put the tone mapping curve back onto a normal's bytes. The rule applies to `blend` alone. A `write` at alpha zero still replaces the pixel.

## Float render targets

A `FLOAT_TARGET` keeps light above one, with no clamp, no tone mapping and no sRGB encode. three.js: `WebGLRenderTarget` with `type: FloatType`. Pass the type to the constructor, draw into the target, and read it with `attachment` or `attachment_texture`.

```mojo
var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0), FLOAT_TARGET)
renderer.render_into(target, scene, assets, camera)
var light = target.attachment_texture(0)
```

`TargetType` is a type. `is_valid` names the three values. A bare integer does not compile. `check_target` refuses any other value.

| Type | three.js | What a readout holds |
|---|---|---|
| `UNSIGNED_BYTE_TARGET` | `UnsignedByteType` | Each channel clamped to zero through one and rounded to a 255th. The default. |
| `HALF_FLOAT_TARGET` | `HalfFloatType` | Each channel rounded to the nearest half float. A value past 65504 is held at 65504. |
| `FLOAT_TARGET` | `FloatType` | Each channel as the target holds it. |

`attachment(0)` gives the light with straight alpha, row-major from the top, four floats a pixel. `stored(value, type)` is the rounding each type applies. `attachment_texture(0)` gives the same numbers in a `FLOAT_TYPE`, `LINEAR` texture, so a later draw samples them as they are.

A pixel that holds data, such as a normal material's bytes, reads as the fractions its bytes show. `resolve` and `texture` do not change with the type. A display always gets bytes.

`depth_texture(type=FLOAT_TARGET)` gives the window depth in a float texture. Zero is the near plane and one is the far plane. A pixel where nothing was drawn holds one. three.js: a `DepthTexture` with `type: FloatType`. The default type gives the eight-bit preview.

This port differs from three.js in two ways:

- Every target accumulates in 32-bit floats, whatever its type. The type applies once, when you read the target. three.js rounds at each write, so a byte target that blends many layers can lose more there.
- A half float target holds 65504 for a larger value. A GPU writes infinity. A texture refuses infinity, so the port keeps the largest finite half.

## Multiple render targets

A target with the `OUTPUT_NORMAL` output keeps the view-space normal of each pixel beside its light. One pass fills both. three.js: `WebGLRenderTarget` with `count: 2`, and a shader that writes `gNormal`.

```mojo
var outputs: List[TargetOutput] = [OUTPUT_COLOR, OUTPUT_NORMAL]
var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0), FLOAT_TARGET, outputs)
renderer.render_into(target, scene, assets, camera)
var normals = target.attachment_texture(1)
```

This port has no user shaders, so `TargetOutput` names what a fragment can write. `is_valid` names the two values. A bare integer does not compile.

| Output | Attachment holds |
|---|---|
| `OUTPUT_COLOR` | The lit color. It must be the first output. |
| `OUTPUT_NORMAL` | The unit normal of the nearest opaque surface, in view space. It is the normal after any normal map or bump map. |

`check_target` refuses an empty list and a first output that is not the color. It also refuses an output that is none of the two, and an output that repeats. `color_only()` is the default list.

Every opaque triangle writes its normal where it writes its color. That includes an unlit triangle and the `SHADE_UV` view. A blended triangle keeps no depth, so it leaves the normal alone too. A line or a point has no surface, so it clears the normal. `clear_inside` clears it too. A pixel with no normal holds zero.

`attachment(1)` holds the normal with an alpha of one, or zero where no surface wrote one. In a float or half float target the normal is raw, from minus one to one. A byte target cannot hold a negative number, so it packs the normal as three.js's `packNormalToRGB` does: halved and moved up by a half.

The renderer turns each normal into view space with the camera's up and back axes. `Lighting.back` and `camera_back` give the back axis. `view_direction` does the turn, and both rasterizers call it.

The screen-space passes read the attachment. The composer draws its frame with a normal attachment when an SSAO, SAO or SSR pass is on. See [Post-processing](Post-processing#the-depth-and-the-normals).

On the GPU, `GpuRenderer.read_back_target(type, outputs)` copies the light, the normal, the depth and the data flag into a `RenderTarget`. The result is the target the CPU fills from the same draw. `tests/test_gpu.mojo` compares the two. See [GPU backend](GPU-backend#gpurenderer).

This port differs from three.js in three ways:

- Only two outputs exist. three.js lets a shader write anything to any attachment.
- A blend does not touch the normal. WebGL blends every attachment with the same equation. A blended normal means nothing, so the port keeps the normal of the surface that owns the depth.
- A clear sets the normal to zero. WebGL clears every attachment to the clear color.

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
