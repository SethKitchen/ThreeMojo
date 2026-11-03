# Virtual scans

`extensions/scan/virtual.mojo` makes a scan of a rendered scene. A renderer that draws a scene well, with materials, shadows, water and woods, draws it slowly. A scan of the scene as splats draws it in milliseconds. The scan can be walked through, cut into parts, weighed and fitted as a building, as a scan of a real building can.

![Wijnendale Castle as a scan of 3.65 million splats: a ring of woods, the island, the moat and the bridge](out/wijnendale-scan.png)

`examples/wijnendale_scan.mojo` made the picture's scan. It takes 24 pictures of [Wijnendale Castle](Castle), each with its depth, and keeps one splat for each 15 cm cell of what they see. The pictures take about ten minutes on 24 CPU threads. The scan is a `.splat` file of 116.9 MB, 3,653,318 splats, in meters with y up and z south. A frame draws in 37 ms on the CPU at 800 by 600. On the GPU at 1920 by 1080 from 90 m, it draws in 35 ms.

```bash
.venv/bin/mojo run -I . examples/wijnendale_scan.mojo
.venv/bin/mojo run -I . examples/scan_view.mojo out/castle.png .cache/wijnendale/wijnendale.splat +y 24 0.22
```

The file is in `.cache/wijnendale/`, which git ignores. Give the example a path that ends in `.png`, and it also draws the scan from above the woods to that picture. The gallery makes `out/wijnendale-scan.png` this way.

## How a picture becomes splats

Each pixel of a picture is a point of the scene, and the picture's color is the color of the point.

1. **The point.** The pixel's center and its stored depth, an NDC depth from -1 to 1, go back through the camera. The inverse of the projection times the view gives a point of the scene.
2. **The surface.** The points of the pixel's right and lower neighbors give two tangents. Their cross product is the normal, turned toward the camera. A pixel on the edge of a surface is left out. It has a neighbor with no depth, or a neighbor more than `edge` of the distance nearer or farther. A normal within `grazing` of the line of sight also leaves it out.
3. **The splat.** It lies in the surface. Its deviation along each tangent is `spread` of the pixel's footprint along it, and its deviation across the surface is `thin` of the smaller one. It has the pixel's color.

The views overlap. Each point goes into a cell, `voxel` on an edge. A cell keeps the sample that was seen best. That is the sample with the greatest cosine between the normal and the line of sight, over its distance. So a scan of 24 views holds a splat for each cell of the surface and no more.

```mojo
var scan = VirtualScan(default_virtual_scan_options())
for view in views:
    var image = draw_castle(castle, renderer, camera, cloud_cover, view)
    _ = scan.add_view(image, camera.view_matrix(), camera.projection_matrix())
scan.write(".cache/wijnendale/wijnendale.splat")
var geometry = scan.geometry()           # or the splats themselves
```

| Option | Default | Meaning |
|---|---|---|
| `voxel` | 0.15 m | The edge of a cell: the scan keeps one splat in each |
| `edge` | 0.03 | The most that a neighbor can be nearer or farther, as a share of the distance, before the pixel is on an edge |
| `grazing` | 0.2 | The least cosine between the line of sight and the normal |
| `spread` | 0.7 | A splat's deviation, as a share of the pixel's footprint |
| `thin` | 0.15 | A splat's deviation across the surface, as a share of the smaller deviation in it |
| `opacity` | 240 | The opacity byte of every splat |

`geometry` gives the splats with covariances `sa^2 a a^T + sb^2 b b^T + sn^2 n n^T`, for the tangents `a` and `b`, the normal `n`, and the deviations. `splat_bytes` and `write` give the rows of a `.splat` file. A row has 32 bytes: the center, the three deviations, the color and a rotation. The rotation's bytes are `128 + 128 q`. `loaders.splat.parse_splat` reads the rows back.

## The Wijnendale scan

The scan's cameras stand on three rings round the middle of the castle. The first ring has 8 views at a radius of 150 m and a height of 0.9 radii. The second has 8 at 105 m and 0.45 radii, and the third 8 at 75 m and 0.22 radii. The views are 800 by 800 pixels with a field of view of 50 degrees. The sun is the sun of 15:00 on 19 October 2026 at Torhout. The scan keeps the woods as well, so the box of its splats is 504 m by 516 m by 29 m.

Use `UP` of `+y` when you draw it. The scene's y is up and its z is south, so a frame of up +y and north -z reads it.

## Limits

- The light is baked. The shadows, the sun and the reflections in the water are those of the pictures. A splat takes the color of its best view, with no spherical harmonics, so the water does not change as the camera moves.
- A surface that no view saw has no splat. The scan holds the outside of the castle and the ground. It holds no interior, no underside of a roof and nothing behind a tree that every view missed.
- The edge test drops the pixels on a silhouette. A thin object, such as a railing, loses some of its splats.
- The cells are of one size. A close view and a distant one are both held to 15 cm, so the detail of a near view is not kept. Use a smaller `voxel` and more views for a scan that is drawn closer.
- The render's supersampling blends the color of an edge pixel with the sky or the water behind it. The edge test drops most of these. Some remain as pale splats on a silhouette.
