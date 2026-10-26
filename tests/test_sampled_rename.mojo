# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Sampled identifier renaming matches the Python checker."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._process import run_program
from tools._sampled_value_gate import (
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
