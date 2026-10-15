# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact CARLA control generators replay the committed fixtures.

Each test copies the committed fixtures to a temporary root and calls the
generators there. A check must not write, and a bad argument must fail
before any write. The fixed-s generator reads the geometry seeds that
`tools/capture_carla_fixed_s_controls.mojo` captures in this build.
"""

from std.os import listdir, makedirs, remove, rmdir
from std.os.path import exists, isdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from loaders.json import parse_json
from tools._carla_controls import (
    bracket,
    hex_word,
    next_down,
    next_up,
    parse_options,
    toward_zero,
)
from tools._bigint import BigInt
from tools._fraction import Fraction
from tools.capture_carla_fixed_s_controls import capture
from tools.generate_carla_directed_controls import run as run_directed
from tools.generate_carla_distance_controls import run as run_distance
from tools.generate_carla_fixed_s_controls import run as run_fixed_s
from tools.generate_carla_index_controls import run as run_index
from tools.generate_carla_lane_distance_controls import run as run_lane
from tools.generate_carla_lane_orientation_controls import (
    report as orientation_report,
    run as run_orientation,
)
from tools.generate_carla_power_controls import run as run_power


comptime NAMES = [
    "lane_distance",
    "power",
    "directed",
    "index",
    "distance",
    "fixed_s",
]
"""The generators."""

comptime CAPTURE = "capture.txt"
"""The fixed-s capture below the temporary root."""

comptime ORIENTATION = (
    "{\n"
    '  "orientation_controls": [\n'
    "    {\n"
    '      "road": 1,\n'
    '      "section": 1,\n'
    '      "lane": -1,\n'
    '      "s": 50,\n'
    '      "yaw": 1.4320961841646465,\n'
    '      "pitch": -0.0,\n'
    '      "forward": [\n'
    "        0.9996876464081226,\n"
    "        0.024992191160203066,\n"
    "        0.0\n"
    "      ]\n"
    "    },\n"
    "    {\n"
    '      "road": 5,\n'
    '      "section": 0,\n'
    '      "lane": -1,\n'
    '      "s": 10,\n'
    '      "yaw": -7.16197243913529,\n'
    '      "pitch": -1.1110515913233194,\n'
    '      "forward": [\n'
    "        0.9920111247332872,\n"
    "        -0.1246512933624105,\n"
    "        0.019390293150875013\n"
    "      ]\n"
    "    },\n"
    "    {\n"
    '      "road": 5,\n'
    '      "section": 0,\n'
    '      "lane": 1,\n'
    '      "s": 40,\n'
    '      "yaw": 133.9651124804412,\n'
    '      "pitch": 361.2666524315157,\n'
    '      "forward": [\n'
    "        -0.694050597730119,\n"
    "        0.719586767987595,\n"
    "        -0.02210545470312238\n"
    "      ]\n"
    "    },\n"
    "    {\n"
    '      "road": 5,\n'
    '      "section": 0,\n'
    '      "lane": -2,\n'
    '      "s": 50,\n'
    '      "yaw": -46.954509986767036,\n'
    '      "pitch": -2.018064258751107,\n'
    '      "forward": [\n'
    "        0.6821554507134533,\n"
    "        -0.7303587297740473,\n"
    "        0.035214583694340454\n"
    "      ]\n"
    "    }\n"
    "  ],\n"
    '  "segment_count": 230,\n'
    '  "segments_by_road_section_lane": {\n'
    '    "1/0": {\n'
    '      "2": 1,\n'
    '      "1": 1,\n'
    '      "-1": 1,\n'
    '      "-2": 1\n'
    "    },\n"
    '    "1/1": {\n'
    '      "2": 1,\n'
    '      "1": 1,\n'
    '      "-1": 1,\n'
    '      "-2": 1\n'
    "    },\n"
    '    "10/0": {\n'
    '      "1": 1,\n'
    '      "-1": 1\n'
    "    },\n"
    '    "11/0": {\n'
    '      "-1": 32,\n'
    '      "-2": 32\n'
    "    },\n"
    '    "2/0": {\n'
    '      "1": 1,\n'
    '      "-1": 1\n'
    "    },\n"
    '    "3/0": {\n'
    '      "-1": 1,\n'
    '      "-2": 1\n'
    "    },\n"
    '    "5/0": {\n'
    '      "1": 38,\n'
    '      "-1": 36,\n'
    '      "-2": 36,\n'
    '      "-3": 36\n'
    "    },\n"
    '    "6/0": {\n'
    '      "2": 1,\n'
    '      "1": 1,\n'
    '      "-1": 1,\n'
    '      "-2": 1,\n'
    '      "-3": 1\n'
    "    },\n"
    '    "7/0": {\n'
    '      "-1": 1\n'
    "    }\n"
    "  },\n"
    '  "heading_threshold_decisions": 292,\n'
    '  "minimum_threshold_margin_radians": 0.00011237220446894819\n'
    "}\n"
)
"""The report of the Python generator that the tool replaces."""


def _fixture(name: String) -> String:
    """Return a generator's fixture path below the root."""
    if name == "distance":
        return "tests/test_carla_curve_distance_fraction.mojo"
    if name == "fixed_s":
        return "tests/test_carla_fixed_s_fraction.mojo"
    if name == "lane_distance":
        return "tests/test_carla_lane_distance_fraction.mojo"
    if name == "power":
        return "tests/test_carla_power_fraction.mojo"
    if name == "directed":
        return "tests/test_carla_directed_fraction.mojo"
    return "tests/test_carla_index_admission.mojo"


