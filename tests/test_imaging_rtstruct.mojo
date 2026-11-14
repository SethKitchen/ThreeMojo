# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""DICOM element trees, RT Structure Sets and their regions in a grid.

The fixtures `rtstruct.dcm` and `rtstruct_implicit.dcm` were written by
pydicom 3.0.1. See `assets/dicom/make_rtstruct.py` and
`assets/dicom/rtstruct_expected.txt`.
"""

from extensions.imaging.dicom import parse_dicom_tree, read_dicom_tree
from extensions.imaging.dicom_write import DicomWriter
from extensions.imaging.ids import (
    BACKGROUND,
    DATA_SET,
    DEFLATED_EXPLICIT,
    DicomNode,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    LabelId,
    RLE_LOSSLESS,
    TransferSyntax,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.rtstruct import (
    RtStructure,
    parse_rt_structures,
    read_rt_structures,
    structure_labels,
)
from extensions.sdf.vector import v3
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _expected() raises -> List[List[String]]:
    var out = List[List[String]]()
    var text = open("assets/dicom/rtstruct_expected.txt", "r").read()
    for line in text.splitlines():
        var words = List[String]()
        for part in line.split(" "):
            words.append(String(part))
        out.append(words^)
    return out^


def _grid() raises -> ImageVolume:
    """The grid of the fixtures: 24 by 20 by 4 voxels of 2 by 2.5 by 3 mm,
    the first voxel at (-23, -24, 0) mm."""
    var volume = ImageVolume(
        24,
        20,
        4,
        Length64(2.0, MILLIMETER64),
        Length64(2.5, MILLIMETER64),
        Length64(3.0, MILLIMETER64),
    )
    volume.origin = v3(-0.023, -0.024, 0.0)
    return volume^


def test_pydicom_fixtures() raises:
    var expected = _expected()
    for name in ["rtstruct.dcm", "rtstruct_implicit.dcm"]:
        var regions = read_rt_structures("assets/dicom/" + name)
        assert_equal(len(regions), 3)
        assert_equal(regions[0].number, 1)
        assert_equal(regions[0].name, "GTV")
        assert_equal(len(regions[0].contours), 2)
        assert_equal(len(regions[0].contours[0]), 9)
        assert_equal(regions[1].name, "Ring")
        assert_equal(len(regions[1].contours), 2)
        # The point of the marker is not a closed contour.
        assert_equal(len(regions[2].contours), 1)
        # The first point of the ring, in meters.
        assert_almost_equal(regions[1].contours[0][0].x, (5.37 - 11.0) / 1000)
        assert_almost_equal(regions[1].contours[0][0].z, 0.0)
        var grid = _grid()
        for r in range(3):
            var map = structure_labels(regions[r], grid, LabelId(r + 1))
            var bits = expected[r][3]
            var count = 0
            for index in range(map.count()):
                var inside = map.labels[index] == UInt8(r + 1)
                assert_equal(inside, bits.as_bytes()[index] == 49)
                if inside:
                    count += 1
            assert_equal(count, atol(expected[r][2]))


def _set(var writer: DicomWriter) raises -> List[UInt8]:
    return writer^.finish()


def _roi(mut writer: DicomWriter, number: String, name: String):
    writer.open_item()
    if number != "":
        writer.text(0x3006, 0x0022, "IS", number)
    writer.text(0x3006, 0x0026, "LO", name)
    writer.close_item()


def _contours(mut writer: DicomWriter, reference: String, data: String):
    writer.open_item()
    writer.text(0x3006, 0x0084, "IS", reference)
    writer.open_sequence(0x3006, 0x0040)
    writer.open_item()
    writer.text(0x3006, 0x0042, "CS", "CLOSED_PLANAR")
    writer.text(0x3006, 0x0050, "DS", data)
    writer.close_item()
    writer.close_sequence()
    writer.close_item()


def _structure_set(
    syntax: TransferSyntax, number: String, reference: String, data: String
) raises -> List[UInt8]:
    var writer = DicomWriter(syntax)
    writer.text(0x0008, 0x0060, "CS", "RTSTRUCT")
    writer.open_sequence(0x3006, 0x0020)
    _roi(writer, number, "Body")
    writer.close_sequence()
    writer.open_sequence(0x3006, 0x0039)
    _contours(writer, reference, data)
    writer.close_sequence()
    return writer^.finish()


def test_written_structure_sets() raises:
    var square = String("0\\0\\0\\10\\0\\0\\10\\10\\0\\0\\10\\0")
    for syntax in [EXPLICIT_LITTLE, IMPLICIT_LITTLE, DEFLATED_EXPLICIT]:
        var regions = parse_rt_structures(
            _structure_set(syntax, "4", "4", square)
        )
        assert_equal(regions[0].number, 4)
        assert_equal(len(regions[0].contours[0]), 4)
        assert_almost_equal(regions[0].contours[0][2].y, 0.01)
    with assert_raises(contains="one ROI number"):
        _ = parse_rt_structures(
            _structure_set(EXPLICIT_LITTLE, "", "4", square)
        )
    with assert_raises(contains="refers to no structure"):
        _ = parse_rt_structures(
            _structure_set(EXPLICIT_LITTLE, "4", "5", square)
        )
    with assert_raises(contains="three points"):
        _ = parse_rt_structures(
            _structure_set(EXPLICIT_LITTLE, "4", "4", "0\\0\\0\\1\\0\\0")
        )
    with assert_raises(contains="three points"):
        _ = parse_rt_structures(
            _structure_set(
                EXPLICIT_LITTLE, "4", "4", "0\\0\\0\\1\\0\\0\\1\\1\\0\\5"
            )
        )
    # A CT image is not a structure set.
    with assert_raises(contains="not an RT Structure Set"):
        _ = parse_rt_structures(Path("assets/dicom/rle16.dcm").read_bytes())
    # The square from 0 to 10 mm on the first slice holds the pixel
    # centers at x = 1, 3, 5, 7 and 9 mm and y = 1, 3.5, 6 and 8.5 mm.
    var regions = parse_rt_structures(
        _structure_set(EXPLICIT_LITTLE, "4", "4", square)
    )
    var map = structure_labels(regions[0], _grid(), LabelId(1))
    assert_equal(map.voxels(LabelId(1)), 20)
    assert_true(map.get(12, 10, 0) == LabelId(1))
    # A region past the last slice adds nothing.
    var high = parse_rt_structures(
        _structure_set(
            EXPLICIT_LITTLE,
            "4",
            "4",
            "0\\0\\30\\10\\0\\30\\10\\10\\30\\0\\10\\30",
        )
    )
    var empty = structure_labels(high[0], _grid(), LabelId(1))
    assert_equal(empty.voxels(LabelId(1)), 0)
    with assert_raises(contains="background"):
        _ = structure_labels(regions[0], _grid(), BACKGROUND)
    with assert_raises(contains="label"):
        _ = structure_labels(regions[0], _grid(), LabelId(256))


def test_trees() raises:
    for syntax in [EXPLICIT_LITTLE, IMPLICIT_LITTLE]:
        var writer = DicomWriter(syntax)
        writer.text(0x0010, 0x0010, "PN", "Phantom")
        writer.text(0x0018, 0x0050, "DS", "1.5\\2\\-3")
        writer.text(0x0018, 0x0088, "DS", "")
        writer.open_sequence(0x0008, 0x1140)
        for n in range(2):
            writer.open_item()
            writer.text(0x0008, 0x1150, "UI", String("1.2.", n))
            writer.open_sequence(0x0008, 0x1155)
            writer.open_item()
            writer.text(0x0008, 0x0100, "SH", "deep")
            writer.close_item()
            writer.close_sequence()
            writer.close_item()
        writer.close_sequence()
        # A sequence of defined length with one item of defined length.
        var item: List[UInt8] = [0xFE, 0xFF, 0x00, 0xE0, 10, 0, 0, 0]
        if syntax == EXPLICIT_LITTLE:
            item.extend(
                [UInt8(0x08), 0, 0x00, 0x01, 0x53, 0x48, 2, 0, 0x41, 0x42]
            )
        else:
            item[4] = 12
            item.extend(
                [UInt8(0x08), 0, 0x00, 0x01, 4, 0, 0, 0, 0x41, 0x42, 0x43, 0x44]
            )
        writer.binary(0x0008, 0x1200, "SQ", item)
        writer.text(0x0010, 0x0010, "PN", "Second")
        var tree = parse_dicom_tree(writer^.finish())
        assert_equal(tree.text(DATA_SET, 0x00100010), "Phantom")
        var values = tree.numbers(DATA_SET, 0x00180050)
        assert_equal(len(values), 3)
        assert_equal(values[2], -3.0)
        assert_equal(len(tree.numbers(DATA_SET, 0x00180088)), 0)
        assert_equal(len(tree.numbers(DATA_SET, 0x00181234)), 0)
        var items = tree.items(DATA_SET, 0x00081140)
        assert_equal(len(items), 2)
        assert_equal(tree.text(items[1], 0x00081150), "1.2.1")
        var inner = tree.items(items[1], 0x00081155)
        assert_equal(tree.text(inner[0], 0x00080100), "deep")
        assert_true(tree.has(DATA_SET, 0x00081140))
        assert_true(tree.has(DATA_SET, 0x00100010))
        assert_false(tree.has(DATA_SET, 0x00100020))
        assert_equal(len(tree.items(DATA_SET, 0x00100020)), 0)
        var defined = tree.items(DATA_SET, 0x00081200)
        assert_equal(len(defined), 1)
        assert_true(tree.text(defined[0], 0x00080100).startswith("AB"))
        assert_true(DATA_SET.is_valid())
        assert_true(items[1].is_valid())
        assert_false(DicomNode(-1).is_valid())
        with assert_raises(contains="no such node"):
            _ = tree.text(DicomNode(99), 0x00100010)
        with assert_raises(contains="no such node"):
            _ = tree.items(DicomNode(-1), 0x00100010)
        with assert_raises(contains="no such node"):
            _ = tree.has(DicomNode(99), 0x00100010)
    # Encapsulated pixel data is stepped over.
    var rle = DicomWriter(RLE_LOSSLESS)
    rle.text(0x0010, 0x0010, "PN", "Pixels")
    rle.encapsulated([UInt8(1), 2, 3, 4])
    rle.text(0x0010, 0x0020, "LO", "after")
    var pixels = parse_dicom_tree(rle^.finish())
    assert_equal(pixels.text(DATA_SET, 0x00100020), "after")
    _ = read_dicom_tree("assets/dicom/pet.dcm")


def _replace(
    bytes: List[UInt8], old: String, new: String
) raises -> List[UInt8]:
    var out = bytes.copy()
    var a = old.as_bytes()
    var b = new.as_bytes()
    for start in range(len(out) - len(a) + 1):
        var same = True
        for offset in range(len(a)):
            if out[start + offset] != a[offset]:
                same = False
                break
        if same:
            for offset in range(len(b)):
                out[start + offset] = b[offset]
            return out^
    raise Error("not found")


def test_tree_refusals() raises:
    with assert_raises(contains="preamble"):
        _ = parse_dicom_tree(List[UInt8](length=100, fill=0))
    with assert_raises(contains="DICM"):
        _ = parse_dicom_tree(List[UInt8](length=200, fill=0))
    var plain = DicomWriter(EXPLICIT_LITTLE)
    plain.text(0x0010, 0x0010, "PN", "X")
    with assert_raises(contains="not one of the four"):
        _ = parse_dicom_tree(
            _replace(
                plain^.finish(), "1.2.840.10008.1.2.1", "1.2.840.10008.1.2.4"
            )
        )
    var writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.text(0x0010, 0x0010, "PN", "X")
    with assert_raises(contains="not an item"):
        _ = parse_dicom_tree(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.close_item()
    with assert_raises(contains="unknown delimiter"):
        _ = parse_dicom_tree(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.open_item()
    writer.open_item()
    with assert_raises(contains="stray delimiter"):
        _ = parse_dicom_tree(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.open_sequence(0x0008, 0x1140)
    writer.open_item()
    with assert_raises(contains="no end"):
        _ = parse_dicom_tree(writer^.finish())
    writer = DicomWriter(EXPLICIT_LITTLE)
    for _ in range(66):
        writer.open_sequence(0x0008, 0x1140)
        writer.open_item()
    with assert_raises(contains="too deep"):
        _ = parse_dicom_tree(writer^.finish())


def test_edges_of_trees_and_sets() raises:
    # A file that ends after its meta group has an empty data set.
    var bare = parse_dicom_tree(DicomWriter(EXPLICIT_LITTLE).finish())
    assert_false(bare.has(DATA_SET, 0x00100010))
    # Of two sequences with one tag, the first counts.
    var writer = DicomWriter(EXPLICIT_LITTLE)
    for value in ["first", "second"]:
        writer.open_sequence(0x0008, 0x1140)
        writer.open_item()
        writer.text(0x0008, 0x0100, "SH", value)
        writer.close_item()
        writer.close_sequence()
    var twice = parse_dicom_tree(writer^.finish())
    var items = twice.items(DATA_SET, 0x00081140)
    assert_equal(len(items), 1)
    assert_true(twice.text(items[0], 0x00080100).startswith("first"))
    # An item of defined length that holds a delimiter is refused.
    writer = DicomWriter(EXPLICIT_LITTLE)
    var item: List[UInt8] = [0xFE, 0xFF, 0x00, 0xE0, 8, 0, 0, 0]
    item.extend([UInt8(0xFE), 0xFF, 0x0D, 0xE0, 0, 0, 0, 0])
    writer.binary(0x0008, 0x1200, "SQ", item)
    with assert_raises(contains="stray delimiter"):
        _ = parse_dicom_tree(writer^.finish())
    # A structure set without regions has none, and a contour item
    # without contours adds none.
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.text(0x0008, 0x0060, "CS", "RTSTRUCT")
    assert_equal(len(parse_rt_structures(writer^.finish())), 0)
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.text(0x0008, 0x0060, "CS", "RTSTRUCT")
    writer.open_sequence(0x3006, 0x0020)
    _roi(writer, "2", "Empty")
    writer.close_sequence()
    writer.open_sequence(0x3006, 0x0039)
    writer.open_item()
    writer.text(0x3006, 0x0084, "IS", "2")
    writer.close_item()
    writer.close_sequence()
    var empty = parse_rt_structures(writer^.finish())
    assert_equal(len(empty[0].contours), 0)
    # A contour without a reference refers to no structure.
    writer = DicomWriter(EXPLICIT_LITTLE)
    writer.text(0x0008, 0x0060, "CS", "RTSTRUCT")
    writer.open_sequence(0x3006, 0x0020)
    _roi(writer, "2", "Empty")
    writer.close_sequence()
    writer.open_sequence(0x3006, 0x0039)
    writer.open_item()
    writer.close_item()
    writer.close_sequence()
    with assert_raises(contains="refers to no structure"):
        _ = parse_rt_structures(writer^.finish())
    # Short contours, contours below the first slice and contours beside
    # the grid add nothing.
    var region = RtStructure(9, "Odd")
    var mm = 0.001
    region.contours.append([v3(0, 0, 0), v3(5 * mm, 0, 0)])
    region.contours.append(
        [
            v3(0, 0, -10 * mm),
            v3(5 * mm, 0, -10 * mm),
            v3(5 * mm, 5 * mm, -10 * mm),
        ]
    )
    region.contours.append(
        [v3(200 * mm, 0, 0), v3(210 * mm, 0, 0), v3(210 * mm, 10 * mm, 0)]
    )
    region.contours.append(
        [
            v3(0, 200 * mm, 3 * mm),
            v3(10 * mm, 200 * mm, 3 * mm),
            v3(10 * mm, 210 * mm, 3 * mm),
        ]
    )
    var none = structure_labels(region, _grid(), LabelId(1))
    assert_equal(none.voxels(LabelId(1)), 0)
    var nothing = structure_labels(RtStructure(1, "None"), _grid(), LabelId(1))
    assert_equal(nothing.voxels(LabelId(1)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
