# Math addons

These are the math addons of three.js's `examples/jsm/math/`. They are noise, an oriented box, a capsule, a collision octree, a surface sampler, color maps, color spaces and HSV colors. The tests retain three.js 0.180 reference values. They also check deliberate corrections with independent geometric references.

![Hills from simplex noise turn under a lamp](out/mathaddons.png)

`examples/terrain.mojo` draws this picture.

| Module | three.js |
|---|---|
| `math/noise.mojo` | `ImprovedNoise`, `SimplexNoise` |
| `math/obb.mojo` | `OBB` |
| `math/capsule.mojo` | `Capsule` |
| `math/octree.mojo` | `Octree`, and `Box3.intersectsTriangle` |
| `math/sort_utils.mojo` | `SortUtils.radixSort` |
| `geometries/surface_sampler.mojo` | `MeshSurfaceSampler` |
| `render/lut.mojo` | `Lut` |
| `render/color_spaces.mojo` | `ColorManagement`, `ColorSpaces` |
| `render/color_converter.mojo` | `ColorConverter` |

The shapes hold bare `Float32` meters, as `Box3` and `Ray` do. See [Math](Math).

## Radix sort

`radix_sort(items, keys, reversed)` sorts items by a 32-bit unsigned key each. It is three.js's `radixSort`. It sorts eight bits at a time from the top, and finishes a run of 32 items or fewer by insertion. The sort is stable, and it gives three.js's order.

three.js takes a `get` that reads each item's key. Here the items are indices into `keys`, so `get` is `keys[item]`. `radix_sort_keys(keys, reversed)` sorts the keys themselves. An item that names no key raises.

## Noise

`ImprovedNoise().noise(x, y, z)` is Ken Perlin's improved noise. It is zero at every whole-number point.

`SimplexNoise(random)` is Stefan Gustavson's simplex noise. It refuses finite coordinates if their lattice transform overflows, before converting lattice cells to integer indices. `noise(x, y)`, `noise3d(x, y, z)` and `noise4d(x, y, z, w)` give the value in two, three and four dimensions.

| Member | Meaning |
|---|---|
| `SimplexNoise(random)` | Draw the permutation from a `SeededRandom`. The seed picks the field. |
| `perm` | The 512 entries of the permutation, three.js's `perm`. |

Both give the value that three.js gives, bit for bit. The arithmetic is in `Float64`, in the order of three.js. Mojo fuses a multiply and an add by default, so each product that an addition uses is rounded first.

`SimplexNoise` takes a `SeededRandom`, which is three.js's `MathUtils.seededRandom`. three.js uses `Math.random` by default, and that cannot be seeded. A coordinate that is not finite is refused. three.js returns `NaN`.

## OBB

`OBB(center, half_size, rotation)` is a box with its own axes. The columns of the `Matrix3` rotation are the axes.

| Member | Meaning |
|---|---|
| `OBB.from_box3(box)` | The oriented box of an axis-aligned box. |
| `size()`, `axis(i)` | The full extent, and one axis. |
| `clamp_point(p)`, `contains_point(p)` | The nearest point of the box, and whether a point is inside. |
| `intersects_box3(box)`, `intersects_sphere(s)` | Whether the box meets the shape. |
| `intersects_obb(other, epsilon)` | The separating axis test of two boxes. |
| `intersects_plane(plane)` | Whether a plane passes through the box. |
| `intersect_ray(ray)`, `intersects_ray(ray)` | Where a ray meets the box, or only whether. |
| `apply_matrix4(m)` | Carry the box through a finite affine transform that preserves perpendicular box axes. |
| `a == b` | three.js's `equals`, exact. |

The port differs from three.js in three places:

- `intersects_plane` adds the plane's constant. three.js subtracts it, and so it tests the plane mirrored through the origin.
- `apply_matrix4` moves the center by the whole matrix and turns the old rotation. three.js adds only the translation. The two agree for a box at the origin with no rotation, which is the use in three.js's example.
- `from_box3` refuses an empty box, and `intersects_box3` says that an empty box meets nothing.

A half size that is negative or not finite is refused.

`apply_matrix4` transforms the box's own axes. Reflections keep a proper rotation and nonnegative half sizes, including when the box is already rotated.

Nonuniform scale is supported when the transformed box axes stay perpendicular. This includes scale along the box axes. A nonuniform world scale can shear a rotated box. Such a transform is refused. A shear is not approximated by an OBB.

