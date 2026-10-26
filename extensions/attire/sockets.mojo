# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named places on the body where a game hangs things.

A socket is a point on the rig that rides one bone: a helmet's crest on
the crown, a shield on the back, a sword at the hip, a weapon in the
hand. Each socket is placed from the rig's own landmarks and scaled
with its stature, so it lands in the same place on every body.

| Socket | Rides | Where |
|---|---|---|
| `CROWN` | head | the top of the head |
| `BACK` | chest | between the shoulder blades, behind the body |
| `RIGHT_HIP`, `LEFT_HIP` | hips | on each side of the hips, at the belt |
| `BELT_FRONT` | hips | in front, at the belt |
| `RIGHT_SHOULDER`, `LEFT_SHOULDER` | chest | on top of each shoulder |
| `RIGHT_GRIP`, `LEFT_GRIP` | each hand | in each palm, where a hilt is held |

`attach` hangs a node from a socket's bone, at the socket. The node
keeps the rotation it was given, so a caller turns a scabbard or a
shield before it is attached. The game humanoid's eyes and hair hang
from the head the same way.

This is not a three.js port. See Extensions.

    var sword = Object3D()
    sword.rotate_z(Angle(20.0, DEGREE))
    var held = attach(scene, person, LEFT_HIP, sword^)
"""

from core.object3d import NodeId, Object3D
from core.ordinal import ordinal_label, ordinal_valid, require_valid
from core.scene import Scene
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_HAND,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    RIGHT_HAND,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    HumanoidRig,
    Joint,
)
from math.vector3 import Vector3

comptime SOCKET_STATURE = Float32(1.8288)
"""The template stature the offsets are given for, in meters."""


@fieldwise_init
struct Socket(Equatable, ImplicitlyCopyable, Writable):
    """A named place on the body that rides one bone."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named socket.

        Returns:
            True for `CROWN` through `LEFT_GRIP`.
        """
        return ordinal_valid(self.value, SOCKET_COUNT - 1)


comptime CROWN = Socket(0)
"""The top of the head."""
comptime BACK = Socket(1)
"""Between the shoulder blades, behind the body."""
comptime RIGHT_HIP = Socket(2)
"""The right side of the hips, at the belt."""
comptime LEFT_HIP = Socket(3)
"""The left side of the hips, at the belt."""
comptime BELT_FRONT = Socket(4)
"""In front of the hips, at the belt."""
comptime RIGHT_SHOULDER = Socket(5)
"""On top of the right shoulder."""
comptime LEFT_SHOULDER = Socket(6)
"""On top of the left shoulder."""
comptime RIGHT_GRIP = Socket(7)
"""In the right palm."""
comptime LEFT_GRIP = Socket(8)
"""In the left palm."""
comptime SOCKET_COUNT = 9
"""How many sockets there are."""


def socket_label(socket: Socket) -> String:
    """Return the name of a socket.

    Args:
        socket: A socket, named or not.

    Returns:
        Its name, as `"leftHip"`, or `"socket"` when it is not named.
    """
    var names: List[String] = [
        "crown",
        "back",
        "rightHip",
        "leftHip",
        "beltFront",
        "rightShoulder",
        "leftShoulder",
        "rightGrip",
        "leftGrip",
    ]
    return ordinal_label(socket.is_valid(), socket.value, names, "socket")


def require_socket(socket: Socket) raises:
    """Refuse a socket that is not named.

    Args:
        socket: The socket.

    Raises:
        Error: If the socket is not named.
    """
    require_valid(socket.is_valid(), "A socket must be a named socket")


def socket_joint(socket: Socket) raises -> Joint:
    """Return the joint a socket rides.

    Args:
        socket: A named socket.

    Returns:
        Its joint.

    Raises:
        Error: If the socket is not named.
    """
    require_socket(socket)
    var joints: List[Joint] = [
        HEAD,
        CHEST,
        HIPS,
        HIPS,
        HIPS,
        CHEST,
        CHEST,
        RIGHT_HAND,
        LEFT_HAND,
    ]
    return joints[socket.value]


def _side(rig: HumanoidRig, right: Joint, left: Joint) -> Vector3:
    """Return the unit step from the left joint toward the right one."""
    var across = rig.joints[right.value] - rig.joints[left.value]
    var length = across.length()
    if length <= 0:
        return Vector3(1, 0, 0)
    return across * (1 / length)


def socket_place(rig: HumanoidRig, socket: Socket) raises -> Vector3:
    """Return where a socket stands on a rig at rest.

    Args:
        rig: The rig.
        socket: A named socket.

    Returns:
        The socket's place in the pelvis frame, in meters.

    Raises:
        Error: If the socket is not named.
    """
    require_socket(socket)
    var s = rig.stature / SOCKET_STATURE
    var right = _side(rig, RIGHT_THIGH, LEFT_THIGH)
    var up = Vector3(0, 1, 0)
    # Forward is the right crossed with up: the pelvis frame has plus x
    # to the right, plus y up and plus z forward.
    var forward = Vector3(
        right.y * up.z - right.z * up.y,
        right.z * up.x - right.x * up.z,
        right.x * up.y - right.y * up.x,
    )
    var hips = rig.joints[HIPS.value]
    if socket == CROWN:
        return rig.ends[HEAD.value]
    if socket == BACK:
        return rig.joints[CHEST.value] + up * (0.08 * s) - forward * (0.16 * s)
    if socket == RIGHT_HIP:
        return hips + right * (0.19 * s) + up * (0.06 * s)
    if socket == LEFT_HIP:
        return hips - right * (0.19 * s) + up * (0.06 * s)
    if socket == BELT_FRONT:
        return hips + up * (0.08 * s) + forward * (0.15 * s)
    if socket == RIGHT_SHOULDER:
        return rig.joints[RIGHT_UPPER_ARM.value] + up * (0.07 * s)
    if socket == LEFT_SHOULDER:
        return rig.joints[LEFT_UPPER_ARM.value] + up * (0.07 * s)
    var hand = RIGHT_HAND
    if socket == LEFT_GRIP:
        hand = LEFT_HAND
    var wrist = rig.joints[hand.value]
    return wrist + (rig.ends[hand.value] - wrist) * 0.4


def attach(
    mut scene: Scene, person: GameHumanoid, socket: Socket, var node: Object3D
) raises -> NodeId:
    """Hang a node from a person's socket.

    The node rides the socket's bone. It stands at the socket at rest and
    keeps the rotation it was given.

    Args:
        scene: The scene the person is in.
        person: The person.
        socket: A named socket.
        node: The node to hang; its position is set to the socket's.

    Returns:
        The node's id.

    Raises:
        Error: If the socket is not named or the scene refuses the node.
    """
    var joint = socket_joint(socket)
    var at = socket_place(person.rig, socket) - person.rig.joints[joint.value]
    node.set_position(at.x, at.y, at.z)
    return scene.attach(node^, person.bones[joint.value])
