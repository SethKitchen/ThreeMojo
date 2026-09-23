# Scene graph

`core/object3d.mojo` and `core/scene.mojo`. A `Scene` holds a flat array of `Object3D` nodes. Each node records its parent's index. Meshes and lights name a node by id.

![A small cube orbits a large cube and passes behind it](out/cubes.png)

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
| `add_instanced_mesh(mesh)`, `add_batched_mesh(mesh)`, `add_lod(lod)` | Add the other things a scene draws. See [Meshes and assets](Meshes-and-assets#instancedmesh). |
| `add_light(light)` | Add a light. See [Lights](Lights). |
| `fog: Fog` | The scene's fog. `no_fog()` to begin with. See [Fog](Fog). |
| `background: Background` | What shows where nothing is drawn. `no_background()` to begin with. See below. |
| `environment: CubeTextureId` | The cube texture a material reflects when its `env_map` is `SCENE_ENVIRONMENT`. `NO_CUBE_TEXTURE` to begin with. |
| `update()` | Compute every world matrix in one forward pass. |
| `world_matrix(id) -> Matrix4` | A node's world transform. Raises if the scene is stale. |
| `world_position(id) -> Vector3` | A node's origin in world space. |
| `look_at(id, target, camera=False)` | Turn a node to face a world-space point. See [Rotations](Rotations). |
| `is_stale() -> Bool` | True when a node changed after the last `update`. |
| `validate()` | Check that every parent index is an earlier node. |

## Background and environment

`core/background.mojo`. A scene holds one background in `scene.background`. three.js's `Scene.background` holds a color, a texture or a cube texture, or nothing. Here the four are one struct with a kind, as a `Fog` is.

```mojo
scene.background = color_background(Color(30, 60, 90))
scene.background = texture_background(picture)
scene.background = cube_background(sky)
scene.background = no_background()
scene.environment = sky
```

| Builder | Kind | The renderer |
|---|---|---|
| `no_background()` | `NO_BACKGROUND` | Clears to its own `background` color. What a scene starts with. |
| `color_background(color)` | `COLOR_BACKGROUND` | Clears to that color instead. three.js's `setClearColor` gives way to `scene.background`. |
| `texture_background(id)` | `TEXTURE_BACKGROUND` | Stretches the texture over the viewport, behind everything. |
| `cube_background(id)` | `CUBE_BACKGROUND` | Draws the cube texture as a sky: each pixel reads the direction its ray leaves the camera along. |

A background is behind everything and claims no depth. A surface at any depth covers it, and a translucent surface blends over it. The fog does not reach it. three.js draws its image backgrounds the same way, with the depth test off, before the scene.

A texture background is read at its full size through its own filter. Its transform is not applied, and its alpha is not read: three.js draws the plane opaque. A cube background turns as the camera turns and holds still as the camera moves. A parallel camera sees one direction everywhere. An image background is a texture, so only `SHADE_TEXTURE` draws it. The other two shading modes clear to the color.

An equirectangular panorama becomes a sky or an environment through `cube_from_equirectangular`. three.js does the same for `EquirectangularReflectionMapping`. See [HDR images](Textures#hdr-images).

`Renderer.backdrop(scene, assets, camera)` returns the image background as the camera sees it, as an opaque `Framebuffer`, or none. `Renderer.render` paints it under the scene, and `GpuRenderer.draw` takes it, so both backends start a frame from the same bytes. See [Renderer](Renderer#what-render-does) and [GPU backend](GPU-backend).

`environment` is the cube texture a material reflects when its `env_map` is `SCENE_ENVIRONMENT`. three.js applies `scene.environment` to every physically based material without asking. Those are not ported, and this project's materials reflect nothing unless told to, so a material asks. See [Materials](Materials#environment-map).

The fields of a `Background` are open. `validate()` refuses a kind that is none of the four, and a texture or cube background that names no id. The renderer calls it every frame, and refuses an id the assets do not hold. `tests/compile_fail/` proves a bare `Color` is not a background.

## Layers

`core/layers.mojo`. A `Layers` is a set of up to thirty-two layers, held as a bit mask. Every node, every light and every camera has one. A camera draws a mesh only if the mesh's node shares a layer with the camera. It lights the frame with only the lights that share a layer with it. All start on layer zero alone, so a scene that never mentions layers renders as before.

Layers are each node's own. A child does not take its parent's layers. A child on the camera's layer is drawn under a parent that is not.

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
scene.lights[0].layers.set(1)        # the first light too
camera.layers.enable(1)              # the camera sees layer one as well
```
| `count() -> Int` | The number of nodes. |
| `meshes`, `instanced_meshes`, `batched_meshes`, `lods`, `lights` | The scene content, as public lists. |

## Visibility, names and render order

`Object3D` carries four more fields, as three.js's `Object3D` does.

| Field | Default | Meaning |
|---|---|---|
| `visible` | `True` | False hides the node and everything under it. |
| `name` | empty | A name to find the node by. Two nodes can share one. |
| `render_order` | `0` | Where the node's objects go in the draw order. Lower draws first. |
| `matrix_auto_update` | `True` | False keeps `matrix` as the caller set it. |

`matrix` is the node's transform relative to its parent. `update` rebuilds it from the position, rotation and scale when `matrix_auto_update` is set. Otherwise it keeps what the caller wrote.

A hidden node still has a world matrix. The renderer skips every mesh, line, point set, sprite and light on it. The raycaster skips its meshes too. `update` works out which nodes are shown.

| Scene member | Meaning |
|---|---|
| `is_shown(node) -> Bool` | True if the node and every node above it are visible. |
| `shows(node, layers) -> Bool` | True if the node is shown and shares a layer with `layers`. The renderer asks this of every object. |
| `light_shown(light) -> Bool` | True if the light has no node, or its node is shown. |
| `find(name) -> Optional[NodeId]` | The earliest node with the name. three.js: `getObjectByName`. |
| `children(node) -> List[NodeId]` | The node's direct children. |
| `descendants(node) -> List[NodeId]` | The node, then every node under it, each after its parent. three.js: `traverse`. |
| `render_order(node) -> Int` | The node's render order. |

The renderer sorts each list of draws by render order first. Within one order, opaque draws go nearest first and blended draws furthest first, as before. Give a translucent surface a higher order to draw it over another whatever their depths.

## Rules

- A parent is always added before its children. `add` and `set` refuse anything else.
- Any change to a node makes the scene stale. `world_matrix` refuses to answer until `update` runs.
- A stale scene renders stale positions. Call `update` before `render`.
- Adding a mesh or a light does not make the scene stale. Neither holds a transform. Nor does setting the fog.

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