Normalized axis dot products can differ from zero by at most `1e-6`. This tolerance allows Float32 rounding. The method then corrects the axes to an orthonormal frame. Each geometric half size is its old value times its transformed axis length.

The stored half sizes also bound Float32 rounding when a local point is formed, transformed and tested. Each scalar operation uses the error bound `u * absolute_magnitude + 2^-150`, with `u = 2^-24`. The method propagates these errors using sums of absolute products, then rounds the final extents outward. Products by zero or signed one, and additions of zero, add no error. An axis-aligned box at the origin keeps exact extents under a signed-permutation transform.

This is a conservative numerical bound, not exact arithmetic or a general shear bound. Cancellation can require a visible increase in a thin extent beside a large extent or center. The increase depends on the absolute products, not the ULP of the small result.

The method refuses nonfinite inputs, projections, collapsed axes, and positive half sizes that underflow. It also refuses center, half-size and conservative-bound overflow. Every refusal leaves the box unchanged.

## Capsule

`Capsule(start, end, radius)` is a sphere swept along a segment. `Capsule()` is three.js's default: one meter up y, one meter in radius.

`center()`, `translate(offset)` and `intersects_box(box)` are three.js's members. The box test is conservative, as in three.js. A radius that is negative or not finite is refused.

## Octree

An `Octree` sorts triangles into nested boxes. A game builds it from a level once, and then asks it which triangles a collider can touch.

