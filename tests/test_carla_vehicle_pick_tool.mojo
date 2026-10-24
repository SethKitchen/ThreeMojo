# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The vehicle body and its glass.

The largest skeletal mesh is the body. An equal size keeps the earlier
mesh. Pedestrian packages are left out. Collision meshes and props are
left out of the glass. A folder mesh is used only when the blueprint
names no body.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_vehicle_pick import pick_text


def _sample() -> String:
    """Return one blueprint with a body, glass, a pedestrian and props."""
    return (
        '{"refs":['
        + '{"path":"/Game/A/Body","class":"SkeletalMesh","size":10},'
        + '{"path":"/Game/Pedestrian/Walker","class":"SkeletalMesh","size":1000},'
        + '{"path":"/Game/Glass","class":"StaticMesh","size":2},'
        + '{"path":"/Game/Wheel_sc_part","class":"StaticMesh","size":9},'
        + '{"path":"/Game/sm_sc_wheel","class":"StaticMesh","size":8},'
        + '{"path":"/Game/Hood_prop","class":"StaticMesh","size":7},'
        + '{"path":"/Game/Small","class":"SkeletalMesh","size":3},'
        + '{"path":"/Game/Light","class":"StaticMesh","size":1}'
        + '],"extras":[{"path":"/Game/Folder/Huge","name":"Huge.uasset",'
        + '"class":"SkeletalMesh","size":99}]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test vehicle pick ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_vehicle_pick")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_the_largest_skeletal_mesh_is_the_body() raises:
    assert_equal(
        pick_text(_sample()),
        '{"body":"/Game/A/Body","static":["/Game/Glass","/Game/Light"],'
        + '"skeletal":["/Game/A/Body","/Game/Small"],"error":""}',
    )
    assert_equal(
        pick_text(
            '{"refs":['
            + '{"path":"/Game/A","class":"SkeletalMesh","size":10},'
            + '{"path":"/Game/B","class":"SkeletalMesh","size":10}'
            + '],"extras":[]}'
        ),
        '{"body":"/Game/A","static":[],"skeletal":["/Game/A","/Game/B"],"error":""}',
    )
    assert_equal(
        pick_text(
            '{"refs":['
            + '{"path":"/Game/Low","class":"SkeletalMesh","size":5},'
            + '{"path":"/Game/High","class":"SkeletalMesh","size":10},'
            + '{"path":"/Game/Tied","class":"SkeletalMesh","size":10}'
            + '],"extras":[]}'
        ),
        '{"body":"/Game/High","static":[],'
        + '"skeletal":["/Game/High","/Game/Tied","/Game/Low"],"error":""}',
    )


def test_glass_keeps_its_order_and_a_prop_suffix_is_exact() raises:
    assert_equal(
        pick_text(
            '{"refs":['
            + '{"path":"/Game/Body","class":"SkeletalMesh","size":1},'
            + '{"path":"/Game/Hood_PROP","class":"StaticMesh","size":1},'
            + '{"path":"/Game/X_SC_Y","class":"StaticMesh","size":1},'
            + '{"path":"/Game/SM_SC/Wheel","class":"StaticMesh","size":1},'
            + '{"path":"/Game/Hood_prop_extra","class":"StaticMesh","size":4},'
            + '{"path":"/Game/Lamp","class":"StaticMesh","size":1},'
            + '{"path":"/Game/pedestrian/Kept","class":"StaticMesh","size":1}'
            + '],"extras":[]}'
        ),
        '{"body":"/Game/Body","static":['
        + '"/Game/Hood_prop_extra","/Game/Lamp","/Game/pedestrian/Kept"'
        + '],"skeletal":["/Game/Body"],"error":""}',
    )
    assert_equal(
        pick_text(
            '{"refs":[{"path":"/Game/A\\"B","class":"SkeletalMesh","size":1}],'
            + '"extras":[]}'
        ),
        '{"body":"/Game/A\\"B","static":[],"skeletal":["/Game/A\\"B"],"error":""}',
    )


def test_a_folder_supplies_the_body_only_when_the_blueprint_has_none() raises:
    assert_equal(
        pick_text(
            '{"refs":['
            + '{"path":"/Game/Pedestrian/Walker","class":"SkeletalMesh","size":9},'
            + '{"path":"/Game/Glass","class":"StaticMesh","size":2},'
            + '{"path":"/Game/Other","class":"Texture2D","size":1}'
            + '],"extras":['
            + '{"path":"/Game/Folder/SK_Skeleton","name":"SK_Skeleton.uasset",'
            + '"class":"SkeletalMesh","size":50},'
            + '{"path":"/Game/Folder/Physics","name":"SK_Physics.uasset",'
            + '"class":"SkeletalMesh","size":40},'
            + '{"path":"/Game/Folder/Loose","name":"SK.uasset.txt",'
            + '"class":"SkeletalMesh","size":30},'
            + '{"path":"/Game/Folder/Upper","name":"SK.UASSET",'
            + '"class":"SkeletalMesh","size":30},'
            + '{"path":"/Game/Skeleton/Body","name":"Body.uasset",'
            + '"class":"SkeletalMesh","size":4},'
            + '{"path":"/Game/Folder/Big","name":"Big.uasset",'
            + '"class":"SkeletalMesh","size":8},'
            + '{"path":"/Game/Folder/Glass","name":"Glass.uasset",'
            + '"class":"StaticMesh","size":100}'
            + "]}"
        ),
        '{"body":"/Game/Folder/Big","static":["/Game/Glass"],'
        + '"skeletal":["/Game/Folder/Big","/Game/Skeleton/Body"],"error":""}',
    )
    assert_equal(
        pick_text(
            '{"refs":['
            + '{"path":"/Game/Pedestrian/Walker","class":"SkeletalMesh","size":9},'
            + '{"path":"/Game/A/Glass","class":"StaticMesh","size":2},'
            + '{"path":"/Game/B/Wheel_sc_","class":"Blueprint","size":1}'
            + '],"extras":[]}'
        ),
        '{"body":"","static":[],"skeletal":[],'
        + '"error":"no skeletal mesh among Glass, Wheel_sc_"}',
    )
    assert_equal(
        pick_text('{"refs":[],"extras":[]}'),
        (
            '{"body":"","static":[],"skeletal":[],"error":"no skeletal mesh'
            ' among "}'
        ),
    )


def test_a_bad_request_is_refused() raises:
    with assert_raises(contains="pick request is not an object"):
        _ = pick_text("[]")
    with assert_raises(contains="KeyError: 'refs'"):
        _ = pick_text("{}")
    with assert_raises(contains="meshes are not a list"):
        _ = pick_text('{"refs":{},"extras":[]}')
    with assert_raises(contains="mesh is not an object"):
        _ = pick_text('{"refs":[1],"extras":[]}')
    with assert_raises(contains="size is not an integer"):
        _ = pick_text(
            '{"refs":[{"path":"/Game/A","class":"SkeletalMesh","size":1.5}],'
            + '"extras":[]}'
        )
    with assert_raises(contains="size is negative"):
        _ = pick_text(
            '{"refs":[{"path":"/Game/A","class":"SkeletalMesh","size":-1}],'
            + '"extras":[]}'
        )


def test_the_command_prints_the_body_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/pick.json"
    Path(path).write_text(_sample())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        '{"body":"/Game/A/Body","static":["/Game/Glass","/Game/Light"],'
        + '"skeletal":["/Game/A/Body","/Game/Small"],"error":""}\n',
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_vehicle_pick FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_vehicle_pick:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_vehicle_pick"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
