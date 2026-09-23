# Raycasting

`core/raycaster.mojo`. A `Raycaster` carries a `Ray` through a scene and returns everything it meets, nearest first: meshes, skinned meshes, lines, points and sprites. Use it to find what is under a pixel.

![A red marker sits where a ray hits the sphere under the pixel](out/raycast.png)

three.js: `Raycaster`, `setFromCamera`, `intersectObject`, `intersectObjects`, `Mesh.raycast`, `SkinnedMesh.raycast`, `Line.raycast`, `Points.raycast`, `Sprite.raycast`.

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

| Field | Default | Meaning |
|---|---|---|
| `line_threshold` | 1 m | How near a line the ray must pass to meet it. three.js: `params.Line.threshold`. |
| `points_threshold` | 1 m | How near a point the ray must pass to meet it. three.js: `params.Points.threshold`. |

Both thresholds are a meter by default, as in three.js. That is wide for a small scene. Set them to what a pointer must reach. A negative threshold, or one that is not a number, raises when it is used.

`caster.layers` is a `Layers`, on layer zero by default. An object whose node shares no layer with it is not tested. See [Scene graph](Scene-graph#layers).

## Aim it

| Method | Meaning |
|---|---|
| `set(origin, direction)` | A new ray. |
| `set_from_camera(coords, camera, scene)` | Through a point of the camera's image. `coords` is a `Vector2` in normalized device coordinates: -1 to 1 each way, y up. |
| `set_from_pixel(x, y, width, height, camera, scene)` | Through a pixel of an image the camera would render at `width` by `height`. y counts down from the top. The center of pixel `(i, j)` is `(i + 0.5, j + 0.5)`. |

A perspective camera's ray leaves the camera's position toward the point. An orthographic camera's ray starts on the camera's own plane and goes the way the camera looks. Every orthographic ray is parallel. Both are three.js's choices.

`set_from_camera` and `set_from_pixel` also keep the camera, three.js's `Raycaster.camera`. A sprite faces the camera, so a sprite is picked only after one of them. A later `set` keeps the camera.

The camera can ride a scene node. The scene must be updated. See [Cameras](Cameras#attach-a-camera-to-a-node).

## Ask the scene

```mojo
var hits = caster.intersect_scene(scene, assets)
if len(hits) > 0:
    print(hits[0].mesh.node, hits[0].point)
```

| Method | Meaning |
|---|---|
| `intersect_scene(scene, assets) -> List[Hit]` | Every hit on everything the scene holds that can be picked, nearest first. Sprites are left out until a camera is kept. |
| `intersect_mesh(scene, assets, index) -> List[Hit]` | Every hit on `scene.meshes[index]`, nearest first. |
| `intersect_instanced_mesh(scene, assets, index) -> List[Hit]` | Every hit on every instance of `scene.instanced_meshes[index]`. |
| `intersect_batched_mesh(scene, assets, index) -> List[Hit]` | Every hit on every instance of `scene.batched_meshes[index]`. |
| `intersect_lod(scene, assets, index) -> List[Hit]` | Every hit on the level of `scene.lods[index]` that the ray's origin picks. |
| `intersect_skinned_mesh(scene, assets, index) -> List[Hit]` | Every hit on `scene.skinned_meshes[index]`, where its bones carry it. |
| `intersect_line(scene, assets, index) -> List[Hit]` | Every segment of `scene.lines[index]` within `line_threshold` of the ray. |
| `intersect_points(scene, assets, index) -> List[Hit]` | Every point of `scene.points[index]` within `points_threshold` of the ray. |
| `intersect_sprite(scene, assets, index) -> List[Hit]` | The hit on `scene.sprites[index]`, if any. |
| `intersect_wide_line(scene, assets, index, camera, width, height) -> List[Hit]` | Every segment of `scene.wide_lines[index]` that the ray passes within half the line's width of. See [wide lines](Lines#wide-lines). |

## Hit

| Field | Meaning |
|---|---|
| `distance` | Meters from the ray's origin. |
| `point` | Where, in world space. |
| `normal` | The face's front in world space, unit length. The face as wound, whichever side the ray came from. Zero for a line, points or a sprite, which have no face. For a wide line, the way back along the ray. |
| `kind` | A `HitKind`: which list `index` counts in. `MESH_HIT`, `INSTANCED_HIT`, `BATCHED_HIT`, `LOD_HIT`, `SKINNED_HIT`, `LINE_HIT`, `POINTS_HIT`, `SPRITE_HIT` or `WIDE_LINE_HIT`. |
| `index` | The object's position in that list. |
| `instance` | Which instance of an instanced or batched mesh, or which level of an LOD. -1 for a plain mesh. three.js's `instanceId` and `batchId`. |
| `mesh` | The shape struck as a `Mesh`: its node, geometry and material. For a plain mesh, the mesh itself. A sprite has no geometry, so its `geometry` is -1. |
| `triangle` | Which of the geometry's triangles, from zero. For a line or a wide line, which segment. For points, which point. For a sprite, which of its two halves. |

A `HitKind` is a type. A bare integer does not compile.

## What it sees

The mesh as it is drawn, not as it was modelled. A mesh wearing a [morph target](Geometry#morph-targets) is picked where the target has carried it, because picking and the renderer both ask `core/deform.mojo` the same question.

They did not always. Rendering wore the targets and picking did not. The drawn shape could not be hit, and the modelled one could be hit where nothing was.

An [instanced mesh](Meshes-and-assets#instancedmesh) is picked instance by instance. Each instance is tested at the node's transform times its own. A [batched mesh](Meshes-and-assets#batchedmesh) is picked the same way, with each instance's own geometry. An [LOD](Meshes-and-assets#lod) is picked on one level. That level is the one the distance from the ray's origin to the node picks with no memory, as three.js's `LOD.raycast` does.

A [skinned mesh](Skinning) is picked where its bones carry it, after its morph targets. The renderer and the raycaster both ask `core/deform.mojo` for the posed bones and the matrix that carries each vertex.

### Lines, points and sprites

A line is met where the ray passes within `line_threshold` of a segment. The hit's `point` is on the segment, and its `distance` is to the ray's nearest point, as three.js reports them. A strip, a loop and a list of segments are all read as the renderer reads them.

Points are met where the ray passes within `points_threshold` of a point. The hit's `point` is the ray's point nearest that point.

The gap is measured in world space. three.js divides the threshold by the object's average scale and measures in the object's own space. The two agree under an even scale. Under an uneven scale, this port is exact and three.js is not.

A sprite is met on its two triangles, laid flat to the kept camera with its center, rotation and size, as the renderer lays them.

## Rules

A mesh is tested in three steps. First its bounding sphere, in world space. Then its bounding box, in its own space. Then every triangle. A mesh the ray misses at the first step costs six multiplies.

The material's `side` decides which faces count. A `FRONT_SIDE` mesh is not picked through its back. A `BACK_SIDE` mesh is picked only on its back. A `DOUBLE_SIDE` mesh is picked on both. What the renderer draws, the raycaster hits. See [Materials](Materials#side).

A mirrored mesh is hit on the face the renderer draws. Its hit normal is turned back, as the renderer turns its geometric normal.

A geometry of lines or points must not be indexed, as for the renderer.

A wide line is picked by `intersect_wide_line` alone, because a width in pixels needs a camera and an image size. `intersect_scene` has neither.

## Errors

- An index that names no object in its list raises.
- A sprite pick with no kept camera raises.
- A negative threshold, or one that is not a number, raises.
- An indexed line or points geometry raises.
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
