# Sphere and static-mesh continuous collision

Use `SPHERE_MESH_CCD` to prevent a supported sphere or rotation-locked capsule from passing through a static triangle during a step. It also prevents two moving spheres from passing through each other. The mode is opt-in. The default `DISCRETE` mode keeps the previous solver behavior.

```mojo
from extensions.physics.ccd import SPHERE_MESH_CCD

world.collision_detection = SPHERE_MESH_CCD
world.ccd_max_impacts = 16
```

The CARLA compatibility module `extensions.carla.physics.world` exports the same mode type and constants. A bare integer is not a collision detection mode. The world rejects an invalid `CollisionDetection` value at step entry.

## Supported worlds

An enabled collider must be a dynamic sphere, a rotation-locked dynamic capsule, a kinematic sphere or a motionless static triangle mesh. Each sphere or capsule must have zero shape offset and zero mass-center offset. A sphere's inverse inertia must be symmetric and positive definite, and the sphere can spin.

The tensor can be anisotropic. Each pair of mirrored off-diagonal elements must be exactly equal. A tensor computed as `R M Rᵀ` in Float32 can round each pair differently. Set each pair to its mean before you give the tensor to the body.

A capsule's inverse inertia must be zero in every element, and its angular velocity and angular push must be zero. A capsule then only translates, as a character or walker body does. Its half height must be finite and at most 10000 meters. Materials keep the existing friction mixing, restitution mixing and bounce threshold.

Each moving body has a reachable region: a ball around its start position, including the contact margin. A capsule's region uses a bounding sphere around its actual world-space segment. The radius includes an outward-rounded length of the Float32-rotated half axis. The same bound selects swept mesh candidates. This includes stretch from accepted near-unit rotations and rotation roundoff.

The bound uses the body's total translational and rotational energy after the force update. The rotational energy uses the inertia tensor at the sphere's orientation at the start of the step. It also includes split-correction travel. This conservative bound covers friction that transfers spin into translation and any number of static-mesh rebounds.

Moving bodies whose reachable regions overlap form a group. An impact can give one member the energy of every other member. So each member of a group reaches as far as the whole group's energy can take it. Groups grow until no two groups overlap. A group of spheres is swept together; see [Moving sphere pairs](#moving-sphere-pairs). A body alone keeps its own bound and its own sweep.

A group can hold spheres and rotation-locked capsules. The mode never silently uses discrete contacts for moving bodies that it cannot sweep.

A kinematic sphere follows its set velocity and takes no impulse. It must have no spin and no angular push. It passes through static meshes and other kinematic bodies, as in the discrete mode. It strikes a dynamic sphere as a body of infinite mass, and its pose stays the one that its velocity gives.

In a kinematic sphere's frame, an impact cannot add energy. So each impact with a kinematic sphere raises a dynamic member's speed by at most twice the kinematic speed. The group's reach bound adds that much for each impact that the impact limit allows its dynamic members. A fast kinematic sphere can therefore join many bodies into one group.

A dynamic sphere that a kinematic sphere drives into a static mesh has no impulse that can open both contacts. The step then raises an error and rolls back.

The mode refuses colliding boxes, convex hulls, capsules that can rotate, kinematic capsules, spinning kinematic spheres, static primitives and offset spheres. General convex, rotating-capsule and rotating-offset CCD remain unsupported. This feature does not turn a box chassis into a continuous collider. A capsule walker is supported only with its rotation locked.

A body with `collides = False` stays outside collision handling. Its forces and motion still follow the original integration rules. It must still have valid finite state. Turning collisions back on restores the same support checks on the next step.

Mesh geometry uses the immutable world-space triangles captured by `add_body`, as the existing mesh index does. Editing a mesh body's shape or pose after insertion does not update this snapshot. Build a new world when the mesh geometry changes.

CCD validates every snapshot triangle before it builds an acceleration index. This includes distant triangles and triangles whose owner has collisions disabled. It retains the successful geometry check for that snapshot.

