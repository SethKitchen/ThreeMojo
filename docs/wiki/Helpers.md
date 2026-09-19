# Helpers

`helpers/`. A helper is a line geometry that shows something about the scene. There are four: the axes of a frame, a grid on the ground, the box around a mesh, and what a camera sees. Each builder returns a `BufferGeometry` for a [`Line`](Lines) in `SEGMENTS` mode.

![A camera circles a cube outlined in yellow, over a grid, beside the axes and a second camera's frustum](out/helpers.png)

three.js: `AxesHelper`, `GridHelper`, `BoxHelper`, `Box3Helper`, `CameraHelper`.

## A helper is a geometry

three.js's helpers are objects. Each one owns a geometry and a material and hangs in the scene graph. Here a helper is the geometry alone. The caller stores it, draws it with a `Line`, and places it on a node, as with any other line. So a helper is shared, sorted, culled and fogged exactly as a line is.

```mojo
from helpers.axes import axes_helper
from helpers.material import helper_material
from objects.line import Line, SEGMENTS

var paint = assets.materials.add(helper_material())
var axes = assets.geometries.add(axes_helper(Length(1.0, METER)))
scene.add_line(Line(axes, paint, node, mode=SEGMENTS))
```

`helper_material()` is the material three.js gives each colored helper: white, unlit, and tinted by the geometry's `color` attribute at every vertex. It takes an `opacity`, a `blending` and `transparent`, as a [material](Materials) does.

three.js's helper materials are not tone mapped. Tone mapping here is applied once to every pixel of a frame, so a helper under a tone curve is curved with the scene. See [tone mapping](Render-target-and-framebuffer#tone-mapping).

## AxesHelper

`axes_helper(size)` is three sticks from the origin. The x stick is red, the y stick green and the z stick blue. Each is paler at its far end, so the direction reads. The colors are the linear floats three.js writes into the attribute.

| Argument | Default | Meaning |
|---|---|---|
| `size` | `Length(1.0, METER)` | How far along each axis the stick reaches. Must be positive. |

## GridHelper

`grid_helper(size, divisions, center_color, grid_color)` is a square of lines in the xz plane, centered on the origin.

| Argument | Default | Meaning |
|---|---|---|
| `size` | `Length(10.0, METER)` | How long the square is on a side. Must be positive. |
| `divisions` | `10` | How many cells across and deep. At least one. |
| `center_color` | `Color(0x44, 0x44, 0x44)` | The two lines through the origin, as authored in sRGB. |
| `grid_color` | `Color(0x88, 0x88, 0x88)` | Every other line. |

The colors are authored bytes, as three.js's `Color(0x444444)` is, and are decoded to linear light on the way in. See [Why color is linear](Why-color-is-linear).

An odd division count has no center line. three.js compares the step to `divisions / 2`, a float that no integer step reaches when the count is odd. The lines straddle the origin, and none takes the center color. That is what three.js draws.

## BoxHelper

`box_helper(box)` is the twelve edges of a `Box3`, as twenty-four points. It carries no `color` attribute: the material colors it. three.js draws it yellow, and `DEFAULT_BOX_COLOR` is that yellow.

three.js has two helpers here. `BoxHelper` takes an object and measures its world-space bounds. `Box3Helper` takes a box. Both draw the same edges, and here they are one builder that takes the box. A mesh's world bounds are its geometry's bounds carried through its node's world matrix, which is what `Box3.setFromObject` does:

```mojo
from helpers.box import DEFAULT_BOX_COLOR, box_helper

var bounds = assets.geometries.get(block).bounding_box()
bounds.apply_matrix4(scene.world_matrix(placed))
var yellow = assets.materials.add(Material(DEFAULT_BOX_COLOR, kind=BASIC))
var edges = assets.geometries.add(box_helper(bounds))
scene.add_line(Line(edges, yellow, root, mode=SEGMENTS))
```

The points are where the box is, so the `Line` belongs on a node at the origin. three.js's `BoxHelper` leaves its own matrix the identity for the same reason. An empty box is refused.

## CameraHelper

`camera_helper(camera)` is the outline of what a camera sees, in the camera's own frame: fifty points, twenty-five lines, five colors.

| Part | Lines | Argument | Default |
|---|---|---|---|
| Frustum | The near and far rectangles, and the four edges between them. | `frustum_color` | `Color(0xFF, 0xAA, 0x00)` |
| Cone | Four lines from the apex to the near corners. | `cone_color` | `Color(0xFF, 0x00, 0x00)` |
| Up | A triangle above the near plane. | `up_color` | `Color(0x00, 0xAA, 0xFF)` |
| Target | The line from the near plane's center to the far plane's. | `target_color` | `Color(0xFF, 0xFF, 0xFF)` |
| Cross | The line from the apex to the near center, and a cross on each plane. | `cross_color` | `Color(0x33, 0x33, 0x33)` |

Every point is a corner of clip space carried back through the inverse of the camera's projection. That is three.js's `unproject` against a camera whose world matrix is the identity. The near rectangle lands at `z = -near` and the far one at `z = -far`, in the camera's frame. Put the `Line` on the node the camera rides, and the outline stands where the camera stands:

```mojo
from helpers.camera import camera_helper

scene.look_at(perch, target, camera=True)
watched.attach(perch)
var outline = assets.geometries.add(camera_helper(watched))
scene.add_line(Line(outline, paint, perch, mode=SEGMENTS))
```

The apex is clip space's origin carried back, which is not the camera's position. Under a perspective projection it is a point between the two planes, at `-2nf / (f + n)`. The cone reaches it from the near corners. That is what three.js draws.

The helper reads the camera's projection once, when it is built. A camera whose projection changes needs a new helper, as three.js's needs `update()`.

## Members

| Function | Returns |
|---|---|
| `helper_material(opacity, blending, transparent)` | The white, unlit, vertex-colored material. |
| `axes_helper(size)` | Six points with colors. |
| `grid_helper(size, divisions, center_color, grid_color)` | `4 * (divisions + 1)` points with colors. |
| `box_helper(box)` | Twenty-four points, no colors. |
| `camera_helper(camera, ...)` | Fifty points with colors. |

## What raises

- A size that is not positive, on the axes or the grid.
- A division count below one.
- An empty box.
- An opacity outside zero to one, or a blending that is neither named value, on the material.
