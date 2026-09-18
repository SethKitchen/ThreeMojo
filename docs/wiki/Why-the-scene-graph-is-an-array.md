# Why the scene graph is an array

`Scene` holds every node in one flat array, and each node records its parent's index. three.js holds a tree of objects that own their children. Mojo cannot express that tree, and the array turned out better.

![A chain of parented cubes waves from the first node](out/chain.png)

## Mojo cannot nest a struct in itself

three.js gives every `Object3D` a `children` array. In Mojo a struct cannot hold a `List` of its own type. The compiler rejects it with `field 'children' has non-'Deinitable' type`.

So the tree is stored the other way round. A node knows its parent. The scene owns the array.

## Parents come first

`add` refuses a parent that is not already in the array. A parent therefore always precedes its children. That makes `update` one forward pass: by the time a node is reached, its parent's world matrix is final. There is no recursion and no visited set. A cycle is impossible by construction.

## Stale transforms are refused

`update` caches every world matrix. Any edit to a node marks the scene stale, and `world_matrix` raises until `update` runs again. Recomputing on read would hide the cost of a render. Serving the stale value would produce a plausible wrong image with no error at all.

## Meshes and lights are scene content

three.js's `scene.add` takes a mesh or a light. Here `add_mesh` and `add_light` do the same. Both name a node by id and hold no transform. A light parented to a turning object moves with it, which a light stored on the renderer could not do.

## Nodes are edited in place

`scene.node(id)` returns a mutable reference and marks the scene stale. That is what `mesh.rotation.y += 0.01` needs in three.js terms: one persistent scene, one field changed, one `update`, one render.

## The limit

A node cannot move under a parent that was added after it. That is a valid acyclic operation which the ordering forbids. The fix, when something needs it, is a stable node id separate from the traversal order.
