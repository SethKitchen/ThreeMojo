# SOG files

`extensions/scan/sog.mojo` reads SOG files, PlayCanvas's compressed Gaussian splats, into a `ScanScene`: a `GaussianSplatGeometry` and the scene's `SplatModel`. SuperSplat publishes its scenes in this format. The reader decodes each field as `readSog` in `@playcanvas/splat-transform` 3.10.1 does. So a SOG scene gives the splats of the PLY file that splat-transform writes from it.

![A building model fitted to a scan of a two-storey room, turning](out/scanned-buildings.png)

The reader is the first step of [Scanned buildings](Scanned-buildings). A `GaussianSplat` draws the geometry as any other; see [Gaussian splats](Gaussian-splats).

## Read a scene

```mojo
var scene = read_sog("scan.sog")                  # a bundle
var other = read_sog("scan/meta.json")           # a folder
var splats = scene.geometry.copy()
var model = scene.model                          # SPLAT_DEFAULT, SPLAT_ANTIALIASED or SPLAT_2DGS
```

`read_sog` reads a `.sog` bundle when the path ends in `.sog`. It reads any other path as a `meta.json` text, with the images beside it. `parse_sog(meta, files)` reads a text and a list of `SogFile` records. `parse_sog_bundle(bytes)` reads the bytes of a bundle. `sog_file_names(meta)` gives the names of the images that a text needs.

## The format

A SOG scene is a `meta.json` text and lossless WebP images. The images are files beside the text, or members of one ZIP file, a `.sog` bundle. Each texel of an image holds one splat, in reading order from the top left.

| Image | What each texel holds |
|---|---|
| `means_l`, `means_u` | The low and high bytes of a 16-bit number for x, y and z |
| `quats` | The three smallest components of the rotation, and the index of the largest |
| `scales` | Three indexes into the 256 logarithms of the scales codebook |
| `sh0` | Three indexes into the zeroth-band codebook, and the opacity |
| `shN_labels` | A 16-bit index into the harmonics palette |
| `shN_centroids` | The palette: 64 entries a row, one texel a coefficient |

- **Centers.** The 16-bit number places `sign(v) * ln(|v| + 1)` between the text's `mins` and `maxs`. A range of zero counts as one.
- **Rotations.** Each stored component is `byte / 255 * 2 - 1`, divided by the square root of two. The fourth byte, 252 to 255, names the largest component of w, x, y and z. That component is positive and makes the rotation a unit. Another fourth byte gives no rotation.
- **Opacity.** The fourth byte of `sh0` is `sigmoid(opacity) * 255`.
- **Harmonics.** A palette of `count` entries of 3, 8 or 15 coefficients for 1, 2 or 3 bands. The red, green and blue bytes of each centroid texel index the harmonics codebook. A label past the palette gives zero coefficients. A row past the end of the centroid image gives codebook entry zero, as in splat-transform.

The reader rounds each field to `Float32` where splat-transform does. It then builds the splats as `loaders.gaussian_splat_ply` builds them from a PLY file.

## What is refused

- A version 1 text, which has no `version`, and a version other than 2.
- A count below one, and a `model` other than `default`, `antialiased` or `2dgs`.
- A codebook that is not 256 finite numbers, and a section or a `files` list that is missing.
- An image with fewer texels than splats, and harmonics centroids that are not 64 entries wide.
- A file name with a folder in it, so a downloaded text cannot read outside its folder.
- A missing file, and anything that `render.webp.decode` and `loaders.zip.unzip` refuse.

ThreeMojo draws every model as a 3D Gaussian. `ScanScene.model` keeps the text's model, so a caller can tell an antialiased or a 2D Gaussian scene apart. `extensions/scan/scene.mojo` holds `SplatModel` and `ScanScene`, which every scan reader gives; see [Compressed PLY files](Compressed-PLY-files).

## Test files

`assets/sog/make_sog.mjs` writes the test files with splat-transform 3.10.1. It writes degree 3 harmonics as a bundle and as a folder, and degree 1 and 2 as bundles. It also writes a degree 0 folder whose z has no range. It reads each one back with the same tool into a `_restored.ply` file. `tests/test_scan_sog.mojo` requires the same centers, covariances, color bytes and harmonics bytes from both, with the helpers of `tests/_splat_same.mojo`. `assets/fixture-manifest.json` records the files' sums and the commands that write them.
