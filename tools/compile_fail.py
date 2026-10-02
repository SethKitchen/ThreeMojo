# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check negative fixtures without treating broken builds as type safety.

A compiler must first build a valid control. Each negative fixture must then
produce an ordinary, located source diagnostic in that fixture. Missing
imports, errors in dependencies, crashes and tool failures are not passes.
Each fixture also has an expected diagnostic location and message. Unexpected
source errors fail rather than hiding syntax errors or API drift.
"""

import argparse
import json
from pathlib import Path
import re
import shlex
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


def rejection_error(fixture, returncode, output, expectations=None):
    """Return why a result is invalid, or None for a source rejection."""
    if returncode == 0:
        return "compiled but should not have"
    if returncode != 1:
        return f"compiler failed abnormally (exit {returncode})"
    output = COLOR.sub("", output)
    output = "\n".join(line for line in output.splitlines()
                       if line != CRASHPAD_STARTUP_WARNING)
    if INFRASTRUCTURE.search(output):
        return "infrastructure or import failure"
    diagnostics = DIAGNOSTIC.findall(output)
    if not diagnostics:
        return "no located source error"
    expected = Path(fixture).resolve()
    if any(Path(path).resolve() != expected for path, _, _, _ in diagnostics):
        return "error outside the negative fixture"
    if expectations is not None:
        actual = {(int(line), int(column), message.strip())
                  for _, line, column, message in diagnostics}
        expected_errors = {(item["line"], item["column"], item["message"])
                           for item in expectations["errors"]}
        notes = sorted(set(NOTE.findall(output)))
        if actual != expected_errors or notes != expectations["notes"]:
            return "unexpected source diagnostic (update only after review)"
    return None


def compile_source(command, flags, source, timeout):
    """Build source and retain all diagnostics. Raise on launch or timeout."""
    return subprocess.run(
        command + ["build"] + flags + ["-o", "/dev/null", str(source)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL, timeout=timeout,
    )


def main(argv=None):
    """Check the compiler and fixtures. Return zero only for valid rejections."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--flags", default="")
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--expectations", default=str(Path(__file__).with_name(
        "compile_fail_expectations.json")))
    parser.add_argument("fixtures", nargs="*")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    command, flags = shlex.split(args.compiler), shlex.split(args.flags)
    if not command:
        parser.error("--compiler must not be empty")
    if not args.fixtures:
        print("No negative fixtures selected.")
        return 0
    try:
        with open(args.expectations, encoding="utf-8") as source:
            expectations = json.load(source)
        for fixture in args.fixtures:
            if fixture not in expectations or not expectations[fixture]:
                raise ValueError(f"Missing expected diagnostics for {fixture}")
        for fixture in args.fixtures:
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
        for fixture in args.fixtures:
            result = compile_source(command, flags, fixture, args.timeout)
            output = result.stdout.decode("utf-8", "replace")
            error = rejection_error(fixture, result.returncode, output, expectations[fixture])
            if error:
                failed = True
                print(f"{fixture}: {error}")
                print(output)
        if failed:
            return 1
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Compile-fail infrastructure error: {error}", file=sys.stderr)
        return 1
    print(f"All {len(args.fixtures)} negative fixtures produced source rejections.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
