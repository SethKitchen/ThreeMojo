# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Validate and summarize the complete owned-snapshot benchmark CSV files.

    mojo run -I . bench/physics_snapshot_report.mojo NATIVE ALLOCATIONS OUTPUT [--small-recheck CSV] [--source-manifest JSON]

Run it from the repository root. The report is the one that the Python
report generator wrote, number for number. Only `analysis_source_sha256`
differs: it hashes this file.
"""

from std.collections import Dict, Set
from std.math import floor
from std.pathlib import Path
from std.sys import argv, exit, stderr

from loaders.json import parse_json
from tools._json_tools import JsonWriter
from tools._python_float import parse_float
from tools._sha256 import sha256_hex
from tools._text import split_lines

comptime SOURCE = "bench/physics_snapshot_report.mojo"
"""This file, relative to the repository root."""
comptime INTEGER_FIELDS = [
    "static",
    "moving",
    "distribution",
    "repetition",
    "ns",
    "peak_bytes",
    "total_bytes",
    "allocations",
    "live_bytes",
    "work",
    "pairs",
    "geometry_bytes",
    "index_bytes",
    "metadata_bytes",
]
"""The integer columns, in the order a `Row` keeps them."""
comptime LAYOUTS = ["grid", "overlapping_x", "clusters", "coincident"]
"""The names of the four layouts."""
comptime RAY_PHASES = [
    "ray_linear_1024",
    "ray_frozen_linear_1024",
    "ray_snapshot_1024",
    "ray_forced_index_1024",
]
"""The ray batch phases."""
comptime SMALL_PHASES = [
    "snapshot_build",
    "forced_index_build",
    "ray_linear_1024",
    "ray_frozen_linear_1024",
    "ray_snapshot_1024",
    "ray_forced_index_1024",
]
"""The phases of the small worlds."""


def field_index(name: String) raises -> Int:
    """Return the position of an integer column.

    Args:
        name: The column name.

    Returns:
        Its position in `Row.values`.

    Raises:
        Error: If the column is not an integer column.
    """
    comptime fields = INTEGER_FIELDS
    var index = 0
    for field in materialize[fields]():
        if field == name:
            return index
        index += 1
    raise Error("not an integer column: " + name)


@fieldwise_init
struct Row(Copyable, Movable):
    """One measured sample."""

    var group: String
    """The case group."""
    var phase: String
    """The measured phase."""
    var values: List[Int]
    """The integer columns, in `INTEGER_FIELDS` order."""
    var checksum: Float64
    """The answer checksum."""

    def get(self, name: String) raises -> Int:
        """Return an integer column.

        Args:
            name: The column name.

        Returns:
            The value.

        Raises:
            Error: If the column is not an integer column.
        """
        return self.values[field_index(name)]


def read_rows(path: String) raises -> List[Row]:
    """Read a benchmark CSV file.

    Args:
        path: The file.

    Returns:
        The rows.

    Raises:
        Error: If a column is missing or a number does not parse.
    """
    var lines = split_lines(Path(path).read_text())
    var header = lines[0].split(",")
    var columns = Dict[String, Int]()
    for index in range(len(header)):
        columns[String(header[index])] = index
    comptime fields = INTEGER_FIELDS
    var rows = List[Row]()
    for line in lines[1:]:
        if line.byte_length() == 0:
            continue
        var cells = line.split(",")
        var values = List[Int]()
        for field in materialize[fields]():
            values.append(Int(String(cells[columns[field]])))
        rows.append(
            Row(
                String(cells[columns["group"]]),
                String(cells[columns["phase"]]),
                values^,
                parse_float(String(cells[columns["checksum"]])),
            )
        )
    return rows^


def key(
    group: String, static: Int, moving: Int, layout: Int, phase: String
) -> String:
    """Return a case key.

    Args:
        group: The case group.
        static: The static count.
        moving: The moving count, or the permuted percent.
        layout: The layout.
        phase: The phase.

    Returns:
        The key.
    """
    return (
        group
        + " "
        + String(static)
        + " "
        + String(moving)
        + " "
        + String(layout)
        + " "
        + phase
    )


def _row_key(row: Row) raises -> String:
    """Return a row's case key."""
    return key(
        row.group,
        row.get("static"),
        row.get("moving"),
        row.get("distribution"),
        row.phase,
    )


