# Sculptor

`geometries/sculptor.mojo` sculpts a mesh with brush strokes. It is three.js's `Sculptor` from `examples/jsm/misc/`, with its helpers `SculptorMesh`, `SculptorTools` and `SculptorUtils`. three.js adapts all four from SculptGL by Stéphane Ginier.

![A brush raises a knob on a sphere, and the sphere turns](out/sculptor.png)

`examples/clay.mojo` draws this picture.

```mojo
var sculptor = Sculptor(scene, assets, 0)
sculptor.set_tool(SCULPT_INFLATE)
var ray = Ray(Vector3(0.2, 0.1, 3), Vector3(0, 0, -1))
_ = sculptor.stroke_from_ray(scene, assets, ray, Length(0.5, METER))
sculptor.end_stroke()
```

## Make a sculptor

`Sculptor(scene, assets, mesh)` takes the mesh at place `mesh` in `scene.meshes`. It welds the mesh's geometry and adds a new geometry to `assets`. The new geometry has `position`, `normal` and an index. The mesh then draws the new geometry. The source geometry does not change.

Welding joins two positions nearer than a ten-millionth of the geometry's largest extent. A triangle that welding makes degenerate is an error. A triangle with no area in `Float32` is an error too.

The constructor raises for a mesh that is not in the scene, and for a mesh with more than one material. Skinned, instanced and batched meshes are in other lists of the scene, so the sculptor cannot take them.

## Stroke with a ray

`stroke_from_ray(scene, assets, ray, world_radius)` stamps the tool once where the ray meets the mesh. The first stamp begins a stroke. Call `end_stroke` after the last stamp. `pick_from_ray` finds the hit and does not sculpt.

A stroke works in the mesh's own space. The mesh's world matrix must be finite and scale by the same amount on each axis, without shear. Each stored axis length must be greater than `MIN_WORLD_SCALE`: `2^-26`, or `1.4901161193847656e-8`. The boundary itself is refused.

Rotation and translation are allowed, including through a parent. The limit applies to the final world matrix, after parent transforms. The scale and shear checks allow for rounding in the stored `Float32` matrix. The minimum does not use that rounding allowance.

### Minimum world scale

The minimum is a conservative supported limit. It keeps world-to-local amplification below `2^26` for a uniform affine matrix. It is not a storage epsilon or the smallest scale that `Float64` can invert. Smaller positive scales can be representable and still be outside this contract. This documents the existing rejection boundary; it does not extend the supported range.

The inverse, ray normalization and radius calculations use `Float64`. For a uniform affine matrix within the allowed rounding, inverse linear entries stay below `2^27` in magnitude. Its inverse translation stays below `2^157`.

Finite `Float32` ray inputs then transform to components below `2^158`. The same bound applies to finite `Float32` points returned by camera unprojection. Squared direction lengths and differences between those transformed points stay below `2^320`. This leaves ample space inside the finite `Float64` range, which extends to nearly `2^1024`.

The pointer brush divides its squared world radius by the squared scale. The limit bounds that amplification below `2^52`. Camera projection and unprojection must still produce usable points. A scale above the limit does not guarantee a hit, a usable camera or an accurate local offset. A large translation or distant ray can erase small local offsets through rounding.

A ray brush has a separate limit: `world_radius / world_scale` must not exceed the largest finite `Float32`, about `3.402823466e38`. Its square is stored in `Float64`. A small accepted scale can still refuse an oversized brush.

`world_radius` is a `Length` in world units. It must be positive and finite. The ray must have a finite origin and a direction that is not zero.

## Stroke with a pointer

`connect(left, top, width, height)` gives the view in pixels. Then pass each pointer event with the camera:

```mojo
sculptor.connect(0, 0, 800, 600)
sculptor.pointer_down(camera, scene, 400, 300)
sculptor.pointer_move(camera, scene, assets, 420, 310)
sculptor.pointer_up()
```

The pointer's ray starts on the near plane. The brush radius is `size` pixels at the hit, carried back to world units. A move stamps each `0.15 * size` pixels along the path. Only the primary button of the primary pointer begins a stroke, and only that pointer continues it.

`pick_from_pointer(camera, scene, x, y)` finds the hit under a pixel and does not sculpt. `disconnect` ends the stroke and forgets the view.

## The tools

`set_tool` selects the tool. Each tool keeps its own size, strength and direction, so `set_tool` restores them.

