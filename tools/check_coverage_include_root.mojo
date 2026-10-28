# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the generated include-root loop inventory.

    check_coverage_include_root --mojo PATH --stage PATH --compiler TEXT --flags TEXT

The program instruments the four lane modules, checks the six closed loop
proofs, and rejects a changed passthrough file. The profiled receipt owner
stays in `tools/check_coverage_loop_proofs.py`. The maintained generation
keeps a 1200-second cap. That cap is separate from the native alarm.
"""

from std.os.path import exists
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PyJson
from tools._sha256 import sha256_hex
from tools.check_coverage_loop_fixture import _fail, _run, _tool
from tools.coverage_loop_seal import constant_loops


def _rows(text: String) -> List[String]:
    """Return lines without break characters, as `str.splitlines` does.

    Args:
        text: The manifest text.

    Returns:
        One string per line. A trailing break does not add an empty line.
    """
    var out = List[String]()
    var start = 0
    var count = text.byte_length()
    var raw = text.as_bytes()
    while start < count:
        var end = start
        while end < count and raw[end] != 10:
            end += 1
        out.append(String(text[byte=start:end]))
        if end >= count:
            break
        start = end + 1
        if start == count:
            break
    return out^


def _fields(row: String) -> List[String]:
    """Split one manifest row on whitespace.

    Args:
        row: One manifest line.

    Returns:
        The non-empty fields.
    """
    var out = List[String]()
    var current = String()
    var started = False
    for byte in row.as_bytes():
        var space = byte == 32 or byte == 9
        if space:
            if started:
                out.append(current)
                current = String()
                started = False
        else:
            current += chr(Int(byte))
            started = True
    if started:
        out.append(current)
    return out^


def _exact(text: String, wanted: String) -> Bool:
    """Return whether one full line equals `wanted`.

    Args:
        text: The file text.
        wanted: The line, without a break.

    Returns:
        True when a line matches.
    """
    for row in _rows(text):
        if row == wanted:
            return True
    return False


def _digest(path: String) raises -> String:
    """Return the SHA-256 hex digest of one file.

    Args:
        path: The file.

    Returns:
        The digest.

    Raises:
        Error: The file cannot be read.
    """
    return sha256_hex(Span(Path(path).read_bytes()))


def _same(left: String, right: String) raises -> Bool:
    """Return whether two files have the same bytes.

    Args:
        left: The first file.
        right: The second file.

    Returns:
        True when the digests match.

    Raises:
        Error: A file cannot be read.
    """
    return _digest(left) == _digest(right)


def _census(path: String, label: String) raises:
    """Require the literal-loop census of one module.

    Args:
        path: The source file.
        label: The failure name. `map` requires the two literal loops.

    Raises:
        Error: The census differs from the reviewed set.
    """
    var found = constant_loops(Path(path).read_text())
    if label != "map":
        if len(found) != 0:
            _fail("Unexpected literal proof in " + label)
        return
    if len(found) != 2:
        _fail("Ordinary proof census differs from the reviewed exact set")
    var seen_short = False
    var seen_long = False
    var index = 0
    while index < len(found):
        var line = found[index][0]
        var kind = found[index][1]
        var count = found[index][2]
        var required = found[index][3]
        var impossible = found[index][4]
        var expression = found[index][5]
        var fits = False
        if line == "2170" and count == "3" and expression == "range (3 )":
            fits = not seen_short
            seen_short = True
        elif line == "2201" and count == "8" and expression == "range (8 )":
            fits = not seen_long
            seen_long = True
        if (
            not fits
            or kind != "literal-range"
            or required != "T"
            or impossible != "F"
        ):
            _fail("Ordinary proof census differs from the reviewed exact set")
        index += 1
    if not seen_short or not seen_long:
        _fail("Ordinary proof census differs from the reviewed exact set")


def _proof_text(doc: PyJson, row: Int, key: String) raises -> String:
    """Return one proof field as text.

    Args:
        doc: The receipt document.
        row: The proof object.
        key: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(row, key))


