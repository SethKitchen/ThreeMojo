# Why transparency is sorted

Blending is not commutative, so `Renderer.prepare` decides the draw order. Opaque meshes come first, nearest first. Translucent meshes follow, furthest first.

## Two rules every renderer has

A translucent surface tests depth without writing it. It is hidden by what is in front and hides nothing behind, so two panes one behind the other both show. three.js's `depthWrite` is on by default for a transparent material too, so there a pane drawn first can hide one drawn after it. That flag is not ported.

Opaque surfaces draw first because they write the depth that stops a pane behind a wall from showing through. Among themselves they draw nearest first. The image does not depend on that order, but the cost does: a fragment that fails the depth test is skipped before it is shaded.

## One answer to one question

Whether a surface composites decides two things together: how its color combines, and whether it writes depth. It has to be one answer. It was three: the mesh sorter asked the material, and each rasterizer asked a vertex color. A material with an opaque `opacity` but a translucent base color sorted as opaque and rasterized as blended. It wrote no depth, and whatever came after painted over it.

`Material.blending` is now that one answer. It is inferred from the opacity and the color where it can be. It is stated where it cannot be, because a texture's own alpha is invisible from the material. It travels to both rasterizers as per-triangle state.

## Per mesh

The sort is per mesh, by the depth of its node's origin, as three.js sorts. A translucent mesh that overlaps itself is still approximate. The alternative is sorting every triangle every frame.

## The GPU blends in one pass

The kernel accumulates every fragment of a pixel in one pass. That is correct only because every opaque triangle arrives before any translucent one. The nearest solid depth is then final when the first blended fragment shows up.

## See it

![Three translucent panes turn through each other over a cube](out/glass.png)

`examples/glass.mojo` renders three translucent panes turning through each other over a solid cube. Submitting them in any order gives the same image, and a test asserts it.
