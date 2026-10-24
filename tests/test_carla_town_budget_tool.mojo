# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Town mesh kinds and triangle limits match the reviewed Python rules."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program, shell_quote
from tools.carla_town_budget import (
    far_budget,
    kind_of,
    near_budget,
    object_fields,
)


def _expect_kind(path: String, kind: String) raises:
    """Require one path to have `kind`.

    Args:
        path: The Unreal object path.
        kind: The expected scenery kind, or `skip`.

    Raises:
        Error: If the kind differs.
    """
    assert_equal(kind_of(path), kind)


def test_kinds_follow_the_static_folder() raises:
    _expect_kind("/Engine/BasicShapes/Cube", "prop")
    _expect_kind("/Engine/Static/Sky/Dome", "prop")
    _expect_kind("/Engine", "prop")
    _expect_kind("/Game/Carla/Static/Building/House", "building")
    _expect_kind("/Game/Carla/Static/Bridge/B", "building")
    _expect_kind("/Game/Carla/Static/Wall/W", "wall")
    _expect_kind("/Game/Carla/Static/Fence/F", "fence")
    _expect_kind("/Game/Carla/Static/GuardRail/G", "fence")
    _expect_kind("/Game/Carla/Static/Road/R", "road")
    _expect_kind("/Game/Carla/Static/RoadLine/R", "road_line")
    _expect_kind("/Game/Carla/Static/SideWalk/S", "sidewalk")
    _expect_kind("/Game/Carla/Static/Ground/G", "ground")
    _expect_kind("/Game/Carla/Static/Terrain/T", "terrain")
    _expect_kind("/Game/Carla/Static/Water/W", "water")
    _expect_kind("/Game/Carla/Static/RailTrack/R", "rail")
    _expect_kind("/Game/Carla/Static/Vegetation/Trees/T", "vegetation")
    _expect_kind("/Game/Carla/Static/Pole/P", "pole")
    _expect_kind("/Game/Carla/Static/StreetLight/S", "pole")
    _expect_kind("/Game/Carla/Static/TrafficLight/T", "traffic_light")
    _expect_kind("/Game/Carla/Static/TrafficSign/T", "traffic_sign")
    _expect_kind("/Game/Carla/Static/Car/C", "parked_vehicle")
    _expect_kind("/Game/Carla/Static/Truck/T", "parked_vehicle")
    _expect_kind("/Game/Carla/Static/Motorcycle/M", "parked_vehicle")
    _expect_kind("/Game/Carla/Static/Bicycle/B", "parked_vehicle")
    _expect_kind("/Game/Carla/Static/Bus/B", "parked_vehicle")
    _expect_kind("/Game/Carla/Static/Unknown/U", "prop")
    _expect_kind("/Game/Carla/Dynamic/Prop/P", "prop")
    _expect_kind("/Game/Other", "prop")
    _expect_kind("", "prop")
    _expect_kind("/Game/Carla/Static/", "prop")
    _expect_kind("/game/carla/static/Building/House", "prop")
    _expect_kind("/Game/Carla/Static/Sky/Dome", "skip")
    _expect_kind("/Game/Carla/Static/Particles/P", "skip")
    _expect_kind("/Game/Carla/Static/Pedestrian/P", "skip")
    _expect_kind("/Game/Carla/Static/Hair/H", "skip")
    _expect_kind("/Game/Carla/Static/CubeMaps/C", "skip")
    _expect_kind("/Game/Carla/Static/HDRi/H", "skip")
    _expect_kind("/Game/Carla/Static/Decals/D", "skip")
    _expect_kind("/Game/Carla/Static/TestWindowsParts/T", "skip")


