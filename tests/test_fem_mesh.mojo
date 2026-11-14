# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tetrahedral meshes, the element stiffness and the material."""

from extensions.fem.elasticity import (
    IsotropicMaterial,
    element_stiffness,
    element_strain,
    gauss_points,
    quadratic_gradients,
    quadratic_stiffness,
    shape_gradients,
    stress_of,
    von_mises,
)
from extensions.fem.ids import (
    DOF_X,
    DOF_Y,
    DOF_Z,
    DofAxis,
    ElementId,
    ElementOrder,
    LINEAR,
    MaterialId,
    NodeId,
    QUADRATIC,
    require_dof_axis,
    require_order,
)
from extensions.fem.mesh import (
    MAX_MESH_ENTRIES,
    TetMesh,
    box_mesh,
    quadratic_mesh,
    signed_volume,
    voxel_mesh,
)
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.sdf.vector import V3, cross, length, v3
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import GIGAPASCAL, Length64, METER, PASCAL, Pressure64


def _m(value: Float64) -> Length64:
    return Length64(value, METER)


def _unit_tet() raises -> TetMesh:
    var mesh = TetMesh()
    _ = mesh.add_node(v3(0, 0, 0))
    _ = mesh.add_node(v3(1, 0, 0))
    _ = mesh.add_node(v3(0, 1, 0))
    _ = mesh.add_node(v3(0, 0, 1))
    return mesh^


def test_elements_turn_to_a_positive_volume() raises:
    var mesh = _unit_tet()
    var forward = mesh.add_element(
        NodeId(0), NodeId(1), NodeId(2), NodeId(3), MaterialId(0)
    )
    var backward = mesh.add_element(
        NodeId(0), NodeId(1), NodeId(3), NodeId(2), MaterialId(1)
    )
    assert_almost_equal(mesh.volume(forward).value, 1.0 / 6.0)
    assert_almost_equal(mesh.volume(backward).value, 1.0 / 6.0)
    assert_equal(mesh.element_nodes(backward)[2], 2)
    assert_almost_equal(mesh.total_volume().value, 1.0 / 3.0)
    assert_equal(mesh.node_count(), 4)
    assert_equal(mesh.element_count(), 2)
    assert_almost_equal(
        signed_volume(v3(0, 0, 0), v3(1, 0, 0), v3(0, 0, 1), v3(0, 1, 0)),
        -1.0 / 6.0,
    )


def test_mesh_refusals() raises:
    var mesh = _unit_tet()
    with assert_raises(contains="finite position"):
        _ = mesh.add_node(v3(inf[DType.float64](), 0, 0))
    with assert_raises(contains="node id"):
        _ = mesh.add_element(
            NodeId(0), NodeId(1), NodeId(2), NodeId(4), MaterialId(0)
        )
    with assert_raises(contains="node id"):
        _ = mesh.add_element(
            NodeId(-1), NodeId(1), NodeId(2), NodeId(3), MaterialId(0)
        )
    with assert_raises(contains="material id cannot be negative"):
        _ = mesh.add_element(
            NodeId(0), NodeId(1), NodeId(2), NodeId(3), MaterialId(-1)
        )
    var flat = mesh.add_node(v3(0.5, 0.5, 0))
    with assert_raises(contains="not flat"):
        _ = mesh.add_element(
            NodeId(0), NodeId(1), NodeId(2), flat, MaterialId(0)
        )
    with assert_raises(contains="element id"):
        _ = mesh.element_nodes(ElementId(0))
    assert_equal(TetMesh().total_volume().value, 0)


def test_box_mesh() raises:
    var mesh = box_mesh(_m(2), _m(1), _m(0.5), 4, 2, 1)
    assert_equal(mesh.node_count(), 5 * 3 * 2)
    assert_equal(mesh.element_count(), 6 * 4 * 2 * 1)
    assert_almost_equal(mesh.total_volume().value, 1.0, atol=1e-12)
    var every = 0.0
    for e in range(mesh.element_count()):
        every = min(every, mesh.volume(ElementId(e)).value)
    assert_true(every >= 0)
    var tolerance = _m(1e-9)
    assert_equal(len(mesh.nodes_on_plane(DOF_X, _m(2), tolerance)), 6)
    assert_equal(len(mesh.nodes_on_plane(DOF_Y, _m(0), tolerance)), 10)
    assert_equal(len(mesh.nodes_on_plane(DOF_Z, _m(0.5), tolerance)), 15)
    assert_equal(len(mesh.nodes_on_plane(DOF_Z, _m(9), tolerance)), 0)
    assert_equal(len(TetMesh().nodes_on_plane(DOF_X, _m(0), tolerance)), 0)
    with assert_raises(contains="axis must be 0 to 2"):
        _ = mesh.nodes_on_plane(DofAxis(3), _m(0), tolerance)


