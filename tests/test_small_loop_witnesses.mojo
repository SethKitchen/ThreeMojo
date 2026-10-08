# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Real supported producers for the small source-bound loop proposals."""
from extensions.carla.rtree import (
    SegmentCloudRtree,
    SegmentElement,
    SegmentFilter,
)
from extensions.carla.map_search import _MapQueryWork, MapQueryBudget
from math.vector3 import Vector3
from objects.line_segments2 import cap_steps
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)
from tests.test_hair_renderer_boundaries import (
    test_valid_solid_and_strand_modes_emit_visible_red_samples,
)
from coverage.report import Hits, parse_manifest, build_report
from coverage.mcdc import DecisionTrace


@fieldwise_init
struct _AcceptEverySegment(ImplicitlyCopyable, SegmentFilter):
    def accepts(self, element: SegmentElement) -> Bool:
        return True


def test_empty_and_split_tree_frontiers_use_real_producers() raises:
    for count in [0, 1, 17, 257]:
        var tree = SegmentCloudRtree()
        for i in range(count):
            tree.insert_element(
                Vector3(Float32(i), 0, 0), Vector3(Float32(i), 1, 0), i, i
            )
        var point = Vector3(0, 0, 0)
        var work = _MapQueryWork(MapQueryBudget())
        var frontier = tree._nearest_begin(point, work)
        assert_equal(len(frontier.items), Int(count > 0))
        var found = 0
        while True:
            var next = tree._nearest_next(
                point, _AcceptEverySegment(), frontier, work
            )
            if not next:
                break
            assert_equal(next.value().start_value, found)
            found += 1
        assert_equal(found, count)
        assert_false(
            Bool(
                tree._nearest_next(point, _AcceptEverySegment(), frontier, work)
            )
        )
        if count > 0:
            for node in tree._tree.nodes:
                assert_true(len(node.children) > 0)
                assert_true(len(node.children) <= 16)


def test_cap_count_all_special_classes_and_public_strand_render() raises:
    for radius in [
        Float32(-1),
        Float32(0),
        Float32(1),
        Float32(1e30),
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
        bitcast[DType.float32](UInt32(0x7F800001)),
        bitcast[DType.float32](UInt32(0xFF800001)),
    ]:
        var count = cap_steps(radius)
        assert_true(count >= 2 and count <= 64)
    test_valid_solid_and_strand_modes_emit_visible_red_samples()


def test_iterator_protocol_keeps_true_and_rejects_contrary_false() raises:
    # Synthetic protocol records exercise reporting only, never production hits.
    var header = String(
        "P constant-loops-v2"
        " 0000000000000000000000000000000000000000000000000000000000000000\n"
    )
    var entries = parse_manifest(
        header + "R iterator 1 T reviewed-nonempty-iterator 1\n"
    )
    var hits = Hits()
    var missing = build_report(entries, hits, List[DecisionTrace]())
    assert_false(missing.is_complete())
    assert_equal(missing.total, 1)
    assert_equal(missing.potential, 2)
    hits.add("iterator:1:T")
    var reached = build_report(entries, hits, List[DecisionTrace]())
    assert_true(reached.is_complete())
    assert_true(
        reached.text.find("reviewed-nonempty-iterator minimum cardinality 1")
        >= 0
    )
    hits.add("iterator:1:F")
    with assert_raises(contains="proof contradicted"):
        _ = build_report(entries, hits, List[DecisionTrace]())
    for record in [
        "R iterator 1 F reviewed-nonempty-iterator 0\n",
        "R iterator 1 T reviewed-nonempty-iterator 2\n",
        "R iterator 1 T reviewed-nonempty-iterator -1\n",
        "R iterator 1 T reviewed-unknown-iterator 1\n",
    ]:
        with assert_raises(contains="Malformed"):
            _ = parse_manifest(header + record)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
