# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The optional-runtime result keeps the new module names in order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._optional_runtime_result import _dump, optional_runtime_result
from tools._python_json import PyJson


def test_the_optional_runtime_result_keeps_module_order() raises:
    """The module list is copied ahead of the fixed scope sentences."""
    assert_equal(
        optional_runtime_result(
            '{"new_modules":["curve_minimizer_support",'
            + '"curve_objective_model"]}'
        ),
        '{"status":"PASS","new_modules":["curve_minimizer_support",'
        + '"curve_objective_model"],"checked_error_edge":'
        + '"guarded raw -> grouped origin -> checked Sum2 leaf",'
        + '"containing_model_consumers":'
        + '"absent from production; standalone helper retained",'
        + '"fresh_cell_producer":'
        + '"original debit immediately precedes current-cell producer",'
        + '"qualification":"source preconditions and dependency integrity'
        ' only",'
        + '"native_execution_qualified":false}',
    )
    assert_equal(
        optional_runtime_result('{"new_modules":[]}'),
        '{"status":"PASS","new_modules":[],"checked_error_edge":'
        + '"guarded raw -> grouped origin -> checked Sum2 leaf",'
        + '"containing_model_consumers":'
        + '"absent from production; standalone helper retained",'
        + '"fresh_cell_producer":'
        + '"original debit immediately precedes current-cell producer",'
        + '"qualification":"source preconditions and dependency integrity'
        ' only",'
        + '"native_execution_qualified":false}',
    )


def test_a_module_list_must_be_a_list() raises:
    """A string of names is not the module tuple."""
    with assert_raises(contains="optional runtime module list changed"):
        _ = optional_runtime_result('{"new_modules":"curve_objective_model"}')


def test_json_text_keeps_true_false_and_null() raises:
    """True, false, null, and a number use Python's JSON spellings."""
    var doc = PyJson.parse('{"ok":true,"no":false,"z":null,"n":1}')
    assert_equal(_dump(doc, doc.root), '{"ok":true,"no":false,"z":null,"n":1}')


def main() raises:
    """Run the optional-runtime result tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
