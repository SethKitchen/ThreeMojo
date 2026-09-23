# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box drawn as lines, from three.js
`examples/jsm/geometries/BoxLineGeometry.js`.

The geometry is for a `LineSegments`: every two vertices are one stick.
Each segment boundary across the width gives a ring of four sticks round
the box, and the height and the depth do the same. So a box of one
segment each way is three sets of two rings, and every edge of the box is
drawn twice.

The positions are added up as three.js adds them: each ring starts where
the last ring was, plus one segment. So the last ring can miss the far
face by a rounding error, as in three.js.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from units.si import Length, METER


def _push(mut out: List[Float64], a: List[Float64], b: List[Float64]):
    """Append one stick, from `a` to `b`, three numbers each."""
    out.extend(a.copy())
    out.extend(b.copy())


def box_line(
    width: Length = Length(1, METER),
    height: Length = Length(1, METER),
    depth: Length = Length(1, METER),
    width_segments: Int = 1,
    height_segments: Int = 1,
    depth_segments: Int = 1,
) raises -> BufferGeometry:
    """Return the rings of a segmented box as line segments, three.js's
    `BoxLineGeometry`.

    Args:
        width: Extent along x. One meter by default.
        height: Extent along y. One meter by default.
        depth: Extent along z. One meter by default.
        width_segments: Cells along x, one or more.
        height_segments: Cells along y, one or more.
        depth_segments: Cells along z, one or more.

    Returns:
        A geometry with only `position`: eight vertices, four sticks, for
        each ring. The rings across x come first, then y, then z.

    Raises:
        Error: If an extent is not positive, or a segment count is less
            than one. three.js divides by zero for no segments.
    """
    if width.value <= 0 or height.value <= 0 or depth.value <= 0:
        raise Error("A box of lines needs positive extents")
    if width_segments < 1 or height_segments < 1 or depth_segments < 1:
        raise Error("A box of lines needs one segment each way")
    var w = Float64(width.value)
    var h = Float64(height.value)
    var d = Float64(depth.value)
    var wh = w / 2
    var hh = h / 2
    var dh = d / 2
    var segment_width = w / Float64(width_segments)
    var segment_height = h / Float64(height_segments)
    var segment_depth = d / Float64(depth_segments)
    var out = List[Float64]()
    var x = -wh
    var y = -hh
    var z = -dh
    for _ in range(width_segments + 1):  # pragma: no branch
        _push(out, [x, -hh, -dh], [x, hh, -dh])
        _push(out, [x, hh, -dh], [x, hh, dh])
        _push(out, [x, hh, dh], [x, -hh, dh])
        _push(out, [x, -hh, dh], [x, -hh, -dh])
        x += segment_width
    for _ in range(height_segments + 1):  # pragma: no branch
        _push(out, [-wh, y, -dh], [wh, y, -dh])
        _push(out, [wh, y, -dh], [wh, y, dh])
        _push(out, [wh, y, dh], [-wh, y, dh])
        _push(out, [-wh, y, dh], [-wh, y, -dh])
        y += segment_height
    for _ in range(depth_segments + 1):  # pragma: no branch
        _push(out, [-wh, -hh, z], [-wh, hh, z])
        _push(out, [-wh, hh, z], [wh, hh, z])
        _push(out, [wh, hh, z], [wh, -hh, z])
        _push(out, [wh, -hh, z], [-wh, -hh, z])
        z += segment_depth
    var data = List[Float32](capacity=len(out))
    for index in range(len(out)):  # pragma: no branch
        data.append(Float32(out[index]))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    return geometry^
