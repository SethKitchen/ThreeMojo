# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lymph nodes of the neck and the head, as implicit solids.

The deep cervical nodes lie in a chain along the internal jugular vein,
joined by the jugular trunk that runs down to the root of the neck. The
submandibular nodes lie under the body of the mandible, the parotid
nodes in front of the ear, the occipital nodes at the back of the
skull, and the supraclavicular nodes above the clavicle. Each group is
paired. Its nodes are small ellipsoids, a few representative ones a
group.

Every node is authored in the torso's frame, on the right; the left is
its mirror image. Radii are authored in template centimeters. They are
not a cited node count or size table.

    var dims = head_muscle_dimensions(person)
    var d = head_lymph_distance(dims, DEEP_CERVICAL_NODES, RIGHT, p)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    template_points,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
    spline_points,
    tube,
)
from math.vector3 import Vector3


@fieldwise_init
struct HeadLymph(Equatable, ImplicitlyCopyable, Writable):
    """Which lymph node group of the neck and the head a caller asks
    for.

    The type stops a bare integer at compile time. A value that is not
    one of the named groups is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named group."""
        if self.value < 0:
            return False
        return self.value <= SUPRACLAVICULAR_NODES.value


comptime DEEP_CERVICAL_NODES = HeadLymph(0)
comptime SUBMANDIBULAR_NODES = HeadLymph(1)
comptime PAROTID_NODES = HeadLymph(2)
comptime OCCIPITAL_NODES = HeadLymph(3)
comptime SUPRACLAVICULAR_NODES = HeadLymph(4)


def head_lymph_label(part: HeadLymph) -> String:
    """Return the error-text name of `part`.

    Args:
        part: A head lymph group, named or not.

    Returns:
        A short American English label, or `"head lymph"` when `part` is
        not named.
    """
    var labels: List[String] = [
        "deep cervical nodes",
        "submandibular nodes",
        "parotid nodes",
        "occipital nodes",
        "supraclavicular nodes",
    ]
    if not part.is_valid():
        return "head lymph"
    return labels[part.value]


def named_head_lymph() -> List[HeadLymph]:
    """Return every named head lymph group in a stable order.

    Returns:
        The deep cervical, submandibular, parotid, occipital and
        supraclavicular nodes.
    """
    var parts = List[HeadLymph]()
    for index in range(SUPRACLAVICULAR_NODES.value + 1):  # pragma: no branch
        parts.append(HeadLymph(index))
    return parts^


def head_lymph_field(
    dimensions: HeadMuscleDimensions, part: HeadLymph, side: BodySide
) raises -> SweepField:
    """Return the implicit solid of one head lymph group.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: A named group.
        side: `RIGHT` or `LEFT`.

    Returns:
        The group's field.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A head lymph group must be a named group")
    if not side.is_valid():
        raise Error("A head side must be RIGHT or LEFT")
    var f = dimensions.head.frame
    # Each node: x, y, z and its radius, in template cm.
    var nodes: List[Float32]
    # fmt: off
    if part == DEEP_CERVICAL_NODES:
        nodes = floats(
            3.4, 65.0, 0.2, 0.5, 3.6, 62.0, 0.9, 0.55,
            3.6, 59.0, 1.6, 0.6, 3.4, 56.0, 1.9, 0.5,
            3.1, 52.5, 1.9, 0.45,
        )
    elif part == SUBMANDIBULAR_NODES:
        nodes = floats(
            3.2, 61.4, 4.2, 0.35, 3.6, 61.9, 2.9, 0.4,
            2.6, 60.9, 5.4, 0.3,
        )
    elif part == PAROTID_NODES:
        nodes = floats(5.6, 69.5, 1.0, 0.3, 5.9, 67.4, 0.6, 0.32)
    elif part == OCCIPITAL_NODES:
        nodes = floats(2.6, 71.0, -8.8, 0.3, 3.9, 70.4, -7.8, 0.32)
    else:
        nodes = floats(4.8, 50.8, 0.6, 0.38, 6.0, 51.0, 0.0, 0.35)
    # fmt: on
    var sweeps = List[Sweep]()
    for index in range(len(nodes) // 4):  # pragma: no branch
        var node = Sweep(Vector3(1, 0, 0))
        node.add(
            f.at(nodes[index * 4], nodes[index * 4 + 1], nodes[index * 4 + 2]),
            f.cm(nodes[index * 4 + 3]),
            f.cm(0.7 * nodes[index * 4 + 3]),
        )
        sweeps.append(node^)
    if part == DEEP_CERVICAL_NODES:
        # The jugular trunk, down the chain to the root of the neck.
        var trunk = template_points(
            f,
            floats(
                3.4, 65.0, 0.2, 3.6, 59.0, 1.6, 3.1, 52.5, 1.9, 2.6, 49.2, 1.7
            ),
        )
        sweeps.append(tube(spline_points(trunk, 3), f.cm(0.12), f.cm(0.14)))
    return SweepField(
        sweeps^, List[Dome](), side, f.cm(0.15), f.cm(0.03), f.cm(0.3)
    )


def head_lymph_distance(
    dimensions: HeadMuscleDimensions,
    part: HeadLymph,
    side: BodySide,
    point: Vector3,
) raises -> Float32:
    """Return how far `point` lies outside `part`, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which group to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return head_lymph_field(dimensions, part, side).distance(point)
