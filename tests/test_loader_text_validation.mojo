# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""External loader bytes must be valid UTF-8 before they become strings."""

from core.binary import append_little_endian_u32
from std.testing import TestSuite, assert_equal, assert_false, assert_raises
from std.pathlib import Path
from core.assets import Assets
from core.scene import Scene
from test_scratch import TestScratch, temporary_path
from loaders.gltf import split_glb, read_gltf
from loaders.gltf_gaussian_splat import (
    read_gltf_gaussian_splats,
    read_gltf_gaussian_splat_scene,
)
from exporters.usdz import UsdzFiles
from loaders.fbx_tree import parse_fbx
from loaders.gaussian_splat_ply import (
    _header_lines,
    detect_spherical_harmonics_degree,
)
from loaders.draco import _metadata_name, decode_draco
from loaders.draco_buffer import DracoBuffer
from loaders.vtk import parse_vtk
from loaders.ultrahdr import parse_ultrahdr, XMP_NAMESPACE
from loaders.lwo import lwo_model_name
from loaders.pdb import parse_pdb
from loaders.svg import parse_svg
from loaders.three_mf import _linear, parse_3mf
from loaders.usda_parser import attribute_match
from loaders.utf8 import byte_slice, char_start, leading_utf8_bom
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive


def test_only_the_complete_utf8_byte_order_mark_is_skipped() raises:
    var mark: List[UInt8] = [0xEF, 0xBB, 0xBF]
    assert_equal(leading_utf8_bom(Span(mark)), 3)
    var cases: List[List[UInt8]] = [
        [],
        [0xEF],
        [0xEF, 0xBB],
        [0xEE, 0xBB, 0xBF],
        [0xEF, 0xBA, 0xBF],
        [0xEF, 0xBB, 0xBE],
    ]
    for bytes in cases:
        assert_equal(leading_utf8_bom(Span(bytes)), 0)


def invalid_sequences() -> List[List[UInt8]]:
    """Return distinct malformed UTF-8 byte sequences."""
    return [
        [0x80],
        [0xC0, 0xAF],
        [0xED, 0xA0, 0x80],
        [0xF4, 0x90, 0x80, 0x80],
        [0xE2, 0x82],
        [0xFF],
    ]


def bytes_of(text: String) -> List[UInt8]:
    """Return a copy of valid text bytes."""
    var out = List[UInt8](text.as_bytes())
    return out^


def utf8_error(bytes: List[UInt8]) raises -> String:
    """Get the pinned standard decoder's error for this malformed input."""
    try:
        _ = String(from_utf8=Span(bytes))
    except error:
        return String(error)
    raise Error("the negative fixture is valid UTF-8")


def le32(mut out: List[UInt8], value: Int):
    """Append a little-endian 32-bit value."""
    append_little_endian_u32(out, value)


def glb(var text: List[UInt8]) -> List[UInt8]:
    """Build a GLB with a single JSON chunk."""
    while len(text) % 4 != 0:
        text.append(32)
    var out = List[UInt8]()
    le32(out, 0x46546C67)
    le32(out, 2)
    le32(out, 20 + len(text))
    le32(out, len(text))
    le32(out, 0x4E4F534A)
    out.extend(text^)
    return out^


def test_a_cut_inside_a_character_moves_back_to_its_start() raises:
    # `a` is one byte, `é` two and `€` three: they start at 0, 1 and 3.
    var text = String("aé€")
    assert_equal(char_start(text, -1), 0)
    assert_equal(char_start(text, 0), 0)
    assert_equal(char_start(text, 2), 1)
    assert_equal(char_start(text, 5), 3)
    assert_equal(char_start(text, 6), 6)
    assert_equal(char_start(text, 9), 6)
    assert_equal(byte_slice(text, 0, 2), "a")
    assert_equal(byte_slice(text, 2, 6), "é€")
    assert_equal(byte_slice(text, 4, 5), "")
    # Bytes that are not UTF-8 stop at the first byte.
    var stray = String(unsafe_from_utf8=[UInt8(0x80), UInt8(0x80)])
    assert_equal(char_start(stray, 1), 0)


def _entry(name: String, text: String) -> ZipEntry:
    var data = List[UInt8]()
    for byte in text.as_bytes():
        data.append(byte)
    return ZipEntry(name, ZIP_STORED, data^)