def test_triangle_limits_follow_kind_and_path() raises:
    assert_equal(near_budget("road", 10000, "/Game/X"), 10000)
    assert_equal(far_budget("road", 10000, "/Game/X"), 10000)
    assert_equal(near_budget("sidewalk", 42, "/Game/X"), 42)
    assert_equal(near_budget("building", 10000, "/Game/X"), 2500)
    assert_equal(far_budget("building", 10000, "/Game/X"), 300)
    assert_equal(near_budget("building", 100, "/Game/X"), 100)
    assert_equal(near_budget("building", -7, "/Game/X"), -2)
    assert_equal(near_budget("parked_vehicle", 10000, "/Game/X"), 2500)
    assert_equal(far_budget("parked_vehicle", 10000, "/Game/X"), 0)
    assert_equal(near_budget("vegetation", 10000, "/Game/X"), 4000)
    assert_equal(
        near_budget("vegetation", 10000, "/Game/Vegetation/Bushes/A"), 800
    )
    assert_equal(far_budget("vegetation", 10000, "/Game/X"), 0)
    assert_equal(
        far_budget("vegetation", 10000, "/Game/Vegetation/Trees/A"), 2000
    )
    assert_equal(far_budget("vegetation", 100, "/game/vegetation/trees/a"), 100)
    assert_equal(near_budget("pole", 10000, "/Game/X"), 1666)
    assert_equal(far_budget("pole", 10000, "/Game/X"), 833)
    assert_equal(far_budget("pole", 100, "/Game/StreetLights/SM_glass_ext"), 0)
    assert_equal(far_budget("pole", 100, "/Game/Lamps/LEDs"), 0)
    assert_equal(far_budget("traffic_light", 100, "/Game/Pole/Glass"), 0)
    assert_equal(near_budget("traffic_sign", 10000, "/Game/X"), 1666)
    assert_equal(far_budget("traffic_sign", 10000, "/Game/X"), 0)
    assert_equal(near_budget("fence", 10000, "/Game/X"), 2500)
    assert_equal(far_budget("fence", 10000, "/Game/X"), 1000)
    assert_equal(far_budget("wall", 10000, "/Game/X"), 1000)
    assert_equal(near_budget("prop", 10000, "/Game/X"), 2500)
    assert_equal(far_budget("prop", 100, "/Game/X"), 0)
    assert_equal(near_budget("", 10000, "/Game/X"), 2500)
    assert_equal(far_budget("", 10000, "/Game/Vegetation/Trees/A"), 2500)


def test_object_names_follow_the_last_separator() raises:
    var plain = object_fields("StaticMesh /Game/A/B.B")
    assert_equal(plain[0], "StaticMesh")
    assert_equal(plain[1], "/Game/A/B")
    assert_equal(plain[2], "B")
    var nested = object_fields("StaticMesh /Game/A/B.B:C.Inner")
    assert_equal(nested[0], "StaticMesh")
    assert_equal(nested[1], "/Game/A/B.B:C")
    assert_equal(nested[2], "Inner")
    var colon = object_fields("StaticMesh /Game/A/B.B:C:D")
    assert_equal(colon[1], "/Game/A/B")
    assert_equal(colon[2], "D")
    var material = object_fields("Material /Game/A/B.B:Material_0")
    assert_equal(material[2], "Material_0")
    var empty = object_fields("StaticMesh /Game/A/B.")
    assert_equal(empty[1], "/Game/A/B")
    assert_equal(empty[2], "")
    var bare = object_fields("Class onlypath")
    assert_equal(bare[0], "Class")
    assert_equal(bare[1], "")
    assert_equal(bare[2], "onlypath")
    var spaced = object_fields("StaticMesh  /Game/A/B.B")
    assert_equal(spaced[0], "StaticMesh")
    assert_equal(spaced[1], " /Game/A/B")
    assert_equal(spaced[2], "B")
    with assert_raises():
        _ = object_fields("NoDot")


def _cli(var args: List[String]) raises -> String:
    """Run one one-shot command and return its standard output."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_budget")
    command.extend(args^)
    var result = run_program(command, 30, merge_errors=False)
    assert_true(result.errors.find("Crashpad") < 0)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def test_the_command_and_the_worker_agree() raises:
    assert_equal(
        _cli(["kind", "/Game/Carla/Static/Sky/Dome"]),
        "skip\n",
    )
    assert_equal(
        _cli(["near", "building", "10000", "/Game/X"]),
        "2500\n",
    )
    assert_equal(
        _cli(["far", "vegetation", "10000", "/Game/Vegetation/Trees/A"]),
        "2000\n",
    )
    assert_equal(
        _cli(["object", "StaticMesh /Game/A/B.B:C.Inner"]),
        "StaticMesh\n/Game/A/B.B:C\nInner\n",
    )
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_budget"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    var bad = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_budget",
            "near",
            "building",
            "nope",
            "/Game/X",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(bad.status, 1)
    assert_true(bad.errors.find("not decimal") >= 0)
    var script = (
        "printf '%s\\n' "
        + shell_quote("kind\t/Game/Carla/Static/Building/House")
        + " "
        + shell_quote("nope")
        + " "
        + shell_quote("object\tStaticMesh /Game/A/B.B")
        + " | sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + " carla_town_budget serve"
    )
    var served = run_program(["sh", "-c", script], 30, merge_errors=False)
    assert_equal(served.status, 0)
    assert_equal(
        served.output,
        "ok\tbuilding\n"
        + "err\tusage: carla_town_budget kind|near|far|object ...\n"
        + "ok\tStaticMesh\t/Game/A/B\tB\n",
    )
    assert_true(served.errors.find("Crashpad") < 0)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_budget"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
