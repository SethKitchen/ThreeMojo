# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for reading an IFC4 file that another program might write.

The file below was written by hand for these tests. It has unset axes, a
2D profile placement, storeys out of elevation order, a storey with no
elevation and no gross height, spaces with unknown uses, materials with
no physical properties, walls that match no model wall, a wall and a
slab with profiles the reader skips, an opening placed outside its wall's
frame, and a window with no glazing properties. Each refusal test changes
one line of it.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.building.ifc.ifc4 import read_ifc
from extensions.building.kinds import (
    BEAM,
    CIRCLE,
    COLUMN,
    DOOR,
    KITCHEN,
    OFFICE,
    SLAB,
    WALL,
    WINDOW,
)
from extensions.building.ids import ElementId
from units.si import DEGREE, DEGREE64, Length64, METER


def _foreign() -> String:
    return String(
        """ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');
FILE_NAME('foreign','2026-01-01T00:00:00',(''),(''),'hand','hand','');
FILE_SCHEMA(('ifc4'));
ENDSEC;
DATA;
/* Written by hand for ThreeMojo's tests: a file as another program might
   write it, with unset axes, 2D placements and no ThreeMojo property sets. */
#1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);
#2=IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);
#3=IFCUNITASSIGNMENT((#1,#2));
#4=IFCCARTESIANPOINT((0.,0.,0.));
#5=IFCAXIS2PLACEMENT3D(#4,$,$);
#6=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#5,$);
#7=IFCPROJECT('0000000000000000000001',$,'p',$,$,$,$,(#6),#3);
#8=IFCLOCALPLACEMENT($,#5);
#9=IFCSITE('0000000000000000000002',$,'site',$,$,#8,$,$,.ELEMENT.,(51,30,0,0),(0,-7,-30,0),$,$,$);
#10=IFCBUILDING('0000000000000000000003',$,$,$,$,#8,$,$,.ELEMENT.,$,$,$);
#11=IFCCARTESIANPOINT((0.,0.,3.));
#12=IFCAXIS2PLACEMENT3D(#11,$,$);
#13=IFCLOCALPLACEMENT(#8,#12);
#14=IFCBUILDINGSTOREY('0000000000000000000004',$,'upper',$,$,#13,$,$,.ELEMENT.,3.);
#15=IFCLOCALPLACEMENT(#8,#5);
#16=IFCBUILDINGSTOREY('0000000000000000000005',$,'ground',$,$,#15,$,$,.ELEMENT.,$);
#17=IFCRELAGGREGATES('0000000000000000000006',$,$,$,#10,(#14,#16));
#18=IFCPROPERTYSET('0000000000000000000007',$,'Pset_BuildingStoreyCommon',$,());
#19=IFCQUANTITYLENGTH('NetHeight',$,$,2.7,$);
#20=IFCELEMENTQUANTITY('0000000000000000000008',$,'Qto_BuildingStoreyBaseQuantities',$,$,(#19));
#21=IFCRELDEFINESBYPROPERTIES('0000000000000000000009',$,$,$,(#16),#18);
#22=IFCRELDEFINESBYPROPERTIES('000000000000000000000A',$,$,$,(#16),#20);
#23=IFCDIRECTION((1.,0.));
#24=IFCCARTESIANPOINT((0.,0.));
#25=IFCAXIS2PLACEMENT2D(#24,#23);
#26=IFCCARTESIANPOINT((4.,0.));
#27=IFCCARTESIANPOINT((4.,3.));
#28=IFCCARTESIANPOINT((0.,3.));
#29=IFCPOLYLINE((#24,#26,#27,#28));
#30=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#29);
#31=IFCDIRECTION((0.,0.,1.));
#32=IFCEXTRUDEDAREASOLID(#30,#5,#31,3.);
#33=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#32));
#34=IFCPRODUCTDEFINITIONSHAPE($,$,(#33));
#35=IFCSPACE('000000000000000000000B',$,'kitchen',$,'Kitchen',#15,#34,$,.ELEMENT.,.SPACE.,$);
#36=IFCCARTESIANPOINT((6.,0.));
#37=IFCCARTESIANPOINT((6.,3.));
#38=IFCPOLYLINE((#26,#36,#37,#27,#26));
#39=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#38);
#40=IFCEXTRUDEDAREASOLID(#39,#5,#31,3.);
#41=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#40));
#42=IFCPRODUCTDEFINITIONSHAPE($,$,(#41));
#43=IFCSPACE('000000000000000000000C',$,'atrium',$,'Atrium',#15,#42,$,.ELEMENT.,.SPACE.,$);
#44=IFCPOLYLINE((#24,#36,#37,#28,#24));
#45=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#44);
#46=IFCEXTRUDEDAREASOLID(#45,#5,#31,2.5);
#47=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#46));
#48=IFCPRODUCTDEFINITIONSHAPE($,$,(#47));
#49=IFCSPACE('000000000000000000000D',$,$,$,$,#13,#48,$,.ELEMENT.,.SPACE.,$);
#50=IFCRELAGGREGATES('000000000000000000000E',$,$,$,#16,(#35,#43));
#51=IFCRELAGGREGATES('000000000000000000000F',$,$,$,#14,(#49));
#52=IFCMATERIAL('Timber post',$,$);
#53=IFCMATERIAL('Unknown stuff',$,$);
#54=IFCPROPERTYSINGLEVALUE('MassDensity',$,IFCMASSDENSITYMEASURE(1234.),$);
#55=IFCPROPERTYSINGLEVALUE('Comment',$,$,$);
#56=IFCPROPERTYENUMERATEDVALUE('Finish',$,(IFCLABEL('matte')),$);
#57=IFCMATERIALPROPERTIES('Pset_MaterialCommon',$,(#54,#55,#56),#53);
#58=IFCMATERIALLAYER(#53,0.2,$,$,$,$,$);
#140=IFCMATERIALLAYERSET((#58),'first set',$);
#59=IFCMATERIALLAYERSET((#58),'stuff wall',$);
#60=IFCMATERIALPROPERTIES('Pset_Orphan',$,(#54),#59);
#61=IFCCARTESIANPOINT((2.,0.));
#62=IFCAXIS2PLACEMENT2D(#61,$);
#151=IFCAXIS2PLACEMENT2D(#61,#23);
#63=IFCRECTANGLEPROFILEDEF(.AREA.,$,#151,4.,0.2);
#64=IFCEXTRUDEDAREASOLID(#63,#5,#31,3.);
#65=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#64));
#66=IFCPRODUCTDEFINITIONSHAPE($,$,(#65));
#141=IFCCARTESIANPOINT((4.,0.,0.));
#142=IFCAXIS2PLACEMENT3D(#141,#31,#68);
#143=IFCLOCALPLACEMENT(#15,#142);
#67=IFCWALL('000000000000000000000G',$,'south',$,$,#143,#66,$,.STANDARD.);
#68=IFCDIRECTION((-1.,0.,0.));
#69=IFCCARTESIANPOINT((4.,3.,0.));
#70=IFCAXIS2PLACEMENT3D(#69,#31,#68);
#71=IFCLOCALPLACEMENT(#15,#70);
#72=IFCWALL('000000000000000000000H',$,'north',$,$,#71,#66,$,.STANDARD.);
#73=IFCCARTESIANPOINT((20.,20.,0.));
#74=IFCAXIS2PLACEMENT3D(#73,$,$);
#75=IFCLOCALPLACEMENT(#15,#74);
#76=IFCWALL('000000000000000000000I',$,'stray',$,$,#75,#66,$,.STANDARD.);
#77=IFCWALL('000000000000000000000J',$,'loose',$,$,#75,#66,$,.STANDARD.);
#78=IFCCIRCLEPROFILEDEF(.AREA.,$,#62,0.1);
#79=IFCEXTRUDEDAREASOLID(#78,#5,#31,3.);
#80=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#79));
#81=IFCPRODUCTDEFINITIONSHAPE($,$,(#80));
#82=IFCWALL('000000000000000000000K',$,'round',$,$,#15,#81,$,.STANDARD.);
#83=IFCSLAB('000000000000000000000L',$,'pad',$,$,#15,#66,$,.FLOOR.);
#84=IFCPOLYLINE((#24,#26,#27,#28,#24));
#85=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#84);
#86=IFCCARTESIANPOINT((0.,0.,-0.3));
#87=IFCAXIS2PLACEMENT3D(#86,$,$);
#88=IFCEXTRUDEDAREASOLID(#85,#87,#31,0.3);
#89=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#88));
#90=IFCPRODUCTDEFINITIONSHAPE($,$,(#89));
#91=IFCSLAB('000000000000000000000M',$,'ground slab',$,$,#15,#90,$,.BASESLAB.);
#92=IFCCARTESIANPOINT((1.,1.,0.));
#93=IFCAXIS2PLACEMENT3D(#92,$,$);
#94=IFCLOCALPLACEMENT(#15,#93);
#95=IFCCOLUMN('000000000000000000000N',$,'post',$,$,#94,#81,$,.COLUMN.);
#96=IFCDIRECTION((1.,0.,0.));
#97=IFCDIRECTION((0.,1.,0.));
#98=IFCCARTESIANPOINT((0.,1.5,3.));
#99=IFCAXIS2PLACEMENT3D(#98,#96,#97);
#100=IFCLOCALPLACEMENT(#15,#99);
#101=IFCRECTANGLEPROFILEDEF(.AREA.,$,#25,0.2,0.4);
#102=IFCEXTRUDEDAREASOLID(#101,#5,#31,6.);
#103=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#102));
#104=IFCPRODUCTDEFINITIONSHAPE($,$,(#103));
#105=IFCBEAM('000000000000000000000O',$,'girder',$,$,#100,#104,$,.BEAM.);
#106=IFCPROPERTYSET('000000000000000000000P',$,'Pset_BeamCommon',$,(#55));
#107=IFCRELDEFINESBYPROPERTIES('000000000000000000000Q',$,$,$,(#105),#106);
#108=IFCRELDEFINESBYPROPERTIES('000000000000000000000R',$,$,$,(#105),#20);
#109=IFCCARTESIANPOINT((1.,0.,1.));
#110=IFCAXIS2PLACEMENT3D(#109,$,$);
#111=IFCLOCALPLACEMENT($,#110);
#112=IFCRECTANGLEPROFILEDEF(.AREA.,$,#62,1.,0.4);
#113=IFCEXTRUDEDAREASOLID(#112,#5,#31,1.);
#114=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#113));
#115=IFCPRODUCTDEFINITIONSHAPE($,$,(#114));
#159=IFCLOCALPLACEMENT(#15,#110);
#116=IFCOPENINGELEMENT('000000000000000000000S',$,'o1',$,$,#159,#115,$,.OPENING.);
#117=IFCWINDOW('000000000000000000000T',$,'w1',$,$,#159,$,$,1.,1.,.WINDOW.,.SINGLE_PANEL.,$);
#118=IFCCARTESIANPOINT((1.,0.,0.));
#119=IFCAXIS2PLACEMENT3D(#118,$,$);
#120=IFCLOCALPLACEMENT(#71,#119);
#121=IFCOPENINGELEMENT('000000000000000000000U',$,'o2',$,$,#120,#115,$,.OPENING.);
#122=IFCDOOR('000000000000000000000V',$,'d1',$,$,#120,$,$,1.,0.8,.DOOR.,.SINGLE_SWING_LEFT.,$);
#123=IFCOPENINGELEMENT('000000000000000000000W',$,'o3',$,$,#111,#115,$,.OPENING.);
#124=IFCOPENINGELEMENT('000000000000000000000X',$,'o4',$,$,#111,#115,$,.OPENING.);
#125=IFCRELVOIDSELEMENT('000000000000000000000Y',$,$,$,#67,#116);
#126=IFCRELFILLSELEMENT('000000000000000000000Z',$,$,$,#116,#117);
#127=IFCRELVOIDSELEMENT('0000000000000000000010',$,$,$,#72,#121);
#128=IFCRELFILLSELEMENT('0000000000000000000011',$,$,$,#121,#122);
#129=IFCRELVOIDSELEMENT('0000000000000000000012',$,$,$,#67,#123);
#130=IFCRELVOIDSELEMENT('0000000000000000000013',$,$,$,#76,#124);
#131=IFCRELFILLSELEMENT('0000000000000000000014',$,$,$,#124,#117);
#132=IFCRELCONTAINEDINSPATIALSTRUCTURE('0000000000000000000015',$,$,$,(#67,#72,#76,#82,#83,#91,#95,#105),#16);
#133=IFCRELASSOCIATESMATERIAL('0000000000000000000016',$,$,$,(#67,#91),#59);
#134=IFCRELASSOCIATESMATERIAL('0000000000000000000017',$,$,$,(#95,#105),#52);
#135=IFCRELASSOCIATESMATERIAL('0000000000000000000018',$,$,$,(#76),#53);
#152=IFCCARTESIANPOINT((3.,3.,1.));
#153=IFCAXIS2PLACEMENT3D(#152,$,$);
#154=IFCLOCALPLACEMENT($,#153);
#160=IFCRECTANGLEPROFILEDEF(.AREA.,$,#62,0.5,0.4);
#161=IFCEXTRUDEDAREASOLID(#160,#5,#31,0.5);
#162=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#161));
#163=IFCPRODUCTDEFINITIONSHAPE($,$,(#162));
#155=IFCOPENINGELEMENT('000000000000000000001F',$,'o5',$,$,#154,#163,$,.OPENING.);
#156=IFCWINDOW('000000000000000000001G',$,'w5',$,$,#154,$,$,0.5,0.5,.WINDOW.,.SINGLE_PANEL.,$);
#157=IFCRELVOIDSELEMENT('000000000000000000001H',$,$,$,#72,#155);
#158=IFCRELFILLSELEMENT('000000000000000000001I',$,$,$,#155,#156);
#170=IFCCARTESIANPOINT((1.,1.5,0.));
#171=IFCAXIS2PLACEMENT3D(#170,$,#96);
#172=IFCLOCALPLACEMENT(#15,#171);
#173=IFCRECTANGLEPROFILEDEF(.AREA.,$,#62,1.,0.6);
#174=IFCEXTRUDEDAREASOLID(#173,#5,#31,0.75);
#175=IFCSHAPEREPRESENTATION(#6,'Body','SweptSolid',(#174));
#176=IFCPRODUCTDEFINITIONSHAPE($,$,(#175));
#177=IFCFURNITURE('000000000000000000001J',$,'desk',$,'Desk',#172,#176,$,$);
#178=IFCFURNITURE('000000000000000000001K',$,'lamp',$,'Lamp',#172,#176,$,$);
#179=IFCFURNITURE('000000000000000000001L',$,'stool',$,'Chair',#172,#81,$,$);
#180=IFCFURNITURE('000000000000000000001M',$,'stray',$,'Table',#172,#176,$,$);
#181=IFCRELCONTAINEDINSPATIALSTRUCTURE('000000000000000000001N',$,$,$,(#177,#178,#179),#35);
#144=IFCRELAGGREGATES('0000000000000000000019',$,$,$,#10,());
#145=IFCRELCONTAINEDINSPATIALSTRUCTURE('000000000000000000001A',$,$,$,(),#16);
#146=IFCRELASSOCIATESMATERIAL('000000000000000000001B',$,$,$,(),#52);
#147=IFCRELDEFINESBYPROPERTIES('000000000000000000001C',$,$,$,(),#18);
#148=IFCMATERIALPROPERTIES('Empty',$,(),#52);
#149=IFCELEMENTQUANTITY('000000000000000000001D',$,'Empty',$,$,());
#150=IFCRELDEFINESBYPROPERTIES('000000000000000000001E',$,$,$,(#16),#149);
ENDSEC;
END-ISO-10303-21;
"""
    )


