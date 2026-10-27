# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the stored-moment pin specification.

The array, scalar, block, and routing tables are fixed. The caller supplies
the dependency record.
"""

from tools._python_json import PY_DICT, PyJson


def _array(mut doc: PyJson, arrays: Int, name: String, path: String, size: Int):
    """Add one array path and size.

    Args:
        doc: The document.
        arrays: The array object.
        name: The array name.
        path: The source path.
        size: The word count.
    """
    var record = doc.new_dict()
    doc.set(record, "path", doc.new_str(path))
    doc.set(record, "size", doc.new_int(size))
    doc.set(arrays, name, record)


def _scalar(mut doc: PyJson, scalars: Int, name: String):
    """Add one scalar whose size is 1.

    Args:
        doc: The document.
        scalars: The scalar object.
        name: The scalar name.
    """
    doc.set(scalars, name, doc.new_int(1))


def _block(mut doc: PyJson, blocks: Int, name: String, path: String):
    """Add one block path.

    Args:
        doc: The document.
        blocks: The block-path object.
        name: The block name.
        path: The source path.
    """
    doc.set(blocks, name, doc.new_str(path))


def _boundary(
    mut doc: PyJson,
    boundaries: Int,
    name: String,
    begin: String,
    end: String,
):
    """Add one block's begin and end markers.

    Args:
        doc: The document.
        boundaries: The boundary object.
        name: The block name.
        begin: The opening marker.
        end: The closing marker.
    """
    var record = doc.new_dict()
    doc.set(record, "begin", doc.new_str(begin))
    doc.set(record, "end", doc.new_str(end))
    doc.set(boundaries, name, record)


def _route(mut doc: PyJson, routes: Int, name: String, path: String):
    """Add one routing path.

    Args:
        doc: The document.
        routes: The routing object.
        name: The routing name.
        path: The source path.
    """
    doc.set(routes, name, doc.new_str(path))


def moment_pin_spec(payload: String) raises -> String:
    """Return the moment pin specification.

    Args:
        payload: A JSON object with a `dependencies` object.

    Returns:
        The specification, including that dependency object.

    Raises:
        Error: `dependencies` is missing or is not an object.
    """
    var doc = PyJson.parse(payload)
    var dependencies = doc.at(doc.root, "dependencies")
    if doc.kind(dependencies) != PY_DICT:
        raise Error("moment pin dependencies changed")
    var spec = doc.new_dict()
    var arrays = doc.new_dict()
    _array(doc, arrays, "_GL_NODES", "extensions/carla/geometry.mojo", 5)
    _array(doc, arrays, "_GL_WEIGHTS", "extensions/carla/geometry.mojo", 5)
    _array(
        doc, arrays, "_COS_COEFFICIENTS", "extensions/carla/curve_trig.mojo", 11
    )
    _array(
        doc, arrays, "_SIN_COEFFICIENTS", "extensions/carla/curve_trig.mojo", 11
    )
    doc.set(spec, "arrays", arrays)
    var scalars = doc.new_dict()
    _scalar(doc, scalars, "_PHASE_LIMIT")
    _scalar(doc, scalars, "_INV_HALF_PI")
    _scalar(doc, scalars, "_HALF_PI_HIGH")
    _scalar(doc, scalars, "_HALF_PI_LOW")
    doc.set(spec, "scalars", scalars)
    doc.set(
        spec, "scalar_path", doc.new_str("extensions/carla/curve_trig.mojo")
    )
    var blocks = doc.new_dict()
    _block(
        doc,
        blocks,
        "geometry_trig_aliases",
        "extensions/carla/lane_geometry.mojo",
    )
    _block(doc, blocks, "scalar_spiral", "extensions/carla/lane_geometry.mojo")
    _block(doc, blocks, "scalar_horner", "extensions/carla/curve_trig.mojo")
    _block(doc, blocks, "scalar_sincos", "extensions/carla/curve_trig.mojo")
    _block(
        doc, blocks, "scalar_trig_wrappers", "extensions/carla/curve_trig.mojo"
    )
    _block(
        doc, blocks, "ideal_sincos_selector", "extensions/carla/curve_trig.mojo"
    )
    _block(doc, blocks, "ideal_horner", "extensions/carla/curve_trig.mojo")
    _block(
        doc, blocks, "ideal_sincos_branch", "extensions/carla/curve_trig.mojo"
    )
    _block(doc, blocks, "ideal_spiral", "extensions/carla/curve_bounds.mojo")
    _block(doc, blocks, "ideal_uncertain", "extensions/carla/curve_trig.mojo")
    doc.set(spec, "block_paths", blocks)
    var boundaries = doc.new_dict()
    _boundary(
        doc,
        boundaries,
        "geometry_trig_aliases",
        "from extensions.carla.curve_trig import (",
        "from std.math import ceil",
    )
    _boundary(
        doc,
        boundaries,
        "scalar_spiral",
        "def _lane_spiral(geometry: RoadGeometry, d: Float64)",
        "def _lane_geometry_derivative_at(",
    )
    _boundary(
        doc,
        boundaries,
        "scalar_horner",
        "def _scalar_polynomial[",
        "def _jet_polynomial[",
    )
    _boundary(
        doc,
        boundaries,
        "scalar_sincos",
        "@no_inline\ndef _curve_sincos(value: Float64)",
        "def _curve_sin(value: Float64)",
    )
    _boundary(
        doc,
        boundaries,
        "scalar_trig_wrappers",
        "def _curve_sin(value: Float64)",
        "@no_inline\ndef _curve_atan(",
    )
    _boundary(
        doc,
        boundaries,
        "ideal_sincos_selector",
        "def _sincos_expression[",
        "def _constant_sincos_jet(",
    )
    _boundary(
        doc,
        boundaries,
        "ideal_horner",
        "def _expression_polynomial[",
        "@no_inline\ndef _curve_sincos(",
    )
    _boundary(
        doc,
        boundaries,
        "ideal_sincos_branch",
        "def _sincos_branch_expression[",
        "def _uncertain(value:",
    )
    _boundary(
        doc,
        boundaries,
        "ideal_spiral",
        "def _spiral_expression[",
        "def _sample_index(",
    )
    _boundary(
        doc,
        boundaries,
        "ideal_uncertain",
        "def _uncertain_expression[",
        "def _sincos_jet(",
    )
    doc.set(spec, "boundaries", boundaries)
    var routes = doc.new_dict()
    _route(doc, routes, "ideal_caller", "extensions/carla/curve_bounds.mojo")
    _route(doc, routes, "trig_dependencies", "extensions/carla/curve_trig.mojo")
    _route(
        doc, routes, "canonical_scalar", "extensions/carla/lane_geometry.mojo"
    )
    _route(doc, routes, "stored_geometry", "extensions/carla/geometry.mojo")
    doc.set(spec, "routing_paths", routes)
    doc.set(spec, "dependencies", doc.copy_node(dependencies))
    doc.root = spec
    return doc.dumps()
