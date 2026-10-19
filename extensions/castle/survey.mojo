# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A castle plan in JSON, so that a survey can replace the estimates.

`plan_to_json` writes a plan. `plan_from_json` reads one and checks it. The
text is plain JSON. Every length is in meters. Every angle is in degrees.
The plan frame is the frame of `extensions.castle.plan`: x to the east, y to
the north and z up, with the ground of the island at z = 0.

The top-level keys are `name`, `latitude`, `longitude`, `towers`, `blocks`,
`moat` and `bridge`. A tower has `name`, `shape`, `x`, `y`, `radius`, `wall`,
`height`, `roof` and `roof_rise`. A block has `name`, `x`, `y`, `length`,
`width`, `heading`, `wall`, `height`, `roof` and `roof_rise`. The moat has
`x`, `y`, `semi_x`, `semi_y`, `island_x`, `island_y`, `island_semi_x`,
`island_semi_y`, `depth` and `freeboard`. The bridge has `x`, `y`, `heading`,
`spans`, `span`, `pier`, `rise`, `ring`, `width`, `fill`, `springing` and
`parapet`. The shape is `round` or `square`. The roof is `cone`, `gable` or
`parapet`.
"""

from extensions.castle.kinds import (
    roof_form_from_name,
    tower_shape_from_name,
)
from extensions.castle.plan import (
    Block,
    Bridge,
    CastlePlan,
    Moat,
    PlanPoint,
    Tower,
)
from loaders.json import JsonDocument, parse_json, quote_json
from units.si import Angle64, DEGREE64, Length64, METER


def _m(value: Float64) -> Length64:
    """Return meters as a length."""
    return Length64(value, METER)


def _pair(key: String, value: Float64) -> String:
    """Return one key and one number as JSON."""
    return quote_json(key) + ": " + String(value)


def _text(key: String, value: String) -> String:
    """Return one key and one string as JSON."""
    return quote_json(key) + ": " + quote_json(value)


def _tower_json(tower: Tower) -> String:
    """Return a tower as a JSON object."""
    return String(
        "{",
        _text("name", tower.name),
        ", ",
        _text("shape", tower.shape.name()),
        ", ",
        _pair("x", tower.center.x.value),
        ", ",
        _pair("y", tower.center.y.value),
        ", ",
        _pair("radius", tower.radius.value),
        ", ",
        _pair("wall", tower.wall.value),
        ", ",
        _pair("height", tower.height.value),
        ", ",
        _text("roof", tower.roof.name()),
        ", ",
        _pair("roof_rise", tower.roof_rise.value),
        "}",
    )


def _block_json(block: Block) -> String:
    """Return a block as a JSON object."""
    return String(
        "{",
        _text("name", block.name),
        ", ",
        _pair("x", block.center.x.value),
        ", ",
        _pair("y", block.center.y.value),
        ", ",
        _pair("length", block.length.value),
        ", ",
        _pair("width", block.width.value),
        ", ",
        _pair("heading", block.heading.to(DEGREE64)),
        ", ",
        _pair("wall", block.wall.value),
        ", ",
        _pair("height", block.height.value),
        ", ",
        _text("roof", block.roof.name()),
        ", ",
        _pair("roof_rise", block.roof_rise.value),
        "}",
    )


def _moat_json(moat: Moat) -> String:
    """Return the moat as a JSON object."""
    return String(
        "{",
        _pair("x", moat.center.x.value),
        ", ",
        _pair("y", moat.center.y.value),
        ", ",
        _pair("semi_x", moat.semi_x.value),
        ", ",
        _pair("semi_y", moat.semi_y.value),
        ", ",
        _pair("island_x", moat.island_center.x.value),
        ", ",
        _pair("island_y", moat.island_center.y.value),
        ", ",
        _pair("island_semi_x", moat.island_semi_x.value),
        ", ",
        _pair("island_semi_y", moat.island_semi_y.value),
        ", ",
        _pair("depth", moat.depth.value),
        ", ",
        _pair("freeboard", moat.freeboard.value),
        "}",
    )


def _bridge_json(bridge: Bridge) -> String:
    """Return the bridge as a JSON object."""
    return String(
        "{",
        _pair("x", bridge.start.x.value),
        ", ",
        _pair("y", bridge.start.y.value),
        ", ",
        _pair("heading", bridge.heading.to(DEGREE64)),
        ", ",
        _pair("spans", Float64(bridge.spans)),
        ", ",
        _pair("span", bridge.span.value),
        ", ",
        _pair("pier", bridge.pier.value),
        ", ",
        _pair("rise", bridge.rise.value),
        ", ",
        _pair("ring", bridge.ring.value),
        ", ",
        _pair("width", bridge.width.value),
        ", ",
        _pair("fill", bridge.fill.value),
        ", ",
        _pair("springing", bridge.springing.value),
        ", ",
        _pair("parapet", bridge.parapet.value),
        "}",
    )


def plan_to_json(plan: CastlePlan) -> String:
    """Write a plan as JSON text.

    Args:
        plan: The plan. It is not checked.

    Returns:
        The text, one part to a line. Lengths are in meters and angles are
        in degrees.
    """
    var out = String("{\n")
    out += "  " + _text("name", plan.name) + ",\n"
    out += "  " + _pair("latitude", plan.latitude.to(DEGREE64)) + ",\n"
    out += "  " + _pair("longitude", plan.longitude.to(DEGREE64)) + ",\n"
    out += '  "towers": [\n'
    for i in range(len(plan.towers)):
        if i > 0:
            out += ",\n"
        out += "    " + _tower_json(plan.towers[i])
    out += '\n  ],\n  "blocks": [\n'
    for i in range(len(plan.blocks)):
        if i > 0:
            out += ",\n"
        out += "    " + _block_json(plan.blocks[i])
    out += '\n  ],\n  "moat": ' + _moat_json(plan.moat) + ",\n"
    out += '  "bridge": ' + _bridge_json(plan.bridge) + "\n}\n"
    return out^


def _number(document: JsonDocument, node: Int, key: String) raises -> Float64:
    """Return a number of an object, or refuse a survey that lacks it."""
    return document.number(
        document.required(node, key, "A survey must give the number " + key)
    )


def _string(document: JsonDocument, node: Int, key: String) raises -> String:
    """Return a string of an object, or refuse a survey that lacks it."""
    return document.string(
        document.required(node, key, "A survey must give the text " + key)
    )


def _point(
    document: JsonDocument, node: Int, x: String, y: String
) raises -> PlanPoint:
    """Return a point of an object from two keys."""
    return PlanPoint(
        _m(_number(document, node, x)), _m(_number(document, node, y))
    )


def _tower(document: JsonDocument, node: Int) raises -> Tower:
    """Read a tower."""
    return Tower(
        _string(document, node, "name"),
        tower_shape_from_name(_string(document, node, "shape")),
        _point(document, node, "x", "y"),
        _m(_number(document, node, "radius")),
        _m(_number(document, node, "wall")),
        _m(_number(document, node, "height")),
        roof_form_from_name(_string(document, node, "roof")),
        _m(_number(document, node, "roof_rise")),
    )


def _block(document: JsonDocument, node: Int) raises -> Block:
    """Read a block."""
    return Block(
        _string(document, node, "name"),
        _point(document, node, "x", "y"),
        _m(_number(document, node, "length")),
        _m(_number(document, node, "width")),
        Angle64(_number(document, node, "heading"), DEGREE64),
        _m(_number(document, node, "wall")),
        _m(_number(document, node, "height")),
        roof_form_from_name(_string(document, node, "roof")),
        _m(_number(document, node, "roof_rise")),
    )


def _moat(document: JsonDocument, node: Int) raises -> Moat:
    """Read the moat."""
    return Moat(
        _point(document, node, "x", "y"),
        _m(_number(document, node, "semi_x")),
        _m(_number(document, node, "semi_y")),
        _point(document, node, "island_x", "island_y"),
        _m(_number(document, node, "island_semi_x")),
        _m(_number(document, node, "island_semi_y")),
        _m(_number(document, node, "depth")),
        _m(_number(document, node, "freeboard")),
    )


def _bridge(document: JsonDocument, node: Int) raises -> Bridge:
    """Read the bridge."""
    return Bridge(
        _point(document, node, "x", "y"),
        Angle64(_number(document, node, "heading"), DEGREE64),
        document.integer(
            document.required(
                node, "spans", "A survey must give the number spans"
            )
        ),
        _m(_number(document, node, "span")),
        _m(_number(document, node, "pier")),
        _m(_number(document, node, "rise")),
        _m(_number(document, node, "ring")),
        _m(_number(document, node, "width")),
        _m(_number(document, node, "fill")),
        _m(_number(document, node, "springing")),
        _m(_number(document, node, "parapet")),
    )


def plan_from_json(text: String) raises -> CastlePlan:
    """Read a plan from JSON text and check it.

    Args:
        text: The text, in the form that `plan_to_json` writes.

    Returns:
        The plan. It has passed `CastlePlan.check`.

    Raises:
        Error: If the text is not JSON, a key is missing or has the wrong
            kind of value, a shape or roof is not named, or a part of the
            plan cannot stand.
    """
    var document = parse_json(text)
    var root = document.root()
    var towers = List[Tower]()
    var tower_list = document.required(
        root, "towers", "A survey must list its towers"
    )
    for i in range(document.length(tower_list)):
        towers.append(_tower(document, document.at(tower_list, i)))
    var blocks = List[Block]()
    var block_list = document.required(
        root, "blocks", "A survey must list its blocks"
    )
    for i in range(document.length(block_list)):
        blocks.append(_block(document, document.at(block_list, i)))
    var plan = CastlePlan(
        _string(document, root, "name"),
        Angle64(_number(document, root, "latitude"), DEGREE64),
        Angle64(_number(document, root, "longitude"), DEGREE64),
        towers^,
        blocks^,
        _moat(
            document,
            document.required(root, "moat", "A survey must give the moat"),
        ),
        _bridge(
            document,
            document.required(root, "bridge", "A survey must give the bridge"),
        ),
    )
    plan.check()
    return plan^
