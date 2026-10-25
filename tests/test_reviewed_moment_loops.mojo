# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed moment, speed, lane, blend, and hair proofs follow the digest."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import PY_NONE, PyJson


def _trim(text: String) -> String:
    """Return `text` without one trailing newline."""
    if text.endswith("\n"):
        return String(text[byte = : text.byte_length() - 1])
    return text


def _run(arguments: List[String]) raises -> String:
    """Run the seal tool and return its standard output."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("coverage_loop_seal")
    for word in arguments:
        command.append(word)
    var ran = run_program(command, 30.0, merge_errors=False)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    return ran.output


def _reviews(root: String, module: String) raises -> PyJson:
    """Return the reviewed proofs for `module` under `root`."""
    return PyJson.parse(_trim(_run(["reviews", root, module])))


def _loops(path: String) raises -> PyJson:
    """Return the literal loop proofs in `path`."""
    return PyJson.parse(_trim(_run(["loops", path])))


def _rows(doc: PyJson) raises -> Int:
    """Return how many proof rows `doc` holds."""
    return doc.length(doc.root)


def _row(doc: PyJson, line: String) raises -> Int:
    """Return the proof whose line is `line`."""
    var index = 0
    while index < _rows(doc):
        var row = doc.item(doc.root, index)
        if doc.text(doc.at(row, "line")) == line:
            return row
        index += 1
    raise Error("missing reviewed line " + line)


def _text_field(doc: PyJson, row: Int, key: String) raises -> String:
    """Return one field, with JSON null as `null`."""
    var node = doc.at(row, key)
    if doc.kind(node) == PY_NONE:
        return "null"
    return doc.text(node)


def _stage(root: String, relative: String) raises:
    """Copy one repository file into `root`."""
    var dest = root + "/" + relative
    var slash = dest.rfind("/")
    var parent = String(dest[byte=:slash])
    var made = run_program(["mkdir", "-p", parent], 10.0)
    if made.status != 0:
        raise Error(made.output)
    Path(dest).write_bytes(Path(relative).read_bytes())


def _once(text: String, before: String, after: String) raises -> String:
    """Replace the first `before` in `text`."""
    var at = text.find(before)
    if at < 0:
        raise Error("missing premise " + before)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _rewrite(root: String, relative: String, text: String) raises:
    """Write `text` over the staged copy."""
    Path(root + "/" + relative).write_text(text)


def _empty(root: String, module: String) raises:
    """Require `module` to have no reviewed proof under `root`."""
    assert_equal(_rows(_reviews(root, module)), 0)


def test_spiral_runtime_sites_keep_their_cardinalities() raises:
    """The seven moment proofs match the reviewed table, and literals stay out.
    """
    var module = "extensions/carla/spiral_moment_proof"
    var source = module + ".mojo"
    var doc = _reviews(".", module)
    assert_equal(_rows(doc), 7)
    var expected = List[String]()
    expected.append("92|literal-range|5|5|range(5)|moment-weight-five-nodes")
    expected.append(
        "97|reviewed-nonempty-range|1|64|range(pieces)|moment-admitted-piece-count-1-to-64"
    )
    expected.append("98|literal-range|5|5|range(5)|moment-piece-five-nodes")
    expected.append(
        "111|literal-range|21|21|range(1, 22)|moment-power-twenty-one"
    )
    expected.append(
        "119|literal-range|21|21|range(1, 22)|moment-normalize-twenty-one"
    )
    expected.append(
        "125|literal-range|11|11|range(11)|moment-eleven-coefficients"
    )
    expected.append(
        "163|literal-range|4|4|range(1, 5)|moment-node-four-successors"
    )
    var index = 0
    while index < len(expected):
        var parts = expected[index].split("|")
        var row = _row(doc, String(parts[0]))
        assert_equal(_text_field(doc, row, "kind"), String(parts[1]))
        assert_equal(_text_field(doc, row, "cardinality"), String(parts[2]))
        assert_equal(
            _text_field(doc, row, "maximum_cardinality"), String(parts[3])
        )
        assert_equal(_text_field(doc, row, "required"), "T")
        assert_equal(_text_field(doc, row, "impossible"), "F")
        assert_equal(_text_field(doc, row, "expression"), String(parts[4]))
        assert_equal(_text_field(doc, row, "proof_id"), String(parts[5]))
        index += 1
    var literals = _loops(source)
    assert_equal(_rows(literals), 0)
    var lines = Path(source).read_text().split("\n")
    for number in [92, 98, 111, 119, 125, 163]:
        var line = String(String(lines[number - 1]).strip())
        assert_true(line.startswith("for "), line)


def test_spiral_edits_and_a_missing_file_omit_every_proof() raises:
    """A changed moment file, or a missing one, leaves the mask empty."""
    var module = "extensions/carla/spiral_moment_proof"
    var source = module + ".mojo"
    var root = mkdtemp(prefix="reviewed-moment-")
    try:
        _stage(root, source)
        var original = Path(source).read_text()
        var kept = original.split("\n")
        for number in [92, 98, 111, 119, 125, 163]:
            var line = String(kept[number - 1])
            var at = line.find("range(")
            if at < 0:
                raise Error("missing range on line " + String(number))
            var changed = List[String]()
            var index = 0
            while index < len(kept):
                if index == number - 1:
                    changed.append(String(line[byte=:at]) + "range(0):")
                else:
                    changed.append(String(kept[index]))
                index += 1
            var text = ""
            index = 0
            while index < len(changed):
                if index > 0:
                    text += "\n"
                text += changed[index]
                index += 1
            _rewrite(root, source, text)
            _empty(root, module)
        var shifts = List[String]()
        shifts.append(original + "\nfrom custom import range\n")
        shifts.append(
            original + "\ndef range(n: Int) -> List[Int]:\n    return []\n"
        )
        shifts.append(
            _once(
                original,
                "comptime for index in range(5):",
                "comptime for index in range(4):",
            )
        )
        shifts.append("\n" + original)
        for text in shifts:
            _rewrite(root, source, text)
            _empty(root, module)
        _ = run_program(["rm", "-f", root + "/" + source], 10.0)
        _empty(root, module)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_the_piece_count_proof_rejects_a_changed_guard() raises:
    """Line 97 stays a 1-to-64 range, and each guard edit drops the proof."""
    var module = "extensions/carla/spiral_moment_proof"
    var source = module + ".mojo"
    var doc = _reviews(".", module)
    var row = _row(doc, "97")
    assert_equal(_text_field(doc, row, "kind"), "reviewed-nonempty-range")
    assert_equal(_text_field(doc, row, "cardinality"), "1")
    assert_equal(_text_field(doc, row, "maximum_cardinality"), "64")
    assert_equal(_text_field(doc, row, "expression"), "range(pieces)")
    assert_equal(
        _text_field(doc, row, "proof_id"),
        "moment-admitted-piece-count-1-to-64",
    )
    assert_equal(_text_field(doc, row, "required"), "T")
    assert_equal(_text_field(doc, row, "impossible"), "F")
    var root = mkdtemp(prefix="reviewed-pieces-")
    try:
        _stage(root, source)
        var original = Path(source).read_text()
        var edits = List[String]()
        edits.append(
            _once(
                original,
                "pieces < 1 or pieces > 64",
                "pieces < 0 or pieces > 64",
            )
        )
        edits.append(
            _once(
                original,
                "pieces < 1 or pieces > 64",
                "pieces < 1 or pieces > 65",
            )
        )
        edits.append(_once(original, "pieces: Int,", "mut pieces: Int,"))
        edits.append(
            _once(
                original,
                "for piece in range(pieces):",
                "for piece in range(0):",
            )
        )
        edits.append(
            _once(
                original,
                "    var moments = Array",
                "    pieces = 0\n    var moments = Array",
            )
        )
        edits.append(original + "\nfrom custom import range\n")
        for text in edits:
            _rewrite(root, source, text)
            _empty(root, module)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_speed_lane_blend_and_hair_proofs_follow_their_files() raises:
    """Those four modules keep one reviewed row until a premise byte changes."""
    var speed = _reviews(".", "extensions/carla/speed_limits")
    var speed_row = _row(speed, "150")
    assert_equal(_rows(speed), 1)
    assert_equal(
        _text_field(speed, speed_row, "kind"), "reviewed-nonempty-iterator"
    )
    assert_equal(_text_field(speed, speed_row, "cardinality"), "1")
    assert_equal(_text_field(speed, speed_row, "maximum_cardinality"), "null")
    assert_equal(
        _text_field(speed, speed_row, "expression"), "number.as_bytes()"
    )
    assert_equal(
        _text_field(speed, speed_row, "proof_id"),
        "speed-number-nonempty-owned-byte-view",
    )
    var lane = _reviews(".", "extensions/carla/lane_distance")
    var lane_row = _row(lane, "50")
    assert_equal(_text_field(lane, lane_row, "kind"), "reviewed-nonempty-range")
    assert_equal(_text_field(lane, lane_row, "cardinality"), "1")
    assert_equal(_text_field(lane, lane_row, "maximum_cardinality"), "3")
    assert_equal(_text_field(lane, lane_row, "expression"), "range(axes)")
    assert_equal(lane.length(lane.at(lane_row, "dependency_sha256")), 6)
    var blend = _reviews(".", "extensions/carla/curve_interval")
    var blend_row = _row(blend, "592")
    assert_equal(_text_field(blend, blend_row, "kind"), "literal-list")
    assert_equal(_text_field(blend, blend_row, "cardinality"), "4")
    assert_equal(_text_field(blend, blend_row, "maximum_cardinality"), "4")
    assert_equal(
        _text_field(blend, blend_row, "expression"),
        "[actual_rate.low, actual_rate.high, one, two]",
    )
    var hair_module = "extensions/humanoid/skeleton/head/hair/strands"
    var hair = _reviews(".", hair_module)
    assert_equal(_rows(hair), 2)
    var ends = _row(hair, "229")
    var channels = _row(hair, "235")
    assert_equal(_text_field(hair, ends, "cardinality"), "2")
    assert_equal(_text_field(hair, channels, "cardinality"), "3")
    assert_equal(
        _text_field(hair, ends, "proof_id"), "hair-upload-two-endpoints"
    )
    assert_equal(
        hair.text(
            hair.at(hair.at(ends, "dependency_sha256"), hair_module + ".mojo")
        ),
        "81d104e6b65fe1539bf9c244330ae53b6d337ad081529cb0c5f7bcde27887db5",
    )
    assert_equal(_rows(_reviews(".", "unlisted/module")), 0)
    var root = mkdtemp(prefix="reviewed-other-")
    try:
        var speed_source = "extensions/carla/speed_limits.mojo"
        _stage(root, speed_source)
        var speed_text = Path(speed_source).read_text()
        var speed_edits = List[String]()
        speed_edits.append(
            _once(
                speed_text,
                "if number.byte_length() == 0:",
                "if number.byte_length() < 0:",
            )
        )
        speed_edits.append(
            _once(
                speed_text,
                "for byte in number.as_bytes():",
                "for byte in String().as_bytes():",
            )
        )
        speed_edits.append(
            _once(
                speed_text,
                "var number = String(text.strip())",
                "var number = String()",
            )
        )
        speed_edits.append(
            _once(
                speed_text,
                "if not _speed_decimal_syntax(number):",
                "if False:",
            )
        )
        speed_edits.append(
            _once(speed_text, "if byte >= 48 and byte <= 57:", "if byte >= 48:")
        )
        speed_edits.append(
            _once(
                speed_text, "if byte == 101 or byte == 69:", "if byte == 101:"
            )
        )
        speed_edits.append(
            _once(speed_text, "if byte >= 49:", "if byte >= 48:")
        )
        for text in speed_edits:
            _rewrite(root, speed_source, text)
            _empty(root, "extensions/carla/speed_limits")
        _ = run_program(["rm", "-f", root + "/" + speed_source], 10.0)
        _empty(root, "extensions/carla/speed_limits")
        var hair_source = hair_module + ".mojo"
        _stage(root, hair_source)
        var hair_text = Path(hair_source).read_text()
        _rewrite(root, hair_source, hair_text + "\n# unrelated change\n")
        _empty(root, hair_module)
        _rewrite(
            root,
            hair_source,
            _once(hair_text, "for end in range(2):", "for end in range(0):"),
        )
        _empty(root, hair_module)
        var blend_source = "extensions/carla/curve_interval.mojo"
        _stage(root, blend_source)
        _rewrite(
            root,
            blend_source,
            _once(
                Path(blend_source).read_text(),
                "[actual_rate.low, actual_rate.high, one, two]",
                "[one]",
            ),
        )
        _empty(root, "extensions/carla/curve_interval")
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def _rows_including(
    root: String, module: String, include: String
) raises -> Int:
    """Return the proof count when `include` is also checked for shadows."""
    var arguments = List[String]()
    arguments.append("reviews")
    arguments.append(root)
    arguments.append(module)
    if include.byte_length() > 0:
        arguments.append("--include")
        arguments.append(include)
    return _rows(PyJson.parse(_trim(_run(arguments))))


def test_lane_blend_and_hair_edits_and_std_shadows_omit_the_proof() raises:
    """A changed premise or a std shadow leaves the lane, blend, and hair proofs out.
    """
    var root = mkdtemp(prefix="reviewed-lane-")
    try:
        var lane_files = List[String]()
        lane_files.append("extensions/__init__.mojo")
        lane_files.append("extensions/carla/__init__.mojo")
        lane_files.append("extensions/carla/curve_distance.mojo")
        lane_files.append("extensions/carla/curve_interval.mojo")
        lane_files.append("extensions/carla/lane_distance.mojo")
        lane_files.append("tools/carla_lane_oracle/shared_helper_contracts.py")
        for name in lane_files:
            _stage(root, name)
        _stage(root, "extensions/humanoid/skeleton/head/hair/strands.mojo")
        assert_equal(_rows(_reviews(root, "extensions/carla/lane_distance")), 1)
        var edits = List[String]()
        edits.append(
            "extensions/carla/curve_distance.mojo|comptime assert axes >= 1 and"
            " axes <= 3|comptime assert axes >= 0 and axes <= 3"
        )
        edits.append(
            "extensions/carla/curve_distance.mojo|comptime assert axes >= 1 and"
            " axes <= 3|comptime assert axes >= 1 and axes <= 4"
        )
        edits.append(
            "extensions/carla/lane_distance.mojo|var bound ="
            " _distance_normalized_square[axes](point, query, scale)|var bound"
            " = _Interval(0.0, 0.0)"
        )
        edits.append(
            "extensions/carla/lane_distance.mojo|_normalized_square as"
            " _distance_normalized_square|_unchecked_square as"
            " _distance_normalized_square"
        )
        edits.append(
            "extensions/carla/lane_distance.mojo|var original ="
            " _normalized_square[axes](point, query, scale)|var original ="
            " _normalized_square[1](point, query, scale)"
        )
        edits.append(
            "extensions/carla/lane_distance.mojo|for axis in range(axes):|for"
            " axis in range(axes - 1):"
        )
        edits.append(
            "extensions/carla/curve_interval.mojo|[actual_rate.low,"
            " actual_rate.high, one, two]|List[Float64]()"
        )
        edits.append(
            "extensions/carla/curve_interval.mojo|var low: Float64|var low:"
            " Float32"
        )
        edits.append(
            "extensions/humanoid/skeleton/head/hair/strands.mojo|for channel in"
            " range(3):|for channel in range(0):"
        )
        for item in edits:
            var first = item.find("|")
            var rest = String(item[byte = first + 1 :])
            var second = rest.find("|")
            var name = String(item[byte=:first])
            var before = String(rest[byte=:second])
            var after = String(rest[byte = second + 1 :])
            var end = name.byte_length() - 5
            var module = String(name[byte=:end])
            if name == "extensions/carla/curve_distance.mojo":
                module = "extensions/carla/lane_distance"
            var original = Path(root + "/" + name).read_text()
            _rewrite(root, name, _once(original, before, after))
            _empty(root, module)
            _rewrite(root, name, original)
        var suffixes = List[String]()
        suffixes.append(
            "extensions/carla/lane_distance.mojo|\nfrom custom import range\n"
        )
        suffixes.append(
            "extensions/humanoid/skeleton/head/hair/strands.mojo|\ndef"
            " range(value: Int) -> List[Int]:\n    return []\n"
        )
        suffixes.append(
            "extensions/carla/curve_interval.mojo|\nfrom custom import List\n"
        )
        for item in suffixes:
            var bar = item.find("|")
            var name = String(item[byte=:bar])
            var suffix = String(item[byte = bar + 1 :])
            var end = name.byte_length() - 5
            var module = String(name[byte=:end])
            var original = Path(root + "/" + name).read_text()
            _rewrite(root, name, original + suffix)
            _empty(root, module)
            _rewrite(root, name, original)
        var hair = "extensions/humanoid/skeleton/head/hair/strands"
        var stage = root + "/coverage/build"
        var made = run_program(["mkdir", "-p", stage], 10.0)
        if made.status != 0:
            raise Error(made.output)
        for place in [root, stage]:
            for shadow in ["std.mojo", "std.mojopkg", "std.unknown"]:
                var path = place + "/" + shadow
                Path(path).write_text("unreviewed range provider")
                assert_equal(_rows_including(root, hair, stage), 0)
                _ = run_program(["rm", "-f", path], 10.0)
        assert_equal(_rows_including(root, hair, stage), 2)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def main() raises:
    """Build the seal, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_loop_seal"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
