# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Build and compare complete ray workloads in balanced serial paired order.

    mojo run -I . bench/run_ray_query_bench.mojo --baseline B --candidate C --output OUT --cpu N [--mojo MOJO] [--pairs 8] [--samples 5] [--repeats 4000]

Supply two source roots. This tool uses identical benchmark drivers from the
candidate root for both builds. It never edits either input tree. Output
must be outside both source roots. No GPU timings are measured by this
runner.

The summary statistics are those of the Python runner that this tool
replaces, digit for digit: `statistics.median`, and `statistics.quantiles`
with its default exclusive method.
"""

from std.collections import Dict, Set
from std.math import isfinite
from std.os import getenv, makedirs
from std.os.path import exists
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.time import perf_counter_ns

from tools._fraction import Fraction
from tools._imports import walk_files
from tools._json_tools import JsonWriter, quote_ascii
from tools._process import run_program
from tools._python_float import parse_float, python_repr
from tools._sha256 import sha256_hex
from tools._text import split_lines

comptime SOURCE = "bench/run_ray_query_bench.mojo"
"""This file, relative to the candidate root."""
comptime SKIPPED = [".cache", "out", ".venv", ".git"]
"""Path parts that leave a file out of a source inventory."""
comptime KINDS = ["queries", "consumers"]
"""The benchmark drivers, in run order."""


def digest(path: String) raises -> String:
    """Return the SHA-256 digest of a complete file.

    Args:
        path: The file.

    Returns:
        The digest, as hex.

    Raises:
        Error: If the file cannot be read.
    """
    return sha256_hex(Span(Path(path).read_bytes()))


def inventory(root: String) raises -> List[Tuple[String, String]]:
    """Hash all source files, excluding generated cache and environment roots.

    Args:
        root: The source root.

    Returns:
        Each `.mojo` file's relative path and digest, sorted by path.

    Raises:
        Error: If a file cannot be read.
    """
    comptime skipped = SKIPPED
    var paths = List[String]()
    for path in walk_files(root, "", False):
        if not path.endswith(".mojo"):
            continue
        var keep = True
        for part in path.split("/"):
            for name in materialize[skipped]():
                if part == name:
                    keep = False
        if keep:
            paths.append(path)
    sort(paths)
    var out = List[Tuple[String, String]]()
    for path in paths:
        out.append((path, digest(root + "/" + path)))
    return out^


def _object_text(entries: List[Tuple[String, String]], compact: Bool) -> String:
    """Return `json.dumps(dict, sort_keys=True)` of a sorted string map."""
    var out = String("{")
    for index in range(len(entries)):
        if index > 0:
            out += "," if compact else ", "
        out += quote_ascii(entries[index][0])
        out += ":" if compact else ": "
        out += quote_ascii(entries[index][1])
    return out + "}"


def canonical_digest(entries: List[Tuple[String, String]]) -> String:
    """Hash a sorted string map as Python's compact sorted JSON.

    Args:
        entries: The map, sorted by key.

    Returns:
        The SHA-256 of the JSON text, as hex.
    """
    return sha256_hex(_object_text(entries, True).as_bytes())


@fieldwise_init
struct Row(Copyable, Movable):
    """One workload measurement."""

    var pair: Int
    """The paired round."""
    var position: Int
    """The variant's position in its round."""
    var sample: Int
    """The sample within the round."""
    var variant: String
    """`baseline` or `candidate`."""
    var workload: String
    """The workload name."""
    var calls: Int
    """The calls the workload made."""
    var ns: Int
    """The elapsed nanoseconds."""
    var checksum: String
    """The result checksum, as the driver printed it."""


@fieldwise_init
struct Num(ImplicitlyCopyable, Movable):
    """A number, and whether Python held it as an int."""

    var value: Float64
    """The value."""
    var whole: Bool
    """True for an int."""


def _exact_product(a: Float64, b: Float64) raises -> Float64:
    """Return a * b rounded once, which no fused multiply-add can change."""
    return (Fraction.from_float(a) * Fraction.from_float(b)).to_float()


