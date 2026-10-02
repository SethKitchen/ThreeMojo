# CARLA recorder

The recorder writes a [CARLA world](CARLA-world) to a log file in CARLA's own binary format, one frame for each tick. The replayer plays a log back into a world. Three queries print CARLA's text about a log: its frames, its collisions and its blocked actors.

The port follows CARLA's simulator plugin at commit `1360bb9`: `Carla/Recorder/CarlaRecorder.cpp`, `CarlaRecorderQuery.cpp`, `CarlaReplayer.cpp`, `CarlaReplayerHelper.cpp` and the file of each packet. The bytes and the text are CARLA's, byte for byte.

## Modules

| Module | What it gives |
|---|---|
| `recorder` | `Recorder`, `recorder_rotation`, `weather_record` and `now_seconds`. |
| `recorder_packets` | `RecorderPacketId`, `SceneLightId`, `SceneLightGroup`, `LogVector`, `LogReader`, the record of each packet and the packet writers. |
| `recorder_physics` | `RecordedPhysicsControl`, `RecordedWheelPhysics` and `physics_control_text`. |
| `recorder_query` | `query_info`, `query_collisions`, `query_blocked`, their file forms and `CollisionCategory`. |
| `recorder_format` | `c_general`, `c_fixed`, `pad_right`, `pad_left` and `c_date`: the C library's number and date text. |
| `replayer` | `Replayer`. |
| `replayer_helper` | What a record does to a world: `process_event_add`, `process_position`, `lerp_angle` and the others. |

## Record a world

Start the recorder on a world. Then call `tick` in place of `World.tick`, or call `record` after each `World.tick`. Stop the recorder to write the file.

```mojo
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.recorder import Recorder
from extensions.carla.world import EpisodeSettings, World
from units.si import Duration, SECOND

var world = World(load_opendrive_file("assets/carla/town.xodr"))
var settings = EpisodeSettings()
settings.fixed_delta_seconds = Duration(0.05, SECOND)
_ = world.apply_settings(settings)
var recorder = Recorder()
_ = recorder.start(world, "/tmp/run.log", "Town", additional_data=True)
for _ in range(100):
    _ = recorder.tick(world)
recorder.stop()
```

The first frame holds every actor of the world, at its pose in the world, and the weather. Each later frame holds what changed and the state of each actor.

- The actors that appeared, with their blueprints, and their parents. A new actor's pose is its spawn pose, in its parent's frame when it has a parent.
- The actors that went, the doors that opened or closed, and the weather when it changed.
- The collisions that each collision sensor reported, one record for each pair.
- The pose of each vehicle, walker and plain actor, in centimeters and degrees.
- Each vehicle's control and lights, and each walker's speed in centimeters per second.
- Each traffic light's state, elapsed time and freeze.

With `additional_data`, a frame also holds the velocities of the vehicles and walkers and the bones of the walkers. It holds the time on the machine's clock since the start. Each new actor also gets its box, or the trigger volume of a light or a sign. Each new vehicle gets its physics control, and each new light its stage times.

The recorder finds the events by comparing the world with the last frame. CARLA's simulator reports each event to its recorder. The frame is the same.

## The file

The file starts with a header: the version 1, the text `CARLA_RECORDER`, the date and the map's name. A frame follows for each tick. Every number is little-endian.

A packet is an id byte, the size of the rest as a `uint32` and the rest. Most packets hold a `uint16` count and that many records. A string is a `uint16` length and its UTF-8 bytes. `LogReader.string` checks UTF-8 before it constructs text. An incomplete or invalid string returns empty text and sets `failed`. A later read stays failed until `seek` clears the flag.

