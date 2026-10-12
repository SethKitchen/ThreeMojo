# Continuous collision

Use `SPHERE_MESH_CCD` to prevent a supported moving body from passing through a static triangle or another moving body during a step. The supported bodies are dynamic spheres, capsules, boxes and hulls, turning or not, and kinematic spheres, capsules, boxes and hulls, with spin and offsets. The mode is opt-in. The default `DISCRETE` mode keeps the previous solver behavior. The mode name is older than the wider support, and it is kept for compatibility.

```mojo
from extensions.physics.ccd import SPHERE_MESH_CCD

world.collision_detection = SPHERE_MESH_CCD
world.ccd_max_impacts = 16
```

The CARLA compatibility module `extensions.carla.physics.world` exports the same mode type and constants. A bare integer is not a collision detection mode. The world rejects an invalid `CollisionDetection` value at step entry.

## Supported worlds

An enabled collider must be a dynamic or kinematic sphere, capsule, box or hull, or a static mesh. A static mesh must not move. A shape can sit off its body's origin and its mass center, by at most 10000 meters. The table gives each motion and the sweep that it takes.

| Body | Motion | Sweep |
|---|---|---|
| Dynamic sphere or capsule | Only translates its shape, alone or in a group of such bodies | Exact analytic sweep; see [Moving sphere pairs](#moving-sphere-pairs) |
| Dynamic sphere or capsule | Turns its shape, alone | Certified sub-steps; see [Turning bodies](#turning-bodies) |
| Dynamic box or hull | Cannot turn, alone | Exact separating-axis sweep; see [Boxes and hulls](#boxes-and-hulls) |
| Dynamic box or hull | Can turn, alone | Conservative advancement; see [Conservative advancement](#conservative-advancement) |
| Any dynamic or kinematic body | In a group with a turning body, a box, a hull or a kinematic shape other than a plain sphere | Conservative advancement |

A sphere's inverse inertia must be symmetric and positive definite, and the sphere can spin. The tensor can be anisotropic. Each pair of mirrored off-diagonal elements must be exactly equal. A tensor computed as `R M Rᵀ` in Float32 can round each pair differently. Set each pair to its mean before you give the tensor to the body.

A capsule, box or hull whose inverse inertia is zero in every element cannot turn. Its angular velocity and angular push must then be zero, and it only translates, as a character or walker body does. Any other dynamic capsule, box or hull turns, and its inverse inertia must be symmetric and positive definite. A capsule's half height must be finite and at most 10000 meters. Materials keep the existing friction mixing, restitution mixing and bounce threshold.

Each moving body has a reachable region: a ball around its start position, including the contact margin. A capsule's region uses a bounding sphere around its actual world-space segment. The radius includes an outward-rounded length of the Float32-rotated half axis. The exact sweeps use the same shape bound to select mesh candidates. This includes stretch from accepted near-unit rotations and rotation roundoff.

The bound uses the body's total translational and rotational energy after the force update. The rotational energy uses the inertia tensor at the body's orientation at the start of the step. It also includes split-correction travel. This conservative bound covers friction that transfers spin into translation and any number of static-mesh rebounds.

Moving bodies whose reachable regions overlap form a group. An impact can give one member the energy of every other member. So each member of a group reaches as far as the whole group's energy can take it. Groups grow until no two groups overlap. A body alone keeps its own bound and its own sweep. The mode never silently uses discrete contacts for moving bodies that it cannot sweep.

A group of centered spheres, centered capsules that cannot turn and plain kinematic spheres takes the exact group sweep; see [Moving sphere pairs](#moving-sphere-pairs). A plain kinematic sphere is centered on its body and mass and has no spin or spin push. Every other group takes conservative advancement.

A kinematic body follows its set velocity and spin and takes no impulse. It passes through static meshes and other kinematic bodies, as in the discrete mode. It strikes a dynamic body as a body of infinite mass, and its pose stays the one that the integrator gives. A kinematic body alone takes no sweep.

In the frame of a kinematic contact point, an impact cannot add energy. So each impact with a kinematic body raises a dynamic member's speed by at most twice the kinematic body's fastest point speed. That speed is its velocity plus its spin times its farthest shape point from its mass center. The group's reach bound adds that much for each impact that the impact limit allows its dynamic members. A fast kinematic body can therefore join many bodies into one group.

That bound does not hold for two kinematic contacts in one simultaneous response. A wedge of two kinematic plates can squeeze a body out faster. Conservative advancement therefore checks every response against each member's certified reach. A response that would carry a member past it raises an error and rolls the step back.

A dynamic body that a kinematic body drives into a static mesh has no impulse that can open both contacts. The step then raises an error and rolls back.

The mode refuses moving meshes and static primitives; see [Remaining refusals](#remaining-refusals).

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

## Turning bodies

A turning body is a dynamic capsule that can turn. A dynamic sphere or capsule that sits off its body's origin or its mass center also turns. Its shape does not move in a straight line, so it does not take the exact sweep. Alone, it advances in sub-steps that this section describes, and a bound certifies each one. In a group it takes [conservative advancement](#conservative-advancement).

Each sub-step lasts as long as every nearby triangle stays clear of the body's true path:

- The shape is its segment, a capsule's axis or a sphere's center, grown by its radius.
- For each triangle, the face plane or one of its three edge side planes separates the segment most. The bound uses that plane.
- The segment's ends move in straight lines at their present velocities. The true rigid path stays within |ω|² r t² / 2 of those straight lines. Here r is the larger distance of an end from the spin axis through the mass center.
- The plane's distance to the straight-line ends, less that term, must stay above the radius less a tolerance of 1/1024 of the radius.

A capsule that slides or spins about its own axis on a floor does not approach it, so its sub-steps stay long. A shape that already overlaps a triangle can deepen by the tolerance at most.

A triangle that the shape touches within the tolerance, at a point that closes on it, takes a rigid impulse at that point. The impulse uses restitution, Coulomb friction and the world inverse inertia at the step's start orientation, which the reach bound also uses. A friction impulse can turn the body and close the contact again. A further normal impulse then opens it to zero closing speed. That impulse cannot add kinetic energy.

The mass center moves at a constant velocity and the body turns at a constant spin between impacts. The pose turns exactly by |ω| t about ω. A turning body always takes its pose and spin from this sweep, and the integrator's torque-free precession resumes on the next step.

The reach bound of a turning body adds |ω| times its farthest segment end from the mass center. |ω| is bounded by its energy, its mass and the trace of its inverse inertia.

Each turning sweep queries triangles for its current velocity, spin and remaining time. The query starts at the current mass center and includes the whole shape and contact margin. After an impact changes velocity or spin, it queries again. Candidate triangles are sorted by insertion order before contact selection.

`ccd_max_substeps` limits the sub-steps of each turning body, and of each conservative-advancement group, in each step. The default is 256, and valid limits are 1 through 65536. Exhausting it, or the impact limit, rolls the step back. A shape that turns quickly near a surface, for example a lying capsule spun about the vertical, needs many sub-steps.

## Boxes and hulls

A box or hull whose inverse inertia is zero in every element, with no spin and no spin push, only translates. It is swept exactly against static triangles by the separating-axis test over time. Its shape can sit off its body's origin.

The solid and a triangle overlap exactly when their projections overlap on every candidate axis. These are the solid's face normals, the triangle's normal, and the cross product of each solid edge with each triangle edge. Along each axis the solid's interval moves linearly. So the two overlap along that axis during one interval of time.

The first contact is the latest entry over all axes, when it comes before the earliest exit. Its normal is the axis that entered last. An axis along which the solid does not move separates it for the whole step, even when the two only touch. So a face or edge that slides along a triangle with zero clearance takes no impulse. A solid that already touches or overlaps a triangle uses the axis of least overlap instead. So a box that rests on a floor and slides does not close on it, and takes no impulse.

The mesh stays one-sided: a triangle that the solid starts wholly behind does not catch it. An impact is a linear impulse with restitution and Coulomb friction. A box or hull takes this sweep when it is alone in its group, and conservative advancement in a group. Its reach bound uses its farthest corner, which also sets its radius-relative precision limits.

## Conservative advancement

A dynamic box or hull that can turn, and every group that the exact sweeps cannot take, advance in certified sub-steps. Each body is a convex core: the hull of its points, grown by a radius. A sphere has one point, a capsule two, and a box or hull its corners. A static triangle is a core with three points.

### Supported motion and precision domain

A dynamic body's mass center moves at a constant velocity and the body turns at a constant spin between responses. Its pose turns exactly by |ω| t about ω, and it takes its pose and spin from the sweep. A kinematic body's sweep turns it by 2 atan(|ω| h / 2) over the step at a constant spin. That is the angle of the integrator's normalized quaternion update. Its sweep path ends at the integrator's pose, which it keeps.

Each body has a tolerance: 1/1024 of its radius for a sphere or capsule, or of its bounding radius for a box or hull. A pair uses the smaller tolerance of its two bodies. A 1 m cube has a tolerance of 0.85 mm, and a 4.5 m by 2 m by 1.5 m chassis has 2.5 mm.

The precision domain has three parts:

- No pair that starts apart overlaps by more than the tolerance before it responds.
- A pair responds only when its clearance is at most the tolerance, so no impact comes early by more than that.
- A pair that already overlaps, or that another body presses together, deepens by at most the tolerance in each sub-step before the next response.

The arithmetic is Float64 with Float32 state. The stored rotation rounds to Float32 at each sub-step, which moves a shape by about 1e-7 of its size. The precision and refusal limits of the other sweeps also apply; see [Precision and refusal limits](#precision-and-refusal-limits).

### The clearance bound

For each pair with a dynamic body, the sweep finds a separating direction and the clearance along it:

- Two round shapes use the closest points of their segments.
- Other pairs use the separating-axis test over each face normal and each edge-edge cross product. A triangle adds its side normals and each edge crossed with its face. These axes are complete for convex polyhedra, segments and points.
- When the best axis leaves less than 16 tolerances, the exact hull distance replaces it. It comes from each corner on each face polygon of the other shape and each pair of edges.
- A pair that overlaps uses the axis of least overlap and a negative clearance.

Each point of a body moves on a straight line at its present rigid velocity. The true path leaves that line by at most |ω|² r t² / 2. Here r is the point's distance from the spin axis through the mass center. That deviation lies across the spin axis. Along the separating direction n, it is at most |ω|² r t² |n × ω̂| / 2.

The separation of the two hulls along a fixed n is the least gap of a point of one over a point of the other. So the clearance stays above the least linear gap of any point pair, less the summed deviation terms. A sub-step lasts until that bound reaches zero for a pair apart by more than its tolerance. For a pair within its tolerance, the bound can reach the tolerance below zero, or below the present overlap. So a sliding contact still advances.

A spin about the contact normal bends no point along it. A cube that slides and spins flat on a floor therefore takes long sub-steps and no impulse.

A pair's clear time holds until a response changes a velocity. Only pairs whose clear time ends are measured again. A pair whose bounding balls cannot meet before the step ends, or whose triangle's face plane keeps it clear, is skipped. The mesh stays one-sided: a body wholly behind a triangle's face does not touch it.

### Simultaneous response

When a pair touches within its tolerance and a contact point closes on it, every touching contact of the group responds together. Contacts within eight tolerances join the response, so a body that two others squeeze does not chatter between them. A joined contact can act up to eight tolerances before it touches.

A contact point is a corner of a body within the band of the other body. The closest point of two crossing edge interiors is a contact point too. Two round shapes touch at their closest points. A point that a body already has against the same partner and normal adds nothing. So coplanar triangles that share an edge report it once.

The response has three parts:

1. The normal impulses solve the plastic contact problem, x ≥ 0 with nonnegative closing speeds and complementarity. A = J M⁻¹ Jᵀ is positive semidefinite. Lawson and Hanson's active-set method solves it in a fixed order, so the result is deterministic.
2. Poisson restitution repeats the impulses e times. e is the least restitution of the contacts, or zero when no contact closes faster than the bounce threshold. With x^T A x = -b^T x, this changes the energy by -(1 - e²) x^T A x / 2.
3. A Coulomb impulse at each contact in turn at most stops its slip. A second plastic solve then opens any contact that friction closed again.

No part adds kinetic energy in the metric of the tensor at the step's start orientation. The response uses that tensor, as the reach bound does. A kinematic body has infinite mass, so its contact points keep their velocity.

The response refuses more than 256 simultaneous contacts, and a set of contacts that no impulse can open. Each refusal rolls the step back. A box that lands flat on a mesh much finer than the box can touch more than 256 triangle corners.

### Cost

A group makes at most `ccd_max_substeps` sub-steps in a step, and each member at most `ccd_max_impacts` responses. Exhausting either rolls the step back.

A response opens a contact to zero closing speed. A body that turns while it stays in contact closes on its partner again, so each re-closing costs a response. A plastic cube that grinds past another at 10 m/s needs tens to hundreds of responses in 0.01 s. So does a light body that a sliding heavy body rolls along the ground. Raise the limits for such scenes, or use a smaller step.

Each sub-step measures the pairs whose clear time ended. A pair measurement costs about the product of the two bodies' point counts, plus their face and edge counts. A response measures every pair again and solves at most 256 contacts.

## Remaining refusals

The mode refuses these worlds explicitly, and it does not fall back to discrete contacts:

- **A moving mesh.** A mesh's triangles are the world-space snapshot taken when the mesh was added. Neither mode moves them, so a moving mesh body has no surface that CCD can follow. Use a kinematic box or hull for a moving solid. A rigidly moving mesh needs a mesh pose in the snapshot, which is separate work.
- **A static primitive.** Use a static mesh, or a kinematic body with zero velocity.
- **A capsule, box or hull that cannot turn but spins.** Every element of its inverse inertia is zero, so it cannot have a spin.
- **A turning body without a symmetric positive definite tensor.** The reach bound needs its rotational energy.
- **Two round shapes whose axes already cross.** They have no separating direction.

A step also rolls back when it exhausts a limit, refuses a contact set or leaves a certified reach.

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
work. It was outside the acceptance of
[issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635), and it
needs its own issue. Conservative advancement has the same limitation, so a
box that slides across a shared edge can take a tilted contact too. No
mesh-validity rule or collision edge is silently skipped to hide this
limitation.

## Precision and refusal limits

The algorithm is an analytic piecewise-linear sweep, or certified conservative advancement, with Float64 intermediates. It does not use exact geometric predicates. Its public state remains Float32. The following limits are checked rather than treated as warnings:

- Sphere radii must be between 0.0001 m and 10000 m, inclusive
- All body positions and cached triangle coordinates must be within 1000000 m of the origin on each axis
- A colliding sphere's coordinates must stay within 65536 times its radius on each axis
- Its reachable radius, including the sphere radius, must not exceed 1048576 times its radius
- A potentially nearby triangle's vertices must lie within 1048576 radii of the sphere center on each axis. Bounds reject distant triangles before this check.
- Each triangle must have a nonzero Float32 raw normal. Its Float64 cross-product magnitude must be at least its longest squared edge length divided by 1048576.
- Body and shape rotations must be finite unit quaternions, within 0.00001 in squared norm
- All state, material and solver values checked by the mode must be valid; newly computed state and impulses must be representable

For a box or hull, the radius in these limits is its bounding radius. Conservative advancement adds its own tolerance; see [Supported motion and precision domain](#supported-motion-and-precision-domain).

The coordinate-to-radius limit bounds each component's final Float32 rounding by approximately radius / 256. The three-component Euclidean rounding bound is less than 0.007 radius. This is a storage bound, not an overall trajectory-accuracy guarantee. Use a local origin and a smaller coordinate range for tighter accuracy. The original Float32 inputs cannot recover geometry that was already rounded away.

The approach test uses a 32-epsilon bound on the sum of absolute dot-product terms. It ignores a normal approach whose sign is unresolved at that arithmetic scale.

Before response, the world rebuilds the shape from its retained impact position. It checks for an initial contact on the selected triangle with the incoming direction. If this contact exists, its normal controls the response. This lookup does not move the body, search future times, or add an impact.

After friction, the response reconstructs the velocity component with the largest normal component. This keeps the restitution target within dot-product roundoff when an almost axial impact cancels most of the incoming speed. The remaining dot-product error then scales with the final operands. This avoids repeated zero-time impacts from projection roundoff.

The bound is relative to the operands. It is not a fixed skin, a larger collision margin or a fixed minimum collision speed. Exact tangency produces no impulse.

Very thin triangles, excessive travel, coarse world coordinates and unsupported shapes raise errors. The mode does not promise collision detection outside these limits. Select application-specific tolerances and validate the intended geometry and motion before engineering use.

## Ordering, limits and rollback

Triangle ties retain triangle insertion order. Equal feature times retain face order, then edge and vertex order. Bodies alone are processed in body insertion order, then groups in the order of their lowest member. All swept events are stably sorted by time, with that order breaking equal times. Initial discrete-solver reports precede swept reports. Each report still supplies equal and opposite normal-impulse events.

A conservative-advancement response reports its pairs in member order, then triangle insertion order, then partner order.

`contact_count` includes initial contact points and each swept impact. `events` is replaced after a successful step. The mode does not promise bitwise equality across compiler versions, architectures or floating-point contraction modes. A rounded edge-to-cap tangency can add a small later impulse and change the capsule impact count.

`ccd_max_impacts` defaults to 16 per body per step. Valid limits are 1 through 1024. The loop does not discard remaining time, freeze a body or continue through a surface after exhaustion. It raises an error.

A failed CCD step restores body positions, rotations, velocities, forces, torques, split state, previous contact count, previous events, primitive order and mesh dirty state. A failed step does not consume pending forces. This applies to every supported shape. Tests check the complete restored state after an impact-limit, sub-step-limit or support failure for spheres, capsules, boxes, hulls, turning capsules and turning boxes. For boxes, hulls, turning capsules and turning boxes, a retried step also matches a world that never failed, bit for bit. A mesh index allocated during an unsuccessful rebuild can remain in memory.

Restoring the dirty flag preserves ray-query behavior. The next successful step rebuilds that contact index. A validated CCD index can remain valid after rollback because the immutable triangle snapshot did not change. Tests cover equal-distance mesh ownership before and after failure.

Use a smaller step or change the model when a supported step exhausts its impact budget. Increasing the budget increases worst-case work. It does not improve unresolved geometry.

## Performance and verification

CCD uses a private triangle bounds tree for meshes with more than eight triangles. Smaller meshes use the original linear scans. The independent brute-force diagnostic path also repeats all geometry and separation checks. It remains the comparison oracle.

The index stores each triangle once. Median splits bound the depth by `ceil(log2(T))` for T triangles. Build work is O(T log² T), with O(T) temporary storage. The retained tree has `2T - 1` nodes.

Queries use escape links and need no traversal stack or full-mesh visited array. Each query visits at most `2T - 1` nodes and returns at most T triangle indices. There is no candidate limit that can discard a possible hit.

Swept query bounds use Float64. Each endpoint addition and radius expansion rounds outward. Stored Float32 triangle bounds convert exactly to Float64. The query covers the complete sphere path, including its endpoints. Existing face, edge, vertex and approach tests are unchanged. An equal-time hit uses triangle insertion order, regardless of tree order.

The two separation checks query the complete reachable region, including the contact margin. They still perform the original domain check on each candidate. The second check uses post-solver velocity, spin and split correction. No early hit can skip another candidate's required refusal.

The cached geometry check is O(1). Live-body validation is O(B) for B bodies. Moving-body grouping costs O(B²) for each round in which groups grow, and there are at most B rounds. It adds tree visits and candidate checks.

A centered sphere or centered capsule that cannot turn does O(T (I + 1)) swept work for T triangle candidates and impact limit I. In a group of G members, each pass sweeps every member against its triangle candidates and every pair once, which is O(G T + G²). Each pass, settling included, ends the step or charges an impact to a dynamic member. So a group makes at most G I + 1 passes. A settled cascade of C contacts tries at most 2^C active sets, and C is at most ten. Overlapping triangle bounds can defeat pruning.

A turning sweep also tests its candidates at each sub-step. Its sub-step and impact limits bound that work. It queries and sorts the candidates at the start and after each impact.

A conservative-advancement group of G members with T triangle candidates each measures at most G T + G² pairs in a sub-step. It usually measures far fewer. Its sub-step and impact limits bound the number of sub-steps and responses. A response solves at most 256 contacts.

Rollback storage still scales with mutable body state and reports. Initial discrete contacts and rays retain the existing octree.

The [acceleration report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/continuous-collision-636.md) reports complete steps, build cost, retained memory, requested allocations, small scenes and worst-overlap controls. It reuses the original 2048, 8192 and 32768 triangle workloads. These are synthetic sphere probes. Measured improvement does not establish universal real-time capacity.

The [interacting-sphere report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/ccd-pairs-635.md) times head-on pairs, chains and struck stacks, 64 groups each, and a rolled-back step. Each check runs outside the timing. On those scenes a CCD step costs about 1.5 to 17 discrete steps. Ray costs and cold index construction remain additional concerns.

`bench/physics_ccd_bench.mojo` times the steps.
`bench/physics_ccd_index_bench.mojo` times the triangle index.
`bench/physics_ccd_walker_bench.mojo` times rotation-locked capsule walkers and spinning anisotropic spheres on a terrain. See [the walker report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/ccd-walker-728.md).

`bench/physics_ccd_engine_bench.mojo` times a turning box chassis, turning walker pairs, piles of interacting bodies and a rolled-back step, with its rollback storage. See [the engine report](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/ccd-engine-635.md). The chassis is a collision probe, not a validated vehicle model.

Tests include the original tunneling example, a radius/speed/step/restitution family, edge and vertex formulas, grazing controls and multiple rebounds. Other controls cover friction, spin energy, late-impact orientation, deterministic ordering, mode changes, ghosts, numeric refusals and rollback. Boxes and hulls have hand-derived grazing and energy controls with restitution 0 and 1 and with friction. Every supported shape has mode-change and ghost controls. Twenty-three reference hits use a separate 70-digit Decimal nearest-triangle-distance search and time bisection. Ordinary discrete physics suites remain part of qualification.

Conservative advancement has its own controls in `tests/test_physics_ccd_engine.mojo`. Flat-face, edge and corner landings follow the rigid impulse law by hand. Off-center landings, elastic and rough tumbling cubes and a rolling chassis check energy in the start metric. Coupled cubes, a capsule and a cube, and a cube on a resting ball check momentum, energy and clearance.

Kinematic boxes, capsules and every kinematic sphere variant strike balls as infinite masses. A kinematic squeeze and a kinematic wedge roll back. Other controls cover grazing slides, one-sided meshes, corners, mesh ordering, mode changes, ghosts, refusals and rollback.

`tests/test_physics_ccd_engine_oracle.mojo` is an independent oracle for turning box and capsule impacts. It shares no geometry with the library. It moves each body on its exact rigid path by Rodrigues' rule. It finds the box distance by golden-section search over the triangle and the overlap depth from the 13 separating axes. Each engine impact must come within the tolerance of contact, with no deeper overlap before it.

Grazing slides, a rolling capsule and a corner that passes two tolerances clear take no impact. The original turning-capsule sweep passes the same oracle.

[Issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635) is complete. Turning boxes and hulls, kinematic shapes of every kind and coupled turning bodies now have continuous collision. The remaining refusals are explicit; see [Remaining refusals](#remaining-refusals). The engine report gives the vehicle, walker and interacting-body benchmarks. The immutable-mesh acceleration in [issue 636](https://github.com/SethKitchen/ThreeMojo/issues/636) does not provide the mutable primitive ownership API in [issue 633](https://github.com/SethKitchen/ThreeMojo/issues/633).
