# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the structural view of a building.

The reference is statics: the support reactions of each load case must
equal the total gravity load. The dead load is the weight of the members
and of the floor and roof constructions. The live load is the floor area
times the ASCE/SEI 7-16 table 4.3-1 value for each use.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.construction import Construction, Layer
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    StoreyId,
)
from extensions.building.kinds import (
    BEAM,
    CORRIDOR,
    MECHANICAL,
    OFFICE,
    SpaceUse,
    STORAGE,
    WINDOW,
)
from extensions.building.construction import double_glazing
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
    steel,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    i_shape,
)
from extensions.building.views.structural import (
    StructuralViewOptions,
    default_options,
    live_load,
    roof_live_load,
    structural_view,
)
from extensions.structure.ids import LoadCaseId
from extensions.structure.kinds import UZ
from extensions.structure.static import StaticSolver
from extensions.topology.arrangement import Point2
from extensions.topology.ids import FaceId
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Angle64,
    DEGREE,
    DEGREE64,
    KILOPASCAL,
    Length64,
    METER,
    SQUARE_METER,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64) -> List[Point2]:
    return [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]


def _building(roof_beams: Bool) raises -> Building:
    """Two storeys on an 8 m by 5 m plan with a steel frame.

    The ground storey has an office and a corridor; the first storey is
    one storage room. Columns stand at the corners and at x = 6 m. Beams
    run along the edges and across at x = 6 m, under the floor and, if
    asked, under the roof.
    """
    var materials = List[BuildingMaterial]()
    materials.append(brick())
    materials.append(mineral_wool())
    materials.append(gypsum_board())
    materials.append(concrete())
    materials.append(steel())
    var constructions = List[Construction]()
    constructions.append(
        Construction(
            "wall",
            [Layer(MaterialId(0), _m(0.2)), Layer(MaterialId(1), _m(0.1))],
        )
    )
    constructions.append(
        Construction("partition", [Layer(MaterialId(2), _m(0.025))])
    )
    # A 50 mm screed over a 200 mm slab: the thickest layer is second.
    constructions.append(
        Construction(
            "floor",
            [Layer(MaterialId(2), _m(0.05)), Layer(MaterialId(3), _m(0.2))],
        )
    )
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("office", OFFICE, _rect(0, 0, 6, 5)))
    ground.append(SpacePlan("corridor", CORRIDOR, _rect(6, 0, 8, 5)))
    plans.append(StoreyPlan("ground", _m(3.5), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("store", STORAGE, _rect(0, 0, 8, 5)))
    plans.append(StoreyPlan("first", _m(3), first^))
    var b = assemble(
        "frame",
        Site(Angle64(40, DEGREE64), Angle64(-105, DEGREE64), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        Length64(1e-6, METER),
    )
    var column = i_shape(_m(0.2), _m(0.2), _m(0.015), _m(0.01))
    var beam = i_shape(_m(0.15), _m(0.3), _m(0.012), _m(0.008))
    var spots = [
        Point2(0, 0),
        Point2(6, 0),
        Point2(8, 0),
        Point2(8, 5),
        Point2(6, 5),
        Point2(0, 5),
    ]
    for s in range(2):
        for i in range(len(spots)):
            _ = b.add_column(StoreyId(s), spots[i], column, MaterialId(4))
    for s in range(2 if roof_beams else 1):
        # The long edges run past the column at x = 6, so the view splits
        # them there.
        _ = b.add_beam(
            StoreyId(s), Point2(0, 0), Point2(8, 0), beam, MaterialId(4)
        )
        _ = b.add_beam(
            StoreyId(s), Point2(8, 5), Point2(0, 5), beam, MaterialId(4)
        )
        _ = b.add_beam(
            StoreyId(s), Point2(0, 0), Point2(0, 5), beam, MaterialId(4)
        )
        _ = b.add_beam(
            StoreyId(s), Point2(8, 0), Point2(8, 5), beam, MaterialId(4)
        )
        _ = b.add_beam(
            StoreyId(s), Point2(6, 0), Point2(6, 5), beam, MaterialId(4)
        )
    return b^


def _member_weight(b: Building, g: Float64) raises -> Float64:
    var total = Float64(0)
    for i in range(len(b.elements)):
        ref e = b.elements[i]
        if e.kind.value >= 3:
            total += (
                b.materials[e.material.value().value].density.value
                * e.section.value().area().to(SQUARE_METER)
                * e.start.distance_to(e.end)
                * g
            )
    return total


def _vertical_reaction(solver: StaticSolver, which: Int) raises -> Float64:
    var r = solver.solve(LoadCaseId(which))
    var total = Float64(0)
    for n in range(len(solver.model.nodes)):
        total += r.reactions[6 * n + 2]
    return total


def test_live_loads() raises:
    """The typical live loads of ASCE/SEI 7-16, table 4.3-1."""
    assert_almost_equal(live_load(OFFICE).to(KILOPASCAL), 2.40, atol=1e-12)
    assert_almost_equal(live_load(CORRIDOR).to(KILOPASCAL), 4.79, atol=1e-12)
    assert_almost_equal(live_load(STORAGE).to(KILOPASCAL), 6.00, atol=1e-12)
    assert_almost_equal(live_load(MECHANICAL).to(KILOPASCAL), 7.18, atol=1e-12)
    assert_almost_equal(roof_live_load().to(KILOPASCAL), 0.96, atol=1e-12)
    with assert_raises(contains="use"):
        _ = live_load(SpaceUse(12))


def test_frame_view_balances_gravity() raises:
    """The tributary view of a two-storey steel frame.

    Reference: the vertical reactions equal the member weight plus the
    floor and roof construction weight (dead), and the floor area times
    the storage live load plus the roof area times the roof live load
    (live). The floor is 40 m² and the roof is 40 m².
    """
    var b = _building(True)
    var g = 9.80665
    var view = structural_view(b, default_options())
    assert_equal(len(view.model.shells), 0)
    # 12 columns, and per level 5 beams of which 2 split in two.
    assert_equal(len(view.model.members), 12 + 2 * 7)
    assert_equal(len(view.member_element), len(view.model.members))
    var notes = String()
    for i in range(len(view.notes)):
        notes += view.notes[i] + "\n"
    assert_true("6 column bases are fixed" in notes, notes)
    assert_true("ground slabs" in notes, notes)
    var solver = StaticSolver(view.model.copy())
    # The slab is 50 mm of gypsum board and 200 mm of concrete.
    var areal = (
        b.materials[2].density.value * 0.05 + b.materials[3].density.value * 0.2
    )
    var dead = _member_weight(b, g) + 2 * 40 * areal * g
    var live = 40 * 6000.0 + 40 * 960.0
    assert_almost_equal(_vertical_reaction(solver, 0), dead, atol=1e-9 * dead)
    assert_almost_equal(_vertical_reaction(solver, 1), live, atol=1e-9 * live)


def test_shell_view_balances_gravity() raises:
    """The shell view of the same frame, with two divisions.

    Reference: as for the tributary view. The shell mass per area equals
    the construction's, so the dead load is the same.
    """
    var b = _building(True)
    var g = 9.80665
    var options = default_options()
    options.shell_divisions = 2
    var view = structural_view(b, options)
    assert_true(len(view.model.shells) > 0)
    assert_equal(len(view.shell_element), len(view.model.shells))
    # The beams are split at the shell corners on them.
    assert_true(len(view.model.members) > 12 + 2 * 7)
    var solver = StaticSolver(view.model.copy())
    var areal = (
        b.materials[2].density.value * 0.05 + b.materials[3].density.value * 0.2
    )
    var dead = _member_weight(b, g) + 2 * 40 * areal * g
    var live = 40 * 6000.0 + 40 * 960.0
    assert_almost_equal(_vertical_reaction(solver, 0), dead, atol=1e-9 * dead)
    assert_almost_equal(_vertical_reaction(solver, 1), live, atol=1e-9 * live)


def test_view_records_what_it_drops() raises:
    """A roof with no beams loses its load, and the view says so."""
    var b = _building(False)
    var wall = 0
    while b.elements[wall].kind.value != 0:
        wall += 1
    _ = b.add_opening(
        WINDOW, ElementId(wall), _m(1), _m(1), _m(1), _m(1), double_glazing()
    )
    var view = structural_view(b, default_options())
    var notes = String()
    for i in range(len(view.notes)):
        notes += view.notes[i] + "\n"
    assert_true("no beam at its level" in notes, notes)
    assert_true("walls are not structural" in notes, notes)
    assert_true("1 openings are ignored" in notes, notes)


def _single_storey(outline: List[Point2], frame: Bool) raises -> Building:
    """One 3 m storey of one office, with a column at each corner and a
    beam along each edge if asked. No outline gives no storey."""
    var materials = List[BuildingMaterial]()
    materials.append(concrete())
    materials.append(steel())
    var constructions = List[Construction]()
    constructions.append(Construction("slab", [Layer(MaterialId(0), _m(0.2))]))
    var plans = List[StoreyPlan]()
    var spaces = List[SpacePlan]()
    if len(outline) > 0:
        spaces.append(SpacePlan("office", OFFICE, outline.copy()))
        plans.append(StoreyPlan("ground", _m(3), spaces^))
    var all = ConstructionId(0)
    var b = assemble(
        "single",
        Site(Angle64(0, DEGREE64), Angle64(0, DEGREE64), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(all, all, all, all, all),
        Length64(1e-6, METER),
    )
    var column = i_shape(_m(0.2), _m(0.2), _m(0.015), _m(0.01))
    var beam = i_shape(_m(0.15), _m(0.3), _m(0.012), _m(0.008))
    for i in range(len(outline) if frame else 0):
        var j = (i + 1) % len(outline)
        _ = b.add_column(StoreyId(0), outline[i], column, MaterialId(1))
        _ = b.add_beam(StoreyId(0), outline[i], outline[j], beam, MaterialId(1))
    return b^


def test_l_shaped_roof() raises:
    """An L-shaped roof of 27 m² on six beams.

    Reference: the vertical reactions equal the frame and roof weights
    (dead) and the roof area times the roof live load (live). Part of the
    L's bounding box lies outside it, and those samples are skipped.
    """
    var outline: List[Point2] = [
        Point2(0, 0),
        Point2(6, 0),
        Point2(6, 3),
        Point2(3, 3),
        Point2(3, 6),
        Point2(0, 6),
    ]
    var b = _single_storey(outline, True)
    var view = structural_view(b, default_options())
    var solver = StaticSolver(view.model.copy())
    var g = 9.80665
    var dead = _member_weight(b, g) + 27 * 2400 * 0.2 * g
    assert_almost_equal(_vertical_reaction(solver, 0), dead, atol=1e-9 * dead)
    assert_almost_equal(
        _vertical_reaction(solver, 1), 27 * 960.0, atol=1e-9 * 27 * 960
    )


def test_buildings_without_a_frame() raises:
    """A building with no columns or beams, and one with no storeys, give
    a model with no members."""
    var bare = _single_storey(
        [Point2(0, 0), Point2(4, 0), Point2(4, 4), Point2(0, 4)], False
    )
    var view = structural_view(bare, default_options())
    assert_equal(len(view.model.members), 0)
    var notes = String()
    for i in range(len(view.notes)):
        notes += view.notes[i] + "\n"
    assert_true("0 column bases are fixed" in notes, notes)
    var empty = _single_storey(List[Point2](), False)
    var nothing = structural_view(empty, default_options())
    assert_equal(len(nothing.model.nodes), 0)


def test_option_refusals() raises:
    var b = _building(True)
    var options = default_options()
    options.tolerance = _m(0)
    with assert_raises(contains="tolerance"):
        _ = structural_view(b, options)
    options = default_options()
    options.tolerance = _m(inf[DType.float64]())
    with assert_raises(contains="tolerance"):
        options.check()
    options = default_options()
    options.shell_divisions = -1
    with assert_raises(contains="divisions"):
        options.check()
    options.shell_divisions = 17
    with assert_raises(contains="divisions"):
        options.check()
    options = default_options()
    options.gravity = Acceleration64(-1)
    with assert_raises(contains="gravity"):
        options.check()
    options.gravity = Acceleration64(nan[DType.float64]())
    with assert_raises(contains="gravity"):
        options.check()
    options.gravity = Acceleration64(inf[DType.float64]())
    with assert_raises(contains="gravity"):
        options.check()
    # A beam without a section cannot be a member.
    var last = len(b.elements) - 1
    b.elements[last].section = None
    with assert_raises(contains="section"):
        _ = structural_view(b, default_options())
    b.elements[last].section = b.elements[last - 1].section
    b.elements[last].material = None
    with assert_raises(contains="section"):
        _ = structural_view(b, default_options())


def test_mutated_building_references_are_refused_before_conversion() raises:
    for field in range(4):
        var b = _building(True)
        if field == 0:
            # Surface ownership must be checked before e.faces[0] is read.
            b.elements[0].faces.clear()
        elif field == 1:
            b.elements[0].faces[0] = FaceId(999)
        elif field == 2:
            b.topology.face_level.clear()
        else:
            var last = len(b.elements) - 1
            b.elements[last].material = MaterialId(999)
        with assert_raises(contains=""):
            _ = structural_view(b, default_options())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
