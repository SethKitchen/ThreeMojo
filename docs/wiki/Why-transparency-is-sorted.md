# Why transparency is sorted

Blending is not commutative, so `Renderer.prepare` decides the draw order. Opaque meshes come first, nearest first. Translucent meshes follow, furthest first.

## Two rules every renderer has

A translucent surface tests depth and writes it, as in three.js. `depth_write` is on by default for a transparent material too. The furthest pane draws first, so a pane behind is already there when a nearer pane mixes over it. A pane drawn first can hide a pane drawn after it, as in three.js. Set `depth_write=False` on a material to let every surface behind it show through.

Opaque surfaces draw first because they write the depth that stops a pane behind a wall from showing through. Among themselves they draw nearest first. The image does not depend on that order, but the cost does: a fragment that fails the depth test is skipped before it is shaded.

## One answer to one question

Whether a surface composites decides two things together: how its color combines, and where it sorts. It has to be one answer. It was three: the mesh sorter asked the material, and each rasterizer asked a vertex color. A material with an opaque `opacity` but a translucent base color sorted as opaque and rasterized as blended. It mixed with the pixel before the surfaces behind it were drawn.

`Material.blending` is now that one answer. It is inferred from the opacity and the color where it can be. It is stated where it cannot be, because a texture's own alpha is invisible from the material. It travels to both rasterizers as per-triangle state.

## Per mesh

The sort is per mesh, by the depth of its node's origin, as three.js sorts. A translucent mesh that overlaps itself is still approximate. The alternative is sorting every triangle every frame.

## The GPU blends in one pass

The kernel accumulates every fragment of a pixel in one pass, in draw order. A fragment that writes depth updates the depth that the next fragments test against, opaque or translucent. The host target writes depth at the same step, so the two backends agree.

## See it

![Three translucent panes turn through each other over a cube](out/glass.png)

`examples/glass.mojo` renders three translucent panes turning through each other over a solid cube. The sort decides the order, so submitting them in any order gives the same image, and a test asserts it.
