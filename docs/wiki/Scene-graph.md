# Scene graph

`core/object3d.mojo` and `core/scene.mojo`. A `Scene` holds a flat array of `Object3D` nodes. Each node records its parent's index. Meshes and lights name a node by id.

three.js: `Object3D`, `Scene`, `Group`.

## Object3D

A node is a transform relative to its parent: a position, a quaternion and a scale.

| Member | Meaning |
|---|---|
| `position: Vector3` | Offset from the parent, in meters. |
| `quaternion: Quaternion` | Rotation. See [Rotations](Rotations). |
| `scale: Vector3` | Scale factors along the node's own axes. |
| `parent: NodeId` | The parent's index, or `NO_PARENT`. |
| `layers: Layers` | Which layers the node is on. Layer zero by default. See below. |
| `set_position(x, y, z)` | Set the position. |
| `set_scale(x, y, z)` | Set the scale. Three factors, so a non-uniform scale is possible. |
| `set_euler(x, y, z, order=XYZ)` | Set the rotation from three angles. |
| `local_matrix()` | The transform `translation * rotation * scale`. |

A `NodeId` wraps an integer. A bare integer does not compile where a node id is expected.

## Scene

| Member | Meaning |
|---|---|
| `add(node) -> NodeId` | Add a root node, or a node whose `parent` is already in the scene. |
| `attach(node, parent) -> NodeId` | Add a node as a child of `parent`. |
| `node(id) -> ref Object3D` | Borrow a node for editing. Marks the scene stale. |
| `get(id) -> Object3D` | Copy a node. |
| `set(id, node)` | Replace a node. The parent must be an earlier node. |
| `add_mesh(mesh)` | Add something to draw. See [Meshes and assets](Meshes-and-assets). |
| `add_light(light)` | Add a light. See [Lights](Lights). |
| `update()` | Compute every world matrix in one forward pass. |
| `world_matrix(id) -> Matrix4` | A node's world transform. Raises if the scene is stale. |
| `world_position(id) -> Vector3` | A node's origin in world space. |
| `look_at(id, target, camera=False)` | Turn a node to face a world-space point. See [Rotations](Rotations). |
| `is_stale() -> Bool` | True when a node changed after the last `update`. |
| `validate()` | Check that every parent index is an earlier node. |

## Layers

`core/layers.mojo`. A `Layers` is a set of up to thirty-two layers, held as a bit mask. Every node and every camera has one. A camera draws a mesh only if the mesh's node shares a layer with the camera. Both start on layer zero alone, so a scene that never mentions layers renders as before.

three.js: `Layers`, `Object3D.layers`, `Camera.layers`.

| Member | Meaning |
|---|---|
| `set(layer)` | Only that layer. |
| `enable(layer)`, `disable(layer)`, `toggle(layer)` | One layer at a time. |
| `enable_all()`, `disable_all()` | Every layer, or none. |
| `is_enabled(layer) -> Bool` | Whether one layer is in the set. |
| `test(other) -> Bool` | Whether the two sets share a layer. |

A layer is a number from 0 to 31. Any other number raises. three.js wraps it silently.

```mojo
scene.node(overlay).layers.set(1)    # only on layer one
camera.layers.enable(1)              # the camera sees layer one as well
```
| `count() -> Int` | The number of nodes. |
| `meshes`, `lights` | The scene content, as public lists. |

## Rules

- A parent is always added before its children. `add` and `set` refuse anything else.
- Any change to a node makes the scene stale. `world_matrix` refuses to answer until `update` runs.
- A stale scene renders stale positions. Call `update` before `render`.
- Adding a mesh or a light does not make the scene stale. Neither holds a transform.

## Example

```mojo
var scene = Scene()
var pivot = scene.add(Object3D())
var moon = Object3D()
moon.set_position(1.6, 0, 0)
var moon_node = scene.attach(moon^, pivot)
scene.update()

scene.node(pivot).rotate_y(Angle(30.0, DEGREE))   # the moon orbits
scene.update()
var where = scene.world_position(moon_node)
```

## Limits

A node cannot move to a parent that was added after it. Reparenting in that direction needs a stable id that is separate from the traversal order, which does not exist yet.

## Why

See [Why the scene graph is an array](Why-the-scene-graph-is-an-array).
