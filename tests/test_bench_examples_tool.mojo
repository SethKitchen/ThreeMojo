# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The example benchmark keeps truthful measurement metadata and its texts.

A partial refresh must keep each row's date and refuse another host. The
tables, the score, the page spans, the results file and the command line
must match what `tools/bench_examples.py` wrote. The golden texts here are
that tool's output for the same fixtures. No check compiles or runs Mojo.
"""

from std.os import listdir, makedirs, remove, rmdir
from std.os.path import isdir
from std.pathlib import Path
from std.subprocess import run as shell
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tools._json_tree import NOTHING, JsonTree, equal
from tools.bench_examples import (
    Finished,
    HOST_MISMATCH,
    Machine,
    State,
    bsd_peak,
    bsd_real,
    cross_report,
    dumps,
    example_table,
    fmt_mib,
    fmt_ratio,
    fmt_s,
    measure_command,
    measurement_label,
    merge_measurements,
    mojo10_table,
    parse_arguments,
    py_strip,
    python_error,
    python_round,
    read_payload,
    refused_reason,
    replace_span,
    require_same_measurement_host,
    rss_line,
    run,
    same_measurement_host,
    slim_payload,
    this_platform,
    usage_text,
    help_text,
    winner_name,
)

comptime HOST = (
    '{"cpu": "Fixture CPU", "os": "Fixture OS", "mojo_1_1": "Mojo 1.1",'
    ' "mojo_1_0": "", "python": "3.12", "node": "v22"}'
)
comptime HOST_KEYS = ["cpu", "os", "mojo_1_1", "mojo_1_0", "python", "node"]
comptime METRIC = (
    '{"ok": true, "seconds": 1.0, "rss_kib": 16, "status": 0, "output": ""}'
)
comptime CATALOG = (
    '[{"name": "triangle", "src": "examples/triangle.mojo", "width": 32,'
    ' "height": 24, "frames": 2}, {"name": "spin", "src":'
    ' "examples/spin.mojo", "width": 32, "height": 24, "frames": 2},'
    ' {"name": "cube", "src": "examples/cube.mojo", "width": 32, "height":'
    ' 24, "frames": 2}]'
)


# --- helpers -------------------------------------------------------------------


struct FakeMachine(Machine):
    """A host that records commands and returns fixed answers."""

    var commands: List[String]
    """Each measured command, joined with spaces."""
    var stdout: String
    """The text written to the standard output."""
    var stderr: String
    """The text written to the standard error."""
    var host_text: String
    """The host record that `host` returns."""
    var metric_text: String
    """The metric that `measure` returns."""

    def __init__(out self, host_text: String, metric_text: String):
        """Make a host.

        Args:
            host_text: The host record JSON.
            metric_text: The metric JSON.
        """
        self.commands = List[String]()
        self.stdout = String()
        self.stderr = String()
        self.host_text = host_text
        self.metric_text = metric_text

    def measure(
        mut self,
        mut tree: JsonTree,
        command: List[String],
        directory: String,
        overrides: List[String],
    ) raises -> Int:
        """Record a command and return the fixed metric."""
        self.commands.append(" ".join(command))
        return tree.parse(self.metric_text)

    def capture(
        mut self,
        command: List[String],
        directory: String,
        overrides: List[String],
    ) raises -> Finished:
        """Return no output."""
        return Finished(0, String(), String(), 0)

    def today(mut self) -> String:
        """Return the fixture date."""
        return "2026-10-01"

    def host(
        mut self,
        mut tree: JsonTree,
        mut state: State,
        mojo11: String,
        mojo10: String,
    ) raises -> Int:
        """Return the fixture host."""
        return tree.parse(self.host_text)

    def out(mut self, text: String):
        """Keep standard output text."""
        self.stdout += text

    def err(mut self, text: String):
        """Keep standard error text."""
        self.stderr += text


def _example_text(name: String) -> String:
    """Return one example row as JSON."""
    return (
        '{"name": "'
        + name
        + '", "width": 32, "height": 24, "frames": 1, "threemojo":'
        + ' {"compile": '
        + METRIC
        + ', "run": '
        + METRIC
        + '}, "threejs_flat": '
        + METRIC
        + ', "threejs_webgl": null, "mojo10": null}'
    )


def _payload_text(date: String, rows: List[String]) -> String:
    """Return results as JSON."""
    return (
        '{"generated_at": "'
        + date
        + '", "host": '
        + HOST
        + ', "examples": ['
        + ", ".join(rows)
        + '], "probe": {}, "baselines": {}, "threejs_webgl": false,'
        + ' "mojo10_total": 0, "mojo10_refused": 0}'
    )


def _names(tree: JsonTree, merged: Int) raises -> String:
    """Return the example names of results, joined with spaces."""
    var names = List[String]()
    var rows = tree.item(merged, "examples")
    for index in range(tree.length(rows)):
        names.append(tree.text(tree.item(tree.at(rows, index), "name")))
    return " ".join(names)


def _row(tree: JsonTree, results: Int, index: Int) raises -> Int:
    """Return one example row of results."""
    return tree.at(tree.item(results, "examples"), index)


def _remove_tree(path: String) raises:
    """Remove a test folder."""
    for name in listdir(path):
        var child = path + "/" + name
        if isdir(child):
            _remove_tree(child)
        else:
            remove(child)
    rmdir(path)


# --- merges --------------------------------------------------------------------


def test_host_and_toolchain_changes_or_missing_metadata_are_refused() raises:
    var tree = JsonTree()
    var host = tree.parse(HOST)
    for key in materialize[HOST_KEYS]():
        var old = tree.parse(
            _payload_text("2026-09-01", [_example_text("cube")])
        )
        tree.set_text(tree.item(old, "host"), key, "different")
        assert_false(same_measurement_host(tree, old, host), key)
        var refused = False
        try:
            require_same_measurement_host(tree, old, host)
        except error:
            refused = String(error).find("host/toolchain") >= 0
        assert_true(refused, key)
    var blank = tree.parse(HOST)
    tree.set_text(blank, "cpu", "")
    var cases: List[Int] = [
        tree.parse("{}"),
        tree.parse('{"host": {}}'),
        tree.parse("[]"),
        tree.object(),
    ]
    tree.set(cases[3], "host", blank)
    for old in cases:
        assert_false(same_measurement_host(tree, old, host))


def test_unknown_identity_is_not_an_established_host_match() raises:
    var tree = JsonTree()
    for key in ["cpu", "os", "mojo_1_1"]:
        for value in ["unknown", "missing", "not installed", " "]:
            var host = tree.parse(HOST)
            tree.set_text(host, key, value)
            var old = tree.object()
            tree.set(old, "host", host)
            assert_false(same_measurement_host(tree, old, host))


def test_retained_direct_dates_and_values_survive_in_catalog_order() raises:
    var tree = JsonTree()
    var catalog = tree.parse(CATALOG)
    var old = tree.parse(_payload_text("2026-09-10", [_example_text("cube")]))
    var cube = _row(tree, old, 0)
    tree.set_text(cube, "measured_on", "2026-09-03")
    tree.set_text(cube, "measurement_date_source", "direct")
    var fresh = tree.parse(
        _payload_text("2026-10-01", [_example_text("triangle")])
    )
    var before = dumps(tree, old) + dumps(tree, fresh)
    var merged = merge_measurements(tree, catalog, old, fresh)
    assert_equal(_names(tree, merged), "triangle cube")
    assert_equal(measurement_label(tree, _row(tree, merged, 0)), "2026-10-01")
    assert_true(equal(tree, _row(tree, merged, 1), tree, cube))
    assert_equal(dumps(tree, old) + dumps(tree, fresh), before)


def test_legacy_dates_are_identified_as_aggregate_only() raises:
    var tree = JsonTree()
    var catalog = tree.parse(CATALOG)
    var old = tree.parse(_payload_text("2026-09-01", [_example_text("cube")]))
    var fresh = tree.parse(
        _payload_text("2026-10-01", [_example_text("triangle")])
    )
    var merged = merge_measurements(tree, catalog, old, fresh)
    var row = _row(tree, merged, 1)
    assert_true(
        equal(
            tree,
            tree.item(row, "threemojo"),
            tree,
            tree.item(_row(tree, old, 0), "threemojo"),
        )
    )
    assert_equal(measurement_label(tree, row), "unknown (legacy: 2026-09-01)")
    assert_equal(measurement_label(tree, tree.object()), "unknown")


def test_aggregate_counts_follow_retained_and_replaced_rows() raises:
    var tree = JsonTree()
    var catalog = tree.parse(CATALOG)
    var old = tree.parse(_payload_text("2026-09-01", [_example_text("cube")]))
    tree.set(
        _row(tree, old, 0),
        "mojo10",
        tree.parse('{"compile": ' + METRIC + ', "run": ' + METRIC + "}"),
    )
    tree.set_flag(old, "threejs_webgl", True)
    var fresh = tree.parse(
        _payload_text("2026-10-01", [_example_text("triangle")])
    )
    tree.set(
        _row(tree, fresh, 0), "mojo10", tree.parse('{"compile": {"ok": false}}')
    )
    var merged = merge_measurements(tree, catalog, old, fresh)
    assert_equal(tree.int_value(tree.item(merged, "mojo10_total")), 2)
    assert_equal(tree.int_value(tree.item(merged, "mojo10_refused")), 1)
    assert_false(tree.flag(tree.item(merged, "threejs_webgl")))


# --- tables --------------------------------------------------------------------


def test_slim_rows_and_tables_show_recorded_dates() raises:
    var tree = JsonTree()
    var slim = slim_payload(
        tree,
        tree.parse(_payload_text("2026-10-01", [_example_text("cube")])),
    )
    assert_equal(measurement_label(tree, _row(tree, slim, 0)), "2026-10-01")
    var table = example_table(tree, tree.item(slim, "examples"), False, NOTHING)
    assert_true(table.find("| Measured |") >= 0)
    assert_true(table.find("| Draw winner |") >= 0)
    assert_true(table.find("| 2026-10-01 |") >= 0)
    assert_true(table.find("per-row measurement date is unknown") >= 0)
    assert_true(table.find("background-color") < 0)


def test_draw_winner_uses_frame_time_and_refused_compiles_stay_out() raises:
    var tree = JsonTree()
    var row = tree.parse(_example_text("cube"))
    tree.set(
        tree.path(row, ["threemojo", "run"]),
        "frames_seconds",
        tree.number(0.020),
    )
    var web = tree.parse(METRIC)
    tree.set(web, "frames_seconds", tree.number(0.050))
    tree.set_text(web, "backend", "webgl")
    tree.set(row, "threejs_webgl", web)
    var flat = tree.parse(METRIC)
    tree.set(flat, "frames_seconds", tree.number(0.010))
    tree.set(row, "threejs_flat", flat)
    var rows = tree.array()
    tree.append(rows, row)
    assert_true(example_table(tree, rows, True, NOTHING).find("| Mojo |") >= 0)
    var refused = tree.parse(_example_text("spin"))
    tree.set(
        refused,
        "mojo10",
        tree.parse(
            '{"compile": {"ok": false, "seconds": 1.0}, "run": {"ok": false}}'
        ),
    )
    var refused_rows = tree.array()
    tree.append(refused_rows, refused)
    var probe = '{"compile": ' + METRIC + ', "run": ' + METRIC + "}"
    var version = mojo10_table(
        tree, tree.parse(probe), tree.parse(probe), refused_rows
    )
    assert_true(version.find("`spin`") < 0)
    assert_true(version.find("Refused catalog rows: 1") >= 0)
    assert_true(version.find("background-color") < 0)


def test_cross_host_ratios_do_not_assume_macos_is_faster() raises:
    var folder = mkdtemp(prefix="bench-cross-")
    var linux_path = folder + "/linux.json"
    var mac_path = folder + "/macos.json"
    Path(mac_path).write_text(
        _payload_text("2026-09-01", [_example_text("cube")])
    )
    for ratio in [0.5, 1.0, 2.0]:
        var tree = JsonTree()
        var linux = tree.parse(
            _payload_text("2026-10-01", [_example_text("cube")])
        )
        for metric in ["compile", "run"]:
            tree.set(
                tree.path(_row(tree, linux, 0), ["threemojo", metric]),
                "seconds",
                tree.number(ratio),
            )
        Path(linux_path).write_text(dumps(tree, linux))
        var report = cross_report(tree, linux_path, mac_path)
        var shown = fmt_ratio(ratio)
        assert_true(
            report.find("Linux/macOS whole-process time ratio is " + shown) >= 0
        )
        assert_true(
            report.find("Linux/macOS compile-time ratio is " + shown) >= 0
        )
        assert_true(
            report.find("Each ratio is Linux time divided by macOS time.") >= 0
        )
        assert_true(
            report.find(
                "The Linux date is 2026-10-01. The macOS date is 2026-09-01."
            )
            >= 0
        )
        assert_true(
            report.find("These ratios do not isolate hardware speed.") >= 0
        )
        assert_true(report.find("faster") < 0)
    var tree = JsonTree()
    assert_equal(
        cross_report(tree, folder + "/none.json", mac_path),
        (
            "One host has no results file. The machine comparison waits for"
            " that file."
        ),
    )
    _remove_tree(folder)


# --- the run -------------------------------------------------------------------


def _main_root(old: String) raises -> String:
    """Make a repository with a catalog, a compiler and a results file."""
    var root = mkdtemp(prefix="bench-main-")
    makedirs(root + "/bench", exist_ok=True)
    makedirs(root + "/.venv/bin", exist_ok=True)
    Path(root + "/bench/catalog.json").write_text(CATALOG)
    Path(root + "/.venv/bin/mojo").write_text("")
    Path(root + "/bench/results-" + this_platform() + ".json").write_text(old)
    return root


def _run_main(incompatible: Bool) raises:
    """Refresh one example over a results file with a fixed host."""
    var old = _payload_text("2026-09-01", [_example_text("cube")])
    var root = _main_root(old)
    var host = String(HOST)
    if incompatible:
        host = host.replace("Fixture CPU", "Other CPU")
    var machine = FakeMachine(
        host,
        (
            '{"ok": false, "seconds": 1.0, "rss_kib": 16, "status": 1,'
            ' "output": ""}'
        ),
    )
    var arguments: List[String] = [
        "--only",
        "triangle",
        "--merge",
        "--skip-mojo10",
        "--skip-threejs",
        "--no-write-wiki",
    ]
    var status = run(machine, arguments, "bench_examples", 80, root)
    var path = root + "/bench/results-" + this_platform() + ".json"
    if incompatible:
        assert_equal(status, 2)
        assert_equal(Path(path).read_text(), old)
        assert_true(machine.stderr.find("host/toolchain") >= 0)
        assert_equal(len(machine.commands), 0)
    else:
        assert_equal(status, 0)
        var tree = JsonTree()
        var result = tree.parse(Path(path).read_text())
        assert_equal(_names(tree, result), "triangle cube")
        assert_equal(
            measurement_label(tree, _row(tree, result, 0)), "2026-10-01"
        )
        assert_equal(
            measurement_label(tree, _row(tree, result, 1)),
            "unknown (legacy: 2026-09-01)",
        )
        assert_true(len(machine.commands) > 0)
    _remove_tree(root)


def test_main_refuses_before_measuring_or_overwriting_results() raises:
    _run_main(True)


def test_main_keeps_valid_same_host_partial_refreshes() raises:
    _run_main(False)


def test_main_reports_unknown_examples_and_platforms() raises:
    var root = _main_root("{}")
    var machine = FakeMachine(HOST, METRIC)
    var unknown: List[String] = ["--only", "cube, nope ,,zz"]
    assert_equal(run(machine, unknown, "bench_examples", 80, root), 2)
    assert_equal(machine.stderr, "unknown example: nope, zz\n")
    var other = "macos" if this_platform() == "linux" else "linux"
    machine.stderr = String()
    var platform: List[String] = ["--platform", other]
    assert_equal(run(machine, platform, "bench_examples", 80, root), 2)
    assert_equal(
        machine.stderr, "--platform only applies with --from-results.\n"
    )
    machine.stderr = String()
    var missing: List[String] = ["--from-results", "--platform", other]
    assert_equal(run(machine, missing, "bench_examples", 80, root), 1)
    assert_equal(
        machine.stderr,
        "bench/results-" + other + ".json is missing. Run the benches first.\n",
    )
    assert_equal(len(machine.commands), 0)
    _remove_tree(root)


def test_from_results_matches_the_python_tables_and_page() raises:
    var root = mkdtemp(prefix="bench-golden-")
    makedirs(root + "/bench", exist_ok=True)
    makedirs(root + "/docs/wiki", exist_ok=True)
    Path(root + "/bench/catalog.json").write_text(CATALOG)
    Path(root + "/bench/results-linux.json").write_text(LINUX_RESULTS)
    Path(root + "/bench/results-macos.json").write_text(MACOS_RESULTS)
    Path(root + "/docs/wiki/Benchmarks.md").write_text(WIKI_BEFORE)
    var machine = FakeMachine(HOST, METRIC)
    var arguments: List[String] = ["--from-results", "--platform", "linux"]
    assert_equal(run(machine, arguments, "bench_examples", 80, root), 0)
    assert_equal(machine.stdout, TABLES)
    assert_equal(
        Path(root + "/docs/wiki/Benchmarks.md").read_text(), WIKI_AFTER
    )
    # A page without a span stops with the Python text.
    Path(root + "/docs/wiki/Benchmarks.md").write_text("no spans\n")
    var stopped = String()
    try:
        _ = run(machine, arguments, "bench_examples", 80, root)
    except error:
        stopped = String(error)
    assert_equal(stopped, "Benchmarks.md is missing <!-- BENCH:HOST:linux -->")
    assert_equal(python_error(stopped), stopped)
    _remove_tree(root)


def test_results_are_written_as_json_dumps_indent_two() raises:
    var tree = JsonTree()
    assert_equal(dumps(tree, tree.parse(LINUX_RESULTS)), LINUX_RESULTS)
    assert_equal(
        dumps(
            tree,
            tree.parse(
                '{"a": [], "b": {}, "c": [NaN, -Infinity, 1e300], "d":'
                ' "\\u00e9"}'
            ),
        ),
        (
            '{\n  "a": [],\n  "b": {},\n  "c": [\n    NaN,\n    -Infinity,\n'
            '    1e+300\n  ],\n  "d": "\\u00e9"\n}'
        ),
    )


# --- the command line ----------------------------------------------------------


def test_help_and_errors_match_argparse() raises:
    var help = parse_arguments(["--he"])
    assert_true(help.help)
    assert_equal(help_text("bench_examples", 58), HELP_60)
    assert_equal(
        usage_text("bench_examples", 198),
        (
            "usage: bench_examples [-h] [--only ONLY] [--merge]"
            " [--skip-threejs] [--skip-webgl] [--skip-mojo10] [--write-wiki]"
            " [--no-write-wiki] [--from-results] [--platform {linux,macos}]\n"
        ),
    )
    assert_equal(
        parse_arguments(["--sk"]).error,
        (
            "ambiguous option: --sk could match --skip-threejs, --skip-webgl,"
            " --skip-mojo10"
        ),
    )
    assert_equal(
        parse_arguments(["--merge=1"]).error,
        "argument --merge: ignored explicit argument '1'",
    )
    assert_equal(
        parse_arguments(["--only", "--merge"]).error,
        "argument --only: expected one argument",
    )
    assert_equal(
        parse_arguments(["--platform", "x"]).error,
        (
            "argument --platform: invalid choice: 'x' (choose from 'linux',"
            " 'macos')"
        ),
    )
    assert_equal(
        parse_arguments(["foo", "--", "-h"]).error,
        "unrecognized arguments: foo -- -h",
    )
    assert_true(parse_arguments(["-hx"]).help)
    var parsed = parse_arguments(
        ["--on=a,b", "--no", "--fr", "--pl", "macos", "--skip-w", "--m"]
    )
    assert_equal(parsed.error, "")
    assert_equal(parsed.only.value(), "a,b")
    assert_false(parsed.write_wiki)
    assert_true(parsed.from_results and parsed.skip_webgl and parsed.merge)
    assert_equal(parsed.platform, "macos")
    var machine = FakeMachine(HOST, METRIC)
    var root = mkdtemp(prefix="bench-args-")
    makedirs(root + "/bench", exist_ok=True)
    Path(root + "/bench/catalog.json").write_text(CATALOG)
    assert_equal(run(machine, ["--bogus"], "bench_examples", 60, root), 2)
    assert_equal(
        machine.stderr,
        usage_text("bench_examples", 58)
        + "bench_examples: error: unrecognized arguments: --bogus\n",
    )
    assert_equal(run(machine, ["-h"], "bench_examples", 60, root), 0)
    assert_equal(machine.stdout, HELP_60)
    _remove_tree(root)


# --- measuring -----------------------------------------------------------------


def test_gnu_time_lines_give_the_peak_and_status() raises:
    var folder = mkdtemp(prefix="bench-time-")
    var stub = folder + "/time"
    Path(stub).write_text(
        '#!/bin/sh\nshift 3\n"$@"\nrc=$?\necho "TIME_RSS 0.01 4321.7'
        ' $rc" >&2\nexit $rc\n'
    )
    var child = folder + "/child"
    Path(child).write_text(
        "#!/bin/sh\necho '{\"frames_ms\": 12}'\nprintf 'a\\r\\n' >&2\n"
        "exit ${1:-0}\n"
    )
    _ = shell("chmod +x '" + stub + "' '" + child + "'")
    var tree = JsonTree()
    var metric = measure_command(
        tree, [child, "3"], folder, List[String](), stub
    )
    assert_false(tree.flag(tree.item(metric, "ok")))
    assert_equal(tree.int_value(tree.item(metric, "rss_kib")), 4321)
    assert_equal(tree.int_value(tree.item(metric, "status")), 3)
    assert_true(tree.is_float(tree.item(metric, "seconds")))
    assert_equal(
        tree.text(tree.item(metric, "output")),
        '{"frames_ms": 12}\n\na\nTIME_RSS 0.01 4321.7 3\n',
    )
    var alone = measure_command(
        tree, [child], folder, List[String](), folder + "/none"
    )
    assert_true(tree.flag(tree.item(alone, "ok")))
    assert_true(tree.is_null(tree.item(alone, "rss_kib")))
    var payload = read_payload(tree, tree.text(tree.item(alone, "output")))
    assert_equal(payload.frames_seconds.value(), 0.012)
    var refused = False
    try:
        _ = measure_command(
            tree, [folder + "/missing"], folder, List[String](), stub + "x"
        )
    except error:
        refused = String(error).startswith("FileNotFoundError: [Errno 2]")
    assert_true(refused)
    _remove_tree(folder)


def test_time_reports_and_payload_lines_are_read_as_python_did() raises:
    assert_equal(len(rss_line("TIME_RSS 1 2 3").value()), 3)
    assert_false(Bool(rss_line("TIME_RSS  1 2 3")))
    assert_false(Bool(rss_line("TIME_RSS 1 2")))
    assert_equal(
        bsd_peak("  1048576  maximum resident set size").value(), 1048576
    )
    assert_false(Bool(bsd_peak("1048576maximum resident set size")))
    assert_true(bsd_real("x\n        0.05 real         0.01 user\n"))
    assert_false(bsd_real("0.05 realtime"))
    var tree = JsonTree()
    var payload = read_payload(
        tree,
        (
            'noise\n {"backend": "webgl", "frames_ms": 20, "import_ms": true}'
            ' \n{bad}\n{"frames_ms": "x"}\n'
        ),
    )
    assert_equal(tree.text(payload.backend), "webgl")
    assert_equal(payload.frames_seconds.value(), 0.02)
    assert_equal(payload.import_seconds.value(), 0.001)
    assert_equal(refused_reason("\n  Crashpad x\n  error: é  \n"), "error: é")
    assert_equal(refused_reason("é" * 130), "é" * 120)
    assert_equal(refused_reason(" \n"), "refused")
    assert_equal(py_strip("  a b\t　"), "a b")


def test_numbers_are_shown_as_python_formats_them() raises:
    assert_equal(fmt_s(None), "—")
    assert_equal(fmt_s(12.25), "12.2")
    assert_equal(fmt_s(0.125), "0.12")
    assert_equal(fmt_s(0.0125), "0.013")
    assert_equal(fmt_s(-0.0001), "-0.000")
    assert_equal(fmt_mib(1536.0), "2")
    assert_equal(fmt_mib(None), "—")
    assert_equal(fmt_ratio(10.5), "10")
    assert_equal(fmt_ratio(2.25), "2.2")
    assert_equal(fmt_ratio(0.125), "0.12")
    assert_equal(python_round(0.00125, 4), 0.0013)
    assert_equal(python_round(2.675, 2), 2.67)
    assert_equal(winner_name(1.0, 1.05, "a", "b"), "tie")
    assert_equal(winner_name(1.0, 1.2, "a", "b"), "a")
    assert_equal(winner_name(2.0, 1.0, "a", "b"), "b")
    assert_equal(winner_name(None, 1.0, "a", "b"), "—")


def test_spans_are_replaced_without_reading_backslashes() raises:
    var text = "a<!-- BENCH:X -->old<!-- /BENCH:X -->b<!-- BENCH:X -->c"
    assert_equal(
        replace_span(text, "X", "\\1 new"),
        "a<!-- BENCH:X -->\n\\1 new\n<!-- /BENCH:X -->b<!-- BENCH:X -->c",
    )
    var missing = String()
    try:
        _ = replace_span("<!-- BENCH:X -->", "X", "")
    except error:
        missing = String(error)
    assert_equal(missing, "Benchmarks.md is missing <!-- BENCH:X -->")
    assert_equal(python_error("'run'"), "KeyError: 'run'")
    assert_equal(
        python_error("'NoneType' object has no attribute 'get'"),
        "AttributeError: 'NoneType' object has no attribute 'get'",
    )


# --- golden texts from tools/bench_examples.py ---------------------------------


comptime LINUX_RESULTS = (
    "{\n"
    '  "generated_at": "2026-10-01",\n'
    '  "host": {\n'
    '    "os": "Linux 6",\n'
    '    "cpu": "Fixture CPU",\n'
    '    "python": "3.12.3",\n'
    '    "mojo_1_1": "Mojo 1.1.0",\n'
    '    "mojo_1_0": "",\n'
    '    "node": "v22"\n'
    "  },\n"
    '  "threejs_webgl": true,\n'
    '  "baselines": {\n'
    '    "mojo": {\n'
    '      "ok": true,\n'
    '      "seconds": 0.0123,\n'
    '      "rss_kib": 2048,\n'
    '      "status": 0\n'
    "    },\n"
    '    "node": {\n'
    '      "ok": true,\n'
    '      "seconds": 0.04,\n'
    '      "rss_kib": 2048,\n'
    '      "status": 0\n'
    "    }\n"
    "  },\n"
    '  "mojo10_refused": 1,\n'
    '  "mojo10_total": 2,\n'
    '  "probe": {\n'
    '    "v11": {\n'
    '      "compile": {\n'
    '        "ok": true,\n'
    '        "seconds": 2.5,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      },\n"
    '      "run": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.25,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      }\n"
    "    },\n"
    '    "v10": {\n'
    '      "compile": {\n'
    '        "ok": true,\n'
    '        "seconds": 5.0,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      },\n"
    '      "run": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.26,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      }\n"
    "    }\n"
    "  },\n"
    '  "examples": [\n'
    "    {\n"
    '      "name": "triangle",\n'
    '      "measured_on": "2026-10-01",\n'
    '      "measurement_date_source": "direct",\n'
    '      "width": 32,\n'
    '      "height": 24,\n'
    '      "frames": 2,\n'
    '      "threemojo": {\n'
    '        "compile": {\n'
    '          "ok": true,\n'
    '          "seconds": 4.5,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        },\n"
    '        "run": {\n'
    '          "ok": true,\n'
    '          "seconds": 0.0125,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0,\n'
    '          "frames_seconds": 0.002\n'
    "        }\n"
    "      },\n"
    '      "threejs_flat": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.08,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0,\n'
    '        "frames_seconds": 0.0085,\n'
    '        "backend": "cpu-flat"\n'
    "      },\n"
    '      "threejs_webgl": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.09,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0,\n'
    '        "frames_seconds": 0.0021,\n'
    '        "backend": "webgl"\n'
    "      },\n"
    '      "mojo10": {\n'
    '        "compile": {\n'
    '          "ok": true,\n'
    '          "seconds": 13.4,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        },\n"
    '        "run": {\n'
    '          "ok": true,\n'
    '          "seconds": 0.0127,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        }\n"
    "      }\n"
    "    },\n"
    "    {\n"
    '      "name": "cube",\n'
    '      "width": 32,\n'
    '      "height": 24,\n'
    '      "frames": 2,\n'
    '      "threemojo": {\n'
    '        "compile": {\n'
    '          "ok": true,\n'
    '          "seconds": 12.0,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        },\n"
    '        "run": {\n'
    '          "ok": true,\n'
    '          "seconds": 0.5,\n'
    '          "rss_kib": 99999,\n'
    '          "status": 0,\n'
    '          "frames_seconds": 0.4\n'
    "        }\n"
    "      },\n"
    '      "threejs_flat": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.1,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0,\n'
    '        "frames_seconds": 0.05\n'
    "      },\n"
    '      "threejs_webgl": {\n'
    '        "ok": false,\n'
    '        "seconds": null,\n'
    '        "rss_kib": null,\n'
    '        "status": 1,\n'
    '        "error": "no context"\n'
    "      },\n"
    '      "mojo10": {\n'
    '        "compile": {\n'
    '          "ok": false,\n'
    '          "seconds": 1.0,\n'
    '          "rss_kib": null,\n'
    '          "status": 1,\n'
    '          "error": "refused"\n'
    "        }\n"
    "      }\n"
    "    }\n"
    "  ]\n"
    "}"
)
comptime MACOS_RESULTS = (
    "{\n"
    '  "generated_at": "2026-09-01",\n'
    '  "host": {\n'
    '    "os": "Linux 6",\n'
    '    "cpu": "Fixture CPU",\n'
    '    "python": "3.12.3",\n'
    '    "mojo_1_1": "Mojo 1.1.0",\n'
    '    "mojo_1_0": "",\n'
    '    "node": "v22"\n'
    "  },\n"
    '  "threejs_webgl": true,\n'
    '  "baselines": {\n'
    '    "mojo": {\n'
    '      "ok": true,\n'
    '      "seconds": 0.0123,\n'
    '      "rss_kib": 2048,\n'
    '      "status": 0\n'
    "    },\n"
    '    "node": {\n'
    '      "ok": true,\n'
    '      "seconds": 0.04,\n'
    '      "rss_kib": 2048,\n'
    '      "status": 0\n'
    "    }\n"
    "  },\n"
    '  "mojo10_refused": 1,\n'
    '  "mojo10_total": 2,\n'
    '  "probe": {\n'
    '    "v11": {\n'
    '      "compile": {\n'
    '        "ok": true,\n'
    '        "seconds": 2.5,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      },\n"
    '      "run": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.25,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      }\n"
    "    },\n"
    '    "v10": {\n'
    '      "compile": {\n'
    '        "ok": true,\n'
    '        "seconds": 5.0,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      },\n"
    '      "run": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.26,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0\n'
    "      }\n"
    "    }\n"
    "  },\n"
    '  "examples": [\n'
    "    {\n"
    '      "name": "triangle",\n'
    '      "measured_on": "2026-10-01",\n'
    '      "measurement_date_source": "direct",\n'
    '      "width": 32,\n'
    '      "height": 24,\n'
    '      "frames": 2,\n'
    '      "threemojo": {\n'
    '        "compile": {\n'
    '          "ok": true,\n'
    '          "seconds": 1.5,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        },\n"
    '        "run": {\n'
    '          "ok": true,\n'
    '          "seconds": 0.025,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0,\n'
    '          "frames_seconds": 0.002\n'
    "        }\n"
    "      },\n"
    '      "threejs_flat": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.08,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0,\n'
    '        "frames_seconds": 0.0085,\n'
    '        "backend": "cpu-flat"\n'
    "      },\n"
    '      "threejs_webgl": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.09,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0,\n'
    '        "frames_seconds": 0.0021,\n'
    '        "backend": "webgl"\n'
    "      },\n"
    '      "mojo10": {\n'
    '        "compile": {\n'
    '          "ok": true,\n'
    '          "seconds": 13.4,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        },\n"
    '        "run": {\n'
    '          "ok": true,\n'
    '          "seconds": 0.0127,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        }\n"
    "      }\n"
    "    },\n"
    "    {\n"
    '      "name": "cube",\n'
    '      "width": 32,\n'
    '      "height": 24,\n'
    '      "frames": 2,\n'
    '      "threemojo": {\n'
    '        "compile": {\n'
    '          "ok": true,\n'
    '          "seconds": 12.0,\n'
    '          "rss_kib": 2048,\n'
    '          "status": 0\n'
    "        },\n"
    '        "run": {\n'
    '          "ok": true,\n'
    '          "seconds": 0.5,\n'
    '          "rss_kib": 99999,\n'
    '          "status": 0,\n'
    '          "frames_seconds": 0.4\n'
    "        }\n"
    "      },\n"
    '      "threejs_flat": {\n'
    '        "ok": true,\n'
    '        "seconds": 0.1,\n'
    '        "rss_kib": 2048,\n'
    '        "status": 0,\n'
    '        "frames_seconds": 0.05\n'
    "      },\n"
    '      "threejs_webgl": {\n'
    '        "ok": false,\n'
    '        "seconds": null,\n'
    '        "rss_kib": null,\n'
    '        "status": 1,\n'
    '        "error": "no context"\n'
    "      },\n"
    '      "mojo10": {\n'
    '        "compile": {\n'
    '          "ok": false,\n'
    '          "seconds": 1.0,\n'
    '          "rss_kib": null,\n'
    '          "status": 1,\n'
    '          "error": "refused"\n'
    "        }\n"
    "      }\n"
    "    }\n"
    "  ]\n"
    "}"
)
comptime WIKI_BEFORE = (
    "# Benchmarks\n"
    "\n"
    "<!-- BENCH:SCORE:linux -->\n"
    "old\n"
    "<!-- /BENCH:SCORE:linux -->\n"
    "<!-- BENCH:CROSS -->\n"
    "<!-- /BENCH:CROSS -->\n"
    "<!-- BENCH:HOST:linux -->x<!-- /BENCH:HOST:linux -->\n"
    "<!-- BENCH:EXAMPLES:linux --><!-- /BENCH:EXAMPLES:linux -->\n"
    "<!-- BENCH:MOJO10:linux -->\n"
    "<!-- /BENCH:MOJO10:linux -->\n"
    "end\n"
)
comptime TABLES = (
    "| Example | Size | Frames | Compile (s) | Mojo draw (s) | cpu-flat draw"
    " (s) | WebGL draw (s) | Draw winner | Mojo RSS (MiB) | Measured"
    " |\n|---|---|---|---|---|---|---|---|---|---|\n| `triangle` | 32×24 | 2 |"
    " 4.50 | 0.002 | 0.009 | 0.002 | tie | 2 | 2026-10-01 |\n| `cube` | 32×24 |"
    " 2 | 12.0 | 0.40 | 0.050 | unavailable | cpu-flat | 98 | unknown (legacy:"
    " 2026-10-01) |\n\nA legacy date is from an older aggregate file; its"
    " per-row measurement date is unknown.\n\nDraw time is the frame loop"
    " inside the process.\nA gap under 10% is a tie.\ncpu-flat is a flat color"
    " fill with a depth test.\nWebGL is the three.js draw used for the language"
    " comparison.\n\n| Program | 1.1 compile (s) | 1.0 compile (s) | Compile"
    " winner | 1.1 run (s) | 1.0 run (s) | Run winner"
    " |\n|---|---|---|---|---|---|---|\n| `probe` | 2.50 | 5.00 | 1.1 | 0.25 |"
    " 0.26 | tie |\n| `triangle` | 4.50 | 13.4 | 1.1 | 0.013 | 0.013 | tie"
    " |\n\nPrograms in this table: 2.\nRefused catalog rows: 1.\nA refused"
    " compile is not a faster compile.\nThose rows stay out of this"
    " table.\n\nUpdated docs/wiki/Benchmarks.md\n"
)
comptime WIKI_AFTER = (
    "# Benchmarks\n\n<!-- BENCH:SCORE:linux -->\n### Linux\n\nWebGL is the draw"
    " comparison on this host.\n1 draw is within 10% and counts as a tie.\nThe"
    " median WebGL draw takes 1.0 times the ThreeMojo draw.\n\ncpu-flat is a"
    " flat color fill. It is not the same work.\nThe median cpu-flat draw takes"
    " 2.2 times the ThreeMojo draw.\n\nThreeMojo uses less memory on 0 of 1"
    " examples.\nThe median resident set is 50 MiB for ThreeMojo and 2 MiB for"
    " WebGL.\n\nWhole-process time includes startup and writing the image.\nThe"
    " median ThreeMojo process takes 0.26 s.\nThe median WebGL process takes"
    " 0.090 s.\nA Mojo program that does nothing takes 0.012 s.\nA Node process"
    " that does nothing takes 0.040 s.\nThe median Mojo 1.1 compile takes 8.25"
    " s.\n\nMojo 1.0 runs 2 programs.\nRefused programs: 1.\nA refused compile"
    " is not a faster compile.\nOn those programs, Mojo 1.1 compiles faster on"
    " 2 of 2.\n\n2 runs are within 10%.\n\nThe catalog lists 3 examples.\nThis"
    " host measures 2 of them.\n<!-- /BENCH:SCORE:linux -->\n<!-- BENCH:CROSS"
    " -->\nFor these saved runs, the median Linux/macOS whole-process time"
    " ratio is 0.75.\nThe median Linux/macOS compile-time ratio is 2.0.\nEach"
    " ratio is Linux time divided by macOS time.\n\nThe Linux date is"
    " 2026-10-01. The macOS date is 2026-09-01.\nThe source and software can"
    " differ between these snapshots.\nThese ratios do not isolate hardware"
    " speed.\nThe comparison uses 2 shared examples.\n<!-- /BENCH:CROSS"
    " -->\n<!-- BENCH:HOST:linux -->\n- Latest refresh: `2026-10-01`\n- OS:"
    " Linux 6\n- CPU: Fixture CPU\n- Mojo 1.1: `Mojo 1.1.0`\n- Mojo 1.0: `not"
    " installed`\n- Node: `v22`\n- three.js backends: `cpu-flat` and `webgl`\n-"
    " A Mojo program that does nothing: `0.012` s\n- A Node process that does"
    " nothing: `0.040` s\n<!-- /BENCH:HOST:linux -->\n<!-- BENCH:EXAMPLES:linux"
    " -->\n| Example | Size | Frames | Compile (s) | Mojo draw (s) | cpu-flat"
    " draw (s) | WebGL draw (s) | Draw winner | Mojo RSS (MiB) | Measured"
    " |\n|---|---|---|---|---|---|---|---|---|---|\n| `triangle` | 32×24 | 2 |"
    " 4.50 | 0.002 | 0.009 | 0.002 | tie | 2 | 2026-10-01 |\n| `cube` | 32×24 |"
    " 2 | 12.0 | 0.40 | 0.050 | unavailable | cpu-flat | 98 | unknown (legacy:"
    " 2026-10-01) |\n\nA legacy date is from an older aggregate file; its"
    " per-row measurement date is unknown.\n\nDraw time is the frame loop"
    " inside the process.\nA gap under 10% is a tie.\ncpu-flat is a flat color"
    " fill with a depth test.\nWebGL is the three.js draw used for the language"
    " comparison.\n<!-- /BENCH:EXAMPLES:linux -->\n<!-- BENCH:MOJO10:linux"
    " -->\n| Program | 1.1 compile (s) | 1.0 compile (s) | Compile winner | 1.1"
    " run (s) | 1.0 run (s) | Run winner |\n|---|---|---|---|---|---|---|\n|"
    " `probe` | 2.50 | 5.00 | 1.1 | 0.25 | 0.26 | tie |\n| `triangle` | 4.50 |"
    " 13.4 | 1.1 | 0.013 | 0.013 | tie |\n\nPrograms in this table: 2.\nRefused"
    " catalog rows: 1.\nA refused compile is not a faster compile.\nThose rows"
    " stay out of this table.\n<!-- /BENCH:MOJO10:linux -->\nend\n"
)

comptime HELP_60 = (
    "usage: bench_examples [-h] [--only ONLY] [--merge]\n"
    "                      [--skip-threejs] [--skip-webgl]\n"
    "                      [--skip-mojo10] [--write-wiki]\n"
    "                      [--no-write-wiki] [--from-results]\n"
    "                      [--platform {linux,macos}]\n"
    "\n"
    "Time cataloged examples against three.js and, when\n"
    "present, Mojo 1.0.\n"
    "\n"
    "options:\n"
    "  -h, --help            show this help message and exit\n"
    "  --only ONLY           Comma-separated example names to\n"
    "                        measure\n"
    "  --merge               Merge into this host's existing\n"
    "                        bench/results-<platform>.json\n"
    "  --skip-threejs        Skip the three.js runner\n"
    "  --skip-webgl          Time cpu-flat only. Use this when\n"
    "                        the host has no GPU.\n"
    "  --skip-mojo10         Skip the Mojo 1.0 comparison\n"
    "  --write-wiki          Update docs/wiki/Benchmarks.md\n"
    "                        tables\n"
    "  --no-write-wiki\n"
    "  --from-results        Rebuild wiki tables from\n"
    "                        bench/results-<platform>.json\n"
    "  --platform {linux,macos}\n"
    "                        Which host's tables --from-results\n"
    "                        rebuilds (default: this host)\n"
)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
