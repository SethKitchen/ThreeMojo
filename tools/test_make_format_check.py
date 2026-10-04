# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exercise bounded formatting recipes without the Mojo compiler."""

import errno
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
MAKE_ENVIRONMENT = {'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'MAKELEVEL',
                    'MAKEFILES', 'GNUMAKEFLAGS'}


def definition(source, name):
    start = source.index('define ' + name + '\n')
    return source[start:source.index('\nendef', start) + len('\nendef')]


class FormatRecipeTests(unittest.TestCase):
    def run_recipe(self, paths, fail_batch=0, changed=(), missing=(),
                   scratch_padding='', delete_manifest_stage=None,
                   check_manifest_commands=False):
        source = (ROOT / 'Makefile').read_text()
        start = source.index('# mojo format has no --check flag')
        end = source.index('\n# Instrument the library', start)
        with tempfile.TemporaryDirectory(prefix='format fixture ') as directory:
            root = Path(directory)
            scratch = root / ('scratch files ' + scratch_padding)
            scratch.mkdir()
            for name in dict.fromkeys(paths):
                if name not in missing:
                    path = root / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('original\n')
            mutation = ('path.write_text("")' if str(delete_manifest_stage).startswith('truncate-')
                        else 'path.unlink()')
            if delete_manifest_stage in ('copy', 'truncate-copy'):
                scripts = root / 'bin'
                scripts.mkdir()
                mktemp = scripts / 'mktemp'
                mktemp.write_text(
                    '#!/usr/bin/env python3\nfrom pathlib import Path\n'
                    'import tempfile\n'
                    f'for path in Path("cache").glob("*inputs-*"): {mutation}\n'
                    'print(tempfile.mkdtemp())\n')
                mktemp.chmod(0o700)
            unrelated = root / 'unselected.mojo'
            unrelated.write_text('unselected\n')
            (root / 'formatter.py').write_text(
                'from pathlib import Path\nimport json, sys\n'
                'assert sys.argv[1:3] == ["format", "-q"]\n'
                'paths = sys.argv[3:]\nassert paths\n'
                'log = Path("invocations")\n'
                'batch = len(log.read_text().splitlines()) + 1 if log.exists() else 1\n'
                'with log.open("a") as out: out.write(json.dumps(paths) + "\\n")\n'
                'print("Failed to initialize Crashpad")\n'
                f'if batch == {fail_batch}:\n'
                '    print("formatter failed")\n    raise SystemExit(7)\n'
                f'if {delete_manifest_stage in ("diff", "truncate-diff")!r}:\n'
                f'    for path in Path("cache").glob("*inputs-*"): {mutation}\n'
                f'changed = {tuple(changed)!r}\n'
                'for name in paths:\n'
                '    if any(name.endswith("/" + item) for item in changed):\n'
                '        Path(name).write_text("formatted\\n")\n')
            makefile = (
                'CACHE_DIR := cache\nHASH := fixture\n'
                'FMT_STAMP := cache/fmt-fixture\n'
                'MOJO := python3 formatter.py\n'
                'quote = \'$(subst \',\'"\'"\',$(1))\'\n'
                'FORMATTED := ' + ' '.join(paths) + '\n' +
                definition(source, 'run') + '\n' +
                definition(source, 'stamp') + '\n' + source[start:end] + '\n')
            (root / 'Makefile').write_text(makefile)
            environment = {key: value for key, value in os.environ.items()
                           if key not in MAKE_ENVIRONMENT}
            environment['TMPDIR'] = str(scratch)
            if delete_manifest_stage in ('copy', 'truncate-copy'):
                environment['PATH'] = str(root / 'bin') + os.pathsep + environment['PATH']
            if check_manifest_commands:
                preview = subprocess.run(['make', '-n', 'fmt-check'], cwd=root,
                                         text=True, capture_output=True, env=environment)
                self.assertEqual(preview.returncode, 0, preview.stderr)
                writers = [line for line in preview.stdout.splitlines()
                           if line.startswith("printf '%s")]
                self.assertTrue(writers)
                for command in writers:
                    self.assertLess(len(os.fsencode(command)), 131072)
                    subprocess.run(['/bin/sh', '-n', '-c', command], check=True)
            result = subprocess.run(['make', '-s', 'fmt-check'], cwd=root,
                                    text=True, capture_output=True, env=environment)
            log = root / 'invocations'
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            selected = ['src/' + name.split('/src/', 1)[1]
                        for call in calls for name in call]
            for name in dict.fromkeys(paths):
                if name not in missing:
                    self.assertEqual((root / name).read_text(), 'original\n')
            self.assertEqual(unrelated.read_text(), 'unselected\n')
            self.assertEqual(list(scratch.iterdir()), [])
            self.assertEqual(list((root / 'cache').glob('*inputs-*')), [])
            self.assertNotIn('Crashpad', result.stdout + result.stderr)
            return result, selected, calls, (root / 'cache/fmt-fixture').exists()

    def test_empty_selection_does_not_invoke_formatter(self):
        result, selected, calls, stamped = self.run_recipe([])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [])
        self.assertTrue(stamped)

    def test_small_selection_keeps_order_duplicates_and_scratch_spaces(self):
        paths = ['src/z.mojo', "src/quote's.mojo", 'src/a.mojo', 'src/z.mojo']
        result, selected, calls, stamped = self.run_recipe(paths)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(selected, paths)
        self.assertEqual(len(calls), 1)
        self.assertTrue(stamped)
        self.assertIn('scratch files ', calls[0][0])

    def test_1789_paths_exceed_old_shell_argument_but_all_are_checked(self):
        paths = [f'src/{index:04d}_' + 'x' * 67 + '.mojo' for index in range(1789)]
        # The former copy and diff loops expanded the complete list twice
        # into a single /bin/sh -c argument. Linux caps each argument at
        # 32 pages, independently of the much larger combined ARG_MAX.
        old_command = ('for f in ' + ' '.join(paths) + '; do :; done; ') * 2
        self.assertGreater(len(old_command.encode()), 131072)
        if sys.platform.startswith('linux') and os.sysconf('SC_PAGESIZE') == 4096:
            with self.assertRaises(OSError) as raised:
                subprocess.run(['/bin/sh', '-c', old_command], check=True)
            self.assertEqual(raised.exception.errno, errno.E2BIG)
        result, selected, calls, stamped = self.run_recipe(paths)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(selected, paths)
        self.assertGreater(len(calls), 1)
        self.assertTrue(all(len(call) <= 64 for call in calls))
        self.assertTrue(all(sum(len(os.fsencode(path)) + 1 for path in call) <= 8192
                            for call in calls))
        self.assertTrue(stamped)

    def test_byte_budget_splits_before_file_count_limit(self):
        paths = [f'src/{index:03d}.mojo' for index in range(70)]
        result, selected, calls, stamped = self.run_recipe(paths, scratch_padding='x' * 180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(selected, paths)
        self.assertLess(len(calls[0]), 64)
        self.assertTrue(all(sum(len(os.fsencode(path)) + 1 for path in call) <= 8192
                            for call in calls))
        self.assertTrue(stamped)

    def test_formatter_failure_stops_next_batch_and_is_not_stamped(self):
        paths = [f'src/{index:03d}.mojo' for index in range(140)]
        result, selected, calls, stamped = self.run_recipe(paths, fail_batch=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('formatter failed', result.stdout)
        self.assertIn('Error 7', result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertEqual(selected, paths[:len(selected)])
        self.assertLess(len(selected), len(paths))
        self.assertFalse(stamped)

    def test_all_differences_are_reported_without_changing_sources(self):
        paths = [f'src/{index:03d}.mojo' for index in range(140)]
        changed = (paths[0], paths[70], paths[-1])
        result, selected, calls, stamped = self.run_recipe(paths, changed=changed)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(selected, paths)
        for name in changed:
            self.assertIn('needs formatting: ' + name, result.stdout)
        self.assertIn("Run 'make fmt'.", result.stdout)
        self.assertFalse(stamped)

    def test_missing_input_fails_without_stamp(self):
        paths = ['src/present.mojo', 'src/missing.mojo']
        result, selected, calls, stamped = self.run_recipe(paths, missing=paths[1:])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assertFalse(stamped)

    def test_missing_or_truncated_manifest_fails_at_both_read_loops(self):
        for stage in ('copy', 'diff', 'truncate-copy', 'truncate-diff'):
            with self.subTest(stage=stage):
                result, selected, calls, stamped = self.run_recipe(
                    ['src/a.mojo'], delete_manifest_stage=stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('All files formatted.', result.stdout)
                self.assertFalse(stamped)
                self.assertEqual(len(calls), 0 if stage.endswith('copy') else 1)

    def test_long_paths_cannot_overflow_manifest_recipe_arguments(self):
        # These are readable where PATH_MAX permits, but 64 quoted copies
        # exceed Linux's single-argument limit. Four per recipe stay bounded.
        prefix = 'src/' + ('d' * 180 + '/') * 12
        paths = [prefix + f'{index:03d}.mojo' for index in range(64)]
        if os.pathconf(tempfile.gettempdir(), 'PC_PATH_MAX') < 3000:
            self.skipTest('platform path limit is below the long-path fixture')
        result, selected, calls, stamped = self.run_recipe(
            paths, check_manifest_commands=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(selected, paths)
        self.assertTrue(stamped)

    def test_concurrent_checks_keep_private_manifests_and_detect_changes(self):
        source = (ROOT / 'Makefile').read_text()
        start = source.index('# mojo format has no --check flag')
        end = source.index('\n# Instrument the library', start)
        for same_hash in (False, True):
            with self.subTest(same_hash=same_hash), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'src').mkdir()
                for name in ('a', 'b'):
                    (root / f'src/{name}.mojo').write_text('original\n')
                os.mkfifo(root / 'release')
                (root / 'formatter.py').write_text(
                    'from pathlib import Path\nimport sys\n'
                    'for path in map(Path, sys.argv[3:]):\n'
                    '    if path.name == "b.mojo":\n'
                    '        Path("ready").touch()\n'
                    '        with open("release") as gate: gate.read(1)\n'
                    '        path.write_text("formatted\\n")\n')
                (root / 'Makefile').write_text(
                    'CACHE_DIR := cache\nHASH ?= fixture\n'
                    'FMT_STAMP := cache/fmt-$(HASH)\n'
                    'MOJO := python3 formatter.py\n'
                    'quote = \'$(subst \',\'"\'"\',$(1))\'\n' +
                    definition(source, 'run') + '\n' +
                    definition(source, 'stamp') + '\n' + source[start:end] + '\n')
                environment = {key: value for key, value in os.environ.items()
                               if key not in MAKE_ENVIRONMENT}
                b_hash = 'same' if same_hash else 'b'
                process = subprocess.Popen(
                    ['make', '-s', 'fmt-check', 'HASH=' + b_hash,
                     'FORMATTED=src/b.mojo'], cwd=root, env=environment,
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    start_new_session=True)
                try:
                    deadline = time.monotonic() + 10
                    while not (root / 'ready').exists():
                        if process.poll() is not None or time.monotonic() >= deadline:
                            self.fail('blocked formatting fixture did not start')
                        time.sleep(0.01)
                    manifests = list((root / 'cache').glob('*inputs-*'))
                    result = subprocess.run(
                        ['make', '-s', 'fmt-check',
                         'HASH=' + ('same' if same_hash else 'a'),
                         'FORMATTED=src/a.mojo'], cwd=root, env=environment,
                        text=True, capture_output=True, timeout=10)
                    with (root / 'release').open('w') as gate:
                        gate.write('x')
                    stdout, stderr = process.communicate(timeout=10)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertNotEqual(process.returncode, 0, stdout + stderr)
                    self.assertIn('needs formatting: src/b.mojo', stdout)
                    self.assertNotIn('All files formatted.', stdout)
                    self.assertEqual(len(manifests), 1)
                    self.assertEqual(list((root / 'cache').glob('*inputs-*')), [])
                    if not same_hash:
                        self.assertFalse((root / 'cache/fmt-b').exists())
                    self.assertEqual((root / 'src/b.mojo').read_text(), 'original\n')
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.communicate()

    def test_outer_make_overrides_cannot_replace_fixture_formatter(self):
        with patch.dict(os.environ, {
            'MAKEFLAGS': '-- MOJO=nonexistent-outer-compiler',
            'MAKEOVERRIDES': 'MOJO=nonexistent-outer-compiler',
            'MFLAGS': '-e', 'GNUMAKEFLAGS': '-e',
            'MAKEFILES': 'nonexistent-outer-include', 'MAKELEVEL': '7',
        }):
            result, selected, calls, stamped = self.run_recipe(['src/a.mojo'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(selected, ['src/a.mojo'])
        self.assertTrue(stamped)


if __name__ == '__main__':
    unittest.main()
