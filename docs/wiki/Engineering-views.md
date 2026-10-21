# Engineering views

`extensions/visual/` draws engineering results. `MeshBuilder` builds walls, pipes and ground as one geometry. `Overlay` draws text, labels, leader lines, arrows and color bars on a rendered frame. The textures give formed concrete, soil and riprap. [Retaining walls](Retaining-walls) gives the analysis that these views show.

## Modules

| Module | What it gives |
|---|---|
| `mesh` | `MeshBuilder`: `triangle`, `smooth_triangle`, `quad`, `oriented`, `prism`, `loft`, `plate`, `tube`, `heightfield` and `geometry` |
| `overlay` | `Overlay` with `text`, `text_width` and `label`, and `fill_polygons`, `fill_rect`, `stroke_line`, `fill_disc` and `arrow` |
| `textures` | `formed_concrete_maps`, `soil_maps` and `riprap_maps` |

## Build a mesh

`MeshBuilder` takes points in a z-up frame in meters: x east, y north, z up. It turns them into the y-up frame that three.js draws in. Texture coordinates are world meters, projected along the axis that the face is most nearly normal to. A texture that repeats every n meters has the same scale on every face.

- `prism` extrudes a section polygon along a straight run.
- `loft` sweeps a section between two placements. Use it for a mitered corner or a sloping top.
- `plate` makes a flat slab with holes through it, for example a headwall with pipe openings.
- `tube` makes a round pipe barrel, solid or hollow.
- `heightfield` makes a smooth surface over a grid of heights.

```mojo
var mb = MeshBuilder()
mb.prism([(0.0, 0.0), (3.0, 0.0), (3.0, 0.5), (0.0, 0.5)], Vec3d(0, 0, 0), Vec3d(0, 5, 0), Vec3d(1, 0, 0), Vec3d(1, 1, 1))
var geometry = mb.geometry()
```

## Annotate a frame

`Overlay.from_ttf` loads a TrueType font. `text` draws one line at a baseline, anchored `LEFT`, `CENTER` or `RIGHT`. `label` draws lines of text on a box, with an optional colored bar. Every shape is filled by the even-odd rule with 4 by 4 samples per pixel, then blended over the frame.

Use the camera's `project` to put a world point on the frame. Then draw a leader line from the label to the point.

## Glyph contours

The overlay fills every contour of a glyph by the even-odd rule. It does not sort the contours into shapes with holes. A font can list a hole before its outline, as DejaVu Sans does for "8". The `to_shapes` method of `ShapePath` keeps the three.js behavior and drops such a hole. The overlay draws it correctly.

## Limits

- The overlay draws in sRGB bytes. It does not tone map.
- Text is one line per call. `label` stacks lines.
- A heightfield whose point count does not fit in an integer is refused.
- An overlay coordinate that does not fit in an integer lies past the frame.