| Tool | Size | Strength | Negative | What it does |
|---|---|---|---|---|
| `SCULPT_CLAY` | 50 | 0.5 | no | Moves the surface toward a plane a tenth of the radius above it |
| `SCULPT_BRUSH` | 50 | 0.5 | no | Moves along the normal at the hit, a tenth of the radius at full strength |
| `SCULPT_INFLATE` | 50 | 0.3 | no | Moves each vertex along its own normal |
| `SCULPT_SMOOTH` | 50 | 0.75 | no | Moves each vertex toward the mean of its neighbors |
| `SCULPT_FLATTEN` | 50 | 0.75 | yes | Moves the surface toward the plane of the brush |
| `SCULPT_PINCH` | 50 | 0.75 | no | Moves the vertices toward the center |
| `SCULPT_CREASE` | 25 | 0.75 | yes | Pinches, and pushes the center along the normal |
| `SCULPT_DRAG` | 150 | 0.5 | no | Moves the surface with the pointer |
| `SCULPT_SCALE` | 50 | 0.5 | no | Moves the surface out as the pointer moves right |

The weight of each move is `3d^4 - 4d^3 + 1`, where `d` is the distance from the center as a share of the radius. `set_negative(True)` turns a tool around. The drag and scale tools need a pointer. `stroke_from_ray` raises for them.

## Adaptive topology

`set_detail` sets how fine the mesh gets under the brush, from 0 to 1. The default is 0.75. Before each stamp, the sculptor splits each edge in the brush whose squared length is more than `radius^2 * (1.1 - detail) * 0.2`. It then collapses each edge whose squared length is less than that limit divided by `2.05^2`. A detail of 0 keeps the vertices and faces as they are.

A split puts a new vertex at the middle of the edge. The vertex bulges along the mean normal, by how far the two normals turn. A collapse moves the joined vertex to the mean of its neighbors, in its tangent plane. Where the two ends of an edge share a third neighbor, the edge flips.

A strength of 0 stops the tool, but not the adaptive topology.

## Events

`events` lists what happened, oldest first. Read the list and clear it as you need.

| Event | When |
|---|---|
| `SCULPT_START` | A stroke begins. |
| `SCULPT_CHANGE` | A stamp wrote a changed geometry. |
| `SCULPT_END` | A stroke ends. |

## Settings and state

| Method | Range | Meaning |
|---|---|---|
| `set_size` | 5 to 500 | The pointer brush radius, in pixels |
| `set_strength` | 0 to 1 | How far the tool moves the surface |
| `set_negative` | | Whether the tool works the other way |
| `set_detail` | 0 to 1 | How fine the adaptive topology gets |
| `enabled` | | Whether pointer events sculpt |

Each setter raises for a value outside its range. `has_hit`, `get_hit_point` and `get_hit_normal` give the last hit, in the mesh's space. `get_world_radius` gives the brush radius as a `Length`. `get_geometry(assets)` returns a copy of the vertices and triangles.

## Where this port differs

- three.js dispatches events. Here they are appended to `events`.
- three.js listens to a DOM element and captures the pointer. Here the caller passes each pointer event.
- three.js keeps spare room in the geometry's buffers and uploads only the changed ranges. Here each stamp writes the attributes and the index at their exact length.
- three.js grows the geometry's bounding box and sphere during a stroke. Here `BufferGeometry` computes its bounds when asked.
- three.js unprojects a pointer in doubles. Here `unproject_point` works in `Float32`, so a pointer stroke agrees with three.js to about 1e-4.
- An octree cell is an index into a list, not an object.

## What is not ported

- This port refuses world axis lengths at or below `2^-26`. See [Minimum world scale](#minimum-world-scale). The limit is independent of the scale and shear rounding checks.
- three.js falls back to a scaled ray test when a product overflows. A ray here always has a unit direction and finite `Float32` corners, so no product overflows, and the fallback is not ported.
- three.js keys a split edge by a string when the key overflows a double. The key here is an `Int`, which does not overflow for any mesh a list can hold.
- The pointer takes no `reversedDepth` camera and no WebGPU depth range, because the cameras here have neither.

## Tests

`tests/test_sculptor.mojo` compares each tool with three.js r186, run in Node on the same meshes and strokes. It checks the vertex and triangle counts, a checksum of every triangle, the sums of the positions and the normals, the hit, and one vertex.
