from pathlib import Path
import unittest
import re
import moment_finiteness_contracts as contract
ROOT=Path(__file__).resolve().parents[2]
class MomentFinitenessContracts(unittest.TestCase):
    def setUp(self):
        self.args=[(ROOT/p).read_text() for p in [contract.MODULE,contract.INTERVAL,'extensions/carla/geometry.mojo','extensions/carla/curve_trig.mojo']]
    def test_baseline(self):self.assertEqual(contract.verify(ROOT)['status'],'PASS')
    def test_benign_comments_and_inline_whitespace(self):
        args=[text+'\n# Benign source commentary\n' for text in self.args]
        args[0]=args[0].replace('pieces > 64','pieces  >  64')
        self.assertEqual(contract.verify_text(*args)['status'],'PASS')
    def test_count_work_and_producer_mutations(self):
        for old,new in [('pieces > 64','pieces > 1024'),('proof_terms += work','proof_terms += 0'),('range(1, 22)','range(1, 222)'),('materialize[_GL_WEIGHTS]()','materialize[_GL_NODES]()'),('var alpha2 =','weights[0] = 1e300\n            var alpha2 =')]:
            with self.subTest(change=new):
                self.assertIn(old,self.args[0]);args=self.args.copy();args[0]=args[0].replace(old,new)
                with self.assertRaises(ValueError):contract.verify_text(*args)
    def test_arithmetic_dependency_mutation(self):
        args=self.args.copy();args[1]=args[1].replace('return Self(_next_down(low), _next_up(high))','return Self(low, high)')
        with self.assertRaises(ValueError):contract.verify_text(*args)
    def test_constant_producer_mutations(self):
        for index,old,new in [(2,'0.5688888888888889','1e300'),(2,'comptime _GL_NODES:','var _GL_NODES:'),(3,'-0.16666666666666666','-2.0')]:
            args=self.args.copy();args[index]=args[index].replace(old,new)
            with self.assertRaises(ValueError):contract.verify_text(*args)
    def test_changed_bounded_constant(self):
        args=self.args.copy();args[3]=args[3].replace('-0.16666666666666666','-0.125')
        self.assertEqual(contract.verify_text(*args)['status'],'PASS')
    def test_all_producer_declarations_reject_decoys(self):
        for name,size,index in [('_GL_NODES',5,2),('_GL_WEIGHTS',5,2),('_COS_COEFFICIENTS',11,3),('_SIN_COEFFICIENTS',11,3)]:
            pattern=r'comptime '+name+r': Array\[Float64, '+str(size)+r'\] = \[[^]]+\]'
            match=re.search(pattern,self.args[index])
            self.assertIsNotNone(match)
            declaration=match.group(0)
            decoys=[('string','"""'+declaration+'"""'),('conditional',declaration+' if False else [0.0]'),('suffix',declaration+' + [0.0]')]
            for label,replacement in decoys:
                with self.subTest(table=name,decoy=label):
                    args=self.args.copy();args[index]=args[index].replace(declaration,replacement,1)
                    with self.assertRaises(ValueError):contract.verify_text(*args)
if __name__=='__main__':unittest.main()
