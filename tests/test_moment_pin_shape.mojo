# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The stored-moment pin shape stays checked."""

from std.testing import TestSuite, assert_raises

from tools._moment_pin_shape import (
    require_legacy_digest,
    require_moment_pin_shape,
    require_projection_result,
)


def _pins() -> String:
    """Return one valid tiny pin document and its specification.

    Returns:
        JSON with `pins` and `spec`.
    """
    return (
        '{"pins":{"schema":3,"scope":"stored","arrays":{"_GL_NODES":{"path":'
        + '"extensions/carla/geometry.mojo","words":["0x0"]}},"scalars":'
        + '{"_PHASE_LIMIT":{"path":"extensions/carla/curve_trig.mojo","word":'
        + '"0x0"}},"blocks":{"ideal_spiral":{"path":'
        + '"extensions/carla/curve_bounds.mojo","begin":"def a","end":"def b",'
        + '"normalized_source":"def a","sha256":"aa"}},"rounded_node_sums":'
        + '["0x0"],"ideal_projection":{"legacy_normalized_source":"def",'
        + '"legacy_sha256":"aa","helper_projections":5,'
        + '"rate_half_commutations":2,"projected_ast_sha256":"bb",'
        + '"sum2_auxiliary_declarations":4,"sum2_term_definitions":2,'
        + '"sum2_auxiliary_updates":4,"sum2_error_writes":2,'
        + '"sum2_environment_guards":1},"routing":{"ideal_caller":{"path":'
        + '"extensions/carla/curve_bounds.mojo","normalized_tokens":"[]",'
        + '"sha256":"cc"}},"dependencies":{"group":"stored_arithmetic"}},'
        + '"spec":{"arrays":{"_GL_NODES":{"path":'
        + '"extensions/carla/geometry.mojo","size":1}},"scalars":'
        + '{"_PHASE_LIMIT":1},"scalar_path":"extensions/carla/curve_trig.mojo",'
        + '"block_paths":{"ideal_spiral":"extensions/carla/curve_bounds.mojo"},'
        + '"boundaries":{"ideal_spiral":{"begin":"def a","end":"def b"}},'
        + '"routing_paths":{"ideal_caller":'
        + '"extensions/carla/curve_bounds.mojo"},"dependencies":{"group":'
        + '"stored_arithmetic"}}}'
    )


def test_the_moment_pin_shape_holds() raises:
    """A matching pin document is accepted."""
    require_moment_pin_shape(_pins())


