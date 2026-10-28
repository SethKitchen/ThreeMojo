# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Compare the reviewed Sum2 caller graphs.

    carla_sum2_graphs PATH
    carla_sum2_graphs --with-imports PATH

PATH is JSON with `texts` and `checkpoints`. The command compares each
caller in the Sum2 plan. It prints nothing when every graph matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import sum2_graph_batch
from tools._python_json import PyJson
from tools._sum2_helper_bindings import sum2_import_batch


def sum2_graphs_and_imports(payload: String) raises:
    """Compare every caller graph, then check the helper imports.

    Args:
        payload: JSON with `texts`, `checkpoints`, and `interval`.

    Raises:
        Error: A caller graph changed, an import changed, or `_stored_half` is missing.
    """
    var doc = PyJson.parse(payload)
    var graphs = PyJson()
    var root = graphs.new_dict()
    graphs.set(root, "texts", graphs.adopt(doc, doc.at(doc.root, "texts")))
    graphs.set(
        root, "checkpoints", graphs.adopt(doc, doc.at(doc.root, "checkpoints"))
    )
    graphs.root = root
    sum2_graph_batch(graphs.dumps())
    var imports = PyJson()
    var imported = imports.new_dict()
    imports.set(
        imported, "texts", imports.adopt(doc, doc.at(doc.root, "texts"))
    )
    imports.set(
        imported,
        "interval",
        imports.new_str(doc.text(doc.at(doc.root, "interval"))),
    )
    imports.root = imported
    sum2_import_batch(imports.dumps())


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_sum2_graphs PATH | carla_sum2_graphs --with-imports PATH",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Compare every reviewed Sum2 caller graph.

    Raises:
        Error: The command is invalid, or a caller graph changed.
    """
    var arguments = argv()
    if len(arguments) == 3 and arguments[1] == "--with-imports":
        try:
            sum2_graphs_and_imports(Path(arguments[2]).read_text())
        except error:
            print(String(error), file=stderr)
            exit(1)
        return
    if len(arguments) != 2:
        _usage()
    try:
        sum2_graph_batch(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
