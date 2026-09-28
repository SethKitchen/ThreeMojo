# Lofts, clipping groups and other leftovers

This page lists seven small parts of three.js that have no other page. The first two are geometries: a loft and a wide wireframe. Then come a clipping group, an animation path helper, a color from a temperature, an animation loader and a cube depth texture.

![A lofted vase turns under a lamp](out/lofts.png)

`examples/vase.mojo` draws this picture.

## Loft geometry

`geometries/loft.mojo` skins a surface through a list of cross sections. It is three.js's `LoftGeometry` from `examples/jsm/geometries/`.

```mojo
var sections = List[List[Vector3]]()
for step in range(11):
    var radius = Float32(2 + sin(Float64(step) * 0.8))
    var ring = List[Vector3]()
    for point in range(32):
        var angle = Float32(point) / 32 * 2 * Float32(pi)
        ring.append(Vector3(sin(angle) * radius, Float32(step), cos(angle) * radius))
    sections.append(ring^)
var geometry = loft(sections, cap_start=True, cap_end=True)
```

- Each section is a list of points in meters. All sections must have the same number of points.
- `closed=True`, the default, treats each section as a ring. `closed=False` treats it as an open strip.
- `cap_start` and `cap_end` close the first and the last section with a flat face.
- The texture coordinates follow the distance between points. `u` runs along the loft and `v` runs around each section.
- The two copies of the first point of a closed section get the mean of their normals. The seam shades smoothly.

The faces point outward when each section runs counterclockwise, seen from the last section toward the first. If the surface is inside out, reverse the points of each section.

`loft` raises for fewer than two sections, a section of fewer than two points, sections of different sizes, or a point that is not finite.

## Wide wireframe

`objects/wireframe_geometry2.mojo` gives every edge of a surface as a wide-line geometry. It is three.js's `WireframeGeometry2` from `examples/jsm/lines/`.

```mojo
var edges = assets.geometries.add(wireframe_geometry2(geometry))
scene.add_wide_line(LineSegments2(edges, assets.materials.add(line_material(color, LineWidth(pixels=3))), node))
```

The edges are the ones `wireframe_geometry` finds. A `LineSegments2` draws them, as three.js's `Wireframe` draws them. See [Lines](Lines).

## Clipping groups

`objects/clipping_group.mojo` gives a node clipping planes. The renderer cuts everything that is drawn at that node and below it. It is three.js's `ClippingGroup`.

```mojo
var holder = scene.add(group())
scene.add_clipping_group(ClippingGroup(holder, [Plane(Vector3(1, 0, 0), 0)]))
var child = scene.attach(Object3D(), holder)
scene.add_mesh(Mesh(geometry, material, child))
```

A `ClippingGroup` has these fields:

| Field | three.js | Default | What it does |
|---|---|---|---|
| `node` | the group | none | The node that holds the planes |
| `clipping_planes` | `clippingPlanes` | none | The planes, in world space |
| `enabled` | `enabled` | `True` | Whether the planes cut |
| `clip_intersection` | `clipIntersection` | `False` | Keep a point in front of one plane, not all of them |
| `clip_shadows` | `clipShadows` | `False` | Also cut the shadow maps |

A node can hold one clipping group. `Scene.add_clipping_group` raises for a second group, or for a node that is not in the scene.

### How groups add up

`Scene.clipping(node, shadow_pass)` collects the planes of the groups at a node and above it. It is three.js's `ClippingContext`. The outer group comes first.

- A group under the union rule adds its planes to `union_planes`. A kept point must be in front of each of them.
- A group under `clip_intersection` adds its planes to `intersection_planes`. A kept point must be in front of one of them.
- A disabled group adds nothing.
- In a shadow pass, a group adds its planes only when `clip_shadows` is on.

A group does not need `Renderer.local_clipping_enabled`, as in three.js. The renderer's own `clipping_planes` and the material's planes still cut too.