def test_a_changed_moment_pin_shape_is_refused() raises:
    """Each pin-shape failure keeps its message."""
    with assert_raises(contains="wrong top-level pin set"):
        require_moment_pin_shape(
            _pins().replace('{"pins":{', '{"pins":{"unexpected":1,')
        )
    with assert_raises(contains="wrong top-level pin set"):
        require_moment_pin_shape(
            _pins().replace('"scope":"stored"', '"extra":"stored"')
        )
    with assert_raises(contains="unsupported pin schema"):
        require_moment_pin_shape(_pins().replace('"schema":3', '"schema":"3"'))
    with assert_raises(contains="unsupported pin schema"):
        require_moment_pin_shape(_pins().replace('"schema":3', '"schema":4'))
    with assert_raises(contains="wrong constant-array pin set"):
        require_moment_pin_shape(
            _pins().replace(
                '"arrays":{"_GL_NODES":{"path":"extensions/carla/geometry.mojo","words"',
                '"arrays":{"_GL_OTHER":{"path":"extensions/carla/geometry.mojo","words"',
            )
        )
    with assert_raises(contains="wrong scalar pin set"):
        require_moment_pin_shape(
            _pins().replace(
                '"scalars":{"_PHASE_LIMIT":{"path"',
                '"scalars":{"_OTHER_LIMIT":{"path"',
            )
        )
    with assert_raises(contains="wrong operation-graph pin set"):
        require_moment_pin_shape(
            _pins().replace(
                '"blocks":{"ideal_spiral"', '"blocks":{"other_spiral"'
            )
        )
    with assert_raises(contains="wrong routing pin set"):
        require_moment_pin_shape(
            _pins().replace(
                '"routing":{"ideal_caller"', '"routing":{"other_caller"'
            )
        )
    with assert_raises(contains="wrong dependency closure pin"):
        require_moment_pin_shape(
            _pins().replace(
                '"group":"stored_arithmetic"}},"spec"',
                '"group":"eligibility"}},"spec"',
            )
        )
    with assert_raises(contains="wrong array pin keys: _GL_NODES"):
        require_moment_pin_shape(
            _pins().replace('"words":["0x0"]', '"words":["0x0"],"extra":1')
        )
    with assert_raises(contains="wrong array pin path/shape: _GL_NODES"):
        require_moment_pin_shape(
            _pins().replace(
                '"extensions/carla/geometry.mojo","words"',
                '"other.mojo","words"',
            )
        )
    with assert_raises(contains="wrong array pin path/shape: _GL_NODES"):
        require_moment_pin_shape(
            _pins().replace('"words":["0x0"]', '"words":"0x0"')
        )
    with assert_raises(contains="wrong array pin path/shape: _GL_NODES"):
        require_moment_pin_shape(
            _pins().replace('"words":["0x0"]', '"words":["0x0","0x1"]')
        )
    with assert_raises(contains="wrong scalar pin keys: _PHASE_LIMIT"):
        require_moment_pin_shape(
            _pins().replace('"word":"0x0"', '"word":"0x0","extra":1')
        )
    with assert_raises(contains="wrong scalar pin path: _PHASE_LIMIT"):
        require_moment_pin_shape(
            _pins().replace(
                '"extensions/carla/curve_trig.mojo","word"',
                '"other.mojo","word"',
            )
        )
    with assert_raises(contains="wrong operation pin keys: ideal_spiral"):
        require_moment_pin_shape(
            _pins().replace('"sha256":"aa"', '"sha256":"aa","extra":1')
        )
    with assert_raises(
        contains="wrong source-block boundary pin: ideal_spiral"
    ):
        require_moment_pin_shape(
            _pins().replace(
                '"begin":"def a","end":"def b","normalized_source"',
                '"begin":"def z","end":"def b","normalized_source"',
            )
        )
    with assert_raises(
        contains="wrong source-block boundary pin: ideal_spiral"
    ):
        require_moment_pin_shape(
            _pins().replace(
                '"end":"def b","normalized_source"',
                '"end":"def z","normalized_source"',
            )
        )
    with assert_raises(contains="wrong operation pin path: ideal_spiral"):
        require_moment_pin_shape(
            _pins().replace(
                '"blocks":{"ideal_spiral":{"path":"extensions/carla/curve_bounds.mojo"',
                '"blocks":{"ideal_spiral":{"path":"other.mojo"',
            )
        )
    with assert_raises(contains="wrong routing pin keys: ideal_caller"):
        require_moment_pin_shape(
            _pins().replace('"sha256":"cc"', '"sha256":"cc","extra":1')
        )
    with assert_raises(contains="wrong routing pin path: ideal_caller"):
        require_moment_pin_shape(
            _pins().replace(
                '"routing":{"ideal_caller":{"path":"extensions/carla/curve_bounds.mojo"',
                '"routing":{"ideal_caller":{"path":"other.mojo"',
            )
        )
    with assert_raises(contains="wrong ideal-projection pin set"):
        require_moment_pin_shape(
            _pins().replace(
                '"sum2_environment_guards":1',
                '"sum2_environment_guards":1,"extra":1',
            )
        )


def test_the_projection_result_pins_hold() raises:
    """A matching legacy digest and result pin set is accepted."""
    require_legacy_digest('{"actual":"aa","expected":"aa"}')
    require_projection_result(
        '{"projection":{"helper_projections":5,"projected_ast_sha256":"bb"},'
        + '"result":{"projected_ast_sha256":"bb","helper_projections":5}}'
    )


def test_a_changed_projection_result_pin_is_refused() raises:
    """A changed digest or result pin keeps its message."""
    with assert_raises(contains="historical ideal pin digest changed"):
        require_legacy_digest('{"actual":"aa","expected":"bb"}')
    with assert_raises(contains="historical ideal pin digest changed"):
        require_legacy_digest('{"actual":5,"expected":"bb"}')
    with assert_raises(contains="wrong ideal-projection result pins"):
        require_projection_result(
            '{"projection":{"helper_projections":4},"result":{"helper_projections":5}}'
        )
    with assert_raises(contains="wrong ideal-projection result pins"):
        require_projection_result(
            '{"projection":{"helper_projections":5},"result":{"helper_projections":5,"extra":1}}'
        )


def main() raises:
    """Run the moment pin-shape tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