def _count(name: String) -> Int:
    """Return a generator's number of cases."""
    if name == "lane_distance" or name == "distance":
        return 100
    if name == "index":
        return 96
    if name == "fixed_s":
        return 135
    return 128


def _run(
    name: String, root: String, arguments: List[String]
) raises -> Tuple[Int, String]:
    """Call a generator. The fixed-s generator gets the capture first."""
    if name == "distance":
        return run_distance(root, arguments)
    if name == "fixed_s":
        var given: List[String] = [root + "/" + CAPTURE]
        given.extend(arguments.copy())
        return run_fixed_s(root, given)
    if name == "lane_distance":
        return run_lane(root, arguments)
    if name == "power":
        return run_power(root, arguments)
    if name == "directed":
        return run_directed(root, arguments)
    return run_index(root, arguments)


struct Copy(Movable):
    """The committed fixtures in a temporary root."""

    var root: String
    """The temporary root."""

    def __init__(out self) raises:
        """Copy every fixture."""
        self.root = mkdtemp(prefix="carla control replay ")
        makedirs(self.root + "/tests")
        for name in materialize[NAMES]():
            var relative = _fixture(name)
            self.write(relative, Path(relative).read_bytes())
        Path(self.path(CAPTURE)).write_text(capture())

    def path(self, relative: String) -> String:
        """Return a path below the root."""
        return self.root + "/" + relative

    def read(self, relative: String) raises -> List[UInt8]:
        """Return a file's bytes."""
        return Path(self.path(relative)).read_bytes()

    def write(self, relative: String, data: List[UInt8]) raises:
        """Replace a file's bytes."""
        Path(self.path(relative)).write_bytes(Span(data))

    def snapshot(self) raises -> Snapshot:
        """Return every path and its bytes, in a fixed order."""
        var found = Snapshot()
        _walk(self.root, "", found)
        return found^

    def close(self) raises:
        """Remove the root."""
        _remove_tree(self.root)


struct Snapshot(Movable):
    """Every path below a root, and each file's bytes."""

    var paths: List[String]
    """The paths, with a directory marked."""
    var contents: List[List[UInt8]]
    """The bytes of each path; a directory has none."""

    def __init__(out self):
        """Start empty."""
        self.paths = List[String]()
        self.contents = List[List[UInt8]]()

    def same(self, other: Snapshot) -> Bool:
        """Return whether two snapshots hold the same paths and bytes."""
        if self.paths != other.paths:
            return False
        for index in range(len(self.contents)):
            if self.contents[index] != other.contents[index]:
                return False
        return True


