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

Tests compare cubes, cuboids, spheres, capsules and tetrahedra with independent solid formulas over several scales. They check translated hulls, transformed centers, tensor rotation, mass scaling, symmetry, positive definiteness and failed-update atomicity. These checks establish a numerical contract. They do not establish physical calibration or add torque-free gyroscopic dynamics.

## Apply forces

A caller can use `RigidBody.add_force` and `apply_impulse` without a CARLA actor. `PhysicsWorld.step` consumes forces for one step. A controller must apply its force before each step. `CarlaPhysics.tick` retains external forces across its substeps and rebuilds vehicle forces per substep.

Gravity, buoyancy, wind, muscles or game forces can use this boundary. This extraction adds no force-dispatch framework. Joint constraints, continuous collision detection, improved angular integration and moving-ground tire coupling remain separate work.

## Disabled collisions

Set `RigidBody.collides` to `False` to leave the primitive contact sweep. For a primitive body, the next step skips its contact-shape transforms and sweep candidate pairs. Set it back to `True` to restore contacts on the next step. The body id stays valid. Forces and motion still integrate.

A disabled body still occupies its body slot. CARLA parks destroyed actors with collisions disabled. This avoids quadratic pair scans between parked bodies, but it does not reclaim their memory. Resource reclamation is tracked in [#306](https://github.com/SethKitchen/ThreeMojo/issues/306).

## Numerical contact boundaries

Convex edge contacts compare differences between support projections. A maximum support vertex stays selected after a large world translation. Contact coordinates still have Float32 resolution. Tests move crossed edges by positive and negative 10 km offsets along each contact axis. Their 3 mm point and depth tolerance allows about three Float32 coordinate steps at 10 km.

These tests do not prove contact accuracy at arbitrary world coordinates. Body positions and contact points still use Float32. A precision-preserving public quantity contract is tracked in [#333](https://github.com/SethKitchen/ThreeMojo/issues/333); a world-origin policy remains a separate design choice.

Material mixing widens the friction product before its square root. This keeps a representable geometric mean finite across the accepted Float32 coefficient range. It does not establish a calibrated material model.

## Verification boundary

The extraction changes import paths, not the numerical solver. Existing CARLA behavior and its known limitations remain. Shared code is not evidence that a model is validated for an engineering scenario. Select measured inputs, acceptance tolerances and validation cases for each use.