def median(values: List[Num]) -> Num:
    """Return `statistics.median`.

    Args:
        values: The samples, all ints or all floats.

    Returns:
        The middle sample, or the mean of the middle two.
    """
    var ordered = List[Float64]()
    for item in values:
        ordered.append(item.value)
    sort(ordered)
    var middle = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return Num(ordered[middle], values[0].whole)
    return Num((ordered[middle - 1] + ordered[middle]) / 2.0, False)


def quartiles(values: List[Float64]) raises -> Tuple[Float64, Float64]:
    """Return the first and third of `statistics.quantiles(values)`.

    Python's default is four groups with the exclusive method.

    Args:
        values: At least two floats.

    Returns:
        The first and third quartiles.

    Raises:
        Error: If there are fewer than two values.
    """
    if len(values) < 2:
        raise Error("must have at least two data points")
    var data = values.copy()
    sort(data)
    var count = len(data)
    var m = count + 1
    var result = List[Float64]()
    for i in [1, 3]:
        var j = i * m // 4
        j = 1 if j < 1 else (count - 1 if j > count - 1 else j)
        var delta = i * m - j * 4
        var low = _exact_product(data[j - 1], Float64(4 - delta))
        var high = _exact_product(data[j], Float64(delta))
        result.append((low + high) / 4.0)
    return (result[0], result[1])


def read_trials(text: String) raises -> List[Row]:
    """Read a trials CSV file.

    Args:
        text: The CSV text, with a header row.

    Returns:
        The rows.

    Raises:
        Error: If a number does not parse.
    """
    var rows = List[Row]()
    var lines = split_lines(text)
    for line in lines[1:]:
        var clean = String(line.rstrip("\r"))
        if clean.byte_length() == 0:
            continue
        var cells = clean.split(",")
        rows.append(
            Row(
                Int(String(cells[0])),
                Int(String(cells[1])),
                Int(String(cells[2])),
                String(cells[3]),
                String(cells[4]),
                Int(String(cells[5])),
                Int(String(cells[6])),
                String(cells[7]),
            )
        )
    return rows^


def summarize(rows: List[Row], pairs: Int) raises -> String:
    """Return the summary JSON, sorted, with two-space indents.

    Args:
        rows: The measurements, in run order.
        pairs: The paired rounds.

    Returns:
        The summary text, without a final newline.

    Raises:
        Error: If a workload has fewer than two samples for a variant.
    """
    var workloads = List[String]()
    var checksums = Dict[String, String]()
    for row in rows:
        if row.workload not in checksums:
            checksums[row.workload] = row.checksum
            workloads.append(row.workload)
    sort(workloads)
    var variants: List[String] = ["baseline", "candidate"]
    var out = JsonWriter()
    out.begin_object()
    for work in workloads:
        var medians = Dict[String, Num]()
        out.key(work)
        out.begin_object()
        for variant in variants:
            var values = List[Float64]()
            var lowest = 0.0
            var highest = 0.0
            for row in rows:
                if row.variant == variant and row.workload == work:
                    var ms = Float64(row.ns) / 1e6
                    if len(values) == 0 or ms < lowest:
                        lowest = ms
                    if len(values) == 0 or ms > highest:
                        highest = ms
                    values.append(ms)
            var as_nums = List[Num]()
            for item in values:
                as_nums.append(Num(item, False))
            var middle = median(as_nums)
            medians[variant] = middle
            var quarters = quartiles(values)
            out.key(variant)
            out.begin_object()
            out.key("max_ms")
            out.number(highest)
            out.key("median_ms")
            out.number(middle.value)
            out.key("min_ms")
            out.number(lowest)
            out.key("q1_ms")
            out.number(quarters[0])
            out.key("q3_ms")
            out.number(quarters[1])
            out.key("samples")
            out.integer(len(values))
            out.end()
        out.key("checksum")
        out.string(checksums[work])
        out.key("median_ratio")
        out.number(medians["candidate"].value / medians["baseline"].value)
        var ratios = List[Num]()
        for pair in range(pairs):
            var round = Dict[String, Num]()
            for variant in variants:
                var samples = List[Num]()
                for row in rows:
                    if (
                        row.pair == pair
                        and row.variant == variant
                        and row.workload == work
                    ):
                        samples.append(Num(Float64(row.ns), True))
                round[variant] = median(samples)
            ratios.append(
                Num(round["candidate"].value / round["baseline"].value, False)
            )
        out.key("paired_round_median_ratio")
        out.number(median(ratios).value)
        out.key("paired_round_ratios")
        out.begin_array()
        for ratio in ratios:
            out.number(ratio.value)
        out.end()
        out.end()
    out.end()
    return out.text()


