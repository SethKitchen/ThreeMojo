# Math

`math/vector2.mojo`, `math/vector3.mojo`, `math/matrix4.mojo` and `math/projection.mojo`. Ported from three.js with the same conventions.

three.js: `Vector2`, `Vector3`, `Matrix4`, `Matrix4.makePerspective`, `makeOrthographic`, `lookAt`.

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
| `extract_rotation() -> Matrix4` | The rotation with scale and translation removed. |
| `transform_point(p) -> Vector3` | Apply with `w = 1` and divide by `w`. |
| `transform_w(p) -> Float32` | The `w` that `transform_point` divides by. |
| `transform_direction(d) -> Vector3` | Apply with `w = 0`. |

Builders: `translation(x, y, z)`, `scaling(x, y, z)`, `rotation_x(angle)`, `rotation_y(angle)`, `rotation_z(angle)`. A rotation takes an `Angle`, so `rotation_z(90.0)` does not compile.

```mojo
var m = translation(10, 0, 0)
m.multiply(rotation_z(Angle(90.0, DEGREE)))
m.multiply(translation(-10, 0, 0))     # a rotation about (10, 0, 0)
```

## Projection

| Function | Meaning |
|---|---|
| `perspective(left, right, top, bottom, near, far)` | Camera space to normalized device space, with perspective. |
| `orthographic(left, right, top, bottom, near, far)` | The same without perspective. `w` stays one. |
| `look_at(eye, target, up)` | The view matrix of a camera at `eye`. |
| `viewport(width, height)` | Normalized device space to pixels. Rows count down. |

Each raises for a degenerate volume, a camera at its own target, or an up vector along the view direction.

Normalized device space is unitless. World space is metres and screen space is pixels. The matrices meet in the middle.
