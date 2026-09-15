# Textures

`render/texture.mojo` and `render/texture_store.mojo`. A `Texture` is an RGBA image with a wrap mode, a filter, a color space and an optional mip chain. A material names one by id.

three.js: `Texture`, `wrapS`, `wrapT`, `magFilter`, `minFilter`, `generateMipmaps`, `colorSpace`.

## Make a texture

```mojo
checkerboard(size, squares, first, second, wrap=REPEAT, filter=NEAREST, mipmapped=False)
texture_from(image, wrap=REPEAT, filter=NEAREST, color_space=None, mipmapped=False)
Texture(width, height, pixels, wrap=REPEAT, filter=NEAREST, color_space=SRGB, mipmapped=False)
```

`checkerboard` builds a test pattern. `texture_from` takes a `DecodedImage` from the PNG reader. `Texture` takes row-major RGBA bytes from the top.

## Wrap

| Value | A coordinate of 1.5 reads |
|---|---|
| `REPEAT` | The same texel as 0.5. |
| `CLAMP` | The edge texel. |
| `MIRROR` | The image reflected, so tiles meet without a seam. |

Under `REPEAT`, coordinates 0 and 1 name the same texel. Under `CLAMP` they name opposite edges.

## Filter

| Value | Meaning |
|---|---|
| `NEAREST` | The texel the sample lands in. Hard edges. |
| `BILINEAR` | The four nearest texels, blended by distance. |

## Mipmaps

`mipmapped=True` builds a chain of halved copies down to one texel. Sampling then picks the level whose texels match the pixel footprint, and blends between the two nearest levels. This stops a distant surface from shimmering.

The chain costs a third more memory. It is built in premultiplied linear light.

## Color space

| Value | Meaning |
|---|---|
| `SRGB` | An image. Bytes are decoded to linear light when read. The default. |
| `LINEAR` | Data. Bytes are used as stored. |
| `UNKNOWN_SPACE` | A decoder's answer for a file it cannot interpret. A texture refuses it. |

Alpha is never decoded. It is coverage, not color.

## Coordinates

`u` runs from left to right and `v` from bottom to top. Rows in memory run from the top. Sampling flips once, as three.js's `flipY` does.

## Members

| Member | Meaning |
|---|---|
| `sample(u, v) -> FloatColor` | The color at a coordinate, level zero. |
| `sample_level(u, v, level) -> FloatColor` | Trilinear, between two mip levels. |
| `texel(x, y) -> Color` | One stored texel. |
| `is_blank() -> Bool` | The blank texture, which samples as opaque white. |
| `validate()` | Refuse a wrap, filter or color space that is none of the named values. |
| `levels`, `width`, `height` | The chain length and the base size. |

## TextureStore

`assets.textures.add(texture)` returns a `TextureId`. `get(id)` borrows it. `NO_TEXTURE` is the id of no texture, and samples as white.

## Errors

- Dimensions must be positive, and the buffer length must match.
- A wrap, filter or color space that is none of its named values raises. The GPU upload checks again.
- A `checkerboard` size must divide evenly by its square count.

## Why

See [Why mipmaps](Why-mipmaps) and [Why color is linear](Why-color-is-linear).
