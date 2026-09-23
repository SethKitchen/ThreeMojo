# Image files

`render/png.mojo`, `render/jpeg.mojo`, `render/tga.mojo`, `render/rgbe.mojo`, `render/exr.mojo`, `render/inflate.mojo`, `render/apng.mojo` and `render/ppm.mojo`. The project writes PNG, APNG and PPM, and reads PNG, JPEG, TGA, Radiance HDR and OpenEXR. No compression or image library is involved.

![A triangle turns in an animated PNG](out/spin.png)

three.js: `TextureLoader` for reading PNG and JPEG, and `TGALoader` for TGA. three.js writes nothing; the browser does.

## Formats

| Format | Read | Write | Alpha | Note |
|---|---|---|---|---|
| PNG | Yes | Yes | 8-bit | The default output. |
| APNG | No | Yes | 8-bit | Many frames in one file. The first frame is a plain PNG. |
| PPM | No | Yes | No | Plain text, for reading pixel values in an editor. |
| JPEG | Yes | No | No | Baseline and progressive. See [Read a JPEG](#read-a-jpeg). |
| TGA | Yes | No | 8-bit | See [Read a TGA](#read-a-tga). |
| Radiance HDR | Yes | No | No | Linear floats. See [HDR images](Textures#hdr-images). |
| OpenEXR | Yes | No | Float | Linear floats. See [HDR images](Textures#hdr-images). |

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
| Baseline sequential Huffman coding, `SOF0` and `SOF1` at 8 bits | Arithmetic coding |
| Progressive Huffman coding, `SOF2`: spectral selection and successive approximation | Twelve bits a sample, and sixteen-bit quantization tables |
| Gray, and YCbCr in three components numbered one, two and three as JFIF numbers them | Four components, which is CMYK, and three numbered any other way |
| 4:4:4, 4:2:2 and 4:2:0 | Other sampling factors |
| Restart intervals, in sequential and progressive scans | |
| A scan of every component, or a scan per component | |
| Application and comment segments, skipped | |

### Progressive files

A progressive file sends the same quantized coefficients as a baseline file, in pieces. The decoder reads every scan into one store of coefficients. It transforms the store once, after the end marker. A baseline file goes through the same store in one scan. A progressive file and its baseline twin at the same quality decode to the same samples, bit for bit. `tests/test_jpeg.mojo` checks this for 4:2:0, 4:2:2, 4:4:4, gray and restart intervals.

The decoder reads the four kinds of progressive scan:

| Scan | What it sends |
|---|---|
| DC first | The high bits of each block's DC coefficient, as a difference from the last block's. |
| DC refinement | One more bit of each DC coefficient, raw. |
| AC first | The high bits of a band of AC coefficients of one component, with end-of-band runs that span blocks. |
| AC refinement | One more bit of a band: a correction bit for each nonzero coefficient, and new coefficients of one bit. |

The decoder checks the order of the scans. A coefficient's first bits must come before its refinements, and each refinement must add exactly one bit. The AC scans of a component must come after its first DC scan. Every component must be in some scan. A file that breaks one of these rules is refused.

### What the decoder computes

The inverse cosine transform is the separable float one, the standard's own definition, rounded once at the end. A chroma component stored at half size is read through a triangle filter. The standard leaves the reconstruction filter to the decoder, and this one uses the filter libjpeg calls fancy upsampling so that the two agree. At the right and bottom edges, the filter repeats the component's last real sample, as libjpeg does. It does not read the encoder's padding.

Two decoders agree on a JPEG to within a level or two and never to the bit. `tests/test_jpeg.mojo` holds this one to two levels of libjpeg's output. One checkered test picture with sharp chroma edges is held to three levels.

### Integrity checks

The decoder checks that every marker segment fits and that the frame header comes once and before the scans. It checks that every table a scan names was defined and holds no zero, and that each scan names components the frame has. It checks that the restart markers arrive in order and that the end marker closes the file. A truncated scan, a code no table defines and a run past a block's end are refused rather than padded.

## Read a TGA

```mojo
from render.tga import decode
from render.texture import texture_from

var image = decode(Path("assets/skin.tga").read_bytes())
var skin = assets.textures.add(texture_from(image, REPEAT, BILINEAR))
```

`render/tga.mojo`. `decode` returns a `DecodedImage`, as the PNG and JPEG readers do, always `SRGB`. The rows run from the top down, whichever corner the file starts at. The reader follows three.js's `TGALoader`.

| Image type | Pixel sizes | Note |
|---|---|---|
| Color-mapped, 1, and run-length color-mapped, 9 | 8-bit indices | The map holds at most 256 entries of 24 bits. |
| True color, 2, and run-length true color, 10 | 24 and 32 bits | A 32-bit pixel carries its alpha. |
| Gray, 3, and run-length gray, 11 | 8 and 16 bits | A 16-bit pixel is a level and an alpha. |

The descriptor byte gives the origin. The reader reads all four corners: bottom left, bottom right, top left and top right. It does not read the attribute bits, and three.js does not read them either. It ignores the image id and the TGA 2.0 footer.

### Where the TGA reader differs from three.js

- The reader refuses 16-bit true color by name. three.js reads the attribute bit as alpha with the opposite meaning from what writers use.
- The reader applies the color map's first entry index. three.js ignores it.
- The reader refuses an index past the color map, a packet past the image and a file that ends early. three.js reads these as whatever its array holds.

`decode_image` in `loaders/gltf.mojo` reads a TGA when the bytes are neither PNG nor JPEG. A TGA has no signature, so the header check alone tells a TGA from other bytes. glTF names only PNG and JPEG, so this fallback is an addition of this port.

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
