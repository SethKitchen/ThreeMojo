# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The strand-cap proof keeps one reviewed pair and refuses a shadowed root."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.coverage_loop_seal import _masked_manifest, strand_cap_line


def _five(
    init_objects: String,
    init_renderers: String,
    renderer: String,
    segments: String,
    witness: String,
) -> List[String]:
    """Return one strand-cap digest list."""
    var hashes = List[String]()
    hashes.append(init_objects)
    hashes.append(init_renderers)
    hashes.append(renderer)
    hashes.append(segments)
    hashes.append(witness)
    return hashes^


def test_historical_pairs_reject_a_mixture() raises:
    """Each reviewed endpoint stays paired, and a mixed pair has no line."""
    var init = (
        "5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479"
    )
    var witness = (
        "8f768e04ecaebdb132cf359819be03cb039d5a546b823674c22ac06a1b790362"
    )
    var old_segments = (
        "5680f188d71c88465be6f7d8173858221a57525663fb4c75d95721fcc2658e79"
    )
    var new_segments = (
        "fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021"
    )
    var first = (
        "ad8d3a26292683ba744d20fa05f13491e31019540774002809bfad8ba3ae6bf5"
    )
    var second = (
        "08ce4d257874c1107305cc1abf45ec4ebd89a9b183902974085d507974410c45"
    )
    var paired = (
        "2491b99a982cd4bc49b3573d3c6db8313bfdd47372e693e932c03c27d0ff127d"
    )
    var camera = (
        "df552b5bc14d6cc5a0ef4cf919afaf66da620f431b0d4f5bb9c3a61538cb2b84"
    )
    var formatted = (
        "990d94c815315c910b12c1b126c076183fc35cdeb9f64a26d1f7e574f424bccd"
    )
    var splat = (
        "c08275ccfea2f32dd84dc5ad54205052f6dfd216104836c858ff259224426332"
    )
    var current = (
        "7fcdce220f3420c7a7739c0419d8af1087a06f79343a9f86cac4f8313fa6fa18"
    )
    assert_equal(
        strand_cap_line(_five(init, init, first, old_segments, witness)), 3757
    )
    assert_equal(
        strand_cap_line(_five(init, init, second, old_segments, witness)), 3886
    )
    assert_equal(
        strand_cap_line(_five(init, init, paired, new_segments, witness)), 4047
    )
    assert_equal(
        strand_cap_line(_five(init, init, camera, new_segments, witness)), 4047
    )
    assert_equal(
        strand_cap_line(_five(init, init, formatted, new_segments, witness)),
        4049,
    )
    assert_equal(
        strand_cap_line(_five(init, init, splat, new_segments, witness)), 4049
    )
    var guarded = (
        "2557d496f1dc49c204314d389bd105c9eaaab4c7762920b7b0d5f97613d4c3cd"
    )
    assert_equal(
        strand_cap_line(_five(init, init, current, guarded, witness)), 4056
    )
    assert_equal(
        strand_cap_line(_five(init, init, current, new_segments, witness)), -1
    )
    assert_equal(
        strand_cap_line(_five(init, init, formatted, old_segments, witness)),
        -1,
    )
    assert_equal(
        strand_cap_line(_five(init, init, current, old_segments, witness)), -1
    )
    assert_equal(
        strand_cap_line(_five(init, init, first, new_segments, witness)), -1
    )
    assert_equal(
        sha256_hex(Path("renderers/renderer.mojo").read_bytes()), current
    )


def _sources() -> List[String]:
    """Return the five strand-cap inputs."""
    var names = List[String]()
    names.append("objects/__init__.mojo")
    names.append("renderers/__init__.mojo")
    names.append("renderers/renderer.mojo")
    names.append("objects/line_segments2.mojo")
    names.append("tests/test_small_loop_witnesses.mojo")
    return names^


def _copy(root: String, name: String) raises:
    """Copy one repository file into `root`."""
    var dest = root + "/" + name
    var slash = dest.rfind("/")
    var parent = String(dest[byte=:slash])
    var made = run_program(["mkdir", "-p", parent], 10.0)
    if made.status != 0:
        raise Error(made.output)
    Path(dest).write_bytes(Path(name).read_bytes())


