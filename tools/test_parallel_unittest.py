# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests for tools/parallel_unittest.py."""

import contextlib
import io
from pathlib import Path
import tempfile
import textwrap
import threading
import unittest
from unittest import mock

import parallel_unittest as runner


def _write(directory, name, body):
    (Path(directory) / name).write_text(textwrap.dedent(body), encoding='utf-8')


_PASS = '''
    import unittest
    class T(unittest.TestCase):
        def test_one(self):
            self.assertTrue(True)
        def test_two(self):
            self.assertTrue(True)
'''
_FAIL = '''
    import unittest
    class T(unittest.TestCase):
        def test_bad(self):
            self.assertEqual(1, 2)
'''
_MODULE_SETUP = '''
    import unittest
    STATE = []
    def setUpModule():
        STATE.append(1)
    class T(unittest.TestCase):
        def test_shared(self):
            self.assertEqual(STATE, [1])
'''
_CLASS_SETUP = '''
    import unittest
    class T(unittest.TestCase):
        @classmethod
        def setUpClass(cls):
            cls.value = 3
        def test_shared(self):
            self.assertEqual(self.value, 3)
'''

# A class over CHUNK tests, a single-test class and a class without set-up.
_CHUNKED = '''
    import unittest
    class A(unittest.TestCase):
        @classmethod
        def setUpClass(cls):
            cls.value = 1
''' + ''.join(f'''        def test_{i}(self):
            self.assertEqual(self.value, 1)
''' for i in range(5)) + '''    class B(unittest.TestCase):
        @classmethod
        def tearDownClass(cls):
            pass
        def test_0(self):
            pass
    class C(unittest.TestCase):
        def test_0(self):
            pass
'''


