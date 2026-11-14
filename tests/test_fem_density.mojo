# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""FEM materials from the CT numbers of a volume."""

from extensions.fem.density import (
    CtDensityLaw,
    density_materials,
    element_ct,
)
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z
from extensions.fem.mesh import TetMesh, box_mesh, voxel_mesh
from extensions.fem.static import StaticProblem, solve_static
from extensions.imaging.ids import LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import threshold
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Density64,
    GRAM_PER_CUBIC_CENTIMETER,
    Length64,
    MEGAPASCAL,
    METER,
    PASCAL,
    Pressure64,
)


def _ct_value(k: Int) -> Float64:
    """The CT number of voxel k: 200, 600, 1000 and 1400."""
    return 200.0 + 400.0 * Float64(k)


def _g(value: Float64) -> Density64:
    return Density64(value, GRAM_PER_CUBIC_CENTIMETER)


def _law(poisson: Float64 = 0.0) raises -> CtDensityLaw:
    """Density in g/cm^3 of CT / 1000, and Morgan's femoral neck law."""
    return CtDensityLaw(
        _g(0),
        _g(0.001),
        Pressure64(6850, MEGAPASCAL),
        1.49,
        _g(0.01),
        poisson,
    )


def _bar() raises -> ImageVolume:
    """A column of four voxels of 1 mm, one CT number in each."""
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(1, 1, 4, mm, mm, mm)
    for k in range(4):
        volume.values[k] = Float32(_ct_value(k))
    return volume^


def test_law() raises:
    var law = _law()
    assert_almost_equal(law.density(1000).to(GRAM_PER_CUBIC_CENTIMETER), 1.0)
    assert_almost_equal(law.modulus(1000).to(MEGAPASCAL), 6850.0)
    assert_almost_equal(
        law.modulus(500).to(MEGAPASCAL), 6850.0 * 0.5**1.49, rtol=1e-12
    )
    # Air is held at the least density.
    assert_almost_equal(law.density(-1000).to(GRAM_PER_CUBIC_CENTIMETER), 0.01)


def _press(
    var mesh: TetMesh, materials: List[IsotropicMaterial]
) raises -> Float64:
    """The shortening of the column under 1 MPa, in meters."""
    var problem = StaticProblem(mesh^, materials.copy())
    var near = Length64(1e-9, METER)
    var bottom = Length64(-0.0005, METER)
    for node in problem.mesh.nodes_on_plane(DOF_Z, bottom, near):
        problem.fix(node, DOF_X, Length64(0, METER))
        problem.fix(node, DOF_Y, Length64(0, METER))
        problem.fix(node, DOF_Z, Length64(0, METER))
    var top = Length64(0.0035, METER)
    _ = problem.press_plane(DOF_Z, top, near, Pressure64(-1, MEGAPASCAL))
    var result = solve_static(problem, 1e-13, 2000)
    var drop = 0.0
    var nodes = problem.mesh.nodes_on_plane(DOF_Z, top, near)
    for node in nodes:
        drop -= result.displacement(node).z
    return drop / Float64(len(nodes))


def test_series_column_is_exact() raises:
    var volume = _bar()
    var map = threshold(volume, -2000, 3000, LabelId(1))
    var mesh = voxel_mesh(map, LabelId(1))
    var ct = element_ct(mesh, volume)
    assert_equal(len(ct), 24)
    assert_equal(ct[0], 200)
    assert_equal(ct[23], 1400)
    var law = _law()
    # Enough bins to give each voxel a material of its own.
    var made = density_materials(mesh, volume, law, 64)
    assert_equal(len(made.materials), 4)
    assert_equal(mesh.materials[0], 0)
    assert_equal(mesh.materials[23], 3)
    assert_almost_equal(
        made.densities[2].to(GRAM_PER_CUBIC_CENTIMETER), 1.0, rtol=1e-12
    )
    # Springs in series: with Poisson's ratio zero, each voxel shortens by
    # p * h / E, and linear elements hold that exactly.
    var expected = 0.0
    for k in range(4):
        expected += 1e6 * 0.001 / law.modulus(_ct_value(k)).to(PASCAL)
    var drop = _press(mesh^, made.materials)
    assert_almost_equal(drop, expected, rtol=1e-9)


