# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.parts`, the parts of a scanned place.

The site is a grid of half-meter voxels on a ground layer: a solid block,
a hollow box, a pillar, an overhang and one floating voxel. Each part's
volume, area, mass, inertia and footing has a closed form. The pillar's
tip angle is checked in `extensions.physics`: leaned less than it, the
pillar falls back; leaned more, it falls over.

The slope of `tests/_scan_slope.mojo` has a building whose walls stand on
ground that rises under them. It is cut above the ground that
`extensions.scan.terrain` finds, and it stands on its bed.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    packed_band,
    write_covariance,
)
from extensions.physics.body import RigidBody, STATIC
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld
from extensions.scan.colliders import add_scan_collider, collision_triangles
from extensions.scan.frame import (
    SCALE_DECLARED,
    SCAN_POSITIVE_Y,
    SCAN_POSITIVE_Z,
    ScanFrame,
)
from extensions.scan.occupancy import OccupancyGrid
from extensions.scan.parts import (
    ScanParts,
    PART_SHELL,
    PART_SOLID,
    PartFill,
    PartOptions,
    part_area,
    part_bed,
    part_body,
    part_footing,
    part_grid,
    part_hull,
    part_mass,
    part_splats,
    scan_parts,
    scan_parts_on,
)
from extensions.scan.terrain import (
    GroundSurface,
    TerrainOptions,
    flat_ground,
    ground_grid,
    terrain_ground,
)
from generators.utils import Vec3d
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import atan2, cos, inf, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._scan_slope import slope_area, slope_site, slope_step
from units.si import (
    Acceleration64,
    Angle64,
    CUBIC_METER,
    DEGREE,
    Density64,
    KILOGRAM,
    KILOGRAM_PER_CUBIC_METER,
    KILOGRAM_SQUARE_METER,
    Length,
    Length64,
    Mass,
    METER,
    METER_PER_SECOND_SQUARED,
    PASCAL,
    RADIAN,
    SECOND,
    SQUARE_METER,
    Duration,
)

comptime EDGE = 0.5
comptime CONCRETE = 2400.0
comptime GRAVITY = 9.80665


def _fill(
    mut grid: OccupancyGrid,
    i0: Int,
    i1: Int,
    j0: Int,
    j1: Int,
    k0: Int,
    k1: Int,
):
    """Make a box of voxels solid, ends included."""
    for k in range(k0, k1 + 1):
        for j in range(j0, j1 + 1):
            for i in range(i0, i1 + 1):
                grid.weights[grid.index(i, j, k)] = 1


def _site() raises -> OccupancyGrid:
    """Return the site of the module docstring."""
    var grid = OccupancyGrid(
        Vec3d(0, 0, 0), Length64(EDGE, METER), 20, 12, 12, 0.5
    )
    _fill(grid, 0, 19, 0, 11, 0, 0)
    # A solid block, 2.5 m by 2.5 m by 2 m: 100 voxels.
    _fill(grid, 2, 6, 2, 6, 1, 4)
    # A hollow box, 2 m on a side: 64 voxels, 8 of them hollow.
    _fill(grid, 15, 18, 2, 5, 1, 4)
    for k in range(2, 4):
        for j in range(3, 5):
            for i in range(16, 18):
                grid.weights[grid.index(i, j, k)] = 0
    # A pillar, 1 m by 1 m by 5 m: 40 voxels.
    _fill(grid, 12, 13, 5, 6, 1, 10)
    # An overhang: a post and an arm out from its top, 13 voxels.
    _fill(grid, 2, 2, 9, 9, 1, 6)
    _fill(grid, 3, 9, 9, 9, 6, 6)
    # A floater.
    grid.weights[grid.index(10, 10, 8)] = 1
    return grid^


def _options() -> PartOptions:
    """Return options with the ground at layer 0."""
    return PartOptions(0, 8)


