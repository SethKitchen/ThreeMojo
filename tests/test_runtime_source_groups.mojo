# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The runtime source groups stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._border_pin_predecessor import restored_border_pins
from tests._geometry_predecessor import restored_geometry
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
from tests._winner_pin_predecessor import (
    _apply,
    _lines_7,
    _replace_spans,
    _spans_8,
    _spans_9,
    restored_count_bounds,
    restored_junction_cleanup,
    restored_rounded_arc_cleanup,
    restored_winner_pins,
)
from tools.runtime_source_groups import runtime_source_groups


def _pins() raises -> String:
    """Return the runtime pin document.

    Returns:
        The document text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("tools/carla_lane_oracle/runtime-source-pins.json").read_text()


def _live(name: String) raises -> String:
    """Return one live CARLA module.

    Args:
        name: The module stem.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/" + name + ".mojo").read_text()


def _add(
    mut paths: List[String],
    mut texts: List[String],
    path: String,
    text: String,
):
    """Append one reviewed source.

    Args:
        paths: The supplied paths.
        texts: The supplied sources.
        path: The repository path.
        text: The reviewed source.
    """
    paths.append(path)
    texts.append(text)


def _pick(paths: List[String], texts: List[String], path: String) -> String:
    """Return one restored source.

    Args:
        paths: The restored paths.
        texts: The restored sources.
        path: The path to find.

    Returns:
        The source, or an empty string when `path` is absent.
    """
    var index = 0
    var found = String("")
    while index < len(paths):
        if paths[index] == path:
            found = String(texts[index])
        index += 1
    return found^


def _lane_order() raises -> String:
    """Return the lane-order successor of the live refinement module.

    Returns:
        The source whose token digest is the runtime pin.

    Raises:
        Error: The restoration failed.
    """
    var live = _live("lane_refinement")
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _lines_7(starts, stops, befores)
    var text = _apply(live, starts, stops, befores)
    var before_spans = List[String]()
    var after_spans = List[String]()
    _spans_8(before_spans, after_spans)
    text = _replace_spans(
        text,
        before_spans,
        after_spans,
        "extensions/carla/lane_refinement.mojo",
    )
    before_spans = List[String]()
    after_spans = List[String]()
    _spans_9(before_spans, after_spans)
    return _replace_spans(
        text,
        before_spans,
        after_spans,
        "extensions/carla/lane_refinement.mojo",
    )


def _map() raises -> String:
    """Return the historical Map source.

    Returns:
        The source whose token digest is the runtime pin.

    Raises:
        Error: The restoration failed.
    """
    var deviation = restored_deviation_map()
    var station = station_endpoint(deviation)
    var score = score_endpoint(station)
    var frontier = frontier_endpoint(score)
    var support = support_endpoint(frontier)
    var optional = optional_endpoint(support)
    return historical_map(count_endpoint(optional))


