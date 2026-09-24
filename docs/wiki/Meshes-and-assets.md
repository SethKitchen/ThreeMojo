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

## Several materials

A mesh can wear a list of materials. Each group of its geometry then draws with the material that its `material_index` names. three.js: `Mesh.material` as an array, with `BufferGeometry.groups`.

```mojo
var faces = List[MaterialId]()
for face in range(6):
    faces.append(assets.materials.add(Material(Color(40 * face, 90, 200))))
scene.add_mesh(Mesh(box, faces, node))
```

| Member | Meaning |
|---|---|
| `Mesh(geometry, materials, node, ...)` | A mesh that wears a list. The list must hold one material or more. |
| `materials` | The list, or empty for a mesh with one material. |
| `material` | The one material, or the first entry of the list. |
| `is_multi_material() -> Bool` | True when the mesh wears a list. three.js: `Array.isArray(mesh.material)`. |
| `group_material(index) -> Optional[MaterialId]` | The material of a group's `MaterialIndex`, or none past the end of the list. |

These rules are three.js's:

- A group whose index is past the end of the list draws nothing.
- A mesh with a list and a geometry without groups draws nothing.
- A mesh with one material ignores the groups and draws every triangle.
- A group that runs past the end of the index stops there. A part of a triangle is not drawn. See `BufferGeometry.triangle_run`.

The renderer makes one draw for each group. The opaque groups and the blended groups go into their own lists, as three.js's `projectObject` puts them. So a blended group of a mesh draws after every opaque group of every mesh. Each group keeps the depth of its mesh. Both rasterizers take the same prepared triangles, so the GPU draws the groups as the CPU does.

A wireframe group draws the edges of its own triangles. A shadow map draws each group that casts. The raycaster tests each group with the side of its own material. See [Raycasting](Raycasting).

The built-in geometries write the groups that three.js writes. See [Geometry](Geometry#groups). `create_meshes_from_multi_material_mesh` splits a mesh that wears a list into one mesh for each material. See [Geometry addons](Geometry-addons).

The loaders keep a list where three.js keeps one: OBJ `usemtl`, [Collada](Model-files#collada), [FBX](Model-files#fbx) and [Scene JSON](Scene-JSON). A glTF mesh of several primitives is a node of several meshes, as three.js makes a `Group` of them. The glTF, OBJ and Scene JSON exporters write a list. See [Exporters](Exporters).

A skinned mesh, an instanced mesh, a batched mesh, an LOD level, a line and points wear one material. three.js lets each of them wear a list. The FBX and Collada loaders cut a skinned geometry of several materials into one skinned mesh for each group. `BufferGeometry.group_part` gives the corners of one group as a geometry of their own.

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

An instanced mesh has no colors until the first `set_color_at`. That call gives every other instance white, as three.js does. An instance appended to `matrices` after the colors has no color. `color_at` reads it as white, and the next `set_color_at` gives it white. The renderer also draws an instance past the end of `colors` in white, as three.js does. It ignores a color past the last instance.

An instanced mesh wears no morph targets. Every instance draws the geometry unmorphed. three.js applies the mesh's `morphTargetInfluences` to every instance, or each instance's own through `setMorphAt` and `morphTexture`. Neither is ported.

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
