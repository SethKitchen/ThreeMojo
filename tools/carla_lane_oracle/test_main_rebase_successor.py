# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact latest-main Streamline composition preserves historical proof evidence."""
import hashlib
import json
from pathlib import Path
import unittest

import full_audit_cleanup_contracts as owner
import pr760_arithmetic_stage as stage

ROOT = Path(__file__).resolve().parents[2]
MAIN_INPUTS = {'examples/streamline.mojo': '21dd83274a80642ab1e6584bff0be6b1c680ae33f6df8c286c0eaf33f9a750cd',
 'extensions/streamline/__init__.mojo': '6adec518df30a78f8e3a1ef6616d752f93c320f65b6bbf492e6c20f8bfec81d2',
 'extensions/streamline/constants.mojo': 'b615c90fbdda9d403273875fa457c96e8ca2ae464ff6c74ae17f846a4ef358a2',
 'extensions/streamline/jitter.mojo': '51a7d80cf43c03ffcab21312fc2daee6af14276b710826a5695c1e1cc9245507',
 'extensions/streamline/kinds.mojo': '33d193bbce007e2c1b9f0a937b4ab6eb03dc2e2434e2901fff210351adbcf9c2',
 'extensions/streamline/options.mojo': '286512fe326badfa8ee4ab5da380f2d882da5762f9571e4813ac23e528b38999',
 'extensions/streamline/sizing.mojo': '8da8084667f413d3354af700b2414bdbb0783033eeca55f8e7a60cf1768b7976',
 'extensions/streamline/tags.mojo': '683876ad1f74491cc22ad6ef5879f6e93ac92af2537f140e95dab4d6466b9e34',
 'extensions/streamline/upscaler.mojo': '7a4edcae38ae426f7cee81ba6f032c56aaded6ce1ca4741f941c5cdb8b9120d9',
 'tests/compile_fail/a_buffer_kind_is_not_a_bare_int.mojo': 'ee03b16868a7c24fba3651ee682ab0861b8ab893c7d97b508b1ba9019f284fb9',
 'tests/compile_fail/a_denoiser_preset_is_not_a_bare_int.mojo': '361cbc3bb49b183ce42f7db30ffdf2a3b6a99b50fe96afe3f6f8890fa3aaf617',
 'tests/compile_fail/a_dlss_feature_is_not_a_bare_int.mojo': 'bc64dbc64b72053756e0cdef165fe44bf11735429232a2fd2f982a99441f30d8',
 'tests/compile_fail/a_dlss_mode_is_not_a_bare_int.mojo': '81b777d7e3b730c96b6923b8b6c36a6f86c9f01eccbca081e9a5dd8f804f8eba',
 'tests/compile_fail/a_motion_vector_space_is_not_a_bare_int.mojo': '279d76407e55570f803f1154a926bb28e7fac7cf279267b328fdf9ce51563806',
 'tests/compile_fail/a_normal_roughness_mode_is_not_a_bare_int.mojo': 'a2c5f2f982c320772bceab8bad80bfc7cceb4ce40db86ca48bf8d2490f05b65b',
 'tests/compile_fail/a_super_resolution_preset_is_not_a_bare_int.mojo': 'd815bbc02df24e36e199eda2118311e92de5a07ae16c3c79597d83ac27a7dc20',
 'tests/test_streamline_constants.mojo': 'ee26d8e6c980d4f5ebb768b10c01badd8e3ba4d4589a67da00235778d9c69425',
 'tests/test_streamline_kinds.mojo': 'ee6c3d9e4fadac58ef8cf5783175450dd93b85bfcdcd708c7358b010af67f973',
 'tests/test_streamline_options.mojo': '9233973ed85436859b2b13f49f198e4352b7931cf6a5eeb6b94949e9bcdb4f3b',
 'tests/test_streamline_sizing.mojo': 'e2ee07176204d094b4da958714caa5ba91939b5bdfacee63ecba8e35ee5ca641',
 'tests/test_streamline_tags.mojo': '0bc1b868a5c820c188b5b93b624687994fc64eb4258549025e37aa7b7f907825',
 'tests/test_streamline_upscaler.mojo': 'f4c1e4c217d332a77dd3079afce7ce7e3e5713183ac575507305c200b3061958',
 'tools/carla_lane_oracle/test_expectation_binding_successor.py': '6f866d62d04370dad8eed28e7e6bd26c5b6ab804b00c407932624ba183cd9a08',
 'tools/carla_lane_oracle/typed_boundary_contracts.py': '59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362',
 'tools/compile_fail_expectations.json': 'deee9f738d1387ee05ebc4a30e2c5bb1ab4cfbfda04dd2fa6c01aec124552a29'}


class MainRebaseSuccessorControls(unittest.TestCase):
    def test_all_main_sources_and_diagnostics_keep_exact_published_bytes(self):
        image = json.loads((ROOT/owner.PR760_IMAGE).read_bytes())
        for path, digest in MAIN_INPUTS.items():
            with self.subTest(path=path):
                self.assertEqual(owner.sha((ROOT/path).read_bytes()), digest)
                if path.endswith('.mojo'):
                    self.assertEqual(image['inputs'][path], digest)
        self.assertEqual(sum(path.endswith('.mojo') for path in MAIN_INPUTS), 22)

    def test_historical_stage_and_typed_evidence_remain_exact(self):
        self.assertEqual(owner.sha((ROOT/'tools/carla_lane_oracle/pr760_arithmetic_stage.py').read_bytes()),
                         '03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359')
        old = ROOT/'tools/carla_lane_oracle/pr760-typed_boundary-predecessor.txt'
        self.assertEqual(owner.sha(old.read_bytes()),
                         stage.PROTECTED_AUTHORITY_SHA256['tools/carla_lane_oracle/typed_boundary_contracts.py'])
        self.assertEqual(owner.sha((ROOT/owner.PR760_OWNER_PREDECESSOR).read_bytes()),
                         '6138ba2dcac394c716ea9ed32e74e0c6d15857d5c605fc82304d21d0c80fdc69')

    def test_stage_witness_inverse_preserves_complete_old_bytes_and_rejects_changes(self):
        path = 'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py'
        current = (ROOT/path).read_bytes()
        old = (ROOT/'tools/carla_lane_oracle/pr760-test_pr760_arithmetic_stage-predecessor.txt').read_bytes()
        self.assertEqual(owner.stage_witness_predecessor_bytes(current), old)
        self.assertEqual(owner.stage_witness_predecessor_bytes(old), old)
        self.assertEqual(owner.sha(old), stage.REGISTRY_INPUT_SHA256[path])
        for bad in (current+b'\n', old+b'\n', bytearray(current), b''):
            with self.subTest(kind=type(bad).__name__), self.assertRaises(owner.ContractError):
                owner.stage_witness_predecessor_bytes(bad)

    def test_all_seven_streamline_diagnostics_extend_original_expectations(self):
        typed = owner.typed_boundary
        raw = (ROOT/'tools/compile_fail_expectations.json').read_bytes()
        before = json.loads(typed.expectation_predecessor(raw))
        current = json.loads(raw)
        self.assertEqual((len(before), len(current)), (689, 704))
        streamline = {path for path in MAIN_INPUTS if path.startswith('tests/compile_fail/')}
        self.assertEqual(len(streamline), 7)
        self.assertTrue(streamline <= set(current)-set(before))
        self.assertEqual({path: current[path] for path in before}, before)


if __name__ == '__main__':
    unittest.main()
