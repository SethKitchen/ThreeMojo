# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Far-bake atlas names match the Python identity, without NumPy."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
)

from tools.carla_bake_identity import bake_key, bake_key_reads
from tools.carla_geometry_digest import digest_text


def _request(
    gltf: String,
    out_dir: String,
    parts: String,
    settings: String,
    mesh: String = "/Game/Fixture",
    kind: String = "baked",
    version: Int = 0,
) -> String:
    """Return one identity request."""
    var text = (
        '{"gltf":'
        + gltf
        + ',"out_dir":"'
        + out_dir
        + '","mesh":"'
        + mesh
        + '","kind":"'
        + kind
        + '","parts":'
        + parts
        + ',"settings":'
        + settings
    )
    if version != 0:
        text += ',"version":' + String(version)
    text += "}"
    return text^


def _fixture() raises -> String:
    """Return a directory with the two sample textures."""
    var root = mkdtemp(prefix="bake identity ")
    Path(root + "/red.png").write_bytes("red pixels".as_bytes())
    Path(root + "/green.png").write_bytes("green pixels".as_bytes())
    return root


def _gltf() -> String:
    """Return the two-material sample document."""
    return '{"materials":[{"name":"red","pbrMetallicRoughness":{"baseColorFactor":[1,1,1,1],"baseColorTexture":{"index":0}}},{"name":"green","pbrMetallicRoughness":{"baseColorFactor":[1,1,1,1],"baseColorTexture":{"index":1}}}],"textures":[{"source":0,"sampler":0},{"source":1,"sampler":0}],"images":[{"uri":"red.png"},{"uri":"green.png"}],"samplers":[{"wrapS":10497,"wrapT":10497}]}'


def test_order_kind_and_settings_change_the_tag() raises:
    var root = _fixture()
    var original = bake_key(
        _request(_gltf(), root, '[["left",0],["right",1]]', '{"samples":4}')
    )
    assert_equal(
        original,
        "baked_f599ed4b0c0a1b3e1ce6e0842eda85ceb9c9f0b781c59dd5b3086aa4cf0bde97",
    )
    assert_not_equal(
        original,
        bake_key(
            _request(_gltf(), root, '[["left",1],["right",0]]', '{"samples":4}')
        ),
    )
    assert_not_equal(
        original,
        bake_key(_request(_gltf(), root, '[["left",0]]', '{"samples":4}')),
    )
    assert_not_equal(
        original,
        bake_key(
            _request(_gltf(), root, '[["left",0],["left",0]]', '{"samples":4}')
        ),
    )
    assert_not_equal(
        original,
        bake_key(
            _request(
                _gltf(), root, '[["changed",0],["right",1]]', '{"samples":4}'
            )
        ),
    )
    assert_not_equal(
        original,
        bake_key(
            _request(
                _gltf(),
                root,
                '[["left",0],["right",1]]',
                '{"samples":4}',
                kind="impostor",
            )
        ),
    )
    assert_not_equal(
        original,
        bake_key(
            _request(_gltf(), root, '[["left",0],["right",1]]', '{"samples":8}')
        ),
    )
    assert_not_equal(
        original,
        bake_key(
            _request(
                _gltf(),
                root,
                '[["left",0],["right",1]]',
                '{"samples":4}',
                version=2,
            )
        ),
    )


def test_parameters_sampler_and_file_bytes_change_the_tag() raises:
    var root = _fixture()
    var original = bake_key(
        _request(_gltf(), root, '[["left",0],["right",1]]', '{"samples":4}')
    )
    var masked = String(_gltf()).replace(
        '"name":"red"', '"name":"red","alphaMode":"MASK"'
    )
    assert_not_equal(
        original,
        bake_key(
            _request(masked, root, '[["left",0],["right",1]]', '{"samples":4}')
        ),
    )
    var cutoff = String(_gltf()).replace(
        '"name":"red"', '"name":"red","alphaCutoff":0.25'
    )
    assert_not_equal(
        original,
        bake_key(
            _request(cutoff, root, '[["left",0],["right",1]]', '{"samples":4}')
        ),
    )
    Path(root + "/red.png").write_bytes(
        "new pixels at the same path".as_bytes()
    )
    assert_not_equal(
        original,
        bake_key(
            _request(_gltf(), root, '[["left",0],["right",1]]', '{"samples":4}')
        ),
    )


def test_table_order_and_output_directory_are_not_identities() raises:
    var root = _fixture()
    var original = bake_key(
        _request(_gltf(), root, '[["left",0],["right",1]]', '{"samples":4}')
    )
    var other = mkdtemp(prefix="bake identity other ")
    Path(other + "/red.png").write_bytes(Path(root + "/red.png").read_bytes())
    Path(other + "/green.png").write_bytes(
        Path(root + "/green.png").read_bytes()
    )
    assert_equal(
        original,
        bake_key(
            _request(
                _gltf(), other, '[["left",0],["right",1]]', '{"samples":4}'
            )
        ),
    )
    var reversed = '{"materials":[{"name":"green","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"baseColorFactor":[1,1,1,1]}},{"name":"red","pbrMetallicRoughness":{"baseColorTexture":{"index":1},"baseColorFactor":[1,1,1,1]}}],"textures":[{"sampler":1,"source":0},{"sampler":1,"source":1}],"images":[{"uri":"green.png"},{"uri":"red.png"}],"samplers":[{"unused":true},{"wrapT":10497,"wrapS":10497}]}'
    assert_equal(
        original,
        bake_key(
            _request(
                reversed, root, '[["left",1],["right",0]]', '{"samples":4}'
            )
        ),
    )