def _read(text: String) raises:
    _ = read_ifc(text, Length64(1e-6, METER))


def test_a_foreign_file_reads() raises:
    var b = read_ifc(_foreign(), Length64(1e-6, METER))
    assert_equal(b.name, "")
    assert_equal(len(b.storeys), 2)
    assert_equal(b.storeys[0].name, "ground")
    assert_equal(b.storeys[0].elevation.value, 0)
    assert_equal(b.storeys[0].height.value, 3)
    assert_equal(b.storeys[1].height.value, 2.5)
    assert_equal(len(b.spaces), 3)
    assert_true(b.spaces[0].use == KITCHEN)
    assert_true(b.spaces[1].use == OFFICE)
    assert_true(b.spaces[2].use == OFFICE)
    assert_equal(b.spaces[2].name, "")
    assert_almost_equal(b.site.latitude.to(DEGREE64), 51.5, atol=1e-12)
    assert_almost_equal(b.site.longitude.to(DEGREE64), -0.125, atol=1e-12)
    assert_equal(b.site.north.value, 0)
    # A timber name without properties takes the timber values; an unknown
    # name takes concrete, with the density the file gives.
    assert_equal(b.materials[0].name, "Timber post")
    assert_equal(b.materials[0].density.value, 500)
    assert_equal(b.materials[1].density.value, 1234)
    assert_equal(b.materials[1].elastic_modulus.value, 30e9)
    assert_equal(len(b.constructions), 2)
    # The south wall and the slab under the kitchen took the second layer
    # set. The north wall matched but has no layer set, so it keeps the
    # first, as the others do.
    var matched = 0
    for e in range(len(b.elements)):
        if (
            b.elements[e].construction
            and b.elements[e].construction.value().value == 1
        ):
            matched += 1
    assert_equal(matched, 2)
    var members = 0
    for e in range(len(b.elements)):
        ref element = b.elements[e]
        if element.kind == COLUMN:
            assert_true(element.section.value().shape == CIRCLE)
            assert_equal(element.start.x, 1)
            members += 1
        elif element.kind == BEAM:
            assert_almost_equal(element.end.x, 6, atol=1e-12)
            members += 1
    assert_equal(members, 2)
    assert_equal(len(b.openings), 3)
    # Only the desk is read: the lamp has no kind, the stool's profile is a
    # circle and the table is in no space.
    assert_equal(len(b.furnishings), 1)
    assert_almost_equal(b.furnishings[0].center.y, 1.5, atol=1e-12)
    assert_true(b.openings[0].kind == WINDOW)
    assert_equal(b.openings[0].glazing.value().solar_heat_gain, 0.4)
    assert_true(b.openings[1].kind == DOOR)
    # Each opening keeps its place on its wall, whichever way the model's
    # wall runs.
    for o in range(3):
        ref opening = b.openings[o]
        var frame = b.wall_frame(opening.host)
        var start = frame.point(opening.offset.value, 0, 0)
        var finish = frame.point(
            opening.offset.value + opening.width.value, 0, 0
        )
        var low = min(start.x, finish.x)
        var lows: List[Float64] = [1.0, 2.2, 3.0]
        var expected = lows[o]
        assert_almost_equal(low, expected, atol=1e-9)


