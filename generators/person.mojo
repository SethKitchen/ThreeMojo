# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A low-poly crowd of pedestrians, from three.js
`examples/jsm/generators/city/PersonGenerator.js`.

A figure is lofted: a shaped head with two ears, a jacket, sleeves and
hands swept through their joints, shoes, and trousers whose two legs meet
at the crotch and are welded into one smooth piece. There are two shared
poses, walking and standing. A standing figure carries a bag.

Each placement is dealt a pose and its proportions from its place in the
list by three hashes, so the crowd varies but the same city deals the same
crowd. Each figure keeps its place as a seed, which three.js's material
hashes into a complexion, a hairstyle and an outfit. The material is not
ported.

The figure stands on y equals zero, centered in x and z, about 1.75
meters tall, and faces +z.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from generators.utils import (
    Instances,
    PartId,
    Vec3d,
    angle_radians as _a,
    length_meters as _l,
    meters,
    part,
    unit_vectors_quaternion,
)
from geometries.box import box
from geometries.cylinder import cylinder
from geometries.loft import loft
from geometries.sphere import sphere
from geometries.torus import torus
from geometries.utils import merge_geometries, merge_vertices
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import cos, pi, sin
from units.si import Length, METER

# A figure's parts.
comptime PERSON_SKIN = PartId(0)
comptime PERSON_HEAD = PartId(1)
comptime PERSON_COAT = PartId(2)
comptime PERSON_LEGS = PartId(3)
comptime PERSON_SHOES = PartId(4)
comptime PERSON_BAG = PartId(5)
comptime PERSON_SLEEVE = PartId(6)
comptime PERSON_HANDLE = PartId(7)


@fieldwise_init
struct Pose(Equatable, ImplicitlyCopyable, Writable):
    """Which of the two shared poses a figure takes, three.js's `walk` and
    `stand`, as a type rather than a string. `person_geometry` stops
    another value with `is_valid`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two poses.

        Returns:
            Whether the pose is walking or standing.
        """
        return self.value == 0 or self.value == 1


comptime WALK = Pose(0)
comptime STAND = Pose(1)


@fieldwise_init
struct Joint(ImplicitlyCopyable):
    """A joint a limb is swept through: its center and the radii of the
    ring there, across and along."""

    var center: Vec3d
    var rx: Float64
    var rz: Float64


def joint(
    parent: Vec3d, length: Float64, swing: Float64, splay: Float64
) -> Vec3d:
    """Return the joint a bone's length below its parent, swung forward
    and splayed out, three.js's `joint`.

    Args:
        parent: The parent joint.
        length: The bone's length, in meters.
        swing: The swing forward, in radians.
        splay: The splay sideways, in radians.

    Returns:
        The joint.
    """
    var vertical = length * cos(splay)
    return Vec3d(
        parent.x + length * sin(splay),
        parent.y - vertical * cos(swing),
        parent.z - vertical * sin(swing),
    )


def ring(
    center: Vec3d, rx: Float64, rz: Float64, segments: Int, phase: Float64
) -> List[Vec3d]:
    """Return an ellipse of points round a center in the ground plane,
    three.js's `ring`.

    Args:
        center: The center.
        rx: The radius along x.
        rz: The radius along z.
        segments: How many points.
        phase: The angle of the first point, in radians.

    Returns:
        The points.
    """
    var points = List[Vec3d]()
    for i in range(segments):
        var a = Float64(i) / Float64(segments) * pi * 2 + phase
        points.append(
            Vec3d(center.x + cos(a) * rx, center.y, center.z + sin(a) * rz)
        )
    return points^


