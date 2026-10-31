# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the cloth solver and the cloak."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, UV, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.attire.cloth import (
    MAX_COLORS,
    Cloak,
    ClothSettings,
    ClothSolver,
    CloakCut,
    add_cloak,
    cloth_grid,
    color_constraints,
    glide,
    predict,
    relax_pair,
    settle,
)
from extensions.attire.apparel import wizard_robe
from extensions.attire.drape import dressed_colliders
from extensions.attire.kinds import FabricKind
from extensions.attire.outfit import Outfit, dress
from extensions.attire.springs import SpringCollider, nearest_on_segment
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_people import coarse_person
from units.si import Duration, SECOND


def _frame() -> Duration:
    """Return one thirtieth of a second."""
    return Duration(1.0 / 30.0, SECOND)


def _hanging(
    columns: Int, rows: Int, settings: ClothSettings = ClothSettings()
) raises -> ClothSolver:
    """Return a sheet hanging from its top row, one meter wide and long."""
    var grid = cloth_grid(
        Vector3(0, 0, 0),
        Vector3(1 / Float32(columns - 1), 0, 0),
        Vector3(0, 0, -1 / Float32(rows - 1)),
        columns,
        rows,
    )
    var pinned = List[Bool](length=columns * rows, fill=False)
    for c in range(columns):
        pinned[c] = True
    return ClothSolver(
        grid[0].copy(), pinned, grid[1].copy(), grid[2].copy(), settings
    )


def test_settings_check_their_ranges() raises:
    ClothSettings().check()
    var bad = ClothSettings()
    bad.substeps = 0
    with assert_raises(contains="substeps"):
        bad.check()
    bad.substeps = 2000
    with assert_raises(contains="substeps"):
        bad.check()
    bad = ClothSettings()
    bad.damping = 1
    with assert_raises(contains="damping"):
        bad.check()
    bad.damping = -0.1
    with assert_raises(contains="damping"):
        bad.check()
    bad = ClothSettings()
    bad.stretch = nan[DType.float32]()
    with assert_raises(contains="stretch"):
        bad.check()
    bad = ClothSettings()
    bad.bend = -1
    with assert_raises(contains="bend"):
        bad.check()
    bad = ClothSettings()
    bad.thickness = 2
    with assert_raises(contains="thickness"):
        bad.check()
    # The upper bound of each range is its own refusal.
    bad = ClothSettings()
    bad.stretch = 1
    with assert_raises(contains="stretch"):
        bad.check()
    bad = ClothSettings()
    bad.bend = 1
    with assert_raises(contains="bend"):
        bad.check()
    bad = ClothSettings()
    bad.thickness = -1
    with assert_raises(contains="thickness"):
        bad.check()


def test_constraints_are_colored_apart() raises:
    var grid = cloth_grid(
        Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0, -0.1, 0), 6, 5
    )
    var pairs = grid[1].copy()
    var colors = color_constraints(pairs, 30)
    var total = 0
    for color in colors:
        var seen = List[Bool](length=30, fill=False)
        for c in color:
            var i = pairs[2 * c]
            var j = pairs[2 * c + 1]
            assert_false(seen[i] or seen[j])
            seen[i] = True
            seen[j] = True
            total += 1
    assert_equal(total, len(pairs) // 2)
    assert_true(len(colors) <= 16)
    # A particle shared by more constraints than there are colors.
    var star = List[Int]()
    for k in range(MAX_COLORS + 1):
        star.append(0)
        star.append(k + 1)
    with assert_raises(contains="too many colors"):
        _ = color_constraints(star, MAX_COLORS + 2)
    var bad: List[List[Int]] = [[-1, 0], [0, -1], [5, 0], [0, 5]]
    for k in range(4):
        with assert_raises(contains="out of range"):
            _ = color_constraints(bad[k], 5)
    with assert_raises(contains="two or more"):
        _ = cloth_grid(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), 1, 4
        )


