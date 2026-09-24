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

### Zoom, film and lens

A perspective camera has three.js's zoom, film and focus. `projection_matrix()` builds from them in the order of three.js's `updateProjectionMatrix`. The values agree with three.js 0.180 to a part in 100,000.

```mojo
camera.zoom = 2
camera.set_focal_length(Length(50.0, MILLIMETER))
var fov = camera.get_effective_fov()          # the field of view after the zoom
var size = camera.get_view_size(Length(10.0, METER))
```

| Member | three.js | Default | Meaning |
|---|---|---|---|
| `zoom` | `zoom` | `1` | Divides the frustum's height and width. Positive. |
| `focus` | `focus` | 10 m | A distance for the scene's JSON. Nothing draws differently for it. Positive. |
| `film_gauge` | `filmGauge` | 35 mm | The film's larger side. Positive. |
| `film_offset` | `filmOffset` | 0 | Moves the film across. The frustum's side edges move by `near * film_offset / film width`. Finite. |
| `get_film_width()`, `get_film_height()` | `getFilmWidth`, `getFilmHeight` | | The film the image covers. A portrait image covers less across, a landscape one less up. |
| `get_focal_length()` | `getFocalLength` | | The lens that sees `fov` on this film, as a `Length`. |
| `set_focal_length(length)` | `setFocalLength` | | Sets `fov` from a lens. The length must be positive. |
| `get_effective_fov()` | `getEffectiveFOV` | | The vertical field of view after the zoom, as an `Angle`. |
| `get_view_bounds(distance)` | `getViewBounds` | | The lower-left and upper-right corners of the view at a distance, in a `ViewBounds`. |
| `get_view_size(distance)` | `getViewSize` | | The width and height of the view at a distance, as a `Vector2`. |
| `validate()` | | | Refuses a zoom, film, focus or view that is not one. |

The film is a `Length`, where three.js takes a bare number in millimeters. Only the ratio of the offset to the gauge reaches the projection. `view_shift` is added to the side edges last, after the film offset.

The fields are open. `projection_matrix()` calls `validate()` first, so a bad value raises there. three.js takes the same value and makes a projection of infinities.

## View offset

`set_view_offset(full_width, full_height, x, y, width, height)` makes a camera draw one tile of a larger image: three.js's `setViewOffset`. Both cameras have it. Use it for a wall of monitors or for a render in tiles.

```mojo
# Three monitors side by side, each 1920 by 1080. This one is the middle.
camera.set_view_offset(5760, 1080, 1920, 0, 1920, 1080)
```

The numbers are pixels of the full image, and need not be whole. The tile starts `x` across and `y` down. The camera keeps the tile in `view`, a `ViewOffset`. A perspective camera also sets its aspect to `full_width / full_height`, as three.js does. An orthographic camera keeps its edges and cuts the tile from the zoomed box.

`clear_view_offset()` draws the whole image again. It keeps the tile and sets its `enabled` to false, as three.js does, so the scene's JSON still carries it. Every number must be finite, and every width and height positive. `set_view_offset` refuses a bad tile and leaves the camera as it was. `projection_matrix()` refuses a bad tile that was written into `view` afterward.

## OrthographicCamera

```mojo
var flat = centered(
    Length(6.0, METER), aspect, Length(0.1, METER), Length(100.0, METER)
)
```

`OrthographicCamera(left, right, top, bottom, near, far)` takes the volume's edges as lengths. `centered(height, aspect, near, far)` builds a symmetric one. `near` can be zero or negative, as in three.js: a top-down view often puts it behind the camera. The edges must be ordered: right beyond left, top above bottom.

An orthographic projection leaves `w` at one. The perspective correction then divides by one, so no code path is special.


