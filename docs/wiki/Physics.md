# Shared physics

`extensions/physics/` holds the rigid-body mechanics shared by simulation extensions. It has no dependency on CARLA actors, maps, sensors or controls. The CARLA extension uses these same types and functions.

## Modules

| Module | What it gives |
|---|---|
| `shape` | Shapes, materials and mass properties |
| `body` | Rigid bodies, body ids, forces and impulses |
| `collide` | Contact points and narrow-phase collision tests |
| `world` | Contact solving, integration and ray casts |
| `quantities` | Torque, energy, momentum, stiffness and unit constants |

The `extensions/carla/physics/` paths for these five modules remain supported compatibility imports. They re-export the shared definitions, with no separate solver or wrapper types. A body made through either path can enter the same world.

Use `extensions.physics` for new consumers of the shared mechanics. The CARLA compatibility imports have no planned removal.

Vehicle setup, wheel forces, CARLA controls, the walker controller and `CarlaPhysics` stay in `extensions/carla/physics/`. They are domain models and tick orchestration. The [CARLA physics](CARLA-physics) page describes them.

## Frames and units

Choose one frame for a world. Express every position, shape, gravity vector, velocity, force and torque in that frame. The default gravity remains (0, 0, -9.8) m/s² for compatibility. A y-up simulation can set gravity to (0, -9.8, 0).

Lengths, masses, durations and other scalar quantities use `units.si` and `units.quantity`. Vector and matrix fields hold SI numbers in `Vector3` and `Matrix3`. Their docstrings give the units. The vector type does not enforce those dimensions.

Keep frame conversion at the domain boundary. For an orthogonal basis R, a center becomes R c and an inertia tensor becomes R I Rᵀ. Keep all six independent entries of the symmetric tensor. A reflection also changes the sign rule for axial vectors such as angular velocity and torque: they use det(R) R. Do not treat a y/z swap as an ordinary rotation.

## Use anatomy mass properties

`SegmentInertia` gives mass, center and the six tensor entries for a limb segment. These entries are about its center of mass in the leg frame. The off-diagonal values already have the tensor sign.

Create the collision shape separately. Set the body's mass, center of mass and inertia from the physical model. Transform the center and the full tensor into the body's frame first. If the reference point changes, apply the parallel-axis theorem. Display mesh thickness must not set physical mass.

`tests/test_shared_physics.mojo` checks this handoff with an authored segment tensor. It does not claim a whole-body physical rig. The current anatomy code supplies no joint solver or muscle-force controller.

## Change a body's motion mode

Use `RigidBody.set_kind` to switch motion mode. Disabling a dynamic body sets its effective mass and inverse inertia to zero. It retains the exact configured dynamic mass and local inverse tensor for later restoration. This includes off-diagonal entries and locked axes. A chain through kinematic and static modes does not replace that saved state.

Dynamic-to-kinematic changes keep velocity. Entering static stops linear, angular and split-impulse velocity. Pending force and torque keep their normal step-consumption lifetime. CARLA's `set_simulate_physics(False)` also stops kinematic velocity, as its adapter did before.

World position and orientation can change while physics is disabled. Restored world inertia uses the new orientation and the retained local tensor. Mass, inertia, mass-center and shape-offset setters reject edits to a disabled dynamic configuration. Restore dynamic mode before making those edits. A body created static or kinematic has no saved dynamic mass; create it dynamic first when later restoration is needed.

Read `kind()`, `mass()`, `inverse_mass()` and `inverse_inertia()` as values. These replace the former public fields. Add parentheses to existing reads. Direct assignment to these names is a compile error. Change the mode with `set_kind`, the mass with `set_mass`, and solid inertia with `set_inertia`.

Use `set_inverse_inertia` for a finite custom inverse tensor, including locked axes. This setter retains the supplied entries. A returned tensor is a copy; editing it does not edit the body. Custom tensors keep their previous finite-entry contract. Negative and nonsymmetric tensors remain accepted for compatibility. They do not need to describe a positive-definite solid.

Mojo 1.1 has no enforced field privacy. Underscore storage is internal by convention, not a security boundary. Do not mutate that storage, use reflection to bypass setters, or replace the shape directly. The supported API prevents partial mode and mass edits; it does not make arbitrary storage access safe.

`validate` checks valid mode, mesh restrictions, reciprocal dynamic mass, finite inverse tensors and zero disabled effective properties. Setters, standalone impulses, world insertion and each world step run this check. A step checks all bodies before it changes any body or consumes forces. A failed check leaves that operation's state unchanged. World insertion and standalone impulses can now raise `Error`.

