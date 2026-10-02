# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exercise production trait defaults through their concrete consumers."""

from materials.nodes import (
    AT_FRAGMENT,
    AT_RIGHT,
    AT_UP,
    COLOR_NODE,
    NodeGraph,
    NodeInputs,
    ProgramSource,
    run_nodes,
)
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from std.testing import TestSuite, assert_equal, assert_false

comptime Lanes = SIMD[DType.float32, 4]


def assert_white(color: FloatColor) raises:
    """Check all four channels of an inherited texture fallback."""
    assert_equal(color.r, 1.0)
    assert_equal(color.g, 1.0)
    assert_equal(color.b, 1.0)
    assert_equal(color.a, 1.0)


def test_program_source_inherits_all_node_source_defaults() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.vec3(0, 0, 0))
    var program = graph.compile()
    var source = ProgramSource(Pointer(to=program))
    assert_equal(source.screen_size(), Lanes(1, 1, 0, 0))
    for context in [AT_FRAGMENT, AT_RIGHT, AT_UP]:
        assert_equal(source.point_coord(context), Lanes(0))
    assert_false(source.seen_from_behind())
    assert_false(source.flip_sided())
    for index in [-1, 0, 7]:
        assert_white(source.behind(Float32(index), -0.5))
        assert_white(source.sample_cube(index, Vector3(1, -2, 3)))
        assert_white(source.sample_3d(index, Vector3(0.1, 0.5, 0.9)))
        assert_white(source.sample_array(index, Vector3(0.2, 0.7, 2)))
        assert_equal(source.compute_builtin(index), Float32(0))
        assert_equal(source.storage_element(index, 3.5), Lanes(0))
        assert_equal(source.statement_result(index), Lanes(0))


def test_node_interpreter_uses_inherited_pixel_and_facing_defaults() raises:
    var graph = NodeGraph()
    var pixel = graph.screen_uv()
    var point = graph.point_coord()
    var face = graph.front_facing()
    var output = graph.add(graph.add(pixel, point), face)
    graph.set_output(COLOR_NODE, graph.swizzle(output, "xyx"))
    var program = graph.compile()
    var zero = Vector3(0, 0, 0)
    var inputs = NodeInputs(0, 0, zero, zero, zero, zero, False)
    var got = run_nodes(ProgramSource(Pointer(to=program)), COLOR_NODE, inputs)
    assert_equal(got, Lanes(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
