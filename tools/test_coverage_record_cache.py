# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free controls for exact, bounded coverage-record memoization."""

import contextlib
import gzip
import io
from pathlib import Path
import random
import signal
import sys
import tempfile
import unittest
from unittest.mock import patch

import coverage_io


class UncachedReducer(coverage_io._EvidenceReducer):
    pass


class CollidingBytes(bytes):
    def __hash__(self):
        return 0


class CoverageRecordCacheTests(unittest.TestCase):
    def compare(self, records):
        outputs = [[], []]
        reducers = [coverage_io.Reducer(outputs[0].append),
                    UncachedReducer(outputs[1].append)]
        for record in records:
            results = []
            for reducer in reducers:
                try:
                    reducer.feed(record)
                    results.append(None)
                except ValueError as error:
                    results.append((type(error), str(error)))
            self.assertEqual(results[0], results[1], record)
            self.assertEqual(outputs[0], outputs[1], record)
            self.assertEqual(reducers[0].payloads, reducers[1].payloads)
            self.assertEqual(reducers[0].evaluations, reducers[1].evaluations)
        return reducers[0], outputs[0]

    def test_hot_records_skip_repeated_parsing(self):
        records = [b'COVLINE:m:1\n', b'COVBRANCH:m:2:T\n',
                   b'COVEVAL2:m:3:F:TF;\n']
        reducer = coverage_io.Reducer(lambda value: None)
        with patch.object(reducer, '_remember', wraps=reducer._remember) as remember:
            for _ in range(100):
                for record in records:
                    reducer.feed(record)
            self.assertEqual(remember.call_count, len(records))
        self.assertEqual(reducer._accepted_records, set(records))

    def test_order_vectors_outcomes_and_abandoned_hits_are_preserved(self):
        records = [
            b'COVLINE:recursive:1.0:T\n', b'COVLINE:recursive:1.0:F\n',
            b'COVEVAL2:recursive:1:F:F-;\n', b'COVLINE:abandoned:2.0:T\n',
            b'COVEVAL2:recursive:1:F:TF;\n', b'COVEVAL2:recursive:1:T:TT;\n',
            b'COVEVAL2:callback:1:F:TF;\n', b'COVEVAL2:callback:1:T:TF;\n',
            b'COVLINE:recursive:1:T\n', b'COVBRANCH:simple:3:F\n',
            b'exception from abandoned evaluation\n',
        ]
        reducer, output = self.compare(records + records[:10] * 100)
        self.assertEqual(output, records[:9] + [b'COVLINE:simple:3:F\n'] + records[9:])
        self.assertEqual(len(reducer.evaluations), 6)
        self.assertNotIn(b'abandoned:2', {key[0] for key in reducer.evaluations})

    def test_exact_raw_bytes_do_not_hide_truncation_or_normalized_variants(self):
        complete = b'COVEVAL2:m:4:T:TT;\n'
        variants = [complete, b' ' + complete, complete[:-1] + b'\r\n',
                    complete[:-1], complete[:-1] + b'\r', complete + b' ',
                    b'\t' + complete, complete[:-1] + b' \n']
        reducer, output = self.compare(variants * 3)
        self.assertEqual(output, [complete])
        self.assertEqual(reducer._accepted_records,
                         {record for record in variants if record.endswith(b'\n')})

    def test_malformed_and_ambiguous_records_always_fail(self):
        bad = [
            b'COVEVAL2:m:4:T:TT\n', b'COVEVAL2:m:4:T:T;\n',
            b'COVEVAL2:m:4:T:--;\n', b'COVEVAL2:m:4:T:TX;\n',
            b'COVEVAL2:m:4:garbage:TT;\n', b'COVEVAL2:m:4.0:T:TT;\n',
            b'COVEVAL2:m:0:T:TT;\n', b'COVEVAL2::4:T:TT;\n',
            b'COVEVAL2:m:4:T:' + b'T' * 512 + b';\n',
            b'COVBRANCH:m:4.0:T\n', b'COVBRANCH:m:4:garbage\n',
            b'COVBRANCH:m:0:T\n', b'COVBRANCH::4:T\n',
        ]
        reducer = coverage_io.Reducer(lambda value: self.fail('invalid record written'))
        for _ in range(3):
            for record in bad:
                with self.subTest(record=record), self.assertRaises(ValueError):
                    reducer.feed(record)
                self.assertNotIn(record, reducer._accepted_records)
        self.compare([b'COVEVAL2:m:4:T:TT;\n', *bad] * 3)

    def test_repeated_diagnostics_never_enter_cache(self):
        records = [b'hello\n', b'COVBRANCH:unparsed\n', b' COVBRANCH: \n',
                   b'COVBRANCH:\n', b'COVEVAL:old\n', b'\n', b'no newline',
                   b'\xff\x00 diagnostic\r\n']
        reducer, output = self.compare(records * 3)
        self.assertEqual(output, records * 3)
        self.assertEqual(reducer._accepted_records, set())

    def test_bytearray_diagnostics_keep_the_original_passthrough_behavior(self):
        records = [bytearray(b'diagnostic\n'), bytearray(b'COVBRANCH:unparsed\n')]
        reducer, output = self.compare(records * 3)
        self.assertEqual(output, records * 3)
        self.assertTrue(all(isinstance(record, bytearray) for record in output))
        self.assertEqual(reducer._accepted_records, set())

    def test_full_cache_reprocesses_evicted_records_without_new_output(self):
        records = [b'COVLINE:m:1\n', b'COVBRANCH:m:2:T\n',
                   b'COVEVAL2:m:3:F:TF;\n']
        with patch.object(coverage_io, 'RECORD_CACHE_CAPACITY', 2):
            reducer, output = self.compare(records * 10)
        self.assertLessEqual(len(reducer._accepted_records), 2)
        self.assertEqual(output, [records[0], b'COVLINE:m:2:T\n', *records[1:]])

    @patch.object(coverage_io, 'CACHE_WINDOW_RECORDS', 16384)
    def test_default_cache_has_bounded_key_count_and_bytes(self):
        capacity = coverage_io.RECORD_CACHE_CAPACITY
        output = []
        reducer = coverage_io.Reducer(output.append)
        records = [b'COVLINE:' + str(index).encode().zfill(502) + b'\n'
                   for index in range(capacity * 3 + 1)]
        for record in records:
            reducer.feed(record)
            self.assertLessEqual(len(reducer._accepted_records), capacity)
        self.assertEqual(output, records)
        self.assertEqual(len(reducer.payloads), len(records))
        self.assertLessEqual(sum(map(len, reducer._accepted_records)),
                             capacity * coverage_io.MAX_RECORD_BYTES)
        for record in records:
            reducer.feed(record)
        self.assertEqual(output, records)

    def test_hash_collisions_compare_complete_record_bytes(self):
        records = [CollidingBytes(record) for record in (
            b'COVLINE:m:1\n', b'COVLINE:m:2\n', b'COVBRANCH:m:3:T\n',
            b'COVBRANCH:m:3:F\n', b'COVEVAL2:m:4:F:TF;\n',
            b'COVEVAL2:m:4:T:TT;\n', b'COVEVAL2:m:4:F:F-;\n',
        )]
        self.assertEqual(len({hash(record) for record in records}), 1)
        reducer, output = self.compare(records * 10)
        self.assertEqual(len(reducer._accepted_records), len(records))
        self.assertEqual(len(output), len(records) + 2)

    def test_utf8_boundaries_and_oversized_raw_padding(self):
        prefix = 'COVEVAL2:é:1:T:'.encode()
        records = [prefix + b'T' * (size - len(prefix) - 2) + b';\n'
                   for size in (511, 512, 513)]
        reducer, output = self.compare(records * 3)
        self.assertEqual(output, records[:2])
        self.assertEqual(reducer._accepted_records, set(records[:2]))
        # Existing parsing checks the stripped evaluation size. Preserve it,
        # but do not let raw padding enlarge cache memory beyond the bound.
        padded = b' ' * 10000 + records[0]
        reducer, output = self.compare([padded] * 3)
        self.assertEqual(output, [records[0]])
        self.assertEqual(reducer._accepted_records, set())

    def test_long_and_unterminated_hits_keep_existing_behavior_uncached(self):
        records = [b'COVLINE:' + b'x' * 10000 + b'\n',
                   b'COVBRANCH:' + b'x' * 10000 + b':1:T\n',
                   b'COVLINE:m:1', b'COVBRANCH:m:2:T']
        reducer, output = self.compare(records * 3)
        self.assertEqual(len(output), 6)
        self.assertEqual(reducer._accepted_records, set())

    def test_admission_follows_every_successful_write(self):
        for record in (b'COVLINE:m:1\n', b'COVEVAL2:m:2:T:TT;\n',
                       b'COVBRANCH:m:3:T\n'):
            output = []
            def write(value):
                self.assertNotIn(record, reducer._accepted_records)
                output.append(value)
            reducer = coverage_io.Reducer(write)
            reducer.feed(record)
            self.assertIn(record, reducer._accepted_records)
            count = len(output)
            reducer.feed(record)
            self.assertEqual(len(output), count)

    def test_write_failure_does_not_admit_a_record(self):
        for record, writes in ((b'COVLINE:m:1\n', 1),
                               (b'COVEVAL2:m:2:T:TT;\n', 1),
                               (b'COVBRANCH:m:3:T\n', 2)):
            for failure in range(1, writes + 1):
                calls = []
                def write(value):
                    calls.append(value)
                    if len(calls) == failure:
                        raise OSError('injected output failure')
                reducer = coverage_io.Reducer(write)
                with self.subTest(record=record, failure=failure), \
                        self.assertRaisesRegex(OSError, 'injected output failure'):
                    reducer.feed(record)
                self.assertEqual(reducer._accepted_records, set())

    def test_cache_is_private_to_each_capture(self):
        record = b'COVEVAL2:m:1:T:TT;\n'
        for _ in range(3):
            output = []
            reducer = coverage_io.Reducer(output.append)
            reducer.feed(record)
            self.assertEqual(output, [record])

    def test_deterministic_mixed_churn_matches_uncached_stream(self):
        rng = random.Random(594)
        records = []
        for index in range(1, 100):
            module = rng.choice([b'carla/map', b'math/vector3', 'café'.encode()])
            decision = module + b':' + str(index).encode()
            records.extend([b'COVLINE:' + decision + b'\n',
                            b'COVLINE:' + decision + b'.0:T\n',
                            b'COVBRANCH:' + decision + b':F\n',
                            b'COVEVAL2:' + decision + b':F:TF--;\n',
                            b'COVEVAL2:' + decision + b':T:T---;\n'])
        records.extend([b'diagnostic\n', b'COVBRANCH:unparsed\n',
                        b'COVEVAL2:m:1:T:TT;', b'COVBRANCH:m:1.0:T\n'])
        stream = [rng.choice(records) for _ in range(5000)]
        with patch.object(coverage_io, 'RECORD_CACHE_CAPACITY', 7):
            self.compare(stream)

    def test_capture_preserves_record_counts_diagnostics_and_failure_exit(self):
        records = b'COVLINE:m:1\nCOVEVAL2:m:2:T:TT;\n'
        diagnostics = b'diagnostic\nCOVBRANCH:unparsed\n'
        for code in (0, 7):
            with tempfile.TemporaryDirectory() as directory, \
                    contextlib.redirect_stdout(io.StringIO()) as progress:
                root = Path(directory)
                command = [sys.executable, '-c',
                           f'import sys;sys.stderr.buffer.write({records!r} * 100 + '
                           f'{diagnostics!r} * 3);print("stdout intact");sys.exit({code})']
                status = coverage_io.capture(command, root / 'out', root / 'err.gz')
                self.assertEqual(status, code)
                self.assertEqual((root / 'out').read_bytes(), b'stdout intact\n')
                self.assertEqual(gzip.decompress((root / 'err.gz').read_bytes()),
                                 records + diagnostics * 3)
                self.assertIn(f'complete (exit {code})', progress.getvalue())
                self.assertIn('206 stderr records', progress.getvalue())

    def test_capture_preserves_signal_exit(self):
        with tempfile.TemporaryDirectory() as directory, \
                contextlib.redirect_stdout(io.StringIO()):
            root = Path(directory)
            command = [sys.executable, '-c',
                       'import os,signal;os.kill(os.getpid(),signal.SIGTERM)']
            self.assertEqual(coverage_io.capture(command, root / 'out', root / 'err.gz'),
                             128 + signal.SIGTERM)