def test_a_sheet_hangs_from_its_pins_without_stretching() raises:
    var sheet = _hanging(8, 8)
    for _ in range(90):
        sheet.step(_frame())
    # It has swung down from the level; its top row has not moved.
    assert_true(sheet.points[63].y < -0.9)
    assert_equal(sheet.points[3].y, 0)
    # Rigid structural constraints and the tethers keep it from
    # stretching: the hem is no farther than a meter below the pins.
    assert_true(sheet.points[60].y > -1.02)
    for c in range(len(sheet.rests)):
        if sheet.bending[c]:
            continue
        var i = sheet.pairs[2 * c]
        var j = sheet.pairs[2 * c + 1]
        var length = (sheet.points[j] - sheet.points[i]).length()
        assert_true(length < sheet.rests[c] * 1.03)


def test_pins_move_their_rows() raises:
    var sheet = _hanging(4, 4)
    for c in range(4):
        sheet.pin(c, Vector3(Float32(c) / 3, 0.5, 0))
    sheet.step(_frame())
    assert_almost_equal(sheet.points[2].y, 0.5, atol=1e-6)
    with assert_raises(contains="No cloth particle"):
        sheet.pin(-1, Vector3(0, 0, 0))
    with assert_raises(contains="No cloth particle"):
        sheet.pin(16, Vector3(0, 0, 0))
    with assert_raises(contains="Only a pinned particle"):
        sheet.pin(8, Vector3(0, 0, 0))
    with assert_raises(contains="above zero"):
        sheet.step(Duration(-1, SECOND))
    with assert_raises(contains="one or more workers"):
        sheet.step(_frame(), 0)


def test_a_cloth_with_no_pin_still_meets_the_capsules() raises:
    # A falling sheet with no pin: each free particle is its own tether,
    # and the bar under it holds it off.
    var grid = cloth_grid(
        Vector3(0, 0, 0), Vector3(0.2, 0, 0), Vector3(0, 0, -0.2), 6, 6
    )
    var sheet = ClothSolver(
        grid[0].copy(),
        List[Bool](length=36, fill=False),
        grid[1].copy(),
        grid[2].copy(),
        ClothSettings(),
    )
    for k in range(sheet.count()):
        assert_equal(sheet.tethers[k], k)
    sheet.set_colliders(
        [Vector3(-1, -0.5, -0.5)], [Vector3(2, -0.5, -0.5)], [Float32(0.1)]
    )
    for _ in range(60):
        sheet.step(_frame())
    for k in range(sheet.count()):
        var p = sheet.points[k]
        var gap = Vector3(0, p.y + 0.5, p.z + 0.5).length()
        assert_true(gap >= 0.1 + sheet.settings.thickness - 1e-3)


def test_a_capsule_holds_the_cloth_off() raises:
    var sheet = _hanging(6, 6)
    # A bar across the sheet, half a meter down: the cloth drapes over it.
    sheet.set_colliders(
        [Vector3(-1, -0.5, -0.1)], [Vector3(2, -0.5, -0.1)], [Float32(0.1)]
    )
    for _ in range(60):
        sheet.step(_frame())
    for k in range(sheet.count()):
        var p = sheet.points[k]
        var gap = Vector3(0, p.y + 0.5, p.z + 0.1).length()
        assert_true(gap >= 0.1 + sheet.settings.thickness - 1e-3)
    with assert_raises(contains="two ends and a radius"):
        sheet.set_colliders([Vector3(0, 0, 0)], List[Vector3](), [Float32(0.1)])
    with assert_raises(contains="two ends and a radius"):
        sheet.set_colliders(
            [Vector3(0, 0, 0)], [Vector3(0, 0, 0)], List[Float32]()
        )


def test_many_threads_settle_the_cloth_as_one_does() raises:
    var settings = ClothSettings()
    settings.stretch = 1e-6
    settings.substeps = 2
    var serial = _hanging(40, 40, settings)
    var parallel = _hanging(40, 40, settings)
    for _ in range(3):
        serial.step(_frame(), 1)
        parallel.step(_frame(), 4)
    for k in range(serial.count()):
        assert_equal(serial.points[k].x, parallel.points[k].x)
        assert_equal(serial.points[k].y, parallel.points[k].y)
        assert_equal(serial.points[k].z, parallel.points[k].z)


