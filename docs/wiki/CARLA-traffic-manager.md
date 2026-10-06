# CARLA traffic manager

`extensions/carla/traffic_manager.mojo` drives the vehicles of a [CARLA world](CARLA-world) as CARLA's traffic manager does. It runs in the same process as the world. Each step reads the world, runs five stages for each registered vehicle and sends one command per vehicle back to the world.

The port follows `LibCarla/source/carla/trafficmanager` at CARLA commit `1360bb9`. It keeps CARLA's formulas, constants, defaults and random draws. The remote traffic manager is not ported, because it is a network transport.

## Modules

| Module | What it gives |
|---|---|
| `traffic_manager` | `TrafficManagerLocal`, `ALSM`, `ActorSet` and the world adapter: `apply_batch`, `set_simulate_physics` and `is_physics_enabled`. |
| `traffic_manager_map` | `InMemoryMap`, `SimpleWaypoint`, `CachedSimpleWaypoint`, `RoadOption`, `SimpleWaypointIndex`, `WaypointId` and `cook`. |
| `traffic_manager_state` | `TrackTraffic`, `SimulationState`, `KinematicState`, `StaticAttributes`, `TrafficActorType` and the path helpers. |
| `traffic_manager_localization` | `LocalizationStage`. |
| `traffic_manager_collision` | `CollisionStage`, `GeometryComparison`, `CollisionLock` and `polygon_distance`. |
| `traffic_manager_planning` | `TrafficLightStage`, `MotionPlanStage` and `VehicleLightStage`. |
| `traffic_manager_parameters` | `Parameters` and `ChangeLaneInfo`. |
| `traffic_manager_pid` | `run_step`, `PIDParameters`, `StateEntry` and `ActuationSignal`. |
| `traffic_manager_random` | `RandomGenerator` and `MersenneTwister`. |
| `traffic_manager_shared` | `TrafficManagerShared`, the frames, `TrafficCommand`, `CommandKind` and `TrafficAction`. |
| `traffic_manager_constants` | The constants of CARLA's `Constants.h`, with their units. |

## Drive vehicles with the traffic manager

The traffic manager needs a world in synchronous mode with a fixed step. Register the vehicles, set the parameters, and call `tick` in place of `world.tick`.

```mojo
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.traffic_manager import TrafficManagerLocal
from extensions.carla.world import EpisodeSettings, World
from units.si import Duration, Length, SECOND

var world = World(load_opendrive_file("assets/carla/town.xodr"))
var settings = EpisodeSettings()
settings.synchronous_mode = True
settings.fixed_delta_seconds = Duration(0.05, SECOND)
_ = world.apply_settings(settings)
var blueprint = world.get_blueprint_library().at("vehicle.lincoln.mkz")
var car = world.spawn_actor(blueprint, world.get_spawn_points()[0])
var tm = TrafficManagerLocal(world, seed=UInt64(42))
tm.set_synchronous_mode(True)
tm.register_vehicles(world, [car])
tm.set_percentage_speed_difference(car, -20.0)
tm.set_distance_to_leading_vehicle(car, Length(5.0))
for _ in range(200):
    _ = tm.tick(world)
```

`tick` ticks the world and then steps the traffic manager, as CARLA's client does. The commands of a step act on the next tick. `step` runs one step without a tick. In asynchronous mode, `step` does nothing on a frame that it already stepped.

The constructor builds the map graph from the world's map. A saved graph from `cook` or `InMemoryMap.save` can go in `cache` instead, which is faster.

## One step

`step` is CARLA's `TrafficManagerLocal::Step`. It does these steps in this order:

1. ALSM, the actor life-cycle manager, updates the tracked actors.
2. The localization stage runs for each vehicle.
3. The collision stage runs for each vehicle.
4. For each vehicle, the traffic-light stage, the motion-planning stage and the vehicle-light stage run.
5. The commands go to the world.

### ALSM

ALSM finds the actors that came and went. It finds the heroes: the vehicles with the role name `hero`. It reads the pose, the speed, the size, the speed limit and the light state of each actor.

