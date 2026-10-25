# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A literal loop receipt matches the Python seal."""

from std.os.path import realpath
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program


def _text(path: String) raises -> String:
    """Return a file as text."""
    return String(from_utf8_lossy=Path(path).read_bytes())


def _same(left: String, right: String) raises:
    """Raise at the first different byte."""
    if left == right:
        return
    var left_bytes = left.as_bytes()
    var right_bytes = right.as_bytes()
    var limit = len(left_bytes)
    if len(right_bytes) < limit:
        limit = len(right_bytes)
    var index = 0
    while index < limit and left_bytes[index] == right_bytes[index]:
        index += 1
    var left_end = index + 160
    if left_end > len(left_bytes):
        left_end = len(left_bytes)
    var right_end = index + 160
    if right_end > len(right_bytes):
        right_end = len(right_bytes)
    raise Error(
        "seal mismatch at "
        + String(index)
        + " lengths "
        + String(len(left_bytes))
        + " "
        + String(len(right_bytes))
        + "\n"
        + String(left[byte=index:left_end])
        + "\n---\n"
        + String(right[byte=index:right_end])
    )


def _cleanup(path: String) raises:
    """Remove a temporary tree."""
    _ = run_program(["rm", "-rf", path], 10)


def _oracle() -> String:
    """Return the script that seals one literal fixture."""
    return (
        "import sys\nfrom pathlib import Path\nsys.path.insert(0,"
        " sys.argv[1])\nimport coverage_loop_proofs as loops\nrepo ="
        " Path(sys.argv[2]).resolve()\nroot ="
        " Path(sys.argv[3]).resolve()\nbuild = Path(sys.argv[4]).resolve()\nfor"
        " name in loops.TOOL_INPUTS:\n    dest = root / name\n   "
        " dest.parent.mkdir(parents=True, exist_ok=True)\n   "
        " dest.write_bytes((repo / name).read_bytes())\nsrc = ('def f():\\n' ' "
        "   for item in range(3):\\n' '        pass\\n' '\\n' 'def g():\\n' '  "
        "  for item in [one, two,]:\\n' '        pass\\n' '\\n' 'def h():\\n' '"
        "    for item in range(n):\\n' '        pass\\n')\n(root /"
        " 'module.mojo').write_text(src)\n(build /"
        " 'module.mojo').parent.mkdir(parents=True, exist_ok=True)\n(build /"
        " 'module.mojo').write_text(src)\nrows = []\nfor number, line in"
        " enumerate(src.splitlines(), 1):\n    if line.startswith('def '):\n   "
        "     rows.append('L module %d\\n' % number)\n    if 'for item in' in"
        " line:\n        rows.append('B module %d\\n' % number)\n(build /"
        " 'manifest.txt').write_text(''.join(rows))\n(root /"
        " 'driver').write_text('compiler\\n')\ndriver = str((root /"
        " 'driver').resolve())\nloops.begin_generation(root, build, 'Mojo"
        " fixture', '-I .',\n    mojo=driver,"
        " sources=['module.mojo'])\nmanifest = (build /"
        " 'manifest.txt').read_bytes()\nnames = ['module.mojo']\nfragments ="
        " []\nfor name in names:\n    module ="
        " name.removesuffix('.mojo').encode()\n    fragment = b''.join(row for"
        " row in manifest.splitlines(keepends=True)\n        if"
        " len(row.split()) >= 2 and row.split()[1] == module)\n   "
        " fragments.append(fragment)\n    parts = [name.encode(), (root /"
        " name).read_bytes(),\n        (build / name).read_bytes(), fragment]\n"
        "    record = b'COVORIGIN1 ' + b' '.join(str(len(part)).encode() for"
        " part in parts) + b'\\n' + b''.join(parts)\n    (build / (name +"
        " '.cov-origin')).write_bytes(record)\ncheckpoint = (build /"
        " 'generation-inputs.json').read_bytes()\nindex = (b'COVORIGIN_INDEX2 '"
        " + str(len(names)).encode() + b' ' + str(len(manifest)).encode()\n   "
        " + b' ' + str(len(checkpoint)).encode() + b'\\n' + manifest +"
        " checkpoint)\nfor name in names:\n    raw = name.encode()\n    index"
        " += str(len(raw)).encode() + b'\\n' + raw\n(build /"
        " 'origins.ready').write_bytes(index)\nenv = loops.seal(root, build,"
        " 'Mojo fixture', '-I .', mojo=driver, suites=[])\nimport json\n"
        "print('Loop proofs:', env['sha256'],"
        " json.dumps(env['receipt']['denominator'], sort_keys=True))\n"
    )


def test_literal_receipt_matches_python() raises:
    var parent = mkdtemp(prefix="coverage-seal-")
    try:
        var root = parent + "/repo"
        var build = root + "/stage"
        var script = parent + "/oracle.py"
        Path(script).write_text(_oracle())
        var sealed = run_program(
            ["python3", script, realpath("tools"), realpath("."), root, build],
            30.0,
            merge_errors=False,
        )
        if sealed.status != 0:
            raise Error(sealed.errors + sealed.output)
        var expected = _text(build + "/loop-proofs.json")
        var expected_out = sealed.output
        _ = run_program(["rm", "-f", build + "/loop-proofs.json"], 10)
        var ran = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "--root",
                root,
                "--build",
                build,
                "--compiler",
                "Mojo fixture",
                "--flags",
                "-I .",
                "--mojo",
                root + "/driver",
            ],
            30.0,
            merge_errors=False,
        )
        if ran.status != 0:
            raise Error(ran.errors + ran.output)
        _same(expected, _text(build + "/loop-proofs.json"))
        assert_equal(ran.output, expected_out)
    finally:
        _cleanup(parent)


def test_usage_exits_2() raises:
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "coverage_loop_seal"],
        20.0,
        merge_errors=False,
    )
    assert_equal(ran.status, 2)
    assert_true(ran.errors.find("usage: coverage_loop_seal ") >= 0)


def main() raises:
    """Build the seal tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "coverage_loop_seal"],
        120.0,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