Validation runs at these boundaries, not inside each contact operation. Read accessors return stored values without validation. Pose, center, shape, material and motion fields remain mutable. These checks do not validate an arbitrary physical model or prevent deliberate, coherent edits to internal storage.


## Mass-property numerical range

`Shape.mass_properties` requires a finite positive mass and a solid shape. It returns the center and the inertia about that center for uniform density. Spheres and capsules use analytic formulas. Capsules compute the cylinder and cap mass fractions without forming their volumes.

Polyhedra use two integration passes in Float64. The first finds the center; the second integrates about that center. This avoids subtracting large translated moments. Face construction and ordering also widen coordinate arithmetic.

The stored center and tensor use Float32. Every tensor entry must be finite, and the stored tensor must be symmetric and positive definite. A zero-volume solid or an inertia that overflows, underflows to a singular tensor, or loses positive definiteness is refused. Small entries round to Float32 precision.

No fixed size limit or determinant tolerance replaces these checks. An error-free determinant expansion tests the sign for the stored tensor, including exact singularity.

Input coordinates already rounded to Float32 cannot recover lost geometric detail.

`RigidBody.set_mass` also requires representable inverse mass and inverse inertia. It computes and validates all candidate properties before it changes the body. `set_inertia` requires exact symmetry, finite entries and positive definiteness. Its inverse must remain finite and positive definite after conversion to Float32. Failed mass, inertia, shape-pose and center updates leave the old properties unchanged. Shape-pose updates normalize finite quaternions, as body construction does.

The `set_inverse_inertia` method permits an intentional zero inverse along a locked axis. Set up these custom constraints while the body is dynamic. Mode changes retain that finite inverse exactly. Do not pass a singular inertia to `set_inertia` to request a locked axis. A zero inertia and a zero inverse inertia have different meanings.

Tests compare cubes, cuboids, spheres, capsules and tetrahedra with independent solid formulas over several scales. They check translated hulls, transformed centers, tensor rotation, mass scaling, symmetry, positive definiteness and failed-update atomicity. These checks establish a numerical contract. They do not establish physical calibration.

## Apply forces

A caller can use `RigidBody.add_force` and `apply_impulse` without a CARLA actor. `PhysicsWorld.step` consumes forces for one step. A controller must apply its force before each step. `CarlaPhysics.tick` retains external forces across its substeps and rebuilds vehicle forces per substep.