def test_box_mesh_refusals() raises:
    with assert_raises(contains="at least one cube"):
        _ = box_mesh(_m(1), _m(1), _m(1), 0, 1, 1)
    with assert_raises(contains="at least one cube"):
        _ = box_mesh(_m(1), _m(1), _m(1), 1, 0, 1)
    with assert_raises(contains="at least one cube"):
        _ = box_mesh(_m(1), _m(1), _m(1), 1, 1, 0)
    with assert_raises(contains="at most 2^24"):
        _ = box_mesh(_m(1), _m(1), _m(1), MAX_MESH_ENTRIES, 1, 1)
    with assert_raises(contains="positive, finite sizes"):
        _ = box_mesh(_m(0), _m(1), _m(1), 1, 1, 1)
    with assert_raises(contains="positive, finite sizes"):
        _ = box_mesh(_m(1), _m(0), _m(1), 1, 1, 1)
    with assert_raises(contains="positive, finite sizes"):
        _ = box_mesh(_m(1), _m(1), _m(0), 1, 1, 1)
    with assert_raises(contains="positive, finite sizes"):
        _ = box_mesh(_m(1), _m(1), _m(inf[DType.float64]()), 1, 1, 1)


def test_voxel_mesh() raises:
    var spacing = Length64(2, MILLIMETER64)
    var volume = ImageVolume(3, 3, 3, spacing, spacing, spacing)
    var map = LabelMap(volume)
    # Two voxels that share a face, and one apart.
    map.set(0, 0, 0, LabelId(4))
    map.set(1, 0, 0, LabelId(4))
    map.set(2, 2, 2, LabelId(4))
    var mesh = voxel_mesh(map, LabelId(4))
    assert_equal(mesh.element_count(), 18)
    assert_equal(mesh.node_count(), 12 + 8)
    assert_almost_equal(mesh.total_volume().value, 3 * 8e-9, atol=1e-18)
    # Voxel (0, 0, 0) reaches half a voxel below its center.
    assert_almost_equal(mesh.nodes[0].x, -0.001)
    with assert_raises(contains="no voxels"):
        _ = voxel_mesh(map, LabelId(5))
    with assert_raises(contains="from 0 to 255"):
        _ = voxel_mesh(map, LabelId(256))


def test_material() raises:
    var steel = IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.3)
    var constants = steel.lame()
    assert_almost_equal(constants[0], 200e9 * 0.3 / (1.3 * 0.4))
    assert_almost_equal(constants[1], 200e9 / 2.6)
    with assert_raises(contains="Young's modulus"):
        _ = IsotropicMaterial(Pressure64(0, PASCAL), 0.3)
    with assert_raises(contains="Young's modulus"):
        _ = IsotropicMaterial(Pressure64(inf[DType.float64](), PASCAL), 0.3)
    with assert_raises(contains="Poisson's ratio"):
        _ = IsotropicMaterial(Pressure64(1, PASCAL), -1)
    with assert_raises(contains="Poisson's ratio"):
        _ = IsotropicMaterial(Pressure64(1, PASCAL), 0.5)


def test_shape_gradients() raises:
    var g = shape_gradients(v3(0, 0, 0), v3(2, 0, 0), v3(0, 2, 0), v3(0, 0, 2))
    assert_almost_equal(g[1].x, 0.5)
    assert_almost_equal(g[2].y, 0.5)
    assert_almost_equal(g[3].z, 0.5)
    var total = g[0] + g[1] + g[2] + g[3]
    assert_true(length(total) < 1e-15)


def test_element_stiffness_has_rigid_modes() raises:
    var corners: List[V3] = [
        v3(0.1, 0, 0),
        v3(1, 0.2, 0),
        v3(0, 1, 0.1),
        v3(0.2, 0.3, 1),
    ]
    var k = element_stiffness(
        corners, IsotropicMaterial(Pressure64(1, GIGAPASCAL), 0.25)
    )
    var asymmetry = 0.0
    var largest = 0.0
    for r in range(12):
        for c in range(12):
            asymmetry = max(asymmetry, abs(k[r * 12 + c] - k[c * 12 + r]))
            largest = max(largest, abs(k[r * 12 + c]))
    assert_true(asymmetry < 1e-6 * largest)
    # A translation and a small rotation about z cause no force.
    var worst = 0.0
    for r in range(12):
        var translate = 0.0
        var rotate = 0.0
        for a in range(4):
            translate += k[r * 12 + 3 * a + 1]
            rotate += k[r * 12 + 3 * a] * (-corners[a].y)
            rotate += k[r * 12 + 3 * a + 1] * corners[a].x
        worst = max(worst, max(abs(translate), abs(rotate)))
    assert_true(worst < 1e-6 * largest)


