# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.meshopt`.

`assets/meshopt/meshopt.json` holds streams that meshoptimizer 0.22's
encoder made, some damaged on purpose, and what three.js 0.180's
`MeshoptDecoder` decodes from each, or the error it throws. It was written
by `three_meshopt.mjs`. `hill_required.gltf` and `hill_optional.gltf`
store every buffer view compressed, the first with a fallback buffer that
holds nothing and the second with one that holds the data unfiltered;
`meshopt.json` has what three.js's `GLTFLoader` reads from each.
"""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION, UV
from core.scene import Scene
from loaders.gltf import GltfModel, is_supported_extension, load_gltf
from loaders.json import JsonDocument, NULL, parse_json
from loaders.meshopt import (
    FILTER_EXPONENTIAL,
    FILTER_NONE,
    FILTER_OCTAHEDRAL,
    FILTER_QUATERNION,
    MESHOPT_ATTRIBUTES,
    MESHOPT_INDICES,
    MESHOPT_TRIANGLES,
    MeshoptFilter,
    MeshoptMode,
    decode_filter_exp,
    decode_filter_oct,
    decode_filter_quat,
    decode_gltf_buffer,
    decode_index_buffer,
    decode_index_sequence,
    decode_vertex_buffer,
    meshopt_filter,
    meshopt_mode,
)
from std.math import sqrt
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _reference() raises -> JsonDocument:
    return parse_json(Path("assets/meshopt/meshopt.json").read_text())


def _nibble(letter: UInt8) -> UInt8:
    if letter >= 97:
        return letter - 87
    return letter - 48


def _bytes(text: String) -> List[UInt8]:
    """Read a string of hexadecimal digits as bytes."""
    var digits = text.as_bytes()
    var out = List[UInt8](capacity=len(digits) // 2)
    for i in range(0, len(digits), 2):
        out.append((_nibble(digits[i]) << 4) | _nibble(digits[i + 1]))
    return out^


def test_every_stream_decodes_as_three_js_decodes_it() raises:
    var doc = _reference()
    var streams = doc.get(doc.root(), "streams")
    for s in range(doc.length(streams)):
        var entry = doc.at(streams, s)
        var name = doc.string(doc.get(entry, "name"))
        var count = doc.integer(doc.get(entry, "count"))
        var stride = doc.integer(doc.get(entry, "stride"))
        var mode = meshopt_mode(doc.string(doc.get(entry, "mode")))
        var filter = FILTER_NONE
        # A stream of indices has no filter, which JSON leaves out.
        if doc.has(entry, "filter"):
            filter = meshopt_filter(doc.string(doc.get(entry, "filter")))
        var source = _bytes(doc.string(doc.get(entry, "source")))
        var error = doc.get(entry, "error")
        if doc.kind(error) == NULL:
            var got = decode_gltf_buffer(count, stride, source, mode, filter)
            var want = _bytes(doc.string(doc.get(entry, "result")))
            assert_equal(len(got), len(want), name)
            for i in range(len(want)):
                assert_equal(got[i], want[i], name + " at " + String(i))
        else:
            # three.js says "Malformed buffer data: -2"; this says the same
            # after "meshopt: ".
            var parts = doc.string(error).split(": ")
            var code = String(parts[len(parts) - 1])
            with assert_raises(contains="malformed buffer data: " + code):
                _ = decode_gltf_buffer(count, stride, source, mode, filter)


def test_names_become_modes_and_filters() raises:
    assert_true(meshopt_mode("ATTRIBUTES") == MESHOPT_ATTRIBUTES)
    assert_true(meshopt_mode("TRIANGLES") == MESHOPT_TRIANGLES)
    assert_true(meshopt_mode("INDICES") == MESHOPT_INDICES)
    assert_true(meshopt_filter("NONE") == FILTER_NONE)
    assert_true(meshopt_filter("OCTAHEDRAL") == FILTER_OCTAHEDRAL)
    assert_true(meshopt_filter("QUATERNION") == FILTER_QUATERNION)
    assert_true(meshopt_filter("EXPONENTIAL") == FILTER_EXPONENTIAL)
    with assert_raises(contains="mode that is not known: POINTS"):
        _ = meshopt_mode("POINTS")
    with assert_raises(contains="filter that is not known: COLOR"):
        _ = meshopt_filter("COLOR")


def test_a_mode_or_a_filter_out_of_range_is_refused() raises:
    assert_false(MeshoptMode(3).is_valid())
    assert_false(MeshoptFilter(4).is_valid())
    var source: List[UInt8] = [0xA0]
    with assert_raises(contains="mode that is not known"):
        _ = decode_gltf_buffer(0, 4, source, MeshoptMode(3))
    with assert_raises(contains="filter that is not known"):
        _ = decode_gltf_buffer(
            0, 4, source, MESHOPT_ATTRIBUTES, MeshoptFilter(4)
        )


def test_the_specification_s_limits_are_kept() raises:
    var source: List[UInt8] = [0xE1]
    with assert_raises(contains="only ATTRIBUTES can have a filter"):
        _ = decode_gltf_buffer(
            3, 2, source, MESHOPT_TRIANGLES, FILTER_OCTAHEDRAL
        )
    with assert_raises(contains="only ATTRIBUTES can have a filter"):
        _ = decode_gltf_buffer(3, 2, source, MESHOPT_INDICES, FILTER_QUATERNION)
    with assert_raises(contains="multiple of 4 from 4 to 256"):
        _ = decode_vertex_buffer(1, 6, source)
    with assert_raises(contains="multiple of 4 from 4 to 256"):
        _ = decode_vertex_buffer(1, 260, source)
    with assert_raises(contains="multiple of 4 from 4 to 256"):
        _ = decode_vertex_buffer(1, 0, source)
    with assert_raises(contains="must not be negative"):
        _ = decode_vertex_buffer(-1, 4, source)
    with assert_raises(contains="size must be 2 or 4"):
        _ = decode_index_buffer(3, 1, source)
    with assert_raises(contains="multiple of 3"):
        _ = decode_index_buffer(4, 2, source)
    with assert_raises(contains="multiple of 3"):
        _ = decode_index_buffer(-3, 2, source)
    with assert_raises(contains="size must be 2 or 4"):
        _ = decode_index_sequence(3, 8, source)
    with assert_raises(contains="must not be negative"):
        _ = decode_index_sequence(-1, 2, source)
    var data = List[UInt8](length=16, fill=0)
    with assert_raises(contains="stride of 4 or 8"):
        decode_filter_oct(data, 1, 12)
    with assert_raises(contains="stride of 8"):
        decode_filter_quat(data, 1, 4)
    with assert_raises(contains="multiple of 4"):
        decode_filter_exp(data, 1, 6)
    with assert_raises(contains="multiple of 4"):
        decode_filter_exp(data, 1, 0)


def test_hand_made_streams_reach_the_rare_paths() raises:
    # A group of all escapes uses up the stream, so the second byte's
    # header is not there.
    var escapes: List[UInt8] = [0xA0, 0x02]
    for _ in range(8):
        escapes.append(0xFF)
    for _ in range(16):
        escapes.append(0)
    with assert_raises(contains="malformed buffer data: -2"):
        _ = decode_vertex_buffer(16, 4, escapes)
    # Three free indices read past the codes' table, so the second
    # triangle has no room.
    var free: List[UInt8] = [0xE1, 0xFF, 0xF0, 0xFF, 0, 0, 0]
    for _ in range(12):
        free.append(0)
    with assert_raises(contains="malformed buffer data: -2"):
        _ = decode_index_buffer(6, 2, free)
    # Five bytes of a number, all with the high bit: the bits past 32
    # are dropped and the fifth byte ends it anyway.
    var long: List[UInt8] = [0xD1, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0]
    var got = decode_index_sequence(1, 4, long)
    assert_equal(got[0], 0)
    assert_equal(got[3], 0xC0)
    # A filter over no elements does nothing.
    var empty = List[UInt8]()
    decode_filter_oct(empty, 0, 4)
    decode_filter_oct(empty, 0, 8)
    decode_filter_quat(empty, 0, 8)
    decode_filter_exp(empty, 0, 4)
    assert_equal(len(empty), 0)


def _hill(name: String) raises -> String:
    return Path("assets/meshopt/hill_" + name + ".gltf").read_text()


def _load(text: String, mut assets: Assets) raises -> GltfModel:
    var scene = Scene()
    return load_gltf(text, List[UInt8](), "assets/meshopt", scene, assets)


def _same(
    got: List[Float32], doc: JsonDocument, node: Int, what: String
) raises:
    """Check floats against three.js's numbers."""
    assert_equal(len(got), doc.length(node), what)
    for k in range(len(got)):
        assert_almost_equal(
            Float64(got[k]), doc.number(doc.at(node, k)), atol=1e-6, msg=what
        )