def test_text_cut_at_a_fixed_byte_never_splits_a_character() raises:
    # Each reader cuts at a fixed byte, as three.js cuts at a fixed
    # character. A character across the cut is read or refused, and the
    # process goes on.
    var mark = "é"
    var atom = (
        "ATOM      1  N   ALA A   1   "
        + mark
        + "  11.104   6.134  -6.504  1.00  0.00           N\n"
    )
    assert_equal(len(parse_pdb(atom).atoms), 1)
    with assert_raises(contains="names no element"):
        _ = parse_svg(
            '<svg xmlns="http://www.w3.org/2000/svg"'
            ' xmlns:xlink="http://www.w3.org/1999/xlink"><use'
            ' xlink:href="é"/></svg>'
        )
    assert_equal(lwo_model_name("Objects€"), "€")
    assert_equal(lwo_model_name(""), "")
    assert_false(Bool(attribute_match("int€ x")))
    with assert_raises():
        _ = _linear("#FF000é")
    # A part the model never uses may have any name.
    var entries = List[ZipEntry]()
    entries.append(
        _entry(
            "_rels/.rels",
            (
                '<Relationships><Relationship Target="/3D/3dmodel.model"'
                ' Id="r"/></Relationships>'
            ),
        )
    )
    entries.append(
        _entry(
            "3D/3dmodel.model",
            (
                '<model unit="millimeter"><resources><object id="1"><mesh>'
                '<vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0"'
                ' z="0"/><vertex x="0" y="1" z="0"/></vertices><triangles>'
                '<triangle v1="0" v2="1" v3="2"/></triangles></mesh></object>'
                '</resources><build><item objectid="1"/></build></model>'
            ),
        )
    )
    entries.append(_entry("3D/Textures/é.png", "unused"))
    var scene = Scene()
    var assets = Assets()
    assert_equal(parse_3mf(zip_archive(entries), scene, assets).mesh_count, 1)


def test_a_splat_ply_shorter_than_its_magic_is_refused() raises:
    for text in [String(""), "pl", "abc"]:
        var bytes = List[UInt8]()
        for byte in text.as_bytes():
            bytes.append(byte)
        with assert_raises(contains="missing PLY header"):
            _ = _header_lines(bytes)


def test_glb_validates_json_utf8() raises:
    var text = '{"name":"é水🙂"}'
    assert_equal(String(split_glb(glb(bytes_of(text)))[0].strip()), text)
    for bytes in invalid_sequences():
        var raw = bytes_of('{"name":"')
        raw.extend(Span(bytes))
        raw.extend(bytes_of('"}'))
        with assert_raises(contains=utf8_error(bytes)):
            _ = split_glb(glb(raw^))


def test_gltf_file_readers_validate_before_scene_mutation() raises:
    var path = temporary_path("text.gltf")
    var valid = bytes_of('{"asset":{"version":"2.0"},"nodes":[]}')
    Path(path).write_bytes(valid)
    var scene = Scene()
    var assets = Assets()
    _ = read_gltf(path, scene, assets)
    assert_equal(len(read_gltf_gaussian_splats(path)), 0)
    assert_equal(len(read_gltf_gaussian_splat_scene(path, scene)), 0)
    var before = scene.count()
    for bytes in invalid_sequences():
        var raw = bytes_of('{"asset":{"version":"2.0"},"name":"')
        raw.extend(Span(bytes))
        raw.extend(bytes_of('"}'))
        Path(path).write_bytes(raw)
        with assert_raises(contains=utf8_error(bytes)):
            _ = read_gltf(path, scene, assets)
        with assert_raises(contains=utf8_error(bytes)):
            _ = read_gltf_gaussian_splats(path)
        with assert_raises(contains=utf8_error(bytes)):
            _ = read_gltf_gaussian_splat_scene(path, scene)
        assert_equal(scene.count(), before)