def test_the_site_has_four_parts_by_size() raises:
    """The block, the hollow box, the pillar and the overhang; no floater."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    assert_equal(len(parts.parts), 4)
    assert_equal(parts.parts[0].count(), 100)
    assert_equal(parts.parts[1].count(), 56)
    assert_equal(parts.parts[2].count(), 40)
    assert_equal(parts.parts[3].count(), 13)
    assert_equal(parts.labels[grid.index(10, 10, 8)], -1)
    assert_equal(parts.labels[grid.index(0, 0, 0)], -1)
    assert_equal(parts.labels[grid.index(4, 4, 2)], 0)
    assert_equal(parts.labels[grid.index(12, 5, 10)], 2)
    var region = parts.parts[0].region(grid)
    assert_true(region.low == Vec3d(1, 1, 0.5))
    assert_true(region.high == Vec3d(3.5, 3.5, 2.5))
    assert_almost_equal(parts.parts[0].volume(grid).to(CUBIC_METER), 12.5)


def test_with_no_ground_the_ground_is_a_part() raises:
    """At ground -1, the ground joins every part that stands on it."""
    var grid = _site()
    var parts = scan_parts(grid, PartOptions(-1, 1))
    assert_equal(len(parts.parts), 2)
    assert_equal(parts.parts[0].count(), 240 + 100 + 56 + 40 + 13)
    assert_equal(parts.parts[1].count(), 1)


def test_a_part_has_its_outer_area_and_its_own_grid() raises:
    """The block's 130 outer faces, and a grid that holds it alone."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    assert_almost_equal(part_area(grid, parts, 0).to(SQUARE_METER), 32.5)
    # The hollow box's faces inside face its hollow: 24 more.
    assert_almost_equal(
        part_area(grid, parts, 1).to(SQUARE_METER), (96 + 24) * EDGE * EDGE
    )
    var alone = part_grid(grid, parts, 0)
    assert_equal(alone.nx, 5)
    assert_equal(alone.ny, 5)
    assert_equal(alone.nz, 4)
    assert_equal(alone.solid_count(), 100)
    assert_true(alone.origin == Vec3d(1, 1, 0.5))
    # A box's faces merge into six rectangles of two triangles each.
    assert_equal(len(collision_triangles(alone)), 12)


def test_a_solid_block_weighs_as_a_box() raises:
    """The voxel sums give a box's mass, center and inertia exactly."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    var mass = part_mass(
        grid,
        parts,
        0,
        Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER),
        PART_SHELL,
    )
    var m = 12.5 * CONCRETE
    assert_almost_equal(mass.mass.to(KILOGRAM), m)
    assert_true(mass.center == Vec3d(2.25, 2.25, 1.5))
    assert_almost_equal(
        mass.xx.to(KILOGRAM_SQUARE_METER),
        m / 12 * (2.5 * 2.5 + 2 * 2),
        rtol=1e-12,
    )
    assert_almost_equal(
        mass.zz.to(KILOGRAM_SQUARE_METER), m / 12 * (2.5 * 2.5 * 2), rtol=1e-12
    )
    assert_almost_equal(mass.xy.to(KILOGRAM_SQUARE_METER), 0, atol=1e-6)
    assert_almost_equal(mass.yz.to(KILOGRAM_SQUARE_METER), 0, atol=1e-6)
    assert_true(mass.fill == PART_SHELL)


def test_a_hollow_box_weighs_its_shell_or_its_whole() raises:
    """The shell leaves out the hollow; the solid counts it."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    var density = Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER)
    var shell = part_mass(grid, parts, 1, density, PART_SHELL)
    var solid = part_mass(grid, parts, 1, density, PART_SOLID)
    var voxel = EDGE * EDGE * EDGE * CONCRETE
    assert_almost_equal(shell.mass.to(KILOGRAM), 56 * voxel)
    assert_almost_equal(solid.mass.to(KILOGRAM), 64 * voxel)
    assert_true(shell.center == solid.center)
    # The overhang encloses nothing: its solid is its shell.
    var open = part_mass(grid, parts, 3, density, PART_SOLID)
    assert_almost_equal(open.mass.to(KILOGRAM), 13 * voxel)
    assert_true(open.xz.to(KILOGRAM_SQUARE_METER) != 0)


