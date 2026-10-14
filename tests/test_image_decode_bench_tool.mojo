# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The #505 image-decode fixtures and benchmark runner keep their contracts.

These checks do not compile or run Mojo programs. The supervisor checks
compile the small C helper with `cc`, or use the one that
`THREEMOJO_RUSAGE_HELPER` names. Without either, they return early.
"""

from std.os.path import exists
from std.pathlib import Path
from std.sys import CompilationTarget
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from bench.image_decode_bench import (
    RUSAGE_MARKER,
    Measurer,
    NativeMeasurer,
    RunOptions,
    check_fields,
    check_resources,
    environment_value,
    here,
    measure,
    measurement_row,
    parse_output,
    parse_rusage,
    read_json,
    run,
    sha,
    summarize,
    write_json,
)
from bench.image_decode_fixture import (
    dimensions,
    fnv64,
    generate,
    png,
    rgba,
)
from render.png import decode
from tools._json_value import JsonTree
from tools._process import run_program
from tools._zlib import crc32


# --- helpers -------------------------------------------------------------------


def _raises_with(message: String, error: Error) -> Bool:
    """Return whether an error's text holds a message."""
    return message in String(error)


def _unit() -> String:
    """Return this platform's `ru_maxrss` unit."""
    comptime if CompilationTarget.is_macos():
        return "bytes"
    else:
        return "KiB"


def _multiplier() -> Int:
    """Return the bytes in one `ru_maxrss` unit."""
    return 1024 if _unit() == "KiB" else 1


def _helper() raises -> String:
    """Return the RSS supervisor: the named one, or a fresh build.

    Returns:
        The helper path, or empty when no C compiler is available.
    """
    var named = environment_value("THREEMOJO_RUSAGE_HELPER")
    if named and named.value().byte_length() > 0:
        return named.value()
    var folder = mkdtemp(prefix="image-decode-helper-")
    var binary = folder + "/image_decode_rusage"
    try:
        var result = run_program(
            [
                String("cc"),
                "-O2",
                "-std=c11",
                "-Wall",
                "-Wextra",
                "-Werror",
                here() + "/image_decode_rusage.c",
                "-o",
                binary,
            ],
            60,
        )
        if result.status != 0:
            return String()
    except:
        return String()
    return binary


def _lines(path: String) raises -> Int:
    """Return the number of lines in a file."""
    var count = 0
    for byte in Path(path).read_bytes():
        if byte == 10:
            count += 1
    return count


def _write_build(
    root: String, helper: String, native: String, labels: List[String]
) raises -> String:
    """Write a complete build record for a helper and one native binary."""
    var tree = JsonTree()
    var record = tree.object()
    tree.set(record, "status", tree.string("complete"))
    var helper_record = tree.object()
    tree.set(helper_record, "binary", tree.string(helper))
    tree.set(helper_record, "binary_sha256", tree.string(sha(helper)))
    tree.set(record, "rusage_helper", helper_record)
    var variants = tree.object()
    for label in labels:
        var binary = native if native.byte_length() > 0 else root + "/" + label
        if native.byte_length() == 0:
            Path(binary).write_text("native recorded bytes")
        var info = tree.object()
        tree.set(info, "binary", tree.string(binary))
        tree.set(info, "binary_sha256", tree.string(sha(binary)))
        tree.set(variants, label, info)
    tree.set(record, "variants", variants)
    var path = root + "/build.json"
    write_json(tree, record, path)
    return path


def _expected(fixtures: String) raises -> List[String]:
    """Return the first dataset's oracle as `key value` pairs."""
    var tree = JsonTree()
    var manifest = read_json(tree, fixtures + "/fixtures.json")
    var expected = tree.get(
        tree.at(tree.get(manifest, "datasets"), 0), "expected"
    )
    var pairs = List[String]()
    for key in tree.keys(expected):
        pairs.append(key + " " + tree.text(tree.get(expected, key)))
    return pairs^


struct _NeverMeasure(Measurer):
    """A measurer that counts calls; no launch must happen."""

    var calls: Int

    def __init__(out self):
        self.calls = 0

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        timeout: Float64,
        directory: String,
        helper: String,
    ) raises -> Int:
        self.calls += 1
        return tree.object()