def qualify_include_root(
    mojo: String, stage: String, compiler: String, flags: String
) raises:
    """Instrument the lane modules and check the six closed loop proofs.

    Args:
        mojo: The Mojo compiler.
        stage: A path that must not exist yet.
        compiler: The compiler version recorded in the receipt.
        flags: The compiler flags recorded in the receipt.

    Raises:
        Error: The inventory, the mask, or a stage mutation check fails.
    """
    if exists(stage):
        _fail("Generated include regression needs a fresh stage")
    var covered = (
        "extensions/carla/curve_rounded_arc.mojo"
        " extensions/carla/curve_rounded_line.mojo"
        " extensions/carla/curve_sample_dispatch.mojo"
        " extensions/carla/map.mojo"
    )
    var instrument = List[String]()
    instrument.append("make")
    instrument.append("--no-print-directory")
    instrument.append("coverage-instrument")
    instrument.append("COV_DIR=" + stage)
    instrument.append("MOJO=" + mojo)
    instrument.append("TOOLCHAIN=" + compiler)
    instrument.append("MOJOFLAGS=" + flags)
    instrument.append("COVERED=" + covered)
    instrument.append(
        "COVERAGE_TESTS=tests/test_carla_lane_geometry_guard_controls.mojo"
    )
    _ = _run(instrument, 1200.0, "")
    var passed = List[String]()
    passed.append("extensions/animals/anatomy/render.mojo")
    passed.append("extensions/building/views/render.mojo")
    for name in passed:
        if not _same(stage + "/" + name, name):
            _fail("Maintained nested-render passthrough is missing")
    var pins = List[String]()
    pins.append(
        "f17bf9a6a744971ea6e792a24b27d6157691e70d50c438880abcf88db2a9123d"
    )
    pins.append(
        "22b70ec9febc6f3d21a8a4d9f1a74650d676e34782fab2812004a1a3aadeb698"
    )
    pins.append(
        "04ff45c12cefcb4dbe3a7b136e77b6baaf02cff52325f6599d99250f820fdebb"
    )
    pins.append(
        "d31186a9f02b328dc644194a1246a0b71ff7bc4c68f8556b8b18e3a623bb90cb"
    )
    var sources = List[String]()
    sources.append("extensions/carla/curve_rounded_arc.mojo")
    sources.append("extensions/carla/curve_rounded_line.mojo")
    sources.append("extensions/carla/curve_sample_dispatch.mojo")
    sources.append("extensions/carla/map.mojo")
    var pin = 0
    for name in sources:
        if _digest(name) != pins[pin]:
            _fail("Current integration source endpoint changed")
        pin += 1
    var names = List[String]()
    names.append("extensions/carla/curve_rounded_arc")
    names.append("extensions/carla/curve_rounded_line")
    names.append("extensions/carla/curve_sample_dispatch")
    names.append("extensions/carla/map")
    names.append("extensions/carla/map")
    names.append("extensions/carla/map")
    var proof_lines = List[String]()
    proof_lines.append("235")
    proof_lines.append("93")
    proof_lines.append("126")
    proof_lines.append("5025")
    proof_lines.append("2170")
    proof_lines.append("2201")
    var ids = List[String]()
    ids.append("rounded-arc-validated-lane-list")
    ids.append("rounded-line-validated-lane-list")
    ids.append("sample-dispatch-count-1-or-2")
    ids.append("construction-geometry-boundary-list")
    ids.append("")
    ids.append("")
    var expressions = List[String]()
    expressions.append("range(len(lanes))")
    expressions.append("range(len(lanes))")
    expressions.append("range(count)")
    expressions.append("boundaries")
    expressions.append("range (3 )")
    expressions.append("range (8 )")
    var kinds = List[String]()
    kinds.append("reviewed-nonempty-range")
    kinds.append("reviewed-nonempty-range")
    kinds.append("reviewed-nonempty-range")
    kinds.append("reviewed-nonempty-iterator")
    kinds.append("literal-range")
    kinds.append("literal-range")
    var counts = List[String]()
    counts.append("1")
    counts.append("1")
    counts.append("1")
    counts.append("1")
    counts.append("3")
    counts.append("8")
    var maximums = List[String]()
    maximums.append("")
    maximums.append("")
    maximums.append("2")
    maximums.append("")
    maximums.append("")
    maximums.append("")
    var doc = PyJson.parse(Path(stage + "/loop-proofs.json").read_text())
    var receipt = doc.at(doc.root, "receipt")
    var proofs = doc.at(receipt, "proofs")
    if doc.length(proofs) != 6:
        _fail("Closed six-row proof inventory differs")
    var proof_at = List[Int]()
    var slot = 0
    while slot < 6:
        proof_at.append(-1)
        slot += 1
    var index = 0
    while index < doc.length(proofs):
        var row = doc.item(proofs, index)
        var module = _proof_text(doc, row, "module")
        var line = _proof_text(doc, row, "line")
        var found = -1
        slot = 0
        while slot < 6:
            if names[slot] == module and proof_lines[slot] == line:
                if found >= 0 or proof_at[slot] >= 0:
                    _fail("Closed six-row proof inventory differs")
                found = slot
            slot += 1
        if found < 0:
            _fail("Closed six-row proof inventory differs")
        proof_at[found] = index
        index += 1
    slot = 0
    while slot < 6:
        var row = doc.item(proofs, proof_at[slot])
        var reviewed = ids[slot].byte_length() > 0
        var proof_id = doc.find(row, "proof_id")
        if reviewed:
            if proof_id == MISSING or doc.text(proof_id) != ids[slot]:
                _fail("Reviewed and ordinary proof inventories differ")
        elif proof_id != MISSING:
            _fail("Reviewed and ordinary proof inventories differ")
        var source_pin = pins[3] if slot >= 3 else pins[slot]
        var maximum = doc.find(row, "maximum_cardinality")
        var maximum_ok: Bool
        if reviewed:
            if maximum == MISSING:
                maximum_ok = False
            elif maximums[slot].byte_length() == 0:
                maximum_ok = doc.is_none(maximum)
            else:
                maximum_ok = (
                    not doc.is_none(maximum)
                    and doc.text(maximum) == maximums[slot]
                )
        else:
            maximum_ok = maximum == MISSING
        if (
            not maximum_ok
            or _proof_text(doc, row, "expression") != expressions[slot]
            or _proof_text(doc, row, "kind") != kinds[slot]
            or _proof_text(doc, row, "cardinality") != counts[slot]
            or _proof_text(doc, row, "required") != "T"
            or _proof_text(doc, row, "impossible") != "F"
            or _proof_text(doc, row, "source_sha256") != source_pin
        ):
            if reviewed:
                _fail("Current proof contract or required True outcome differs")
            _fail("Ordinary literal-range proof contract differs")
        if slot == 3:
            var minimum = doc.find(row, "minimum_cardinality")
            if minimum == MISSING or doc.text(minimum) != "1":
                _fail("Constructor boundary minimum changed")
        elif not reviewed:
            if (
                doc.find(row, "minimum_cardinality") != MISSING
                or doc.find(row, "dependency_sha256") != MISSING
                or doc.length(row) != 8
            ):
                _fail("Ordinary literal-range proof contract differs")
        slot += 1
    _census("extensions/carla/map.mojo", "map")
    _census(
        "extensions/carla/curve_rounded_arc.mojo",
        "extensions/carla/curve_rounded_arc.mojo",
    )
    _census(
        "extensions/carla/curve_rounded_line.mojo",
        "extensions/carla/curve_rounded_line.mojo",
    )
    _census(
        "extensions/carla/curve_sample_dispatch.mojo",
        "extensions/carla/curve_sample_dispatch.mojo",
    )
    var original = Path(stage + "/manifest.txt").read_text()
    var modules = List[String]()
    for row in _rows(original):
        var fields = _fields(row)
        if len(fields) == 0:
            continue
        var mark = fields[0]
        if mark == "L" or mark == "B" or mark == "C" or mark == "M":
            var name = fields[1]
            var known = False
            for item in modules:
                if item == name:
                    known = True
            if not known:
                modules.append(name)
    var expected_modules = List[String]()
    expected_modules.append("extensions/carla/curve_rounded_arc")
    expected_modules.append("extensions/carla/curve_rounded_line")
    expected_modules.append("extensions/carla/curve_sample_dispatch")
    expected_modules.append("extensions/carla/map")
    if len(modules) != len(expected_modules):
        _fail("Original selected-module denominator differs")
    for name in expected_modules:
        var known = False
        for item in modules:
            if item == name:
                known = True
        if not known:
            _fail("Original selected-module denominator differs")
    var excluded = List[Int]()
    excluded.append(1223)
    excluded.append(1766)
    excluded.append(2205)
    excluded.append(3003)
    excluded.append(3010)
    excluded.append(3032)
    excluded.append(3104)
    excluded.append(3109)
    excluded.append(3118)
    excluded.append(3127)
    excluded.append(4908)
    excluded.append(5333)
    excluded.append(5353)
    for line in excluded:
        var label = "B extensions/carla/map " + String(line)
        if _exact(original, label):
            _fail("Existing Map branch exclusion changed")
    var masked_path = stage + "/mojo-masked-manifest.txt"
    var mask = _tool(mojo, "coverage_loop_seal")
    mask.append("mask")
    mask.append("--build")
    mask.append(stage)
    mask.append("--output")
    mask.append(masked_path)
    _ = _run(mask, 120.0, "")
    var masked = Path(masked_path).read_text()
    var built = (
        "P constant-loops-v2 " + doc.text(doc.at(doc.root, "sha256")) + "\n"
    )
    var used = List[Bool]()
    slot = 0
    while slot < 6:
        used.append(False)
        slot += 1
    for row in _rows(original):
        var fields = _fields(row)
        var replaced = False
        if len(fields) >= 3 and fields[0] == "B":
            slot = 0
            while slot < 6:
                if fields[1] == names[slot] and fields[2] == proof_lines[slot]:
                    var proof = doc.item(proofs, proof_at[slot])
                    built += (
                        "R "
                        + names[slot]
                        + " "
                        + proof_lines[slot]
                        + " "
                        + _proof_text(doc, proof, "required")
                        + " "
                        + _proof_text(doc, proof, "kind")
                        + " "
                        + _proof_text(doc, proof, "cardinality")
                        + "\n"
                    )
                    used[slot] = True
                    replaced = True
                slot += 1
        if not replaced:
            built += row + "\n"
    slot = 0
    while slot < 6:
        if not used[slot]:
            _fail("Proof does not identify an original branch")
        var label = "B " + names[slot] + " " + proof_lines[slot]
        if not _exact(original, label):
            _fail("Missing original branch")
        if not _exact(masked, "L " + names[slot] + " " + proof_lines[slot]):
            _fail("Original line was removed")
        var proof = doc.item(proofs, proof_at[slot])
        if (
            _proof_text(doc, proof, "required") != "T"
            or _proof_text(doc, proof, "impossible") != "F"
        ):
            _fail("Current theorem weakened its required true outcome")
        slot += 1
    if masked != built:
        _fail("An unrelated manifest row or its order changed")
    var mutations = _tool(mojo, "check_coverage_loop_fixture")
    mutations.append("--mojo")
    mutations.append(mojo)
    mutations.append("--mutations")
    mutations.append(stage)
    _ = _run(mutations, 1200.0, "")
    print(
        "PASS: generated include-root keeps six closed loop proofs;"
        " changed passthrough bytes and a new provider are rejected"
    )


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: check_coverage_include_root --mojo PATH --stage PATH"
            " --compiler TEXT --flags TEXT"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one fresh generated include-root stage."""
    var mojo = String("")
    var stage = String("")
    var compiler = String("")
    var flags = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--mojo"
            or word == "--stage"
            or word == "--compiler"
            or word == "--flags"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--mojo":
                mojo = value
            elif word == "--stage":
                stage = value
            elif word == "--compiler":
                compiler = value
            else:
                flags = value
            index += 2
            continue
        _usage()
    if (
        mojo.byte_length() == 0
        or stage.byte_length() == 0
        or compiler.byte_length() == 0
        or flags.byte_length() == 0
    ):
        _usage()
    try:
        qualify_include_root(mojo, stage, compiler, flags)
    except error:
        print("check_coverage_include_root: " + String(error), file=stderr)
        exit(1)
