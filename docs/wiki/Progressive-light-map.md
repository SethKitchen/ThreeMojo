# Progressive light map

`renderers/progressive_light_map.mojo` bakes the light on a set of meshes into one texture, a little each frame. It is three.js's `ProgressiveLightMap` from `examples/jsm/misc/`. Move the lights a small random distance each frame, and the shadows soften into an average.

![A cube's shadow softens on the floor as the lamp walks a circle](out/lightmap.png)

`examples/baked.mojo` draws this picture.

```mojo
var light_map = ProgressiveLightMap(assets, 1024)
light_map.add_objects_to_light_map(scene, assets, [ground, box])
# For each frame:
light_map.update(renderer, scene, assets, camera, blend_window=100)
var frame = renderer.render(scene, assets, camera)
```

## Adding the meshes

`add_objects_to_light_map(scene, assets, meshes)` takes the meshes by their place in `scene.meshes`. It gives each mesh a square of the map, with three pixels of padding around it. `math/potpack.mojo` packs the squares, as three.js packs them with mapbox's `potpack`.

The function writes each mesh's place into its geometry's `uv1`. It is the mesh's `uv`, moved into its square and scaled to the map. Then the function changes the mesh and its material:

- The material reads the second map as its `light_map`, with `dithering` on.
- The mesh casts and receives shadows.
- The mesh's node draws after the rest, in the order given: `render_order` is `1000` plus its place in the list.

A mesh must have a `uv`. Its material must be basic or lit, and not a wireframe, because only those read a light map. The function raises for any other mesh.

## An update

`update(renderer, scene, assets, camera, blend_window, blur_edges)` draws the meshes into the map once. It draws each mesh where its `uv1` puts it, with a white `PHONG` material. The material mixes the new light into the old map: `mix(old, lit, 1 / blend_window)`. So each update adds one part in `blend_window`, and the default is 100.

The map is two float textures in `light_map.maps`. An update draws into one and reads the other, so the two change places each time. The meshes read the second texture, as three.js's meshes read `progressiveLightMap2`.

`update` does nothing before a mesh is added. It raises if `blend_window` is not a positive finite number.

## The blur

With `blur_edges` on, the default, each pixel of the map first takes the average of its eight neighbors in the old map. Then the meshes draw over their own pixels. So only the padding keeps the blur. The padding takes the color of the edges beside it, and a filtered read at an edge does not get black.

## The draw in texture space

`update` draws with a copy of the renderer, the size of the map. It sets the copy's `uv_space_meshes` to the meshes. You can set this field on any `Renderer`:

- Only the meshes in the list are drawn. No other mesh, line, point, sprite or background is drawn.
- Each triangle is put where its `uv1` is on the viewport, `u1` from the left and `v1` up from the bottom. It is three.js's `gl_Position = vec4((uv1 - 0.5) * 2.0, 1.0, 1.0)`.
- The triangle is lit where it stands in the world. It is not clipped, culled or fogged.

Both rasterizers draw this frame the same way. `tests/test_gpu.mojo` checks it.

## The debug plane

`show_debug_light_map(scene, assets, visible, position)` shows the first map on a plane, 100 units wide. It is three.js's `showDebugLightmap`. The first call adds the plane beside the first mesh, 250 units up. It raises if no mesh has been added.

## Where this port differs

- three.js moves the meshes into a scene of their own and hands the lights to that scene. Here the meshes stay in their scene. All of the scene's lights light them, and all of its casters shadow them.
- three.js culls the back of a triangle in texture space. Here neither side is culled.
- The maps are float textures in `assets.textures`. three.js keeps them in render targets.
- The blur is done on the host before the draw. three.js draws a plane with a blur shader.
