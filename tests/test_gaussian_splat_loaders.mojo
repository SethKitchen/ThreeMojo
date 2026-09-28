# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the Gaussian splat loaders: `loaders.splat`, `loaders.ksplat`,
`loaders.spz`, `loaders.gaussian_splat_ply` and
`loaders.gltf_gaussian_splat`.

Every file in `assets/gaussian_splat/` was read by three.js r186's own
loaders into `expected.json` by `make_splats.mjs` there. Each is read here
and compared with it: the centers and the covariances to a float's
precision, and the color and harmonics bytes exactly. Every way a file can
be wrong is built byte by byte and refused.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry, write_covariance
from loaders.gaussian_splat_ply import (
    detect_spherical_harmonics_degree,
    parse_gaussian_splat_ply,
    read_gaussian_splat_ply,
)
from loaders.gltf_gaussian_splat import (
    GltfGaussianSplatMesh,
    load_gltf_gaussian_splats,
    read_gltf_gaussian_splats,
)
from loaders.json import JsonDocument, parse_json
from loaders.ksplat import (
    KSPLAT_BYTE_HARMONICS,
    KSPLAT_HALF,
    KSPLAT_UNCOMPRESSED,
    KsplatCompressionLevel,
    ksplat_band_index,
    ksplat_components,
    ksplat_layout,
    parse_ksplat,
    read_ksplat,
)
from loaders.splat import le_f32, le_u16, le_u32, parse_splat, read_splat
from loaders.spz import (
    parse_raw_spz,
    parse_raw_spz_v4,
    parse_spz,
    read_spz,
    smallest_three,
    spz_color,
    spz_quaternion_component,
    spz_scale,
    spz_vectors,
)
from std.math import exp, isnan, nan, sqrt
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime DIR = "assets/gaussian_splat/"
comptime ALPHABET = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
)


# --- expected values ----------------------------------------------------------


def expected() raises -> JsonDocument:
    """Return what three.js read from every file."""
    return parse_json(Path(DIR + "expected.json").read_text())


def numbers(document: JsonDocument, node: Int) raises -> List[Float64]:
    """Return a JSON array of numbers."""
    var out = List[Float64]()
    for at in range(document.length(node)):
        out.append(document.number(document.at(node, at)))
    return out^


def assert_geometry(
    got: GaussianSplatGeometry, document: JsonDocument, node: Int
) raises:
    """Assert a geometry is what three.js made, as `expected.json` has it."""
    var count = document.integer(document.get(node, "count"))
    assert_equal(got.count(), count)
    var centers = numbers(document, document.get(node, "centers"))
    assert_equal(len(got.centers), len(centers))
    for at in range(len(centers)):
        assert_almost_equal(
            Float64(got.centers[at]), centers[at], atol=1e-6, rtol=1e-6
        )
    var covariances = numbers(document, document.get(node, "covariances"))
    assert_equal(len(got.covariances), len(covariances))
    for at in range(len(covariances)):
        assert_almost_equal(
            Float64(got.covariances[at]), covariances[at], atol=1e-9, rtol=1e-5
        )
    var colors = numbers(document, document.get(node, "colors"))
    assert_equal(len(got.colors), len(colors))
    for at in range(len(colors)):
        assert_equal(Int(got.colors[at]), Int(colors[at]))
    var degree = 0
    for band in range(1, 4):
        var key = "sh" + String(band)
        if not document.has(node, key):
            continue
        degree = band
        var bytes = numbers(document, document.get(node, key))
        var mine = got.sh1.copy()
        if band == 2:
            mine = got.sh2.copy()
        if band == 3:
            mine = got.sh3.copy()
        assert_equal(len(mine), len(bytes))
        for at in range(len(bytes)):
            assert_equal(Int(mine[at]), Int(bytes[at]), "band " + key)
    assert_equal(got.spherical_harmonics_degree(), degree)


def check_file(name: String, got: GaussianSplatGeometry) raises:
    """Assert a file's geometry is three.js's."""
    var document = expected()
    assert_geometry(got, document, document.get(document.root(), name))


# --- bytes ----------------------------------------------------------------------


def put_u16(mut bytes: List[UInt8], at: Int, value: Int):
    """Write a little-endian 16-bit integer."""
    bytes[at] = UInt8(value & 255)
    bytes[at + 1] = UInt8((value >> 8) & 255)


def put_u32(mut bytes: List[UInt8], at: Int, value: Int):
    """Write a little-endian 32-bit integer."""
    put_u16(bytes, at, value & 0xFFFF)
    put_u16(bytes, at + 2, (value >> 16) & 0xFFFF)


def put_f32(mut bytes: List[UInt8], at: Int, value: Float32):
    """Write a little-endian float."""
    put_u32(bytes, at, Int(bitcast[DType.uint32](value)))


def append_f32(mut bytes: List[UInt8], value: Float32):
    """Append a little-endian float."""
    var at = len(bytes)
    for _ in range(4):
        bytes.append(0)
    put_f32(bytes, at, value)


