# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Package names from a CARLA town layout.

`object` keeps the text before the last dot. `relative` drops the first
six characters and adds `.uasset`. `wanted` keeps each `/Game/` path once,
in sorted order.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_paths import (
    command_text,
    cooked_name,
    export_path,
    package_of,
    pending_text,
    split_text,
    wanted_text,
)


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town paths ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _write(root: String, name: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/" + name
    Path(path).write_text(text)
    return path


def _cli(var arguments: List[String]) raises -> ProcessResult:
    """Run the built program."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_paths")
    command.extend(arguments^)
    return run_program(command, 30, merge_errors=False)


def _two(first: String, second: String) -> List[String]:
    """Return two command arguments."""
    var arguments = List[String]()
    arguments.append(first)
    arguments.append(second)
    return arguments^


def test_a_package_drops_the_class_and_the_last_dot() raises:
    assert_equal(package_of("StaticMesh /Game/A/B.B"), "/Game/A/B")
    assert_equal(package_of("StaticMesh /Game/A/B.B:C.Inner"), "/Game/A/B.B:C")
    assert_equal(package_of("Class /Game/Only"), "/Game/Only")
    assert_equal(package_of("Class  /Game/A.A"), " /Game/A")
    with assert_raises(contains="object path has no class"):
        _ = package_of("NoSpace")


def test_a_cooked_name_drops_the_first_six_characters() raises:
    assert_equal(cooked_name("/Game/A/B"), "A/B.uasset")
    assert_equal(cooked_name("/Engine/Foo"), "e/Foo.uasset")
    assert_equal(cooked_name("/Game/"), ".uasset")
    assert_equal(cooked_name("hi"), ".uasset")


def test_layouts_keep_sorted_game_paths_once() raises:
    var root = _dir()
    var first = _write(
        root,
        "TownA.jsonl",
        '{"mesh": "StaticMesh /Game/Carla/Static/B.B", "materials": '
        + '["Material /Game/Carla/Mat/Red.Red", null, ""]}\n'
        + '{"mesh": "StaticMesh /Engine/BasicShapes/Cube.Cube", "materials": '
        + '["Material /Game/Carla/Mat/Red.Red"]}\r\n',
    )
    var second = _write(
        root,
        "TownB.jsonl",
        '{"mesh": "Class /Game/Carla/Only", "materials": '
        + '["Material /Engine/EngineMaterials/Default.Default", '
        + '"Material /Game/Carla/Mat/Blue.Blue"]}\n'
        + '{"mesh": "StaticMesh /Game/Carla/Static/A.A", "materials": []}\n',
    )
    var paths = List[String]()
    paths.append(first)
    paths.append(second)
    assert_equal(
        wanted_text(paths^),
        '{"meshes": ["/Game/Carla/Only", "/Game/Carla/Static/A", '
        + '"/Game/Carla/Static/B"], "materials": ["/Game/Carla/Mat/Blue", '
        + '"/Game/Carla/Mat/Red"]}',
    )
    var empty = List[String]()
    assert_equal(wanted_text(empty^), '{"meshes": [], "materials": []}')
    _remove(root)


def test_pending_skips_an_export_and_keeps_batches() raises:
    assert_equal(
        export_path("/work/raw", "/Game/Carla/Static/Foo", ".gltf"),
        "/work/raw/Carla/Static/Foo.gltf",
    )
    assert_equal(export_path("/work/raw", "/Game/A", ".mat"), "/work/raw/A.mat")
    assert_equal(export_path("/work/raw", "/Game/", ".gltf"), "/work/raw/.gltf")
    assert_equal(export_path("/work/raw", "short", ".gltf"), "/work/raw/.gltf")
    assert_equal(
        export_path("/work/raw", "/Game/A/B/", ".gltf"), "/work/raw/A/B/.gltf"
    )
    assert_equal(
        export_path("/work/raw", "/Game/A//B", ".gltf"), "/work/raw/A/B.gltf"
    )
    var root = _dir()
    _ = run_program(["mkdir", "-p", root + "/A"], 10)
    Path(export_path(root, "/Game/A/Keep", ".gltf")).write_text("x")
    var request = (
        '{"root":"'
        + root
        + '","batch":2,"meshes":["/Game/A/Keep","/Game/B","/Game/C","/Game/D",'
        + '"/Game/E"],"materials":["/Game/M"]}'
    )
    assert_equal(
        pending_text(request),
        '{"todo": 5, "meshes": ["/Game/B", "/Game/C", "/Game/D", "/Game/E"], '
        + '"materials": ["/Game/M"], "mesh_batches": [["/Game/B", "/Game/C"], '
        + '["/Game/D", "/Game/E"]], "material_batches": [["/Game/M"]]}',
    )
    with assert_raises(contains="batch is not positive"):
        _ = pending_text('{"root":"/tmp","batch":0,"meshes":[],"materials":[]}')
    with assert_raises(contains="pending request is not an object"):
        _ = pending_text("[]")
    _remove(root)


def test_the_command_prints_the_names_and_refuses_bad_use() raises:
    var root = _dir()
    var layout = _write(
        root,
        "Town.jsonl",
        '{"mesh": "StaticMesh /Game/A/B.B", "materials": []}\n',
    )
    var object_result = _cli(_two("object", "StaticMesh /Game/A/B.B"))
    assert_equal(object_result.status, 0)
    assert_equal(object_result.errors, "")
    assert_equal(object_result.output, "/Game/A/B\n")
    var relative = _cli(_two("relative", "/Game/A/B"))
    assert_equal(relative.status, 0)
    assert_equal(relative.output, "A/B.uasset\n")
    var exported = List[String]()
    exported.append("export")
    exported.append(root)
    exported.append("/Game/Carla/Static/Mesh")
    exported.append(".gltf")
    var mesh = _cli(exported^)
    assert_equal(mesh.status, 0)
    assert_equal(mesh.output, root + "/Carla/Static/Mesh.gltf\n")
    var files = List[String]()
    files.append("wanted")
    files.append(layout)
    var listed = _cli(files^)
    assert_equal(listed.status, 0)
    assert_equal(
        listed.output,
        '{"meshes": ["/Game/A/B"], "materials": []}\n',
    )
    var none = List[String]()
    none.append("wanted")
    var bare = _cli(none^)
    assert_equal(bare.status, 0)
    assert_equal(bare.output, '{"meshes": [], "materials": []}\n')
    var usage = _cli(List[String]())
    assert_equal(usage.status, 2)
    assert_true(usage.errors.startswith("usage: carla_town_paths "))
    var missing = _two("wanted", root + "/missing.jsonl")
    var failed = _cli(missing^)
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_paths:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def test_a_timed_out_batch_is_cut_in_half() raises:
    assert_equal(
        split_text('["/Game/Only"]'),
        '{"action": "gave_up", "path": "/Game/Only"}',
    )
    assert_equal(
        split_text('["/Game/A","/Game/B","/Game/C"]'),
        (
            '{"action": "split", "left": ["/Game/A"], "right": ["/Game/B",'
            ' "/Game/C"]}'
        ),
    )
    assert_equal(
        split_text('["/Game/A","/Game/B","/Game/C","/Game/D","/Game/E"]'),
        (
            '{"action": "split", "left": ["/Game/A", "/Game/B"], "right":'
            ' ["/Game/C", "/Game/D", "/Game/E"]}'
        ),
    )
    with assert_raises(contains="batch is empty"):
        _ = split_text("[]")
    with assert_raises(contains="package is not text"):
        _ = split_text("[1]")


def test_a_batch_becomes_the_umodel_arguments() raises:
    assert_equal(
        command_text(
            '{"umodel":"U","content":"C","out":"R","mesh":true,"packages":["/Game/A/B","/Game/C"]}'
        ),
        '["U","-game=ue4.26","-path=C","-export","-png","-out=R","-gltf","A/B.uasset","-pkg=C.uasset"]',
    )
    assert_equal(
        command_text(
            '{"umodel":"U","content":"C","out":"R","mesh":false,"packages":["/Game/Only"]}'
        ),
        '["U","-game=ue4.26","-path=C","-export","-png","-out=R","Only.uasset"]',
    )
    with assert_raises(contains="batch is empty"):
        _ = command_text(
            '{"umodel":"U","content":"C","out":"R","mesh":true,"packages":[]}'
        )
    with assert_raises(contains="command request is not an object"):
        _ = command_text("[]")
    with assert_raises(contains="mesh is not a bool"):
        _ = command_text(
            '{"umodel":"U","content":"C","out":"R","mesh":1,"packages":["/Game/A"]}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_paths"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
