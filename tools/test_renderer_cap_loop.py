# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bind the renderer cap's complete producer graph and revoke changed inputs."""
from pathlib import Path
import tempfile
import unittest
import coverage_loop_proofs as loops

ROOT = Path(__file__).resolve().parents[1]
MODULE = 'renderers/renderer'


class RendererCapLoopTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in loops.STRAND_CAP_SOURCES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((ROOT / name).read_bytes())

    def test_exact_bound_retains_required_runtime_true(self):
        proof = loops.reviewed_nonempty_loops(self.root, MODULE)
        self.assertEqual(set(proof), {3757})
        row = proof[3757]
        self.assertEqual((row['required'], row['impossible']), ('T', 'F'))
        self.assertEqual((row['minimum_cardinality'], row['maximum_cardinality']), (2, 64))
        self.assertEqual(row['dependency_sha256'], loops.STRAND_CAP_SOURCES)
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'other/renderer'), {})

    def test_producer_consumer_and_control_changes_revoke(self):
        cases = (
            ('objects/line_segments2.mojo', 'MIN_CAP_STEPS = 2', 'MIN_CAP_STEPS = 0'),
            ('objects/line_segments2.mojo', 'MAX_CAP_STEPS = 64', 'MAX_CAP_STEPS = 0'),
            ('objects/line_segments2.mojo', 'var wanted = ceil(', 'var wanted = Float32(0) # ceil('),
            ('renderers/renderer.mojo', 'for step in range(1, steps + 1):', 'for step in range(1, steps):'),
            ('renderers/renderer.mojo', '    cap_steps,', '    cap_steps as alternate_cap_steps,'),
            ('tests/test_small_loop_witnesses.mojo', 'count >= 2 and count <= 64', 'count >= 0'),
        )
        for name, before, after in cases:
            path = self.root / name
            original = path.read_text()
            self.assertIn(before, original)
            with self.subTest(name=name, premise=before):
                path.write_text(original.replace(before, after, 1))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})
                path.write_text(original)

    def test_missing_inputs_revoke(self):
        for name in loops.STRAND_CAP_SOURCES:
            path = self.root / name
            original = path.read_bytes()
            with self.subTest(name=name):
                path.unlink()
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})
                path.write_bytes(original)

    def test_source_and_generated_stdlib_shadows_revoke(self):
        stage = self.root / 'coverage/build'
        stage.mkdir(parents=True)
        for root in (self.root, stage):
            for name in ('std.mojo', 'std.mojopkg', 'std.unknown'):
                path = root / name
                with self.subTest(root=root, name=name):
                    path.write_text('unreviewed shadow')
                    self.assertEqual(loops.reviewed_nonempty_loops(
                        self.root, MODULE, include_roots=(stage,)), {})
                    path.unlink()
        self.assertTrue(loops.reviewed_nonempty_loops(self.root, MODULE, include_roots=(stage,)))

    def test_alternate_packages_modules_and_import_roots_revoke(self):
        stage = self.root / 'coverage/build'
        stage.mkdir(parents=True)
        for root in (self.root, stage):
            for relative in ('objects.mojo', 'objects.mojopkg',
                             'objects/line_segments2.mojopkg', 'objects/line_segments2.mojoc',
                             'objects/line_segments2.🔥',
                             'renderers/objects.mojo', 'tests/objects.mojo',
                             'renderers/objects/line_segments2.mojo',
                             'renderers/__init__.🔥'):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                with self.subTest(root=root, relative=relative):
                    path.write_text('unreviewed module')
                    self.assertEqual(loops.reviewed_nonempty_loops(
                        self.root, MODULE, include_roots=(stage,)), {})
                    path.unlink()
                    if relative == 'renderers/objects/line_segments2.mojo':
                        path.parent.rmdir()
            path = root / 'objects/line_segments2'
            with self.subTest(root=root, relative='objects/line_segments2/'):
                path.mkdir()
                self.assertEqual(loops.reviewed_nonempty_loops(
                    self.root, MODULE, include_roots=(stage,)), {})
                path.rmdir()
        self.assertTrue(loops.reviewed_nonempty_loops(self.root, MODULE, include_roots=(stage,)))

    def test_include_root_cannot_hide_physical_entrypoint_shadow(self):
        shadow = self.root / 'tests/objects/line_segments2.mojo'
        shadow.parent.mkdir(parents=True)
        shadow.write_text('unreviewed shadow')
        for include_roots in ((), (self.root / 'tests',)):
            with self.subTest(include_roots=include_roots):
                self.assertEqual(loops.strand_cap_loops(
                    self.root, include_roots=include_roots), {})
                self.assertEqual(loops.reviewed_nonempty_loops(
                    self.root, MODULE, include_roots=include_roots), {})

    def test_manifest_changes_only_the_one_impossible_outcome(self):
        raw = b'L renderers/renderer 3756\nB renderers/renderer 3757\nB renderers/renderer 3758\n'
        proof = loops.reviewed_nonempty_loops(self.root, MODULE)[3757]
        proof['module'] = MODULE
        envelope = {'sha256': '0' * 64, 'receipt': {
            'manifest_sha256': loops.sha256(raw), 'proofs': [proof]}}
        result = loops.masked_manifest(raw, envelope).decode()
        self.assertIn('R renderers/renderer 3757 T reviewed-nonempty-range 1\n', result)
        self.assertIn('L renderers/renderer 3756\n', result)
        self.assertIn('B renderers/renderer 3758\n', result)
        self.assertEqual(result.count('\n'), 4)


if __name__ == '__main__':
    unittest.main()