def zeros(count: Int) -> List[UInt8]:
    """Return that many zero bytes."""
    return List[UInt8](length=count, fill=0)


def read(name: String) raises -> List[UInt8]:
    """Return a file's bytes."""
    return Path(DIR + name).read_bytes()


# --- .splat -----------------------------------------------------------------------


def test_the_readers_read_little_endian() raises:
    var bytes: List[UInt8] = [1, 2, 3, 4, 0, 0, 128, 63]
    assert_equal(le_u16(bytes, 0), 0x0201)
    assert_equal(le_u32(bytes, 0), 0x04030201)
    assert_equal(le_f32(bytes, 4), 1.0)


def test_a_splat_file_reads_as_three_js_reads_it() raises:
    check_file("three.splat", read_splat(DIR + "three.splat"))
    # `four.splat` is the object of `expected.json`, not one of its files.
    assert_equal(parse_splat(read("four.splat")).count(), 4)


def test_a_splat_file_of_part_of_a_row_is_refused() raises:
    with assert_raises(contains="invalid .splat byte length"):
        _ = parse_splat(zeros(33))


def test_no_rows_are_no_splats() raises:
    assert_equal(parse_splat(List[UInt8]()).count(), 0)


# --- .ksplat ----------------------------------------------------------------------


def test_the_compression_levels() raises:
    assert_true(KSPLAT_HALF.is_valid())
    assert_false(KsplatCompressionLevel(3).is_valid())
    assert_false(KsplatCompressionLevel(-1).is_valid())
    assert_equal(ksplat_layout(KSPLAT_UNCOMPRESSED).bytes_per_center, 12)
    assert_equal(ksplat_layout(KSPLAT_HALF).bytes_per_harmonic, 2)
    assert_equal(ksplat_layout(KSPLAT_BYTE_HARMONICS).bytes_per_harmonic, 1)
    with assert_raises(contains="unsupported compression level 7"):
        _ = ksplat_layout(KsplatCompressionLevel(7))


def test_the_band_order_is_three_js_table() raises:
    var one: List[Int] = [0, 3, 6, 1, 4, 7, 2, 5, 8]
    for at in range(9):
        assert_equal(ksplat_band_index(1, at), one[at])
    var two: List[Int] = [9, 14, 19, 10, 15, 20, 11, 16, 21]
    for at in range(9):
        assert_equal(ksplat_band_index(2, at), two[at])
    var three: List[Int] = [24, 31, 38, 25, 32, 39, 26, 33, 40, 27]
    for at in range(10):
        assert_equal(ksplat_band_index(3, at), three[at])
    assert_equal(ksplat_components(0), 0)
    assert_equal(ksplat_components(3), 45)
    with assert_raises(contains="unsupported spherical harmonics degree 4"):
        _ = ksplat_components(4)


def test_ksplat_files_read_as_three_js_reads_them() raises:
    check_file("level0.ksplat", read_ksplat(DIR + "level0.ksplat"))
    check_file("level1.ksplat", parse_ksplat(read("level1.ksplat")))
    check_file("level2.ksplat", parse_ksplat(read("level2.ksplat")))
    check_file(
        "level2_default_range.ksplat",
        parse_ksplat(read("level2_default_range.ksplat")),
    )


def test_a_harmonics_range_that_is_not_a_number_is_the_default() raises:
    var bytes = read("level2.ksplat")
    put_f32(bytes, 36, nan[DType.float32]())
    put_f32(bytes, 40, nan[DType.float32]())
    check_file("level2_default_range.ksplat", parse_ksplat(bytes))


def ksplat(level: Int, sections: Int, splats: Int) -> List[UInt8]:
    """Return a header and empty section headers."""
    var bytes = zeros(4096 + sections * 1024)
    bytes[1] = 1
    put_u32(bytes, 4, sections)
    put_u32(bytes, 16, splats)
    put_u16(bytes, 20, level)
    return bytes^


def section(
    mut bytes: List[UInt8],
    index: Int,
    splats: Int,
    rows: Int,
    degree: Int = 0,
):
    """Fill one section header's counts."""
    var at = 4096 + index * 1024
    put_u32(bytes, at, splats)
    put_u32(bytes, at + 4, rows)
    put_u16(bytes, at + 40, degree)


def test_a_ksplat_header_that_is_wrong_is_refused() raises:
    with assert_raises(contains="invalid KSPLAT header"):
        _ = parse_ksplat(zeros(4095))
    var major = ksplat(0, 0, 0)
    major[0] = 1
    with assert_raises(contains="unsupported KSPLAT version 1.1"):
        _ = parse_ksplat(major)
    var minor = ksplat(0, 0, 0)
    minor[1] = 0
    with assert_raises(contains="unsupported KSPLAT version 0.0"):
        _ = parse_ksplat(minor)
    with assert_raises(contains="unsupported compression level 3"):
        _ = parse_ksplat(ksplat(3, 0, 0))
    with assert_raises(contains="too many splats (10000001)"):
        _ = parse_ksplat(ksplat(0, 0, 10000001))
    var short = ksplat(0, 1, 0)
    put_u32(short, 4, 2)
    with assert_raises(contains="invalid KSPLAT section headers"):
        _ = parse_ksplat(short)


