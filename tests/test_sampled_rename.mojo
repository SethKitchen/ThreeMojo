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


def test_a_real_trig_function_matches_python() raises:
    var script = (
        "import sys\n"
        "sys.path.insert(0, 'tools/carla_lane_oracle')\n"
        "import check_sampled_values as checker\n"
        "text = open('extensions/carla/curve_trig.mojo').read()\n"
        "body = checker.function(text, '_atan_jet')\n"
        "sys.stdout.write(checker.translated(body))\n"
    )
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    var text = Path("extensions/carla/curve_trig.mojo").read_text()
    var body = extract_sampled_function(text, "_atan_jet")
    assert_equal(rename_sampled_identifiers(body), result.output)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