def test_a_part_bears_on_its_lowest_layer() raises:
    """Area, pressure, margin and tip angle of the block and the pillar."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    var density = Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER)
    var gravity = Acceleration64(GRAVITY, METER_PER_SECOND_SQUARED)
    var block = part_footing(
        grid, parts, 0, part_mass(grid, parts, 0, density, PART_SHELL), gravity
    )
    assert_equal(block.base, 1)
    assert_almost_equal(block.area.to(SQUARE_METER), 6.25)
    assert_almost_equal(
        block.pressure.to(PASCAL), 12.5 * CONCRETE * GRAVITY / 6.25
    )
    assert_almost_equal(block.margin.to(METER), 1.25)
    assert_almost_equal(block.tip.to(RADIAN), atan2(1.25, 1.0))
    assert_true(block.stands())
    var pillar = part_footing(
        grid, parts, 2, part_mass(grid, parts, 2, density, PART_SHELL), gravity
    )
    assert_almost_equal(pillar.margin.to(METER), 0.5)
    assert_almost_equal(pillar.tip.to(RADIAN), atan2(0.5, 2.5))
    var overhang = part_footing(
        grid, parts, 3, part_mass(grid, parts, 3, density, PART_SHELL), gravity
    )
    assert_true(overhang.margin.to(METER) < 0)
    assert_true(overhang.tip.to(RADIAN) < 0)
    assert_false(overhang.stands())


def test_a_hull_holds_the_corners_of_the_box() raises:
    """A box's hull is its eight corners."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    var hull = part_hull(grid, parts, 0)
    assert_equal(len(hull), 8)
    var found = False
    for point in hull:
        found = found or point == Vec3d(3.5, 3.5, 2.5)
    assert_true(found)


def _lean(angle: Float64) raises -> Float64:
    """Lean the pillar about its base's edge, and return how far it leans
    after two seconds, in degrees."""
    var grid = _site()
    var parts = scan_parts(grid, _options())
    var mass = part_mass(
        grid,
        parts,
        2,
        Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER),
        PART_SHELL,
    )
    var body = part_body(grid, parts, 2, mass, PhysicsMaterial.default())
    # Turn about the x axis through the base's edge at y = 3.5, z = 0.5.
    # A negative turn about x lifts the base's far edge and moves the top
    # toward the edge it turns about.
    var a = -angle * 3.141592653589793 / 180
    var pivot = Vec3d(mass.center.x, 3.5, 0.5)
    var r = mass.center - pivot
    var turned = Vec3d(
        r.x, r.y * cos(a) - r.z * sin(a), r.y * sin(a) + r.z * cos(a)
    )
    body.position = (pivot + turned).vector3()
    body.rotation = Quaternion(Float32(sin(a / 2)), 0, 0, Float32(cos(a / 2)))
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, Float32(-GRAVITY))
    var ground = RigidBody(
        STATIC,
        Shape.box(Length(10, METER), Length(6, METER), Length(0.25, METER)),
        Mass(0, KILOGRAM),
        Vector3(5, 3, 0.25),
        Quaternion.identity(),
    )
    _ = world.add_body(ground^)
    var id = world.add_body(body^)
    for _ in range(120):
        world.step(Duration(1.0 / 60, SECOND))
    var q = world.bodies[id.value].rotation
    return 2 * atan2(Float64(abs(q.x)), Float64(q.w)) * 180 / 3.141592653589793


def test_a_pillar_stands_below_its_tip_angle_and_falls_above_it() raises:
    """The tip angle from `part_footing` is where physics tips it."""
    # The tip angle is atan(0.5 / 2.5), 11.3 degrees.
    assert_true(_lean(6) < 3)
    assert_true(_lean(17) > 30)


def _scan() raises -> List[Float32]:
    """Return the centers of four splats: in the block, in the pillar, in
    the ground, and in the floater."""
    return [2.0, 2.0, 1.5, 6.25, 2.75, 4.0, 5.0, 5.0, 0.25, 5.25, 5.25, 4.25]