### Both backends

The renderer cuts the triangles, lines, points, sprites and wide lines on the host, before it rasterizes them. The cut uses `renderers/clip.mojo`, the same code that cuts for the other clipping planes. So the CPU and the GPU rasterizers get the same triangles. `tests/test_gpu.mojo` checks that both backends draw a cube under two nested groups alike.

## Animation path helper

`helpers/animation_path.mojo` draws the path an animated node moves along. It is three.js's `AnimationPathHelper` from `examples/jsm/helpers/`.

```mojo
var helper = add_animation_path_helper(scene, assets, clip, node)
```

- The line follows the node's position track. It is sampled `divisions + 1` times from the start of the clip to its end. The default is 100 divisions.
- A point marks the value of each key. Set `show_markers=False` to leave the points out.
- The line is green and the points are red, five pixels across at any distance. Neither is tone mapped.
- The helper's node is under the node's parent, so the path is in the parent's space.

`animation_path` and `animation_path_markers` return the two geometries alone. `position_track` finds the track. It is the first track that drives the node's `POSITION`. The functions raise if the clip has no such track.

## Color from a temperature

`render/color_utils.mojo` gives the color of a light at a color temperature. It is three.js's `ColorUtils.setKelvin`, with Tanner Helland's fit.

```mojo
var candle = kelvin_color(Temperature(1900, KELVIN))
set_kelvin(light_color, Temperature(6500, KELVIN))
```

The temperature is clamped to 1000 K to 40000 K. The color is in linear light, as three.js keeps it. `set_kelvin` keeps the alpha. Both functions raise for a temperature that is not a number.

A `Temperature` is in `units/temperature.mojo`. It is not a `Quantity`, because a Celsius reading has a different zero. Read it on either scale with `to(KELVIN)` or `to(CELSIUS)`.

## Animation loader

`loaders/animation_loader.mojo` reads a JSON array of clips. It is three.js's `AnimationLoader`.

```mojo
var clips = read_animations("walk.json", scene, root)
```

Each clip is in the form that `AnimationClip.toJSON` writes. The loader finds the target of each track below `root`, as three.js's `PropertyBinding.findNode` does:

- An empty node name, `.`, or the root's own name is the root.
- Any other name is the first node below the root with that name.
- `.bones[name]` is the first node below that node with the bone's name.
- `.material` and `.map` are the material of the first mesh at the node.
- `.morphTargetInfluences[i]` is a morph target of the first mesh at the node, by index or by name.
- A light property is the first light at the node.

`track_target(scene, root, name)` finds one target. `parse_animations(text, scene, root)` reads text that is already in memory.

## Cube depth texture

`render/cube_depth_texture.mojo` keeps the depth of six square renders as one cube. It is three.js's `CubeDepthTexture`.

```mojo
var faces = List[Framebuffer]()
for face in range(6):
    faces.append(renderer.render(scene, assets, cube_camera.face_camera(face, scene)))
var depth = cube_depth_texture_of(faces)
var seen = depth.sample(Vector3(1, 0, 0)).r
```

Each face holds the window depth: zero at the near plane and one at the far plane. A texel is read nearest, as three.js's `NearestFilter` reads it. `cube_depth_texture(size, depths, mode)` builds the cube from six depth buffers in one list.

## What is not ported

- A loft is a `BufferGeometry` with no `GeometryType` of its own. Scene JSON does not write its sections.
- Scene JSON does not write or read a clipping group.
- The animation loader leaves out a track that finds no target. A clip with no track left is left out too. three.js keeps both and binds the track to nothing.
- The animation loader does not bind a track to a camera, to `.material[i]`, to `.materials`, or to the morph targets of a `SkinnedMesh`.
- The animation path helper does not have `setColor` and `setMarkerColor`. Change the materials in the assets instead.
- A cube depth texture holds eight bits a texel, as `depth_texture_of` does. three.js's holds a depth format.
