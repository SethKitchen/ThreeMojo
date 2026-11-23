# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the input decks of `extensions.fem.deck`.

The deck format is that of Dhondt, "CalculiX CrunchiX User's Manual". The
bar reference is Hooke's law: a bar in uniform tension stretches by
σ L / E. The other references are the same problems built in code.
"""

from std.math import inf, nan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.fem.deck import (
    Deck,
    DeckUnits,
    deck_text,
    millimeter_units,
    parse_deck,
    read_deck,
    si_units,
)
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import (
    DOF_X,
    DOF_Y,
    DOF_Z,
    MaterialId,
    NodeId,
    QUADRATIC,
)
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.static import StaticProblem, solve_static
from extensions.numerics.iterative import CONVERGED
from extensions.sdf.vector import v3
from tests.test_scratch import TestScratch, temporary_path
from units.si import (
    Acceleration64,
    Density64,
    Force64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    NEWTON,
    PASCAL,
    Pressure64,
)


def _m(value: Float64) -> Length64:
    return Length64(value, METER)


def _steel() raises -> IsotropicMaterial:
    return IsotropicMaterial(Pressure64(200e9, PASCAL), 0.3)


def _bar(quadratic: Bool) raises -> StaticProblem:
    """A 2 m bar pulled by 50 MPa, held on three planes of symmetry."""
    var mesh = box_mesh(_m(2), _m(1), _m(1), 2, 1, 1)
    if quadratic:
        mesh = quadratic_mesh(mesh)
    # The second material has no element.
    var problem = StaticProblem(mesh^, [_steel(), _steel()])
    var axes = [DOF_X, DOF_Y, DOF_Z]
    for a in range(3):
        var held = problem.mesh.nodes_on_plane(axes[a], _m(0), _m(1e-9))
        for i in range(len(held)):
            problem.fix(held[i], axes[a], _m(0))
    _ = problem.press_plane(DOF_X, _m(2), _m(1e-9), Pressure64(50e6, PASCAL))
    return problem^


def _round_trip(quadratic: Bool) raises:
    var problem = _bar(quadratic)
    var text = deck_text(problem, "A bar in tension")
    var deck = parse_deck(text, si_units())
    var again = deck.problem()
    assert_equal(again.mesh.node_count(), problem.mesh.node_count())
    assert_equal(again.mesh.element_count(), problem.mesh.element_count())
    assert_true(again.mesh.order == problem.mesh.order)
    assert_equal(len(again.materials), 2)
    var first = solve_static(problem, 1e-13, 5000)
    var second = solve_static(again, 1e-13, 5000)
    assert_true(second.status == CONVERGED)
    var stretch = 50e6 * 2 / 200e9
    for n in range(problem.mesh.node_count()):
        var a = first.displacement(NodeId(n))
        var b = second.displacement(NodeId(n))
        assert_almost_equal(b.x, a.x, atol=1e-11 * stretch + 1e-18)
        assert_almost_equal(b.y, a.y, atol=1e-11 * stretch + 1e-18)
        assert_almost_equal(b.z, a.z, atol=1e-11 * stretch + 1e-18)
        var x = problem.mesh.nodes[n].x
        assert_almost_equal(b.x, stretch * x / 2, atol=1e-8 * stretch)


def test_linear_bar_round_trip() raises:
    """A bar of four-node elements, written as a deck and read back.

    Reference: Hooke's law. The end moves by σ L / E, and the deck gives
    the displacements of the problem it was written from.
    """
    _round_trip(False)


def test_quadratic_bar_round_trip() raises:
    """The same bar with ten-node elements."""
    _round_trip(True)


comptime _TET = """** One tetrahedron, in millimeters.
*HEADING
A single tetrahedron
*NODE, NSET=Nall
1, 0, 0, 0
2, 1000, 0, 0
3, 0, 1000, 0