def test_a_part_takes_its_splats_with_their_harmonics() raises:
    """The block's splat is copied, bytes and all; others are left."""
    var centers = _scan()
    var covariances = List[Float32](length=24, fill=0)
    for index in range(4):
        write_covariance(covariances, index * 6, 0.1, 0.1, 0.1, 0, 0, 0, 1)
    var colors: List[UInt8] = [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
    ]
    var band = packed_band(4, 1)
    for at in range(len(band)):
        band[at] = UInt8(at)
    var geometry = create_gaussian_splat_geometry(
        centers^, covariances^, colors^, band^
    )
    var frame = ScanFrame(
        SCAN_POSITIVE_Z,
        SCAN_POSITIVE_Y,
        Length64(1, METER),
        SCALE_DECLARED,
        Angle64(0, RADIAN),
        Vec3d(0, 0, 0),
    )
    var grid = _site()
    var parts = scan_parts(grid, _options())
    var block = part_splats(geometry, frame, grid, parts, 0, 0)
    assert_equal(block.count(), 1)
    assert_equal(block.centers[0], 2.0)
    assert_equal(block.colors[3], 4)
    assert_equal(block.spherical_harmonics_degree(), 1)
    for at in range(len(block.sh1)):
        assert_equal(block.sh1[at], geometry.sh1[at])
    var pillar = part_splats(geometry, frame, grid, parts, 2, 1)
    assert_equal(pillar.count(), 1)
    assert_equal(pillar.colors[0], 5)
    assert_equal(len(pillar.sh1), len(geometry.sh1) // 4)
    with assert_raises(contains="no splat is part 1's"):
        _ = part_splats(geometry, frame, grid, parts, 1, 0)
    with assert_raises(contains="a reach is 0 or more"):
        _ = part_splats(geometry, frame, grid, parts, 0, -1)


def test_what_cannot_be_cut_or_weighed_is_refused() raises:
    """A ground past the grid, no voxels, no part, no fill, no density and
    no gravity are refused."""
    var grid = _site()
    with assert_raises(contains="ground layer must be -1 to 11"):
        _ = scan_parts(grid, PartOptions(12, 1))
    with assert_raises(contains="ground layer must be -1 to 11"):
        _ = scan_parts(grid, PartOptions(-2, 1))
    with assert_raises(contains="one voxel at least"):
        _ = scan_parts(grid, PartOptions(0, 0))
    var parts = scan_parts(grid, _options())
    with assert_raises(contains="there is no part 4 of 4"):
        _ = part_area(grid, parts, 4)
    with assert_raises(contains="there is no part -1 of 4"):
        _ = part_grid(grid, parts, -1)
    var density = Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER)
    with assert_raises(contains="a fill is 0 or 1, not 2"):
        _ = part_mass(grid, parts, 0, density, PartFill(2))
    for bad in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        with assert_raises(contains="density must be positive"):
            _ = part_mass(
                grid,
                parts,
                0,
                Density64(bad, KILOGRAM_PER_CUBIC_METER),
                PART_SHELL,
            )
    var mass = part_mass(grid, parts, 0, density, PART_SHELL)
    with assert_raises(contains="gravity must be positive"):
        _ = part_footing(
            grid, parts, 0, mass, Acceleration64(0, METER_PER_SECOND_SQUARED)
        )
    with assert_raises(contains="there is no part 9"):
        _ = part_hull(grid, parts, 9)


def _shapes() raises -> OccupancyGrid:
    """Return a grid of one-meter voxels with no ground: a lone voxel, a
    part on an L-shaped base, a cup open at the top and a stair, found in
    that order and largest last but one."""
    var grid = OccupancyGrid(Vec3d(0, 0, 0), Length64(1, METER), 14, 4, 4, 0.5)
    _fill(grid, 0, 0, 0, 0, 0, 0)
    _fill(grid, 3, 3, 0, 0, 0, 1)
    _fill(grid, 2, 2, 1, 1, 0, 1)
    _fill(grid, 3, 3, 1, 1, 1, 1)
    _fill(grid, 6, 9, 0, 3, 0, 2)
    _fill(grid, 7, 8, 1, 2, 1, 2)
    for k in range(1, 3):
        for j in range(1, 3):
            for i in range(7, 9):
                grid.weights[grid.index(i, j, k)] = 0
    _fill(grid, 12, 13, 0, 0, 0, 0)
    _fill(grid, 13, 13, 0, 0, 1, 1)
    return grid^