struct _Scripted(Measurer):
    """A measurer that returns recorded rows in order."""

    var rows: List[String]
    var calls: Int

    def __init__(out self, var rows: List[String]):
        self.rows = rows^
        self.calls = 0

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        timeout: Float64,
        directory: String,
        helper: String,
    ) raises -> Int:
        var text = self.rows[self.calls]
        self.calls += 1
        return tree.parse(text)


def _prepare(root: String) raises -> RunOptions:
    """Write two-image fixtures and a two-variant build of placeholders."""
    _ = generate(root + "/fixtures", 2, 4, [String("uniform_tiny")])
    var helper = root + "/helper-placeholder"
    Path(helper).write_text("helper recorded bytes")
    var build = _write_build(
        root, helper, "", [String("baseline"), String("dynamic")]
    )
    var options = RunOptions(build, root + "/fixtures", root + "/results")
    options.repetitions = 1
    options.workers = [1]
    options.apis = [String("gltf")]
    options.timeout = 5
    return options^


def _measured_row(
    fixtures: String, field: String = "", value: String = ""
) raises -> String:
    """Return a successful row whose native line has one changed field."""
    var pairs = _expected(fixtures)
    var line = String("result")
    var names: List[String] = []
    var values: List[String] = []
    for pair in pairs:
        var at = pair.find(" ")
        names.append(String(pair[byte=:at]))
        values.append(String(pair[byte = at + 1 :]))
    for extra in [
        ("api", "gltf"),
        ("workers", "1"),
        ("runtime_parallelism", "4"),
        ("load_ns", "100"),
        ("all_fnv64", "17"),
        ("shape_fnv64", "19"),
    ]:
        names.append(String(extra[0]))
        values.append(String(extra[1]))
    for i in range(len(names)):
        var text = value if names[i] == field else values[i]
        line += " " + names[i] + " " + text
    var tree = JsonTree()
    var row = tree.object()
    tree.set(row, "exit_code", tree.integer(0))
    tree.set(row, "timed_out", tree.boolean(False))
    tree.set(row, "measurement_error", tree.null())
    tree.set(row, "stdout", tree.string(line + "\n"))
    tree.set(row, "stderr", tree.string(""))
    tree.set(row, "peak_rss_bytes", tree.integer(100))
    return tree.dumps(row)


def _marker(fields: String) -> String:
    """Return a supervisor marker line with the given JSON members."""
    return RUSAGE_MARKER + "{" + fields + "}\n"


def _usage(exit_status: Int, signal: Int) -> String:
    """Return a complete supervisor marker line."""
    var m = _multiplier()
    return _marker(
        '"schema": 1, "rss_unit": "'
        + _unit()
        + '", "maxrss_raw": 7, "peak_rss_bytes": '
        + String(7 * m)
        + ', "user_seconds": 0, "system_seconds": 0, "minor_faults": 0,'
        ' "major_faults": 0, "voluntary_context_switches": 0,'
        ' "involuntary_context_switches": 0, "native_exit_status": '
        + String(exit_status)
        + ', "native_signal": '
        + String(signal)
        + ', "exec_errno": 0'
    )


def _sh(script: String) -> List[String]:
    """Return a command that runs a shell script."""
    return [String("/bin/sh"), "-c", script]


# --- fixtures ------------------------------------------------------------------


def test_fnv_vectors() raises:
    var empty = List[UInt8]()
    assert_true(fnv64(Span(empty)) == UInt64(14695981039346656037))
    var a: List[UInt8] = [97]
    assert_true(fnv64(Span(a)) == UInt64(12638187200555641996))


def test_adversarial_jobs() raises:
    var sizes = dimensions("stride_skew", 16, 4)
    var large = List[Int]()
    for i in range(len(sizes)):
        if sizes[i] == 768:
            large.append(i)
    assert_true(large == [0, 4, 8, 12])
    sizes = dimensions("batch_boundary", 16, 4)
    large = List[Int]()
    for i in range(len(sizes)):
        if sizes[i] == 768:
            large.append(i)
    assert_true(large == [3, 4, 11, 12])


