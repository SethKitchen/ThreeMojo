# Image files

`render/png.mojo`, `render/jpeg.mojo`, `render/inflate.mojo`, `render/apng.mojo` and `render/ppm.mojo`. The project writes PNG, APNG and PPM, and reads PNG and JPEG. No compression or image library is involved.

![A triangle turns in an animated PNG](out/spin.png)

three.js: `TextureLoader` for reading. three.js writes nothing; the browser does.

## Formats

| Format | Read | Write | Alpha | Note |
|---|---|---|---|---|
| PNG | Yes | Yes | 8-bit | The default output. |
| APNG | No | Yes | 8-bit | Many frames in one file. The first frame is a plain PNG. |
| PPM | No | Yes | No | Plain text, for reading pixel values in an editor. |
| JPEG | Yes | No | No | Baseline only. See [Read a JPEG](#read-a-jpeg). |

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
| Grayscale, RGB, palette, grayscale with alpha, RGBA, all at 8 bits | 16-bit channels |
| A `tRNS` transparency chunk | Palettes below 8 bits |
| Every row filter | Adam7 interlacing |
| Stored, fixed-Huffman and dynamic-Huffman DEFLATE blocks | |

## Read a JPEG

```mojo
from render.jpeg import decode
from render.texture import texture_from

var photo = decode(Path("assets/photo.jpg").read_bytes())
var skin = assets.textures.add(texture_from(photo, REPEAT, BILINEAR, mipmapped=True))
```

`render/jpeg.mojo`. `decode` returns a `DecodedImage`, as the PNG reader does, always `SRGB`: a JPEG declares no color space, and every viewer assumes that one. No image library is involved.

| Supported | Refused by name |
|---|---|
| Baseline sequential Huffman coding, `SOF0` and `SOF1` at 8 bits | Progressive and arithmetic coding |
| Gray, and YCbCr in three components | Four components, which is CMYK |
| Sampling factors of one or two each way, so 4:4:4, 4:2:2 and 4:2:0 | Twelve bits a sample, and sixteen-bit quantization tables |
| Restart intervals | A scan per component |
| Application and comment segments, skipped | |

### What the decoder computes

The inverse cosine transform is the separable float one, the standard's own definition, rounded once at the end. A chroma component stored at half size is read through the triangle filter the standard recommends, which libjpeg calls fancy upsampling. Two decoders agree on a JPEG to within a level or two and never to the bit. `tests/test_jpeg.mojo` holds this one to two levels of libjpeg's output.

### Integrity checks

The decoder checks that every marker segment fits and that the frame header comes once and before the scan. It checks that every table the scan names was defined and that the scan names the frame's components. It checks that the restart markers arrive in order and that the end marker closes the file. A truncated scan, a code no table defines and a run past a block's end are refused rather than padded.

## Color space of a decoded file

| The file says | `color_space` |
|---|---|
| Nothing | `SRGB` |
| `gAMA` of 100000 | `LINEAR` |
| `gAMA` near 45455 | `SRGB`, as an approximation |
| An ICC profile, or another gamma | `UNKNOWN_SPACE` |

`texture_from` refuses `UNKNOWN_SPACE` unless you pass `color_space=SRGB` or `LINEAR`. The gamma reading is approximate: a pure power differs from the sRGB curve by about a percent at midtones.

## Integrity checks

The decoder checks each chunk's CRC, the zlib Adler-32, and that the output has exactly the size the header promised. It checks chunk order, duplication and length, and it refuses an unknown critical chunk. See [Why the PNG reader checks structure](Why-the-PNG-reader-checks-structure).