def test_a_compressed_model_reads_as_three_js_reads_it() raises:
    var ref_doc = _reference()
    var models = ref_doc.get(ref_doc.root(), "models")
    for name in ["required", "optional"]:
        var want = ref_doc.get(models, name)
        var assets = Assets()
        var model = _load(_hill(name), assets)
        ref geometry = assets.geometries.get(model.geometries[0])
        _same(
            geometry.attribute_view(POSITION).data,
            ref_doc,
            ref_doc.get(want, "position"),
            name,
        )
        _same(
            geometry.attribute_view(NORMAL).data,
            ref_doc,
            ref_doc.get(want, "normal"),
            name,
        )
        _same(
            geometry.attribute_view(UV).data,
            ref_doc,
            ref_doc.get(want, "uv"),
            name,
        )
        var index = ref_doc.get(want, "index")
        assert_equal(len(geometry.index), ref_doc.length(index))
        for k in range(len(geometry.index)):
            assert_equal(
                geometry.index[k], ref_doc.integer(ref_doc.at(index, k))
            )
        ref track = model.animations[0].tracks[0]
        _same(track.times, ref_doc, ref_doc.get(want, "times"), name)
        # A rotation key is normalized here, which three.js leaves to
        # whoever built the track; see `KeyframeTrack`.
        var values = ref_doc.get(want, "values")
        assert_equal(len(track.values), ref_doc.length(values))
        for key in range(len(track.values) // 4):
            var q = List[Float64]()
            for c in range(4):
                q.append(ref_doc.number(ref_doc.at(values, key * 4 + c)))
            var length = sqrt(
                q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]
            )
            for c in range(4):
                assert_almost_equal(
                    Float64(track.values[key * 4 + c]),
                    q[c] / length,
                    atol=1e-6,
                    msg=name,
                )


