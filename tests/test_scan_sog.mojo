# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.sog`, the SOG splat reader.

`assets/sog/make_sog.mjs` wrote every SOG file in `assets/sog/` with
PlayCanvas splat-transform 3.10.1, and read each one back with the same
tool into a `_restored.ply` file. The reader must make, from each SOG
scene, the splats that `loaders.gaussian_splat_ply` makes from its PLY
file: the same centers, covariances, color bytes and harmonics bytes.
Every way a text can be wrong is made from a real text and refused.
"""

from extensions.scan.scene import SPLAT_ANTIALIASED, SPLAT_DEFAULT
from extensions.scan.sog import (
    SogFile,
    _quaternion,
    parse_sog,
    parse_sog_bundle,
    read_sog,
    sog_file_names,
)
from loaders.gaussian_splat_ply import read_gaussian_splat_ply
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from std.pathlib import Path
from tests._splat_same import same_bytes, same_floats, same_splats
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime DIR = "assets/sog/"


def _folder(name: String) raises -> List[SogFile]:
    """Return the images of a folder scene."""
    var meta = Path(DIR + name + "/meta.json").read_text()
    var files = List[SogFile]()
    for file in sog_file_names(meta):
        files.append(SogFile(file, Path(DIR + name + "/" + file).read_bytes()))
    return files^


def _meta(name: String) raises -> String:
    """Return a folder scene's text."""
    return Path(DIR + name + "/meta.json").read_text()


def _bundle(name: String) raises -> Tuple[String, List[SogFile]]:
    """Return a bundle's text and images."""
    from loaders.zip import unzip

    var meta = String()
    var files = List[SogFile]()
    for entry in unzip(Path(DIR + name + ".sog").read_bytes()):
        if entry.name == "meta.json":
            meta = String(from_utf8=Span(entry.data))
        else:
            files.append(SogFile(entry.name, entry.data.copy()))
    return (meta, files^)


def _swap(
    var files: List[SogFile], name: String, var data: List[UInt8]
) -> List[SogFile]:
    """Return the files with one image's bytes replaced."""
    for index in range(len(files)):
        if files[index].name == name:
            files[index].data = data^
            break
    return files^


def _without(files: List[SogFile], name: String) -> List[SogFile]:
    """Return the files without one image."""
    var kept = List[SogFile]()
    for file in files:
        if file.name != name:
            kept.append(file.copy())
    return kept^


def test_every_bundle_makes_the_splats_of_its_restored_ply() raises:
    """Each bundle, read here, holds what splat-transform read from it."""
    for name in ["sh3", "sh2", "sh1", "flat"]:
        var scene = read_sog(DIR + name + ".sog")
        same_splats(
            scene.geometry,
            read_gaussian_splat_ply(DIR + name + "_restored.ply"),
        )
        assert_true(scene.model == SPLAT_DEFAULT)


def test_every_folder_makes_the_splats_of_its_restored_ply() raises:
    """A folder scene is read from the files beside its text."""
    for name in ["sh3", "flat"]:
        var scene = read_sog(DIR + name + "/meta.json")
        same_splats(
            scene.geometry,
            read_gaussian_splat_ply(DIR + name + "_folder_restored.ply"),
        )


def test_the_bands_follow_the_harmonics_degree() raises:
    """Degree 3, 2, 1 and 0 scenes keep that many bands."""
    assert_equal(
        read_sog(DIR + "sh3.sog").geometry.spherical_harmonics_degree(), 3
    )
    assert_equal(
        read_sog(DIR + "sh2.sog").geometry.spherical_harmonics_degree(), 2
    )
    assert_equal(
        read_sog(DIR + "sh1.sog").geometry.spherical_harmonics_degree(), 1
    )
    assert_equal(
        read_sog(DIR + "flat.sog").geometry.spherical_harmonics_degree(), 0
    )
    assert_equal(read_sog(DIR + "sh3.sog").geometry.count(), 300)


def test_a_text_names_its_images() raises:
    """The names come in means, scales, quats, sh0 and shN order."""
    var flat = sog_file_names(_meta("flat"))
    assert_equal(len(flat), 5)
    assert_equal(flat[0], "means_l.webp")
    assert_equal(flat[1], "means_u.webp")
    assert_equal(flat[2], "scales.webp")
    assert_equal(flat[3], "quats.webp")
    assert_equal(flat[4], "sh0.webp")
    var full = sog_file_names(_meta("sh3"))
    assert_equal(len(full), 7)
    assert_equal(full[5], "shN_centroids.webp")
    assert_equal(full[6], "shN_labels.webp")