def _stage() raises -> String:
    """Copy the strand-cap inputs into a fresh root."""
    var root = mkdtemp(prefix="strand-cap-")
    for name in _sources():
        _copy(root, name)
    return root


def _reviews(root: String, extra: String) raises -> String:
    """Return the renderer reviews for `root`."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("coverage_loop_seal")
    command.append("reviews")
    command.append(root)
    command.append("renderers/renderer")
    if extra.byte_length() > 0:
        command.append("--include")
        command.append(extra)
    var ran = run_program(command, 30.0, merge_errors=False)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    return ran.output


def _empty(root: String) raises:
    """Require the renderer proof to be absent."""
    var text = _reviews(root, "")
    assert_true(text.find("[]") >= 0, text)
    assert_true(text.find("4056") < 0, text)


def _once(text: String, before: String, after: String) raises -> String:
    """Replace the first `before`."""
    var at = text.find(before)
    if at < 0:
        raise Error("missing premise " + before)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def test_the_current_pair_keeps_the_runtime_true_edge() raises:
    """A clean copy admits line 4056, and another module admits nothing."""
    var root = _stage()
    try:
        var text = _reviews(root, "")
        assert_true(text.find('"line":4056') >= 0, text)
        assert_true(text.find('"minimum_cardinality":2') >= 0, text)
        assert_true(text.find('"maximum_cardinality":64') >= 0, text)
        assert_true(text.find('"required":"T"') >= 0, text)
        assert_true(text.find('"impossible":"F"') >= 0, text)
        var other = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "reviews",
                root,
                "other/renderer",
            ],
            30.0,
            merge_errors=False,
        )
        if other.status != 0:
            raise Error(other.errors)
        assert_true(other.output.find("[]") >= 0)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_a_symlink_or_missing_input_revokes_the_cap() raises:
    """A symlinked producer, or any missing input, leaves the proof out."""
    var root = _stage()
    try:
        var producer = root + "/objects/line_segments2.mojo"
        var raw = Path(producer).read_bytes()
        Path(root + "/retained.mojo").write_bytes(raw)
        _ = run_program(["rm", producer], 10.0)
        _ = run_program(["ln", "-s", root + "/retained.mojo", producer], 10.0)
        _empty(root)
        _ = run_program(["rm", producer], 10.0)
        Path(producer).write_bytes(raw)
        for name in _sources():
            var path = root + "/" + name
            var saved = Path(path).read_bytes()
            _ = run_program(["rm", path], 10.0)
            _empty(root)
            Path(path).write_bytes(saved)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_cap_edits_and_shadows_revoke_the_proof() raises:
    """A changed premise, a std shadow, or an alternate module removes the proof.
    """
    var root = _stage()
    try:
        var renderer = root + "/renderers/renderer.mojo"
        var original = Path(renderer).read_text()
        var start = original.find("def _emit_strand_cap(")
        if start < 0:
            raise Error("missing cap function")
        var rest = String(original[byte = start + 1 :])
        var end = rest.find("\ndef ")
        if end < 0:
            raise Error("missing following function")
        var body = String(original[byte = start : start + 1 + end])
        for pair in [
            "var steps = cap_steps(|var steps = 0 # cap_steps(",
            "for step in range(1, steps + 1):|for step in range(1, steps):",
            (
                "    for step in range(1, steps + 1):|    steps = 0\n    for"
                " step in range(1, steps + 1):"
            ),
        ]:
            var bar = pair.find("|")
            var before = String(pair[byte=:bar])
            var after = String(pair[byte = bar + 1 :])
            if body.find(before) < 0:
                raise Error("missing premise " + before)
            var changed = (
                String(original[byte=:start])
                + _once(body, before, after)
                + String(original[byte = start + body.byte_length() :])
            )
            Path(renderer).write_text(changed)
            _empty(root)
            Path(renderer).write_text(original)
        Path(renderer).write_text(
            original
            + "\n# An unrelated source edit still revokes the exact endpoint.\n"
        )
        _empty(root)
        Path(renderer).write_text(original)
        var cases = List[String]()
        cases.append(
            "objects/line_segments2.mojo|MIN_CAP_STEPS = 2|MIN_CAP_STEPS = 0"
        )
        cases.append(
            "objects/line_segments2.mojo|MAX_CAP_STEPS = 64|MAX_CAP_STEPS = 0"
        )
        cases.append(
            "objects/line_segments2.mojo|var wanted = ceil(|var wanted ="
            " Float32(0) # ceil("
        )
        cases.append(
            "renderers/renderer.mojo|for step in range(1, steps + 1):|for step"
            " in range(1, steps):"
        )
        cases.append(
            "renderers/renderer.mojo|    cap_steps,|    cap_steps as"
            " alternate_cap_steps,"
        )
        cases.append(
            "tests/test_small_loop_witnesses.mojo|count >= 2 and count <="
            " 64|count >= 0"
        )
        for item in cases:
            var first = item.find("|")
            var second = String(item[byte = first + 1 :]).find("|")
            var name = String(item[byte=:first])
            var before = String(item[byte = first + 1 : first + 1 + second])
            var after = String(item[byte = first + 1 + second + 1 :])
            var path = root + "/" + name
            var text = Path(path).read_text()
            Path(path).write_text(_once(text, before, after))
            _empty(root)
            Path(path).write_text(text)
        Path(root + "/std.mojo").write_text("unreviewed shadow")
        _empty(root)
        _ = run_program(["rm", root + "/std.mojo"], 10.0)
        var stage = root + "/coverage/build"
        _ = run_program(["mkdir", "-p", stage], 10.0)
        Path(stage + "/std.mojo").write_text("unreviewed shadow")
        var included = _reviews(root, stage)
        assert_true(included.find("4056") < 0, included)
        _ = run_program(["rm", stage + "/std.mojo"], 10.0)
        var restored = _reviews(root, stage)
        assert_true(restored.find('"line":4056') >= 0, restored)
        var shadow = root + "/objects.mojo"
        Path(shadow).write_text("unreviewed module")
        _empty(root)
        _ = run_program(["rm", shadow], 10.0)
        var hidden = root + "/tests/objects"
        _ = run_program(["mkdir", "-p", hidden], 10.0)
        Path(hidden + "/line_segments2.mojo").write_text("unreviewed shadow")
        _empty(root)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_the_mask_replaces_only_the_cap_branch() raises:
    """Line 4049 becomes an R record, and the other branches stay B records."""
    var raw = (
        "L renderers/renderer 4046\nB renderers/renderer 4049\nB"
        " renderers/renderer 4048\nB renderers/renderer 3757\nB"
        " renderers/renderer 3810\n"
    )
    var doc = PyJson()
    var envelope = doc.new_dict()
    doc.root = envelope
    var receipt = doc.new_dict()
    doc.set(
        envelope,
        "sha256",
        doc.new_str(
            "0000000000000000000000000000000000000000000000000000000000000000"
        ),
    )
    var raw_bytes = List[UInt8]()
    for byte in raw.as_bytes():
        raw_bytes.append(byte)
    doc.set(
        receipt, "manifest_sha256", doc.new_str(sha256_hex(Span(raw_bytes)))
    )
    var proofs = doc.new_list()
    var proof = doc.new_dict()
    doc.set(proof, "module", doc.new_str("renderers/renderer"))
    doc.set(proof, "line", doc.new_int(4049))
    doc.set(proof, "required", doc.new_str("T"))
    doc.set(proof, "kind", doc.new_str("reviewed-nonempty-range"))
    doc.set(proof, "cardinality", doc.new_int(1))
    doc.append(proofs, proof)
    doc.set(receipt, "proofs", proofs)
    doc.set(envelope, "receipt", receipt)
    var masked = _masked_manifest(raw_bytes, doc)
    assert_true(
        masked.find("R renderers/renderer 4049 T reviewed-nonempty-range 1\n")
        >= 0,
        masked,
    )
    assert_true(masked.find("L renderers/renderer 4046\n") >= 0, masked)
    assert_true(masked.find("B renderers/renderer 4048\n") >= 0, masked)
    assert_true(masked.find("B renderers/renderer 3757\n") >= 0, masked)
    assert_true(masked.find("B renderers/renderer 3810\n") >= 0, masked)
    assert_true(masked.find("R renderers/renderer 3757 ") < 0, masked)
    assert_true(masked.find("R renderers/renderer 3810 ") < 0, masked)
    var newlines = 0
    for byte in masked.as_bytes():
        if byte == 10:
            newlines += 1
    assert_equal(newlines, 6)


def main() raises:
    """Build the seal, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_loop_seal"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