| Id | Packet | Record |
|---|---|---|
| 0 | `FrameStart` | The frame number, its duration and the elapsed time. |
| 1 | `FrameEnd` | Nothing. |
| 2 | `EventAdd` | An actor's id, kind, pose and blueprint with its attributes. |
| 3 | `EventDel` | An actor's id. |
| 4 | `EventParent` | A child's id and its parent's id. |
| 5 | `Collision` | The collision's number, two ids and two hero flags. |
| 6 | `Position` | An actor's location and rotation. |
| 7 | `State` | A traffic light's freeze, elapsed time and state. |
| 8 | `AnimVehicle` | A vehicle's steer, throttle, brake, hand brake and gear. |
| 9 | `AnimWalker` | A walker's speed. |
| 10 | `VehicleLight` | A vehicle's light flags. |
| 11 | `SceneLight` | A scene light's id, intensity, color, switch and group. |
| 12 | `Kinematics` | An actor's velocity and angular velocity. |
| 13 | `BoundingBox` | An actor's box. |
| 14 | `PlatformTime` | The machine's time since the start. |
| 15 | `PhysicsControl` | A vehicle's physics control and its wheels. |
| 16 | `TrafficLightTime` | A light's green, yellow and red times. |
| 17 | `TriggerVolume` | A light's or a sign's trigger volume. |
| 18 | `FrameCounter` | A frame counter. CARLA does not write it. |
| 19 | `WalkerBones` | A walker's bones: a name and a pose each. |
| 20 | `VisualTime` | The time of the visual effects. |
| 21 | `AnimVehicleWheels` | Each wheel's steer angle and spin. |
| 22 | `AnimBiker` | A two-wheeler's speed and engine speed. |
| 23 | `VehicleDoor` | A door and whether it opened. |
| 24 | `Weather` | The weather's fourteen numbers. |

A location is in centimeters. A rotation is the roll, the pitch and the yaw, in degrees, in that order. `LogVector` converts both to the world's units.

CARLA writes -1 as a frame's duration. It writes the real duration when the next frame starts, so the last frame keeps -1.

A wheel in the physics control is a copy of CARLA's C++ record, 208 bytes. It holds the three pointers of a C++ list, the lateral slip graph. The port writes those as zeros, which is what CARLA writes for an empty graph.

## Query a log

Each query takes a file or the bytes of a log, and returns CARLA's text.

```mojo
from extensions.carla.recorder_query import (
    CATEGORY_HERO,
    CATEGORY_VEHICLE,
    show_recorder_actors_blocked,
    show_recorder_collisions,
    show_recorder_file_info,
)
from units.si import CENTIMETER, Duration, Length, SECOND

print(show_recorder_file_info("/tmp/run.log", show_all=True))
print(show_recorder_collisions("/tmp/run.log", CATEGORY_HERO, CATEGORY_VEHICLE))
print(show_recorder_actors_blocked("/tmp/run.log", Duration(30, SECOND), Length(10, CENTIMETER)))
```

- `show_recorder_file_info` lists the actors made and removed, the parents, the collisions and the weather of each frame. With `show_all` it lists every packet it knows, and every frame.
- `show_recorder_collisions` lists each collision once, in the frame it starts. The categories are `o` other, `v` vehicle, `w` walker, `t` traffic light, `h` hero and `a` any.
- `show_recorder_actors_blocked` lists each actor that moved less than the distance for the time or longer. The longest stop comes first.

A number is in the C library's form: six significant digits for a stream's default. A collision's time and a stop's time have no fraction. The date is in UTC.

CARLA's queries keep some behavior that looks like a slip. The port keeps it, so the text is the same:

- The last `FrameEnd` is read twice, so the file-info query ends its last frame with two newlines.
- The collision and blocked queries forget the last actor added when any actor is removed.
- The blocked query adds the last frame's duration of -1 to each actor that did not move in it.
- After a collision line, the collision query writes the duration with no fraction.

The collision query reads an actor's category from its kind. So a traffic sign is `h` and a sensor is `a`, as in CARLA.

## Replay a log

The replayer makes the log's actors in a world, and moves them frame by frame. `step` ticks the world and then moves the replay on by the tick.

```mojo
from extensions.carla.replayer import Replayer
from units.si import Duration, SECOND

var replayer = Replayer()
print(replayer.replay_file(world, "/tmp/run.log", Duration(0, SECOND)))
while replayer.is_enabled():
    _ = replayer.step(world)
```

`replay_file` takes CARLA's options:

- `time_start`: where to start. A negative time counts back from the end.
- `duration`: how long to play. Zero plays to the end.
- `follow_id` and `follow_offset`: the spectator follows that actor, at that pose in its frame.
- `replay_sensors` makes the sensors of the log. `replay_weather` sets its weather.

`set_time_factor` plays faster or slower. `set_ignore_hero` leaves the actors whose role name is `hero` to the world. `set_ignore_spectator`, on by default, leaves the spectator alone.

A replayed actor gets a new id from the world. The replayer maps each id of the log to the world's id. A traffic light or a sign is not made: the replayer finds the one at the logged place, to the whole centimeter.

The replay stops at the end of its time and keeps its actors. `stop` runs the rest of the log's events first, unless it keeps the actors. Then each vehicle gets its gravity back, stops and gets a control in first gear. Each walker stops.

### Between frames

Frame k holds the poses at its time t(k). While the replay's time t is in frame k, each actor sits between its poses of frames k - 1 and k. The fraction is (t - t(k)) / d(k), where d(k) is the frame's duration.

So the replay shows the poses of frame k - 1 at t(k), one frame behind the log, as CARLA's replayer does. An actor with no pose in the frame before takes its pose of frame k.

The location moves in a straight line. Each angle moves the shorter way round: from 174 to -178 degrees it passes 180. At a time factor of 2 or more, each actor takes the pose of the last frame read, with no interpolation.

## What the port reuses

- `sensor_data.ByteWriter` writes the little-endian numbers.
- `collision.CollisionSensor` finds the hits that a collision sensor reports.
- `actor.rotation_matrix` and `actor.rotation_of` give a rotation as CARLA stores it. `actor.compose` places the spectator behind a followed actor.
- The world's own types carry the records: `ActorId`, `ActorKind`, `TrafficLightState`, `VehicleLightState`, `VehicleDoor`, `Gear` and `ActorAttributeType`.
- `VehiclePhysicsControl` gives the physics control, and `WeatherParameters` the weather.

## Differences from CARLA

- The recording stays in memory until `stop` writes the file. `bytes` returns it at any time.
- A door found by comparison gives one event for each door. CARLA gives one event for all the doors at once.
- A later change of a physics control or of a light's times is recorded by `add_physics_control` and `add_traffic_light_time`.
- The world has no scene lights and no wheel or bicycle animation. `add_light_scene`, `add_anim_wheels` and `add_anim_biker` record them.
- CARLA keeps a frame's collisions in a hash set. The port writes them in the order they happened.
- The visual time is the world's elapsed time. The platform time comes from a monotonic clock.
- The replayer does not load a map. It plays into the world it is given, and there is no map override.
- CARLA turns off a replayed vehicle's physics and collisions. The world cannot, so the helper turns off its gravity, and sets the pose after the world's tick.
- A replayed vehicle or walker spawns 1000 m up and then moves to its place, as CARLA spawns it 1 km up.
- The world cannot attach a vehicle or a walker, or remove a light, a sign or the spectator. Those events do nothing.
- A pose for an actor that was not replayed goes to the world's actor with the logged id, as in CARLA.
- The blocked query lists the actors still stopped at the end in the order they appeared. CARLA lists equal times in its hash map's order.
- Each query starts from frame zero. CARLA's queries keep the last frame between calls.

## Not ported

- The replay after a map load: the world here has one map.
- The autopilot at the end of a replay, and the removal of the map's movable props. The world has neither.
- The wheel and bicycle animation of a replayed vehicle, which CARLA's current replayer skips too. The replayer keeps the records for a renderer.

## Tests

- `tests/test_carla_recorder.mojo` checks the bytes and the text against a C++ program outside the repository. The program holds CARLA's packet writers, its frame writer and its three queries, with standard types in place of the engine's. The suite builds the same three logs and compares every byte and every character.
- The same suite checks the number text against Python's `%g` and `%f`, and the dates against Python's `strftime`.
- `tests/test_carla_recorder_world.mojo` records worlds and replays them. The expected poses and times are worked by hand from CARLA's replayer.