def test_a_foreign_file_refuses_what_it_cannot_read() raises:
    var text = _foreign()
    with assert_raises(contains="IFC4"):
        _read(text.replace("('ifc4')", "('IFC2X3')"))
    with assert_raises(contains="meters"):
        _read(text.replace(".LENGTHUNIT.,$,", ".LENGTHUNIT.,.MILLI.,"))
    with assert_raises(contains="names no material"):
        _read(
            text.replace("#58=IFCMATERIALLAYER(#53", "#58=IFCMATERIALLAYER(#59")
        )
    with assert_raises(contains="belong to a storey"):
        _read(text.replace("$,#14,(#49));", "$,#16,(#7));"))
    with assert_raises(contains="closed polyline"):
        _read(
            text.replace(
                "#45=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#44);",
                "#45=IFCRECTANGLEPROFILEDEF(.AREA.,$,#62,1.,1.);",
            )
        )
    with assert_raises(contains="in a storey"):
        _read(text.replace("#91,#95,#105),#16", "#91,#105),#16"))
    with assert_raises(contains="needs a material"):
        _read(text.replace("(#95,#105),#52", "(#105),#52"))
    with assert_raises(contains="member profile"):
        _read(text.replace("#94,#81,$,.COLUMN.", "#94,#90,$,.COLUMN."))
    with assert_raises(contains="no shape"):
        _read(text.replace("$,$,$,#13,#48,", "$,$,$,#13,$,"))
    with assert_raises(contains="no extruded solid"):
        _read(text.replace("'SweptSolid',(#46));", "'SweptSolid',(#45));"))
    with assert_raises(contains="polyline"):
        _read(text.replace("#29=IFCPOLYLINE", "#29=IFCCOMPOSITECURVE"))
    with assert_raises(contains="placement"):
        _read(text.replace("#5=IFCAXIS2PLACEMENT3D", "#5=IFCAXIS1PLACEMENT"))


