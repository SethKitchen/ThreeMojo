# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Sampled identifier renaming matches the Python checker."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._process import run_program
from tests._python_tokens import project_constant_heading, sampled_top_level
from tests._python_expr import (
    body_role_json,
    body_statement_json,
    expression_dump,
    return_elements_json,
    statement_dump,
)
from tools._python_json import PyJson
from tools._sampled_value_gate import (
    drop_derivative_intersection,
    extract_sampled_function,
    rename_sampled_identifiers,
)


def test_comments_and_strings_keep_the_old_name() raises:
    var source = (
        'def _atan_jet(x):\n    # _Jet stays\n    s = "_Jet"\n    return _Jet\n'
    )
    assert_equal(
        rename_sampled_identifiers(source),
        (
            'def _atan_value(x):\n    # _Jet stays\n    s = "_Jet"\n    return'
            " _ValueJet\n"
        ),
    )
    assert_equal(
        rename_sampled_identifiers('r"_Jet"\n_Jet\n'), 'r"_Jet"\n_ValueJet\n'
    )
    assert_equal(
        rename_sampled_identifiers("''' _Jet '''\n_Jet\n"),
        "''' _Jet '''\n_ValueJet\n",
    )
    var formatted = 'f"' + "{" + "_Jet" + "}" + '"\n'
    var formatted_out = 'f"' + "{" + "_ValueJet" + "}" + '"\n'
    assert_equal(rename_sampled_identifiers(formatted), formatted_out)


def test_the_first_derivative_intersection_becomes_a_blank_line() raises:
    """Only the first derivative intersection assignment is removed."""
    var source = (
        "keep\n"
        + "    result.first = _intersect_ideal_bounds(result.first,"
        " ideal.first)\n"
        + "    result.first = _intersect_ideal_bounds(result.first,"
        " ideal.first)\n"
    )
    assert_equal(
        drop_derivative_intersection(source, "first"),
        (
            "keep\n\n"
            + "    result.first = _intersect_ideal_bounds(result.first,"
            " ideal.first)\n"
        ),
    )
    with assert_raises(contains="derivative intersection shape changed"):
        _ = drop_derivative_intersection("none\n", "second")
    with assert_raises(contains="derivative intersection shape changed"):
        _ = drop_derivative_intersection(
            (
                "result.first = _intersect_ideal_bounds( result.first,"
                " ideal.first)\n"
            ),
            "first",
        )


def test_one_function_is_cut_before_the_next() raises:
    var source = "def _atan_jet(x):\n    return _Jet\ndef other():\n    pass\n"
    assert_equal(
        extract_sampled_function(source, "_atan_jet"),
        "def _atan_jet(x):\n    return _Jet\n",
    )
    with assert_raises(contains="missing or ambiguous function"):
        _ = extract_sampled_function(source, "absent")


def _names() -> List[String]:
    """Return every renamed function the checker copies or projects."""
    var names = List[String]()
    var literals = List[String]()
    literals.append("_polynomial_jet")
    literals.append("_unknown_point")
    literals.append("_geometry_distance")
    literals.append("_sample_blend_jet")
    literals.append("_sample_jet")
    literals.append("_atan_branch")
    literals.append("_atan_jet")
    literals.append("_atan2_jet")
    literals.append("_jet_polynomial")
    literals.append("_uncertain")
    literals.append("_sinc_jet")
    literals.append("_sincos_jet")
    literals.append("_arc_offset_jet")
    literals.append("_constant_sincos_jet")
    literals.append("_union_points")
    for name in literals:
        names.append(name)
    return names^


def test_every_renamed_function_matches_python() raises:
    """Each live jet function renames like `check_sampled_values.translated`."""
    var script = (
        "import sys\n"
        "sys.path.insert(0, 'tools/carla_lane_oracle')\n"
        "import check_sampled_values as checker\n"
        "files = [open(path).read() for path in ("
        "'extensions/carla/curve_trig.mojo',"
        "'extensions/carla/curve_bounds.mojo')]\n"
        "names = sys.argv[1].split(',')\n"
        "for name in names:\n"
        "    found = None\n"
        "    for text in files:\n"
        "        try:\n"
        "            found = checker.function(text, name)\n"
        "            break\n"
        "        except checker.CheckError:\n"
        "            continue\n"
        "    if found is None:\n"
        "        sys.stderr.write('missing ' + name)\n"
        "        sys.exit(1)\n"
        "    sys.stdout.write('\\n---RAW ' + name + '\\n')\n"
        "    sys.stdout.write(found)\n"
        "    sys.stdout.write('\\n---REN ' + name + '\\n')\n"
        "    sys.stdout.write(checker.translated(found))\n"
    )
    var joined = String("")
    var names = _names()
    for index in range(len(names)):
        if index > 0:
            joined += ","
        joined += names[index]
    var result = run_program(
        ["python3", "-c", script, joined], 30, merge_errors=False
    )
    if result.status != 0:
        raise Error(result.errors)
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    var output = result.output
    for index in range(len(names)):
        var name = names[index]
        var raw_mark = "\n---RAW " + name + "\n"
        var ren_mark = "\n---REN " + name + "\n"
        var raw_at = output.find(raw_mark)
        var ren_at = output.find(ren_mark)
        if raw_at < 0 or ren_at < 0:
            raise Error("missing python function " + name)
        var raw_body = String(
            output[byte = raw_at + raw_mark.byte_length() : ren_at]
        )
        var next = output.byte_length()
        if index + 1 < len(names):
            var next_mark = "\n---RAW " + names[index + 1] + "\n"
            var next_at = output.find(next_mark)
            if next_at >= 0:
                next = next_at
        var renamed = String(
            output[byte = ren_at + ren_mark.byte_length() : next]
        )
        var extracted = String("")
        var in_bounds = False
        try:
            extracted = extract_sampled_function(trig, name)
        except:
            in_bounds = True
        if in_bounds:
            extracted = extract_sampled_function(bounds, name)
        assert_equal(extracted, raw_body)
        assert_equal(rename_sampled_identifiers(extracted), renamed)


