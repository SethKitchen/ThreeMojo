# Textures

`render/texture.mojo` and `render/texture_store.mojo`. A `Texture` is an RGBA image with a wrap mode, a filter, a color space, an alpha mode and an optional mip chain. A material names one by id.

![Two checkerboard cubes turn, nearest beside bilinear](out/textured.png)

three.js: `Texture`, `wrapS`, `wrapT`, `magFilter`, `minFilter`, `generateMipmaps`, `colorSpace`.

## Make a texture

```mojo
checkerboard(size, squares, first, second, wrap=REPEAT, filter=NEAREST, mipmapped=False, alpha=COVERAGE)
texture_from(image, wrap=REPEAT, filter=NEAREST, color_space=None, mipmapped=False, alpha=COVERAGE)
Texture(width, height, pixels, wrap=REPEAT, filter=NEAREST, color_space=SRGB, mipmapped=False, alpha=COVERAGE)
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

The chain costs a third more memory. It is built in premultiplied linear light, unless the texture ignores its alpha.

## Color space

| Value | Meaning |
|---|---|
| `SRGB` | An image. Bytes are decoded to linear light when read. The default. |
| `LINEAR` | Data. Bytes are used as stored. |
| `UNKNOWN_SPACE` | A decoder's answer for a file it cannot interpret. A texture refuses it. |

Alpha is never decoded. It is coverage, not color.

## Alpha

| Value | Meaning |
|---|---|
| `COVERAGE` | Alpha hides color. Filtering and the mip chain weight each texel by it, and a sample carries it. The default. |
| `IGNORED` | Alpha is not read. Every alpha byte counts as 255. Color is filtered as it is, and every sample is opaque. |

An emissive map must ignore its alpha. Its alpha is not coverage. Filtered as coverage, a white texel with alpha zero turns black under `BILINEAR`, and the whole mip chain darkens with it. The renderer refuses an emissive map built with `COVERAGE`.

An alpha map must ignore its alpha too, and must be `LINEAR`. Its green channel is a coverage rather than a color. See [Materials](Materials#alpha-map-and-alpha-test).

`ignoring_alpha()` copies a texture into the other mode and rebuilds its mip chain from the full-size image. Use it when one image is both a base map and an emissive map. The blank texture's copy is blank and ignores its alpha, so it passes as an emissive map and samples as white.

## Coordinates

`u` runs from left to right and `v` from bottom to top. Rows in memory run from the top. Sampling flips once, as three.js's `flipY` does.

## Transform

A texture can move, tile and turn on a surface. three.js: `offset`, `repeat`, `rotation`, `center`, `matrix`.

| Field | Default | Meaning |
|---|---|---|
| `offset` | `Vector2(0, 0)` | How far the coordinates move, after the rest. |
| `repeat` | `Vector2(1, 1)` | How many times the texture fits across each axis. |
| `rotation` | zero | How far the image turns, counter-clockwise. An `Angle`. |
| `center` | `Vector2(0, 0)` | The point the turn and the scale are about. |

Set the fields after construction, as in three.js. `uv_transform()` returns the matrix they make. See [Math](Math#matrix3) for its order.

The renderer carries every coordinate of a mesh through its map's matrix before the fragment samples with it. The texture itself does not change. The wrap mode still decides what a coordinate past the edge reads. Both rasterizers get the same coordinates.

A fragment samples the map, the emissive map and the alpha map at one coordinate. A material that names more than one must give them all the same transform. The renderer refuses them otherwise. `ignoring_alpha()` copies the transform, so two maps from one image agree.

```mojo
var board = checkerboard(64, 8, white, blue)
board.repeat = Vector2(4, 4)
board.rotation = Angle(45.0, DEGREE)
board.center = Vector2(0.5, 0.5)
var id = assets.textures.add(board^)
```

## Members

| Member | Meaning |
|---|---|
| `sample(u, v) -> FloatColor` | The color at a coordinate, level zero. |
| `sample_level(u, v, level) -> FloatColor` | Trilinear, between two mip levels. |
| `texel(x, y) -> Color` | One stored texel. |
| `is_blank() -> Bool` | The blank texture, which samples as opaque white. |
| `ignoring_alpha() -> Texture` | A copy that ignores its alpha, with its chain rebuilt. |
| `uv_transform() -> Matrix3` | The transform on the coordinates, from the four fields above. |
| `validate()` | Refuse a wrap, filter, color space or alpha mode that is none of the named values. |
| `levels`, `width`, `height`, `alpha` | The chain length, the base size and the alpha mode. |
| `offset`, `repeat`, `rotation`, `center` | The transform's fields. |

## TextureStore

`assets.textures.add(texture)` returns a `TextureId`. `get(id)` borrows it. `NO_TEXTURE` is the id of no texture, and samples as white.

## Errors

- Dimensions must be positive, and the buffer length must match.
- A wrap, filter, color space or alpha mode that is none of its named values raises. The GPU upload checks again.
- A `checkerboard` size must divide evenly by its square count.
- The renderer refuses a map and an emissive map on one material whose transforms differ.

## Why

See [Why mipmaps](Why-mipmaps) and [Why color is linear](Why-color-is-linear).
