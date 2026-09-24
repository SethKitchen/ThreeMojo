# Why render hooks are a trait

A render hook is a struct that conforms to `RenderHooks`, and the renderer takes it as a generic parameter. A function field on each object cannot keep state, and a trait object does not exist in Mojo. A generic trait parameter keeps state and costs nothing when no hook is given.

## What three.js does

three.js puts a function on each object: `mesh.onBeforeRender = function (renderer, scene, camera, geometry, material, group) { ... }`. The function is a closure. It can hold a counter, a list or a reference to another object. The renderer calls it for each object that it draws.

## Why a function field does not work

A struct field in Mojo can hold a `thin` function. A thin function captures nothing, so it cannot count, log or collect. A capturing closure has a type that the compiler makes for that closure only, so a list of objects cannot hold closures of different types.

The objects of a scene live in lists of plain values, such as `scene.meshes`. A field of a closure type on `Mesh` would make every mesh a different type. See [Why the scene graph is an array](Why-the-scene-graph-is-an-array).

## Why a trait object does not work

A language with trait objects stores a pointer and a table of functions, and calls through the table. Mojo 1.1 has no such type. A trait in Mojo is a bound on a generic parameter. The compiler makes one copy of the function for each type that it is called with.

## What the port does

The renderer takes one hooks value for the whole frame: `render_with[C: Camera, H: RenderHooks](hooks, scene, assets, camera)`. The hooks struct holds the state. Each method receives the `RenderItem`, which names the node, the geometry and the material. A hook that runs for one object only compares the node.

- `RenderHooks` gives every method a body that does nothing. A struct replaces only the methods that it needs.
- `render` passes `NoHooks`. Its calls do no work, so a frame with no hooks costs the same as before.
- The hooks value is `mut`, so a hook can count or collect without a global.

## Why a sort is a function

A sort compares two items and keeps no state. three.js passes a comparator for `setOpaqueSort` and `setTransparentSort`. A thin function does the same job, so `RenderSort` is a thin function type, and `set_opaque_sort` stores it in a field.

## Why a hook cannot change the frame

The renderer prepares the whole frame, and then both rasterizers draw it. The CPU draws it in bands on many threads, and the GPU draws it in one launch. There is no point between two objects where a hook can run. So the before hooks run after the frame is prepared and before it is drawn, and the after hooks run after it is drawn. To change what an object looks like, change the scene or the assets between frames.
