# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cut a surface into triangles no longer than a limit, from three.js
`examples/jsm/modifiers/TessellateModifier.js`.

Each pass looks at every triangle. A triangle with an edge longer than
the limit is cut in two across its longest edge, at the middle of it. A
triangle with every edge short enough is kept. The passes stop when one
pass cuts nothing, or after the most passes allowed. So a triangle can
still have a long edge at the end, if the passes ran out.

The midpoint takes the average of the two ends' position, normal, color
and both texture coordinates. The normal is not made unit length again,
as in three.js. The new points are worked out in doubles, as three.js's
arrays hold them, and rounded to floats only at the end.

Only `position`, `normal`, `color`, `uv` and `uv1` are kept. Other
attributes, the groups and the morph targets are dropped, as in three.js.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    COLOR,
    NORMAL,
    POSITION,
    UV,
    UV1,
)
from std.math import isfinite
from units.si import Length, METER


def _names() -> List[String]:
    """Return the names the modifier carries, positions first."""
    return [
        String(POSITION),
        String(NORMAL),
        String(COLOR),
        String(UV),
        String(UV1),
    ]


def _sizes() -> List[Int]:
    """Return how many numbers an item of each of `_names` holds."""
    return [3, 3, 3, 2, 2]


def _lerped(data: List[Float64], size: Int, a: Int, b: Int) -> List[Float64]:
    """Return the item halfway between items `a` and `b`, three.js's
    `lerpVectors` and `lerpColors` at one half."""
    var out = List[Float64](capacity=size)
    for axis in range(size):  # pragma: no branch
        # An item size is two or three, so this runs.
        var start = data[a * size + axis]
        out.append(start + (data[b * size + axis] - start) * 0.5)
    return out^


def _distance_squared(p: List[Float64], a: Int, b: Int) -> Float64:
    """Return the squared distance between two positions."""
    var dx = p[a * 3] - p[b * 3]
    var dy = p[a * 3 + 1] - p[b * 3 + 1]
    var dz = p[a * 3 + 2] - p[b * 3 + 2]
    return dx * dx + dy * dy + dz * dz


def tessellate(
    geometry: BufferGeometry,
    max_edge_length: Length = Length(0.1, METER),
    max_iterations: Int = 6,
) raises -> BufferGeometry:
    """Return a surface cut until no edge is longer than a limit, three.js's
    `TessellateModifier.modify`.

    Args:
        geometry: The surface. It must carry positions; an indexed one is
            made non-indexed first.
        max_edge_length: The longest edge to keep, zero or more. A tenth
            of a meter by default, as in three.js.
        max_iterations: The most passes to make, zero or more. Six by
            default, as in three.js.

    Returns:
        A geometry without an index, holding the attributes named in the
        module docstring that the surface carries.

    Raises:
        Error: If the limit is negative or not finite, the pass count is
            negative, the surface has no positions, an attribute it keeps
            holds the wrong number of numbers an item, or its vertices do
            not make whole triangles.
    """
    if not (max_edge_length.value >= 0 and isfinite(max_edge_length.value)):
        raise Error("A tessellation edge limit must be finite and not negative")
    if max_iterations < 0:
        raise Error("A tessellation cannot make a negative number of passes")
    var flat = geometry.to_non_indexed()
    var count = flat.vertex_count()
    if count % 3 != 0:
        raise Error("A tessellated surface must be whole triangles")
    var limit = Float64(max_edge_length.value) * Float64(max_edge_length.value)
    # The arrays of the attributes that are there, in `_names` order.
    var names = _names()
    var sizes = _sizes()
    var present = List[Int]()
    var arrays = List[List[Float64]]()
    for slot in range(len(names)):  # pragma: no branch
        ref name = names[slot]
        if not flat.has_attribute(name):
            continue
        ref attribute = flat.attribute_view(name)
        if attribute.item_size != sizes[slot]:
            raise Error("A tessellated attribute has the wrong item size")
        var numbers = attribute.packed()
        var doubles = List[Float64](capacity=len(numbers))
        for index in range(len(numbers)):
            doubles.append(Float64(numbers[index]))
        present.append(slot)
        arrays.append(doubles^)

    var iteration = 0
    var tessellating = True
    while tessellating and iteration < max_iterations:
        iteration += 1
        tessellating = False
        var next = List[List[Float64]]()
        for _ in range(len(arrays)):  # pragma: no branch
            # Positions are always there, so this runs.
            next.append(List[Float64]())
        var triangles = len(arrays[0]) // 9
        for triangle in range(triangles):
            var a = triangle * 3
            var b = a + 1
            var c = a + 2
            var dab = _distance_squared(arrays[0], a, b)
            var dbc = _distance_squared(arrays[0], b, c)
            var dac = _distance_squared(arrays[0], a, c)
            # The corners of each new triangle, in three.js's order: the
            # three old corners are 0, 1 and 2, and the midpoint is 3.
            var corners: List[Int] = [0, 1, 2]
            var ends: List[Int] = [a, a]
            if dab > limit or dbc > limit or dac > limit:
                tessellating = True
                if dab >= dbc and dab >= dac:
                    ends = [a, b]
                    corners = [0, 3, 2, 3, 1, 2]
                elif dbc >= dab and dbc >= dac:
                    ends = [b, c]
                    corners = [0, 1, 3, 3, 2, 0]
                else:
                    ends = [a, c]
                    corners = [0, 1, 3, 3, 1, 2]
            for attribute in range(len(arrays)):  # pragma: no branch
                # Positions are always there, so this runs.
                var size = sizes[present[attribute]]
                ref data = arrays[attribute]
                var middle = _lerped(data, size, ends[0], ends[1])
                for corner in corners:  # pragma: no branch
                    # Three corners at least, so this runs.
                    if corner == 3:
                        next[attribute].extend(middle.copy())
                        continue
                    var item = a + corner
                    for axis in range(size):  # pragma: no branch
                        # An item size is two or three.
                        next[attribute].append(data[item * size + axis])
        arrays = next^

    var result = BufferGeometry()
    for attribute in range(len(arrays)):  # pragma: no branch
        # Positions are always there, so this runs.
        var slot = present[attribute]
        var numbers = List[Float32](capacity=len(arrays[attribute]))
        for index in range(len(arrays[attribute])):
            numbers.append(Float32(arrays[attribute][index]))
        result.set_attribute(
            names[slot], BufferAttribute(numbers^, sizes[slot])
        )
    return result^