Adding a mesh invalidates the check and index together. Adding a sphere does not invalidate either. The next CCD step validates the complete new snapshot before it queries the index. Direct edits to private triangle or index fields are unsupported.

Body state, collision flags, materials, sphere radii and solver settings stay live. Each step checks them again. The cache does not extend the supported precision domain. Nearby candidates still pass the original radius-relative domain check.

## Step and contact behavior

Forces, gravity and damping update velocity once per step. The swept path is piecewise linear at that post-update velocity. It is not the curved path of continuous acceleration.

The sweep tests the triangle face, its three edge cylinders and its three vertex spheres. It uses the earliest approaching front-side contact. After an impact, it applies a normal impulse and a Coulomb-limited tangential impulse. It then sweeps the remaining time with the changed velocity. More than one impact can occur in a step.

A capsule's sweep adds two features to the two cap spheres. The segment can reach a triangle edge, and a triangle vertex can reach the segment's cylinder. The segment's interior reaches the face itself only when the segment is parallel to it. Then the whole segment reaches the plane at once, and a cap over the face or an edge crossing reports that time. Because the capsule cannot rotate, its friction impulse changes only its velocity.

The normal response cannot add kinetic energy for restitution between zero and one. Tangential response dissipates slip energy.

For an anisotropic sphere, every impact in a step uses the world tensor at the step's start orientation. The energy that the separation bound measured then cannot increase during the step. These statements apply to the ideal static impulse calculation. Stored state still rounds to Float32. External forces and the existing split-overlap correction are separate operations.

The sphere's orientation advances separately over each time segment. It uses the existing normalized-quaternion rule and the angular velocity for that segment. This is an approximate rotation integrator, not an exact angular trajectory.

A sphere with an impact keeps the constant angular velocity that made its orientation in that step. For an anisotropic tensor, the integrator's torque-free precession starts again on the next step. A sphere's sweep does not depend on its orientation, so this choice does not change any impact time.

Initial front-side overlaps keep the existing contact solver and pose-only split correction. Stationary and slow front-side contacts keep the previous speculative-contact path. A negative-depth contact is deferred to the sweep when its closing travel exceeds the existing contact margin. This prevents a fast sphere from bouncing before it reaches the surface. The margin is not enlarged.

CCD rejects initial backface contacts, including a sphere that already overlaps the back of the face. It does not catch a sphere that starts behind a triangle and crosses toward its front during that segment. This one-sided rule also applies to edge and vertex candidates. A capsule is behind the face only when both segment endpoints start behind it. Reversing the endpoints does not change admission. A segment that starts partly in front keeps the existing overlap and split-correction response.