class AdaptiveRecordCacheTests(CoverageRecordCacheTests):
    # Reuse the complete record/protocol controls with short transitions too.
    def setUp(self):
        for name, value in (("CACHE_WINDOW_RECORDS", 16),
                            ("CACHE_BYPASS_RECORDS", 32)):
            active = patch.object(coverage_io, name, value)
            active.start()
            self.addCleanup(active.stop)

    def test_low_hit_window_bypasses_and_then_resamples_hot_records(self):
        output = []
        reducer = coverage_io.Reducer(output.append)
        unique = [b'COVLINE:cold:' + str(index).encode() + b'\n'
                  for index in range(16)]
        for record in unique:
            reducer.feed(record)
        hot = b'COVEVAL2:hot:1:T:TT;\n'
        for index in range(32):
            reducer.feed(hot)
            self.assertTrue(reducer._bypassing)
            self.assertEqual(reducer._accepted_records, set())
            self.assertEqual(reducer._remaining, 31 - index)
        reducer.feed(hot)
        self.assertFalse(reducer._bypassing)
        self.assertEqual(reducer._accepted_records, {hot})
        for _ in range(16):
            reducer.feed(hot)
        self.assertFalse(reducer._bypassing)
        self.assertEqual(output, unique + [hot])

    def test_hit_threshold_is_exactly_one_quarter(self):
        hot = b'COVLINE:hot:1\n'
        for hits, bypass in ((3, True), (4, False)):
            reducer = coverage_io.Reducer(lambda value: None)
            for _ in range(hits + 1):
                reducer.feed(hot)
            for index in range(15 - hits):
                reducer.feed(b'COVLINE:cold:' + str(index).encode() + b'\n')
            self.assertEqual(reducer._remaining, 0)
            self.assertEqual(reducer._hits, hits)
            reducer.feed(b'diagnostic\n')
            self.assertEqual(reducer._bypassing, bypass)

    def test_bypass_calls_original_parser_for_every_record(self):
        reducer = coverage_io.Reducer(lambda value: None)
        for index in range(16):
            reducer.feed(b'COVLINE:cold:' + str(index).encode() + b'\n')
        original = coverage_io._EvidenceReducer.feed
        with patch.object(coverage_io._EvidenceReducer, 'feed', autospec=True,
                          side_effect=original) as parse:
            for _ in range(32):
                reducer.feed(b'COVEVAL2:hot:1:T:TT;\n')
        self.assertEqual(parse.call_count, 32)
        self.assertTrue(reducer._bypassing)

    def test_hot_cold_unique_churn_and_hot_phase_transitions(self):
        hot = [b'COVLINE:hot:1.0:T\n', b'COVEVAL2:hot:1:T:T-;\n']
        cold = [b'COVLINE:cold:' + str(index).encode() + b'\n'
                for index in range(100)]
        churn = [b'COVEVAL2:churn:' + str(index).encode() + b':F:TF;\n'
                 for index in range(1, 10)]
        with patch.object(coverage_io, 'RECORD_CACHE_CAPACITY', 8):
            reducer, _ = self.compare(hot * 40 + cold + churn * 20 + hot * 100)
        self.assertFalse(reducer._bypassing)
        self.assertTrue(set(hot).issubset(reducer._accepted_records))
        self.assertLessEqual(len(reducer._accepted_records), 8)
        self.assertGreaterEqual(reducer._remaining, 0)
        self.assertLessEqual(reducer._remaining, 32)

    def test_repeated_errors_cannot_stall_the_window_counter(self):
        output = []
        reducer = coverage_io.Reducer(output.append)
        good = b'COVEVAL2:m:1:T:TT;\n'
        bad = good[:-1]
        reducer.feed(good)
        for _ in range(200):
            with self.assertRaises(ValueError):
                reducer.feed(bad)
            self.assertGreaterEqual(reducer._remaining, 0)
            self.assertLessEqual(reducer._remaining, 32)
            self.assertNotIn(bad, reducer._accepted_records)
        self.assertEqual(output, [good])
        self.compare([good] + [bad] * 200 + [good] * 100)

    def test_writer_failures_across_transitions_do_not_admit_new_records(self):
        def fail(value):
            raise OSError('injected output failure')
        reducer = coverage_io.Reducer(fail)
        for index in range(1, 201):
            record = b'COVEVAL2:m:' + str(index).encode() + b':F:TF;\n'
            with self.assertRaisesRegex(OSError, 'injected output failure'):
                reducer.feed(record)
            self.assertNotIn(record, reducer._accepted_records)
            self.assertGreaterEqual(reducer._remaining, 0)
            self.assertLessEqual(reducer._remaining, 32)

    def test_diagnostics_and_bytearrays_remain_repeated_in_every_phase(self):
        rows = [b'COVBRANCH:unparsed\n', b'hello\n',
                bytearray(b'mutable diagnostic\n')]
        reducer, output = self.compare(rows * 100)
        self.assertEqual(output, rows * 100)
        self.assertEqual(reducer._accepted_records, set())


if __name__ == '__main__':
    unittest.main()
