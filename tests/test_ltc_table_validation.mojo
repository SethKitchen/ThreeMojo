# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Both LTC tables must be complete before resolving rectangle lights."""

from core.object3d import Object3D
from core.scene import Scene
from lights.light import rect_area_light
from lights.lighting import Lighting
from lights.ltc import LTC_FLOATS, LtcTables
from render.framebuffer import Color
from std.testing import TestSuite, assert_equal, assert_raises


def _tables() raises -> LtcTables:
    return LtcTables(
        List[Float32](length=LTC_FLOATS, fill=0),
        List[Float32](length=LTC_FLOATS, fill=0),
    )


def _scene() raises -> Scene:
    var scene = Scene()
    scene.add_light(
        rect_area_light(Color(255, 255, 255), scene.add(Object3D()))
    )
    scene.update()
    return scene^


def test_missing_or_truncated_first_tables_are_not_loaded() raises:
    for empty in [False, True]:
        var tables = _tables()
        if empty:
            tables.first.clear()
        else:
            _ = tables.first.pop()
        assert_equal(tables.is_loaded(), False)
        with assert_raises(contains="LTC tables"):
            _ = Lighting(_scene(), ltc=tables^)


def test_missing_or_truncated_second_tables_are_not_loaded() raises:
    for empty in [False, True]:
        var tables = _tables()
        if empty:
            tables.second.clear()
        else:
            _ = tables.second.pop()
        assert_equal(tables.is_loaded(), False)
        with assert_raises(contains="LTC tables"):
            _ = Lighting(_scene(), ltc=tables^)


def test_complete_tables_are_accepted_and_empty_tables_remain_absent() raises:
    assert_equal(LtcTables().is_loaded(), False)
    var lighting = Lighting(_scene(), ltc=_tables())
    assert_equal(lighting.ltc.is_loaded(), True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