The opt-in mode corrects the tunneling example in [issue 292](https://github.com/SethKitchen/ThreeMojo/issues/292), recorded against the port at `af6c253`. The test uses radius 0.1 m, initial z 0.15 m, velocity -30 m/s and step 0.01 s. The sphere now stops at z = 0.1 m on a plastic horizontal mesh. Discrete mode still reaches z = -0.15 m. This is a correction to the port's own solver. It does not claim an identical CARLA trajectory.

## Moving sphere pairs

The members of a group move together in time order. Each pass finds the earliest impact of any member with a static triangle or another member. It moves every member to that time and applies that one impulse. Then it sweeps the remaining time again.

A pair's sweep uses their relative motion and their summed radius. Each member is a segment: a capsule's axis, or a sphere's center. The sweep tests each end of one segment against the other segment, as a cylinder and two end caps. It also tests the two interiors across the plane that both axes span. It is exact for shapes that only translate, as spheres and rotation-locked capsules do between impacts. Equal times keep the lower member first, then a triangle before another member, then the lower other member.

A pair impact uses the normal between the two closest points. The normal impulse uses both inverse masses and the pair's restitution and bounce threshold. A Coulomb friction impulse then acts at the contact. It uses each sphere's world inverse inertia at its orientation at the start of the step. The normal response with restitution between zero and one cannot add kinetic energy. Friction that at most stops the slip cannot add it either.

A body that falls onto a resting stack makes a cascade: several impacts at one instant. A plastic cascade only halves the speeds each round, so it would never end. A second impact at the same instant therefore settles the cascade. It finds every contact that touches at that instant, including pairs and member triangles. It solves their normal impulses together as one plastic contact problem. The solver tries active sets in one fixed order, so the result is deterministic.

Settled impulses are plastic and frictionless, and they cannot add kinetic energy. A bouncing impact in a cascade stays sequential, so an elastic stack still bounces. After twice as many impacts as the group has members, the rest of a cascade settles plastically.

The settling refuses more than ten simultaneous contacts. It also refuses a set of contacts that no impulse can open. Each refusal rolls the step back.

Each impact counts against `ccd_max_impacts` for every body that it moves. A settled contact counts in the same way.

Fast contacts between two moving spheres within the contact margin use their relative velocity. A pair closing faster than the margin per step goes to the sweep. A slower pair keeps the existing speculative contact. Against a static mesh, the relative velocity is the body's own velocity, as before.

## Tessellated-floor limitation

Shared triangle edges can produce false edge contacts. The mesh stores no
adjacency or feature Voronoi regions. A sphere that overlaps a flat floor
slightly can hit an internal edge with a tilted normal. That impulse can
turn horizontal speed into vertical speed, even with zero restitution.
Both `DISCRETE` and `SPHERE_MESH_CCD` have this limitation. It is not a new
regression in CCD, and CCD does not make the result independent of mesh
triangulation.

The test `test_tessellated_floor_documents_existing_ghost_contacts` compares
one triangle with the same surface split into four triangles. It uses a
0.1 m sphere at z = 0.0996 m, horizontal speed 5 m/s, gravity, zero friction
and restitution, and twenty 0.01 s steps. The single-triangle control has
no upward launch. Both tessellated cases produce upward velocity. The test
records the limitation; it does not certify that response as physically
correct. Existing face, boundary-edge and vertex controls stay in place.

A correction needs topology-aware feature admission for swept and initial
contacts. It must retain real boundary edges, triangle tie order, mesh
validation and transactional failure. This is separate contact-topology
work for the [physics follow-up scope](https://github.com/SethKitchen/ThreeMojo/issues/635).
No mesh-validity rule or collision edge is silently skipped to hide this
limitation.

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

The approach test uses a 32-epsilon bound on the sum of absolute dot-product terms. It ignores a normal approach whose sign is unresolved at that arithmetic scale.

Before response, the world rebuilds the shape from its retained impact position. It checks for an initial contact on the selected triangle with the incoming direction. If this contact exists, its normal controls the response. This lookup does not move the body, search future times, or add an impact.

After friction, the response reconstructs the velocity component with the largest normal component. This keeps the restitution target within dot-product roundoff when an almost axial impact cancels most of the incoming speed. The remaining dot-product error then scales with the final operands. This avoids repeated zero-time impacts from projection roundoff.

The bound is relative to the operands. It is not a fixed skin, a larger collision margin or a fixed minimum collision speed. Exact tangency produces no impulse.

Very thin triangles, excessive travel, coarse world coordinates and unsupported shapes raise errors. The mode does not promise collision detection outside these limits. Select application-specific tolerances and validate the intended geometry and motion before engineering use.

## Ordering, limits and rollback

Triangle ties retain triangle insertion order. Equal feature times retain face order, then edge and vertex order. Bodies alone are processed in body insertion order, then groups in the order of their lowest member. All swept events are stably sorted by time, with that order breaking equal times. Initial discrete-solver reports precede swept reports. Each report still supplies equal and opposite normal-impulse events.

`contact_count` includes initial contact points and each swept impact. `events` is replaced after a successful step. The mode does not promise bitwise equality across compiler versions, architectures or floating-point contraction modes. A rounded edge-to-cap tangency can add a small later impulse and change the capsule impact count.

`ccd_max_impacts` defaults to 16 per body per step. Valid limits are 1 through 1024. The loop does not discard remaining time, freeze a body or continue through a surface after exhaustion. It raises an error.

A failed CCD step restores body positions, rotations, velocities, forces, torques, split state, previous contact count, previous events, primitive order and mesh dirty state. A failed step does not consume pending forces. A mesh index allocated during an unsuccessful rebuild can remain in memory.

Restoring the dirty flag preserves ray-query behavior. The next successful step rebuilds that contact index. A validated CCD index can remain valid after rollback because the immutable triangle snapshot did not change. Tests cover equal-distance mesh ownership before and after failure.

Use a smaller step or change the model when a supported step exhausts its impact budget. Increasing the budget increases worst-case work. It does not improve unresolved geometry.

## Performance and verification

CCD uses a private triangle bounds tree for meshes with more than eight triangles. Smaller meshes use the original linear scans. The independent brute-force diagnostic path also repeats all geometry and separation checks. It remains the comparison oracle.

The index stores each triangle once. Median splits bound the depth by `ceil(log2(T))` for T triangles. Build work is O(T log² T), with O(T) temporary storage. The retained tree has `2T - 1` nodes.

Queries use escape links and need no traversal stack or full-mesh visited array. Each query visits at most `2T - 1` nodes and returns at most T triangle indices. There is no candidate limit that can discard a possible hit.

Swept query bounds use Float64. Each endpoint addition and radius expansion rounds outward. Stored Float32 triangle bounds convert exactly to Float64. The query covers the complete sphere path, including its endpoints. Existing face, edge, vertex and approach tests are unchanged. An equal-time hit uses triangle insertion order, regardless of tree order.

The two separation checks query the complete reachable region, including the contact margin. They still perform the original domain check on each candidate. The second check uses post-solver velocity, spin and split correction. No early hit can skip another candidate's required refusal.

The cached geometry check is O(1). Live-body validation is O(B) for B bodies. Moving-body grouping costs O(B²) for each round in which groups grow, and there are at most B rounds. It adds tree visits and candidate checks.

A body alone does O(T (I + 1)) swept work for T triangle candidates and impact limit I. In a group of G members, each pass sweeps every member against its triangle candidates and every pair once, which is O(G T + G²). Each pass, settling included, ends the step or charges an impact to a dynamic member. So a group makes at most G I + 1 passes. A settled cascade of C contacts tries at most 2^C active sets, and C is at most ten. Overlapping triangle bounds can defeat pruning.

Rollback storage still scales with mutable body state and reports. Initial discrete contacts and rays retain the existing octree.

The [acceleration report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/continuous-collision-636.md) reports complete steps, build cost, retained memory, requested allocations, small scenes and worst-overlap controls. It reuses the original 2048, 8192 and 32768 triangle workloads. These are synthetic sphere probes. Measured improvement does not establish universal real-time capacity.

The [interacting-sphere report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/ccd-pairs-635.md) times head-on pairs, chains and struck stacks, 64 groups each, and a rolled-back step. Each check runs outside the timing. On those scenes a CCD step costs about 1.5 to 17 discrete steps. Ray costs and cold index construction remain additional concerns.

`bench/physics_ccd_bench.mojo` times the steps.
`bench/physics_ccd_index_bench.mojo` times the triangle index.
`bench/physics_ccd_walker_bench.mojo` times rotation-locked capsule walkers and spinning anisotropic spheres on a terrain. See [the walker report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/ccd-walker-728.md).

Tests include the original tunneling example, a radius/speed/step/restitution family, edge and vertex formulas, grazing controls and multiple rebounds. Other controls cover friction, spin energy, late-impact orientation, deterministic ordering, mode changes, ghosts, numeric refusals and rollback. Twenty-three reference hits use a separate 70-digit Decimal nearest-triangle-distance search and time bisection. Ordinary discrete physics suites remain part of qualification.

General shapes and moving-pair CCD remain separate work in [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635). The immutable-mesh acceleration in [issue 636](https://github.com/SethKitchen/ThreeMojo/issues/636) does not provide the mutable primitive ownership API in [issue 633](https://github.com/SethKitchen/ThreeMojo/issues/633).
