# Image files

`render/png.mojo`, `render/inflate.mojo`, `render/apng.mojo` and `render/ppm.mojo`. The project writes PNG, APNG and PPM, and reads PNG. No compression library is involved.

three.js: `TextureLoader` for reading. three.js writes nothing; the browser does.

## Formats

| Format | Read | Write | Alpha | Note |
|---|---|---|---|---|
| PNG | Yes | Yes | 8-bit | The default output. |
| APNG | No | Yes | 8-bit | Many frames in one file. The first frame is a plain PNG. |
| PPM | No | Yes | No | Plain text, for reading pixel values in an editor. |

## Write a PNG

```mojo
from render.png import encode
Path("out/frame.png").write_bytes(encode(framebuffer))
```

The encoder uses DEFLATE's stored blocks, so the file is larger than a compressed one and legal everywhere.

## Write an APNG

```mojo
from render.apng import encode
Path("out/turn.png").write_bytes(encode(frames, delay_ms=60))
```

`frames` is a `List[Framebuffer]` of one size. The encoder raises for an empty list or a frame of a different size.

## Write a PPM

```mojo
from render.ppm import to_stdout
to_stdout(framebuffer)
```

## Read a PNG

```mojo
from render.png import decode
from render.texture import texture_from

var image = decode(Path("assets/brick.png").read_bytes())
var skin = assets.textures.add(texture_from(image, REPEAT, BILINEAR, mipmapped=True))
```

`decode` returns a `DecodedImage`: `width`, `height`, RGBA `pixels`, and a `color_space`.

| Supported | Refused by name |
|---|---|
| Greyscale, RGB, palette, greyscale with alpha, RGBA, all at 8 bits | 16-bit channels |
| A `tRNS` transparency chunk | Palettes below 8 bits |
| Every row filter | Adam7 interlacing |
| Stored, fixed-Huffman and dynamic-Huffman DEFLATE blocks | |

## Colour space of a decoded file

| The file says | `color_space` |
|---|---|
| Nothing | `SRGB` |
| `gAMA` of 100000 | `LINEAR` |
| `gAMA` near 45455 | `SRGB`, as an approximation |
| An ICC profile, or another gamma | `UNKNOWN_SPACE` |

`texture_from` refuses `UNKNOWN_SPACE` unless you pass `color_space=SRGB` or `LINEAR`. The gamma reading is approximate: a pure power differs from the sRGB curve by about a percent at midtones.

## Integrity checks

The decoder checks each chunk's CRC, the zlib Adler-32, and that the output has exactly the size the header promised. It checks chunk order, duplication and length, and it refuses an unknown critical chunk. See [Why the PNG reader checks structure](Why-the-PNG-reader-checks-structure).
