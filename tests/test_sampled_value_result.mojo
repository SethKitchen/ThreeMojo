# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled-value result keeps historical field order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._sampled_value_result import (
    sampled_result_from_frame,
    sampled_value_result,
)
from tools._sha256 import sha256_hex

comptime SCOPE = (
    "Current typed/conditioned source admission; historical "
    + "sampled/ARC/LINE correspondence and SPIRAL bridge with "
    + "stored-arithmetic closure; source binding is not "
    + "mathematical/runtime qualification. Separate "
    + "eligibility/translation/support source gate, "
    + "native/codegen/budget/coverage/performance remain required"
)


def _result(body: String) -> String:
    """Join the fixed prefix, one copied body, and the scope.

    Args:
        body: The copied fields, already in JSON, with a trailing comma.

    Returns:
        The full result text.
    """
    return '{"status":"PASS",' + body + '"scope":"' + SCOPE + '"}'


def test_the_sampled_value_result_keeps_field_order() raises:
    """Counts, digests, and edges stay in the historical order."""
    assert_equal(
        sampled_value_result(
            '{"root":"say \\"hi\\"","shared":14,"modules":3,'
            + '"primitive":"abc","sources":{"curve_bounds.mojo":"aa",'
            + '"curve_trig.mojo":"bb"},"successors":{"ok":true,"no":false,'
            + '"z":null,"items":[1,null],"empty":[],"n":1.5}}'
        ),
        _result(
            '"repo_root":"say \\"hi\\"","copied_functions":8,'
            + '"dispatch_functions":6,"additional_source_pairs":3,'
            + '"shared_generic_and_bridge_functions":14,'
            + '"complete_reference_modules":3,'
            + '"primitive_graph_sha256":"abc","source_sha256":'
            + '{"curve_bounds.mojo":"aa","curve_trig.mojo":"bb"},'
            + '"typed_boundary_successors":{"ok":true,"no":false,"z":null,'
            + '"items":[1,null],"empty":[],"n":1.5},'
        ),
    )
    assert_equal(
        sampled_value_result(
            '{"root":"","shared":0,"modules":0,"primitive":"",'
            + '"sources":{},"successors":null}'
        ),
        _result(
            '"repo_root":"","copied_functions":8,"dispatch_functions":6,'
            + '"additional_source_pairs":3,'
            + '"shared_generic_and_bridge_functions":0,'
            + '"complete_reference_modules":0,"primitive_graph_sha256":"",'
            + '"source_sha256":{},"typed_boundary_successors":null,'
        ),
    )


def test_a_sampled_value_field_must_keep_its_type() raises:
    """A wrong JSON type is refused before the result is built."""
    with assert_raises(contains="sampled repository root changed"):
        _ = sampled_value_result('{"root":1}')
    with assert_raises(contains="sampled shared function count changed"):
        _ = sampled_value_result('{"root":"r","shared":true}')
    with assert_raises(contains="sampled shared function count changed"):
        _ = sampled_value_result('{"root":"r","shared":14.0}')
    with assert_raises(contains="sampled reference module count changed"):
        _ = sampled_value_result('{"root":"r","shared":1,"modules":"3"}')
    with assert_raises(contains="sampled primitive digest changed"):
        _ = sampled_value_result(
            '{"root":"r","shared":1,"modules":2,"primitive":1}'
        )
    with assert_raises(contains="sampled source digest changed"):
        _ = sampled_value_result(
            '{"root":"r","shared":1,"modules":2,"primitive":"p","sources":[]}'
        )
    with assert_raises(contains="KeyError: 'successors'"):
        _ = sampled_value_result(
            '{"root":"r","shared":1,"modules":2,"primitive":"p","sources":{}}'
        )


def test_a_short_frame_fails_before_the_result() raises:
    """Too few framed payloads fail before the result is built."""
    with assert_raises(contains="sampled source frame changed"):
        _ = sampled_result_from_frame(
            String("").as_bytes(),
            '{"root":"r","shared":1,"modules":1,"primitive":"p","names":["a"],'
            + '"successors":{}}',
        )


def test_one_framed_source_keeps_its_digest() raises:
    """One framed payload becomes the first source digest."""
    var digest = sha256_hex(String("ab").as_bytes())
    var result = sampled_result_from_frame(
        String("2\nab").as_bytes(),
        '{"root":"r","shared":1,"modules":1,"primitive":"p","names":["a.mojo"],'
        + '"successors":{}}',
    )
    assert_equal(result.find('"status":"PASS"') >= 0, True)
    assert_equal(result.find(digest) >= 0, True)
    assert_equal(result.find('"a.mojo"') >= 0, True)


def main() raises:
    """Run the sampled-value result tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