- In hybrid mode, a registered vehicle farther than the hybrid radius from every hero moves without physics.
- A registered vehicle slower than 0.8 m/s is idle. After 90 s of idle time, or 180 s at a red light, it is stuck.
- ALSM destroys the stuck vehicle that is idle longest. It destroys one each 10 s at most, and never a hero.
- In Open Street Map mode, ALSM destroys the vehicles whose path ends at a dead end.

The world has no call to turn off an actor's physics. `set_simulate_physics` makes the body kinematic and stops it. The traffic manager then moves the body with teleports.

### Actor lifetime

Temporary unregister and permanent destruction have different effects.

`unregister_vehicles` removes runtime observations, including the cached
physics-enabled flag. It keeps the actor's parameter settings. Registering
the vehicle again makes a new physics decision. This also works when the
caller changed its physics mode while it was unregistered.

Removing an actor from runtime tracking also drops its collision lock and
locks that name it as the lead. This applies to temporary unregister and
the permanent destruction of an observed unregistered actor. Other locks
keep their values. Both collision cycle caches are cleared together because
a surviving boundary or pair distance can depend on a removed lock. A later
update with no candidate cannot retain that removed lead's distance.

Registering a live, observed vehicle preserves collision locks that name it
as the lead. It also preserves both cycle caches until the normal cycle
boundary. Leaving the unregistered list is not actor destruction.

After `world.destroy_actor`, the next processed traffic-manager step removes
the actor's parameter settings. It also removes other actors' collision-ignore
references to that actor. This cleanup includes actors destroyed after
unregister and actors destroyed before the manager first observed them.
Settings for surviving actors stay unchanged. Settings for an actor id that
the world has not issued yet stay pending.

In asynchronous mode, a repeated step on the same frame still does nothing.
Cleanup waits for the next processed step. A stopped manager does not observe
destruction until it steps again.

`stop` and `release` keep parameter settings. `reset(world)` clears all
per-actor settings because an id can name a different actor in the new
episode. Global settings stay configured. Callers that need the same
per-actor settings after reset must set them again.

For direct settings management, `Parameters.configured_actor_ids()` lists
configured owners and collision-ignore targets. `remove_actor(id)` removes
one actor's settings and incoming references. Do not use it for temporary
unregister. `clear_actor_settings()` removes all per-actor settings and keeps
global settings.

