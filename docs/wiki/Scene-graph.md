# Scene graph

`core/object3d.mojo` and `core/scene.mojo`. A `Scene` holds a flat array of `Object3D` nodes. Each node records its parent's index. Meshes and lights name a node by id. A node can move under any other node, and it keeps its id.

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
| `object_type: ObjectType` | `OBJECT3D_TYPE`, or `GROUP_TYPE` for a group. See [Groups](#groups). |
| `user_data: UserData` | What the caller keeps on the node. See [User data](#user-data). |
| `set_position(x, y, z)` | Set the position. |
| `set_scale(x, y, z)` | Set the scale. Three factors, so a non-uniform scale is possible. |
| `set_euler(x, y, z, order=XYZ)` | Set the rotation from three angles. |
| `local_matrix()` | The transform `translation * rotation * scale`. |

A `NodeId` wraps an integer. A bare integer does not compile where a node id is expected.

### Transform a node in its own frame

These methods change one node and need no scene. They use three.js's arithmetic.

| Member | three.js | Meaning |
|---|---|---|
| `translate_x(d)`, `translate_y(d)`, `translate_z(d)` | `translateX` and the others | Move a `Length` along one of the node's own axes. |
| `translate_on_axis(axis, d)` | `translateOnAxis` | Move a `Length` along a unit axis in the node's own frame. |
| `rotate_x(a)`, `rotate_y(a)`, `rotate_z(a)` | `rotateX` and the others | Turn an `Angle` about one of the node's own axes. |
| `rotate_on_axis(axis, a)` | `rotateOnAxis` | Turn about a unit axis in the node's own frame. |
| `rotate_on_world_axis(axis, a)` | `rotateOnWorldAxis` | Turn about a unit axis in the parent's frame. |
| `apply_matrix4(m)` | `applyMatrix4` | Premultiply the node's matrix by `m`, then read the position, rotation and scale back. |
| `apply_quaternion(q)` | `applyQuaternion` | Premultiply the rotation by `q`. |
| `set_rotation_from_axis_angle(axis, a)` | `setRotationFromAxisAngle` | Set the rotation to one turn about a unit axis. |
| `set_rotation_from_euler(e)` | `setRotationFromEuler` | Set the rotation from an `Euler`. |
| `set_rotation_from_matrix(m)` | `setRotationFromMatrix` | Set the rotation from a pure rotation matrix. |
| `set_rotation_from_quaternion(q)` | `setRotationFromQuaternion` | Set the rotation to `q`. |
| `set_from_matrix(m)` | `matrix.decompose` | Set the position, rotation and scale from a transform. |

`apply_matrix4` and `set_from_matrix` refuse a matrix that flattens an axis. three.js writes a rotation that is not a number in that case. The node does not change when they refuse.

## Scene

| Member | Meaning |
|---|---|
| `add(node) -> NodeId` | Add a root node, or a node whose `parent` is already in the scene. |
| `attach(node, parent) -> NodeId` | Add a node as a child of `parent`. |
| `node(id) -> ref Object3D` | Borrow a node for editing. Marks the scene stale. |
| `get(id) -> Object3D` | Copy a node. |
| `set(id, node)` | Replace a node. The parent must not be the node or under it. |
| `count() -> Int` | The number of nodes, removed nodes included. |
| `add_mesh(mesh)` | Add something to draw. See [Meshes and assets](Meshes-and-assets). |
| `add_instanced_mesh(mesh)`, `add_batched_mesh(mesh)`, `add_lod(lod)` | Add the other things a scene draws. See [Meshes and assets](Meshes-and-assets#instancedmesh). |
| `add_light(light)` | Add a light. See [Lights](Lights). |
| `fog: Fog` | The scene's fog. `no_fog()` to begin with. See [Fog](Fog). |
| `background: Background` | What shows where nothing is drawn. `no_background()` to begin with. See below. |
| `environment: CubeTextureId` | The cube texture a material reflects when its `env_map` is `SCENE_ENVIRONMENT`. `NO_CUBE_TEXTURE` to begin with. |
| `update()` | Compute every world matrix in one pass down the tree. |
| `world_matrix(id) -> Matrix4` | A node's world transform. Raises if the scene is stale. |
| `world_position(id) -> Vector3` | A node's origin in world space. |
| `look_at(id, target, camera=False)` | Turn a node to face a world-space point. See [Rotations](Rotations). |
| `is_stale() -> Bool` | True when a node changed after the last `update`. |
| `validate()` | Check that every parent index names a node and that no parent links make a loop. |

## Edit the graph

A node moves under a new parent with `add` or `attach`. It leaves its parent with `remove`. The new parent can be older or newer than the node. `NO_PARENT` stands for the scene itself.

| Member | three.js | Meaning |
|---|---|---|
| `add(child, parent=p)` | `p.add(child)` | Move a node under `p`. It keeps its local transform, so it moves in the world. |
| `attach(child, parent=p)` | `p.attach(child)` | Move a node under `p` and keep its world transform. |
| `detach(child)` | `scene.attach(child)` | Move a node to the top of the scene and keep its world transform. |
| `remove(child, parent=p)` | `p.remove(child)` | Take a node off `p`. Nothing happens when `p` is not its parent. |
| `remove_from_parent(child)` | `removeFromParent` | Take a node off its parent, whatever the parent is. |
| `clear(p)`, `clear()` | `p.clear()`, `scene.clear()` | Take off every child of `p`, or every node at the top of the scene. |
| `in_scene(id) -> Bool` | | True when the node and every node above it are not removed. |

A moved node becomes the last child of its new parent, as in three.js. `add` and `attach` refuse a parent that is the node or under it. three.js accepts that parent and makes a loop.

`attach` works out the world transforms from the parents at once. The scene does not need to be current. Under a nonuniform scale the result can be sheared. A node cannot hold a shear, so the shear is lost, as in three.js.

```mojo
var arm = scene.add(Object3D())
var cup = scene.add(Object3D())
scene.attach(cup, parent=arm)     # the cup stays where it is and follows the arm
scene.remove(cup, parent=arm)     # the cup leaves the scene
scene.add(cup)                    # the cup comes back at the top of the scene
```

### Removed nodes

A removed node stays in the array and keeps its id. Everything that names it by id stays valid. A removed node keeps its children, its transform and its world matrix.

A removed node and everything under it are out of the scene:

- The renderer does not draw what they carry, and their lights do not shine.
- The raycaster does not hit their meshes.
- The animation mixer does not change them.
- The scene JSON, glTF, OBJ, STL and PLY exporters do not write them.
- `traverse`, `find` and the other searches of the whole scene do not reach them.

`add` or `attach` brings a removed node back with its subtree. A scene that removes a node every frame grows by one node every frame. Build a new scene when that matters.

## Transforms in the world

These methods read the world matrices that `update` computed. They raise when the scene is stale.

| Member | three.js | Meaning |
|---|---|---|
| `local_to_world(id, point)` | `localToWorld` | Carry a point from the node's frame into the world. |
| `world_to_local(id, point)` | `worldToLocal` | Carry a point from the world into the node's frame. |
| `world_position(id)` | `getWorldPosition` | The node's origin in the world. |
| `world_quaternion(id)` | `getWorldQuaternion` | The node's rotation in the world. |
| `world_scale(id)` | `getWorldScale` | The node's scale in the world. A mirror gives a negative x scale. |
| `world_direction(id, camera=False)` | `getWorldDirection` | The node's world +z axis, unit length. A camera gives -z. |

A camera looks along its -z axis, so `camera=True` negates the direction, as three.js's `Camera.getWorldDirection` does. A light is not a camera. Its direction is +z, as in three.js. `look_at` turns a light's -z to the target, as three.js's `lookAt` does. So a light that looks at a target has a direction that points away from it.

`world_quaternion` refuses a world matrix that flattens an axis. three.js returns numbers that are not numbers in that case.

## Walk the graph

Each method returns a list of node ids. three.js calls a function on each node instead. The order is three.js's order: a node, then each child's subtree in turn, in the order of `children`.

| Member | three.js | Meaning |
|---|---|---|
| `children(id)` | `children` | The node's direct children, in the order they became its children. `NO_PARENT` gives the nodes at the top of the scene. |
| `traverse(root=NO_PARENT)` | `traverse` | The root, then every node under it. `NO_PARENT` walks the whole scene. |
| `traverse_visible(root=NO_PARENT)` | `traverseVisible` | As `traverse`, without a hidden node and its subtree. |
| `traverse_ancestors(id)` | `traverseAncestors` | The parent, then the parent's parent, up to the top. |
| `descendants(id)` | `traverse` | The same as `traverse` from a node. |
| `find(name, root=NO_PARENT)` | `getObjectByName` | The first node with the name, or None. |
| `objects_by_name(name, root=NO_PARENT)` | `getObjectsByProperty('name', name)` | Every node with the name. |
| `object_by_id(id, root=NO_PARENT)` | `getObjectById` | The node, when it is the root or under it. Else None. |

`traverse` from a removed node walks its subtree, as three.js walks an object with no parent.

three.js's `getObjectsByProperty` takes the name of any property as a string. A Mojo struct has no lookup by name. Filter the list from `traverse` for any other property.

## Clone and copy

`clone` copies a node and its subtree as new nodes. `copy` makes one existing node like another.

| Member | three.js | Meaning |
|---|---|---|
| `clone(id, recursive=True) -> NodeId` | `clone` | New nodes with new ids. The copy of the root is removed, because three.js's clone has no parent. Add it with `add`. |
| `copy(target, source, recursive=True)` | `target.copy(source)` | The target takes the source's fields. With `recursive`, a clone of each child of the source is added under the target. |

`clone` also copies what each copied node carries: meshes, instanced and batched meshes, LODs, skinned meshes, lines, points, sprites, wide lines and lights. A light whose target is in the copied subtree aims at the copy of the target. A skinned mesh keeps its skeleton, as three.js's clone shares it.

`copy` keeps the target's parent, its place among its siblings, its `object_type` and what it carries. three.js keeps the class of the target in the same way.

```mojo
var second = scene.clone(car)          # a removed copy of the car and its wheels
scene.add(second)                      # put it in the scene
scene.node(second).translate_x(Length(3.0, METER))
```

## Groups

`objects/group.mojo`. `group()` returns an `Object3D` whose `object_type` is `GROUP_TYPE`. three.js's `Group` is an `Object3D` with the type `'Group'` and nothing more. A group moves, turns and hides its children as any node does.

The type matters only in scene JSON. The exporter writes a group as `"Group"`, and the loader reads `"Group"` back as a group. `ObjectType` is a type with `is_valid`. `add`, `set`, `update` and the exporter refuse a value that is neither type.

## User data

`core/user_data.mojo`. `UserData` is three.js's `userData`: a map from a string key to one JSON value. The keys keep the order in which they were first set.

| Member | Meaning |
|---|---|
| `set_number(key, x)`, `set_string(key, s)`, `set_boolean(key, b)`, `set_null(key)` | Set a key to one value. A number must be finite. |
| `set_json(key, text)` | Set a key to any one JSON value, such as an object or an array. |
| `number(key)`, `string(key)`, `boolean(key)` | Read a value. Raises when the key is missing or the value is of another kind. |
| `json(key)`, `kind(key)` | A value as JSON text, and its `JsonKind`. |
| `has(key)`, `remove(key)`, `count()`, `key(i)` | Ask about the keys, and remove one. |
| `to_json()` | The whole map as one JSON object. |

The scene JSON exporter writes the map as `userData`, and the loader reads it back. The glTF exporter writes it as `extras`, as three.js's `GLTFExporter` does. `clone` and `copy` copy the map, so the copy is independent.

A value is stored as JSON text. A whole number below 2^53 is written without a point, as `JSON.stringify` writes it. Other numbers can differ in form from JavaScript, for example `1e-07` for `1e-7`. Both forms are valid JSON. JavaScript puts keys that look like array indices first. This port keeps every key where it was first set.

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

A texture with an equirectangular mapping is not stretched. The renderer reads it by direction, as a sky. Name it as an environment through `cube_of_panorama`. See [An equirectangular environment or background](Textures#an-equirectangular-environment-or-background).

The scene holds five more settings, as three.js's `Scene` does:

| Field | three.js | Default | Meaning |
|---|---|---|---|
| `background_blurriness` | `backgroundBlurriness` | `0` | Above zero, a cube or a panorama background is read at this roughness, from zero to one. A cube reads its PMREM when it has one. |
| `background_intensity` | `backgroundIntensity` | `1` | What every background image is multiplied by. |
| `background_rotation` | `backgroundRotation` | no turn | An `Euler` that turns a cube or a panorama background. |
| `environment_intensity` | `environmentIntensity` | `1` | What a physical surface multiplies the scene's environment by. |
| `environment_rotation` | `environmentRotation` | no turn | An `Euler` that turns the scene's environment. |

`validate_environment()` refuses a blurriness outside zero to one, a negative intensity, and a rotation that is not finite or has no valid order. The renderer asks it every frame. A blurred background is read from a PMREM, so call `prefilter_environments(scene, assets)` first. Without one, a cube reads down its chain instead.

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

| Scene member | Meaning |
|---|---|
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
| `find(name) -> Optional[NodeId]` | The first node with the name. See [Walk the graph](#walk-the-graph). |
| `render_order(node) -> Int` | The node's render order. |

The renderer sorts each list of draws by render order first. Within one order, opaque draws go nearest first and blended draws furthest first, as before. Give a translucent surface a higher order to draw it over another whatever their depths.

## Rules

- A node's parent must be a node in the scene, or `NO_PARENT`.
- A node cannot go under itself or under one of its descendants. `update` and `validate` find a loop that a reference from `node` makes.
- Any change to a node makes the scene stale. `world_matrix` refuses to answer until `update` runs.
- A stale scene renders stale positions. Call `update` before `render`.
- Adding a mesh or a light does not make the scene stale. Neither holds a transform. Nor does setting the fog.
- A node's id never changes. A removed node keeps its id.

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

## Differences from three.js

- `add`, `attach` and `set` refuse a loop. three.js accepts it.
- A removed node stays in the scene's array. See [Removed nodes](#removed-nodes).
- The mixer does not animate a removed node. three.js goes on changing an object that it holds after the object leaves the scene.
- The walks return lists. three.js calls a function on each node.
- `traverse_ancestors` ends at the top node. three.js ends at the `Scene` object.
- A world query raises on a stale scene. three.js updates the world matrices first.
- `apply_matrix4`, `set_from_matrix` and `world_quaternion` refuse a matrix that flattens an axis.
- A change of parent made through `node(id)` keeps the node's place among its new siblings. Use `add` or `attach` to make it the last child.

## Why

See [Why the scene graph is an array](Why-the-scene-graph-is-an-array).
