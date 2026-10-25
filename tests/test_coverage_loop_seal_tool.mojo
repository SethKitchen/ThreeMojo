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


def _reviewed_oracle() -> String:
    """Return the script that seals reviewed proofs and one literal loop."""
    return (
        "import json, sys\nfrom pathlib import Path\nsys.path.insert(0,"
        " sys.argv[1])\nimport coverage_loop_proofs as loops\nrepo ="
        " Path(sys.argv[2]).resolve()\nroot ="
        " Path(sys.argv[3]).resolve()\nbuild ="
        " Path(sys.argv[4]).resolve()\nflip = len(sys.argv) > 5 and sys.argv[5]"
        " == 'flip'\ntable = json.loads((repo /"
        " 'tools/coverage_reviewed_loops.json').read_text())\nmodules ="
        " ['extensions/carla/curve_interval', 'extensions/carla/lane_distance',"
        " 'extensions/carla/speed_limits',"
        " 'extensions/carla/spiral_moment_proof',"
        " 'extensions/humanoid/skeleton/head/hair/strands',"
        " 'renderers/renderer']\nfor name in loops.TOOL_INPUTS:\n    dest ="
        " root / name\n    dest.parent.mkdir(parents=True, exist_ok=True)\n   "
        " dest.write_bytes((repo / name).read_bytes())\nneeded = set()\nfor"
        " module in modules:\n    for proof in table[module]:\n       "
        " needed.update(proof['dependency_sha256'])\nfor name in needed:\n   "
        " dest = root / name\n    dest.parent.mkdir(parents=True,"
        " exist_ok=True)\n    if not dest.exists():\n       "
        " dest.write_bytes((repo / name).read_bytes())\nif flip:\n    path ="
        " root / 'extensions/carla/speed_limits.mojo'\n    raw ="
        " bytearray(path.read_bytes())\n    raw[raw.index(ord('e'))] ="
        " ord('E')\n    path.write_bytes(bytes(raw))\n(root /"
        " 'module.mojo').write_text('def f():\\n    for item in range(3):\\n   "
        "     pass\\n')\nsources = sorted([module + '.mojo' for module in"
        " modules] + ['module.mojo'])\nrows = []\nfor name in sources:\n   "
        " module = name.removesuffix('.mojo')\n    data = (root /"
        " name).read_bytes()\n    dest = build / name\n   "
        " dest.parent.mkdir(parents=True, exist_ok=True)\n   "
        " dest.write_bytes(data)\n    if module == 'module':\n       "
        " rows.append('L module 1\\n')\n        rows.append('B module 2\\n')\n "
        "   else:\n        for proof in table[module]:\n           "
        " rows.append('B %s %d\\n' % (module, proof['line']))\nmanifest ="
        " ''.join(rows).encode()\n(build /"
        " 'manifest.txt').write_bytes(manifest)\n(root /"
        " 'driver').write_text('compiler\\n')\ndriver = str((root /"
        " 'driver').resolve())\nloops.begin_generation(root, build, 'Mojo"
        " fixture', '-I .', mojo=driver, sources=sources)\nnames = sources\nfor"
        " name in names:\n    mod = name.removesuffix('.mojo').encode()\n   "
        " fragment = b''.join(row for row in"
        " manifest.splitlines(keepends=True)\n        if len(row.split()) >= 2"
        " and row.split()[1] == mod)\n    parts = [name.encode(), (root /"
        " name).read_bytes(), (build / name).read_bytes(), fragment]\n   "
        " record = b'COVORIGIN1 ' + b' '.join(str(len(part)).encode() for part"
        " in parts) + b'\\n' + b''.join(parts)\n    (build / (name +"
        " '.cov-origin')).write_bytes(record)\ncheckpoint = (build /"
        " 'generation-inputs.json').read_bytes()\nindex = (b'COVORIGIN_INDEX2 '"
        " + str(len(names)).encode() + b' ' + str(len(manifest)).encode()\n   "
        " + b' ' + str(len(checkpoint)).encode() + b'\\n' + manifest +"
        " checkpoint)\nfor name in names:\n    raw = name.encode()\n    index"
        " += str(len(raw)).encode() + b'\\n' + raw\n(build /"
        " 'origins.ready').write_bytes(index)\nenv = loops.seal(root, build,"
        " 'Mojo fixture', '-I .', mojo=driver, suites=[])\nprint('Loop"
        " proofs:', env['sha256'], json.dumps(env['receipt']['denominator'],"
        " sort_keys=True))\n"
    )


