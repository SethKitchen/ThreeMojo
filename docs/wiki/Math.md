# Math

`math/vector2.mojo`, `math/vector3.mojo`, `math/vector4.mojo`, `math/matrix3.mojo`, `math/matrix4.mojo`, `math/bounds.mojo`, `math/frustum.mojo`, `math/ray.mojo` and `math/projection.mojo`. Ported from three.js with the same conventions.

![A quaternion turns a vector, and a sphere follows that point](out/math.png)

three.js: `Vector2`, `Vector3`, `Vector4`, `Matrix3`, `Matrix4`, `Matrix4.makePerspective`, `makeOrthographic`, `lookAt`, `Box3`, `Sphere`, `Plane`, `Frustum`, `Ray`.

## Vector2 and Vector3

`Vector2(x, y)` and `Vector3(x, y, z)` hold `Float32` components. Both are value types. Assignment copies.

`Vector2` has the same members in two dimensions, plus `cross(other) -> Float32`, which is the one component a cross product has in a plane. It is positive when `other` lies to the left of `self`. The curves asked for them; see [Curves and paths](Curves).

| Vector3 member | Meaning |
|---|---|
| `dot(other) -> Float32` | The dot product. |
| `length() -> Float32` | The Euclidean length. |
| `add(other)`, `sub(other)` | Change `self` in place. |
| `cross(other)` | `self = self × other`. |
| `normalize()` | Scale to unit length. A zero vector stays zero. |
| `a + b`, `a - b`, `a * f`, `-a` | Return a new vector. |

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

Builders: `translation(x, y, z)`, `scaling(x, y, z)`, `rotation_x(angle)`, `rotation_y(angle)`, `rotation_z(angle)`. A rotation takes an `Angle`, so `rotation_z(90.0)` does not compile.

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

| Sphere member | Meaning |
|---|---|
| `Sphere(center, radius)`, `Sphere.empty()` | A negative radius is the empty sphere. |
| `Sphere.from_points(points)` | Centered on the points' box, reaching the farthest point. |
| `is_empty()`, `contains_point(p)`, `distance_to_point(p)` | The distance is signed: negative inside. |
| `intersects_sphere(other)`, `intersects_box(box)` | Touching counts. |
| `expand_by_point(p)` | Grow in place, by as little as possible. |
| `apply_matrix4(m)` | Move the center. The radius grows by `max_stretch`. |
| `bounding_box() -> Box3` | The box around the sphere. |

| Plane member | Meaning |
|---|---|
| `Plane(normal, constant)` | The points where `dot(normal, p) + constant` is zero. The normal is made unit length, and the constant scaled with it. |
| `Plane.from_normal_and_point(n, p)` | Through `p`, facing `n`. |
| `Plane.from_coplanar_points(a, b, c)` | Through three points, facing the side they wind counter-clockwise from. |
| `distance_to_point(p)`, `distance_to_sphere(s)` | Signed: positive in front. |
| `project_point(p)`, `coplanar_point()` | The nearest point on the plane. |
| `negate()`, `translate(offset)` | Turn around, or move, in place. |
| `intersects_sphere(s)`, `intersects_box(box)` | Whether the plane passes through it. |

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

Each raises for a degenerate volume, a camera at its own target, or an up vector along the view direction.

Normalized device space is unitless. World space is meters and screen space is pixels. The matrices meet in the middle.