def _row_json(row: Row) -> String:
    """Return `json.dumps(row, sort_keys=True)`."""
    return (
        '{"calls": '
        + String(row.calls)
        + ', "checksum": '
        + quote_ascii(row.checksum)
        + ', "ns": '
        + String(row.ns)
        + ', "pair": '
        + String(row.pair)
        + ', "position": '
        + String(row.position)
        + ', "sample": '
        + String(row.sample)
        + ', "variant": '
        + quote_ascii(row.variant)
        + ', "workload": '
        + quote_ascii(row.workload)
        + "}"
    )


def _row_csv(row: Row) -> String:
    """Return a trials CSV row, ended as Python's `csv` ends it."""
    return (
        String(row.pair)
        + ","
        + String(row.position)
        + ","
        + String(row.sample)
        + ","
        + row.variant
        + ","
        + row.workload
        + ","
        + String(row.calls)
        + ","
        + String(row.ns)
        + ","
        + row.checksum
        + "\r\n"
    )


@fieldwise_init
struct Build(Copyable, Movable):
    """One compiled driver."""

    var name: String
    """`VARIANT-KIND`."""
    var seconds: Float64
    """The build's wall time."""
    var sha256: String
    """The binary's digest."""
    var file_bytes: Int
    """The binary's size."""
    var text_bytes: Int
    """The text segment size."""
    var data_bytes: Int
    """The data segment size."""
    var bss_bytes: Int
    """The BSS segment size."""


struct Options(Movable):
    """The command line."""

    var baseline: String
    """The baseline source root."""
    var candidate: String
    """The candidate source root."""
    var output: String
    """The new output folder."""
    var mojo: String
    """The compiler."""
    var cpu: Int
    """The logical CPU to run on."""
    var pairs: Int
    """The paired rounds, a positive even number."""
    var samples: Int
    """The samples of each binary in each round."""
    var repeats: Int
    """The query driver's repeats."""

    def __init__(out self):
        """Start with the defaults."""
        self.baseline = String()
        self.candidate = String()
        self.output = String()
        self.mojo = "mojo"
        self.cpu = -1
        self.pairs = 8
        self.samples = 5
        self.repeats = 4000


def parse_options(given: List[String]) raises -> Options:
    """Read the command line.

    Args:
        given: The arguments after the program name.

    Returns:
        The options.

    Raises:
        Error: If an argument is unknown, missing or out of range.
    """
    var options = Options()
    var index = 0
    while index < len(given):
        var word = given[index]
        if index + 1 >= len(given):
            raise Error("expected one argument after " + word)
        var text = given[index + 1]
        if word == "--baseline":
            options.baseline = text
        elif word == "--candidate":
            options.candidate = text
        elif word == "--output":
            options.output = text
        elif word == "--mojo":
            options.mojo = text
        elif word == "--cpu":
            options.cpu = Int(text)
        elif word == "--pairs":
            options.pairs = Int(text)
        elif word == "--samples":
            options.samples = Int(text)
        elif word == "--repeats":
            options.repeats = Int(text)
        else:
            raise Error("unrecognized argument: " + word)
        index += 2
    if (
        not options.baseline
        or not options.candidate
        or not options.output
        or options.cpu < 0
    ):
        raise Error(
            "the arguments --baseline, --candidate, --output and --cpu are"
            " required"
        )
    if (
        options.pairs <= 0
        or options.pairs % 2 != 0
        or options.samples <= 0
        or options.repeats <= 0
    ):
        raise Error(
            "pairs must be positive and even; samples and repeats must be"
            " positive"
        )
    return options^


def _absolute(path: String) raises -> String:
    """Return a path made absolute against the working directory."""
    if path.startswith("/"):
        return path
    var here = run_program(["pwd", "-P"], 10.0)
    return String(here.output.rstrip("\n")) + "/" + path


