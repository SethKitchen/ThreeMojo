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
- A changed test or test helper also selects the library it exercises and
  every suite that can reach that library, so coverage loss is checked.
  Removed imports use the full check because the current graph no longer
  describes the test's former coverage obligations.
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
PLAIN_IMPORT = re.compile(r"^\s*import\s+(.*)$")
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
    except (OSError, UnicodeError, subprocess.CalledProcessError):
        return None


def changed_paths(base):
    """Return the paths changed since the merge base, with deletions, or None."""
    merge_base = git("merge-base", base, "HEAD")
    if merge_base is None:
        return None
    diff = git("diff", "--name-status", "--no-renames", "-z", merge_base.strip())
    untracked = git("ls-files", "--others", "--exclude-standard", "-z")
    if diff is None or untracked is None:
        return None
    paths = {}
    fields = diff.split("\0")
    for status, path in zip(fields[0::2], fields[1::2]):
        paths[path] = status == "D"
    # An untracked file matters only when a build reads it: a new module or
    # a new asset. A `.venv` link or an editor's scratch file does not.
    for path in filter(None, untracked.split("\0")):
        if path.endswith((".mojo", ".py")) or path.startswith("assets/"):
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
    lines = [line.split("#", 1)[0] for line in source.splitlines()]
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
                for item in match.group(1).split(","):
                    name = item.strip().split(" as ")[0].strip()
                    if name:
                        names.append(name)
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


def reachable(seeds, edges):
    """Return the transitive closure of `seeds` through `edges`."""
    found = set()
    pending = list(seeds)
    while pending:
        path = pending.pop()
        if path not in found:
            found.add(path)
            pending.extend(edges.get(path, ()))
    return found


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
    importers, imports = {}, {}
    seeds = {p for p in changed if p.endswith(".mojo")}
    assets = [p for p in changed if p.startswith("assets/")]
    for path in files:
        try:
            with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
                source = handle.read()
        except (OSError, UnicodeError):
            return ALL
        for name in imported_names(source):
            for target in resolve(name, path, known):
                if target != path:
                    importers.setdefault(target, set()).add(path)
                    imports.setdefault(path, set()).add(target)
        for quoted in QUOTED_ASSET.findall(source):
            if any(asset.startswith(quoted) for asset in assets):
                seeds.add(path)

    affected = reachable(seeds, importers)
    if any(path.startswith("tests/") for path in seeds):
        # An edited test can stop exercising unchanged library code. Measure
        # its imports too, with all the suites that can reach those modules.
        # Include users of a changed helper, not only the helper's imports.
        tests = {path for path in affected if path.startswith("tests/")}
        measured = reachable(tests, imports)
        affected.update(reachable(measured, importers))
    return affected


def test_imports_removed(changed, base):
    """Return True if a changed test drops imports, or its past is unknown.

    The current graph cannot reach an import a test no longer names. Fall
    back to the full check rather than lose that former coverage obligation.
    Added tests have no former imports; their current graph is sufficient.
    """
    tests = [path for path in changed
             if path.startswith("tests/") and path.endswith(".mojo")]
    if not tests:
        return False
    merge_base = git("merge-base", base, "HEAD")
    if merge_base is None:
        return True
    revision = merge_base.strip()
    tracked = git("ls-tree", "-r", "--name-only", "-z", revision, "--", *tests)
    if tracked is None:
        return True
    for path in filter(None, tracked.split("\0")):
        if changed[path]:
            return True
        before = git("show", revision + ":" + path)
        if before is None:
            return True
        try:
            with open(os.path.join(ROOT, path), encoding="utf-8") as source:
                after = source.read()
        except (OSError, UnicodeError):
            return True
        if set(imported_names(before)) - set(imported_names(after)):
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True, help="the ref to compare with")
    parser.add_argument("--changed", action="store_true", help="changed only")
    parser.add_argument("--list", action="store_true", help="print the change")
    parser.add_argument("files", nargs="*")
    options = parser.parse_args()

    changed = changed_paths(options.base)
    if changed is not None and test_imports_removed(changed, options.base):
        changed = None
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