def _reviewed(mut paths: List[String], mut texts: List[String]) raises:
    """Fill the reviewed source of every runtime group path.

    Args:
        paths: The supplied paths, replaced by this call.
        texts: The supplied sources, replaced by this call.

    Raises:
        Error: A restoration failed.
    """
    var border_paths = List[String]()
    var border_texts = List[String]()
    restored_border_pins(border_paths, border_texts)
    var winner_paths = List[String]()
    var winner_texts = List[String]()
    restored_winner_pins(winner_paths, winner_texts)
    var live_names = List[String]()
    live_names.append("curve_sum2")
    live_names.append("curve_interval")
    live_names.append("spiral_roundoff_proof")
    live_names.append("spiral_moment_proof")
    live_names.append("spiral_moment_table")
    live_names.append("curve_minimizer_support")
    live_names.append("curve_objective_model")
    live_names.append("spiral_grouped_roundoff_proof")
    live_names.append("curve_trig")
    live_names.append("curve_frozen_arc")
    live_names.append("spiral_moment_table_data")
    live_names.append("lane_distance")
    var index = 0
    while index < len(live_names):
        var name = live_names[index]
        _add(paths, texts, "extensions/carla/" + name + ".mojo", _live(name))
        index += 1
    _add(
        paths,
        texts,
        "extensions/carla/lane_geometry.mojo",
        _pick(
            border_paths, border_texts, "extensions/carla/lane_geometry.mojo"
        ),
    )
    _add(
        paths,
        texts,
        "extensions/carla/curve_rounded_line.mojo",
        _pick(
            border_paths,
            border_texts,
            "extensions/carla/curve_rounded_line.mojo",
        ),
    )
    _add(
        paths,
        texts,
        "extensions/carla/curve_sample_dispatch.mojo",
        _pick(
            border_paths,
            border_texts,
            "extensions/carla/curve_sample_dispatch.mojo",
        ),
    )
    _add(
        paths,
        texts,
        "extensions/carla/map_builder.mojo",
        _pick(border_paths, border_texts, "extensions/carla/map_builder.mojo"),
    )
    _add(
        paths,
        texts,
        "extensions/carla/road_info.mojo",
        _pick(border_paths, border_texts, "extensions/carla/road_info.mojo"),
    )
    _add(
        paths,
        texts,
        "extensions/carla/spiral_domain_proof.mojo",
        _pick(
            border_paths,
            border_texts,
            "extensions/carla/spiral_domain_proof.mojo",
        ),
    )
    _add(
        paths,
        texts,
        "extensions/carla/spiral_grouped_lane.mojo",
        _pick(
            border_paths,
            border_texts,
            "extensions/carla/spiral_grouped_lane.mojo",
        ),
    )
    _add(
        paths,
        texts,
        "extensions/carla/curve_bounds.mojo",
        restored_count_bounds(),
    )
    _add(paths, texts, "extensions/carla/geometry.mojo", restored_geometry())
    _add(
        paths,
        texts,
        "extensions/carla/lane_value_bounds.mojo",
        _pick(
            winner_paths,
            winner_texts,
            "extensions/carla/lane_value_bounds.mojo",
        ),
    )
    _add(
        paths,
        texts,
        "extensions/carla/polynomial.mojo",
        _pick(winner_paths, winner_texts, "extensions/carla/polynomial.mojo"),
    )
    _add(paths, texts, "extensions/carla/map.mojo", _map())
    _add(paths, texts, "extensions/carla/lane_refinement.mojo", _lane_order())
    _add(
        paths,
        texts,
        "extensions/carla/curve_rounded_arc.mojo",
        restored_rounded_arc_cleanup(),
    )
    _add(
        paths,
        texts,
        "extensions/carla/junction_bounds.mojo",
        restored_junction_cleanup(),
    )


def test_the_runtime_groups_hold() raises:
    """The six groups match their reviewed token pins."""
    var pins = _pins()
    var paths = List[String]()
    var texts = List[String]()
    _reviewed(paths, texts)
    runtime_source_groups(pins, paths, texts)
    var commented = List[String]()
    var commented_texts = List[String]()
    var index = 0
    while index < len(paths):
        commented.append(paths[index])
        if paths[index] == "extensions/carla/curve_trig.mojo":
            commented_texts.append(texts[index] + "\n# reviewed\n")
        else:
            commented_texts.append(texts[index])
        index += 1
    runtime_source_groups(pins, commented, commented_texts)


