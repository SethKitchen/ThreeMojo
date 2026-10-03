# CARLA agents

The `extensions/carla/agents*.mojo` modules drive a vehicle of a [CARLA world](CARLA-world) as CARLA's navigation agents do. The `extensions/carla/navigation*.mojo` modules move pedestrians on a navigation mesh as CARLA's AI walkers do. Both run in the same process as the world.

The port follows CARLA's `PythonAPI/carla/agents` and `LibCarla/source/carla/nav` at commit `1360bb9`. It keeps CARLA's formulas, constants and defaults. Where the Python agents fail on a missing waypoint, the port follows CARLA's C++ agents in `LibCarla/source/carla/agents/navigation`.

## Modules

| Module | What it gives |
|---|---|
| `agents_misc` | `RoadOption`, `BehaviorType`, `BehaviorParameters` and the helpers of `misc.py`. |
| `agents_controller` | `PIDLongitudinalController`, `PIDLateralController`, `VehiclePIDController` and `PIDGains`. |
| `agents_local_planner` | `LocalPlanner`, `LocalPlannerOptions`, `PlanItem`, `compute_connection` and `retrieve_options`. |
| `agents_route` | `GlobalRoutePlanner`, `RouteNodeId`, `RouteEdge` and `turn_option`. |
| `agents` | `BasicAgent`, `BasicAgentOptions` and the two detection results. |
| `agents_behavior` | `BehaviorAgent` and `ConstantVelocityAgent`. |
| `navigation_mesh` | `NavMesh`, `NavPolygon`, `NavArea`, `NavFlags`, `NavQueryFilter` and `build_navigation_mesh`. |
| `navigation` | `Navigation`, `WalkerManager`, `WalkerEvent` and the crowd. |
| `navigation_walkers` | `WalkerNavigation` and `WalkerAIController`. |

## Drive a vehicle to a destination

Make an agent for a vehicle and give it a destination. At each tick, ask the agent for a control and apply it.

```mojo
from extensions.carla.agents import BasicAgent
from extensions.carla.agents_misc import from_kmh
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.world import EpisodeSettings, World
from math.vector3 import Vector3
from units.si import Duration, SECOND

var world = World(load_opendrive_file("assets/carla/town.xodr"))
var settings = EpisodeSettings()
settings.fixed_delta_seconds = Duration(0.05, SECOND)
_ = world.apply_settings(settings)
var blueprint = world.get_blueprint_library().at("vehicle.lincoln.mkz")
var car = world.spawn_actor(blueprint, world.get_spawn_points()[0])
var agent = BasicAgent(world, car, from_kmh(30))
agent.set_destination(world, Vector3(110, 1.75, 0))
while not agent.done():
    world.apply_control(car, agent.run_step(world))
    _ = world.tick()
```

An agent keeps the id of its vehicle. Each call takes the world, so the agent reads the vehicle, the lights and the other actors at that moment.

## The route planner

`GlobalRoutePlanner` makes a directed graph from the map's topology.

1. Each pair of the topology is a lane piece. The planner samples it at each `sampling_resolution`.
2. Each end of a piece, rounded to whole meters, is a node. Each piece is an edge. Its weight is the number of samples plus one.
3. A piece that leads to a lane with no piece gets an extra edge to a loose end. A loose end has a negative id.
4. Where a lane mark lets a vehicle cross to a driving lane of the same road, an edge of weight zero joins the two pieces.

`trace_route` finds a minimum-cost route between the pieces under the two points. The cost is the sum of the graph's sample counts. Lane changes cost zero. This objective does not measure meters, travel time, or the number of lane changes. Changing the sampling resolution can change the preferred route.

The search uses Dijkstra's algorithm, which is A* with a zero heuristic. CARLA's Euclidean heuristic is in meters. It can exceed the remaining sample-count cost, especially across zero-cost lane changes. It can therefore select a more costly route. This port deliberately removes that heuristic, while it keeps the graph costs.

The search takes the lowest accumulated cost first. Equal costs use the lowest node id. An equal-cost alternative keeps the first predecessor. This retains deterministic ties, but some routes can differ from CARLA's heuristic search. Zero-cost cycles do not change predecessors or cause an infinite search.

Scenario replay and route comparisons against a CARLA server must allow for this difference. The current planner has no mode that restores CARLA's heuristic. The project keeps proven correctness fixes even when upstream results differ; see the [contribution rules](https://github.com/SethKitchen/ThreeMojo/blob/main/CONTRIBUTING.md#upstream-behavior-and-correctness).

All edge costs must be nonnegative. Graph construction checks this once. Private graph edits must preserve this invariant before a search.

The search keeps exact integer costs through the signed 64-bit range. Larger sums share an overflow marker that sorts after every supported cost. A reachable target raises an error only when its minimum cost exceeds that range. Overflow on other paths does not block a valid route or turn an unreachable target into an error.