def _phase_of(case_key: String) -> String:
    """Return a case key's phase."""
    return String(case_key[byte = case_key.rfind(" ") + 1 :])


def _prefix_of(case_key: String) -> String:
    """Return a case key without its phase."""
    return String(case_key[byte = : case_key.rfind(" ")])


def load(path: String, repeats: Int) raises -> Dict[String, List[Row]]:
    """Read rows, reject incomplete or inconsistent measurements, and group.

    Args:
        path: The CSV file.
        repeats: The repetitions of each case.

    Returns:
        The rows of each case.

    Raises:
        Error: If a case is missing, extra, incomplete or inconsistent.
    """
    var grouped = Dict[String, List[Row]]()
    for row in read_rows(path):
        var name = _row_key(row)
        if name not in grouped:
            grouped[name] = List[Row]()
        grouped[name].append(row.copy())
    var required = Dict[String, Int]()
    comptime ray_phases = RAY_PHASES
    comptime small_phases = SMALL_PHASES
    for n in [100, 1000, 10000]:
        for moving in [1, 10, 100]:
            for layout in range(4):
                for phase in [
                    "sweep_query",
                    "dynamic_prepare",
                    "dynamic_query",
                    "snapshot_build",
                    "forced_index_build",
                ]:
                    required[key("corpus", n, moving, layout, phase)] = repeats
                if moving == 10:
                    for phase in materialize[ray_phases]():
                        required[
                            key("corpus", n, moving, layout, phase)
                        ] = repeats
                    required[
                        key(
                            "corpus",
                            n,
                            moving,
                            layout,
                            "frozen_after_release_1024",
                        )
                    ] = 1
    for n in [0, 1, 4, 8, 16, 32, 64]:
        for layout in range(4):
            for phase in materialize[small_phases]():
                required[key("small", n, 0, layout, phase)] = repeats
    for n in [100, 1000, 10000]:
        for percent in [0, 25, 50, 100]:
            for phase in [
                "index_refit",
                "index_rebuild",
                "refit_ray_1024",
                "rebuilt_ray_1024",
            ]:
                required[key("refit", n, percent, 0, phase)] = repeats
    var missing = 0
    for name in required.keys():
        if name not in grouped:
            missing += 1
    var extra = 0
    for name in grouped.keys():
        if name not in required:
            extra += 1
    if missing or extra:
        raise Error(
            "Case set differs: missing "
            + String(missing)
            + " cases, extra "
            + String(extra)
            + " cases"
        )
    for entry in required.items():
        var expected = List[Int]()
        if _phase_of(entry.key) == "frozen_after_release_1024":
            expected.append(repeats - 1)
        else:
            for index in range(entry.value):
                expected.append(index)
        var found = List[Int]()
        for row in grouped[entry.key]:
            found.append(row.get("repetition"))
        sort(found)
        if found != expected:
            raise Error("Wrong sample set for " + entry.key)
        for row in grouped[entry.key]:
            if row.get("ns") < 0 or not (
                0 <= row.get("live_bytes")
                and row.get("live_bytes") <= row.get("peak_bytes")
                and row.get("peak_bytes") <= row.get("total_bytes")
            ):
                raise Error(
                    "Invalid timing or memory counters for " + entry.key
                )
    for entry in grouped.items():
        var phase = _phase_of(entry.key)
        if not (
            phase == "ray_frozen_linear_1024"
            or phase == "ray_snapshot_1024"
            or phase == "ray_forced_index_1024"
            or phase == "frozen_after_release_1024"
        ):
            continue
        var expected = Dict[Int, Float64]()
        for row in grouped[_prefix_of(entry.key) + " ray_linear_1024"]:
            expected[row.get("repetition")] = row.checksum
        for row in entry.value:
            if row.checksum != expected[row.get("repetition")]:
                raise Error("Answer checksum mismatch for " + entry.key)
    return grouped^


@fieldwise_init
struct Num(ImplicitlyCopyable, Movable):
    """A number, an int when Python held an int, or `None`."""

    var value: Float64
    """The value."""
    var whole: Bool
    """True for an int."""
    var none: Bool
    """True for `None`."""


def median_of(values: List[Int]) -> Num:
    """Return `statistics.median` of ints.

    Args:
        values: The samples.

    Returns:
        The middle sample, or the float mean of the middle two.
    """
    var ordered = values.copy()
    sort(ordered)
    var middle = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return Num(Float64(ordered[middle]), True, False)
    return Num(
        Float64(ordered[middle - 1] + ordered[middle]) / 2.0, False, False
    )


