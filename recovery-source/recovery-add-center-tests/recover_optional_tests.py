"""Reconstruct optional tests from context without importing any repository.

Usage: python -B recover_optional_tests.py PATH_TO_RESTORED_V17_TEST
Only writes this recovery directory. Until its expected SHA matches, output is
explicitly reconstructed/unqualified, not claimed as recovered exact bytes.
"""
import ast
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import sys

base = Path(__file__).resolve().parent
expected_before = '249ff8921939d0da2b9a9a6032f77c632eaca8d9658b8df31914bd65add0b543'
expected_after = '123b14e2e96c853c77ed82c3e1ada96940e36356b9530414b5b0a5d118e53292'
raw = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(raw).hexdigest() != expected_before:
    raise RuntimeError('Restore the exact v17 optional baseline before reconstruction')
old_text = raw.decode()
new_text = old_text
fragment = (base/'optional-replacement-methods.txt').read_text()
fragment_tree = ast.parse('class Recovered:\n' + fragment)
fragment_lines = fragment.splitlines(keepends=True)
replacements = {}
for node in fragment_tree.body[0].body:
    start = min([node.lineno] + [item.lineno for item in node.decorator_list]) - 2
    replacements[node.name] = ''.join(fragment_lines[start:node.end_lineno-1])
old_tree = ast.parse(old_text)
old_class = next(n for n in old_tree.body if isinstance(n, ast.ClassDef) and n.name=='OptionalRuntimeContracts')
lines = new_text.splitlines(keepends=True)
changes = []
for node in old_class.body:
    if isinstance(node, ast.FunctionDef) and node.name in replacements:
        start = min([node.lineno] + [item.lineno for item in node.decorator_list]) - 1
        changes.append((start, node.end_lineno, replacements[node.name]))
if len(changes)!=5:
    raise RuntimeError('Expected exactly five existing method replacements')
for start,end,text in sorted(changes,reverse=True):
    lines[start:end] = [text]
new_text=''.join(lines)
anchor='    def exercise(self, case):\n'
if new_text.count(anchor)!=1:
    raise RuntimeError('Unique exercise anchor missing')
new_text=new_text.replace(anchor,(base/'optional-added-helper.txt').read_text()+'\n'+anchor)
anchor='class OptionalRuntimeContracts(unittest.TestCase):\n'
if new_text.count(anchor)!=1:
    raise RuntimeError('Unique class anchor missing')
new_text=new_text.replace(anchor,(base/'optional-preclass-additions.txt').read_text()+'\n\n\n'+anchor)
anchor='\n\nfor case in CASES:\n'
if new_text.count(anchor)!=1:
    raise RuntimeError('Unique dynamic-cases anchor missing')
new_text=new_text.replace(anchor,'\n\n'+(base/'optional-added-tests.txt').read_text()+'\n'+anchor)
new_tree=ast.parse(new_text)
new_class=next(n for n in new_tree.body if isinstance(n,ast.ClassDef) and n.name=='OptionalRuntimeContracts')
old_methods={n.name:n for n in old_class.body if isinstance(n,ast.FunctionDef)}
new_methods={n.name:n for n in new_class.body if isinstance(n,ast.FunctionDef)}
def assertions(node):
    return Counter(ast.dump(n,include_attributes=False) for n in ast.walk(node)
                   if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute)
                   and isinstance(n.func.value,ast.Name) and n.func.value.id=='self'
                   and n.func.attr.startswith('assert'))
if not set(old_methods)<=set(new_methods):
    raise RuntimeError('Old method missing')
for name,node in old_methods.items():
    if assertions(node)-assertions(new_methods[name]):
        raise RuntimeError('Original assertion missing in '+name)
actual=hashlib.sha256(new_text.encode()).hexdigest()
name='test_optional_runtime_contracts.py' if actual==expected_after else 'test_optional_runtime_contracts.RECONSTRUCTED.py'
target=base/name
temporary=target.with_suffix('.tmp');temporary.write_text(new_text);os.replace(temporary,target)
report={'path':str(target),'sha256':actual,'expected_sha256':expected_after,
        'byte_recovered':actual==expected_after,'qualified':False,
        'validation':'AST parse and original assertion retention only; no repository imports or tests',
        'old_test_methods':sum(name.startswith('test_') for name in old_methods),
        'new_test_methods':sum(name.startswith('test_') for name in new_methods)}
target=base/'OPTIONAL-ASSEMBLY-STATUS.json';temporary=target.with_suffix('.tmp')
temporary.write_text(json.dumps(report,indent=2)+'\n');os.replace(temporary,target)
print(json.dumps(report,indent=2))
