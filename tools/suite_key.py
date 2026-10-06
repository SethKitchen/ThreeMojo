# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Print the test suites that must run again, each with its cache key.

    python3 tools/suite_key.py --stamps .cache/suites --setting=... \\
        tests/test_a.mojo tests/test_b.mojo ...

prints `SUITE KEY` for each suite that has no stamp named `NAME-KEY` in
`--stamps`, and a count of the others on standard error. `make test-cpu`
builds and runs only the printed suites, and writes the stamp when one
passes.

A suite's key hashes everything that can change what it does:

- the suite and every file it imports, directly or through other files,
  resolved as `tools/affected.py` resolves them;
- every file under `assets/` whose path starts with a path that one of
  those files quotes, as `"assets/draco/"` does;
- the Makefile and the tools that build and run a suite;
- the `--setting` values: the toolchain, the flags and the time limit.

So a change to one module runs only the suites that can reach it. A
change the import graph cannot see, such as a new file that a suite reads
through a path it builds at run time, is not seen. `make -B test-cpu`
ignores the stamps and runs every suite.
"""

import argparse
import hashlib
import os
import sys

import affected

# The files that decide how a suite is built and run.
TOOLING = ["Makefile", "tools/affected.py", "tools/run_suite.py", "tools/suite_key.py",
           "tools/test_environment.py", "tools/compiler_telemetry.py"]


def closure(suite, known, imports):
    """Return the sorted files `suite` reaches through its imports, itself
    included. `imports` caches each file's direct imports."""
    seen = {suite}
    stack = [suite]
    while stack:
        path = stack.pop()
        if path not in imports:
            with open(os.path.join(affected.ROOT, path), encoding="utf-8") as source:
                text = source.read()
            reached = []
            for name in affected.imported_names(text):
                reached.extend(affected.resolve(name, path, known))
            imports[path] = (reached, affected.QUOTED_ASSET.findall(text))
        for target in imports[path][0]:
            if target not in seen:
                seen.add(target)
                stack.append(target)
    return sorted(seen)


def asset_files():
    """Return every file under `assets/`, as a sorted relative path."""
    found = []
    for directory, _, files in os.walk(os.path.join(affected.ROOT, "assets")):
        relative = os.path.relpath(directory, affected.ROOT).replace(os.sep, "/")
        found.extend(relative + "/" + name for name in files)
    return sorted(found)


def suite_key(suite, settings, known, imports, assets, contents):
    """Return the cache key of `suite`. `contents` caches file digests."""
    digest = hashlib.sha256()

    def add(data):
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)

    def add_file(path):
        if path not in contents:
            with open(os.path.join(affected.ROOT, path), "rb") as source:
                contents[path] = hashlib.sha256(source.read()).digest()
        add(path.encode())
        add(contents[path])

    for setting in settings:
        add(setting.encode())
    files = closure(suite, known, imports)
    quoted = {prefix for path in files for prefix in imports[path][1]}
    used = [path for path in assets if any(path.startswith(p) for p in quoted)]
    for path in TOOLING + files + used:
        add_file(path)
    return digest.hexdigest()[:20]


def main(argv):
    """Print the suites to run, and return 0."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stamps", required=True)
    parser.add_argument("--setting", action="append", default=[])
    parser.add_argument("suites", nargs="*")
    args = parser.parse_args(argv)
    known = set(affected.mojo_files())
    imports, contents, assets = {}, {}, asset_files()
    cached = 0
    for suite in args.suites:
        key = suite_key(suite, args.setting, known, imports, assets, contents)
        name = os.path.splitext(os.path.basename(suite))[0]
        if os.path.exists(os.path.join(args.stamps, f"{name}-{key}")):
            cached += 1
        else:
            print(suite, key)
    print(f"{cached} of {len(args.suites)} suites passed before and are unchanged.",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