def limb_sections(
    joints: List[Joint], segments: Int, phase: Float64
) -> List[List[Vec3d]]:
    """Return the rings of a limb, each turned to follow the limb through
    its joint, three.js's `limbSections`.

    Args:
        joints: The joints, from the root.
        segments: The points a ring.
        phase: The angle of each ring's first point.

    Returns:
        One ring a joint.
    """
    var sections = List[List[Vec3d]]()
    var last = len(joints) - 1
    for i in range(len(joints)):
        var before = joints[max(0, i - 1)].center
        var after = joints[min(last, i + 1)].center
        var turn = unit_vectors_quaternion(
            Vec3d(0, -1, 0), (after - before).normalized()
        )
        var points = ring(
            Vec3d(0, 0, 0), joints[i].rx, joints[i].rz, segments, phase
        )
        for k in range(len(points)):  # pragma: no branch
            points[k] = turn.apply(points[k]) + joints[i].center
        sections.append(points^)
    return sections^


def _vectors(sections: List[List[Vec3d]]) -> List[List[Vector3]]:
    """Return sections rounded to `Float32`, for a loft."""
    var out = List[List[Vector3]]()
    for i in range(len(sections)):  # pragma: no branch
        var row = List[Vector3]()
        for k in range(len(sections[i])):  # pragma: no branch
            row.append(sections[i][k].vector3())
        out.append(row^)
    return out^


def _limb(
    joints: List[Joint], cap_end: Bool, segments: Int
) raises -> BufferGeometry:
    """Return a limb lofted through its joints, three.js's `limb`."""
    return loft(
        _vectors(limb_sections(joints, segments, 0)), True, False, cap_end
    )


def torso_section(y: Float64, width: Float64, depth: Float64) -> List[Vec3d]:
    """Return a ring of the jacket: broad front and back, rounded sides,
    three.js's `torsoSection`.

    Args:
        y: The height, in meters.
        width: The half width.
        depth: The half depth.

    Returns:
        Eight points.
    """
    return [
        Vec3d(width, y, depth * 0.45),
        Vec3d(width * 0.65, y, depth),
        Vec3d(-width * 0.65, y, depth),
        Vec3d(-width, y, depth * 0.45),
        Vec3d(-width, y, -depth * 0.45),
        Vec3d(-width * 0.65, y, -depth),
        Vec3d(width * 0.65, y, -depth),
        Vec3d(width, y, -depth * 0.45),
    ]


def hip_section(side: Float64) -> List[Vec3d]:
    """Return the top ring of one trouser leg, three.js's `hipSection`:
    its inner edge meets the other leg's at the crotch.

    Args:
        side: One for the right leg, minus one for the left.

    Returns:
        Seven points.
    """
    var xs: List[Float64] = [1, -0.1, -0.8, -1, -0.8, -0.1, 1]
    var zs: List[Float64] = [0.5, 1, 0.7, 0, -0.7, -1, -0.5]
    var points = List[Vec3d]()
    for i in range(7):  # pragma: no branch
        var y = 0.82 if i == 0 or i == 6 else 0.89
        points.append(
            Vec3d(side * 0.093 - side * xs[i] * 0.093, y, zs[i] * 0.1)
        )
    if side > 0:
        points.reverse()
    return points^


def shoe_section(z: Float64, width: Float64, top: Float64) -> List[Vec3d]:
    """Return one ring of a shoe, three.js's `shoeSection`.

    Args:
        z: Where along the foot, in meters.
        width: The half width.
        top: The height of the upper.

    Returns:
        Six points.
    """
    return [
        Vec3d(width, top - 0.025, z),
        Vec3d(width * 0.7, top, z),
        Vec3d(-width * 0.7, top, z),
        Vec3d(-width, top - 0.025, z),
        Vec3d(-width * 0.9, -0.085, z),
        Vec3d(width * 0.9, -0.085, z),
    ]


def _uv_from(
    mut geometry: BufferGeometry, first: Int, second: Int, both: Bool
) raises:
    """Copy position components into the texture coordinates: `u` from
    one, and `v` from another when `both`."""
    var uv = geometry.clone_attribute(String(UV))
    ref p = geometry.attribute_view(String(POSITION))
    for i in range(p.count()):  # pragma: no branch
        uv.set_component(i, 0, p.component(i, first))
        if both:
            uv.set_component(i, 1, p.component(i, second))
    geometry.set_attribute(String(UV), uv^)


