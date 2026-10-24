# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town binary glTF matches the reviewed Python packer."""

from std.os.path import isfile
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.carla_town_glb import pack_glb


comptime _PACK_SHA = (
    "c831c65d59f1d85bfc1e052101c5d5d080ba57f69b575b8a973374479d035653"
)
"""SHA-256 of the package that stores a PNG and a JPEG."""
comptime _SOLO_SHA = (
    "42954f7db92fd7a70f60e69ab6b14982ca6e2c31909f698de6d2f564d6432a52"
)
"""SHA-256 of the package that has no images and a one-byte buffer."""
comptime _PACK_JSON = (
    '{"asset":{"version":"2.0","generator":"ThreeMojo'
    ' build_towns.py"},"buffers":[{"byteLength":3,"uri":"pack.bin"}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":3}],"accessors":[{"bufferView":0,"componentType":5126,"count":1,"type":"SCALAR","min":[0.5],"max":[0.5]}],"images":[{"uri":"textures/red.png"},{"uri":"textures/blue.jpg","name":"drop-me"}],"materials":[{"name":"plain","doubleSided":true,"pbrMetallicRoughness":{"metallicFactor":0.0,"roughnessFactor":0.6}}],"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}],"nodes":[{"name":"building_0_0_lod0","mesh":0,"extras":{"carla_kind":"building","carla_lod":0}}],"scenes":[{"nodes":[0]}],"scene":0}'
)
"""The loose glTF of the image package."""
comptime _SOLO_JSON = '{"buffers":[{"byteLength":1,"uri":"solo.bin"}],"bufferViews":[],"accessors":[],"meshes":[],"nodes":[],"scenes":[{"nodes":[]}]}'
"""The loose glTF of the package with no images."""


def _png() -> List[UInt8]:
    """Return the sample PNG bytes."""
    var out = List[UInt8]()
    out.append(0x89)
    out.append(0x50)
    out.append(0x4E)
    out.append(0x47)
    out.append(0x0D)
    out.append(0x0A)
    return out^


def _jpeg() -> List[UInt8]:
    """Return the sample JPEG bytes."""
    var out = List[UInt8]()
    out.append(0xFF)
    out.append(0xD8)
    out.append(0xFF)
    return out^


def _write_images(directory: String) raises:
    """Write the two sample images."""
    var textures = directory + "/textures"
    _ = run_program(["mkdir", "-p", textures], 10)
    Path(textures + "/red.png").write_bytes(Span(_png()))
    Path(textures + "/blue.jpg").write_bytes(Span(_jpeg()))


def test_images_are_stored_and_loose_files_go() raises:
    var directory = mkdtemp(prefix="town glb ")
    Path(directory + "/pack.gltf").write_text(_PACK_JSON)
    var body = List[UInt8]()
    body.append(1)
    body.append(2)
    body.append(3)
    Path(directory + "/pack.bin").write_bytes(Span(body))
    _write_images(directory)
    Path(directory + "/Town.xodr").write_text("<OpenDRIVE/>")
    pack_glb(directory, "pack")
    var packed = Path(directory + "/pack.glb").read_bytes()
    assert_equal(len(packed), 804)
    assert_equal(sha256_hex(Span(packed)), _PACK_SHA)
    assert_equal(Int(packed[0]), 0x67)
    assert_equal(Int(packed[1]), 0x6C)
    assert_equal(Int(packed[2]), 0x54)
    assert_equal(Int(packed[3]), 0x46)
    assert_true(isfile(directory + "/Town.xodr"))
    assert_false(isfile(directory + "/pack.gltf"))
    assert_false(isfile(directory + "/pack.bin"))
    assert_false(Path(directory + "/textures").exists())
    _ = run_program(["rm", "-rf", directory], 10)


def test_a_package_without_images_still_pads_the_buffer() raises:
    var directory = mkdtemp(prefix="town glb ")
    Path(directory + "/solo.gltf").write_text(_SOLO_JSON)
    var body = List[UInt8]()
    body.append(90)
    Path(directory + "/solo.bin").write_bytes(Span(body))
    pack_glb(directory, "solo")
    var packed = Path(directory + "/solo.glb").read_bytes()
    assert_equal(len(packed), 144)
    assert_equal(sha256_hex(Span(packed)), _SOLO_SHA)
    assert_false(isfile(directory + "/solo.gltf"))
    _ = run_program(["rm", "-rf", directory], 10)


def test_the_command_packs_one_package() raises:
    var directory = mkdtemp(prefix="town glb ")
    Path(directory + "/pack.gltf").write_text(_PACK_JSON)
    var body = List[UInt8]()
    body.append(1)
    body.append(2)
    body.append(3)
    Path(directory + "/pack.bin").write_bytes(Span(body))
    _write_images(directory)
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_glb",
            directory,
            "pack",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    var packed = Path(directory + "/pack.glb").read_bytes()
    assert_equal(sha256_hex(Span(packed)), _PACK_SHA)
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_glb"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    Path(directory + "/pack.gltf").write_text("{")
    var bad_bin = List[UInt8]()
    Path(directory + "/pack.bin").write_bytes(Span(bad_bin))
    var bad = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_glb",
            directory,
            "pack",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(bad.status, 1)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_glb"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