def test_an_empty_ksplat_file_has_no_splats() raises:
    assert_equal(parse_ksplat(ksplat(0, 0, 0)).count(), 0)


def test_a_ksplat_section_that_is_wrong_is_refused() raises:
    var degree = ksplat(0, 1, 0)
    section(degree, 0, 0, 0, 4)
    with assert_raises(contains="unsupported spherical harmonics degree 4"):
        _ = parse_ksplat(degree)
    var long = ksplat(0, 1, 1)
    section(long, 0, 1, 1)
    with assert_raises(contains="invalid KSPLAT byte length"):
        _ = parse_ksplat(long)
    var crowded = ksplat(0, 1, 2)
    section(crowded, 0, 2, 1)
    crowded.extend(zeros(44))
    with assert_raises(contains="more splats than rows"):
        _ = parse_ksplat(crowded)
    var over = ksplat(0, 1, 1)
    section(over, 0, 2, 2)
    over.extend(zeros(88))
    with assert_raises(contains="splat count mismatch"):
        _ = parse_ksplat(over)
    var under = ksplat(0, 1, 2)
    section(under, 0, 1, 1)
    under.extend(zeros(44))
    with assert_raises(contains="splat count mismatch"):
        _ = parse_ksplat(under)


def test_a_splat_past_every_bucket_is_refused() raises:
    # Two partly filled buckets of no splats each.
    var empty = ksplat(1, 1, 1)
    section(empty, 0, 1, 1)
    put_u32(empty, 4096 + 8, 1)
    put_u32(empty, 4096 + 12, 2)
    put_u16(empty, 4096 + 20, 12)
    put_u32(empty, 4096 + 36, 2)
    empty.extend(zeros(8 + 24 + 24))
    with assert_raises(contains="invalid KSPLAT bucket data"):
        _ = parse_ksplat(empty)
    # A splat past the full buckets, with no partly filled bucket.
    var full = ksplat(1, 1, 2)
    section(full, 0, 2, 2)
    put_u32(full, 4096 + 8, 1)
    put_u32(full, 4096 + 12, 1)
    put_u16(full, 4096 + 20, 12)
    put_u32(full, 4096 + 32, 1)
    full.extend(zeros(12 + 48))
    with assert_raises(contains="invalid KSPLAT bucket data"):
        _ = parse_ksplat(full)
    # A thousand buckets whose lengths would run past the file.
    var runaway = ksplat(1, 1, 1)
    section(runaway, 0, 1, 1)
    put_u32(runaway, 4096 + 8, 1)
    put_u32(runaway, 4096 + 12, 1000)
    runaway.extend(zeros(24))
    with assert_raises(contains="invalid KSPLAT bucket data"):
        _ = parse_ksplat(runaway)


# --- .spz --------------------------------------------------------------------------


def test_the_spz_tables() raises:
    assert_equal(spz_vectors(0), 0)
    assert_equal(spz_vectors(4), 24)
    with assert_raises(contains="unsupported SPZ spherical harmonics degree 5"):
        _ = spz_vectors(5)
    assert_equal(Int(spz_color(128)), 128)
    assert_equal(Int(spz_color(0)), 0)
    assert_equal(spz_scale(160), Float64(Float32(exp(Float64(0)))))
    assert_almost_equal(spz_quaternion_component(511), sqrt(0.5))
    assert_almost_equal(spz_quaternion_component(512 | 511), -sqrt(0.5))
    var q = smallest_three(3 << 30)
    assert_equal(q[3], 1.0)
    assert_equal(q[0], 0.0)


def test_spz_files_read_as_three_js_reads_them() raises:
    check_file("v1.spz", read_spz(DIR + "v1.spz"))
    check_file("v2.spz", parse_spz(read("v2.spz")))
    check_file("v3.spz", parse_spz(read("v3.spz")))
    check_file("v4.spz", parse_spz(read("v4.spz")))


def raw_spz(version: Int, count: Int, degree: Int, flags: Int) -> List[UInt8]:
    """Return a raw version 1 to 3 header and zero fields of the right
    length."""
    var positions = count * 3 * (2 if version == 1 else 3)
    var rotations = count * (4 if version == 3 else 3)
    var harmonics = count * ((degree + 1) * (degree + 1) - 1) * 3
    var lod = count * 6 if (flags & 0x80) != 0 else 0
    var bytes = zeros(16 + positions + count * 7 + rotations + harmonics + lod)
    put_u32(bytes, 0, 0x5053474E)
    put_u32(bytes, 4, version)
    put_u32(bytes, 8, count)
    bytes[12] = UInt8(degree)
    bytes[14] = UInt8(flags)
    return bytes^