def value(
    rows: Dict[String, List[Row]],
    prefix: String,
    phase: String,
    field: String = "ns",
) raises -> Num:
    """Return a phase's sample median without mixing native and hooked runs.

    Args:
        rows: The grouped rows.
        prefix: The case key without its phase.
        phase: The phase.
        field: The integer column.

    Returns:
        The median.

    Raises:
        Error: If the case is missing.
    """
    var samples = List[Int]()
    for row in rows[prefix + " " + phase]:
        samples.append(row.get(field))
    return median_of(samples)


def ratio(a: Num, b: Num) -> Num:
    """Return `a / b` as Python's true division gives it.

    Args:
        a: The dividend.
        b: The divisor.

    Returns:
        The quotient, a float.
    """
    return Num(a.value / b.value, False, False)


def break_even(build: Num, live: Num, frozen: Num) -> Num:
    """Estimate strict query-count break-even from per-batch medians.

    Args:
        build: The build time.
        live: The live batch time.
        frozen: The frozen batch time.

    Returns:
        The query count, or `None` when freezing saves nothing.
    """
    var saved = (live.value - frozen.value) / 1024.0
    if saved > 0:
        return Num(floor(build.value / saved) + 1.0, True, False)
    return Num(0.0, False, True)


def write_num(mut out: JsonWriter, number: Num):
    """Write a number as Python wrote it.

    Args:
        out: The writer.
        number: The number.
    """
    if number.none:
        out.null()
    elif number.whole:
        out.integer(Int(number.value))
    else:
        out.number(number.value)


def _member(mut out: JsonWriter, name: String, number: Num):
    """Write one numeric member."""
    out.key(name)
    write_num(out, number)


