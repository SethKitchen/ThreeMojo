# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed runtime-boundary record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises

from tools._bound_consumer_messages import bound_consumer_messages
from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.carla_runtime_boundary_gate import (
    boundary_extend,
    boundary_extends,
    boundary_steps,
    runtime_boundary_bytes_all,
    runtime_boundary_checked_edges,
    runtime_boundary_checked_edges_with_messages,
    runtime_boundary_edges_after_steps,
    runtime_boundary_modules,
    runtime_boundary_extended_edges,
    runtime_boundary_record,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed runtime boundary successor: unreviewed exact edge"
    ):
        runtime_boundary_record(String("").as_bytes())


def test_a_foreign_view_step_is_refused() raises:
    """A step outside the four modules fails closed."""
    var directory = "/tmp/boundary-step-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text('["extensions/carla/map.mojo"]')
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step outside"
            " the boundary scope"
        )
    ):
        boundary_steps(directory)


def test_a_disconnected_view_step_is_refused() raises:
    """A step that does not start at the edge end fails closed."""
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step does not"
            " extend the edge: extensions/carla/world.mojo"
        )
    ):
        boundary_extend("aa", "bb", "cc", "cc", "extensions/carla/world.mojo")


def test_listed_extensions_keep_their_order() raises:
    """A later extension failure keeps its own path."""
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step does not"
            " extend the edge: two.mojo"
        )
    ):
        boundary_extends(
            '[{"path":"one.mojo","step_sha":"aa","edge_sha":"aa",'
            + '"step_token":"bb","edge_token":"bb"},'
            + '{"path":"two.mojo","step_sha":"aa","edge_sha":"cc",'
            + '"step_token":"bb","edge_token":"bb"}]'
        )


def test_listed_boundary_digests_keep_their_order() raises:
    """A later digest failure keeps its own label."""
    var directory = mkdtemp(prefix="boundary-bytes-")
    var first = String("one")
    Path(directory + "/0").write_bytes(first.as_bytes())
    Path(directory + "/1").write_bytes(String("two").as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(first.as_bytes())
        + '","label":"first"},{"name":"1","sha":"00","label":"second"}]'
    )
    with assert_raises(contains="reviewed runtime boundary successor: second"):
        runtime_boundary_bytes_all(directory)


def test_a_checked_boundary_edge_writes_the_path_first() raises:
    """A matching digest writes the module path before the stored keys."""
    var directory = mkdtemp(prefix="boundary-checked-")
    var body = String("edge")
    Path(directory + "/0").write_bytes(body.as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(body.as_bytes())
        + '","label":"edge","path":"extensions/carla/map.mojo",'
        + '"edge":{"after_sha256":"aa"}}]'
    )
    assert_equal(
        runtime_boundary_checked_edges(directory),
        '[{"path":"extensions/carla/map.mojo","after_sha256":"aa"}]',
    )


def test_a_changed_checked_boundary_digest_is_refused() raises:
    """A later digest failure is reported before any edge is returned."""
    var directory = mkdtemp(prefix="boundary-checked-bad-")
    var body = String("edge")
    Path(directory + "/0").write_bytes(body.as_bytes())
    Path(directory + "/1").write_bytes(String("other").as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(body.as_bytes())
        + '","label":"first","path":"a.mojo","edge":{"after_sha256":"aa"}},'
        + '{"name":"1","sha":"00","label":"second","path":"b.mojo",'
        + '"edge":{"after_sha256":"bb"}}]'
    )
    with assert_raises(contains="reviewed runtime boundary successor: second"):
        _ = runtime_boundary_checked_edges(directory)


def test_a_missing_view_step_leaves_the_edge() raises:
    """A path without a step is not an extension."""
    var payload = (
        '{"steps":{},"items":[{"path":"a.mojo",'
        + '"edge":{"after_sha256":"aa","after_token_sha256":"bb"}}]}'
    )
    assert_equal(
        runtime_boundary_extended_edges(payload),
        '[{"extend":false}]',
    )


