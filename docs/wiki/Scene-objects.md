# Scene objects

This page covers the scene objects of three.js's `examples/jsm/objects/`. They are a mirror, a refracting pane, two waters, a sky, a lens flare, marching cubes, a grounded skybox and a planar shadow. Both rasterizers draw them, because each shader is a [node program](Node-materials) compiled from three.js's GLSL.

| Module | three.js |
|---|---|
| `objects/reflector.mojo` | `Reflector`, `Refractor` |
| `objects/water.mojo` | `Water` from `Water.js` |
| `objects/water2.mojo` | `Water` from `Water2.js` |
| `objects/sky.mojo` | `Sky` |
| `objects/lensflare.mojo` | `Lensflare`, `LensflareElement` |
| `objects/marching_cubes.mojo` | `MarchingCubes` |
| `objects/grounded_skybox.mojo` | `GroundedSkybox` |
| `objects/shadow_mesh.mojo` | `ShadowMesh` |

Each object adds its geometry, its program and its material to the stores. It holds a `mesh` that you add to the scene. The tests compare the matrices, the vertices and the flow with three.js 0.180 in Node. `assets/scene_objects/reference.mjs` writes the numbers.

## Mirrors and panes

A `Reflector` shows the scene mirrored through its plane. A `Refractor` shows what lies behind it. Before each frame, each object renders the scene again into a render target from a virtual camera. Its shader then reads the target at the point where the virtual camera saw each pixel.

```mojo
var mirror = Reflector(assets, quad, node, texture_width=512, texture_height=512)
scene.add_mesh(mirror.mesh)
scene.update()
_ = mirror.update(renderer, scene, assets, camera)
var image = renderer.render(scene, assets, camera)
```

Call `update` after `Scene.update` and before the render. `update` returns False and renders nothing when the camera is behind the surface. Set `force_update` to render the mirror once from behind, as three.js does.

| Member | three.js | Meaning |
|---|---|---|
| `mesh` | the mesh | The geometry, the shader material and the node. The surface's +z faces the viewer. |
| `program` | `material.uniforms` | The compiled shader. Its uniforms are `color`, `tDiffuse` and `textureMatrix`. |
| `texture` | `getRenderTarget().texture` | The target's texture. `update` replaces the texture that the id names. |
| `camera` | `camera` | The `VirtualCamera` of the last update. |
| `texture_matrix` | `textureMatrix` | The bias, the virtual projection and view, and the surface's world matrix. |
| `clip_bias` | `clipBias` | How far past the surface the clipping plane lies, as a `Length`. |

The constructor takes the three.js options: `color`, `texture_width`, `texture_height`, `clip_bias`, and a `vertex_shader` and a `fragment_shader` for three.js's `shader` option. The target is a half float target, as in three.js. The `Refractor` material is transparent, as in three.js.

### How the view is cut

The virtual render cuts away what lies on the wrong side of the surface. three.js puts the surface's plane into the projection as an oblique near plane. The clipper of this port cuts at the camera's near distance, so that projection would put the cut geometry at a depth below zero. The virtual render adds the plane to the renderer's clipping planes instead. The target gets the same pixels, and the depth keeps its full range.

`clip_bias` moves that plane past the surface in meters. three.js adds its bias to the oblique row of the projection, so the two biases do not have the same unit.

### Why update is a call

