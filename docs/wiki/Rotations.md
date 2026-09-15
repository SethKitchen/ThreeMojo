# Rotations

`math/quaternion.mojo`, `math/euler.mojo`, and the rotation methods of `Object3D`. A node's rotation is a quaternion. Euler angles set it. The rotate methods turn it further. `rotation()` reads Euler angles back out of it.

three.js: `Quaternion`, `Euler`, `Euler.setFromRotationMatrix`, `Euler.setFromQuaternion`, `Object3D.rotation`, `Object3D.rotateX/Y/Z`, `rotateOnAxis`, `rotateOnWorldAxis`, `lookAt`.

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

| Member | Meaning |
|---|---|
| `Euler.from_matrix(matrix, order=XYZ)` | The angles that compose, in `order`, to a pure rotation matrix. |
| `Euler.from_quaternion(q, order=XYZ)` | The same, from a unit quaternion. |
| `to_quaternion() -> Quaternion` | The rotation as a quaternion. |
| `to_matrix() -> Matrix4` | The rotation as a matrix. |
| `EulerOrder.is_valid() -> Bool` | Whether the order names three different axes. |
| `EulerOrder.is_cyclic() -> Bool` | Whether the axes run x, y, z round: `XYZ`, `YZX` or `ZXY`. |

The six orders are `XYZ`, `YXZ`, `ZXY`, `ZYX`, `YZX` and `XZY`. `XYZ` is the default, as in three.js. It turns about x, then about the turned y, then about the twice-turned z. As a matrix that is `Rx * Ry * Rz`.

`from_matrix` and `from_quaternion` are three.js's `setFromRotationMatrix` and `setFromQuaternion`. They work for all six orders. The angles they return rebuild the rotation. The numbers can differ from the ones that made it. Past a right angle on the middle axis, more than one triple makes the same rotation.

At a right angle exactly, the first and third axes fold onto one line, and only one combination of their angles is defined. That is gimbal lock. The whole combination goes to the first angle, and the third angle is zero, as in three.js.

Both refuse an `EulerOrder` that does not name three different axes.

## Object3D methods

| Method | Meaning |
|---|---|
| `set_euler(x, y, z, order=XYZ)` | Set the rotation from three angles. |
| `set_rotation(euler)` | Set the rotation from an `Euler`. |
| `set_quaternion(q)` | Set the rotation directly. |
| `rotation(order=XYZ) -> Euler` | The rotation as three angles, read from the quaternion. three.js's `Object3D.rotation`. |
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