def test_a_matching_view_step_extends_the_edge() raises:
    """A step that meets the edge replaces the after digests."""
    var payload = (
        '{"steps":{"a.mojo":{"before_sha256":"aa",'
        + '"before_token_sha256":"bb","after_sha256":"cc",'
        + '"after_token_sha256":"dd"}},'
        + '"items":[{"path":"a.mojo","edge":{"after_sha256":"aa",'
        + '"after_token_sha256":"bb"}}]}'
    )
    assert_equal(
        runtime_boundary_extended_edges(payload),
        '[{"extend":true,"edge":{"after_sha256":"cc",'
        + '"after_token_sha256":"dd"}}]',
    )


def test_a_disconnected_extension_is_refused() raises:
    """A step that does not meet the edge fails before the decision is used."""
    var payload = (
        '{"steps":{"a.mojo":{"before_sha256":"aa",'
        + '"before_token_sha256":"bb","after_sha256":"cc",'
        + '"after_token_sha256":"dd"}},'
        + '"items":[{"path":"a.mojo","edge":{"after_sha256":"zz",'
        + '"after_token_sha256":"bb"}}]}'
    )
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step does not"
            " extend the edge: a.mojo"
        )
    ):
        _ = runtime_boundary_extended_edges(payload)


def test_the_consumer_messages_are_read_before_the_digests() raises:
    """A matching digest keeps the messages, and a change uses that label."""
    var directory = mkdtemp(prefix="runtime-labeled-")
    var body = String("actor")
    Path(directory + "/0").write_bytes(body.as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(body.as_bytes())
        + '","path":"a.mojo","edge":{"after_sha256":"aa"}}]'
    )
    assert_equal(
        runtime_boundary_checked_edges_with_messages(directory),
        '{"edges":[{"path":"a.mojo","after_sha256":"aa"}],"messages":'
        + bound_consumer_messages()
        + "}",
    )
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"00","path":"a.mojo","edge":{"after_sha256":"aa"}}]'
    )
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: unreviewed runtime boundary"
            " consumer: a.mojo"
        )
    ):
        _ = runtime_boundary_checked_edges_with_messages(directory)


def test_view_steps_are_checked_before_the_module_paths() raises:
    """A foreign step fails before a missing edge, and a full edge set extends.
    """
    var lane = "extensions/carla/lane_invasion.mojo"
    var step = (
        '{"before_sha256":"aa","before_token_sha256":"bb",'
        + '"after_sha256":"cc","after_token_sha256":"dd"}'
    )
    var edge = '{"after_sha256":"aa","after_token_sha256":"bb"}'
    var modules = (
        '["extensions/carla/cameras.mojo","'
        + lane
        + '","extensions/carla/sensor_manager.mojo",'
        + '"extensions/carla/world.mojo"]'
    )
    with assert_raises(
        contains=(
            "reviewed runtime boundary successor: runtime view step outside the"
            " boundary scope"
        )
    ):
        _ = runtime_boundary_edges_after_steps(
            '{"steps":{"other.mojo":' + step + '},"edges":{}}'
        )
    with assert_raises(contains="KeyError: 'extensions/carla/cameras.mojo'"):
        _ = runtime_boundary_edges_after_steps(
            '{"steps":{},"edges":{"extensions/carla/world.mojo":' + edge + "}}"
        )
    var payload = (
        '{"steps":{"'
        + lane
        + '":'
        + step
        + '},"edges":{"extensions/carla/cameras.mojo":'
        + edge
        + ',"'
        + lane
        + '":'
        + edge
        + ',"extensions/carla/sensor_manager.mojo":'
        + edge
        + ',"extensions/carla/world.mojo":'
        + edge
        + "}}"
    )
    var doc = PyJson.parse(runtime_boundary_edges_after_steps(payload))
    assert_equal(runtime_boundary_modules(), modules)
    var decisions = doc.at(doc.root, "decisions")
    assert_equal(doc.length(decisions), 4)
    assert_equal(doc.flag(doc.at(doc.item(decisions, 0), "extend")), False)
    assert_equal(doc.flag(doc.at(doc.item(decisions, 1), "extend")), True)


def main() raises:
    """Run the runtime-boundary gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
