# Sphere and static-mesh continuous collision

Use `SPHERE_MESH_CCD` to prevent a supported sphere from passing through a static triangle during a step. The mode is opt-in. The default `DISCRETE` mode keeps the previous solver behavior.

```mojo
from extensions.physics.ccd import SPHERE_MESH_CCD

world.collision_detection = SPHERE_MESH_CCD
world.ccd_max_impacts = 16
```

The CARLA compatibility module `extensions.carla.physics.world` exports the same mode type and constants. A bare integer is not a collision detection mode. The world rejects an invalid `CollisionDetection` value at step entry.

## Supported worlds

An enabled collider must be either a dynamic sphere or a motionless static triangle mesh. Each sphere must have zero shape offset and zero mass-center offset. Its inverse inertia must be positive and isotropic. The sphere can spin. Materials keep the existing friction mixing, restitution mixing and bounce threshold.

A sphere's reachable region must not overlap another sphere's reachable region, including the contact margin. The bound uses the sphere's total translational and rotational energy after the force update. It also includes split-correction travel. This conservative check covers friction that transfers spin into translation and any number of static-mesh rebounds. A step that cannot establish separation raises an error. It does not silently use discrete moving-body contacts.

The mode refuses colliding boxes, convex hulls, capsules, kinematic bodies, static primitives, offset spheres and interacting moving bodies. General convex, capsule, rotating-offset and moving-pair CCD remain unsupported. This feature does not turn a box chassis or a capsule walker into a continuous collider.

A body with `collides = False` stays outside collision handling. Its forces and motion still follow the original integration rules. It must still have valid finite state. Turning collisions back on restores the same support checks on the next step.

Mesh geometry uses the immutable world-space triangles captured by `add_body`, as the existing mesh index does. Editing a mesh body's shape or pose after insertion does not update this snapshot. Build a new world when the mesh geometry changes.

## Step and contact behavior

Forces, gravity and damping update velocity once per step. The swept path is piecewise linear at that post-update velocity. It is not the curved path of continuous acceleration.

The sweep tests the triangle face, its three edge cylinders and its three vertex spheres. It uses the earliest approaching front-side contact. After an impact, it applies a normal impulse and a Coulomb-limited tangential impulse. It then sweeps the remaining time with the changed velocity. More than one impact can occur in a step.

The normal response cannot add kinetic energy for restitution between zero and one. Tangential response dissipates slip energy. These statements apply to the ideal static, isotropic impulse calculation. Stored state still rounds to Float32. External forces and the existing split-overlap correction are separate operations.

The sphere's orientation advances separately over each time segment. It uses the existing normalized-quaternion rule and the angular velocity for that segment. This is an approximate rotation integrator, not an exact angular trajectory.

Initial front-side overlaps keep the existing contact solver and pose-only split correction. Stationary and slow front-side contacts keep the previous speculative-contact path. A negative-depth contact is deferred to the sweep when its closing travel exceeds the existing contact margin. This prevents a fast sphere from bouncing before it reaches the surface. The margin is not enlarged.

CCD rejects initial backface contacts, including a sphere that already overlaps the back of the face. It does not catch a sphere that starts behind a triangle and crosses toward its front during that segment. This one-sided rule also applies to edge and vertex candidates.

