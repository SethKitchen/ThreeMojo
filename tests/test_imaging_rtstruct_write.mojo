# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Label maps written as RT Structure Sets, and read back voxel for voxel."""

from extensions.imaging.dicom import parse_dicom_tree
from extensions.imaging.ids import (
    BACKGROUND,
    DATA_SET,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    LabelId,
    RLE_LOSSLESS,
    TransferSyntax,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.rtstruct import (
    RtStructure,
    parse_rt_structures,
    structure_labels,
)
from extensions.imaging.rtstruct_write import (
    RT_STRUCTURE_SET_STORAGE,
    encode_rt_structures,
    label_structure,
)
from extensions.sdf.vector import V3, v3
from std.math import cos, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, MILLIMETER64, Length64


def _volume() raises -> ImageVolume:
    """A grid of 20 by 18 by 6 voxels of 0.8 by 1.1 by 2.5 mm, turned 20
    degrees about (1, 1, 1)."""
    var volume = ImageVolume(
        20,
        18,
        6,
        Length64(0.8, MILLIMETER64),
        Length64(1.1, MILLIMETER64),
        Length64(2.5, MILLIMETER64),
    )
    var c = cos(0.349065850398866)
    var s = sin(0.349065850398866)
    var t = 1.0 - c
    var u = 1.0 / sqrt(3.0)
    # Rodrigues' rotation about the unit axis (u, u, u).
    volume.axis_x = v3(t * u * u + c, t * u * u + s * u, t * u * u - s * u)
    volume.axis_y = v3(t * u * u - s * u, t * u * u + c, t * u * u + s * u)
    volume.axis_z = v3(t * u * u + s * u, t * u * u - s * u, t * u * u + c)
    volume.origin = v3(-0.007, 0.003, -0.012)
    return volume^


def _map(volume: ImageVolume) raises -> LabelMap:
    """Four labels: a ball, a ring with a hole, pixels that touch at
    corners, and pixels on the edges of the grid."""
    var map = LabelMap(volume)
    for k in range(6):
        for j in range(18):
            for i in range(20):
                var dx = Float64(i) - 7.0
                var dy = Float64(j) - 8.0
                var dz = (Float64(k) - 2.5) * 2.5
                if dx * dx * 0.64 + dy * dy * 1.21 + dz * dz <= 25.0:
                    map.labels[map.index(i, j, k)] = 1
                var ring = max(abs(i - 15), abs(j - 12))
                if k >= 1 and k <= 3 and ring >= 1 and ring <= 2:
                    map.labels[map.index(i, j, k)] = 2
    # A checkerboard of pixels that touch at corners, and one alone.
    for j in range(1, 4):
        for i in range(14, 18):
            if (i + j) % 2 == 0:
                map.labels[map.index(i, j, 2)] = 3
    map.labels[map.index(10, 16, 4)] = 3
    # The edges and corners of the grid.
    for i in range(20):
        map.labels[map.index(i, 0, 5)] = 4
    for j in range(18):
        map.labels[map.index(19, j, 0)] = 4
    map.labels[map.index(0, 17, 0)] = 4
    return map^


def _regions(map: LabelMap, volume: ImageVolume) raises -> List[RtStructure]:
    var names: List[String] = ["Ball", "Ring", "Board", "Edges"]
    var out = List[RtStructure]()
    for n in range(4):
        out.append(
            label_structure(map, volume, LabelId(n + 1), 10 * (n + 1), names[n])
        )
    return out^


def test_round_trip() raises:
    var volume = _volume()
    var map = _map(volume)
    var regions = _regions(map, volume)
    var syntaxes: List[TransferSyntax] = [IMPLICIT_LITTLE, EXPLICIT_LITTLE]
    for syntax in syntaxes:
        var bytes = encode_rt_structures(
            regions, "1.2.826.0.1.3680043.10.1078", "1.2.3.4", "Labels", syntax
        )
        var read = parse_rt_structures(bytes)
        assert_equal(len(read), 4)
        for n in range(4):
            assert_equal(read[n].number, 10 * (n + 1))
            assert_equal(read[n].name, regions[n].name)
            assert_equal(len(read[n].contours), len(regions[n].contours))
            var back = structure_labels(read[n], volume, LabelId(1))
            var count = 0
            for at in range(map.count()):
                var want = map.labels[at] == UInt8(n + 1)
                assert_equal(back.labels[at] == 1, want)
                if want:
                    count += 1
            assert_true(count > 0)
            assert_equal(back.voxels(LabelId(1)), count)
    # The ring has an outline and a hole on each of its three slices.
    assert_equal(len(regions[1].contours), 6)


def test_points() raises:
    var volume = ImageVolume(
        6,
        5,
        1,
        Length64(1.0, MILLIMETER64),
        Length64(2.0, MILLIMETER64),
        Length64(3.0, MILLIMETER64),
    )
    volume.origin = v3(0.010, 0.020, 0.030)
    var map = LabelMap(volume)
    map.labels[map.index(1, 1, 0)] = 1
    for i in range(2, 5):
        map.labels[map.index(i, 3, 0)] = 2
    # One pixel: a diamond through the middles of its sides.
    var one = label_structure(map, volume, LabelId(1), 1, "One")
    assert_equal(len(one.contours), 1)
    ref diamond = one.contours[0]
    assert_equal(len(diamond), 4)
    var low_x = 1.0
    var high_y = 0.0
    for p in diamond:
        low_x = min(low_x, p.x)
        high_y = max(high_y, p.y)
        assert_almost_equal(p.z, 0.030)
    assert_almost_equal(low_x, 0.0105)
    assert_almost_equal(high_y, 0.023)
    # A bar of three pixels keeps six corners: its two middle points are
    # on straight runs.
    var bar = label_structure(map, volume, LabelId(2), 2, "Bar")
    assert_equal(len(bar.contours[0]), 6)


def test_file_elements() raises:
    var volume = _volume()
    var map = _map(volume)
    var regions = List[RtStructure]()
    regions.append(label_structure(map, volume, LabelId(1), 7, "Ball"))
    regions.append(RtStructure(9, ""))
    var bytes = encode_rt_structures(regions, "1.2.34", "1.2.3", "Set")
    var tree = parse_dicom_tree(bytes)
    assert_equal(tree.text(DATA_SET, 0x00080016), RT_STRUCTURE_SET_STORAGE)
    assert_equal(tree.text(DATA_SET, 0x00080018), "1.2.34.3")
    assert_equal(tree.text(DATA_SET, 0x0020000D), "1.2.34.1")
    assert_equal(tree.text(DATA_SET, 0x0020000E), "1.2.34.2")
    assert_equal(tree.text(DATA_SET, 0x00080060), "RTSTRUCT")
    assert_equal(tree.text(DATA_SET, 0x30060002), "Set")
    assert_true(tree.has(DATA_SET, 0x00100010))
    var frames = tree.items(DATA_SET, 0x30060010)
    assert_equal(tree.text(frames[0], 0x00200052), "1.2.3")
    var rois = tree.items(DATA_SET, 0x30060020)
    assert_equal(len(rois), 2)
    assert_equal(tree.text(rois[0], 0x30060024), "1.2.3")
    assert_equal(tree.text(rois[1], 0x30060022), "9")
    var contours = tree.items(DATA_SET, 0x30060039)
    var first = tree.items(contours[0], 0x30060040)
    assert_equal(len(first), len(regions[0].contours))
    for c in range(len(first)):
        var points = tree.numbers(first[c], 0x30060046)
        assert_equal(Int(points[0]), len(regions[0].contours[c]))
    assert_equal(len(tree.items(contours[1], 0x30060040)), 0)
    assert_equal(tree.text(contours[1], 0x30060084), "9")
    var seen = tree.items(DATA_SET, 0x30060080)
    assert_equal(tree.text(seen[1], 0x30060082), "2")
    assert_equal(tree.text(seen[1], 0x30060084), "9")
    # The meta group names the same instance as the data set.
    var text = String(unsafe_from_utf8=bytes)
    assert_equal(text.count("1.2.34.3"), 2)


def _refuses(
    regions: List[RtStructure],
    root: String,
    frame: String,
    label: String,
    message: String,
    syntax: TransferSyntax = IMPLICIT_LITTLE,
) raises:
    with assert_raises(contains=message):
        _ = encode_rt_structures(regions, root, frame, label, syntax)


def test_refusals() raises:
    var square: List[V3] = [
        v3(0, 0, 0),
        v3(0.01, 0, 0),
        v3(0.01, 0.01, 0),
        v3(0, 0.01, 0),
    ]
    var regions = List[RtStructure]()
    regions.append(RtStructure(1, "Body"))
    regions[0].contours.append(square.copy())
    _refuses(List[RtStructure](), "1.2", "1.2", "Set", "one region or more")
    # UIDs: at most 62 characters in a root, and 64 in a frame.
    var long_root = String("1.") + String("2") * 60
    _ = encode_rt_structures(regions, long_root, "1.0", "Set")
    _refuses(regions, long_root + "3", "1.2", "Set", "1 to 62 characters")
    _refuses(regions, "", "1.2", "Set", "1 to 62 characters")
    _refuses(regions, "1.2", "1." + String("2") * 63, "Set", "1 to 64")
    var bad: List[String] = ["1..2", "1.02", ".1", "1."]
    for uid in bad:
        _refuses(regions, uid, "1.2", "Set", "empty part or a leading zero")
    var odd: List[String] = ["1.a", "1.-"]
    for uid in odd:
        _refuses(regions, "1.2", uid, "Set", "digits and dots only")
    # The label, the names and the syntax.
    _refuses(regions, "1.2", "1.2", "", "1 to 16 characters")
    _refuses(regions, "1.2", "1.2", String("x") * 17, "1 to 16 characters")
    _refuses(regions, "1.2", "1.2", "A\\B", "no backslash")
    _refuses(regions, "1.2", "1.2", "Set", "implicit or explicit", RLE_LOSSLESS)
    var named = regions.copy()
    named[0].name = String("n") * 65
    _refuses(named, "1.2", "1.2", "Set", "at most 64 characters")
    named[0].name = "Left\\Right"
    _refuses(named, "1.2", "1.2", "Set", "no backslash")
    var twice = regions.copy()
    twice.append(RtStructure(1, "Again"))
    _refuses(twice, "1.2", "1.2", "Set", "share one ROI number")
    # Contours.
    var short = regions.copy()
    short[0].contours.append([v3(0, 0, 0), v3(0.01, 0, 0)])
    _refuses(short, "1.2", "1.2", "Set", "three points or more")
    var far = regions.copy()
    far[0].contours[0][1] = v3(1.0e6, 0, 0)
    _refuses(far, "1.2", "1.2", "Set", "")
    var long = RtStructure(1, "Long")
    var many = List[V3]()
    for n in range(4000):
        var a = Float64(n) * 0.00157
        many.append(v3(0.05 * cos(a), 0.05 * sin(a), 0.0))
    long.contours.append(many^)
    var longs = List[RtStructure]()
    longs.append(long^)
    _refuses(longs, "1.2", "1.2", "Set", "too long", EXPLICIT_LITTLE)
    var read = parse_rt_structures(
        encode_rt_structures(longs, "1.2", "1.2", "Set")
    )
    assert_equal(len(read[0].contours[0]), 4000)
    # A label on another grid, or the background.
    var volume = _volume()
    var map = _map(volume)
    var other = ImageVolume(
        2,
        2,
        2,
        Length64(1.0, MILLIMETER64),
        Length64(1.0, MILLIMETER64),
        Length64(1.0, MILLIMETER64),
    )
    with assert_raises(contains="different grids"):
        _ = label_structure(map, other, LabelId(1), 1, "A")
    with assert_raises(contains="background"):
        _ = label_structure(map, volume, BACKGROUND, 1, "A")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
