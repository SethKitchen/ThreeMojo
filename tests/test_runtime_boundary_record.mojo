# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The runtime-boundary cameras and world endpoints restore from the live files."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tests._runtime_boundary_predecessor import restored_cameras, restored_world
from tools._python_json import PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/runtime-boundary-successor.json"
"""The reviewed runtime-boundary record."""
comptime _RECORD_SHA256 = (
    "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00"
)
"""The SHA-256 of that record."""
comptime _CAMERAS = "extensions/carla/cameras.mojo"
"""The cameras consumer."""
comptime _CAMERAS_LIVE_TOKEN = (
    "b631e1dbe6630902a5c0522836b854066a038d20ad40fe8bfc1015cad22008fb"
)
"""The token digest of the live cameras module."""
comptime _CAMERAS_TOKEN = (
    "a8038afbfcbd536fd5f12b10f6a2718ddb1f2d480d97854f8db4375264e1b65d"
)
"""The token digest of the restored cameras endpoint."""
comptime _WORLD = "extensions/carla/world.mojo"
"""The world consumer."""
comptime _WORLD_LIVE_TOKEN = (
    "056d05b7306a1b03390df568cde37ca711653daaf812294967b9b9be96def22c"
)
"""The token digest of the live world module."""
comptime _WORLD_TOKEN = (
    "9a50dbb87e6b604699dc19bd38f62abd0351b7b279fab5e1e37e3f81863c9d72"
)
"""The token digest of the restored world endpoint."""
comptime _CAMERAS_AFTER = (
    "dbff553682707e52175a967b7a09618716f1c7c8ba28c17e1fa7f6225725e778"
)
"""The file digest of the cameras boundary endpoint."""
comptime _WORLD_AFTER = (
    "0c7a44bfda063270715b20dfee7d21d08390f3db97f60c3bb9ddd959eaa6becd"
)
"""The file digest of the world boundary endpoint."""


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
    """Return the runtime-boundary record after its file digest matches.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error(
            "reviewed runtime boundary successor: unreviewed exact edge"
        )
    return PyJson.parse(Path(_RECORD).read_text())


def _edge(doc: PyJson, path: String) raises -> Int:
    """Return one edge and require both digests to move.

    Args:
        doc: The record.
        path: The consumer path.

    Returns:
        The edge object.

    Raises:
        Error: The edge is missing or does not move both digests.
    """
    var edges = doc.at(doc.root, "edges")
    var edge = doc.at(edges, path)
    if doc.length(edge) != 4:
        raise Error(
            "reviewed runtime boundary successor: malformed edge: " + path
        )
    var names = List[String]()
    names.append("before_sha256")
    names.append("after_sha256")
    names.append("before_token_sha256")
    names.append("after_token_sha256")
    for name in names:
        if doc.get(edge, name) < 0:
            raise Error(
                "reviewed runtime boundary successor: malformed edge: " + path
            )
    if _field(doc, edge, "before_sha256") == _field(doc, edge, "after_sha256"):
        raise Error(
            "reviewed runtime boundary successor: malformed edge: " + path
        )
    if _field(doc, edge, "before_token_sha256") == _field(
        doc, edge, "after_token_sha256"
    ):
        raise Error(
            "reviewed runtime boundary successor: malformed edge: " + path
        )
    return edge


def test_cameras_and_world_restore_their_boundary_endpoints() raises:
    """The cameras and world line edits restore the boundary endpoints."""
    var doc = _record()
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT or doc.text(schema) != "1":
        raise Error(
            "reviewed runtime boundary successor: unexpected successor scope"
        )
    if doc.text(doc.at(doc.root, "issue")) != "333":
        raise Error(
            "reviewed runtime boundary successor: unexpected successor scope"
        )
    var edges = doc.at(doc.root, "edges")
    if doc.length(edges) != 4:
        raise Error(
            "reviewed runtime boundary successor: unexpected successor scope"
        )
    var cameras = _edge(doc, _CAMERAS)
    var world = _edge(doc, _WORLD)
    _ = _edge(doc, "extensions/carla/lane_invasion.mojo")
    _ = _edge(doc, "extensions/carla/sensor_manager.mojo")
    assert_equal(_field(doc, cameras, "after_sha256"), _CAMERAS_AFTER)
    assert_equal(_field(doc, cameras, "after_token_sha256"), _CAMERAS_TOKEN)
    assert_equal(_field(doc, world, "after_sha256"), _WORLD_AFTER)
    assert_equal(_field(doc, world, "after_token_sha256"), _WORLD_TOKEN)
    var camera_text = restored_cameras()
    assert_equal(sha256_hex(camera_text.as_bytes()), _CAMERAS_AFTER)
    assert_equal(token_sha256(camera_text), _CAMERAS_TOKEN)
    assert_equal(token_sha256(Path(_CAMERAS).read_text()), _CAMERAS_LIVE_TOKEN)
    var world_text = restored_world()
    assert_equal(sha256_hex(world_text.as_bytes()), _WORLD_AFTER)
    assert_equal(token_sha256(world_text), _WORLD_TOKEN)
    assert_equal(token_sha256(Path(_WORLD).read_text()), _WORLD_LIVE_TOKEN)
    var tests = doc.at(doc.root, "correctness_tests")
    assert_equal(doc.length(tests), 12)
    var paths = List[String]()
    paths.append(
        "tests/compile_fail/carla_event_camera_time_rejects_float32_duration.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_event_camera_time_rejects_length.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_event_camera_time_rejects_raw_float64.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_lane_invasion_time_rejects_float32_duration.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_lane_invasion_time_rejects_length.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_lane_invasion_time_rejects_raw_float64.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_light_search_distance_rejects_duration.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_light_search_distance_rejects_float32_length.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_light_search_distance_rejects_raw_float64.mojo"
    )
    for path in paths:
        assert_equal(
            sha256_hex(Path(path).read_bytes()), _field(doc, tests, path)
        )


def test_a_changed_boundary_record_or_endpoint_is_refused() raises:
    """A changed record, endpoint, or bound fixture changes its digest."""
    var cameras = restored_cameras()
    var changed = cameras + "\nvar unreviewed = 1\n"
    assert_true(sha256_hex(changed.as_bytes()) != _CAMERAS_AFTER)
    assert_true(token_sha256(changed) != _CAMERAS_TOKEN)
    var world = restored_world()
    changed = world + "\nvar unreviewed = 1\n"
    assert_true(sha256_hex(changed.as_bytes()) != _WORLD_AFTER)
    assert_true(token_sha256(changed) != _WORLD_TOKEN)
    var record = Path(_RECORD).read_text()
    assert_true(sha256_hex((record + " ").as_bytes()) != _RECORD_SHA256)
    var doc = _record()
    var tests = doc.at(doc.root, "correctness_tests")
    var paths = List[String]()
    paths.append(
        "tests/compile_fail/carla_event_camera_time_rejects_float32_duration.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_event_camera_time_rejects_length.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_event_camera_time_rejects_raw_float64.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_lane_invasion_time_rejects_float32_duration.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_lane_invasion_time_rejects_length.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_lane_invasion_time_rejects_raw_float64.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_light_search_distance_rejects_duration.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_light_search_distance_rejects_float32_length.mojo"
    )
    paths.append(
        "tests/compile_fail/carla_light_search_distance_rejects_raw_float64.mojo"
    )
    for path in paths:
        var raw = Path(path).read_text()
        assert_true(
            sha256_hex((raw + "\n").as_bytes()) != _field(doc, tests, path)
        )


def main() raises:
    """Run the runtime-boundary record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
