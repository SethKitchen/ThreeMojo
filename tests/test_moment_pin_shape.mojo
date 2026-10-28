# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The stored-moment pin shape stays checked."""

from std.testing import TestSuite, assert_raises

from tools._python_json import PyJson
from tools._moment_pin_shape import (
    moment_pins_after_spec,
    require_legacy_digest,
    require_moment_pin_shape,
    require_projection_result,
)
from tools._moment_pin_spec import moment_pin_spec


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


def _matching_pins(spec_text: String) raises -> String:
    """Return pin JSON that matches one specification.

    Args:
        spec_text: The specification JSON.

    Returns:
        A pin document whose sets, paths, and sizes match `spec_text`.
    """
    var spec = PyJson.parse(spec_text)
    var doc = PyJson()
    var pins = doc.new_dict()
    doc.set(pins, "schema", doc.new_int(3))
    doc.set(pins, "scope", doc.new_str("stored"))
    var arrays = doc.new_dict()
    var array_spec = spec.at(spec.root, "arrays")
    var count = spec.length(array_spec)
    var index = 0
    while index < count:
        var name = spec.key(array_spec, index)
        var wanted = spec.value(array_spec, index)
        var record = doc.new_dict()
        doc.set(record, "path", doc.new_str(spec.text(spec.at(wanted, "path"))))
        var words = doc.new_list()
        var size = Int(spec.text(spec.at(wanted, "size")))
        var word = 0
        while word < size:
            doc.append(words, doc.new_str("0x0"))
            word += 1
        doc.set(record, "words", words)
        doc.set(arrays, name, record)
        index += 1
    doc.set(pins, "arrays", arrays)
    var scalars = doc.new_dict()
    var scalar_spec = spec.at(spec.root, "scalars")
    var scalar_path = spec.text(spec.at(spec.root, "scalar_path"))
    count = spec.length(scalar_spec)
    index = 0
    while index < count:
        var scalar_name = spec.key(scalar_spec, index)
        var scalar_record = doc.new_dict()
        doc.set(scalar_record, "path", doc.new_str(scalar_path))
        doc.set(scalar_record, "word", doc.new_str("0x0"))
        doc.set(scalars, scalar_name, scalar_record)
        index += 1
    doc.set(pins, "scalars", scalars)
    var blocks = doc.new_dict()
    var block_paths = spec.at(spec.root, "block_paths")
    var boundaries = spec.at(spec.root, "boundaries")
    count = spec.length(block_paths)
    index = 0
    while index < count:
        var block_name = spec.key(block_paths, index)
        var boundary = spec.at(boundaries, block_name)
        var block_record = doc.new_dict()
        doc.set(
            block_record,
            "path",
            doc.new_str(spec.text(spec.value(block_paths, index))),
        )
        doc.set(
            block_record,
            "begin",
            doc.new_str(spec.text(spec.at(boundary, "begin"))),
        )
        doc.set(
            block_record,
            "end",
            doc.new_str(spec.text(spec.at(boundary, "end"))),
        )
        doc.set(block_record, "normalized_source", doc.new_str("def"))
        doc.set(block_record, "sha256", doc.new_str("aa"))
        doc.set(blocks, block_name, block_record)
        index += 1
    doc.set(pins, "blocks", blocks)
    var sums = doc.new_list()
    doc.append(sums, doc.new_str("0x0"))
    doc.set(pins, "rounded_node_sums", sums)
    var projection = doc.new_dict()
    doc.set(projection, "legacy_normalized_source", doc.new_str("def"))
    doc.set(projection, "legacy_sha256", doc.new_str("aa"))
    doc.set(projection, "helper_projections", doc.new_int(5))
    doc.set(projection, "rate_half_commutations", doc.new_int(2))
    doc.set(projection, "projected_ast_sha256", doc.new_str("bb"))
    doc.set(projection, "sum2_auxiliary_declarations", doc.new_int(4))
    doc.set(projection, "sum2_term_definitions", doc.new_int(2))
    doc.set(projection, "sum2_auxiliary_updates", doc.new_int(4))
    doc.set(projection, "sum2_error_writes", doc.new_int(2))
    doc.set(projection, "sum2_environment_guards", doc.new_int(1))
    doc.set(pins, "ideal_projection", projection)
    var routing = doc.new_dict()
    var routing_paths = spec.at(spec.root, "routing_paths")
    count = spec.length(routing_paths)
    index = 0
    while index < count:
        var route_name = spec.key(routing_paths, index)
        var route_record = doc.new_dict()
        doc.set(
            route_record,
            "path",
            doc.new_str(spec.text(spec.value(routing_paths, index))),
        )
        doc.set(route_record, "normalized_tokens", doc.new_str("[]"))
        doc.set(route_record, "sha256", doc.new_str("cc"))
        doc.set(routing, route_name, route_record)
        index += 1
    doc.set(pins, "routing", routing)
    doc.root = pins
    var body = doc.dumps()
    var end = body.byte_length() - 1
    var prefix = body[byte=0:end]
    var dependencies = spec.subtree(spec.at(spec.root, "dependencies")).dumps()
    return String(prefix) + ',"dependencies":' + dependencies + "}"


def test_a_bad_dependency_record_fails_before_the_pins() raises:
    """A bad dependency record fails before the pin document is checked."""
    with assert_raises(contains="KeyError: 'dependencies'"):
        moment_pins_after_spec('{"pins":{}}')
    with assert_raises(contains="moment pin dependencies changed"):
        moment_pins_after_spec('{"dependencies":[],"pins":{}}')


def test_a_bad_pin_shape_fails_after_the_specification() raises:
    """A bad pin document fails after the specification is built."""
    with assert_raises(contains="wrong top-level pin set"):
        moment_pins_after_spec(
            '{"dependencies":{"group":"stored_arithmetic"},"pins":{}}'
        )


def test_a_matching_specification_accepts_the_pins() raises:
    """Pins that match the built specification are accepted."""
    var dependencies = '{"group":"stored_arithmetic"}'
    var spec = moment_pin_spec('{"dependencies":' + dependencies + "}")
    var pins = _matching_pins(spec)
    moment_pins_after_spec(
        '{"dependencies":' + dependencies + ',"pins":' + pins + "}"
    )


def main() raises:
    """Run the moment pin-shape tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