def test_raw_spz_that_is_wrong_is_refused() raises:
    with assert_raises(contains="invalid SPZ header"):
        _ = parse_raw_spz(zeros(15))
    var magic = raw_spz(2, 1, 0, 0)
    magic[0] = 0
    with assert_raises(contains="invalid SPZ magic"):
        _ = parse_raw_spz(magic)
    with assert_raises(contains="SPZ version 0 is not supported"):
        _ = parse_raw_spz(raw_spz(0, 1, 0, 0))
    with assert_raises(contains="SPZ version 4 is not supported"):
        _ = parse_raw_spz(raw_spz(4, 1, 0, 0))
    var degree = raw_spz(2, 0, 0, 0)
    degree[12] = 5
    with assert_raises(contains="degree 5"):
        _ = parse_raw_spz(degree)
    var long = raw_spz(2, 1, 0, 0)
    long.append(0)
    with assert_raises(contains="invalid SPZ byte length"):
        _ = parse_raw_spz(long)
    assert_equal(parse_raw_spz(raw_spz(2, 2, 0, 0x80)).count(), 2)
    # No splats, in half floats, and with a band.
    assert_equal(parse_raw_spz(raw_spz(1, 0, 0, 0)).count(), 0)
    assert_equal(parse_raw_spz(raw_spz(2, 0, 1, 0)).count(), 0)


def test_an_spz_file_is_gzip_or_version_4() raises:
    with assert_raises(contains="SPZ version 2 is not supported"):
        _ = parse_spz(raw_spz(2, 1, 0, 0))
    with assert_raises(contains="invalid gzip data"):
        _ = parse_spz(zeros(5))
    with assert_raises(contains="invalid gzip data"):
        _ = parse_spz(zeros(12))


def zstd_raw(bytes: List[UInt8]) -> List[UInt8]:
    """Return a Zstandard frame of one raw block."""
    var out: List[UInt8] = [0x28, 0xB5, 0x2F, 0xFD, 0xA0, 0, 0, 0, 0]
    put_u32(out, 5, len(bytes))
    var header = 1 | (len(bytes) << 3)
    out.append(UInt8(header & 255))
    out.append(UInt8((header >> 8) & 255))
    out.append(UInt8((header >> 16) & 255))
    out.extend(bytes.copy())
    return out^


def spz4(
    count: Int, degree: Int, var streams: List[List[UInt8]]
) -> List[UInt8]:
    """Return a version 4 file of these streams, each a raw zstd frame."""
    var bytes = zeros(20 + len(streams) * 16)
    put_u32(bytes, 0, 0x5053474E)
    put_u32(bytes, 4, 4)
    put_u32(bytes, 8, count)
    bytes[12] = UInt8(degree)
    bytes[13] = 8
    bytes[15] = UInt8(len(streams))
    put_u32(bytes, 16, 20)
    for at in range(len(streams)):
        var frame = zstd_raw(streams[at])
        put_u32(bytes, 20 + at * 16, len(frame))
        bytes.extend(frame^)
    return bytes^


def one_splat_streams() -> List[List[UInt8]]:
    """Return a version 4 file's five streams for one splat of degree 0."""
    var position: List[UInt8] = [0, 1, 0, 0, 2, 0, 0, 255, 255]
    var alpha: List[UInt8] = [200]
    var color: List[UInt8] = [10, 20, 30]
    var scale: List[UInt8] = [150, 160, 170]
    var rotation: List[UInt8] = [0, 0, 0, 0xC0]
    return [position^, alpha^, color^, scale^, rotation^]


def test_a_version_4_field_of_no_bytes_has_no_stream() raises:
    var got = parse_spz(spz4(1, 0, one_splat_streams()))
    assert_equal(got.count(), 1)
    assert_equal(got.spherical_harmonics_degree(), 0)
    assert_equal(got.centers[0], 1.0)
    assert_equal(got.centers[1], 2.0)
    assert_equal(got.centers[2], Float32(-256) / 256)
    assert_equal(Int(got.colors[3]), 200)
    # The largest component is w, and the rest are zero.
    assert_almost_equal(
        Float64(got.covariances[0]), exp(Float64(150) / 16 - 10) ** 2, rtol=1e-5
    )


def test_version_4_that_is_wrong_is_refused() raises:
    var short = spz4(1, 0, one_splat_streams())
    with assert_raises(contains="invalid SPZ header"):
        _ = parse_raw_spz_v4(List[UInt8](short[:19]))
    var crowded = spz4(1, 0, one_splat_streams())
    put_u32(crowded, 8, 10000001)
    with assert_raises(contains="too many splats"):
        _ = parse_raw_spz_v4(crowded)
    var table = spz4(1, 0, one_splat_streams())
    put_u32(table, 16, len(table))
    with assert_raises(contains="table of contents is past the end"):
        _ = parse_raw_spz_v4(table)
    var streams = one_splat_streams()
    _ = streams.pop()
    with assert_raises(contains="too few SPZ streams"):
        _ = parse_raw_spz_v4(spz4(1, 0, streams^))
    var past = spz4(1, 0, one_splat_streams())
    put_u32(past, 20 + 4 * 16, 1000)
    with assert_raises(contains="stream is past the end"):
        _ = parse_raw_spz_v4(past)
    var thin = one_splat_streams()
    _ = thin[0].pop()
    with assert_raises(contains="does not hold its field"):
        _ = parse_raw_spz_v4(spz4(1, 0, thin^))


