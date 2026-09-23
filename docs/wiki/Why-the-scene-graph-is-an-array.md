# Why the scene graph is an array

`Scene` holds every node in one flat array, and each node records its parent's index. three.js holds a tree of objects that own their children. Mojo cannot express that tree, and the array turned out better.

![A chain of parented cubes waves from the first node](out/chain.png)

## Mojo cannot nest a struct in itself

three.js gives every `Object3D` a `children` array. In Mojo a struct cannot hold a `List` of its own type. The compiler rejects it with `field 'children' has non-'Deinitable' type`.

So the tree is stored the other way round. A node knows its parent. The scene owns the array.

## Ids are stable and the order is kept apart

A node's id is its place in the array. The id never changes, because every mesh, light, bone and animation track names its node by id.

The order of the tree is kept beside the array. The scene lists every node in the order it became a child, which is the order of three.js's `children`. `update` walks the tree from the roots in that order. A parent is therefore always final before its children, whatever the ids. So a node can move under a node that was added after it.

## A loop is found

`add` and `attach` refuse a parent that is the node or under it. A reference from `scene.node(id)` can still set any parent. A node on a loop cannot be reached from a root. So `update` counts the nodes it reaches, and it raises when some are missing.

## Removed nodes stay in the array

three.js's `remove` gives an object no parent, and something else can still hold that object. Here the scene holds every node, so a removed node stays in the array with a mark. It keeps its id, so nothing that names it goes wrong. The renderer, the raycaster, the mixer and the exporters skip it. The cost is that the array only grows.

## Stale transforms are refused

`update` caches every world matrix. Any edit to a node marks the scene stale, and `world_matrix` raises until `update` runs again. Recomputing on read would hide the cost of a render. Serving the stale value would produce a plausible wrong image with no error at all.

## Meshes and lights are scene content

three.js's `scene.add` takes a mesh or a light. Here `add_mesh` and `add_light` do the same. Both name a node by id and hold no transform. A light parented to a turning object moves with it, which a light stored on the renderer could not do.

## Nodes are edited in place

`scene.node(id)` returns a mutable reference and marks the scene stale. That is what `mesh.rotation.y += 0.01` needs in three.js terms: one persistent scene, one field changed, one `update`, one render.