def test_a_text_can_name_its_model() raises:
    """A `model` entry is kept with the splats."""
    var meta = _meta("flat").replace(
        '"count":', '"model":"antialiased","count":'
    )
    var scene = parse_sog(meta, _folder("flat"))
    assert_true(scene.model == SPLAT_ANTIALIASED)
    same_splats(
        scene.geometry,
        read_gaussian_splat_ply(DIR + "flat_folder_restored.ply"),
    )
    with assert_raises(contains="unknown splat model"):
        _ = parse_sog(
            _meta("flat").replace('"count":', '"model":"mip","count":'),
            _folder("flat"),
        )


def test_only_version_two_is_read() raises:
    """A text with no version is version 1, and version 3 is unknown."""
    var meta = _meta("flat")
    with assert_raises(contains="version 1 files"):
        _ = parse_sog(meta.replace('"version":2,', ""), _folder("flat"))
    with assert_raises(contains="version 3 is not read"):
        _ = parse_sog(
            meta.replace('"version":2', '"version":3'), _folder("flat")
        )


def test_a_scene_has_splats() raises:
    """A count below one, or one with no texels, is refused."""
    var meta = _meta("flat")
    with assert_raises(contains="at least one splat"):
        _ = parse_sog(meta.replace('"count":9', '"count":0'), _folder("flat"))
    with assert_raises(contains="no count"):
        _ = parse_sog(meta.replace('"count":9', '"counted":9'), _folder("flat"))
    with assert_raises(contains="fewer texels than splats"):
        _ = parse_sog(meta.replace('"count":9', '"count":17'), _folder("flat"))


def test_every_section_is_needed() raises:
    """Each of means, scales, quats and sh0 must be there."""
    var meta = _meta("flat")
    for key in ["means", "scales", "quats", "sh0"]:
        with assert_raises(contains="meta.json has no " + key):
            _ = parse_sog(
                meta.replace('"' + key + '":', '"x' + key + '":'),
                _folder("flat"),
            )
        with assert_raises(contains="meta.json has no " + key):
            _ = sog_file_names(
                meta.replace('"' + key + '":', '"x' + key + '":')
            )


def test_the_files_must_be_file_names() raises:
    """A missing list, a wrong count and a folder are refused."""
    var meta = _meta("flat")
    var files = _folder("flat")
    with assert_raises(contains="quats has no files"):
        _ = parse_sog(meta.replace('"quats":{"files"', '"quats":{"x"'), files)
    with assert_raises(contains="quats names 1 files, not 2"):
        _ = parse_sog(
            meta.replace('"quats.webp"', '"quats.webp","quats.webp"'), files
        )
    for name in ["a/quats.webp", "a\\\\quats.webp"]:
        with assert_raises(contains="names a folder"):
            _ = parse_sog(meta.replace('"quats.webp"', '"' + name + '"'), files)
    for name in ["", ".", ".."]:
        with assert_raises(contains="is not a file name"):
            _ = parse_sog(meta.replace('"quats.webp"', '"' + name + '"'), files)
    with assert_raises(contains="names a folder"):
        _ = sog_file_names(meta.replace('"quats.webp"', '"../quats.webp"'))
    with assert_raises(contains="the scene has no file quats.webp"):
        _ = parse_sog(meta, _without(files, "quats.webp"))
    with assert_raises(contains="the scene has no file means_l.webp"):
        _ = parse_sog(meta, List[SogFile]())


def test_the_codebooks_hold_256_finite_numbers() raises:
    """A missing, short or overflowing codebook is refused."""
    var meta = _meta("flat")
    var files = _folder("flat")
    with assert_raises(contains="scales has no codebook"):
        _ = parse_sog(
            meta.replace('"scales":{"codebook"', '"scales":{"x"'), files
        )
    with assert_raises(contains="the sh0 codebook is not 256 entries"):
        _ = parse_sog(
            meta.replace('"sh0":{"codebook":[', '"sh0":{"codebook":[0,'), files
        )
    with assert_raises(contains="the scales codebook must be finite"):
        var key = '"scales":{"codebook":['
        var cut = meta.find(key) + key.byte_length()
        var end = meta.find(",", cut)
        _ = parse_sog(
            String(meta[byte=0:cut]) + "1e300" + String(meta[byte=end:]), files
        )


def test_the_means_hold_three_numbers_each() raises:
    """Each of mins and maxs must be three numbers."""
    var meta = _meta("flat")
    var files = _folder("flat")
    with assert_raises(contains="means has no mins"):
        _ = parse_sog(meta.replace('"mins":', '"xmins":'), files)
    with assert_raises(contains="means maxs is not three numbers"):
        _ = parse_sog(meta.replace('"maxs":[', '"maxs":[0,'), files)