# --- Gaussian splat PLY -------------------------------------------------------------


def test_splat_ply_files_read_as_three_js_reads_them() raises:
    check_file("splat.ply", read_gaussian_splat_ply(DIR + "splat.ply"))
    check_file("ascii.ply", parse_gaussian_splat_ply(read("ascii.ply")))


def ply(header: String, body: String = "") -> List[UInt8]:
    """Return an ASCII PLY file's bytes."""
    var text = "ply\nformat ascii 1.0\n" + header + "end_header\n" + body
    return List[UInt8](text.as_bytes())


comptime REQUIRED = (
    "property float x\nproperty float y\nproperty float z\n"
    "property float scale_0\nproperty float scale_1\nproperty float"
    " scale_2\nproperty float rot_0\nproperty float rot_1\nproperty float"
    " rot_2\nproperty float rot_3\nproperty float f_dc_0\nproperty float"
    " f_dc_1\nproperty float f_dc_2\nproperty float opacity\n"
)


def test_the_header_decides_the_degree() raises:
    assert_equal(detect_spherical_harmonics_degree(read("splat.ply")), 1)
    var rest = String("")
    for at in range(24):
        rest += "property float f_rest_" + String(at) + "\n"
    var header = "element vertex 0\n" + REQUIRED + rest
    assert_equal(detect_spherical_harmonics_degree(ply(header)), 2)
    # Names that only look like `f_rest_N` are not counted.
    var odd = (
        "element vertex 0\n"
        + REQUIRED
        + "property float f_rest_\nproperty float f_rest_1a\r\n"
        + "property float f_rest_1+\n"
    )
    assert_equal(detect_spherical_harmonics_degree(ply(odd)), 0)


def test_a_splat_ply_that_is_wrong_is_refused() raises:
    with assert_raises(contains="missing PLY header"):
        _ = parse_gaussian_splat_ply(List[UInt8]("end_header".as_bytes()))
    with assert_raises(contains="missing PLY header"):
        _ = parse_gaussian_splat_ply(List[UInt8]("ply\nformat".as_bytes()))
    with assert_raises(contains="requires position, scale"):
        _ = parse_gaussian_splat_ply(List[UInt8]("plyend_header".as_bytes()))
    with assert_raises(contains="requires position, scale"):
        _ = parse_gaussian_splat_ply(
            ply("element vertex 0\nproperty float x\n")
        )
    var five = String("element vertex 0\n") + REQUIRED
    for at in range(5):
        five += "property float f_rest_" + String(at) + "\n"
    with assert_raises(contains="f_rest spherical harmonics coefficients (5)"):
        _ = parse_gaussian_splat_ply(ply(five))
    with assert_raises(contains="requires position, scale"):
        _ = parse_gaussian_splat_ply(ply("element vertex 0\n" + REQUIRED))


# --- glTF KHR_gaussian_splatting ------------------------------------------------------


def check_gltf(meshes: List[GltfGaussianSplatMesh]) raises:
    """Assert the splat meshes of `splats.gltf` are what three.js read."""
    var document = expected()
    var found = document.get(document.root(), "splats.gltf")
    assert_equal(len(meshes), 3)
    assert_equal(meshes[0].mesh, 0)
    assert_equal(meshes[1].mesh, 2)
    assert_equal(meshes[2].mesh, 3)
    assert_false(meshes[0].is_group())
    assert_true(meshes[1].is_group())
    assert_equal(meshes[0].extras.string("tag"), "a")
    assert_equal(meshes[0].extras.number("count"), 3)
    assert_equal(meshes[1].extras.count(), 0)
    var at = 0
    for mesh in range(len(meshes)):
        for primitive in range(len(meshes[mesh].primitives)):
            ref splat = meshes[mesh].primitives[primitive]
            var want = document.at(found, at)
            assert_equal(
                splat.name, document.string(document.get(want, "name"))
            )
            assert_equal(splat.primitive, primitive)
            assert_equal(splat.kernel, "ellipse")
            assert_equal(splat.color_space, "srgb_rec709_display")
            assert_equal(splat.projection, "perspective")
            assert_equal(splat.sorting_method, "cameraDistance")
            assert_geometry(
                splat.geometry, document, document.get(want, "geometry")
            )
            at += 1
    assert_equal(at, document.length(found))


def test_gltf_splats_read_as_three_js_reads_them() raises:
    check_gltf(read_gltf_gaussian_splats(DIR + "splats.gltf"))


def test_a_buffer_beside_the_file_and_a_glb_read_the_same() raises:
    check_gltf(read_gltf_gaussian_splats(DIR + "external.gltf"))
    check_gltf(read_gltf_gaussian_splats(DIR + "splats.glb"))


