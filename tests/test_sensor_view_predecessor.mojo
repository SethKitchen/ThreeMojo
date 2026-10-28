# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live sensor manager restores the runtime-view endpoint."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tests._sensor_view_predecessor import restored_sensor_view
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/sensor_manager.mojo"
"""The sensor manager this view step names."""
comptime _LIVE_TOKEN = (
    "fac0a508fbc6540191d09b3a91e449544ebd6557399f2696bc6bf81cbddd86b4"
)
"""The token digest of the live sensor manager."""
comptime _RESTORED_SHA256 = (
    "6c8c81d18596601c31b4bb8e510beb814cbadd237dd8494b954c3e0663eeec82"
)
"""The file digest of the restored view endpoint."""
comptime _RESTORED_TOKEN = (
    "88272d53dd71b4e142e020d6371b22dc55354a91192ba8f4aeedf998fb5cf602"
)
"""The token digest of that endpoint."""
comptime _VIEW = "tools/carla_lane_oracle/runtime-view-successor.json"
"""The runtime-view record."""
comptime _VIEW_SHA256 = (
    "40fe6f5aef91b4a9f407f1a8ea83721b317d24b690d947c623feca8b73dcc907"
)
"""The SHA-256 of that record."""
comptime _BOUNDARY = "tools/carla_lane_oracle/runtime-boundary-successor.json"
"""The runtime-boundary record."""
comptime _BOUNDARY_SHA256 = (
    "992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00"
)
"""The SHA-256 of that record."""


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


def _pinned(path: String, digest: String) raises -> PyJson:
    """Return a record after its file digest matches.

    Args:
        path: The record path.
        digest: The required digest.

    Returns:
        The parsed record.

    Raises:
        Error: The record bytes changed.
    """
    if sha256_hex(Path(path).read_bytes()) != digest:
        raise Error("reviewed runtime view successor: unreviewed exact step")
    return PyJson.parse(Path(path).read_text())


def test_live_sensor_restores_the_view_endpoint() raises:
    """Two source edits and ten view edits restore the sensor view endpoint."""
    var restored = restored_sensor_view()
    assert_equal(sha256_hex(restored.as_bytes()), _RESTORED_SHA256)
    assert_equal(token_sha256(restored), _RESTORED_TOKEN)
    assert_equal(token_sha256(Path(_MODULE).read_text()), _LIVE_TOKEN)
    var view = _pinned(_VIEW, _VIEW_SHA256)
    var step = view.at(view.at(view.root, "steps"), _MODULE)
    assert_equal(_field(view, step, "after_sha256"), _RESTORED_SHA256)
    assert_equal(_field(view, step, "after_token_sha256"), _RESTORED_TOKEN)
    var boundary = _pinned(_BOUNDARY, _BOUNDARY_SHA256)
    var edge = boundary.at(boundary.at(boundary.root, "edges"), _MODULE)
    assert_equal(
        _field(view, step, "before_sha256"),
        _field(boundary, edge, "after_sha256"),
    )
    assert_equal(
        _field(view, step, "before_token_sha256"),
        _field(boundary, edge, "after_token_sha256"),
    )
    assert_true(_field(view, step, "before_sha256") != _RESTORED_SHA256)
    assert_true(_field(view, step, "before_token_sha256") != _RESTORED_TOKEN)


def test_a_changed_sensor_endpoint_is_refused() raises:
    """A changed sensor endpoint or view record changes its digest."""
    var restored = restored_sensor_view()
    var changed = restored + "\nvar unreviewed = 1\n"
    assert_true(sha256_hex(changed.as_bytes()) != _RESTORED_SHA256)
    assert_true(token_sha256(changed) != _RESTORED_TOKEN)
    var record = Path(_VIEW).read_text()
    assert_true(sha256_hex((record + " ").as_bytes()) != _VIEW_SHA256)


def main() raises:
    """Run the sensor view predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
