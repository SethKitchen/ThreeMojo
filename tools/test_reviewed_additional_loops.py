# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Four individually bound loop proofs, without generic scope inference."""
from pathlib import Path
import tempfile
import unittest
import coverage_loop_proofs as loops

ROOT = Path(__file__).resolve().parents[1]
AXES = 'extensions/carla/lane_distance'
PRODUCER = 'extensions/carla/curve_distance'
BLEND = 'extensions/carla/curve_interval'
HAIR = 'extensions/humanoid/skeleton/head/hair/strands'


class ReviewedAdditionalLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='reviewed additional loops ',
            dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for module in (AXES, PRODUCER, BLEND, HAIR):
            target = self.root/(module+'.mojo')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/(module+'.mojo')).read_bytes())
        leaf = 'tools/carla_lane_oracle/shared_helper_contracts.py'
        target = self.root/leaf
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT/leaf).read_bytes())
        for package in ('extensions/__init__.mojo', 'extensions/carla/__init__.mojo'):
            (self.root/package).write_bytes((ROOT/package).read_bytes())

    def test_extracted_provider_and_executing_leaf_changes_reject_locally(self):
        from unittest.mock import patch
        from carla_lane_oracle import shared_helper_contracts as helpers
        path = self.root/(BLEND + '.mojo')
        raw = path.read_bytes()
        path.write_bytes(raw.replace(b'bits + 1', b'bits + 2', 1))
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, AXES), {})
        path.write_bytes(raw)
        with patch.object(helpers, 'verify_correspondence', lambda texts: (PRODUCER + '.mojo',)):
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, AXES), {})
        receipt = loops.reviewed_nonempty_loops(self.root, AXES)[50]['dependency_sha256']
        for name, digest in receipt.items():
            self.assertEqual(loops.file_sha256(self.root/name), digest)
        self.assertIn('tools/carla_lane_oracle/shared_helper_contracts.py', receipt)
        self.assertIn(BLEND + '.mojo', receipt)

    def test_provider_shadow_during_final_leaf_read_rejects_locally(self):
        from unittest.mock import patch
        leaf = self.root/'tools/carla_lane_oracle/shared_helper_contracts.py'
        shadow = self.root/(BLEND + '.mojopkg')
        read, visits = Path.read_bytes, []
        def observed(path, *args, **kwargs):
            raw = read(path, *args, **kwargs)
            if path == leaf:
                visits.append(True)
                if len(visits) == 2: shadow.write_bytes(b'unreviewed compiled provider')
            return raw
        with patch.object(Path, 'read_bytes', observed):
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, AXES), {})
        self.assertEqual(len(visits), 2)

