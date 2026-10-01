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

The `extensions/carla/physics/` paths for these five modules remain valid. They import the shared definitions. They do not copy the solver or wrap its types. A body made through either path can enter the same world.

Vehicle setup, wheel forces, CARLA controls, the walker controller and `CarlaPhysics` stay in `extensions/carla/physics/`. They are domain models and tick orchestration. The [CARLA physics](CARLA-physics) page describes them.

## Frames and units

Choose one frame for a world. Express every position, shape, gravity vector, velocity, force and torque in that frame. The default gravity remains (0, 0, -9.8) m/s² for compatibility. A y-up simulation can set gravity to (0, -9.8, 0).

Lengths, masses, durations and other scalar quantities use `units.si` and `units.quantity`. Vector and matrix fields hold SI numbers in `Vector3` and `Matrix3`. Their docstrings give the units. The vector type does not enforce those dimensions.

Keep frame conversion at the domain boundary. For an orthogonal basis R, a center becomes R c and an inertia tensor becomes R I Rᵀ. Keep all six independent entries of the symmetric tensor. A reflection also changes the sign rule for axial vectors such as angular velocity and torque: they use det(R) R. Do not treat a y/z swap as an ordinary rotation.

## Use anatomy mass properties

`SegmentInertia` gives mass, center and the six tensor entries for a limb segment. These entries are about its center of mass in the leg frame. The off-diagonal values already have the tensor sign.

Create the collision shape separately. Set the body's mass, center of mass and inertia from the physical model. Transform the center and the full tensor into the body's frame first. If the reference point changes, apply the parallel-axis theorem. Display mesh thickness must not set physical mass.

`tests/test_shared_physics.mojo` checks this handoff with an authored segment tensor. It does not claim a whole-body physical rig. The current anatomy code supplies no joint solver or muscle-force controller.

## Apply forces

A caller can use `RigidBody.add_force` and `apply_impulse` without a CARLA actor. `PhysicsWorld.step` consumes forces for one step. A controller must apply its force before each step. `CarlaPhysics.tick` retains external forces across its substeps and rebuilds vehicle forces per substep.

Gravity, buoyancy, wind, muscles or game forces can use this boundary. This extraction adds no force-dispatch framework. Joint constraints, continuous collision detection, improved angular integration and moving-ground tire coupling remain separate work.

## Disabled collisions

Set `RigidBody.collides` to `False` to leave the primitive contact sweep. For a primitive body, the next step skips its contact-shape transforms and sweep candidate pairs. Set it back to `True` to restore contacts on the next step. The body id stays valid. Forces and motion still integrate.

A disabled body still occupies its body slot. CARLA parks destroyed actors with collisions disabled. This avoids quadratic pair scans between parked bodies, but it does not reclaim their memory. Resource reclamation is tracked in [#306](https://github.com/SethKitchen/ThreeMojo/issues/306).

## Verification boundary

The extraction changes import paths, not the numerical solver. Existing CARLA behavior and its known limitations remain. Shared code is not evidence that a model is validated for an engineering scenario. Select measured inputs, acceptance tolerances and validation cases for each use.
