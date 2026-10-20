# Splat level of detail

`render/splat_lod.mojo` draws a large splat scan with about as many splats as it covers pixels. A tree of merged splats stands in for each cluster of splats that is only a few pixels wide on the screen. On four CPU cores, the 445,409 splats of the tomatoes draw in 22 milliseconds at 320 by 200 pixels. Every splat takes 47 milliseconds.

![A hillside site of splats with a hall and a tower, drawn with levels of detail, and a copy of the hall beside it](out/scan-parts.png)

The picture comes from `examples/scan_parts.mojo`. It draws a site of splats and a copy of its largest [part](Scan-parts) at about 300 frames a second on four cores.

## Draw a scan with levels of detail

```mojo
var lod = build_splat_lod(geometry, node)      # once, when the scan loads
draw_splat_lod(target, scene, lod, camera, None, workers)
```

`draw_splat_lod` takes the place of `draw_gaussian_splat`. `prepare_splat_lod` gives the projected splats, in draw order, for `rasterize_splats`, as `prepare_gaussian_splat` does. Both take `pixels`: how many pixels a node's bounding sphere reaches, at most, for the node to draw as one merged splat. The default is `LOD_PIXELS`, 2.5. At 0, every splat of the scan is drawn.

## The speed

The next numbers come from a Linux machine with four cores and no GPU. "Every splat" is a frame of `draw_gaussian_splat`, with its sort. Each other time is the mean of 12 or more frames round the scan.

| Scan | Splats | Frame | Every splat | Levels of detail | Splats drawn |
|---|---|---|---|---|---|
| The tomatoes, which fill the frame | 445,409 | 320 by 200 | 47 ms | 22 ms, 46 frames a second | 151,780 |
| The tomatoes, from 2.5 times as far | 445,409 | 320 by 200 | 46 ms | 5.5 ms, 183 frames a second | 32,221 |
| The tomatoes, which fill the frame | 445,409 | 640 by 360 | 55 ms | 40 ms, 25 frames a second | 285,464 |
| The site of `examples/scan_parts.mojo`, and the copy of its hall | 73,752 | 320 by 200 | 11 to 14 ms | 2.7 to 3.6 ms, 280 to 370 frames a second | 11,411 |

The tree is built once. It takes about 1.4 seconds for the tomatoes, and about 85 milliseconds for the site.

## The tree

`build_splat_lod` sorts the splats along a Morton curve of their centers, and builds an octree over the sorted splats. So each node holds one run of them. A leaf holds `LOD_LEAF`, eight, splats or fewer, unless more share one Morton code. Each node of more than one splat has a merged splat:

- **Weight.** A splat weighs its opacity times its area: the square root of the sum of its covariance's 2 by 2 principal minors. For a flat splat that is the product of its two widest deviations.
- **Shape.** The merged splat has the weighted mean of the centers. Its covariance is the weighted mean of the covariances, each widened by its center's offset from that mean. That is the Gaussian with the same first two moments.
- **Widening.** Splats whose summed weight is more than that area widen the merged splat. Its covariance grows until its area holds their weight. It stops where the root of the covariance's trace reaches the node's radius.
- **Color.** The color bytes and the spherical harmonics are weighted means. The opacity is the summed weight over the merged splat's own area, at most one, so a surface of opaque splats stays opaque.

The merged splats follow the scan's splats in the tree's geometry, level by level. So the merged splats that a view selects at one level are near each other in memory.

## Why the merged splats widen

A Gaussian with the moments of a square of splats is too narrow to tile a surface. Two such merged splats side by side give about half the opacity at their common edge. So a flat wall of merged splats showed a grid of seams, one at each edge of a node. The widened splats meet with no seam. They hold the same weight, so the wall is not more opaque.

## The selection

`select_splats` walks the tree for a view:

1. A node wholly behind the camera, or past a side of the view by its radius, is skipped with all of its splats.
2. A node whose bounding sphere reaches `pixels` pixels or fewer draws as its merged splat. The camera must be outside the sphere.
3. A leaf draws its own splats. Any other node passes the decision to its children.

The workers share the walk out in subtrees. The tree is opened, level by level, into about 16 subtrees for each worker. Then the subtrees' splats are joined in tree order, so the selection is the same for any count of workers.

`prepare_splat_lod` shades and projects the selected splats and sorts them back to front, into the 4,096 bins of view depth that `GaussianSplat.update_sort` uses. The splats of one bin keep the tree's order. So at 0 pixels the picture differs from `draw_gaussian_splat` only where two splats share a bin.

## The picture

At 2.5 pixels, a frame differs from the frame of every splat by less than 1.5 levels of 255 on average:

| Scan | Frame | Mean difference, of 255 |
|---|---|---|
| The tomatoes, which fill the frame | 320 by 200 | 0.38 |
| The tomatoes, from 2.5 times as far | 320 by 200 | 0.10 |
| The tomatoes, which fill the frame | 640 by 360 | 0.20 |
| The site of `examples/scan_parts.mojo` | 320 by 200 | 1.4 |

The difference of the site is from the frame at 0 pixels. The site's regular rows of splats show each change, and a real scan hides more.

## Limits

- The tree holds the scan's splats again, in tree order, and about one merged splat for every three. The tomatoes' tree holds 590,878 splats.
- A merged splat is a Gaussian. A cluster with a hole or a sharp edge in it looks blurred until the camera is near enough to open it.
- A widened splat reaches past its node. So an edge against the background can blur by a pixel or two.
- The tree is for the CPU fill. The C ABI's splat app draws every splat on the GPU; see [C ABI and hosts](C-ABI-and-hosts).
