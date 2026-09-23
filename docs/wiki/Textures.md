# Textures

`render/texture.mojo` and `render/texture_store.mojo`. A `Texture` is an RGBA image with a wrap mode, a filter, a color space, an alpha mode and an optional mip chain. It holds bytes, or floats for an HDR image. A material names one by id.

![Two checkerboard cubes turn, nearest beside bilinear](out/textured.png)

three.js: `Texture`, `DataTexture`, `DepthTexture`, `CompressedTexture`, `CubeTexture`, `WebGLRenderTarget.texture`, `wrapS`, `wrapT`, `magFilter`, `minFilter`, `generateMipmaps`, `colorSpace`, `anisotropy`, `type`, `RGBELoader`, `EXRLoader`.

## Make a texture

```mojo
checkerboard(size, squares, first, second, wrap=REPEAT, filter=BILINEAR, mipmapped=True, alpha=COVERAGE)
texture_from(image, wrap=REPEAT, filter=BILINEAR, color_space=None, mipmapped=True, alpha=COVERAGE)
Texture(width, height, pixels, wrap=REPEAT, filter=BILINEAR, color_space=SRGB, mipmapped=True, alpha=COVERAGE)
data_texture(width, height, numbers, channels=4, wrap=CLAMP, filter=NEAREST, mipmapped=False, alpha=COVERAGE)
texture_of(framebuffer, wrap=CLAMP, filter=BILINEAR, mipmapped=True, alpha=COVERAGE)
depth_texture_of(framebuffer, wrap=CLAMP)
float_texture(width, height, floats, wrap=CLAMP, filter=BILINEAR, mipmapped=False, alpha=COVERAGE)
float_texture_from(hdr_image, wrap=CLAMP, filter=BILINEAR, mipmapped=False, alpha=COVERAGE)
```

