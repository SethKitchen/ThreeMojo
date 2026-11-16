# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Select build and test files belonging to one `extensions/<domain>` package.

    sh tools/tool.sh .venv/bin/mojo domain_scope --domain NAME FILE...

Prints the subset of `FILE...` inside `extensions/NAME/` or transitively
importing a module under `extensions/NAME/`, preserving argument order.
"""

from std.collections import Set
from std.os.path import isdir
from std.sys import argv, exit, stderr

from tools.ci_scope import Graph, source_tree
from tools._imports import reachable


def select_domain(
    root: String, domain: String, candidates: List[String]
) raises -> List[String]:
    """Return the items of `candidates` owned by or importing `domain`.

    Args:
        root: Repository root path.
        domain: Subdirectory name under `extensions/`.
        candidates: Candidate repository-relative paths.

    Returns:
        Matching paths from `candidates`, in their original order.

    Raises:
        Error: If `domain` is empty, unsafe, or does not exist under
            `extensions/`.
    """
    if (
        domain == ""
        or "/" in domain
        or "." in domain
        or not isdir(root + "/extensions/" + domain)
    ):
        raise Error("Unknown extension domain: " + domain)
    var prefix = "extensions/" + domain + "/"
    var sources = source_tree(root)
    var graph = Graph(sources)
    var seeds = Set[String]()
    for entry in sources.items():
        if entry.key.startswith(prefix):
            seeds.add(entry.key)
    var reached = reachable(seeds, graph.users)
    var out = List[String]()
    for item in candidates:
        if item.startswith(prefix) or item in reached:
            out.append(item)
    return out^


def main() raises:
    """Parse `--domain NAME FILE...` and print selected paths."""
    var args = argv()
    var domain = String()
    var files = List[String]()
    var index = 1
    while index < len(args):
        var current = String(args[index])
        if current == "--domain" and index + 1 < len(args):
            domain = String(args[index + 1])
            index += 2
        elif current.startswith("--domain="):
            domain = String(current[byte=9:])
            index += 1
        else:
            files.append(current)
            index += 1
    try:
        var selected = select_domain(".", domain, files)
        print(" ".join(selected))
    except error:
        print("domain_scope:", error, file=stderr)
        exit(2)
