# CARLA world

`extensions/carla/world.mojo` holds a CARLA world: a map, the actors on it and their physics, stepped in fixed ticks. The vehicles and walkers move by [CARLA physics](CARLA-physics). The traffic lights and signs come from the map's signals and act on the vehicles in their boxes.

The port follows the CARLA source at commit `1360bb9`: `LibCarla/source/carla/client` and `rpc` for the API and the records. The traffic lights and signs, the blueprint definitions and the weather ranges come from CARLA's simulator plugin, in `Carla/Traffic`, `Carla/Actor`, `Carla/Game` and `Carla/Weather`. See [CARLA maps](CARLA-maps) for the map and [CARLA geometry](CARLA-geometry) for the frame.

## Modules

| Module | What it gives |
|---|---|
| `world` | `World`, `EpisodeSettings` and `LabelledPoint`. |
| `world_snapshot` | `WorldSnapshot`, `ActorSnapshot`, `Timestamp` and `TrafficLightData`. |
| `actor` | `ActorId`, `ActorKind`, `ActorState`, `AttachmentType`, `TrafficLightState` and the `Actor` record. |
| `vehicle` | `VehicleLightState`, `VehicleDoor`, `VehicleWheelLocation`, `VehicleData` and the vehicle models. |
| `walker` | `WalkerBoneControlIn`, `WalkerBoneControlOut` and the walker record. |
| `traffic_light` | `TrafficLightController`, `TrafficLightGroup`, `TrafficLight` and `TrafficLightManager`. |
| `traffic_sign` | `TrafficSign`, `TriggerBox` and the box builders. |
| `blueprint` | `ActorAttribute`, `ActorBlueprint`, `BlueprintLibrary` and the catalog. |
| `weather` | `WeatherParameters` and CARLA's 23 presets. |

## Build a world and step it

A world takes a map. Its road and sidewalk surfaces become static colliders. The ticks need a fixed step.

```mojo
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.world import EpisodeSettings, World
from units.si import Duration, SECOND

var world = World(load_opendrive_file("assets/carla/town.xodr"))
var settings = EpisodeSettings()
settings.synchronous_mode = True
settings.fixed_delta_seconds = Duration(0.05, SECOND)
_ = world.apply_settings(settings)
var frame = world.tick()
var snapshot = world.get_snapshot()
```

The world is an entity registry. Each actor has an `ActorId`, from 1 up. The spectator is actor 1, and the traffic lights and signs follow it. An operation on an actor is a method of the world that takes the id.

### One tick

`tick` is a fixed-step game loop. It does these steps in this order:

1. The frame counts up, and the time moves on by `fixed_delta_seconds`.
2. The give-way timers of the stop and yield signs run down.
3. The traffic-light groups advance their cycles.
4. The physics steps. The tick is cut into the fewest substeps no longer than `max_substep_delta_time`, and into `max_substeps` at most.
5. The world finds the road boxes that each vehicle is in. It tells the lights and signs about each vehicle that came or went.
6. The world takes its snapshot.

### Signal ids in snapshots

A snapshot holds at most 32 UTF-8 bytes of each traffic light or sign id. This is a byte limit, not a character count. If the 32-byte limit would split a codepoint, the snapshot ends before that codepoint. The result stays valid UTF-8. An ASCII id keeps its first 32 characters.

The world keeps the full OpenDRIVE id. `get_opendrive_id` and `get_traffic_light_from_opendrive` use that full id. Only the snapshot field is shortened. Recording and replay can tick a world with these ids; their actor records use actor ids and positions rather than snapshot sign strings.

## Spawn and control actors

`spawn_actor` takes a blueprint from the world's library and a transform. A `vehicle.*` blueprint makes a vehicle and a `walker.*` blueprint makes a walker. A `sensor.*`, `static.*`, `util.*` or `controller.*` blueprint makes an actor with no body.

```mojo
from extensions.carla.physics.vehicle_control import VehicleControl
from math.vector3 import Vector3

var blueprint = world.get_blueprint_library().at("vehicle.lincoln.mkz")
var car = world.spawn_actor(blueprint, world.get_spawn_points()[0])
var camera_bp = world.get_blueprint_library().at("sensor.camera.rgb")
var mount = world.get_transform(car)
mount.location = Vector3(1.5, 0, 2.4)
var camera = world.spawn_actor(camera_bp, mount, car)
var control = VehicleControl()
control.throttle = 0.5
world.apply_control(car, control)
```

A spawn fails when the new vehicle's or walker's box meets the box of another vehicle or walker. `try_spawn_actor` returns None instead. A failed spawn leaves the actor and physics lists unchanged and does not consume an actor id. Required vehicle attributes are checked before the world adds a body. A sensor or a prop can have a parent, and then its transform is in the parent's frame.

The spawn points are the start of each lane of the map's topology, 0.5 m above the road. CARLA makes them so for a map that has none placed.

### What an actor gives