def test_a_fallback_buffer_with_no_mark_is_not_read_either() raises:
    # A buffer past the first with no URI holds nothing, as a fallback
    # does, and only compressed views name it.
    var text = _hill("required").replace(
        ',"extensions":{"EXT_meshopt_compression":{"fallback":true}}', ""
    )
    var assets = Assets()
    var model = _load(text, assets)
    assert_equal(len(assets.geometries.get(model.geometries[0]).index), 216)
    assert_true(is_supported_extension("EXT_meshopt_compression"))


def _refused(old: String, new: String, message: String) raises:
    var original = _hill("required")
    var text = original.replace(old, new)
    assert_true(text != original, old)
    var assets = Assets()
    with assert_raises(contains=message):
        _ = _load(text, assets)


def test_a_malformed_compressed_view_is_refused() raises:
    _refused(
        '"buffer":0,"byteOffset":0,',
        '"buffer":1,"byteOffset":0,',
        "names a buffer that is not there",
    )
    _refused(
        '"buffer":0,"byteOffset":0,',
        '"buffer":7,"byteOffset":0,',
        "names a buffer that is not there",
    )
    _refused(
        '"byteOffset":704,"byteLength":61',
        '"byteOffset":704,"byteLength":6100',
        "compressed buffer view runs past its buffer",
    )
    _refused(
        '"byteOffset":704,"byteLength":61',
        '"byteOffset":-4,"byteLength":61',
        "compressed buffer view runs past its buffer",
    )
    _refused(
        '"byteOffset":704,"byteLength":61',
        '"byteOffset":704,"byteLength":-1',
        "compressed buffer view runs past its buffer",
    )
    _refused(
        '"byteLength":392,',
        '"byteLength":400,',
        "count times its byteStride",
    )
    _refused(
        '}},"byteStride":8,',
        '}},"byteStride":12,',
        "byteStride must match",
    )
    _refused(
        '"mode":"TRIANGLES"',
        '"mode":"POINTS"',
        "mode that is not known",
    )
    _refused(
        '"filter":"QUATERNION"',
        '"filter":"SPHERICAL"',
        "filter that is not known",
    )
    _refused(
        '"byteOffset":656,"byteLength":48',
        '"byteOffset":656,"byteLength":47',
        "malformed buffer data: -3",
    )
    _refused(
        '"byteOffset":656,"byteLength":48',
        '"byteOffset":656,"byteLength":0',
        "malformed buffer data: -2",
    )
    # A view that is not compressed cannot read the fallback.
    _refused(
        (
            '"extensions":{"EXT_meshopt_compression":{"buffer":0,'
            + '"byteOffset":656,"byteLength":48,"byteStride":4,"count":5,'
            + '"mode":"ATTRIBUTES","filter":"EXPONENTIAL"}}'
        ),
        '"name":"plain"',
        "only a compressed buffer view can name a fallback buffer",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
