# Compressed PLY files

`extensions/scan/compressed_ply.mojo` reads compressed PLY files, PlayCanvas's packed Gaussian splats, into a `ScanScene`. SuperSplat writes this format, often as `.compressed.ply`. The reader decodes each field as `readPly` in `@playcanvas/splat-transform` 3.10.1 does. So a compressed file gives the splats of the PLY file that splat-transform writes from it, to the bit.

A [scanned building](Scanned-buildings) can be a compressed PLY file. `examples/scan_parts.mojo` takes the path of one, and cuts it into [parts](Scan-parts).

## Read a file

```mojo
var scene = read_compressed_ply("scan.compressed.ply")
var splats = scene.geometry.copy()      # the splats and their bands
var model = scene.model                 # SPLAT_DEFAULT, from the comments
```

`parse_compressed_ply(bytes)` reads the bytes of a file. `is_compressed_ply(bytes)` tells a compressed file from a plain splat PLY by its header. `extensions/scan/files.mojo` calls both when it reads a file of any format; see [Scan files](#scan-files).

## The format

A compressed PLY file is a binary little-endian PLY file with two or three elements:

| Element | Rows | What a row holds |
|---|---|---|
| `chunk` | One for each 256 splats | The least and the most of the chunk's centers and scale logarithms, and of its colors when it has them |
| `vertex` | One for each splat | Four 32-bit words: `packed_position`, `packed_rotation`, `packed_scale` and `packed_color` |
| `sh` | One for each splat, or none | 9, 24 or 45 bytes, `f_rest_0` and on |

- **Centers and scales.** A word holds 11, 10 and 11 bits for x, y and z, from the top bit down. Each is a fraction of the way from the chunk's least to its most.
- **Rotations.** The top two bits name the largest of w, x, y and z. The other three are 10-bit numbers, each `(n / 1023 - 0.5) * sqrt(2)`. The largest makes the rotation a unit.
- **Colors.** A byte each for red, green, blue and opacity, from the top byte down. A color byte is a fraction `c` of 255, or of the chunk's color range when the chunk has one. The zeroth band is `(c - 0.5) / SH_C0`. The opacity's logit is `-ln(1 / a - 1)`, so a byte of 0 gives no opacity and 255 gives full opacity.
- **Harmonics.** A byte `b` is `(n - 0.5) * 8`, with `n` 0 for 0, 1 for 255, and `(b + 0.5) / 256` for the others.

The reader rounds each field to `Float32` where splat-transform does. It uses splat-transform's own constants: its `SH_C0` is one unit in the last place from three.js's.

The header's comments name the splat model, as `extensions/scan/scene.mojo` reads them. Brush writes `SplatRenderMode: default`, `mip` or `2dgs`. Postshot writes `antialiased 0` or `1`.

## What is refused

- A header that is not PLY, that has a list property, or that counts more than 4,294,967,295 rows.
- A file whose `vertex` element has no `packed_position`. Read a plain splat PLY with `loaders.gaussian_splat_ply`.
- A format other than binary little-endian.
- A file with no `chunk` element, or with a missing `packed` word, chunk bound or color bound.
- A `packed` word that is not a `uint`, and an `sh` byte that is not a `uchar`.
- A count of chunks that is not one for each 256 splats.
- A count of `sh` bytes that is not 0, 9, 24 or 45, and an `sh` element with another count of rows.
- No splats, and a file shorter than its header says.

## No strings

The reader keeps byte ranges of the header, and no text. The WebAssembly build of the C ABI's splat app has no strings, so this is what lets a browser read a compressed scan. See [C ABI and hosts](C-ABI-and-hosts).

## Scan files

`read_scan(path)` reads a scan file of any format into a `ScanScene`, and `parse_scan(bytes, format)` reads its bytes. `scan_format(name, bytes)` tells the formats apart:

| Format | How it is told | Reader |
|---|---|---|
| `SCAN_SOG` | `PK`, 3 and 4: a ZIP file | [SOG files](SOG-files) |
| `SCAN_SOG_FOLDER` | A name that ends in `meta.json` | [SOG files](SOG-files) |
| `SCAN_COMPRESSED_PLY` | `ply`, and `packed_position` in its header | This page |
| `SCAN_PLY` | `ply` | `loaders.gaussian_splat_ply` |
| `SCAN_SPZ` | gzip's 31 and 139, or `NGSP` | `loaders.spz` |
| `SCAN_KSPLAT` | A name that ends in `.ksplat` | `loaders.ksplat` |
| `SCAN_SPLAT` | A name that ends in `.splat` | `loaders.splat` |

The first bytes come before the name. Every format but SPZ holds the axes of the Gaussian splatting training code: x to the right, y down and z forward. `ScanFormat.y_down` says which, so that a viewer can stand a scan up.

## Test files

`assets/compressed_ply/make_compressed_ply.mjs` writes the test files with splat-transform 3.10.1, and reads each one back into a `_restored.ply` file. It writes degree 3 over three chunks, degree 2, 1 and 0, and a degree 1 file without the chunks' color bounds. `tests/test_scan_compressed_ply.mojo` requires the same centers, covariances, color bytes and harmonics bytes from each pair. `assets/fixture-manifest.json` records the files' sums and the commands that write them.
