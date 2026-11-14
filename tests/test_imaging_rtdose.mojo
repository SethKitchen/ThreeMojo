# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""RT Dose files, and the dose-volume histograms of regions.

The fixtures `rtdose.dcm` and `rtdose_implicit.dcm` were written by
pydicom 3.0.1. See `assets/dicom/make_rtdose.py` and
`assets/dicom/rtdose_expected.txt`, whose histograms numpy 2.1.3 gave.
"""

from extensions.imaging.dicom_write import DicomWriter
from extensions.imaging.dvh import (
    CUBIC_CENTIMETER64,
    DoseVolumeHistogram,
    dose_volume_histogram,
)
from extensions.imaging.ids import (
    BACKGROUND,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    LabelId,
    RLE_LOSSLESS,
    TransferSyntax,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.rtdose import (
    AbsorbedDose64,
    CENTIGRAY,
    GRAY,
    RtDose,
    parse_rt_dose,
    read_rt_dose,
)
from extensions.imaging.rtstruct import read_rt_structures, structure_labels
from extensions.sdf.vector import v3
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CUBIC_METER, Length64, METER, Volume64


def _lines() raises -> List[List[String]]:
    var out = List[List[String]]()
    var text = open("assets/dicom/rtdose_expected.txt", "r").read()
    for line in text.splitlines():
        var words = List[String]()
        for part in line.split(" "):
            words.append(String(part))
        out.append(words^)
    return out^


def _close(actual: Float64, expected: String) raises:
    assert_almost_equal(actual, atof(expected), atol=0.0, rtol=1e-12)


def test_pydicom_fixtures() raises:
    var lines = _lines()
    var names: List[String] = ["rtdose.dcm", "rtdose_implicit.dcm"]
    var at = 0
    for f in range(2):
        assert_equal(lines[at][1], names[f])
        var read = read_rt_dose("assets/dicom/" + names[f])
        ref dose = read.dose
        assert_equal(read.dose_type, "PHYSICAL")
        assert_equal(read.summation, "PLAN")
        assert_equal(dose.nx, 24)
        assert_equal(dose.ny, 20)
        assert_equal(dose.nz, 4)
        assert_almost_equal(dose.spacing_x.to(METER), 0.002)
        assert_almost_equal(dose.spacing_y.to(METER), 0.0025)
        assert_almost_equal(dose.spacing_z.to(METER), 0.003)
        # The implicit file runs down from z = 9 mm, and is turned over.
        assert_almost_equal(dose.origin.x, -0.023)
        assert_almost_equal(dose.origin.y, -0.024)
        assert_almost_equal(dose.origin.z, 0.0)
        assert_almost_equal(dose.axis_z.z, 1.0)
        ref values = lines[at + 1]
        assert_equal(len(values), 1 + dose.count())
        for v in range(dose.count()):
            assert_equal(dose.values[v], Float32(atof(values[1 + v])))
        at += 2
        # Each region of the structure fixtures, on the dose grid.
        var regions = read_rt_structures("assets/dicom/rtstruct.dcm")
        for r in range(2):
            ref want = lines[at]
            assert_equal(want[1], regions[r].name)
            var map = structure_labels(regions[r], dose, LabelId(1))
            var dvh = dose_volume_histogram(dose, map, LabelId(1))
            assert_equal(dvh.count(), atol(want[2]))
            _close(dvh.minimum().to(GRAY), want[3])
            _close(dvh.mean().to(GRAY), want[4])
            _close(dvh.maximum().to(GRAY), want[5])
            var fractions: List[Float64] = [0.98, 0.95, 0.5, 0.02]
            for p in range(4):
                _close(dvh.dose_at_fraction(fractions[p]).to(GRAY), want[6 + p])
            _close(
                dvh.volume_at_dose(AbsorbedDose64(20, GRAY)).to(
                    CUBIC_CENTIMETER64
                ),
                want[10],
            )
            _close(
                dvh.volume_at_dose(AbsorbedDose64(4000, CENTIGRAY)).to(
                    CUBIC_CENTIMETER64
                ),
                want[11],
            )
            _close(
                dvh.dose_at_volume(Volume64(0.03, CUBIC_CENTIMETER64)).to(GRAY),
                want[12],
            )
            _close(
                dvh.dose_at_volume(Volume64(0.1, CUBIC_CENTIMETER64)).to(GRAY),
                want[13],
            )
            _close(dvh.equivalent_uniform_dose(-10.0).to(GRAY), want[14])
            _close(dvh.equivalent_uniform_dose(5.0).to(GRAY), want[15])
            at += 1


struct _Spec(Copyable, Movable):
    """The elements of a small written RT Dose file."""

    var modality: String
    var units: String
    var rows: Int
    var columns: Int
    var bits: Int
    var stored: Int
    var signed: Int
    var frames: String
    var scaling: String
    var position: String
    var orientation: String
    var spacing: String
    var offsets: String
    var values: List[Int]
    var has_rows: Bool

    def __init__(out self):
        """Two frames of 2 by 3 values, 0 to 11, at 0.5 Gy a value."""
        self.modality = "RTDOSE"
        self.units = "GY"
        self.rows = 2
        self.columns = 3
        self.bits = 16
        self.stored = 16
        self.signed = 0
        self.frames = "2"
        self.scaling = "0.5"
        self.position = "-1\\-2\\10"
        self.orientation = "1\\0\\0\\0\\1\\0"
        self.spacing = "2\\1.5"
        self.offsets = "0\\4"
        self.values = List[Int]()
        for v in range(12):
            self.values.append(v)
        self.has_rows = True


def _file(
    spec: _Spec, syntax: TransferSyntax = EXPLICIT_LITTLE
) raises -> List[UInt8]:
    var w = DicomWriter(syntax)
    w.text(0x0008, 0x0060, "CS", spec.modality)
    if spec.position != "":
        w.text(0x0020, 0x0032, "DS", spec.position)
    w.text(0x0020, 0x0037, "DS", spec.orientation)
    if spec.frames != "":
        w.text(0x0028, 0x0008, "IS", spec.frames)
    if spec.has_rows:
        w.short(0x0028, 0x0010, spec.rows)
    w.short(0x0028, 0x0011, spec.columns)
    w.text(0x0028, 0x0030, "DS", spec.spacing)
    w.short(0x0028, 0x0100, spec.bits)
    w.short(0x0028, 0x0101, spec.stored)
    w.short(0x0028, 0x0103, spec.signed)
    w.text(0x3004, 0x0002, "CS", spec.units)
    w.text(0x3004, 0x0004, "CS", "PHYSICAL")
    w.text(0x3004, 0x000A, "CS", "BEAM")
    if spec.offsets != "":
        w.text(0x3004, 0x000C, "DS", spec.offsets)
    w.text(0x3004, 0x000E, "DS", spec.scaling)
    var data = List[UInt8]()
    var size = spec.bits // 8
    for v in spec.values:
        var stored = v
        if stored < 0:
            stored += 1 << (8 * size)
        for b in range(size):
            data.append(UInt8((stored >> (8 * b)) & 0xFF))
    if syntax == RLE_LOSSLESS:
        w.encapsulated(data)
    else:
        w.binary(0x7FE0, 0x0010, "OW", data)
    return w^.finish()


def _read(spec: _Spec) raises -> ImageVolume:
    return parse_rt_dose(_file(spec)).dose.copy()


def test_written_doses() raises:
    var plain = _Spec()
    var read = parse_rt_dose(_file(plain, IMPLICIT_LITTLE))
    assert_equal(read.summation, "BEAM")
    ref dose = read.dose
    assert_equal(dose.nx, 3)
    assert_equal(dose.ny, 2)
    assert_equal(dose.nz, 2)
    assert_almost_equal(dose.spacing_x.to(METER), 0.0015)
    assert_almost_equal(dose.spacing_y.to(METER), 0.002)
    assert_almost_equal(dose.spacing_z.to(METER), 0.004)
    assert_almost_equal(dose.origin.z, 0.010)
    assert_equal(dose.get(2, 1, 1), 5.5)
    assert_equal(dose.get(1, 0, 0), 0.5)
    # Offsets that go down turn the frames over.
    var down = _Spec()
    down.offsets = "0\\-4"
    var turned = _read(down)
    assert_almost_equal(turned.origin.z, 0.006)
    assert_almost_equal(turned.spacing_z.to(METER), 0.004)
    assert_equal(turned.get(0, 0, 0), 3.0)
    assert_equal(turned.get(0, 0, 1), 0.0)
    # Offsets that are the z of each frame, up and down.
    var up = _Spec()
    up.offsets = "10\\14"
    assert_equal(_read(up).get(0, 0, 1), 3.0)
    var absolute = _Spec()
    absolute.position = "-1\\-2\\14"
    absolute.offsets = "14\\10"
    var below = _read(absolute)
    assert_almost_equal(below.origin.z, 0.010)
    assert_equal(below.get(0, 0, 0), 3.0)
    # Offsets from 0 take frames of any orientation.
    var sagittal = _Spec()
    sagittal.orientation = "0\\1\\0\\0\\0\\-1"
    var side = _read(sagittal)
    assert_almost_equal(side.axis_z.x, -1.0)
    assert_almost_equal(side.origin.x, -0.001)
    # One frame, without a frame count or offsets, is as deep as a
    # column gap.
    var one = _Spec()
    one.frames = ""
    one.offsets = ""
    one.values = [7, 8, 9, 10, 11, 12]
    var flat = _read(one)
    assert_equal(flat.nz, 1)
    assert_almost_equal(flat.spacing_z.to(METER), 0.0015)
    assert_equal(flat.get(2, 1, 0), 6.0)
    # Signed and 32-bit values.
    var signed = _Spec()
    signed.signed = 1
    signed.values[0] = -1
    signed.values[1] = 32767
    var negative = _read(signed)
    assert_equal(negative.get(0, 0, 0), -0.5)
    assert_equal(negative.get(1, 0, 0), 16383.5)
    var high = _Spec()
    high.values[0] = 40000
    assert_equal(_read(high).get(0, 0, 0), 20000.0)
    var wide = _Spec()
    wide.bits = 32
    wide.stored = 32
    wide.scaling = "1E-6"
    wide.values[0] = 3000000000
    wide.values[1] = 70000
    var big = _read(wide)
    assert_almost_equal(Float64(big.get(0, 0, 0)), 3000.0, rtol=1e-7)
    assert_almost_equal(Float64(big.get(1, 0, 0)), 0.07, rtol=1e-7)
    var wide_signed = wide.copy()
    wide_signed.signed = 1
    wide_signed.values[0] = -2
    assert_almost_equal(
        Float64(_read(wide_signed).get(0, 0, 0)), -2e-6, rtol=1e-7
    )


def _refuses(spec: _Spec, message: String) raises:
    with assert_raises(contains=message):
        _ = parse_rt_dose(_file(spec))


def test_dose_refusals() raises:
    var s = _Spec()
    s.modality = "CT"
    _refuses(s, "not an RT Dose")
    s = _Spec()
    s.units = "RELATIVE"
    _refuses(s, "in GY")
    s = _Spec()
    s.has_rows = False
    _refuses(s, "of its rows")
    s = _Spec()
    s.bits = 8
    _refuses(s, "16 or 32 bits")
    s = _Spec()
    s.stored = 12
    _refuses(s, "every bit")
    s = _Spec()
    s.signed = 2
    _refuses(s, "0 or 1")
    var counts: List[String] = ["0", "1.5"]
    for c in counts:
        s = _Spec()
        s.frames = c
        _refuses(s, "whole number of frames")
    s = _Spec()
    s.frames = "2\\3"
    _refuses(s, "values of its number of frames")
    var scalings: List[String] = ["0", "-1"]
    for c in scalings:
        s = _Spec()
        s.scaling = c
        _refuses(s, "scaling must be positive")
    s = _Spec()
    s.position = ""
    _refuses(s, "values of its image position")
    var spacings: List[String] = ["0\\1", "1\\0"]
    for c in spacings:
        s = _Spec()
        s.spacing = c
        _refuses(s, "spacing must be positive")
    s = _Spec()
    s.orientation = "2\\0\\0\\0\\1\\0"
    _refuses(s, "unit directions")
    s = _Spec()
    s.orientation = "1\\0\\0\\0.6\\0.8\\0"
    _refuses(s, "square directions")
    # Offsets that are z need axial frames that start at the position.
    s = _Spec()
    s.offsets = "12\\16"
    _refuses(s, "axial frames")
    s = _Spec()
    s.orientation = "0\\1\\0\\1\\0\\0"
    s.offsets = "10\\14"
    _refuses(s, "axial frames")
    s = _Spec()
    s.orientation = "1\\0\\0\\0\\0\\1"
    s.offsets = "10\\14"
    _refuses(s, "axial frames")
    s = _Spec()
    s.offsets = "0\\0"
    _refuses(s, "share one place")
    s = _Spec()
    s.offsets = "0"
    _refuses(s, "values of its grid frame offsets")
    s = _Spec()
    s.frames = "3"
    s.offsets = "0\\4\\9"
    for v in range(12, 18):
        s.values.append(v)
    _refuses(s, "not evenly spaced")
    s = _Spec()
    _ = s.values.pop()
    _refuses(s, "does not fill its grid")
    # Encapsulated pixel data is not native.
    with assert_raises(contains="does not fill its grid"):
        _ = parse_rt_dose(_file(_Spec(), RLE_LOSSLESS))
    s = _Spec()
    s.rows = 0
    s.values = List[Int]()
    _refuses(s, "one voxel")
    with assert_raises(contains="preamble"):
        _ = parse_rt_dose(List[UInt8](length=20, fill=0))
    with assert_raises():
        _ = read_rt_dose("assets/dicom/no_such_dose.dcm")


def _known() raises -> DoseVolumeHistogram:
    """Doses of 1 to 5 Gy in voxels of 2 mm^3."""
    var doses: List[Float64] = [3.0, 1.0, 2.0, 5.0, 4.0]
    return DoseVolumeHistogram(doses^, Volume64(2e-9, CUBIC_METER))


def test_histogram_measures() raises:
    var dvh = _known()
    assert_equal(dvh.count(), 5)
    assert_equal(dvh.doses[0], 5.0)
    assert_almost_equal(dvh.volume().to(CUBIC_METER), 1e-8)
    assert_equal(dvh.minimum().to(GRAY), 1.0)
    assert_equal(dvh.maximum().to(GRAY), 5.0)
    assert_equal(dvh.mean().to(GRAY), 3.0)
    # The hottest part is counted up to whole voxels.
    assert_equal(dvh.dose_at_fraction(1.0).to(GRAY), 1.0)
    assert_equal(dvh.dose_at_fraction(0.2).to(GRAY), 5.0)
    assert_equal(dvh.dose_at_fraction(0.21).to(GRAY), 4.0)
    assert_equal(dvh.dose_at_fraction(0.6).to(GRAY), 3.0)
    assert_equal(dvh.dose_at_fraction(1e-12).to(GRAY), 5.0)
    assert_equal(dvh.dose_at_volume(Volume64(2e-9, CUBIC_METER)).to(GRAY), 5.0)
    assert_equal(
        dvh.dose_at_volume(Volume64(4.000001e-9, CUBIC_METER)).to(GRAY), 3.0
    )
    assert_equal(dvh.dose_at_volume(Volume64(1e-8, CUBIC_METER)).to(GRAY), 1.0)
    # A dose and more.
    assert_almost_equal(
        dvh.volume_at_dose(AbsorbedDose64(3, GRAY)).to(CUBIC_METER), 6e-9
    )
    assert_almost_equal(
        dvh.volume_at_dose(AbsorbedDose64(3.5, GRAY)).to(CUBIC_METER), 4e-9
    )
    assert_almost_equal(
        dvh.volume_at_dose(AbsorbedDose64(0, GRAY)).to(CUBIC_METER), 1e-8
    )
    assert_equal(dvh.volume_at_dose(AbsorbedDose64(6, GRAY)).to(CUBIC_METER), 0)
    assert_equal(dvh.fraction_at_dose(AbsorbedDose64(300, CENTIGRAY)), 0.6)
    # gEUD: the mean at 1, the root mean square at 2, the harmonic mean
    # at -1.
    assert_almost_equal(dvh.equivalent_uniform_dose(1.0).to(GRAY), 3.0)
    assert_almost_equal(dvh.equivalent_uniform_dose(2.0).to(GRAY), sqrt(11.0))
    assert_almost_equal(
        dvh.equivalent_uniform_dose(-1.0).to(GRAY), 300.0 / 137.0
    )
    var cold: List[Float64] = [0.0, 2.0]
    var zero = DoseVolumeHistogram(cold^, Volume64(1e-9, CUBIC_METER))
    assert_equal(zero.equivalent_uniform_dose(-10.0).to(GRAY), 0.0)
    assert_almost_equal(zero.equivalent_uniform_dose(0.5).to(GRAY), 0.5)
    # A power past the range of Float64 is kept as it is: infinite or 0.
    var tiny: List[Float64] = [1e-40, 1e-40]
    var faint = DoseVolumeHistogram(tiny^, Volume64(1e-9, CUBIC_METER))
    assert_equal(faint.equivalent_uniform_dose(-10.0).to(GRAY), 0.0)
    assert_equal(faint.equivalent_uniform_dose(10.0).to(GRAY), 0.0)
    # The curve at steps of 1 Gy, from 0 to the first step past 5 Gy.
    var curve = dvh.curve(AbsorbedDose64(1, GRAY))
    var want: List[Float64] = [1.0, 1.0, 0.8, 0.6, 0.4, 0.2, 0.0]
    assert_equal(len(curve), len(want))
    for k in range(len(want)):
        assert_almost_equal(curve[k], want[k])
    var below: List[Float64] = [-2.0, -1.0]
    var errors = DoseVolumeHistogram(below^, Volume64(1e-9, CUBIC_METER))
    var flat = errors.curve(AbsorbedDose64(1, GRAY))
    assert_equal(len(flat), 2)
    assert_equal(flat[0], 0.0)


def test_histogram_refusals() raises:
    var dvh = _known()
    var fractions: List[Float64] = [0.0, 1.5, nan[DType.float64]()]
    for f in fractions:
        with assert_raises(contains="above 0 and at most 1"):
            _ = dvh.dose_at_fraction(f)
    var volumes: List[Float64] = [0.0, inf[DType.float64]()]
    for v in volumes:
        with assert_raises(contains="positive and finite"):
            _ = dvh.dose_at_volume(Volume64(v, CUBIC_METER))
    with assert_raises(contains="larger than the region"):
        _ = dvh.dose_at_volume(Volume64(1.01e-8, CUBIC_METER))
    with assert_raises(contains="must be finite"):
        _ = dvh.volume_at_dose(AbsorbedDose64(nan[DType.float64](), GRAY))
    with assert_raises(contains="must be finite"):
        _ = dvh.fraction_at_dose(AbsorbedDose64(inf[DType.float64](), GRAY))
    var parameters: List[Float64] = [0.0, inf[DType.float64]()]
    for a in parameters:
        with assert_raises(contains="gEUD parameter"):
            _ = dvh.equivalent_uniform_dose(a)
    var below: List[Float64] = [-2.0, 1.0]
    var errors = DoseVolumeHistogram(below^, Volume64(1e-9, CUBIC_METER))
    with assert_raises(contains="not negative"):
        _ = errors.equivalent_uniform_dose(2.0)
    var steps: List[Float64] = [0.0, inf[DType.float64](), 1e-5]
    for s in steps:
        with assert_raises(contains="step"):
            _ = dvh.curve(AbsorbedDose64(s, GRAY))
    with assert_raises(contains="one dose or more"):
        _ = DoseVolumeHistogram(List[Float64](), Volume64(1e-9, CUBIC_METER))
    var voxels: List[Float64] = [0.0, inf[DType.float64]()]
    for v in voxels:
        var doses: List[Float64] = [1.0]
        with assert_raises(contains="voxel volume"):
            _ = DoseVolumeHistogram(doses^, Volume64(v, CUBIC_METER))
    var bad: List[Float64] = [1.0, nan[DType.float64]()]
    with assert_raises(contains="finite doses"):
        _ = DoseVolumeHistogram(bad^, Volume64(1e-9, CUBIC_METER))
    # A label on the dose's grid, with voxels.
    var dose = _read(_Spec())
    var map = LabelMap(dose)
    with assert_raises(contains="one dose or more"):
        _ = dose_volume_histogram(dose, map, LabelId(1))
    map.labels[3] = 1
    var one = dose_volume_histogram(dose, map, LabelId(1))
    assert_equal(one.count(), 1)
    assert_equal(one.maximum().to(GRAY), 1.5)
    assert_almost_equal(one.volume().to(CUBIC_METER), 1.2e-8)
    with assert_raises(contains="not background"):
        _ = dose_volume_histogram(dose, map, BACKGROUND)
    with assert_raises(contains="label"):
        _ = dose_volume_histogram(dose, map, LabelId(300))
    var other = ImageVolume(
        2,
        2,
        2,
        Length64(1.0, MILLIMETER64),
        Length64(1.0, MILLIMETER64),
        Length64(1.0, MILLIMETER64),
    )
    with assert_raises(contains="different grids"):
        _ = dose_volume_histogram(other, map, LabelId(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
