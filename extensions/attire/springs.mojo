# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Spring chains: the secondary motion of things that hang and swing.

A scabbard swings from the hip, a plume from a helmet, a tasset from the
belt. None of them needs a cloth solver. Each is a chain of joints that
springs back toward its rest direction, drags against the air, falls
under gravity, and is kept off the body by capsules on its bones.

This is the spring bone of the VRM 1.0 format, `VRMC_springBone`, which
`three-vrm` implements for three.js. Each step, for each joint of the
chain, from the root out:

1. The joint's tail keeps the motion it had, less its drag.
2. It springs toward its rest direction, by the stiffness times the
   step's length, and falls by the gravity times the step's length.
3. It is put back at its bone's length from the joint's head.
4. Each collider pushes it out, and it is put back at its length again,
   four times over, where VRM does it once.
5. The joint turns so its bone points at the tail.

The settings use VRM's names and units: a stiffness and a gravity power
per second, a drag force zero through one, and a hit radius in meters.

A chain keeps its settings in the user data of its first node, under
`SPRING_KEY`. A glTF export writes them as that node's extras, and
`chain_settings` reads them back after a load. `vrm_spring_json` writes
the chains in the shape of `VRMC_springBone`, with joints and colliders
named by node, for a tool that makes a VRM file.

This is not a three.js port. See Extensions.

    var chain = add_spring_chain(scene, hip, [top, tip], SpringSettings())
    chain.colliders = body_colliders(person)
    scene.update()
    chain.step(scene, Duration(1.0 / 30, SECOND))
"""


from core.object3d import NodeId, Object3D
from core.scene import Scene
from core.user_data import UserData
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    LEFT_FOREARM,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    SPINE,
    Joint,
)
from loaders.json import parse_json
from math.quaternion import Quaternion
from math.vector3 import Vector3
from units.si import Duration, SECOND

comptime SPRING_KEY = "threemojo_spring"
"""The user data key a chain's first node keeps its settings under."""
comptime COLLISION_PASSES = 4
"""How many times a step pushes a tail out of the colliders and puts it back
at its length. VRM does it once; a few passes keep a tail from settling
inside a collider it rests against."""
comptime COLLIDER_STATURE = Float32(1.8288)
"""The template stature the body's colliders are sized for, in meters."""


struct SpringSettings(Copyable, ImplicitlyCopyable, Movable):
    """How a chain springs, in the units of `VRMC_springBone`."""

    var stiffness: Float32
    """How fast it springs back to rest, per second."""
    var gravity: Float32
    """How fast it falls, in meters per second."""
    var gravity_direction: Vector3
    """The unit direction it falls in."""
    var drag: Float32
    """How much of its motion the air takes each step, zero through one."""
    var radius: Float32
    """How far each joint's tail is kept off a collider, in meters."""

    def __init__(
        out self,
        stiffness: Float32 = 1.0,
        gravity: Float32 = 0.5,
        drag: Float32 = 0.4,
        radius: Float32 = 0.02,
    ):
        """Take a chain's settings. Gravity falls straight down.

        Args:
            stiffness: How fast it springs back, per second.
            gravity: How fast it falls, in meters per second.
            drag: How much of its motion it loses each step.
            radius: How far a tail is kept off a collider, in meters.
        """
        self.stiffness = stiffness
        self.gravity = gravity
        self.gravity_direction = Vector3(0, -1, 0)
        self.drag = drag
        self.radius = radius

    def check(self) raises:
        """Refuse settings a chain cannot use.

        Raises:
            Error: If the stiffness or the gravity is negative or not
                finite, the drag is not zero through one, the radius is
                negative, or the gravity's direction is not a unit
                vector.
        """
        if not (self.stiffness >= 0 and self.stiffness < 1e6):
            raise Error("A spring's stiffness must be zero or more")
        if not (self.gravity >= 0 and self.gravity < 1e6):
            raise Error("A spring's gravity must be zero or more")
        if not (self.drag >= 0 and self.drag <= 1):
            raise Error("A spring's drag must be zero through one")
        if not (self.radius >= 0 and self.radius < 1e6):
            raise Error("A spring's hit radius must be zero or more")
        if not (abs(self.gravity_direction.length() - 1) < 1e-3):
            raise Error("A spring's gravity direction must be a unit vector")


