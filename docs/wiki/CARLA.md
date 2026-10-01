# CARLA

The `extensions/carla/` modules port the CARLA driving simulator: everything that CARLA runs without its game engine and its network transport. This port adds its own physics and its own renderer. It loads OpenDRIVE maps and simulates vehicles, walkers, traffic lights and signs. It drives the traffic manager and the agents, and reads every CARLA sensor. It records, replays and renders towns in CARLA's weathers.

![The town at clear noon, wet sunset, in rain and at night, each at 800 x 600](out/carla_town.png)

![An RGB image with LiDAR points, a semantic image and a depth image](out/carla.png)

CARLA is by the Computer Vision Center at the Universitat Autonoma de Barcelona (MIT). This port follows CARLA's source at commit `1360bb9`. See [Extensions](Extensions).

To render the images, run `mojo run -I . examples/carla_town.mojo out/carla_town.png` and `mojo run -I . examples/carla.mojo out/carla.png`. Each view is 800 x 600, the size of CARLA's default RGB camera.

## Parts

| Page | What it covers |
|---|---|
| [CARLA geometry](CARLA-geometry) | CARLA's vector and arc math, bounding boxes, geo-projections, the R-tree, meshes, point clouds and image converters |
| [CARLA maps](CARLA-maps) | The OpenDRIVE parser, the road map and its queries, and the road meshes |
| [CARLA physics](CARLA-physics) | The rigid-body solver, the vehicle model and the walker controller |
| [CARLA world](CARLA-world) | Actors, the tick, snapshots, traffic lights, signs, blueprints and weather |
| [CARLA sensors](CARLA-sensors) | Every CARLA sensor, its raw data and the sensor manager |
| [CARLA traffic manager](CARLA-traffic-manager) | The local traffic manager and its stages |
| [CARLA agents](CARLA-agents) | The route planner, the navigation agents and walker navigation |
| [CARLA recorder](CARLA-recorder) | The recorder, the replayer and the recorder queries |
| [CARLA rendering](CARLA-rendering) | Towns, materials, weather and camera effects |
| [CARLA assets](CARLA-assets) | The photoscanned assets and CARLA's own vehicles, and how to fetch them |

## Build a road

Read an OpenDRIVE file with `load_opendrive_file`, or build a map in code with `MapBuilder`. See [CARLA maps](CARLA-maps) for the map, its queries and its meshes.

```mojo
from extensions.carla.map import Waypoint
from extensions.carla.mesh_factory import MeshFactory, to_three_frame
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LaneId, RoadId, SectionId

var map = load_opendrive_file("assets/carla/town.xodr")
var pose = map.compute_transform(
    Waypoint(RoadId(1), SectionId(0), LaneId(-1), 10.0)
)
var surface = to_three_frame(
    MeshFactory().generate_whole_lane(map.road(RoadId(1)), 0, 1)
)
```

`compute_transform` returns the pose of a vehicle in that lane, in CARLA's frame. `generate_whole_lane` returns the lane's surface in CARLA's frame, and `to_three_frame` turns it into the three.js frame.

## Records

`RoadGeometryKind` names five records. Each record starts at an s, a point and a heading.

| Kind | Helper | What it adds |
|---|---|---|
| `LINE` | `line` | Nothing. The heading stays the same. |
| `ARC` | `arc` | A curvature other than zero. |
| `SPIRAL` | `spiral` | A start and an end curvature. |
| `POLY3` | `poly3` | The cubic v(u) in the record's frame. |
| `PARAM_POLY3` | `param_poly3` | The cubics u(p) and v(p), and a `ParamPoly3Range`. |

The frame is OpenDRIVE's. It is right-handed, and the heading turns counter-clockwise from plus x.

CARLA uses the odrSpiral Fresnel code for a spiral. This port integrates the same clothoid with Gauss-Legendre quadrature. The result agrees with a fine numerical integral to 1e-5 meters. It also holds when the two curvatures are equal, where odrSpiral divides by zero.

A poly3 and a paramPoly3 keep CARLA's sample tables and its linear interpolation. A poly3 samples u every 0.3 meters. A paramPoly3 has one interval for each 0.5 meters, and at least five.

## Lanes

A `LaneId` is minus for a lane on the right of the reference line and plus for a lane on the left. Lane 0 is the reference line. It has no width, but it carries the center mark.

On a road that keeps traffic to the right, a right lane faces along the road. A left lane faces against it, so its yaw gains 180 degrees.

`LaneMarkingType` names CARLA's eleven marking types. The mesh factory draws `SOLID` as one strip and `BROKEN` as dashes of three resolutions with gaps of three. It draws no other type, as CARLA does.

## Frames

In CARLA's frame, plus x is forward, plus y is right and plus z is up. The frame is left-handed.

`carla_to_three` swaps y and z. `CarlaTransform.three_matrix` places a three.js node where CARLA places an actor. `CarlaTransform.camera_matrix` also turns the node so that a three.js camera looks along CARLA's forward axis.

`CarlaRotation` keeps CARLA's pitch sign from 2026. The z part of the forward vector is minus the sine of the pitch.

`DirectedPoint.to_carla` negates y and the heading. CARLA calls this its "Y axis hack".

## Sensors

`encode_depth` packs a planar depth into 24 bits of RGB. Red is the low byte. The full scale is `DEPTH_FAR`, 1000 meters. `decode_depth` and `normalized_depth` unpack it. `logarithmic_gray` gives CARLA's logarithmic depth view.

`SemanticTag` names CARLA's 30 tags. `cityscapes_color` gives each tag its CityScapes color. CARLA wraps a tag past the palette. This port refuses it.

`CameraIntrinsics` is the K matrix from CARLA's PythonAPI examples. The focal length is the width divided by twice the tangent of half the horizontal field of view.

`depth_frame` and `semantic_frame` cast one ray through the center of each pixel with the scene's `Raycaster`. CARLA reads these images from its renderer's G-buffer.

## LiDAR

`LidarDescription` holds the settings of `sensor.lidar.ray_cast` with CARLA's defaults. `scan_lidar` casts one tick against a scene.

1. The lasers spread evenly from `upper_fov` down to `lower_fov`.
2. Each laser fires `points_per_laser(tick)` rays across the angle that one tick turns.
3. A general drop-off removes a fraction of the rays before the cast.
4. A hit's intensity is exp(-a d), where a is the attenuation and d the distance.
5. A hit at or below the intensity limit stays with a probability that rises with its intensity.

The random numbers come from a seeded generator, so one seed gives the same scan. Plus elevation is above the horizon. Plus azimuth turns from forward to right.

## Not ported

These parts are not ported:

- The network transport: the RPC server and client, streaming, ROS 2 and multi-GPU.
- The RSS sensor. It wraps a third-party library.
- CARLA's game engine and its assets. This port has its own physics and its own renderer. A physics step and an image are therefore not the same as CARLA's.
