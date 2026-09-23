# Textures

`render/texture.mojo` and `render/texture_store.mojo`. A `Texture` is an RGBA image with a wrap mode, a filter, a color space, an alpha mode and an optional mip chain. It holds bytes, or floats for an HDR image. A material names one by id.

![Two checkerboard cubes turn, nearest beside bilinear](out/textured.png)

three.js: `Texture`, `DataTexture`, `DepthTexture`, `CompressedTexture`, `KTX2Loader`, `KTXLoader`, `DDSLoader`, `CubeTexture`, `Data3DTexture`, `DataArrayTexture`, `WebGLRenderTarget.texture`, `wrapS`, `wrapT`, `magFilter`, `minFilter`, `generateMipmaps`, `colorSpace`, `anisotropy`, `type`, `channel`, `RGBELoader`, `EXRLoader`.

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

`compressed_texture(width, height, data, format, wrap=CLAMP, filter=BILINEAR, color_space=None, mipmapped=False, alpha=COVERAGE)`. The defaults are three.js's own for the class: edges clamped and no chain, since a compressed file usually carries its own levels. Only the level you pass is read. Pass `mipmapped=True` to build a chain from the decoded image.

The S3TC formats are below. See [KTX2 and compressed formats](#ktx2-and-compressed-formats) for the other fourteen formats and for the three container files.

| `format` | three.js | A 4x4 block is |
|---|---|---|
| `RGB_S3TC_DXT1_FORMAT` | `RGB_S3TC_DXT1_Format` | Eight bytes: two RGB565 colors and a two-bit index per texel. The transparent index reads as opaque black. |
| `RGBA_S3TC_DXT1_FORMAT` | `RGBA_S3TC_DXT1_Format` | The same, with the transparent index read as transparent black. |
| `RGBA_S3TC_DXT3_FORMAT` | `RGBA_S3TC_DXT3_Format` | Sixteen bytes: sixteen four-bit alphas, then a color block always read in its four-color order. |
| `RGBA_S3TC_DXT5_FORMAT` | `RGBA_S3TC_DXT5_Format` | Sixteen bytes: two alphas and a three-bit index per texel, then a color block always read in its four-color order. |

The 565 channels widen to eight bits by copying their top bits down, as the hardware widens them. The blends round to nearest. An image need not be whole blocks: the texels past the edge are decoded and dropped. `decode_s3tc` returns the RGBA bytes of an S3TC payload without building a texture. `decode_compressed` does the same for every format.

`compressed_texture` refuses a format that is none of the eighteen, dimensions that are not positive, and a payload whose length is not the block grid's. `tests/compile_fail/` proves a bare integer is not a format.

## KTX2 and compressed formats

`render/compressed_texture.mojo` decodes eighteen block formats. `render/dds.mojo`, `render/ktx.mojo` and `render/ktx2.mojo` read the three container files that three.js reads. Each container gives every level of every face, and a `texture` method decodes one of them. A KTX2 file can also hold Basis Universal data, UASTC or ETC1S, and Zstandard supercompression. This reader decodes both.

three.js: `KTX2Loader`, `KTXLoader`, `DDSLoader`, `CompressedTexture` and the compressed format constants.

```mojo
from render.ktx2 import read as read_ktx2

var container = read_ktx2(Path("rock.ktx2").read_bytes())
var rock = assets.textures.add(container.texture(mipmapped=True))
```

### The formats

A format that a byte cannot hold decodes to floats, and its texture is a float texture. `CompressedFormat.is_float` names these formats. A color format is `SRGB` by default. Every other format holds data, so it is `LINEAR`, and `SRGB` is refused.

| `format` | Block | Decodes to |
|---|---|---|
| `RGB_S3TC_DXT1_FORMAT`, `RGBA_S3TC_DXT1_FORMAT` | BC1, 8 bytes | RGBA bytes |
| `RGBA_S3TC_DXT3_FORMAT` | BC2, 16 bytes | RGBA bytes |
| `RGBA_S3TC_DXT5_FORMAT` | BC3, 16 bytes | RGBA bytes |
| `RED_RGTC1_FORMAT` | BC4, 8 bytes | Red bytes |
| `SIGNED_RED_RGTC1_FORMAT` | BC4 signed, 8 bytes | Red floats, -1 to 1 |
| `RED_GREEN_RGTC2_FORMAT` | BC5, 16 bytes | Red and green bytes |
| `SIGNED_RED_GREEN_RGTC2_FORMAT` | BC5 signed, 16 bytes | Red and green floats, -1 to 1 |
| `RGB_BPTC_UNSIGNED_FORMAT` | BC6H, 16 bytes | RGB half floats, widened |
| `RGB_BPTC_SIGNED_FORMAT` | BC6H signed, 16 bytes | RGB half floats, widened |
| `RGBA_BPTC_FORMAT` | BC7, 16 bytes | RGBA bytes |
| `RGB_ETC1_FORMAT` | ETC1, 8 bytes | RGB bytes |
| `RGB_ETC2_FORMAT` | ETC2, 8 bytes | RGB bytes |
| `RGBA_ETC2_EAC_FORMAT` | EAC alpha and ETC2, 16 bytes | RGBA bytes |
| `R11_EAC_FORMAT`, `SIGNED_R11_EAC_FORMAT` | EAC, 8 bytes | Red floats |
| `RG11_EAC_FORMAT`, `SIGNED_RG11_EAC_FORMAT` | Two EAC blocks, 16 bytes | Red and green floats |

A red or a red-green format gives a blue of zero and an alpha of one, as WebGL samples it. `render/bptc.mojo` holds the BC6H and BC7 decoders, and `render/etc.mojo` holds the ETC and EAC decoders.

- **BC7** blends two endpoints with an exact integer weight. Every decoder gives the same texels. A block whose first byte is zero names no mode and decodes to transparent black.
- **BC6H** has fourteen modes. The endpoints are unquantized to sixteen bits, blended, and read as a half. Four reserved mode numbers decode to black.
- **ETC2** reads an ETC1 block unchanged. A difference that leaves its range selects the T, H or planar mode.
- **EAC R11** keeps eleven bits. A texel is `(base * 8 + 4 + offset * multiplier * 8) / 2047`, or `/ 1023` for the signed form.

The tests check each decoder against hand-built blocks with worked-out texels. They also check blocks of every mode against the reference decoders `bcdec` and `texture2ddecoder`.

### The containers

| Reader | Returns | Reads |
|---|---|---|
| `render.dds.read(bytes)` | `CompressedImage` | A four-character code or a DX10 header, levels and cubes. |
| `render.ktx.read(bytes)` | `CompressedImage` | KTX 1 in both byte orders, levels and cubes. |
| `render.ktx2.read(bytes)` | `KTX2Container` | KTX 2.0: the header, the level index, the data format descriptor, levels, cubes and arrays. |

`CompressedImage.mipmaps` holds each face's levels in turn: `mipmaps[face * levels + level]`. `texture(face, level, ...)` decodes one of them. `KTX2Container.level_data` holds each level with its supercompression removed. `texture(face, layer, level, ...)` decodes one image of it.

The color space comes from the file. A DDS or KTX file is `SRGB` only for a format with sRGB in its name. A KTX2 file is `SRGB` when its data format descriptor names the sRGB transfer function, as three.js reads it.

A KTX2 file can also hold eight-bit, half and float texels. `R8`, `R8G8` and `R8G8B8A8` give a byte texture, in `UNORM` or `SRGB`. `R16`, `R16G16` and `R16G16B16A16` halves, and `R32` to `R32G32B32A32` floats, give a float texture. These are the uncompressed formats three.js reads.

| KTX2 supercompression | Here |
|---|---|
| 0, none | Read. |
| 1, BasisLZ | Read for ETC1S data through `render/etc1s.mojo`. BasisLZ holds only ETC1S. |
| 2, Zstandard | Read through `render/zstd.mojo`. |
| 3, zlib | Read through `render/inflate.mojo`. three.js refuses it. |

### Basis Universal

A KTX2 file whose data format descriptor names the UASTC or the ETC1S color model holds Basis Universal data. Its Vulkan format is `VK_FORMAT_UNDEFINED`. three.js transcodes the data to a GPU format with the Basis Universal WebAssembly transcoder. Here `texture` decodes it to an RGBA byte texture. The texels are the texels that transcoder gives for its `RGBA32` target.

```mojo
var container = read_ktx2(Path("rock_uastc.ktx2").read_bytes())
if container.is_uastc() or container.is_etc1s():
    var rock = assets.textures.add(container.texture(level=0))
```

| Data | Module | How it decodes |
|---|---|---|
| UASTC LDR 4x4 | `render/uastc.mojo` | One 16-byte block for each 4x4 texels. A prefix code names one of nineteen modes. The mode sets the subsets, the planes, the components and the endpoint and weight ranges. The endpoints unquantize and blend as ASTC blends them. |
| ETC1S | `render/etc1s.mojo` | The BasisLZ global data holds an endpoint codebook, a selector codebook and four Huffman tables. Each image is a slice of Huffman-coded codebook indices, with predictions from the neighbor blocks and a history of recent selectors. A file with alpha has a second slice per image, and its green is the alpha. |

The two modules port the transcoder of Binomial's Basis Universal, which is Apache-2.0. [THIRD-PARTY-NOTICES.md](https://github.com/SethKitchen/ThreeMojo/blob/main/THIRD-PARTY-NOTICES.md) holds its notice. A UASTC level can be stored whole, or supercompressed with Zstandard or zlib.

The tests decode files that the Basis Universal 2.50 encoder wrote. Between them, the UASTC files use all nineteen modes. The ETC1S files have alpha, mipmaps, sizes that are not a multiple of four, and gray endpoints. Every level must have the same texels as the three.js r186 transcoder gives.

### Zstandard

`render/zstd.mojo` decodes Zstandard, RFC 8878, with no compression library. `zstd_decompress(bytes, limit)` returns the bytes of every frame, joined. A KTX2 level with scheme 2 is one Zstandard frame, and `read` decompresses it to its stated size.

The decoder reads the whole format except dictionaries:

- Raw, RLE and compressed blocks, and skippable frames.
- Raw, RLE, Huffman and treeless literals, in one stream or in four.
- Huffman weights, direct or coded with an FSE table.
- Sequences with predefined, single-symbol, described and repeated FSE tables.
- The three repeated offsets, and the checksum, an XXH64 of the content.

The tests decode frames that libzstd 1.5.7 wrote at levels -5 to 19. Frames built by hand cover the modes libzstd rarely writes. libzstd decodes the same bytes from them.

### What is not ported

- UASTC HDR, in its 4x4 and 6x6 forms, and XUASTC. A file with those color models is refused as a format this reader does not decode.
- The transcode from UASTC or ETC1S to a GPU block format. Each image decodes to RGBA bytes, as the transcoder's `RGBA32` target gives them.
- ETC1S video. A KTX2 file whose images include a P-frame is refused.
- Zstandard dictionaries. A frame that names a dictionary is refused. A KTX2 file never names one.
- ASTC, PVRTC and ETC2 with punch-through alpha. Each container refuses them by name. three.js uploads ASTC and PVRTC as they are.
- Uncompressed DDS files, the premultiplied DXT2 and DXT4, and DDS texture arrays.
- 1D, 3D and array textures in KTX 1, and 1D and 3D textures in KTX2.
- The GPU upload of the blocks. Each image decodes on the host and keeps RGBA in memory.
- A file's own smaller levels in the texture. The container gives them, but a texture builds its chain from the level it decodes.
- `CompressedCubeTexture` and `CompressedArrayTexture`. Take each face or layer with `texture(face, layer)`.

### Where the formats differ from three.js

- three.js hands the blocks to the GPU. Here the decoded texels are what the hardware gives, to the last bit for BC6H, BC7, ETC and EAC. The BC1 to BC5 blends round to nearest, as the reference decoder rounds them. A GPU can differ by one step.
- The eleven-bit EAC formats and the signed RGTC formats decode to floats. A byte cannot hold a negative value or eleven bits.
- DDSLoader computes a level's size from `max(4, width) / 4`, which is a fraction for a width that is not a multiple of four. This reader rounds up to whole blocks.
- A container is refused if it names more levels than its size has, or a face count other than one or six. A level that does not fit is refused too. three.js reads past such a file.
- three.js transcodes Basis Universal data to a GPU format, and hands that to the GPU. Here UASTC and ETC1S decode to the `RGBA32` texels of the same transcoder. A GPU that samples the transcoded blocks can differ from them by a step.
- A Zstandard repeated offset of zero is refused. libzstd reads it as one.
- An ETC1S Huffman code of one symbol matches only its own bit. Binomial's decoder reads any other bit as that symbol.

### Errors

- Each container refuses a wrong identifier or magic, a size that is not positive, and a file that ends early.
- A size that decodes to more than `MAX_DECODED_BYTES` is refused before any allocation. A float format counts sixteen bytes a texel.
- A KTX2 file refuses a descriptor or a level outside the file, and a level whose length is not its size.
- A KTX2 half or float format with the sRGB transfer function is refused.
- A KTX2 file with ETC1S data must use BasisLZ, and BasisLZ must hold ETC1S. Basis Universal data must name no Vulkan format.
- The BasisLZ global data must fit in the file and hold what its header states. A codebook or a table that is empty or malformed is refused.
- `texture` refuses a UASTC block with the reserved mode or a partition its mode does not have. It refuses an ETC1S slice that predicts from outside the image or reads past its codebooks.
- `zstd_decompress` refuses a frame that is cut short, has a reserved bit or type, or does not match its size or its checksum. It refuses a malformed table or bitstream, and a stream that expands past `limit`.
- `tests/compile_fail/` proves that a bare integer is not a `VkFormat` or a `Supercompression`.

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

## 3D textures

`render/volume_texture.mojo`. A `Data3DTexture` is a volume of texels, `width` by `height` by `depth`, sampled by three coordinates. It is three.js's `Data3DTexture`, read as a GLSL `sampler3D` reads it. A color lookup table is one: see [Post-processing](Post-processing#lut).

three.js: `Data3DTexture`, `wrapR`, `texture` and `texelFetch` on a `sampler3D`.

```mojo
var image = VolumeImage.of_floats(16, 16, 16, densities, channels=1)
var volume = Data3DTexture(image^, wrap=CLAMP, filter=BILINEAR)
var id = assets.data_3d_textures.add(volume^)
var color = assets.data_3d_textures.get(id).sample(0.5, 0.5, 0.25)
```

### The image

A `VolumeImage` holds the texels. It is three.js's `texture.image`, `{ data, width, height, depth }`. The first coordinate changes fastest, then the second, then the third.

| Builder | three.js | Meaning |
|---|---|---|
| `VolumeImage.of_bytes(width, height, depth, bytes, channels=4)` | `UnsignedByteType` | One through four bytes a texel. |
| `VolumeImage.of_floats(width, height, depth, floats, channels=4)` | `FloatType` | One through four finite floats a texel. |

A texel with fewer than four channels fills red first. A color channel that it does not reach is zero. A missing alpha is one. That is how WebGL samples a `RedFormat` or an `RGFormat` texture. The image is stored as RGBA.

### The texture

`Data3DTexture(image, wrap=CLAMP, filter=NEAREST, color_space=LINEAR)` takes three.js's defaults. The fields are `image`, `wrap_s`, `wrap_t`, `wrap_r`, `filter` and `color_space`. The constructor sets all three wrap modes to `wrap`. Set one field afterward to make the axes differ.

| Member | GLSL | Meaning |
|---|---|---|
| `sample(s, t, r) -> FloatColor` | `texture(sampler3D, vec3)` | The color at a coordinate. |
| `texel_fetch(x, y, z) -> FloatColor` | `texelFetch(sampler3D, ivec3, 0)` | The texel at an index. |
| `validate()` | | Refuse a field edited into nonsense. |

Under `NEAREST`, `sample` returns the texel that the coordinate lands in. Under `BILINEAR`, three.js's `LinearFilter`, it blends the eight texels around the coordinate. Texel centers are at half-integers. Each index is wrapped on its own axis by `wrap_s`, `wrap_t` or `wrap_r`.

A byte is read as a fraction of 255. With `SRGB`, the three color channels are decoded through the sRGB curve, and alpha is not. A float is read as it is.

### Where the 3D textures differ from the 2D texture

- **The rows run up.** three.js sets `flipY` to false for both kinds, and WebGL does not flip a 3D upload. Texel `(0, 0, 0)` is at the coordinate origin. A 2D `Texture` reads its first row at the top.
- **The filter is straight.** GLSL blends each stored channel on its own, and so does this port. A 2D `Texture` blends premultiplied, because its alpha is coverage. The fourth channel of a volume is often density or data.
- **There is no mip chain.** three.js turns `generateMipmaps` off for both kinds. One filter serves both magnification and minification.

## Array textures

`render/volume_texture.mojo`. A `DataArrayTexture` is a stack of images of one size, sampled by two coordinates and a layer number. It is three.js's `DataArrayTexture`, read as a GLSL `sampler2DArray` reads it.

three.js: `DataArrayTexture`, `texture` and `texelFetch` on a `sampler2DArray`.

```mojo
var image = VolumeImage.of_bytes(64, 64, 8, frames)
var stack = DataArrayTexture(image^, wrap=REPEAT, filter=BILINEAR, color_space=SRGB)
var id = assets.data_array_textures.add(stack^)
var color = assets.data_array_textures.get(id).sample(0.5, 0.5, 3)
```

The image is a `VolumeImage`. Its `depth` is the number of layers. `DataArrayTexture(image, wrap=CLAMP, filter=NEAREST, color_space=LINEAR)` takes three.js's defaults. The fields are `image`, `wrap_s`, `wrap_t`, `filter` and `color_space`.

| Member | GLSL | Meaning |
|---|---|---|
| `sample(u, v, layer) -> FloatColor` | `texture(sampler2DArray, vec3)` | The color at a coordinate in one layer. |
| `texel_fetch(x, y, layer) -> FloatColor` | `texelFetch(sampler2DArray, ivec3, 0)` | The texel at an index. |
| `layers() -> Int` | `image.depth` | How many layers there are. |
| `validate()` | | Refuse a field edited into nonsense. |

`array_layer(layer, depth)` finds the layer that `sample` reads. It rounds the coordinate to the nearest whole number, and a half rounds up. Then it holds the result inside the stack. That is the OpenGL rule. A sample never blends two layers. Within the layer, the filter and the wrap modes work as they do for a [3D texture](#3d-textures).

### The stores

`assets.data_3d_textures.add(texture)` returns a `Data3DTextureId`. `assets.data_array_textures.add(texture)` returns a `DataArrayTextureId`. `get(id)` borrows the texture. `NO_DATA_3D_TEXTURE` and `NO_DATA_ARRAY_TEXTURE` are the ids of no texture.

The two ids are types. A bare number does not compile. `tests/compile_fail/` proves it.

### Errors of the 3D and array textures

- `of_bytes` and `of_floats` refuse a dimension that is not positive. They refuse a channel count outside one through four, and a length that does not match.
- `of_floats` refuses a number that is not finite.
- `validate` refuses a wrap mode, a filter, a color space or a texel type that is not named. It refuses `UNKNOWN_SPACE`, and a float image that is not `LINEAR`. It refuses an image whose length does not match its dimensions.
- `texel_fetch` refuses an index outside the image. GLSL leaves that result undefined.
- The stores refuse the "no texture" ids and any id that they do not hold.

### Not ported in the 3D and array textures

- The GPU backend samples neither kind. three.js reads them only from a custom shader or from `LUTPass`, and this port has no custom shaders.
- `layerUpdates`, `addLayerUpdate` and `unpackAlignment` control the upload to WebGL. They have no counterpart here.
- Mip chains, separate `magFilter` and `minFilter`, and the formats other than red, RG, RGB and RGBA.

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

`channel`, three.js's `Texture.channel`, says which set of the geometry's coordinates a texture reads. `UV_CHANNEL_0`, the default, reads `uv`. `UV_CHANNEL_1` reads `uv1`. Only an ambient occlusion map or a light map can read the second set. See [Light map](Materials#light-map).

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
| `validate()` | Refuse a wrap, filter, color space, alpha mode, texel type or channel that is none of the named values, a float texture that is not `LINEAR`, or an anisotropy below one or above `MAX_ANISOTROPY`. |
| `levels`, `width`, `height`, `alpha`, `anisotropy` | The chain length, the base size, the alpha mode and the tap count. |
| `channel` | Which coordinates the texture reads: `UV_CHANNEL_0` or `UV_CHANNEL_1`. |
| `texel_type`, `pixels`, `data` | `UNSIGNED_BYTE_TYPE` with bytes in `pixels`, or `FLOAT_TYPE` with floats in `data`. See [HDR images](#hdr-images). |
| `offset`, `repeat`, `rotation`, `center` | The transform's fields. |

## TextureStore

`assets.textures.add(texture)` returns a `TextureId`. `get(id)` borrows it. `NO_TEXTURE` is the id of no texture, and samples as white.

## Errors

- Dimensions must be positive, and the buffer length must match.
- A wrap, filter, color space, alpha mode or channel that is none of its named values raises. The GPU upload checks again.
- A `checkerboard` size must divide evenly by its square count.
- A `data_texture` with a channel count outside one through four, a length that does not match, or a number that is not finite.
- A `float_texture` with a length that does not match, or a number that is not finite. A float texture that is not `LINEAR`, or a texel type that is none of the two, raises in `validate`.
- The RGBE and EXR readers refuse a file cut short, a malformed header, and each feature in [What is not ported](#what-is-not-ported).
- The renderer refuses a map and an emissive map on one material whose transforms differ.
- An anisotropy below one, or above `MAX_ANISOTROPY`, raises in `validate`.
- A `Footprint` with no taps, or a non-finite level or step, raises in `sample_footprint`.
- See [Cube textures](#cube-textures) for what a cube refuses, and [KTX2 and compressed formats](#ktx2-and-compressed-formats) for what a compressed payload or container refuses.

## Why

See [Why mipmaps](Why-mipmaps) and [Why color is linear](Why-color-is-linear).
