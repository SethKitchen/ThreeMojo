# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check negative fixtures without treating broken builds as type safety.

A compiler must first build a valid control. Each negative fixture must then
produce an ordinary, located source diagnostic in that fixture. Missing
imports, errors in dependencies, crashes and tool failures are not passes.
Each fixture also has an expected diagnostic location and message. Unexpected
source errors fail rather than hiding syntax errors or API drift.
Regeneration requires --update-expectations and an explicit fixture selection.
"""

import argparse
import difflib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile

COLOR = re.compile(r"\x1b\[[0-9;]*m")
DIAGNOSTIC = re.compile(r"^(.+?):(\d+):(\d+):\s*(?:fatal )?error:\s*(.*)$", re.M)
NOTE = re.compile(r"^.*?:\d+:\d+:\s*note:\s*(.*)$", re.M)
# The pinned compiler can emit this startup warning without failing to compile.
# Match the entire line so real crashes, import errors and added text still fail.
CRASHPAD_STARTUP_WARNING = (
    "Failed to initialize Crashpad.  Crash reporting will not be available.  "
    "Cause: while locating crashpad handler: unable to locate crashpad handler executable"
)
INFRASTRUCTURE = re.compile(
    r"unable to (?:locate|find|open|load)|cannot (?:find|open|load) (?:file|module)|"
    r"module .*not found|no such file or directory|failed to (?:load|import)|"
    r"could not (?:find|load|import)|unknown (?:argument|option)|"
    r"unrecognized (?:argument|option)|internal compiler error|"
    r"LLVM ERROR|PLEASE submit a bug report|segmentation fault|"
    r"stack dump|assertion .*failed|out of memory|resource temporarily unavailable",
    re.I,
)


def _clean_output(output):
    """Remove color and the one known harmless startup warning."""
    output = COLOR.sub("", output)
    return "\n".join(line for line in output.splitlines()
                     if line != CRASHPAD_STARTUP_WARNING)


def _expected_diagnostics(output):
    """Retain exact error locations, messages and candidate notes in stable order."""
    output = _clean_output(output)
    errors = sorted({(int(line), int(column), message.strip())
                     for _, line, column, message in DIAGNOSTIC.findall(output)})
    return {
        "errors": [{"line": line, "column": column, "message": message}
                   for line, column, message in errors],
        "notes": sorted(set(NOTE.findall(output))),
    }


def rejection_error(fixture, returncode, output, expectations=None):
    """Return why a result is invalid, or None for a source rejection."""
    if returncode == 0:
        return "compiled but should not have"
    if returncode != 1:
        return f"compiler failed abnormally (exit {returncode})"
    output = _clean_output(output)
    if INFRASTRUCTURE.search(output):
        return "infrastructure or import failure"
    diagnostics = DIAGNOSTIC.findall(output)
    if not diagnostics:
        return "no located source error"
    expected = Path(fixture).resolve()
    if any(Path(path).resolve() != expected for path, _, _, _ in diagnostics):
        return "error outside the negative fixture"
    if expectations is not None:
        captured = _expected_diagnostics(output)
        actual = {(item["line"], item["column"], item["message"])
                  for item in captured["errors"]}
        expected_errors = {(item["line"], item["column"], item["message"])
                           for item in expectations["errors"]}
        if actual != expected_errors or captured["notes"] != expectations["notes"]:
            return "unexpected source diagnostic (update only after review)"
    return None


def compile_source(command, flags, source, timeout):
    """Build source and retain all diagnostics. Raise on launch or timeout."""
    return subprocess.run(
        command + ["build"] + flags + ["-o", "/dev/null", str(source)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL, timeout=timeout,
    )


def _write_expectations(path, original, expectations):
    """Replace the manifest atomically, without losing edits made during builds."""
    if path.is_symlink():
        raise ValueError("Refusing to update a symlink expectations file")
    # Sort only fixture keys. Keep unselected records intact and use the
    # existing line/column/message field order to avoid unrelated diff noise.
    updated = (json.dumps({key: expectations[key] for key in sorted(expectations)},
                          indent=2) + "\n").encode("utf-8")
    if original == updated:
        if path.read_bytes() != original:
            raise ValueError("Expectations changed during compilation; retry after review")
        return False
    mode = stat.S_IMODE(path.stat().st_mode)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", dir=path.parent,
                                         prefix=path.name + ".", suffix=".tmp",
                                         delete=False) as target:
            temporary = Path(target.name)
            target.write(updated)
            target.flush()
            os.fsync(target.fileno())
        os.chmod(temporary, mode)
        if path.is_symlink():
            raise ValueError("Refusing to update a symlink expectations file")
        if path.read_bytes() != original:
            raise ValueError("Expectations changed during compilation; retry after review")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print("\n".join(difflib.unified_diff(
        original.decode("utf-8").splitlines(), updated.decode("utf-8").splitlines(),
        fromfile=str(path) + " (before)", tofile=str(path) + " (after)", lineterm="")))
    return True


def main(argv=None):
    """Check the compiler and fixtures. Return zero only for valid rejections."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--flags", default="")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--expectations", default=str(Path(__file__).with_name(
        "compile_fail_expectations.json")))
    parser.add_argument("--update-expectations", action="store_true",
                        help="explicitly regenerate only selected fixtures; review the diff")
    parser.add_argument("fixtures", nargs="*")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    command, flags = shlex.split(args.compiler), shlex.split(args.flags)
    if not command:
        parser.error("--compiler must not be empty")
    if args.update_expectations and not args.fixtures:
        parser.error("--update-expectations requires at least one explicit fixture")
    if not args.fixtures:
        print("No negative fixtures selected.")
        return 0
    try:
        manifest = Path(args.expectations)
        if args.update_expectations and manifest.is_symlink():
            raise ValueError("Refusing to update a symlink expectations file")
        original = manifest.read_bytes()
        expectations = json.loads(original.decode("utf-8"))
        if not isinstance(expectations, dict):
            raise ValueError("Expected a JSON object of fixture records")
        fixtures = sorted(set(args.fixtures))
        for fixture in fixtures:
            if not args.update_expectations and not expectations.get(fixture):
                raise ValueError(f"Missing expected diagnostics for {fixture}")
        for fixture in fixtures:
            if not Path(fixture).is_file():
                raise FileNotFoundError(fixture)
        with tempfile.TemporaryDirectory(prefix="threemojo-compile-control-") as tmp:
            control = Path(tmp) / "control.mojo"
            control.write_text("def main():\n    pass\n", encoding="utf-8")
            result = compile_source(command, flags, control, args.timeout)
            if result.returncode:
                print("Compiler control failed; negative checks not measured.")
                print(result.stdout.decode("utf-8", "replace"))
                return 1
        failed = False
        for fixture in fixtures:
            result = compile_source(command, flags, fixture, args.timeout)
            output = result.stdout.decode("utf-8", "replace")
            expected = None if args.update_expectations else expectations[fixture]
            error = rejection_error(fixture, result.returncode, output, expected)
            if error:
                failed = True
                print(f"{fixture}: {error}")
                print(output)
            elif args.update_expectations:
                expectations[fixture] = _expected_diagnostics(output)
        if failed:
            return 1
        if args.update_expectations:
            changed = _write_expectations(manifest, original, expectations)
            print("Updated expectations; review every diagnostic change." if changed
                  else "Expectations unchanged.")
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Compile-fail infrastructure error: {error}", file=sys.stderr)
        return 1
    print(f"All {len(fixtures)} negative fixtures produced source rejections.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