@fieldwise_init
struct SpringCollider(ImplicitlyCopyable):
    """A capsule on a bone that a chain cannot pass into. A capsule whose
    two ends meet is a sphere."""

    var node: NodeId
    """The bone it rides."""
    var start: Vector3
    """One end, in the bone's frame."""
    var end: Vector3
    """The other end, in the bone's frame."""
    var radius: Float32
    """Its radius, in meters."""


def _capsule(
    person: GameHumanoid, joint: Joint, radius: Float32
) -> SpringCollider:
    """Return a capsule down one bone of a person, in that bone's frame."""
    var along = person.rig.ends[joint.value] - person.rig.joints[joint.value]
    return SpringCollider(
        person.bones[joint.value], Vector3(0, 0, 0), along, radius
    )


def body_colliders(person: GameHumanoid) -> List[SpringCollider]:
    """Return capsules on a person's trunk and limbs, and a sphere on the
    head, sized for the person's stature.

    They stand for the body roughly, as the colliders of a game's
    character do: within a few centimeters of the skin.

    Args:
        person: The person.

    Returns:
        The colliders.
    """
    var s = person.rig.stature / COLLIDER_STATURE
    var all = List[SpringCollider]()
    all.append(_capsule(person, HIPS, 0.15 * s))
    all.append(_capsule(person, SPINE, 0.14 * s))
    all.append(_capsule(person, CHEST, 0.15 * s))
    for joint in [RIGHT_THIGH, LEFT_THIGH]:  # pragma: no branch
        all.append(_capsule(person, joint, 0.085 * s))
    for joint in [RIGHT_SHIN, LEFT_SHIN]:  # pragma: no branch
        all.append(_capsule(person, joint, 0.06 * s))
    for joint in [RIGHT_UPPER_ARM, LEFT_UPPER_ARM]:  # pragma: no branch
        all.append(_capsule(person, joint, 0.055 * s))
    for joint in [RIGHT_FOREARM, LEFT_FOREARM]:  # pragma: no branch
        all.append(_capsule(person, joint, 0.045 * s))
    var crown = person.rig.ends[HEAD.value] - person.rig.joints[HEAD.value]
    var middle = crown * 0.5
    all.append(
        SpringCollider(person.bones[HEAD.value], middle, middle, 0.1 * s)
    )
    return all^


def nearest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
    """Return the point of a segment nearest a point.

    Args:
        p: The point.
        a: One end.
        b: The other end. It may equal `a`.

    Returns:
        The nearest point.
    """
    var ab = b - a
    var length = ab.dot(ab)
    if length <= 0:
        return a
    var t = max(Float32(0), min(Float32(1), (p - a).dot(ab) / length))
    return a + ab * t


def push_out(p: Vector3, a: Vector3, b: Vector3, radius: Float32) -> Vector3:
    """Return a point pushed out of a capsule, or the point if it is out.

    Args:
        p: The point.
        a: One end of the capsule's axis.
        b: The other end.
        radius: The capsule's radius.

    Returns:
        The point, or the nearest point on the capsule's surface. A point
        on the axis itself is pushed straight up.
    """
    var on = nearest_on_segment(p, a, b)
    var away = p - on
    var gap = away.length()
    if gap >= radius:
        return p
    if gap <= 0:
        return on + Vector3(0, radius, 0)
    return on + away * (radius / gap)


