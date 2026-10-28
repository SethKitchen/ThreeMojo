# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A vehicle export runs UModel, merges the meshes, and writes the package."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="vehicle-export-")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _cli(var arguments: List[String]) raises -> ProcessResult:
    """Run the built program."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_vehicle_export")
    command.extend(arguments^)
    return run_program(command, 60, merge_errors=False)


def _pad(text: String) -> String:
    """Return `text` padded to 36 characters."""
    var out = text
    while out.byte_length() < 36:
        out += " "
    return out


def test_an_unknown_id_is_refused() raises:
    var arguments = List[String]()
    arguments.append("vehicle.missing")
    var ran = _cli(arguments^)
    assert_equal(ran.status, 0)
    assert_equal(
        ran.output,
        "FAIL " + _pad("vehicle.missing") + " KeyError('vehicle.missing')\n",
    )


def test_a_pedestrian_blueprint_has_no_body() raises:
    var root = _dir()
    var folder = (
        root + "/cooked/CarlaUE4/Content/Carla/Blueprints/Vehicles/AudiA2"
    )
    _ = run_program(["mkdir", "-p", folder], 10)
    Path(folder + "/BP_AudiA2.uasset").write_text(
        "/Game/Carla/Static/Pedestrian/Walker\n"
    )
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("vehicle.audi.a2")
    var ran = _cli(arguments^)
    assert_equal(ran.status, 0)
    assert_equal(
        ran.output,
        "FAIL " + _pad("vehicle.audi.a2") + " no skeletal mesh among \n",
    )
    _remove(root)


def test_a_body_and_one_glass_mesh_are_exported() raises:
    var root = _dir()
    var content = root + "/cooked/CarlaUE4/Content"
    var folder = content + "/Carla/Blueprints/Vehicles/AudiA2"
    var mesh = content + "/Carla/Static/Car"
    _ = run_program(["mkdir", "-p", folder, mesh, root + "/umodel"], 10)
    Path(folder + "/BP_AudiA2.uasset").write_text(
        "/Game/Carla/Static/Car/SK_Body\n/Game/Carla/Static/Car/SM_Glass\n"
    )
    Path(mesh + "/SK_Body.uasset").write_text("skeletal")
    Path(mesh + "/SK_Body.uexp").write_text("0123456789ab")
    Path(mesh + "/SM_Glass.uasset").write_text("static")
    var writer = root + "/umodel/write_mesh.py"
    Path(writer).write_text(
        "import json, struct, sys\ndest, bin_path = sys.argv[1],"
        " sys.argv[2]\nblob = struct.pack('<9f', 0, 0, 0, 1, 0, 0, 0, 1, 0) +"
        " struct.pack('<3H', 0, 1, 2)\nopen(bin_path, 'wb').write(blob)\nname ="
        " bin_path.rsplit('/', 1)[-1]\ngltf = {\n 'asset': {'version':"
        " '2.0'},\n 'buffers': [{'uri': name, 'byteLength': len(blob)}],\n"
        " 'bufferViews': [\n  {'buffer': 0, 'byteOffset': 0, 'byteLength':"
        " 36},\n  {'buffer': 0, 'byteOffset': 36, 'byteLength': 6}],\n"
        " 'accessors': [\n  {'bufferView': 0, 'componentType': 5126, 'count':"
        " 3, 'type': 'VEC3'},\n  {'bufferView': 1, 'componentType': 5123,"
        " 'count': 3, 'type': 'SCALAR'}],\n 'meshes': [{'primitives':"
        " [{'attributes': {'POSITION': 0}, 'indices': 1}]}],\n 'nodes':"
        " [{'mesh': 0}],\n 'scenes': [{'nodes': [0]}],\n 'scene':"
        " 0}\nopen(dest, 'w').write(json.dumps(gltf))\n"
    )
    var script = root + "/umodel/umodel_64.exe"
    Path(script).write_text(
        "#!/bin/sh\n"
        "mode=\n"
        "out=\n"
        "rel=\n"
        'for arg in "$@"; do\n'
        '  case "$arg" in\n'
        "    -list) mode=list ;;\n"
        "    -export) mode=export ;;\n"
        "    -out=*) out=${arg#-out=} ;;\n"
        "    -*) ;;\n"
        "    *) rel=$arg ;;\n"
        "  esac\n"
        "done\n"
        'base=$(basename "$rel" .uasset)\n'
        'if [ "$mode" = list ]; then\n'
        '  if [ "$base" = SK_Body ]; then\n'
        '    echo "a b c SkeletalMesh $base"\n'
        "  else\n"
        '    echo "a b c StaticMesh $base"\n'
        "  fi\n"
        "  exit 0\n"
        "fi\n"
        'dest="$out/${rel%.uasset}.gltf"\n'
        'mkdir -p "$(dirname "$dest")"\n'
        'bin="${dest%.gltf}.bin"\n'
        "python3 "
        + writer
        + ' "$dest" "$bin"\n'
    )
    var mode = run_program(["chmod", "+x", script], 10)
    if mode.status != 0:
        raise Error(mode.output)
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("vehicle.audi.a2")
    var ran = _cli(arguments^)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    if not ran.output.startswith("OK   " + _pad("vehicle.audi.a2")):
        raise Error(ran.output + ran.errors)
    assert_true(ran.output.find("SK_Body + 1 attachments, ") >= 0)
    assert_true(ran.output.find(" MB\n") >= 0)
    assert_true(
        Path(root + "/packages/vehicle.audi.a2/vehicle.audi.a2.gltf").exists()
    )
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_vehicle_export"],
        180,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