def encode_base64(bytes: List[UInt8]) -> String:
    """Return the standard, padded base64 text of some bytes."""
    var table = String(ALPHABET).as_bytes()
    var out = List[UInt8]()
    var at = 0
    while at < len(bytes):
        var left = len(bytes) - at
        var n = Int(bytes[at]) << 16
        if left > 1:
            n |= Int(bytes[at + 1]) << 8
        if left > 2:
            n |= Int(bytes[at + 2])
        out.append(table[(n >> 18) & 63])
        out.append(table[(n >> 12) & 63])
        out.append(table[(n >> 6) & 63] if left > 1 else UInt8(61))
        out.append(table[n & 63] if left > 2 else UInt8(61))
        at += 3
    return String(unsafe_from_utf8=out)


struct Gltf(Movable):
    """A glTF document built a run of numbers at a time, each run its own
    view and accessor."""

    var bytes: List[UInt8]
    var views: List[String]
    var accessors: List[String]

    def __init__(out self):
        """Start empty."""
        self.bytes = List[UInt8]()
        self.views = List[String]()
        self.accessors = List[String]()

    def view(mut self, var data: List[UInt8], stride: Int = 0) -> Int:
        """Add a buffer view of these bytes and return its index."""
        while len(self.bytes) % 4 != 0:
            self.bytes.append(0)
        var start = len(self.bytes)
        var length = len(data)
        self.bytes.extend(data^)
        var text = (
            '{"buffer":0,"byteOffset":'
            + String(start)
            + ',"byteLength":'
            + String(length)
        )
        if stride > 0:
            text += ',"byteStride":' + String(stride)
        self.views.append(text + "}")
        return len(self.views) - 1

    def accessor(mut self, text: String) -> Int:
        """Add an accessor's JSON and return its index."""
        self.accessors.append(text)
        return len(self.accessors) - 1

    def floats(
        mut self, values: List[Float32], kind: String, count: Int
    ) -> Int:
        """Add an accessor of floats."""
        var data = List[UInt8]()
        for value in values:
            append_f32(data, value)
        var view = self.view(data^)
        return self.accessor(
            '{"bufferView":'
            + String(view)
            + ',"componentType":5126,"count":'
            + String(count)
            + ',"type":"'
            + kind
            + '"}'
        )

    def integers(
        mut self,
        values: List[Int],
        component: Int,
        width: Int,
        kind: String,
        count: Int,
        normalized: Bool,
    ) -> Int:
        """Add an accessor of integers `width` bytes each."""
        var data = List[UInt8]()
        for value in values:
            for byte in range(width):
                data.append(UInt8((value >> (byte * 8)) & 255))
        var view = self.view(data^)
        var text = (
            '{"bufferView":'
            + String(view)
            + ',"componentType":'
            + String(component)
            + ',"count":'
            + String(count)
            + ',"type":"'
            + kind
            + '"'
        )
        if normalized:
            text += ',"normalized":true'
        return self.accessor(text + "}")

    def document(self, meshes: String) -> String:
        """Return the document with these meshes."""
        var views = String("")
        for at in range(len(self.views)):
            views += ("," if at > 0 else "") + self.views[at]
        var accessors = String("")
        for at in range(len(self.accessors)):
            accessors += ("," if at > 0 else "") + self.accessors[at]
        return (
            '{"asset":{"version":"2.0"},"buffers":[{"byteLength":'
            + String(len(self.bytes))
            + ',"uri":"data:application/octet-stream;base64,'
            + encode_base64(self.bytes)
            + '"}],"bufferViews":['
            + views
            + '],"accessors":['
            + accessors
            + '],"meshes":'
            + meshes
            + "}"
        )


def filled(count: Int, value: Float32) -> List[Float32]:
    """Return a list of one value."""
    return List[Float32](length=count, fill=value)


def splat_attributes(mut gltf: Gltf, n: Int, sizes: List[Int]) -> String:
    """Return a splat primitive's attributes, each of its given count:
    position, scale, rotation, opacity and the zeroth band."""
    var names: List[String] = [
        "POSITION",
        "KHR_gaussian_splatting:SCALE",
        "KHR_gaussian_splatting:ROTATION",
        "KHR_gaussian_splatting:OPACITY",
        "KHR_gaussian_splatting:SH_DEGREE_0_COEF_0",
    ]
    var kinds: List[String] = ["VEC3", "VEC3", "VEC4", "SCALAR", "VEC3"]
    var widths: List[Int] = [3, 3, 4, 1, 3]
    var text = String("")
    for at in range(5):
        var count = sizes[at] if at < len(sizes) else n
        var index = gltf.floats(
            filled(count * widths[at], 0.5), kinds[at], count
        )
        text += ("," if at > 0 else "") + '"' + names[at] + '":' + String(index)
    return text


def band(mut gltf: Gltf, degree: Int, coefficient: Int, n: Int) -> String:
    """Return one harmonics attribute's JSON entry, three floats a splat."""
    var index = gltf.floats(filled(n * 3, 0.25), "VEC3", n)
    return (
        ',"KHR_gaussian_splatting:SH_DEGREE_'
        + String(degree)
        + "_COEF_"
        + String(coefficient)
        + '":'
        + String(index)
    )