def test_one_build_reads_a_shared_image_once() raises:
    var root = _fixture()
    var gltf = '{"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}],"textures":[{"source":0}],"images":[{"uri":"red.png"}]}'
    var pair = bake_key_reads(_request(gltf, root, '[["a",0],["b",1]]', "{}"))
    assert_equal(pair[1], 1)
    assert_true(pair[0].startswith("baked_"))


def test_factors_and_missing_sampler_need_no_extra_files() raises:
    var plain = bake_key(
        '{"gltf":{"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,1]}}]},"out_dir":"/tmp","mesh":"mesh","kind":"baked","parts":[["shape",0]],"settings":{}}'
    )
    assert_true(plain.startswith("baked_"))
    assert_equal(plain.byte_length(), 6 + 64)
    var changed = bake_key(
        '{"gltf":{"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[0,0,0,1]}}]},"out_dir":"/tmp","mesh":"mesh","kind":"baked","parts":[["shape",0]],"settings":{}}'
    )
    assert_not_equal(plain, changed)
    var root = _fixture()
    var gltf = '{"materials":[{"extraTexture":null,"extensions":{"fixture":{"unusedTexture":{}}},"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},{"pbrMetallicRoughness":{"baseColorTexture":{"index":1}}}],"textures":[{"source":0},{"source":1}],"images":[{"uri":"red.png"},{"uri":"green.png"}]}'
    var first = bake_key(_request(gltf, root, '[["left",0],["right",1]]', "{}"))
    var mime = '{"materials":[{"extraTexture":null,"extensions":{"fixture":{"unusedTexture":{}}},"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},{"pbrMetallicRoughness":{"baseColorTexture":{"index":1}}}],"textures":[{"source":0},{"source":1}],"images":[{"uri":"red.png","mimeType":"image/png"},{"uri":"green.png"}]}'
    assert_not_equal(
        first, bake_key(_request(mime, root, '[["left",0],["right",1]]', "{}"))
    )


def test_the_simple_material_keeps_the_pinned_tag() raises:
    var tag = bake_key(
        '{"gltf":{"materials":[{"base":[1,2,3]}]},"out_dir":"/tmp","mesh":"mesh","kind":"baked","parts":[["shape",0]],"settings":{}}'
    )
    assert_equal(
        tag,
        "baked_b3697ccb0e157a5f8aeba3bc58f0949dc000188f799d294396c65ea585779432",
    )


def test_a_missing_file_and_a_nonfinite_number_fail() raises:
    var root = _fixture()
    with assert_raises():
        _ = bake_key(
            _request(
                _gltf(),
                root + "-absent",
                '[["left",0],["right",1]]',
                '{"samples":4}',
            )
        )
    with assert_raises():
        _ = bake_key(
            '{"gltf":{"materials":[{"factor":NaN}]},"out_dir":"/tmp","mesh":"mesh","kind":"baked","parts":[["shape",0]],"settings":{}}'
        )


def _primitive(x: String) -> String:
    """Return one primitive whose first position is `x`."""
    return (
        '{"primitives":[{"positions":{"shape":[1,3],"values":['
        + x
        + ',0,0]},"normals":{"shape":[1,3],"values":[0,1,0]},'
        + '"uvs":{"shape":[1,2],"values":[0,0]},'
        + '"triangles":{"shape":[1,3],"values":[0,0,0]}}]}'
    )


def test_a_geometry_or_setting_change_changes_the_atlas_tag() raises:
    """The atlas name follows the geometry digest, the target, and the density.
    """
    var first = digest_text(_primitive("0"))[0]
    var second = digest_text(_primitive("1"))[0]
    assert_not_equal(first, second)
    var nested = digest_text(
        '{"primitives":[{"positions":[[0,0,0]],"normals":[[0,1,0]],'
        + '"uvs":[[0,0]],"triangles":[[0,0,0]]}]}'
    )[0]
    assert_equal(first, nested)
    var gltf = '{"materials":[{"name":"plain"}]}'
    var original = bake_key(
        _request(gltf, "/tmp", '[["' + first + '",0]]', "[24,6.0]")
    )
    assert_not_equal(
        original,
        bake_key(_request(gltf, "/tmp", '[["' + second + '",0]]', "[24,6.0]")),
    )
    assert_equal(
        original,
        bake_key(_request(gltf, "/tmp", '[["' + nested + '",0]]', "[24,6.0]")),
    )
    assert_not_equal(
        original,
        bake_key(_request(gltf, "/tmp", '[["' + first + '",0]]', "[8,6.0]")),
    )
    assert_not_equal(
        original,
        bake_key(_request(gltf, "/tmp", '[["' + first + '",0]]', "[24,7.0]")),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