def _head(walking: Bool) raises -> List[BufferGeometry]:
    """Return the head and its two ears, turned and tilted for the pose
    and set so the crown is at 1.75."""
    var rows: List[Float64] = [
        1.75,
        0.014,
        0.014,
        -0.012,
        1.708,
        0.081,
        0.081,
        -0.01,
        1.656,
        0.093,
        0.086,
        0,
        1.617,
        0.086,
        0.077,
        0.009,
        1.561,
        0.072,
        0.065,
        0.012,
        1.532,
        0.045,
        0.043,
        0.005,
    ]
    var sections = List[List[Vec3d]]()
    for r in range(6):  # pragma: no branch
        sections.append(
            ring(
                Vec3d(0, rows[r * 4], rows[r * 4 + 3]),
                rows[r * 4 + 1],
                rows[r * 4 + 2],
                10,
                pi / 2,
            )
        )
    sections[3][0].z += 0.022
    var head = loft(_vectors(sections), True, True, True)
    # The unposed height rides in u, so the face follows the head.
    _uv_from(head, 1, 1, False)
    var heads: List[BufferGeometry] = [head^]
    for s in range(2):  # pragma: no branch
        var ear = sphere(_l(1), 4, 2)
        ear.scale(0.016, 0.026, 0.018)
        ear.translate(_l(Float64(s * 2 - 1) * 0.092), _l(1.62), _l(-0.004))
        heads.append(ear^)
    for i in range(3):  # pragma: no branch
        heads[i].translate(_l(0), _l(-1.535), _l(0))
        heads[i].rotate_y(_a(0.14 if walking else -0.16))
        heads[i].rotate_z(_a(-0.02 if walking else 0.055))
        heads[i].translate(_l(0), _l(1.535), _l(0))
    var offset = 1.75 - Float64(heads[0].bounding_box().max.y)
    for i in range(3):  # pragma: no branch
        heads[i].translate(_l(0), _l(offset), _l(0))
    return heads^


def _shoe(walking: Bool, side: Float64) raises -> BufferGeometry:
    """Return one shoe, turned for the pose, its sole still at the origin."""
    var sections: List[List[Vec3d]] = [
        shoe_section(-0.075, 0.044, -0.008),
        shoe_section(0.015, 0.054, 0.016),
        shoe_section(0.125, 0.055, -0.025),
        shoe_section(0.18, 0.036, -0.045),
    ]
    var shoe = loft(_vectors(sections), True, True, True)
    # The local height and length ride in the texture coordinates, so the
    # sole and the laces stay on the foot once it is posed.
    _uv_from(shoe, 1, 2, True)
    var pitch = (-0.12 if side < 0 else 0.25) if walking else 0.0
    var turn = side * 0.03 if walking else side * 0.16
    shoe.rotate_x(_a(pitch))
    shoe.rotate_y(_a(turn))
    return shoe^


