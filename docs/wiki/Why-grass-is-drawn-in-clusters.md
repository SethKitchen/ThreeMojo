# Why grass is drawn in clusters

A meadow has millions of blades, and a frame can draw only a few hundred thousand of them. Clusters let a frame draw only the blades that it can see, at the detail that their distance needs.

![Gusts sweep across the meadow and bend the tall grass](out/meadow-wind.png)

`examples/meadow_wind.mojo` draws this picture. The page is an explanation. For the calls and the numbers, see [Vegetation](Vegetation).

## The work a GPU-driven renderer does

A renderer for dense vegetation on a GPU does most of its work before the draw. It cuts the geometry into clusters of about a hundred triangles, often called meshlets. A compute pass tests each cluster against the view and picks its level of detail. Only the clusters that pass go to the draw.

The table shows where each step is in this extension.

| GPU-driven step | Here |
|---|---|
| Cut the geometry into meshlets with bounds | `GrassField` cuts the field into square clusters and keeps a bounding sphere for each. |
| Cull each meshlet in a compute pass | `GrassField.select` tests each bound against the frustum. |
| Pick the level of detail on the GPU | `select` picks the first `LodBand` whose reach holds the cluster. |
| Generate the grass in a compute pass | `GrassField.build` grows the blades of a drawn cluster from its seed. |
| Bend the grass in the vertex shader | `build` bends each blade by `Wind.tip_bend` as it grows it. |
| Draw with indirect calls | `Meadow.update` shows the drawn clusters' meshes and hides the rest. |

The rasterizer here draws about a million triangles a second on each core. A frame costs about one microsecond for each triangle, whatever the size of the image. So the count of triangles that reach the draw sets the frame time, and culling and levels of detail are the work that pays.

## Why a level is a prefix of a stream

A field of ten million blades is too large to store. A cluster stores a corner, a bound and two counts. Its blades are a stream: blade `i` belongs to tuft `i % tufts`, and a hash of the cluster and `i` gives its place and its shape.

The first `n` blades of the stream are an even sample of the cluster, with a few blades in each tuft. So a level that keeps a fraction of the blades builds the first part of the stream. Nothing is sorted. A blade of a far level is the same blade at a near level. So a cluster keeps its look when its level changes.

The chance that a blade is a poppy is the blade's own chance, and not the tuft's. Each level then keeps the same mix of grass, straw and poppies.

## Why a thin level widens its blades

A level that keeps a tenth of the blades covers a tenth of the ground. Each kept blade is wider by `keep ** -0.7`, so the field keeps most of its cover. A far blade also stays wider than a pixel. A blade narrower than a pixel falls between the samples on some frames and not on others, and it flickers.

Past the last level, the ground carries the far color of the grass that grows on it. The thinnest blades fade into a ground of their own color, and the eye does not find the edge of the field. The same rule tints the ground red under far poppy drifts.

## Why a bend is an angle

The wind turns each segment of a blade by its share of an angle. It does not push the tip by a distance. A turned segment keeps its length, so a bent blade is as long as a straight one. A push would stretch the blade in a gust.

A gust is a patch of noise that travels downwind. Every blade under a patch bends together. A bent blade shows more of its lit face, and the gust also brightens the tips it reaches. The patches are then seen as waves of light that sweep across the field. The flutter is a small wobble of each blade on its own, with its own phase.

## Why a blade is lit from both sides

A blade is thin. Light that reaches one face shows through on the other, so a blade with the sun behind it glows. The renderer lights a double-sided face seen from behind with its normal turned round, as three.js does. For a blade, that turns half of the field dark.

`two_sided_program` adds `2 * (front_facing - 1) * normal` to the normal. The offset is zero on a front face. On a back face, it turns the normal to the front again. The leaves of the trees use the same program.

## Why a crown is lit by its clumps

A crown is tens of thousands of small leaves turned every way. Lit by their own normals and the sun's shadow map, the leaves are a noise of light and dark, and thin leaves shadow themselves. Real crowns read as clumps: bright where the sun reaches a clump's top, and dark under it and inside the crown.

So the leaves hang in clumps, and the clumps are spheres. The light that reaches a leaf through spheres is exact and cheap: the sum of a few chords, and Beer's law. The sun's share dims only the sun, and the sky's share dims only the sky, as the light of a real crown does. A leaf in the shade then keeps the blue light of the sky.

A far crown keeps fewer leaves and makes each larger, and the farthest uses cards. It stays geometry, so it is lit and it casts a shadow as a near crown does.