def unit_or_down(v: Vector3) -> Vector3:
    """Return a vector at unit length, or straight down if it is zero.

    Args:
        v: The vector.

    Returns:
        Its direction, or minus y for a zero vector.
    """
    var length = v.length()
    if length <= 0:
        return Vector3(0, -1, 0)
    return v * (1 / length)


def _frame(scene: Scene, node: NodeId) raises -> Tuple[Vector3, Quaternion]:
    """Return a node's world position and world rotation."""
    var world = scene.world_matrix(node)
    return (
        world.transform_point(Vector3(0, 0, 0)),
        Quaternion.from_matrix(world.extract_rotation()),
    )


struct SpringChain(Movable):
    """A chain of joints that springs, and the state of its tails."""

    var parent: NodeId
    """The node the chain hangs from."""
    var nodes: List[NodeId]
    """Its joints, from the root out. The last is the tip and does not
    turn."""
    var offsets: List[Vector3]
    """Each joint's place in the joint before it, at rest."""
    var tails: List[Vector3]
    """Each moving joint's tail, in world space."""
    var previous: List[Vector3]
    """Each tail a step ago."""
    var settings: SpringSettings
    """How it springs."""
    var colliders: List[SpringCollider]
    """What it cannot pass into."""

    def __init__(
        out self,
        parent: NodeId,
        var nodes: List[NodeId],
        var offsets: List[Vector3],
        settings: SpringSettings,
    ) raises:
        """Hold a chain at rest. `start` places its tails.

        Args:
            parent: The node it hangs from.
            nodes: Its joints, two or more.
            offsets: Each joint's place in the one before it.
            settings: How it springs.

        Raises:
            Error: If there are fewer than two joints, or not one offset
                for each joint.
        """
        if len(nodes) < 2 or len(offsets) != len(nodes):
            raise Error("A spring chain needs two or more joints, each placed")
        self.parent = parent
        self.nodes = nodes^
        self.offsets = offsets^
        self.tails = List[Vector3]()
        self.previous = List[Vector3]()
        self.settings = settings
        self.colliders = List[SpringCollider]()

    def joint_count(self) -> Int:
        """Return how many joints turn: every one but the tip.

        Returns:
            The number of moving joints.
        """
        return len(self.nodes) - 1

    def start(mut self, scene: Scene) raises:
        """Put every tail where the scene has it now, at rest.

        Args:
            scene: The scene, updated.

        Raises:
            Error: If the scene is stale or a node is not in it.
        """
        self.tails = List[Vector3]()
        for k in range(1, len(self.nodes)):  # pragma: no branch
            self.tails.append(
                scene.world_matrix(self.nodes[k]).transform_point(
                    Vector3(0, 0, 0)
                )
            )
        self.previous = self.tails.copy()

    def step(mut self, mut scene: Scene, time: Duration) raises:
        """Move the chain one step and turn its joints.

        Call `scene.update` before the step, so the chain reads where its
        parent and its colliders' bones are, and after it, so the joints'
        new rotations reach the nodes hung from them.

        Args:
            scene: The scene, updated.
            time: The step's length, above zero.

        Raises:
            Error: If the step is not above zero, the settings do not
                check, or the scene is stale.
        """
        var dt = Float32(time.to(SECOND))
        if not (dt > 0 and dt < 1e6):
            raise Error("A spring's step must be above zero")
        self.settings.check()
        if len(self.tails) != self.joint_count():
            self.start(scene)
        # The colliders, in world space, once a step.
        var starts = List[Vector3]()
        var ends = List[Vector3]()
        for collider in self.colliders:
            var world = scene.world_matrix(collider.node)
            starts.append(world.transform_point(collider.start))
            ends.append(world.transform_point(collider.end))
        var frame = _frame(scene, self.parent)
        var head = frame[0] + frame[1].rotate(self.offsets[0])
        var turn = frame[1]
        for k in range(self.joint_count()):  # pragma: no branch
            var rest = self.offsets[k + 1]
            var length = rest.length()
            var axis = unit_or_down(rest)
            var tail = self.tails[k]
            var moved = tail + (tail - self.previous[k]) * (
                1 - self.settings.drag
            )
            moved = moved + turn.rotate(axis) * (self.settings.stiffness * dt)
            moved = moved + self.settings.gravity_direction * (
                self.settings.gravity * dt
            )
            moved = head + unit_or_down(moved - head) * length
            for _ in range(COLLISION_PASSES):  # pragma: no branch
                for c in range(len(self.colliders)):
                    moved = push_out(
                        moved,
                        starts[c],
                        ends[c],
                        self.colliders[c].radius + self.settings.radius,
                    )
                    moved = head + unit_or_down(moved - head) * length
            self.previous[k] = tail
            self.tails[k] = moved
            # Turn the joint so its bone points at the tail.
            var local = turn.conjugate().rotate(unit_or_down(moved - head))
            var spin = Quaternion.from_unit_vectors(axis, local)
            scene.node(self.nodes[k]).set_quaternion(spin)
            turn = turn * spin
            head = moved

    def record(self) raises -> UserData:
        """Return the chain's settings as the user data its first node
        keeps.

        Returns:
            The settings, in VRM's names.

        Raises:
            Error: If a setting is not finite.
        """
        var data = UserData()
        data.set_number("stiffness", Float64(self.settings.stiffness))
        data.set_number("gravityPower", Float64(self.settings.gravity))
        var g = self.settings.gravity_direction
        data.set_json(
            "gravityDir",
            "["
            + String(Float64(g.x))
            + ","
            + String(Float64(g.y))
            + ","
            + String(Float64(g.z))
            + "]",
        )
        data.set_number("dragForce", Float64(self.settings.drag))
        data.set_number("hitRadius", Float64(self.settings.radius))
        return data^


