# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The runtime-support result keeps the check records in order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._runtime_support_result import runtime_support_result


def test_the_runtime_support_result_keeps_historical_order() raises:
    """Fixed scope text stays ahead of the copied check records."""
    var payload = String(
        '{"root":"/tmp/repo","groups":{"stored_arithmetic":{"ok":true}},'
        + '"successors":["extensions/carla/map.mojo"],'
        + '"heading":{"heading_consumers":3},'
        + '"optional":{"status":"PASS","room":false},'
        + '"sum2":{"status":"PASS","guard":null}}'
    )
    assert_equal(
        runtime_support_result(payload),
        '{"status":"PASS","scope":"Current source-integrity and explicit'
        + " typed/conditioned successors; old source comparisons retain"
        + " historical provenance only. Native execution, performance and"
        + ' coverage are separate requirements","repo_root":"/tmp/repo",'
        + '"groups":{"stored_arithmetic":{"ok":true}},'
        + '"typed_boundary_successors":["extensions/carla/map.mojo"],'
        + '"heading_correspondence":{"heading_consumers":3},'
        + '"optional_runtime":{"status":"PASS","room":false},'
        + '"sum2_correspondence":{"status":"PASS","guard":null}}',
    )


def test_a_missing_runtime_record_is_a_key_error() raises:
    """The result is not built without the Sum2 record."""
    with assert_raises(contains="KeyError: 'sum2'"):
        _ = runtime_support_result(
            '{"root":"/tmp/repo","groups":{},"successors":[],"heading":{},'
            + '"optional":{}}'
        )


def main() raises:
    """Run the runtime-support result tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
