# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Select the files that a change can affect, for `make ... AFFECTED=<ref>`.

    python3 tools/affected.py --base origin/main [--changed] FILE...
    python3 tools/affected.py --base origin/main --list

With FILE..., prints the FILEs that the change can affect, in their order:

- A `.mojo` file is affected when it changed, or when it imports an affected
  file, directly or through other files. Imports resolve as Mojo 1.1 resolves
  them: a module beside the importer first, then the repo root.
- A file under `assets/` affects each `.mojo` file whose source quotes a path
  that the asset's path starts with, as `"assets/draco/"` does.
- Documentation (`*.md`, `docs/`, `out/`) affects no `.mojo` file.
- Any other change affects everything: the Makefile, the CI workflow, the
  coverage tool (it decides what coverage means), a deleted test suite (its
  coverage goes with it), or a file this script does not know.

With `--changed`, prints the FILEs that changed, which is what formatting
needs. With `--list`, prints every changed path, or `ALL` when everything is
affected.

The change is everything from the merge base of `--base` and HEAD to the
working tree, with the untracked `.mojo` files and assets. If git cannot say
what changed, every
FILE is printed: an unknown change is treated as a change to everything.
"""

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Trees that hold no source this script needs, or copies of it.
SKIP_DIRS = {".git", ".venv", ".cache", "out", "coverage/build", "node_modules"}

FROM_IMPORT = re.compile(r"^\s*from\s+([A-Za-z_][\w.]*)\s+import\s+(.*)$")
PLAIN_IMPORT = re.compile(r"^\s*import\s+([A-Za-z_][\w.]*)")
QUOTED_ASSET = re.compile(r'"(assets/[^"]*)"')

ALL = "ALL"


def git(*args):
    """Return git's output, or None when git fails."""
    try:
        return subprocess.run(
            ["git", *args],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def changed_paths(base):
    """Return the paths changed since the merge base, with deletions, or None."""
    merge_base = git("merge-base", base, "HEAD")
    if merge_base is None:
        return None
    diff = git("diff", "--name-status", "--no-renames", merge_base.strip())
    untracked = git("ls-files", "--others", "--exclude-standard")
    if diff is None or untracked is None:
        return None
    paths = {}
    for line in diff.splitlines():
        status, _, path = line.partition("\t")
        paths[path] = status == "D"
    # An untracked file matters only when a build reads it: a new module or
    # a new asset. A `.venv` link or an editor's scratch file does not.
    for path in untracked.splitlines():
        if path.endswith(".mojo") or path.startswith("assets/"):
            paths[path] = False
    return paths


def is_documentation(path):
    """Return whether a path is documentation, which no build reads."""
    return (
        path.endswith(".md")
        or path.startswith("docs/")
        or path.startswith("out/")
        or path.startswith(".vscode/")
        or path in ("LICENSE", "skills-lock.json", ".gitignore")
    )


def mojo_files():
    """Return every `.mojo` file in the repo, as a relative path."""
    found = []
    for directory, subdirectories, files in os.walk(ROOT):
        relative = os.path.relpath(directory, ROOT).replace(os.sep, "/")
        subdirectories[:] = [
            name
            for name in subdirectories
            if (name if relative == "." else relative + "/" + name)
            not in SKIP_DIRS
        ]
        for name in files:
            if name.endswith(".mojo"):
                path = name if relative == "." else relative + "/" + name
                found.append(path)
    return found


def imported_names(source):
    """Return the dotted module names a source imports, with the names
    after `import` in a `from` line, which can be submodules."""
    names = []
    lines = source.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        match = FROM_IMPORT.match(line)
        if match:
            module, rest = match.group(1), match.group(2)
            # A parenthesized list can run over several lines.
            if "(" in rest:
                while ")" not in rest and index + 1 < len(lines):
                    index += 1
                    rest += " " + lines[index]
            rest = rest.split("#")[0].replace("(", " ").replace(")", " ")
            names.append(module)
            for item in rest.split(","):
                item = item.strip().split(" as ")[0].strip()
                if item:
                    names.append(module + "." + item)
        else:
            match = PLAIN_IMPORT.match(line)
            if match:
                names.append(match.group(1))
        index += 1
    return names


def resolve(name, importer, known):
    """Return the files a dotted name reaches from an importer: the module
    and the package `__init__.mojo` files on the way to it."""
    parts = name.split(".")
    importer_dir = os.path.dirname(importer)
    for base in ([importer_dir] if importer_dir else []) + [""]:
        prefix = base + "/" if base else ""
        reached = []
        for count in range(1, len(parts) + 1):
            package = prefix + "/".join(parts[:count]) + "/__init__.mojo"
            if package in known:
                reached.append(package)
        module = prefix + "/".join(parts) + ".mojo"
        if module in known:
            return reached + [module]
        if reached and reached[-1] == prefix + "/".join(parts) + "/__init__.mojo":
            return reached
    return []


def affected_set(changed):
    """Return the `.mojo` files a change affects, or ALL."""
    for path, deleted in changed.items():
        if is_documentation(path):
            continue
        if path.endswith(".mojo") and not path.startswith("coverage/"):
            if deleted and path.startswith("tests/test_"):
                return ALL
            continue
        if path.startswith("assets/"):
            continue
        return ALL

    files = mojo_files()
    known = set(files) | {p for p in changed if p.endswith(".mojo")}
    importers = {}
    seeds = {p for p in changed if p.endswith(".mojo")}
    assets = [p for p in changed if p.startswith("assets/")]
    for path in files:
        with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
            source = handle.read()
        for name in imported_names(source):
            for target in resolve(name, path, known):
                if target != path:
                    importers.setdefault(target, set()).add(path)
        for quoted in QUOTED_ASSET.findall(source):
            if any(asset.startswith(quoted) for asset in assets):
                seeds.add(path)

    affected = set()
    pending = list(seeds)
    while pending:
        path = pending.pop()
        if path in affected:
            continue
        affected.add(path)
        pending.extend(importers.get(path, ()))
    return affected


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True, help="the ref to compare with")
    parser.add_argument("--changed", action="store_true", help="changed only")
    parser.add_argument("--list", action="store_true", help="print the change")
    parser.add_argument("files", nargs="*")
    options = parser.parse_args()

    changed = changed_paths(options.base)
    if options.list:
        if changed is None or affected_set(changed) == ALL:
            print(ALL)
        else:
            print("\n".join(sorted(changed)))
        return 0

    candidates = [path.removeprefix("./") for path in options.files]
    if changed is None:
        selected = candidates
    else:
        affected = affected_set(changed)
        if affected == ALL:
            selected = candidates
        elif options.changed:
            selected = [path for path in candidates if path in changed]
        else:
            selected = [path for path in candidates if path in affected]
    print(" ".join(selected))
    return 0


if __name__ == "__main__":
    sys.exit(main())
