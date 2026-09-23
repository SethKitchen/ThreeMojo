# Lines

`objects/line.mojo`, `render/linerule.mojo` and the line pass in both rasterizers. A line joins points with one-pixel strokes. It is the second kind of primitive the renderer draws, beside the triangle. A line wider than one pixel is a [wide line](#wide-lines), drawn as triangles.

![A gold loop and a white path turn with a box](out/lines.png)

three.js: `Line`, `LineLoop`, `LineSegments`, `LineBasicMaterial`, `LineDashedMaterial`, `computeLineDistances`.

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
| `line_distances(mode, positions)` | How far along the line each point is, for the dashes. |

`segment_ends` is the whole of the difference between the three modes. Everything that draws a line walks `segment_count` and asks `segment_ends`, so all three modes share one path through the renderer.

A surface can be read back as lines: see [edges and wireframes](Geometry#edges-and-wireframes). A material can ask for its own surface to be drawn that way: see [wireframe](Materials#wireframe).

## What a line is made of

A line geometry carries its points in order, in the `position` attribute. It carries no index buffer.

`BufferGeometry.set_index` demands whole triangles, because an index buffer here is a triangle index. It cannot say which two points a segment joins. `Renderer.prepare_lines` refuses an indexed geometry rather than reading a triangle list as a line list. three.js produces the same shape: `EdgesGeometry` and `WireframeGeometry` both build a plain array of point pairs.

## What a line is drawn with

A `BASIC` material, three.js's `LineBasicMaterial`.

A line has no surface. It has no normal, and every lighting term needs one. It has no surface coordinates either, so there is nothing to sample a map with. `prepare_lines` refuses a lit kind, a map and an alpha map. It refuses them rather than carrying them and drawing neither.

The color, the opacity, the blending and the geometry's vertex colors all work as they do on a mesh. So does the [fog](Fog): a line that recedes is veiled like anything else.

## Dashed lines

`line_dashed_material` draws a line in dashes, three.js's `LineDashedMaterial`. A dash is a length along the line, and so is the gap after it.

```mojo
from materials.material import line_dashed_material

var dashed = assets.materials.add(
    line_dashed_material(
        Color(240, 240, 255),
        dash_size=Length(0.2, METER),
        gap_size=Length(0.1, METER),
    )
)
```

| Argument | three.js | Default | Meaning |
|---|---|---|---|
| `dash_size` | `dashSize` | `3` | How long each dash is, along the line. |
| `gap_size` | `gapSize` | `1` | How long the gap after it is. Zero is a solid line. |
| `scale` | `scale` | `1` | What the distance along the line is multiplied by first. |

The defaults are three.js's own. They are large for a scene measured in meters: three.js draws a dash of three units and a gap of one. Pass a dash and a gap that suit the line.

### What a dash measures

The distance along the line, from its first point, in the geometry's own space. three.js keeps that distance in a `lineDistance` attribute, and `computeLineDistances` fills it in. A dashed line whose author forgot to call it is drawn solid. Here `line_distances` works the distance out from the points, and `prepare_lines` calls it for every dashed line. Nothing has to be called first.

The arithmetic is three.js's. A `STRIP` accumulates from its first point. `SEGMENTS` accumulate across the sticks too, as `LineSegments.computeLineDistances` does, so the pattern runs on from one stick to the next. A `LOOP` accumulates as a strip does. Its closing segment runs from the last point's distance back to zero, so the pattern along that one segment runs backward. That is what three.js draws.

The distance is measured before the node's transform. A node scaled by two draws dashes twice as long, as in three.js. Set `scale` to change the pattern without changing the geometry.

The distance is a varying. It is interpolated with perspective correction, as the color is, so a dash that recedes shortens on the screen as the line does. A segment cut at the near plane keeps its dashes where they were.

### The rule

A pixel is in a dash when the distance folded into one period lands at or before the dash's end. The fold is GLSL's `mod`, so a distance below zero still lands inside the period. `dash_covers` in `render/linerule.mojo` is that rule, and both rasterizers ask it. See [Shared CPU and GPU code](Why-the-CPU-and-GPU-share-code).

A pixel in a gap is thrown away before the depth test, as three.js's `discard` throws it away. A gap claims no depth, so what is behind it shows through, whether the line blends or not.

### Where dashes are refused

Only a `BASIC` material can be dashed, because only a line has a length to measure along. A dashed material on a mesh is refused when it is built. A [wireframe](Materials#wireframe) cannot be dashed either: its edges are paired from a surface and carry no distance along them. A gap with no dash before it would draw nothing, and is refused too.

## The rule

A line is walked along whichever axis it covers more of. That is its major axis. It lights exactly one pixel in each row or column of that axis.

That is the oldest rasterization rule there is, and it is what "a width of one pixel" means: no thickness, no coverage, no anti-aliasing. A diagonal line is a staircase.

A line lights the pixel each of its ends lands in, both ends included. So a line cut at the edge of a [viewport](Renderer#viewport-and-scissor) lights one pixel past that edge. A scissor keeps it out.

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

three.js is the same. WebGL ignores `linewidth`, which is why three.js ships `Line2` as geometry rather than as a line. A thicker line here is a [wide line](#wide-lines): quads, and quads are triangles, which `render/fillrule.mojo` already covers.

## Two lists, one order

Lines are prepared by their own pass into their own list.

```mojo
var corners = renderer.prepare(scene, assets, camera)
var segments = renderer.prepare_lines(scene, assets, camera)
var frame = renderer.prepare_frame(scene, assets, camera)
```

`prepare_lines` is `prepare` for lines, and it is the same boundary: screen-space primitives with their varyings worked out. `prepare_frame` makes both lists and one order over them: a list of `Draw` records, each a run of triangles or a run of segments. `Renderer.render` fills a frame with `rasterize_frame`. `GpuRenderer.draw` takes the same three lists and walks the same order in one launch.

The order is the one every renderer uses. Opaque runs come first, triangles then segments, nearest first. Blended runs follow, triangles and segments together, furthest first, by the depth of each draw's own placed origin. A blended line is drawn after the blended surface behind it and before the one in front of it. See [Sorted transparency](Why-transparency-is-sorted).

An opaque line behind a translucent pane stays behind it. Drawing every line after every triangle put that line on top: the pane had blended without claiming the depth, and the line passed the test.

A line tests the depth of what was drawn before it. An opaque line in front of a surface is drawn over it. A line behind an opaque surface is hidden by it. A blended line tests the depth and does not claim it, as a blended surface does not.

`prepare_lines` returns its list in that order too: opaque lines and wireframes nearest first, then the blended ones furthest first. A wireframe is sorted among the lines by its own depth.

A line whose node shares no layer with the camera contributes nothing. Nor does one whose bounding sphere lies outside the camera's frustum, unless it opted out with `frustum_culled=False`.

## Clipping

`renderers/clip.mojo` cuts a segment against the near and far planes with `clip_segment`.

Cutting a segment leaves a segment or nothing at all. There is no polygon to fan, which is the one way it is simpler than `clip_depth`. Both ends move by the same arithmetic the triangle clipper uses. A mesh edge and a line lying on it are cut at the same place.

## Wide lines

A `LineSegments2` draws its segments wider than one pixel. `Line2` is the same object with a path for a geometry. Each segment becomes a quad of two triangles, with a round cap at each end. Both rasterizers fill them by the triangle rule.

three.js: `LineSegments2`, `Line2`, `LineSegmentsGeometry`, `LineGeometry`, `LineMaterial`, from `examples/jsm/lines`.

```mojo
from materials.material import LineWidth, line_material
from objects.line_segments2 import Line2, LineSegments2, line_geometry

var path = assets.geometries.add(line_geometry(points, colors))
var ink = assets.materials.add(
    line_material(Color(255, 255, 255), LineWidth(pixels=5), vertex_colors=True)
)
scene.add_wide_line(Line2(path, ink, node))
```

| Member | three.js | Meaning |
|---|---|---|
| `LineSegments2(geometry, material, node)` | `LineSegments2` | Separate wide sticks at a scene node. |
| `Line2(geometry, material, node)` | `Line2` | Another name for `LineSegments2`. |
| `line_segments_geometry(points, colors)` | `LineSegmentsGeometry` | A geometry of sticks, two points each. |
| `line_geometry(points, colors)` | `LineGeometry` | A geometry of one path. Each inner point is written twice. |
| `scene.add_wide_line(line)` | `scene.add` | Adds a wide line to draw. |
| `line_material(...)` | `LineMaterial` | An unlit material with a width and dashes. |

### The geometry

A wide-line geometry holds its points in pairs, one pair per segment. That is the layout `SEGMENTS` reads. three.js keeps the same pairs in `instanceStart` and `instanceEnd`. An edges or a wireframe geometry is therefore a wide-line geometry already.

A `color` attribute of three floats per point gives the vertex colors. The colors are linear, as a mesh's are.

### The width

`LineWidth` says how wide the line is, and in which units. It is three.js's `linewidth` and `worldUnits` together.

| Width | three.js | Meaning |
|---|---|---|
| `LineWidth(pixels=5)` | `linewidth = 5` | Five output pixels on the image, at any distance. |
| `LineWidth(world=Length(0.1, METER))` | `worldUnits = true` | A tenth of a meter in the scene. It shrinks with distance. |

A bare float does not compile. The default is one pixel, as in three.js.

A width in pixels is in output pixels. With [anti-aliasing](Renderer#anti-aliasing) on, the renderer multiplies it by its render scale. three.js reads the viewport size from `LineMaterial.resolution`. Here the renderer supplies it, so there is nothing to set.

### The material

| Argument | three.js | Default | Meaning |
|---|---|---|---|
| `color` | `color` | white | The color, in sRGB. |
| `line_width` | `linewidth`, `worldUnits` | one pixel | How wide the line is. |
| `dash_size` | `dashSize` | none | How long each dash is. |
| `gap_size` | `gapSize` | none | How long each gap is. A gap above zero turns the dashes on. |
| `dash_scale` | `dashScale` | `1` | What the distance along the line is multiplied by first. |
| `dash_offset` | `dashOffset` | none | How far the pattern slides along the line, after the scale. |
| `vertex_colors` | `vertexColors` | off | Whether the `color` attribute tints the line. |

three.js turns the dashes on with a `dashed` flag. Here a gap above zero turns them on, as it does for `line_dashed_material`.

### How a segment becomes triangles

`Renderer.prepare` builds the triangles, as three.js's `LineMaterial` vertex shader builds them.

1. The segment is cut to the near and far planes.
2. For a width in pixels, each corner is its end moved on the image, then carried back into camera space at the end's own depth. three.js moves the clip-space corner by an offset times `w`, which is the same move.
3. For a width in the world, each corner is its end moved in camera space. It moves across the segment and square to the direction of the segment's middle, three.js's `worldUp`.
4. A round cap is added at each end, as a fan of triangles.
5. The triangles go through the clipper and are sorted among the meshes by the depth of the line's node.

Two segments that share an end overlap in their caps. That overlap is the round join, as in three.js. A blended line is therefore twice as opaque where two caps overlap, as in three.js.

### Dashes

A dashed segment is cut into one quad per dash. A dashed line has no caps, because three.js throws the caps of a dashed line away.

The distance along the line is worked out by the renderer, as for a [dashed line](#dashed-lines). three.js calls this `LineSegments2.computeLineDistances`. The pattern runs on from one segment to the next.

### Picking

`Raycaster.intersect_wide_line` is three.js's `LineSegments2.raycast`. It takes the camera and the image size, which three.js reads from `raycaster.camera` and `material.resolution`. See [Raycasting](Raycasting).

A width in the world is measured in the world. A width in pixels is measured on the image, from the point one meter along the ray. A hit's `triangle` says which segment was struck.

### What is not ported, and what differs

- **The caps are fans, not discs.** three.js cuts a half disc out of a square for each fragment. Here the cap is a fan of triangles within an eighth of a pixel of the circle. `cap_steps` sets the count.
- **The dashes are cut, not discarded.** three.js discards each fragment in a gap. Here the segment is cut at the dash boundaries, so both rasterizers need no rule of their own. A segment cut into more than 4096 dashes raises.
- **A width in the world is a flat ribbon.** three.js traces a capsule for each fragment. Here the ribbon faces the camera, and its outline matches the capsule's outline. Where the ribbon passes through another surface, the two cross along a different curve.
- **A segment with no length is a round dot.** three.js normalizes a zero vector there, and GLSL leaves the result undefined.
- **A hit outside `near` and `far` is dropped.** three.js's `LineSegments2.raycast` keeps it. A mesh hit is dropped in both.
- **Not ported:** `alphaToCoverage`, the raycaster's `params.Line2.threshold`, a hit's `pointOnLine`, `LineMaterial.resolution`, and a `Line2` that casts or receives a shadow.
- **`intersect_scene` does not pick a wide line.** It has no camera for a width in pixels.

### What raises

- A material that is not `BASIC`, or carries a map, an alpha map or an env map, or is a wireframe.
- A geometry with an index buffer, no positions or an odd count of points.
- A material that asks for vertex colors when the geometry has no `color` attribute.
- A width that is not a positive number, or a dash offset that is not finite.
- A width or a dash offset on a material that is not `BASIC`, or on a wireframe.
- A width or a dash offset on a one-pixel `Line`. Draw a wider line as a `LineSegments2`.

## What raises

- A line naming a node, a geometry or a material that is not there.
- A geometry with no positions, or with an index buffer.
- A point count that does not suit the mode: an odd count under `SEGMENTS`.
- A material that is not `BASIC`, or that carries a map or an alpha map.
- A segment whose two ends disagree about the dashes, or whose dash or gap is negative, at the rasterizer boundary.
- A material asking for vertex colors when the geometry has no `color` attribute.
- A segment whose two ends disagree about blending, at the rasterizer boundary.

## Limits

A line is not morphed and not skinned. three.js allows both. Neither has a caller here yet, and adding one is a matter of routing `core/deform.mojo` the way `prepare` routes it.