def _seal_mojo(root: String, build: String) raises -> String:
    """Return the Mojo seal output and require a zero status."""
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
    return ran.output


def _run_reviewed(flip: Bool) raises:
    """Seal one reviewed fixture and require the Mojo receipt to match."""
    var parent = mkdtemp(prefix="coverage-reviewed-")
    try:
        var root = parent + "/repo"
        var build = root + "/coverage/build"
        var script = parent + "/oracle.py"
        Path(script).write_text(_reviewed_oracle())
        var args = List[String]()
        args.append("python3")
        args.append(script)
        args.append(realpath("tools"))
        args.append(realpath("."))
        args.append(root)
        args.append(build)
        if flip:
            args.append("flip")
        var sealed = run_program(args, 30.0, merge_errors=False)
        if sealed.status != 0:
            raise Error(sealed.errors + sealed.output)
        var expected = _text(build + "/loop-proofs.json")
        var expected_out = sealed.output
        _ = run_program(["rm", "-f", build + "/loop-proofs.json"], 10)
        var output = _seal_mojo(root, build)
        _same(expected, _text(build + "/loop-proofs.json"))
        assert_equal(output, expected_out)
    finally:
        _cleanup(parent)


def test_reviewed_receipt_matches_python() raises:
    _run_reviewed(False)


def test_changed_review_digest_omits_proof() raises:
    _run_reviewed(True)


def test_density_reviews_match_python() raises:
    var parent = mkdtemp(prefix="coverage-density-")
    try:
        var script = parent + "/reviews.py"
        Path(script).write_text(
            "import json, sys\nfrom pathlib import Path\nsys.path.insert(0,"
            " sys.argv[1])\nimport coverage_loop_proofs as loops\nroot ="
            " Path(sys.argv[2]).resolve()\nmodule = sys.argv[3]\nresult ="
            " loops.reviewed_nonempty_loops(root, module)\nprint(json.dumps("
            "[result[line] for line in sorted(result)], sort_keys=True,"
            " separators=(',', ':')))\n"
        )
        var module = "extensions/humanoid/skeleton/head/hair/density"
        var sealed = run_program(
            ["python3", script, realpath("tools"), realpath("."), module],
            30.0,
            merge_errors=False,
        )
        if sealed.status != 0:
            raise Error(sealed.errors + sealed.output)
        var ran = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "reviews",
                ".",
                module,
            ],
            30.0,
            merge_errors=False,
        )
        if ran.status != 0:
            raise Error(ran.errors + ran.output)
        _same(sealed.output, ran.output)
    finally:
        _cleanup(parent)


def test_prepare_report_matches_python() raises:
    var parent = mkdtemp(prefix="coverage-report-")
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
        var hits = parent + "/hits"
        _ = run_program(["mkdir", "-p", hits], 10)
        var py_manifest = parent + "/py-manifest.txt"
        var prepare = parent + "/prepare.py"
        Path(prepare).write_text(
            "import sys\nfrom pathlib import Path\nsys.path.insert(0,"
            " sys.argv[1])\nimport coverage_io\nroot ="
            " Path(sys.argv[2]).resolve()\nbuild ="
            " Path(sys.argv[3]).resolve()\nmanifest ="
            " Path(sys.argv[4])\ndriver = str((root /"
            " 'driver').resolve())\ncoverage_io.prepare_report(['reporter',"
            " str((build / 'manifest.txt').resolve())], [], root, build,"
            " 'Mojo fixture', '-I .', driver, None, [], manifest)\n"
        )
        var py = run_program(
            [
                "python3",
                prepare,
                realpath("tools"),
                root,
                build,
                py_manifest,
            ],
            30.0,
            merge_errors=False,
        )
        if py.status != 0:
            raise Error(py.errors + py.output)
        var mojo_manifest = parent + "/mojo-manifest.txt"
        var ran = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "prepare-report",
                "--capture-dir",
                hits,
                "--loop-proof-root",
                root,
                "--loop-proof-build",
                build,
                "--manifest",
                mojo_manifest,
                "--compiler",
                "Mojo fixture",
                "--flags",
                "-I .",
                "--mojo",
                root + "/driver",
                "--",
                "reporter",
                build + "/manifest.txt",
            ],
            30.0,
            merge_errors=False,
        )
        if ran.status != 0:
            raise Error(ran.errors + ran.output)
        _same(_text(py_manifest), _text(mojo_manifest))
        assert_equal(ran.output, py.output)
        var finished = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "finish-report",
                "--capture-dir",
                hits,
                "--loop-proof-root",
                root,
                "--loop-proof-build",
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
        if finished.status != 0:
            raise Error(finished.errors + finished.output)
        var refused = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "prepare-report",
                "--capture-dir",
                hits,
                "--loop-proof-root",
                root,
                "--loop-proof-build",
                build,
                "--manifest",
                mojo_manifest,
                "--compiler",
                "Mojo fixture",
                "--flags",
                "-I .",
                "--mojo",
                root + "/driver",
                "--",
                "reporter",
                "missing-manifest",
            ],
            30.0,
            merge_errors=False,
        )
        assert_equal(refused.status, 1)
        assert_true(
            refused.errors.find(
                "The report command must end with the original manifest"
            )
            >= 0
        )
    finally:
        _cleanup(parent)