def test_parts_found_small_first_are_put_in_order() raises:
    """A larger part found later comes first, and each shape weighs and
    stands as it should."""
    var grid = _shapes()
    var parts = scan_parts(grid, PartOptions(-1, 1))
    assert_equal(len(parts.parts), 4)
    assert_equal(parts.parts[0].count(), 40)
    assert_equal(parts.parts[1].count(), 5)
    assert_equal(parts.parts[2].count(), 3)
    assert_equal(parts.parts[3].count(), 1)
    # The lone voxel is at the grid's corner: all six of its faces count.
    assert_almost_equal(part_area(grid, parts, 3).to(SQUARE_METER), 6)
    var density = Density64(1000, KILOGRAM_PER_CUBIC_METER)
    # The cup is open at the top, and the stair's corner is open to the
    # side: neither encloses a voxel.
    var cup = part_mass(grid, parts, 0, density, PART_SOLID)
    assert_almost_equal(cup.mass.to(KILOGRAM), 40000)
    var stair = part_mass(grid, parts, 2, density, PART_SOLID)
    assert_almost_equal(stair.mass.to(KILOGRAM), 3000)
    var gravity = Acceleration64(GRAVITY, METER_PER_SECOND_SQUARED)
    var l_shape = part_footing(
        grid, parts, 1, part_mass(grid, parts, 1, density, PART_SHELL), gravity
    )
    assert_almost_equal(l_shape.margin.to(METER), 0.8 / 2.0**0.5, atol=1e-9)
    assert_almost_equal(l_shape.area.to(SQUARE_METER), 2)
    with assert_raises(contains="gravity must be positive"):
        _ = part_footing(
            grid,
            parts,
            1,
            part_mass(grid, parts, 1, density, PART_SHELL),
            Acceleration64(inf[DType.float64](), METER_PER_SECOND_SQUARED),
        )


def test_a_ground_at_the_top_leaves_no_part() raises:
    """With every layer ground there is nothing to cut, and no splat of an
    empty scan is a part's."""
    var grid = _shapes()
    var none = scan_parts(grid, PartOptions(grid.nz - 1, 1))
    assert_equal(len(none.parts), 0)
    var parts = scan_parts(grid, PartOptions(-1, 1))
    var frame = ScanFrame(
        SCAN_POSITIVE_Z,
        SCAN_POSITIVE_Y,
        Length64(1, METER),
        SCALE_DECLARED,
        Angle64(0, RADIAN),
        Vec3d(0, 0, 0),
    )
    with assert_raises(contains="no splat is part 0's"):
        _ = part_splats(GaussianSplatGeometry(), frame, grid, parts, 0, 1)


def test_the_fills_have_their_names() raises:
    """Each fill has its name, and no other value is one."""
    assert_equal(PART_SHELL.name(), "shell")
    assert_equal(PART_SOLID.name(), "solid")
    assert_equal(PartFill(2).name(), "unknown")
    assert_false(PartFill(-1).is_valid())


def _slope_parts(grid: OccupancyGrid) raises -> ScanParts:
    """Return the parts of the slope, cut above its terrain."""
    return scan_parts_on(
        grid,
        terrain_ground(grid, TerrainOptions(slope_step(), slope_area())),
        1,
    )


def test_parts_on_a_slope_are_cut_above_its_terrain() raises:
    """The building and the bump are parts; the ground under them is not."""
    var grid = slope_site()
    var parts = _slope_parts(grid)
    assert_equal(len(parts.parts), 2)
    assert_equal(parts.parts[0].count(), 46)
    assert_equal(parts.parts[1].count(), 16)
    assert_equal(parts.labels[grid.index(5, 3, 8)], 0)
    assert_equal(parts.labels[grid.index(4, 2, 3)], 0)
    assert_equal(parts.labels[grid.index(9, 1, 5)], 1)
    assert_equal(parts.labels[grid.index(9, 1, 4)], -1)
    assert_equal(parts.labels[grid.index(0, 0, 0)], -1)
    assert_equal(parts.ground.tolerance, 2)
    with assert_raises(contains="one voxel at least"):
        _ = scan_parts_on(grid, parts.ground, 0)
    var other = OccupancyGrid(
        Vec3d(0, 0, 0), Length64(1, METER), 12, 9, 12, 0.5
    )
    with assert_raises(contains="is not the ground of a grid"):
        _ = scan_parts_on(other, parts.ground, 1)