def _walk(root: String, relative: String, mut found: Snapshot) raises:
    """Record each path below a directory, and each file's bytes."""
    var directory = root + "/" + relative
    var names = listdir(directory)
    sort(names)
    for name in names:
        var child = relative + name
        if isdir(root + "/" + child):
            found.paths.append("directory " + child)
            found.contents.append(List[UInt8]())
            _walk(root, child + "/", found)
        else:
            found.paths.append("file " + child)
            found.contents.append(Path(root + "/" + child).read_bytes())


def _remove_tree(directory: String) raises:
    """Remove a directory and everything below it."""
    for name in listdir(directory):
        var child = directory + "/" + name
        if isdir(child):
            _remove_tree(child)
        else:
            remove(child)
    rmdir(directory)


def _assert_read_only(
    copy: Copy, name: String, arguments: List[String], status: Int
) raises -> String:
    """Run a generator that must not write, and check its status."""
    var before = copy.snapshot()
    var outcome = _run(name, copy.root, arguments)
    assert_equal(outcome[0], status, name + ": " + outcome[1])
    assert_true(copy.snapshot().same(before), name + " wrote a file")
    return outcome[1]


def test_committed_fixtures_replay_exactly_without_writes() raises:
    var copy = Copy()
    for name in materialize[NAMES]():
        var output = _assert_read_only(copy, name, ["--check"], 0)
        assert_true(
            output.startswith("Verified " + String(_count(name)) + " "),
            output,
        )
    copy.close()


def test_default_generation_and_json_need_no_existing_fixture() raises:
    var copy = Copy()
    for name in materialize[NAMES]():
        var relative = _fixture(name)
        var expected = copy.read(relative)
        remove(copy.path(relative))
        var report = copy.path(name + ".json")
        var outcome = _run(name, copy.root, ["--json", report])
        assert_equal(outcome[0], 0, outcome[1])
        assert_true(outcome[1].startswith("Generated "), outcome[1])
        assert_true(copy.read(relative) == expected, name)
        var document = parse_json(Path(report).read_text())
        assert_equal(document.length(document.root()), _count(name))
        _ = _assert_read_only(copy, name, ["--check"], 0)
    copy.close()


def _replace_first(
    data: List[UInt8], old: String, new: String
) raises -> List[UInt8]:
    """Return the bytes with the first occurrence of old replaced."""
    var text = String(unsafe_from_utf8=Span(data))
    var at = text.find(old)
    if at < 0:
        raise Error("missing " + old)
    var changed = (
        String(text[byte=:at])
        + new
        + String(text[byte = at + old.byte_length() :])
    )
    var out = List[UInt8]()
    out.extend(changed.as_bytes())
    return out^


def _corruptions(original: List[UInt8]) raises -> List[List[UInt8]]:
    """Return the original changed in a word, an import, an assertion,
    a space, the newlines, the length and the encoding."""
    var text = String(unsafe_from_utf8=Span(original))
    var start = text.find("UInt64(0x") + "UInt64(0x".byte_length()
    var numeric = original.copy()
    numeric[start] = UInt8(ord("F")) if numeric[start] != UInt8(
        ord("F")
    ) else UInt8(ord("E"))
    var newlines = List[UInt8]()
    for byte in original:
        if byte == UInt8(ord("\n")):
            newlines.append(UInt8(ord("\r")))
        newlines.append(byte)
    var truncated = original.copy()
    _ = truncated.pop()
    var encoded = original.copy()
    encoded.append(0xFF)
    return [
        numeric^,
        _replace_first(
            original, "from extensions.carla.", "from extensions.wrong."
        ),
        _replace_first(original, "assert_true(", "assert_false("),
        _replace_first(original, "    var cases:", "     var cases:"),
        newlines^,
        truncated^,
        encoded^,
    ]