def person_geometry(pose: Pose, height: Length) raises -> BufferGeometry:
    """Return one posed figure, three.js's `buildPersonGeometry`.

    Args:
        pose: Walking or standing.
        height: The figure's height. The figure is built 1.75 meters tall
            and scaled.

    Returns:
        The figure, indexed, with a `partId`.

    Raises:
        Error: If the pose is not one there is, or the height is not
            positive.
    """
    if not pose.is_valid():
        raise Error("A pose must be walking or standing")
    if not meters(height) > 0:
        raise Error("A person's height must be positive")
    var walking = pose == WALK
    var parts = List[BufferGeometry]()
    var heads = _head(walking)
    for i in range(3):  # pragma: no branch
        parts.append(part(heads[i], PERSON_HEAD if i == 0 else PERSON_SKIN))
    var neck = cylinder(_l(0.045), _l(0.052), _l(0.10), 5, 1, True)
    neck.translate(_l(0), _l(1.515), _l(0))
    parts.append(part(neck, PERSON_SKIN))
    var jacket_rows: List[Float64] = [
        1.5,
        0.055,
        0.052,
        1.425,
        0.20,
        0.10,
        1.365,
        0.195,
        0.111,
        1.285,
        0.18,
        0.115,
        1.095,
        0.152,
        0.103,
        1.015,
        0.166,
        0.108,
    ]
    var jacket = List[List[Vec3d]]()
    for r in range(6):  # pragma: no branch
        jacket.append(
            torso_section(
                jacket_rows[r * 3],
                jacket_rows[r * 3 + 1],
                jacket_rows[r * 3 + 2],
            )
        )
    parts.append(part(loft(_vectors(jacket), True, False, True), PERSON_COAT))
    var trousers = List[BufferGeometry]()
    var hips = List[List[Vec3d]]()
    for s in range(2):  # pragma: no branch
        var side = Float64(s * 2 - 1)
        _arm(parts, walking, side)
        var shoe = _shoe(walking, side)
        var hip = Vec3d(side * 0.093, 0.89, 0)
        var ankle_z = -side * 0.235 if walking else (
            0.065 if side < 0 else -0.025
        )
        var ankle = Vec3d(
            side * (0.105 if walking else 0.12),
            -Float64(shoe.bounding_box().min.y),
            ankle_z,
        )
        var knee = hip.lerp(ankle, 0.53)
        var bend = (0.095 if side > 0 else 0.015) if walking else (
            0.06 if side < 0 else 0.01
        )
        knee = Vec3d(knee.x, knee.y, knee.z + bend)
        var calf = knee.lerp(ankle, 0.40)
        var leg_joints: List[Joint] = [
            Joint(hip, 0.087, 0.092),
            Joint(knee, 0.062, 0.067),
            Joint(calf, 0.066, 0.067),
            Joint(ankle + Vec3d(0, -0.018, 0), 0.045, 0.046),
        ]
        var leg = limb_sections(
            leg_joints, 7, pi / 7 + (pi if side > 0 else 0.0)
        )
        leg[0] = hip_section(side)
        hips.append(leg[0].copy())
        trousers.append(loft(_vectors(leg), True, False, True))
        shoe.translate(_l(ankle.x), _l(ankle.y), _l(ankle.z))
        parts.append(part(shoe, PERSON_SHOES))
    var crotch = hips[0].copy()
    for i in range(1, 6):  # pragma: no branch
        crotch.append(hips[1][i])
    var waist: List[List[Vec3d]] = [
        ring(Vec3d(0, 1.04, 0), 0.157, 0.1, 12, pi / 2),
        crotch^,
    ]
    trousers.append(loft(_vectors(waist)))
    var pants = merge_geometries(trousers)
    pants.delete_attribute(String(NORMAL))
    pants.delete_attribute(String(UV))
    var joined = merge_vertices(pants)
    joined.compute_vertex_normals()
    joined.set_attribute(
        String(UV),
        BufferAttribute(
            List[Float32](length=joined.vertex_count() * 2, fill=0), 2
        ),
    )
    parts.append(part(joined, PERSON_LEGS))
    var geometry = merge_geometries(parts)
    var scale = meters(height) / 1.75
    if scale != 1:
        geometry.scale(Float32(scale), Float32(scale), Float32(scale))
    return geometry^


