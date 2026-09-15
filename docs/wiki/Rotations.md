# Rotations

`math/quaternion.mojo`, `math/euler.mojo`, and the rotation methods of `Object3D`. A node's rotation is a quaternion. Euler angles set it. The rotate methods turn it further.

three.js: `Quaternion`, `Euler`, `Object3D.rotateX/Y/Z`, `rotateOnAxis`, `rotateOnWorldAxis`, `lookAt`.

## Quaternion

A rotation as `(x, y, z, w)`. The identity is `(0, 0, 0, 1)`. `a * b` applies `b` first and then `a`, as the matrices do.

| Member | Meaning |
|---|---|
| `Quaternion.identity()` | No rotation. |
| `Quaternion.from_axis_angle(axis, angle)` | A turn of `angle` about a unit `axis`. |
| `Quaternion.from_matrix(matrix)` | The rotation a pure rotation matrix applies. |
| `to_matrix() -> Matrix4` | The rotation as a matrix. |
| `multiply(other)` | `self = self * other`. |
| `premultiply(other)` | `self = other * self`. |
| `rotate(v) -> Vector3` | `v` turned by this rotation. |
| `conjugate() -> Quaternion` | The inverse of a unit quaternion. |
| `normalize()` | Scale to unit length. Zero becomes the identity. |
| `slerp(other, t) -> Quaternion` | The rotation a fraction `t` along the shortest arc to `other`. |
| `dot(other)`, `length()` | The four-component dot product and length. |

`from_matrix` expects a pure rotation. Use `Matrix4.extract_rotation` first when the matrix carries scale.

## Euler and EulerOrder

`Euler(x, y, z, order)` holds three angles and an order. `to_quaternion()` and `to_matrix()` compose the three axis rotations in that order.

The six orders are `XYZ`, `YXZ`, `ZXY`, `ZYX`, `YZX` and `XZY`. `XYZ` is the default, as in three.js. It turns about x, then about the turned y, then about the twice-turned z. As a matrix that is `Rx * Ry * Rz`.

Reading Euler angles back out of a rotation is not ported.

## Object3D methods

| Method | Meaning |
|---|---|
| `set_euler(x, y, z, order=XYZ)` | Set the rotation from three angles. |
| `set_rotation(euler)` | Set the rotation from an `Euler`. |
| `set_quaternion(q)` | Set the rotation directly. |
| `rotate_x(angle)`, `rotate_y(angle)`, `rotate_z(angle)` | Turn about the node's own axis. three.js's `rotateX`, `rotateY`, `rotateZ`. |
| `rotate_on_axis(axis, angle)` | Turn about a unit axis in the node's own frame. |
| `rotate_on_world_axis(axis, angle)` | Turn about a unit axis in the parent's frame. |
| `look_at(target, camera=False)` | Face a point given in the parent's frame. Up is the parent's +y. |

`rotate_y` is not `rotation.y += angle` in three.js terms. The two agree only while the other two angles are zero. An Euler component is not a local axis.

## Scene.look_at

`scene.look_at(id, target, camera=False)` faces a world-space point. It builds the facing in world space with world up, then undoes the parent's rotation. The parent's scale is normalized away. A mirrored or flattened parent is refused.

An object faces the target with its +z axis. A camera faces it with its -z axis. Pass `camera=True` for a node that a camera rides.

Both `look_at` methods refuse a target at the node's own position, and a target straight along the up direction.

## Example

```mojo
var node = Object3D()
node.set_euler(Angle(20.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
node.rotate_y(Angle(10.0, DEGREE))      # about the tilted y axis

var half = Quaternion.identity().slerp(
    Quaternion.from_axis_angle(Vector3(0, 0, 1), Angle(90.0, DEGREE)), 0.5
)                                        # a 45 degree turn
```
