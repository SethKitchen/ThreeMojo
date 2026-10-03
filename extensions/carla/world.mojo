# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's world: actors on a map, stepped in fixed ticks.

A `World` holds a `Map`, a physics world with the map's road and
sidewalk surfaces as static colliders, the blueprint library, the
weather, the episode settings and every actor. It is an entity registry:
an actor is a numbered record, and a vehicle's, walker's, light's or
sign's own state sits in a list for its kind. Every operation of CARLA's
client `Actor`, `Vehicle`, `Walker`, `TrafficLight` and `TrafficSign` is
a method of the world that takes the actor's id.

**The tick.** `tick` is a fixed-step game loop. With `fixed_delta_seconds`
set, one tick does this, in order:

1. The frame counts up, and the time moves on by the fixed step.
2. The stop and yield signs' give-way timers run down.
3. The traffic-light groups advance their cycles.
4. The physics steps, cut into substeps no longer than
   `max_substep_delta_time`, at most `max_substeps` of them. Each live
   walker's procedural gait advances from horizontal speed and tick time.
5. The world finds which road boxes each vehicle is in, and tells the
   lights and signs about each vehicle that came or went.
6. The world takes its snapshot.

The sources are CARLA's `LibCarla/source/carla/client/World.cpp`,
`Actor.cpp`, `Vehicle.cpp`, `Walker.cpp`, `TrafficLight.cpp`,
`TrafficSign.cpp`, `ActorList.cpp`, `rpc/EpisodeSettings.h` and
`client/detail/Simulator.cpp`, and CARLA's simulator plugin,
`Carla/Game/CarlaEpisode.cpp`, `CarlaGameModeBase.cpp`,
`Carla/Actor/ActorRegistry.cpp` and `Carla/Sensor/WorldObserver.cpp`.

**Differences from CARLA.**

- There is no server and no client: a method returns at once. A world
  has no asynchronous mode and no wall clock; `tick` needs
  `fixed_delta_seconds`.
- A spawn fails when the new vehicle's or walker's box meets another
  vehicle's or walker's. The road and props are not checked.
- A vehicle or a walker cannot be attached to a parent. A spring-arm
  attachment follows its parent rigidly.
- A destroyed vehicle's or walker's body stays in the physics world,
  parked far below the map with no collisions: the physics world has no
  way to remove a body. Traffic lights, signs and the spectator cannot be
  destroyed. The children of a destroyed actor stay where they are.
- An actor without a body reports zero velocity and acceleration.
- The on-tick callbacks, the map layers, the environment objects, the
  textures, the light manager, `cast_ray`, `set_simulate_physics` and the
  large-map settings are not ported.
