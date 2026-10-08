# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Partial benchmark refreshes must retain truthful measurement metadata."""

import argparse
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import bench_examples as bench


HOST = {'cpu': 'Fixture CPU', 'os': 'Fixture OS', 'mojo_1_1': 'Mojo 1.1',
        'mojo_1_0': '', 'python': '3.12', 'node': 'v22'}
METRIC = {'ok': True, 'seconds': 1.0, 'rss_kib': 16, 'status': 0, 'output': ''}


def example(name):
    return {'name': name, 'width': 32, 'height': 24, 'frames': 1,
            'threemojo': {'compile': dict(METRIC), 'run': dict(METRIC)},
            'threejs_flat': dict(METRIC), 'threejs_webgl': None, 'mojo10': None}


def payload(date, rows):
    return {'generated_at': date, 'host': dict(HOST), 'examples': rows,
            'probe': {}, 'baselines': {}, 'threejs_webgl': False,
            'mojo10_total': 0, 'mojo10_refused': 0}


class BenchmarkProvenanceTests(unittest.TestCase):
    def test_host_and_toolchain_changes_or_missing_metadata_are_refused(self):
        for key in HOST:
            old = payload('2026-09-01', [example('cube')])
            old['host'][key] = 'different'
            with self.assertRaisesRegex(ValueError, 'host/toolchain'):
                bench.require_same_measurement_host(old, HOST)
        for old in ({}, {'host': {}}, [], {'host': HOST | {'cpu': ''}}):
            with self.assertRaises(ValueError):
                bench.require_same_measurement_host(old, HOST)

    def test_unknown_identity_is_not_an_established_host_match(self):
        for key in ('cpu', 'os', 'mojo_1_1'):
            for value in ('unknown', 'missing', 'not installed', ' '):
                host = HOST | {key: value}
                with self.assertRaises(ValueError):
                    bench.require_same_measurement_host({'host': host}, host)

    def test_retained_direct_dates_and_values_survive_in_catalog_order(self):
        old = payload('2026-09-10', [example('cube')])
        old['examples'][0].update(measured_on='2026-09-03', measurement_date_source='direct')
        fresh = payload('2026-10-01', [example('triangle')])
        before = copy.deepcopy((old, fresh))
        merged = bench.merge_measurements(old, fresh)
        self.assertEqual([row['name'] for row in merged['examples']], ['triangle', 'cube'])
        self.assertEqual(bench.measurement_label(merged['examples'][0]), '2026-10-01')
        self.assertEqual(merged['examples'][1], old['examples'][0])
        self.assertEqual((old, fresh), before)

    def test_legacy_dates_are_identified_as_aggregate_only(self):
        old = payload('2026-09-01', [example('cube')])
        merged = bench.merge_measurements(old, payload('2026-10-01', [example('triangle')]))
        row = merged['examples'][1]
        self.assertEqual(row['threemojo'], old['examples'][0]['threemojo'])
        self.assertEqual(bench.measurement_label(row), 'unknown (legacy: 2026-09-01)')
        self.assertEqual(bench.measurement_label({}), 'unknown')

    def test_aggregate_counts_follow_retained_and_replaced_rows(self):
        cube = example('cube')
        cube['mojo10'] = {'compile': dict(METRIC), 'run': dict(METRIC)}
        old = payload('2026-09-01', [cube])
        old['threejs_webgl'] = True
        triangle = example('triangle')
        triangle['mojo10'] = {'compile': {'ok': False}}
        merged = bench.merge_measurements(old, payload('2026-10-01', [triangle]))
        self.assertEqual((merged['mojo10_total'], merged['mojo10_refused']), (2, 1))
        self.assertFalse(merged['threejs_webgl'])

    def test_slim_rows_and_tables_show_recorded_dates(self):
        slim = bench.slim_payload(payload('2026-10-01', [example('cube')]))
        row = slim['examples'][0]
        self.assertEqual(bench.measurement_label(row), '2026-10-01')
        table = bench.example_table(slim['examples'], False)
        self.assertIn('| Measured |', table)
        self.assertIn('| Draw winner |', table)
        self.assertIn('| 2026-10-01 |', table)
        self.assertIn('per-row measurement date is unknown', table)
        self.assertNotIn('background-color', table)

    def test_draw_winner_uses_frame_time_and_refused_compiles_stay_out(self):
        row = example('cube')
        row['threemojo']['run']['frames_seconds'] = 0.020
        row['threejs_webgl'] = dict(METRIC) | {'frames_seconds': 0.050, 'backend': 'webgl'}
        row['threejs_flat'] = dict(METRIC) | {'frames_seconds': 0.010}
        table = bench.example_table([row], True)
        self.assertIn('| Mojo |', table)
        refused = example('spin')
        refused['mojo10'] = {'compile': {'ok': False, 'seconds': 1.0}, 'run': {'ok': False}}
        version = bench.mojo10_table({'compile': dict(METRIC), 'run': dict(METRIC)},
                                     {'compile': dict(METRIC), 'run': dict(METRIC)},
                                     [refused])
        self.assertNotIn('`spin`', version)
        self.assertIn('Refused catalog rows: 1', version)
        self.assertNotIn('background-color', version)

    def test_cross_host_ratios_do_not_assume_macos_is_faster(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = {key: Path(directory) / (key + '.json') for key in bench.PLATFORMS}
            mac = payload('2026-09-01', [example('cube')])
            paths['macos'].write_text(json.dumps(mac))
            for ratio in (0.5, 1.0, 2.0):
                with self.subTest(ratio=ratio):
                    linux = payload('2026-10-01', [example('cube')])
                    for metric in ('compile', 'run'):
                        linux['examples'][0]['threemojo'][metric]['seconds'] = ratio
                    paths['linux'].write_text(json.dumps(linux))
                    with patch.object(bench, 'results_path', side_effect=paths.__getitem__):
                        report = bench.cross_report()
                    shown = bench.fmt_ratio(ratio)
                    self.assertIn('Linux/macOS whole-process time ratio is ' + shown, report)
                    self.assertIn('Linux/macOS compile-time ratio is ' + shown, report)
                    self.assertIn('Each ratio is Linux time divided by macOS time.', report)
                    self.assertIn('The Linux date is 2026-10-01. The macOS date is 2026-09-01.', report)
                    self.assertIn('These ratios do not isolate hardware speed.', report)
                    self.assertNotIn('faster', report)

    def run_main(self, incompatible):
        with tempfile.TemporaryDirectory() as directory, ExitStack() as stack:
            root = Path(directory)
            path = root / 'results.json'
            old = payload('2026-09-01', [example('cube')])
            path.write_text(json.dumps(old))
            before = path.read_bytes()
            args = argparse.Namespace(platform=bench.this_platform(), from_results=False,
                                      write_wiki=False, skip_mojo10=True, skip_threejs=True,
                                      only='triangle', merge=True)
            host = HOST | {'cpu': 'Other CPU'} if incompatible else HOST
            metric = METRIC | {'ok': False, 'status': 1}
            for name, value in {'parse_args': args, 'results_path': path,
                                'which_mojo': Path('/fixture/mojo'), 'host_info': host}.items():
                stack.enter_context(patch.object(bench, name, return_value=value))
            stack.enter_context(patch.object(bench, 'ROOT', root))
            stack.enter_context(patch.object(bench.time, 'strftime', return_value='2026-10-01'))
            stack.enter_context(patch.object(bench, 'ensure_dirs'))
            stack.enter_context(patch.object(bench, 'emit_tables'))
            baseline = stack.enter_context(patch.object(bench, 'bench_baselines', return_value={'mojo': metric, 'node': metric}))
            probe = stack.enter_context(patch.object(bench, 'bench_probe', return_value={'compile': metric, 'run': metric}))
            compile_example = stack.enter_context(patch.object(bench, 'bench_compile', return_value=metric))
            errors = io.StringIO()
            with redirect_stdout(io.StringIO()), redirect_stderr(errors):
                status = bench.main()
            if incompatible:
                self.assertEqual(status, 2)
                self.assertEqual(path.read_bytes(), before)
                self.assertIn('host/toolchain', errors.getvalue())
                baseline.assert_not_called()
                probe.assert_not_called()
                compile_example.assert_not_called()
            else:
                self.assertEqual(status, 0)
                result = json.loads(path.read_text())
                self.assertEqual([row['name'] for row in result['examples']], ['triangle', 'cube'])
                self.assertEqual(bench.measurement_label(result['examples'][0]), '2026-10-01')
                self.assertEqual(bench.measurement_label(result['examples'][1]), 'unknown (legacy: 2026-09-01)')

    def test_main_refuses_before_measuring_or_overwriting_results(self):
        self.run_main(True)

    def test_main_keeps_valid_same_host_partial_refreshes(self):
        self.run_main(False)


if __name__ == '__main__':
    unittest.main()