def test_numeric_import_assertion_and_format_drift_fail_without_repair() raises:
    var copy = Copy()
    for name in materialize[NAMES]():
        var relative = _fixture(name)
        var original = copy.read(relative)
        for changed in _corruptions(original):
            assert_false(changed == original)
            copy.write(relative, changed)
            var output = _assert_read_only(copy, name, ["--check"], 1)
            assert_true("is stale" in output, output)
            assert_true(copy.read(relative) == changed)
        copy.write(relative, original)
    copy.close()


def test_missing_and_unreadable_fixtures_fail_without_creation() raises:
    var copy = Copy()
    for name in materialize[NAMES]():
        var target = copy.path(_fixture(name))
        remove(target)
        var output = _assert_read_only(copy, name, ["--check"], 1)
        assert_true(output.startswith("Cannot check " + target), output)
        assert_false(exists(target))
        makedirs(target)
        output = _assert_read_only(copy, name, ["--check"], 1)
        assert_true(output.startswith("Cannot check " + target), output)
        assert_true(isdir(target))
        # Generation cannot replace a directory either.
        output = _assert_read_only(copy, name, [], 1)
        assert_true(output.startswith("Cannot write " + target), output)
        rmdir(target)
    copy.close()


def test_conflicting_and_unknown_arguments_fail_before_any_write() raises:
    var copy = Copy()
    var report = copy.path("report.json")
    Path(report).write_text("preserve this report\n")
    var fresh = copy.path("new.json")
    var sets: List[List[String]] = [
        ["--check", "--json", report],
        ["--json", report, "--check"],
        ["--check", "--json", fresh],
        ["--check", "--json=" + fresh],
        ["--check", "--unknown"],
        ["--unknown"],
        ["--che"],
        ["--jso", report],
        ["positional"],
        ["--json"],
        ["--json", "--check"],
    ]
    for name in materialize[NAMES]():
        for arguments in sets:
            var output = _assert_read_only(copy, name, arguments, 2)
            assert_true(output.startswith("usage: generate_carla_"), output)
            assert_true(": error: " in output, output)
        var help = _assert_read_only(copy, name, ["--check", "-h"], 0)
        assert_true("verify without writing" in help, help)
    copy.close()


def test_an_unwritable_report_fails() raises:
    var copy = Copy()
    # A directory cannot take the report.
    var report = copy.path("tests")
    for name in materialize[NAMES]():
        var outcome = _run(name, copy.root, ["--json", report])
        assert_equal(outcome[0], 1, outcome[1])
        assert_true(outcome[1].startswith("Cannot write " + report))
    copy.close()


def test_options_parse_as_argparse_does() raises:
    var options = parse_options("tool", "About.", ["--json=a.json", "--check"])
    assert_equal(options.status, 2)
    assert_true("do not combine it with --json" in options.message)
    options = parse_options("tool", "About.", ["--json", "a", "--json", "b"])
    assert_equal(options.status, 0)
    assert_equal(options.json, "b")
    assert_false(options.check)
    options = parse_options("tool", "About.", ["--check", "--check"])
    assert_equal(options.status, 0)
    assert_true(options.check and not options.has_json)
    options = parse_options("tool", "About.", ["--json", "-"])
    assert_equal(options.json, "-")
    options = parse_options("tool", "About.", ["--help"])
    assert_equal(options.status, -1)
    assert_true(options.message.startswith("usage: tool [-h]"))


