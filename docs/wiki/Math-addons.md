# Math addons

The math addons of three.js's `examples/jsm/math/`: noise, an oriented box, a capsule, an octree for collisions, a surface sampler, color maps and color spaces. Each module is a line-by-line port. Its tests check it against values that three.js 0.180 calculated.

| Module | three.js |
|---|---|
| `math/noise.mojo` | `ImprovedNoise`, `SimplexNoise` |
| `math/obb.mojo` | `OBB` |
| `math/capsule.mojo` | `Capsule` |
| `math/octree.mojo` | `Octree`, and `Box3.intersectsTriangle` |
| `geometries/surface_sampler.mojo` | `MeshSurfaceSampler` |
| `render/lut.mojo` | `Lut` |
| `render/color_spaces.mojo` | `ColorManagement`, `ColorSpaces` |

The shapes hold bare `Float32` meters, as `Box3` and `Ray` do. See [Math](Math).

## Noise

`ImprovedNoise().noise(x, y, z)` is Ken Perlin's improved noise. It is zero at every whole-number point.

`SimplexNoise(random)` is Stefan Gustavson's simplex noise. `noise(x, y)`, `noise3d(x, y, z)` and `noise4d(x, y, z, w)` give the value in two, three and four dimensions.

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
| `apply_matrix4(m)` | Carry the box through an affine transform. |
| `a == b` | three.js's `equals`, exact. |

The port differs from three.js in three places:

- `intersects_plane` adds the plane's constant. three.js subtracts it, and so it tests the plane mirrored through the origin.
- `apply_matrix4` moves the center by the whole matrix and turns the old rotation. three.js adds only the translation. The two agree for a box at the origin with no rotation, which is the use in three.js's example.
- `from_box3` refuses an empty box, and `intersects_box3` says that an empty box meets nothing.

A half size that is negative or not finite is refused.

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

The boxes are nodes in one list, and each node holds indices into `triangles`. Every query visits the boxes and the triangles in the order of three.js, so a push is the push that three.js gives.

The port differs from three.js in two places:

- `triangles_per_leaf` and `max_level` hold at every level. three.js reads them only on the root.
- `from_graph_node` reads the plain meshes, `Scene.meshes`. three.js also reads a skinned mesh in its bind pose, and an instanced mesh once.

## Surface sampler

`MeshSurfaceSampler(geometry, random)` picks random points on the triangles of a geometry. A larger triangle gets more points.

1. Optionally, call `set_weight_attribute(name)`. The first number of the attribute weighs each vertex.
2. Call `build()`. It adds up the weight of each triangle.
3. Call `sample()` for each point.

A `SurfaceSample` holds the triangle, the position and the unit normal. It also holds the color and the texture coordinates when the geometry has them. The normal comes from the normals, or from the triangle when there are none.

The random numbers come from a `SeededRandom`, so the same seed gives the same points. Each sample draws three numbers in the order of three.js. A seeded three.js sampler picks the same triangles and the same points.

A missing weight attribute, a weight that is negative or not a number, and positions that do not make whole triangles are refused. A sample from a surface with no weight is refused too.

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
