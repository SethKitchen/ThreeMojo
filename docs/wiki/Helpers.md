# Helpers

`helpers/`. A helper is a line geometry that shows something about the scene. Each builder returns a `BufferGeometry` for a [`Line`](Lines) in `SEGMENTS` mode. There are helpers for axes, grids, boxes, cameras, arrows, planes, skeletons, lights, and vertex normals and tangents.

![A camera circles a cube outlined in yellow, over a grid, beside the axes and a second camera's frustum](out/helpers.png)

three.js: `AxesHelper`, `GridHelper`, `PolarGridHelper`, `BoxHelper`, `Box3Helper`, `CameraHelper`, `ArrowHelper`, `PlaneHelper`, `SkeletonHelper`, `DirectionalLightHelper`, `PointLightHelper`, `HemisphereLightHelper`, `SpotLightHelper`, `RectAreaLightHelper`, `VertexNormalsHelper`, `VertexTangentsHelper`.

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

## PolarGridHelper

`polar_grid_helper(radius, sectors, rings, divisions, color1, color2)` is a round grid in the xz plane, centered on the origin. It is spokes from the origin, then rings from the outside in.

| Argument | Default | Meaning |
|---|---|---|
| `radius` | `Length(10.0, METER)` | How far the grid reaches. Must be positive. |
| `sectors` | `16` | How many spokes. Zero or one draws no spoke, as in three.js. |
| `rings` | `8` | How many rings. The outermost ring is at `radius`. |
| `divisions` | `64` | How many segments make each ring. |
| `color1` | `Color(0x44, 0x44, 0x44)` | The odd spokes and rings. |
| `color2` | `Color(0x88, 0x88, 0x88)` | The even spokes and rings, the first included. |

A count must not be negative. A count of zero draws nothing of that part, so the result can be empty.

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

The points are where the box was when the helper was built. It does not follow a node that moves; build it again. The `Line` belongs on a node at the origin. three.js's `BoxHelper` leaves its own matrix the identity for the same reason. An empty box is refused.

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

## ArrowHelper

`arrow_helper(direction, origin, length, color, head_length, head_width)` is an arrow from `origin` along `direction`. It is twenty-two points: the shaft, the five sides of the head's base, and the five edges from the base to the tip.

| Argument | Default | Meaning |
|---|---|---|
| `direction` | `Vector3(0, 0, 1)` | Which way the arrow points. Any length but zero. |
| `origin` | `Vector3(0, 0, 0)` | Where the arrow starts. |
| `length` | `Length(1.0, METER)` | How long the arrow is, tip included. Must be positive. |
| `color` | `Color(0xFF, 0xFF, 0x00)` | The color of the whole arrow. |
| `head_length` | A fifth of `length` | How long the head is. Must be positive. |
| `head_width` | A fifth of `head_length` | How wide the head's base is. Must be positive. |

three.js fills the head as a solid cone of five sides. Here the head is the ten edges of that cone. The rotation is three.js's `setDirection`. A direction near +y gets no turn, and a direction near -y gets a half turn about x.

A head longer than the arrow leaves a shaft of one ten-thousandth of a meter, as in three.js.

## PlaneHelper

`plane_helper(plane, size, color)` is a square on a `Plane`, with its two diagonals. It is fourteen points, the seven segments of three.js's line strip.

| Argument | Default | Meaning |
|---|---|---|
| `plane` | | The plane to show. |
| `size` | `Length(1.0, METER)` | How long the square is on a side. Must be positive. |
| `color` | `Color(0xFF, 0xFF, 0x00)` | The color of every line. |

The center of the square is the point of the plane nearest the origin. The +z of the square is the normal of the plane. The points are in world space, so put the `Line` on a node at the origin.

three.js also fills the square with a faint mesh. That fill is not a line, and this helper does not build it.

## SkeletonHelper

`skeleton_helper(skeleton, scene, bone_color, parent_color)` is one segment for each bone whose parent is also a bone. The segment goes from the world position of the bone to the world position of its parent.

| Argument | Default | Meaning |
|---|---|---|
| `skeleton` | | The [skeleton](Skinning) to draw. |
| `scene` | | The scene that holds the bones. Call `scene.update()` first. |
| `bone_color` | `Color(0x00, 0x00, 0xFF)` | The color at the end of the bone. |
| `parent_color` | `Color(0x00, 0xFF, 0x00)` | The color at the end of the parent. |

A parent is a bone if the same skeleton names its node. The root bone has no segment. A skeleton of one bone gives an empty geometry. The points are in world space, so put the `Line` on a node at the origin.

```mojo
from helpers.skeleton import skeleton_helper

scene.update()
var bones = assets.geometries.add(skeleton_helper(skeleton, scene))
scene.add_line(Line(bones, paint, root, mode=SEGMENTS))
```

## Light helpers

`helpers/light.mojo` has one helper for each kind of light with a node. Each helper reads a `Light` and the scene that holds its node. It returns points in world space, so put the `Line` on a node at the origin.

```mojo
from helpers.light import spot_light_helper

scene.update()
var cone = assets.geometries.add(spot_light_helper(lamp, scene))
scene.add_line(Line(cone, paint, root, mode=SEGMENTS))
```

| Function | three.js | Lines |
|---|---|---|
| `directional_light_helper(light, scene, size, color)` | `DirectionalLightHelper` | A square of half-side `size` at the light, facing the target, and a line to the target. Ten points. |
| `point_light_helper(light, scene, sphere_size, color)` | `PointLightHelper` | The twelve edges of an octahedron of radius `sphere_size`. Twenty-four points. |
| `hemisphere_light_helper(light, scene, size, color)` | `HemisphereLightHelper` | An octahedron of `size`, three edges for each face. Forty-eight points. |
| `spot_light_helper(light, scene, color)` | `SpotLightHelper` | Five lines from the light and a rim of thirty-two segments. Seventy-four points. |
| `rect_area_light_helper(light, scene, color)` | `RectAreaLightHelper` | The four sides of the rectangle. Eight points. |

Each size is a `Length` of one meter by default, and must be positive. Each color is an `Optional[Color]`. When it is unset, the helper uses the color of the light, as three.js does.

- The hemisphere helper colors the four faces on the sky side with the sky color. It colors the other four faces with the ground color. Its sky corner points from the origin toward the node of the light.
- The spot helper's cone reaches the light's `distance`. A light with no cutoff gives a cone of one thousand meters, as in three.js. The cone is as wide as the light's `angle`.
- The rect area helper uses the color of the light times its intensity. If a channel is above one, the helper divides all three channels by the largest. That keeps the hue, as three.js does.

The point light helper uses the full world matrix of the light's node, as three.js does. The rect area helper uses the rotation and position of the node, but not its scale, as three.js does. The directional, hemisphere and spot helpers aim with three.js's `lookAt`, with +y up. three.js also scales those parts by the world scale of the node. This port does not apply that scale.

The helper shows the light as it was when you built it. After the light or its node moves, build the helper again. three.js calls `update()` for the same reason.

A helper refuses a light of a different kind, and a light kind that `is_valid` refuses. It also refuses a light that `Light.validate` refuses.

## VertexNormalsHelper and VertexTangentsHelper

`vertex_normals_helper(geometry, world, size, color)` is a stick at each vertex along its normal. `vertex_tangents_helper(geometry, world, size, color)` is a stick at each vertex along its tangent.

| Argument | Default | Meaning |
|---|---|---|
| `geometry` | | The geometry to show. It must have one normal, or one tangent, for each position. |
| `world` | | The world matrix of the mesh's node, from `scene.world_matrix`. |
| `size` | `Length(1.0, METER)` | How long each stick is. Must be positive. |
| `color` | `Color(0xFF, 0x00, 0x00)` for normals, `Color(0x00, 0xFF, 0xFF)` for tangents | The color of every stick. |

The result is two points for each vertex, in world space, so put the `Line` on a node at the origin. The normal matrix carries a normal, so the normal stays perpendicular to a stretched surface. The world matrix carries a tangent, as three.js's `transformDirection` does. A normal or tangent of zero length gives a stick of zero length.

A geometry holds any attribute by name. `TANGENT` is `"tangent"`, the name that three.js uses, with four floats for each vertex. The helper reads the first three. This port has no `computeTangents`, so the tangents must come from a loader or from you.

## Members

| Function | Returns |
|---|---|
| `helper_material(opacity, blending, transparent)` | The white, unlit, vertex-colored material. |
| `axes_helper(size)` | Six points with colors. |
| `grid_helper(size, divisions, center_color, grid_color)` | `4 * (divisions + 1)` points with colors. |
| `box_helper(box)` | Twenty-four points, no colors. |
| `camera_helper(camera, ...)` | Fifty points with colors. |
| `polar_grid_helper(radius, sectors, rings, divisions, color1, color2)` | Two points for each spoke and each ring segment, with colors. |
| `arrow_helper(direction, origin, length, color, head_length, head_width)` | Twenty-two points with colors. |
| `plane_helper(plane, size, color)` | Fourteen points with colors. |
| `skeleton_helper(skeleton, scene, bone_color, parent_color)` | Two points for each bone with a bone for a parent. |
| `directional_light_helper(light, scene, size, color)` | Ten points with colors. |
| `point_light_helper(light, scene, sphere_size, color)` | Twenty-four points with colors. |
| `hemisphere_light_helper(light, scene, size, color)` | Forty-eight points with colors. |
| `spot_light_helper(light, scene, color)` | Seventy-four points with colors. |
| `rect_area_light_helper(light, scene, color)` | Eight points with colors. |
| `vertex_normals_helper(geometry, world, size, color)` | Two points for each vertex, with colors. |
| `vertex_tangents_helper(geometry, world, size, color)` | Two points for each vertex, with colors. |

## What raises

- A size, radius or length that is not positive.
- A division count below one on the square grid, or a negative count on the polar grid.
- An arrow direction of zero length, or an arrow head of a size that is not positive.
- A light of the wrong kind, a light kind that is not valid, or a light that `Light.validate` refuses.
- A geometry with no normals or tangents, or not one for each position.
- A world matrix with no normal matrix, on the vertex normals helper.
- A scene that changed after its last `update`, on a helper that reads world positions.
- An empty box.
- An opacity outside zero to one, or a blending that is neither named value, on the material.
