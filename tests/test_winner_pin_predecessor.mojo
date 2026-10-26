# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed winner pins restore from the live consumer files."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._border_pin_predecessor import restored_border_pins
from tests._geometry_predecessor import restored_geometry
from tests._opendrive_border import restored_opendrive
from tests._render_actor_predecessor import restored_render_actors
from tests._runtime_boundary_predecessor import restored_cameras, restored_world
from tests._sensor_view_predecessor import restored_sensor_view
from tests._winner_pin_predecessor import (
    restored_cameras_winner,
    restored_dispatch_winner,
    restored_domain_winner,
    restored_frozen_arc_winner,
    restored_junction_winner,
    restored_lane_invasion_winner,
    restored_opendrive_winner,
    restored_render_actor_winner,
    restored_rounded_arc_winner,
    restored_rounded_line_winner,
    restored_sensor_winner,
    restored_winner_pins,
    restored_world_winner,
)
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _RECORD = "tools/carla_lane_oracle/winner-sign-query-migration.json"
"""The reviewed winner and sign record."""
comptime _RECORD_SHA256 = (
    "b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3"
)
"""The SHA-256 of that record."""
comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The geometry module restored by its own predecessor."""
comptime _DOMAIN = "extensions/carla/spiral_domain_proof.mojo"
"""The domain module restored from its border pin."""
comptime _ARC = "extensions/carla/curve_rounded_arc.mojo"
"""The rounded arc module restored from the live file."""
comptime _ROUNDED = "extensions/carla/curve_rounded_line.mojo"
"""A border pin that is not the winner pin."""
comptime _DISPATCH = "extensions/carla/curve_sample_dispatch.mojo"
"""A border pin that is not the winner pin."""
comptime _FROZEN = "extensions/carla/curve_frozen_arc.mojo"
"""The frozen arc module restored from the live file."""
comptime _LANE = "extensions/carla/lane_invasion.mojo"
"""The lane invasion module restored from the live file."""
comptime _JUNCTION = "extensions/carla/junction_bounds.mojo"
"""The junction module restored from the live file."""
comptime _CAMERAS = "extensions/carla/cameras.mojo"
"""The cameras module restored from its boundary endpoint."""
comptime _WORLD = "extensions/carla/world.mojo"
"""The world module restored from its boundary endpoint."""
comptime _SENSOR = "extensions/carla/sensor_manager.mojo"
"""The sensor manager restored from its view endpoint."""
comptime _ACTORS = "extensions/carla/render_actors.mojo"
"""The render-actor module restored from its ledger endpoint."""
comptime _OPEN = "extensions/carla/opendrive.mojo"
"""The OpenDRIVE module restored from its border endpoint."""


def _find(paths: List[String], name: String) -> Int:
    """Return the index of `name`, or -1.

    Args:
        paths: The restored paths.
        name: The path to find.

    Returns:
        The index, or -1 when the path was not restored here.
    """
    for index in range(len(paths)):
        if paths[index] == name:
            return index
    return -1


def test_live_consumers_restore_their_winner_pins() raises:
    """Restored consumers match the winner pins, and live matches stay direct.
    """
    if sha256_hex(Path(_RECORD).read_bytes()) != _RECORD_SHA256:
        raise Error("winner/sign source contract: unreviewed migration record")
    var doc = PyJson.parse(Path(_RECORD).read_text())
    var schema = doc.at(doc.root, "schema")
    if doc.text(schema) != "1":
        raise Error("winner/sign source contract: unsupported migration schema")
    var pins = doc.at(doc.root, "canonical_source_unchanged")
    var border_paths = List[String]()
    var border_texts = List[String]()
    restored_border_pins(border_paths, border_texts)
    var paths = List[String]()
    var texts = List[String]()
    restored_winner_pins(paths, texts)
    assert_equal(len(paths), 16)
    var geometry = restored_geometry()
    var direct = 0
    var border_match = 0
    var border_differ = 0
    var covered = 0
    var index = 0
    while index < doc.length(pins):
        var name = doc.key(pins, index)
        var expected = doc.text(doc.value(pins, index))
        if name == _GEOMETRY:
            assert_equal(sha256_hex(geometry.as_bytes()), expected)
        else:
            var found = _find(paths, name)
            if found >= 0:
                assert_equal(sha256_hex(texts[found].as_bytes()), expected)
            else:
                var border = _find(border_paths, name)
                if border >= 0:
                    var digest = sha256_hex(border_texts[border].as_bytes())
                    if digest == expected:
                        border_match += 1
                    else:
                        border_differ += 1
                        if name == _DOMAIN:
                            var domain = restored_domain_winner(
                                border_texts[border]
                            )
                            assert_equal(
                                sha256_hex(domain.as_bytes()), expected
                            )
                        elif name == _DISPATCH:
                            var dispatch = restored_dispatch_winner(
                                border_texts[border]
                            )
                            assert_equal(
                                sha256_hex(dispatch.as_bytes()), expected
                            )
                        else:
                            assert_true(name == _ROUNDED)
                            var line = restored_rounded_line_winner()
                            assert_equal(sha256_hex(line.as_bytes()), expected)
                elif name == _ARC:
                    var arc = restored_rounded_arc_winner()
                    assert_equal(sha256_hex(arc.as_bytes()), expected)
                elif name == _FROZEN:
                    var frozen = restored_frozen_arc_winner()
                    assert_equal(sha256_hex(frozen.as_bytes()), expected)
                    covered += 1
                elif name == _LANE:
                    var lane = restored_lane_invasion_winner()
                    assert_equal(sha256_hex(lane.as_bytes()), expected)
                    covered += 1
                elif name == _JUNCTION:
                    var junction = restored_junction_winner()
                    assert_equal(sha256_hex(junction.as_bytes()), expected)
                    covered += 1
                elif name == _CAMERAS:
                    var cameras = restored_cameras_winner(restored_cameras())
                    assert_equal(sha256_hex(cameras.as_bytes()), expected)
                    covered += 1
                elif name == _WORLD:
                    var world = restored_world_winner(restored_world())
                    assert_equal(sha256_hex(world.as_bytes()), expected)
                    covered += 1
                elif name == _SENSOR:
                    var sensor = restored_sensor_winner(restored_sensor_view())
                    assert_equal(sha256_hex(sensor.as_bytes()), expected)
                    covered += 1
                elif name == _ACTORS:
                    var actors = restored_render_actor_winner(
                        restored_render_actors()
                    )
                    assert_equal(sha256_hex(actors.as_bytes()), expected)
                    covered += 1
                elif name == _OPEN:
                    var opendrive = restored_opendrive_winner(
                        restored_opendrive()
                    )
                    assert_equal(sha256_hex(opendrive.as_bytes()), expected)
                    covered += 1
                elif sha256_hex(Path(name).read_bytes()) == expected:
                    direct += 1
        index += 1
    assert_equal(doc.length(pins), 112)
    assert_equal(border_match, 42)
    assert_equal(border_differ, 3)
    assert_equal(direct, 41)
    assert_equal(covered, 8)


def test_a_changed_winner_pin_is_refused() raises:
    """A changed record or restored consumer changes its digest."""
    var record = Path(_RECORD).read_text()
    assert_true(sha256_hex((record + " ").as_bytes()) != _RECORD_SHA256)
    var paths = List[String]()
    var texts = List[String]()
    restored_winner_pins(paths, texts)
    var changed = texts[0] + "\n"
    assert_true(
        sha256_hex(changed.as_bytes()) != sha256_hex(texts[0].as_bytes())
    )
    var border_paths = List[String]()
    var border_texts = List[String]()
    restored_border_pins(border_paths, border_texts)
    var domain_at = _find(border_paths, _DOMAIN)
    var domain = restored_domain_winner(border_texts[domain_at])
    assert_true(
        sha256_hex((domain + "\n").as_bytes()) != sha256_hex(domain.as_bytes())
    )
    var dispatch_at = _find(border_paths, _DISPATCH)
    var dispatch = restored_dispatch_winner(border_texts[dispatch_at])
    assert_true(
        sha256_hex((dispatch + "\n").as_bytes())
        != sha256_hex(dispatch.as_bytes())
    )
    var line = restored_rounded_line_winner()
    assert_true(
        sha256_hex((line + "\n").as_bytes()) != sha256_hex(line.as_bytes())
    )
    var arc = restored_rounded_arc_winner()
    assert_true(
        sha256_hex((arc + "\n").as_bytes()) != sha256_hex(arc.as_bytes())
    )
    var frozen = restored_frozen_arc_winner()
    assert_true(
        sha256_hex((frozen + "\n").as_bytes()) != sha256_hex(frozen.as_bytes())
    )
    var lane = restored_lane_invasion_winner()
    assert_true(
        sha256_hex((lane + "\n").as_bytes()) != sha256_hex(lane.as_bytes())
    )
    var junction = restored_junction_winner()
    assert_true(
        sha256_hex((junction + "\n").as_bytes())
        != sha256_hex(junction.as_bytes())
    )
    var cameras = restored_cameras_winner(restored_cameras())
    assert_true(
        sha256_hex((cameras + "\n").as_bytes())
        != sha256_hex(cameras.as_bytes())
    )
    var world = restored_world_winner(restored_world())
    assert_true(
        sha256_hex((world + "\n").as_bytes()) != sha256_hex(world.as_bytes())
    )
    var sensor = restored_sensor_winner(restored_sensor_view())
    assert_true(
        sha256_hex((sensor + "\n").as_bytes()) != sha256_hex(sensor.as_bytes())
    )
    var actors = restored_render_actor_winner(restored_render_actors())
    assert_true(
        sha256_hex((actors + "\n").as_bytes()) != sha256_hex(actors.as_bytes())
    )
    var opendrive = restored_opendrive_winner(restored_opendrive())
    assert_true(
        sha256_hex((opendrive + "\n").as_bytes())
        != sha256_hex(opendrive.as_bytes())
    )


def main() raises:
    """Run the winner pin predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