class ParallelUnittest(unittest.TestCase):
    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = runner.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def test_independent_tests_run_one_per_process(self):
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_a.py', _PASS)
            _write(directory, 'helper.py', _FAIL)  # Not a test module.
            self.assertEqual(runner.modules(directory), ['test_a.py'])
            labels = [label for label, _ in runner.units(directory, 'test_a.py')]
            self.assertEqual(labels, ['test_a.T.test_one', 'test_a.T.test_two'])
            code, out, err = self.run_main('--jobs', '2', directory)
        self.assertEqual(code, 0)
        self.assertIn('2 of 2 units passed (1 modules)', out)
        self.assertEqual(err, '')

    def test_shared_set_up_runs_a_few_tests_of_one_class_per_process(self):
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_m.py', _MODULE_SETUP)
            _write(directory, 'test_c.py', _CLASS_SETUP)
            _write(directory, 'test_k.py', _CHUNKED)
            for name in ('test_m.py', 'test_c.py'):
                (unit,) = runner.units(directory, name)
                self.assertNotIn('discover', unit[1])
            listed = runner.units(directory, 'test_k.py')
            self.assertEqual([label for label, _ in listed],
                             [f'test_k.A.test_0 (+{runner.CHUNK - 1})',
                              f'test_k.A.test_{runner.CHUNK}', 'test_k.B.test_0', 'test_k.C.test_0'])
            self.assertEqual(listed[0][1][3:], [f'test_k.A.test_{i}' for i in range(runner.CHUNK)])
            code, out, _ = self.run_main(directory)
        self.assertEqual(code, 0)
        self.assertIn('6 of 6 units passed (3 modules)', out)

    def test_shards_partition_the_units(self):
        for index, count in ((1, 1), (1, 6), (6, 6), (10, 12)):
            self.assertEqual(runner.shard(f'{index}/{count}'), (index, count))
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_a.py', _PASS)
            _write(directory, 'test_b.py', _FAIL)
            _write(directory, 'test_k.py', _CHUNKED)
            results = [self.run_main('--shard', f'{index}/3', directory) for index in (1, 2, 3)]
        counts = [int(out.rsplit(' units passed', 1)[0].rsplit(' of ', 1)[1]) for _, out, _ in results]
        self.assertEqual(sum(counts), 7)
        self.assertEqual(sorted(code for code, _, _ in results), [0, 0, 1])
        for bad in ('0/3', '4/3', '1', 'a/b', '01/6', '1/06', '+1/6', '1/+6',
                    ' 1/6', '1/6 ', '1 /6', '1/ 6', '\t1/6', '1/6\n',
                    '1/1_0', '١/6', '1/６'):
            with self.subTest(shard=bad), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(SystemExit) as raised:
                    self.run_main('--shard', bad, directory)
                self.assertEqual(raised.exception.code, 2)

    def test_an_import_error_runs_and_fails_as_one_module(self):
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_x.py', 'import missing_module_for_this_test\n')
            (unit,) = runner.units(directory, 'test_x.py')
            self.assertIn('discover', unit[1])
            code, out, err = self.run_main(directory)
        self.assertEqual(code, 1)
        self.assertIn('missing_module_for_this_test', out)
        self.assertIn('failed: test_x.py', err)

    def test_a_failing_test_fails_the_run(self):
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_a.py', _PASS)
            _write(directory, 'test_b.py', _FAIL)
            code, out, err = self.run_main('--jobs', '1', directory)
        self.assertEqual(code, 1)
        self.assertIn('2 of 3 units passed', out)
        self.assertIn('AssertionError', out)
        self.assertIn('failed: test_b.T.test_bad', err)

    def test_unreadable_listing_falls_back_to_the_whole_module(self):
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_a.py', _PASS)
            (unit,) = runner.units(directory, 'test_a.py', python=sys_executable_that_prints_nothing())
            self.assertEqual(unit[0], 'test_a.py')

    def test_an_empty_directory_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            code, _, err = self.run_main(directory)
        self.assertEqual(code, 1)
        self.assertIn('no test modules', err)

    def test_jobs_must_be_positive(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                self.run_main('--jobs', '0', directory)

    def test_run_unit_reports_output_and_time(self):
        with tempfile.TemporaryDirectory() as directory:
            _write(directory, 'test_a.py', _PASS)
            label, code, seconds, output = runner.run_unit(
                directory, 'x', [runner.sys.executable, '-c', 'print("done", end="")'])
        self.assertEqual((label, code, output), ('x', 0, 'done'))
        self.assertGreaterEqual(seconds, 0.0)

    def test_exclusive_selection_uses_exact_command_not_label(self):
        target = runner._EXCLUSIVE_TEST
        self.assertTrue(runner._exclusive(
            ['python', '-m', 'unittest', 'test_other.T.test_a', target]))
        self.assertTrue(runner._exclusive(
            ['python', '-m', 'unittest', 'discover', '-s', '/tmp/tests',
             '-p', 'test_coverage_invariant_contracts.py']))
        for tests in ([target + '_other'], [target.replace('test_historical', 'test_other')],
                      ['discover', '-s', '/tmp/tests', '-p', 'test_other.py']):
            with self.subTest(tests=tests):
                self.assertFalse(runner._exclusive(['python', '-m', 'unittest', *tests]))

    def test_exclusive_unit_finishes_before_other_units_still_run_in_parallel(self):
        target = runner._EXCLUSIVE_TEST
        # The target is not the label or first test in its shared set-up group.
        first = target.rsplit('.', 1)[0] + '.test_first'
        grouped = (first + ' (+1)', ['python', '-m', 'unittest', first, target])
        fallback = ('test_coverage_invariant_contracts.py',
                    ['python', '-m', 'unittest', 'discover', '-s', '/tmp/tests',
                     '-p', 'test_coverage_invariant_contracts.py'])
        for exclusive in (grouped, fallback):
            with self.subTest(exclusive=exclusive[0]):
                work = [
                    ('test_other.py', ['python', '-m', 'unittest', 'discover',
                                       '-s', '/tmp/tests', '-p', 'test_other.py']),
                    exclusive,
                    ('test_a.T.test_one', ['python', '-m', 'unittest', 'test_a.T.test_one']),
                ]
                finished = threading.Event()
                together = threading.Barrier(2)
                seen = []

                def run(directory, label, command):
                    seen.append((label, command))
                    if (label, command) == exclusive:
                        self.assertEqual(seen, [exclusive])
                        finished.set()
                    else:
                        self.assertTrue(finished.is_set())
                        together.wait(timeout=3)
                    return label, 0, 0, ''

                with mock.patch.object(runner, 'modules', return_value=['test_fixture.py']), \
                        mock.patch.object(runner, 'units', return_value=work) as listing, \
                        mock.patch.object(runner, 'run_unit', side_effect=run):
                    code, out, err = self.run_main('--jobs', '2', '/tmp/tests')
                listing.assert_called_once()
                self.assertEqual(code, 0)
                self.assertCountEqual(seen, work)
                self.assertIn('3 of 3 units passed (1 modules)', out)
                self.assertEqual(err, '')

    def test_exclusive_scheduling_preserves_shards_inventory_and_failure(self):
        target = runner._EXCLUSIVE_TEST
        work = [(name, ['python', '-m', 'unittest', name])
                for name in ('test_a.T.test_one', target, 'test_z.T.test_one')]
        seen = []
        for index in (1, 2, 3, 4):
            shard_seen = []

            def run(directory, label, command):
                shard_seen.append((label, command))
                return label, int(label == target), 1, 'proof failed\n' if label == target else ''

            with mock.patch.object(runner, 'modules', return_value=['test_fixture.py']), \
                    mock.patch.object(runner, 'units', return_value=work) as listing, \
                    mock.patch.object(runner, 'run_unit', side_effect=run):
                code, out, err = self.run_main('--jobs', '2', '--shard', f'{index}/4',
                                               '/tmp/tests')
            listing.assert_called_once()
            self.assertEqual(shard_seen, work[index - 1::4])
            self.assertEqual(code, int(index == 2))
            if index == 2:
                self.assertIn('proof failed', out)
                self.assertIn('failed: ' + target, err)
            seen.extend(shard_seen)
        self.assertCountEqual(seen, work)

    def test_exclusive_failure_does_not_skip_remaining_work(self):
        target = runner._EXCLUSIVE_TEST
        work = [(name, ['python', '-m', 'unittest', name])
                for name in ('test_a.T.test_one', target)]
        with mock.patch.object(runner, 'modules', return_value=['test_fixture.py']), \
                mock.patch.object(runner, 'units', return_value=work), \
                mock.patch.object(runner, 'run_unit', side_effect=[
                    (target, 1, 1, 'proof failed'), ('test_a.T.test_one', 0, 1, '')
                ]) as run:
            code, out, err = self.run_main('--jobs', '2', '/tmp/tests')
        self.assertEqual([call.args[1:] for call in run.call_args_list], [work[1], work[0]])
        self.assertEqual(code, 1)
        self.assertIn('1 of 2 units passed', out)
        self.assertIn('proof failed\n', out)
        self.assertIn('failed: ' + target, err)


def sys_executable_that_prints_nothing():
    """A real program that exits 0 with no output, standing in for Python."""
    return 'true'


if __name__ == '__main__':
    unittest.main()
