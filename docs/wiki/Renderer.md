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

`set_shading` refuses a mode that is none of the three.

## What prepare does

First, leave out every mesh whose node shares no layer with the camera. Then leave out every mesh whose bounding sphere lies wholly outside the camera's frustum. Then sort the rest into draw order. Then, for each mesh in that order:

1. Transform the positions to world space and camera space.
2. Transform the normals with the normal matrix, or compute a face normal.
3. Clip each triangle against the near and far planes.
4. Project each corner to pixels and keep `1 / w`.
5. Cull faces that the material's `side` does not draw.
6. Flip the normal of a face seen from behind.

The output is one flat list, three `RasterVertex` per triangle. Both rasterizers consume it. See [Rasterization](Rasterization).

## Draw order

Opaque meshes come first, nearest first. Translucent meshes follow, furthest first. The order is per mesh, by the depth of its node's origin. Only the meshes the camera draws are sorted. See [Why transparency is sorted](Why-transparency-is-sorted).

## Frustum culling

`prepare` skips a mesh whose bounding sphere lies wholly outside the view. The frustum's four sides come from the camera's projection matrix times its view matrix, read as planes in world space. Its near and far planes come from the camera's distances and the view matrix, the same numbers the clipper uses. See [Math](Math#frustum).

The sphere is the geometry's, computed once per geometry per frame and reused by every mesh that draws it. It is carried through each node's world matrix. A sphere within a millionth of the far distance of a plane is kept. The clipper decides such ties.

The image does not change. Every triangle of such a mesh is clipped away or lands off the image. What the test saves is the transform, the clip and the projection of those triangles. The bound itself reads the positions, twice.

`Mesh(geometry, material, node, frustum_culled=False)` opts a mesh out. three.js: `Object3D.frustumCulled`. A mesh that is left out is not read. Its material and its index buffer are checked when it is drawn.

## What render does

`render` calls `prepare`, then resolves the lights once for the frame with `Lighting(scene, visible=camera.visible_layers())`. A light on a layer the camera does not watch lights nothing. See [Lights](Lights#lighting). Then it rasterizes the triangles and resolves the image.

## Workers

With more than one worker, the image is cut into horizontal bands. Each band is drawn on its own thread. The result is byte for byte the same as one thread. See [Why the CPU renderer uses bands](Why-the-CPU-renderer-uses-bands).

The default is one worker. The coverage tool needs probe records in order.

## Errors

`prepare` raises in four cases. A mesh names a node, geometry or material that does not exist. A material names a texture or an emissive map that does not exist. An emissive map reads its alpha as coverage. A geometry has no positions. A mesh the camera's layers or frustum leave out is not checked.

## Performance

`make bench-scene` times each stage on a sphere of twelve thousand triangles. At 1280 by 720 with 24 workers a frame takes about 19 milliseconds. `prepare` is single threaded and is the largest stage.