def test_one_bin_takes_the_mean() raises:
    var volume = _bar()
    var map = threshold(volume, -2000, 3000, LabelId(1))
    var mesh = voxel_mesh(map, LabelId(1))
    var law = _law()
    var made = density_materials(mesh, volume, law, 1)
    assert_equal(len(made.materials), 1)
    var mean = 0.0
    var rho = 0.0
    for k in range(4):
        mean += law.modulus(_ct_value(k)).to(PASCAL) / 4
        rho += law.density(_ct_value(k)).to(GRAM_PER_CUBIC_CENTIMETER) / 4
    assert_almost_equal(made.materials[0].young.to(PASCAL), mean, rtol=1e-12)
    assert_almost_equal(
        made.densities[0].to(GRAM_PER_CUBIC_CENTIMETER), rho, rtol=1e-12
    )
    # Two bins: the two soft voxels share one, the two stiff ones the other.
    mesh = voxel_mesh(map, LabelId(1))
    made = density_materials(mesh, volume, law, 2)
    assert_equal(len(made.materials), 2)
    assert_equal(mesh.materials[12], 1)
    # A uniform volume makes one material, whatever the bins.
    var uniform = _bar()
    for k in range(4):
        uniform.values[k] = 700
    mesh = voxel_mesh(map, LabelId(1))
    made = density_materials(mesh, uniform, _law(0.3), 8)
    assert_equal(len(made.materials), 1)
    assert_equal(made.materials[0].poisson, 0.3)


def test_refusals() raises:
    var volume = _bar()
    var map = threshold(volume, -2000, 3000, LabelId(1))
    var mesh = voxel_mesh(map, LabelId(1))
    with assert_raises(contains="from 1 to 1024 bins"):
        _ = density_materials(mesh, volume, _law(), 0)
    with assert_raises(contains="from 1 to 1024 bins"):
        _ = density_materials(mesh, volume, _law(), 1025)
    var empty = TetMesh()
    with assert_raises(contains="with an element"):
        _ = density_materials(empty, volume, _law(), 4)
    assert_equal(len(element_ct(TetMesh(), volume)), 0)
    # A box of 2 mm reaches past the column of 1 mm.
    var wide = box_mesh(
        Length64(0.002, METER),
        Length64(0.001, METER),
        Length64(0.001, METER),
        2,
        1,
        1,
    )
    with assert_raises(contains="outside the CT volume"):
        _ = element_ct(wide, volume)
    var mpa = Pressure64(6850, MEGAPASCAL)
    with assert_raises(contains="intercept must be finite"):
        _ = CtDensityLaw(
            _g(nan[DType.float64]()), _g(0.001), mpa, 1.5, _g(0.01), 0
        )
    with assert_raises(contains="slope must be finite"):
        _ = CtDensityLaw(_g(0), _g(inf[DType.float64]()), mpa, 1.5, _g(0.01), 0)
    with assert_raises(contains="coefficient must be positive"):
        _ = CtDensityLaw(
            _g(0), _g(0.001), Pressure64(0, PASCAL), 1.5, _g(0.01), 0
        )
    with assert_raises(contains="coefficient must be positive"):
        _ = CtDensityLaw(
            _g(0),
            _g(0.001),
            Pressure64(inf[DType.float64](), PASCAL),
            1.5,
            _g(0.01),
            0,
        )
    with assert_raises(contains="exponent must be positive"):
        _ = CtDensityLaw(_g(0), _g(0.001), mpa, 0, _g(0.01), 0)
    with assert_raises(contains="exponent must be positive"):
        _ = CtDensityLaw(
            _g(0), _g(0.001), mpa, inf[DType.float64](), _g(0.01), 0
        )
    with assert_raises(contains="minimum density"):
        _ = CtDensityLaw(_g(0), _g(0.001), mpa, 1.5, _g(0), 0)
    with assert_raises(contains="minimum density"):
        _ = CtDensityLaw(
            _g(0), _g(0.001), mpa, 1.5, _g(inf[DType.float64]()), 0
        )
    with assert_raises(contains="Poisson"):
        _ = CtDensityLaw(_g(0), _g(0.001), mpa, 1.5, _g(0.01), 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
