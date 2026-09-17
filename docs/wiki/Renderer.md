# Renderer

`renderers/renderer.mojo`. The `Renderer` turns a scene, its assets and a camera into an image. `prepare` makes screen-space triangles. `render` also fills them on the CPU.

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
| `render(scene, assets, camera) -> Framebuffer` | `prepare`, then rasterize and resolve. |
| `available_workers() -> Int` | One per logical core. |

`scene.update()` must run before `prepare` or `render`. The renderer reads world matrices and does not recompute them.

## Shading modes

| Mode | A fragment's color is |
|---|---|
| `SHADE_TEXTURE` | The material color, times its texture, times the light, plus the emissive times its map. The default. |
| `SHADE_LIT` | The material color times the light, plus the emissive. Textures are ignored. |
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
4. Clip each triangle against the near and far planes.
5. Project each corner to pixels and keep `1 / w`.
6. Cull faces that the material's `side` does not draw.
7. Flip the normal of a face seen from behind.

The output is one flat list, three `RasterVertex` per triangle. Both rasterizers consume it. See [Rasterization](Rasterization).

## Draw order

Opaque draws come first, nearest first. Translucent draws follow, furthest first. The order is per draw, by the depth of its own placed origin. An instance sorts where it is, not where its node is, so a translucent mesh between two instances of a group falls between them. Only the draws the camera makes are sorted. See [Why transparency is sorted](Why-transparency-is-sorted).

## Frustum culling

`prepare` skips a mesh whose bounding sphere lies wholly outside the view. The frustum's four sides come from the camera's projection matrix times its view matrix, read as planes in world space. Its near and far planes come from the camera's distances and the view matrix, the same numbers the clipper uses. See [Math](Math#frustum).

The sphere is the geometry's, computed once per geometry per frame and reused by every mesh that draws it. It is carried through each node's world matrix. A sphere within a millionth of the far distance of a plane is kept. The clipper decides such ties.

The image does not change. Every triangle of such a mesh is clipped away or lands off the image. What the test saves is the transform, the clip and the projection of those triangles. The bound itself reads the positions, twice.

`Mesh(geometry, material, node, frustum_culled=False)` opts a mesh out. three.js: `Object3D.frustumCulled`. A mesh that is left out is not read. Its material and its index buffer are checked when it is drawn.

Each instance of an instanced or batched mesh is tested on its own, with the instance's matrix folded into the node's. three.js tests the whole group by one bound. An LOD's shown level is tested as a mesh is.

## What render does

`render` calls `prepare`, then resolves the lights once for the frame with `Lighting(scene, visible=camera.visible_layers())`. A light on a layer the camera does not watch lights nothing. See [Lights](Lights#lighting). It resolves the scene's fog for the camera with `FogView(scene.fog, view)`. See [Fog](Fog). Then it rasterizes the triangles and resolves the image through the tone mapping curve.

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

## Performance

`make bench-scene` times each stage on a sphere of twelve thousand triangles. At 1280 by 720 with 24 workers a frame takes about 19 milliseconds. `prepare` is single threaded and is the largest stage.