def test_degenerate_constraints_are_skipped() raises:
    # Two pinned particles, and two free ones on one spot.
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, -1, 0),
        Vector3(0, -1, 0),
    ]
    var sheet = ClothSolver(
        points^,
        [True, True, False, False],
        [0, 1, 2, 3, 0, 2],
        [False, False, False],
        ClothSettings(),
    )
    sheet.step(_frame())
    assert_equal(sheet.points[1].x, 1)
    with assert_raises(contains="one pin flag"):
        _ = ClothSolver(
            [Vector3(0, 0, 0)],
            List[Bool](),
            List[Int](),
            List[Bool](),
            ClothSettings(),
        )
    with assert_raises(contains="two particles per constraint"):
        _ = ClothSolver(
            [Vector3(0, 0, 0)], [True], [0], List[Bool](), ClothSettings()
        )
    var bad = ClothSettings()
    bad.substeps = 0
    with assert_raises(contains="substeps"):
        _ = ClothSolver(
            [Vector3(0, 0, 0)], [True], List[Int](), List[Bool](), bad
        )


def test_a_cloak_hangs_from_the_shoulders_and_moves() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    scene.update()
    var cloak = add_cloak(scene, assets, person)
    var top = cloak.solver.points[0]
    var hem = cloak.solver.points[cloak.solver.count() - 1]
    assert_true(hem.y < top.y - 0.8)
    for _ in range(10):
        scene.update()
        cloak.step(scene, assets, _frame(), 2)
    # The pins stay at the shoulders; the mesh follows the cloth.
    assert_almost_equal(cloak.solver.points[0].y, top.y, atol=1e-4)
    ref placed = assets.geometries.get(cloak.geometry).attribute_view(
        String(POSITION)
    )
    var last = cloak.solver.count() - 1
    assert_equal(placed.vector3(last).y, cloak.solver.points[last].y)
    var cut = CloakCut()
    cut.fabric = FabricKind(42)
    with assert_raises(contains="named kind"):
        _ = add_cloak(scene, assets, person, cut)


def test_a_cloak_falls_over_a_robe_and_is_trimmed() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(wizard_robe())
    var over = dressed_colliders(
        person, outfit, dress(scene, assets, person, outfit)
    )
    scene.update()
    var cut = CloakCut(trim=Color(214, 170, 64))
    var cloak = add_cloak(scene, assets, person, cut, over)
    assert_equal(len(cloak.colliders), len(over))
    scene.update()
    # Every particle, each pin too, starts out of the colliders.
    for p in cloak.solver.points:
        for c in over:
            var world = scene.world_matrix(c.node)
            var a = world.transform_point(c.start)
            var b = world.transform_point(c.end)
            var d = (p - nearest_on_segment(p, a, b)).length()
            assert_true(d >= c.radius + cut.settings.thickness - 1e-3)
    # The hem and the edges take the trim; the middle takes the dye.
    ref mesh = assets.geometries.get(cloak.geometry)
    ref colors = mesh.attribute_view(String(COLOR))
    ref uv = mesh.attribute_view(String(UV))
    var edge = cloak.solver.count() - 1
    var middle = cut.columns // 2
    assert_true(colors.component(edge, 0) > colors.component(middle, 0))
    assert_true(colors.component(edge, 2) < colors.component(middle, 2) + 0.2)
    # The texture coordinates are in meters: the last column lies a
    # top's width from the first.
    assert_true(uv.component(cut.columns - 1, 0) > 0.2)
    assert_true(uv.component(cut.columns - 1, 0) < 0.6)
    for _ in range(4):
        scene.update()
        cloak.step(scene, assets, _frame(), 2)
    # A cloak without a trim is one dye throughout.
    var plain = add_cloak(scene, assets, person, CloakCut(folds=0))
    ref flat = assets.geometries.get(plain.geometry)
    ref hues = flat.attribute_view(String(COLOR))
    assert_almost_equal(hues.component(0, 0), hues.component(middle, 0))