class ReviewedAxisReceiptTests(unittest.TestCase):
    """The real producer verifier with explicitly modeled compiler-free origins."""
    def setUp(self):
        import test_coverage_loop_proofs as fixtures
        from carla_lane_oracle import full_audit_cleanup_contracts as audit
        self.audit = audit
        self.model_generation = fixtures.model_generation
        self.fixture = fixtures.ProofBindingTests('test_escaped_source_identity_is_rejected')
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.setUp()
        self.root = self.fixture.root
        self.build = self.root/'coverage/build'
        self.build.parent.mkdir(exist_ok=True)
        self.fixture.build.rename(self.build)
        self.fixture.build = self.build
        self.fixture.source.unlink()
        for name in ('module.mojo', 'module.mojo.cov-origin'):
            (self.build/name).unlink()
        self.names = tuple(module + '.mojo' for module in (AXES, PRODUCER, BLEND))
        inputs = (*self.names, 'extensions/__init__.mojo',
                  'extensions/carla/__init__.mojo',
                  'tools/carla_lane_oracle/shared_helper_contracts.py')
        for name in inputs:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/name).read_bytes())
            if name.endswith('.mojo'):
                staged = self.build/name
                staged.parent.mkdir(parents=True, exist_ok=True)
                staged.write_bytes(target.read_bytes() if name not in self.names else
                                   b'compiler-free modeled instrumented provider\n')
        self.manifest = (f'B {AXES} 50\nB {AXES} 56\n'
                         f'B {PRODUCER} 200\nB {BLEND} 592\n').encode()
        (self.build/'manifest.txt').write_bytes(self.manifest)
        loops.begin_generation(self.root, self.build, 'Mojo fixture', '-Werror',
                               sources=self.names)
        self.model_generation(self.root, self.build, names=self.names)

    def derive(self):
        return loops.build_receipt(self.root, self.build, 'Mojo fixture', '-Werror')

    def test_measured_providers_keep_exact_local_false_edge(self):
        receipt = self.derive()
        proof = next(row for row in receipt['proofs'] if row['module'] == AXES)
        self.assertEqual((proof['line'], proof['required'], proof['impossible'],
                          proof['cardinality'], proof['maximum_cardinality']),
                         (50, 'T', 'F', 1, 3))
        self.assertEqual(len(proof['dependency_sha256']), 6)
        for name, digest in proof['dependency_sha256'].items():
            self.assertEqual(loops.file_sha256(self.root/name), digest)
        masked = loops.masked_manifest(self.manifest, {
            'receipt': receipt, 'sha256': loops.sha256(loops.canonical(receipt))}).decode()
        self.assertIn(f'R {AXES} 50 T ', masked)
        self.assertIn(f'B {AXES} 56\n', masked)
        self.assertNotIn(f'B {AXES} 50\n', masked)

    def test_origin_tamper_missing_extra_and_symlink_refuse(self):
        origin = self.build/(PRODUCER + '.mojo.cov-origin')
        raw = origin.read_bytes()
        extra = self.build/(PRODUCER + '.mojo.cov-origin.extra.cov-origin')
        for fault in ('tamper', 'missing', 'extra', 'symlink'):
            with self.subTest(fault=fault):
                if fault == 'tamper':
                    origin.write_bytes(raw + b'unreviewed')
                elif fault == 'missing':
                    origin.unlink()
                elif fault == 'extra':
                    extra.write_bytes(raw)
                else:
                    origin.unlink()
                    origin.symlink_to(self.root/(PRODUCER + '.mojo'))
                try:
                    with self.assertRaises((OSError, ValueError)):
                        self.derive()
                finally:
                    extra.unlink(missing_ok=True)
                    origin.unlink(missing_ok=True)
                    origin.write_bytes(raw)
        self.assertTrue(any(row['module'] == AXES for row in self.derive()['proofs']))

    def test_late_source_and_include_shadows_refuse_at_owner_exit(self):
        import sys
        for location in (self.root, self.build):
            for suffix in ('.extra', '.cov-origin.extra'):
                target = location/(PRODUCER + '.mojo' + suffix)
                fired = []
                def observe(frame, event, value):
                    if (not fired and event == 'return'
                            and frame.f_code is loops._receipt_reviewed_nonempty_loops.__code__
                            and frame.f_locals['module'] == AXES):
                        self.assertIn(50, value)
                        fired.append(True)
                        target.write_bytes(b'late unmaintained resolver shadow')
                with self.subTest(location=location, suffix=suffix):
                    self.assertIsNone(sys.getprofile())
                    sys.setprofile(observe)
                    try:
                        with self.assertRaisesRegex(ValueError, 'resolver surface changed'):
                            self.derive()
                    finally:
                        sys.setprofile(None)
                        target.unlink(missing_ok=True)
                    self.assertEqual(fired, [True])

    def test_provider_origin_changed_after_row_refuses_final_generation_check(self):
        import sys
        origin = self.build/(PRODUCER + '.mojo.cov-origin')
        raw, fired = origin.read_bytes(), []
        def observe(frame, event, value):
            if (not fired and event == 'return'
                    and frame.f_code is loops._receipt_reviewed_nonempty_loops.__code__
                    and frame.f_locals['module'] == AXES):
                self.assertIn(50, value)
                fired.append(True)
                origin.write_bytes(raw + b'late origin mutation')
        self.assertIsNone(sys.getprofile())
        sys.setprofile(observe)
        try:
            with self.assertRaisesRegex(ValueError, 'generation origins'):
                self.derive()
        finally:
            sys.setprofile(None)
            origin.write_bytes(raw)
        self.assertEqual(fired, [True])


if __name__ == '__main__':
    unittest.main()
