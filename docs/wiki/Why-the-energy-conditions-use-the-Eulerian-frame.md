# Why the energy conditions use the Eulerian frame

The energy conditions in `extensions/warp/` read the stress-energy tensor in the frame of the Eulerian observer, with the Minkowski metric. That frame is orthonormal, so its components and its metric belong together. This page explains why that matters, and why the port differs from WarpFactory for two of the four conditions.

## An energy condition is about observers

The null energy condition says that no ray of light sees a negative energy density. In symbols, T_ab k^a k^b ≥ 0 for every null vector k. The weak condition says the same for every observer, with timelike vectors. These are statements about all vectors at a point, so they do not depend on coordinates.

A program cannot test every vector. It samples a set of directions and keeps the least value. A direction is null or timelike only with respect to a metric, so the directions and the tensor must use the same metric.

## The Eulerian frame is orthonormal

The Eulerian observer is at rest in the slices of constant time. `to_eulerian` finds a basis for this observer in which the metric is the Minkowski metric η = diag(-1, 1, 1, 1). In that basis, (1, n̂) is null for every unit vector n̂, and (1, s n̂) is timelike for s < 1. That is why the sampled directions are simple.

The components of the tensor in that basis are T̂^ab. To contract them with a direction, the indices must come down with the metric of the same basis, which is η. Then T̂_ab k^a k^b is the energy density that a real ray of light sees.

## What WarpFactory does

WarpFactory lowers the Eulerian components with the metric of the coordinate grid for the null and weak conditions. It uses η for the strong and dominant conditions. Where the grid metric g is η, as far from a bubble at rest, the two give the same value.

Where g is not η, the product mixes the components of one basis with the metric of another. The result is not T_ab k^a k^b for any vector k. In the wall of a moving bubble the difference is large. In the parity test it is more than 1 percent at the point the test checks.

The port uses η for all four conditions. `tests/test_warp_parity.mojo` reproduces WarpFactory's value with WarpFactory's lowering, to show that the rest of the chain agrees. Then it checks that the corrected value differs.

## Limits of a sampled condition

A sampled condition can find a violation, but it cannot prove that a condition holds. A negative value proves a violation at that point. A positive value says only that no sampled direction violates it. More directions make the test finer.

Where the slices of constant time are not spacelike, the Eulerian observer does not exist. This is the case inside a Krasnikov tube and inside a horizon. There `to_eulerian` raises an error, and these conditions cannot be evaluated in this frame.
