<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Owned physics query snapshots: issue 633

The production API owns complete frozen query state. It keeps `PhysicsWorld.raycast` unchanged. A bounded numerical admission rule permits a primitive index for coordinate-axis rays. All other queries use owned linear geometry. This report separates capture cost, retained query cost, and a forced mathematical-BVH experiment.

The implementation starts from draft #632 commit `84038a2e06b0945fb1586b712298ab9268741b81`. The toolchain is Mojo 1.1.0 (`8189361e`), with warnings as errors. Native timing and allocation-hook runs are separate. Measurements use one serial CPU lane; the host is not dedicated or CPU-isolated.

## Ownership and lifetime

`PhysicsQuerySnapshot` owns world-space primitive shapes, their bounds, captured material values, source-slot metadata, registered mesh triangles, and the clean mesh octree when present. Queries have no source-world reference. Later source edits and source destruction leave the capture frozen.

`SnapshotOwner` retains an allocation token for its capture and a historical source index. Its type differs from `BodyId`. Equal integer source slots from separate captures are different owners. A retained hit prevents token-address reuse from producing a false identity match. `check_owner` checks capture membership only. It never resolves a live body.

Every refresh constructs a new complete capture and a new identity. There is no public bounds-only refit. Insertion, removal, replacement, enablement, mode, shape, pose, material and registered-mesh changes need a new capture to become visible. Failed construction does not change earlier captures. Empty worlds and fully disabled worlds answer no hits.

Mojo field naming does not enforce privacy or invalidation. The supported snapshot API has no mutating method. Its safety with respect to world edits follows from owned data. A caller that edits underscore storage is outside that API.

## Why ordinary half-ray bounds are not sufficient

Two retained regressions show why exact legacy answers need a numerical admission rule:

1. A radius-one sphere at `(1e8, 1e8, 0)` has collapsed Float32 x/y bounds. A ray from `(99999984, 99999984, 0)` in direction `(1, 1.0000001, 0)` misses the exact box line. The current sphere narrow kernel returns a finite hit near 21.6274 meters. A tight-bounds candidate query would remove that legacy answer.
2. A radius-`1e20` sphere at the origin and a ray from `(2e20, 0, 0)` along +z have finite input values. The current narrow kernel computes `inf - inf` and returns an Optional hit with NaN distance. The mathematical box ray rejects it. The snapshot preserves the legacy Optional result and NaN fields.

These examples do not show an error in mathematical box traversal. They show that replacing the existing Float32 narrow semantics with geometric culling can change answers. No narrow kernel is changed in this issue. Nonfinite legacy results from unsafe shapes remain in historical primitive order, because a NaN comparison can affect which later hit wins.

## Numerical admission proof

Queries first construct the same normalized `Ray` as the existing API. The index tests the already-normalized ray direction. Its sole nonzero component is exactly +1 or -1. The index path requires an exact coordinate-axis direction and origin components with absolute value at most `1e12`. It checks the full line's two transverse coordinates only. It never rejects on longitudinal coordinates, reach, or whether the box is behind the origin.

### Spheres

Admitted round endpoints have absolute coordinate values at most `1e12`. The radius is in `[2^-16, 2^16]`. Every ray-center subtraction is finite.

For an axis direction, the longitudinal component of the sphere kernel's `drop` vector is exactly zero. Transverse components are the rounded center-origin differences. Their squares and sum are finite. The radius square is finite and normal.

Let `u = 2^-24`, the Float32 unit roundoff. If the computed squared gap `h` is nonnegative, the rounded radius square is at least the rounded sum of transverse squares. The positive sum is at least either rounded square. For a transverse rounded difference `q` greater in magnitude than the radius, its square is normal. The usual rounded multiplication bounds give

`abs(q) <= radius * sqrt((1 + u) / (1 - u))`.

The exact transverse subtraction then satisfies

`abs(center - origin) <= abs(q) / (1 - u) < radius * (1 + 4*u)`.

If `abs(q)` is no greater than the radius, the same final bound holds directly from subtraction rounding. A zero or subnormal subtraction has magnitude far below the minimum admitted radius. The relative-error bound is needed only for larger, normal differences. A zero result in the `h` subtraction cannot invalidate this argument. Distinct radius-scale Float32 operands have a normal difference in this admitted range.

The implementation multiplies the radius in Float64 by exactly `1 + 8*u`. It rounds that radius upward to Float32. It then rounds each endpoint-minus-radius bound downward and endpoint-plus-radius bound upward. The resulting box encloses every transverse coordinate that the legacy sphere predicate can accept. The bound also covers radius collapse at a large Float32 center. The factor is an arithmetic bound, not a measured tolerance.

### Capsules

A capsule is admitted only when its stored segment is exactly parallel to the query axis. The bounded endpoints make its squared segment length finite. In the existing cylinder kernel, `length_sq` and `ad * ad` are then the same Float32 multiplication. Its coefficient `a` is exactly zero, so the cylinder path returns no side hit. The two endpoint sphere tests satisfy the sphere proof above. A zero-length capsule is a sphere for all three query axes.

### Solids

An admitted solid has only exact signed coordinate-axis unit plane normals, with both signs present on every axis. Its vertices are bounded. `Polyhedron.transformed` recomputes every plane offset from a validated indexed transformed vertex. It does this even if the caller edited the source offsets.

For either transverse coordinate, a ray origin outside the complete vertex min/max range is outside a parallel signed-axis plane. The plane dot product is exactly that coordinate or its negation. The subtraction keeps its sign. The existing narrow kernel rejects that ray. Arbitrary edited face connectivity cannot move the supporting corner outside the complete vertex bounds. No geometric convexity assumption is needed for this implication.

### Ordering and fallbacks

The index has one leaf per admitted primitive entry. Its traversal returns no duplicate. Sorted candidate entry indices merge with per-axis unsafe entries in the original primitive order. Mesh queries still run first through the captured dirty list or clean octree.

Fewer than 32 admitted entries or a common intersection of all admitted bounds selects the owned linear path. Non-axis rays and origins outside the admitted range also select it. A candidate set with at least one quarter of all primitives returns to that path. These decisions affect work only. No fallback changes geometry, materials, owner identity, or the final narrow predicate.

## Measurements and verification

Read the [measurement report](owned-physics-snapshots-633.md) for the complete corpus, amortization, retained memory, dynamic-only sweep control, refit/rebuild criterion, and final verification evidence.