def test_a_changed_runtime_group_is_refused() raises:
    """A changed pin, source, or document is refused."""
    var pins = _pins()
    var paths = List[String]()
    var texts = List[String]()
    _reviewed(paths, texts)
    var changed = List[String]()
    var changed_texts = List[String]()
    var index = 0
    while index < len(paths):
        changed.append(paths[index])
        if paths[index] == "extensions/carla/curve_sum2.mojo":
            changed_texts.append(texts[index] + '\nvar extra = "a\\\\b"\n')
        else:
            changed_texts.append(texts[index])
        index += 1
    with assert_raises(
        contains=(
            "runtime source dependency changed [canonical_accumulation]: "
            "extensions/carla/curve_sum2.mojo"
        )
    ):
        runtime_source_groups(pins, changed, changed_texts)
    var closer = List[String]()
    var closer_texts = List[String]()
    index = 0
    while index < len(paths):
        closer.append(paths[index])
        if paths[index] == "extensions/carla/curve_sum2.mojo":
            closer_texts.append(texts[index] + "\n)\n")
        else:
            closer_texts.append(texts[index])
        index += 1
    with assert_raises(contains="invalid source tokens: extra closer"):
        runtime_source_groups(pins, closer, closer_texts)
    var kept = List[String]()
    var kept_texts = List[String]()
    index = 0
    while index < len(paths):
        if paths[index] != "extensions/carla/curve_sum2.mojo":
            kept.append(paths[index])
            kept_texts.append(texts[index])
        index += 1
    with assert_raises(
        contains=(
            "runtime source dependency changed [canonical_accumulation]: "
            "extensions/carla/curve_sum2.mojo"
        )
    ):
        runtime_source_groups(pins, kept, kept_texts)
    with assert_raises(contains="wrong runtime source pin keys"):
        runtime_source_groups(
            pins.replace(
                '{\n  "schema": 1,', '{\n  "schema": 1,\n  "extra": 1,'
            ),
            paths,
            texts,
        )
    with assert_raises(contains="unsupported runtime source pin schema"):
        runtime_source_groups(
            pins.replace('"schema": 1', '"schema": 2'), paths, texts
        )
    with assert_raises(contains="wrong runtime dependency group set"):
        runtime_source_groups(
            pins.replace("canonical_accumulation", "canonical_other"),
            paths,
            texts,
        )
    with assert_raises(
        contains="wrong runtime dependency path set: canonical_accumulation"
    ):
        runtime_source_groups(
            pins.replace(
                "extensions/carla/curve_sum2.mojo",
                "extensions/carla/curve_sum2_other.mojo",
            ),
            paths,
            texts,
        )
    with assert_raises(
        contains=(
            "invalid runtime dependency digest: "
            "extensions/carla/curve_sum2.mojo"
        )
    ):
        runtime_source_groups(
            pins.replace(
                '"extensions/carla/curve_sum2.mojo": "3fbcbb7f',
                '"extensions/carla/curve_sum2.mojo": "ggbcbb7f',
            ),
            paths,
            texts,
        )
    with assert_raises(
        contains=(
            "invalid runtime dependency digest: "
            "extensions/carla/curve_sum2.mojo"
        )
    ):
        runtime_source_groups(
            pins.replace(
                (
                    '"extensions/carla/curve_sum2.mojo": '
                    '"3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d"'
                ),
                '"extensions/carla/curve_sum2.mojo": "ab"',
            ),
            paths,
            texts,
        )
    with assert_raises(
        contains=(
            "invalid runtime dependency digest: "
            "extensions/carla/curve_sum2.mojo"
        )
    ):
        runtime_source_groups(
            pins.replace(
                (
                    '"extensions/carla/curve_sum2.mojo": '
                    '"3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d"'
                ),
                '"extensions/carla/curve_sum2.mojo": 1',
            ),
            paths,
            texts,
        )
    with assert_raises(contains="wrong qualifier file set"):
        runtime_source_groups(
            pins.replace('"curve_bounds.mojo"', '"curve_bounds_other.mojo"'),
            paths,
            texts,
        )
    var empty = List[String]()
    var empty_texts = List[String]()
    with assert_raises(contains="wrong runtime source pin keys"):
        runtime_source_groups("[]", empty, empty_texts)
    with assert_raises(contains="unsupported runtime source pin schema"):
        runtime_source_groups(
            pins.replace('"schema": 1', '"schema": "1"'), paths, texts
        )
    with assert_raises(contains="wrong runtime dependency group set"):
        runtime_source_groups(
            (
                '{"schema": 1, "groups": [], "qualifiers": {'
                '"curve_bounds.mojo": "a", "curve_trig.mojo": "a", '
                '"curve_interval.mojo": "a", '
                '"lane_value_bounds.mojo": "a"}}'
            ),
            empty,
            empty_texts,
        )
    with assert_raises(contains="wrong qualifier file set"):
        runtime_source_groups(
            (
                '{"schema": 1, "groups": {"canonical_accumulation": 1, '
                '"optional_runtime": 1, "stored_arithmetic": 1, '
                '"eligibility": 1, "translation": 1, "support": 1}, '
                '"qualifiers": 1}'
            ),
            empty,
            empty_texts,
        )
    with assert_raises(
        contains="wrong runtime dependency path set: canonical_accumulation"
    ):
        runtime_source_groups(
            (
                '{"schema": 1, "groups": {"canonical_accumulation": 1, '
                '"optional_runtime": {}, "stored_arithmetic": {}, '
                '"eligibility": {}, "translation": {}, "support": {}}, '
                '"qualifiers": {"curve_bounds.mojo": "a", '
                '"curve_trig.mojo": "a", "curve_interval.mojo": "a", '
                '"lane_value_bounds.mojo": "a"}}'
            ),
            empty,
            empty_texts,
        )
    var open_string = List[String]()
    var open_texts = List[String]()
    index = 0
    while index < len(paths):
        open_string.append(paths[index])
        if paths[index] == "extensions/carla/curve_sum2.mojo":
            open_texts.append(texts[index] + '\nvar extra = "abc')
        else:
            open_texts.append(texts[index])
        index += 1
    with assert_raises(contains="invalid source tokens: unclosed string"):
        runtime_source_groups(pins, open_string, open_texts)
    var open_triple = List[String]()
    var open_triple_texts = List[String]()
    index = 0
    while index < len(paths):
        open_triple.append(paths[index])
        if paths[index] == "extensions/carla/curve_sum2.mojo":
            open_triple_texts.append(texts[index] + '\nvar extra = """abc')
        else:
            open_triple_texts.append(texts[index])
        index += 1
    with assert_raises(contains="invalid source tokens: unclosed string"):
        runtime_source_groups(pins, open_triple, open_triple_texts)


def main() raises:
    """Run the runtime source group tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
