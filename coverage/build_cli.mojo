# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Writes instrumented copies of the given sources, plus a manifest.

    mojo run -I . coverage/build_cli.mojo <build-dir> <source.mojo>...

Each source is rewritten into `<build-dir>/<source path>`, so running the test
suite with `-I <build-dir> -I .` resolves library imports to the instrumented
copies while everything else still comes from the repo. The manifest records
every line and decision the instrumented code is able to report on, which is
the denominator the report tool divides by.
"""

from coverage.instrument import instrument
from std.pathlib import Path
from std.sys import argv

comptime MANIFEST_NAME = "manifest.txt"


def module_name(path: String) -> String:
    """Return the probe-id module name for a source path."""
    return String(path.removesuffix(".mojo"))


def main() raises:
    var args = argv()
    if len(args) < 3:
        raise Error("usage: build_cli <build-dir> <source.mojo>...")

    var build_dir = String(args[1])
    var manifest = String("")
    var total_lines = 0
    var total_branches = 0
    var total_conditions = 0

    for index in range(2, len(args)):
        var source_path = String(args[index])
        var module = module_name(source_path)
        var result = instrument(Path(source_path).read_text(), module)

        Path(build_dir + "/" + source_path).write_text(result.text)

        for line in result.lines:
            manifest += "L " + module + " " + String(line) + "\n"
        for position in range(len(result.branches)):
            var line = result.branches[position]
            manifest += "B " + module + " " + String(line) + "\n"
            # A compound decision also reports each of its operands, and each
            # operand additionally owes an MC-DC independence pair.
            for index in range(result.conditions[position]):
                var suffix = module + " " + String(line) + " " + String(index)
                manifest += "C " + suffix + "\n"
                manifest += "M " + suffix + "\n"
            total_conditions += result.conditions[position]

        total_lines += len(result.lines)
        total_branches += len(result.branches)

    Path(build_dir + "/" + MANIFEST_NAME).write_text(manifest)
    print(
        "Instrumented",
        len(args) - 2,
        "files:",
        total_lines,
        "lines,",
        total_branches,
        "decisions,",
        total_conditions,
        "conditions.",
    )
