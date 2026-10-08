from pathlib import Path
import unittest
import envelope_budget_contracts as contract
ROOT=Path(__file__).resolve().parents[2]
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