def _command_output(command: List[String]) raises -> String:
    """Run a command that must succeed and return its standard output."""
    var result = run_program(command, 600.0, merge_errors=False)
    if result.status != 0:
        raise Error("command failed: " + " ".join(command))
    return result.output


def _write_commands(mut out: JsonWriter, commands: List[List[String]]):
    """Write a list of commands."""
    out.begin_array()
    for command in commands:
        out.begin_array()
        for word in command:
            out.string(word)
        out.end()
    out.end()


def _write_private(
    path: String,
    options: Options,
    roots: List[String],
    output: String,
    compiler: String,
    builds: List[List[String]],
    runs: List[List[String]],
    kernel: String,
    models: List[String],
) raises:
    """Write the private provenance, which is not published."""
    var out = JsonWriter()
    out.begin_object()
    out.key("cpu_affinity")
    out.integer(options.cpu)
    out.key("kernel")
    out.string(kernel)
    out.key("source_roots")
    out.begin_object()
    out.key("baseline")
    out.string(roots[0])
    out.key("candidate")
    out.string(roots[1])
    out.end()
    out.key("output")
    out.string(output)
    out.key("compiler")
    out.string(compiler)
    out.key("build_commands")
    _write_commands(out, builds)
    out.key("run_commands")
    _write_commands(out, runs)
    out.key("telemetry_enabled")
    var telemetry = getenv("MODULAR_TELEMETRY_ENABLED", "\0")
    if telemetry == "\0":
        out.null()
    else:
        out.string(telemetry)
    if len(models) > 0:
        out.key("cpu_models")
        out.begin_array()
        for model in models:
            out.string(model)
        out.end()
    out.end()
    Path(path).write_text(out.text() + "\n")


def _write_metadata(
    path: String,
    options: Options,
    toolchain: String,
    system: String,
    machine: String,
    runner: String,
    inventories: List[String],
    drivers: List[String],
    builds: List[Build],
    rows: Int,
) raises:
    """Write the published metadata, keys sorted; `rows` < 0 while running."""
    var out = JsonWriter()
    out.begin_object()
    out.key("builds")
    out.begin_object()
    for build in builds:
        out.key(build.name)
        out.begin_object()
        out.key("binary_sha256")
        out.string(build.sha256)
        out.key("bss_bytes")
        out.integer(build.bss_bytes)
        out.key("data_bytes")
        out.integer(build.data_bytes)
        out.key("file_bytes")
        out.integer(build.file_bytes)
        out.key("text_bytes")
        out.integer(build.text_bytes)
        out.key("wall_seconds")
        out.number(build.seconds)
        out.end()
    out.end()
    out.key("cpu_affinity")
    out.string("one fixed logical CPU")
    out.key("driver_sha256")
    out.begin_object()
    out.key("consumers")
    out.string(drivers[1])
    out.key("queries")
    out.string(drivers[0])
    out.end()
    out.key("flags")
    out.begin_array()
    for flag in ["build", "--Werror", "-I", "SOURCE"]:
        out.string(flag)
    out.end()
    out.key("history")
    out.string(
        "Query/Gaussian drivers reconstructed from issue 550; physics"
        " geometry newly specified. Historical binaries are not used."
    )
    out.key("pairs")
    out.integer(options.pairs)
    out.key("platform")
    out.begin_object()
    out.key("architecture")
    out.string(machine)
    out.key("os")
    out.string(system)
    out.end()
    out.key("repeats")
    out.integer(options.repeats)
    if rows >= 0:
        out.key("rows")
        out.integer(rows)
    out.key("runner_sha256")
    out.string(runner)
    out.key("samples_per_binary_per_pair")
    out.integer(options.samples)
    out.key("schema")
    out.integer(1)
    out.key("source_inventory_sha256")
    out.begin_object()
    out.key("baseline")
    out.string(inventories[0])
    out.key("candidate")
    out.string(inventories[1])
    out.end()
    out.key("status")
    out.string("complete" if rows >= 0 else "running")
    out.key("toolchain")
    out.string(toolchain)
    if rows >= 0:
        out.key("verified_unchanged_sources_and_binaries")
        out.boolean(True)
    out.key("workloads")
    out.begin_object()
    out.key("gaussian")
    out.string(
        "4096000 splat-candidate visits in 1000 public raycast calls; every"
        " returned field consumed"
    )
    out.key("physics_mesh")
    out.string(
        "2048 triangles, prepared Octree, 5600 rays; full PhysicsWorld.raycast"
        " with every returned field consumed"
    )
    out.key("queries")
    out.string(
        "256 stored rays repeated without reducing work; every point"
        " coordinate consumed"
    )
    out.end()
    out.end()
    Path(path).write_text(out.text() + "\n")


