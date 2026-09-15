# Why colour is linear

Every colour in the renderer is decoded to linear light on the way in, mixed there, and encoded to sRGB once at the pixel. Arithmetic on encoded bytes gives shaded midtones that are far too dark.

## Light adds and sRGB does not

A byte value of 128 is not half the light of 255. It is about 21.6 percent of it. sRGB spends more of its 256 steps on dark values, where the eye can tell them apart. Every image file and every authored colour is encoded that way.

Filtering blends texels. Shading multiplies by a Lambert term. Blending mixes a translucent surface with what is behind it. Each is arithmetic on light, and it is only right where the numbers are proportional to light.

## What it changed

A white surface at a Lambert level of 0.4 used to come out as byte 102. The right answer is 170.

| Lambert level | Encoded bytes | Linear light |
|---|---|---|
| 0.25 | 64 | 137 |
| 0.40 | 102 | 170 |
| 0.60 | 153 | 203 |
| 0.80 | 204 | 231 |

## Where decoding happens

- A material colour is decoded once in `Renderer.prepare`.
- A texture is decoded through a 256-entry table built once per texture. The same table goes to the GPU.
- Alpha is never decoded. It is coverage, not colour.
- A `LINEAR` texture holds data and is not decoded.

## Premultiplied alpha

The `RenderTarget` holds premultiplied linear RGBA at float precision. Compositing and filtering are both weighted sums, and a hidden colour must weigh nothing:

```
out.rgb = src.rgb + dst.rgb * (1 - src.a)
out.a   = src.a   + dst.a   * (1 - src.a)
```

Two bugs forced this. Rounding to a byte after every translucent layer lost a hundred faint layers entirely. And blending half-transparent red over fully transparent blue gave opaque purple, because the invisible blue contributed colour.

## Where linear stops

`resolve` unpremultiplies and encodes each pixel once. PNG stores unassociated alpha, and alpha does not go through the sRGB curve. Texture mip levels are built the same way and re-encoded to bytes, as a GPU stores them.

## Lights add

Two white lamps at half strength make one at full strength. That is true of linear numbers and false of bytes, where half plus half comes to 128 rather than 255. Nothing is clamped until `resolve`, so two lamps can overexpose a white surface and the headroom survives every step.
