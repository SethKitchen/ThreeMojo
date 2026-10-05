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

## Lane orientation

A known waypoint uses the derivative of its evaluated offset-plus-width
centerline for heading and pitch. This covers all five reference geometries,
inner-lane widths, lane offsets, and both traffic directions. It preserves
center coordinates and zero roll. See [lane orientation](CARLA-lane-orientation)
for record boundaries, singular tangents, rounding and remaining limits.

## Lane endpoints

`generate_topology` keeps each dead-end driving lane. Its terminal waypoint uses the known road, section and lane with an s in double precision. It does not look the endpoint up again through `waypoint_xodr`. This keeps the endpoint in its own section when rounding would select the next section or reject the road end. Connected pairs keep their existing order.

`next_until_lane_end` and `previous_until_lane_start` follow the unique lane path within the starting road. They stop at a road boundary, an unlinked section boundary or a branch. The final waypoint is the reachable endpoint in the requested direction. A start already at or beyond that inward endpoint returns an empty list.

The inward offset is capped at one quarter of the section length so tiny positive sections retain valid endpoints. If no interior value is representable, the boundary is used. A positive final remainder still emits the endpoint, even below the usual inward offset.

The input s must be finite and inside the specified lane section. Shared endpoints are valid for either adjacent section. The spacing must be finite and greater than `EPSILON`. A spacing that cannot advance the waypoint raises an error.

The endpoint is resolved before sampling. A large interval does not traverse a different road. Ordinary forward samples keep the existing spacing and order. Exact endpoints do not add a duplicate sample.

## Junction bounds

`junction_box` encloses the centers of nonzero lanes selected by `LANE_ANY`
on each connecting road. This mask excludes `LANE_NONE`. It includes every
section, even when lane links stop or change lane id.
It evaluates increasing road s for both traffic directions. It includes the
exact section endpoints and both sides of each record boundary.

It does not follow a successor road. Repeated connections do not change
the result.
A junction without lanes keeps CARLA's empty-box sentinel.

The bound covers the supported lane-center model, not the lane surface.
That model includes line, arc, spiral, poly3 and paramPoly3 geometry, lane
widths, lane offsets and elevation. Poly3 and paramPoly3 use the existing
sampled position and tangent tables, including their extrapolated tail.
Superelevation, crossfall and shape remain outside the supported model.

The approximation has an explicit error budget:

- Split at geometry starts and ends, table knots, section boundaries, and
  all width, offset and elevation record starts.
- On each smooth span, bound the second derivative. Subdivide until the
  maximum coordinate distance from a chord is at most 0.01 m. Add that
  distance to the sampled box. Constant-offset arcs instead evaluate the
  cardinal headings that can contain an extremum.
- Add a Float32 rounding allowance of four machine epsilons times the
  coordinate and offset scale, with a 1 m floor. Add coefficient-scaled
  Float64 Horner error for the road-s cubics. A large road s can make this
  numerical allowance much larger than 0.01 m. Arc bounds also include
  phase and radius cancellation error. Unresolved arc phases use a
  full-circle-sized numerical allowance.
- For a spiral, also add `1.1e-7 * geometry.length` meters per plan axis.
  This covers twice the five-point Gauss-Legendre remainder bound for the
  supported evaluator. It is separate from the chord error.
- A singular paramPoly3 tangent or a span that needs more than 65,536
  subdivisions uses a wider envelope. It encloses the reference chord,
  its curvature error, and the complete lateral-offset disk. Elevation
  uses its cubic envelope. This fallback has no 0.01 m tightness claim.

These are conservative numerical bounds, not exact extrema. The geometric
proof applies to finite record arithmetic. Non-finite coefficient or
subdivision arithmetic raises an error. Evaluated locations and padded
bounds must fit in finite Float32 coordinates. This contract does not
repair unrelated geometry evaluation or nearest-lane limitations.

For a smooth coordinate with second derivative bounded by M, the chord
error is at most `M * h * h / 8`. For a lane center `P + t*n`, a sufficient
plan bound is `|P''| + |t''| + 2*|t'|*|heading'| +
|t|*(|heading''| + |heading'|^2)`. Cubic Bernstein control values bound the
width, offset and elevation terms. A parametric tangent uses the minimum
length of its interpolated derivative vector over the complete span.

Corrected boxes can add junction road conflicts and stop/yield check boxes.
They can also change mesh-region selection and the expanded mesh boxes.
Traffic-manager waypoint junction flags use road topology, not these boxes.
Scenario replay can therefore differ where the old box omitted a curved
interior. Ordering remains deterministic.

## Fixed-s road queries

`Road.nearest_lane` selects a lane at one supplied s in the OpenDRIVE frame.
It retains Float64 centers and compares their stored-point distances exactly.
It returns a scale-safe approximate Float64 distance and checks its finite range.
This helper visits all eligible lane centers and preserves exact-tie ordering.
It does not call or change the Map nearest-waypoint search.
See [fixed-s nearest lane queries](CARLA-fixed-s-nearest) for limits and record rules.

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

This port keeps CARLA's numbers except for the corrections listed here.

- Waypoint orientation follows the geometric centerline tangent, including lateral and curvature derivatives. Pitch uses vertical speed over actual horizontal speed, with the sign required by the [corrected CARLA rotation basis](https://github.com/carla-simulator/carla/blob/1360bb9/LibCarla/source/carla/geom/Rotation.h). CARLA used a lateral slope as an angle and a raw elevation grade as positive pitch. See [issue #485](https://github.com/SethKitchen/ThreeMojo/issues/485) and the [orientation contract](CARLA-lane-orientation).
- Topology retains dead-end lanes and their section identity. The pinned [CARLA `Map.cpp`](https://github.com/carla-simulator/carla/blob/1360bb9/LibCarla/source/carla/road/Map.cpp) narrows the endpoint to a float before lookup. This can drop an increasing-s lane at the road end. The port deliberately corrects that behavior. See [issue #285](https://github.com/SethKitchen/ThreeMojo/issues/285).
- Backward lane traversal measures the remainder toward the lane start. The pinned [CARLA `Waypoint.cpp`](https://github.com/carla-simulator/carla/blob/1360bb9/LibCarla/source/carla/client/Waypoint.cpp) uses the forward remainder for its final backward step. That can leave the starting road or fail at an isolated end. The port deliberately corrects that behavior and handles exact and unlinked section endpoints. See [issue #286](https://github.com/SethKitchen/ThreeMojo/issues/286).
- Junction bounds include reverse-running curved lane interiors. The pinned CARLA `CreateJunctionBoundingBoxes` uses a signed ten-step interval and skips those interiors. The port uses the [bounded approximation](#junction-bounds) above. A 100 m semicircle with a positive RHT lane is the reproducible counterexample. See [issue #487](https://github.com/SethKitchen/ThreeMojo/issues/487).
- CARLA walks roads, junctions and signals in hash order. This port walks them in order of id.
- CARLA computes a point in single precision. This port computes in double and rounds where CARLA returns a float, except for the fixed-s nearest-lane correction.
- Fixed-s nearest-lane selection keeps wide stored centers and checks every center. It no longer turns narrowed centers or underflowed squares into false ties. See [issue #604](https://github.com/SethKitchen/ThreeMojo/issues/604) and the [precision limits](CARLA-fixed-s-nearest).
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
