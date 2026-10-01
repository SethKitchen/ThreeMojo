# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's actors: the ids, kinds and states, and the record a world keeps.

An actor is anything a world holds: a vehicle, a walker, a traffic light,
a traffic sign, a sensor or a plain prop. Each has an `ActorId`, the id of
the blueprint it was made from, the attributes it was made with, a
bounding box in its own frame and the semantic tags a camera sees. The
world keeps one `Actor` per id, an entity registry, and keeps what is
particular to a vehicle, a walker or a signal in its own list.

The enums are CARLA's: `rpc/ActorId.h`, `rpc/ActorState.h`,
`rpc/AttachmentType.h` and `rpc/TrafficLightState.h`, and the actor kinds
of CARLA's simulator plugin, `Carla/Actor/CarlaActor.h`.
"""

from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.physics.body import BodyId
from extensions.carla.sensor import SemanticTag
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.matrix3 import Matrix3
from math.obb import OBB
from math.vector3 import Vector3
from std.math import asin, atan2
from units.si import DEGREE, Angle

comptime _UINT32_MAX = 4294967295


@fieldwise_init
struct ActorId(Equatable, ImplicitlyCopyable, Writable):
    """An actor's id, CARLA's `ActorId`: a 32-bit number. Zero is none."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits CARLA's unsigned 32 bits.

        Returns:
            Whether the value is from 0 to 2^32 - 1. Zero is valid and
            names no actor.
        """
        return self.value >= 0 and self.value <= _UINT32_MAX


# The parent of an actor that has none.
comptime NO_ACTOR = ActorId(0)


@fieldwise_init
struct ActorKind(Equatable, ImplicitlyCopyable, Writable):
    """What an actor is: CARLA's actor type."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a kind.

        Returns:
            Whether the value is from 0 to 5.
        """
        return self.value >= 0 and self.value <= 5


comptime OTHER_ACTOR = ActorKind(0)
comptime VEHICLE_ACTOR = ActorKind(1)
comptime WALKER_ACTOR = ActorKind(2)
comptime TRAFFIC_LIGHT_ACTOR = ActorKind(3)
comptime TRAFFIC_SIGN_ACTOR = ActorKind(4)
comptime SENSOR_ACTOR = ActorKind(5)


@fieldwise_init
struct ActorState(Equatable, ImplicitlyCopyable, Writable):
    """Whether an actor is simulated, `rpc::ActorState`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a state.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


comptime ACTOR_INVALID = ActorState(0)
comptime ACTOR_ACTIVE = ActorState(1)
comptime ACTOR_DORMANT = ActorState(2)
comptime ACTOR_PENDING_KILL = ActorState(3)