def add_spring_chain(
    mut scene: Scene,
    parent: NodeId,
    points: List[Vector3],
    settings: SpringSettings = SpringSettings(),
) raises -> SpringChain:
    """Hang a chain of joints from a node, and keep its settings on it.

    Args:
        scene: The scene.
        parent: The node the chain hangs from.
        points: Where its joints stand at rest, in the parent's frame, from
            the root out: two or more, each apart from the one before.
        settings: How it springs.

    Returns:
        The chain, at rest.

    Raises:
        Error: If there are fewer than two points, two points meet, the
            settings do not check, or the scene refuses a node.
    """
    settings.check()
    if len(points) < 2:
        raise Error("A spring chain needs two or more points")
    var nodes = List[NodeId]()
    var offsets = List[Vector3]()
    var hang = parent
    for k in range(len(points)):  # pragma: no branch
        var offset = points[k]
        if k > 0:
            offset = points[k] - points[k - 1]
            if offset.length() <= 0:
                raise Error("A spring chain's points must stand apart")
        var node = Object3D()
        node.set_position(offset.x, offset.y, offset.z)
        hang = scene.attach(node^, hang)
        nodes.append(hang)
        offsets.append(offset)
    var chain = SpringChain(parent, nodes^, offsets^, settings)
    scene.node(chain.nodes[0]).user_data.set_json(
        String(SPRING_KEY), chain.record().to_json()
    )
    return chain^


def chain_settings(data: UserData) raises -> SpringSettings:
    """Read a chain's settings back from its first node's user data.

    Args:
        data: The node's user data, as a glTF load gives it.

    Returns:
        The settings.

    Raises:
        Error: If the user data holds no chain, or it is malformed or
            does not check.
    """
    if not data.has(String(SPRING_KEY)):
        raise Error("This node keeps no spring chain")
    var document = parse_json(data.json(String(SPRING_KEY)))
    var root = document.root()
    var settings = SpringSettings()
    settings.stiffness = Float32(
        document.number(
            document.required(root, "stiffness", "A spring needs stiffness")
        )
    )
    settings.gravity = Float32(
        document.number(
            document.required(root, "gravityPower", "A spring needs gravity")
        )
    )
    var direction = document.required(
        root, "gravityDir", "A spring needs a gravity direction"
    )
    if document.length(direction) != 3:
        raise Error("A spring's gravity direction has three components")
    settings.gravity_direction = Vector3(
        Float32(document.number(document.at(direction, 0))),
        Float32(document.number(document.at(direction, 1))),
        Float32(document.number(document.at(direction, 2))),
    )
    settings.drag = Float32(
        document.number(
            document.required(root, "dragForce", "A spring needs drag")
        )
    )
    settings.radius = Float32(
        document.number(
            document.required(root, "hitRadius", "A spring needs a radius")
        )
    )
    settings.check()
    return settings^


