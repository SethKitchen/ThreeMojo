# Math

`math/vector2.mojo`, `math/vector3.mojo`, `math/vector4.mojo`, `math/matrix3.mojo`, `math/matrix4.mojo`, `math/bounds.mojo`, `math/frustum.mojo`, `math/ray.mojo`, `math/projection.mojo`, `math/triangle.mojo`, `math/spherical.mojo`, `math/matrix2.mojo` and `math/utils.mojo`. Ported from three.js with the same conventions.

![A quaternion turns a vector, and a sphere follows that point](out/math.png)

three.js: `Vector2`, `Vector3`, `Vector4`, `Quaternion`, `Matrix3`, `Matrix4`, `Matrix4.makePerspective`, `makeOrthographic`, `lookAt`, `Box3`, `Sphere`, `Plane`, `Frustum`, `FrustumArray`, `Ray`, `Triangle`, `Line3`, `Spherical`, `Cylindrical`, `Matrix2`, `Box2`, `MathUtils`.

## The three.js math API

Each class has the members of three.js's `src/math` class of the same name. A three.js name in camel case is a Mojo name in snake case: `distanceTo` is `distance_to`. The tables below list the members. The numbers match three.js 0.180 to Float32 precision. The tests check them against three.js run in node.

Some three.js members have a different form here:

- A setter that builds a value from another value is a static constructor. `setFromMatrixPosition` is `Vector3.from_matrix_position(m)`. `setFromCenterAndSize` is `Box3.from_center_and_size(c, s)`.
- A `Matrix4` builder is a free function, as `translation` is: `compose`, `rotation_axis`, `shear`, `basis`, `rotation_from_quaternion` and `rotation_from_euler`.
- `equals` is `==`. `multiplyMatrices` and `multiplyQuaternions` are `*`. `divideScalar` is `/`.
- A random member takes a `SeededRandom`. A seed gives the same numbers as three.js's `seededRandom`.
- `setFromSpherical` and `setFromCylindrical` are `Spherical.to_vector3()` and `Cylindrical.to_vector3()`.
- A member that reads a scene is in `core.object_bounds`: `Box3.setFromObject`, `expandByObject`, `Frustum.intersectsObject` and `intersectsSprite`. See [Bounds of scene content](#bounds-of-scene-content).
- `Color` is `FloatColor`. See [Render target and framebuffer](Render-target-and-framebuffer#color-and-floatcolor).

A question with no answer raises, where three.js returns `NaN`, an infinity or a zero vector. Examples are `decompose` of a flat matrix, `get_parameter` of a flat box and the nearest point of an empty sphere. Each table says where.

These three.js members are not ported:

- `fromArray`, `toArray` and `fromBufferAttribute` read JavaScript arrays and attributes. `BufferAttribute` has its own readers.
- `Quaternion.slerpFlat` and `multiplyQuaternionsFlat` work on flat arrays.
- `Vector3.setFromColor` and `Color.setFromVector3` join two packages that do not import each other.
- `Triangle.getInterpolatedAttribute` reads an attribute.

## Vector2 and Vector3

`Vector2(x, y)` and `Vector3(x, y, z)` hold `Float32` components. Both are value types. Assignment copies.

`Vector2` has the same members in two dimensions, except the ones that need a third. It adds `cross(other) -> Float32`, which is the one component a cross product has in a plane. It is positive when `other` lies to the left of `self`. It also adds `angle()`, the angle from +x, and `rotate_around(center, angle)`. The curves asked for the first members; see [Curves and paths](Curves).

A method that changes the vector changes `self` in place, as in three.js.

| Vector3 member | Meaning |
|---|---|
| `dot(other) -> Float32` | The dot product. |
| `length()`, `length_sq()`, `manhattan_length()` | The Euclidean length, its square, and the sum of the absolute components. |
| `distance_to(p)`, `distance_to_squared(p)`, `manhattan_distance_to(p)` | The distance to another point. |
| `angle_to(v) -> Angle` | The angle between two vectors. A zero vector gives a right angle, as in three.js. |
| `add(other)`, `sub(other)`, `add_scaled_vector(v, s)`, `negate()` | Change `self` in place. |
| `cross(other)` | `self = self × other`. |
| `normalize()`, `set_length(l)` | Scale to unit length, or to `l`. A zero vector stays zero. |
| `lerp(v, alpha)`, `lerp_vectors(a, b, alpha)` | A point on the line between two vectors. |
| `reflect(normal)` | Reflect off a plane with a unit normal. |
| `apply_matrix4(m)`, `apply_matrix3(m)`, `apply_normal_matrix(m)` | Multiply by a matrix. `apply_matrix4` divides by `w`, but not by a `w` of zero. `apply_normal_matrix` makes the result unit length. |
| `apply_quaternion(q)`, `apply_euler(e)`, `apply_axis_angle(axis, angle)` | Turn the vector. |
| `transform_direction(m)` | Turn by the rotation and scale of `m`, then make unit length. `Matrix4.transform_direction` does not normalize. |
| `project(view, projection)`, `unproject(view, projection)` | To and from normalized device space. `cameras.camera.project_point(p, camera, scene)` and `unproject_point` take a camera. |
| `min(v)`, `max(v)`, `clamp(low, high)`, `clamp_scalar(low, high)`, `clamp_length(low, high)` | Hold the components, or the length, in a range. |
| `multiply(v)`, `divide(v)` | Component by component. |
| `floor()`, `ceil()`, `round()`, `round_to_zero()` | Round each component. `round` rounds a half up, as JavaScript's `Math.round` does. |
| `project_on_vector(v)`, `project_on_plane(normal)` | Keep the part along `v`, or remove the part along `normal`. A zero `v` gives a zero vector. |
| `get_component(i)`, `set_component(i, value)` | One component by index. An index other than 0, 1 or 2 raises. |
| `Vector3.from_matrix_position(m)`, `from_matrix_scale(m)`, `from_matrix_column(m, i)`, `from_matrix3_column(m, i)` | Read a matrix. A column index out of range raises. |
| `Vector3.random(rng)`, `Vector3.random_direction(rng)` | Random vectors, from a `SeededRandom`. |
| `a + b`, `a - b`, `a * f`, `a / f`, `-a`, `a == b` | Return a new vector, or compare exactly. |

## Vector4

`Vector4(x, y, z, w)` holds four `Float32` components. `w` is the homogeneous coordinate: one for a position, zero for a direction. `Vector4(of=v, w=1)` builds one from a `Vector3`.

| Member | Meaning |
|---|---|
| `xyz() -> Vector3` | The first three components. |
| `dot(other)`, `length()` | Over all four components. |
| `add(other)`, `sub(other)`, `normalize()` | Change `self` in place. |
| `apply_matrix4(m)` | `self = m * self`, with nothing divided. A projection leaves the clip-space `w` in `w`. |
| `a + b`, `a - b`, `a * f`, `-a` | Return a new vector. |

`Matrix4.transform_point` divides by `w` and discards it. `apply_matrix4` keeps the whole product.

## Matrix3

`Matrix3` is column-major, as `Matrix4` is. Element `(row, col)` is at `col * 3 + row`. `set` takes nine arguments in row-major order.

It has two jobs, as in three.js. It is the rotation and scale part of a `Matrix4`, which is what a normal is transformed by. And it is a 2D affine transform, which is what a texture's repeat, offset and rotation come to.

| Member | Meaning |
|---|---|
| `Matrix3()` | The identity. |
| `set(n11, ..., n33)` | Every element, row by row. |
| `get(row, col)`, `put(row, col, value)` | One element. |
| `multiply(other)`, `premultiply(other)` | `self * other` and `other * self`. |
| `transpose()`, `invert()`, `determinant()` | As named. A singular matrix inverts to zeros. |
| `transform(v) -> Vector3` | `self * v`. three.js's `Vector3.applyMatrix3`. |
| `transform_point(p) -> Vector2` | A 2D point with a third coordinate of one. three.js's `Vector2.applyMatrix3`. |
| `scale(x, y)`, `rotate(angle)`, `translate(x, y)` | Apply a 2D scale, turn or move after this transform, in place. |
| `as_matrix4() -> Matrix4` | This matrix in the upper-left corner, with no translation. |
| `a == b`, `a != b` | Whether every element is equal, exactly. three.js's `equals`. |
| `a * b`, `multiply_scalar(f)` | The product of two matrices, or every element times a number. |
| `extract_basis(x, y, z)` | Write the three columns into three vectors. |

Builders, as static methods:

| Builder | Meaning |
|---|---|
| `Matrix3.from_matrix4(m)` | The upper-left 3 by 3 of a `Matrix4`. |
| `Matrix3.normal_matrix(m)` | The inverse transpose of that corner, for normals. Raises for a collapsed transform. |
| `Matrix3.translation(x, y)`, `Matrix3.scaling(x, y)`, `Matrix3.rotation(angle)` | The 2D transforms. A rotation takes an `Angle`. |
| `Matrix3.uv_transform(offset, repeat, rotation, center)` | three.js's `setUvTransform`: turn about `center` by minus `rotation`, then scale by `repeat` about it, then move by `offset`. |

`rotate(angle)` turns by `-angle`, as three.js does. It exists to build a texture transform, where a turn of the coordinates one way shows the image turned the other. `Matrix3.rotation(angle)` turns the coordinates themselves.

`Matrix4.normal_matrix()` gives the same answer as a `Matrix4`. The renderer uses that one.

## Matrix4

Column-major storage, as three.js and OpenGL. Element `(row, col)` is at `col * 4 + row`. The translation is at elements 12 to 14.

`set` takes its sixteen arguments in row-major order, so a matrix in source reads as it does on paper. That asymmetry is three.js's.

| Member | Meaning |
|---|---|
| `Matrix4()` | The identity. |
| `set(n11, n12, ..., n44)` | Every element, row by row. |
| `get(row, col)`, `put(row, col, value)` | One element. |
| `multiply(other)` | `self = self * other`. The right-hand matrix applies first. |
| `premultiply(other)` | `self = other * self`. |
| `transpose()`, `invert()`, `determinant()` | As named. A singular matrix inverts to zeros. |
| `normal_matrix() -> Matrix4` | The inverse transpose, for normals. |
| `extract_rotation() -> Matrix4` | The rotation with scale and translation removed. A shear or a mirror stays. |
| `is_rotation(tolerance=1e-4) -> Bool` | Whether the upper-left 3 by 3 is a rotation: unit axes at right angles, right-handed. |
| `is_scaled_rotation(tolerance=1e-4) -> Bool` | Whether it is a rotation times a positive uniform scale. |
| `max_scale() -> Float32` | The longest axis column. three.js's `getMaxScaleOnAxis`. |
| `max_stretch() -> Float32` | A bound on the most any direction is stretched. It holds under shear, where the longest axis does not. |
| `is_affine() -> Bool` | Whether the bottom row is `(0, 0, 0, 1)`. |
| `transform_point(p) -> Vector3` | Apply with `w = 1` and divide by `w`. |
| `transform_w(p) -> Float32` | The `w` that `transform_point` divides by. |
| `transform_direction(d) -> Vector3` | Apply with `w = 0`. |
| `a == b`, `a * b`, `multiply_scalar(f)` | Compare exactly, multiply, or multiply every element by a number. |
| `scale(v)` | Scale the three axis columns: a scale applied first. |
| `set_position(v)`, `copy_position(m)` | Set the translation column. |
| `extract_basis(x, y, z)` | Write the three axis columns into three vectors. |
| `look_at(eye, target, up)` | Set the rotation so that +z points from `target` to `eye`. The translation is kept. `math.projection.look_at` builds a view matrix instead. |
| `decompose(position, quaternion, scale)` | Split into a translation, a rotation and a scale. A mirror gives a negative x scale. An axis of zero length raises; three.js writes `NaN`. |

Builders: `translation(x, y, z)`, `scaling(x, y, z)`, `rotation_x(angle)`, `rotation_y(angle)`, `rotation_z(angle)`, `rotation_axis(axis, angle)`, `shear(xy, xz, yx, yz, zx, zy)`, `basis(x, y, z)`, `compose(position, quaternion, scale)`, `rotation_from_quaternion(q)` and `rotation_from_euler(e)`. A rotation takes an `Angle`, so `rotation_z(90.0)` does not compile.

```mojo
var m = translation(10, 0, 0)
m.multiply(rotation_z(Angle(90.0, DEGREE)))
m.multiply(translation(-10, 0, 0))     # a rotation about (10, 0, 0)
```

## Box3, Sphere and Plane

`math/bounds.mojo`. The volumes a renderer tests against, and the plane a frustum is made of. All three hold bare `Float32` meters, as `Vector3` does.

An empty box or sphere holds no points. It is a value, not an error. A box is empty when a corner is inside out on any axis. A sphere is empty when its radius is negative. Every operation treats an empty bound as the set it is.

Expanding an empty bound by a point gives the bound of that one point. A union with one changes nothing. An overlap test with one is false. A transform leaves one empty.

A question that needs a point of an empty bound raises: `clamp_point`, `distance_to_point` and `distance_to_sphere`.

Both transforms take an affine matrix, one that keeps `w` at one. A projection raises. A transformed sphere grows by `max_stretch`, which holds under shear. three.js grows by the longest axis, which can fall short of a point the sphere held.

| Box3 member | Meaning |
|---|---|
| `Box3(min, max)`, `Box3.empty()` | Two corners, or the inside-out box that holds nothing. |
| `Box3.from_points(points)` | The smallest box around the points. |
| `is_empty()`, `center()`, `size()` | As named. An empty box has the origin as its center and no size. |
| `expand_by_point(p)`, `union(other)` | Grow in place. |
| `contains_point(p)`, `clamp_point(p)`, `distance_to_point(p)` | The faces count as inside. |
| `intersects_box(other)`, `intersects_sphere(s)` | Touching counts. |
| `apply_matrix4(m)` | Transform the eight corners and bound them again, in place. |
| `bounding_sphere() -> Sphere` | The sphere through the corners. |
| `Box3.from_center_and_size(c, s)` | The box of size `s` centered on `c`. |
| `expand_by_vector(v)`, `expand_by_scalar(f)`, `translate(v)` | Move each face out, or move the box. |
| `intersect(other)` | Keep what both boxes hold. Boxes that do not overlap give the empty box. |
| `contains_box(other)` | Whether all of `other` is inside. The empty box is inside every box. |
| `get_parameter(p) -> Vector3` | Where `p` lies, as a fraction of each side. A box with no extent on an axis raises; three.js divides by zero. |
| `intersects_plane(p)`, `intersects_triangle(t)` | Whether the box meets a plane or a triangle. The triangle test is three.js's separating axis test. |
| `a == b` | Both corners equal. |

| Sphere member | Meaning |
|---|---|
| `Sphere(center, radius)`, `Sphere.empty()` | A negative radius is the empty sphere. |
| `Sphere.from_points(points)` | Centered on the points' box, reaching the farthest point. |
| `is_empty()`, `contains_point(p)`, `distance_to_point(p)` | The distance is signed: negative inside. |
| `intersects_sphere(other)`, `intersects_box(box)` | Touching counts. |
| `expand_by_point(p)` | Grow in place, by as little as possible. |
| `apply_matrix4(m)` | Move the center. The radius grows by `max_stretch`. |
| `bounding_box() -> Box3` | The box around the sphere. |
| `Sphere.from_points_around(points, center)` | three.js's `setFromPoints` with a center: the sphere at `center` that reaches every point. |
| `union(other)`, `translate(v)` | Grow to hold another sphere, or move. |
| `clamp_point(p)` | The nearest point of the sphere. The empty sphere raises; three.js uses a radius of one. |
| `intersects_plane(p)` | Whether a plane passes through the sphere. |
| `a == b` | Centers and radii equal. |

| Plane member | Meaning |
|---|---|
| `Plane(normal, constant)` | The points where `dot(normal, p) + constant` is zero. The normal is made unit length, and the constant scaled with it. |
| `Plane.from_normal_and_point(n, p)` | Through `p`, facing `n`. |
| `Plane.from_coplanar_points(a, b, c)` | Through three points, facing the side they wind counter-clockwise from. |
| `distance_to_point(p)`, `distance_to_sphere(s)` | Signed: positive in front. |
| `project_point(p)`, `coplanar_point()` | The nearest point on the plane. |
| `negate()`, `translate(offset)` | Turn around, or move, in place. |
| `intersects_sphere(s)`, `intersects_box(box)` | Whether the plane passes through it. |
| `intersect_line(line) -> Optional[Vector3]` | Where a segment crosses the plane. A segment in the plane gives its start, as in three.js. |
| `intersects_line(line)` | Whether the two ends lie on opposite sides. An end on the plane does not count. |
| `apply_matrix4(m)`, `apply_matrix4(m, normal_matrix)` | Carry the plane through a transform. A transform that collapses a dimension raises. |
| `a == b` | Normals and constants equal. |

A plane refuses a zero normal. Three points on one line do not make a plane.

## Frustum

`math/frustum.mojo`. Six planes facing inward: right, left, bottom, top, far and near, in three.js's order. `RIGHT` to `NEAR` index them in `planes`.

`Frustum.from_projection_matrix(m)` reads the planes off a matrix. Each plane is a sum or difference of the bottom row with another row. Give it a projection for camera space, or a projection times a view for world space.

| Member | Meaning |
|---|---|
| `Frustum.from_projection_matrix(m)` | The frustum a matrix sees. Raises for a matrix that describes no volume. |
| `Frustum.from_camera(clip, view, near, far)` | The sides from `clip`, the near and far planes from the view matrix and the two distances. Raises for a view that is not affine, or a far plane not beyond the near one. |
| `contains_point(p)` | Whether `p` is in front of every plane. A point on a plane counts. |
| `intersects_sphere(s)` | Whether any of `s` is in view. False for an empty sphere. |
| `intersects_box(b)` | Whether any of `b` is in view. False for an empty box. |

`from_projection_matrix(m, coordinate_system, reversed_depth)` takes three.js's two other arguments. `coordinate_system` is `WEBGL_COORDINATES`, the default, or `WEBGPU_COORDINATES`. It is a `CoordinateSystem`, not a bare integer, and an invalid one raises. A WebGPU projection puts the near plane at a depth of zero. With `reversed_depth`, the far plane is at a depth of zero.

`cameras.frustum_array.FrustumArray` is three.js's `FrustumArray`. Its `intersects_object`, `intersects_sprite`, `intersects_sphere`, `intersects_box` and `contains_point` take an `ArrayCamera` and a scene. Each is true when any camera sees the thing. An array with no cameras sees nothing.

## Bounds of scene content

`core/object_bounds.mojo` holds the three.js members that read a scene. The scene must be updated first.

`box_from_object(scene, assets, node, precise=False)` is three.js's `Box3.setFromObject`. It returns the world-space box around everything drawn at `node` and under it. `expand_by_object(box, scene, assets, node, precise)` is `expandByObject`: it grows a box instead.

Each thing adds the bound three.js gives it:

- A mesh, a line, a set of points or a wide line adds its geometry's box.
- An instanced or a batched mesh adds the box of its instances' boxes.
- A level of detail adds every level, because three.js's levels are children.
- A skinned mesh adds the box of its posed vertices.
- A sprite adds the unit square.

With `precise`, each vertex goes to world space on its own. The box is tighter for a turned object. A mesh or a skinned mesh wears its morph targets there, as in three.js. The geometry's own box leaves the morph targets out. three.js's includes them.

`intersects_object(frustum, scene, assets, thing)` is `Frustum.intersectsObject`, for a `Mesh`, a `Line`, a `Points` or an `InstancedMesh`. It tests the geometry's bounding sphere, carried to world space. `intersects_sprite(frustum, scene, sprite)` is `intersectsSprite`.

A sphere or a box that crosses a plane is in view as far as the test knows. One that crosses two planes outside their corner is in view too. That is the usual bargain. The renderer uses `intersects_sphere` to skip meshes. See [Renderer](Renderer#frustum-culling).

The renderer builds its frustum with `from_camera`. A far plane read back off a `Float32` projection can sit meters short when `far` is thousands of times `near`. For a near plane at 0.1 and a far one at 5000 it sits at 4993. The camera's own distances put it at 5000, where the clipper has it.

## Ray

`math/ray.mojo`. A `Ray` is an origin and a unit direction: a half-line. The constructor makes the direction unit length and refuses a zero one. Every answer below assumes it.

A hit is an `Optional`. A miss is `None`. Every hit is forward of the origin. A ray inside a sphere or a box hits where it leaves.

| Member | Meaning |
|---|---|
| `Ray(origin, direction)` | From `origin`, along `direction`. |
| `at(t) -> Vector3` | The point `t` meters along the ray. |
| `look_at(target)`, `recast(t)` | Aim at a point, or move the origin along the ray, in place. |
| `closest_point_to_point(p)`, `distance_to_point(p)`, `distance_sq_to_point(p)` | The nearest point of the ray, never behind the origin, and the distance to it. |
| `intersect_sphere(s)`, `intersects_sphere(s)` | Where the ray enters the sphere. |
| `distance_to_plane(p)`, `intersect_plane(p)`, `intersects_plane(p)` | Where the ray meets the plane. A ray in the plane meets it at its origin. |
| `intersect_box(b)`, `intersects_box(b)` | Where the ray enters the box. |
| `intersect_triangle(a, b, c, cull_back)` | Where the ray meets the triangle. With `cull_back`, a hit from behind is a miss. |
| `apply_matrix4(m)` | Carry the ray through an affine matrix, in place. |

An empty sphere or box is hit nowhere. A ray parallel to a plane meets it only when it lies in it. A ray in a triangle's plane misses the triangle, and so does a degenerate triangle.

`apply_matrix4` raises for a projection, and for a matrix that flattens the direction to nothing. `look_at` raises for the origin itself.

`core.raycaster` carries a ray through a scene. See [Raycasting](Raycasting).

## Projection

| Function | Meaning |
|---|---|
| `perspective(left, right, top, bottom, near, far)` | Camera space to normalized device space, with perspective. |
| `orthographic(left, right, top, bottom, near, far)` | The same without perspective. `w` stays one. |
| `look_at(eye, target, up)` | The view matrix of a camera at `eye`. |
| `viewport(width, height)` | Normalized device space to pixels. Rows count down. |

Each raises for a degenerate volume. `look_at` never raises. A camera at its own target looks down its own -z. An up vector along the view direction is nudged off it, as three.js does.

Normalized device space is unitless. World space is meters and screen space is pixels. The matrices meet in the middle.

## Triangle and Line3

`math/triangle.mojo`. `Triangle(a, b, c)` holds three corners. They turn counterclockwise when seen from the front.

| Triangle member | Meaning |
|---|---|
| `normal() -> Vector3` | The unit normal. three.js: `getNormal`. |
| `area() -> Float32` | The area. |
| `midpoint() -> Vector3` | The average of the corners. |
| `plane() -> Plane` | The plane the triangle lies in. |
| `barycoord(point) -> Vector3` | The weights of `a`, `b` and `c` at the point's projection onto the plane. |
| `contains_point(point) -> Bool` | True if the projection lies inside or on an edge. |
| `interpolate(point, at_a, at_b, at_c) -> Vector3` | Three corner values mixed by the barycentric weights. |
| `is_front_facing(direction) -> Bool` | True if a ray along the direction meets the front. |
| `closest_point_to_point(point) -> Vector3` | The nearest point on the face, an edge or a corner. |

A degenerate triangle has its corners on one line. It has no normal, no plane and no barycentric coordinates, and those questions raise. three.js answers them with a zero vector or `null`. `closest_point_to_point` still answers: it uses the nearest point of the three edges.

`Triangle.from_points_and_indices(points, a, b, c)` picks three corners from a list. An index out of range raises. `intersects_box(box)` is `Box3.intersects_triangle`. `a == b` compares the corners in order.

`Line3(start, end)` is a segment. `delta()`, `center()`, `distance()`, `distance_sq()` and `at(t)` describe it. `a == b` compares the ends. `closest_point_parameter(point, clamp)` and `closest_point(point, clamp)` find the point nearest a point. A segment of no length raises for them.

`distance_to_line(other)` is the shortest distance between two segments. `closest_points_to_line(other, on_self, on_other)` is three.js's `distanceSqToLine3`. It writes the two nearest points and returns the squared distance. `apply_matrix4(matrix)` moves both ends.

## Spherical and Cylindrical

`math/spherical.mojo`. `Spherical(radius, phi, theta)` names a point by its distance from the origin and two `Angle`s. `phi` goes down from +y. `theta` turns about y from +z. `Cylindrical(radius, theta, y)` names a point by its distance from the y axis, the same `theta` and a height.

`from_vector3(v)` and `to_vector3()` convert both ways. The origin has both spherical angles zero. `Spherical.make_safe()` keeps `phi` a millionth of a radian away from each pole. [OrbitControls](Windowing-and-controls#orbitcontrols) holds its camera's offset as a `Spherical`.

## Matrix2 and Box2

`math/matrix2.mojo`. `Matrix2(m00, m01, m10, m11)` is stored row by row and multiplies a column vector on its right. `identity()`, `rotation(angle)` and `scaling(x, y)` build one. `a * b` applies `b` first.

`determinant()`, `transposed()`, `inverse()` and `transform(v)` are the rest. A singular matrix raises for `inverse`. three.js returns zeros.

`Box2(min, max)` is `Box3` in the plane. It has the same empty box, with its corners inside out. These members work as in `Box3`: `from_points`, `from_center_and_size`, `expand_by_point`, `expand_by_vector`, `expand_by_scalar`, `union`, `intersect`, `translate`, `center`, `size`, `contains_point`, `contains_box`, `get_parameter`, `intersects_box`, `clamp_point`, `distance_to_point` and `==`. The empty box has its center at the origin, as in three.js.

## MathUtils

`math/utils.mojo`. The scalar helpers of three.js's `MathUtils`: `clamp`, `lerp`, `inverse_lerp`, `map_linear`, `damp`, `euclidean_modulo`, `pingpong`, `smootherstep`, `smooth_step`, `is_power_of_two`, `ceil_power_of_two` and `floor_power_of_two`.

`damp(x, y, rate, delta)` takes the frame time as a `Duration`. `smooth_step(x, low, high)` has three.js's argument order. The shaders read `smoothstep(edge0, edge1, x)` from `math/smoothstep.mojo`, in GLSL's order.

A function that a GPU kernel calls must not call `std.math.atan` or `atan2`. They call libm, and a GPU has no libm. On a card before sm_80, `atan2` does not link. Use `atan_float32` and `atan2_float32` from `math/arc_tangent.mojo`. They are Cephes's `atanf` in plain arithmetic, and the CPU calls them too.

`degToRad` and `radToDeg` are not here. An `Angle` converts itself.

`generate_uuid(rng)` is three.js's `generateUUID`, with the numbers from a `SeededRandom`.

`quaternion_from_proper_euler(a, b, c, order)` is three.js's `setQuaternionFromProperEuler`. `order` is a `ProperEulerOrder`: `PROPER_XYX`, `PROPER_YZY`, `PROPER_ZXZ`, `PROPER_XZX`, `PROPER_YXY` or `PROPER_ZYZ`. An invalid one raises; three.js warns.

`normalize(value, component)` and `denormalize(value, component)` convert between a number and a stored integer. `component` is a `ComponentType`, such as `UINT8_COMPONENT`. three.js reads it from the typed array.

`SeededRandom(seed)` is three.js's Mulberry32 generator. `next()` returns a number from zero up to one. `float_in(low, high)`, `float_spread(spread)` and `int_in(low, high)` are three.js's `randFloat`, `randFloatSpread` and `randInt`. The same seed gives the same numbers as three.js's `seededRandom`, on every platform.