def test_directed_rounding_brackets_rationals() raises:
    assert_equal(hex_word(0x0123456789ABCDEF), "0123456789ABCDEF")
    assert_equal(next_up(0.0), next_up(-0.0))
    assert_equal(next_down(1.0), toward_zero(1.0))
    assert_equal(next_up(-1.0), toward_zero(-1.0))
    var infinity = next_up(Float64.MAX_FINITE)
    assert_equal(next_up(infinity), infinity)
    assert_equal(next_down(-infinity), -infinity)
    # An exact value is one point; a third lies between two neighbors.
    var point = bracket(Fraction(3))
    assert_equal(point[0], 3.0)
    assert_equal(point[1], 3.0)
    var third = bracket(Fraction.of(BigInt(1), BigInt(3)))
    assert_equal(next_up(third[0]), third[1])
    # Past the range, the bracket runs from the largest finite double.
    var huge = Fraction.from_float(Float64.MAX_FINITE) * Fraction(2)
    var above = bracket(huge)
    assert_equal(above[0], Float64.MAX_FINITE)
    assert_equal(above[1], infinity)
    var below = bracket(-huge)
    assert_equal(below[0], -infinity)
    assert_equal(below[1], -Float64.MAX_FINITE)


def test_a_bad_capture_fails_before_any_write() raises:
    var copy = Copy()
    var good = Path(copy.path(CAPTURE)).read_text()
    var missing = copy.path("missing.txt")
    var lines = good.split("\n")
    var short = String()
    for index in range(44):
        short += String(lines[index]) + "\n"
    var bad_inputs: List[String] = [
        # One line too few gives 132 cases.
        short,
        good + "0 0 0 0 0 0 0\n",
        "0 0 0 0 0 0\n" + good,
        "0 0 0 0 0 0 18446744073709551616\n" + good,
        "0 0 0 0 0 0 -1\n" + good,
        "0 0 0 0 0 0 x\n" + good,
    ]
    for capture_text in bad_inputs:
        Path(copy.path(CAPTURE)).write_text(capture_text)
        var sets: List[List[String]] = [[], ["--check"]]
        for arguments in sets:
            var output = _assert_read_only(copy, "fixed_s", arguments, 1)
            assert_true(output.startswith("Cannot read "), output)
    Path(copy.path(CAPTURE)).write_text(good)
    var before = copy.snapshot()
    var outcome = run_fixed_s(copy.root, [missing, "--check"])
    assert_equal(outcome[0], 1)
    assert_true(outcome[1].startswith("Cannot read " + missing), outcome[1])
    assert_true(copy.snapshot().same(before))
    assert_false(exists(missing))
    copy.close()


def test_the_capture_is_a_required_positional_argument() raises:
    var program = "generate_carla_fixed_s_controls"
    var options = parse_options(program, "About.", [], "capture")
    assert_equal(options.status, 2)
    assert_true(
        options.message.startswith(
            "usage: " + program + " [-h] [--json JSON] [--check] capture\n"
        )
    )
    assert_true("required: capture" in options.message)
    options = parse_options(program, "About.", ["--bad"], "capture")
    assert_true("required: capture" in options.message)
    options = parse_options(program, "About.", ["a", "b"], "capture")
    assert_true("unrecognized arguments: b" in options.message)
    options = parse_options(program, "About.", ["--", "--check"], "capture")
    assert_equal(options.status, 0)
    assert_equal(options.positional, "--check")
    assert_false(options.check)
    options = parse_options(program, "About.", ["-", "--check"], "capture")
    assert_equal(options.positional, "-")
    assert_true(options.check)
    options = parse_options(program, "About.", ["a", "--json"], "capture")
    assert_true("--json: expected one argument" in options.message)
    options = parse_options(program, "About.", ["-h"], "capture")
    assert_equal(options.status, -1)
    assert_true("\npositional arguments:\n  capture\n" in options.message)
    # A tool without a positional argument refuses one, and "--" too.
    options = parse_options(program, "About.", ["--"])
    assert_true("unrecognized arguments: --" in options.message)


def test_orientation_report_matches_the_python_generator() raises:
    assert_equal(run_orientation("."), ORIENTATION)
    # A left-hand town turns each lane the other way.
    var town = Path("assets/carla/town.xodr").read_text()
    var left = orientation_report(town.replace('rule="RHT"', 'rule="LHT"'))
    assert_true(left != ORIENTATION)
    assert_true('"segment_count": ' in left)
    with assert_raises():
        _ = orientation_report("<OpenDRIVE/>")
    with assert_raises():
        _ = run_orientation("/nonexistent")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