def vrm_spring_json(scene: Scene, chains: List[SpringChain]) raises -> String:
    """Return chains in the shape of the `VRMC_springBone` extension.

    VRM names nodes by their index in the glTF file. This writes each
    node's name instead, in `"node"`, and a tool that writes the VRM file
    turns the names into indices. Each collider is a capsule, or a sphere
    where its ends meet, and has a collider group of its own.

    Args:
        scene: The scene, for the nodes' names.
        chains: The chains.

    Returns:
        One JSON object: `specVersion`, `colliders`, `colliderGroups` and
        `springs`.

    Raises:
        Error: If a node is not in the scene.
    """
    var colliders = String("[")
    var groups = String("[")
    var springs = String("[")
    var count = 0
    for k in range(len(chains)):
        ref chain = chains[k]
        var mine = String("[")
        for c in range(len(chain.colliders)):
            var collider = chain.colliders[c]
            if count > 0:
                colliders += ","
                groups += ","
            var shape: String
            if (collider.end - collider.start).length() <= 0:
                shape = (
                    '{"sphere":{"offset":'
                    + _triple(collider.start)
                    + ',"radius":'
                    + String(Float64(collider.radius))
                    + "}}"
                )
            else:
                shape = (
                    '{"capsule":{"offset":'
                    + _triple(collider.start)
                    + ',"radius":'
                    + String(Float64(collider.radius))
                    + ',"tail":'
                    + _triple(collider.end)
                    + "}}"
                )
            colliders += (
                '{"node":'
                + _quoted(scene.get(collider.node).name)
                + ',"shape":'
                + shape
                + "}"
            )
            groups += '{"colliders":[' + String(count) + "]}"
            if c > 0:
                mine += ","
            mine += String(count)
            count += 1
        mine += "]"
        if k > 0:
            springs += ","
        var joints = String("[")
        for j in range(len(chain.nodes)):  # pragma: no branch
            if j > 0:
                joints += ","
            joints += '{"node":' + _quoted(scene.get(chain.nodes[j]).name)
            joints += (
                ',"stiffness":'
                + String(Float64(chain.settings.stiffness))
                + ',"gravityPower":'
                + String(Float64(chain.settings.gravity))
                + ',"gravityDir":'
                + _triple(chain.settings.gravity_direction)
                + ',"dragForce":'
                + String(Float64(chain.settings.drag))
                + ',"hitRadius":'
                + String(Float64(chain.settings.radius))
                + "}"
            )
        springs += '{"joints":' + joints + '],"colliderGroups":' + mine + "}"
    var data = UserData()
    data.set_string("specVersion", "1.0")
    data.set_json("colliders", colliders + "]")
    data.set_json("colliderGroups", groups + "]")
    data.set_json("springs", springs + "]")
    return data.to_json()


def _triple(v: Vector3) -> String:
    """Return a vector as a JSON array of three numbers."""
    return (
        "["
        + String(Float64(v.x))
        + ","
        + String(Float64(v.y))
        + ","
        + String(Float64(v.z))
        + "]"
    )


def _quoted(text: String) raises -> String:
    """Return a string as JSON text."""
    var data = UserData()
    data.set_string("x", text)
    return data.json("x")