A [render hook](Renderer-hooks-and-material-flags#hooks) observes a frame and cannot change it. So this port has no `onBeforeRender` that draws a target. `update` takes the scene mutably, because it hides the object's node while it draws the target. three.js sets `visible` to false for the same reason. The node gets its old value back, also when the render raises.

`view_renderer` makes the renderer that draws the target. It copies the background, the shading, the workers, the clipping planes, the shadow filter, the depth mode, the time and the area light tables. It has no tone mapping, because three.js tone maps no render target.

## Water

`Water` is three.js's ocean from `Water.js`: a mirror that a normal map ripples. The shader reads four moving copies of the normal map and bends the reflection with them. A sun adds a highlight, and a Fresnel term mixes the reflection with the water's color.

```mojo
var water = Water(assets, quad, node, normals, sun_direction=Vector3(0.7, 0.7, 0))
water.set_time(assets, Duration(1.5, SECOND))
_ = water.update(renderer, scene, assets, camera)
```

Set the wrap of the normal map to `REPEAT`, as three.js's example does. The options are three.js's: `alpha`, `time`, `sun_direction`, `sun_color`, `water_color`, `eye`, `distortion_scale`, `side` and `fog`. `update` sets the `eye` uniform to the camera's position, as three.js does. The target is a byte target, as in three.js.

## Flowing water

`Water2` is three.js's water from `Water2.js`. It holds a `Reflector` and a `Refractor` on its own node, and its shader mixes their two targets. Two normal maps move along a flow and bend the coordinates. A flow map gives the flow at each point. Without one, `flow_direction` holds everywhere.

```mojo
var water = Water2(assets, quad, node, normal_map0, normal_map1, scale=4)
water.update(renderer, scene, assets, camera, Duration(1.0 / 60, SECOND))
```

`update` takes the time since the last frame. three.js reads that time from a `Clock`. The two flow offsets add up in doubles, as JavaScript adds them. The constructor sets the wrap of both normal maps to `REPEAT`, as three.js sets it.

## Sky

`Sky` is Preetham's daylight model on a unit box seen from inside. Scale the box's node until it holds the scene. Set the sun with the `sunPosition` uniform.

```mojo
var sky = Sky(assets, node)
assets.programs.get(sky.program).set_uniform("sunPosition", Vector3(0, 0.1, -1))
assets.programs.get(sky.program).set_uniform("turbidity", Float32(10))
```

The uniforms start at three.js's defaults. The tests compare the colors of three views with three.js's shader, calculated again in doubles.

## Lens flare

A `Lensflare` stands at a node, usually the node of a light. Draw the scene into a target, then call `render` on the target. The flare finds where the node lands on the image, and how much of it the scene hides. It then adds its elements along the line from that point through the center of the image.

```mojo
var flare = Lensflare(assets, light_node)
flare.add_element(assets, LensflareElement(glow, size=700, distance=0))
flare.add_element(assets, LensflareElement(ring, size=60, distance=0.6))
renderer.render_into(target, scene, assets, camera)
_ = flare.render(renderer, target, scene, assets, camera)
var image = target.resolve()
```

three.js copies the sixteen by sixteen pixels around the light, and draws a magenta square there at the light's depth. It reads nine pixels of the copy: the mean red, times one minus the mean green, times the mean blue. This port runs the depth test at the same nine pixels. Where the test fails, it reads the pixel that the display shows. So a magenta object in front of the light does not hide it, as in three.js.

Each element is a square with a shader material, drawn with additive blending. An orthographic camera draws the squares in normalized device space. As in three.js, the elements lie at a device depth of zero, because three.js sets only `x` and `y` of their position.

## Marching cubes

`MarchingCubes` holds a cube of cells, each with a number. `update` finds the surface where the numbers pass `isolation`, and makes triangles by Paul Bourke's tables. The gradient of the field gives the normals.

```mojo
var cubes = MarchingCubes(28, enable_uvs=False, enable_colors=True)
cubes.reset()
cubes.add_ball(0.5, 0.5, 0.5, 0.6, 12)
cubes.add_plane_y(2, 12)
cubes.update()
var id = assets.geometries.add(cubes.geometry())
```

| Member | three.js |
|---|---|
| `add_ball(x, y, z, strength, subtract, color)` | `addBall` |
| `add_plane_x`, `add_plane_y`, `add_plane_z` | `addPlaneX`, `addPlaneY`, `addPlaneZ` |
| `set_cell`, `get_cell`, `blur`, `reset`, `update` | same names |
| `isolation`, `flat_shading`, `count` | `isolation`, `material.flatShading`, `count` |
| `geometry()`, `replace_geometry(assets, id)` | the geometry and its `needsUpdate` |

The arithmetic is three.js's, step by step, in doubles, and the field, the normals and the vertices are stored as floats. So each vertex, normal, color and coordinate is the float that three.js makes. The normals stay cached between updates, as in three.js. Call `reset` before you build a new field.

## Grounded skybox

`GroundedSkybox` is a sphere seen from inside, with its lower half pressed flat. The floor of the panorama then lies on the ground of the scene. Put the node at the height of the camera that took the panorama.

`grounded_skybox(height, radius, resolution)` returns the geometry, vertex for vertex as three.js builds it. The material is basic, with the map and no depth write.

## Shadow mesh

`ShadowMesh` draws the shadow of a mesh on a plane: the mesh flattened away from a light, in black at an opacity of 0.6. The stencil draws each pixel once, as in three.js. So overlapping faces do not darken the shadow twice.

```mojo
var shadow = ShadowMesh(assets, scene, caster)
scene.add_mesh(shadow.mesh)
scene.update()
shadow.update(scene, Plane(Vector3(0, 1, 0), 0.01), Vector4(5, 10, 2, 1))
scene.update()
```

`update` sets the shadow's node to three.js's shadow matrix times the world matrix of the caster. Give the light a `w` of one for a position, or zero for a direction. three.js's arithmetic negates the plane's constant. So the plane `(0, 1, 0), 0.01` puts the shadow at y = 0.01, a little above a ground at zero.

## Where this port differs

- **Updates are calls.** `update` and `render` replace three.js's `onBeforeRender`.
- **The cut is a clipping plane.** See [How the view is cut](#how-the-view-is-cut). `clip_bias` is a length.
- **The texture matrix uniform acts on world positions.** The GLSL subset refuses a varying that reads `position`. So the uniform stops at world space, and the vertex shader multiplies it by the world position. `texture_matrix` keeps three.js's value.
- **The shaders are in the GLSL subset.** `texture2DProj` is a division, and an overload has its own name. The two results of `sunLight` in `Water.js` come from two functions, because the subset has no `inout`. `getShadowMask()` is one, because the shader material is unlit.
- **The sky is not moved to the far plane.** three.js writes `gl_Position.z = gl_Position.w`. Keep the box inside the camera's far distance.
- **The sky's long constants are shorter.** Each has seventeen digits, more than a float holds. The GLSL compiler reads at most twenty digits.
- **A lens flare's color is light.** The resolve encodes it. three.js's raw shader writes it to the drawing buffer as it is. The flare reads a target of standard depth only.
- **A marching cubes surface that fills its buffer raises.** three.js writes past the end and warns. The geometry holds exactly the triangles made, and its bound is calculated.
- **A shadow draws a copy of its caster's geometry, without normals.** The renderer turns normals by the inverse of the world matrix, and a shadow matrix can have no inverse.
- **Refusals.** A size that is not positive, a number that is not finite, and a texture id that is not in the stores are refused. A grounded skybox needs two rings at least.

## What is not ported

- Multisampled targets: three.js's `multisample` option.
- `ReflectorForSSRPass`, and the node versions for WebGPU: `SkyMesh`, `WaterMesh`, `Water2Mesh` and `LensflareMesh`.
- The textures that `Water2` loads by default. Pass the two normal maps.
