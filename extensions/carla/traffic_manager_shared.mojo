# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the traffic manager's stages share, and what they hand on.

CARLA's stages hold references to the traffic manager's lists and maps.
Here `TrafficManagerShared` holds them, and each stage's `update` takes
it. The stages run in CARLA's order each step, and each fills its frame
for the next:

1. Localization fills `localization_frame`: whether each vehicle is at a
   junction's entrance, and the free space after the junction.
2. Collision fills `collision_frame`: the actor each vehicle must yield
   to, and the room it has.
3. The traffic-light stage fills `tl_frame`: whether a light or a sign
   stops the vehicle.
4. Motion planning fills `control_frame` with one command a vehicle. The
   vehicle-light stage appends light commands.

A command is CARLA's `rpc::Command`, cut down to the three kinds the
traffic manager sends.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/DataStructures.h`
and `TrafficManagerLocal.h`.
"""

from extensions.carla.actor import ActorId, NO_ACTOR, no_rotation
from extensions.carla.map import Waypoint
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    NO_SIMPLE_WAYPOINT,
    RoadOption,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_parameters import Parameters
from extensions.carla.traffic_manager_random import RandomGenerator
from extensions.carla.traffic_manager_state import (
    SimulationState,
    TrackTraffic,
)
from extensions.carla.transform import CarlaTransform
from extensions.carla.vehicle import LIGHTS_NONE, VehicleLightState
from std.collections import Dict, Optional
from units.si import Length


@fieldwise_init
struct LocalizationData(ImplicitlyCopyable):
    """One vehicle's localization, CARLA's `LocalizationData`."""

    var junction_end_point: SimpleWaypointIndex
    var safe_point: SimpleWaypointIndex
    var is_at_junction_entrance: Bool


def no_localization() -> LocalizationData:
    """Return an empty localization record.

    Returns:
        No junction end, no safe point, not at an entrance.
    """
    return LocalizationData(NO_SIMPLE_WAYPOINT, NO_SIMPLE_WAYPOINT, False)


@fieldwise_init
struct CollisionHazardData(ImplicitlyCopyable):
    """One vehicle's collision hazard, CARLA's `CollisionHazardData`."""

    var available_distance_margin: Length
    var hazard_actor_id: ActorId
    var hazard: Bool


@fieldwise_init
struct CommandKind(Equatable, ImplicitlyCopyable, Writable):
    """What a traffic manager command does."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a kind.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


comptime NO_COMMAND = CommandKind(0)
comptime APPLY_VEHICLE_CONTROL = CommandKind(1)
comptime APPLY_TRANSFORM = CommandKind(2)
comptime SET_VEHICLE_LIGHT_STATE = CommandKind(3)


@fieldwise_init
struct TrafficCommand(ImplicitlyCopyable):
    """One order to the world, CARLA's `rpc::Command`: a vehicle control,
    a teleport or a light state."""

    var kind: CommandKind
    var actor: ActorId
    var control: VehicleControl
    var transform: CarlaTransform
    var light_state: VehicleLightState


def _origin() -> CarlaTransform:
    return CarlaTransform(Length(0), Length(0), Length(0), no_rotation())


def no_command() -> TrafficCommand:
    """Return the empty command a fresh frame holds.

    Returns:
        A command that does nothing.
    """
    return TrafficCommand(
        NO_COMMAND, NO_ACTOR, VehicleControl(), _origin(), LIGHTS_NONE
    )


def apply_vehicle_control(
    actor: ActorId, control: VehicleControl
) -> TrafficCommand:
    """Return CARLA's `Command::ApplyVehicleControl`.

    Args:
        actor: The vehicle.
        control: Its pedals and wheel.

    Returns:
        The command.
    """
    return TrafficCommand(
        APPLY_VEHICLE_CONTROL, actor, control, _origin(), LIGHTS_NONE
    )


def apply_transform(
    actor: ActorId, transform: CarlaTransform
) -> TrafficCommand:
    """Return CARLA's `Command::ApplyTransform`.

    Args:
        actor: The vehicle.
        transform: Where to put it.

    Returns:
        The command.
    """
    return TrafficCommand(
        APPLY_TRANSFORM, actor, VehicleControl(), transform, LIGHTS_NONE
    )


def set_vehicle_light_state(
    actor: ActorId, lights: VehicleLightState
) -> TrafficCommand:
    """Return CARLA's `Command::SetVehicleLightState`.

    Args:
        actor: The vehicle.
        lights: The lights that are on.

    Returns:
        The command.
    """
    return TrafficCommand(
        SET_VEHICLE_LIGHT_STATE, actor, VehicleControl(), _origin(), lights
    )


@fieldwise_init
struct LargeVehicle(ImplicitlyCopyable):
    """A bus's or a truck's turn, CARLA's `std::pair<float, bool>` of
    large vehicles."""

    # The length of the junction path it turns on; zero going straight.
    var junction_length: Length
    # True for a right turn.
    var turn_right: Bool


@fieldwise_init
struct TrafficAction(ImplicitlyCopyable):
    """A vehicle's next move, CARLA's `Action`."""

    var road_option: RoadOption
    # Where it happens, or None.
    var waypoint: Optional[Waypoint]


struct TrafficManagerShared(Movable):
    """The lists and maps CARLA's stages share by reference."""

    var vehicle_id_list: List[ActorId]
    var buffer_map: Dict[Int, List[SimpleWaypointIndex]]
    var simulation_state: SimulationState
    var track_traffic: TrackTraffic
    var local_map: InMemoryMap
    var parameters: Parameters
    var random_device: RandomGenerator
    var large_vehicles: Dict[Int, LargeVehicle]
    var marked_for_removal: List[ActorId]
    var localization_frame: List[LocalizationData]
    var collision_frame: List[CollisionHazardData]
    var tl_frame: List[Bool]
    var control_frame: List[TrafficCommand]

    def __init__(out self, var local_map: InMemoryMap, seed: UInt64):
        """Create empty state on a map.

        Args:
            local_map: The traffic manager's map.
            seed: The random seed.
        """
        self.vehicle_id_list = List[ActorId]()
        self.buffer_map = Dict[Int, List[SimpleWaypointIndex]]()
        self.simulation_state = SimulationState()
        self.track_traffic = TrackTraffic()
        self.local_map = local_map^
        self.parameters = Parameters()
        self.random_device = RandomGenerator(seed)
        self.large_vehicles = Dict[Int, LargeVehicle]()
        self.marked_for_removal = List[ActorId]()
        self.localization_frame = List[LocalizationData]()
        self.collision_frame = List[CollisionHazardData]()
        self.tl_frame = List[Bool]()
        self.control_frame = List[TrafficCommand]()

    def buffer(self, actor: ActorId) -> List[SimpleWaypointIndex]:
        """Return a copy of a vehicle's path.

        Args:
            actor: The vehicle.

        Returns:
            Its path, or an empty one.
        """
        return self.buffer_map.get(actor.value, List[SimpleWaypointIndex]())

    def reset_frames(mut self):
        """Size each frame for this step's vehicles, emptied."""
        var n = len(self.vehicle_id_list)
        self.localization_frame = List[LocalizationData](
            length=n, fill=no_localization()
        )
        self.collision_frame = List[CollisionHazardData](
            length=n,
            fill=CollisionHazardData(Length(0), NO_ACTOR, False),
        )
        self.tl_frame = List[Bool](length=n, fill=False)
        self.control_frame = List[TrafficCommand](length=n, fill=no_command())
