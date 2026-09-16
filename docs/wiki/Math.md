# Math

`math/vector2.mojo`, `math/vector3.mojo`, `math/matrix4.mojo`, `math/bounds.mojo` and `math/projection.mojo`. Ported from three.js with the same conventions.

three.js: `Vector2`, `Vector3`, `Matrix4`, `Matrix4.makePerspective`, `makeOrthographic`, `lookAt`, `Box3`, `Sphere`, `Plane`.

## Vector2 and Vector3

`Vector2(x, y)` and `Vector3(x, y, z)` hold `Float32` components. Both are value types. Assignment copies.

| Vector3 member | Meaning |
|---|---|
| `dot(other) -> Float32` | The dot product. |
| `length() -> Float32` | The Euclidean length. |
| `add(other)`, `sub(other)` | Change `self` in place. |
| `cross(other)` | `self = self × other`. |
| `normalize()` | Scale to unit length. A zero vector stays zero. |
| `a + b`, `a - b`, `a * f`, `-a` | Return a new vector. |

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

## Projection

| Function | Meaning |
|---|---|
| `perspective(left, right, top, bottom, near, far)` | Camera space to normalized device space, with perspective. |
| `orthographic(left, right, top, bottom, near, far)` | The same without perspective. `w` stays one. |
| `look_at(eye, target, up)` | The view matrix of a camera at `eye`. |
| `viewport(width, height)` | Normalized device space to pixels. Rows count down. |

Each raises for a degenerate volume, a camera at its own target, or an up vector along the view direction.

Normalized device space is unitless. World space is meters and screen space is pixels. The matrices meet in the middle.
