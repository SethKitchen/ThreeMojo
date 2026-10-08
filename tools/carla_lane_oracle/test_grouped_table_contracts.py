"""Mutation controls for the exact producer/consumer contract."""
from pathlib import Path
import unittest
import grouped_table_contracts as contract

ROOT=Path(__file__).resolve().parents[2]
class GroupedTableContractTests(unittest.TestCase):
    def setUp(self):
        import selection_finiteness_contracts as selection
        self.module=selection.predecessor_text(ROOT,contract.MODULE)
        self.geometry=(ROOT/'extensions/carla/geometry.mojo').read_text()
    def test_current_producer_consumer(self):
        self.assertEqual(contract.verify(ROOT)['status'],'PASS')
    def test_benign_comments_and_inline_spacing(self):
        for text in ['# harmless comment\n' + self.module,
                     self.module.replace('var node_low =', 'var  node_low =')]:
            self.assertEqual(contract.verify_text(text,self.geometry)['status'],'PASS')
    def test_consumer_mutations(self):
        for old,new in [('materialize[_GL_WEIGHTS]()','materialize[_GL_NODES]()'),('materialize[_GL_NODES]()','materialize[_GL_WEIGHTS]()'),('var node_low =','weights[0] = 0.0\n    var node_low ='),('d.error','0.0'),('5 * pieces','pieces'),('if not _sum2_supported_environment():','if _sum2_supported_environment():'),('_GL_WEIGHTS[0] <= 1.0','_GL_WEIGHTS[0] < 1.0')]:
            with self.subTest(change=new):
                self.assertIn(old,self.module)
                with self.assertRaises(ValueError):contract.verify_text(self.module.replace(old,new),self.geometry)
    def test_producer_mutations(self):
        for old,new in [('comptime _GL_WEIGHTS:','var _GL_WEIGHTS:'),('0.5688888888888889','0.0'),('0.9061798459386640','1.0')]:
            with self.subTest(change=new):
                with self.assertRaises(ValueError):contract.verify_text(self.module,self.geometry.replace(old,new))
    def test_constant_declaration_decoys_are_rejected(self):
        import re
        declaration = re.search(r'comptime _GL_WEIGHTS: Array\[Float64, 5\] = \[.*?\]', self.geometry, re.S).group(0)
        for replacement in ['"""' + declaration + '"""',
                            'if True:\n' + '\n'.join('    ' + line for line in declaration.splitlines()),
                            declaration + ' + [0.0]']:
            with self.subTest(replacement=replacement):
                with self.assertRaises(ValueError):
                    contract.verify_text(self.module,self.geometry.replace(declaration,replacement))
    def test_valid_symmetric_table_change(self):
        self.assertEqual(contract.verify_text(self.module,self.geometry.replace('0.2369268850561891','0.25'))['status'],'PASS')
if __name__=='__main__':unittest.main()
