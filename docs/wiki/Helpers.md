# Helpers

`helpers/`. A helper shows something about the scene. Most helpers are a line geometry: each builder returns a `BufferGeometry` for a [`Line`](Lines) in `SEGMENTS` mode. There are line helpers for axes, grids, boxes, octrees, cameras, arrows, planes, skeletons, lights, and vertex normals and tangents.

Four helpers draw more than lines. The light probe helper and the texture helper are meshes. The view helper and the shadow map viewer draw over a part of the image.

![A camera circles a cube outlined in yellow, over a grid, beside the axes and a second camera's frustum](out/helpers.png)

three.js: `AxesHelper`, `GridHelper`, `PolarGridHelper`, `BoxHelper`, `Box3Helper`, `CameraHelper`, `ArrowHelper`, `PlaneHelper`, `SkeletonHelper`, `DirectionalLightHelper`, `PointLightHelper`, `HemisphereLightHelper`, `SpotLightHelper`, `RectAreaLightHelper`, `VertexNormalsHelper`, `VertexTangentsHelper`. From `examples/jsm`: `OctreeHelper`, `LightProbeHelper`, `TextureHelper`, `ViewHelper`, `ShadowMapViewer`, `CSMHelper` and `UVsDebug`.

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

A geometry holds any attribute by name. `TANGENT` is `"tangent"`, the name that three.js uses, with four floats for each vertex. The helper reads the first three. The tangents come from a loader, from `BufferGeometry.compute_tangents`, or from `compute_mikktspace_tangents`. See [Geometry](Geometry#tangents).

## OctreeHelper

`octree_helper(octree)` is the twelve edges of every box of an [`Octree`](Math-addons#octree) below its root. It gives twenty-four points for each box, in the order of `Octree.boxes()`: each box, then the boxes in it. The root box is not drawn, as in three.js.

The geometry carries no `color` attribute. three.js draws it yellow, and `DEFAULT_OCTREE_COLOR` is that yellow. An octree that is not built, or that holds no triangle, gives an empty geometry.

```mojo
from helpers.octree import DEFAULT_OCTREE_COLOR, octree_helper

var yellow = assets.materials.add(Material(DEFAULT_OCTREE_COLOR, kind=BASIC))
var boxes = assets.geometries.add(octree_helper(level))
scene.add_line(Line(boxes, yellow, root, mode=SEGMENTS))
```

The points are in world space, so put the `Line` on a node at the origin. After the octree changes, build the helper again. three.js calls `update()` for the same reason.

## LightProbeHelper

`LightProbeHelper(light, assets, size)` is a sphere that shows the light of a light probe. Each point shows the light that a matte white surface catches from the probe alone when it faces that way. No other light reaches the sphere.

| Argument | Default | Meaning |
|---|---|---|
| `light` | | A light probe, from `light_probe`. |
| `assets` | | Where the sphere, its material and its program go. |
| `size` | `Length(1.0, METER)` | The radius of the sphere. Must be positive. |

The sphere uses the shader of three.js. `materials.glsl` compiles it to a node program, and both rasterizers run it for each pixel. The GLSL subset has no arrays, so the nine coefficients are nine uniforms, `sh0` to `sh8`. See [node materials](Node-materials).

```mojo
from helpers.light_probe import LightProbeHelper

var helper = LightProbeHelper(probe, assets, Length(0.5, METER))
scene.add_mesh(helper.mesh(where))
```

A light probe here has no node. Put the mesh on the node where you want to see the probe. three.js copies the position of the probe to its helper. The rotation of the node does not change what the sphere shows, because each normal of a sphere points away from its center.

After the probe changes, call `helper.update(light, assets)`. It writes the coefficients and the intensity into the program again. three.js reads them before each frame.

## TextureHelper

`texture_helper(texture, assets, width, height, depth)` shows a texture as it is. There is one function for each kind of texture id. It returns a `TextureHelper`: a list of meshes on one node.

| Texture | Shape | Alpha |
|---|---|---|
| `TextureId` | A plane of `width` by `height`. | One. |
| `Data3DTextureId` | One plane for each slice, from `-depth / 2` to `depth / 2` along z. | `max(1 / slices, 0.25)`. |
| `DataArrayTextureId` | One plane for each layer, spread the same way. | `max(1 / layers, 0.25)`. |
| `CubeTextureId` | A box of `width` by `height` by `depth`. | One. |

Each size is a `Length` of one meter by default, and must be positive. The color is the color of the texel. The alpha of the texel is not used. Both sides of each plane are drawn.

```mojo
from helpers.texture import texture_helper

var helper = texture_helper(lut_volume, assets)
helper.add_to(scene, node)
```

three.js reads the texture in a shader, at a `uvw` attribute. The rasterizers here sample a 2D map at `uv`. So each plane or face is a mesh of its own. It has an unlit `BASIC` material and a 2D map that holds what the shader of three.js reads:

- A 2D texture is copied with its alpha ignored. The copy has no offset, repeat, rotation or channel, because the shader reads the coordinates as they are. The image is upright for each value of `flip_y`.
- A slice of a 3D texture is read at each texel center with `Data3DTexture.sample`, at the third coordinate of three.js. A bilinear sample of that image is the trilinear sample of the volume.
- A layer of an array texture is read the same way with `DataArrayTexture.sample`.
- A face of a cube is read with `CubeTexture.sample` on a grid of the size of the cube. Each point is read in its direction from the center.

The helper differs from three.js in two places:

- For a box whose three sides are not equal, a face is a resampling of the cube. It can differ from three.js by a filter step between texels.
- A plane or a cube with an alpha of one is drawn opaque, and the nearer face hides the far one, as in three.js. The slices of a stack blend in order from the most negative z, and each slice writes its depth, as in three.js. Seen from +z, each slice blends over the slices behind it. Seen from -z, the nearest slice draws first and hides the rest.

A blank texture, a size that is not positive, and an id that is not in its store are refused.

## ViewHelper

`ViewHelper()` shows the axes of the world in a square of 128 pixels in the bottom right corner of the image. It turns against the camera. A click on one of its six disks turns the camera to look along that axis.

The helper reads and writes a [`CameraFrame`](Windowing-and-controls), not a camera. A camera here has a position, a target and an up. The helper of three.js writes a quaternion.

```mojo
from controls.camera_frame import CameraFrame
from helpers.view import ViewHelper

var gizmo = ViewHelper()
var frame = CameraFrame.of(camera)
gizmo.render(target, frame)
_ = gizmo.handle_click(x, y, width, height, frame)
if gizmo.animating:
    gizmo.update(Duration(0.016, SECOND), frame)
    frame.place(camera)
```

| Member | Meaning |
|---|---|
| `render(target, camera, workers)` | Draw the helper over the bottom right corner of a `RenderTarget`. |
| `axis_at(x, y, width, height, camera)` | The disk under a point of the image, or none. |
| `handle_click(x, y, width, height, camera)` | Start a turn toward the disk under a click. False while a turn runs, or when no disk is hit. |
| `turn_toward(axis, camera)` | Start a turn toward one `ViewAxis`, from `POSITIVE_X` to `NEGATIVE_Z`. |
| `update(delta, camera)` | Turn the camera by a `Duration`, a full turn in a second at most. It clears `animating` when the turn ends. |
| `center` | The point the camera turns around. The origin by default. |

`x` and `y` are pixels from the top left corner of the image, as the `clientX` and `clientY` of three.js are. The click finds the disk nearest to the camera of the helper, as the `Raycaster` of three.js does.

The helper draws into a target of its own, cleared to transparent black. Then it blends that image over the corner of your image. Each translucent disk then looks the same as when it is drawn over your image directly. A target smaller than 128 pixels gets the part of the corner that fits.

The disks have no labels. The `setLabels` and `setLabelStyle` of three.js write text with a 2D canvas, and this port has no canvas text.

## ShadowMapViewer

`ShadowMapViewer(light)` shows the shadow map of one light in a rectangle over the image. The map is gray: white at the near plane of the light, black at the far plane and where nothing was drawn. It works for a directional light and a spot light, as in three.js.

| Field | Default | Meaning |
|---|---|---|
| `light` | | The `LightIndex` of the light in `scene.lights`. |
| `x`, `y` | `10`, `10` | The pixels from the top left corner of the image to the rectangle. |
| `width`, `height` | `256`, `256` | The size of the rectangle in pixels. |
| `enabled` | `True` | Whether `render` draws. |

```mojo
from animation.keyframe_track import LightIndex
from helpers.shadow_map_viewer import ShadowMapViewer

var viewer = ShadowMapViewer(LightIndex(0))
renderer.render_into(target, scene, assets, camera)
viewer.render(renderer, target, scene, assets)
```

`render` draws the shadow map with `Renderer.shadow_maps`. Then it draws a plane with that map inside the rectangle, with the scissor test on. After that, it puts back the scissor of the renderer. A rectangle that is partly outside the image is clipped.

The gray is `1 - depth`, as the `UnpackDepthRGBAShader` of three.js gives it. three.js writes it to the canvas with no conversion to sRGB. So the map is kept as sRGB bytes, and each byte comes out of the resolve as it went in.

To draw on the GPU, use `hud(renderer, scene, assets)`. It gives the scene, the assets and the camera of the plane. Prepare the scene with `Renderer.prepare_frame`, and upload its textures. Then give `rect(width, height)` to the draw as its scissor.

The viewer refuses a point light, a light that casts no shadow, and a variance shadow map. The shader of three.js reads none of these. It also refuses a light index that is not in the scene, and a size that is not positive. The label with the name of the light is not ported, because this port has no canvas text.

## CSMHelper

`helpers/csm.mojo`. A `CSMHelper` shows what a [`CSM`](Lights) cuts, and where its lights look. Call it after `csm.update`.

```mojo
var helper = CSMHelper()
var lines = assets.geometries.add(helper.lines(csm, scene, camera))
scene.add_line(Line(lines, paint, node, mode=SEGMENTS))
var sheet = assets.materials.add(csm_plane_material())
var faces = helper.planes(csm, scene, camera)
```

`lines` returns segments in world space. The frustum of the camera, out to `max_far`, is white. A box around the far face of each cascade is white. The box that the shadow camera of each cascade light sees is yellow.

`planes` returns one rectangle for each cascade, on its far face, in world space. Draw each one with `csm_plane_material()`: white, a tenth opaque, two-sided, and with no depth write.

| Member | Default | Meaning |
|---|---|---|
| `display_frustum` | `True` | Show the frustum and the cascade boxes. |
| `display_planes` | `True` | Show the planes, when the frustum shows. |
| `display_shadow_bounds` | `True` | Show the shadow boxes. |

three.js's helper is a group that copies the camera's position, rotation and scale. Here the parts are in world space, which is the same for a camera outside a group. three.js reads each shadow box from its shadow camera, which moves at a render, so its boxes are one frame late. Here each box is where its light is now. There is no `updateVisibility`: each call reads the three members.

## UVsDebug

`uvs_debug(geometry, size)` in `helpers/uvs_debug.mojo` draws a geometry's texture coordinates as an image. It is three.js's `UVsDebug`. Each triangle's outline is dark gray on white, where its coordinates put it.

three.js also writes each triangle's number and each corner's letter on the image. This port has no canvas text. So `labels` holds each label: its text, its place, its size and its color. `outlines` holds each triangle's corners in pixels. A canvas antialiases its lines. Here a line is the pixels that a one-pixel pen crosses.

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
| `octree_helper(octree)` | Twenty-four points for each box below the root, no colors. |
| `LightProbeHelper(light, assets, size)` | A sphere in `assets`, with `mesh(node)` and `update(light, assets)`. |
| `texture_helper(texture, assets, width, height, depth)` | A `TextureHelper`, with `meshes(node)` and `add_to(scene, node)`. |
| `ViewHelper()` | The axes in the corner, with `render`, `handle_click` and `update`. |
| `ShadowMapViewer(light)` | The shadow map in a rectangle, with `render`, `hud` and `rect`. |

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
- A light that is not a light probe, on the light probe helper.
- A blank texture, or an id that is not in its store, on the texture helper.
- A `ViewAxis` that is not one of the six, an image with no size, or a negative `Duration`, on the view helper.
- A light index that is not in the scene, or a light with no shadow map, on the shadow map viewer.
- A light that is not a directional or a spot light, or a variance shadow map, on the shadow map viewer.