def test_the_harmonics_section_is_checked() raises:
    """The bands, the count and the centroids' width are refused when wrong."""
    var meta = _meta("sh3")
    var files = _folder("sh3")
    with assert_raises(contains="shN has no bands"):
        _ = parse_sog(meta.replace('"bands":3', '"band":3'), files)
    with assert_raises(contains="shN has 4 bands, not 0 to 3"):
        _ = parse_sog(meta.replace('"bands":3', '"bands":4'), files)
    with assert_raises(contains="shN has -1 bands, not 0 to 3"):
        _ = parse_sog(meta.replace('"bands":3', '"bands":-1'), files)
    with assert_raises(contains="shN has no count"):
        _ = parse_sog(meta.replace('"shN":{"count"', '"shN":{"x"'), files)
    with assert_raises(contains="shN centroids are 960 texels wide, not 512"):
        _ = parse_sog(meta.replace('"bands":3', '"bands":2'), files)


def test_no_bands_keeps_no_harmonics() raises:
    """A section with no bands is a scene of degree 0."""
    var scene = parse_sog(
        _meta("sh3").replace('"bands":3', '"bands":0'), _folder("sh3")
    )
    assert_equal(scene.geometry.spherical_harmonics_degree(), 0)
    var plain = read_sog(DIR + "sh3/meta.json")
    same_floats(scene.geometry.centers, plain.geometry.centers, "centers")
    same_bytes(scene.geometry.colors, plain.geometry.colors, "colors")


def test_a_label_past_the_palette_gives_zero_coefficients() raises:
    """With a palette of none, every coefficient is zero: byte 128."""
    var scene = parse_sog(
        _meta("sh3").replace('"shN":{"count":256', '"shN":{"count":0'),
        _folder("sh3"),
    )
    for byte in scene.geometry.sh3:
        assert_equal(Int(byte), 128)


def test_a_row_past_the_centroids_is_codebook_entry_zero() raises:
    """Labels past the last row of centroids read entry zero, as in
    splat-transform. The one-row centroids of the degree 1 bundle are read
    with the 256 labels of the degree 3 folder."""
    var sh1 = _bundle("sh1")
    var centroids = List[UInt8]()
    for file in sh1[1]:
        if file.name == "shN_centroids.webp":
            centroids = file.data.copy()
    var meta = _meta("sh3").replace('"bands":3', '"bands":1')
    var files = _swap(_folder("sh3"), "shN_centroids.webp", centroids^)
    var scene = parse_sog(meta, files)
    assert_equal(scene.geometry.spherical_harmonics_degree(), 1)
    # Every label in a row past the first gives three coefficients of
    # codebook entry zero, so each splat with one has nine equal bytes.
    from extensions.scan.sog import _harmonics
    from loaders.json import parse_json

    var document = parse_json(meta)
    var rest = _harmonics(document, files, 300)
    assert_equal(rest.degree, 1)
    ref values = rest.values
    var zero = Float32(0)
    var first = True
    var seen = 0
    for index in range(300):
        var all_same = True
        for k in range(9):
            if values[index * 9 + k] != values[index * 9]:
                all_same = False
        if all_same:
            if first:
                zero = values[index * 9]
                first = False
            if values[index * 9] == zero:
                seen += 1
    assert_true(seen > 0)


def test_an_unknown_quaternion_tag_is_no_rotation() raises:
    """A fourth byte below 252 gives the identity, as in splat-transform."""
    var pixels: List[UInt8] = [10, 20, 30, 251]
    var w: Float32
    var x: Float32
    var y: Float32
    var z: Float32
    w, x, y, z = _quaternion(pixels, 0)
    assert_equal(w, 1)
    assert_equal(x, 0)
    assert_equal(y, 0)
    assert_equal(z, 0)
    # Tag 254 names y; the three stored components are near zero.
    var tagged: List[UInt8] = [128, 128, 128, 254]
    w, x, y, z = _quaternion(tagged, 0)
    assert_true(y > 0.99)
    assert_true(abs(w) < 0.01)
    assert_true(abs(x) < 0.01)
    assert_true(abs(z) < 0.01)


def test_a_bundle_needs_its_text() raises:
    """A ZIP file with no meta.json, or text that is not UTF-8, is refused."""
    with assert_raises(contains="the bundle has no meta.json"):
        _ = parse_sog_bundle(zip_archive(List[ZipEntry]()))
    var entries = List[ZipEntry]()
    entries.append(ZipEntry("meta.json", ZIP_STORED, [0xFF, 0xFE]))
    with assert_raises():
        _ = parse_sog_bundle(zip_archive(entries))
    with assert_raises():
        _ = parse_sog_bundle([1, 2, 3])


def test_a_folder_scene_needs_its_files() raises:
    """A text whose images are not beside it cannot be read."""
    with assert_raises():
        _ = read_sog(DIR + "no-such-folder/meta.json")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
