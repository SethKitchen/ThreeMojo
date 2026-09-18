# Why coverage uses fixed point

The rasterizer snaps vertices to a 1/16 pixel grid and evaluates the edge function in integers. Floating point left one-pixel cracks along shared edges.

![A large triangle turns slowly, and its edges stay locked to pixels](out/coverage.png)

## The crack

Two triangles that share an edge test it from opposite corner orders. One asks `edge(A, B, p)`, the other `edge(B, A, p)`. In floating point those results need not negate exactly. A pixel almost on the edge can come out negative for both, and neither triangle draws it.

That left one-pixel cracks along the diagonal of a quad: two in a large quad, forty-four with the camera inside a cube.

## The fix

With coordinates snapped to a grid, the edge function is exact integer arithmetic. Reversing an edge negates the value exactly. No pixel can be missed.

## The top-left rule

Exactness opens the opposite problem: a pixel exactly on a shared edge is now claimed by both triangles. That is invisible under an opaque depth test. It doubles every shared edge once anything is blended.

The top-left fill rule gives such a pixel to one triangle: the one whose edge is a top edge or a left edge. `tests/test_fillrule.mojo` asserts that a shared edge is claimed exactly once.

## One implementation

`render/fillrule.mojo` allocates nothing, prints nothing and raises nothing, so it compiles for a device as readily as for the host. The GPU kernel calls the same functions. See [Why the CPU and GPU share code](Why-the-CPU-and-GPU-share-code).

## A bug that parity could not see

A shared implementation means a parity test cannot catch a bug inside it, because both sides are wrong together. The fill-rule tests therefore pin the module against values derived from the definitions. That caught the horizontal half of the top-left rule reversed. A reversed rule is still a consistent tie-break, so no crack test sees it. It silently lost a triangle's top row when that edge landed on pixel centers.
