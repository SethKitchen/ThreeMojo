# CARLA physics

`extensions/carla/physics/` simulates CARLA's actors: rigid bodies with contacts and friction, wheeled vehicles driven by `VehicleControl`, and walkers driven by `WalkerControl`. The physics engine is the port's own. It takes CARLA's field names, defaults and controllers, and it gives the results that mechanics predicts.

The port follows the CARLA source at commit `1360bb9`. The records come from `LibCarla/source/carla/rpc`. The controllers come from the `Carla/Vehicle` and `Carla/Walker` sources of CARLA's simulator plugin. No game-engine source code is ported. See [CARLA](CARLA) for the frame and the roads.

The rigid-body core lives in [Shared physics](Physics). Its CARLA import paths remain compatible.

## Modules

| Module | What it gives |
|---|---|
| `quantities` | `Torque`, `Energy`, `Momentum`, `Stiffness`, `DampingRate`, `CorneringStiffness`, `Jerk`, and units such as `REVOLUTION_PER_MINUTE` and `MILE_PER_HOUR`. |
| `shape` | `Shape`: sphere, box, capsule, convex hull and static mesh. `PhysicsMaterial`, `Polyhedron`, mass properties. |
| `body` | `RigidBody`: six degrees of freedom, static, dynamic or kinematic. `BodyId`, `BodyKind`. |
| `collide` | The narrow phase: the contact points of two shapes. |
| `world` | `PhysicsWorld`: the fixed step, the broad phase, the contact solver, ray casts and collision events. |
| `vehicle_physics` | `VehiclePhysicsControl` and `WheelPhysicsControl`, with CARLA's defaults. |
| `vehicle_control` | `VehicleControl`, `VehicleAckermannControl`, `AckermannControllerSettings`, the telemetry records, and CARLA's `AckermannController`. |
| `wheeled_vehicle` | `WheeledVehicle`: the chassis, the ray-cast suspension, the engine, the gearbox and the tires. |
| `walker` | `Walker`, `WalkerControl` and `WalkerParameters`: a kinematic character controller. |
| `simulation` | `CarlaPhysics`: one world with its vehicles and walkers, and `carla_transform`. |

## What the port reuses

- Positions, velocities and directions are `math.vector3.Vector3`, in meters. Orientations are `math.quaternion.Quaternion`, and inertia tensors are `math.matrix3.Matrix3`.
- A convex hull comes from `math.convex_hull.ConvexHull`. The port merges its coplanar triangles into faces.
- The static meshes go into one `math.octree.Octree`. A moving shape asks it for the triangles near it, and a ray asks it for the triangles on its path.
- A sphere or a capsule against a mesh triangle uses `triangle_sphere_intersect` and `triangle_capsule_intersect` from `math.octree`.
- The nearest points of two segments come from `math.triangle.Line3.closest_points_to_line`. The nearest point of a face comes from `Triangle.closest_point_to_point`.
- A ray is a `math.ray.Ray`. A sphere and a mesh triangle use its tests. A box, a hull and a capsule use the port's own tests, because they need the surface normal.
- The walker's capsule is a `math.capsule.Capsule` when it meets a mesh.
- A pose from CARLA is a `CarlaTransform` from `extensions/carla/transform.mojo`. `Quaternion.from_matrix` turns its matrix into the body's rotation.
- The torque, speed and slip units extend `units.si`.

`core/raycaster` is not used. It casts rays through a scene graph of meshes, and the physics world has no scene graph.

## Step a world

`CarlaPhysics.tick` advances the world by CARLA's `fixed_delta_seconds`. It can cut the step into substeps. Each substep updates every vehicle and walker, and then steps the world. External forces and torques applied before the tick act through every substep. They are cleared after the tick.

The [tick-force benchmark](Tick-force-restoration) retains all-body snapshots after comparing dynamic-only alternatives. Static and kinematic forces are consumed without acceleration. Ghost dynamic bodies still receive their forces.

```mojo
from extensions.carla.physics.shape import PhysicsMaterial
from extensions.carla.physics.simulation import CarlaPhysics
from units.si import Duration, SECOND

var sim = CarlaPhysics()
var road = sim.add_static_mesh(triangles^, PhysicsMaterial.default())
sim.tick(Duration(0.05, SECOND), 2)
for event in sim.events:
    print(event.body.value, event.other.value, event.normal_impulse.x)
```