@fieldwise_init
struct AttachmentType(Equatable, ImplicitlyCopyable, Writable):
    """How a child follows its parent, `rpc::AttachmentType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names an attachment.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime RIGID = AttachmentType(0)
comptime SPRING_ARM = AttachmentType(1)
comptime SPRING_ARM_GHOST = AttachmentType(2)


@fieldwise_init
struct TrafficLightState(Equatable, ImplicitlyCopyable, Writable):
    """A traffic light's color, `rpc::TrafficLightState`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a state.

        Returns:
            Whether the value is from 0 to 4.
        """
        return self.value >= 0 and self.value <= 4


comptime RED = TrafficLightState(0)
comptime YELLOW = TrafficLightState(1)
comptime GREEN = TrafficLightState(2)
comptime OFF = TrafficLightState(3)
comptime UNKNOWN = TrafficLightState(4)


def no_rotation() -> CarlaRotation:
    """Return the rotation that turns nothing.

    Returns:
        Zero pitch, yaw and roll.
    """
    return CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE))


def compose(parent: CarlaTransform, child: CarlaTransform) -> CarlaTransform:
    """Return a child's world pose from its pose in its parent's frame.

    Args:
        parent: The parent's pose in the world.
        child: The child's pose in the parent's frame.

    Returns:
        The child's pose in the world. The location is the parent's
        `transform_point` of the child's; the rotation turns as the
        parent's rotation after the child's.
    """
    var m = rotation_matrix(parent.rotation) * rotation_matrix(child.rotation)
    var out = parent
    out.location = parent.transform_point(child.location)
    out.rotation = rotation_of(m)
    return out


def relative(parent: CarlaTransform, world: CarlaTransform) -> CarlaTransform:
    """Return a pose in a parent's frame, the inverse of `compose`.

    Args:
        parent: The parent's pose in the world.
        world: The pose in the world.

    Returns:
        The pose in the parent's frame.
    """
    var back = rotation_matrix(parent.rotation)
    back.transpose()
    var m = back * rotation_matrix(world.rotation)
    var out = world
    out.location = parent.inverse_transform_point(world.location)
    out.rotation = rotation_of(m)
    return out


def rotation_matrix(r: CarlaRotation) -> Matrix3:
    """Return a rotation as a matrix whose columns are its axes.

    Args:
        r: The rotation.

    Returns:
        The matrix with the forward, right and up vectors as columns.
    """
    var f = r.forward_vector()
    var y = r.right_vector()
    var u = r.up_vector()
    var m = Matrix3()
    m.set(f.x, y.x, u.x, f.y, y.y, u.y, f.z, y.z, u.z)
    return m


def rotation_of(m: Matrix3) -> CarlaRotation:
    """Return the pitch, yaw and roll of a rotation matrix.

    Args:
        m: A rotation whose columns are the forward, right and up axes.

    Returns:
        The rotation, as CARLA's `Rotation` reads it: the third row is
        (-sin pitch, cos pitch sin roll, cos pitch cos roll).
    """
    ref e = m.elements
    # `Matrix3` is column-major: element (row, column) is e[column * 3 + row].
    var pitch = asin(max(min(-e[2], Float32(1)), Float32(-1)))
    var yaw = atan2(e[1], e[0])
    var roll = atan2(e[5], e[8])
    var to_degrees = Float32(57.29577951308232)
    return CarlaRotation(
        Angle(pitch * to_degrees, DEGREE),
        Angle(yaw * to_degrees, DEGREE),
        Angle(roll * to_degrees, DEGREE),
    )


def world_obb(transform: CarlaTransform, box: BoundingBox) raises -> OBB:
    """Return a bounding box in the world.

    Args:
        transform: The pose of the box's frame, such as an actor's.
        box: The box in that frame.

    Returns:
        The oriented box: its center moved by the pose, its axes the pose's
        turn of the box's own axes.

    Raises:
        Error: If the half size is not valid.
    """
    var axes = rotation_matrix(transform.rotation) * rotation_matrix(
        box.rotation
    )
    return OBB(transform.transform_point(box.location), box.extent, axes)


struct Actor(Copyable, Movable):
    """What a world knows of one actor, the registry's record."""

    var id: ActorId
    # The blueprint's id, such as "vehicle.lincoln.mkz".
    var type_id: String
    var kind: ActorKind
    var state: ActorState
    # The blueprint's values when the actor spawned.
    var attributes: List[ActorAttributeValue]
    var parent: ActorId
    var attachment: AttachmentType
    # Where the actor is in its parent's frame, or in the world with no
    # parent. A vehicle's and a walker's pose come from their body.
    var local_transform: CarlaTransform
    var bounding_box: BoundingBox
    var semantic_tags: List[SemanticTag]
    # The actor's place in the world's list for its kind, or -1.
    var handle: Int
    # The physics body of a vehicle or a walker, or -1.
    var body: BodyId
    # The velocity at the last tick, in m/s, for the acceleration.
    var last_velocity: Vector3

    def __init__(
        out self,
        id: ActorId,
        type_id: String,
        kind: ActorKind,
        var attributes: List[ActorAttributeValue],
        transform: CarlaTransform,
        bounding_box: BoundingBox,
        var semantic_tags: List[SemanticTag],
    ) raises:
        """Create an active actor with no parent.

        Args:
            id: Its id.
            type_id: Its blueprint's id.
            kind: What it is.
            attributes: The values it was made with.
            transform: Where it is.
            bounding_box: Its box in its own frame.
            semantic_tags: The tags a camera sees on it.

        Raises:
            Error: If the id or the kind is not valid.
        """
        if not (id.is_valid() and kind.is_valid()):
            raise Error("Actor id or kind is not valid")
        self.id = id
        self.type_id = type_id
        self.kind = kind
        self.state = ACTOR_ACTIVE
        self.attributes = attributes^
        self.parent = NO_ACTOR
        self.attachment = RIGID
        self.local_transform = transform
        self.bounding_box = bounding_box
        self.semantic_tags = semantic_tags^
        self.handle = -1
        self.body = BodyId(-1)
        self.last_velocity = Vector3(0, 0, 0)

    def is_alive(self) -> Bool:
        """Return whether the actor is in the world, `IsAlive`.

        Returns:
            Whether its state is active or dormant.
        """
        return self.state == ACTOR_ACTIVE or self.state == ACTOR_DORMANT

    def attribute(self, id: String) -> Optional[ActorAttributeValue]:
        """Return one of the values the actor was made with.

        Args:
            id: The attribute's id.

        Returns:
            The value, or None.
        """
        for a in self.attributes:
            if a.id == id:
                return a.copy()
        return None

    def role_name(self) -> String:
        """Return the actor's role name.

        Returns:
            The `role_name` attribute, or empty.
        """
        var found = self.attribute("role_name")
        if Bool(found):
            return found.value().value
        return ""
