# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Empty and degenerate inputs to the species helpers.

Each helper reads a table that its species' callers fill. These checks
give it an empty table instead, and characterize the result: an empty
list, a far distance, no solids, or the refusal of the solid it would
make. They do not say that the input describes a valid animal.
"""

from extensions.animals.coat import Palette
from extensions.animals.options import (
    ADULT,
    CROWD,
    FEMALE,
    MALE,
    Sex,
    Variant,
    animal_options,
    body_random,
)
from extensions.animals.registry import (
    CHICKEN,
    LION,
    SHARK,
    SHEEP,
    SPIDER,
    SpeciesId,
    species_rig,
    species_traits,
)
from extensions.animals.species.bird_rig import Feather, FeatherFrame
from extensions.animals.species.cat import _line
from extensions.animals.species.chicken import (
    _Stack,
    _bed,
    _box,
    _plate,
    _shield,
)
from extensions.animals.species.fish import (
    _Geo,
    _Median,
    _caudal_rays,
    _median_rays,
    _pectoral_rays,
    _pelvic_rays,
    _skin_x,
)
from extensions.animals.species.horse import _bone_list
from extensions.animals.species.lion import _sculpt_mane
from extensions.animals.species.rat import _toes
from extensions.animals.species.shark import (
    _caudal_edge,
    _fin_color,
    _geo,
    _line_dist,
    _median_fin,
    _taper_fin,
)
from extensions.animals.species.sheep import _locks, _neck_s
from extensions.animals.species.snake import _pchip_slopes, _seg2
from extensions.animals.species.spider import (
    _Dims,
    _chain,
    _leg_chain,
    _palp_chain,
)
from extensions.animals.species.swimmer_rig import (
    fan_rays,
    fin_outline,
    fin_ray_coords,
)
from extensions.animals.traits import Traits
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId
from extensions.sdf.vector import V3
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _draw(species: SpeciesId, sex: Sex = FEMALE) raises -> Traits:
    var options = animal_options(
        1, quality=CROWD, sex=sex, age=ADULT, variant=Variant(0)
    )
    var r = body_random(options.seed)
    return species_traits(species, r, options)


def test_fewer_than_two_fin_rays_have_no_outline_or_coordinates() raises:
    for count in range(2):
        var lengths = List[Float64](length=count, fill=0.3)
        var rays = fan_rays(0, 0, 1, 0, 30, 60, lengths)
        assert_equal(len(rays), count * 4)
        assert_equal(len(fin_outline(rays, 0.02, 0.1)), 0)
        for point in [V3(-0.1, 0.2, 0), V3(0.3, -0.2, 0)]:
            var at = fin_ray_coords(rays, point.x, point.y)
            assert_equal(at.phase, 0.0)
            assert_equal(at.along, 0.0)


def test_empty_fish_ray_tables_give_no_rays() raises:
    var g = _Geo(0, 1.0, 1.0)
    var none = _Median(0.4, 0.8, 0, 100, 150, 0.2, 0.1, 0, False, False)
    assert_equal(len(_median_rays(g, none, True)), 0)
    g.v.c_n = 0
    g.v.p_n = 0
    g.v.v_n = 0
    assert_equal(len(_caudal_rays(g)), 0)
    assert_equal(len(_pectoral_rays(g)), 0)
    assert_equal(len(_pelvic_rays(g)), 0)
    # No body section lies near a station past the tail: no skin there.
    assert_true(_skin_x(g, 5.0, 0.0) <= 1e-9)


def test_empty_mammal_tables_give_no_solids_and_far_lines() raises:
    var m = SdfModel()
    assert_equal(len(_bone_list(m, BoneId(0))), 0)
    _toes(m, BoneId(0), V3(0, 0, 0), V3(0, 0, 1), 1.0, [], 0.0)
    assert_equal(len(m.prims), 0)
    var o = V3(0, 0, 0)
    assert_equal(
        _line(o, V3(1, 0, 0), 1.0, o, o, o, o, o, o, List[Float64]()), 1e9
    )


def test_short_snake_curves_have_no_slope_and_no_distance() raises:
    assert_equal(len(_pchip_slopes(List[Float64](), List[Float64]())), 0)
    var one = _pchip_slopes([1.0], [2.0])
    assert_equal(len(one), 1)
    assert_equal(one[0], 0.0)
    var unpaired = _pchip_slopes([0.0, 1.0], [2.0])
    assert_equal(len(unpaired), 2)
    assert_equal(_seg2(0.0, 0.0, List[V3](), List[Float64]()), 1e9)


def test_empty_shark_outlines_give_no_fin() raises:
    var t = _draw(SHARK)
    var g = _geo(t)
    var m = SdfModel()
    var o = V3(0, 0, 0)
    with assert_raises(contains="three or more points"):
        _taper_fin(
            m,
            "dorsal1",
            BoneId(0),
            o,
            V3(0, 0, -1),
            V3(0, 1, 0),
            List[Float64](),
            0.0,
            0.0,
            0.01,
            0.002,
            0.01,
        )
    var pts = List[Float64]()
    _caudal_edge(pts, g, o, V3(1, 1, 0), 0, 0.0, False)
    assert_equal(len(pts), 0)
    assert_equal(_line_dist(0.0, 0.0, List[Float64](), List[Float64]()), 1e9)
    g.d1_poly = List[Float64]()
    var fin = _median_fin(g, 0)
    assert_equal(len(fin[1]), 0)
    assert_equal(fin[2], 0.0)
    assert_equal(fin[3], 0.0)
    # A pectoral fin with no outline still paints from the body's colors.
    g = _geo(t)
    g.p_poly = List[Float64]()
    var paint = _fin_color(
        Palette(), t, g, "pectoral", "pectoralL", o, V3(0, -1, 0), o
    )
    assert_true(paint[1] <= 1.0)


def test_degenerate_chicken_wings_fit_no_plane() raises:
    var st = _Stack()
    assert_equal(st.near(0.0, 0.0, -1.0), -1e30)
    var box = _box(List[Float64]())
    assert_equal(box[0].x, 1e9)
    assert_equal(box[1].x, -1e9)
    # A wing of no size covers no lattice point: no fitted plane.
    var t = _draw(CHICKEN)
    t.set("wingK", 0.0)
    var shield = _shield(t)
    assert_equal(shield.plane.x, -1e300)
    assert_equal(shield.lid_plane.x, -1e300)
    var rig = species_rig(CHICKEN, _draw(CHICKEN))
    var m = SdfModel()
    with assert_raises(contains="three or more points"):
        _plate(m, rig, "L", List[Float64](), V3(0, 0, 0), 2.0, 1.0, 0.5, True)
    _bed(
        m,
        rig,
        List[FeatherFrame](),
        List[Feather](),
        List[Float64](),
        List[Float64](),
    )
    assert_equal(len(m.prims), 0)


def test_a_sheep_without_fleece_grows_no_locks() raises:
    var t = _draw(SHEEP)
    var m = SdfModel()
    _locks(m, t, List[Int](), List[Bool](), 1.0, False)
    assert_equal(len(m.prims), 0)
    # Far below the cut, with no ears, only the cut counts.
    assert_true(_neck_s(V3(0, -10, -10), List[V3]()) < -1.0)


def test_a_mane_too_small_for_one_lock_keeps_its_volume() raises:
    var t = _draw(LION, MALE)
    var rig = species_rig(LION, t)
    var m = SdfModel()
    # Fourteen locks less twenty for each unit of shrinkage round to none.
    _sculpt_mane(m, rig, t, -0.72)
    assert_true(len(m.prims) > 0)
    for p in m.prims:
        assert_equal(m.tags[p.tag.value], "mane")


def test_unsolvable_spider_chains_keep_only_their_base() raises:
    var base = V3(1, 2, 3)
    var bare = _chain(base, 0.0, List[Float64](), List[Float64](), 0, 0.0)
    assert_equal(len(bare), 1)
    assert_equal(bare[0].y, 2.0)
    var unpaired = _chain(base, 0.0, [10.0], [1.0, 1.0], 1, 0.0)
    assert_equal(len(unpaired), 1)
    assert_equal(len(_chain(base, 0.0, [10.0], [1.0], -1, 0.0)), 1)
    var d = _Dims(_draw(SPIDER))
    d.seg = List[Float64]()
    d.palp_seg = List[Float64]()
    assert_equal(len(_leg_chain(d, 0)), 1)
    assert_equal(len(_palp_chain(d)), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
