# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The runtime-view steps start at the boundary edges."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/runtime-view-successor.json"
"""The reviewed runtime-view record."""
comptime _RECORD_SHA256 = (
    "40fe6f5aef91b4a9f407f1a8ea83721b317d24b690d947c623feca8b73dcc907"
)
"""The SHA-256 of that record."""
comptime _BOUNDARY = "tools/carla_lane_oracle/runtime-boundary-successor.json"
"""The boundary record whose after digests start these steps."""
comptime _LANE = "extensions/carla/lane_invasion.mojo"
"""The lane invasion consumer whose live file is the step end."""
comptime _SENSOR = "extensions/carla/sensor_manager.mojo"
"""The sensor consumer whose step starts at its boundary edge."""


def _field(doc: PyJson, node: Int, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The document.
        node: The object.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(node, name))


def _record() raises -> PyJson:
    """Return the runtime-view record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error("reviewed runtime view successor: unreviewed exact step")
    return PyJson.parse(Path(_RECORD).read_text())


def _step(doc: PyJson, steps: Int, path: String) raises -> Int:
    """Return one step and require its four digests to move.

    Args:
        doc: The record.
        steps: The step object.
        path: The consumer path.

    Returns:
        The step object.

    Raises:
        Error: The step is missing or does not move both digests.
    """
    var step = doc.at(steps, path)
    if doc.length(step) != 4:
        raise Error("reviewed runtime view successor: malformed step: " + path)
    var names = List[String]()
    names.append("before_sha256")
    names.append("after_sha256")
    names.append("before_token_sha256")
    names.append("after_token_sha256")
    for name in names:
        _ = _field(doc, step, name)
    if _field(doc, step, "before_sha256") == _field(
        doc, step, "after_sha256"
    ) or _field(doc, step, "before_token_sha256") == _field(
        doc, step, "after_token_sha256"
    ):
        raise Error("reviewed runtime view successor: malformed step: " + path)
    return step


def test_the_view_steps_start_at_the_boundary_edges() raises:
    """Both steps start at the boundary edges, and the lane file is the step end.
    """
    var doc = _record()
    assert_equal(_field(doc, doc.root, "schema"), "1")
    assert_equal(_field(doc, doc.root, "issue"), "333")
    var steps = doc.at(doc.root, "steps")
    assert_equal(doc.length(steps), 2)
    var boundary = PyJson.parse(Path(_BOUNDARY).read_text())
    var edges = boundary.at(boundary.root, "edges")
    assert_equal(boundary.length(edges), 4)
    var paths = List[String]()
    paths.append(_LANE)
    paths.append(_SENSOR)
    for path in paths:
        var step = _step(doc, steps, path)
        var edge = boundary.at(edges, path)
        assert_equal(
            _field(doc, step, "before_sha256"),
            _field(boundary, edge, "after_sha256"),
        )
        assert_equal(
            _field(doc, step, "before_token_sha256"),
            _field(boundary, edge, "after_token_sha256"),
        )
    var lane = Path(_LANE).read_text()
    var lane_step = doc.at(steps, _LANE)
    assert_equal(
        sha256_hex(lane.as_bytes()), _field(doc, lane_step, "after_sha256")
    )
    assert_equal(
        token_sha256(lane), _field(doc, lane_step, "after_token_sha256")
    )
    var others = List[String]()
    others.append("extensions/carla/cameras.mojo")
    others.append("extensions/carla/world.mojo")
    for path in others:
        assert_true(doc.get(steps, path) < 0)
        _ = boundary.at(edges, path)
    var tests = doc.at(doc.root, "correctness_tests")
    assert_equal(doc.length(tests), 5)
    var index = 0
    while index < doc.length(tests):
        var path = doc.key(tests, index)
        assert_equal(
            sha256_hex(Path(path).read_bytes()),
            doc.text(doc.value(tests, index)),
        )
        index += 1


def test_a_changed_step_file_or_fixture_is_refused() raises:
    """A changed record, lane file, or bound fixture changes its digest."""
    var doc = _record()
    var raw = Path(_RECORD).read_bytes()
    raw.append(UInt8(32))
    var refused = False
    try:
        if sha256_hex(raw) != _RECORD_SHA256:
            raise Error(
                "reviewed runtime view successor: unreviewed exact step"
            )
    except error:
        refused = True
        assert_true(String(error).find("unreviewed exact step") >= 0)
    assert_true(refused)
    var lane = Path(_LANE).read_bytes()
    lane.append(UInt8(10))
    var step = doc.at(doc.at(doc.root, "steps"), _LANE)
    assert_true(sha256_hex(lane) != _field(doc, step, "after_sha256"))
    var tests = doc.at(doc.root, "correctness_tests")
    var index = 0
    while index < doc.length(tests):
        var path = doc.key(tests, index)
        var fixture = Path(path).read_bytes()
        fixture.append(UInt8(32))
        assert_true(sha256_hex(fixture) != doc.text(doc.value(tests, index)))
        index += 1


def main() raises:
    """Run the runtime-view record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
