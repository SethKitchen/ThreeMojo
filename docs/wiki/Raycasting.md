# Raycasting

`core/raycaster.mojo`. A `Raycaster` carries a `Ray` through a scene and returns every mesh it meets, nearest first. Use it to find what is under a pixel.

![A red marker sits where a ray hits the sphere under the pixel](out/raycast.png)

three.js: `Raycaster`, `setFromCamera`, `intersectObject`, `intersectObjects`, `Mesh.raycast`.

## Construct one

```mojo
var caster = Raycaster(origin, direction)
var ranged = Raycaster(origin, direction, Length(0.1, METER), Length(50.0, METER))
```

| Argument | Type | Default | Meaning |
|---|---|---|---|
| `origin` | `Vector3` | required | Where the ray starts, in world space. |
| `direction` | `Vector3` | required | Which way it goes. Any length but zero. |
| `near` | `Length` | zero | Hits nearer than this are dropped. |
| `far` | `Length` | unbounded | Hits further than this are dropped. |

The two distances are lengths. A bare number does not compile. `near` must not be negative, `far` must not be below `near`, and neither can be NaN.

`caster.layers` is a `Layers`, on layer zero by default. An object whose node shares no layer with it is not tested. See [Scene graph](Scene-graph#layers).

## Aim it

| Method | Meaning |
|---|---|
| `set(origin, direction)` | A new ray. |
| `set_from_camera(coords, camera, scene)` | Through a point of the camera's image. `coords` is a `Vector2` in normalized device coordinates: -1 to 1 each way, y up. |
| `set_from_pixel(x, y, width, height, camera, scene)` | Through a pixel of an image the camera would render at `width` by `height`. y counts down from the top. The center of pixel `(i, j)` is `(i + 0.5, j + 0.5)`. |

A perspective camera's ray leaves the camera's position toward the point. An orthographic camera's ray starts on the camera's own plane and goes the way the camera looks. Every orthographic ray is parallel. Both are three.js's choices.

The camera can ride a scene node. The scene must be updated. See [Cameras](Cameras#attach-a-camera-to-a-node).

## Ask the scene

```mojo
var hits = caster.intersect_scene(scene, assets)
if len(hits) > 0:
    print(hits[0].mesh.node, hits[0].point)
```

| Method | Meaning |
|---|---|
| `intersect_scene(scene, assets) -> List[Hit]` | Every hit on every mesh, instanced mesh, batched mesh and LOD, nearest first. |
| `intersect_mesh(scene, assets, index) -> List[Hit]` | Every hit on `scene.meshes[index]`, nearest first. |
| `intersect_instanced_mesh(scene, assets, index) -> List[Hit]` | Every hit on every instance of `scene.instanced_meshes[index]`. |
| `intersect_batched_mesh(scene, assets, index) -> List[Hit]` | Every hit on every instance of `scene.batched_meshes[index]`. |
| `intersect_lod(scene, assets, index) -> List[Hit]` | Every hit on the level of `scene.lods[index]` that the ray's origin picks. |

## Hit

| Field | Meaning |
|---|---|
| `distance` | Meters from the ray's origin. |
| `point` | Where, in world space. |
| `normal` | The face's front in world space, unit length. The face as wound, whichever side the ray came from. |
| `kind` | A `HitKind`: which list `index` counts in. `MESH_HIT`, `INSTANCED_HIT`, `BATCHED_HIT` or `LOD_HIT`. |
| `index` | The object's position in that list. |
| `instance` | Which instance of an instanced or batched mesh, or which level of an LOD. -1 for a plain mesh. three.js's `instanceId` and `batchId`. |
| `mesh` | The shape struck as a `Mesh`: its node, geometry and material. For a plain mesh, the mesh itself. |
| `triangle` | Which of the geometry's triangles, from zero. |

A `HitKind` is a type. A bare integer does not compile.

## What it sees

The mesh as it is drawn, not as it was modelled. A mesh wearing a [morph target](Geometry#morph-targets) is picked where the target has carried it, because picking and the renderer both ask `core/deform.mojo` the same question.

They did not always. Rendering wore the targets and picking did not. The drawn shape could not be hit, and the modelled one could be hit where nothing was.

An [instanced mesh](Meshes-and-assets#instancedmesh) is picked instance by instance. Each instance is tested at the node's transform times its own. A [batched mesh](Meshes-and-assets#batchedmesh) is picked the same way, with each instance's own geometry. An [LOD](Meshes-and-assets#lod) is picked on one level. That level is the one the distance from the ray's origin to the node picks with no memory, as three.js's `LOD.raycast` does.

A [skinned mesh](Skinning) is not picked at all. A `SkinnedMesh` is in a list of its own. A rig is therefore never offered to the ray, rather than being silently picked in its rest pose. Teaching it about rigs needs the posed bones, which come from the scene rather than the geometry.

## Rules

A mesh is tested in three steps. First its bounding sphere, in world space. Then its bounding box, in its own space. Then every triangle. A mesh the ray misses at the first step costs six multiplies.

The material's `side` decides which faces count. A `FRONT_SIDE` mesh is not picked through its back. A `BACK_SIDE` mesh is picked only on its back. A `DOUBLE_SIDE` mesh is picked on both. What the renderer draws, the raycaster hits. See [Materials](Materials#side).

A mirrored mesh is hit on the face the renderer draws. Its hit normal is turned back, as the renderer turns its geometric normal.

Skinned meshes and lines are not picked.

## Errors

- An index that names no mesh, instanced mesh, batched mesh or LOD raises.
- A mesh that names a missing node, geometry or material raises. A geometry with no positions raises.
- A stale scene raises. Call `scene.update()` first.
- A mesh whose world transform flattens a dimension raises. It has no inverse to carry the ray through.
- `set_from_pixel` raises for an image with no size.

## Example

```mojo
var caster = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1))
caster.set_from_pixel(160.5, 120.5, 320, 240, camera, scene)
for hit in caster.intersect_scene(scene, assets):
    print(hit.index, hit.distance)
```

See [Math](Math#ray) for the `Ray` the raycaster carries.