def test_a_foreign_file_without_optional_parts() raises:
    var text = _foreign()
    var variants: List[String] = [
        text.replace(
            "IFCGEOMETRICREPRESENTATIONCONTEXT(",
            "IFCGEOMETRICREPRESENTATIONCONTEXTX(",
        ),
        text.replace("=IFCSITE(", "=IFCSITEX("),
        text.replace("(51,30,0,0),(0,-7,-30,0)", "$,()"),
        text.replace("=IFCSIUNIT(", "=IFCSIUNITX("),
        text.replace("=IFCBUILDING(", "=IFCBUILDINGX("),
    ]
    for i in range(len(variants)):
        var b = read_ifc(variants[i], Length64(1e-6, METER))
        assert_equal(len(b.spaces), 3)
    var no_building = read_ifc(variants[4], Length64(1e-6, METER))
    assert_equal(no_building.name, "building")
    # With no spaces there are no walls or slabs to match.
    var no_spaces = (
        text.replace("=IFCSPACE(", "=IFCSPACEX(")
        .replace(
            "IFCQUANTITYLENGTH('NetHeight'", "IFCQUANTITYLENGTH('GrossHeight'"
        )
        .replace("$,$,$,(#16),#20);", "$,$,$,(#16,#14),#20);")
    )
    var bare = read_ifc(no_spaces, Length64(1e-6, METER))
    assert_equal(bare.storeys[1].height.value, 2.7)
    assert_equal(len(bare.spaces), 0)
    assert_equal(len(bare.openings), 0)


