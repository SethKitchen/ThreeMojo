# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Sampled identifier renaming matches the Python checker."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._process import run_program
from tests._python_tokens import (
    decorator_prefix,
    primitive_aliases,
    project_constant_heading,
    project_lane_value,
    project_reference_value,
    project_union_value,
    sampled_top_level,
    replace_function,
    strip_try_only_refusal,
)
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


def test_union_projection_keeps_the_return_body() raises:
    """The value-only signature replaces the generic header only."""
    var source = (
        "def _union_points[derivatives: Bool](\n"
        "    one: Tuple[_JetExpression[derivatives]],\n"
        ") -> Tuple[_Jet, _Jet, _Jet]:\n"
        "    return _uncertain(one)\n"
    )
    var projected = project_union_value(source)
    if projected.find("def _union_value_points(") < 0:
        raise Error("value signature missing")
    if projected.find("return _uncertain(one)") < 0:
        raise Error("return body missing")
    if projected.find("_JetExpression") >= 0:
        raise Error("generic header remained")
    with assert_raises(contains="union complete body shape changed"):
        _ = project_union_value(
            "def demo():\n    var one = 1\n    return one\n"
        )


def test_reference_projection_drops_the_three_kind_branches() raises:
    """The line, arc, and spiral branches are removed from the dispatcher."""
    var source = String("def old[capture: Bool](geometry: RoadGeometry):\n")
    source += "    return marker_00\n"
    source += "    if marker_01:\n        return 1\n"
    source += "    if marker_02:\n        return 1\n"
    source += "    if marker_03:\n        return 1\n"
    var index = 4
    while index < 12:
        source += "    return marker_" + String(index) + "\n"
        index += 1
    var projected = project_reference_value(source)
    if projected.find("def _reference_sampled_value(") < 0:
        raise Error("sampled signature missing")
    if projected.find("geometry.kind != POLY3") < 0:
        raise Error("kind guard missing")
    if (
        projected.find("return marker_00") < 0
        or projected.find("return marker_4") < 0
    ):
        raise Error("sampled tail missing")
    if projected.find("marker_01") >= 0 or projected.find("marker_03") >= 0:
        raise Error("kind branch remained")
    with assert_raises(contains="complete reference dispatcher layout changed"):
        _ = project_reference_value("def demo():\n    return 1\n")


def test_lane_projection_wraps_the_arc_and_line_branches() raises:
    """The proof refusal and capture branch are removed."""
    var source = String("def old[capture: Bool](road: Road):\n")
    var index = 0
    while index < 24:
        var label = String(index)
        if index < 10:
            label = "0" + label
        if index == 16 or index == 17:
            source += "    if marker_" + label + ":\n        return 1\n"
        else:
            source += "    return marker_" + label + "\n"
        index += 1
    var projected = project_lane_value(source)
    if projected.find("def _lane_value_bound_impl[") < 0:
        raise Error("lane signature missing")
    if projected.find("if all_geometry:") < 0:
        raise Error("geometry guard missing")
    if projected.find("_reference_sampled_value") < 0:
        raise Error("sampled call missing")
    if (
        projected.find("marker_01") < 0
        or projected.find("marker_16") < 0
        or projected.find("marker_22") < 0
    ):
        raise Error("kept lane statement missing")
    if (
        projected.find("marker_00") >= 0
        or projected.find("marker_15") >= 0
        or projected.find("marker_18") >= 0
    ):
        raise Error("removed lane statement remained")
    with assert_raises(contains="complete lane dispatcher layout changed"):
        _ = project_lane_value("def demo():\n    return 1\n")


def test_decorator_lines_stay_above_their_function() raises:
    """Only the decorators immediately above the named function are kept."""
    var source = (
        "@no_inline\ndef _atan_branch():\n    return 1\ndef other():\n   "
        " return 2\n"
    )
    assert_equal(decorator_prefix(source, "_atan_branch"), "@no_inline\n")
    assert_equal(decorator_prefix(source, "other"), "")
    assert_equal(
        decorator_prefix("@a\n@b(1)\ndef f():\n    return 1\n", "f"),
        "@a\n@b(1)\n",
    )
    with assert_raises(contains="missing or ambiguous function"):
        _ = decorator_prefix(source, "absent")


def test_try_only_refusal_is_removed_from_the_proof() raises:
    """The reuse parameter and its elif branch are deleted together."""
    var source = (
        "def _lane_jet_model_proof(\n"
        "    ideal_translation: Bool = False,\n"
        "    require_reuse: Bool = False,\n"
        "):\n"
        "    if reused:\n"
        "        point = reused.value()\n"
        "    elif require_reuse:\n"
        "        return _unknown_point()\n"
        "    else:\n"
        "        point = fallback()\n"
    )
    var projected = strip_try_only_refusal(source)
    if projected.find("require_reuse") >= 0:
        raise Error("try-only parameter remained")
    if projected.find("fallback()") < 0 or projected.find("if reused:") < 0:
        raise Error("fallback branch missing")
    with assert_raises(contains="try-only refusal changed"):
        _ = strip_try_only_refusal(
            "def _lane_jet_model_proof():\n    return 1\n"
        )


def test_one_function_is_replaced_without_moving_its_neighbors() raises:
    """A historical helper replaces one function and leaves the others."""
    var source = (
        "def keep():\n    return 1\n"
        "@old\n"
        "def _try_lane_envelope_capture():\n    return old\n"
        "def after():\n    return 2\n"
    )
    var projected = replace_function(
        source,
        "_try_lane_envelope_capture",
        "def _try_lane_envelope_capture():\n    return historical\n",
    )
    if projected.find("return historical") < 0:
        raise Error("historical helper missing")
    if projected.find("return old") >= 0 or projected.find("@old") >= 0:
        raise Error("old helper remained")
    if projected.find("def keep()") < 0 or projected.find("def after()") < 0:
        raise Error("neighbor function missing")
    with assert_raises(contains="missing or ambiguous function"):
        _ = replace_function(source, "absent", "def absent():\n    return 1\n")


def test_derivative_aliases_keep_their_reviewed_values() raises:
    """The Jet alias is true and the value alias is false."""
    var source = (
        "comptime _Jet = _JetExpression[True]\n"
        "comptime _ValueJet = _JetExpression[False]\n"
    )
    primitive_aliases(source)
    with assert_raises(contains="actual derivative alias changed: _Jet"):
        primitive_aliases(
            "comptime _Jet = _JetExpression[False]\n"
            "comptime _ValueJet = _JetExpression[False]\n"
        )
    with assert_raises(contains="missing or ambiguous actual alias: _Jet"):
        primitive_aliases("comptime _ValueJet = _JetExpression[False]\n")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