def _harness_oracle() -> String:
    """Return the script that seals the loop-proof harness fixture."""
    return (
        "import json, sys\nfrom pathlib import Path\nsys.path.insert(0,"
        " sys.argv[1])\nimport check_coverage_loop_proofs as harness\nimport"
        " coverage_loop_proofs as loops\nrepo ="
        " Path(sys.argv[2]).resolve()\nroot ="
        " Path(sys.argv[3]).resolve()\nbuild = Path(sys.argv[4]).resolve()\nfor"
        " name in loops.TOOL_INPUTS:\n    dest = root / name\n   "
        " dest.parent.mkdir(parents=True, exist_ok=True)\n   "
        " dest.write_bytes((repo / name).read_bytes())\nsrc ="
        " harness.SOURCE\n(root / 'fixture.mojo').write_text(src)\n(build /"
        " 'fixture.mojo').parent.mkdir(parents=True, exist_ok=True)\n(build /"
        " 'fixture.mojo').write_text(src)\nrows = []\nfor number, line in"
        " enumerate(src.splitlines(), 1):\n    if line.startswith('def '):\n   "
        "     rows.append('L fixture %d\\n' % number)\n    if line.startswith('"
        "    for '):\n        rows.append('B fixture %d\\n' % number)\n(build /"
        " 'manifest.txt').write_text(''.join(rows))\n(root /"
        " 'driver').write_text('compiler\\n')\ndriver = str((root /"
        " 'driver').resolve())\nloops.begin_generation(root, build, 'Mojo"
        " fixture', '-I .', mojo=driver, sources=['fixture.mojo'])\nmanifest ="
        " (build / 'manifest.txt').read_bytes()\nname = 'fixture.mojo'\nmodule"
        " = b'fixture'\nfragment = b''.join(row for row in"
        " manifest.splitlines(keepends=True)\n    if len(row.split()) >= 2 and"
        " row.split()[1] == module)\nparts = [name.encode(), (root /"
        " name).read_bytes(), (build / name).read_bytes(), fragment]\nrecord ="
        " b'COVORIGIN1 ' + b' '.join(str(len(part)).encode() for part in parts)"
        " + b'\\n' + b''.join(parts)\n(build / (name +"
        " '.cov-origin')).write_bytes(record)\ncheckpoint = (build /"
        " 'generation-inputs.json').read_bytes()\nindex = b'COVORIGIN_INDEX2 1"
        " ' + str(len(manifest)).encode() + b' ' +"
        " str(len(checkpoint)).encode() + b'\\n' + manifest + checkpoint +"
        " str(len(name.encode())).encode() + b'\\n' + name.encode()\n(build /"
        " 'origins.ready').write_bytes(index)\nenv = loops.seal(root, build,"
        " 'Mojo fixture', '-I .', mojo=driver, suites=[])\nprint('Loop"
        " proofs:', env['sha256'], json.dumps(env['receipt']['denominator'],"
        " sort_keys=True))\n"
    )


def test_harness_fixture_matches_python() raises:
    var parent = mkdtemp(prefix="coverage-harness-")
    try:
        var root = parent + "/repo"
        var build = root + "/stage"
        var script = parent + "/oracle.py"
        Path(script).write_text(_harness_oracle())
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
        var output = _seal_mojo(root, build)
        _same(expected, _text(build + "/loop-proofs.json"))
        assert_equal(output, expected_out)
        var checked = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "coverage_loop_seal",
                "verify",
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
        if checked.status != 0:
            raise Error(checked.errors + checked.output)
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