def test_png_crc_and_pixels() raises:
    var pixels = rgba(16, 3)
    var encoded = png(16, pixels)
    assert_true(encoded == png(16, rgba(16, 3)))
    var signature: List[UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    assert_true(encoded[:8] == signature)
    var at = 8
    var chunks = 0
    while at < len(encoded):
        var size = 0
        for i in range(4):
            size = size * 256 + Int(encoded[at + i])
        var body = List[UInt8](encoded[at + 4 : at + 8 + size])
        var checksum = UInt32(0)
        for i in range(4):
            checksum = checksum * 256 + UInt32(encoded[at + 8 + size + i])
        assert_equal(checksum, crc32(body))
        at += 12 + size
        chunks += 1
    assert_equal(chunks, 3)
    var image = decode(encoded)
    assert_equal(image.width, 16)
    assert_equal(image.height, 16)
    assert_true(image.pixels == pixels)


def test_gltf_and_manifest() raises:
    var root = mkdtemp()
    var result = generate(root, 3, 4, [String("uniform_tiny")])
    ref tree = result.tree
    var data = tree.at(tree.get(result.manifest, "datasets"), 0)
    var documents = JsonTree()
    var gltf = read_json(documents, root + "/uniform_tiny/scene.gltf")
    var manifest = read_json(documents, root + "/uniform_tiny/manifest.json")
    assert_equal(documents.length(documents.get(gltf, "images")), 3)
    var mesh = documents.at(documents.get(gltf, "meshes"), 0)
    assert_equal(documents.length(documents.get(mesh, "primitives")), 3)
    assert_equal(documents.length(documents.get(manifest, "bindings")), 3)
    var expected = tree.get(data, "expected")
    assert_equal(
        tree.int_value(tree.get(expected, "base_bytes")), 3 * 16 * 16 * 4
    )
    assert_equal(
        tree.int_value(tree.get(expected, "payload_bytes")),
        3 * (256 + 64 + 16 + 4 + 1) * 4,
    )
    var files = tree.get(data, "files")
    for index in range(tree.length(files)):
        var item = tree.at(files, index)
        var path = root + "/uniform_tiny/" + tree.text(tree.get(item, "path"))
        assert_equal(
            len(Path(path).read_bytes()),
            tree.int_value(tree.get(item, "bytes")),
        )
        assert_equal(sha(path), tree.text(tree.get(item, "sha256")))


# --- measurement ---------------------------------------------------------------


def test_resource_guards() raises:
    var low = False
    try:
        _ = check_resources(String("MemAvailable: 1024 kB"), 1 << 40, True)
    except e:
        low = _raises_with("below 3 GiB", e)
    assert_true(low)
    var full = False
    try:
        _ = check_resources(String("MemAvailable: 9999999 kB"), 1, True)
    except e:
        full = _raises_with("below 2 GiB", e)
    assert_true(full)
    var unknown = False
    try:
        _ = check_resources(None, 1 << 40, True)
    except e:
        unknown = _raises_with("Cannot verify MemAvailable", e)
    assert_true(unknown)
    var reading = check_resources(None, 1 << 40, False)
    assert_false(Bool(reading.available))


def test_protocol_runner_with_stub() raises:
    # This checks the runner protocol, not native image loading performance.
    var helper = _helper()
    if helper.byte_length() == 0:
        return
    var root = mkdtemp()
    _ = generate(root + "/fixtures", 2, 4, [String("uniform_tiny")])
    var oracle = String()
    for pair in _expected(root + "/fixtures"):
        oracle += " " + pair
    var stub = root + "/protocol_stub.sh"
    Path(stub).write_text(
        "#!/bin/sh\necho result api $2 workers $3 runtime_parallelism 4"
        " load_ns 100"
        + oracle
        + " all_fnv64 1 shape_fnv64 1\n"
    )
    _ = run_program([String("chmod"), "755", stub], 10)
    var build = _write_build(
        root, helper, stub, [String("baseline"), String("dynamic")]
    )
    var options = RunOptions(
        build, root + "/fixtures", root + "/protocol-output"
    )
    options.repetitions = 1
    options.workers = [1, 2]
    options.apis = [String("gltf")]
    options.timeout = 5
    var measurer = NativeMeasurer()
    run(options, measurer)
    var tree = JsonTree()
    var metadata = read_json(tree, options.destination + "/metadata.json")
    assert_equal(tree.text(tree.get(metadata, "status")), "complete")
    assert_equal(tree.int_value(tree.get(metadata, "completed_rows")), 4)
    assert_equal(_lines(options.destination + "/raw.jsonl"), 4)
    assert_equal(_lines(options.destination + "/validated.jsonl"), 4)


def test_rusage_marker_parser() raises:
    var m = _multiplier()
    var marker = _marker(
        '"schema": 1, "rss_unit": "'
        + _unit()
        + '", "maxrss_raw": 7, "peak_rss_bytes": '
        + String(7 * m)
    )
    var tree = JsonTree()
    var parsed = parse_rusage(tree, "native diagnostic\n" + marker)
    assert_equal(tree.int_value(tree.get(parsed.record, "maxrss_raw")), 7)
    assert_equal(
        tree.int_value(tree.get(parsed.record, "peak_rss_bytes")), 7 * m
    )
    assert_equal(parsed.native_stderr, "native diagnostic\n")
    var twice = marker.copy()
    twice += marker
    for text in [twice, String("native diagnostic only")]:
        var failed = False
        try:
            _ = parse_rusage(tree, text)
        except:
            failed = True
        assert_true(failed)


def test_true_rss_independent_of_runner_heap() raises:
    var helper = _helper()
    if helper.byte_length() == 0:
        return
    var tree = JsonTree()
    var before = List[Int]()
    for _ in range(3):
        before.append(measure(tree, [String("/bin/true")], 10, ".", helper))
    var memory = List[UInt8](length=128 * 1024 * 1024, fill=0)
    for i in range(0, len(memory), 4096):
        memory[i] = 120
    var after = List[Int]()
    for _ in range(3):
        after.append(measure(tree, [String("/bin/true")], 10, ".", helper))
    # Keep the enlarged heap live through all launches.
    assert_equal(memory[0], 120)
    var most_before = 0
    var most_after = 0
    for row in before:
        assert_equal(tree.int_value(tree.get(row, "exit_code")), 0)
        assert_equal(tree.text(tree.get(row, "measurement_error")), "null")
        most_before = max(
            most_before, tree.int_value(tree.get(row, "peak_rss_bytes"))
        )
    for row in after:
        assert_equal(tree.int_value(tree.get(row, "exit_code")), 0)
        assert_equal(tree.text(tree.get(row, "measurement_error")), "null")
        most_after = max(
            most_after, tree.int_value(tree.get(row, "peak_rss_bytes"))
        )
    assert_true(most_after < most_before + 16 * 1024 * 1024)
    assert_true(most_after < 64 * 1024 * 1024)


def test_native_errors_propagate() raises:
    var helper = _helper()
    if helper.byte_length() == 0:
        return
    var tree = JsonTree()
    var row = measure(tree, _sh("exit 23"), 10, ".", helper)
    assert_equal(tree.int_value(tree.get(row, "exit_code")), 23)
    assert_equal(tree.int_value(tree.get(row, "native_exit_code")), 23)
    row = measure(tree, _sh("kill -TERM $$"), 10, ".", helper)
    assert_equal(tree.int_value(tree.get(row, "exit_code")), -15)
    assert_equal(tree.int_value(tree.get(row, "native_exit_code")), -15)
    row = measure(
        tree,
        [String("/path/that/does/not/exist/image_decode")],
        10,
        ".",
        helper,
    )
    assert_equal(tree.int_value(tree.get(row, "exit_code")), 127)
    assert_true(tree.text(tree.get(row, "measurement_error")) != "null")
    var errno = tree.get(tree.get(row, "rusage"), "exec_errno")
    assert_true(tree.int_value(errno) != 0)


def test_parser() raises:
    var tree = JsonTree()
    var parsed = parse_output(tree, "result api gltf workers 4 load_ns 123\n")
    assert_equal(
        tree.dumps(parsed), '{"api": "gltf", "workers": 4, "load_ns": 123}'
    )
    var failed = False
    try:
        _ = parse_output(tree, "result api gltf workers 1 workers 2")
    except:
        failed = True
    assert_true(failed)


def test_per_child_rss() raises:
    # Large first, small second: a cumulative children high-water mark
    # would incorrectly give the second process the first one's memory.
    var helper = _helper()
    if helper.byte_length() == 0:
        return
    var tree = JsonTree()
    var big = measure(
        tree,
        [String("dd"), "if=/dev/zero", "of=/dev/null", "bs=64M", "count=1"],
        10,
        ".",
        helper,
    )
    var small = measure(
        tree,
        [String("dd"), "if=/dev/zero", "of=/dev/null", "bs=1M", "count=1"],
        10,
        ".",
        helper,
    )
    assert_equal(tree.int_value(tree.get(big, "exit_code")), 0)
    assert_equal(tree.int_value(tree.get(small, "exit_code")), 0)
    assert_true(
        tree.int_value(tree.get(big, "peak_rss_bytes"))
        > tree.int_value(tree.get(small, "peak_rss_bytes")) + 24 * 1024 * 1024
    )


def _alive(pid: String) raises -> Bool:
    """Return whether a process runs; a zombie counts as ended."""
    var stat = "/proc/" + pid + "/stat"
    if not exists(stat):
        return False
    try:
        var text = Path(stat).read_text()
        var close = text.rfind(")")
        return not String(text[byte = close + 1 :]).strip().startswith("Z")
    except:
        return False


def test_timeout_terminates_native_and_descendant() raises:
    comptime if CompilationTarget.is_macos():
        return
    var helper = _helper()
    if helper.byte_length() == 0:
        return
    var root = mkdtemp()
    var script = (
        "echo $$ > native.tmp && mv native.tmp native.pid\n"
        "sleep 1000 &\n"
        "echo $! > descendant.tmp && mv descendant.tmp descendant.pid\n"
        "wait\n"
    )
    var tree = JsonTree()
    var row = measure(tree, _sh(script), 1.0, root, helper)
    assert_true(tree.text(tree.get(row, "timed_out")) == "true")
    assert_true(tree.int_value(tree.get(row, "exit_code")) != 0)
    assert_equal(tree.text(tree.get(row, "peak_rss_bytes")), "null")
    var pids = List[String]()
    for name in ["native.pid", "descendant.pid"]:
        assert_true(exists(root + "/" + name))
        pids.append(String(Path(root + "/" + name).read_text().strip()))
    # SIGKILL to the group ends both; allow the kernel a moment to reap.
    var waited = 0
    while waited < 200 and (_alive(pids[0]) or _alive(pids[1])):
        _ = run_program([String("sleep"), "0.01"], 5)
        waited += 1
    assert_false(_alive(pids[0]), "the native child survived killpg")
    assert_false(_alive(pids[1]), "the descendant survived killpg")


def test_summary_pairs() raises:
    var tree = JsonTree()
    var rows = List[Int]()
    for repetition in range(3):
        for pair in [("baseline", 100), ("dynamic", 50)]:
            var native = tree.object()
            for field in check_fields():
                tree.set(native, field, tree.integer(1))
            tree.set(native, "load_ns", tree.integer(pair[1]))
            tree.set(native, "runtime_parallelism", tree.integer(4))
            tree.set(native, "base_bytes", tree.integer(400))
            var row = tree.object()
            tree.set(row, "dataset", tree.string("test"))
            tree.set(row, "api", tree.string("gltf"))
            tree.set(row, "workers", tree.integer(4))
            tree.set(row, "variant", tree.string(String(pair[0])))
            tree.set(row, "repetition", tree.integer(repetition))
            tree.set(row, "peak_rss_bytes", tree.integer(100))
            tree.set(row, "native", native)
            rows.append(row)
    var out = JsonTree()
    var summary = summarize(tree, rows, "baseline", out)
    var dynamic = out.at(summary, 1)
    assert_equal(out.text(out.get(dynamic, "variant")), "dynamic")
    var speedup = out.get(dynamic, "paired_speedup_vs_baseline")
    assert_equal(out.text(out.get(speedup, "median")), "2.0")
    var rate = out.get(dynamic, "base_megapixels_per_second")
    assert_equal(out.text(out.get(rate, "median")), "2000.0")
    assert_equal(out.int_value(out.get(out.get(dynamic, "load_ns"), "n")), 3)


# --- rejected evidence ---------------------------------------------------------


def test_tampered_fixture_hash_rejected_before_launch() raises:
    var root = mkdtemp()
    var options = _prepare(root)
    var path = options.fixtures + "/uniform_tiny/image-0000.png"
    var content = Path(path).read_bytes()
    # Same length: this specifically tests SHA-256 admission.
    content[len(content) - 1] ^= 1
    Path(path).write_bytes(Span(content))
    var measurer = _NeverMeasure()
    var rejected = False
    try:
        run(options, measurer)
    except e:
        rejected = _raises_with("Fixture changed", e)
    assert_true(rejected)
    assert_equal(measurer.calls, 0)


def test_tampered_native_or_helper_binary_rejected_before_launch() raises:
    for label in ["baseline", "helper-placeholder"]:
        var root = mkdtemp()
        var options = _prepare(root)
        var path = root + "/" + label
        var content = Path(path).read_bytes()
        content[0] ^= 1
        Path(path).write_bytes(Span(content))
        var pattern = (
            "Binary changed since build" if label
            == "baseline" else "RSS supervisor binary changed"
        )
        var measurer = _NeverMeasure()
        var rejected = False
        try:
            run(options, measurer)
        except e:
            rejected = _raises_with(pattern, e)
        assert_true(rejected, label)
        assert_equal(measurer.calls, 0)


def test_incorrect_base_hash_rejected_by_fixture_oracle() raises:
    var root = mkdtemp()
    var options = _prepare(root)
    var expected = String()
    for pair in _expected(options.fixtures):
        if pair.startswith("base_fnv64 "):
            expected = String(pair[byte=11:])
    var changed = UInt64(0)
    for byte in expected.as_bytes():
        changed = changed * 10 + UInt64(Int(byte) - 48)
    changed ^= 1
    var measurer = _Scripted(
        [_measured_row(options.fixtures, "base_fnv64", String(changed))]
    )
    var rejected = False
    try:
        run(options, measurer)
    except e:
        rejected = _raises_with("Fixture oracle failed", e) and _raises_with(
            "base_fnv64", e
        )
    assert_true(rejected)
    var tree = JsonTree()
    var metadata = read_json(tree, options.destination + "/metadata.json")
    assert_equal(tree.text(tree.get(metadata, "status")), "failed")
    assert_equal(tree.int_value(tree.get(metadata, "completed_rows")), 0)
    assert_equal(_lines(options.destination + "/raw.jsonl"), 1)


def test_incorrect_all_mip_or_shape_hash_rejected() raises:
    for field in ["all_fnv64", "shape_fnv64"]:
        var root = mkdtemp()
        var options = _prepare(root)
        var measurer = _Scripted(
            [
                _measured_row(options.fixtures),
                _measured_row(options.fixtures, field, "99"),
            ]
        )
        var rejected = False
        try:
            run(options, measurer)
        except e:
            rejected = _raises_with(
                "Output differs across variants/workers/trials", e
            )
        assert_true(rejected, field)
        var tree = JsonTree()
        var metadata = read_json(tree, options.destination + "/metadata.json")
        assert_equal(tree.text(tree.get(metadata, "status")), "failed")
        assert_equal(tree.int_value(tree.get(metadata, "completed_rows")), 1)
        assert_equal(_lines(options.destination + "/raw.jsonl"), 2)
        assert_equal(_lines(options.destination + "/validated.jsonl"), 1)


def test_invalid_rss_units_and_conversion_rejected() raises:
    var m = _multiplier()
    var good = '"schema": 1, "rss_unit": "' + _unit() + '"'
    for fields in [
        String('"schema": 1, "rss_unit": "MiB", "maxrss_raw": 7,')
        + ' "peak_rss_bytes": '
        + String(7 * m),
        good + ', "maxrss_raw": 7, "peak_rss_bytes": ' + String(7 * m + 1),
        good + ', "maxrss_raw": -1, "peak_rss_bytes": ' + String(-m),
    ]:
        var tree = JsonTree()
        var failed = False
        try:
            _ = parse_rusage(tree, _marker(fields))
        except:
            failed = True
        assert_true(failed, fields)


def test_native_supervisor_status_disagreement_rejected() raises:
    for case_ in [(23, 0), (-1, 15)]:
        var tree = JsonTree()
        var row = measurement_row(
            tree,
            [String("unexecuted-native")],
            [String("unexecuted-helper"), "--", "unexecuted-native"],
            0,
            False,
            tree.object(),
            1,
            "",
            _usage(case_[0], case_[1]),
        )
        assert_true(
            "did not propagate" in tree.text(tree.get(row, "measurement_error"))
        )
        assert_equal(tree.int_value(tree.get(row, "exit_code")), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
