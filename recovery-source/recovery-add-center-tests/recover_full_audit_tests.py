"""Reconstruct v18 pre-final-review test text without importing any repository.

Usage: python -B recover_full_audit_tests.py PATH_TO_RESTORED_V17_TEST
Output is confined to this recovery directory. No candidate is created.
"""
import ast
import hashlib
import json
import os
from pathlib import Path
import sys

base = Path(__file__).resolve().parent
expected_before = '494239ab0d2643a8a607809c98b97e3ac191145ace7c2611791d54231f7545a2'
expected_after = '1626247dc36e6607d6a53100f0ab9ffd36ad585ecb2f09b1118e86db29bbcec2'
raw = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(raw).hexdigest() != expected_before:
    raise RuntimeError('Restore the exact v17 baseline before byte recovery')
text = raw.decode()
anchor = '    def test_unknown_projection_requests_do_not_authorize_an_edge(self):\n'
if text.count(anchor) != 1:
    raise RuntimeError('Unique insertion anchor missing')
new = text.replace(anchor, (base/'full-audit-additions.txt').read_text() + anchor)
ast.parse(new)
actual = hashlib.sha256(new.encode()).hexdigest()
if actual != expected_after:
    raise RuntimeError('Reconstruction does not match old proposal: ' + actual)
target = base/'test_full_audit_cleanup_contracts.py'
temporary = target.with_suffix('.tmp')
temporary.write_text(new)
os.replace(temporary, target)
print(json.dumps({'path': str(target), 'sha256': actual,
                  'byte_recovered': True, 'qualified': False,
                  'remaining': 'Variant import removal mutation and final independent review'}, indent=2))
