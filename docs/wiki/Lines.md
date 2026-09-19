# Lines

`objects/line.mojo`, `render/linerule.mojo` and the line pass in both rasterizers. A line joins points with one-pixel strokes. It is the second kind of primitive the renderer draws, beside the triangle.

![A gold loop and a white path turn with a box](out/lines.png)

three.js: `Line`, `LineLoop`, `LineSegments`, `LineBasicMaterial`.

## Three objects, one mode

three.js has three classes here and one class body. They differ only in how the points are paired. Here they are one `Line` and a `LineMode`.

| Mode | three.js | Segments from n points |
|---|---|---|
| `STRIP` | `Line` | n - 1, each point to the next |
| `LOOP` | `LineLoop` | n, the last joined back to the first |
| `SEGMENTS` | `LineSegments` | n / 2, points read two at a time |

```mojo
from objects.line import Line, LOOP, SEGMENTS

var path = Line(geometry, material, node)              # a strip
var ring = Line(geometry, material, node, mode=LOOP)   # closed
var sticks = Line(geometry, material, node, mode=SEGMENTS)
scene.add_line(path)
```

| Member | Meaning |
|---|---|
| `Line(geometry, material, node)` | A line at a scene node. |
| `line.mode` | How its points are paired. |
| `line.frustum_culled` | Whether the renderer can skip it when out of view. |
| `line.segment_count(vertices)` | How many segments it makes. |
| `segment_count(mode, vertices)` | The same, without a line. |
| `segment_ends(mode, vertices, segment)` | Which two points one segment joins. |

`segment_ends` is the whole of the difference between the three modes. Everything that draws a line walks `segment_count` and asks `segment_ends`, so all three modes share one path through the renderer.

A surface can be read back as lines: see [edges and wireframes](Geometry#edges-and-wireframes).

## What a line is made of

A line geometry carries its points in order, in the `position` attribute. It carries no index buffer.

`BufferGeometry.set_index` demands whole triangles, because an index buffer here is a triangle index. It cannot say which two points a segment joins. `Renderer.prepare_lines` refuses an indexed geometry rather than reading a triangle list as a line list. three.js produces the same shape: `EdgesGeometry` and `WireframeGeometry` both build a plain array of point pairs.

## What a line is drawn with

A `BASIC` material, three.js's `LineBasicMaterial`.

A line has no surface. It has no normal, and every lighting term needs one. It has no surface coordinates either, so there is nothing to sample a map with. `prepare_lines` refuses a lit kind, a map and an alpha map. It refuses them rather than carrying them and drawing neither.

The color, the opacity, the blending and the geometry's vertex colors all work as they do on a mesh. So does the [fog](Fog): a line that recedes is veiled like anything else.

## The rule

A line is walked along whichever axis it covers more of. That is its major axis. It lights exactly one pixel in each row or column of that axis.

That is the oldest rasterization rule there is, and it is what "a width of one pixel" means: no thickness, no coverage, no anti-aliasing. A diagonal line is a staircase.

`render/linerule.mojo` holds it. `other_at` is the whole rule. Give it a line and one coordinate along the major axis. It says which pixel on the minor axis the line lights there.

| Function | Answer |
|---|---|
| `major_is_x(a, b)` | Whether the line covers more columns than rows. |
| `span_of(a, b)` | How many pixels it lights. |
| `major_at(a, b, step)` | The major-axis pixel one step along. |
| `share_at(a, b, major)` | How far along the line one major-axis pixel is. |
| `other_at(a, b, major)` | The minor-axis pixel it lights there. |
| `covers(a, b, x, y)` | Whether it lights one pixel. |

The CPU walks the major axis and asks `other_at` for the minor one. The kernel asks `covers` whether this pixel is the one. The two loops are shaped differently and cannot disagree, because both get the answer from one expression. See [Shared CPU and GPU code](Why-the-CPU-and-GPU-share-code).

### Why not a distance from the line

A distance test is the natural way to ask "is this pixel on the line" per pixel. It is also a different rule. It lights two pixels in a column wherever the line passes near a boundary, and the walk lights one. Reconciling the two is more arithmetic than the rule it protects.

### Why one pixel only

three.js is the same. WebGL ignores `linewidth`, which is why three.js ships `Line2` as geometry rather than as a line. When thickness arrives here it will be quads, and quads are triangles, which `render/fillrule.mojo` already covers.

## The two passes

Lines are prepared by their own pass and drawn by their own pass.

```mojo
var corners = renderer.prepare(scene, assets, camera)
var segments = renderer.prepare_lines(scene, assets, camera)
```

`prepare_lines` is `prepare` for lines, and it is the same boundary: screen-space primitives with their varyings worked out. `Renderer.render` fills the triangles and then the segments. `GpuRenderer.draw` takes both lists and does both passes in one launch.

The lines go second, and they test the triangles' depth. A line in front of a surface is drawn over it. A line behind one is hidden by it.

Opaque lines are prepared first, nearest first, then the blended ones furthest first. That is the order `prepare` puts the triangles in, and for the same reasons. See [Sorted transparency](Why-transparency-is-sorted).

A line whose node shares no layer with the camera contributes nothing. Nor does one whose bounding sphere lies outside the camera's frustum, unless it opted out with `frustum_culled=False`.

## Clipping

`renderers/clip.mojo` cuts a segment against the near and far planes with `clip_segment`.

Cutting a segment leaves a segment or nothing at all. There is no polygon to fan, which is the one way it is simpler than `clip_depth`. Both ends move by the same arithmetic the triangle clipper uses. A mesh edge and a line lying on it are cut at the same place.

## What raises

- A line naming a node, a geometry or a material that is not there.
- A geometry with no positions, or with an index buffer.
- A point count that does not suit the mode: an odd count under `SEGMENTS`.
- A material that is not `BASIC`, or that carries a map or an alpha map.
- A material asking for vertex colors when the geometry has no `color` attribute.
- A segment whose two ends disagree about blending, at the rasterizer boundary.

## Limits

A line is not morphed and not skinned. three.js allows both. Neither has a caller here yet, and adding one is a matter of routing `core/deform.mojo` the way `prepare` routes it.
