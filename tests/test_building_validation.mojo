# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mutated-model refusals at the canonical building boundary.

Every case starts from the same valid, assembled two-storey model. Each
mutation changes a public field to a value the existing views cannot use.
"""

from std.math import inf, nan
from std.testing import TestSuite, assert_raises
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    SpaceId,
    StoreyId,
)
from extensions.building.construction import double_glazing
from extensions.building.kinds import FurnitureKind, WALL, WINDOW
from extensions.building.model import (
    Building,
    rectangle,
    _check_face_area,
    _check_outline_area,
    _check_space_measures,
)
from extensions.topology.arrangement import Point2
from extensions.topology.complex import FaceKind, HORIZONTAL
from extensions.topology.ids import CellId, FaceId, RegionId, VertexId
from tests.test_building_model import _two_storeys
from units.si import Angle64, Length64, METER


def _m(value: Float64) -> Length64:
    return Length64(value, METER)


def _refuses(model: Building) raises:
    with assert_raises(contains=""):
        model.validate()


def test_each_topology_map_has_the_required_size() raises:
    for field in range(5):
        var b = _two_storeys()
        if field == 0:
            b.topology.cell_storey.clear()
        elif field == 1:
            b.topology.cell_region.clear()
        elif field == 2:
            b.spaces.clear()
        elif field == 3:
            b.topology.face_level.clear()
        else:
            b.face_element.clear()
        _refuses(b)


def test_storey_numbers_are_finite_positive_and_consistent() raises:
    for field in range(8):
        var b = _two_storeys()
        if field == 0:
            b.storeys[0].elevation = _m(nan[DType.float64]())
        elif field == 1:
            b.storeys[0].height = _m(0)
        elif field == 2:
            b.storeys[0].height = _m(-1)
        elif field == 3:
            b.storeys[0].height = _m(inf[DType.float64]())
        elif field == 4:
            b.storeys[0].height = _m(nan[DType.float64]())
        elif field == 5:
            b.storeys[0].elevation = _m(1e308)
            b.storeys[0].height = _m(1e308)
        elif field == 6:
            b.storeys[1].elevation = _m(4)
        else:
            b.storeys.clear()
        _refuses(b)


def test_space_ids_and_outlines_agree_with_cells() raises:
    for field in range(8):
        var b = _two_storeys()
        if field == 0:
            b.spaces[0].cell = CellId(-1)
        elif field == 1:
            b.spaces[0].cell = CellId(1)
        elif field == 2:
            b.topology.cell_storey[0] = 1
        elif field == 3:
            b.topology.cell_region[0] = RegionId(99)
        elif field == 4:
            b.spaces[0].outline.clear()
        elif field == 5:
            b.spaces[0].outline[0].x = nan[DType.float64]()
        elif field == 6:
            b.spaces[0].outline[0].y = inf[DType.float64]()
        else:
            b.spaces[0].outline[1] = b.spaces[0].outline[0]
        _refuses(b)


def test_complex_public_references_are_checked_before_use() raises:
    for field in range(13):
        var b = _two_storeys()
        if field == 0:
            b.topology.complex.welder.tolerance = 0
        elif field == 1:
            b.topology.complex.welder.tolerance = inf[DType.float64]()
        elif field == 2:
            b.topology.complex.welder.points[0].x = nan[DType.float64]()
        elif field == 3:
            b.topology.complex.welder.points[0].y = nan[DType.float64]()
        elif field == 4:
            b.topology.complex.welder.points[0].z = nan[DType.float64]()
        elif field == 5:
            b.topology.complex.edge_faces.clear()
        elif field == 6:
            b.topology.complex.edges[0].a = VertexId(-1)
        elif field == 7:
            b.topology.complex.edges[0].b = b.topology.complex.edges[0].a
        elif field == 8:
            b.topology.complex.edge_faces[0][0] = FaceId(999)
        elif field == 9:
            b.topology.complex.faces[0].kind = FaceKind(999)
        elif field == 10:
            b.topology.complex.faces[0].loop.clear()
        elif field == 11:
            b.topology.complex.faces[0].loop[1] = b.topology.complex.faces[
                0
            ].loop[0]
        else:
            b.topology.complex.faces[0].positive = CellId(999)
        _refuses(b)


def test_face_levels_and_owners_are_checked() raises:
    for field in range(7):
        var b = _two_storeys()
        if field == 0:
            b.topology.face_level[0] = -1
        elif field == 1:
            b.topology.face_level[0] = 99
        elif field == 2:
            b.elements[0].faces[0] = FaceId(-1)
        elif field == 3:
            b.elements[1].faces[0] = b.elements[0].faces[0]
        elif field == 4:
            b.elements[0].kind = WALL
        elif field == 5:
            b.elements[0].storey = StoreyId(1)
        else:
            b.elements[0].material = MaterialId(0)
        _refuses(b)
    for sign in range(2):
        var b = _two_storeys()
        var shift = -0.1 if sign == 0 else 0.1
        for i in range(len(b.topology.complex.welder.points)):
            b.topology.complex.welder.points[i].z += shift
        _refuses(b)


def test_orphan_building_faces_are_refused() raises:
    var b = _two_storeys()
    var loop = b.topology.complex.faces[0].loop.copy()
    _ = b.topology.complex.add_face(loop^, None, None, HORIZONTAL)
    b.topology.face_level.append(0)
    b.face_element.append(-1)
    _refuses(b)


def test_frame_material_axes_and_face_fields_are_checked() raises:
    for field in range(12):
        var b = _two_storeys()
        var id = b.add_column(
            StoreyId(0),
            Point2(1, 1),
            rectangle(_m(0.3), _m(0.3)),
            MaterialId(0),
        )
        if field == 0:
            b.elements[id.value].material = None
        elif field == 1:
            b.elements[id.value].construction = ConstructionId(0)
        elif field == 2:
            b.elements[id.value].faces.append(FaceId(0))
        elif field == 3:
            b.elements[id.value].start.x = nan[DType.float64]()
        elif field == 4:
            b.elements[id.value].start.y = nan[DType.float64]()
        elif field == 5:
            b.elements[id.value].start.z = nan[DType.float64]()
        elif field == 6:
            b.elements[id.value].end.x = nan[DType.float64]()
        elif field == 7:
            b.elements[id.value].end.y = nan[DType.float64]()
        elif field == 8:
            b.elements[id.value].end.z = nan[DType.float64]()
        elif field == 9:
            b.elements[id.value].end = b.elements[id.value].start
        elif field == 10:
            b.elements[id.value].end.x = 1e308
        else:
            b.elements[id.value].end.y += 0.1
        _refuses(b)


def test_furnishing_edits_are_checked() raises:
    for field in range(12):
        var b = _two_storeys()
        _ = b.add_furnishing(
            FurnitureKind(0),
            SpaceId(0),
            Point2(2, 2),
            Angle64(0),
            _m(1),
            _m(1),
            _m(1),
        )
        if field == 0:
            b.furnishings[0].kind = FurnitureKind(99)
        elif field == 1:
            b.furnishings[0].space = SpaceId(99)
        elif field == 2:
            b.furnishings[0].width = _m(0)
        elif field == 3:
            b.furnishings[0].depth = _m(0)
        elif field == 4:
            b.furnishings[0].height = _m(0)
        elif field == 5:
            b.furnishings[0].height = _m(inf[DType.float64]())
        elif field == 6:
            b.furnishings[0].center.x = nan[DType.float64]()
        elif field == 7:
            b.furnishings[0].center.y = nan[DType.float64]()
        elif field == 8:
            b.furnishings[0].rotation = Angle64(nan[DType.float64]())
        elif field == 9:
            b.furnishings[0].center = Point2(20, 20)
        elif field == 10:
            _ = b.add_furnishing(
                FurnitureKind(0),
                SpaceId(0),
                Point2(4, 2),
                Angle64(0),
                _m(1),
                _m(1),
                _m(1),
            )
            b.furnishings[1].center = Point2(2, 2)
        else:
            b.furnishings[0].width = _m(nan[DType.float64]())
        _refuses(b)


def test_beam_plan_axis_keeps_the_factory_minimum() raises:
    var b = _two_storeys()
    var id = b.add_beam(
        StoreyId(0),
        Point2(0, 0),
        Point2(1, 0),
        rectangle(_m(0.3), _m(0.3)),
        MaterialId(0),
    )
    # A nonzero vertical difference inside the topology tolerance must
    # not disguise coincident endpoints in plan.
    b.elements[id.value].end.x = 0
    b.elements[id.value].end.z += b.topology.complex.welder.tolerance / 2
    with assert_raises(contains="differ in plan"):
        b.validate()
    b.elements[id.value].end.z = b.elements[id.value].start.z
    b.elements[id.value].end.x = 1e-6
    with assert_raises(contains="differ in plan"):
        b.validate()
    b.elements[id.value].end.x = 1.001e-6
    b.validate()


def _four_corner_wall(b: Building) raises -> ElementId:
    for i in range(len(b.elements)):
        if b.elements[i].kind == WALL:
            if (
                len(b.topology.complex.faces[b.elements[i].faces[0].value].loop)
                == 4
            ):
                return ElementId(i)
    raise Error("The fixture needs a four-corner wall")


def test_derived_measure_guards_cover_each_finite_requirement() raises:
    _check_space_measures(1, 1)
    for field in range(4):
        var area = Float64(1)
        var volume = Float64(1)
        if field == 0:
            area = 0
        elif field == 1:
            area = inf[DType.float64]()
        elif field == 2:
            volume = 0
        else:
            volume = inf[DType.float64]()
        with assert_raises(contains="positive finite"):
            _check_space_measures(area, volume)
    _check_face_area(1)
    with assert_raises(contains="positive finite"):
        _check_face_area(0)
    with assert_raises(contains="positive finite"):
        _check_face_area(inf[DType.float64]())
    _check_outline_area(1, 1, 0)
    with assert_raises(contains="cell area"):
        _check_outline_area(nan[DType.float64](), 1, 0)
    with assert_raises(contains="cell area"):
        _check_outline_area(2, 1, 0)


def test_wall_frame_checks_each_shape_before_normalizing() raises:
    for field in range(6):
        var b = _two_storeys()
        var id = _four_corner_wall(b)
        var face = b.elements[id.value].faces[0].value
        var loop = b.topology.complex.faces[face].loop.copy()
        if field == 0:
            b.elements[id.value].faces.clear()
        elif field == 1:
            _ = b.topology.complex.faces[face].loop.pop()
        elif field == 2:
            for k in range(4):
                b.topology.complex.welder.points[loop[k].value].z = 0
        elif field == 3:
            b.topology.complex.welder.points[
                loop[1].value
            ] = b.topology.complex.welder.points[loop[0].value]
        elif field == 4:
            for k in range(2, 4):
                b.topology.complex.welder.points[loop[k].value].z = -1
        else:
            b.topology.complex.welder.points[loop[0].value].x = -1e308
            b.topology.complex.welder.points[loop[1].value].x = 1e308
        with assert_raises(contains="wall"):
            _ = b.wall_frame(id)


def test_wall_geometry_checks_level_height_and_planarity() raises:
    for field in range(3):
        var b = _two_storeys()
        var id = _four_corner_wall(b)
        var face = b.elements[id.value].faces[0].value
        var loop = b.topology.complex.faces[face].loop.copy()
        var wall = b.wall_frame(id)
        if field == 0:
            for k in range(4):
                b.topology.complex.welder.points[loop[k].value].z += 0.1
        elif field == 1:
            for k in range(2, 4):
                b.topology.complex.welder.points[loop[k].value].z -= 0.1
        else:
            b.topology.complex.welder.points[loop[2].value].x += (
                0.1 * wall.normal.x
            )
            b.topology.complex.welder.points[loop[2].value].y += (
                0.1 * wall.normal.y
            )
        with assert_raises(contains="wall"):
            b._check_wall_geometry(id, b.elements[id.value].storey.value, 1e-6)


def test_space_measurements_match_geometry_and_levels() raises:
    var b = _two_storeys()
    b.spaces[0].outline = [
        Point2(1, 1),
        Point2(5, 1),
        Point2(5, 4),
        Point2(1, 4),
    ]
    with assert_raises(contains="outline and its cell"):
        b.validate()
    b = _two_storeys()
    b.storeys[0].height = _m(3.6)
    b.storeys[1].elevation = _m(3.6)
    with assert_raises(contains="volume and its storey height"):
        b.validate()
    b = _two_storeys()
    b.topology.complex.faces.clear()
    b.topology.complex.edges.clear()
    b.topology.complex.edge_faces.clear()
    for i in range(len(b.topology.complex.cell_faces)):
        b.topology.complex.cell_faces[i].clear()
    b.topology.face_level.clear()
    b.face_element.clear()
    b.elements.clear()
    with assert_raises(contains="positive finite area"):
        b.validate()


def test_remaining_member_and_opening_conditions() raises:
    for field in range(3):
        var b = _two_storeys()
        var id = b.add_column(
            StoreyId(0),
            Point2(1, 1),
            rectangle(_m(0.3), _m(0.3)),
            MaterialId(0),
        )
        if field == 0:
            b.elements[id.value].start.x = -1e308
            b.elements[id.value].end.x = 1e308
        elif field == 1:
            b.elements[id.value].start.z += 0.1
        else:
            b.elements[id.value].end.z += 0.1
        _refuses(b)
    for field in range(2):
        var b = _two_storeys()
        var id = b.add_beam(
            StoreyId(0),
            Point2(0, 0),
            Point2(1, 0),
            rectangle(_m(0.3), _m(0.3)),
            MaterialId(0),
        )
        if field == 0:
            b.elements[id.value].start.z += 0.1
        else:
            b.elements[id.value].end.z += 0.1
        _refuses(b)
    var b = _two_storeys()
    b.elements[0].section = rectangle(_m(0.3), _m(0.3))
    _refuses(b)
    b = _two_storeys()
    with assert_raises(contains="inside"):
        _ = b.add_opening(
            WINDOW,
            _four_corner_wall(b),
            _m(0),
            _m(inf[DType.float64]()),
            _m(1),
            _m(1),
            double_glazing(),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