def binary_fbx(name: List[UInt8], text: List[UInt8]) -> List[UInt8]:
    """Build one binary FBX node holding one string property."""
    var out = bytes_of("Kaydara FBX Binary  \0")
    out.append(0x1A)
    out.append(0)
    le32(out, 7400)
    var property_size = 5 + len(text)
    le32(out, 27 + 13 + len(name) + property_size)
    le32(out, 1)
    le32(out, property_size)
    out.append(UInt8(len(name)))
    out.extend(Span(name))
    out.append(83)
    le32(out, len(text))
    out.extend(Span(text))
    out.extend(List[UInt8](length=177, fill=0))
    return out^


def test_fbx_text_and_binary_validate_utf8() raises:
    var valid = bytes_of("é水🙂")
    var document = parse_fbx(binary_fbx(valid, valid))
    assert_equal(document.name(1), "é水🙂")
    for bytes in invalid_sequences():
        var raw = bytes_of('FBXVersion: 7400\nName: "')
        raw.extend(Span(bytes))
        raw.extend(bytes_of('"\n'))
        with assert_raises(contains=utf8_error(bytes)):
            _ = parse_fbx(raw)
        with assert_raises(contains=utf8_error(bytes)):
            _ = parse_fbx(binary_fbx(bytes, valid))
        with assert_raises(contains=utf8_error(bytes)):
            _ = parse_fbx(binary_fbx(valid, bytes))


def test_splat_ply_header_validates_utf8() raises:
    var good = _header_lines(bytes_of("ply\ncomment é水🙂\nend_header\n"))
    assert_equal(good[1], "comment é水🙂")
    for bytes in invalid_sequences():
        var raw = bytes_of("ply\ncomment ")
        raw.extend(Span(bytes))
        raw.extend(bytes_of("\nend_header\n"))
        with assert_raises(contains=utf8_error(bytes)):
            _ = _header_lines(raw)
        with assert_raises(contains=utf8_error(bytes)):
            _ = detect_spherical_harmonics_degree(raw)


def test_draco_metadata_validates_utf8() raises:
    var good = bytes_of("é水🙂")
    var raw: List[UInt8] = [UInt8(len(good))]
    raw.extend(good^)
    var reader = DracoBuffer(raw^)
    assert_equal(_metadata_name(reader), "é水🙂")
    for bytes in invalid_sequences():
        var record: List[UInt8] = [UInt8(len(bytes))]
        record.extend(Span(bytes))
        var buffer = DracoBuffer(record^)
        with assert_raises(contains=utf8_error(bytes)):
            _ = _metadata_name(buffer)
        with assert_raises(contains=utf8_error(bytes)):
            _ = decode_draco(bytes.copy())


def test_vtk_detection_validates_utf8() raises:
    for bytes in invalid_sequences():
        var raw = bytes.copy()
        raw.extend(bytes_of("\nTitle\nBINARY\n"))
        raw.extend(List[UInt8](length=250, fill=0))
        with assert_raises(contains=utf8_error(bytes)):
            _ = parse_vtk(raw)
        raw = bytes_of("# vtk DataFile Version 3.0\nTitle\n")
        raw.extend(Span(bytes))
        raw.extend(bytes_of("\n"))
        raw.extend(List[UInt8](length=250, fill=0))
        with assert_raises(contains=utf8_error(bytes)):
            _ = parse_vtk(raw)


def test_ultrahdr_xmp_validates_utf8() raises:
    for bytes in invalid_sequences():
        var payload = bytes_of(XMP_NAMESPACE)
        payload.append(0)
        payload.extend(Span(bytes))
        var size = len(payload) + 2
        var raw: List[UInt8] = [
            0xFF,
            0xD8,
            0xFF,
            0xE1,
            UInt8(size >> 8),
            UInt8(size & 255),
        ]
        raw.extend(payload^)
        raw.extend([UInt8(0xFF), UInt8(0xD9)])
        with assert_raises(contains=utf8_error(bytes)):
            _ = parse_ultrahdr(raw)


def test_usdz_text_rejects_binary_or_invalid_utf8() raises:
    var files = UsdzFiles()
    files.add("valid.usda", bytes_of("é水🙂"))
    assert_equal(files.text("valid.usda"), "é水🙂")
    var cases = invalid_sequences()
    for i in range(len(cases)):
        var bytes = cases[i].copy()
        var name = String(i) + ".usda"
        files.add(name, bytes.copy())
        with assert_raises(contains=utf8_error(bytes)):
            _ = files.text(name)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