| Member | Meaning |
|---|---|
| `add_triangle(t)`, `build()` | Add triangles, then cut the boxes. |
| `from_graph_node(scene, assets, node)` | Add the meshes at and below a node, in world space, and build. |
| `capsule_intersect(c)`, `sphere_intersect(s)` | The push that moves a collider out of the level, or None. |
| `ray_intersect(ray)` | The nearest triangle a ray meets from its front, or None. |
| `ray_triangles`, `sphere_triangles`, `capsule_triangles` | The triangles a shape can reach, each once. |
| `triangles_per_leaf`, `max_level` | Eight triangles to a box, and sixteen levels, by default. |
| `layers` | Which layers `from_graph_node` reads. |
| `boxes()` | The box of every node below the root, each box before the boxes in it. The [octree helper](Helpers#octreehelper) draws them. |
| `clear()` | Empty the tree. |

`triangle_capsule_intersect`, `triangle_sphere_intersect` and `box_intersects_triangle` answer for one triangle. A contact gives the push direction, the point met and the depth.

The boxes are nodes in one list, and each node holds indices into `triangles`. Every query visits the boxes and the triangles in the order of three.js. Contact distances use corrected geometric minima.

Sphere queries accept a center on either side of a face. A face contact pushes toward the front, even from behind. An edge contact pushes away from the nearest edge. Capsule queries ignore a segment wholly behind the face. Their face contacts push toward the front. A ray only meets the front.

Front-face, edge or vertex tangency gives a contact with zero depth. A sphere tangent to the back of a face still gets the push toward the front. A zero total push gives a zero collision direction.

A collinear triangle uses its nonzero edges. An edge of zero length is ignored. A triangle made of one repeated point meets nothing. Zero separation from a collinear edge has no unique normal, so it gives a zero direction.

The port corrects proven upstream defects, as stated in the
[contribution rules](https://github.com/SethKitchen/ThreeMojo/blob/main/CONTRIBUTING.md#upstream-behavior-and-correctness).
It does not reproduce every collision output of three.js 0.180.0. A port of
three.js's first-person game can therefore move a player differently near
an edge or tangent contact. There is no legacy contact mode.

The port differs from three.js in these places:

- Sphere edge tests compare the full squared distance with the full squared radius. They select the nearest edge. This corrects missed coplanar and behind-plane contacts.
- Segment tests recompute the other parameter after an endpoint limits the minimum. The solver is shared with `Line3`. Octree keeps every nonzero segment; `Line3` keeps its documented short-segment threshold.
- Edge and vertex tangency counts as a zero-depth contact instead of being rejected by the inherited strict edge test. Capsule face tangency avoids zero-over-zero interpolation.
- Thin-triangle containment uses the stable barycentric kernel from `Triangle`.
- `triangles_per_leaf` and `max_level` hold at every level. three.js reads them only on the root.
- `from_graph_node` reads the plain meshes, `Scene.meshes`. three.js also reads a skinned mesh in its bind pose, and an instanced mesh once.

## Surface sampler

`MeshSurfaceSampler(geometry, random)` picks random points on the triangles of a geometry. A larger triangle gets more points.

1. Optionally, call `set_weight_attribute(name)`. The first number of the attribute weighs each vertex.
2. Call `build()`. It adds up the weight of each triangle.
3. Call `sample()` for each point.

A `SurfaceSample` holds the triangle, the position and the unit normal. It also holds the color and the texture coordinates when the geometry has them. The normal comes from the normals, or from the triangle when there are none.

The random numbers come from a `SeededRandom`, so the same seed gives the same points. Each sample draws three numbers in the order of three.js. A seeded three.js sampler picks the same triangles and the same points.

A missing weight attribute, a used vertex weight that is negative or not finite, and positions that do not make whole triangles are refused. Empty and all-zero distributions can be built, but cannot be sampled.

Positive triangle weights must keep finite, nonzero intervals in the `Float32` distribution. A build refuses overflow, underflow to zero, or a positive interval lost to rounding. A failed build clears the old distribution. Correct the input and build again before sampling.

## Color maps

`Lut(name, count)` samples a color map at `count + 1` points. `get_color(value)` gives the nearest sample for a value between `min_v` and `max_v`.

| Member | Meaning |
|---|---|
| `Lut(name, count)` | A preset: `RAINBOW`, `COOL_TO_WARM`, `BLACKBODY` or `GRAYSCALE`. |
| `Lut(stops, count)` | A custom map, three.js's `addColorMap`. |
| `set_min(v)`, `set_max(v)` | The range. |
| `get_color(value) -> FloatColor` | The value clamped to the range, and its nearest sample. |
| `canvas_pixels() -> List[UInt8]` | The image of three.js's `updateCanvas`: one pixel wide, `n` high, RGBA. |

A `ColorMapName` names a preset. A `ColorStop` is a position from zero to one and a color as `0xRRGGBB`.

three.js decodes the first and the last sample from sRGB, and it does not decode the samples between. The port keeps this, so each color is the color that three.js gives. A custom map must start at zero, end at one and go up.

## Color spaces

`convert(color, source, target)` converts a `FloatColor` between two color spaces, as three.js's `ColorManagement.convert` does. It decodes the source's transfer function, carries the color through CIE XYZ, and encodes the target's transfer function.

| `ColorSpaceId` | three.js |
|---|---|
| `SRGB_COLOR_SPACE` | `'srgb'` |
| `LINEAR_SRGB_COLOR_SPACE` | `'srgb-linear'` |
| `DISPLAY_P3_COLOR_SPACE` | `'display-p3'` |
| `LINEAR_DISPLAY_P3_COLOR_SPACE` | `'display-p3-linear'` |
| `LINEAR_REC2020_COLOR_SPACE` | `'rec2020-linear'` |
| `EXTENDED_SRGB_COLOR_SPACE` | `'extended-srgb'` |
| `NO_COLOR_SPACE` | `''`, numbers that are not color |

`color_space(id)` gives the definition: the primaries, the white point, the `ColorTransfer`, the matrices to and from XYZ, and the luminance coefficients. The matrices are the matrices of three.js, to seven places.

`conversion_matrix(source, target)` is the target's matrix from XYZ times the source's matrix to XYZ. three.js's internal `_getMatrix` multiplies the two in the other order.

`srgb_to_linear_three` and `linear_to_srgb_three` are three.js's transfer functions, with the constants of three.js. `render/srgb.mojo` holds the transfer functions that the renderer uses, written from the definition.

## HSV colors

`set_hsv(color, h, s, v)` sets a `FloatColor` from hue, saturation and value, and `get_hsv(color)` gives them back as an `HSV`. three.js's `ColorConverter.setHSV` and `getHSV`. Both go through HSL in the linear working space, as three.js's do.

| Member | Meaning |
|---|---|
| `set_hsv(color, h, s, v)` | Set red, green and blue. The hue wraps. The saturation and the value clamp to zero to one. Alpha is kept. |
| `get_hsv(color) -> HSV` | The hue, saturation and value of the linear channels. |
| `HSV(hue, saturation, value)` | The three numbers, each nominally zero to one. |

```mojo
var color = FloatColor(0, 0, 0)
set_hsv(color, 0.3, 0.6, 0.8)                # linear (0.416, 0.8, 0.32)
var back = get_hsv(color)                     # HSV(0.3, 0.6, 0.8)
```

Black and white have no saturation, and three.js divides zero by zero for both. There, `setHSV` gives a color that is not a number, and `getHSV` of black gives a saturation that is not a number. Here both give a saturation of zero. All other inputs give three.js's numbers.
