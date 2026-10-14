# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Recompute the #505 summaries from checked-in data without native runs.

The tool reads `image-decode-505-trials.csv` and
`image-decode-505-provenance.json` in the evidence folder. It checks the
trial file hash, every trial's output oracle, the complete matrix, the
balanced variant order, and each expanded source tree digest. Then it
recomputes each summary and compares it with the checked-in JSON and CSV.

Usage:
    image_decode_505_recompute [--directory DIR] [--write]

The default folder is `docs/validation` beside this tool's `tools` folder.
`--write` replaces the JSON and CSV summaries after the checks pass.
"""

from std.collections import Dict
from std.pathlib import Path
from std.reflection import source_location
from std.sys import argv, exit, stderr

from tools._json_value import JsonTree, sorted_strings
from tools._python_float import parse_float, python_repr
from tools._python_stats import PyNumber, distribution, true_divide
from tools._sha256 import sha256_hex

comptime PREFIX = "image-decode-505"
"""The file name prefix of the evidence packet."""


def check_fields() -> List[String]:
    """Return the native output fields that every variant must agree on.

    Returns:
        The field names in their recorded order.
    """
    return [
        String("textures"),
        String("base_bytes"),
        String("payload_bytes"),
        String("mip_levels"),
        String("all_fnv64"),
        String("base_fnv64"),
        String("shape_fnv64"),
    ]


def _is_text_field(name: String) -> Bool:
    """Return whether a trial column holds text."""
    return (
        name == "run"
        or name == "dataset"
        or name == "api"
        or name == "variant"
        or name == "recorded_utc"
    )


def _is_float_field(name: String) -> Bool:
    """Return whether a trial column holds a float."""
    return name == "user_seconds" or name == "system_seconds"


def _check(condition: Bool, message: String) raises:
    """Raise an assertion error when a condition is false."""
    if not condition:
        raise Error("AssertionError: " + message)


def parse_csv(text: String) raises -> List[List[String]]:
    """Return the records of CSV text, as Python's `csv.reader` reads them.

    Fields are separated by commas. A quoted field can hold commas, line
    breaks and doubled quotes. Empty lines are skipped.

    Args:
        text: The CSV text.

    Returns:
        Each record's fields.

    Raises:
        Error: If a quoted field does not end.
    """
    var bytes = text.as_bytes()
    var records = List[List[String]]()
    var record = List[String]()
    var field = List[UInt8]()
    var quoted = False
    var started = False
    var i = 0
    while i < len(bytes):
        var byte = Int(bytes[i])
        if quoted:
            if byte == ord('"'):
                if i + 1 < len(bytes) and Int(bytes[i + 1]) == ord('"'):
                    field.append(UInt8(byte))
                    i += 1
                else:
                    quoted = False
            else:
                field.append(UInt8(byte))
        elif byte == ord('"') and len(field) == 0:
            quoted = True
            started = True
        elif byte == ord(","):
            record.append(String(unsafe_from_utf8=field^))
            field = List[UInt8]()
            started = True
        elif byte == ord("\n") or byte == ord("\r"):
            if started or len(field) > 0:
                record.append(String(unsafe_from_utf8=field^))
                records.append(record^)
            field = List[UInt8]()
            record = List[String]()
            started = False
            if (
                byte == ord("\r")
                and i + 1 < len(bytes)
                and Int(bytes[i + 1]) == ord("\n")
            ):
                i += 1
        else:
            field.append(UInt8(byte))
            started = True
        i += 1
    if quoted:
        raise Error("unexpected end of data")
    if started or len(field) > 0:
        record.append(String(unsafe_from_utf8=field^))
        records.append(record^)
    return records^


@fieldwise_init
struct Trial(Copyable, Movable):
    """One normalized trial row."""

    var names: List[String]
    """The column names."""
    var values: List[String]
    """Each value's Python text: the string, `int` digits or float `repr`."""

    def value(self, name: String) raises -> String:
        """Return a column's text.

        Args:
            name: The column.

        Returns:
            The text.

        Raises:
            Error: `'name'` when there is no such column.
        """
        for i in range(len(self.names)):
            if self.names[i] == name:
                return self.values[i]
        raise Error("'" + name + "'")

    def integer(self, name: String) raises -> Int:
        """Return an integer column.

        Args:
            name: The column.

        Returns:
            The value.

        Raises:
            Error: If the column is absent or does not fit 64 bits.
        """
        return Int(self.value(name))


