# CARLA sensors

The CARLA extension gives every CARLA sensor. `SensorManager` attaches a sensor to a world's actor and gives its measurements on each `tick`. Each sensor reads its settings from its actor's attributes, which come from the world's blueprint library. If `spawn_sensor` fails, the world and the manager keep their prior records. The failed sensor does not consume an actor id.

The port follows the CARLA source at commit `1360bb9`. The records and their bytes come from `LibCarla/source/carla/sensor`. What each sensor measures comes from CARLA's simulator plugin, `Carla/Sensor` and `Carla/Sensor/V2X`. See [CARLA world](CARLA-world) for the world and [CARLA](CARLA) for the RGB, depth and semantic cameras of a scene.

## Listen to a sensor

Spawn the sensor through the manager. Then tick the manager, not the world. The manager ticks the world, and then measures each sensor that is due.

```mojo
from extensions.carla.sensor_manager import IMU_KIND, SensorManager
from extensions.carla.transform import CarlaRotation, CarlaTransform
from units.si import DEGREE, METER, Angle, Length

var manager = SensorManager()
var car = world.spawn_actor(
    world.get_blueprint_library().at("vehicle.lincoln.mkz"),
    world.get_spawn_points()[0],
)
var mount = CarlaTransform(
    Length(0, METER), Length(0, METER), Length(2, METER),
    CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
)
var imu = manager.spawn_sensor(
    world, world.get_blueprint_library().at("sensor.other.imu"), mount, car
)
var measurements = manager.tick(world)
for m in measurements:
    if m.kind == IMU_KIND:
        print(m.imu.value())
```

`listen` starts a sensor that was spawned before. `stop` ends it. `send` queues a message on a custom V2X sensor for its next due tick.

### One tick

1. Each V2X sensor that is due makes its cooperative awareness message (CAM). Each custom V2X sensor that is due moves its queued messages to its outbox.
2. The world ticks.
3. Each sensor that is due measures, in the order it was listened to.

A V2X receiver hears only senders that are due on the same world tick. A saved CAM or custom outbox is not retransmitted on intervening ticks. A receiver that is not due does not buffer transmissions for a later measurement.

A sensor is due on the first tick that brings the time since its last measurement to its `sensor_tick` or more. A `sensor_tick` of zero is every tick. The measurement uses that time as its tick. The collision and lane invasion sensors report on every tick.

### What a measurement holds

Every `SensorMeasurement` has the frame, the time, the sensor's transform, the 48-byte header and the `raw_data` bytes. It also holds the record of its sensor.

| Blueprint | Record | When |
|---|---|---|
| `sensor.camera.depth`, `semantic_segmentation`, `instance_segmentation`, `normals`, `rgb` | `pixels` | Each tick |
| `sensor.camera.*_fisheye` | `pixels` through the lens | Each tick |
| `sensor.camera.optical_flow` | `flow` | Each tick |
| `sensor.camera.dvs` | `events` | A tick with events |
| `sensor.lidar.ray_cast`, `hss_lidar` | `lidar` | Each tick |
| `sensor.lidar.ray_cast_semantic` | `semantic_lidar` | Each tick |
| `sensor.other.radar` | `radar` | Each tick |
| `sensor.other.imu` | `imu` | Each tick |
| `sensor.other.gnss` | `gnss` | Each tick |
| `sensor.other.collision` | `collision` | One for each hit |
| `sensor.other.lane_invasion` | `lane_invasion` | A crossed mark |
| `sensor.other.obstacle` | `obstacle` | Something ahead |
| `sensor.other.v2x` | `cams` | A message heard |
| `sensor.other.v2x_custom` | `custom` | A message heard |

`image()` returns a camera's pixels as a `Framebuffer`.

## Modules

| Module | What it gives |
|---|---|
| `sensor_manager` | `SensorManager`, `SensorMeasurement` and `SensorKind`. |
| `semantic_lidar` | The semantic, ray-cast and HSS LiDARs. |
| `radar` | `Radar`, `RadarDescription` and `RadarDetection`. |
| `imu` | `IMU`, the accelerometer, the gyroscope and the compass. |
| `gnss` | `Gnss` and `GnssDescription`. |
| `collision` | `CollisionSensor` and `CollisionMeasurement`. |
| `lane_invasion` | `LaneInvasionSensor` and `LaneInvasionEvent`. |
| `obstacle` | `detect_obstacle` and `sweep_sphere`. |
| `cameras` | The ground-truth images, the wide-angle lens and `DVSCamera`. |
| `v2x` | `PathLossModel`, `CaService`, the CAM records and custom messages. |
| `sensor_data` | The header and the `raw_data` of each measurement. |
| `sensor_rays` | `RayScene`, `WorldRays` and `MeshRays`. |
| `sensor_noise` | `SensorRandom`, the noise engine of a sensor. |
| `sensor_attributes` | How a sensor reads an attribute. |