Each mesh triangle is solid from its front: the side where (b − a) × (c − a) points. A shape behind a triangle does not touch it.

`sim.events` holds the collision events of the last tick. An event gives the body, the other body and the impulse that the other body gave. That is the data of CARLA's collision sensor.

## Drive a vehicle

`add_vehicle` spawns a chassis body from a transform, a bounding box and a `VehiclePhysicsControl`. The bounding box is in the vehicle's frame. The chassis collider starts at the lowest wheel center, so that the wheels and not the box touch the road.

```mojo
from extensions.carla.physics.vehicle_control import VehicleControl

var car = sim.add_vehicle(transform, box_center, box_extent, physics^)
var control = VehicleControl()
control.throttle = 0.6
sim.apply_vehicle_control(car, control)
sim.tick(Duration(0.05, SECOND), 2)
var telemetry = sim.telemetry(car)
```

`apply_ackermann_control` hands the pedals to CARLA's Ackermann controller. A later `apply_vehicle_control` turns the controller off and resets it, as in CARLA. `apply_physics_control` replaces the setup, and it must keep the number of wheels.

The world worker can also call `WheeledVehicle.update` and `PhysicsWorld.step` directly. `update` must run before each step.

### The order of one vehicle update

1. The Ackermann controller, when it is active, writes the control.
2. A change of `reverse` selects gear −1 or 1 at once. Otherwise `manual_gear_shift` selects `gear` at once. This is CARLA's `ProcessControl`.
3. Each wheel casts a ray along its suspension axis. The spring force is the spring rate times the compression from full drop, plus the preload, plus a damper.
4. The engine locks to the driven wheels while a gear is engaged. The automatic gearbox shifts at `change_up_rpm` and `change_down_rpm`.
5. The tires make their forces inside the friction circle. The tires are solved together, with projected Gauss-Seidel.
6. The air drag and the downforce act at the center of mass.
7. CARLA's rollover behavior damps the spin of a car that rolls past 130 degrees.

### The units of CARLA's fields

CARLA's setup records keep lengths in centimeters. Some fields have no written unit. The port chooses these units, and the defaults agree with them: four default springs hold a 1000 kg car at their drop limit.

| Field | Unit in the port | CARLA default |
|---|---|---|
| `wheel_radius`, `suspension_max_raise`, `suspension_max_drop` | `Length` | 30 cm, 10 cm, 10 cm |
| `spring_rate` | `Stiffness` in N/cm | 250 N/cm |
| `spring_preload` | `Force` | 50 N |
| `cornering_stiffness` | `CorneringStiffness` in N/deg | 1000 N/deg |
| `max_brake_torque`, `max_hand_brake_torque`, `max_torque` | `Torque` | 1500, 3000, 300 N m |
| `max_rpm`, `idle_rpm`, `change_up_rpm`, `change_down_rpm` | `AngularVelocity` in rpm | 5000, 1, 4500, 2000 rpm |
| `brake_effect` | `Torque` of engine braking at the largest engine speed | 1 N m |
| `rev_down_rate` | `AngularAcceleration` in rpm/s | 600 rpm/s |
| `steering_curve` x | forward speed in km/h, the unit of CARLA's speed limits | (0, 1), (10, 0.5) |
| `torque_curve` | rpm against N m, limited to `max_torque` | (0, 500), (5000, 500) |

A tire's grip is `friction_force_multiplier` times the friction of the ground's material. Its load blends an equal share of the weight with the spring force, by `wheel_load_ratio`.

### What a vehicle does

- A brake holds the wheel like static friction, up to its torque over the wheel radius. If that is more than the tire's grip, the wheel locks and slides. With `abs_enabled` it does not lock.
- A driven wheel whose drive passes its grip spins, up to `max_wheelspin_rotation` faster than the ground. With `traction_control_enabled` it does not spin.
- The side force stops the slide across the tire, up to the cornering stiffness times the slip angle.
- Without a throttle, the engine brakes the car a little. Out of gear, the engine revs against `rev_up_moi`.
- The differential follows `differential_type`: each wheel with `affected_by_engine`, all wheels with `front_rear_split`, the front axle, or the rear axle.