This cleanup does not reclaim World actor records, physics bodies or render
resources. Those remain part of
[resource lifetime work](https://github.com/SethKitchen/ThreeMojo/issues/306).

### Localization

The localization stage keeps a path for each vehicle: a list of map nodes, nearest first.

1. It drops a path whose first node is more than 20 m away. It drops the nodes behind the vehicle.
2. It finds a junction entrance: the first node is not in a junction, and the node 5 m on is.
3. It chooses a lane change: a forced one, a random one, a keep-right one, or one around a slower vehicle ahead.
4. It grows the path to the horizon, the speed times 2 s and at least 15 m. A fork takes a random branch, an imported path or an imported route.
5. At a junction entrance, it grows the path past the junction to a safe point 4 m clear of it.

### Collision

The collision stage finds the actor that each vehicle must yield to. The candidates share a geodesic grid with the vehicle's path and are within 20 m plus 2.65 s of its speed. Each candidate is compared by the distances between the two boxes and the two geodesic boundaries. A geodesic boundary is the box plus a strip of the path ahead, as wide as the vehicle.

The pair cache stores the smaller actor id as the reference. Each read returns the distances in the requested actor order. Repeated reads do not change the result. The strip includes the final buffered waypoint when the requested length reaches the end of the path. Clearing the cycle cache or resetting the collision stage drops both cached distances and boundaries.

### Traffic lights and signs

A vehicle at a red or a yellow light stops. At a junction without a light, a vehicle that the world tells to stop joins a queue for the junction. It stops fully, waits 2 s, and goes when it is first in the queue.

### Motion planning

The target speed is the speed limit less the speed difference, or the desired speed. It drops near a light, a sign, a lower limit and in a curve. A hazard ahead sets the target to the other actor's speed while the gap is large. The vehicle brakes fully when the gap is less than 0.2 m.

A vehicle with physics gets throttle, brake and steer from the PID controller. A vehicle without physics moves by its target speed times 0.05 s each step, toward its first node. A dormant vehicle moves to a free place between the respawn bounds from the hero.

### Curve radius and coordinate precision

The turn radius uses the stored Float32 x and y coordinates. It ignores z.
Widened edge lengths and a checked determinant avoid cancellation
from absolute squared world coordinates. For example, the unit circle
through `(1, 0)`, `(0, 1)` and `(-1, 0)` keeps its 1 m radius after a
translation of 10,000 m. The pinned CARLA formula can return 0 m there.

The near-line rule stays absolute: return `FLT_MAX` meters when twice the
absolute plan determinant is at most `EPSILON`, or 2^-22 square meters.
This includes repeated points. A smaller angle alone does not reject a
finite radius.

A proved Float64 error bound handles ordinary triangles. The wide radius
has relative error below 2^-27 before Float32 conversion. Uncertain
comparisons and cancellation use exact Float32 coordinate products,
including cases arbitrarily close to the cutoff. A radius above the
Float32 range also returns `FLT_MAX`.

Translation and uniform scaling preserve the geometric radius when the
stored points preserve the same shape and stay above the cutoff. Scaling
a small triangle across the cutoff changes it to the sentinel by design.
A translation that rounds distinct coordinates together cannot preserve
the original shape. The public coordinate layout remains Float32.

The curve speed uses `sqrt(r * 0.6 * 9.81)` with widened multiplication.
A large representable radius cannot overflow before the square root.
The straight-line sentinel now gives a finite speed of about 4.48e19 m/s.
The motion stage still takes the minimum of this speed, the configured
speed and the landmark speed.

The regression tests use circle, right-triangle and isosceles-triangle
identities, plus an independent perpendicular-bisector reference. Their
new radius and speed ratio checks have absolute tolerance 2e-7. Existing
traffic-manager tolerances and workloads are unchanged.

### Vehicle lights

The stage switches the lights of a vehicle with `set_update_vehicle_lights` on. It switches the brake lights, the blinkers before a turn, and the position, low-beam and fog lights by the weather. The lights are on at night, in heavy rain and in fog.

## The PID controller

`run_step` is CARLA's `PID::RunStep`. The speed error is (target - speed) / target. The heading error is the angle to the target point in half turns. One step gives:

    u = kp e + ki (e + e_prev) dt + kd (e - e_prev) / dt

The step `dt` is 0.05 s. A positive speed command is a throttle of at most 0.85. A negative one is a brake of at most 0.7. The steer moves at most 0.15 per step and stays within 0.8.

| Gains | kp | ki | kd |
|---|---|---|---|
| Speed, at or below 60 km/h | 12.0 | 0.05 | 0.02 |
| Speed, above 60 km/h | 20.0 | 0.05 | 0.01 |
| Heading, at or below 60 km/h | 8.0 | 0.04 | 0.16 |
| Heading, above 60 km/h | 4.0 | 0.04 | 0.08 |

The constructor of `TrafficManagerLocal` takes other gains as arguments.

## Random numbers

All random choices come from one `RandomGenerator`, which gives CARLA's stream for the same seed. It is the 32-bit Mersenne Twister, `mt19937`. A draw is a percentage in [0, 100) from two 32-bit numbers, as the GNU C++ library makes a double. Set the seed in the constructor or with `set_random_device_seed`.

## Parameters

A parameter is global, per vehicle, or both. A per-vehicle value wins over the global value.

| Setter | Default |
|---|---|
| `set_global_percentage_speed_difference`, `set_percentage_speed_difference` | 0 % |
| `set_desired_speed` | none |
| `set_global_distance_to_leading_vehicle`, `set_distance_to_leading_vehicle` | 2 m |
| `set_global_lane_offset`, `set_lane_offset` | 0 m |
| `set_auto_lane_change` | on |
| `set_force_lane_change` | none, used once |
| `set_keep_slow_lane_percentage`, `set_random_left_lane_change_percentage`, `set_random_right_lane_change_percentage` | off |
| `set_percentage_running_light`, `set_percentage_running_sign` | 0 % |
| `set_percentage_ignore_vehicles`, `set_percentage_ignore_walkers` | 0 % |
| `set_collision_detection` | on for each pair |
| `set_update_vehicle_lights` | off |
| `set_global_large_vehicle_wide_turn`, `set_large_vehicle_wide_turn` | on |
| `set_synchronous_mode`, `set_synchronous_mode_time_out` | off, 10 ms |
| `set_hybrid_physics_mode`, `set_hybrid_physics_radius` | off, 70 m |
| `set_respawn_dormant_vehicles`, `set_boundaries_respawn_dormant_vehicles` | off, 100 m to 1000 m |
| `set_osm_mode` | on |
| `set_custom_path`, `set_imported_route` | none |

A negative speed difference makes a vehicle faster than the limit. The setters clamp the values as CARLA does.

## The map graph

`InMemoryMap.set_up` samples each driving lane each 5 m and links the nodes into a graph. It adds nodes where two nodes are too far apart or turn too much. It gives each node a geodesic grid id, a new one each 20 m. A node in a junction has the junction's id as its grid.

Each node has a road option: straight, left or right through a junction, lane follow elsewhere, and road end where the graph ends. `get_waypoint` finds the nearest node with an R-tree.

`save` and `load` use CARLA's binary cache layout. Two things differ from CARLA's file. The node ids count the places from 1, where CARLA uses a hash. A query lists equally near nodes in the order they were made.

## Differences from CARLA

These corrections can change hazard decisions, vehicle controls and paths
compared with a CARLA server. The same seed does not guarantee identical
scenario replay. There is no legacy-bug compatibility mode. The
[contribution rules](https://github.com/SethKitchen/ThreeMojo/blob/main/CONTRIBUTING.md#upstream-behavior-and-correctness)
explain why proven corrections take priority over upstream defects.

- Curve radii are stable under representable translations and scales above the retained near-line cutoff. This corrects the absolute-coordinate cancellation in CARLA `1360bb9`. The widened curve-speed product avoids intermediate overflow. These corrections can change braking and wide-turn decisions on translated maps.

- Collision cache reads preserve the requested actor order. The geodesic boundary includes the final buffered waypoint. These correct two defects in the pinned CARLA source.
- Removing an actor drops its own and incoming collision locks and clears both cycle caches. This includes observed unregistered leads. This correction can change a scenario that depended on a removed lead's distance; actor ids and recording formats are unchanged.

- Graph walks stop at repeated waypoints. A vehicle's path does not add a place already in its buffer, including on later updates. Unreachable imported path points and route options stay pending. A walk trapped in a cycle has no safe point. Later updates retry incomplete junction walks. Fork selection skips branches without an exit and keeps the first branch if none has an exit.
- Stopping or resetting clears actor tracking and transient junction, hero and physics caches. A new map cannot inherit cached waypoint indices from the old one. Stopping keeps parameter settings. Resetting keeps global settings but clears per-actor settings, so a reused id cannot inherit an old actor's preferences.
- Temporary unregister keeps user settings and removes the cached physics-enabled flag. Permanent destruction removes per-actor settings and incoming collision-ignore references on the next processed step. This lifetime policy can change a scenario that depended on stale settings after destruction or reset. Actor id allocation and recording formats are unchanged.
- The remote traffic manager, its server and its client are not ported. They are a network transport.
- Asynchronous mode has no worker thread. The caller calls `step`.
- The world never makes an actor dormant. A caller can mark one with `ACTOR_DORMANT`.
- CARLA walks hash sets in hash order. Here a set of actors is sorted by id.
- Where CARLA reads past the end of an empty list, the port raises an error or stops the walk. Each docstring says which.
- A NaN pedal, which CARLA sends for a desired speed of zero, goes to the world as zero.

### Speed-unit correction

The landmark stage reads a speed signal through its explicit unit. It
compares the configured desired speed and the landmark speed in m/s. This
corrects the mixed-unit comparison in CARLA 1360bb9. For example, a desired
5 m/s stays 5 m/s at the sign, instead of being compared as the number 18.
See [OpenDRIVE speed limits](CARLA-speed-limits) for the checked conversions.
