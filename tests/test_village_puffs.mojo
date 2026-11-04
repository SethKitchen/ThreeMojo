# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Puffs of smoke and dust: where they are, and how they are drawn."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from extensions.building.material import brick
from extensions.vegetation.ground import Ground
from extensions.village.house import HouseParameters, house_lot, house_model
from extensions.village.house_view import stand_house
from extensions.village.puffs import (
    DUST_TAN,
    NEAREST,
    Puff,
    SMOKE_GRAY,
    SMOKE_LIFE,
    SMOKE_PUFFS,
    chimney_smoke,
    draw_puffs,
    dust_puffs,
)
from extensions.village.surfaces import house_looks
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, RADIAN, Angle, Length


def test_smoke_rises_from_the_pot_drifts_and_fades() raises:
    var top = Vector3(2, 6, -3)
    var wind = Vector3(0.5, 0, 0)
    var puffs = chimney_smoke(top, 3, wind, 1)
    assert_equal(len(puffs), SMOKE_PUFFS)
    for puff in puffs:
        assert_true(puff.at.y >= top.y)
        assert_true(puff.opacity >= 0 and puff.opacity <= 0.75)
        assert_true(puff.radius >= 0.2)
        assert_true(puff.color == SMOKE_GRAY)
    # A puff that has risen far has drifted downwind and grown.
    var high = puffs[0]
    for puff in puffs:
        if puff.at.y > high.at.y:
            high = puff
    assert_true(high.at.x > top.x)
    assert_true(high.radius > 0.6)
    # The smoke repeats after a puff's life, and a time before zero too.
    var later = chimney_smoke(top, 3 + SMOKE_LIFE, wind, 1)
    assert_almost_equal(later[0].at.y, puffs[0].at.y, atol=1e-3)
    _ = chimney_smoke(top, -2.5, wind, 1)
    # Another chimney puffs out of step.
    var other = chimney_smoke(top, 3, wind, 2)
    assert_true(other[0].at.y != puffs[0].at.y)


def test_dust_rises_from_a_foot_and_settles() raises:
    var foot = Vector3(1, 0, 1)
    assert_equal(len(dust_puffs(foot, 2, -0.1, 3)), 0)
    assert_equal(len(dust_puffs(foot, 2, 1, 3)), 0)
    var dust = dust_puffs(foot, 2, 0.3, 3)
    assert_equal(len(dust), 5)
    for puff in dust:
        assert_true(puff.color == DUST_TAN)
        assert_true(puff.at.y > foot.y)
        assert_true(puff.opacity > 0)


def _camera() raises -> PerspectiveCamera:
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 1, 5), Vector3(0, 1, 0))
    return camera^


def test_a_puff_shows_in_front_and_hides_behind() raises:
    var camera = _camera()
    var image = Framebuffer(32, 32, Color(0, 0, 0, 255))
    var white = Puff(Vector3(0, 1, 0), 1, 1, Vector3(1, 1, 1))
    var faint = Puff(Vector3(0, 1, -1), 1, 0.5, Vector3(1, 1, 1))
    var none = Puff(Vector3(0, 1, 0), 1, 0, Vector3(1, 1, 1))
    var behind = Puff(Vector3(0, 1, 20), 1, 1, Vector3(1, 1, 1))
    var close = Puff(Vector3(0, 1, 5 - NEAREST), 0.1, 1, Vector3(1, 1, 1))
    var aside = Puff(Vector3(60, 1, 0), 1, 1, Vector3(1, 1, 1))
    var far = Puff(Vector3(0, 1, -200), 1, 1, Vector3(1, 1, 1))
    var shown = draw_puffs(
        image, [white, faint, none, behind, close, aside, far], camera, 1
    )
    assert_equal(shown, 2)
    var middle = image.get_pixel(16, 16)
    assert_true(middle.r > 150)
    # The rim is fainter than the middle.
    assert_true(image.get_pixel(16, 3).r < middle.r)
    # A wall nearer than the puff hides it.
    var walled = Framebuffer(32, 32, Color(0, 0, 0, 255))
    for k in range(len(walled.depth)):
        walled.depth[k] = -0.99
    assert_equal(draw_puffs(walled, [white], camera, 1), 1)
    assert_equal(walled.get_pixel(16, 16).r, 0)
    # At night a puff is dim.
    var night = Framebuffer(32, 32, Color(0, 0, 0, 255))
    _ = draw_puffs(night, [white], camera, 0.2)
    assert_true(night.get_pixel(16, 16).r < middle.r)


def test_puffs_are_checked() raises:
    var camera = _camera()
    var image = Framebuffer(8, 8, Color(0, 0, 0, 255))
    with assert_raises(contains="light"):
        _ = draw_puffs(image, List[Puff](), camera, 2)
    var bare = Framebuffer(8, 8, Color(0, 0, 0, 255))
    bare.depth = List[Float32]()
    with assert_raises(contains="depth"):
        _ = draw_puffs(bare, List[Puff](), camera, 1)


def test_a_house_with_a_hearth_has_a_chimney_pot() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var house = HouseParameters(
        "cottage", Length(7.0, METER), Length(5.0, METER), 1, brick()
    )
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var standing = stand_house(
        scene,
        assets,
        looks,
        house,
        house_model(house),
        lot,
        Ground(hill_height=Length(0.0, METER)),
    )
    assert_true(Bool(standing.chimney))
    assert_true(standing.chimney.value().y > 3)
    var flat = HouseParameters(
        "shed",
        Length(7.0, METER),
        Length(5.0, METER),
        1,
        brick(),
        pitch=Angle(0.0, DEGREE),
    )
    var flat_scene = Scene()
    var bare = stand_house(
        flat_scene,
        assets,
        looks,
        flat,
        house_model(flat),
        house_lot(flat, 0, 0, Angle(0.0, RADIAN)),
        Ground(hill_height=Length(0.0, METER)),
    )
    assert_false(Bool(bare.chimney))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