| Question | Method |
|---|---|
| Where is it? | `get_transform`, `get_location`, `get_bounding_box` |
| How does it move? | `get_velocity`, `get_angular_velocity`, `get_acceleration` |
| Move it | `set_transform`, `set_location`, `set_target_velocity`, `set_target_angular_velocity` |
| Push it | `add_impulse`, `add_force`, `add_torque`, `add_angular_impulse`, `set_enable_gravity` |
| Drive a vehicle | `apply_control`, `apply_ackermann_control`, `apply_physics_control`, `enable_constant_velocity` |
| Read a vehicle | `get_control`, `get_telemetry_data`, `get_physics_control`, `get_failure_state`, `get_wheel_steer_angle` |
| A vehicle's lights and doors | `set_light_state`, `get_light_state`, `open_door`, `close_door`, `is_door_open` |
| A vehicle's signals | `get_speed_limit`, `get_traffic_light_state`, `is_at_traffic_light`, `get_traffic_light` |
| Move a walker | `apply_walker_control`, `get_walker_control` |
| A walker's bones | `set_bones_transform`, `get_bones_transform`, `blend_pose` |

An actor also carries the data that the renderer and the sensors read. The data is its blueprint id, its attributes, such as `color`, its bounding box and its semantic tags.

The velocity is in m/s. The angular velocity is in degrees per second, as CARLA reports it. The acceleration is the change of the velocity since the last tick, over the tick.

## Traffic lights

A light belongs to a controller, and a controller belongs to a group, one group for each junction. The world places each traffic-light signal that a controller holds. It also places each traffic-light signal outside a junction that no controller holds. That light gets its own group and controller, with a red stage of 10 s.

A controller runs its stages in turn: 10 s green, 3 s yellow and 2 s red. A group runs its controllers in turn. While one controller runs its cycle, the lights of the others stay red.

A stage changes on the first tick that takes the elapsed time past the stage's time. The elapsed time then starts again from zero. With 0.25 s ticks, green changes to yellow on tick 41, because 40 ticks give exactly 10 s.

| Question | Method |
|---|---|
| The state | `get_traffic_light_state_of`, `set_traffic_light_state` |
| The times | `get_light_time`, `set_light_time`, `get_elapsed_time` |
| Stop the clock | `freeze`, `freeze_all_traffic_lights`, `is_frozen` |
| Start again | `reset_group`, `reset_all_traffic_lights` |
| The group | `get_group_traffic_lights`, `get_traffic_lights_in_junction` |
| The lanes | `get_affected_lane_waypoints`, `get_stop_waypoints`, `get_trigger_volume` |

`set_traffic_light_state` sets one light. The controller does not know, and its next stage sets the light again. `freeze` stops every light, as in CARLA.

### A light's boxes

Each lane that a light holds gets a box 3 m before the light, against the lane's traffic. The box is 3 m long, half a lane wide and 2 m high. On a junction lane with one predecessor outside the junction, the box moves to that predecessor.

A vehicle that enters a box takes the light's state, and each change of the light reaches it at once. A vehicle is told green again after leaving the last occupied box of that light. The light's internal vehicle list has one entry per occupied box, so duplicate vehicle ids there are intentional.

### Trigger offset direction

The box center moves against the resolved lane's travel direction. Right-hand negative lanes and left-hand positive lanes travel with increasing s. Their offsets subtract from s. The other lanes add to s.

A light, stop or yield box uses a 3 m offset. A speed-limit box uses its half size. Each center stays inside its lane section, at least 0.00001 m from either end. A section shorter than 0.00002 m uses its midpoint instead. An offset does not cross a section boundary.

The direction belongs to the waypoint that receives the box. A junction reference can move the box to a predecessor with a different lane id or road rule.

At s = 50 on left-hand lane 1, the light box center is s = 47. The old lane-sign rule put it at s = 53. Left-hand scenario replay can therefore enter the box earlier. Existing right-hand results stay the same when a predecessor does not change the lane sign.

## Traffic signs

The world places a stop sign for each signal of type 206, except the painted "Stencil_STOP". It places a yield sign for type 205. It places a speed-limit sign for type 274 with a subtype from 30 to 120 in steps of ten.

- A speed-limit box gives the vehicle the sign's limit. The limit stays after the vehicle leaves. Before any box, the limit is 30 km/h.
- A stop sign's effect box tells a vehicle red. After 2 s, the sign lets the vehicle go if its check boxes are empty. Otherwise it checks again after 1 s.
- A yield sign checks at once, and again after 0.5 s.
- A vehicle that leaves a check box starts a check after 0.5 s.

The check boxes cover each junction road that crosses the sign's road and does not come from the same road. They are cubes 0.9 of a lane wide, along the road. They also reach back along the lanes before it, for 0.1 s at the road's speed.

The delayed checks are a scheduled-callback queue in each sign. A timer fires on the first tick that brings it to zero or below.

## Blueprints

`BlueprintLibrary` holds CARLA's blueprints, sorted by id. `filter` keeps the blueprints whose id or tag matches a shell wildcard, as `fnmatch` matches it. `filter_by_attribute` keeps the blueprints that offer a value.

