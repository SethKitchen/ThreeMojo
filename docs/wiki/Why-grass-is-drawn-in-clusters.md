# Why grass is drawn in clusters

A meadow has millions of blades, and a frame can draw only a few hundred thousand of them. Clusters let a frame draw only the blades that it can see, at the detail that their distance needs.

![Gusts sweep across the meadow and bend the tall grass, in a loop](out/meadow-wind.png)

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

A gust is a patch of noise that travels downwind. Every blade under a patch bends together. A bent blade shows more of its lit face, and the gust also brightens the tips it reaches. The patches are then seen as waves of light that sweep across the field.

The eye reads wind in what moves together. A blade that moves on its own is noise. A thin blade that trembles a few degrees moves a pixel or two a frame, and a field of them looks as if it buzzes. So the gust does most of the bending. The sway that rides on it moves whole patches in step. The flutter of each blade is only a degree.

## Why the wind loops

An animation that plays round and round jumps at its end unless its last frame leads into its first. Noise that travels never comes back to where it started. So a looping wind fades the gusts at a time into the gusts one loop earlier. At the start of the loop the first pattern shows, and at its end the second, which is the first one again.

Two patterns faded half and half are flatter than either. The fade divides by the length of its weights, `sqrt((1 - w)^2 + w^2)`, so the gusts keep their contrast through the loop. The sway and the flutter swing a whole number of times a loop, so they also end where they began.

## Why a blade is lit from both sides

A blade is thin. Light that reaches one face shows through on the other, so a blade with the sun behind it glows. The renderer lights a double-sided face seen from behind with its normal turned round, as three.js does. For a blade, that turns half of the field dark.

`two_sided_program` adds `2 * (front_facing - 1) * normal` to the normal. The offset is zero on a front face. On a back face, it turns the normal to the front again. The leaves of the trees use the same program.

## Why a tree grows toward points

A tree grown by rules, with each branch forking at fixed angles, has a crown that is even all round. Real crowns are not. A tree grows toward the light, and its limbs compete for room. So a crown is lobes of leaves with sky between them, and each lobe is fed by a limb.

Space colonization grows a tree in that way. The crown's lobes are filled with points, the places that the leaves reach for. Each point pulls the branch nearest to it, and a branch grows toward the mean of its pulls. Points close together pull one branch, and points apart split it in two. A limb then grows into each lobe and forks to fill it, and a gap between the lobes stays open. The trunk forks where it enters the crown, as a lone tree's trunk does.

The thickness follows the pipe model, so each fork carries the wood of the branches above it.

## Why a crown's light comes from a grid

A crown is tens of thousands of small leaves turned every way. Lit by their own normals and the sun's shadow map, the leaves are a noise of light and dark, and thin leaves shadow themselves. Real crowns read as masses: bright where the sun reaches the top of a lobe, and dark under it and inside the crown.

So each leaf carries the light that reaches it through the others. The leaves are counted in a grid of cells, and a ray from each leaf steps through the cells toward the sun and the sky. Beer's law gives the light that comes through. The grid holds any shape of crown, and its cost grows with the leaves, not with their square. The sun's share dims only the sun, and the sky's share dims only the sky, as the light of a real crown does. A leaf in the shade then keeps the blue light of the sky.

A far crown keeps fewer leaves and makes each larger, and the farthest uses cards. It stays geometry, so it is lit and it casts a shadow as a near crown does. The crown is grown and lit once, and each level draws from the same leaves.

## Why a crown sways in the vertex stage

A GPU-driven renderer moves a tree's leaves in its vertex shader. The geometry stays as it was built, and a few sines of time and place move each vertex. Here a node program's position output does the same. To grow the crown again on each frame would cost far more.

A position program reads only constants, uniforms, time, math and the vertex's own position and normal. It reads no attribute, so how far a vertex sways cannot be baked into it. So the program works that share out from where the vertex is: higher up and further out from the trunk, it sways more. A twig and its leaves are in the same place, so they move together. A far tree's leaves are a few pixels, and its motion would not show. So the levels of cards stand still, and cost nothing for it.
