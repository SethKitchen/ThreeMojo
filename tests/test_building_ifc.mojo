# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for IFC exchange: the STEP physical file of ISO 10303-21 and the
IFC4 mapping of the building model.

The reference for the mapping is the round trip: a model written and read
back has the same fingerprint, so every storey, space, element, opening,
material and construction came back exactly.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.building.construction import (
    Construction,
    Layer,
    double_glazing,
)
from extensions.building.fingerprint import fingerprint
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    StoreyId,
)
from extensions.building.ifc.ifc4 import ifc_guid, read_ifc, write_ifc
from extensions.building.ifc.step import (
    DERIVED,
    ENUMERATION,
    INTEGER,
    LIST,
    REAL,
    REFERENCE,
    STRING,
    StepFile,
    StepKind,
    TYPED,
    UNSET,
    encode_string,
    format_real,
    parse,
)
from extensions.building.kinds import (
    CIRCLE,
    CORRIDOR,
    DOOR,
    KITCHEN,
    OFFICE,
    WALL,
    WINDOW,
)
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
    Section,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    i_shape,
    rectangle,
)
from extensions.building.generate.tower import TowerOptions, generate_tower
from generators.skyscraper import SkyscraperParameters
from extensions.topology.arrangement import Point2, Region
from extensions.topology.storeys import build_storeys
from units.si import Angle64, DEGREE, DEGREE64, Length, Length64, METER


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64) -> List[Point2]:
    return [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]


