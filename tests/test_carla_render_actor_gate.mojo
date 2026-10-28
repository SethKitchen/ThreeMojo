# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed render-actor record fails the gate."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises

from tools._sha256 import sha256_hex
from tools.carla_render_actor_gate import (
    render_actor_bytes_all,
    render_actor_checked_edges,
    render_actor_record,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed render actor reuse successor: unreviewed exact edge"
    ):
        render_actor_record(String("").as_bytes())


def test_listed_render_actor_digests_keep_their_order() raises:
    """A later digest failure keeps its own label."""
    var directory = mkdtemp(prefix="render-bytes-")
    var first = String("one")
    Path(directory + "/0").write_bytes(first.as_bytes())
    Path(directory + "/1").write_bytes(String("two").as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(first.as_bytes())
        + '","label":"first"},{"name":"1","sha":"00","label":"second"}]'
    )
    with assert_raises(
        contains="reviewed render actor reuse successor: second"
    ):
        render_actor_bytes_all(directory)


def test_a_checked_render_actor_edge_writes_the_path_first() raises:
    """A matching digest writes the module path before the stored keys."""
    var directory = mkdtemp(prefix="render-checked-")
    var body = String("actor")
    Path(directory + "/0").write_bytes(body.as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(body.as_bytes())
        + '","label":"actor","path":"extensions/carla/render_actors.mojo",'
        + '"edge":{"after_sha256":"aa"}}]'
    )
    assert_equal(
        render_actor_checked_edges(directory),
        '[{"path":"extensions/carla/render_actors.mojo","after_sha256":"aa"}]',
    )


def test_a_changed_checked_render_actor_digest_is_refused() raises:
    """A later digest failure is reported before any edge is returned."""
    var directory = mkdtemp(prefix="render-checked-bad-")
    var body = String("actor")
    Path(directory + "/0").write_bytes(body.as_bytes())
    Path(directory + "/1").write_bytes(String("other").as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(body.as_bytes())
        + '","label":"first","path":"a.mojo","edge":{"after_sha256":"aa"}},'
        + '{"name":"1","sha":"00","label":"second","path":"b.mojo",'
        + '"edge":{"after_sha256":"bb"}}]'
    )
    with assert_raises(
        contains="reviewed render actor reuse successor: second"
    ):
        _ = render_actor_checked_edges(directory)


def main() raises:
    """Run the render-actor gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