def _expected_calls(kind: String, workload: String, repeats: Int) -> Int:
    """Return a workload's expected call count, or -1 for an unknown one."""
    if kind == "queries":
        if (
            workload == "sphere_point"
            or workload == "sphere_bool"
            or workload == "box_point"
            or workload == "box_bool"
        ):
            return 256 * repeats
        return -1
    if workload == "gaussian":
        return 4096000
    if workload == "physics_mesh":
        return 5600
    return -1


def run(options: Options) raises -> String:
    """Build both variants, validate every trial, and save complete evidence.

    Args:
        options: The command line.

    Returns:
        The summary JSON.

    Raises:
        Error: If a build, a run or a validation fails.
    """
    var roots: List[String] = [
        _absolute(options.baseline),
        _absolute(options.candidate),
    ]
    var names: List[String] = ["baseline", "candidate"]
    var out = _absolute(options.output)
    for root in roots:
        if out == root or out.startswith(root + "/"):
            raise Error("output must be outside both source roots")
    if exists(out):
        raise Error("the output folder already exists: " + out)
    makedirs(out)
    comptime kinds = KINDS
    var drivers: List[String] = [
        roots[1] + "/bench/ray_query_bench.mojo",
        roots[1] + "/bench/ray_query_consumers.mojo",
    ]
    var inventories = List[List[Tuple[String, String]]]()
    var inventory_digests = List[String]()
    for root in roots:
        var found = inventory(root)
        inventory_digests.append(canonical_digest(found))
        inventories.append(found^)
    var driver_digests: List[String] = [digest(drivers[0]), digest(drivers[1])]
    var toolchain = String(_command_output([options.mojo, "--version"]).strip())
    var system = String(_command_output(["uname", "-s"]).strip())
    var machine = String(_command_output(["uname", "-m"]).strip())
    var kernel = String(_command_output(["uname", "-r"]).strip())
    var compiler = _absolute(options.mojo)
    var runner = digest(roots[1] + "/" + SOURCE)
    var models = List[String]()
    if exists("/proc/cpuinfo"):
        var seen = Set[String]()
        for line in split_lines(Path("/proc/cpuinfo").read_text()):
            if line.startswith("model name"):
                var model = String(line[byte = line.find(":") + 1 :].strip())
                if model not in seen:
                    seen.add(model)
                    models.append(model)
        sort(models)
    var build_commands = List[List[String]]()
    var run_commands = List[List[String]]()
    _write_private(
        out + "/private-provenance.json",
        options,
        roots,
        out,
        compiler,
        build_commands,
        run_commands,
        kernel,
        models,
    )
    var inventory_text = String("{")
    for index in range(2):
        if index > 0:
            inventory_text += ", "
        inventory_text += (
            quote_ascii(names[index])
            + ": "
            + _object_text(inventories[index], False)
        )
    Path(out + "/source-inventories.json").write_text(inventory_text + "}\n")
    var builds = List[Build]()
    for variant in range(2):
        for kind in range(2):
            var name = names[variant] + "-" + String(materialize[kinds]()[kind])
            var binary = out + "/" + name
            var started = perf_counter_ns()
            var command: List[String] = [
                options.mojo,
                "build",
                "--Werror",
                "-I",
                roots[variant],
                drivers[kind],
                "-o",
                binary,
            ]
            build_commands.append(command.copy())
            var result = run_program(command, 3600.0, merge_errors=False)
            var elapsed = Float64(perf_counter_ns() - started) / 1e9
            Path(out + "/" + name + "-build.log").write_text(
                result.output + result.errors
            )
            if result.status != 0:
                raise Error("build failed: " + name)
            var size = split_lines(_command_output(["size", binary]))[1].split()
            builds.append(
                Build(
                    name,
                    elapsed,
                    digest(binary),
                    len(Path(binary).read_bytes()),
                    Int(String(size[0])),
                    Int(String(size[1])),
                    Int(String(size[2])),
                )
            )
            print(
                "Built",
                names[variant],
                materialize[kinds]()[kind],
                python_repr(Float64(Int(elapsed * 1000.0 + 0.5)) / 1000.0),
            )
    _write_metadata(
        out + "/metadata.json",
        options,
        toolchain,
        system,
        machine,
        runner,
        inventory_digests,
        driver_digests,
        builds,
        -1,
    )
    var rows = List[Row]()
    var checksums = Dict[String, String]()
    var jsonl = String()
    for pair in range(options.pairs):
        var order: List[Int] = [0, 1] if pair % 2 == 0 else [1, 0]
        for position in range(2):
            var variant = order[position]
            for sample in range(options.samples):
                for kind in range(2):
                    var kind_name = String(materialize[kinds]()[kind])
                    var command: List[String] = [
                        "taskset",
                        "-c",
                        String(options.cpu),
                        out + "/" + names[variant] + "-" + kind_name,
                    ]
                    if kind_name == "queries":
                        command.append(String(options.repeats))
                    run_commands.append(command.copy())
                    var output = _command_output(command)
                    var seen = Set[String]()
                    for line in split_lines(output):
                        var cells = line.split(",")
                        if len(cells) != 4:
                            raise Error("malformed driver line: " + line)
                        var workload = String(cells[0])
                        var calls = Int(String(cells[1]))
                        var ns = Int(String(cells[2]))
                        var checksum = String(cells[3])
                        var expected = _expected_calls(
                            kind_name, workload, options.repeats
                        )
                        if expected < 0 or workload in seen:
                            raise Error("unexpected workload: " + workload)
                        if calls != expected or ns <= 0:
                            raise Error("wrong call count or time: " + line)
                        if not isfinite(parse_float(checksum)):
                            raise Error("nonfinite result checksum")
                        seen.add(workload)
                        if workload not in checksums:
                            checksums[workload] = checksum
                        if checksum != checksums[workload]:
                            raise Error(
                                "checksum mismatch: "
                                + names[variant]
                                + " "
                                + workload
                            )
                        var row = Row(
                            pair,
                            position,
                            sample,
                            names[variant],
                            workload,
                            calls,
                            ns,
                            checksum,
                        )
                        jsonl += _row_json(row) + "\n"
                        rows.append(row^)
                    var wanted = 4 if kind_name == "queries" else 2
                    if len(seen) != wanted:
                        raise Error("a driver left out a workload")
                    Path(out + "/trials.jsonl").write_text(jsonl)
            print("Completed pair", pair)
    for index in range(2):
        var now = inventory(roots[index])
        var same = len(now) == len(inventories[index])
        if same:
            for item in range(len(now)):
                if (
                    now[item][0] != inventories[index][item][0]
                    or now[item][1] != inventories[index][item][1]
                ):
                    same = False
        if not same:
            raise Error("source changed during measurement: " + names[index])
    for build in builds:
        if digest(out + "/" + build.name) != build.sha256:
            raise Error("binary changed during measurement: " + build.name)
    var csv = String(
        "pair,position,sample,variant,workload,calls,ns,checksum\r\n"
    )
    for row in rows:
        csv += _row_csv(row)
    Path(out + "/trials.csv").write_text(csv)
    var summary = summarize(rows, options.pairs)
    _write_private(
        out + "/private-provenance.json",
        options,
        roots,
        out,
        compiler,
        build_commands,
        run_commands,
        kernel,
        models,
    )
    _write_metadata(
        out + "/metadata.json",
        options,
        toolchain,
        system,
        machine,
        runner,
        inventory_digests,
        driver_digests,
        builds,
        len(rows),
    )
    Path(out + "/summary.json").write_text(summary + "\n")
    return summary


def main() raises:
    var given = argv()
    var words = List[String]()
    for index in range(1, len(given)):
        words.append(String(given[index]))
    var options = Options()
    try:
        options = parse_options(words)
    except error:
        print("run_ray_query_bench: error:", error, file=stderr)
        exit(2)
    print(run(options))
