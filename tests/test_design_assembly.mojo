# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the staged assembly views of `extensions.design.assembly`."""

from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from core.assets import Assets
from core.scene import Scene
from extensions.design.assembly import (
    Assembly,
    LEGEND_MAX,
    NO_RATIO,
    Part,
    add_assembly,
    draw_ratio_legend,
    orbit_eye,
    ratio_color,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from units.si import Length, METER


def _three_stages() raises -> Assembly:
    var a = Assembly()
    var gray = Color(120, 120, 120)
    a.add_box("footing", Vector3(0, 0, 0), Vector3(2, 0.3, 1), gray, 0, 0.4)
    a.add_box("wall", Vector3(0, 0.3, 0), Vector3(0.25, 2.5, 1), gray, 1, 0.9)
    a.add_box("beam", Vector3(0, 2.5, 0), Vector3(2, 2.7, 0.2), gray, 2)
    a.add(
        Part(
            "roof",
            Vector3(1, 3, 0),
            Vector3(2, 0.1, 1),
            gray,
            2,
            NO_RATIO,
            0.3,
            0.5,
        )
    )
    return a^


def test_stage_count_and_box_corners() raises:
    var a = _three_stages()
    assert_equal(a.stage_count(), 3)
    assert_equal(Assembly().stage_count(), 0)
    ref p = a.parts[1]
    assert_almost_equal(Float64(p.center.y), 1.4, atol=1e-6)
    assert_almost_equal(Float64(p.size.x), 0.25, atol=1e-6)


def test_build_state_selects_parts() raises:
    var a = _three_stages()
    var counts: List[Int] = []
    for build in [0.0, 0.5, 1.0, 1.25, 2.5, 3.0, 9.0]:
        var scene = Scene()
        var assets = Assets()
        counts.append(
            add_assembly(scene, assets, a, build, False, Length(2.0, METER))
        )
        assert_equal(len(scene.meshes), counts[len(counts) - 1])
    assert_equal(counts[0], 0)
    assert_equal(counts[1], 1)
    assert_equal(counts[2], 1)
    assert_equal(counts[3], 2)
    assert_equal(counts[4], 4)
    assert_equal(counts[5], 4)
    assert_equal(counts[6], 4)
    var scene = Scene()
    var assets = Assets()
    assert_equal(
        add_assembly(
            scene, assets, a, 3.0, True, Length(0.0, METER), first_stage=1
        ),
        3,
    )


def test_build_state_refuses_bad_inputs() raises:
    var a = _three_stages()
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="build state"):
        _ = add_assembly(scene, assets, a, -1.0, False, Length(0.0, METER))
    with assert_raises(contains="drop height"):
        _ = add_assembly(scene, assets, a, 1.0, False, Length(-1.0, METER))


def test_part_check() raises:
    var gray = Color(1, 2, 3)
    var a = Assembly()
    with assert_raises(contains="size must be positive"):
        a.add_box("flat", Vector3(0, 0, 0), Vector3(1, 0, 1), gray, 0)
    with assert_raises(contains="size must be positive"):
        a.add_box("flat", Vector3(0, 0, 0), Vector3(0, 1, 1), gray, 0)
    with assert_raises(contains="size must be positive"):
        a.add_box("flat", Vector3(0, 0, 0), Vector3(1, 1, 0), gray, 0)
    with assert_raises(contains="stage"):
        a.add_box("early", Vector3(0, 0, 0), Vector3(1, 1, 1), gray, -1)
    with assert_raises(contains="opacity"):
        a.add(
            Part(
                "ghost",
                Vector3(0, 0, 0),
                Vector3(1, 1, 1),
                gray,
                0,
                NO_RATIO,
                0,
                0,
            )
        )


def test_ratio_colors_and_legend() raises:
    assert_true(ratio_color(NO_RATIO) == Color(150, 154, 160))
    var low = ratio_color(0.0)
    var fail = ratio_color(1.0)
    assert_true(low.g > low.r)
    assert_true(fail.r > fail.g)
    var frame = Framebuffer(40, 20, Color(0, 0, 0))
    draw_ratio_legend(frame, 2, 2, 30, 6)
    assert_true(frame.get_pixel(2, 2) == Color(30, 34, 40))
    assert_true(frame.get_pixel(3, 4) == ratio_color(LEGEND_MAX / 29))
    var tick = Int(Float64(1.0) / LEGEND_MAX * 29 + 0.5)
    assert_true(frame.get_pixel(2 + tick, 4) == Color(255, 255, 255))
    with assert_raises(contains="2 by 2"):
        draw_ratio_legend(frame, 0, 0, 1, 5)
    with assert_raises(contains="fit inside"):
        draw_ratio_legend(frame, 30, 0, 20, 5)


def test_orbit_eye() raises:
    var e = orbit_eye(Vector3(1, 2, 3), 10, 5, Float32(pi / 2))
    assert_almost_equal(Float64(e.x), 1, atol=1e-5)
    assert_almost_equal(Float64(e.y), 7, atol=1e-5)
    assert_almost_equal(Float64(e.z), -7, atol=1e-5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