comptime EXTENSION = (
    '"extensions":{"KHR_gaussian_splatting":{"kernel":"ellipse",'
    '"colorSpace":"srgb"}}'
)


def primitive(attributes: String, extra: String = ',"mode":0') -> String:
    """Return a splat primitive's JSON."""
    return '{"attributes":{' + attributes + "}" + extra + "," + EXTENSION + "}"


def load(text: String) raises -> List[GltfGaussianSplatMesh]:
    """Read the splat meshes of a document."""
    return load_gltf_gaussian_splats(text, List[UInt8](), "")


def test_a_document_with_no_meshes_has_no_splats() raises:
    assert_equal(len(load('{"asset":{"version":"2.0"}}')), 0)
    assert_equal(len(load('{"buffers":[],"meshes":[]}')), 0)
    assert_equal(len(load('{"meshes":[{"primitives":[]}]}')), 0)
    assert_equal(len(read_gltf_gaussian_splats(DIR + "empty.gltf")), 0)


def test_each_component_type_reads_as_three_js_reads_it() raises:
    var gltf = Gltf()
    var position = gltf.integers([1, 2, 3], 5125, 4, "VEC3", 1, False)
    var scale = gltf.integers([2, 0xFFFE, 3], 5122, 2, "VEC3", 1, False)
    var rotation = gltf.integers([127, 0x81, 0, 0x80], 5120, 1, "VEC4", 1, True)
    var opacity = gltf.integers([0x8000], 5123, 2, "SCALAR", 1, True)
    var color = gltf.integers([255, 0, 128], 5121, 1, "VEC3", 1, False)
    var attributes = (
        '"POSITION":'
        + String(position)
        + ',"KHR_gaussian_splatting:SCALE":'
        + String(scale)
        + ',"KHR_gaussian_splatting:ROTATION":'
        + String(rotation)
        + ',"KHR_gaussian_splatting:OPACITY":'
        + String(opacity)
        + ',"KHR_gaussian_splatting:SH_DEGREE_0_COEF_0":'
        + String(color)
    )
    var meshes = load(
        gltf.document("[{" + '"primitives":[' + primitive(attributes) + "]}]")
    )
    ref got = meshes[0].primitives[0].geometry
    assert_equal(got.centers[0], 1.0)
    assert_equal(got.centers[2], 3.0)
    assert_equal(meshes[0].primitives[0].name, "mesh_0")
    # The opacity is 32768 / 65535.
    assert_equal(Int(got.colors[3]), 128)
    # A byte of -127 normalized is -1, as is -128.
    var want = List[Float32](length=6, fill=0)
    write_covariance(want, 0, 2, -2, 3, 1, -1, 0, -1)
    for at in range(6):
        assert_almost_equal(got.covariances[at], want[at], rtol=1e-6)


def test_an_accessor_with_no_view_is_zeros() raises:
    var gltf = Gltf()
    var attributes = splat_attributes(gltf, 2, List[Int]())
    var none = gltf.accessor('{"componentType":5126,"count":2,"type":"VEC3"}')
    attributes += band(gltf, 1, 0, 2) + band(gltf, 1, 1, 2)
    attributes += ',"KHR_gaussian_splatting:SH_DEGREE_1_COEF_2":' + String(none)
    var meshes = load(
        gltf.document('[{"primitives":[' + primitive(attributes) + "]}]")
    )
    ref got = meshes[0].primitives[0].geometry
    assert_equal(got.spherical_harmonics_degree(), 1)
    # 0.25 is byte 160, and zero is 128.
    assert_equal(Int(got.sh1[0]), 160)
    assert_equal(Int(got.sh1[6]), 128)


def test_a_short_element_reads_on_into_the_next() raises:
    # A rotation of three numbers: w is the next splat's x, and past the
    # last splat it is not a number, as a typed array reads it.
    var gltf = Gltf()
    var attributes = splat_attributes(gltf, 1, List[Int]())
    var turn = gltf.floats(filled(3, 0.5), "VEC3", 1)
    attributes += ',"KHR_gaussian_splatting:ROTATION":' + String(turn)
    var meshes = load(
        gltf.document('[{"primitives":[' + primitive(attributes) + "]}]")
    )
    assert_true(isnan(meshes[0].primitives[0].geometry.covariances[0]))


def test_extras_that_are_not_an_object_are_skipped() raises:
    var gltf = Gltf()
    var attributes = splat_attributes(gltf, 1, List[Int]())
    var meshes = load(
        gltf.document(
            '[{"extras":7,"primitives":[' + primitive(attributes) + "]}]"
        )
    )
    assert_equal(meshes[0].extras.count(), 0)


def refused(text: String, reason: String) raises:
    """Assert a document is refused for a reason."""
    with assert_raises(contains=reason):
        _ = load(text)