def read_trials(directory: String) raises -> List[Trial]:
    """Read the normalized trials, as `csv.DictReader` and the types give.

    Args:
        directory: The evidence folder.

    Returns:
        The trials. Text columns stay text, the time columns are floats,
        and every other column is an integer.

    Raises:
        Error: If a value has the wrong type or a row the wrong length.
    """
    var records = parse_csv(
        Path(directory + "/" + PREFIX + "-trials.csv").read_text()
    )
    var trials = List[Trial]()
    if len(records) == 0:
        return trials^
    var header = records[0].copy()
    var tree = JsonTree()
    for index in range(1, len(records)):
        _check(
            len(records[index]) == len(header),
            "row " + String(index) + " does not match the header",
        )
        var values = List[String]()
        for column in range(len(header)):
            var text = records[index][column]
            if _is_text_field(header[column]):
                values.append(text)
            elif _is_float_field(header[column]):
                values.append(python_repr(parse_float(text)))
            else:
                values.append(tree.text(tree.integer_text(text)))
        trials.append(Trial(header.copy(), values^))
    return trials^


def _expected_positions(repetitions: Int) -> List[Int]:
    """Return `sorted(list(range(3)) * (repetitions // 3))`."""
    var result = List[Int]()
    for value in range(3):
        for _ in range(repetitions // 3):
            result.append(value)
    return result^


def _sorted_ints(var values: List[Int]) -> List[Int]:
    """Return integers in ascending order."""
    for i in range(1, len(values)):
        var j = i
        while j > 0 and values[j] < values[j - 1]:
            values.swap_elements(j, j - 1)
            j -= 1
    return values^


def verify(trials: List[Trial], tree: JsonTree, provenance: Int) raises:
    """Check every oracle, the matrix, the variant order and source trees.

    Args:
        trials: The trials.
        tree: The provenance values.
        provenance: The provenance object.

    Raises:
        Error: On the first check that fails.
    """
    var fixtures = tree.get(tree.get(provenance, "fixtures"), "datasets")
    var datasets = List[String]()
    var expected_nodes = List[Int]()
    for index in range(tree.length(fixtures)):
        var dataset = tree.at(fixtures, index)
        var name = tree.string_value(tree.get(dataset, "name"))
        var found = -1
        for i in range(len(datasets)):
            if datasets[i] == name:
                found = i
        if found >= 0:
            expected_nodes[found] = tree.get(dataset, "expected")
        else:
            datasets.append(name)
            expected_nodes.append(tree.get(dataset, "expected"))
    var signatures = Dict[String, String]()
    var fields = check_fields()
    for trial in trials:
        for name in [
            "exit_code",
            "native_exit_code",
            "native_signal",
            "exec_errno",
            "timed_out",
            "measurement_error",
        ]:
            _check(trial.integer(name) == 0, name + " is not zero")
        _check(
            trial.integer("load_ns") > 0
            and trial.integer("peak_rss_bytes") > 0,
            "load_ns and peak_rss_bytes must be positive",
        )
        _check(
            trial.integer("peak_rss_bytes")
            == trial.integer("maxrss_raw") * 1024,
            "peak_rss_bytes is not maxrss_raw KiB",
        )
        _check(
            trial.integer("runtime_parallelism") == 9,
            "runtime_parallelism is not 9",
        )
        var dataset = trial.value("dataset")
        var which = -1
        for i in range(len(datasets)):
            if datasets[i] == dataset:
                which = i
        if which < 0:
            raise Error("'" + dataset + "'")
        var expected = expected_nodes[which]
        for key in tree.keys(expected):
            var node = tree.get(expected, key)
            var matches: Bool
            if tree.is_integer(node):
                matches = trial.value(key) == tree.text(node)
            else:
                var number = PyNumber.of_int(trial.integer(key))
                matches = number.as_float() == tree.float_value(node)
            _check(matches, "(" + dataset + ", " + key + ")")
        var signature = String()
        for field in fields:
            signature += trial.value(field) + ","
        if dataset in signatures:
            _check(
                signatures[dataset] == signature,
                "output signature differs: " + dataset,
            )
        else:
            signatures[dataset] = signature
    var runs = tree.get(provenance, "runs")
    var workers: List[Int] = [1, 2, 4, 17]
    for run in tree.keys(runs):
        var metadata = tree.get(runs, run)
        var subset = List[Int]()
        for index in range(len(trials)):
            if trials[index].value("run") == run:
                subset.append(index)
        _check(
            len(subset) == tree.int_value(tree.get(metadata, "planned_rows"))
            and len(subset)
            == tree.int_value(tree.get(metadata, "completed_rows")),
            "row counts differ for run " + run,
        )
        _check(
            tree.string_value(tree.get(metadata, "status")) == "complete",
            "run " + run + " is not complete",
        )
        var repetitions = tree.int_value(tree.get(metadata, "repetitions"))
        var positions = Dict[String, List[Int]]()
        for index in subset:
            ref trial = trials[index]
            var key = (
                trial.value("dataset")
                + "\n"
                + trial.value("api")
                + "\n"
                + String(trial.integer("workers"))
                + "\n"
                + trial.value("variant")
            )
            if not key in positions:
                positions[key] = List[Int]()
            positions[key].append(trial.integer("variant_order"))
        var expected_keys = 0
        for dataset in datasets:
            for api in ["gltf", "registry"]:
                for worker in workers:
                    for variant in ["baseline", "dynamic", "stride"]:
                        var key = (
                            dataset
                            + "\n"
                            + api
                            + "\n"
                            + String(worker)
                            + "\n"
                            + variant
                        )
                        _check(key in positions, "matrix is missing " + key)
                        expected_keys += 1
        _check(len(positions) == expected_keys, "matrix has extra cases")
        var balanced = _expected_positions(repetitions)
        for entry in positions.items():
            _check(
                len(entry.value) == repetitions,
                "repetition count differs: " + entry.key,
            )
            _check(
                _sorted_ints(entry.value.copy()) == balanced,
                "variant order is not balanced: " + entry.key,
            )
    var base = tree.get(provenance, "baseline_mojo_files")
    var variants = tree.get(tree.get(provenance, "build"), "variants")
    for label in tree.keys(variants):
        var source = tree.get(tree.get(variants, label), "source")
        var removed = tree.get(source, "removed_from_baseline")
        var updates = tree.get(source, "file_updates_from_baseline")
        var inventory = JsonTree()
        var files = inventory.object()
        for name in tree.keys(base):
            var drop = False
            for index in range(tree.length(removed)):
                if tree.string_value(tree.at(removed, index)) == name:
                    drop = True
            if not drop:
                inventory.set(
                    files,
                    name,
                    inventory.string(tree.text(tree.get(base, name))),
                )
        for name in tree.keys(updates):
            inventory.set(
                files,
                name,
                inventory.string(tree.text(tree.get(updates, name))),
            )
        var text = inventory.dumps(files, -1, True, ",", ":")
        _check(
            sha256_hex(text.as_bytes())
            == tree.string_value(tree.get(source, "mojo_tree_sha256")),
            "source tree digest differs: " + label,
        )


@fieldwise_init
struct _Case(Copyable, Movable):
    """The key of one summary case."""

    var run: String
    var dataset: String
    var api: String
    var workers: Int

    def less(self, other: _Case) -> Bool:
        """Return whether this key sorts first, as tuples compare."""
        if self.run != other.run:
            return self.run < other.run
        if self.dataset != other.dataset:
            return self.dataset < other.dataset
        if self.api != other.api:
            return self.api < other.api
        return self.workers < other.workers

    def same(self, other: _Case) -> Bool:
        """Return whether two keys are equal."""
        return (
            self.run == other.run
            and self.dataset == other.dataset
            and self.api == other.api
            and self.workers == other.workers
        )


def _metric(
    mut tree: JsonTree,
    trials: List[Trial],
    rows: List[Int],
    name: String,
) raises -> Int:
    """Add the distribution of one per-trial metric."""
    var values = List[PyNumber]()
    for index in rows:
        ref trial = trials[index]
        var load = trial.integer("load_ns")
        if name == "load_ns" or name == "peak_rss_bytes":
            values.append(PyNumber.of_int(trial.integer(name)))
        elif name == "images_per_second":
            # textures * 1e9 is a float; dividing by an int converts it.
            var scaled = Float64(trial.integer("textures")) * 1e9
            values.append(
                PyNumber.of_float(scaled / PyNumber.of_int(load).as_float())
            )
        else:
            values.append(
                PyNumber.of_float(
                    true_divide(trial.integer("base_bytes") * 250, load)
                )
            )
    return distribution(tree, values)


def metric_names() -> List[String]:
    """Return the per-variant metrics in their recorded order.

    Returns:
        `load_ns`, `peak_rss_bytes`, `images_per_second` and
        `base_megapixels_per_second`.
    """
    return [
        String("load_ns"),
        String("peak_rss_bytes"),
        String("images_per_second"),
        String("base_megapixels_per_second"),
    ]


def summarize(mut tree: JsonTree, trials: List[Trial]) raises -> Int:
    """Return the summary object of every case.

    Args:
        tree: The tree for the summary.
        trials: The trials.

    Returns:
        The summary node.

    Raises:
        Error: If a trial repeats or a case lacks a variant or repetition.
    """
    var cases = List[_Case]()
    for trial in trials:
        var key = _Case(
            trial.value("run"),
            trial.value("dataset"),
            trial.value("api"),
            trial.integer("workers"),
        )
        var known = False
        for case_key in cases:
            if case_key.same(key):
                known = True
                break
        if not known:
            cases.append(key^)
    for i in range(1, len(cases)):
        var j = i
        while j > 0 and cases[j].less(cases[j - 1]):
            cases.swap_elements(j, j - 1)
            j -= 1
    var variants: List[String] = ["baseline", "dynamic", "stride"]
    var list = tree.array()
    for key in cases:
        # Each variant's trials, by repetition, in file order.
        var by_variant = List[List[Int]]()
        var repetitions = List[List[Int]]()
        var others = List[String]()
        for _ in variants:
            by_variant.append(List[Int]())
            repetitions.append(List[Int]())
        for index in range(len(trials)):
            ref trial = trials[index]
            var here = _Case(
                trial.value("run"),
                trial.value("dataset"),
                trial.value("api"),
                trial.integer("workers"),
            )
            if not here.same(key):
                continue
            var variant = trial.value("variant")
            var slot = -1
            for v in range(len(variants)):
                if variants[v] == variant:
                    slot = v
            if slot < 0:
                others.append(variant)
                continue
            var repetition = trial.integer("repetition")
            _check(not repetition in repetitions[slot], "Duplicate trial")
            by_variant[slot].append(index)
            repetitions[slot].append(repetition)
        _check(
            len(others) == 0
            and len(by_variant[0]) > 0
            and len(by_variant[1]) > 0
            and len(by_variant[2]) > 0,
            "variants are not baseline, dynamic and stride",
        )
        var reference = _sorted_ints(repetitions[1].copy())
        for slot in range(len(variants)):
            _check(
                _sorted_ints(repetitions[slot].copy()) == reference,
                "repetitions differ between variants",
            )
        var item = tree.object()
        tree.set(item, "run", tree.string(key.run))
        tree.set(item, "dataset", tree.string(key.dataset))
        tree.set(item, "api", tree.string(key.api))
        tree.set(item, "workers", tree.integer(key.workers))
        tree.set(item, "repetitions", tree.integer(len(reference)))
        var per_variant = tree.object()
        for slot in range(len(variants)):
            var metrics = tree.object()
            for name in metric_names():
                tree.set(
                    metrics, name, _metric(tree, trials, by_variant[slot], name)
                )
            tree.set(per_variant, variants[slot], metrics)
        tree.set(item, "variants", per_variant)
        var paired = tree.object()
        for slot in [0, 2]:
            var speedups = List[PyNumber]()
            var ratios = List[PyNumber]()
            for repetition in reference:
                var dynamic = -1
                var other = -1
                for k in range(len(repetitions[1])):
                    if repetitions[1][k] == repetition:
                        dynamic = by_variant[1][k]
                for k in range(len(repetitions[slot])):
                    if repetitions[slot][k] == repetition:
                        other = by_variant[slot][k]
                ref dyn = trials[dynamic]
                ref ref_trial = trials[other]
                speedups.append(
                    PyNumber.of_float(
                        true_divide(
                            ref_trial.integer("load_ns"),
                            dyn.integer("load_ns"),
                        )
                    )
                )
                ratios.append(
                    PyNumber.of_float(
                        true_divide(
                            dyn.integer("peak_rss_bytes"),
                            ref_trial.integer("peak_rss_bytes"),
                        )
                    )
                )
            var comparison = tree.object()
            tree.set(comparison, "speedup", distribution(tree, speedups))
            tree.set(comparison, "rss_ratio", distribution(tree, ratios))
            tree.set(paired, variants[slot], comparison)
        tree.set(item, "paired", paired)
        tree.append(list, item)
    var summary = tree.object()
    tree.set(summary, "schema", tree.integer(1))
    tree.set(
        summary,
        "description",
        tree.string(
            "All dynamic cases with each variant's distributions and paired"
            " dynamic comparisons."
        ),
    )
    var units = tree.object()
    tree.set(units, "load_ns", tree.string("nanoseconds"))
    tree.set(units, "peak_rss_bytes", tree.string("bytes"))
    tree.set(
        units, "speedup", tree.string("reference load_ns / dynamic load_ns")
    )
    tree.set(
        units,
        "rss_ratio",
        tree.string("dynamic peak_rss_bytes / reference peak_rss_bytes"),
    )
    tree.set(units, "mad", tree.string("unscaled median absolute deviation"))
    tree.set(summary, "units", units)
    tree.set(summary, "cases", list)
    return summary


def _csv_field(text: String) -> String:
    """Return a field as `csv.writer` writes it with minimal quoting."""
    if "," in text or '"' in text or "\n" in text or "\r" in text:
        return '"' + text.replace('"', '""') + '"'
    return text


def summary_csv(tree: JsonTree, summary: Int) raises -> String:
    """Return the summaries as flat CSV, as `csv.DictWriter` writes them.

    Args:
        tree: The summary values.
        summary: The summary object.

    Returns:
        A header and one line per case, each ending in a newline.

    Raises:
        Error: If the summary has no cases.
    """
    var cases = tree.get(summary, "cases")
    var header = List[String]()
    var lines = List[String]()
    for index in range(tree.length(cases)):
        var item = tree.at(cases, index)
        var names = List[String]()
        var values = List[String]()
        for key in ["run", "dataset", "api", "workers", "repetitions"]:
            names.append(key)
            values.append(tree.text(tree.get(item, key)))
        for group in ["variants", "paired"]:
            var section = tree.get(item, group)
            for variant in tree.keys(section):
                var metrics = tree.get(section, variant)
                for metric in tree.keys(metrics):
                    var stats = tree.get(metrics, metric)
                    for stat in tree.keys(stats):
                        if stat == "n":
                            continue
                        var prefix = (
                            variant if group
                            == "variants" else "dynamic_vs_" + variant
                        )
                        names.append(prefix + "_" + metric + "_" + stat)
                        values.append(tree.text(tree.get(stats, stat)))
        if index == 0:
            header = names.copy()
        _check(names == header, "dict contains fields not in fieldnames")
        var line = String()
        for i in range(len(values)):
            if i > 0:
                line += ","
            line += _csv_field(values[i])
        lines.append(line^)
    if len(lines) == 0:
        raise Error("list index out of range")
    var out = String()
    for i in range(len(header)):
        if i > 0:
            out += ","
        out += _csv_field(header[i])
    out += "\n"
    for line in lines:
        out += line + "\n"
    return out^


def default_directory() -> String:
    """Return the evidence folder beside this tool's `tools` folder.

    Returns:
        The `docs/validation` path of the source tree that built the tool.
    """
    var file = String(source_location().file_name())
    var slash = file.rfind("/")
    var tools = String(file[byte=:slash]) if slash >= 0 else String(".")
    var slash2 = tools.rfind("/")
    var root = String(tools[byte=:slash2]) if slash2 >= 0 else String(".")
    return root + "/docs/validation"


def recompute(directory: String, write: Bool) raises -> String:
    """Check the evidence packet and its summaries.

    Args:
        directory: The evidence folder.
        write: True to replace the JSON and CSV summaries; False to compare.

    Returns:
        The `PASS` line.

    Raises:
        Error: On the first check that fails.
    """
    var tree = JsonTree()
    var provenance = tree.parse(
        Path(directory + "/" + PREFIX + "-provenance.json").read_text()
    )
    var trials_bytes = Path(
        directory + "/" + PREFIX + "-trials.csv"
    ).read_bytes()
    _check(
        sha256_hex(Span(trials_bytes))
        == tree.string_value(tree.get(provenance, "normalized_trials_sha256")),
        "trial file hash differs",
    )
    var trials = read_trials(directory)
    verify(trials, tree, provenance)
    var output = JsonTree()
    var summary = summarize(output, trials)
    var json_path = directory + "/" + PREFIX + "-summary.json"
    var csv_path = directory + "/" + PREFIX + "-summary.csv"
    var csv_text = summary_csv(output, summary)
    if write:
        Path(json_path).write_text(
            output.dumps(summary, -1, True, ",", ":") + "\n"
        )
        Path(csv_path).write_text(csv_text)
    else:
        var recorded = output.parse(Path(json_path).read_text())
        _check(output.equal(recorded, summary), "JSON summary differs")
        _check(Path(csv_path).read_text() == csv_text, "CSV summary differs")
    return (
        "PASS: "
        + String(len(trials))
        + " trials, "
        + String(output.length(output.get(summary, "cases")))
        + " case summaries, all output oracles and source inventory hashes"
    )


def main() raises:
    """Run the checks from the command line.

    Raises:
        Error: On the first check that fails.
    """
    var given = argv()
    var directory = default_directory()
    var write = False
    var i = 1
    while i < len(given):
        var word = String(given[i])
        if word == "--write":
            write = True
        elif word == "--directory":
            i += 1
            if i >= len(given):
                print(
                    (
                        "image_decode_505_recompute: error: argument"
                        " --directory: expected one argument"
                    ),
                    file=stderr,
                )
                exit(2)
            directory = String(given[i])
        elif word.startswith("--directory="):
            directory = String(word[byte=12:])
        elif word == "-h" or word == "--help":
            print(
                "usage: image_decode_505_recompute [--directory DIR] [--write]"
            )
            exit(0)
        else:
            print(
                "image_decode_505_recompute: error: unrecognized arguments: "
                + word,
                file=stderr,
            )
            exit(2)
        i += 1
    print(recompute(directory, write))