## Rays

A sensor casts its rays against a `RayScene`. `WorldRays` casts against a world's colliders: the road, the sidewalks, the vehicles and the walkers. `MeshRays` casts against a ThreeMojo `Scene`, and the caller names the actor, the tag and the velocity of each mesh.

A hit names its actor and the actor's first semantic tag. A hit on a map surface names no actor. Its tag is the one that `World.project_point` reads there. A hit also carries the velocity of the point and of the actor.

## Physical settings

Physical float settings must be finite in `Float32`. The sensor attribute reader refuses NaN, infinity, and a finite decimal that overflows during conversion. A missing or mistyped attribute keeps its finite default. Metadata strings are not subject to these checks.

Descriptions and sensor constructors also check their domains before they publish state:

- Noise standard deviations, attenuation, and the sensor tick must be nonnegative. Biases and radio power can be negative.
- Radar range must be positive. Its fields of view are from 0 up to, but not including, 180 degrees. A zero point rate produces no rays.
- LiDARs require positive range, frequency, point rate, and channel count. Their drop-off rates are from 0 through 1. HSS keeps its CARLA clamp: a nonpositive horizontal resolution becomes 0.01 degrees, and a negative horizontal field of view produces no rays. HSS ignores rotation and point rates; its intensity limit can be zero.
- Camera contrast thresholds and logarithm epsilon must be positive. RGB gamma, ISO, f-stop, shutter speed, and exposure calibration must be positive. Threshold noise and the refractory period must be nonnegative. A wide-angle lens requires finite coefficients and a positive finite focal length. Its zero-fov attribute still selects the 90-degree fallback.
- V2X frequency and reference distance must be positive. Its filter distance, path-loss exponent, and fading deviation must be nonnegative. CAM intervals must be positive, with the minimum no greater than the maximum.

These checks are an intentional difference from CARLA's permissive numeric parsing. Boolean parsing still follows CARLA: only `true`, in any letter case, means true. Other text, including `yes`, means false. The generic blueprint can store numeric text that a physical sensor later refuses.

`spawn_sensor` rejects invalid settings without consuming an actor id or a manager slot. If `listen` rejects an existing actor, that actor stays alive and unlistened. Direct IMU, GNSS, radar, DVS, and V2X constructors check descriptions too. These checks do not limit metadata values or change the seeded noise sequence.

## Noise

Each sensor has its own `SensorRandom`, seeded with its `noise_seed`. The engine is C++'s `std::minstd_rand`, which the C++ standard fixes. The uniform and normal floats follow the GNU C++ library, which CARLA's Linux build uses. The normal is Marsaglia's polar method. A sensor draws in CARLA's order, so one seed gives CARLA's numbers.

## The sensors

### LiDARs

Each laser of a rotating LiDAR fires the points per second times the tick over the channels, rounded half away from zero. The rays sweep the angle that the rotation covers in the tick, from where the last tick stopped.

- The semantic LiDAR keeps each hit. A hit holds the point in the sensor's frame, the cosine between the normal and the way back, the actor id and the tag.
- The ray-cast LiDAR draws a drop-off for each ray before the cast. Each hit then gets exp(-a d), noise along its direction and a drop-off by intensity.
- The HSS LiDAR does not turn. Each laser fires one ray for each step of `horizontal_resolution` across the field of view.

A tick with no ray to fire sends the last measurement again, as CARLA does.

### Radar

The radar fires the points per second times the tick, truncated. Each ray draws a radius and an angle inside the two fields of view. A hit gives the depth, the azimuth, the altitude and the velocity toward the radar. That velocity is the hit actor's velocity less the radar's own, along the ray.

### IMU

- The accelerometer is the second derivative of the parabola through the last three locations. The world's `imu_gravity` is added to z.
- The gyroscope is the parent's angular velocity, turned into the sensor's frame, plus a bias.
- The compass is the angle from north, (0, -1, 0), to the forward vector on the ground.

### GNSS

The receiver projects its location with the map's projection. It then adds a bias and a normal noise to the latitude, the longitude and the altitude.

### Collision

The sensor reports each body that pushed its parent in the tick. It gives the other actor and the impulse on the parent, once for each pair and frame. A map surface is no actor, and its measurement carries the surface's tag.

### Lane invasion

The sensor follows the four bottom corners of its parent vehicle's box. When the corners move, it asks the map which marks each corner crossed. It reports only when a mark was crossed.

`LaneInvasionSensor.tick` takes the snapshot time as a `Duration64`. The time must be finite and nonnegative. The event's `timestamp` field keeps the same Float64 seconds.

