# Meshes and assets

`objects/mesh.mojo` and `core/assets.mojo`. A `Mesh` is three ids: a geometry, a material and a scene node. `Assets` owns the geometry, materials and textures that meshes name. An `InstancedMesh`, a `BatchedMesh` and an `Lod` draw at a node too, and are described below.

![Eight cubes share one geometry on a turning ring](out/instances.png)

three.js: `Mesh`. three.js has no assets store. A JavaScript mesh holds references; a Mojo mesh holds ids.

## Assets

```mojo
var assets = Assets()
var box = assets.geometries.add(cube(Length(1.0, METER)))
var paint = assets.materials.add(Material(Color(255, 140, 40)))
var board = assets.textures.add(checkerboard(64, 8, white, blue))
```

| Store | Id type | Holds |
|---|---|---|
| `assets.geometries` | `GeometryId` | `BufferGeometry` |
| `assets.materials` | `MaterialId` | `Material` |
| `assets.textures` | `TextureId` | `Texture` |

Each store is append-only. `add` returns the id. `get(id)` returns the item, or raises for an unknown id. `count()` returns how many items there are.

## Mesh

```mojo
scene.add_mesh(Mesh(box, paint, node))
```

`Mesh(geometry, material, node, frustum_culled=True)`. The first three arguments are typed ids. Swapping two of them does not compile.

A mesh holds no transform. The node holds it. One geometry can be drawn at many nodes without a copy.

`frustum_culled` lets the renderer skip the mesh when its bounds are out of view. It is on by default, as three.js's `Object3D.frustumCulled` is. See [Renderer](Renderer#frustum-culling).

`cast_shadow` and `receive_shadow` are three.js's `castShadow` and `receiveShadow`, both off by default. See [Shadows](Lights#shadows).

## InstancedMesh

`objects/instanced_mesh.mojo`. An `InstancedMesh` draws one geometry with one material at many transforms, each relative to one node. three.js: `InstancedMesh`, `instanceMatrix`, `setMatrixAt`, `getMatrixAt`.

```mojo
var forest = InstancedMesh(tree, bark, node, 200)
forest.set_matrix_at(0, translation(3, 0, -4))
scene.add_instanced_mesh(forest^)
```

| Member | Meaning |
|---|---|
| `InstancedMesh(geometry, material, node, count, frustum_culled=True)` | `count` instances, each at the identity. |
| `count() -> Int` | How many instances. |
| `matrix_at(index) -> Matrix4`, `set_matrix_at(index, matrix)` | One instance's transform, relative to the node. |
| `color_at(index) -> Color`, `set_color_at(index, color)` | One instance's color. three.js: `getColorAt`, `setColorAt`. |
| `matrices` | Every transform, in order. |
| `colors` | Every color, in order, or none. three.js: `instanceColor`. |

Moving the node moves every instance. The renderer orders every instance on its own: opaque nearest first, translucent furthest first. three.js keeps an instanced mesh's instances together. That draws a translucent instance over one it is behind when the two were added the other way round. It culls each instance on its own, so an instance out of view costs nothing. three.js culls the whole group by one bound.

An instance matrix must be affine and finite. It moves, turns, scales, shears or mirrors, and keeps `w` at one. A matrix that projects, or holds an infinity or a not-a-number, raises at `set_matrix_at`, and again when the scene renders, because the list is open.

An instance index is a plain number, as three.js's `instanceId` is. An index that names no instance raises.

### Instance colors

An instance's color multiplies the material's color, as a vertex color does. The two rasterizers see the same result, because the color is on each prepared corner. A geometry's own vertex colors multiply it again. The alpha is not changed.

An instanced mesh has no colors until the first `set_color_at`. That call gives every other instance white, as three.js does. An instance appended to `matrices` after the colors has no color. `color_at` reads it as white, and the next `set_color_at` gives it white. The `colors` list is open, so the renderer refuses a list that is not empty and does not hold one color per instance.