def summarize(
    mut out: JsonWriter,
    native: Dict[String, List[Row]],
    hooked: Dict[String, List[Row]],
) raises:
    """Write measured medians and explicitly derived amortization estimates.

    Args:
        out: The writer.
        native: The native rows.
        hooked: The allocation-hooked rows.

    Raises:
        Error: If a case is missing.
    """
    comptime layouts = LAYOUTS
    var names = materialize[layouts]()
    out.begin_object()
    for group in ["corpus", "small"]:
        var counts: List[Int] = [100, 1000, 10000] if group == "corpus" else [
            0,
            1,
            4,
            8,
            16,
            32,
            64,
        ]
        var moving = 10 if group == "corpus" else 0
        out.key(group)
        out.begin_array()
        for n in counts:
            for layout in range(4):
                var prefix = _prefix_of(key(group, n, moving, layout, ""))
                var build = value(native, prefix, "snapshot_build")
                var index_build = value(native, prefix, "forced_index_build")
                var live = value(native, prefix, "ray_linear_1024")
                var frozen = value(native, prefix, "ray_snapshot_1024")
                var owned = value(native, prefix, "ray_frozen_linear_1024")
                var indexed = value(native, prefix, "ray_forced_index_1024")
                out.begin_object()
                out.key("static")
                out.integer(n)
                out.key("moving")
                out.integer(moving)
                out.key("layout")
                out.string(String(names[layout]))
                _member(out, "snapshot_build_ns", build)
                _member(out, "forced_index_build_ns", index_build)
                _member(out, "world_batch_ns", live)
                _member(out, "snapshot_batch_ns", frozen)
                _member(out, "frozen_linear_batch_ns", owned)
                _member(out, "forced_index_batch_ns", indexed)
                _member(out, "world_over_snapshot", ratio(live, frozen))
                _member(out, "linear_over_snapshot", ratio(owned, frozen))
                _member(
                    out, "snapshot_over_forced_index", ratio(frozen, indexed)
                )
                _member(
                    out,
                    "estimated_snapshot_break_even_rays",
                    break_even(build, live, frozen),
                )
                _member(
                    out,
                    "estimated_experimental_index_break_even_rays",
                    break_even(index_build, owned, indexed),
                )
                out.key("estimated_amortized_snapshot_ns_per_ray")
                out.begin_object()
                for q in [1, 16, 128, 1024, 8192]:
                    out.key(String(q))
                    out.number(build.value / Float64(q) + frozen.value / 1024.0)
                out.end()
                var hooked_members: List[Tuple[String, String, String]] = [
                    ("indexed_primitive_entries", "snapshot_build", "pairs"),
                    (
                        "retained_requested_bytes",
                        "snapshot_build",
                        "live_bytes",
                    ),
                    (
                        "owned_geometry_capacity_bytes",
                        "snapshot_build",
                        "geometry_bytes",
                    ),
                    (
                        "owned_bounds_and_indexes_capacity_bytes",
                        "snapshot_build",
                        "index_bytes",
                    ),
                    (
                        "owner_material_capacity_bytes",
                        "snapshot_build",
                        "metadata_bytes",
                    ),
                    (
                        "forced_primitive_index_capacity_bytes",
                        "forced_index_build",
                        "index_bytes",
                    ),
                    (
                        "world_query_total_bytes",
                        "ray_linear_1024",
                        "total_bytes",
                    ),
                    (
                        "world_query_allocations",
                        "ray_linear_1024",
                        "allocations",
                    ),
                    (
                        "frozen_linear_query_total_bytes",
                        "ray_frozen_linear_1024",
                        "total_bytes",
                    ),
                    (
                        "frozen_linear_query_allocations",
                        "ray_frozen_linear_1024",
                        "allocations",
                    ),
                    (
                        "snapshot_query_peak_bytes",
                        "ray_snapshot_1024",
                        "peak_bytes",
                    ),
                    (
                        "snapshot_query_total_bytes",
                        "ray_snapshot_1024",
                        "total_bytes",
                    ),
                    (
                        "snapshot_query_allocations",
                        "ray_snapshot_1024",
                        "allocations",
                    ),
                    (
                        "forced_index_query_peak_bytes",
                        "ray_forced_index_1024",
                        "peak_bytes",
                    ),
                ]
                for member in hooked_members:
                    _member(
                        out,
                        member[0],
                        value(hooked, prefix, member[1], member[2]),
                    )
                out.end()
        out.end()
    out.key("dynamic_sweep")
    out.begin_array()
    for n in [100, 1000, 10000]:
        for moving in [1, 10, 100]:
            for layout in range(4):
                var prefix = _prefix_of(key("corpus", n, moving, layout, ""))
                out.begin_object()
                out.key("static")
                out.integer(n)
                out.key("moving")
                out.integer(moving)
                out.key("layout")
                out.string(String(names[layout]))
                _member(
                    out,
                    "historical_sweep_query_ns",
                    value(native, prefix, "sweep_query"),
                )
                _member(
                    out,
                    "dynamic_prepare_ns",
                    value(native, prefix, "dynamic_prepare"),
                )
                _member(
                    out,
                    "dynamic_ordered_query_ns",
                    value(native, prefix, "dynamic_query"),
                )
                _member(
                    out,
                    "historical_visited",
                    value(native, prefix, "sweep_query", "work"),
                )
                _member(
                    out,
                    "dynamic_visited",
                    value(native, prefix, "dynamic_query", "work"),
                )
                _member(
                    out,
                    "pairs",
                    value(native, prefix, "dynamic_query", "pairs"),
                )
                _member(
                    out,
                    "pair_scratch_peak_bytes",
                    value(hooked, prefix, "dynamic_query", "peak_bytes"),
                )
                _member(
                    out,
                    "pair_scratch_live_bytes",
                    value(hooked, prefix, "dynamic_query", "live_bytes"),
                )
                out.end()
    out.end()
    out.key("refit")
    out.begin_array()
    for n in [100, 1000, 10000]:
        for percent in [0, 25, 50, 100]:
            var prefix = _prefix_of(key("refit", n, percent, 0, ""))
            var refit = value(native, prefix, "index_refit")
            var rebuild = value(native, prefix, "index_rebuild")
            var degraded = value(native, prefix, "refit_ray_1024")
            var fresh = value(native, prefix, "rebuilt_ray_1024")
            out.begin_object()
            out.key("entries")
            out.integer(n)
            out.key("permuted_percent")
            out.integer(percent)
            _member(out, "refit_ns", refit)
            _member(out, "rebuild_ns", rebuild)
            _member(out, "refitted_batch_ns", degraded)
            _member(out, "rebuilt_batch_ns", fresh)
            _member(
                out,
                "refitted_nodes_visited",
                value(native, prefix, "refit_ray_1024", "work"),
            )
            _member(
                out,
                "rebuilt_nodes_visited",
                value(native, prefix, "rebuilt_ray_1024", "work"),
            )
            _member(
                out,
                "candidates",
                value(native, prefix, "refit_ray_1024", "pairs"),
            )
            _member(out, "query_time_degradation", ratio(degraded, fresh))
            var batches = Num(0.0, False, True)
            if degraded.value > fresh.value:
                batches = Num(
                    floor(
                        max(0.0, rebuild.value - refit.value)
                        / (degraded.value - fresh.value)
                    )
                    + 1.0,
                    True,
                    False,
                )
            _member(out, "estimated_rebuild_break_even_batches", batches)
            out.end()
    out.end()
    out.end()


