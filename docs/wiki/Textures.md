# Textures

`render/texture.mojo` and `render/texture_store.mojo`. A `Texture` is an RGBA image with a wrap mode, a filter, a color space, an alpha mode and an optional mip chain. A material names one by id.

![Two checkerboard cubes turn, nearest beside bilinear](out/textured.png)

three.js: `Texture`, `DataTexture`, `DepthTexture`, `CompressedTexture`, `CubeTexture`, `WebGLRenderTarget.texture`, `wrapS`, `wrapT`, `magFilter`, `minFilter`, `generateMipmaps`, `colorSpace`, `anisotropy`.

## Make a texture

```mojo
checkerboard(size, squares, first, second, wrap=REPEAT, filter=BILINEAR, mipmapped=True, alpha=COVERAGE)
texture_from(image, wrap=REPEAT, filter=BILINEAR, color_space=None, mipmapped=True, alpha=COVERAGE)
Texture(width, height, pixels, wrap=REPEAT, filter=BILINEAR, color_space=SRGB, mipmapped=True, alpha=COVERAGE)
data_texture(width, height, numbers, channels=4, wrap=CLAMP, filter=NEAREST, mipmapped=False, alpha=COVERAGE)
texture_of(framebuffer, wrap=CLAMP, filter=BILINEAR, mipmapped=True, alpha=COVERAGE)
depth_texture_of(framebuffer, wrap=CLAMP)
```

`checkerboard` builds a test pattern. `texture_from` takes a `DecodedImage` from the PNG reader. `Texture` takes row-major RGBA bytes from the top. The last three are below.

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

## Anisotropy

A surface seen at a glancing angle covers a footprint that is long one way and short the other. A mip level is square. The level the long axis wants blurs the short axis, and the level the short axis wants sparkles along the long one. `anisotropy`, three.js's `Texture.anisotropy`, is how many samples a fragment can take along the long axis instead, each read at the level the short axis wants.

```mojo
var floor = checkerboard(64, 8, white, blue)
floor.anisotropy = 16
```

One, the default, is the plain trilinear read. Sixteen is what a GPU usually caps it at. Set the field after construction, as in three.js. `validate()` refuses a value below one, and the GPU upload refuses it again.

`anisotropic_footprint(along_x, along_y, width, height, anisotropy)` returns a `Footprint`: the level, the tap count and the step between taps. The tap count is the ratio of the footprint's two lengths, rounded up. It is capped at the anisotropy and at the long axis's length in texels. The level is that of the long axis divided by the count. With one tap the level is what `mip_level` gives, so a texture that asks for nothing reads as it did.

`sample_footprint(u, v, footprint)` takes the taps and averages them premultiplied. Both rasterizers call the same two functions; see [Rasterization](Rasterization).

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

A face is read at its full size, never down a mip chain. A reflection's direction changes across a surface at a rate that is not the surface's own texture footprint. The same rule keeps a matcap out of its chain. A chain can still be built; nothing reads it.

A face must be wrapped `CLAMP`. A coordinate past a face's edge belongs to the next face, and a flat image has no next face to read. The bilinear filter's neighbors at an edge hold that edge.

### CubeTextureStore

`assets.cube_textures.add(cube)` returns a `CubeTextureId`. `get(id)` borrows it. `NO_CUBE_TEXTURE` is the id of no cube texture. `SCENE_ENVIRONMENT` is not an id either: a material naming it reflects the scene's `environment`. See [Materials](Materials#environment-map) and [Scene graph](Scene-graph#background-and-environment).

### Errors

- A cube needs exactly six faces. Each must hold texels, be square, be the size of the others, and be wrapped `CLAMP`.
- `cube_texture_from` refuses a layout that is neither named value, and an empty image. It refuses a file whose color space cannot be interpreted when none is given.
- `validate()` refuses a face edited into nonsense after the cube was built. The GPU upload calls it again.
- The store refuses `NO_CUBE_TEXTURE`, `SCENE_ENVIRONMENT` and any id it does not hold.

`examples/mirror.mojo` builds a sky from six computed faces, renders a cube camera's view every frame, and reflects it in a chrome ball.

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
| `texel(x, y) -> Color` | One stored texel. |
| `is_blank() -> Bool` | The blank texture, which samples as opaque white. |
| `ignoring_alpha() -> Texture` | A copy that ignores its alpha, with its chain rebuilt. |
| `uv_transform() -> Matrix3` | The transform on the coordinates, from the four fields above. |
| `sample_footprint(u, v, footprint) -> FloatColor` | One trilinear sample, or several along a footprint's long axis. See [Anisotropy](#anisotropy). |
| `validate()` | Refuse a wrap, filter, color space or alpha mode that is none of the named values, or an anisotropy below one. |
| `levels`, `width`, `height`, `alpha`, `anisotropy` | The chain length, the base size, the alpha mode and the tap count. |
| `offset`, `repeat`, `rotation`, `center` | The transform's fields. |

## TextureStore

`assets.textures.add(texture)` returns a `TextureId`. `get(id)` borrows it. `NO_TEXTURE` is the id of no texture, and samples as white.

## Errors

- Dimensions must be positive, and the buffer length must match.
- A wrap, filter, color space or alpha mode that is none of its named values raises. The GPU upload checks again.
- A `checkerboard` size must divide evenly by its square count.
- A `data_texture` with a channel count outside one through four, a length that does not match, or a number that is not finite.
- The renderer refuses a map and an emissive map on one material whose transforms differ.
- An anisotropy below one raises in `validate`.
- See [Cube textures](#cube-textures) for what a cube refuses, and [From a compressed file](#from-a-compressed-file) for what a compressed payload refuses.

## Why

See [Why mipmaps](Why-mipmaps) and [Why color is linear](Why-color-is-linear).
