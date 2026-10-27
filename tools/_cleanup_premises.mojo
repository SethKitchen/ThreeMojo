# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write the reviewed cleanup premise directory.

The five declaration texts come from the caller. The fragment lists and
their labels stay in historical order.
"""

from std.pathlib import Path

from tools._python_json import PyJson


def _words(mut doc: PyJson, var fragments: List[String]) -> Int:
    """Return a JSON list of fragment strings.

    Args:
        doc: The document.
        fragments: The fragments, in order.

    Returns:
        The list node.
    """
    var node = doc.new_list()
    for fragment in fragments:
        doc.append(node, doc.new_str(fragment))
    return node


def _row(
    mut doc: PyJson,
    rows: Int,
    directory: String,
    index: Int,
    key: String,
    var fragments: List[String],
    label: String,
) raises:
    """Write one source file and append its premise row.

    Args:
        doc: The document.
        rows: The row list.
        directory: The premise directory.
        index: The source file number.
        key: The source key in `sources.json`.
        fragments: The fragments that must occur once, in order.
        label: The failure label.

    Raises:
        Error: `key` is missing.
    """
    var source = doc.text(doc.at(doc.root, key))
    Path(directory + "/" + String(index) + ".mojo").write_text(source)
    var row = doc.new_dict()
    doc.set(row, "label", doc.new_str(label))
    doc.set(row, "fragments", _words(doc, fragments^))
    doc.append(rows, row)


def prepare_cleanup_premises(directory: String) raises:
    """Write `labels.json` and the five declaration files.

    Args:
        directory: A directory that already holds `sources.json`.

    Raises:
        Error: A declaration key is missing, or `sources.json` is not an
            object.
    """
    var doc = PyJson.parse(Path(directory + "/sources.json").read_text())
    var rows = doc.new_list()
    var line = List[String]()
    line.append("road._check_lane(section, lane)")
    line.append("if len(road.info.geometries) != 1: return None")
    line.append("not _RoundedBox.bounds(low, high).known")
    line.append("if info_index(road.info.geometries, low) != 0: return None")
    line.append("or info_index(road.info.lane_offsets, high) != offset_at")
    line.append("or info_index(road.info.elevations, high) != elevation_at")
    line.append(
        "if width_at < 0 or info_index(widths, high) != width_at: return None"
    )
    _row(
        doc,
        rows,
        directory,
        0,
        "line",
        line^,
        "LINE singleton/domain/low lookup and multi-record profile premises",
    )
    var arc = List[String]()
    arc.append("road._check_lane(section, lane)")
    arc.append("if len(road.info.geometries) != 1: return None")
    arc.append(
        "if not _RoundedBox.bounds(low, high).known or high > road.length:"
        " return None"
    )
    arc.append("if info_index(road.info.geometries, low) != 0: return None")
    arc.append(
        "if len(road.info.lane_offsets) != 1 or len(road.info.elevations) != 1:"
        " return None"
    )
    arc.append("info_index(road.info.lane_offsets, low) != 0")
    arc.append("or info_index(road.info.elevations, low) != 0")
    arc.append("if len(widths) != 1: return None")
    arc.append("if info_index(widths, low) != 0: return None")
    _row(
        doc,
        rows,
        directory,
        1,
        "arc",
        arc^,
        "ARC singleton/domain/low lookup premises",
    )
    var bounds = List[String]()
    bounds.append("_rounded_operand(low)")
    bounds.append("_rounded_operand(high)")
    bounds.append("and low <= high")
    _row(
        doc,
        rows,
        directory,
        2,
        "bounds",
        bounds^,
        "ordered finite domain premise",
    )
    var center = List[String]()
    center.append("if not half.known: return [unknown, unknown, unknown]")
    center.append(
        "var selector = _rounded_madd(half, _RoundedBox.point(_INV_HALF_PI),"
        " _RoundedBox.point(0.5))"
    )
    center.append(
        "if not selector.known or selector.low < 0.0 or selector.high >= 1.0:"
        " return [unknown, unknown, unknown]"
    )
    center.append("var square = half * half")
    _row(
        doc,
        rows,
        directory,
        3,
        "center",
        center^,
        "quarter implication requires the same accepted selector hull",
    )
    var outward = List[String]()
    outward.append("var result = Float32(value)")
    outward.append("var outside: Bool")
    outward.append("if lower: outside = Float64(result) > value")
    outward.append("else: outside = Float64(result) < value")
    outward.append("if outside:")
    outward.append("UInt32(0x80000001) if lower else UInt32(1)")
    outward.append("if (result > 0.0) == lower: bits -= 1 else: bits += 1")
    outward.append("result = bitcast[DType.float32](bits)")
    _row(
        doc,
        rows,
        directory,
        4,
        "outward",
        outward^,
        "outward conversion direction and adjacent-word premises",
    )
    var saved = doc.root
    doc.root = rows
    var text = doc.dumps()
    doc.root = saved
    Path(directory + "/labels.json").write_text(text)