def summarize_small_recheck(mut out: JsonWriter, path: String) raises:
    """Validate the separate nine-sample tiny repeat without replacing rows.

    Args:
        out: The writer.
        path: The tiny-repeat CSV file.

    Raises:
        Error: If the tiny repeat is incomplete or inconsistent.
    """
    comptime small_phases = SMALL_PHASES
    comptime layouts = LAYOUTS
    var phases = materialize[small_phases]()
    var names = materialize[layouts]()
    var rows = Dict[String, List[Row]]()
    var samples = 0
    for row in read_rows(path):
        if row.group != "small" or row.get("moving") != 0 or row.get("ns") < 0:
            raise Error(
                "Invalid tiny-repeat group, participant count, or timing"
            )
        for field in ["peak_bytes", "total_bytes", "allocations", "live_bytes"]:
            if row.get(field) != 0:
                raise Error(
                    "The tiny repeat must be native, without allocation hooks"
                )
        var name = key(
            "small", row.get("static"), 0, row.get("distribution"), row.phase
        )
        if name not in rows:
            rows[name] = List[Row]()
        rows[name].append(row.copy())
        samples += 1
    var required = Set[String]()
    for n in [0, 1, 4, 8, 16, 32, 64]:
        for d in range(4):
            for phase in phases:
                required.add(key("small", n, 0, d, String(phase)))
    if len(rows) != len(required):
        raise Error("Incomplete or expanded tiny-repeat case set")
    for name in rows.keys():
        if name not in required:
            raise Error("Incomplete or expanded tiny-repeat case set")
    for entry in rows.items():
        var found = List[Int]()
        for row in entry.value:
            found.append(row.get("repetition"))
        sort(found)
        var expected = List[Int]()
        for index in range(9):
            expected.append(index)
        if found != expected:
            raise Error("Wrong tiny-repeat samples for " + entry.key)
    out.begin_object()
    out.key("source")
    out.string(path)
    out.key("sha256")
    out.string(sha256_hex(Span(Path(path).read_bytes())))
    out.key("samples")
    out.integer(samples)
    out.key("repetitions")
    out.integer(9)
    out.key("cases")
    out.begin_array()
    for n in [0, 1, 4, 8, 16, 32, 64]:
        for layout in range(4):
            var prefix = _prefix_of(key("small", n, 0, layout, ""))
            var expected = Dict[Int, Float64]()
            for row in rows[prefix + " ray_linear_1024"]:
                expected[row.get("repetition")] = row.checksum
            for index in range(3, len(phases)):
                for row in rows[prefix + " " + String(phases[index])]:
                    if row.checksum != expected[row.get("repetition")]:
                        raise Error(
                            "Tiny-repeat answer mismatch at "
                            + String(n)
                            + "/"
                            + String(layout)
                            + "/"
                            + String(phases[index])
                        )
            var timing = Dict[String, Num]()
            for phase in phases:
                timing[String(phase)] = value(rows, prefix, String(phase))
            var lowest = 0
            var highest = 0
            var first = True
            for row in rows[prefix + " ray_snapshot_1024"]:
                var ns = row.get("ns")
                if first or ns < lowest:
                    lowest = ns
                if first or ns > highest:
                    highest = ns
                first = False
            out.begin_object()
            out.key("static")
            out.integer(n)
            out.key("layout")
            out.string(String(names[layout]))
            out.key("phase_median_ns")
            out.begin_object()
            for phase in phases:
                _member(out, String(phase), timing[String(phase)])
            out.end()
            out.key("snapshot_min_ns")
            out.integer(lowest)
            out.key("snapshot_max_ns")
            out.integer(highest)
            _member(
                out,
                "linear_over_snapshot",
                ratio(
                    timing["ray_frozen_linear_1024"],
                    timing["ray_snapshot_1024"],
                ),
            )
            _member(
                out,
                "estimated_snapshot_break_even_rays",
                break_even(
                    timing["snapshot_build"],
                    timing["ray_linear_1024"],
                    timing["ray_snapshot_1024"],
                ),
            )
            _member(
                out,
                "indexed_primitive_entries",
                value(rows, prefix, "snapshot_build", "pairs"),
            )
            out.end()
    out.end()
    out.end()


