# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed speed and rtree loop proofs keep their sources."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._map_score_predecessor import (
    count_endpoint,
    frontier_endpoint,
    historical_map,
    optional_endpoint,
    restored_deviation_map,
    score_endpoint,
    station_endpoint,
    support_endpoint,
)
from tests._small_loop_proofs import (
    NEAREST_BEGIN,
    NEAREST_NEXT,
    RTREE,
    SPEED,
    rtree_loop_admitted,
    speed_loop_admitted,
)


def _historical() raises -> String:
    """Return the historical Map used by the rtree frontier proof.

    Returns:
        The historical Map source.

    Raises:
        Error: A Map endpoint changed.
    """
    var score = score_endpoint(station_endpoint(restored_deviation_map()))
    return historical_map(
        count_endpoint(
            optional_endpoint(support_endpoint(frontier_endpoint(score)))
        )
    )


def _replace_all(text: String, before: String, after: String) raises -> String:
    """Replace every `before` and require at least one.

    Args:
        text: The source.
        before: The premise text.
        after: The mutated text.

    Returns:
        The source with every premise replaced.

    Raises:
        Error: The premise is absent.
    """
    var out = String()
    var rest = text
    var found = False
    while True:
        var at = rest.find(before)
        if at < 0:
            if not found:
                raise Error("small loop premise missing")
            return out + rest
        found = True
        out += String(rest[byte=:at])
        out += after
        var tail = String(rest[byte = at + before.byte_length() :])
        rest = tail


def _rtree_inputs(
    map_text: String, mut paths: List[String], mut texts: List[String]
) raises:
    """Fill the four rtree proof sources.

    Args:
        map_text: The historical Map.
        paths: The proof paths, replaced by this call.
        texts: The proof sources, in the same order.

    Raises:
        Error: A live proof file cannot be read.
    """
    paths.clear()
    texts.clear()
    paths.append("extensions/carla/rtree.mojo")
    texts.append(Path("extensions/carla/rtree.mojo").read_text())
    paths.append("extensions/carla/map.mojo")
    texts.append(map_text)
    paths.append("tests/_published_seed_selector.mojo")
    texts.append(Path("tests/_published_seed_selector.mojo").read_text())
    paths.append("tests/test_small_loop_witnesses.mojo")
    texts.append(Path("tests/test_small_loop_witnesses.mojo").read_text())


def test_speed_and_rtree_loops_match_their_reviews() raises:
    """The speed file and the four frontier callers keep the reviewed proofs."""
    var speed = Path("extensions/carla/speed_limits.mojo").read_text()
    assert_true(speed_loop_admitted(speed))
    assert_false(speed_loop_admitted(speed + "\n"))
    var paths = List[String]()
    var texts = List[String]()
    _rtree_inputs(_historical(), paths, texts)
    assert_true(rtree_loop_admitted(paths, texts))
    assert_false(speed_loop_admitted("other"))
    var empty_paths = List[String]()
    var empty_texts = List[String]()
    assert_false(rtree_loop_admitted(empty_paths, empty_texts))
    _ = SPEED
    _ = RTREE


def test_a_changed_small_loop_source_is_refused() raises:
    """A premise edit, a missing file, or a new caller removes the proof."""
    var speed = Path("extensions/carla/speed_limits.mojo").read_text()
    var speed_edits = List[String]()
    speed_edits.append("if number.byte_length() == 0:")
    speed_edits.append("for byte in number.as_bytes():")
    speed_edits.append("var number = String(text.strip())")
    speed_edits.append("if not _speed_decimal_syntax(number):")
    speed_edits.append("if byte >= 48 and byte <= 57:")
    speed_edits.append("if byte == 101 or byte == 69:")
    speed_edits.append("if byte >= 49:")
    for edit in speed_edits:
        var changed = _replace_all(speed, edit, "False")
        assert_false(speed_loop_admitted(changed))
    var historical = _historical()
    var paths = List[String]()
    var texts = List[String]()
    _rtree_inputs(historical, paths, texts)
    var rtree_edits = List[String]()
    rtree_edits.append("if self.size() > 0:")
    rtree_edits.append("group_a.append(seed_a)")
    rtree_edits.append("group_b.append(seed_b)")
    rtree_edits.append("children.append(self.root)")
    rtree_edits.append("children.append(split)")
    rtree_edits.append("self.nodes[node].children.append(entry)")
    for edit in rtree_edits:
        var changed = _replace_all(texts[0], edit, "pass")
        var mutated = List[String]()
        mutated.append(changed)
        mutated.append(texts[1])
        mutated.append(texts[2])
        mutated.append(texts[3])
        assert_false(rtree_loop_admitted(paths, mutated))
    var map_changed = _replace_all(
        historical,
        "var frontier = self._tree." + NEAREST_BEGIN + "(location, work)",
        "var frontier = _Heap()",
    )
    var map_texts = List[String]()
    map_texts.append(texts[0])
    map_texts.append(map_changed)
    map_texts.append(texts[2])
    map_texts.append(texts[3])
    assert_false(rtree_loop_admitted(paths, map_texts))
    var selector = _replace_all(
        texts[2],
        "var frontier = map._tree." + NEAREST_BEGIN + "(location, work)",
        "var frontier = _Heap()",
    )
    var selector_texts = List[String]()
    selector_texts.append(texts[0])
    selector_texts.append(texts[1])
    selector_texts.append(selector)
    selector_texts.append(texts[3])
    assert_false(rtree_loop_admitted(paths, selector_texts))
    var missing = List[String]()
    var missing_texts = List[String]()
    missing.append(paths[0])
    missing_texts.append(texts[0])
    missing.append(paths[2])
    missing_texts.append(texts[2])
    missing.append(paths[3])
    missing_texts.append(texts[3])
    assert_false(rtree_loop_admitted(missing, missing_texts))
    var extra_paths = List[String]()
    var extra_texts = List[String]()
    extra_paths.append(paths[0])
    extra_texts.append(texts[0])
    extra_paths.append(paths[1])
    extra_texts.append(texts[1])
    extra_paths.append(paths[2])
    extra_texts.append(texts[2])
    extra_paths.append(paths[3])
    extra_texts.append(texts[3])
    extra_paths.append("new_caller.mojo")
    extra_texts.append(
        "def call(tree, heap, work):\n    return tree."
        + NEAREST_NEXT
        + "(point, filter, heap, work)\n"
    )
    assert_false(rtree_loop_admitted(extra_paths, extra_texts))
    assert_true(speed_loop_admitted(speed))


def main() raises:
    """Run the small loop proof tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
