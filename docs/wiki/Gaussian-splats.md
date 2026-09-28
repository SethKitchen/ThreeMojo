# Gaussian splats

A Gaussian splat is a small 3D Gaussian with a color and an opacity. Many of them make a scene that a 3D Gaussian Splatting trainer made from photos. This port reads the four splat file formats and the glTF extension, and draws the splats on both rasterizers. It follows three.js r186: `examples/jsm/objects/GaussianSplat.js`, the splat loaders and `utils/GaussianSplatUtils.js`.

```mojo
var scene = Scene()
var node = scene.add(Object3D())
scene.update()
var splat = GaussianSplat(read_spz("garden.spz"), node)
var target = RenderTarget(640, 480, Color(0, 0, 0))
renderer.render_into(target, scene, assets, camera)
draw_gaussian_splat(target, scene, splat, camera)
var image = target.resolve()
```

## The data

`core/gaussian_splat_utils.mojo` holds the splats in a `GaussianSplatGeometry`. Each splat has these fields:

| Field | What |
|---|---|
| `centers` | Three floats: the center. |
| `covariances` | Six floats: `c00 c01 c02 c11 c12 c22`, the upper triangle of the 3D covariance. |
| `colors` | Four bytes: red, green, blue and opacity. A byte `b` is `b / 255`. |
| `sh1`, `sh2`, `sh3` | The bytes of the higher spherical harmonics bands. A byte `b` is `(b - 128) / 128`. |

A band of degree `d` has `2d + 1` coefficients, with three channels each. The bytes of one splat hold one coefficient after the other, and red, green and blue in each. `sh_band_words(d)` gives the 32-bit words of one splat in a band: 3, 4 or 6. `band_words` gives the words as three.js packs them.

`create_gaussian_splat_geometry` checks the lengths. It refuses a band that has no band below it. `to_buffer_geometry` and `gaussian_splat_geometry_of` convert to and from three.js's splat `BufferGeometry`.

The file formats keep a scale and a rotation. `write_covariance` makes the covariance from them, as three.js does. It composes `M = R S` and writes `M M^T`. It calculates in 64-bit floats and keeps 32-bit floats. `clamped_byte` stores a number as a `Uint8ClampedArray` stores it: clamped, and rounded half to even.

## The object

`objects/gaussian_splat.mojo` has `GaussianSplat`. It holds the geometry and the scene node that places it.

- `compute_bounding_box` and `compute_bounding_sphere` grow each splat by two standard deviations of its widest axis.
- `raycast(world, raycaster)` finds where a ray meets the ellipsoid of each splat at two standard deviations. It skips a splat with an opacity below 0.2. It returns one `SplatHit` for each splat that the ray meets, with the distance as a `Length`.
- `update_sort(world, view, near)` sorts the splats from far to near into `order`. It uses 4096 depth bins and a stable counting sort, as three.js's CPU sort does. It sorts again only when the view direction turns by more than the threshold of three.js.
- `spherical_harmonics_colors(camera)` gives the view-dependent color of each splat for a camera position in the object's space.

## The draw

`render/splat_raster.mojo` draws a `GaussianSplat` into a `RenderTarget`. Do these steps to draw a scene with splats:

1. Call `Renderer.render_into` to draw the meshes, lines and points into the target.
2. Call `draw_gaussian_splat` for each `GaussianSplat`.
3. Call `RenderTarget.resolve` to make the image.

`prepare_gaussian_splat` sorts the splats when `auto_sort` is on. It adds the spherical harmonics to the colors. Then it projects each splat with `render/splatrule.mojo`. `rasterize_splats` blends the projected splats in draw order.

The projection is the vertex shader of three.js. The 3D covariance goes into view space, and the Jacobian of the perspective divide takes it onto the screen. The 2D covariance gets 0.3 pixels squared on its diagonal. The opacity is scaled by `sqrt(det / det')`, so the filter does not make a splat brighter. The axes of the ellipse are the eigenvectors of the 2D covariance.

The fragment is the fragment shader of three.js. A pixel center has an offset of `u` and `v` standard deviations along the two axes. The pixel is discarded where `u^2 + v^2` is more than 4. Other pixels get the opacity `a exp(-(u^2 + v^2) / 2)`.

A splat blends source over with straight alpha. It tests depth with less-or-equal and writes no depth. So an opaque surface in front of a splat hides it, and the splat hides nothing behind it.

A splat is not drawn when its center is behind the camera or outside the near and far planes. It is also not drawn more than 1.4 `w` to a side.

## The GPU

`render.gpu.GpuSplats` draws the same list on the device, with one thread for each pixel. The thread walks the splats in draw order. The host and the device share `splat_alpha` and `splat_depth_passes`, so the two images agree. `tests/test_gpu.mojo` compares them pixel by pixel.

```mojo
var device = GpuSplats()
device.draw_gaussian_splat(target, scene, splat, camera)
```

## The file formats

| Format | Reader | What it is |
|---|---|---|
| `.splat` | `loaders/splat.mojo`: `read_splat`, `parse_splat` | Rows of 32 bytes: a center, a scale, a color and a rotation in bytes. |
| `.ksplat` | `loaders/ksplat.mojo`: `read_ksplat`, `parse_ksplat` | GaussianSplats3D sections, at compression level 0, 1 or 2, with buckets and harmonics. |
| `.spz` | `loaders/spz.mojo`: `read_spz`, `parse_spz` | Niantic's format: gzip for versions 1 to 3, Zstandard streams for version 4. |
| `.ply` | `loaders/gaussian_splat_ply.mojo`: `read_gaussian_splat_ply` | The GraphDECO and INRIA splat PLY, with `f_rest` harmonics up to degree 3. |
| glTF | `loaders/gltf_gaussian_splat.mojo`: `read_gltf_gaussian_splats` | Meshes with the `KHR_gaussian_splatting` extension, from `.gltf` or `.glb`. |

`KsplatCompressionLevel` is a type with `is_valid`. `ksplat_layout` refuses a level that is not 0, 1 or 2.

The SPZ reader uses `loaders.nrrd.gunzip` for gzip and `render.zstd` for Zstandard. A version 4 file needs no other decoder.

The glTF reader returns one `GltfGaussianSplatMesh` for each mesh that has splat primitives. Each primitive gets a name that is unique, as three.js makes it. The mesh keeps its `extras` as user data.

Each reader refuses a file with the problems that three.js refuses. The module docstrings list them.

## Tests

`assets/gaussian_splat/make_splats.mjs` writes the test files. It reads each file with the loaders of three.js r186 into `expected.json`. It also writes the bounds, a raycast and the sort of three.js's `GaussianSplat` for one object and one camera. `tests/test_gaussian_splat_loaders.mojo` and `tests/test_gaussian_splat.mojo` compare the port with these values.

## What is not ported

- `Renderer.render` does not draw a `GaussianSplat` by itself. You must call `draw_gaussian_splat` after `render_into`. The splats do not mix with the depth order of other transparent objects.
- The splats cover the whole target. A viewport of the renderer does not move them.
- The glTF reader does not place the splat meshes on the nodes of the file. It reads no sparse accessor. It counts only the mesh names when it makes a name unique. three.js also counts the node names.
- The GPU sort of three.js runs on the CPU here, as the WebGL fallback of three.js does.
- A `.ksplat` section that holds more splats than its rows is refused. three.js reads on into the next section.