### Moving supports

Tire slip and wheel spin use motion relative to the support surface.
At a contact point, each body's velocity is `v + omega cross r`.
Here, `r` runs from that body's center of mass to the contact point.
The tire solver subtracts the support velocity from the chassis velocity.
It predicts both bodies' pending gravity, force, torque and damping kicks.

Both bodies' mass and world inertia determine the tire's effective mass.
Each incremental impulse updates both predicted states.
Wheels on the same support share its prediction.
Each final wheel force and its opposite reaction are added once.
Static and kinematic supports have no impulse response.
A moving kinematic support can supply work through its prescribed motion.

The solver keeps eight passes and the existing tire force limits.
It solves one vehicle's wheels at a time.
It does not predict later aerodynamic forces or collision impulses.
For physical inertia in a closed finite-mass pair without drive, braking
does not increase kinetic energy. It preserves total linear and angular
momentum within rounding.
World damping, external forces and engine torque can change these totals.

A uniform translation leaves the tire result unchanged when the tire
directions and relative motion stay the same.
Air drag still uses world velocity in still air.
Chassis speed telemetry and the controller's speed input remain world
quantities. They do not become wheel rolling speed.

The relative-velocity and effective-mass equations follow rigid-body
impulse mechanics. See [Catto's sequential-impulse derivation, slides
18–24](https://box2d.org/files/ErinCatto_SequentialImpulses_GDC2006.pdf).
The focused tests also use independent scalar impulse calculations.

## Walk a walker

`add_walker` spawns a capsule at a location. `apply_walker_control` takes a direction, a speed and a jump.

```mojo
from extensions.carla.physics.walker import WalkerControl, WalkerParameters
from units.si import Velocity

var walker = sim.add_walker(Vector3(10, 2, 1), WalkerParameters())
var control = WalkerControl()
control.speed = Velocity(1.4)
sim.apply_walker_control(walker, control)
```

The walker is a kinematic character controller of the port's own design. CARLA's walker controller gives the semantics: the walker goes along the control's direction at the control's speed, capped at CARLA's 40.96 m/s, and `jump` jumps. CARLA allows two jumps before the walker lands, so a second press in the air jumps again.

Each step, nine rays look down for a floor: one at the axis and eight around the rim. A floor must be no higher than the step height above the feet, and no steeper than the slope limit.

On the ground, the horizontal velocity moves straight toward the target. The change in one step is at most the acceleration times the step, or the braking deceleration times the step when there is no input. The ground's friction caps both at μg, so a walker on ice starts and stops slowly. The walker follows the floor's plane, so it keeps its horizontal speed on a slope, steps up a curb and steps down a step. In the air, gravity pulls it, and input steers it at a fraction of the ground rate. A walker that falls to the floor snaps onto it and does not bounce.

| Setting | Default | Source |
|---|---|---|
| `radius`, `half_height`, `mass` | 0.25 m, 0.9 m, 75 kg | Adult body-size surveys: a stature of 1.6 to 1.9 m, a shoulder breadth of 0.4 to 0.5 m, a mass of 60 to 90 kg. |
| `max_acceleration` | 1 m/s² | Gait studies: 0.5 to 1.5 m/s² when a pedestrian starts to walk. |
| `braking_deceleration` | 2 m/s² | Gait studies: a stop from walking speed in one or two steps. |
| `max_step_height` | 0.3 m | Building codes cap a stair riser at about 0.2 m, and a curb is 0.1 to 0.2 m high. |
| `max_slope` | 35° | Past about 30 to 35 degrees, a slope is a scramble and not a walk. |
| `jump_speed` | 3 m/s | A lift of about 0.46 m, near an adult's standing vertical jump of 0.4 to 0.5 m. |
| `air_control`, `skin` | 0.2, 1 cm | Design choices: a little steering in a fall, and a gap that keeps resting contacts steady. |
| `max_speed`, `jump_max_count` | 40.96 m/s, 2 | CARLA's walker controller. |

The capsule is a dynamic body that does not turn. A vehicle or a prop pushes it. The controller then brings the velocity back toward the target.

## Rigid bodies and contacts

A body has one shape, placed in the body's frame. A dynamic body gets the mass properties of its solid shape. The inertia of a hull is exact, from signed tetrahedra.

One step of `PhysicsWorld` does this:

1. Gravity, forces and damping change the velocities.
2. Sweep and prune pairs the moving shapes. The octree gives the mesh triangles near each one.
3. The narrow phase gives the contact points. Two polyhedra use the separating-axis test and clip the incident face. A sphere or a capsule meets a polyhedron at the minimum of its signed distance.
4. Sequential impulses solve the contacts, with Coulomb friction in a cone.
5. A second pass gives the restitution to each point that hit faster than 1 m/s, Box2D's restitution threshold.
6. Split impulses push overlapping bodies apart without adding energy.
7. The velocities move the bodies.

A contact can have a gap of up to 2 cm. The solver lets the bodies close the gap and no more, so a fast body stops at a surface and not in it. Two materials use the geometric mean of the frictions and the larger restitution, as Box2D mixes them. The default material is Box2D's: a friction of 0.6 and a restitution of 0. The damping is Box2D's implicit damping, and it is 0 by default. The gravity is 9.8 m/s², standard gravity rounded.

## Ray casts

`PhysicsWorld.raycast` and `CarlaPhysics.raycast` give the nearest shape on a ray, within a distance. The hit has the body, the point, the surface normal, the distance and the surface material. A ray can ignore one body, such as the body that casts it.

## Differences from CARLA

- The physics engine is the port's own. The tire, spring, engine and walker models are the ones described above.
- The shared world has an opt-in [sphere/static-mesh continuous mode](Continuous-collision). It refuses unsupported shapes and interacting moving bodies. Vehicle chassis and capsule walkers remain outside this mode. Discrete mode is unchanged.
- The moving-support tire correction changes replay from the port at `af6c253`. A car and platform moving together at 10 m/s previously produced about −20000 N of braking with zero relative motion. The corrected force is zero when aerodynamic forces are disabled. This is a correction to the port's model. It does not claim identical CARLA trajectories.
- `SPHERECAST` and `SHAPECAST` wheels cast a ray, as `RAYCAST` wheels do.
- `lateral_slip_graph`, `suspension_smoothing`, `sleep_threshold` and `sleep_slope_limit` are kept for CARLA's API, and the model does not read them. Bodies do not sleep.
- `WheelPhysicsControl`'s run-time fields `wheel_index`, `location`, `old_location` and `velocity` are not part of the setup. `WheelState` reports the location and the velocity.
- The front wheels turn by one angle. The inner wheel does not turn more than the outer wheel.
- The chassis has no linear damping, because the air drag is modeled on its own.
- There are no joints, so vehicle doors do not swing.

## Tests

The four suites `tests/test_carla_physics_bodies.mojo`, `_world.mojo`, `_vehicle.mojo` and `_walker.mojo` check the behavior against mechanics worked by hand:

- A free fall, the velocities after an elastic and a plastic hit, and the conservation of linear and angular momentum.
- The rebound height from the restitution.
- A box that holds on a slope, and a box that slides with a = g (sin θ − μ cos θ).
- The spring compression that holds the weight, and the stopping distance from a brake torque or from the tire grip.
- The speeds of the gear changes, and the top speed at the engine's limit and against the drag.
- The roll down a slope, with and without the handbrake.
- The yaw rate of a steered car, the Ackermann controller's steps and its convergence, and CARLA's rollover behavior.
- The walker's speed, braking, turning, traction limit, slope, curb, step, wall, landing, jump height and double jump.

`tests/test_carla_moving_supports.mojo` checks uniform translations,
common rigid rotation and accelerating supports. It also checks coupled
off-center mass, shared supports and separate finite supports.
Other controls check forward and reverse traction, braking energy loss,
momentum conservation and the still-air distinction.

### Tire benchmark

`bench/carla_moving_supports_bench.mojo` measures three four-wheel tire solves.
The support can be static, one moving body or four moving bodies.
Each case has 5000 warm-up solves and 500000 measured solves.
The checksum consumes chassis force and every wheel's speed on each iteration.

Build the same benchmark source against each implementation before comparison.
Use the same CPU and balanced variant order when possible.
These costs exclude suspension ray casts and the world's contact solve.
