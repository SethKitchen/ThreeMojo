# Meshes and assets

`objects/mesh.mojo` and `core/assets.mojo`. A `Mesh` is three ids: a geometry, a material and a scene node. `Assets` owns the geometry, materials and textures that meshes name. An `InstancedMesh`, a `BatchedMesh` and an `Lod` draw at a node too, and are described below.

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
| `matrices` | Every transform, in order. |

Moving the node moves every instance. The renderer sorts the group as one object, as three.js does. It culls each instance on its own, so an instance out of view costs nothing. three.js culls the whole group by one bound.

An instance index is a plain number, as three.js's `instanceId` is. An index that names no instance raises.

Per-instance colors are not ported. A geometry's vertex colors reach every instance.

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
| `matrix_at(index)`, `set_matrix_at(index, matrix)` | One instance's transform. |
| `count() -> Int` | How many instances. |

three.js copies the geometries into one shared buffer. Here every geometry is in the store already, so an instance names one by id.

## LOD

`objects/lod.mojo`. An `Lod` shows one of several geometries at a node, by the camera's distance to the node. three.js: `LOD`, `addLevel`, `getCurrentLevel`.

```mojo
var tree = Lod(node)
tree.add_level(full_tree, bark)
tree.add_level(rough_tree, bark, Length(20.0, METER))
tree.add_level(billboard, bark, Length(80.0, METER))
scene.add_lod(tree^)
```

| Member | Meaning |
|---|---|
| `Lod(node, frustum_culled=True)` | An LOD with no levels. |
| `add_level(geometry, material, distance=Length(0.0, METER))` | A level to show from `distance` on. The levels stay in order of distance. |
| `count() -> Int`, `level_at(index) -> LodLevel` | The levels, nearest first. |
| `level_for(distance) -> Int` | Which level shows from `distance`, or -1 with no levels. |
| `levels` | Every level, in order. |

The renderer measures the distance from the camera's position to the node's world origin, each frame. It shows the last level whose distance has been reached. Below the second level's distance it shows the first. An LOD with no levels shows nothing.

A distance is a `Length`. A bare number does not compile. A negative distance raises.

## Rules

- The node must exist in the scene when `add_mesh` is called.
- The geometry and material are checked when the scene renders. The scene does not see the assets.
- A material's texture id is checked when the scene renders too.

## Ids

Every id wraps one integer in a struct. The wrapper costs nothing at run time. The compiler refuses a bare integer, and `tests/compile_fail/` proves it. See [Why types and checks both exist](Why-types-and-checks-both-exist).