`checkerboard` builds a test pattern. `texture_from` takes a `DecodedImage` from the PNG reader. `Texture` takes row-major RGBA bytes from the top. The next three are below. The float textures are in [HDR images](#hdr-images).

## From numbers

`data_texture` is three.js's `DataTexture`: a texture from raw numbers rather than from an image file. Each number is a fraction from zero to one and becomes one byte, quantized without any transfer function. The texture is `LINEAR`, so the byte samples back as the fraction it was. A number outside zero to one is clamped.

```mojo
var ramp = data_texture(3, 1, [0.35, 0.7, 1.0], channels=1, alpha=IGNORED)
var cel = toon_material(Color(255, 170, 60), gradient_map=assets.textures.add(ramp^))
```

| `channels` | three.js | Each texel holds |
|---|---|---|
| `1` | `RedFormat` | Red. Green and blue are zero, alpha is one. |
| `2` | `RGFormat` | Red and green. Blue is zero, alpha is one. |
| `3` | `RGBFormat` | Red, green and blue. Alpha is one. |
| `4` | `RGBAFormat` | All four. The default. |

The numbers fill the channels in order, as WebGL samples these formats. A one-channel texture is red, not gray. A toon ramp reads red alone, so one channel serves it. A gray image needs three equal numbers a texel.

The defaults are three.js's own for a `DataTexture`: nearest, no mip chain, and the edges clamped. Data is read where it was written. The length must be `width * height * channels`, and every number must be finite.

## From a render

`texture_of` takes a `Framebuffer` and returns the texture that holds it: three.js's `WebGLRenderTarget.texture`. A framebuffer holds eight-bit sRGB with unassociated alpha, which is what a color texture holds, so nothing is converted. `RenderTarget.texture()` resolves a target and does the same in one call. A later draw can then sample what an earlier one drew.

```mojo
var target = RenderTarget(160, 120, Color(30, 60, 90))
renderer.render_into(target, stage, props, studio_camera)
var picture = assets.textures.add(target.texture())
var screen = Material(Color(255, 255, 255), picture, kind=BASIC)
```

The texture is a copy, not a view. Drawing into the target again changes nothing the texture holds. The edges are clamped by default, as three.js clamps a render target's texture.

It is a snapshot in bytes. Light above one was clamped or tone mapped when the image was resolved, and a later exposure cannot bring it back. That suits a picture on a screen in the scene. A linear texture that keeps a render's range for a later pass is a different thing, and this is not it.

`depth_texture_of` takes the depth the framebuffer carries and returns it as a texture: a preview of three.js's `DepthTexture`, at eight bits. Each texel is the window-space depth a GPU stores, as one gray byte in every channel. It is zero at the near plane and one at the far plane. A pixel nothing was drawn into is at the far plane. The texture is `LINEAR`, ignores its alpha, and is read nearest with no chain: two depths averaged are the depth of nothing.

`RenderTarget.depth_texture()` does the same for a target as it stands. `depth_texture_of_buffer` takes a bare depth buffer.

It is a picture of the depth, not the depth. A byte holds 256 steps, and a perspective projection spends most of them near the near plane. Take planes at a tenth of a meter and a hundred. A surface one meter away is byte 230, ten meters is 253, and forty meters is 255, the far plane's own byte. three.js's `DepthTexture` holds a real depth format. Use this to look at a depth, not to compare or reconstruct one.

`examples/television.mojo` renders a box into a small target every frame and shows its picture and its depth on two screens.

## From a compressed file

`render/compressed_texture.mojo`. `compressed_texture` decodes a block-compressed payload into an ordinary texture: three.js's `CompressedTexture`. The GPU samples a compressed texture as it is. This project's rasterizers read bytes, so the blocks are decoded once, on the host, and sampled like any other image.

```mojo
var image = compressed_texture(width, height, blocks, RGBA_S3TC_DXT5_FORMAT)
```

`compressed_texture(width, height, data, format, wrap=CLAMP, filter=BILINEAR, color_space=SRGB, mipmapped=False, alpha=COVERAGE)`. The defaults are three.js's own for the class: edges clamped and no chain, since a compressed file usually carries its own levels. Only the first level is read. Pass `mipmapped=True` to build a chain from the decoded image.

| `format` | three.js | A 4x4 block is |
|---|---|---|
| `RGB_S3TC_DXT1_FORMAT` | `RGB_S3TC_DXT1_Format` | Eight bytes: two RGB565 colors and a two-bit index per texel. The transparent index reads as opaque black. |
| `RGBA_S3TC_DXT1_FORMAT` | `RGBA_S3TC_DXT1_Format` | The same, with the transparent index read as transparent black. |
| `RGBA_S3TC_DXT5_FORMAT` | `RGBA_S3TC_DXT5_Format` | Sixteen bytes: two alphas and a three-bit index per texel, then a color block always read in its four-color order. |

The 565 channels widen to eight bits by copying their top bits down, as the hardware widens them. The blends round to nearest. An image need not be whole blocks: the texels past the edge are decoded and dropped. `decode_s3tc` returns the RGBA bytes without building a texture.

`compressed_texture` refuses a format that is none of the three, dimensions that are not positive, and a payload whose length is not the block grid's. `tests/compile_fail/` proves a bare integer is not a format.

## HDR images

An HDR image holds linear light with no upper limit. `render/rgbe.mojo` reads a Radiance `.hdr` file and `render/exr.mojo` reads an OpenEXR file. Each returns a `FloatImage`, and `float_texture_from` turns it into a float texture. Use the texture as a map, or turn it into a cube for a background or an environment.

three.js: `RGBELoader` (now `HDRLoader`), `EXRLoader`, `DataTexture` with `FloatType`, and `WebGLCubeRenderTarget.fromEquirectangularTexture`.

```mojo
from render.exr import decode as decode_exr
from render.rgbe import decode as decode_rgbe

var sky = float_texture_from(decode_exr(Path("sky.exr").read_bytes()))
var cube = assets.cube_textures.add(cube_from_equirectangular(sky, mipmapped=True))
scene.background = cube_background(cube)
scene.environment = cube
var lamp = assets.textures.add(float_texture_from(decode_rgbe(Path("lamp.hdr").read_bytes())))
```

### Float textures

`float_texture(width, height, floats)` takes row-major RGBA floats from the top. Its `texel_type` is `FLOAT_TYPE`, three.js's `FloatType`. A byte texture is `UNSIGNED_BYTE_TYPE`, three.js's `UnsignedByteType`. The floats are in `data`, and `pixels` is empty.

A float is sampled as it is. There is no ramp, no clamp and no transfer function, so the texture must be `LINEAR`. The filter and the mip chain average the floats premultiplied, as they average a byte texture's decoded light. A texel of 8 beside a texel of 0 filters to 4, where a byte texture gives one half.

The defaults are three.js's loader settings: `CLAMP`, `BILINEAR` and no chain. Every number must be finite: an infinity or a NaN spreads through every filter that reads it. `texel(x, y)` returns bytes, so a float texture refuses it. Use `wrapped_texel(x, y)`.

Both rasterizers sample a float texture. The GPU texel buffer holds bytes, so each float crosses as four little-endian bytes. The kernel reads the bits back with `float_from_bytes`, and both backends make the color with `float_texel`. A gradient map must hold bytes, on both backends.

### Read an RGBE file

`render.rgbe.decode(bytes)` reads a Radiance `.hdr` file. The header must start with `#?` and a program name. It must name `FORMAT=32-bit_rle_rgbe` and a size line `-Y height +X width`. Each scanline is flat, or run-length encoded one channel after another.

A channel is `byte * 2^(exponent - 128) / 255`, worked in doubles and stored as a float. This is three.js's arithmetic. Alpha is one. `GAMMA` and `EXPOSURE` are read past, as three.js reads past them.

### Read an EXR file

`render.exr.decode(bytes)` reads a single-part scanline OpenEXR file. The header needs `channels`, `compression` and `dataWindow`. Other attributes are read past.

| Compression | Lines a block | Note |
|---|---|---|
| `NO_COMPRESSION` | 1 | |
| `RLE_COMPRESSION` | 1 | Run-length bytes, then the predictor and the split undone. |
| `ZIPS_COMPRESSION` | 1 | zlib through `render/inflate.mojo`, then the same. |
| `ZIP_COMPRESSION` | 16 | The same, sixteen lines at a time. |
| `PIZ_COMPRESSION` | 32 | A bitmap and a lookup table, a Huffman code, and a Haar wavelet per channel. |

A channel holds halves or floats. A half widens to the float it spells, subnormals and all. `R`, `G` and `B` make RGBA, with `A` as the alpha or one where there is none. `Y` alone makes gray, with an alpha of one. Other channels are read past. Rows come out from the top line of the data window.

### An equirectangular environment or background

`cube_from_equirectangular(image, size=None, mipmapped=None)` turns a panorama into a `CubeTexture`. three.js does the same when a texture with `EquirectangularReflectionMapping` becomes a background or an environment. Each face texel reads the panorama at `equirect_uv` of its direction, three.js's `equirectUv`.

The faces keep the panorama's texel type, color space, filter and alpha mode. A float panorama gives float faces. The face size is the panorama's height by default, as in three.js. The faces get a chain if the panorama has one, and `mipmapped=True` asks for one. A rough surface reads the chain, see [Materials](Materials#the-environment).

### What is not ported

- Half-float storage. three.js's loaders default to `HalfFloatType`. Here a half widens to a float, which holds every half exactly.
- The `mapping` field. Call `cube_from_equirectangular` and name the cube. The renderer does not convert a texture on its own.
- The automatic PMREM. three.js prefilters an environment on its own. Here you call `pmrem_from_equirectangular`, see [PMREM](#pmrem).
- Light above one in a background. The backdrop crosses to both backends as sRGB bytes, so a background clips at one before tone mapping. A reflection keeps the floats.
- RGBE: XYZE pixels, the old Radiance run-length scheme, and every orientation but `-Y +X`. The first is refused, and three.js reads none of them correctly.
- EXR: tiled, deep and multi-part files, PXR24, B44, B44A, DWAA and DWAB compression, luminance-chroma images, subsampled channels, and `UINT` color. Each is refused by name. three.js reads all but the last two.
- `EXRLoader.setOutputFormat`. The output is always RGBA, three.js's default.

### Where the HDR readers differ from three.js

Each reader refuses a file that three.js reads wrongly. three.js reads every EXR color channel with the type of the last one. This reader reads each channel as its own type. three.js reads past the end of a block, a Huffman table or a file. It also leaves the rows of a short RGBE file black. Both readers here refuse each of these.

## Anisotropy

A surface seen at a glancing angle covers a footprint that is long one way and short the other. A mip level is square. The level the long axis wants blurs the short axis, and the level the short axis wants sparkles along the long one. `anisotropy`, three.js's `Texture.anisotropy`, is how many samples a fragment can take along the long axis instead, each read at the level the short axis wants.

```mojo
var floor = checkerboard(64, 8, white, blue)
floor.anisotropy = 16
```

One, the default, is the plain trilinear read. `MAX_ANISOTROPY` is sixteen, which is what a desktop GPU reports and what three.js caps a texture at. Set the field after construction, as in three.js. `validate()` refuses a value below one or above the cap, and the GPU upload refuses it again.

### The footprint is an ellipse, not two derivatives

`anisotropic_footprint(along_x, along_y, width, height, anisotropy)` returns a `Footprint`: the level, the tap count and the step between taps.

The two arguments are how far the texture coordinates move for one pixel right and one pixel down. They are the columns of a 2x2 matrix, and the footprint is the ellipse that matrix maps the unit disc onto. Its principal lengths are that matrix's singular values, which are **not** the lengths of the two derivatives.

Measure the derivatives instead and a rotation breaks it. Take a footprint 16 texels long and 1 across, then turn the screen's basis 45 degrees. The ellipse is unchanged, but the two derivatives now have the same length. Measuring them calls the footprint round: one tap at level 3.5, where sixteen taps at level 0 are correct. A surface blurs because of how it happens to lie against the screen axes.

`_principal_axes` takes the real lengths from a quadratic, and `_major_direction` takes the real long axis. Neither needs a decomposition library.

### The level follows the short axis

Taps along the long axis filter along the long axis. They do nothing across the short one, so rounding the tap count up must not shrink the level below what the short axis needs:

```
effective minor = max(1, minor, major / taps allowed)
taps            = clamp(ceil(major / effective minor), 1, allowed)
level           = log2(effective minor)
```

Dividing the major axis by the tap count jumps instead. Take a footprint going from 16 by 16 to 16.001 by 16. It gains one tap, and it used to lose almost a whole level with it, from 4.0 to 3.0. A thousandth of a texel moved the level by one. It now gains the tap and keeps the level. The floor of one stops a tap per texel from reading any texel twice.

With an anisotropy of one the level is the log of the longer derivative. That is the number `mip_level` gives, and the number OpenGL's isotropic rho gives. A texture that asks for nothing reads exactly as it did.

### Sampling a footprint

`sample_footprint(u, v, footprint)` takes the taps and averages them premultiplied. It calls `Footprint.validate()` first, because a `Footprint` is fieldwise-constructible and `Footprint(0, 0, Vector2(0, 0))` builds: zero taps would divide the average by nothing. The rasterizers take `_sample_footprint`, which does not check. What they pass came from `anisotropic_footprint`, and a fragment loop is not a place to handle an error.

Both rasterizers call the same estimator and the same accumulation; see [Rasterization](Rasterization).

## Cube textures

`render/cube_texture.mojo` and `render/cube_texture_store.mojo`. A `CubeTexture` is six square textures, one per face of a box around the viewer, sampled by direction rather than by place. It is what a mirror reflects and what a sky is made of.

![A chrome ball under a sky reflects two boxes that circle it](out/mirror.png)

three.js: `CubeTexture`, `CubeTextureLoader`, `WebGLCubeRenderTarget.texture`.

```mojo
var sky = assets.cube_textures.add(cube_texture_from(images, SEEN_FROM_OUTSIDE))
var seen = assets.cube_textures.add(renderer.render_cube(scene, assets, cube_camera))
var chrome = Material(Color(255, 255, 255), kind=BASIC, env_map=sky)
scene.background = cube_background(sky)
```

| Builder | Meaning |
|---|---|
| `CubeTexture(faces)` | Six textures in face order, each square, all one size, all `CLAMP`. |
| `cube_texture_from(images, layout=SEEN_FROM_INSIDE, filter=BILINEAR, color_space=None, mipmapped=False, alpha=COVERAGE)` | Six `DecodedImage`s. three.js's `CubeTextureLoader`. |
| `cube_texture_of(images, filter=BILINEAR, mipmapped=False, alpha=COVERAGE)` | Six `Framebuffer`s, as a [CubeCamera](Cameras#cubecamera) renders them. |

The faces are held in three.js's order: `POSITIVE_X`, `NEGATIVE_X`, `POSITIVE_Y`, `NEGATIVE_Y`, `POSITIVE_Z`, `NEGATIVE_Z`. `FACE_COUNT` is six.

### One convention

Every face is what a camera at the center of the box sees looking out along one axis. `face_forward(face)` is the axis and `face_up(face)` is the camera's up. The up is positive y for the four side faces, and the z axis for the two faces on y. These are three.js's own six ups. A `CubeCamera` renders the faces this way, and the sampler reads them this way, so a rendered cube needs no flip.

The six images of an OpenGL cube map are the same views mirrored left for right. three.js flips a sign for them, `flipEnvMap`. Here `cube_texture_from` takes a `CubeLayout`. `SEEN_FROM_INSIDE`, the default, reads each image as it is. `SEEN_FROM_OUTSIDE` mirrors each face once, on the way in. Use it for a set of six image files stored the usual way.

### Sampling

`sample(direction)` returns the color in a direction. `face_of(direction)` picks the face on the axis the direction leans along most. A tie goes to x, then y, then z, as OpenGL picks it. `face_uv(face, direction)` projects the direction onto that face and reads how far it lands across and up, in the camera's own right and up axes. Both are pure, and both rasterizers call them.

A face is read at its full size, never down a mip chain. A reflection's direction changes across a surface at a rate that is not the surface's own texture footprint. The same rule keeps a matcap out of its chain. One reader asks for the chain by a number of its own: a physical surface reads it by its roughness. `sample_level(direction, level)` reads a face `level` down, and `levels()` says how many there are. See [Materials](Materials#the-environment).

A face must be wrapped `CLAMP`. A coordinate past a face's edge belongs to the next face, and a flat image has no next face to read. The bilinear filter's neighbors at an edge hold that edge.

### CubeTextureStore

`assets.cube_textures.add(cube)` returns a `CubeTextureId`. `get(id)` borrows it. `NO_CUBE_TEXTURE` is the id of no cube texture. `SCENE_ENVIRONMENT` is not an id either: a material naming it reflects the scene's `environment`. See [Materials](Materials#environment-map) and [Scene graph](Scene-graph#background-and-environment).

### Errors

- A cube needs exactly six faces. Each must hold texels, be square, be the size of the others, and be wrapped `CLAMP`.
- `cube_texture_from` refuses a layout that is neither named value, and an empty image. It refuses a file whose color space cannot be interpreted when none is given.
- `validate()` refuses a face edited into nonsense after the cube was built. The GPU upload calls it again.
- The store refuses `NO_CUBE_TEXTURE`, `SCENE_ENVIRONMENT` and any id it does not hold.

`examples/mirror.mojo` builds a sky from six computed faces, renders a cube camera's view every frame, and reflects it in a chrome ball.

## PMREM

`render/pmrem.mojo` and `render/cube_uv.mojo`. A PMREM is an environment prefiltered for every roughness. A rough `STANDARD` or `PHYSICAL` surface reads it and sees the environment blurred by its own lobe. Without one, the surface reads the cube's box-filtered chain.

three.js: `PMREMGenerator.fromCubemap`, `PMREMGenerator.fromEquirectangular`, `cube_uv_reflection_fragment`.

```mojo
var sky = pmrem_from_cube(cube_texture_from(images, SEEN_FROM_OUTSIDE))
var env = assets.cube_textures.add(sky^)
scene.environment = env
var hdr = assets.cube_textures.add(pmrem_from_equirectangular(panorama))
```

| Builder | Meaning |
|---|---|
| `pmrem_from_cube(cube)` | A copy of `cube` with its PMREM in `cube_uv`. Byte or float faces. |
| `pmrem_from_equirectangular(image)` | The faces of `cube_from_equirectangular`, with a PMREM read straight from the panorama. |

The result is an ordinary `CubeTexture`. Name it as an env map, as a scene's `environment` or as a background. `is_prefiltered()` says whether a cube holds a PMREM. three.js's `fromScene` is `Renderer.render_cube` and then `pmrem_from_cube`.

### The layout

The PMREM is one float image in three.js's cube UV layout. Each copy of the environment is six square tiles, three across and two up. The sharpest copy is the face size, rounded down to a power of two, at the bottom left. Each copy above it is half the size, down to sixteen texels. Six more sixteen-texel copies sit beside the last one, each blurrier than the one before.

Every tile keeps a one-texel border in the directions of the next face. The bilinear filter never reads a neighbor tile, so a rough reflection has no seam.

### How a roughness reads it

`roughness_to_mip(roughness)` is three.js's table from a roughness to a copy. Roughness one reads the blurriest copy, and a low roughness reads the sharpest. `cube_uv_taps` finds the two copies on either side and the fraction between them. `sample_cube_uv` reads both and mixes them, as three.js's `textureCubeUV` does.

A physical surface asks `CubeTexture.sample_rough(direction, roughness)`. It reads the radiance at its roughness and the irradiance around its normal at roughness one, as three.js's `getIBLRadiance` and `getIBLIrradiance` do. A cube without a PMREM answers from its chain at `reflection_level`. Both rasterizers use this arithmetic. The GPU reads the PMREM from the row after the six faces. See [GPU backend](GPU-backend).

### How it is built

The sharpest copy reads the source in the direction of each texel. Each copy after it is the one before, blurred by a Gaussian on the sphere. The blurs add up to each copy's own width: `1 / size` for the halving copies, and three.js's `extra_lod_sigma()` for the six others. three.js chose those widths to follow the GGX lobe at each roughness.

Each blur is two passes. The first turns about a pole and the second turns toward it. The pole changes each time among ten axes of a dodecahedron, `pole_axis`. This is three.js's `SphericalGaussianBlur`, run on the host once.

### Where it differs from three.js

- The image holds 32-bit floats. three.js renders half floats.
- A face smaller than sixteen texels is read at sixteen. three.js's layout does not work below sixteen.
- A mirror read of a prefiltered cube reads its faces, not the sharpest copy. The two hold the same image.
- A background reads the faces. three.js's `backgroundBlurriness` is not ported.

### Errors

- `pmrem_from_cube` refuses a cube that `CubeTexture.validate` refuses.
- `pmrem_from_equirectangular` refuses a blank panorama.
- `validate_cube_uv` refuses a layout image that is not float, `CLAMP` and `BILINEAR` with no chain. It refuses a size that is not three.js's layout. `CubeTexture.validate` calls it, and so does the GPU upload.

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

The chain is built by default, as three.js's `Texture` sets `generateMipmaps` and `LinearMipmapLinearFilter`, and the filter is bilinear by default, as three.js's `LinearFilter` is. Pass `mipmapped=False` or `NEAREST` to turn either off.

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
| `data_texture(width, height, numbers, channels)` | A texture from fractions. See [From numbers](#from-numbers). |
| `texture_of(framebuffer)`, `depth_texture_of(framebuffer)` | A texture from a render, and from its depth. See [From a render](#from-a-render). |
| `sample(u, v) -> FloatColor` | The color at a coordinate, level zero. |
| `sample_level(u, v, level) -> FloatColor` | Trilinear, between two mip levels. |
| `texel(x, y) -> Color` | One stored texel. A float texture refuses it. |
| `wrapped_texel(x, y, level=0) -> FloatColor` | One texel as light, wrapped. Floats as they are, bytes through the ramp. |
| `is_blank() -> Bool` | The blank texture, which samples as opaque white. |
| `ignoring_alpha() -> Texture` | A copy that ignores its alpha, with its chain rebuilt. |
| `uv_transform() -> Matrix3` | The transform on the coordinates, from the four fields above. |
| `sample_footprint(u, v, footprint) -> FloatColor` | One trilinear sample, or several along a footprint's long axis. See [Anisotropy](#anisotropy). |
| `validate()` | Refuse a wrap, filter, color space, alpha mode or texel type that is none of the named values, a float texture that is not `LINEAR`, or an anisotropy below one or above `MAX_ANISOTROPY`. |
| `levels`, `width`, `height`, `alpha`, `anisotropy` | The chain length, the base size, the alpha mode and the tap count. |
| `texel_type`, `pixels`, `data` | `UNSIGNED_BYTE_TYPE` with bytes in `pixels`, or `FLOAT_TYPE` with floats in `data`. See [HDR images](#hdr-images). |
| `offset`, `repeat`, `rotation`, `center` | The transform's fields. |

## TextureStore

`assets.textures.add(texture)` returns a `TextureId`. `get(id)` borrows it. `NO_TEXTURE` is the id of no texture, and samples as white.

## Errors

- Dimensions must be positive, and the buffer length must match.
- A wrap, filter, color space or alpha mode that is none of its named values raises. The GPU upload checks again.
- A `checkerboard` size must divide evenly by its square count.
- A `data_texture` with a channel count outside one through four, a length that does not match, or a number that is not finite.
- A `float_texture` with a length that does not match, or a number that is not finite. A float texture that is not `LINEAR`, or a texel type that is none of the two, raises in `validate`.
- The RGBE and EXR readers refuse a file cut short, a malformed header, and each feature in [What is not ported](#what-is-not-ported).
- The renderer refuses a map and an emissive map on one material whose transforms differ.
- An anisotropy below one, or above `MAX_ANISOTROPY`, raises in `validate`.
- A `Footprint` with no taps, or a non-finite level or step, raises in `sample_footprint`.
- See [Cube textures](#cube-textures) for what a cube refuses, and [From a compressed file](#from-a-compressed-file) for what a compressed payload refuses.

## Why

See [Why mipmaps](Why-mipmaps) and [Why color is linear](Why-color-is-linear).