`zoom` magnifies the view, three.js's `zoom`. The volume's width and height are divided by it about their center. It is one by default and must be positive. [OrbitControls](Windowing-and-controls#orthographic-cameras) zooms an orthographic camera by changing it.

An orthographic camera also has `set_view_offset` and `clear_view_offset`. See [View offset](#view-offset).

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

`add` copies its camera. A `StereoCamera` updated afterward does not reach an array that already holds its eyes, so rebuild the array after each update. The two lists are open, and `count` refuses lists of different lengths. A camera refused after an earlier one drew leaves that one's rectangle drawn: the renderer's settings are put back, the target is not. Where two rectangles overlap, the later camera clears and replaces the overlap.

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
| `focus` | `camera.focus` | 10 m | How far ahead the two views cross. Positive. three.js reads the camera's `focus`. This port keeps its own. |
| `aspect` | `aspect` | `1.0` | What the camera's aspect is multiplied by for each eye. A half for a side-by-side pair. |

`update(camera, scene)` places `left` and `right` from the camera as it stands, placed or riding a node of the scene. The eyes take the camera's field of view, zoom, planes and layers. They do not take its film offset or view offset, as in three.js. The skew is `eye_separation / 2 * near / focus` at the near plane, three.js's own arithmetic, set as each eye's `view_shift`. A point at the focus lands on the same column in both eyes. A nearer point lands further apart, which is the parallax.

The three settings are open fields. `validate()` refuses a negative or non-finite separation and a focus or aspect that is not positive and finite. `update` calls it before it places an eye. It builds both eyes before it keeps either, so a refused update leaves the pair as it was.

An eye is a placed camera with a `Float32` position. A million meters from the origin a `Float32` steps in sixteenths of a meter. A sixty-four millimeter baseline is then lost, while the skew still assumes it. Keep a stereo scene within a few thousand meters of the origin, or rebase the scene on the camera. There the baseline holds to a part in a hundred. The test suite pins the baseline at a thousand meters.

`examples/stereo.mojo` draws a stereo pair of a box and a ring, side by side, from a circling camera.

## CubeCamera

`CubeCamera` stands at one point and looks out along each axis in turn. Its six square views have a ninety degree field of view, and together they see everything around it. three.js's `CubeCamera.update(renderer, scene)` renders the six into a cube render target. Here `Renderer.render_cube(scene, assets, camera)` renders them into six images and returns the [cube texture](Textures#cube-textures) built from them.

```mojo
from cameras.cube_camera import CubeCamera

var eye = CubeCamera(Length(0.1, METER), Length(50.0, METER), 64)
eye.attach(ball_node)
var seen = assets.cube_textures.add(renderer.render_cube(scene, assets, eye))
var chrome = Material(Color(255, 255, 255), kind=BASIC, env_map=seen)
```

| Member | Meaning |
|---|---|
| `CubeCamera(near, far, size)` | Two `Length` planes and the width of each face in pixels. |
| `place(position)` | Stand at a world-space point. Lets go of any node. |
| `attach(node)` | Stand wherever the scene puts a node. Only its position is read. |
| `eye(scene) -> Vector3` | Where the camera stands. |
| `face_camera(face, scene) -> PerspectiveCamera` | The camera that draws one face, placed. |
| `layers` | Which layers the six faces draw. Layer zero alone to begin with. |

Each face camera looks along `face_forward(face)` with `face_up(face)` as its up. Those are the two tables the cube texture sampler reads with, and three.js's own six ups. So a rendered cube reflects the scene it was rendered from with no flip. The node's own turn is not read: a cube texture is sampled in world space.

`render_cube` draws each face with a renderer of the face's size and this renderer's background, shading and workers, through `render`. The scene's own background is in the faces. The tone mapping is left off, as three.js turns it off around its update: the faces are light the main frame maps once.

A cube camera at the center of a mirror ball sees the inside of the ball. three.js's examples hide the ball around the update. Here the camera has `layers`, as every camera has. Put the ball on a layer of its own and the main camera on both, and the cube camera does not draw it.

The constructor refuses a size that is not positive. It refuses a near plane that is not in front of the camera, and a far plane that is not beyond it. A face that is none of the six is refused, and so is a stale scene or a missing node. `tests/compile_fail/` proves a bare float is not a plane.

`examples/mirror.mojo` renders a cube camera's view every frame and reflects it in a chrome ball.

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
