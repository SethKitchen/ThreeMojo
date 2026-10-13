from pathlib import Path
import unittest
import envelope_budget_contracts as contract
ROOT=Path(__file__).resolve().parents[2]


# This module's fixed byte/line/body assertions describe the historical main
# graph. The #333 current graph has separate physical admission/mutation tests.
_CURRENT_SOURCE_ROOT = ROOT


def setUpModule():
    global ROOT
    import _full_audit_test_fixtures as historical_fixtures
    owner = type('HistoricalModuleFixture', (), {
        'addCleanup': staticmethod(unittest.addModuleCleanup)})()
    ROOT = historical_fixtures.copy_historical_boundary_root(owner, _CURRENT_SOURCE_ROOT)
    unittest.addModuleCleanup(globals().__setitem__, 'ROOT', _CURRENT_SOURCE_ROOT)
class EnvelopeBudgetContracts(unittest.TestCase):
    def setUp(self):self.text=(ROOT/contract.MODULE).read_text()
    def test_baseline(self):self.assertEqual(contract.verify(ROOT)['status'],'PASS')
    def test_benign_comment_and_spacing(self):
        text=(self.text+'\n# Benign source commentary\n').replace('optional_work = 1024','optional_work  =  1024')
        self.assertEqual(contract.verify_text(text)['status'],'PASS')
    def test_remove_initial_guard(self):
        with self.assertRaises(ValueError):contract.verify_text(self.text.replace('terms < 0 or terms > max_terms or 1024 > max_terms - terms','1024 > max_terms - terms'))
    def test_mutating_counter_and_reference_pass(self):
        for injection in ['terms = -1','_mutate_counter(terms)','max_terms = 0']:
            with self.subTest(injection=injection):
                text=self.text.replace('    var optional_work = 1024 * branches','    '+injection+'\n    var optional_work = 1024 * branches')
                with self.assertRaises(ValueError):contract.verify_text(text)
    def test_move_debit_before_admission(self):
        text=self.text.replace('    terms += optional_work\n','').replace('    if optional_work > max_terms - terms:','    terms += optional_work\n    if optional_work > max_terms - terms:')
        with self.assertRaises(ValueError):contract.verify_text(text)
    def test_remove_second_capacity_check(self):
        with self.assertRaises(ValueError):contract.verify_text(self.text.replace('optional_work > max_terms - terms','False'))
if __name__=='__main__':unittest.main()