The destination piece is appended after the search, as before. Its fixed cost is the same for every alternative.

Each step of the route gets a `RoadOption`. A step into a junction compares the heading before the junction with the heading at the end of the junction. Within 35 degrees the step is `OPTION_STRAIGHT`. Otherwise it is `OPTION_LEFT` or `OPTION_RIGHT`, against the other ways out of the junction.

The planner keeps its last decision between calls, as CARLA's does. A second route through the same junction entry can therefore keep an old decision.

## The local planner and the controllers

`LocalPlanner` keeps a queue of plan items. At each step it drops the items that the vehicle has reached and steers for the next one.

- An item counts as reached within `base_min_distance` plus `distance_ratio` times the speed. The last item needs 1 m.
- Without a route, the planner adds waypoints `sampling_radius` apart. At a fork it picks a road option at random, from a seeded generator.
- The speed loop is a PID on the speed error in km/h, with the gains 1.5, 0.05 and 0.2.
- The steering loop is a PID on the heading error in radians, with the gains 1.95, 0.05 and 0.2.
- The throttle stops at 0.75, the brake at 0.3 and the steering at 0.8. The steering changes by 0.1 in one step at most.

## The agents

| Agent | What it does |
|---|---|
| `BasicAgent` | It follows its route. It brakes with `max_brake` for a red light or for a vehicle in its way. |
| `BehaviorAgent` | It does the same with one of three behavior types. It follows cars, stops for walkers, slows for turns and moves away from a tailgater. |
| `ConstantVelocityAgent` | It holds its vehicle at one speed with the world's constant velocity mode. A collision stops the mode. |

The detection ranges are CARLA's. A basic agent looks 5 m ahead plus 1 s of travel. The range holds between the centers of the two vehicles.

CARLA's angle ranges are open, so a target at exactly 0 degrees is not in the range from 0 to 90 degrees. A target exactly on the line of the vehicle's center is therefore not seen.

The three behavior types keep these numbers:

| Type | Top speed | Below the limit | Minimum range | Braking distance |
|---|---|---|---|---|
| `CAUTIOUS` | 40 km/h | 6 km/h | 12 m | 6 m |
| `NORMAL` | 50 km/h | 3 km/h | 10 m | 5 m |
| `AGGRESSIVE` | 70 km/h | 1 km/h | 8 m | 4 m |

## Walk a pedestrian

Spawn a walker and a `controller.ai.walker` with the walker as its parent. Start the controller and send the walker to a place. After each world tick, tick the walker navigation. In the example, `start` is a pose on a sidewalk.

```mojo
from extensions.carla.navigation_walkers import (
    WalkerAIController,
    WalkerNavigation,
)

var navigation = WalkerNavigation(world)
var walker = world.spawn_actor(
    world.get_blueprint_library().at("walker.pedestrian.0020"), start
)
var controller = WalkerAIController(
    world.spawn_actor(
        world.get_blueprint_library().at("controller.ai.walker"), start, walker
    )
)
controller.start(world, navigation)
_ = controller.go_to_location(world, navigation, Vector3(20, -4.5, 0.15))
for _ in range(400):
    _ = world.tick()
    navigation.tick(world)
```

## The navigation mesh

CARLA bakes its pedestrian mesh offline with a third-party library. This port builds its own mesh from the map with these patterns:

- **A polygon graph.** Each lane is cut into strips at each resolution along s and at the ends of each crosswalk. A strip is a convex quad from the lane's two edges.
- **Area kinds.** A sidewalk strip is `AREA_SIDEWALK`. A road strip is `AREA_ROAD`, or `AREA_CROSSWALK` when its middle is in a crosswalk outline.
- **Shared-edge adjacency.** Two polygons are neighbors where their edges lie along each other for more than 5 cm, within a climb of 0.5 m.
- **A* over the polygons.** A step goes from portal middle to portal middle. It costs its length times the area cost.
- **The funnel algorithm.** The path is pulled tight through the portals. A point is added where the path goes into another area kind.
- **Area-weighted random points.** A random point is uniform over the area of the polygons that the filter allows.

CARLA's filters decide where a walker can go. Filter 0 keeps a walker off the roads, so it crosses only at crosswalks. Filter 1 lets it cross anywhere, at a cost of 10 a meter on a road. `set_pedestrians_cross_factor` sets the chance that a new walker gets filter 1.

## The crowd and the routes

The crowd moves each walker toward the next corner of its path at up to 1.47 m/s. It uses this port's own simple crowd steering:

- Seek: the walker heads for the next corner and slows within 0.6 m of its target.
- Separation: other walkers and the boxes of vehicles push the walker away.
- The walker stays on the polygons that its filter allows.