The opt-in mode corrects the tunneling example in [issue 292](https://github.com/SethKitchen/ThreeMojo/issues/292), recorded against the port at `af6c253`. The test uses radius 0.1 m, initial z 0.15 m, velocity -30 m/s and step 0.01 s. The sphere now stops at z = 0.1 m on a plastic horizontal mesh. Discrete mode still reaches z = -0.15 m. This is a correction to the port's own solver. It does not claim an identical CARLA trajectory.

## Precision and refusal limits

The algorithm is an analytic piecewise-linear sweep with Float64 intermediates. It does not use exact geometric predicates. Its public state remains Float32. The following limits are checked rather than treated as warnings:

- Sphere radii must be between 0.0001 m and 10000 m, inclusive
- All body positions and cached triangle coordinates must be within 1000000 m of the origin on each axis
- A colliding sphere's coordinates must stay within 65536 times its radius on each axis
- Its reachable radius, including the sphere radius, must not exceed 1048576 times its radius
- A potentially nearby triangle's vertices must lie within 1048576 radii of the sphere center on each axis. Bounds reject distant triangles before this check.
- Each triangle must have a nonzero Float32 raw normal. Its Float64 cross-product magnitude must be at least its longest squared edge length divided by 1048576.
- Body and shape rotations must be finite unit quaternions, within 0.00001 in squared norm
- All state, material and solver values checked by the mode must be valid; newly computed state and impulses must be representable

The coordinate-to-radius limit bounds each component's final Float32 rounding by approximately radius / 256. The three-component Euclidean rounding bound is less than 0.007 radius. This is a storage bound, not an overall trajectory-accuracy guarantee. Use a local origin and a smaller coordinate range for tighter accuracy. The original Float32 inputs cannot recover geometry that was already rounded away.

The approach test uses a 32-epsilon bound on the sum of absolute dot-product terms. It ignores a normal approach whose sign is unresolved at that arithmetic scale. This avoids repeated zero-time impacts from projection roundoff. The bound is relative to the operands. It is not a fixed skin, a larger collision margin or a fixed minimum collision speed. Exact tangency produces no impulse.

Very thin triangles, excessive travel, coarse world coordinates and unsupported shapes raise errors. The mode does not promise collision detection outside these limits. Select application-specific tolerances and validate the intended geometry and motion before engineering use.

## Ordering, limits and rollback

Triangle ties retain triangle insertion order. Equal feature times retain face order, then edge and vertex order. Spheres are processed in body insertion order. Their independent swept events are stably sorted by time, with body order breaking equal times. Initial discrete-solver reports precede swept reports. Each report still supplies equal and opposite normal-impulse events.

`contact_count` includes initial contact points and each swept impact. `events` is replaced after a successful step. The mode does not promise bitwise equality across compiler versions or architectures.

`ccd_max_impacts` defaults to 16 per sphere per step. Valid limits are 1 through 1024. The loop does not discard remaining time, freeze a body or continue through a surface after exhaustion. It raises an error.

A failed CCD step restores body positions, rotations, velocities, forces, torques, split state, previous contact count, previous events, primitive order and mesh dirty state. A failed step does not consume pending forces. A mesh index allocated during an unsuccessful rebuild can remain in memory. Restoring the dirty flag preserves ray-query behavior. The next successful step rebuilds that index. Tests cover equal-distance mesh ownership before and after failure.

Use a smaller step or change the model when a supported step exhausts its impact budget. Increasing the budget increases worst-case work. It does not improve unresolved geometry.

## Performance and verification

The current implementation scans static triangles for each sweep. It does not claim a production acceleration structure. For B spheres, T triangles and an impact limit I, the swept work is bounded by O(B T (I + 1)). Support preflights add O(B T + B²), and rollback storage scales with mutable body state and reports. Initial discrete contacts retain the existing octree.

The [validation report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/continuous-collision-292.md) gives fixed vehicle-probe, separated-fleet and dense-sensor workloads. The benchmark includes geometry checks and transaction costs. These are synthetic sphere probes, not a validated vehicle fleet. Large measured scenes exceed a 10 ms step budget. Ray timings do not establish real-time capacity for a complete simulation.

Tests include the original tunneling example, a radius/speed/step/restitution family, edge and vertex formulas, grazing controls and multiple rebounds. Other controls cover friction, spin energy, late-impact orientation, deterministic ordering, mode changes, ghosts, numeric refusals and rollback. Twenty-three reference hits use a separate 70-digit Decimal nearest-triangle-distance search and time bisection. Ordinary discrete physics suites remain part of qualification.

General shapes and moving-pair CCD are tracked in [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635). Conservative triangle candidates and enabled-step cost are tracked in [issue 636](https://github.com/SethKitchen/ThreeMojo/issues/636). Both remain follow-up work outside this mode.