## BatchedMesh

A `BatchedMesh` draws many geometries with one material at many transforms, each relative to one node. Each instance names its own geometry. three.js: `BatchedMesh`, `addInstance`, `setMatrixAt`, `setGeometryAt`.

```mojo
var batch = BatchedMesh(bark, node)
var oak = batch.add_instance(oak_shape, translation(-2, 0, 0))
var pine = batch.add_instance(pine_shape, translation(2, 0, 0))
scene.add_batched_mesh(batch^)
```

| Member | Meaning |
|---|---|
| `BatchedMesh(material, node, frustum_culled=True)` | An empty batch. |
| `add_instance(geometry, matrix=Matrix4()) -> Int` | Add an instance and return its index. |
| `geometry_at(index)`, `set_geometry_at(index, geometry)` | Which geometry one instance draws. |
| `matrix_at(index)`, `set_matrix_at(index, matrix)` | One instance's transform. Affine and finite, as an instanced mesh's. |
| `color_at(index)`, `set_color_at(index, color)` | One instance's color, white until set. It multiplies the material's color. |
| `count() -> Int` | How many instances. |
| `instances` | Every `BatchedInstance`, in order: a geometry id, a matrix and a color, held together. |

three.js copies the geometries into one shared buffer. Here every geometry is in the store already, so an instance names one by id. The renderer orders each instance on its own, as it orders an instanced mesh's.

## LOD

`objects/lod.mojo`. An `Lod` shows one of several geometries at a node, by the camera's distance to the node. three.js: `LOD`, `addLevel`, `getObjectForDistance`, `update`.

```mojo
var tree = Lod(node)
tree.add_level(full_tree, bark)
tree.add_level(rough_tree, bark, Length(20.0, METER))
tree.add_level(billboard, bark, Length(80.0, METER), 0.1)
scene.add_lod(tree^)
```

| Member | Meaning |
|---|---|
| `Lod(node, frustum_culled=True)` | An LOD with no levels. |
| `add_level(geometry, material, distance=Length(0.0, METER), hysteresis=0)` | A level to show from `distance` on. The levels stay in order of distance. |
| `count() -> Int`, `level_at(index) -> LodLevel` | The levels, nearest first. |
| `level_for(distance) -> Int` | Which level shows from `distance` with no memory, or -1 with no levels. three.js's `getObjectForDistance`. |
| `level_from(distance, shown) -> Int` | Which level shows from `distance` when `shown` shows now. Hysteresis applies. |
| `update(distance) -> Int` | Choose the level from `distance` and remember it in `shown`. three.js's `LOD.update`. |
| `shown` | The level `update` last chose. Zero at first. |
| `levels` | Every level, in order. |

The renderer measures the distance from the camera's position to the node's world origin, each frame. It shows the last level whose distance has been reached. Below the second level's distance it shows the first. An LOD with no levels shows nothing.

A level's `hysteresis` is a fraction of its distance, from zero to one. Once the level is shown, it keeps showing until the camera comes that fraction nearer than its distance. That stops the level flipping every frame when the camera hovers at the distance. three.js's `addLevel` takes the same fraction.

The hysteresis needs a memory of the shown level. `scene.update_lods(eye)` chooses and remembers every LOD's level for a camera at `eye`, after `scene.update()`. The renderer reads the memory and never writes it. A scene never given `update_lods` shows the stateless choice.

A distance is a `Length`. A bare number does not compile. A negative distance raises. A hysteresis outside zero to one raises.

## Rules

- The node must exist in the scene when `add_mesh` is called.
- The geometry and material are checked when the scene renders. The scene does not see the assets.
- A material's texture id is checked when the scene renders too.

## Ids

Every id wraps one integer in a struct. The wrapper costs nothing at run time. The compiler refuses a bare integer, and `tests/compile_fail/` proves it. See [Why types and checks both exist](Why-types-and-checks-both-exist).
