# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's collision stage, CARLA's `CollisionStage`.

Each step, each vehicle looks for the actor it must yield to:

1. The candidates are the actors whose paths share a geodesic grid with
   its path, within a radius of 20 m plus 2.65 s of its speed (8 m plus
   its half length below 2 m/s), and less than 4 m above or below it,
   nearest first.
2. Each candidate is negotiated. A vehicle's geodesic boundary is its
   box followed by a strip of its path, as wide as the vehicle, as long
   as 2.5 m plus (0.36 v)^2 and at least the distance to the leading
   vehicle. `collision_yields` decides from the distances between the
   two bodies and the two boundaries.
3. The first candidate it yields to is its hazard, unless the chance to
   ignore vehicles (or walkers) wins a draw. The room it has is the
   distance from its body to the other's boundary, less the distance to
   the leading vehicle.

A collision lock keeps a boundary from shrinking faster than the gap to
the vehicle ahead, so a vehicle closes in smoothly.

**Polygon distance.** CARLA measures with Boost.Geometry in double: zero
when two polygons meet or one holds the other, else the least distance
between their edges. Here the edges come from
`extensions.carla.map.segment_distance_2d`, and a polygon holds a point
by the nonzero winding rule, as Boost's winding strategy decides.
ThreeMojo's `math.shape_path.is_point_inside_polygon` uses the even-odd
rule and `Float32`, which differ for the self-crossing boundaries of a
curving path, so it does not serve here.