def _arm(mut parts: List[BufferGeometry], walking: Bool, side: Float64) raises:
    """Add one sleeve and hand, and on a standing figure's right hand a
    bag and its handle."""
    var swing = -side * 0.35 if walking else (-0.12 if side < 0 else 0.06)
    var shoulder = Vec3d(side * 0.197, 1.425, 0.008)
    var upper = joint(shoulder, 0.075, swing, side * 0.08)
    var elbow = joint(shoulder, 0.285, swing, side * 0.08)
    var wrist = joint(elbow, 0.255, swing - 0.22, side * 0.03)
    var sleeve: List[Joint] = [
        Joint(Vec3d(side * 0.14, 1.415, 0), 0.024, 0.035),
        Joint(upper, 0.066, 0.063),
        Joint(elbow, 0.051, 0.048),
        Joint(wrist, 0.029, 0.033),
    ]
    parts.append(part(_limb(sleeve, False, 5), PERSON_SLEEVE))
    var along = (wrist - elbow).normalized()
    var hand = wrist + along * 0.05
    var palm: List[Joint] = [
        Joint(wrist, 0.029, 0.033),
        Joint(hand, 0.032, 0.039),
        Joint(wrist + along * 0.095, 0.019, 0.025),
    ]
    parts.append(part(_limb(palm, True, 5), PERSON_SKIN))
    if not walking and side > 0:
        var bag = box(_l(0.075), _l(0.21), _l(0.22))
        bag.translate(_l(hand.x), _l(hand.y - 0.19), _l(hand.z))
        parts.append(part(bag, PERSON_BAG))
        var handle = torus(_l(0.045), _l(0.006), 3, 4, _a(pi))
        handle.rotate_y(_a(pi / 2))
        handle.translate(_l(hand.x), _l(hand.y - 0.08), _l(hand.z))
        parts.append(part(handle, PERSON_HANDLE))


def person_hash(index: Int, multiplier: Int) -> Float64:
    """Return one of the hashes that deal a figure its pose and
    proportions: `((index * multiplier) >>> 0) % 1000 / 1000`.

    Args:
        index: The figure's place in the list.
        multiplier: The hash's multiplier.

    Returns:
        A number from zero up to one, in thousandths.
    """
    return Float64(((index * multiplier) & 0xFFFFFFFF) % 1000) / 1000


struct PersonGenerator(Movable):
    """Builds the crowd, three.js's `PersonGenerator`: one instanced draw a
    pose, each figure with its own proportions and seed."""

    # The figure's standing height.
    var height: Length

    def __init__(out self):
        """Create three.js's default crowd."""
        self.height = Length(1.75, METER)

    def build(self, placements: List[Matrix4]) raises -> List[Instances]:
        """Deal each placement a pose and proportions and place it,
        three.js's `build`.

        Args:
            placements: One matrix a figure.

        Returns:
            The walking figures, then the standing ones, each named
            `People`. Each figure's matrix is its placement times its
            scale, and its value is its place in the list, three.js's
            `personSeed`.

        Raises:
            Error: If the height is not positive.
        """
        var walk = Instances("People", person_geometry(WALK, self.height))
        var stand = Instances("People", person_geometry(STAND, self.height))
        _ready(walk)
        _ready(stand)
        for i in range(len(placements)):
            var h1 = person_hash(i, 2654435761)
            var h2 = person_hash(i, 1597334677)
            var h3 = person_hash(i, 3812015801)
            var scale = 0.92 + h2 * 0.15
            var width = scale * (0.9 + h3 * 0.2)
            var sized = placements[i] * _scaling(width, scale, width)
            if h1 < 0.65:
                walk.matrices.append(sized)
                walk.values.append(Float32(i))
            else:
                stand.matrices.append(sized)
                stand.values.append(Float32(i))
        return [walk^, stand^]


def _ready(mut instances: Instances):
    """Set a crowd's seeds to one number a figure, and its shadows on."""
    instances.item_size = 1
    instances.cast_shadow = True
    instances.receive_shadow = True


def _scaling(x: Float64, y: Float64, z: Float64) -> Matrix4:
    """Return three.js's `makeScale`."""
    var m = Matrix4()
    m.elements[0] = Float32(x)
    m.elements[5] = Float32(y)
    m.elements[10] = Float32(z)
    return m