def test_walls_on_a_slope_bear_within_the_tolerance() raises:
    """Each wall's foot bears; the roof over the middle does not. With no
    tolerance, the feet above the lowest ground do not bear."""
    var grid = slope_site()
    var parts = _slope_parts(grid)
    var density = Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER)
    var gravity = Acceleration64(GRAVITY, METER_PER_SECOND_SQUARED)
    var mass = part_mass(grid, parts, 0, density, PART_SHELL)
    var c = mass.center
    var footing = part_footing(grid, parts, 0, mass, gravity)
    assert_equal(footing.base, 3)
    assert_almost_equal(footing.area.to(SQUARE_METER), 8)
    assert_almost_equal(
        footing.margin.to(METER),
        min(c.x - 4, 7 - c.x, c.y - 2, 5 - c.y),
        atol=1e-12,
    )
    assert_almost_equal(
        footing.tip.to(RADIAN), atan2(footing.margin.to(METER), c.z - 3)
    )
    var strict = scan_parts_on(
        grid, GroundSurface(12, 8, parts.ground.layers.copy(), 0), 1
    )
    var narrow = part_footing(grid, strict, 0, mass, gravity)
    assert_almost_equal(narrow.area.to(SQUARE_METER), 5)
    assert_almost_equal(
        narrow.margin.to(METER),
        min(c.x - 5, 7 - c.x, c.y - 2, 5 - c.y),
        atol=1e-12,
    )


def test_a_part_that_touches_no_ground_bears_on_its_lowest_layer() raises:
    """A floating post bears on its lowest voxel alone."""
    var grid = OccupancyGrid(Vec3d(0, 0, 0), Length64(1, METER), 3, 3, 6, 0.5)
    _fill(grid, 1, 1, 1, 1, 3, 4)
    var parts = scan_parts_on(grid, flat_ground(grid, 0), 1)
    var mass = part_mass(
        grid, parts, 0, Density64(1000, KILOGRAM_PER_CUBIC_METER), PART_SHELL
    )
    var footing = part_footing(
        grid, parts, 0, mass, Acceleration64(GRAVITY, METER_PER_SECOND_SQUARED)
    )
    assert_equal(footing.base, 3)
    assert_almost_equal(footing.area.to(SQUARE_METER), 1)
    assert_almost_equal(footing.margin.to(METER), 0.5)


def _settle(bed: OccupancyGrid) raises -> Float64:
    """Stand the slope's building on a bed for one second, and return how
    far it moves."""
    var grid = slope_site()
    var parts = _slope_parts(grid)
    var mass = part_mass(
        grid,
        parts,
        0,
        Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER),
        PART_SHELL,
    )
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, Float32(-GRAVITY))
    _ = add_scan_collider(world, bed, PhysicsMaterial.default())
    var id = world.add_body(
        part_body(grid, parts, 0, mass, PhysicsMaterial.default())
    )
    var placed = world.bodies[id.value].position
    for _ in range(60):
        world.step(Duration(1.0 / 60, SECOND))
    return Float64((world.bodies[id.value].position - placed).length())


def test_a_part_stands_on_its_bed_and_not_on_the_whole_ground() raises:
    """The bed leaves out the ground that the hull holds: the column under
    the slope of the hull's lower face. On it the building stands still;
    on the whole ground the hull is pushed out of it."""
    var grid = slope_site()
    var parts = _slope_parts(grid)
    var mass = part_mass(
        grid,
        parts,
        0,
        Density64(CONCRETE, KILOGRAM_PER_CUBIC_METER),
        PART_SHELL,
    )
    var whole = ground_grid(grid, parts.ground)
    var bed = part_bed(grid, parts, 0, mass)
    assert_equal(whole.solid_count() - bed.solid_count(), 3)
    for j in range(2, 5):
        assert_false(bed.is_solid(6, j, 3))
        assert_true(bed.is_solid(6, j, 2))
        assert_true(bed.is_solid(4, j, 1))
    assert_true(bed.is_solid(5, 3, 1))
    assert_true(bed.is_solid(7, 3, 3))
    assert_true(_settle(bed) < 1e-3)
    assert_true(_settle(whole) > 0.1)
    with assert_raises(contains="there is no part 2 of 2"):
        _ = part_bed(grid, parts, 2, mass)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
