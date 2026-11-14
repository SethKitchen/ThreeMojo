# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PET elements of DICOM files and standardized uptake values.

The fixtures `pet.dcm` and `pet_implicit.dcm` were written by pydicom
3.0.1. See `assets/dicom/make_pet.py` and `assets/dicom/pet_expected.txt`.
"""

from extensions.imaging.dicom import (
    Activity64,
    BECQUEREL,
    MEGABECQUEREL,
    PetDose,
    parse_dicom,
    read_dicom,
)
from extensions.imaging.dicom_write import DicomWriter
from extensions.imaging.ids import (
    BACKGROUND,
    EXPLICIT_LITTLE,
    IMPLICIT_LITTLE,
    LabelId,
    TransferSyntax,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.suv import (
    GRAM_PER_BECQUEREL,
    SuvFactor64,
    suv_factor,
    suv_statistics,
    suv_volume,
)
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Duration64,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM,
    Length64,
    Mass64,
    SECOND,
)

comptime F18_HALF_LIFE = 6586.2


def _expected(name: String) raises -> List[String]:
    """Return the words that pydicom printed for one file."""
    var text = open("assets/dicom/pet_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if parts[0] == name:
            var out = List[String]()
            for part in parts:
                out.append(String(part))
            return out^
    raise Error("no expected values for " + name)


def test_pydicom_fixtures() raises:
    for name in ["pet.dcm", "pet_implicit.dcm"]:
        var words = _expected(name)
        var image = read_dicom("assets/dicom/" + name)
        ref pet = image.pet
        assert_equal(pet.units, words[1])
        assert_equal(pet.decay_correction, words[2])
        assert_almost_equal(pet.patient_weight.to(KILOGRAM), atof(words[3]))
        assert_true(pet.has_series_time)
        assert_almost_equal(pet.series_time.to(SECOND), atof(words[4]))
        assert_true(pet.has_injection_time)
        assert_almost_equal(pet.injection_time.to(SECOND), atof(words[5]))
        assert_almost_equal(pet.injected_dose.to(BECQUEREL), atof(words[6]))
        assert_almost_equal(pet.half_life.to(SECOND), atof(words[7]))
        var factor = suv_factor(pet).to(GRAM_PER_BECQUEREL)
        assert_almost_equal(factor, atof(words[8]), rtol=1e-14)
        for v in range(12):
            assert_equal(Float64(image.values[v]), atof(words[9 + v]))


def _file(
    syntax: TransferSyntax, series: String, weight: String
) raises -> DicomWriter:
    """Return a writer of one pixel, with a series time and a weight."""
    var writer = DicomWriter(syntax)
    writer.text(0x0008, 0x0031, "TM", series)
    writer.text(0x0010, 0x1030, "DS", weight)
    writer.short(0x0028, 0x0010, 1)
    writer.short(0x0028, 0x0011, 1)
    writer.short(0x0028, 0x0100, 16)
    writer.short(0x0028, 0x0103, 0)
    return writer^


def _pixel(var writer: DicomWriter) raises -> List[UInt8]:
    writer.binary(0x7FE0, 0x0010, "OW", [UInt8(5), UInt8(0)])
    return writer^.finish()


def test_times_and_absent_elements() raises:
    var cases: List[String] = ["10", "1015", "101500", "101500.5", "235960"]
    var seconds: List[Float64] = [36000, 36900, 36900, 36900.5, 86400]
    for c in range(len(cases)):
        var image = parse_dicom(_pixel(_file(EXPLICIT_LITTLE, cases[c], "61")))
        assert_true(image.pet.has_series_time)
        assert_equal(image.pet.series_time.to(SECOND), seconds[c])
        assert_equal(image.pet.patient_weight.to(KILOGRAM), 61.0)
    # Empty elements are absent, as in a CT file.
    var empty = parse_dicom(_pixel(_file(IMPLICIT_LITTLE, "", "")))
    assert_false(empty.pet.has_series_time)
    assert_false(empty.pet.has_injection_time)
    assert_equal(empty.pet.patient_weight.to(KILOGRAM), 0.0)
    assert_equal(empty.pet.units, "")
    assert_equal(empty.pet.injected_dose.to(BECQUEREL), 0.0)
    # The first item of the dose sequence counts; a second one does not.
    var writer = _file(EXPLICIT_LITTLE, "120000", "80")
    writer.open_sequence(0x0054, 0x0016)
    writer.open_item()
    writer.text(0x0018, 0x1072, "TM", "110000")
    writer.text(0x0018, 0x1074, "DS", "200000000")
    writer.text(0x0018, 0x1075, "DS", "")
    writer.close_item()
    writer.open_item()
    writer.text(0x0018, 0x1074, "DS", "999")
    writer.close_item()
    writer.close_sequence()
    writer.text(0x0054, 0x1001, "CS", "BQML")
    writer.text(0x0054, 0x1102, "CS", "ADMIN")
    var pet = parse_dicom(_pixel(writer^)).pet.copy()
    assert_equal(pet.injection_time.to(SECOND), 39600.0)
    assert_equal(pet.injected_dose.to(MEGABECQUEREL), 200.0)
    assert_equal(pet.half_life.to(SECOND), 0.0)
    assert_almost_equal(
        suv_factor(pet).to(GRAM_PER_BECQUEREL), 80000.0 / 2e8, rtol=1e-15
    )
    # A dose sequence without items gives nothing.
    writer = _file(EXPLICIT_LITTLE, "120000", "80")
    writer.open_sequence(0x0054, 0x0016)
    writer.close_sequence()
    var bare = parse_dicom(_pixel(writer^)).pet.copy()
    assert_false(bare.has_injection_time)
    # Of two dose sequences, the first counts.
    writer = _file(EXPLICIT_LITTLE, "120000", "80")
    for start in ["080000", "090000"]:
        writer.open_sequence(0x0054, 0x0016)
        writer.open_item()
        writer.text(0x0018, 0x1072, "TM", start)
        writer.close_item()
        writer.close_sequence()
    var twice = parse_dicom(_pixel(writer^)).pet.copy()
    assert_equal(twice.injection_time.to(SECOND), 28800.0)


def test_bad_times_and_numbers() raises:
    var bad: List[String] = [
        "1",
        "123",
        "12345",
        "1234567",
        "12.5",
        "120000.",
        "120000.1234567",
        "120000.5.1",
        "12a000",
        "12/000",
        "120000.5x",
        "120000./",
        "1a/000",
        ".5",
    ]
    for text in bad:
        with assert_raises(contains="HHMMSS"):
            _ = parse_dicom(_pixel(_file(EXPLICIT_LITTLE, text, "70")))
    for text in ["240000", "126000", "125961"]:
        with assert_raises(contains="time of day"):
            _ = parse_dicom(_pixel(_file(EXPLICIT_LITTLE, text, "70")))
    with assert_raises(contains="patient weight"):
        _ = parse_dicom(_pixel(_file(EXPLICIT_LITTLE, "120000", "heavy")))
    var writer = _file(EXPLICIT_LITTLE, "120000", "80")
    writer.open_sequence(0x0054, 0x0016)
    writer.open_item()
    writer.text(0x0018, 0x1072, "TM", "99")
    writer.close_item()
    writer.close_sequence()
    with assert_raises(contains="injection time"):
        _ = parse_dicom(_pixel(writer^))
    for tag in [0x1074, 0x1075]:
        writer = _file(EXPLICIT_LITTLE, "120000", "80")
        writer.open_sequence(0x0054, 0x0016)
        writer.open_item()
        writer.text(0x0018, tag, "DS", "lots")
        writer.close_item()
        writer.close_sequence()
        with assert_raises(contains="not a number"):
            _ = parse_dicom(_pixel(writer^))


def test_suv_factor() raises:
    var dose = PetDose()
    dose.units = "BQML"
    dose.decay_correction = "START"
    dose.patient_weight = Mass64(70, KILOGRAM)
    dose.injected_dose = Activity64(370, MEGABECQUEREL)
    dose.half_life = Duration64(F18_HALF_LIFE, SECOND)
    # Injected at 23:50, scanned at 00:20: half an hour past midnight.
    dose.injection_time = Duration64(85800, SECOND)
    dose.series_time = Duration64(1200, SECOND)
    dose.has_injection_time = True
    dose.has_series_time = True
    var decayed = 3.7e8 * 2.0 ** (-1800.0 / F18_HALF_LIFE)
    assert_almost_equal(
        suv_factor(dose).to(GRAM_PER_BECQUEREL), 70000.0 / decayed, rtol=1e-14
    )
    # Corrected to the injection, the dose does not decay.
    var admin = dose.copy()
    admin.decay_correction = "ADMIN"
    admin.has_series_time = False
    admin.half_life = Duration64(0, SECOND)
    assert_almost_equal(
        suv_factor(admin).to(GRAM_PER_BECQUEREL), 70000.0 / 3.7e8, rtol=1e-15
    )
    var wrong = dose.copy()
    wrong.units = "CNTS"
    with assert_raises(contains="BQML"):
        _ = suv_factor(wrong)
    wrong = dose.copy()
    wrong.decay_correction = "NONE"
    with assert_raises(contains="START or ADMIN"):
        _ = suv_factor(wrong)
    for kilograms in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        wrong = dose.copy()
        wrong.patient_weight = Mass64(kilograms, KILOGRAM)
        with assert_raises(contains="weight"):
            _ = suv_factor(wrong)
    for becquerels in [0.0, inf[DType.float64]()]:
        wrong = dose.copy()
        wrong.injected_dose = Activity64(becquerels, BECQUEREL)
        with assert_raises(contains="injected dose"):
            _ = suv_factor(wrong)
    for half in [0.0, inf[DType.float64]()]:
        wrong = dose.copy()
        wrong.half_life = Duration64(half, SECOND)
        with assert_raises(contains="half-life"):
            _ = suv_factor(wrong)
    wrong = dose.copy()
    wrong.has_series_time = False
    with assert_raises(contains="series time"):
        _ = suv_factor(wrong)
    wrong = dose.copy()
    wrong.has_injection_time = False
    with assert_raises(contains="injection time"):
        _ = suv_factor(wrong)
    # A scan after the injection on one day.
    wrong = dose.copy()
    wrong.series_time = Duration64(86000, SECOND)
    var later = 3.7e8 * 2.0 ** (-200.0 / F18_HALF_LIFE)
    assert_almost_equal(
        suv_factor(wrong).to(GRAM_PER_BECQUEREL), 70000.0 / later, rtol=1e-14
    )


def _grid(
    nx: Int, ny: Int, nz: Int, sx: Float64, sy: Float64, sz: Float64
) raises -> ImageVolume:
    return ImageVolume(
        nx,
        ny,
        nz,
        Length64(sx, MILLIMETER64),
        Length64(sy, MILLIMETER64),
        Length64(sz, MILLIMETER64),
    )


def test_suv_volume() raises:
    var volume = _grid(2, 1, 1, 1, 1, 1)
    volume.values[0] = 1000
    volume.values[1] = 5000
    var factor = SuvFactor64(0.0004, GRAM_PER_BECQUEREL)
    var suv = suv_volume(volume, factor)
    assert_almost_equal(Float64(suv.values[0]), 0.4, rtol=1e-6)
    assert_almost_equal(Float64(suv.values[1]), 2.0, rtol=1e-6)
    assert_equal(volume.values[0], 1000)
    for bad in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        with assert_raises(contains="factor"):
            _ = suv_volume(volume, SuvFactor64(bad, GRAM_PER_BECQUEREL))


def test_suv_statistics() raises:
    # Voxels of 4 by 4 by 3 mm, with an SUV that rises along i.
    var suv = _grid(9, 8, 7, 4, 4, 3)
    for k in range(7):
        for j in range(8):
            for i in range(9):
                suv.set(
                    i, j, k, Float32(1 + 0.5 * Float64(i) + 0.1 * Float64(k))
                )
    var map = LabelMap(suv)
    var cells: List[Tuple[Int, Int, Int]] = [
        (0, 0, 0),
        (4, 4, 3),
        (8, 7, 6),
        (7, 3, 1),
    ]
    for c in cells:
        map.set(c[0], c[1], c[2], LabelId(2))
    var stats = suv_statistics(suv, map, LabelId(2))
    # A search of every voxel near each center.
    var radius = (3.0 / (4.0 * 3.141592653589793)) ** (1.0 / 3.0) * 10.0
    var best = -1.0
    var best_cell = 0
    var largest = 0.0
    var total = 0.0
    for n in range(len(cells)):
        var c = cells[n]
        var value = Float64(suv.get(c[0], c[1], c[2]))
        largest = max(largest, value)
        total += value
        var sum = 0.0
        var held = 0
        for k in range(7):
            for j in range(8):
                for i in range(9):
                    var d = sqrt(
                        (Float64(i - c[0]) * 4) ** 2
                        + (Float64(j - c[1]) * 4) ** 2
                        + (Float64(k - c[2]) * 3) ** 2
                    )
                    if d <= radius:
                        sum += Float64(suv.get(i, j, k))
                        held += 1
        if sum / Float64(held) > best:
            best = sum / Float64(held)
            best_cell = n
    assert_almost_equal(
        stats.maximum.to(GRAM_PER_CUBIC_CENTIMETER), largest, rtol=1e-6
    )
    assert_almost_equal(
        stats.mean.to(GRAM_PER_CUBIC_CENTIMETER), total / 4, rtol=1e-6
    )
    assert_almost_equal(
        stats.peak.to(GRAM_PER_CUBIC_CENTIMETER), best, rtol=1e-6
    )
    assert_equal(stats.peak_voxel[0], cells[best_cell][0])
    assert_equal(stats.peak_voxel[1], cells[best_cell][1])
    assert_equal(stats.peak_voxel[2], cells[best_cell][2])
    # A flat SUV ties every sphere: the lowest voxel counts.
    var flat = _grid(5, 5, 5, 2, 2, 2)
    for index in range(flat.count()):
        flat.values[index] = 2.5
    var all = LabelMap(flat)
    all.set(3, 3, 3, LabelId(1))
    all.set(1, 2, 2, LabelId(1))
    var even = suv_statistics(flat, all, LabelId(1))
    assert_equal(even.peak.to(GRAM_PER_CUBIC_CENTIMETER), 2.5)
    assert_equal(even.peak_voxel[0], 1)
    with assert_raises(contains="background"):
        _ = suv_statistics(flat, all, BACKGROUND)
    with assert_raises(contains="no voxels"):
        _ = suv_statistics(flat, all, LabelId(9))
    with assert_raises(contains="label"):
        _ = suv_statistics(flat, all, LabelId(256))
    with assert_raises(contains="different grids"):
        _ = suv_statistics(suv, all, LabelId(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