def test_strain_stress_and_von_mises() raises:
    var g = shape_gradients(v3(0, 0, 0), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
    # u = (0.01 x, 0, 0) at the corners.
    var moves: List[V3] = [
        v3(0, 0, 0),
        v3(0.01, 0, 0),
        v3(0, 0, 0),
        v3(0, 0, 0),
    ]
    var strain = element_strain(g, moves)
    assert_almost_equal(strain[0], 0.01)
    assert_almost_equal(strain[1], 0)
    # u = (0.02 y, 0, 0) is a shear.
    var shear = element_strain(
        g, [v3(0, 0, 0), v3(0, 0, 0), v3(0.02, 0, 0), v3(0, 0, 0)]
    )
    assert_almost_equal(shear[5], 0.02)
    var material = IsotropicMaterial(Pressure64(100, PASCAL), 0.0)
    var stress = stress_of(strain, material)
    assert_almost_equal(stress[0], 1.0)
    assert_almost_equal(von_mises(stress).to(PASCAL), 1.0)
    var pure_shear = stress_of(shear, material)
    assert_almost_equal(pure_shear[5], 1.0)
    assert_almost_equal(von_mises(pure_shear).to(PASCAL), sqrt(3.0))
    var none = element_strain(List[V3](), List[V3]())
    assert_equal(none[0], 0)
    var other: List[Float64] = [0, 0, 0, 1, 1, 0]
    assert_almost_equal(von_mises(other).to(PASCAL), sqrt(6.0))


def test_ids() raises:
    require_dof_axis(DOF_Z)
    with assert_raises(contains="axis must be 0 to 2"):
        require_dof_axis(DofAxis(-1))
    assert_true(NodeId(0).is_valid())
    assert_false(ElementId(-1).is_valid())
    assert_true(MaterialId(2).is_valid())


def test_quadratic_mesh() raises:
    var cube = box_mesh(_m(1), _m(1), _m(1), 1, 1, 1)
    var quadratic = quadratic_mesh(cube)
    # Eight corners and one node on each of the 19 edges: 12 cube edges,
    # 6 face diagonals and the body diagonal.
    assert_equal(quadratic.node_count(), 27)
    assert_equal(quadratic.nodes_per_element(), 10)
    assert_true(quadratic.order == QUADRATIC)
    var nodes = quadratic.element_nodes(ElementId(0))
    assert_equal(len(nodes), 10)
    var middle = quadratic.nodes[nodes[4]]
    var expected = (quadratic.nodes[nodes[0]] + quadratic.nodes[nodes[1]]) * 0.5
    assert_true(length(middle - expected) < 1e-15)
    assert_almost_equal(quadratic.total_volume().value, 1.0, atol=1e-12)
    with assert_raises(contains="already quadratic"):
        _ = quadratic_mesh(quadratic)
    assert_equal(quadratic_mesh(TetMesh()).element_count(), 0)
    with assert_raises(contains="four-node elements"):
        _ = quadratic.add_element(
            NodeId(0), NodeId(1), NodeId(2), NodeId(3), MaterialId(0)
        )
    assert_equal(LINEAR.nodes(), 4)
    require_order(QUADRATIC)
    with assert_raises(contains="element order"):
        require_order(ElementOrder(2))


def test_quadratic_shape_functions() raises:
    var linear = shape_gradients(
        v3(0, 0, 0), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)
    )
    var points = gauss_points()
    var worst = 0.0
    for point in range(4):
        var weights: List[Float64] = [
            points[4 * point],
            points[4 * point + 1],
            points[4 * point + 2],
            points[4 * point + 3],
        ]
        var g = quadratic_gradients(linear, weights)
        var total = v3(0, 0, 0)
        for a in range(10):
            total = total + g[a]
        worst = max(worst, length(total))
    # The ten functions sum to one, so their gradients sum to zero.
    assert_true(worst < 1e-14)
    var corners: List[V3] = [
        v3(0.1, 0, 0),
        v3(1, 0.2, 0),
        v3(0, 1, 0.1),
        v3(0.2, 0.3, 1),
    ]
    var k = quadratic_stiffness(
        corners, IsotropicMaterial(Pressure64(1, GIGAPASCAL), 0.25)
    )
    var asymmetry = 0.0
    var largest = 0.0
    for r in range(30):
        for c in range(30):
            asymmetry = max(asymmetry, abs(k[r * 30 + c] - k[c * 30 + r]))
            largest = max(largest, abs(k[r * 30 + c]))
    assert_true(asymmetry < 1e-6 * largest)
    # A translation along y and a small turn about z cause no force.
    var places = corners.copy()
    var pairs: List[Int] = [0, 1, 1, 2, 0, 2, 0, 3, 1, 3, 2, 3]
    for edge in range(6):
        places.append(
            (corners[pairs[2 * edge]] + corners[pairs[2 * edge + 1]]) * 0.5
        )
    var rigid = 0.0
    for r in range(30):
        var translate = 0.0
        var rotate = 0.0
        for a in range(10):
            translate += k[r * 30 + 3 * a + 1]
            rotate += k[r * 30 + 3 * a] * (-places[a].y)
            rotate += k[r * 30 + 3 * a + 1] * places[a].x
        rigid = max(rigid, max(abs(translate), abs(rotate)))
    assert_true(rigid < 1e-6 * largest)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