"""

from extensions.carla.actor import (
    ACTOR_ACTIVE,
    ACTOR_INVALID,
    Actor,
    ActorId,
    ActorKind,
    AttachmentType,
    GREEN,
    NO_ACTOR,
    OTHER_ACTOR,
    RIGID,
    SENSOR_ACTOR,
    TRAFFIC_LIGHT_ACTOR,
    TRAFFIC_SIGN_ACTOR,
    TrafficLightState,
    VEHICLE_ACTOR,
    WALKER_ACTOR,
    YELLOW,
    RED,
    compose,
    no_rotation,
    relative,
    world_obb,
)
from extensions.carla.blueprint import (
    ActorAttributeValue,
    ActorBlueprint,
    BlueprintLibrary,
    default_blueprint_library,
    wildcard_match,
)
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.map import Landmark, Map, Waypoint, is_traffic_light
from extensions.carla.mesh_factory import generate_mesh
from extensions.carla.physics.body import BodyId
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.physics.shape import PhysicsMaterial
from extensions.carla.physics.simulation import CarlaPhysics
from extensions.carla.physics.vehicle_control import (
    AckermannControllerSettings,
    VehicleAckermannControl,
    VehicleControl,
    VehicleFailureState,
    VehicleTelemetryData,
)
from extensions.carla.physics.vehicle_physics import VehiclePhysicsControl
from extensions.carla.physics.walker import WalkerControl, WalkerParameters
from extensions.carla.road_info import JuncId, SignalId
from extensions.carla.sensor import (
    CAR,
    PEDESTRIAN,
    ROAD,
    ROAD_LINE,
    SIDEWALK,
    STATIC,
    SemanticTag,
    TRAFFIC_LIGHT,
    TRAFFIC_SIGN,
    UNLABELED,
    WALL,
)
from extensions.carla.traffic_light import (
    TrafficLightManager,
    affected_lane_waypoints,
    light_transform,
    stop_waypoints,
)
from extensions.carla.traffic_sign import (
    SPEED_LIMIT_SIGN,
    STOP_SIGN,
    SignalUpdate,
    TrafficSign,
    TriggerBox,
    give_way_boxes,
    sign_kind_of,
    sign_type_id,
    speed_limit_boxes,
)
from extensions.carla.transform import CarlaTransform
from extensions.carla.vehicle import (
    DOOR_ALL,
    LIGHTS_NONE,
    VehicleData,
    VehicleDoor,
    VehicleLightState,
    VehicleRecord,
    VehicleWheelLocation,
    vehicle_bounding_box,
    vehicle_physics_control,
    vehicle_semantic_tag,
)
from extensions.carla.walker import (
    WalkerBoneControlIn,
    WalkerBoneControlOut,
    WalkerRecord,
)
from extensions.carla.walker_gait import WalkerGait
from extensions.carla.weather import WeatherParameters
from extensions.carla.world_snapshot import (
    ActorSnapshot,
    Timestamp,
    TrafficLightData,
    WorldSnapshot,
)
from math.obb import OBB
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.hashlib import Hasher
from std.collections import Set
from std.math import ceil
from std.time import perf_counter_ns
from units.si import (
    Acceleration,
    Angle,
    RADIAN,
    Duration,
    Length,
    METER,
    SECOND,
    Velocity,
)

comptime _TO_DEGREES = Float32(57.29577951308232)
# CARLA's spawn points stand this far above the road.
comptime _SPAWN_HEIGHT = Float32(0.5)
# Where a destroyed body waits, below any map.
comptime _PARKED = Vector3(0, 0, -10000)
# The part of a step a substep count rounds away, so that 0.05 / 0.01
# gives five substeps and not six.
comptime _SUBSTEP_SLACK = 1e-6


struct EpisodeSettings(Copyable, Equatable, Movable, Writable):
    """How a world steps, CARLA's `rpc::EpisodeSettings`."""

    var synchronous_mode: Bool
    var no_rendering_mode: Bool
    var fixed_delta_seconds: Optional[Duration]
    var substepping: Bool
    var max_substep_delta_time: Duration
    var max_substeps: Int
    var max_culling_distance: Length
    var deterministic_ragdolls: Bool
    var tile_stream_distance: Length
    var actor_active_distance: Length
    var spectator_as_ego: Bool

    def __init__(out self):
        """Create CARLA's defaults: asynchronous, no fixed step, up to ten
        substeps of 0.01 s."""
        self.synchronous_mode = False
        self.no_rendering_mode = False
        self.fixed_delta_seconds = None
        self.substepping = True
        self.max_substep_delta_time = Duration(0.01, SECOND)
        self.max_substeps = 10
        self.max_culling_distance = Length(0, METER)
        self.deterministic_ragdolls = True
        self.tile_stream_distance = Length(3000, METER)
        self.actor_active_distance = Length(2000, METER)
        self.spectator_as_ego = True

    def __init__(
        out self,
        synchronous_mode: Bool,
        no_rendering_mode: Bool,
        fixed_delta_seconds: Duration,
    ):
        """Create settings in CARLA's argument order, the rest defaults.

        Args:
            synchronous_mode: Whether the client drives each tick.
            no_rendering_mode: Whether cameras stay dark.
            fixed_delta_seconds: The step. Zero or less means none, as in
                CARLA.
        """
        self = EpisodeSettings()
        self.synchronous_mode = synchronous_mode
        self.no_rendering_mode = no_rendering_mode
        if fixed_delta_seconds.value > 0:
            self.fixed_delta_seconds = fixed_delta_seconds

    def check(self) raises:
        """Refuse settings a world cannot step with.

        Raises:
            Error: If the fixed step is set and not more than zero, the
                substep time is not more than zero, or `max_substeps` is
                not from 1 to 16, CARLA's range.
        """
        if Bool(self.fixed_delta_seconds) and not (
            self.fixed_delta_seconds.value().value > 0
        ):
            raise Error("fixed_delta_seconds must be more than zero")
        if not (self.max_substep_delta_time.value > 0):
            raise Error("max_substep_delta_time must be more than zero")
        if self.max_substeps < 1 or self.max_substeps > 16:
            raise Error("max_substeps must be from 1 to 16")

    def substep_count(self, dt: Duration) -> Int:
        """Return how many physics steps one tick is cut into.

        Args:
            dt: The tick.

        Returns:
            One without substepping. Otherwise the fewest steps no longer
            than `max_substep_delta_time`, at most `max_substeps`.
        """
        if not self.substepping:
            return 1
        var n = Int(
            ceil(
                Float64(dt.value) / Float64(self.max_substep_delta_time.value)
                - _SUBSTEP_SLACK
            )
        )
        return min(max(n, 1), self.max_substeps)

    def __eq__(self, other: Self) -> Bool:
        """Return True if every setting matches, as CARLA compares.

        Args:
            other: The other settings.

        Returns:
            Whether all eleven settings are equal.
        """
        var same_step = Bool(self.fixed_delta_seconds) == Bool(
            other.fixed_delta_seconds
        )
        if same_step and Bool(self.fixed_delta_seconds):
            same_step = (
                self.fixed_delta_seconds.value()
                == other.fixed_delta_seconds.value()
            )
        return (
            same_step
            and self.synchronous_mode == other.synchronous_mode
            and self.no_rendering_mode == other.no_rendering_mode
            and self.substepping == other.substepping
            and self.max_substep_delta_time == other.max_substep_delta_time
            and self.max_substeps == other.max_substeps
            and self.max_culling_distance == other.max_culling_distance
            and self.deterministic_ragdolls == other.deterministic_ragdolls
            and self.tile_stream_distance == other.tile_stream_distance
            and self.actor_active_distance == other.actor_active_distance
            and self.spectator_as_ego == other.spectator_as_ego
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the settings.

        Args:
            writer: The destination.
        """
        writer.write(
            "WorldSettings(synchronous_mode=",
            self.synchronous_mode,
            ",no_rendering_mode=",
            self.no_rendering_mode,
            ",fixed_delta_seconds=",
        )
        if Bool(self.fixed_delta_seconds):
            writer.write(self.fixed_delta_seconds.value().value)
        else:
            writer.write("None")
        writer.write(",substepping=", self.substepping, ")")


@fieldwise_init
struct LabelledPoint(ImplicitlyCopyable, Writable):
    """A point on a surface and what the surface is, `rpc::LabelledPoint`."""

    var location: Vector3
    var label: SemanticTag


@fieldwise_init
struct _Overlap(Hashable, ImplicitlyCopyable, KeyElement):
    """A vehicle inside one road box."""

    var vehicle: Int
    # 0: a light's box, 1: a sign's effect box, 2: a sign's check box.
    var owner: Int
    var index: Int
    var box: Int

    def __hash__[H: Hasher](self, mut hasher: H):
        self.vehicle.__hash__(hasher)
        self.owner.__hash__(hasher)
        self.index.__hash__(hasher)
        self.box.__hash__(hasher)


def surface_tag(kind: Int) -> SemanticTag:
    """Return the tag a camera sees on a road mesh's surface kind.

    Args:
        kind: A `mesh_factory.SurfaceKind` value.

    Returns:
        Road for the driving surface, sidewalk for a sidewalk's top and
        curb, wall for a wall, and road line for a crosswalk or paint.
    """
    if kind == 0:
        return ROAD
    if kind == 1 or kind == 2:
        return SIDEWALK
    if kind == 3:
        return WALL
    return ROAD_LINE


def cut_sign_id(id: String) -> String:
    """Return a signal id as a snapshot holds it.

    Args:
        id: The OpenDRIVE signal id.

    Returns:
        The longest UTF-8 prefix that fits CARLA's 32-byte field. This
        limits bytes, not characters, and never keeps a partial codepoint.

        An id that fits is unchanged. The world keeps the full id outside
        this snapshot field.
    """
    if id.byte_length() <= 32:
        return id
    var end = 32
    # Byte 32 exists. Back up over continuation bytes to a codepoint start.
    # A valid UTF-8 String needs at most three steps; ASCII keeps 32 bytes.
    while (id.as_bytes()[end] & 0xC0) == 0x80:
        end -= 1
    return String(id[byte=0:end])


def _origin() -> CarlaTransform:
    return CarlaTransform(
        Length(0, METER), Length(0, METER), Length(0, METER), no_rotation()
    )


def _obbs(boxes: List[TriggerBox]) raises -> List[OBB]:
    var out = List[OBB]()
    for b in boxes:
        out.append(b.obb())
    return out^


def _quaternion(rotation: CarlaTransform) -> Quaternion:
    """A CARLA pose's turn as the physics tier's quaternion."""
    return Quaternion.from_matrix(rotation.matrix())


struct World(Movable):
    """A CARLA world: a map, its actors and their physics."""

    var map: Map
    var physics: CarlaPhysics
    var blueprints: BlueprintLibrary
    var settings: EpisodeSettings
    var weather: WeatherParameters
    var imu_gravity: Acceleration
    var episode_id: Int
    var frame: Int
    var elapsed_seconds: Float64
    var delta_seconds: Float64
    # One record per id; the id is the index plus one.
    var actors: List[Actor]
    var vehicles: List[VehicleRecord]
    var walkers: List[WalkerRecord]
    var traffic_lights: TrafficLightManager
    var signs: List[TrafficSign]
    var spawn_points: List[CarlaTransform]
    var spectator: ActorId
    var snapshot: WorldSnapshot
    # The road bodies and the tag of each.
    var _road_bodies: List[BodyId]
    var _road_tags: List[SemanticTag]
    var _light_actors: List[ActorId]
    var _light_boxes: List[List[OBB]]
    var _effect_boxes: List[List[OBB]]
    var _check_boxes: List[List[OBB]]
    var _overlaps: List[_Overlap]
    # A walker's box, measured once from a capsule of the physics tier.
    var _walker_box: BoundingBox

    def __init__(
        out self,
        var map: Map,
        resolution: Length = Length(2, METER),
        episode_id: Int = 1,
    ) raises:
        """Build a world on a map.

        The road and sidewalk surfaces become static colliders. The
        spectator is actor 1; the traffic lights and the signs follow.
        The spawn points are the start of each lane of the map's topology,
        0.5 m up, as CARLA makes them for a map with none placed.

        Args:
            map: The map.
            resolution: The spacing of the collider mesh's rows along each
                lane.
            episode_id: The world's episode id.

        Raises:
            Error: If the resolution is not more than zero, or a map query
                fails.
        """
        self.map = map^
        self.physics = CarlaPhysics()
        self.blueprints = default_blueprint_library()
        self.settings = EpisodeSettings()
        self.weather = WeatherParameters()
        self.imu_gravity = Acceleration(9.81)
        self.episode_id = episode_id
        self.frame = 0
        self.elapsed_seconds = 0
        self.delta_seconds = 0
        self.actors = List[Actor]()
        self.vehicles = List[VehicleRecord]()
        self.walkers = List[WalkerRecord]()
        self.traffic_lights = TrafficLightManager()
        self.signs = List[TrafficSign]()
        self.spawn_points = List[CarlaTransform]()
        self.spectator = NO_ACTOR
        self.snapshot = WorldSnapshot(episode_id, Timestamp(0, 0, 0, 0))
        self._road_bodies = List[BodyId]()
        self._road_tags = List[SemanticTag]()
        self._light_actors = List[ActorId]()
        self._light_boxes = List[List[OBB]]()
        self._effect_boxes = List[List[OBB]]()
        self._check_boxes = List[List[OBB]]()
        self._overlaps = List[_Overlap]()
        self._walker_box = BoundingBox(Vector3(0, 0, 0))
        self._build_colliders(resolution)
        self._measure_walker()
        self.spectator = self._register(
            "spectator",
            OTHER_ACTOR,
            List[ActorAttributeValue](),
            _origin(),
            BoundingBox(Vector3(0, 0, 0)),
            List[SemanticTag](),
        )
        self._place_signals()
        for pair in self.map.generate_topology():
            var t = self.map.compute_transform(pair[0])
            t.location.z += _SPAWN_HEIGHT
            self.spawn_points.append(t)
        self.snapshot = self._take_snapshot()

    # --- building ---------------------------------------------------------------

    def _build_colliders(mut self, resolution: Length) raises:
        var mesh = generate_mesh(self.map, resolution)
        if len(mesh.groups) == 0:
            return
        ref position = mesh.attribute_view("position")
        # The mesh has a group, checked above.
        for group in mesh.groups:  # pragma: no branch
            var triangles = List[Triangle]()
            # A group holds one triangle at least.
            for t in range(
                group.start // 3, (group.start + group.count) // 3
            ):  # pragma: no branch
                triangles.append(
                    Triangle(
                        position.vector3(mesh.index[3 * t]),
                        position.vector3(mesh.index[3 * t + 1]),
                        position.vector3(mesh.index[3 * t + 2]),
                    )
                )
            var body = self.physics.add_static_mesh(
                triangles^, PhysicsMaterial.default()
            )
            self._road_bodies.append(body)
            self._road_tags.append(surface_tag(group.material_index.value))

    def _measure_walker(mut self) raises:
        var probe = CarlaPhysics()
        var w = probe.add_walker(Vector3(0, 0, 0), WalkerParameters())
        var box = probe.world.bounds(probe.walker_body(w))
        var half = (box.max - box.min) * Float32(0.5)
        self._walker_box = BoundingBox((box.max + box.min) * Float32(0.5), half)

    def _register(
        mut self,
        type_id: String,
        kind: ActorKind,
        var attributes: List[ActorAttributeValue],
        transform: CarlaTransform,
        box: BoundingBox,
        var tags: List[SemanticTag],
    ) raises -> ActorId:
        var id = ActorId(len(self.actors) + 1)
        self.actors.append(
            Actor(id, type_id, kind, attributes^, transform, box, tags^)
        )
        return id

    def _place_signals(mut self) raises:
        self.traffic_lights = TrafficLightManager.from_map(self.map)
        for i in range(len(self.traffic_lights.lights)):
            var pose = self.traffic_lights.lights[i].transform
            var id = self._register(
                "traffic.traffic_light",
                TRAFFIC_LIGHT_ACTOR,
                List[ActorAttributeValue](),
                pose,
                BoundingBox(Vector3(0, 0, 0)),
                [TRAFFIC_LIGHT],
            )
            self.actors[id.value - 1].handle = i
            self._light_actors.append(id)
            self._light_boxes.append(_obbs(self.traffic_lights.lights[i].boxes))
        for s in self.map.signals:
            var kind = sign_kind_of(s.type, s.subtype, s.name)
            if not Bool(kind):
                continue
            var sign = TrafficSign(
                s.signal_id,
                kind.value(),
                light_transform(s.transform),
                Velocity(Float32(s.value), KILOMETER_PER_HOUR),
            )
            if kind.value() == SPEED_LIMIT_SIGN:
                sign.effect_boxes = speed_limit_boxes(self.map, s.signal_id)
            else:
                var boxes = give_way_boxes(self.map, s.signal_id)
                sign.effect_boxes = boxes.effect.copy()
                sign.check_boxes = boxes.check.copy()
            var id = self._register(
                sign_type_id(kind.value(), s.subtype),
                TRAFFIC_SIGN_ACTOR,
                List[ActorAttributeValue](),
                sign.transform,
                BoundingBox(Vector3(0, 0, 0)),
                [TRAFFIC_SIGN],
            )
            self.actors[id.value - 1].handle = len(self.signs)
            self._effect_boxes.append(_obbs(sign.effect_boxes))
            self._check_boxes.append(_obbs(sign.check_boxes))
            self.signs.append(sign^)

    # --- the registry -----------------------------------------------------------

    def _index(self, id: ActorId) raises -> Int:
        if not id.is_valid() or id.value < 1 or id.value > len(self.actors):
            raise Error("Actor id names no actor")
        if not self.actors[id.value - 1].is_alive():
            raise Error("The actor has been destroyed")
        return id.value - 1

    def actor(self, id: ActorId) raises -> Actor:
        """Return an actor's record, `GetActor`.

        Args:
            id: The actor.

        Returns:
            A copy of the record.

        Raises:
            Error: If the id names no living actor.
        """
        return self.actors[self._index(id)].copy()

    def is_alive(self, id: ActorId) -> Bool:
        """Return whether an actor is in the world, `IsAlive`.

        Args:
            id: The actor.

        Returns:
            Whether the id names an actor that has not been destroyed.
        """
        return (
            id.is_valid()
            and id.value >= 1
            and id.value <= len(self.actors)
            and self.actors[id.value - 1].is_alive()
        )

    def get_actors(self) -> List[ActorId]:
        """Return every living actor, `GetActors`.

        Returns:
            Their ids, in order.
        """
        var out = List[ActorId]()
        # The spectator is always in the list.
        for a in self.actors:  # pragma: no branch
            if a.is_alive():
                out.append(a.id)
        return out^

    def filter_actors(self, pattern: String) -> List[ActorId]:
        """Return the living actors whose blueprint id matches a wildcard,
        `ActorList::Filter`.

        Args:
            pattern: Such as `vehicle.*`.

        Returns:
            Their ids, in order.
        """
        var out = List[ActorId]()
        # The spectator is always in the list.
        for a in self.actors:  # pragma: no branch
            if a.is_alive() and wildcard_match(a.type_id, pattern):
                out.append(a.id)
        return out^

    def get_spectator(self) -> ActorId:
        """Return the spectator, `GetSpectator`.

        Returns:
            Its id.
        """
        return self.spectator

    def get_blueprint_library(self) -> BlueprintLibrary:
        """Return the blueprint library, `GetBlueprintLibrary`.

        Returns:
            A copy of the library.
        """
        return self.blueprints.copy()

    def get_settings(self) -> EpisodeSettings:
        """Return the settings, `GetSettings`.

        Returns:
            A copy of the settings.
        """
        return self.settings.copy()

    def apply_settings(mut self, settings: EpisodeSettings) raises -> Int:
        """Change the settings, `ApplySettings`.

        Args:
            settings: The new settings.

        Returns:
            The current frame.

        Raises:
            Error: If `EpisodeSettings.check` refuses them.
        """
        settings.check()
        self.settings = settings.copy()
        return self.frame

    def get_weather(self) -> WeatherParameters:
        """Return the weather, `GetWeather`.

        Returns:
            The weather.
        """
        return self.weather

    def set_weather(mut self, weather: WeatherParameters):
        """Change the weather, `SetWeather`.

        Args:
            weather: The new weather.
        """
        self.weather = weather

    def get_snapshot(self) -> WorldSnapshot:
        """Return the snapshot of the last tick, `GetSnapshot`.

        Returns:
            A copy of the snapshot.
        """
        return self.snapshot.copy()

    def get_spawn_points(self) -> List[CarlaTransform]:
        """Return the recommended spawn points, `GetRecommendedSpawnPoints`.

        Returns:
            The points.
        """
        return self.spawn_points.copy()

    # --- spawning -----------------------------------------------------------------

    def _collides(
        self, transform: CarlaTransform, box: BoundingBox
    ) raises -> Bool:
        var mine = world_obb(transform, box)
        # The spectator is always in the list.
        for i in range(len(self.actors)):  # pragma: no branch
            ref a = self.actors[i]
            if not a.is_alive() or a.body.value < 0:
                continue
            var theirs = world_obb(self.get_transform(a.id), a.bounding_box)
            if mine.intersects_obb(theirs):
                return True
        return False

    def spawn_actor(
        mut self,
        blueprint: ActorBlueprint,
        transform: CarlaTransform,
        parent: ActorId = NO_ACTOR,
        attachment: AttachmentType = RIGID,
    ) raises -> ActorId:
        """Spawn an actor, `SpawnActor`.

        A `vehicle.*` blueprint makes a vehicle, a `walker.*` one a walker,
        a `sensor.*` one a sensor, and `static.*`, `util.*` and
        `controller.*` ones a plain actor. A sensor or a plain actor can
        be attached to a parent; its transform is then in the parent's
        frame. A failed spawn leaves the actors and physics unchanged.

        Args:
            blueprint: The blueprint, from this world's library.
            transform: Where, in the world or in the parent's frame.
            parent: The parent, or `NO_ACTOR`.
            attachment: How it follows the parent.

        Returns:
            The new actor's id.

        Raises:
            Error: If the blueprint is not in the library, its kind cannot
                be spawned, the parent is not alive, the attachment is not
                valid, a vehicle or walker is given a parent, or a vehicle's
                or walker's box meets another's, or a required vehicle
                attribute is missing or has an invalid value.
        """
        if not Bool(self.blueprints.find(blueprint.id)):
            raise Error("The blueprint is not in the library: " + blueprint.id)
        if not attachment.is_valid():
            raise Error("Attachment type is not valid")
        if parent != NO_ACTOR:
            _ = self._index(parent)
        var attributes = blueprint.description()
        var id = ActorId(len(self.actors) + 1)
        var physical = blueprint.id.startswith(
            "vehicle."
        ) or blueprint.id.startswith("walker.")
        if physical and parent != NO_ACTOR:
            raise Error("A vehicle or a walker cannot have a parent")
        if blueprint.id.startswith("vehicle."):
            var base = blueprint.attribute("base_type").value
            var box = vehicle_bounding_box(base)
            if self._collides(transform, box):
                raise Error(
                    "Spawn failed because of collision at spawn position"
                )
            # Finish fallible blueprint reads and actor validation before
            # adding anything to the physics or actor registries.
            var doors = blueprint.attribute("has_dynamic_doors").as_bool()
            var sticky = blueprint.attribute("sticky_control").as_bool()
            var actor = Actor(
                id,
                blueprint.id,
                VEHICLE_ACTOR,
                attributes^,
                transform,
                box,
                [vehicle_semantic_tag(base)],
            )
            var v = self.physics.add_vehicle(
                transform,
                box.location,
                box.extent,
                vehicle_physics_control(box),
            )
            # The returned index names the vehicle just added. Publish only
            # complete records; no fallible attribute reads remain.
            actor.handle = len(self.vehicles)
            actor.body = self.physics.vehicles[v.value].body
            self.vehicles.append(VehicleRecord(v, doors, sticky))
            self.actors.append(actor^)
            return id
        if blueprint.id.startswith("walker."):
            if self._collides(transform, self._walker_box):
                raise Error(
                    "Spawn failed because of collision at spawn position"
                )
            var actor = Actor(
                id,
                blueprint.id,
                WALKER_ACTOR,
                attributes^,
                transform,
                self._walker_box,
                [PEDESTRIAN],
            )
            var w = self.physics.add_walker(
                transform.location, WalkerParameters()
            )
            var body = self.physics.walkers[w.value].body
            self.physics.world.bodies[body.value].rotation = _quaternion(
                transform
            )
            actor.handle = len(self.walkers)
            actor.body = body
            self.walkers.append(WalkerRecord(w))
            self.actors.append(actor^)
            return id
        var kind = OTHER_ACTOR
        var tags = List[SemanticTag]()
        if blueprint.id.startswith("sensor."):
            kind = SENSOR_ACTOR
        elif blueprint.id.startswith("static."):
            tags.append(STATIC)
        elif not (
            blueprint.id.startswith("util.")
            or blueprint.id.startswith("controller.")
        ):
            raise Error("This kind of actor cannot be spawned: " + blueprint.id)
        var actor = Actor(
            id,
            blueprint.id,
            kind,
            attributes^,
            transform,
            BoundingBox(Vector3(0, 0, 0)),
            tags^,
        )
        actor.parent = parent
        actor.attachment = attachment
        self.actors.append(actor^)
        return id

    def try_spawn_actor(
        mut self,
        blueprint: ActorBlueprint,
        transform: CarlaTransform,
        parent: ActorId = NO_ACTOR,
        attachment: AttachmentType = RIGID,
    ) -> Optional[ActorId]:
        """Spawn an actor, or return None, `TrySpawnActor`.

        Args:
            blueprint: The blueprint.
            transform: Where.
            parent: The parent, or `NO_ACTOR`.
            attachment: How it follows the parent.

        Returns:
            The new actor's id, or None where `spawn_actor` would raise.
            A failure leaves the actors and physics unchanged.
        """
        try:
            return self.spawn_actor(blueprint, transform, parent, attachment)
        except:
            return None

    def _park(mut self, body: BodyId):
        ref b = self.physics.world.bodies[body.value]
        b.position = _PARKED
        b.linear_velocity = Vector3(0, 0, 0)
        b.angular_velocity = Vector3(0, 0, 0)
        b.gravity_scale = 0
        b.collides = False

    def _park_destroyed(mut self):
        # The spectator is always in the list.
        for i in range(len(self.actors)):  # pragma: no branch
            var body = self.actors[i].body
            if self.actors[i].state == ACTOR_INVALID and body.value >= 0:
                self._park(body)

    def destroy_actor(mut self, id: ActorId) raises -> Bool:
        """Destroy an actor, `Destroy`.

        A vehicle leaves the road boxes it was in first. Its children stay
        where they are, in the world.

        Args:
            id: The actor.

        Returns:
            True if it was destroyed; False if it is not alive, or is a
            traffic light, a sign or the spectator.

        Raises:
            Error: If a pose cannot be read.
        """
        if not self.is_alive(id) or id == self.spectator:
            return False
        var i = id.value - 1
        var kind = self.actors[i].kind
        if kind == TRAFFIC_LIGHT_ACTOR or kind == TRAFFIC_SIGN_ACTOR:
            return False
        if kind == VEHICLE_ACTOR:
            var left = List[_Overlap]()
            for o in self._overlaps:
                if o.vehicle == id.value:
                    left.append(o)
            self._leave(left)
        # The spectator is always in the list.
        for c in range(len(self.actors)):  # pragma: no branch
            if self.actors[c].is_alive() and self.actors[c].parent == id:
                self.actors[c].local_transform = self.get_transform(
                    self.actors[c].id
                )
                self.actors[c].parent = NO_ACTOR
        self.actors[i].state = ACTOR_INVALID
        var body = self.actors[i].body
        if body.value >= 0:
            self._park(body)
        return True

    # --- an actor's pose and motion ---------------------------------------------

    def get_transform(self, id: ActorId) raises -> CarlaTransform:
        """Return an actor's pose in the world, `GetTransform`.

        Args:
            id: The actor.

        Returns:
            A vehicle's or walker's body pose, an attached actor's pose
            moved by its parent's, or the pose it was placed at.

        Raises:
            Error: If the id names no living actor.
        """
        var i = self._index(id)
        if self.actors[i].body.value >= 0:
            return self.physics.transform(self.actors[i].body)
        if self.actors[i].parent != NO_ACTOR:
            return compose(
                self.get_transform(self.actors[i].parent),
                self.actors[i].local_transform,
            )
        return self.actors[i].local_transform

    def get_location(self, id: ActorId) raises -> Vector3:
        """Return an actor's location, `GetLocation`.

        Args:
            id: The actor.

        Returns:
            The location, in meters.

        Raises:
            Error: If the id names no living actor.
        """
        return self.get_transform(id).location

    def get_velocity(self, id: ActorId) raises -> Vector3:
        """Return an actor's velocity, `GetVelocity`.

        Args:
            id: The actor.

        Returns:
            The body's velocity in m/s, or zero without a body.

        Raises:
            Error: If the id names no living actor.
        """
        var i = self._index(id)
        if self.actors[i].body.value < 0:
            return Vector3(0, 0, 0)
        return self.physics.velocity(self.actors[i].body)

    def get_angular_velocity(self, id: ActorId) raises -> Vector3:
        """Return an actor's angular velocity, `GetAngularVelocity`.

        Args:
            id: The actor.

        Returns:
            The body's angular velocity in degrees per second, as CARLA
            reports it, or zero without a body.

        Raises:
            Error: If the id names no living actor.
        """
        var i = self._index(id)
        if self.actors[i].body.value < 0:
            return Vector3(0, 0, 0)
        return self.physics.angular_velocity(self.actors[i].body) * _TO_DEGREES

    def get_acceleration(self, id: ActorId) raises -> Vector3:
        """Return an actor's acceleration at the last tick,
        `GetAcceleration`.

        Args:
            id: The actor.

        Returns:
            The acceleration in the last snapshot, in m/s^2, or zero if the
            actor is not in it.

        Raises:
            Error: If the id names no living actor.
        """
        _ = self._index(id)
        var found = self.snapshot.find(id)
        if not Bool(found):
            return Vector3(0, 0, 0)
        return found.value().acceleration

    def get_bounding_box(self, id: ActorId) raises -> BoundingBox:
        """Return an actor's box in its own frame.

        Args:
            id: The actor.

        Returns:
            The box.

        Raises:
            Error: If the id names no living actor.
        """
        return self.actors[self._index(id)].bounding_box

    def set_transform(mut self, id: ActorId, transform: CarlaTransform) raises:
        """Move an actor, `SetTransform`.

        A vehicle or a walker keeps its velocity. A light's or a sign's
        boxes move with it.

        Args:
            id: The actor.
            transform: The new pose in the world.

        Raises:
            Error: If the id names no living actor.
        """
        var i = self._index(id)
        var body = self.actors[i].body
        if body.value >= 0:
            ref b = self.physics.world.bodies[body.value]
            b.position = transform.location
            b.rotation = _quaternion(transform)
            return
        var old = self.get_transform(id)
        if self.actors[i].parent != NO_ACTOR:
            self.actors[i].local_transform = relative(
                self.get_transform(self.actors[i].parent), transform
            )
        else:
            self.actors[i].local_transform = transform
        var h = self.actors[i].handle
        if self.actors[i].kind == TRAFFIC_LIGHT_ACTOR:
            ref light = self.traffic_lights.lights[h]
            light.transform = transform
            for k in range(len(light.boxes)):
                light.boxes[k].transform = compose(
                    transform, relative(old, light.boxes[k].transform)
                )
            self._light_boxes[h] = _obbs(light.boxes)
        elif self.actors[i].kind == TRAFFIC_SIGN_ACTOR:
            ref sign = self.signs[h]
            sign.transform = transform
            for k in range(len(sign.effect_boxes)):
                sign.effect_boxes[k].transform = compose(
                    transform, relative(old, sign.effect_boxes[k].transform)
                )
            for k in range(len(sign.check_boxes)):
                sign.check_boxes[k].transform = compose(
                    transform, relative(old, sign.check_boxes[k].transform)
                )
            self._effect_boxes[h] = _obbs(sign.effect_boxes)
            self._check_boxes[h] = _obbs(sign.check_boxes)

    def set_location(mut self, id: ActorId, location: Vector3) raises:
        """Move an actor and keep its rotation, `SetLocation`.

        Args:
            id: The actor.
            location: The new location, in meters.

        Raises:
            Error: If the id names no living actor.
        """
        var t = self.get_transform(id)
        t.location = location
        self.set_transform(id, t)

    def _body(self, id: ActorId) raises -> Int:
        var i = self._index(id)
        if self.actors[i].body.value < 0:
            raise Error("The actor has no physics body")
        return self.actors[i].body.value

    def set_target_velocity(mut self, id: ActorId, velocity: Vector3) raises:
        """Set a body's velocity, `SetTargetVelocity`.

        Args:
            id: A vehicle or a walker.
            velocity: The velocity, in m/s.

        Raises:
            Error: If the actor has no body.
        """
        self.physics.world.bodies[self._body(id)].linear_velocity = velocity

    def set_target_angular_velocity(
        mut self, id: ActorId, degrees_per_second: Vector3
    ) raises:
        """Set a body's angular velocity, `SetTargetAngularVelocity`.

        Args:
            id: A vehicle or a walker.
            degrees_per_second: The angular velocity, in degrees per
                second as CARLA takes it.

        Raises:
            Error: If the actor has no body.
        """
        var b = self._body(id)
        self.physics.world.bodies[b].angular_velocity = (
            degrees_per_second / _TO_DEGREES
        )

    def add_impulse(mut self, id: ActorId, impulse: Vector3) raises:
        """Push a body at its center of mass, `AddImpulse`.

        Args:
            id: A vehicle or a walker.
            impulse: The impulse, in N s.

        Raises:
            Error: If the actor has no body.
        """
        ref b = self.physics.world.bodies[self._body(id)]
        b.apply_impulse(impulse, b.world_center_of_mass())

    def add_force(mut self, id: ActorId, force: Vector3) raises:
        """Push a body at its center of mass for the next step, `AddForce`.

        Args:
            id: A vehicle or a walker.
            force: The force, in newtons.

        Raises:
            Error: If the actor has no body.
        """
        ref b = self.physics.world.bodies[self._body(id)]
        b.add_force(force, b.world_center_of_mass())

    def add_torque(mut self, id: ActorId, torque: Vector3) raises:
        """Turn a body for the next step, `AddTorque`.

        Args:
            id: A vehicle or a walker.
            torque: The torque, in N m.

        Raises:
            Error: If the actor has no body.
        """
        ref b = self.physics.world.bodies[self._body(id)]
        b.torque = b.torque + torque

    def add_angular_impulse(mut self, id: ActorId, impulse: Vector3) raises:
        """Spin a body, `AddAngularImpulse`.

        Args:
            id: A vehicle or a walker.
            impulse: The angular impulse, in N m s.

        Raises:
            Error: If the actor has no body.
        """
        ref b = self.physics.world.bodies[self._body(id)]
        b.angular_velocity = (
            b.angular_velocity + b.world_inverse_inertia().transform(impulse)
        )

    def set_enable_gravity(mut self, id: ActorId, enabled: Bool) raises:
        """Turn gravity on or off for a body, `SetEnableGravity`.

        A walker's movement sets its own gravity again each step.

        Args:
            id: A vehicle or a walker.
            enabled: Whether gravity pulls it.

        Raises:
            Error: If the actor has no body.
        """
        self.physics.world.bodies[
            self._body(id)
        ].gravity_scale = 1 if enabled else 0

    # --- vehicles -----------------------------------------------------------------

    def _vehicle(self, id: ActorId) raises -> Int:
        var i = self._index(id)
        if self.actors[i].kind != VEHICLE_ACTOR:
            raise Error("The actor is not a vehicle")
        return self.actors[i].handle

    def apply_control(mut self, id: ActorId, control: VehicleControl) raises:
        """Drive a vehicle, `Vehicle::ApplyControl`.

        Args:
            id: The vehicle.
            control: The control.

        Raises:
            Error: If the actor is not a vehicle, or the control is refused.
        """
        var v = self._vehicle(id)
        self.physics.apply_vehicle_control(self.vehicles[v].physics, control)

    def get_control(self, id: ActorId) raises -> VehicleControl:
        """Return the control a vehicle was last given, `GetControl`.

        Args:
            id: The vehicle.

        Returns:
            The control.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        return self.physics.vehicles[self.vehicles[v].physics.value].control

    def apply_ackermann_control(
        mut self, id: ActorId, control: VehicleAckermannControl
    ) raises:
        """Drive a vehicle by a target, `ApplyAckermannControl`.

        Args:
            id: The vehicle.
            control: The target.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        self.physics.apply_ackermann_control(self.vehicles[v].physics, control)

    def get_ackermann_controller_settings(
        self, id: ActorId
    ) raises -> AckermannControllerSettings:
        """Return a vehicle's Ackermann gains,
        `GetAckermannControllerSettings`.

        Args:
            id: The vehicle.

        Returns:
            The settings.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        var p = self.vehicles[v].physics.value
        return self.physics.vehicles[p].ackermann.settings()

    def apply_ackermann_controller_settings(
        mut self, id: ActorId, settings: AckermannControllerSettings
    ) raises:
        """Set a vehicle's Ackermann gains,
        `ApplyAckermannControllerSettings`.

        Args:
            id: The vehicle.
            settings: The settings.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        var p = self.vehicles[v].physics.value
        self.physics.vehicles[p].ackermann.apply_settings(settings)

    def apply_physics_control(
        mut self, id: ActorId, var physics: VehiclePhysicsControl
    ) raises:
        """Replace a vehicle's setup, `ApplyPhysicsControl`.

        Args:
            id: The vehicle.
            physics: The setup.

        Raises:
            Error: If the actor is not a vehicle, or the setup is refused.
        """
        var v = self._vehicle(id)
        self.physics.apply_physics_control(self.vehicles[v].physics, physics^)

    def get_physics_control(self, id: ActorId) raises -> VehiclePhysicsControl:
        """Return a vehicle's setup, `GetPhysicsControl`.

        Args:
            id: The vehicle.

        Returns:
            A copy of the setup.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        var p = self.vehicles[v].physics.value
        return self.physics.vehicles[p].physics.copy()

    def get_telemetry_data(self, id: ActorId) raises -> VehicleTelemetryData:
        """Return a vehicle's telemetry, `GetTelemetryData`.

        Args:
            id: The vehicle.

        Returns:
            The telemetry.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        return self.physics.telemetry(self.vehicles[v].physics)

    def get_failure_state(self, id: ActorId) raises -> VehicleFailureState:
        """Return why a vehicle stopped working, `GetFailureState`.

        Args:
            id: The vehicle.

        Returns:
            The failure state.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var v = self._vehicle(id)
        var p = self.vehicles[v].physics.value
        return self.physics.vehicles[p].failure_state

    def get_wheel_steer_angle(
        self, id: ActorId, wheel: VehicleWheelLocation
    ) raises -> Angle:
        """Return a wheel's steer angle, `GetWheelSteerAngle`.

        Args:
            id: The vehicle.
            wheel: The wheel.

        Returns:
            The angle the wheel is turned by.

        Raises:
            Error: If the actor is not a vehicle, or the vehicle has no
                such wheel.
        """
        var v = self._vehicle(id)
        ref physics = self.physics.vehicles[self.vehicles[v].physics.value]
        if not wheel.is_valid() or wheel.value >= len(physics.wheels):
            raise Error("The vehicle has no such wheel")
        return Angle(physics.wheels[wheel.value].steer, RADIAN)

    def set_light_state(
        mut self, id: ActorId, lights: VehicleLightState
    ) raises:
        """Turn a vehicle's lights on and off, `SetLightState`.

        Args:
            id: The vehicle.
            lights: The lights that are on.

        Raises:
            Error: If the actor is not a vehicle, or the flags are not
                valid.
        """
        var v = self._vehicle(id)
        if not lights.is_valid():
            raise Error("Vehicle light state is not valid")
        self.vehicles[v].light_state = lights

    def get_light_state(self, id: ActorId) raises -> VehicleLightState:
        """Return the lights that are on, `GetLightState`.

        Args:
            id: The vehicle.

        Returns:
            The lights.

        Raises:
            Error: If the actor is not a vehicle.
        """
        return self.vehicles[self._vehicle(id)].light_state

    def get_vehicles_light_states(
        self,
    ) -> List[Tuple[ActorId, VehicleLightState]]:
        """Return every living vehicle's lights, `GetVehiclesLightStates`.

        Returns:
            The vehicles and their lights, in order.
        """
        var out = List[Tuple[ActorId, VehicleLightState]]()
        # The spectator is always in the list.
        for a in self.actors:  # pragma: no branch
            if a.is_alive() and a.kind == VEHICLE_ACTOR:
                out.append((a.id, self.vehicles[a.handle].light_state))
        return out^

    def open_door(mut self, id: ActorId, door: VehicleDoor) raises:
        """Open a door, `OpenDoor`.

        Args:
            id: The vehicle.
            door: The door, or all.

        Raises:
            Error: If the actor is not a vehicle, or the door is not valid.
        """
        self.vehicles[self._vehicle(id)].set_door(door, True)

    def close_door(mut self, id: ActorId, door: VehicleDoor) raises:
        """Shut a door, `CloseDoor`.

        Args:
            id: The vehicle.
            door: The door, or all.

        Raises:
            Error: If the actor is not a vehicle, or the door is not valid.
        """
        self.vehicles[self._vehicle(id)].set_door(door, False)

    def is_door_open(self, id: ActorId, door: VehicleDoor) raises -> Bool:
        """Return whether a door is open.

        Args:
            id: The vehicle.
            door: One door.

        Returns:
            Whether it is open.

        Raises:
            Error: If the actor is not a vehicle, or the door is not one
                door.
        """
        return self.vehicles[self._vehicle(id)].is_door_open(door)

    def get_speed_limit(self, id: ActorId) raises -> Velocity:
        """Return the speed limit a vehicle obeys, `GetSpeedLimit`.

        Args:
            id: The vehicle.

        Returns:
            The limit of the last speed-limit box it entered, 30 km/h
            before any.

        Raises:
            Error: If the actor is not a vehicle.
        """
        return self.vehicles[self._vehicle(id)].speed_limit

    def get_traffic_light_state(self, id: ActorId) raises -> TrafficLightState:
        """Return the signal state a vehicle obeys, `GetTrafficLightState`.

        Args:
            id: The vehicle.

        Returns:
            The state its light or sign gave it, green otherwise.

        Raises:
            Error: If the actor is not a vehicle.
        """
        return self.vehicles[self._vehicle(id)].traffic_light_state

    def is_at_traffic_light(self, id: ActorId) raises -> Bool:
        """Return whether a vehicle is in a light's box, `IsAtTrafficLight`.

        Args:
            id: The vehicle.

        Returns:
            Whether it has a light.

        Raises:
            Error: If the actor is not a vehicle.
        """
        return self.vehicles[self._vehicle(id)].traffic_light != NO_ACTOR

    def get_traffic_light(self, id: ActorId) raises -> Optional[ActorId]:
        """Return the light whose box a vehicle is in, `GetTrafficLight`.

        Args:
            id: The vehicle.

        Returns:
            The light, or None.

        Raises:
            Error: If the actor is not a vehicle.
        """
        var light = self.vehicles[self._vehicle(id)].traffic_light
        if light == NO_ACTOR:
            return None
        return light

    def enable_constant_velocity(
        mut self, id: ActorId, velocity: Vector3
    ) raises:
        """Hold a vehicle's velocity in its own frame each tick,
        `EnableConstantVelocity`.

        Args:
            id: The vehicle.
            velocity: The velocity along its forward, right and up axes,
                in m/s.

        Raises:
            Error: If the actor is not a vehicle.
        """
        self.vehicles[self._vehicle(id)].constant_velocity = velocity

    def disable_constant_velocity(mut self, id: ActorId) raises:
        """Stop holding a vehicle's velocity, `DisableConstantVelocity`.

        Args:
            id: The vehicle.

        Raises:
            Error: If the actor is not a vehicle.
        """
        self.vehicles[self._vehicle(id)].constant_velocity = None

    # --- walkers ------------------------------------------------------------------

    def _walker(self, id: ActorId) raises -> Int:
        var i = self._index(id)
        if self.actors[i].kind != WALKER_ACTOR:
            raise Error("The actor is not a walker")
        return self.actors[i].handle

    def apply_walker_control(
        mut self, id: ActorId, control: WalkerControl
    ) raises:
        """Move a walker, `Walker::ApplyControl`.

        Args:
            id: The walker.
            control: The control.

        Raises:
            Error: If the actor is not a walker, or the control is refused.
        """
        var w = self._walker(id)
        self.physics.apply_walker_control(self.walkers[w].physics, control)
        self.walkers[w].control = control

    def get_walker_gait(self, id: ActorId) raises -> WalkerGait:
        """Read a copy of a capsule walker's simulation-driven gait.

        Args:
            id: A live walker.

        Returns:
            Its bounded phase and smooth amplitude, without advancing time.

        Raises:
            Error: If the actor is not a live walker.
        """
        return self.walkers[self._walker(id)].gait

    def get_walker_control(self, id: ActorId) raises -> WalkerControl:
        """Return the control a walker was last given, `GetWalkerControl`.

        Args:
            id: The walker.

        Returns:
            The control.

        Raises:
            Error: If the actor is not a walker.
        """
        return self.walkers[self._walker(id)].control

    def set_bones_transform(
        mut self, id: ActorId, control: WalkerBoneControlIn
    ) raises:
        """Set a walker's bone poses, `SetBonesTransform`.

        Args:
            id: The walker.
            control: The bones.

        Raises:
            Error: If the actor is not a walker.
        """
        self.walkers[self._walker(id)].set_bones(control)

    def get_bones_transform(self, id: ActorId) raises -> WalkerBoneControlOut:
        """Return a walker's set bones, `GetBonesTransform`.

        Args:
            id: The walker.

        Returns:
            The bones.

        Raises:
            Error: If the actor is not a walker.
        """
        var w = self._walker(id)
        return self.walkers[w].bones_out(self.get_transform(id))

    def blend_pose(mut self, id: ActorId, blend: Float32) raises:
        """Blend a walker's set pose over its walk, `BlendPose`.

        Args:
            id: The walker.
            blend: From zero to one.

        Raises:
            Error: If the actor is not a walker, or the blend is out of
                range.
        """
        self.walkers[self._walker(id)].blend_pose(blend)

    # --- traffic lights and signs -----------------------------------------------

    def _light(self, id: ActorId) raises -> Int:
        var i = self._index(id)
        if self.actors[i].kind != TRAFFIC_LIGHT_ACTOR:
            raise Error("The actor is not a traffic light")
        return self.actors[i].handle

    def _sign(self, id: ActorId) raises -> Int:
        var i = self._index(id)
        if self.actors[i].kind != TRAFFIC_SIGN_ACTOR:
            raise Error("The actor is not a traffic sign")
        return self.actors[i].handle

    def _notify(mut self):
        """Give each vehicle in a set light's boxes the light's state."""
        for light in self.traffic_lights.notified:
            ref l = self.traffic_lights.lights[light]
            for v in l.vehicles:
                self.vehicles[
                    self.actors[v.value - 1].handle
                ].traffic_light_state = l.state
        self.traffic_lights.notified = List[Int]()

    def set_traffic_light_state(
        mut self, id: ActorId, state: TrafficLightState
    ) raises:
        """Set a light's state, `TrafficLight::SetState`.

        Args:
            id: The light.
            state: The new state.

        Raises:
            Error: If the actor is not a traffic light, or the state is
                not valid.
        """
        self.traffic_lights.set_light_state(self._light(id), state)
        self._notify()

    def get_traffic_light_state_of(
        self, id: ActorId
    ) raises -> TrafficLightState:
        """Return a light's state, `TrafficLight::GetState`.

        Args:
            id: The light.

        Returns:
            The state.

        Raises:
            Error: If the actor is not a traffic light.
        """
        return self.traffic_lights.lights[self._light(id)].state

    def set_light_time(
        mut self, id: ActorId, state: TrafficLightState, time: Duration
    ) raises:
        """Set a light's green, yellow or red time, `SetGreenTime`,
        `SetYellowTime` and `SetRedTime`.

        Args:
            id: The light.
            state: Which stage.
            time: The new time.

        Raises:
            Error: If the actor is not a traffic light, or has no
                controller.
        """
        self.traffic_lights.set_time_of(self._light(id), state, time)

    def get_light_time(
        self, id: ActorId, state: TrafficLightState
    ) raises -> Duration:
        """Return a light's green, yellow or red time, `GetGreenTime`,
        `GetYellowTime` and `GetRedTime`.

        Args:
            id: The light.
            state: Which stage.

        Returns:
            The time.

        Raises:
            Error: If the actor is not a traffic light.
        """
        return self.traffic_lights.time_of(self._light(id), state)

    def get_elapsed_time(self, id: ActorId) raises -> Duration:
        """Return the time in a light's stage, `GetElapsedTime`.

        Args:
            id: The light.

        Returns:
            The time.

        Raises:
            Error: If the actor is not a traffic light.
        """
        return self.traffic_lights.elapsed_time(self._light(id))

    def freeze(mut self, id: ActorId, frozen: Bool) raises:
        """Freeze or free the lights, `TrafficLight::Freeze`. As in CARLA
        this acts on every light.

        Args:
            id: A light.
            frozen: Whether time stops for the lights.

        Raises:
            Error: If the actor is not a traffic light.
        """
        _ = self._light(id)
        self.freeze_all_traffic_lights(frozen)

    def is_frozen(self, id: ActorId) raises -> Bool:
        """Return whether a light's group is frozen, `IsFrozen`.

        Args:
            id: The light.

        Returns:
            Whether it is frozen.

        Raises:
            Error: If the actor is not a traffic light.
        """
        return self.traffic_lights.is_frozen(self._light(id))

    def get_pole_index(self, id: ActorId) raises -> Int:
        """Return a light's pole index, `GetPoleIndex`.

        Args:
            id: The light.

        Returns:
            The index; zero for a light placed from the map.

        Raises:
            Error: If the actor is not a traffic light.
        """
        return self.traffic_lights.lights[self._light(id)].pole_index

    def get_group_traffic_lights(self, id: ActorId) raises -> List[ActorId]:
        """Return the lights of a light's group, `GetGroupTrafficLights`.

        Args:
            id: The light.

        Returns:
            The lights, the given one among them.

        Raises:
            Error: If the actor is not a traffic light.
        """
        var out = List[ActorId]()
        # A light placed from the map is in a group with itself.
        for l in self.traffic_lights.group_lights(
            self._light(id)
        ):  # pragma: no branch
            out.append(self._light_actors[l])
        return out^

    def reset_group(mut self, id: ActorId) raises:
        """Reset a light's group, `ResetGroup`.

        Args:
            id: The light.

        Raises:
            Error: If the actor is not a traffic light.
        """
        self.traffic_lights.reset_group_of(self._light(id))
        self._notify()

    def reset_all_traffic_lights(mut self):
        """Reset every group, `ResetAllTrafficLights`."""
        self.traffic_lights.reset_all()
        self._notify()

    def freeze_all_traffic_lights(mut self, frozen: Bool):
        """Freeze or free every light, `FreezeAllTrafficLights`.

        Args:
            frozen: Whether time stops for the lights.
        """
        self.traffic_lights.set_frozen(frozen)

    def get_opendrive_id(self, id: ActorId) raises -> SignalId:
        """Return the signal of a light or a sign, `GetOpenDRIVEID` and
        `GetSignId`.

        Args:
            id: The light or the sign.

        Returns:
            The signal id.

        Raises:
            Error: If the actor is neither.
        """
        var i = self._index(id)
        if self.actors[i].kind == TRAFFIC_LIGHT_ACTOR:
            return self.traffic_lights.lights[self.actors[i].handle].sign_id
        return self.signs[self._sign(id)].sign_id

    def get_trigger_volume(self, id: ActorId) raises -> BoundingBox:
        """Return a light's or a sign's first box in its frame,
        `GetTriggerVolume`.

        Args:
            id: The light or the sign.

        Returns:
            The box, or a zero box when it has none.

        Raises:
            Error: If the actor is neither.
        """
        var i = self._index(id)
        if self.actors[i].kind == TRAFFIC_LIGHT_ACTOR:
            return self.traffic_lights.lights[
                self.actors[i].handle
            ].trigger_volume()
        ref sign = self.signs[self._sign(id)]
        if len(sign.effect_boxes) == 0:
            return BoundingBox(Vector3(0, 0, 0))
        var local = relative(sign.transform, sign.effect_boxes[0].transform)
        return BoundingBox(
            local.location, sign.effect_boxes[0].extent, local.rotation
        )

    def get_affected_lane_waypoints(self, id: ActorId) raises -> List[Waypoint]:
        """Return the waypoints of the lanes a light holds,
        `GetAffectedLaneWaypoints`.

        Args:
            id: The light.

        Returns:
            The waypoints.

        Raises:
            Error: If the actor is not a traffic light.
        """
        var l = self._light(id)
        return affected_lane_waypoints(
            self.map, self.traffic_lights.lights[l].sign_id
        )

    def get_stop_waypoints(self, id: ActorId) raises -> List[Waypoint]:
        """Return where vehicles stop for a light, `GetStopWaypoints`.

        Args:
            id: The light.

        Returns:
            The waypoints.

        Raises:
            Error: If the actor is not a traffic light.
        """
        var l = self._light(id)
        return stop_waypoints(
            self.map,
            self.traffic_lights.lights[l].transform,
            self.traffic_lights.lights[l].trigger_volume(),
        )

    def get_traffic_light_from_opendrive(
        self, sign_id: SignalId
    ) -> Optional[ActorId]:
        """Return the light of a signal, `GetTrafficLightFromOpenDRIVE`.

        Args:
            sign_id: The signal.

        Returns:
            The light, or None.
        """
        var l = self.traffic_lights.find(sign_id)
        if l < 0:
            return None
        return self._light_actors[l]

    def get_traffic_light(self, landmark: Landmark) -> Optional[ActorId]:
        """Return the light of a landmark, `World::GetTrafficLight`.

        Args:
            landmark: The landmark.

        Returns:
            The light, or None.
        """
        return self.get_traffic_light_from_opendrive(
            landmark.reference.signal_id
        )

    def get_traffic_sign(self, landmark: Landmark) raises -> Optional[ActorId]:
        """Return the actor of a landmark, `World::GetTrafficSign`.

        As in CARLA, the search takes every actor whose blueprint id
        matches `*traffic.*`, so a light can be the answer.

        Args:
            landmark: The landmark.

        Returns:
            The first such actor with the landmark's signal, or None.

        Raises:
            Error: If a signal id cannot be read.
        """
        # The spectator is always in the list.
        for a in self.actors:  # pragma: no branch
            if not (a.is_alive() and wildcard_match(a.type_id, "*traffic.*")):
                continue
            if self.get_opendrive_id(a.id) == landmark.reference.signal_id:
                return a.id
        return None

    def get_traffic_lights_from_waypoint(
        self, waypoint: Waypoint, distance: Float64
    ) raises -> List[ActorId]:
        """Return the lights ahead of a waypoint,
        `GetTrafficLightsFromWaypoint`.

        Args:
            waypoint: The start.
            distance: How far ahead, in meters.

        Returns:
            Each light once, in the order the landmarks come.

        Raises:
            Error: If the lane is not in the map.
        """
        var out = List[ActorId]()
        for landmark in self.map.landmarks_in_distance(waypoint, distance):
            ref signal = self.map.signal(landmark.reference.signal_id)
            if not is_traffic_light(signal.type):
                continue
            var light = self.get_traffic_light(landmark)
            if Bool(light) and not (light.value() in out):
                out.append(light.value())
        return out^

    def get_traffic_lights_in_junction(
        self, junction: JuncId
    ) raises -> List[ActorId]:
        """Return the lights of a junction's controllers,
        `GetTrafficLightsInJunction`.

        Args:
            junction: The junction.

        Returns:
            The lights of each controller's signals, in order.

        Raises:
            Error: If the junction is not in the map.
        """
        var out = List[ActorId]()
        for c in self.map.junction(junction).controllers:
            for s in self.map.controller(c).signals:
                var light = self.get_traffic_light_from_opendrive(s)
                if Bool(light):
                    out.append(light.value())
        return out^

    # --- ray queries --------------------------------------------------------------

    def project_point(
        self,
        location: Vector3,
        direction: Vector3,
        search_distance: Length = Length(10000, METER),
    ) raises -> Optional[LabelledPoint]:
        """Return the first surface along a direction, `ProjectPoint`.

        Args:
            location: Where to start.
            direction: Which way.
            search_distance: How far.

        Returns:
            The point and its surface's tag, or None.

        Raises:
            Error: If the direction is zero.
        """
        var hit = self.physics.raycast(location, direction, search_distance)
        if not Bool(hit):
            return None
        var h = hit.value()
        var label = UNLABELED
        for i in range(len(self._road_bodies)):
            if self._road_bodies[i] == h.body:
                label = self._road_tags[i]
        # The spectator is always in the list.
        for a in self.actors:  # pragma: no branch
            # Only a vehicle or a walker has a body, and each has a tag.
            if a.body == h.body:
                label = a.semantic_tags[0]
        return LabelledPoint(h.point, label)

    def ground_projection(
        self,
        location: Vector3,
        search_distance: Length = Length(10000, METER),
    ) raises -> Optional[LabelledPoint]:
        """Return the surface below a point, `GroundProjection`.

        Args:
            location: Where to start.
            search_distance: How far down.

        Returns:
            The point and its surface's tag, or None.

        Raises:
            Error: Never; the ray's check is passed on.
        """
        return self.project_point(location, Vector3(0, 0, -1), search_distance)

    # --- the tick -------------------------------------------------------------------

    def _apply(mut self, updates: List[SignalUpdate]):
        for u in updates:
            var v = self.actors[u.vehicle.value - 1].handle
            self.vehicles[v].traffic_light_state = u.state

    def _leave(mut self, overlaps: List[_Overlap]):
        """The vehicles leave these boxes."""
        if len(overlaps) == 0:
            return
        var gone = Set[_Overlap]()
        # The empty list returned above.
        for o in overlaps:  # pragma: no branch
            gone.add(o)
            var vehicle = ActorId(o.vehicle)
            var v = self.actors[o.vehicle - 1].handle
            if o.owner == 0:
                # Each overlapping box contributes one entry. Leaving one
                # box must not remove the entries for the same light's others.
                var kept = List[ActorId]()
                var removed = False
                # _enter added one membership for this live overlap;
                # each prior departure removed only its own membership.
                for w in self.traffic_lights.lights[
                    o.index
                ].vehicles:  # pragma: no branch
                    if w == vehicle and not removed:
                        removed = True
                    else:
                        kept.append(w)
                if (
                    vehicle not in kept
                    and self.vehicles[v].traffic_light
                    == self._light_actors[o.index]
                ):
                    self.vehicles[v].traffic_light_state = GREEN
                    self.vehicles[v].traffic_light = NO_ACTOR
                self.traffic_lights.lights[o.index].vehicles = kept^
            elif o.owner == 1:
                if self.signs[o.index].kind != SPEED_LIMIT_SIGN:
                    self.signs[o.index].end_effect(vehicle)
            else:
                self.signs[o.index].end_check(vehicle)
        var kept = List[_Overlap]()
        # Every overlap being left is in the list.
        for have in self._overlaps:  # pragma: no branch
            if have not in gone:
                kept.append(have)
        self._overlaps = kept^

    def _enter(mut self, o: _Overlap):
        var vehicle = ActorId(o.vehicle)
        var v = self.actors[o.vehicle - 1].handle
        if o.owner == 0:
            ref light = self.traffic_lights.lights[o.index]
            self.vehicles[v].traffic_light_state = light.state
            light.vehicles.append(vehicle)
            self.vehicles[v].traffic_light = self._light_actors[o.index]
        elif o.owner == 1:
            if self.signs[o.index].kind == SPEED_LIMIT_SIGN:
                self.vehicles[v].speed_limit = self.signs[o.index].speed_limit
            else:
                self._apply(self.signs[o.index].begin_effect(vehicle))
        else:
            self._apply(self.signs[o.index].begin_check(vehicle))
        self._overlaps.append(o)

    def _append_overlaps(
        self,
        mut out: List[_Overlap],
        id: ActorId,
        owner: Int,
        box: OBB,
        groups: List[List[OBB]],
    ):
        var reach = box.half_size.length()
        for i in range(len(groups)):
            ref boxes = groups[i]
            for k in range(len(boxes)):
                var gap = (boxes[k].center - box.center).length()
                if gap > reach + boxes[k].half_size.length():
                    continue
                if box.intersects_obb(boxes[k]):
                    out.append(_Overlap(id.value, owner, i, k))

    def _find_overlaps(self) raises -> List[_Overlap]:
        var out = List[_Overlap]()
        # The spectator is always in the list.
        for a in self.actors:  # pragma: no branch
            if not (a.is_alive() and a.kind == VEHICLE_ACTOR):
                continue
            var box = world_obb(self.get_transform(a.id), a.bounding_box)
            self._append_overlaps(out, a.id, 0, box, self._light_boxes)
            self._append_overlaps(out, a.id, 1, box, self._effect_boxes)
            self._append_overlaps(out, a.id, 2, box, self._check_boxes)
        return out^

    def _update_overlaps(mut self) raises:
        var now = self._find_overlaps()
        var present = Set[_Overlap]()
        var previous = Set[_Overlap]()
        for o in now:
            present.add(o)
        var gone = List[_Overlap]()
        for o in self._overlaps:
            previous.add(o)
            if o not in present:
                gone.append(o)
        self._leave(gone)
        for o in now:
            if o not in previous:
                self._enter(o)

    def tick(mut self) raises -> Int:
        """Advance the world by one fixed step, `World::Tick`.

        Returns:
            The new frame.

        Raises:
            Error: If `fixed_delta_seconds` is not set, or the physics
                fails.
        """
        if not Bool(self.settings.fixed_delta_seconds):
            raise Error("A tick needs fixed_delta_seconds")
        var dt = self.settings.fixed_delta_seconds.value()
        self.frame += 1
        self.delta_seconds = Float64(dt.value)
        self.elapsed_seconds += self.delta_seconds
        for s in range(len(self.signs)):
            self._apply(self.signs[s].tick_timers(dt.value))
        self.traffic_lights.tick(dt)
        self._notify()
        self._park_destroyed()
        # The spectator is always in the list.
        for i in range(len(self.actors)):  # pragma: no branch
            if not (
                self.actors[i].is_alive()
                and self.actors[i].kind == VEHICLE_ACTOR
            ):
                continue
            var held = self.vehicles[self.actors[i].handle].constant_velocity
            if Bool(held):
                var body = self.actors[i].body
                var t = self.physics.transform(body)
                self.physics.world.bodies[
                    body.value
                ].linear_velocity = t.rotation.rotate_vector(held.value())
        self.physics.tick(dt, self.settings.substep_count(dt))
        self._park_destroyed()
        # The spectator is always in the list.
        for i in range(len(self.actors)):  # pragma: no branch
            if (
                self.actors[i].is_alive()
                and self.actors[i].kind == WALKER_ACTOR
            ):
                var velocity = self.get_velocity(self.actors[i].id)
                velocity.z = 0
                self.walkers[self.actors[i].handle].gait.advance(
                    Velocity(velocity.length()), dt
                )
            if not (
                self.actors[i].is_alive()
                and self.actors[i].kind == VEHICLE_ACTOR
            ):
                continue
            var h = self.actors[i].handle
            if not self.vehicles[h].sticky_control:
                self.physics.apply_vehicle_control(
                    self.vehicles[h].physics, VehicleControl()
                )
        self._update_overlaps()
        self.snapshot = self._take_snapshot()
        return self.frame

    def _take_snapshot(mut self) raises -> WorldSnapshot:
        var stamp = Timestamp(
            self.frame,
            self.elapsed_seconds,
            self.delta_seconds,
            Float64(perf_counter_ns()) * 1e-9,
        )
        var out = WorldSnapshot(self.episode_id, stamp)
        # The spectator is always in the list.
        for i in range(len(self.actors)):  # pragma: no branch
            if not self.actors[i].is_alive():
                continue
            var id = self.actors[i].id
            var v = self.get_velocity(id)
            var acceleration = Vector3(0, 0, 0)
            if self.delta_seconds > 0:
                acceleration = (v - self.actors[i].last_velocity) / Float32(
                    self.delta_seconds
                )
            self.actors[i].last_velocity = v
            var s = ActorSnapshot(
                id,
                self.actors[i].state,
                self.get_transform(id),
                v,
                self.get_angular_velocity(id),
                acceleration,
            )
            var kind = self.actors[i].kind
            var h = self.actors[i].handle
            if kind == VEHICLE_ACTOR:
                ref r = self.vehicles[h]
                s.vehicle = VehicleData(
                    self.get_control(id),
                    r.speed_limit,
                    r.traffic_light_state,
                    r.traffic_light != NO_ACTOR,
                    r.traffic_light,
                    self.get_failure_state(id),
                )
            elif kind == WALKER_ACTOR:
                s.walker_control = self.walkers[h].control
            elif kind == TRAFFIC_LIGHT_ACTOR:
                s.traffic_light = TrafficLightData(
                    cut_sign_id(self.traffic_lights.lights[h].sign_id.value),
                    self.traffic_lights.time_of(h, GREEN),
                    self.traffic_lights.time_of(h, YELLOW),
                    self.traffic_lights.time_of(h, RED),
                    self.traffic_lights.elapsed_time(h),
                    self.traffic_lights.lights[h].pole_index,
                    self.traffic_lights.is_frozen(h),
                    self.traffic_lights.lights[h].state,
                )
            elif kind == TRAFFIC_SIGN_ACTOR:
                s.sign_id = cut_sign_id(self.signs[h].sign_id.value)
            out.actors.append(s^)
        return out^
