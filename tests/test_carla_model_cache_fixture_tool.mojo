# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The synthetic model-cache fixture is complete and self-consistent."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from bench.carla_model_cache_fixture import generate
from loaders.json import parse_json
from render.png import decode
from tools._sha256 import sha256_hex


def test_the_fixture_files_and_hashes_agree() raises:
    var root = mkdtemp()
    var summary = parse_json(generate(root))
    assert_equal(
        summary.integer(summary.get(summary.root(), "triangles")), 34992
    )
    var manifest = parse_json(Path(root + "/manifest.json").read_text())
    var entry = manifest.at(manifest.get(manifest.root(), "entries"), 0)
    var files = manifest.get(entry, "files")
    assert_equal(manifest.length(files), 3)
    for index in range(3):
        var item = manifest.at(files, index)
        var path = root + "/" + manifest.string(manifest.get(item, "path"))
        assert_equal(
            manifest.string(manifest.get(item, "sha256")),
            sha256_hex(Span(Path(path).read_bytes())),
        )
    var gltf = parse_json(Path(root + "/vehicle.gltf").read_text())
    var buffer = gltf.at(gltf.get(gltf.root(), "buffers"), 0)
    # Six faces of 55 * 55 vertices with 8 floats, and 54 * 54 * 6 indices.
    assert_equal(
        gltf.integer(gltf.get(buffer, "byteLength")),
        6 * (55 * 55 * 8 + 54 * 54 * 6) * 4,
    )
    assert_equal(
        len(Path(root + "/vehicle.bin").read_bytes()),
        gltf.integer(gltf.get(buffer, "byteLength")),
    )


def test_the_texture_holds_the_coordinate_pattern() raises:
    var root = mkdtemp()
    _ = generate(root)
    var image = decode(Path(root + "/vehicle.png").read_bytes())
    assert_equal(image.width, 1024)
    assert_equal(image.height, 1024)
    for point in [(0, 0), (300, 7), (1023, 1023)]:
        var x = point[0]
        var y = point[1]
        var at = (y * 1024 + x) * 4
        assert_true(image.pixels[at] == UInt8(x % 256))
        assert_true(image.pixels[at + 1] == UInt8(y % 256))
        assert_true(image.pixels[at + 2] == UInt8((x ^ y) % 256))
        assert_true(image.pixels[at + 3] == 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
