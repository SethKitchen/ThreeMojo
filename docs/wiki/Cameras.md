# Cameras

`cameras/camera.mojo`, `cameras/perspective_camera.mojo`, `cameras/orthographic_camera.mojo`, `cameras/array_camera.mojo`, `cameras/stereo_camera.mojo`. A camera gives the renderer a view matrix, a camera-to-pixels matrix and two clipping distances. The renderer is generic over the `Camera` trait.

![An orthographic camera rides a pivot around a cube](out/cameras.png)

three.js: `Camera`, `PerspectiveCamera`, `OrthographicCamera`, `ArrayCamera`, `StereoCamera`.

## Camera trait

| Method | Meaning |
|---|---|
| `view_matrix_in(scene) -> Matrix4` | World space to camera space. Reads the scene when the camera rides a node. |
| `view_matrix() -> Matrix4` | The same, for a placed camera. Raises for an attached one. |
| `projection_matrix() -> Matrix4` | Camera space to normalized device space. The renderer reads its frustum from it. See [Renderer](Renderer#frustum-culling). |
| `view_to_screen_matrix(width, height) -> Matrix4` | Camera space to pixels. |
| `near_distance() -> Float32` | The near clipping distance, in meters. |
| `far_distance() -> Float32` | The far clipping distance, in meters. |
| `visible_layers() -> Layers` | Which layers the camera draws. See [Scene graph](Scene-graph#layers). |

## PerspectiveCamera

```mojo
var camera = PerspectiveCamera(
    Angle(45.0, DEGREE),     # vertical field of view
    4.0 / 3.0,               # aspect ratio, width over height
    Length(0.1, METER),      # near plane
    Length(100.0, METER),    # far plane
)
camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
```

The field of view is an `Angle`. A bare number does not compile. The near plane must be positive, and the far plane beyond it.

`PerspectiveCamera(fov, aspect, near, far, view_shift=Length(0.02, METER))` moves the frustum's two side edges along x at the near plane, keeping their distance apart. The camera then looks a little to one side without turning. Zero, the default, looks straight ahead. A `StereoCamera` sets it on each eye. The shift is a `Length`, and must be finite.

| Member | Meaning |
|---|---|
| `place(position, target)` | Put the camera at `position`, looking at `target`, with +y up. |
| `attach(node)` | Ride a scene node. See below. |
| `layers` | The layers it draws. Layer zero by default. Both cameras have it. |
| `projection_matrix()` | Camera space to normalized device space. |
| `project(point, width, height) -> Vector3` | A world point in pixels, with NDC depth in z. |
| `screen_matrix(width, height)` | World space to pixels in one matrix. |

## OrthographicCamera

```mojo
var flat = centered(
    Length(6.0, METER), aspect, Length(0.1, METER), Length(100.0, METER)
)
```

`OrthographicCamera(left, right, top, bottom, near, far)` takes the volume's edges as lengths. `centered(height, aspect, near, far)` builds a symmetric one. `near` can be zero or negative, as in three.js: a top-down view often puts it behind the camera. The edges must be ordered: right beyond left, top above bottom.

An orthographic projection leaves `w` at one. The perspective correction then divides by one, so no code path is special.

## ArrayCamera

`ArrayCamera` is a list of perspective cameras, each with the rectangle of the image it draws into: three.js's `ArrayCamera` and its sub cameras' `viewport`. `Renderer.render_array` draws the scene once per camera, into that camera's rectangle, and resolves the image once.

```mojo
from cameras.array_camera import ArrayCamera

var wall = ArrayCamera()
wall.add(left_camera, Rect(0, 0, 120, 120))
wall.add(right_camera, Rect(120, 0, 120, 120))
var image = renderer.render_array(scene, assets, wall)
```

| Member | Meaning |
|---|---|
| `ArrayCamera()` | An array of no cameras. |
| `add(camera, viewport)` | Add a camera and its rectangle. The rectangle must hold a pixel. |
| `count()` | How many cameras. |
| `cameras`, `viewports` | The two lists. |
| `renderer.render_array(scene, assets, array)` | The image, one rectangle per camera. |
| `renderer.render_array_into(target, scene, assets, array)` | The same into a target you hold, resolved by you. |

Each rectangle is cleared to the background and drawn with the scissor on, so nothing of one reaches another. Pixels outside every rectangle keep the background. A rectangle must lie inside the target, and every rectangle is checked before any is drawn. The renderer's own viewport, scissor and scissor test are put back afterward. Each camera keeps its own aspect: one that does not match its rectangle draws a squeezed image, as three.js's does.

## StereoCamera

`StereoCamera` makes a left and a right eye from one camera: three.js's `StereoCamera`. Each eye stands half `eye_separation` to its side of the camera and looks the same way. Each eye's frustum is skewed toward the other so the two views cross at `focus`. Draw the eyes through an `ArrayCamera` for a side-by-side image.

```mojo
from cameras.stereo_camera import StereoCamera

var stereo = StereoCamera(
    eye_separation=Length(0.064, METER), focus=Length(10.0, METER), aspect=0.5
)
stereo.update(camera, scene)
var eyes = ArrayCamera()
eyes.add(stereo.left, Rect(0, 0, 120, 120))
eyes.add(stereo.right, Rect(120, 0, 120, 120))
```

| Argument | three.js | Default | Meaning |
|---|---|---|---|
| `eye_separation` | `eyeSep` | 64 mm | How far apart the eyes are. Not negative. |
| `focus` | `camera.focus` | 10 m | How far ahead the two views cross. Positive. |
| `aspect` | `aspect` | `1.0` | What the camera's aspect is multiplied by for each eye. A half for a side-by-side pair. |

`update(camera, scene)` places `left` and `right` from the camera as it stands, placed or riding a node of the scene. The eyes take the camera's field of view, planes and layers. The skew is `eye_separation / 2 * near / focus` at the near plane, three.js's own arithmetic, set as each eye's `view_shift`. A point at the focus lands on the same column in both eyes. A nearer point lands further apart, which is the parallax.

`examples/stereo.mojo` draws a stereo pair of a box and a ring, side by side, from a circling camera.

## Attach a camera to a node

```mojo
var eye = Object3D()
eye.set_position(0, 0, 3)
var eye_node = scene.attach(eye^, pivot)
camera.attach(eye_node)
```

An attached camera looks down its node's -z axis with the node's +y up. Its view is the inverse of the node's world position and rotation. Scale is dropped, as three.js drops it. The node's world axes must stay at right angles. A nonuniform scale above a turn shears them, and the node is refused. A mirrored or flattened node is refused.

Aim an attached camera with `scene.look_at(eye_node, target, camera=True)`. Turn the pivot to orbit it. `place` lets go of the node.

The two contracts differ, because `look_at` carries a facing into the parent's frame and a camera only drops a scale. The table lists what each accepts of a world transform: the camera's node, or the parent of the node `look_at` turns.

| World transform | Attached camera node | Parent of a `Scene.look_at` node |
|---|---|---|
| Rotation and translation | Accepted | Accepted |
| Uniform scale | Accepted, dropped | Accepted, normalized away |
| Nonuniform scale along the node's own axes | Accepted, dropped | Refused |
| Nonuniform scale above a turn, which shears | Refused | Refused |
| Mirror, a negative scale | Refused | Refused |
| Flattened axis, a scale of zero | Refused | Refused |

## Errors

- `view_matrix()` raises when the camera is attached. Only the scene knows where the node is.
- `view_matrix_in(scene)` raises when the scene is stale or the node is missing.
- `view_matrix_in(scene)` raises when the node's world transform is mirrored, flattened or sheared.
- A camera at its own target keeps the identity rotation. An up along the view direction is nudged off it by a ten-thousandth, as three.js's `lookAt` does. Neither raises.

## Example

`examples/ortho.mojo` orbits an attached `OrthographicCamera` around a cube. `examples/photo.mojo` does the same with a perspective camera and a decoded PNG.