### Obstacle

The detector sweeps a sphere of `hit_radius` along its forward vector for `distance`. The sweep passes through the detector and its parent. With `only_dynamics`, it meets only the bodies that move.

### Cameras

A ground-truth camera casts one ray through the center of each pixel.

- Depth packs the planar depth into RGB.
- Semantic segmentation writes the tag in red.
- Instance segmentation writes the tag in red and the low 16 bits of the actor id in green and blue.
- Normals write the normal in the view frame: x right, y up and z toward the camera.
- Optical flow gives the move of each pixel's point since the last frame, in normalized device units.
- RGB is a shaded stand-in: the tag's CityScapes color times the light on the surface. The [rendering tier](CARLA) draws the real image.

The event camera compares the log intensity of each pixel with the last frame. Each crossing of the threshold gives an event with a time inside the tick.

`DVSCamera.simulate` takes the frame time as a `Duration64`, so a short tick late in a run keeps its Float64 digits. The time must be finite, nonnegative and at most 9.2e9 seconds. A larger time has too many nanoseconds for an event's `Int` time.

### Wide-angle lens

`WideAngleLens` gives CARLA's six lens models: perspective, stereographic, equidistant, equisolid, orthographic and Kannala-Brandt. The field of view is vertical, and the focal length fits it to the image height. A Kannala-Brandt angle comes from 32 Newton steps, as in CARLA.

### V2X

A receiver hears a sender that is closer than `filter_distance`. A line between the two finds the path state: line of sight, a vehicle in the way or a building in the way. The loss follows WINNER+ or the geometric model, with ETSI's shadow fading. A message arrives when the power is at least `receiver_sensitivity`.

A vehicle sends a CAM when its heading, position or speed changed enough, or when `gen_cam` has passed. A sensor without a vehicle parent is a roadside unit and sends every 0.5 s.

## Bytes

`sensor_data` writes the bytes that CARLA sends. The header is the sensor's registry place, the frame, the time and the transform. An image is a 12-byte header and 4 bytes a pixel, blue first. A LiDAR, a radar and an event camera write packed records. The IMU, the GNSS, the collision and the obstacle sensors write MessagePack.

A V2X sensor writes a copy of CARLA's C++ record for each message that it heard. A `CAMData` record is 3168 bytes and a `CustomV2XData` record is 136 bytes. The layout is the one that the LP64 ABI of Linux and macOS gives. `v2x_cam_data` and `v2x_custom_data` state each offset.

## Differences from CARLA

- CARLA renders the cameras and resamples a fisheye from six cube faces. This port casts one ray a pixel.
- CARLA's wide-angle shader is not in its source. The mask, its fade, the equirectangular mapping and the perspective switch are this port's.
- The sensor tick is an interval timer, not CARLA's actor tick.
- The line between two V2X antennas passes through the two sensors' parents.
- A CAM's generation time counts from a start that the caller gives, not from the wall clock.
- The event camera sorts events that tie in time in their order. CARLA's sort is not stable.
- A CAM's size fields keep CARLA's units: the box in centimeters, times ten.
- The V2X bytes have zero in each padding byte and in each field that CARLA does not set. CARLA leaves some of these bytes undefined.
- The obstacle detector's sweep is a sphere trace, the conservative-advancement pattern. It stops at a gap of 0.1 mm or after 512 steps.

## Not ported

- The stream token of a sensor's actor record, which is a network handle. It is written empty.
- The RSS sensor, which needs a third-party library.

## What the port reuses

- `lidar.LidarDescription` for the LiDAR settings and the laser angles.
- `pointcloud.SemanticLidarDetection` and `LidarDetection` for the points and their PLY files.
- `sensor.CameraIntrinsics`, `encode_depth` and `cityscapes_color`, and `image_convert.encode_instance`.
- `geo.GeoProjection` for the GNSS and the CAM positions.
- `map.Map.calculate_crossed_lanes` for the lane invasion.
- The physics tier's ray cast, collision events, shapes and `signed_distance`.
- `core.raycaster` for `MeshRays`, and `render.framebuffer` for the images.

## Tests

Two suites check the sensors against numbers from outside the port:

- `tests/test_carla_sensors.mojo`: the noise engine, the LiDARs, the radar, the IMU and the GNSS. It also checks the cameras, the lenses, the event camera, the V2X losses and the bytes.
- `tests/test_carla_sensors_world.mojo`: the rays in a world, the collisions, the lane invasion, the obstacles, the V2X channel and CAMs, and the manager.

The expected numbers come from hand calculation, from a C++ program built with the GNU C++ library, and from Python models of CARLA's C++.
