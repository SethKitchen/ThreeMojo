# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town package is refused for the same engine words as the Python check."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_clean import refusal


def _mkdir(path: String) raises:
    """Make a directory."""
    _ = run_program(["mkdir", "-p", path], 10)


def test_a_clean_package_is_kept() raises:
    var directory = mkdtemp(prefix="town clean ")
    Path(directory + "/town.gltf").write_text('{"buffers":[]}')
    Path(directory + "/Town.xodr").write_text("<OpenDRIVE/>")
    _mkdir(directory + "/unreal")
    Path(directory + "/unreal/note.txt").write_text("ok")
    Path(directory + "/data.bin").write_text("/Game/secret")
    # A different stem: on a case-insensitive volume, as macOS uses by
    # default, `Town.GLTF` is the same file as `town.gltf`.
    Path(directory + "/Scene.GLTF").write_text("/Game/not-scanned")
    assert_equal(refusal(directory), "")
    assert_equal(refusal(directory + "/missing"), "")
    _ = run_program(["rm", "-rf", directory], 10)


def test_a_file_name_is_refused_before_its_text() raises:
    var directory = mkdtemp(prefix="town clean ")
    Path(directory + "/unreal.gltf").write_text("clean text")
    assert_equal(
        refusal(directory), "unclean file name: " + directory + "/unreal.gltf"
    )
    var other = mkdtemp(prefix="town clean ")
    Path(other + "/mesh.UASSET").write_text("x")
    assert_equal(refusal(other), "unclean file name: " + other + "/mesh.UASSET")
    _ = run_program(["rm", "-rf", directory], 10)
    _ = run_program(["rm", "-rf", other], 10)


def test_gltf_and_xodr_text_uses_the_python_window() raises:
    var directory = mkdtemp(prefix="town clean ")
    var long = String("prefix ")
    for _ in range(80):
        long += "a"
    long += "unreal"
    for _ in range(80):
        long += "b"
    Path(directory + "/town.gltf").write_text(long)
    assert_equal(
        refusal(directory),
        (
            "unclean text in town.gltf:"
            " 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaunrealbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'"
        ),
    )
    var quoted = mkdtemp(prefix="town clean ")
    Path(quoted + "/town.gltf").write_text("a quote 'ue4' here")
    assert_equal(
        refusal(quoted),
        "unclean text in town.gltf: \"a quote 'ue4' here\"",
    )
    var plain = mkdtemp(prefix="town clean ")
    Path(plain + "/town.gltf").write_text(
        "ue40 is fine and blue4 and EpicGames"
    )
    assert_equal(refusal(plain), "")
    var road = mkdtemp(prefix="town clean ")
    _mkdir(road + "/sub")
    Path(road + "/sub/Map.xodr").write_text("see umodel")
    assert_equal(refusal(road), "unclean text in Map.xodr: 'see umodel'")
    _ = run_program(["rm", "-rf", directory], 10)
    _ = run_program(["rm", "-rf", quoted], 10)
    _ = run_program(["rm", "-rf", plain], 10)
    _ = run_program(["rm", "-rf", road], 10)


def test_the_command_refuses_one_package() raises:
    var directory = mkdtemp(prefix="town clean ")
    Path(directory + "/town.gltf").write_text("path /ENGINE/Basic")
    var result = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_clean", directory],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 1)
    assert_equal(
        result.errors, "unclean text in town.gltf: 'path /ENGINE/Basic'\n"
    )
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_clean"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_clean"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
