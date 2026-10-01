# CARLA maps

The CARLA map modules read an OpenDRIVE file into a road network, answer CARLA's map queries on it, and build its road surface as meshes. They port CARLA's `opendrive/parser/*`, `road/*` and `road/MeshFactory` at commit `1360bb9`.

See [CARLA](CARLA) for the frame, the sensors and the LiDAR, and [Extensions](Extensions) for the other extensions.

## Load a map

`load_opendrive_file` reads an `.xodr` file. `load_opendrive` reads the same text from a string.

```mojo
from extensions.carla.map import Waypoint
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LaneId, RoadId, SectionId
from math.vector3 import Vector3

var map = load_opendrive_file("assets/carla/town.xodr")
var here = map.waypoint(Vector3(20, 1.75, 0)).value()
var ahead = map.next(here, 5.0)
var pose = map.compute_transform(ahead[0])
```

`waypoint` gives the waypoint under a point in CARLA's frame, or none. `next` gives every waypoint 5 meters ahead. `compute_transform` gives the pose of a vehicle there.

The test town is `assets/carla/town.xodr`. Road 1 runs east into junction 100. Road 10 goes on to road 2 and road 11 turns right onto road 3. Roads 5, 6 and 7 stand alone and carry the other records.

## Modules

| Module | What it holds |
|---|---|
| `road_info` | The ids, the lane kinds, every `RoadInfo` record, `InformationSet` and `LaneMarking`. |
| `road` | `Road`, `LaneSection`, `Lane` and `LaneKey`. |
| `map` | `Map`, `Waypoint`, `Junction`, `Signal`, `Controller`, `RoadObject`, the signal types and the deformation. |
| `map_builder` | `MapBuilder`, which joins the parser's pieces into a `Map`. |
| `opendrive` | The parser and pugixml's attribute readers. |
| `mesh_factory` | `MeshFactory` and the map's meshes. |

## Waypoints

A `Waypoint` is a road id, a lane section id, a lane id and an s. The s is a `Float64` in meters. CARLA steps a waypoint 10 double epsilons inside a section's edge, and a `Float32` cannot hold that step.

Two waypoints are equal when the road, the section and the lane match and `floor(200 s)` matches. This is CARLA's hash.

## The query surface

| Question | Method |
|---|---|
| Where is a waypoint? | `compute_transform`, `lane_width`, `lane_type` |
| Which waypoint is near a point? | `closest_waypoint_on_road`, `waypoint` |
| Which waypoint is at a road, lane and s? | `waypoint_xodr` |
| What is ahead or behind? | `next`, `previous`, `successors`, `predecessors` |
| Where does the lane end? | `next_until_lane_end`, `previous_until_lane_start` |
| What is beside? | `right`, `left` |
| Which marks bound the lane? | `mark_record`, `right_lane_marking`, `left_lane_marking`, `lane_change` |
| Which marks does a move cross? | `calculate_crossed_lanes` |
| Which signals are ahead? | `signals_in_distance`, `landmarks_in_distance`, `landmarks_of_type_in_distance` |
| Which signals are there? | `all_signal_references`, `all_landmarks`, `landmarks_from_id`, `all_landmarks_of_type`, `landmark_group` |
| Where are the crosswalks? | `all_crosswalk_zones` |
| Which waypoints cover the map? | `generate_waypoints`, `generate_waypoints_on_road_entries`, `generate_waypoints_in_road`, `generate_topology` |
| What is in a junction? | `junction`, `junction_waypoints`, `compute_junction_conflicts`, `is_junction`, `junction_id` |

Right and left are as the lane's traffic sees them. A lane that runs against s faces the other way, so its yaw gains 180 degrees.

`LaneType` is a bit mask. A query takes a mask, such as `LANE_DRIVING | LANE_SHOULDER`, and keeps the lanes whose type shares a bit with it.

## Traffic rules

A road with `rule="LHT"` keeps traffic to the left. Its left lanes run with s and its right lanes against it. `right`, `left`, the lane change and the sign placement all follow the rule.

## How the map is built

`MapBuilder.build` joins the pieces in CARLA's order.

1. It links each lane to the lanes it leads to, within its road, onto the next road, or through a junction.
2. It removes a signal reference whose every validity is lane 0 to lane 0.
3. It sorts each road's and each lane's records by s.
4. It places each signal on its road, or at its inertial position.
5. It gives a reference with no validity the lanes that face it.
6. It tells each signal which controllers hold it, through the junctions that name them.
7. It cuts each lane into straight segments for the nearest-waypoint search.
8. It boxes each junction and finds the junction roads that cross.
9. It moves each sign that stands on a driving lane off that lane.

The segments are in `extensions.carla.rtree.SegmentCloudRtree`.

## Meshes

`MeshFactory` returns a `BufferGeometry` in CARLA's frame. Each geometry has per-vertex normals, UVs in meters and one group for each surface kind. `to_three_frame` turns a geometry into the three.js frame.

| Surface kind | What it is |
|---|---|
| `ROAD_SURFACE` | The driving surface. |
| `SIDEWALK_SURFACE` | The top of a sidewalk. |
| `CURB_SURFACE` | The sides of a sidewalk. |
| `WALL_SURFACE` | A safety wall on a section's outer edge. |
| `CROSSWALK_SURFACE` | A crosswalk. |
| `WHITE_MARK_SURFACE` | White paint. |
| `YELLOW_MARK_SURFACE` | The yellow center line. |

On a lane, u is the offset from lane 0 and v is s. On a curb or a wall, u is the height. On a crosswalk, u and v are x and y. The `uv1` attribute holds CARLA's own grid coordinates where CARLA writes them.

The map functions are `generate_mesh`, `generate_chunked_mesh`, `generate_ordered_chunked_mesh_in_locations`, `trees_transform`, `all_crosswalk_mesh`, `generate_line_markings` and `junctions_bounding_boxes`.

## Differences from CARLA

This port keeps CARLA's numbers. The differences are these.

- CARLA walks roads, junctions and signals in hash order. This port walks them in order of id.
- CARLA computes a point in single precision. This port computes in double and rounds where CARLA returns a float.
- A spiral uses Gauss-Legendre quadrature, as [CARLA](CARLA) explains.
- The segment search breaks a tie by the order the segments were made. Boost leaves that order open.
- A lane link that names no lane is dropped. CARLA stores a null pointer and crashes on it.
- A signal reference that names no signal is refused. CARLA crashes on it.
- CARLA loops forever on a lane with no road mark at its section's start. The mark generator stops there.
- A mesh keeps the triangles of one surface kind together. CARLA interleaves a sidewalk's curb and top row by row.
- A clockwise crosswalk outline is turned so that its face points up.
- A junction of more than two connections is built from its lanes. CARLA uses marching cubes from a third-party library there.

## Not ported

- The lateral profile: superelevation, crossfall and shape. CARLA reads it and never stores it.
- The traffic groups in `userData`. CARLA's parser for them is empty.
- `Map::GenerateWalls`. CARLA declares it and does not define it.
- `SDFToMesh`, which needs the MeshReconstruction library.

The geographic reference comes from `extensions.carla.geo`. See [CARLA geometry](CARLA-geometry).
