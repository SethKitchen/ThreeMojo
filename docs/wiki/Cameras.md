# Cameras

`cameras/camera.mojo`, `cameras/perspective_camera.mojo`, `cameras/orthographic_camera.mojo`. A camera gives the renderer a view matrix, a camera-to-pixels matrix and two clipping distances. The renderer is generic over the `Camera` trait.

three.js: `Camera`, `PerspectiveCamera`, `OrthographicCamera`.

## Camera trait

| Method | Meaning |
|---|---|
| `view_matrix_in(scene) -> Matrix4` | World space to camera space. Reads the scene when the camera rides a node. |
| `view_matrix() -> Matrix4` | The same, for a placed camera. Raises for an attached one. |
| `view_to_screen_matrix(width, height) -> Matrix4` | Camera space to pixels. |
| `near_distance() -> Float32` | The near clipping distance, in metres. |
| `far_distance() -> Float32` | The far clipping distance, in metres. |

## PerspectiveCamera

```mojo
var camera = PerspectiveCamera(
    Angle(45.0, DEGREE),     # vertical field of view
    4.0 / 3.0,               # aspect ratio, width over height
    Length(0.1, METRE),      # near plane
    Length(100.0, METRE),    # far plane
)
camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
```

The field of view is an `Angle`. A bare number does not compile. The near plane must be positive, and the far plane beyond it.

| Member | Meaning |
|---|---|
| `place(position, target)` | Put the camera at `position`, looking at `target`, with +y up. |
| `attach(node)` | Ride a scene node. See below. |
| `projection_matrix()` | Camera space to normalized device space. |
| `project(point, width, height) -> Vector3` | A world point in pixels, with NDC depth in z. |
| `screen_matrix(width, height)` | World space to pixels in one matrix. |

## OrthographicCamera

```mojo
var flat = centred(
    Length(6.0, METRE), aspect, Length(0.1, METRE), Length(100.0, METRE)
)
```

`OrthographicCamera(left, right, top, bottom, near, far)` takes the volume's edges as lengths. `centred(height, aspect, near, far)` builds a symmetric one. `near` can be zero. The edges must be ordered: right beyond left, top above bottom.

An orthographic projection leaves `w` at one. The perspective correction then divides by one, so no code path is special.

## Attach a camera to a node

```mojo
var eye = Object3D()
eye.set_position(0, 0, 3)
var eye_node = scene.attach(eye^, pivot)
camera.attach(eye_node)
```

An attached camera looks down its node's -z axis with the node's +y up. Its view is the inverse of the node's world position and rotation. Scale is dropped, as three.js drops it. A mirrored node is refused.

Aim an attached camera with `scene.look_at(eye_node, target, camera=True)`. Turn the pivot to orbit it. `place` lets go of the node.

## Errors

- `view_matrix()` raises when the camera is attached. Only the scene knows where the node is.
- `view_matrix_in(scene)` raises when the scene is stale or the node is missing.
- A camera at its own target, or with up along the view direction, raises.

## Example

`examples/photo.mojo` orbits an attached camera around a textured cube.