Gravity, buoyancy, wind, muscles or game forces can use this boundary. This extraction adds no force-dispatch framework. Joint constraints remain separate work. The opt-in [sphere/static-mesh continuous mode](Continuous-collision) has an explicit support and precision boundary. Moving-ground tire coupling is described in [CARLA physics](CARLA-physics#moving-supports).

## Free rotational integration

A dynamic body with a symmetric positive-definite inverse tensor follows the coupled Euler equations. Angular velocity remains a world-frame, writable value. The solver reconstructs momentum after forces, damping and contact impulses. It does not keep a hidden momentum cache. Changes to velocity or inertia take effect on the next step.

The free drift uses a second-order symmetric Hamiltonian split. Write the local inverse tensor as A = LDLᵀ. Each column of L supplies one axis. After normalization, energy is a sum of Hᵢ = cᵢ (uᵢ · m)² / 2, where m is local angular momentum. Each term has an exact solution: rotate the pose about uᵢ, and rotate m by the opposite angle. The rate cᵢ (uᵢ · m) stays constant during that term.

The solver applies terms 1, 2, 3, 2, 1 with durations h/2, h/2, h, h/2, h/2. The factorization and rotations use Float64. Pose and angular velocity still store Float32. The solver reconstructs velocity from the final stored pose and the original world momentum. Each such drift performs five rotations. It has no iterative solve, convergence fallback or spin-dependent loop.

This uses the exact-flow splitting principle of [Dullweber, Leimkuhler and McLachlan (1997)](https://www-wales.ch.cam.ac.uk/~andreas/paper/symplectic.html). The LDLᵀ axes need not be orthogonal. This factorization is an implementation choice, rather than a principal-axis eigensolver.

Each subflow preserves world angular momentum in exact arithmetic. The composition has second-order trajectory and energy error at resolved timesteps. It does not exactly preserve energy. For positive-definite A, the preserved momentum norm bounds the energy between its smallest and largest eigenvalues times |m|²/2. This is a stability bound. Large timesteps can still give inaccurate motion and large energy error.

The torque kick has ΔL = h τ before damping. An impulse J at offset r has ΔL = r × J.

Damping keeps the factor 1/(1 + h d), applied before free drift. Contacts keep the same impulse solver. Split impulses remain pose-only contact corrections. They do not change the stored velocity directly; for an anisotropic body, that pose correction can change angular momentum and rotational energy. Free-drift conservation claims exclude those corrections, damping and applied torques.

Isotropic bodies keep the previous normalized-quaternion update and constant torque-free world angular velocity. Kinematic bodies also keep prescribed velocity. A zero angular velocity needs no free drift. Singular, negative or nonsymmetric custom inverse tensors keep the previous prescribed-velocity update. Their finite-entry API remains supported; it does not describe an unconstrained rigid solid. In particular, a locked axis does not have a finite reciprocal inertia.

Float32 pose and velocity impose a precision limit. Tensor conditioning can amplify their rounding error. Positive definiteness alone does not establish that a tensor describes a realizable or calibrated mass distribution. Neither very large spin nor a very ill-conditioned tensor has an unrestricted accuracy guarantee. The resulting pose and velocity must remain representable. Choose a step that resolves the rotation, then check convergence for the intended model.

`test_physics_rotation` checks the original asymmetric-cuboid failure, arbitrary initial orientation and full off-diagonal tensors. Controls include an analytical symmetric top and an independent Float64 RK4 solution of the coupled Euler and quaternion equations. The reference is checked at two resolutions. A thin physical-top control checks that ill-conditioning does not disable gyroscopic motion.

Tests measure maximum momentum and energy errors throughout a 100-second run. They also check second-order refinement, torque and impulse balance, damping, off-center contact, high-spin stability, deterministic repeats and custom-tensor compatibility. Determinism here means repeat runs with the same build and inputs. It does not promise bitwise parity between architectures.

## Disabled collisions

Set `RigidBody.collides` to `False` to leave the primitive contact sweep. For a primitive body, the next step skips its contact-shape transforms and sweep candidate pairs. Set it back to `True` to restore contacts on the next step. The body id stays valid. Forces and motion still integrate.

A disabled body still occupies its body slot. CARLA parks destroyed actors with collisions disabled. This avoids quadratic pair scans between parked bodies, but it does not reclaim their memory. Resource reclamation is tracked in [#306](https://github.com/SethKitchen/ThreeMojo/issues/306).

## Numerical contact boundaries

Convex edge contacts compare differences between support projections. A maximum support vertex stays selected after a large world translation. Contact coordinates still have Float32 resolution. Tests move crossed edges by positive and negative 10 km offsets along each contact axis. Their 3 mm point and depth tolerance allows about three Float32 coordinate steps at 10 km.

These tests do not prove contact accuracy at arbitrary world coordinates. Body positions and contact points still use Float32. A precision-preserving public quantity contract is tracked in [#333](https://github.com/SethKitchen/ThreeMojo/issues/333); a world-origin policy remains a separate design choice.

Material mixing widens the friction product before its square root. This keeps a representable geometric mean finite across the accepted Float32 coefficient range. It does not establish a calibrated material model.

## Verification boundary

The shared solver includes the rotational integration described above. CARLA uses the same implementation. Other known model limitations remain. Shared code is not evidence that a model is validated for an engineering scenario. Select measured inputs, acceptance tolerances and validation cases for each use.

## Static primitive index design

The [static primitive benchmark](https://github.com/SethKitchen/ThreeMojo/blob/main/docs/validation/static-primitive-index-288.md) compares the current sweep with a bounded snapshot BVH. It measures 100, 1,000 and 10,000 static primitives, mixed moving participants and dense ray batches. The report includes allocation costs, brute-force checks and rebuild/refit rules.

The production sweep and existing world ray path stay unchanged. [Owned query snapshots](Physics-query-snapshots) provide an explicit frozen view for repeated rays. They own bounds, narrow geometry, materials, and historical owner identity. Their documented query policy preserves the current narrow-phase answers. The snapshot measurement report separates retained-query savings from capture costs and experimental index results.

## Continuous collision

The opt-in [sphere/static-mesh sweep](Continuous-collision) handles fast, centered dynamic spheres against one-sided static triangles. It supports multiple impacts and transactional failure. Other shapes and interacting moving bodies are refused. The default discrete mode keeps its previous behavior. Read the support, precision and performance limits before use.
