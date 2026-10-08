# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Only literal spelling may change; stored words and every other token stay bound."""
from pathlib import Path
import unittest
import reviewed_cleanup_contracts as contracts

ROOT = Path(__file__).resolve().parents[2]


class StoredWordDependencyTests(unittest.TestCase):
    def test_original_complete_fingerprints_are_retained(self):
        trig = (ROOT/contracts.TRIG_PATH).read_text()
        geometry = (ROOT/contracts.GEOMETRY_PATH).read_text()
        self.assertEqual(contracts.trig_word_sha256(trig), contracts.TRIG_WORD_SHA256)
        self.assertEqual(contracts.geometry_word_sha256(geometry), contracts.GEOMETRY_WORD_SHA256)

    def test_same_words_and_comments_are_accepted_on_named_paths_only(self):
        text = (ROOT/contracts.GEOMETRY_PATH).read_text()
        changed = text.replace('0.2369268850561891,', '0.23692688505618910000,') + '\n# harmless comment\n'
        changed = changed.replace('-0.9061798459386640,', '-0.90617984593866400,')
        self.assertNotEqual(text, changed)
        contracts.verify_dependency(contracts.GEOMETRY_PATH, changed, contracts.GEOMETRY_TOKEN_SHA256)
        with self.assertRaises(ValueError):
            contracts.verify_dependency('unlisted/geometry.mojo', changed, contracts.GEOMETRY_TOKEN_SHA256)
        with self.assertRaises(ValueError):
            contracts.verify_dependency(contracts.GEOMETRY_PATH, changed, '0'*64)

    def test_changed_word_type_and_declaration_binding_are_rejected(self):
        text = (ROOT/contracts.GEOMETRY_PATH).read_text()
        for before, after in [('0.2369268850561891,', '0.2469268850561891,'),
                              ('comptime _GL_NODES:', 'comptime _OTHER_NODES:'),
                              ('Array[Float64, 5]', 'Array[Float32, 5]')]:
            with self.subTest(before=before):
                self.assertIn(before, text)
                with self.assertRaises(ValueError):
                    contracts.verify_dependency(contracts.GEOMETRY_PATH, text.replace(before, after, 1), contracts.GEOMETRY_TOKEN_SHA256)

    def test_expression_suffix_hidden_declaration_and_extra_flow_are_rejected(self):
        text = (ROOT/contracts.GEOMETRY_PATH).read_text()
        marker = 'comptime _GL_NODES: Array[Float64, 5] = ['
        at = text.index(']', text.index(marker) + len(marker)) + 1
        start = text.index(marker)
        declaration = text[start:at]
        removed = text[:start] + text[at:]
        moved = declaration + '\n' + removed
        nested = removed + '\ndef _hidden_constants():\n' + '\n'.join('    '+line for line in declaration.splitlines()) + '\n'
        mutations = [moved, nested, text[:at]+' + [0.0]'+text[at:],
                     text+'\n"""comptime _GL_NODES: Array[Float64, 5] = [0.0]"""\n',
                     text+'\ndef _unreviewed_control() -> Int:\n    return 1\n',
                     text+'\nfrom unreviewed import Float64\n']
        for changed in mutations:
            with self.subTest(suffix=changed[-80:]), self.assertRaises(ValueError):
                contracts.verify_dependency(contracts.GEOMETRY_PATH, changed, contracts.GEOMETRY_TOKEN_SHA256)


if __name__ == '__main__':
    unittest.main()
