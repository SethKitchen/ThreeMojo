# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Text as a solid, from three.js
`examples/jsm/geometries/TextGeometry.js`.

three.js's `TextGeometry` is an `ExtrudeGeometry` of the shapes a `Font`
lays the text out as, with defaults of its own. This is the same: the
font gives the shapes, `extrude` gives each one its thickness, and the
parts are joined end to end in the order of the shapes. That is the order
three.js's `ExtrudeGeometry` writes them in when it is given a list of
shapes, one shape's caps and walls after another's.

The defaults are three.js's: a size of 100, a depth of 50, a bevel 10
thick and 8 out when it is turned on. They are in meters here, so a
caller sets `size` to the height it wants.

## Groups

three.js's `ExtrudeGeometry` adds two groups per shape, one for the caps
and one for the walls, so a caller can give them two materials. This does
the same: each shape's two groups from `extrude` are kept, moved to where
the shape starts. The caps wear material 0 and the walls material 1.

A text with nothing to draw, such as spaces, is a geometry with empty
`position`, `normal` and `uv` attributes, as it is in three.js. The
options are checked all the same.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.extrude import check_extrusion, extrude
from geometries.utils import merge_geometries
from loaders.font import Font
from units.si import Length, METER


def text_geometry(
    text: String,
    font: Font,
    size: Length = Length(100, METER),
    depth: Length = Length(50, METER),
    curve_segments: Int = 12,
    steps: Int = 1,
    bevel_enabled: Bool = False,
    bevel_thickness: Length = Length(10, METER),
    bevel_size: Length = Length(8, METER),
    bevel_offset: Length = Length(0, METER),
    bevel_segments: Int = 3,
) raises -> BufferGeometry:
    """Return `text` in `font` as a solid, three.js's `TextGeometry`.

    Args:
        text: The text. `\\n` starts a new line.
        font: The font the text is set in.
        size: One em; positive.
        depth: How thick the letters are, along z from zero; positive.
        curve_segments: How many straight runs each curve of a glyph is
            sampled into; at least one.
        steps: How many layers the walls are cut into; at least one.
        bevel_enabled: True to round the edges of the letters off.
        bevel_thickness: How far past each face the bevel reaches;
            positive when there is a bevel.
        bevel_size: How far out from the outline the bevel stands; not
            negative when there is a bevel.
        bevel_offset: How far out every layer is moved before the bevel is
            measured.
        bevel_segments: How many bands each bevel is cut into; at least one
            when there is a bevel.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index buffer, as `extrude` builds it, one shape after another,
        with each shape's two groups.

    Raises:
        Error: If an option is refused by `check_extrusion`, if the size is
            not positive or a character has no glyph (see
            `Font.generate_shapes`), or if a glyph's shape cannot be filled
            in (see `geometries.shape.triangulate`).
    """
    check_extrusion(
        depth,
        steps,
        curve_segments,
        bevel_enabled,
        bevel_thickness,
        bevel_size,
        bevel_segments,
    )
    var shapes = font.generate_shapes(text, size)
    if len(shapes) == 0:
        var empty = BufferGeometry()
        empty.set_attribute(
            String(POSITION), BufferAttribute(List[Float32](), 3)
        )
        empty.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
        empty.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
        return empty^
    var parts = List[BufferGeometry]()
    for index in range(len(shapes)):  # pragma: no branch
        # There is a shape, so this runs.
        parts.append(
            extrude(
                shapes[index],
                depth,
                steps,
                curve_segments,
                bevel_enabled,
                bevel_thickness,
                bevel_size,
                bevel_offset,
                bevel_segments,
            )
        )
    var merged = merge_geometries(parts)
    # Each shape's caps and walls, moved to where the shape starts, as
    # three.js's `ExtrudeGeometry` adds them shape after shape.
    var offset = 0
    for index in range(len(parts)):  # pragma: no branch
        for group in parts[index].groups:  # pragma: no branch
            merged.add_group(
                offset + group.start, group.count, group.material_index
            )
        offset += parts[index].vertex_count()
    return merged^