def test_a_splat_mesh_that_is_wrong_is_refused() raises:
    var gltf = Gltf()
    var good = splat_attributes(gltf, 1, List[Int]())
    refused(
        gltf.document(
            '[{"primitives":['
            + primitive(good)
            + ',{"attributes":{"POSITION":0}}]}]'
        ),
        "mixed gaussian",
    )
    refused(
        gltf.document('[{"primitives":[' + primitive(good, "") + "]}]"),
        "must use POINTS mode",
    )
    var no_kernel = (
        '[{"primitives":[{"attributes":{'
        + good
        + '},"mode":0,"extensions":{"KHR_gaussian_splatting":{}}}]}]'
    )
    refused(
        gltf.document(no_kernel), "unsupported KHR_gaussian_splatting kernel"
    )
    var no_space = (
        '[{"primitives":[{"attributes":{'
        + good
        + '},"mode":0,"extensions":{"KHR_gaussian_splatting":{"kernel":'
        + '"ellipse"}}}]}]'
    )
    refused(gltf.document(no_space), "colorSpace is required")
    refused(
        gltf.document('[{"primitives":[' + primitive('"POSITION":0') + "]}]"),
        "requires KHR_gaussian_splatting:SCALE",
    )
    for field in range(1, 5):
        var sizes = List[Int](length=5, fill=1)
        sizes[field] = 2
        var attributes = splat_attributes(gltf, 1, sizes)
        refused(
            gltf.document('[{"primitives":[' + primitive(attributes) + "]}]"),
            "counts must match POSITION",
        )


def test_harmonics_that_are_wrong_are_refused() raises:
    var gltf = Gltf()
    var good = splat_attributes(gltf, 1, List[Int]())
    var two = band(gltf, 1, 0, 2)
    refused(
        gltf.document('[{"primitives":[' + primitive(good + two) + "]}]"),
        "invalid KHR_gaussian_splatting:SH_DEGREE_1_COEF_0 attribute",
    )
    var wide = gltf.floats(filled(4, 0.5), "VEC4", 1)
    refused(
        gltf.document(
            '[{"primitives":['
            + primitive(
                good
                + ',"KHR_gaussian_splatting:SH_DEGREE_1_COEF_0":'
                + String(wide)
            )
            + "]}]"
        ),
        "invalid KHR_gaussian_splatting:SH_DEGREE_1_COEF_0 attribute",
    )
    refused(
        gltf.document(
            '[{"primitives":[' + primitive(good + band(gltf, 1, 0, 1)) + "]}]"
        ),
        "incomplete KHR_gaussian_splatting SH degree 1",
    )
    refused(
        gltf.document(
            '[{"primitives":[' + primitive(good + band(gltf, 2, 0, 1)) + "]}]"
        ),
        "must be contiguous",
    )


def test_accessors_that_are_wrong_are_refused() raises:
    var gltf = Gltf()
    var good = splat_attributes(gltf, 1, List[Int]())
    var sparse = gltf.accessor(
        '{"componentType":5126,"count":1,"type":"VEC3","sparse":{}}'
    )
    var odd = gltf.accessor('{"componentType":5124,"count":1,"type":"VEC3"}')
    var matrix = gltf.accessor('{"componentType":5126,"count":1,"type":"MAT4"}')
    var long = gltf.accessor(
        '{"bufferView":0,"componentType":5126,"count":2,"type":"VEC3"}'
    )
    var view = gltf.view(zeros(4))
    var bad_view = gltf.view(zeros(4))
    var cases: List[Int] = [sparse, odd, matrix, long]
    var reasons: List[String] = [
        "sparse splat accessor",
        "unknown component type 5124",
        "cannot be MAT4",
        "reaches past its data",
    ]
    for at in range(len(cases)):
        refused(
            gltf.document(
                '[{"primitives":['
                + primitive(
                    good
                    + ',"KHR_gaussian_splatting:SH_DEGREE_1_COEF_0":'
                    + String(cases[at])
                )
                + "]}]"
            ),
            reasons[at],
        )
    # A view that reaches past the buffer.
    gltf.views[bad_view] = (
        '{"buffer":0,"byteOffset":0,"byteLength":'
        + String(len(gltf.bytes) + 4)
        + "}"
    )
    var past = gltf.accessor(
        '{"bufferView":'
        + String(bad_view)
        + ',"componentType":5126,"count":1,"type":"SCALAR"}'
    )
    _ = view
    refused(
        gltf.document(
            '[{"primitives":['
            + primitive(
                good
                + ',"KHR_gaussian_splatting:SH_DEGREE_1_COEF_0":'
                + String(past)
            )
            + "]}]"
        ),
        "reaches past its data",
    )


def test_an_accessor_of_nothing_reads_nothing() raises:
    var gltf = Gltf()
    var attributes = splat_attributes(gltf, 0, List[Int]())
    for coefficient in range(3):
        attributes += band(gltf, 1, coefficient, 0)
    var meshes = load(
        gltf.document('[{"primitives":[' + primitive(attributes) + "]}]")
    )
    assert_equal(meshes[0].primitives[0].geometry.count(), 0)


def test_a_data_uri_must_be_base64() raises:
    var head = '{"asset":{"version":"2.0"},"buffers":[{"byteLength":1,"uri":"'
    refused(head + 'data:text/plain,abc"}]}', "not base64")
    refused(head + 'data:abc"}]}', "not base64")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
