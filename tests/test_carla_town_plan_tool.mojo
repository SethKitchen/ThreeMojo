# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The town plan keeps the cube, thins grass, and bakes a building."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_plan import plan_text


def test_hidden_sky_and_engine_meshes_stay_out() raises:
    var doc = plan_text(
        '{"mode":"select","rows":['
        '{"mesh":"/Game/Carla/Static/Building/A","visible":false},'
        '{"mesh":"/Game/Carla/Static/Sky/Dome","visible":true},'
        '{"mesh":"/Engine/EngineMaterials/Default","visible":true},'
        '{"mesh":"/Engine/BasicShapes/Cube","visible":true},'
        '{"mesh":"/Game/Carla/Static/Building/A","visible":true}'
        "]}"
    )
    assert_equal(doc, '{"rows":[3,4]}')


def test_grass_thins_and_a_building_far_level_is_baked() raises:
    var doc = plan_text(
        '{"mode":"jobs","rows":['
        '{"mesh":"/Game/Carla/Static/Vegetation/Grass/Blade","copies":15,'
        '"triangles":2,"materials":["Leaf"]},'
        '{"mesh":"/Game/Carla/Static/Vegetation/Grass/Blade","copies":10,'
        '"triangles":2,"materials":["Leaf"]},'
        '{"mesh":"/Game/Carla/Static/Building/Block","copies":1,"triangles":100,'
        '"materials":["WorldGridMaterial","Wall"]},'
        '{"mesh":"/Game/Carla/Static/Vegetation/Trees/Pine","copies":1,'
        '"triangles":20,"materials":["Bark","Leaf"]},'
        '{"mesh":"/Game/Carla/Static/StreetLight/StreetLights/SM_glass_x",'
        '"copies":1,"triangles":8,"materials":["Glass"]}'
        "]}"
    )
    assert_true(doc.find('{"kind":"vegetation","lod":0,"count":26,') >= 0)
    assert_true(doc.find('"copies":[0,10]') >= 0)
    assert_true(doc.find('"copies":[5]') >= 0)
    assert_true(
        doc.find(
            '{"index":1,"material":"Wall","levels":[{"lod":0,"action":"lower","factor":1.0},{"lod":1,"action":"baked","factor":1.0,"goal":'
        )
        >= 0
    )
    assert_true(doc.find('"action":"impostor"') >= 0)
    assert_true(doc.find('"lamp_glass":true') >= 0)
    assert_true(doc.find('"material":"WorldGridMaterial"') < 0)


def test_cli_prints_the_plan() raises:
    var path = String("/tmp/carla-town-plan.json")
    Path(path).write_text(
        '{"mode":"select","rows":[{"mesh":"/Engine/BasicShapes/Cube","visible":true}]}'
    )
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_plan", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, '{"rows":[0]}\n')
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_plan"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_plan FILE\n")
    with assert_raises(contains="mode is not select or jobs"):
        _ = plan_text('{"mode":"other","rows":[]}')
    with assert_raises(contains="plan request is not an object"):
        _ = plan_text("[]")


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_plan"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