**Differences from CARLA.** CARLA walks the candidates in hash order
before it sorts them; here they come by id before the sort, and the sort
keeps ties in that order. The pair cache stores distances in actor-id
order and orients each read to the caller. The path strip includes its
last buffered waypoint when it reaches the end.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/CollisionStage.cpp`.
"""

from extensions.carla.actor import ActorId, GREEN, NO_ACTOR, OFF
from extensions.carla.map import segment_distance_2d
from extensions.carla.math import make_unit_vector
from extensions.carla.traffic_manager_constants import (
    BOUNDARY_EXTENSION_MINIMUM,
    COLLISION_RADIUS_MIN,
    COLLISION_RADIUS_RATE,
    COLLISION_RADIUS_STOP,
    COS_10_DEGREES,
    EPSILON,
    JUNCTION_LOOK_AHEAD,
    LOCKING_DISTANCE_PADDING,
    MAX_LOCKING_EXTENSION,
    MIN_REFERENCE_DISTANCE,
    OVERLAP_THRESHOLD,
    SQUARE_ROOT_OF_TWO,
    VEL_EXT_FACTOR,
    VERTICAL_OVERLAP_THRESHOLD,
    WALKER_TIME_EXTENSION,
)
from extensions.carla.traffic_manager_map import distance_squared
from extensions.carla.traffic_manager_shared import (
    CollisionHazardData,
    TrafficManagerShared,
)
from extensions.carla.traffic_manager_state import (
    TRAFFIC_PEDESTRIAN,
    TRAFFIC_VEHICLE,
    get_target_waypoint,
)
from math.vector3 import Vector3
from std.collections import Dict
from std.math import inf
from units.si import Length


@fieldwise_init
struct GeometryComparison(ImplicitlyCopyable, Writable):
    """Four distances between two vehicles, CARLA's
    `GeometryComparison`, in meters."""

    # From the reference vehicle's body to the other's boundary.
    var reference_vehicle_to_other_geodesic: Float64
    # From the other vehicle's body to the reference's boundary.
    var other_vehicle_to_reference_geodesic: Float64
    var inter_geodesic_distance: Float64
    var inter_bbox_distance: Float64


@fieldwise_init
struct CollisionLock(ImplicitlyCopyable, Writable):
    """A vehicle's hold on the vehicle ahead, CARLA's `CollisionLock`."""

    # In meters.
    var distance_to_lead_vehicle: Float64
    var initial_lock_distance: Float64
    var lead_vehicle_id: ActorId


def _winding(point: Vector3, polygon: List[Vector3]) -> Bool:
    """Whether a closed polygon holds a point, by the nonzero winding
    rule, in double."""
    var px = Float64(point.x)
    var py = Float64(point.y)
    var count = 0
    var n = len(polygon)
    for i in range(n):  # pragma: no branch
        var ax = Float64(polygon[i].x)
        var ay = Float64(polygon[i].y)
        var bx = Float64(polygon[(i + 1) % n].x)
        var by = Float64(polygon[(i + 1) % n].y)
        var side = (bx - ax) * (py - ay) - (px - ax) * (by - ay)
        if ay <= py:
            if by > py and side > 0.0:
                count += 1
        elif by <= py and side < 0.0:
            count -= 1
    return count != 0


def polygon_distance(a: List[Vector3], b: List[Vector3]) -> Float64:
    """Return the plan distance between two closed polygons, as
    Boost.Geometry's `distance`.

    Args:
        a: A polygon's corners, in meters. The last joins the first.
        b: Another polygon's corners.

    Returns:
        Zero if the edges meet or one polygon holds the other, else the
        least distance between their edges, in meters. Polygons with no
        corners are infinitely far apart.
    """
    var least = inf[DType.float64]()
    var n = len(a)
    var m = len(b)
    for i in range(n):
        for j in range(m):
            var d = segment_distance_2d(
                a[i], a[(i + 1) % n], b[j], b[(j + 1) % m]
            )
            least = min(least, d)
    if least == 0.0:
        return 0.0
    if n > 0 and m > 0 and (_winding(a[0], b) or _winding(b[0], a)):
        return 0.0
    return least


def collision_yields(g: GeometryComparison, ego_angular_priority: Bool) -> Bool:
    """Return whether a vehicle yields, CARLA's rule in
    `NegotiateCollision`.

    The two boundaries must touch (less than 0.1 m apart). Then, before a
    crash (the boxes 0.1 m apart or more), the vehicle yields when the
    other's body is in its path, or when the other's path is clear of its
    body and it has the lower priority: its body is not nearer the
    other's path, and is farther, or it faces the other more than the
    other faces it. After a crash, it yields when it faces the other more.

    Args:
        g: The distances between the two.
        ego_angular_priority: Whether the vehicle faces the other less
            than the other faces it.

    Returns:
        Whether it yields.
    """
    var threshold = Float64(OVERLAP_THRESHOLD.value)
    var paths_touching = g.inter_geodesic_distance < threshold
    var boxes_touching = g.inter_bbox_distance < threshold
    var ego_path_clear = g.other_vehicle_to_reference_geodesic > threshold
    var other_path_clear = g.reference_vehicle_to_other_geodesic > threshold
    var ego_path_priority = (
        g.reference_vehicle_to_other_geodesic
        < g.other_vehicle_to_reference_geodesic
    )
    var other_path_priority = (
        g.reference_vehicle_to_other_geodesic
        > g.other_vehicle_to_reference_geodesic
    )
    var lower_priority = not ego_path_priority and (
        other_path_priority or not ego_angular_priority
    )
    var blocked = not ego_path_clear or (other_path_clear and lower_priority)
    var yield_pre_crash = not boxes_touching and blocked
    var yield_post_crash = boxes_touching and not ego_angular_priority
    return paths_touching and (yield_pre_crash or yield_post_crash)


struct CollisionStage(Movable):
    """The collision stage, CARLA's `CollisionStage`."""

    var collision_locks: Dict[Int, CollisionLock]
    # The smaller actor id is the reference in every cached comparison.
    var geometry_cache: Dict[Int, GeometryComparison]
    var geodesic_boundary_map: Dict[Int, List[Vector3]]

    def __init__(out self):
        """Create an empty stage."""
        self.collision_locks = Dict[Int, CollisionLock]()
        self.geometry_cache = Dict[Int, GeometryComparison]()
        self.geodesic_boundary_map = Dict[Int, List[Vector3]]()

    def update(mut self, index: Int, mut shared: TrafficManagerShared) raises:
        """Find one vehicle's hazard, `Update`.

        Args:
            index: The vehicle's place in `shared.vehicle_id_list`.
            shared: The traffic manager's state.

        Raises:
            Error: If the index is out of range, or a tracked vehicle has
                no path.
        """
        if index < 0 or index >= len(shared.vehicle_id_list):
            raise Error("The vehicle index is out of range")
        var obstacle = NO_ACTOR
        var hazard = False
        var margin = inf[DType.float32]()
        var ego = shared.vehicle_id_list[index]
        if shared.simulation_state.contains_actor(ego):
            var ego_location = shared.simulation_state.get_location(ego)
            if ego.value not in shared.buffer_map:
                raise Error("A tracked vehicle has no path")
            var look_ahead = get_target_waypoint(
                shared.buffer_map[ego.value],
                shared.local_map,
                JUNCTION_LOOK_AHEAD,
            )[1]
            var velocity = shared.simulation_state.get_velocity(ego).length()
            var lead = shared.parameters.get_distance_to_leading_vehicle(
                ego
            ).value
            var reach = (
                COLLISION_RADIUS_RATE.value * velocity
                + COLLISION_RADIUS_MIN.value
            )
            var radius_square = reach * reach
            if velocity < 2.0:
                var stop = (
                    COLLISION_RADIUS_STOP.value
                    + shared.simulation_state.get_dimensions(ego).x
                )
                radius_square = stop * stop
            # CARLA compares a distance with a squared radius here.
            if lead > radius_square:
                radius_square = lead * lead
            var candidates = List[ActorId]()
            var distances = List[Float32]()
            for other in shared.track_traffic.get_overlapping_vehicles(ego):
                var at = shared.simulation_state.get_location(other)
                var d = distance_squared(at, ego_location)
                if (
                    other != ego
                    and d < radius_square
                    and abs(ego_location.z - at.z)
                    < VERTICAL_OVERLAP_THRESHOLD.value
                ):
                    # Insertion by distance, stable.
                    var k = len(candidates)
                    while k > 0 and distances[k - 1] > d:
                        k -= 1
                    candidates.insert(k, other)
                    distances.insert(k, d)
            var i = 0
            while i < len(candidates) and not hazard:
                var other = candidates[i]
                i += 1
                var other_type = shared.simulation_state.get_type(other)
                # CARLA also asks that the other is tracked. It is: its
                # location was read above, which raises for an untracked
                # actor.
                if shared.parameters.get_collision_detection(ego, other):
                    var result = self.negotiate_collision(
                        ego, other, look_ahead, shared
                    )
                    if result[0] and (
                        (
                            other_type == TRAFFIC_VEHICLE
                            and Float64(
                                shared.parameters.get_percentage_ignore_vehicles(
                                    ego
                                )
                            )
                            <= shared.random_device.next()
                        )
                        or (
                            other_type == TRAFFIC_PEDESTRIAN
                            and Float64(
                                shared.parameters.get_percentage_ignore_walkers(
                                    ego
                                )
                            )
                            <= shared.random_device.next()
                        )
                    ):
                        hazard = True
                        obstacle = other
                        margin = result[1]
        shared.collision_frame[index] = CollisionHazardData(
            Length(margin), obstacle, hazard
        )

    def remove_actor(mut self, actor: ActorId) raises:
        """Drop a vehicle's lock, `RemoveActor`.

        Args:
            actor: The vehicle.

        Raises:
            Error: Never; the lookup is checked.
        """
        if actor.value in self.collision_locks:
            _ = self.collision_locks.pop(actor.value)

    def reset(mut self):
        """Drop every lock and cached comparison, `Reset`."""
        self.collision_locks = Dict[Int, CollisionLock]()
        self.clear_cycle_cache()

    def clear_cycle_cache(mut self):
        """Forget this step's boundaries and distances, `ClearCycleCache`."""
        self.geodesic_boundary_map = Dict[Int, List[Vector3]]()
        self.geometry_cache = Dict[Int, GeometryComparison]()

    def get_bounding_box_extension(
        self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> Float32:
        """Return how far a vehicle's boundary reaches ahead,
        `GetBoundingBoxExtention`.

        Args:
            actor: The vehicle.
            shared: The traffic manager's state.

        Returns:
            2.5 m plus (0.36 v)^2 for a forward speed v in m/s, or the
            locked distance plus 4 m while that is less than 10 m past the
            lock's start, in meters.

        Raises:
            Error: If the vehicle is not tracked.
        """
        var velocity = shared.simulation_state.get_velocity(actor).dot(
            shared.simulation_state.get_heading(actor)
        )
        var velocity_extension = VEL_EXT_FACTOR * velocity
        var extension = (
            BOUNDARY_EXTENSION_MINIMUM.value
            + velocity_extension * velocity_extension
        )
        var lock = self.collision_locks.get(actor.value)
        if Bool(lock):
            var boundary = Float32(
                lock.value().distance_to_lead_vehicle
                + Float64(LOCKING_DISTANCE_PADDING.value)
            )
            if Float64(boundary) - lock.value().initial_lock_distance < Float64(
                MAX_LOCKING_EXTENSION.value
            ):
                extension = boundary
        return extension

    def get_boundary(
        self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> List[Vector3]:
        """Return a vehicle's box in plan, `GetBoundary`.

        A walker's box grows by 1.5 s of its speed on each side.

        Args:
            actor: The actor.
            shared: The traffic manager's state.

        Returns:
            The four corners, clockwise seen from above in CARLA's frame.

        Raises:
            Error: If the actor is not tracked.
        """
        ref state = shared.simulation_state
        var heading = state.get_heading(actor)
        var forward_extension = Float32(0.0)
        if state.get_type(actor) == TRAFFIC_PEDESTRIAN:
            forward_extension = (
                state.get_velocity(actor).length() * WALKER_TIME_EXTENSION.value
            )
        var dimensions = state.get_dimensions(actor)
        var x_vector = heading * (dimensions.x + forward_extension)
        var perpendicular = make_unit_vector(
            Vector3(-heading.y, heading.x, 0), EPSILON
        )
        var y_vector = perpendicular * (dimensions.y + forward_extension)
        var location = state.get_location(actor)
        return [
            location + (x_vector - y_vector),
            location + (x_vector * -1.0 - y_vector),
            location + (x_vector * -1.0 + y_vector),
            location + (x_vector + y_vector),
        ]

    def get_geodesic_boundary(
        mut self, actor: ActorId, shared: TrafficManagerShared
    ) raises -> List[Vector3]:
        """Return a vehicle's box and the strip of path ahead of it,
        `GetGeodesicBoundary`, cached for the step.

        Args:
            actor: The actor.
            shared: The traffic manager's state.

        Returns:
            The right edge of the strip from far to near, the box, and the
            left edge from near to far; the box alone for an actor with no
            path.

        Raises:
            Error: If the actor is not tracked.
        """
        var cached = self.geodesic_boundary_map.get(actor.value)
        if Bool(cached):
            return cached.value().copy()
        var bbox = self.get_boundary(actor, shared)
        var boundary = bbox.copy()
        var found = shared.buffer_map.get(actor.value)
        if Bool(found):
            ref map = shared.local_map
            var buffer = found.value().copy()
            var extension = max(
                shared.parameters.get_distance_to_leading_vehicle(actor).value,
                self.get_bounding_box_extension(actor, shared),
            )
            var extension_square = extension * extension
            var dimensions = shared.simulation_state.get_dimensions(actor)
            var width = dimensions.y
            var target = get_target_waypoint(buffer, map, Length(dimensions.x))
            var start = map.at(target[0]).location()
            var left = List[Vector3]()
            var right = List[Vector3]()
            var has_end = False
            var end_forward = Vector3(0, 0, 0)
            var reached = False
            var j = target[1]
            # Read node j before testing its distance and final index.
            # The endpoint must not lag one waypoint behind the index.
            while not reached:
                ref point = map.at(buffer[j])
                if (
                    distance_squared(start, point.location()) > extension_square
                    or j == len(buffer) - 1
                ):
                    reached = True
                var forward = point.forward_vector()
                if (
                    not has_end
                    or end_forward.dot(forward) < COS_10_DEGREES
                    or reached
                ):
                    var side = (
                        make_unit_vector(
                            Vector3(-forward.y, forward.x, 0), EPSILON
                        )
                        * width
                    )
                    left.append(point.location() + side)
                    right.append(point.location() + side * -1.0)
                    has_end = True
                    end_forward = forward
                j += 1
            boundary = List[Vector3]()
            for k in range(len(right) - 1, -1, -1):  # pragma: no branch
                boundary.append(right[k])
            boundary.extend(bbox^)
            boundary.extend(left^)
        self.geodesic_boundary_map[actor.value] = boundary.copy()
        return boundary^

    def get_geometry_between_actors(
        mut self,
        reference: ActorId,
        other: ActorId,
        shared: TrafficManagerShared,
    ) raises -> GeometryComparison:
        """Return the four distances between two actors,
        `GetGeometryBetweenActors`, cached for the step.

        The cache uses the smaller actor id as its reference. A read
        swaps only the two cross distances when the larger actor asks.
        The first caller and later query order do not change the result.

        Args:
            reference: The vehicle that asks.
            other: The other actor.
            shared: The traffic manager's state.

        Returns:
            The distances, in meters.

        Raises:
            Error: If an actor is not tracked.
        """
        var low = min(reference.value, other.value)
        var high = max(reference.value, other.value)
        var key = (low << 32) | high
        var cached = self.geometry_cache.get(key)
        var result: GeometryComparison
        if Bool(cached):
            result = cached.value()
        else:
            var reference_box = self.get_boundary(ActorId(low), shared)
            var other_box = self.get_boundary(ActorId(high), shared)
            var reference_geodesic = self.get_geodesic_boundary(
                ActorId(low), shared
            )
            var other_geodesic = self.get_geodesic_boundary(
                ActorId(high), shared
            )
            result = GeometryComparison(
                polygon_distance(reference_box, other_geodesic),
                polygon_distance(other_box, reference_geodesic),
                polygon_distance(reference_geodesic, other_geodesic),
                polygon_distance(reference_box, other_box),
            )
            self.geometry_cache[key] = result
        if reference.value > other.value:
            var swap = result.reference_vehicle_to_other_geodesic
            result.reference_vehicle_to_other_geodesic = (
                result.other_vehicle_to_reference_geodesic
            )
            result.other_vehicle_to_reference_geodesic = swap
        return result

    def negotiate_collision(
        mut self,
        reference: ActorId,
        other: ActorId,
        look_ahead_index: Int,
        shared: TrafficManagerShared,
    ) raises -> Tuple[Bool, Float32]:
        """Decide whether a vehicle yields to an actor,
        `NegotiateCollision`.

        The two are compared only when the vehicle is not stopped by a
        light at a junction's entrance, and the other is within reach:
        in front and within its boundary plus both lengths, or, inside a
        junction, within both boundaries plus both lengths.

        Args:
            reference: The vehicle.
            other: The other actor.
            look_ahead_index: The index of the vehicle's node 5 m on.
            shared: The traffic manager's state.

        Returns:
            Whether it yields, and the room it has in meters (infinite
            when it does not yield).

        Raises:
            Error: If an actor is not tracked, or the vehicle has no path.
        """
        var hazard = False
        var margin = inf[DType.float32]()
        ref state = shared.simulation_state
        var reference_location = state.get_location(reference)
        var other_location = state.get_location(other)
        var reference_heading = state.get_heading(reference)
        var reference_to_other = make_unit_vector(
            other_location - reference_location, EPSILON
        )
        var other_heading = state.get_heading(other)
        var other_to_reference = make_unit_vector(
            reference_location - other_location, EPSILON
        )
        var reference_length = (
            state.get_dimensions(reference).x * SQUARE_ROOT_OF_TWO
        )
        var other_length = state.get_dimensions(other).x * SQUARE_ROOT_OF_TWO
        var inter_vehicle_distance = distance_squared(
            reference_location, other_location
        )
        var ego_extension = self.get_bounding_box_extension(reference, shared)
        var other_extension = self.get_bounding_box_extension(other, shared)
        var inter_vehicle_length = reference_length + other_length
        var ego_range = ego_extension + inter_vehicle_length
        var cross_range = ego_extension + inter_vehicle_length + other_extension
        var in_ego_range = inter_vehicle_distance < ego_range * ego_range
        var in_cross_range = inter_vehicle_distance < cross_range * cross_range
        var reference_dot = reference_heading.dot(reference_to_other)
        var other_in_front = reference_dot > 0
        if reference.value not in shared.buffer_map:
            raise Error("A tracked vehicle has no path")
        ref buffer = shared.buffer_map[reference.value]
        ref closest = shared.local_map.at(buffer[0])
        var ego_inside_junction = closest.check_junction()
        var light = state.get_tls(reference)
        var stopped_by_light = light.tl_state != GREEN and light.tl_state != OFF
        var at_entrance = (
            not closest.check_junction()
            and shared.local_map.at(buffer[look_ahead_index]).check_junction()
        )
        # Choose the range policy once. Repeating the junction flag in
        # both alternatives creates a coupled, non-independent condition.
        # The light guard still short-circuits before either range policy.
        var may_negotiate = False
        if not (at_entrance and light.at_traffic_light and stopped_by_light):
            if ego_inside_junction:
                if in_cross_range:
                    may_negotiate = True
            else:
                if other_in_front and in_ego_range:
                    may_negotiate = True
        if may_negotiate:
            var g = self.get_geometry_between_actors(reference, other, shared)
            var ego_angular_priority = reference_dot < other_heading.dot(
                other_to_reference
            )
            if collision_yields(g, ego_angular_priority):
                hazard = True
                var specific = max(
                    shared.parameters.get_distance_to_leading_vehicle(
                        reference
                    ).value,
                    MIN_REFERENCE_DISTANCE.value,
                )
                margin = Float32(
                    max(
                        g.reference_vehicle_to_other_geodesic
                        - Float64(specific),
                        0.0,
                    )
                )
                var lock = self.collision_locks.get(reference.value)
                if Bool(lock) and lock.value().lead_vehicle_id == other:
                    var held = lock.value()
                    if g.other_vehicle_to_reference_geodesic < Float64(
                        OVERLAP_THRESHOLD.value
                    ):
                        held.distance_to_lead_vehicle = g.inter_bbox_distance
                    else:
                        held.distance_to_lead_vehicle = (
                            g.reference_vehicle_to_other_geodesic
                        )
                    self.collision_locks[reference.value] = held
                else:
                    self.collision_locks[reference.value] = CollisionLock(
                        g.inter_bbox_distance, g.inter_bbox_distance, other
                    )
        if not hazard and reference.value in self.collision_locks:
            _ = self.collision_locks.pop(reference.value)
        return (hazard, margin)
