<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Physics query snapshots

`PhysicsQuerySnapshot` owns a frozen ray-query view. A query never reads the source `PhysicsWorld`. The source can change or be destroyed after capture. Existing `PhysicsWorld.raycast` calls keep their behavior.

Import the API from `extensions.physics.query_snapshot`.

## API

- `PhysicsQuerySnapshot(world)` captures enabled primitive shapes, their bounds, materials, source slots, and registered mesh query data
- `snapshot.raycast(origin, direction, max_distance, ignore)` returns an optional `SnapshotRaycastHit`
- `snapshot.body_count()` returns the captured source slot count, including disabled bodies
- `snapshot.check_owner(owner)` checks that a historical owner belongs to this capture

A hit has `owner`, `point`, `normal`, `distance`, and `material` fields. Point and distance values use meters. The hit owns its material value and owner token. It can outlive both the source world and the snapshot.

`ignore` is a `BodyId` interpreted in the captured source-slot namespace. `BodyId(-1)` ignores none. A nonnegative index outside the capture ignores none. An index below -1 is invalid.

The reach is inclusive for finite hit distances. Negative reach rejects those hits. Existing nonfinite narrow-phase answers keep their legacy behavior. NaN reach is invalid. Infinite reach is allowed. The origin and direction must be finite, and the direction must be nonzero.

## Historical owners

`SnapshotOwner` is a distinct type. It is not a live `BodyId`. Its `source_body` field records the source index at capture time. Its retained token identifies the capture. Two captures of the same world have different owner identities. Moving a snapshot preserves its identity.

`check_owner` checks only captured membership. It does not prove that a body still exists in a live world. Do not use `source_body` to apply a force, change a material, or resolve a current actor without a separate application-level lifetime check. A later body can occupy the same integer slot. Snapshot owner tokens stay distinct even after source and snapshot destruction.

There is no live-body resolver in this API. Resource reclamation and generational live handles remain the scope of [#306](https://github.com/SethKitchen/ThreeMojo/issues/306).

## Mutation contract

Every later source edit leaves an existing capture unchanged:

- Body insertion, removal, replacement, or list reordering
- Collision enablement or disablement
- Static, dynamic, or kinematic mode changes
- Body pose, local shape pose, dimensions, vertices, planes, or topology edits
- Surface material changes
- World stepping, registered mesh changes, or octree rebuilds

Build a new `PhysicsQuerySnapshot(world)` to capture another state. A failed constructor leaves earlier captures usable. Assign or move the new value only after construction succeeds. An empty world produces an empty capture. Disabling every body produces a capture that answers no hits.

The API has no mutation or refit method. It cannot update bounds without updating narrow geometry and materials. Rebuilding means constructing a complete new capture with a new owner identity. Independent captures share no geometry, materials, index storage, or query scratch.

Mojo 1.1 does not enforce field privacy. Underscore fields mark implementation storage by convention. They do not enforce invalidation. Callers must use the documented API and must not edit that storage. Source-world mutation safety comes from owned copies, not an add-body counter or naming convention.

## Registered static meshes

The world records mesh triangles in world space when a mesh body is added. Its existing raycast reads that registered view. A snapshot copies the same view. A later edit to a mesh body's local geometry or pose does not change the registered triangles in either ray API.

Capture-time mesh materials and collision enablement come from the source slot. The snapshot owns these values. Later source edits cannot change them. A missing, out-of-range, or non-mesh registered owner causes capture to fail. Capture does not infer the lifetime of a removed body from an integer slot reused before capture.

A dirty world uses the registered triangle list in insertion order. A clean world uses an owned copy of the existing octree and its traversal order. This retains the established mesh-first tie rule and the current tie order between mesh triangles. Primitive distance ties keep the lower captured body index.

## Validation

Capture checks body mode and mass consistency, shape kinds, and materials. Enabled primitives also require finite poses, unit rotations, valid round-shape dimensions, and structurally valid finite solid geometry. These checks run before indexed geometry reads. Registered mesh vertices must be finite.

The checks do not certify that an arbitrary edited polyhedron is a convex physical solid. The snapshot preserves the existing narrow-phase interpretation of accepted geometry. Disabled primitive geometry is not transformed or queried. Its shape kind, body state, and material still need valid values.

## Query strategy

Queries read owned world-space primitive geometry. This removes the per-ray transformation and deep geometry allocation in `PhysicsWorld.raycast`. The static mesh path stays unchanged.

The sole bounded primitive index lives in `extensions/physics/primitive_index.mojo`. The earlier benchmark imports that implementation. A snapshot can own one index over its captured primitive entries. No query reads live geometry after index traversal.

The indexed path has a strict numerical admission rule:

- The normalized ray must point along exactly one coordinate axis
- Each ray-origin component must have absolute value at most 10^12 meters
- An admitted sphere must have radius from 2^-16 through 2^16 meters and bounded endpoint coordinates
- A capsule must meet the sphere limits, and its segment must be exactly parallel to the ray axis
- A solid must have exact coordinate-axis unit plane normals, with both signs on each axis, and bounded vertices

Bounds for round shapes include a proved outward rounding allowance. The index tests only the two transverse coordinates. It does not cull behind the origin or by reach. Other shapes use the same owned-linear narrow phase during that query. The merge restores complete captured body order, including unsafe shapes whose legacy calculations can return NaN. The existing narrow kernels and their answers stay unchanged.

A capture with fewer than 32 admitted primitives uses the linear path. Bounds with a common intersection also use the linear path. A query that retains at least one quarter of all primitives returns to the linear path before sorting. Non-axis rays and origins outside the admitted range use the linear path. These fallbacks change work, not answers.

Tight mathematical half-ray bounds alone cannot preserve every existing answer. Regression tests include a finite hit outside collapsed Float32 bounds and a finite-input legacy NaN hit. Those are limitations of the existing narrow arithmetic. They do not establish an error in the mathematical BVH. The benchmark separates the safe production path from a forced mathematical-BVH experiment.

An experimental index refit must retain entry count and owner mapping. Insertion, removal, remapping, or active-set changes require rebuild. Large motion can leave a refitted tree slow even when its candidate set is correct. Compare query node visits and elapsed time with a fresh rebuild before reuse. Empty rebuilds clear all entries. No experiment changes the contact sweep or solver.

See the [measurement report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/owned-physics-snapshots-633.md) for build amortization, retained memory, the small-world policy, dynamic-only sweep control, and refit degradation.