`WalkerManager` gives each route point an event. The first point on a road or a crosswalk is a stop and check. There the walker waits while the nearest traffic light is green or yellow for the vehicles. Then it waits until no vehicle is within 6 m ahead. At the end of its route, a walker goes to a new random point.

A walker that moves less than 0.5 m in 4 s gets a new random route, as in CARLA.

## Differences from CARLA

- The global route planner minimizes the graph's sample-count cost with a zero heuristic. It does not use CARLA's Euclidean heuristic. See [The route planner](#the-route-planner).
- A local planner that reaches a dead end keeps returning full brake on later steps, even with automatic waypoint generation enabled. It does not read an empty queue.
- The agents take the world at each call. CARLA's agents keep a reference to the world.
- The random choices use a seeded minimal-standard generator, not Python's `random` module.
- A lane change takes `OPTION_CHANGE_LANE_LEFT` or `OPTION_CHANGE_LANE_RIGHT` in place of the strings "left" and "right".
- The constant velocity agent reads its collisions with a `CollisionSensor` at each step. CARLA spawns a sensor actor.
- The mesh comes from the map, not from a baked file. The crowd's steering and its constants are this port's own.
- A walker keeps its body in the world. The navigation turns off its gravity and sets its pose at each tick.
- Where CARLA plans a new walker route again and again, this port plans once more and then waits.

## Not ported

- `draw_waypoints`, because this port has no debug drawing.
- A walker killed by a vehicle, because it needs a ragdoll.
- The obstacle avoidance of CARLA's crowd library, which is third-party. The separation pattern takes its place.

## Tests

The suites check the agents and the navigation against numbers from outside the port:

- `tests/test_carla_agents.mojo`: the helpers by hand, and the PID controllers, the local planner and the route planner against CARLA's own Python agents. The Python runs on a mock `carla` module with the lanes of the test town worked out by hand.
- `tests/test_carla_route_search.mojo`: hand-worked search counterexamples, integer cost boundaries, and an independent Floyd-Warshall all-pairs oracle. Public map queries also use that oracle. These checks establish graph-cost optimality without copying the production search.
- `tests/test_carla_route_boundaries.mojo`: public query checks, loose ends at road and lane boundaries, and short-section and junction traces from analytic OpenDRIVE inputs.
- `tests/test_carla_agents_drive.mojo`: a basic agent that reaches its destination, stops for a red light and stops behind a car. It also checks the three behavior types, car following, tailgating and the constant velocity agent.
- `tests/test_carla_navigation.mojo`: the mesh, the paths, the crowd and the walker manager on a hand-made street.
- `tests/test_carla_navigation_world.mojo`: the town's mesh, a walker that crosses only at the crosswalk, and a walker that waits for green.

## Search queues

The route planner and the pedestrian navigation mesh use one private binary min-heap. Route scores are unsigned 64-bit integers with a marker above the supported signed range. Pedestrian scores remain floating point. A lower search score comes first. Equal scores use the lower node id, as before. Route searches skip entries for closed nodes.

Pedestrian searches also skip an old score when a better route has replaced it, and can reopen a closed polygon. Partial paths retain the previous strict best-record update rule.

Area costs must be finite and at least 1. Both the setter and the read boundary check this, including direct changes to the public cost array. A NaN search score raises an error. Use an excluded area flag to block travel, as CARLA's filters do. This finite-cost check is a port safety rule; upstream Detour does not enforce it in its setter.

Each queue push and pop costs O(log n) for n pending entries. This change does not speed up graph construction or spatial queries. [Lane endpoint corrections](CARLA-maps#lane-endpoints) retain dead-end topology and keep backward traversal on its starting road.

Run `mojo run -I . bench/carla_search_queue_bench.mojo` to compare queue operations at 100, 1,000 and 10,000 entries. This benchmark excludes map lookup and geometry work. The tests compare complete generated paths with linear-selection references. The route reference uses the same zero-heuristic policy. A separate all-pairs oracle checks that route costs are minimum.

Run `mojo run -I . bench/carla_route_search_bench.mojo` to compare complete searches on generated sparse and wide-frontier graphs with 100, 1,000 and 10,000 nodes. Graph construction is outside the timed region. Both searches must return the same path.

## Search budgets

`NavigationSearchBudget` sets finite limits for one graph search. Its default policy allows 4,096 discovered nodes, 8,192 expansions, 8,192 resident heap entries, 32,768 heap pops, and 65,536 examined edges. These values are a resource policy, not an optimal size for every map. A caller can set larger finite limits.

There is no implicit unlimited mode. Each query checks all limits, including fields changed after construction. Negative limits raise an error.

The limits are independent. A zero value forbids that operation. A query from a node to itself needs one discovered node, one queue slot, and one pop. It needs no expansion or edge inspection.

A goal pop is not an expansion. A stale heap entry still consumes a pop. A reopened polygon can consume another expansion. Every inspected adjacency entry consumes an edge, including excluded areas and candidates that do not improve a path.

One wide node therefore cannot bypass the work limits.

Each query stops before the first operation that would exceed a limit. Node and queue capacity checks occur before either structure grows. The mesh stores only discovered polygon records. It does not initialize or scan a record for every polygon.

Reconstruction is bounded by the discovered records. Counts limit logical entries, not allocator bytes. Dynamic arrays and hash tables can reserve extra capacity.

`NavMesh.find_path_result` returns `NavPathResult`. Its `polygons` field holds the path. `GlobalRoutePlanner.search_nodes` searches typed graph node ids without localization. `path_search_result` localizes two map points first. Both return `RouteSearchResult`, whose `nodes` field holds the route. Each result has a `report` with these fields:

- `status`: `SEARCH_SUCCESS`, `SEARCH_UNREACHABLE`, `SEARCH_EXHAUSTED`, or `SEARCH_TRUNCATED`
- `limit`: the first exhausted resource, or `SEARCH_LIMIT_NONE`
- `discovered`, `expanded`, `queue_peak`, `popped`, and `examined`: exact logical counts
- `stale` and `reopened`: stale pops and reopened mesh nodes
- `output_truncated`: whether the output omitted a suffix

`SEARCH_TRUNCATED` means the goal was reached but the polygon output was shortened. An exhausted or unreachable result keeps that status when its output is also shortened. Check `output_truncated` separately. `max_polygons` remains an output limit.

It does not reduce search work. It must be nonnegative. Zero can return an empty prefix after a successful search.

A mesh partial path preserves the previous best-record rule. A newly admitted or improved record replaces the selected record only when its heuristic is strictly smaller than the selected record's current heuristic. Equal heuristics retain the previous choice. An improved route can change a record's portal position and increase its heuristic.

The rule does not recompute a global nearest polygon. An exhausted mesh result can include a discovered goal before it is settled. This does not certify an optimal path. An exhausted route path ends at the last settled node in deterministic cost and node-id order.

It can be empty before the first pop. It has no closest-to-goal guarantee. An unreachable route is empty. `path_search_result` appends the destination piece only after success, so its output can hold one more entry than `max_nodes`.

The existing list methods `find_path` and `path_search` accept an optional trailing budget. `trace_route` also forwards an optional trailing budget. `Navigation` accepts a constructor `search_budget` and exposes that field for later queries. It applies to path queries, agent routes, and crowd corridor replans.

They raise `Navigation search budget exhausted` when a limit stops the search. This prevents exhaustion from appearing to be unreachability. With sufficient limits, successful and unreachable outputs retain their previous behavior. The mesh still returns the same deterministic partial path and output prefix.

Route costs remain exact integers. Mesh area costs must still be finite and at least 1.

A failed direct walker-target search preserves the previous target and corridor. An exhausted crowd corridor replan also preserves those fields and raises the error to its caller. A multi-agent tick is not transactional. A route-point advance commits its index and walking state only after the direct-target search returns.

If another search fails during replacement-route preparation, the manager restores that walker's previous route record.

These limits do not bound graph construction, map localization, mesh building, or straight-path processing. They do not replace those operations' separate safety contracts.

### Measure bounded searches

`tests/test_carla_navigation_search_budget.mojo` checks zero and one limits, stale entries, reopened polygons, disconnected graphs, deterministic partial paths, output truncation, and independent shortest-path references. A 10,000-node wide graph checks exact counts, not only elapsed time.

`bench/carla_navigation_budget_bench.mojo` measures searches on 1,000, 10,000, and 100,000-node graphs. It also measures peak requested Mojo heap bytes with a Linux/ELF allocation hook for the pinned Mojo 1.1.0 runtime. The hook excludes allocator metadata and other threads. Graph construction is outside each measurement. Build and run it with:

```sh
cc -shared -fPIC -O2 bench/navigation_allocations.c -o /tmp/navigation_allocations.so
mojo build -I . bench/carla_navigation_budget_bench.mojo -o /tmp/navigation_budget_bench
LD_PRELOAD=/tmp/navigation_allocations.so /tmp/navigation_budget_bench /tmp/navigation_allocations.so
```

The complete-search comparison in `bench/carla_route_search_bench.mojo` supplies explicit sufficient budgets for its existing 10,000-node workloads. It still checks every output node against the former linear-selection search.


Run `mojo run -I . bench/carla_navigation_headroom_bench.mojo` to measure the default policy on the project fixtures. The route measurements used 1,072 queries over the town, long-road, and two-lane fixtures. Their maxima were 7 records, 7 expansions, 2 heap entries, 7 pops, and 8 edges. Across 384 sampled mesh queries, the maxima were 389 records, 375 expansions, 180 heap entries, 481 pops, and 1,309 edges.

These measurements establish headroom for these fixtures only.
