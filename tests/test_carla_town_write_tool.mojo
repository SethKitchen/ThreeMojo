# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town package's binary glTF matches the previous writer."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._tree import tool_mojo
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.carla_town_write import write_town


def _request(out_dir: String) -> String:
    """Return the one-triangle package request."""
    var text = String('{"out_dir":"')
    text += out_dir
    text += (
        '","name":"carla.town.fixture","gltf":{"materials":[{"name":"plain",'
        '"pbrMetallicRoughness":{"baseColorFactor":[0.5,0.5,0.5,1],'
        '"metallicFactor":0.0,"roughnessFactor":0.7}}]},"groups":[{"lod":0,'
        '"kind":"building","cell":[0,0],"material":0,"positions":[[[0.0,0.0,0.0],'
        '[1.0,0.0,0.0],[0.0,1.0,0.0]]],"normals":[[[0.0,1.0,0.0],[0.0,1.0,0.0],'
        '[0.0,1.0,0.0]]],"uvs":[[[0.0,0.0],[1.0,0.0],[0.0,1.0]]],"triangles":'
        '[[[0,1,2]]]}],"lamps":[[1.25,2.5,3.75]]}'
    )
    return text


def test_the_binary_gltf_matches_the_previous_package() raises:
    var out_dir = String("/tmp/carla-town-write")
    var made = run_program(["mkdir", "-p", out_dir], 10)
    if made.status != 0:
        raise Error(made.errors)
    var result = write_town(_request(out_dir))
    assert_equal(result, '{"triangles":[1,0],"nodes":1}')
    assert_equal(
        sha256_hex(Path(out_dir + "/carla.town.fixture.glb").read_bytes()),
        "94ebcbe4b3fb2b9ae7399437a12ec632fc3e9b124c9cd775bd970e4d8fbdb492",
    )


def test_cli_prints_the_counts() raises:
    var out_dir = String("/tmp/carla-town-write-cli")
    var made = run_program(["mkdir", "-p", out_dir], 10)
    if made.status != 0:
        raise Error(made.errors)
    var path = out_dir + "/write.json"
    Path(path).write_text(_request(out_dir + "/out"))
    var nested = run_program(["mkdir", "-p", out_dir + "/out"], 10)
    if nested.status != 0:
        raise Error(nested.errors)
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_write", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, '{"triangles":[1,0],"nodes":1}\n')
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_write"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_write FILE\n")


def test_a_request_that_is_not_an_object_is_refused() raises:
    with assert_raises(contains="town write is not an object"):
        _ = write_town("[]")


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_write"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