def _building() raises -> Building:
    var materials = List[BuildingMaterial]()
    materials.append(brick())
    materials.append(mineral_wool())
    materials.append(gypsum_board())
    materials.append(concrete())
    materials.append(steel())
    var constructions = List[Construction]()
    constructions.append(
        Construction(
            "exterior wall",
            [
                Layer(MaterialId(0), _m(0.2)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    constructions.append(
        Construction("partition", [Layer(MaterialId(2), _m(0.1))])
    )
    constructions.append(Construction("slab", [Layer(MaterialId(3), _m(0.25))]))
    constructions.append(Construction("roof", [Layer(MaterialId(3), _m(0.3))]))
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("office", OFFICE, _rect(0, 0, 6, 5)))
    ground.append(SpacePlan("hall", CORRIDOR, _rect(6, 0, 8.5, 5)))
    plans.append(StoreyPlan("ground", _m(3.5), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("kitchen", KITCHEN, _rect(0, 0, 8.5, 5)))
    plans.append(StoreyPlan("first", _m(3.1), first^))
    var crown = List[SpacePlan]()
    crown.append(SpacePlan("lantern", OFFICE, _rect(3, 1.5, 5, 3.5)))
    plans.append(StoreyPlan("crown", _m(2.4), crown^))
    var b = assemble(
        "IFC test",
        Site(
            Angle64(39.7392, DEGREE64),
            Angle64(-104.9903, DEGREE64),
            _m(1609),
            Angle64(12, DEGREE64),
        ),
        _m(0.15),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(3),
        ),
        Length64(1e-6, METER),
    )
    # Openings in two walls, facing either way along the model axes.
    var count = 0
    for e in range(len(b.elements)):
        if b.elements[e].kind != WALL or count >= 2:
            continue
        var frame = b.wall_frame(ElementId(e))
        if frame.length < 4 or frame.height < 3:
            continue
        _ = b.add_opening(
            WINDOW,
            ElementId(e),
            _m(0.5),
            _m(0.9),
            _m(1.2),
            _m(1.3),
            double_glazing(),
        )
        _ = b.add_opening(
            DOOR, ElementId(e), _m(2.5), _m(0), _m(0.9), _m(2.1), None
        )
        count += 1
    var section = i_shape(_m(0.2), _m(0.3), _m(0.012), _m(0.008))
    _ = b.add_column(StoreyId(0), Point2(3, 2.5), section, MaterialId(4))
    _ = b.add_beam(
        StoreyId(0), Point2(0, 2.5), Point2(8.5, 2.5), section, MaterialId(4)
    )
    _ = b.add_beam(
        StoreyId(1),
        Point2(0.3, 0.3),
        Point2(7.7, 4.1),
        rectangle(_m(0.3), _m(0.5)),
        MaterialId(3),
    )
    var round = Section(CIRCLE, _m(0.3), _m(0), _m(0), _m(0))
    _ = b.add_column(StoreyId(1), Point2(4, 2.5), round, MaterialId(3))
    return b^


# --- STEP ----------------------------------------------------------------------


def test_reals_round_trip_in_step_form() raises:
    assert_equal(format_real(1.0), "1.")
    assert_equal(format_real(0.25), "0.25")
    assert_equal(format_real(1e-5), "1.E-05")
    assert_equal(format_real(-2.5e20), "-2.5E+20")
    assert_equal(format_real(-0.0), "-0.")
    var third = 1.0 / 3.0
    assert_equal(atof(format_real(third)), third)
    with assert_raises(contains="finite"):
        _ = format_real(Float64.MAX * 2)


def test_strings_escape_and_decode() raises:
    assert_equal(encode_string("it's"), "it''s")
    assert_equal(encode_string("a\\\\b"), "a\\\\\\\\b")
    assert_equal(encode_string("café"), "caf\\X2\\00E9\\X0\\")
    assert_equal(encode_string("🏠"), "\\X4\\0001F3E0\\X0\\")
    var text = String(
        "ISO-10303-21;\nHEADER;\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n#1=IFCLABEL('caf\\X2\\00E9\\X0\\"
        " it''s \\X\\E9 \\\\"
        " \\X4\\0001F3E0\\X0\\');\nENDSEC;\nEND-ISO-10303-21;\n"
    )
    var f = parse(text)
    assert_equal(f.as_string(f.argument(1, 0)), "café it's é \\ 🏠")


def test_a_file_parses_and_writes_back() raises:
    var text = String(
        "ISO-10303-21;\n/* a comment\nover lines"
        " */\nHEADER;\nFILE_DESCRIPTION(('x'),'2;1');\nENDSEC;\nDATA;\n#7 ="
        " IFCTHING(1, -2.5E+3, 'a', .ENUM., #7, (1, (2, $)), IFCLABEL('t'), $,"
        " *, ());\n#9=ifclower(+3,0.5);\nENDSEC;\nEND-ISO-10303-21;\n"
    )
    var f = parse(text)
    assert_equal(len(f.header), 1)
    assert_equal(len(f.entities), 2)
    assert_true(f.has(7))
    assert_false(f.has(8))
    assert_equal(f.entity(9).name, "IFCLOWER")
    assert_equal(f.as_integer(f.argument(7, 0)), 1)
    assert_equal(f.as_real(f.argument(7, 1)), -2500)
    assert_equal(f.as_real(f.argument(7, 0)), 1)
    assert_equal(f.as_string(f.argument(7, 2)), "a")
    assert_equal(f.as_enumeration(f.argument(7, 3)), "ENUM")
    assert_equal(f.as_reference(f.argument(7, 4)), 7)
    var nested = f.as_list(f.argument(7, 5))
    assert_equal(len(nested), 2)
    assert_true(f.kind_of(f.as_list(nested[1])[1]) == UNSET)
    assert_true(f.kind_of(f.argument(7, 6)) == TYPED)
    assert_equal(f.as_string(f.untyped(f.argument(7, 6))), "t")
    assert_true(f.kind_of(f.argument(7, 8)) == DERIVED)
    assert_equal(len(f.as_list(f.argument(7, 9))), 0)
    assert_equal(f.as_real(f.argument(9, 1)), 0.5)
    assert_equal(len(f.all_of("IFCTHING")), 1)
    # Writing and reading again gives the same text.
    var again = parse(f.write())
    assert_equal(again.write(), f.write())
    assert_true(INTEGER.is_valid())
    assert_false(StepKind(9).is_valid())
    assert_false(StepKind(-1).is_valid())


def test_a_built_file_numbers_its_entities() raises:
    var f = StepFile()
    var a = f.add("IFCA", [f.integer(1), f.real(2.0), f.string("s")])
    var b = f.add(
        "IFCB", [f.reference(a), f.enumeration("E"), f.unset(), f.derived()]
    )
    assert_equal(a, 1)
    assert_equal(b, 2)
    f.add_header("FILE_SCHEMA", [f.list([f.string("IFC4")])])
    var text = f.write()
    assert_true(text.find("#2=IFCB(#1,.E.,$,*);") >= 0)
    with assert_raises(contains="finite"):
        _ = f.real(Float64.MAX * 2)
    with assert_raises(contains="No STEP entity"):
        _ = f.entity(5)
    with assert_raises(contains="no attribute"):
        _ = f.argument(1, 3)
    with assert_raises(contains="no attribute"):
        _ = f.argument(1, -1)
    with assert_raises(contains="an integer"):
        _ = f.as_integer(f.argument(1, 1))
    with assert_raises(contains="a real"):
        _ = f.as_real(f.argument(1, 2))
    with assert_raises(contains="a string"):
        _ = f.as_string(f.argument(1, 0))
    with assert_raises(contains="an enumeration"):
        _ = f.as_enumeration(f.argument(1, 0))
    with assert_raises(contains="a reference"):
        _ = f.as_reference(f.argument(1, 0))
    with assert_raises(contains="a list"):
        _ = f.as_list(f.argument(1, 0))


def _bad(body: String) raises -> String:
    return (
        String("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\n")
        + body
        + "\nENDSEC;\nEND-ISO-10303-21;\n"
    )


def test_parse_refuses_malformed_files() raises:
    with assert_raises(contains="ISO-10303-21"):
        _ = parse("HELLO;")
    with assert_raises(contains="semicolon"):
        _ = parse("ISO-10303-21 HEADER;")
    with assert_raises(contains="HEADER"):
        _ = parse("ISO-10303-21;\nDATA;")
    with assert_raises(contains="DATA"):
        _ = parse("ISO-10303-21;\nHEADER;\nENDSEC;\nFOO;")
    with assert_raises(contains="END-ISO"):
        _ = parse("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\nENDSEC;\nEND;")
    with assert_raises(contains="unclosed comment"):
        _ = parse("ISO-10303-21; /* never closed")
    with assert_raises(contains="line 5"):
        _ = parse(_bad("#1=X('unclosed);"))
    with assert_raises(contains="unclosed string"):
        _ = parse(_bad("#1=X('unclosed);"))
    with assert_raises(contains="repeated"):
        _ = parse(_bad("#1=X(1);\n#1=X(2);"))
    with assert_raises(contains="instance number"):
        _ = parse(_bad("#=X(1);"))
    with assert_raises(contains="instance number"):
        _ = parse(_bad("#1=X(#);"))
    with assert_raises(contains="equals"):
        _ = parse(_bad("#1 X(1);"))
    with assert_raises(contains="a name"):
        _ = parse(_bad("#1=(1);"))
    with assert_raises(contains="parentheses"):
        _ = parse(_bad("#1=X 1;"))
    with assert_raises(contains="comma"):
        _ = parse(_bad("#1=X(1 2);"))
    with assert_raises(contains="expected a value"):
        _ = parse(_bad("#1=X(@);"))
    with assert_raises(contains="dot after"):
        _ = parse(_bad("#1=X(.E);"))
    with assert_raises(contains="parenthesis after a type"):
        _ = parse(_bad("#1=X(T 1);"))
    with assert_raises(contains="closing parenthesis after"):
        _ = parse(_bad("#1=X(T(1 2));"))
    with assert_raises(contains="escape"):
        _ = parse(_bad("#1=X('\\Q');"))
    with assert_raises(contains="hexadecimal digit"):
        _ = parse(_bad("#1=X('\\X\\ZZ');"))
    with assert_raises(contains="short hexadecimal"):
        _ = parse("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\n#1=X('\\X2\\00")
    with assert_raises(contains="entity or ENDSEC"):
        _ = parse("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\nFOO;")


# --- IFC4 ------------------------------------------------------------------------


def test_guids_are_22_characters_and_distinct() raises:
    var a = ifc_guid(7, 1)
    var b = ifc_guid(7, 2)
    assert_equal(a.byte_length(), 22)
    assert_true(a != b)
    assert_equal(a, ifc_guid(7, 1))
    var first = String(a[byte=0])
    assert_true(first == "0" or first == "1" or first == "2" or first == "3")


def test_a_model_round_trips_exactly() raises:
    var b = _building()
    var text = write_ifc(b, "2026-01-01T00:00:00")
    assert_true(text.find("FILE_SCHEMA(('IFC4'))") >= 0)
    assert_true(text.find("IFCARBITRARYPROFILEDEFWITHVOIDS") >= 0)
    var back = read_ifc(text, Length64(1e-6, METER))
    assert_equal(len(back.storeys), 3)
    assert_equal(len(back.spaces), 4)
    assert_equal(len(back.elements), len(b.elements))
    assert_equal(len(back.openings), len(b.openings))
    assert_equal(back.spaces[2].name, "kitchen")
    assert_true(back.spaces[2].use == KITCHEN)
    assert_equal(back.storeys[1].elevation.value, 3.65)
    assert_equal(back.storeys[2].height.value, 2.4)
    assert_almost_equal(
        back.site.latitude.value, b.site.latitude.value, atol=1e-12
    )
    assert_almost_equal(
        back.site.longitude.value, b.site.longitude.value, atol=1e-12
    )
    assert_almost_equal(back.site.north.value, b.site.north.value, atol=1e-12)
    assert_equal(back.site.elevation.value, 1609)
    assert_equal(back.materials[3].look.red, b.materials[3].look.red)
    assert_equal(
        back.materials[4].strength.value, b.materials[4].strength.value
    )
    assert_equal(fingerprint(back), fingerprint(b))
    # The same model gives the same file.
    assert_true(write_ifc(back, "2026-01-01T00:00:00") == text)


def test_read_ifc_refuses() raises:
    var tol = Length64(1e-6, METER)
    with assert_raises(contains="IFC4"):
        _ = read_ifc(
            "ISO-10303-21;\nHEADER;\nFILE_SCHEMA(('IFC2X3'));\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n",
            tol,
        )
    var text = write_ifc(_building(), "t")
    var milli = text.replace(
        "IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)",
        "IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.)",
    )
    with assert_raises(contains="meters"):
        _ = read_ifc(milli, tol)
    var kilo = text.replace(
        "IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)",
        "IFCSIUNIT(*,.LENGTHUNIT.,.KILO.,.METRE.)",
    )
    with assert_raises(contains="meters"):
        _ = read_ifc(kilo, tol)


def test_an_empty_model_round_trips() raises:
    var empty = Building(
        "empty",
        Site(Angle64(0), Angle64(0), _m(0), Angle64(0)),
        List[BuildingMaterial](),
        List[Construction](),
        build_storeys([_m(0)], List[List[Region]](), Length64(1e-6, METER)),
    )
    var text = write_ifc(empty, "t")
    var back = read_ifc(text, Length64(1e-6, METER))
    assert_equal(len(back.storeys), 0)
    assert_equal(back.constructions[0].name, "default slab")
    # A storey with no spaces, an unused material and an unused
    # construction.
    var materials = List[BuildingMaterial]()
    materials.append(concrete())
    materials.append(steel())
    var constructions = List[Construction]()
    constructions.append(Construction("c", [Layer(MaterialId(0), _m(0.2))]))
    constructions.append(
        Construction("unused", [Layer(MaterialId(0), _m(0.1))])
    )
    var plans = List[StoreyPlan]()
    plans.append(StoreyPlan("bare", _m(3), List[SpacePlan]()))
    var c = ConstructionId(0)
    var bare = assemble(
        "bare",
        Site(Angle64(0), Angle64(0), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(c, c, c, c, c),
        Length64(1e-6, METER),
    )
    var again = read_ifc(write_ifc(bare, "t"), Length64(1e-6, METER))
    assert_equal(len(again.storeys), 1)
    assert_equal(fingerprint(again), fingerprint(bare))


def test_step_lexical_corners() raises:
    # Tabs, carriage returns, a lone slash in a string, lowercase exponents
    # and hexadecimal digits, and an entity added after parsing.
    var text = String(
        "ISO-10303-21;\r\n\tHEADER;\nENDSEC;\nDATA;\n#1=X(1.5e2,'a/b"
        " \\X\\e9',.E.);\n#3=Y(());\nENDSEC;\nEND-ISO-10303-21;\n"
    )
    var f = parse(text)
    assert_equal(f.as_real(f.argument(1, 0)), 150)
    assert_equal(f.as_string(f.argument(1, 1)), "a/b é")
    # The next number after two entities is #3, which is taken.
    var id = f.add("Z", List[Int]())
    assert_equal(id, 4)
    assert_equal(f.add("Z", List[Int]()), 5)
    var empty_list = f.reals(List[Float64]())
    assert_equal(len(f.as_list(empty_list)), 0)
    assert_equal(len(f.as_list(f.references(List[Int]()))), 0)
    assert_equal(encode_string("tab\there"), "tab\\X2\\0009\\X0\\here")
    var blank = StepFile()
    assert_equal(
        blank.write(),
        "ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n",
    )
    with assert_raises(contains="expected a name"):
        _ = parse("ISO-10303-21;\nHEADER;\n/ x")


def test_step_end_of_file_cases() raises:
    with assert_raises(contains="a name"):
        _ = parse("ISO-10303-21;")
    with assert_raises(contains="a name"):
        _ = parse("ISO-10303-21;/")
    with assert_raises(contains="semicolon"):
        _ = parse("ISO-10303-21")
    with assert_raises(contains="equals"):
        _ = parse("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\n#1")
    with assert_raises(contains="hexadecimal digit"):
        _ = parse(_bad("#1=X('\\X\\ 1');"))
    with assert_raises(contains="hexadecimal digit"):
        _ = parse(_bad("#1=X('\\X\\zz');"))
    with assert_raises(contains="comma"):
        _ = parse("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\n#1=X('abc'")
    var f = parse(_bad("/* a * b */ #1=X(1E3,1e3);"))
    assert_equal(f.as_real(f.argument(1, 0)), 1000)
    assert_equal(f.as_real(f.argument(1, 1)), 1000)
    _ = f.add("Z", List[Int]())
    assert_true(f.write().find("=Z();") >= 0)


def test_a_furnished_tower_round_trips() raises:
    var params = SkyscraperParameters()
    params.total_height = Length(8, METER)
    var tower = generate_tower(TowerOptions(params^))
    var back = read_ifc(write_ifc(tower, "t"), Length64(1e-6, METER))
    assert_equal(len(back.furnishings), len(tower.furnishings))
    assert_equal(fingerprint(back), fingerprint(tower))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