4, 0, 0, 1000
*ELEMENT, TYPE=C3D4, ELSET=Eall
7, 1, 2, 3, 4
*NSET, NSET=Base
1, 2, 3,
1
*NSET, NSET=Gen, GENERATE
1, 3, 2
*NSET, NSET=Pair, GENERATE
1, 2
*NSET, NSET=Three, GENERATE
1, 3,
*ELSET, ELSET=Copy
7
*ELSET, ELSET=Copy
7
*MATERIAL, NAME=Other
*ELASTIC, TYPE=ISO
1000, 0.2
*MATERIAL, NAME=Steel
*ELASTIC
210000, 0.3
*DENSITY
7.85e-9
*SOLID SECTION, ELSET=Eall, MATERIAL=Steel
1.0
*BOUNDARY
Base, 1, 3
*STEP
*STATIC
1., 1.
*CLOAD
4, 3, -1000
*DLOAD
Eall, GRAV, 9810, 0, 0, -1
*NODE FILE
U
*EL FILE
S
*NODE PRINT, NSET=Nall
U
*EL PRINT, ELSET=Eall
S
*END STEP
"""


def test_keywords_of_a_small_deck() raises:
    """Each keyword of the subset, in a deck of millimeters and newtons.

    Reference: the same tetrahedron built in code, in meters. A deck
    stress is a megapascal and a deck density is a tonne per cubic
    millimeter, which is 1e12 kg/m³.
    """
    var deck = parse_deck(_TET, millimeter_units())
    assert_equal(deck.mesh.node_count(), 4)
    assert_equal(deck.mesh.element_count(), 1)
    assert_almost_equal(deck.mesh.nodes[1].x, 1.0, atol=1e-15)
    assert_almost_equal(deck.mesh.nodes[3].z, 1.0, atol=1e-15)
    assert_equal(deck.node(4).value, 3)
    assert_equal(deck.element(7).value, 0)
    assert_equal(deck.node_numbers[2], 3)
    assert_equal(deck.element_numbers[0], 7)
    assert_equal(len(deck.node_sets["NALL"]), 4)
    assert_equal(len(deck.node_sets["BASE"]), 3)
    assert_equal(len(deck.node_sets["GEN"]), 2)
    assert_equal(deck.node_sets["GEN"][1], 2)
    assert_equal(len(deck.node_sets["PAIR"]), 2)
    assert_equal(len(deck.node_sets["THREE"]), 3)
    assert_equal(len(deck.element_sets["COPY"]), 1)
    assert_equal(len(deck.materials), 2)
    assert_equal(deck.material_names[1], "STEEL")
    assert_almost_equal(deck.materials[1].young.to(PASCAL), 210e9, atol=1e-3)
    assert_almost_equal(deck.materials[1].poisson, 0.3, atol=0)
    assert_almost_equal(deck.densities[1], 7850.0, atol=1e-9)
    assert_almost_equal(deck.densities[0], 0.0, atol=0)
    assert_equal(deck.mesh.materials[0], 1)
    assert_equal(len(deck.supports), 9)
    assert_equal(len(deck.loads), 1)
    assert_almost_equal(deck.loads[0].value, -1000.0, atol=0)
    assert_almost_equal(deck.gravity, 9.81, atol=1e-12)
    var problem = deck.problem()
    # The point load and a quarter of the weight ρ g V act on node 4.
    var weight = 7850 * 9.81 / 6
    assert_almost_equal(problem.forces[11], -1000 - weight / 4, atol=1e-9)
    assert_almost_equal(problem.forces[2], -weight / 4, atol=1e-9)
    assert_true(problem.prescribed[0])
    assert_true(problem.prescribed[8])
    assert_true(not problem.prescribed[9])
    with assert_raises(contains="no node 9"):
        _ = deck.node(9)
    with assert_raises(contains="no element 1"):
        _ = deck.element(1)


def test_boundary_forms() raises:
    """The forms of a boundary line and of a load line."""
    var text = (
        String(_TET)
        .replace(
            "Base, 1, 3\n",
            "1, 1, 1, 0.5\n2, 2, , 0.25\n3, 3, 3,\n4, 1\nGen, 2\n",
        )
        .replace("4, 3, -1000\n", "Gen, 1, 5\n4, 2, 7\n")
    )
    var deck = parse_deck(text, millimeter_units())
    assert_equal(len(deck.supports), 6)
    assert_almost_equal(deck.supports[0].value, 0.0005, atol=1e-18)
    assert_equal(deck.supports[1].axis, 1)
    assert_almost_equal(deck.supports[1].value, 0.00025, atol=1e-18)
    assert_almost_equal(deck.supports[2].value, 0.0, atol=0)
    assert_equal(deck.supports[3].node, 3)
    assert_equal(deck.supports[5].node, 2)
    assert_equal(len(deck.loads), 3)
    assert_equal(deck.loads[1].node, 2)
    assert_equal(deck.loads[2].axis, 1)
    # A deck with no boundary and no load still gives a problem, and a
    # gravity load can name no set.
    var bare = (
        String(_TET)
        .replace("*BOUNDARY\nBase, 1, 3\n", "")
        .replace("*CLOAD\n4, 3, -1000\n", "")
    )
    var free = parse_deck(bare, millimeter_units())
    assert_equal(len(free.supports), 0)
    _ = free.problem()
    var quiet = bare.replace("*DLOAD\nEall, GRAV, 9810, 0, 0, -1\n", "")
    var still = parse_deck(quiet, millimeter_units()).problem()
    assert_almost_equal(still.forces[11], 0.0, atol=0)
    # A set line of commas alone adds nothing.
    var commas = String(_TET).replace("1, 2, 3,\n1\n", ",\n1, 2, 3,\n")
    assert_equal(
        len(parse_deck(commas, millimeter_units()).node_sets["BASE"]), 3
    )
    var unnamed = String(_TET).replace("Eall, GRAV", ", GRAV")
    assert_almost_equal(
        parse_deck(unnamed, millimeter_units()).gravity, 9.81, atol=1e-12
    )


def test_pressure_on_each_face() raises:
    """A pressure of 2 MPa on each face of one tetrahedron, in millimeters.

    Reference: the faces are 1-2-3, 1-4-2, 2-4-3 and 3-4-1. A positive
    pressure pushes into the element with a force of the pressure times
    the area, and each corner of the face takes a third. Three faces have
    an area of 0.5 m². The fourth has the normal (1, 1, 1) and an area of
    sqrt(3) / 2 m².
    """
    var third = 2e6 * 0.5 / 3
    # The face, the node off the face, and the push on each node of it.
    var labels = ["P1", "P2", "P3", "P4"]
    var off = [3, 2, 0, 1]
    var pushes = [
        v3(0, 0, third),
        v3(0, third, 0),
        v3(-third, -third, -third),
        v3(third, 0, 0),
    ]
    for face in range(4):
        var text = (
            String(_TET)
            .replace("Eall, GRAV, 9810, 0, 0, -1", "7, " + labels[face] + ", 2")
            .replace("4, 3, -1000\n", "")
        )
        var deck = parse_deck(text, millimeter_units())
        assert_equal(len(deck.loads), 9)
        var forces = deck.problem().forces.copy()
        for node in range(4):
            var expected = pushes[face]
            if node == off[face]:
                expected = v3(0, 0, 0)
            assert_almost_equal(forces[3 * node], expected.x, atol=1e-6)
            assert_almost_equal(forces[3 * node + 1], expected.y, atol=1e-6)
            assert_almost_equal(forces[3 * node + 2], expected.z, atol=1e-6)
    # An element with its last two nodes swapped is inverted. Its face
    # P1 is then 1-2-4, in the plane y = 0, and the push is still inward.
    var inverted = (
        String(_TET)
        .replace("7, 1, 2, 3, 4", "7, 1, 2, 4, 3")
        .replace("Eall, GRAV, 9810, 0, 0, -1", "7, P1, 2")
        .replace("4, 3, -1000\n", "")
    )
    var turned = parse_deck(inverted, millimeter_units()).problem()
    assert_almost_equal(turned.forces[1], third, atol=1e-6)
    assert_almost_equal(turned.forces[4], third, atol=1e-6)
    assert_almost_equal(turned.forces[10], third, atol=1e-6)
    assert_almost_equal(turned.forces[7], 0.0, atol=0)
    # An element set as the target gives the same forces.
    var by_set = (
        String(_TET)
        .replace("Eall, GRAV, 9810, 0, 0, -1", "Eall, P1, 2")
        .replace("4, 3, -1000\n", "")
    )
    var forces = parse_deck(by_set, millimeter_units()).problem().forces.copy()
    assert_almost_equal(forces[2], third, atol=1e-6)


def _pressed_bar(quadratic: Bool) raises:
    """Compare a bar pulled by face pressures with `press_plane`."""
    var problem = _bar(quadratic)
    var bare = _bar(quadratic)
    for i in range(len(bare.forces)):
        bare.forces[i] = 0
    var text = deck_text(bare, "A bar with no load")
    # A pull of 50 MPa on each element face that lies on the end x = 2 m.
    var corners = [0, 1, 2, 0, 3, 1, 1, 3, 2, 2, 3, 0]
    var per = problem.mesh.nodes_per_element()
    var lines = String("*DLOAD\n")
    var count = 0
    for e in range(problem.mesh.element_count()):
        for face in range(4):
            var on_end = True
            for n in range(3):
                var node = problem.mesh.corners[per * e + corners[3 * face + n]]
                if abs(problem.mesh.nodes[node].x - 2) > 1e-9:
                    on_end = False
            if on_end:
                lines += String(e + 1, ", P", face + 1, ", -50e6\n")
                count += 1
    assert_equal(count, 2)
    var deck = parse_deck(
        text.replace("*NODE FILE", lines + "*NODE FILE"), si_units()
    )
    var forces = deck.problem().forces.copy()
    for i in range(len(forces)):
        assert_almost_equal(forces[i], problem.forces[i], atol=1e-6)


def test_face_pressure_matches_press_plane() raises:
    """A bar pulled by a pressure of -50 MPa on its end faces.

    Reference: `press_plane` on the same faces, for four-node and for
    ten-node elements. A ten-node element puts the force on its edge
    nodes.
    """
    _pressed_bar(False)
    _pressed_bar(True)


comptime _TEN = """*NODE
1, 0, 0, 0
2, 2, 0, 0
3, 0, 2, 0
4, 0, 0, 2
5, 1, 0, 0
6, 1, 1, 0
7, 0, 1, 0
8, 0, 0, 1
9, 1, 0, 1
10, 0, 1, 1
*ELEMENT, TYPE=C3D10, ELSET=E
1, 1, 2, 3, 4, 5, 6,
7, 8, 9, 10
*MATERIAL, NAME=M
*ELASTIC
100, 0.25
*SOLID SECTION, ELSET=E, MATERIAL=M
"""


def test_ten_node_element() raises:
    """A ten-node element on two lines, and the same element inverted.

    Reference: the edge nodes follow the edges 1-2, 2-3, 1-3, 1-4, 2-4
    and 3-4. An element with corners 3 and 4 swapped is turned back, with
    its edge nodes.
    """
    var deck = parse_deck(_TEN, si_units())
    assert_true(deck.mesh.order == QUADRATIC)
    for i in range(10):
        assert_equal(deck.mesh.corners[i], i)
    # Corners 1, 2, 4, 3 with the edge nodes of 1-2, 2-4, 1-4, 1-3, 2-3
    # and 4-3.
    var inverted = String(_TEN).replace(
        "1, 1, 2, 3, 4, 5, 6,\n7, 8, 9, 10", "1, 1, 2, 4, 3, 5, 9, 8, 7, 6, 10"
    )
    var turned = parse_deck(inverted, si_units())
    for i in range(10):
        assert_equal(turned.mesh.corners[i], i)
    var second = String(_TEN).replace(
        "7, 8, 9, 10\n", "7, 8, 9, 10\n2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10\n"
    )
    assert_equal(parse_deck(second, si_units()).mesh.element_count(), 2)


def test_deck_file() raises:
    var path = temporary_path("tet.inp")
    Path(path).write_text(_TET)
    var deck = read_deck(path, millimeter_units())
    assert_equal(deck.mesh.element_count(), 1)


def test_units() raises:
    var units = millimeter_units()
    assert_almost_equal(units.stress(), 1e6, atol=1e-6)
    assert_almost_equal(units.density() / 1e12, 1.0, atol=1e-12)
    assert_almost_equal(si_units().stress(), 1.0, atol=0)
    with assert_raises(contains="deck length"):
        _ = DeckUnits(_m(0), Force64(1, NEWTON))
    with assert_raises(contains="deck force"):
        _ = DeckUnits(_m(1), Force64(inf[DType.float64](), NEWTON))


def _refuse(text: String, part: String) raises:
    with assert_raises(contains=part):
        _ = parse_deck(text, millimeter_units())


def _swap(old: String, new: String, part: String) raises:
    """Refuse the small deck with one piece of its text replaced."""
    assert_true(old in String(_TET), old)
    _refuse(String(_TET).replace(old, new), part)


def test_keyword_refusals() raises:
    _swap("*HEADING", "*CONTACT PAIR", "is not supported")
    _swap("TYPE=C3D4, ", "", "needs TYPE=")
    _swap("TYPE=C3D4", "TYPE=C3D8", "C3D8 is not supported")
    _swap("*NSET, NSET=Base", "*NSET", "needs NSET=")
    _swap("*ELSET, ELSET=Copy\n7\n*ELSET, ELSET=Copy", "*ELSET", "needs ELSET=")
    _swap("NAME=Other", "", "needs NAME=")
    _swap("NAME=Other", "NAME=Steel", "STEEL repeats")
    _swap("TYPE=ISO", "TYPE=ORTHO", "TYPE=ISO")
    _swap("*MATERIAL, NAME=Other\n", "", "must follow a *MATERIAL")
    _swap(
        "*MATERIAL, NAME=Other\n*ELASTIC, TYPE=ISO\n1000, 0.2\n",
        "*DENSITY\n1\n",
        "must follow a *MATERIAL",
    )
    _swap("ELSET=Eall, MATERIAL=Steel", "MATERIAL=Steel", "needs ELSET=")
    _swap("ELSET=Eall, MATERIAL=Steel", "ELSET=Eall", "needs MATERIAL=")
    _swap("*STEP", "*STEP, NLGEOM", "NLGEOM")
    _swap("*END STEP\n", "*END STEP\n*STEP\n", "one *STEP only")
    _swap("*STEP\n", "", "*STATIC must be in a *STEP")
    _swap("*STEP\n*STATIC\n1., 1.\n", "", "*CLOAD must be in a *STEP")
    _swap(
        "*STEP\n*STATIC\n1., 1.\n*CLOAD\n4, 3, -1000\n",
        "",
        "*DLOAD must be in a *STEP",
    )
    _swap("*HEADING", "*END STEP", "*END STEP must be in a *STEP")
    _swap("*END STEP\n", "", "no *END STEP")
    # A parameter with no name is passed over.
    var deck = parse_deck(
        String(_TET).replace("*NODE, NSET=Nall", "*NODE, , NSET=Nall"),
        millimeter_units(),
    )
    assert_equal(len(deck.node_sets["NALL"]), 4)


def test_data_refusals() raises:
    _swap("1, 0, 0, 0", "1, 0, 0", "a node needs")
    _swap("1, 0, 0, 0", "x, 0, 0, 0", "is not an integer")
    _swap("1, 0, 0, 0", "1, a, 0, 0", "is not a number")
    _swap("1, 0, 0, 0", "1, 1e999, 0, 0", "must be finite")
    _swap("1, 0, 0, 0", "0, 0, 0, 0", "positive and new")
    _swap("2, 1000, 0, 0", "1, 1000, 0, 0", "positive and new")
    _swap("7, 1, 2, 3, 4", "7, 1, 2, 3", "needs a number and 4 nodes")
    _swap("7, 1, 2, 3, 4", "0, 1, 2, 3, 4", "element number")
    _swap("7, 1, 2, 3, 4", "7, 1, 2, 3, 4\n7, 1, 2, 3, 4", "element number")
    _swap("7, 1, 2, 3, 4", "7, 1, 2, 3, 9", "names node 9")
    _swap("7, 1, 2, 3, 4", "7, 1, 2, 3,", "ends with a comma")
    _swap("1, 2, 3,\n1\n", "9\n", "names number 9")
    _swap("*ELSET, ELSET=Copy\n7\n", "*ELSET, ELSET=Copy\n8\n", "number 8")
    _swap("1, 3, 2\n", "1\n", "a first and a last")
    _swap("1, 3, 2\n", "1, 3, 0\n", "positive step")
    _swap("1, 3, 2\n", "3, 1\n", "positive step")
    _swap("1, 3, 2\n", "1, 99999999999\n", "too many")
    _swap("210000, 0.3", "210000", "Young's modulus and Poisson")
    _swap("210000, 0.3", "210000, 0.3\n200000, 0.3, 400", "one line")
    _swap("7.85e-9", "-1", "zero or more")
    _swap("Base, 1, 3", "Base", "a node and a degree")
    _swap("Base, 1, 3", "None, 1, 3", "no node set NONE")
    _swap("Base, 1, 3", "9, 1, 3", "no node 9")
    _swap("Base, 1, 3", "Base, 0, 3", "1, 2 or 3")
    _swap("Base, 1, 3", "Base, 1, 4", "1, 2 or 3")
    _swap("Base, 1, 3", "Base, 3, 1", "below the first")
    _swap("4, 3, -1000", "4, 3", "a degree of freedom and a value")
    _swap("Eall, GRAV, 9810, 0, 0, -1", "Eall, GRAV, 9810", "GRAV")
    _swap("Eall, GRAV, 9810, 0, 0, -1", "Eall, P5, 1, 0, 0, 0", "GRAV")
    _swap("Eall, GRAV, 9810, 0, 0, -1", "Eall, P1", "GRAV")
    _swap("Eall, GRAV, 9810, 0, 0, -1", "9, P1, 2", "element set 9")
    _swap("Eall, GRAV, 9810, 0, 0, -1", "None, P1, 2", "element set NONE")
    _swap("Eall, GRAV, 9810, 0, 0, -1", "7, P1, much", "is not a number")
    _swap(
        "Eall, GRAV, 9810, 0, 0, -1",
        "Eall, GRAV, 9810, 0, 0, -1\nEall, GRAV, 9810, 0, 0, -1",
        "one GRAV",
    )
    _swap("Eall, GRAV", "None, GRAV", "no element set NONE")
    _swap("*MATERIAL, NAME=Other\n", "*MATERIAL, NAME=Other\n5\n", "no keyword")
    _swap("*STEP\n", "*STEP\n5\n", "no keyword")
    _swap("*END STEP\n", "*END STEP\n5\n", "no keyword")
    _swap("** One tetrahedron, in millimeters.\n", "5\n", "no keyword")


def test_whole_deck_refusals() raises:
    _swap(
        "*MATERIAL, NAME=Other\n*ELASTIC, TYPE=ISO\n1000, 0.2\n",
        "*MATERIAL, NAME=Other\n",
        "OTHER has no *ELASTIC",
    )
    _swap("MATERIAL=Steel", "MATERIAL=Brass", "names material BRASS")
    _swap("ELSET=Eall, MATERIAL", "ELSET=None, MATERIAL", "element set NONE")
    _swap("*SOLID SECTION, ELSET=Eall, MATERIAL=Steel\n1.0\n", "", "Element 7")
    _swap("4, 0, 0, 1000\n", "4, 0, 0, 1000\n5, 1, 1, 1\n", "Node 5 belongs")
    _refuse("*NODE\n1, 0, 0, 0\n", "no element")
    # A section with no material at all, and an element in no set.
    with assert_raises(contains="names material M"):
        _ = parse_deck(
            String(_TEN).replace(
                "*MATERIAL, NAME=M\n*ELASTIC\n100, 0.25\n", ""
            ),
            si_units(),
        )
    _swap(
        "*ELEMENT, TYPE=C3D4, ELSET=Eall",
        "*ELEMENT, TYPE=C3D4",
        "no element set EALL",
    )
    _refuse(
        String(_TET) + "*ELEMENT, TYPE=C3D4\n8, 1, 2, 3,", "ends with a comma"
    )
    # A second element of the other type cannot join the mesh.
    _swap(
        "7, 1, 2, 3, 4\n",
        (
            "7, 1, 2, 3, 4\n*ELEMENT, TYPE=C3D10\n8, 1, 2, 3, 4, 1, 2, 3, 4,"
            " 1, 2\n"
        ),
        "cannot mix",
    )
    with assert_raises(contains="not flat"):
        _ = parse_deck(
            String(_TEN).replace("4, 0, 0, 2", "4, 1, 1, 0"), si_units()
        )
    # A gravity load on a part of the mesh is refused.
    var two = (
        String(_TET)
        .replace(
            "7, 1, 2, 3, 4\n",
            "7, 1, 2, 3, 4\n*ELEMENT, TYPE=C3D4, ELSET=Rest\n8, 1, 2, 3, 4\n",
        )
        .replace(
            "*SOLID SECTION, ELSET=Eall, MATERIAL=Steel",
            (
                "*SOLID SECTION, ELSET=Rest, MATERIAL=Other\n*SOLID SECTION,"
                " ELSET=Eall, MATERIAL=Steel"
            ),
        )
    )
    _refuse(two, "every element")


def test_writer_refusals() raises:
    var problem = _bar(False)
    with assert_raises(contains="title"):
        _ = deck_text(problem, "two\nlines")
    with assert_raises(contains="title"):
        _ = deck_text(problem, " *NODE")
    problem.thermal[0] = 1e-3
    with assert_raises(contains="thermal"):
        _ = deck_text(problem, "hot")


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