def test_statement_roles_match_the_reviewed_shape() raises:
    """Top-level roles keep the Python statement classes and tests."""
    var plain = "def demo():\n    return 1\n"
    assert_equal(body_role_json(plain), '["return"]')
    var mixed = (
        "def demo[capture: Bool](flag: Bool = False):\n"
        "    ref lanes = road\n"
        "    comptime if capture:\n"
        "        return 1\n"
        "    var reused: Int = 0\n"
        "    if proof and not ready():\n"
        "        while flag:\n"
        "            continue\n"
        "    return lanes\n"
    )
    assert_equal(
        body_role_json(mixed),
        (
            '["assign:lanes","if:capture","annotate:reused","if:proof and (not'
            ' ready())","return"]'
        ),
    )


def test_a_body_statement_dump_matches_cpython_shape() raises:
    """Indexed body dumps keep the stored constructor and a returned tuple."""
    var source = (
        "def demo():\n"
        "    zero = _Interval.point(0.0)\n"
        "    comptime if capture:\n"
        "        captured.low = low\n"
        "    return (A(0), A(1))\n"
    )
    assert_equal(
        body_statement_json(source, 0),
        statement_dump("zero = _Interval.point(0.0)"),
    )
    assert_equal(
        body_statement_json(source, 1),
        statement_dump("if capture:\n    captured.low = low\n"),
    )
    var first = expression_dump("A(0)")
    var second = expression_dump("A(1)")
    var doc = PyJson()
    var rows = doc.new_list()
    doc.append(rows, doc.new_str(first))
    doc.append(rows, doc.new_str(second))
    doc.root = rows
    assert_equal(return_elements_json(source, 2), doc.dumps())
    assert_equal(return_elements_json("def demo():\n    return 1\n", 0), "null")


def test_top_level_helpers_reject_an_extra_name_or_statement() raises:
    """Helper names are a set, and only imports, functions, and strings pass."""
    var source = (
        '"""doc"""\nfrom a import b\n@decorator\ndef one():\n    return 1\n'
        "def two():\n    return 2\n"
    )
    sampled_top_level(source, "two,one")
    with assert_raises(contains="missing or extra sampled helper"):
        sampled_top_level(source, "one")
    with assert_raises(contains="missing or extra sampled helper"):
        sampled_top_level(
            source + "def three():\n    x = 1\n",
            "one,two",
        )
    with assert_raises(
        contains="unexpected top-level execution in sampled graph"
    ):
        sampled_top_level(source + "x = 1\n", "one,two")
    var live = Path("extensions/carla/lane_value_bounds.mojo").read_text()
    sampled_top_level(
        live,
        (
            "_arc_offset_value,_atan2_value,_atan_value,_atan_value_branch,"
            "_constant_sincos_value,_lane_value_bound,_lane_value_bound_impl,"
            "_polynomial_value,_reference_sampled_value,_sample_blend_value,"
            "_sample_value,_sampled_lane_value_bound,_sinc_value,"
            "_uncertain_value,_union_value_points,_unknown_value_point,"
            "_value_geometry_distance"
        ),
    )


def test_constant_heading_projection_uses_unknown_intervals() raises:
    """The zero constructor and its four field names become unknown."""
    var source = (
        "def _constant_sincos_value(heading: Float64):\n"
        "    # zero stays in this comment\n"
        "    var result = _sincos_expression(_ValueJet.constant(heading))\n"
        "    var zero = _Interval.point(0.0)\n"
        "    return (\n"
        "        _ValueJet(result[0].rounded_value(), zero, zero, 0.0),\n"
        "        _ValueJet(result[1].rounded_value(), zero, zero, 0.0),\n"
        "    )\n"
    )
    var projected = project_constant_heading(source)
    if projected.find("whole") < 0:
        raise Error("unknown constructor missing")
    if projected.find("point") >= 0:
        raise Error("zero constructor remained")
    if projected.find("unknown") < 0:
        raise Error("unknown interval missing")
    with assert_raises(
        contains="constant heading derivative constructor changed"
    ):
        _ = project_constant_heading("def demo():\n    return 1\n")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
