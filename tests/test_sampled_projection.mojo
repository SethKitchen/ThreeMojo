# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The copied sampled helpers keep their reviewed projection."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._python_tokens import (
    decorator_prefix,
    decorator_prefix_json,
    project_union_value,
)
from tools._python_json import PyJson
from tools._sampled_declarations import sampled_declarations
from tools._sampled_projection import project_reviewed_helpers
from tools._sampled_value_gate import (
    drop_derivative_intersection,
    extract_sampled_function,
    rename_sampled_identifiers,
)


def _absent(doc: PyJson, node: Int, name: String) -> Bool:
    """Return whether `name` is absent from one object.

    Args:
        doc: The projection document.
        node: An object in `doc`.
        name: A helper name.

    Returns:
        True when `name` is not a key.
    """
    var missing = False
    try:
        _ = doc.at(node, name)
    except error:
        missing = True
    return missing


def test_decorator_prefix_map_matches_one_lookup() raises:
    """One tokenization records the same prefix as a single lookup."""
    var source = (
        "@a\n@b(1)\ndef f():\n    return 1\ndef other():\n    return 2\n"
    )
    var doc = PyJson.parse(decorator_prefix_json(source))
    assert_equal(doc.text(doc.at(doc.root, "f")), decorator_prefix(source, "f"))
    assert_equal(
        doc.text(doc.at(doc.root, "other")), decorator_prefix(source, "other")
    )


def test_copied_helpers_keep_the_reviewed_projection() raises:
    """Blend drops both intersections, and the union dispatcher replaces the copy.
    """
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    var record = PyJson.parse(project_reviewed_helpers(bounds, trig))
    var helpers = record.at(record.root, "helpers")
    var blend = rename_sampled_identifiers(
        extract_sampled_function(bounds, "_sample_blend_jet")
    )
    blend = drop_derivative_intersection(blend, "first")
    blend = drop_derivative_intersection(blend, "second")
    var blend_text = record.text(record.at(helpers, "_sample_blend_value"))
    var blend_body = blend.byte_length()
    assert_equal(
        String(blend_text[byte = blend_text.byte_length() - blend_body :]),
        blend,
    )
    var union = rename_sampled_identifiers(
        extract_sampled_function(bounds, "_union_points")
    )
    assert_equal(
        record.text(record.at(helpers, "_union_value_points")),
        project_union_value(union),
    )
    var declared = PyJson.parse(sampled_declarations())
    assert_equal(
        record.text(record.at(helpers, "_uncertain_value")),
        declared.text(declared.at(declared.root, "_uncertain_value")),
    )
    var atan = rename_sampled_identifiers(
        extract_sampled_function(trig, "_atan_jet")
    )
    var atan_text = record.text(record.at(helpers, "_atan_value"))
    var atan_body = atan.byte_length()
    assert_equal(
        String(atan_text[byte = atan_text.byte_length() - atan_body :]),
        atan,
    )
    assert_equal(record.length(helpers), 17)
    assert_false(_absent(record, helpers, "_constant_sincos_value"))
    assert_false(_absent(record, helpers, "_lane_value_bound_impl"))
    assert_false(_absent(record, helpers, "_reference_sampled_value"))
    var constant = record.at(record.root, "constant")
    var lane = record.at(record.root, "lane")
    assert_true(record.text(record.at(constant, "dump")).byte_length() > 0)
    assert_true(record.text(record.at(constant, "pair")).byte_length() > 0)
    assert_true(record.text(record.at(lane, "refusal")).byte_length() > 0)
    assert_true(record.text(record.at(lane, "capture")).byte_length() > 0)


def main() raises:
    """Run the sampled projection tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