def test_a_cut_s_folds_and_flare_are_checked() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    scene.update()
    with assert_raises(contains="folds must be zero or more"):
        _ = add_cloak(scene, assets, person, CloakCut(folds=-1))
    with assert_raises(contains="six columns"):
        _ = add_cloak(scene, assets, person, CloakCut(columns=13, folds=3))
    with assert_raises(contains="flare"):
        _ = add_cloak(scene, assets, person, CloakCut(flare=-0.5))
    with assert_raises(contains="flare"):
        _ = add_cloak(scene, assets, person, CloakCut(flare=11))


def test_the_shared_arithmetic_moves_one_particle_at_a_time() raises:
    # A pinned particle glides a share of the way to its target.
    var halfway = glide(Vector3(0, 0, 0), Vector3(2, 0, 0), 0.5)
    assert_almost_equal(halfway.x, 1)
    # A free particle keeps its damped velocity and falls.
    var next = predict(
        Vector3(1, 0, 0), Vector3(0, 0, 0), 0.5, Vector3(0, -0.1, 0)
    )
    assert_almost_equal(next.x, 1.5)
    assert_almost_equal(next.y, -0.1)
    # A stretched pair of equal weights closes evenly; a stiff one closes
    # all the way.
    var moved = relax_pair(Vector3(0, 0, 0), Vector3(2, 0, 0), 1, 1, 1, 0, 1)
    assert_almost_equal(moved[0].x, 0.5)
    assert_almost_equal(moved[1].x, 1.5)
    # A pinned end does not move.
    var held = relax_pair(Vector3(0, 0, 0), Vector3(2, 0, 0), 0, 1, 1, 0, 1)
    assert_equal(held[0].x, 0)
    assert_almost_equal(held[1].x, 1)
    # Two pinned ends, or two particles in one place, do not move.
    var both = relax_pair(Vector3(0, 0, 0), Vector3(2, 0, 0), 0, 0, 1, 0, 1)
    assert_equal(both[1].x, 2)
    var met = relax_pair(Vector3(1, 0, 0), Vector3(1, 0, 0), 1, 1, 1, 0, 1)
    assert_equal(met[0].x, 1)
    # A tether holds a particle within its reach.
    var pulled = settle(Vector3(3, 0, 0), Vector3(0, 0, 0), 1)
    assert_almost_equal(pulled.x, 1)
    var free = settle(Vector3(0.5, 0, 0), Vector3(0, 0, 0), 1)
    assert_equal(free.x, 0.5)


def test_an_empty_cloth_steps_and_draws_nothing() raises:
    assert_equal(len(color_constraints(List[Int](), 0)), 0)
    var scene = Scene()
    var assets = Assets()
    var node = scene.add(Object3D())
    scene.update()
    var solver = ClothSolver(
        List[Vector3](),
        List[Bool](),
        List[Int](),
        List[Bool](),
        ClothSettings(),
    )
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    var geometry = assets.geometries.add(mesh^)
    var cloak = Cloak(
        solver^,
        geometry,
        node,
        node,
        List[Vector3](),
        List[Int](),
        List[SpringCollider](),
        List[Int](),
    )
    cloak.step(scene, assets, Duration(1.0 / 60.0, SECOND), 2)
    assert_equal(assets.geometries.get(geometry).vertex_count(), 0)


def test_a_step_too_long_and_a_grid_one_row_deep_are_refused() raises:
    var grid = cloth_grid(
        Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0, -0.1, 0), 3, 3
    )
    var solver = ClothSolver(
        grid[0].copy(),
        List[Bool](length=9, fill=False),
        grid[1].copy(),
        grid[2].copy(),
        ClothSettings(),
    )
    with assert_raises(contains="step"):
        solver.step(Duration(1e7, SECOND), 1)
    # A setting changed after the cloth was made is refused at the step.
    solver.settings.substeps = 0
    with assert_raises(contains="substeps"):
        solver.step(Duration(0.01, SECOND), 1)
    with assert_raises(contains="two or more"):
        _ = cloth_grid(
            Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0, -0.1, 0), 3, 1
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