def test_a_foreign_file_refuses_empty_parts() raises:
    var text = _foreign()
    with assert_raises(contains="no extruded solid"):
        _read(
            text.replace(
                "#104=IFCPRODUCTDEFINITIONSHAPE($,$,(#103));",
                "#104=IFCPRODUCTDEFINITIONSHAPE($,$,());",
            )
        )
    with assert_raises(contains="no extruded solid"):
        _read(text.replace("'SweptSolid',(#102));", "'SweptSolid',());"))
    with assert_raises(contains="three corners"):
        _read(
            text.replace(
                "#29=IFCPOLYLINE((#24,#26,#27,#28));", "#29=IFCPOLYLINE(());"
            )
        )
    with assert_raises(contains="three corners"):
        _read(
            text.replace(
                "#29=IFCPOLYLINE((#24,#26,#27,#28));", "#29=IFCPOLYLINE((#24));"
            )
        )
    with assert_raises(contains="IFC4"):
        _read(text.replace("FILE_SCHEMA(('ifc4'));", ""))
    with assert_raises(contains="IFC4"):
        _read(text.replace("FILE_SCHEMA(('ifc4'));", "FILE_SCHEMA(());"))
    with assert_raises(contains="IFC4"):
        _read(
            text.replace(
                "FILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');\n",
                "",
            )
            .replace(
                "FILE_NAME('foreign','2026-01-01T00:00:00',(''),(''),'hand','hand','');\n",
                "",
            )
            .replace("FILE_SCHEMA(('ifc4'));\n", "")
        )
    with assert_raises(contains="layer"):
        _read(
            text.replace(
                "#59=IFCMATERIALLAYERSET((#58),", "#59=IFCMATERIALLAYERSET((),"
            )
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