def _count(rows: Dict[String, List[Row]]) -> Int:
    """Return the number of rows."""
    var total = 0
    for entry in rows.values():
        total += len(entry)
    return total


def report(
    native_path: String,
    allocations_path: String,
    small_recheck: String,
    source_manifest: String,
) raises -> Tuple[String, String]:
    """Build the report after verifying the complete native/hooked corpus.

    Args:
        native_path: The native CSV file.
        allocations_path: The allocation-hooked CSV file.
        small_recheck: The tiny-repeat CSV file, or empty.
        source_manifest: The measured-source JSON file, or empty.

    Returns:
        The report text and the printed summary.

    Raises:
        Error: If the measurements are incomplete or inconsistent.
    """
    var native = load(native_path, 3)
    var hooked = load(allocations_path, 1)
    var out = JsonWriter()
    out.begin_object()
    out.key("schema")
    out.integer(1)
    out.key("native_samples")
    out.integer(_count(native))
    out.key("allocation_samples")
    out.integer(_count(hooked))
    out.key("measurements")
    summarize(out, native, hooked)
    out.key("raw_sha256")
    out.begin_object()
    for path in [native_path, allocations_path]:
        out.key(path)
        out.string(sha256_hex(Span(Path(path).read_bytes())))
    out.end()
    out.key("limitations")
    out.begin_array()
    for line in [
        "Native timings are shared-host samples, not CPU-isolated claims.",
        "Hooked times are excluded from speedup calculations.",
        (
            "Allocation counters cover requested Mojo bytes on the query"
            " thread, not RSS or allocator metadata."
        ),
        (
            "Capacity payloads omit inline headers and capture-token"
            " metadata; live_bytes includes all measured surviving runtime"
            " allocations."
        ),
        (
            "Amortization values are estimates from independently measured"
            " phase medians, not end-to-end samples."
        ),
        (
            "The forced index is experimental and ordinary-corpus parity does"
            " not prove safe culling for all accepted Float32 inputs."
        ),
        (
            "Dynamic sweep includes pair output and ordering; historical"
            " sweep_query only counts pairs. Neither measures world-step"
            " narrow phase or solving."
        ),
        (
            "Refit probes permute entry bounds; they do not add a public"
            " snapshot refit API."
        ),
    ]:
        out.string(line)
    out.end()
    if small_recheck:
        out.key("tiny_repeat")
        summarize_small_recheck(out, small_recheck)
    if source_manifest:
        var document = parse_json(Path(source_manifest).read_text())
        out.key("measured_source")
        out.node(document, document.root())
    out.key("analysis_source_sha256")
    out.string(sha256_hex(Span(Path(SOURCE).read_bytes())))
    out.end()
    return (
        out.text() + "\n",
        "Validated "
        + String(_count(native))
        + " native rows and "
        + String(_count(hooked))
        + " allocation rows",
    )


def main() raises:
    var given = argv()
    var positional = List[String]()
    var small_recheck = String()
    var source_manifest = String()
    var index = 1
    while index < len(given):
        var word = String(given[index])
        if (
            word == "--small-recheck" or word == "--source-manifest"
        ) and index + 1 < len(given):
            if word == "--small-recheck":
                small_recheck = String(given[index + 1])
            else:
                source_manifest = String(given[index + 1])
            index += 2
            continue
        positional.append(word)
        index += 1
    if len(positional) != 3:
        print(
            (
                "usage: physics_snapshot_report NATIVE ALLOCATIONS OUTPUT"
                " [--small-recheck CSV] [--source-manifest JSON]"
            ),
            file=stderr,
        )
        exit(2)
    var result = report(
        positional[0], positional[1], small_recheck, source_manifest
    )
    Path(positional[2]).write_text(result[0])
    print(result[1])
