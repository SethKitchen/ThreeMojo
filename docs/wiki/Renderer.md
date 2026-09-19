# Renderer

`renderers/renderer.mojo`. The `Renderer` turns a scene, its assets and a camera into an image. `prepare` makes screen-space triangles, `prepare_lines` makes screen-space segments and `prepare_points` makes screen-space points. `render` also fills them on the CPU.

![A cube leaves the frustum and vanishes, then returns](out/culling.png)

three.js: `WebGLRenderer.render(scene, camera)`, plus the assets argument that Mojo needs.

## Construct one

```mojo
var renderer = Renderer(320, 240)
var fast = Renderer(1280, 720, workers=available_workers())
```

| Member | Meaning |
|---|---|
| `Renderer(width, height, workers=1)` | An image size and a thread count. |
| `set_workers(workers)` | Change the thread count. At least one. |
| `set_background(color)` | The clear color. |
| `set_shading(mode)` | What a fragment's color comes from. See below. |
| `set_tone_mapping(mode, exposure=1.0)` | The curve that compresses the light for a display. See below. |
| `prepare(scene, assets, camera) -> List[RasterVertex]` | Transform, clip and project every mesh. |
| `prepare_lines(scene, assets, camera) -> List[RasterVertex]` | The same for the scene's [lines](Lines) and wireframes. |
| `prepare_points(scene, assets, camera) -> List[RasterVertex]` | The same for the scene's [points](Points-and-sprites). A [sprite](Points-and-sprites#sprites) is two triangles, and `prepare` makes them. |
| `prepare_frame(scene, assets, camera) -> Frame` | All three lists, and the one order both rasterizers draw them in. See [Lines](Lines#two-lists-one-order). |
| `render(scene, assets, camera) -> Framebuffer` | Every pass, then rasterize and resolve. |
| `render_into(target, scene, assets, camera)` | The same into a target of the renderer's size, cleared first, resolved by the caller. See below. |
| `render_array(scene, assets, array) -> Framebuffer` | Once per camera of an [ArrayCamera](Cameras#arraycamera), each into its own rectangle. |
| `render_array_into(target, scene, assets, array)` | The same into a target you hold. |
| `tone_curve() -> ToneMapping` | The curve `render` resolves through: the one set, or none in the uv view. |
| `set_viewport(rect)` | Where the image lands on the target. See below. |
| `set_scissor(rect)`, `set_scissor_test(enabled)` | Which pixels a draw may touch, and whether that is enforced. See below. |
| `available_workers() -> Int` | One per logical core. |
| `camera_position(scene, camera) -> Vector3` | Where the camera stands, in world space. |
| `toward_camera(scene, camera) -> Vector3` | The one direction toward it, or `PERSPECTIVE_VIEW`. |
| `camera_up(scene, camera) -> Vector3` | Which way is up for it, in world space. |

The two passes are separate because almost nothing a triangle carries applies to a line. `render` fills the triangles and then draws the segments over them, depth tested against them. See [Lines](Lines).

`scene.update()` must run before `prepare` or `render`. The renderer reads world matrices and does not recompute them.

## Shading modes

| Mode | A fragment's color is |
|---|---|
| `SHADE_TEXTURE` | The material color, times its texture, times the light, plus the highlight and the emissive times its map. The default. |
| `SHADE_LIT` | The material color times the light, plus the highlight and the emissive. Textures are ignored. |
| `SHADE_UV` | The texture coordinates, as red and green. A debug view. |

A `NORMALS` or `DEPTH` material writes data under either lit mode. See [Materials](Materials#data-materials).

`set_shading` refuses a mode that is none of the three.

## Tone mapping

`set_tone_mapping` picks one of the seven curves in `render/tonemap.mojo` and an exposure. `NO_TONE_MAPPING` and an exposure of one are the defaults, as in three.js. `render` applies the curve in `RenderTarget.resolve`, once per pixel, after every fragment is composited. The `SHADE_UV` view is never tone mapped, and nor is a pixel a data material wrote. See [Render target](Render-target-and-framebuffer#tone-mapping).

`set_tone_mapping` refuses a curve that is none of the seven, and an exposure that is negative or not finite.

## What prepare does

First, read the scene as draws. A mesh is one draw. An instanced or batched mesh is one draw per instance, kept together as one group. An LOD is one draw, the level its distance from the camera picks. See [Meshes and assets](Meshes-and-assets#instancedmesh).

Leave out every group whose node shares no layer with the camera. Then leave out every draw whose bounding sphere lies wholly outside the camera's frustum. Then sort the groups into draw order. Then, for each draw in that order:

1. Transform the positions to world space and camera space.
2. Carry the texture coordinates through the map's transform. See [Textures](Textures#transform).
3. Transform the normals with the normal matrix, or compute a face normal. Carry them into view space for a `NORMALS` material.
4. Clip each triangle against the near and far planes and the four sides of the view. See [Rasterization](Rasterization#clipping).
5. Project each corner to pixels and keep `1 / w`.
6. Cull faces that the material's `side` does not draw.
7. Flip the normal of a `BACK_SIDE` face, and of a `DOUBLE_SIDE` face seen from behind, as three.js's `FLIP_SIDED` and `faceDirection` do.

The output is one flat list, three `RasterVertex` per triangle. Both rasterizers consume it. See [Rasterization](Rasterization).

## Draw order

Opaque draws come first, nearest first. Translucent draws follow, furthest first. The order is per draw, by the depth of its own placed origin. An instance sorts where it is, not where its node is, so a translucent mesh between two instances of a group falls between them. Only the draws the camera makes are sorted. See [Why transparency is sorted](Why-transparency-is-sorted).

`prepare_frame` sorts lines and wireframes into the same order. A translucent line falls between the translucent surfaces on either side of it. See [Lines](Lines#two-lists-one-order).

## Frustum culling

`prepare` skips a mesh whose bounding sphere lies wholly outside the view. The frustum's four sides come from the camera's projection matrix times its view matrix, read as planes in world space. Its near and far planes come from the camera's distances and the view matrix, the same numbers the clipper uses. See [Math](Math#frustum).

The sphere is the geometry's, computed once per geometry per frame and reused by every mesh that draws it. It is carried through each node's world matrix. A sphere within a millionth of the far distance of a plane is kept. The clipper decides such ties.

The image does not change. Every triangle of such a mesh is clipped away or lands off the image. What the test saves is the transform, the clip and the projection of those triangles. The bound itself reads the positions, twice.

`Mesh(geometry, material, node, frustum_culled=False)` opts a mesh out. three.js: `Object3D.frustumCulled`. A mesh that is left out is not read. Its material and its index buffer are checked when it is drawn.

Each instance of an instanced or batched mesh is tested on its own, with the instance's matrix folded into the node's. three.js tests the whole group by one bound. An LOD's shown level is tested as a mesh is.

## What render does

`render` calls `prepare_frame`, then resolves the lights once for the frame with `Lighting(scene, camera.visible_layers(), camera_position(scene, camera), toward_camera(scene, camera))`. A light on a layer the camera does not watch lights nothing. The camera's position goes with the lights because a `PHONG` material measures its highlight from there. See [Lights](Lights#lighting).

`toward_camera` goes with it because a parallel projection has one direction toward the camera for every surface. It asks `Matrix4.is_affine()` of the projection matrix. A converging projection has a bottom row that is not (0, 0, 0, 1), and `toward_camera` returns `PERSPECTIVE_VIEW` for it. A parallel one returns the camera's own world +z axis, made unit length. See [Lights](Lights#which-way-the-camera-lies).

`camera_up` goes with them for a `MATCAP` surface, which is looked up in the camera's own frame. It is the view space +y axis carried back into the world. Every projection answers the same way. See [Materials](Materials#matcap).

It resolves the scene's fog for the camera with `FogView(scene.fog, view)`. See [Fog](Fog). Then it rasterizes the frame with `rasterize_frame`, in the frame's order, and resolves the image through the tone mapping curve.

## Viewport and scissor

`set_viewport(rect)` puts the camera's image in a rectangle of the target, three.js's `setViewport`. `set_scissor(rect)` and `set_scissor_test(True)` keep every draw inside a rectangle, three.js's `setScissor` and `setScissorTest`. A `Rect` is a corner and a size, and the corner counts up from the bottom left, as three.js's does.

```mojo
from render.rect import Rect

renderer.set_viewport(Rect(0, 0, 160, 240))
renderer.set_scissor(Rect(0, 0, 160, 240))
renderer.set_scissor_test(True)
```

The viewport is folded into the screen matrix by `prepare`, `prepare_lines` and `prepare_points`. The projection is mapped onto the rectangle rather than onto the whole target. The image is squeezed or stretched to the rectangle's size, as three.js's is. A viewport hanging off the target is allowed: the pixels it puts outside are not drawn. A viewport must hold at least one pixel.

A viewport is a mapping, not a scissor. Every triangle and segment is clipped against the camera's four side planes first, so nothing lands outside the camera's image. With the scissor test off, the whole target is cleared and the geometry outside the view produces no pixel.

The scissor is enforced by the render target on the CPU and by the kernel on the GPU. Both ask `Rect.contains_pixel`, so they agree about every edge. A pixel outside is neither cleared nor drawn. With the test off, the default, the scissor is kept and ignored. A scissor must lie wholly inside the target.

A split screen is two cameras, two viewports and two scissors drawing into one target. `render_into` draws into a target you hold, clearing the scissor alone to the background, so a second draw leaves the first's pixels. Resolve the target once, through `tone_curve`:

```mojo
var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0))
renderer.set_scissor_test(True)
renderer.set_viewport(left)
renderer.set_scissor(left)
renderer.render_into(target, scene, assets, perspective)
renderer.set_viewport(right)
renderer.set_scissor(right)
renderer.render_into(target, scene, assets, top_view)
var image = target.resolve(renderer.workers, renderer.tone_curve(), renderer.tone_mapping_exposure)
```

`GpuRenderer.draw` takes the same `scissor`, and its device target keeps its pixels between draws the same way. See [GPU backend](GPU-backend#gpurenderer). `examples/split.mojo` draws a split screen.

## Workers

With more than one worker, the image is cut into horizontal bands. Each band is drawn on its own thread. The result is byte for byte the same as one thread. See [Why the CPU renderer uses bands](Why-the-CPU-renderer-uses-bands).

The default is one worker. The coverage tool needs probe records in order.

## Errors

`prepare` raises in five cases:

- A mesh names a node, geometry or material that does not exist.
- A material names a texture, an emissive map or an alpha map that does not exist.
- An emissive map reads its alpha as coverage.
- An alpha map is not stored as data, which means `LINEAR` and `IGNORED`.
- A material names two maps whose transforms differ.
- A geometry has no positions.

A mesh the camera's layers or frustum leave out is not checked.

`render` also raises when `scene.fog` holds an unknown kind or an inside-out range.

`set_viewport` raises for a rectangle with no pixel. `set_scissor` raises for one that reaches outside the target. `render_into` raises for a target that is not the renderer's size.

## Performance

`make bench-scene` times each stage on its own on a sphere of twelve thousand triangles. At 1280 by 720 with 16 workers a frame takes about 6 milliseconds on an Apple M4 Max. The rasterizer is the largest stage. `prepare` is single threaded and takes about half a millisecond. A triangle wholly inside the depth range skips the clipper, and the corner list is sized once per draw.

The resolve encodes the clear color once and copies it to every pixel that still holds it. A frame that is mostly background pays for the pixels that are not.