An attribute keeps its value as text, as CARLA does. `as_bool`, `as_int`, `as_float`, `as_string` and `as_color` read it. A number reads as C's `atoi` and `atof` read it, so "3.5f" is 3.5. A modifiable attribute starts at its first recommended value.

The library has these blueprints:

- The cameras (RGB, depth, semantic and instance segmentation, optical flow, normals, DVS) and the fisheye forms of the first four.
- The three LiDARs, the radar, GNSS, IMU, collision, lane-invasion and obstacle sensors, and the two V2X senders.
- The 12 vehicles and 37 pedestrians of CARLA's catalogs.
- `controller.ai.walker`, `static.trigger.friction`, `static.prop.mesh` and `util.actor.empty`.

The sensor attributes and their defaults are CARLA's. CARLA keeps its vehicle and pedestrian models as assets, and some of their data is not published. This port chooses these values:

- Five colors for every vehicle.
- A box for each vehicle base type: a car is 4.8 m long, 2.0 m wide and 1.5 m high.
- CARLA's default `VehiclePhysicsControl` on four wheels in that box.
- The gender "other", the generation 2 and the speeds 0, 1.4 and 2.8 m/s for each pedestrian.

## Weather

`WeatherParameters` is data. The renderer reads it. The fields, the defaults and the 23 presets, such as `ClearNoon` and `HardRainNight`, are CARLA's. `weather_preset` returns a preset by name.

The sun's angles are `Angle`s and the fog distance is a `Length`. The other fields are percentages or plain factors. `clamped` puts each field in CARLA's range. `rain_screen_weight` and `dust_screen_weight` give the strength of the rain and dust effects on a camera image.

## What the port reuses

- The physics tier's `CarlaPhysics` simulates the vehicles and walkers, and its ray cast answers `project_point` and `ground_projection`.
- `mesh_factory.generate_mesh` gives the road and sidewalk colliders. `map.Map` gives the signals, the controllers, the lanes and the topology.
- A box in the world is a `math.obb.OBB`, and `intersects_obb` tests a vehicle against a light's or a sign's box.
- An actor's box is a `bounding_box.BoundingBox`. A pose is a `transform.CarlaTransform`.
- A color attribute reads as a `render.framebuffer.Color`, and a semantic tag is a `sensor.SemanticTag`.
- `math.generate_range` walks a signal's lanes, as CARLA's `Math::GenerateRange` does.

## Differences from CARLA

- There is no server and no client, so a method returns at once. A world has no asynchronous mode and no wall clock. `tick` needs `fixed_delta_seconds`.
- A spawn checks only against vehicles and walkers, not against the road or props.
- A vehicle or a walker cannot have a parent. A spring-arm attachment follows its parent rigidly.
- The physics world cannot remove a body. A destroyed vehicle's or walker's body waits far below the map, with no collisions.
- Traffic lights, signs and the spectator cannot be destroyed. The children of a destroyed actor stay where they were.
- An actor without a body reports zero velocity and zero acceleration.
- A light with no OpenDRIVE controller reads as zero in CARLA, because CARLA does not tell its controller the group. Here that light reports its state.
- CARLA `1360bb9` [offsets sign boxes by lane sign alone](https://github.com/carla-simulator/carla/blob/1360bb9/Unreal/CarlaUnreal/Plugins/Carla/Source/Carla/Traffic/TrafficLightComponent.cpp#L74-L84). This port uses the resolved lane direction and keeps centers inside short sections. See [Trigger offset direction](#trigger-offset-direction).
- CARLA keeps the blueprints, groups and actors in hash maps. This port keeps them in a fixed order.
- A walker's bones are data only. There is no skeleton, and each bone hangs from the walker's origin.
- A hexadecimal float in an attribute reads as zero, where C reads it in full.

## Not ported

- The network and the episode transport: the client and the server run in one process here.
- The on-tick callbacks, the map layers, the environment objects, the textures and the light manager.
- `cast_ray` and `set_simulate_physics`, because the physics tier has no ray that passes through a hit and no way to change a body's kind.
- The props of `static.prop.*` and the vehicle models' meshes, which are assets. The render tier draws its own.
- The RSS sensor, which needs a third-party library.

## Tests

The world suites check numbers from outside the port:

- `tests/test_carla_world_blueprint.mojo`: the wildcard, `atoi` and `atof` results of glibc, the sensor attributes read out of CARLA's C++ by a script, and CARLA's weather table.
- `tests/test_carla_world_signals.mojo`: a cross town with lights, stop, yield and speed-limit signs. The poses of the lights and boxes are worked by hand. The light cycles and the stop sign's checks come from Python models of CARLA's C++.
- `tests/test_carla_trigger_direction.mojo`: both lane signs under right-hand and left-hand traffic, section clamps, predecessor changes, and world trigger entry and exit.
- `tests/test_carla_world.mojo`: the settings, spawning, attachments, destroying, a free fall, pushes, vehicle controls, walkers and the snapshot.
