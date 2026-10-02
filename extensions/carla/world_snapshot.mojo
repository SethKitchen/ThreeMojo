# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's world snapshot: the frame, the time and every actor's state.

A world makes one `WorldSnapshot` at the end of each tick. It holds a
`Timestamp` and, for each actor, an `ActorSnapshot`: the pose, the
velocity, the angular velocity and the acceleration, and the data of its
kind: a vehicle's control and signals, a walker's control, a traffic
light's state and times, or a sign's id.

The records are CARLA's `LibCarla/source/carla/client/Timestamp.h`,
`ActorSnapshot.h`, `WorldSnapshot.h` and `sensor/data/ActorDynamicState.h`.
The values are the ones CARLA's world observer writes, in CARLA's
simulator plugin, `Carla/Sensor/WorldObserver.cpp`:

- The velocity is in m/s.
- The angular velocity is in degrees per second, as CARLA reports it.
- The acceleration is the change of the velocity since the last tick,
  over the tick. It is zero in the first snapshot.

**Time.** CARLA keeps the elapsed and the delta seconds in `double`. A
`Duration` holds a `Float32`, which counts a long run only to a
millisecond. So `Timestamp` keeps them as `Float64` seconds, and
`elapsed` and `delta` give them as `Duration`s.
"""

from extensions.carla.actor import (
    ActorId,
    ActorState,
    TrafficLightState,
)
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.transform import CarlaTransform
from extensions.carla.vehicle import VehicleData
from math.vector3 import Vector3
from units.si import SECOND, Duration


@fieldwise_init
struct Timestamp(Equatable, ImplicitlyCopyable, Writable):
    """When a snapshot was taken, CARLA's `Timestamp`."""

    # Frames since the world started.
    var frame: Int
    # Simulated seconds since the world started.
    var elapsed_seconds: Float64
    # Simulated seconds since the last frame.
    var delta_seconds: Float64
    # The system clock when the frame ended, in seconds.
    var platform_timestamp: Float64

    def elapsed(self) -> Duration:
        """Return the simulated time since the world started.

        Returns:
            `elapsed_seconds` as a `Duration`.
        """
        return Duration(Float32(self.elapsed_seconds), SECOND)

    def delta(self) -> Duration:
        """Return the simulated time since the last frame.

        Returns:
            `delta_seconds` as a `Duration`.
        """
        return Duration(Float32(self.delta_seconds), SECOND)

    def __eq__(self, other: Self) -> Bool:
        """Return True for the same frame, as CARLA compares.

        Args:
            other: The other timestamp.

        Returns:
            Whether the frames match.
        """
        return self.frame == other.frame

    def write_to(self, mut writer: Some[Writer]):
        """Write the timestamp as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "Timestamp(frame=",
            self.frame,
            ",elapsed_seconds=",
            self.elapsed_seconds,
            ",delta_seconds=",
            self.delta_seconds,
            ",platform_timestamp=",
            self.platform_timestamp,
            ")",
        )


@fieldwise_init
struct TrafficLightData(ImplicitlyCopyable, Movable):
    """A traffic light's part of a snapshot, CARLA's `TrafficLightData`."""

    # The OpenDRIVE signal id: at most 32 UTF-8 bytes, no partial codepoint.
    var sign_id: String
    var green_time: Duration
    var yellow_time: Duration
    var red_time: Duration
    var elapsed_time: Duration
    var pole_index: Int
    var time_is_frozen: Bool
    var state: TrafficLightState


struct ActorSnapshot(Copyable, Movable):
    """One actor at one frame, CARLA's `ActorSnapshot`."""

    var id: ActorId
    var actor_state: ActorState
    var transform: CarlaTransform
    # In m/s.
    var velocity: Vector3
    # In degrees per second.
    var angular_velocity: Vector3
    # In m/s^2.
    var acceleration: Vector3
    var vehicle: Optional[VehicleData]
    var walker_control: Optional[WalkerControl]
    var traffic_light: Optional[TrafficLightData]
    # A sign's id: at most 32 UTF-8 bytes, no partial codepoint, or empty.
    var sign_id: String

    def __init__(
        out self,
        id: ActorId,
        actor_state: ActorState,
        transform: CarlaTransform,
        velocity: Vector3,
        angular_velocity: Vector3,
        acceleration: Vector3,
    ):
        """Create a snapshot with no data of a kind.

        Args:
            id: The actor.
            actor_state: Whether it is active.
            transform: Its pose.
            velocity: Its velocity, in m/s.
            angular_velocity: Its angular velocity, in degrees per second.
            acceleration: Its acceleration, in m/s^2.
        """
        self.id = id
        self.actor_state = actor_state
        self.transform = transform
        self.velocity = velocity
        self.angular_velocity = angular_velocity
        self.acceleration = acceleration
        self.vehicle = None
        self.walker_control = None
        self.traffic_light = None
        self.sign_id = ""


struct WorldSnapshot(Copyable, Movable):
    """Every actor at one frame, CARLA's `WorldSnapshot`."""

    # The world's episode id.
    var id: Int
    var timestamp: Timestamp
    var actors: List[ActorSnapshot]

    def __init__(out self, id: Int, timestamp: Timestamp):
        """Create a snapshot with no actors.

        Args:
            id: The episode id.
            timestamp: The frame and its time.
        """
        self.id = id
        self.timestamp = timestamp
        self.actors = List[ActorSnapshot]()

    def frame(self) -> Int:
        """Return the frame, `GetFrame`.

        Returns:
            The timestamp's frame.
        """
        return self.timestamp.frame

    def contains(self, id: ActorId) -> Bool:
        """Return whether an actor is in the snapshot, `Contains`.

        Args:
            id: The actor.

        Returns:
            Whether a snapshot has that id.
        """
        for a in self.actors:
            if a.id == id:
                return True
        return False

    def find(self, id: ActorId) -> Optional[ActorSnapshot]:
        """Return an actor's snapshot, `Find`.

        Args:
            id: The actor.

        Returns:
            A copy of its snapshot, or None.
        """
        for a in self.actors:
            if a.id == id:
                return a.copy()
        return None

    def size(self) -> Int:
        """Return how many actors the snapshot holds.

        Returns:
            The count.
        """
        return len(self.actors)

    def __eq__(self, other: Self) -> Bool:
        """Return True for the same episode and frame, as CARLA compares.

        Args:
            other: The other snapshot.

        Returns:
            Whether the ids and the timestamps match.
        """
        return self.id == other.id and self.timestamp == other.timestamp
