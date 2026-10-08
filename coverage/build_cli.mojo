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
    # Invalidate a prior generation before any output changes. The complete
    # index is published only after every output and the manifest are written.
    var origin_index_path = build_dir + "/origins.ready"
    Path(origin_index_path).write_text(String(""))
    var checkpoint = String("")
    var checkpoint_path = Path(build_dir + "/generation-inputs.json")
    if checkpoint_path.exists():
        checkpoint = checkpoint_path.read_text()
    var origin_names = String("")
    var manifest = String("")
    var total_lines = 0
    var total_branches = 0
    var total_conditions = 0

    for index in range(2, len(args)):
        var source_path = String(args[index])
        var module = module_name(source_path)
        var original = Path(source_path).read_text()
        var result = instrument(original, module)

        Path(build_dir + "/" + source_path).write_text(result.text)

        var fragment = String("")
        for line in result.lines:
            fragment += "L " + module + " " + String(line) + "\n"
        for position in range(len(result.branches)):
            var line = result.branches[position]
            fragment += "B " + module + " " + String(line) + "\n"
            # A compound decision also reports each of its operands, and each
            # operand additionally owes an MC-DC independence pair.
            for index in range(result.conditions[position]):
                var suffix = module + " " + String(line) + " " + String(index)
                fragment += "C " + suffix + "\n"
                fragment += "M " + suffix + "\n"
            total_conditions += result.conditions[position]

        total_lines += len(result.lines)
        total_branches += len(result.branches)
        manifest += fragment
        # This trusted producer records the exact input of instrument and
        # its exact output/manifest fragment together. Lengths are UTF-8 bytes,
        # so source text, CR/LF endings and embedded delimiters are unambiguous.
        var origin = (
            "COVORIGIN1 "
            + String(source_path.byte_length())
            + " "
            + String(original.byte_length())
            + " "
            + String(result.text.byte_length())
            + " "
            + String(fragment.byte_length())
            + "\n"
            + source_path
            + original
            + result.text
            + fragment
        )
        Path(build_dir + "/" + source_path + ".cov-origin").write_text(origin)
        origin_names += String(source_path.byte_length()) + "\n" + source_path

    Path(build_dir + "/" + MANIFEST_NAME).write_text(manifest)
    Path(origin_index_path).write_text(
        "COVORIGIN_INDEX2 "
        + String(len(args) - 2)
        + " "
        + String(manifest.byte_length())
        + " "
        + String(checkpoint.byte_length())
        + "\n"
        + manifest
        + checkpoint
        + origin_names
    )
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
