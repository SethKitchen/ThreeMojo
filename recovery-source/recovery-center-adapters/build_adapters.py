from pathlib import Path
import ast
import difflib
import hashlib
import json
import os

BASE = Path('/workspace/scratch/c2bcdb1ca387/pr711-current-integration/center-successor-proposal-v17')
OUT = BASE.parent / 'source-successor-center-adapter-repair-v18'
PREFIX = Path('tools/carla_lane_oracle')
NAMES = ('optional_runtime_contracts.py', 'rounded_line_selector_contracts.py', 'rounded_line_singleton_contracts.py')

def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.new')
    temporary.write_text(text)
    os.replace(temporary, path)

original = {name: (BASE/PREFIX/name).read_text() for name in NAMES}
updated = dict(original)
text = original[NAMES[0]]
old = "    import source_contracts\n"
assert text.count(old) == 1
text = text.replace(old, old + '    import full_audit_cleanup_contracts as full_audit\n', 1)
old = '    from tools.carla_lane_oracle import sum2_guard_contracts as guard, source_contracts\n'
assert text.count(old) == 1
text = text.replace(old, old + '    from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit\n', 1)
old = "def body(root, module, name):\n    text = (root / ('extensions/carla/' + module + '.mojo')).read_text()\n    source = guard.declaration(text, name)\n"
new = "def body(root, module, name):\n    text = (root / ('extensions/carla/' + module + '.mojo')).read_text()\n    return body_from_source(text, name)\n\n\ndef body_from_source(text, name):\n    \"\"\"Parse a supplied semantic fixture; this grants no source admission.\"\"\"\n    source = guard.declaration(text, name)\n"
assert text.count(old) == 1
text = text.replace(old, new, 1)
start = text.index('    verify_fresh_producer(run)\n', text.index('def verify_semantics(root):'))
end = text.index('    # The standalone helper remains reviewed', start)
first_block = text[start:end]
text = text[:start] + text[end:]
start = text.index('    sequence(run, GROUPED_ADMISSION,', text.index('def verify_semantics(root):'))
end = text.index("    fee = body(root, 'map', '_query_node_step_cost')", start)
second_block = text[start:end]
text = text[:start] + text[end:]
text = text.replace("    run = body(root, 'lane_refinement', '_run_lane_search')\n", '', 1)
new_helper = '''def verify_search_semantics(run):
    """Check the retained pre-center run predicates, without admitting a root.

    Production callers must first qualify the complete live successor and
    reconstruct its exact center predecessor. Tests may give this pure checker
    separately mutated historical AST fixtures; those fixtures are never an
    alternative live-source endpoint.
    """
''' + first_block + second_block + '\n\n'
text = text.replace('def verify_semantics(root):\n', new_helper + 'def verify_semantics(root):\n', 1)
old = '    raw_inverse.verify_premises(root)\n'
new = '''    raw_inverse.verify_premises(root)
    # Preserve specific live producer, absence, integer-fee and raw-inverse
    # diagnostics before the transitive source gate. Current lane faults use
    # the complete-successor diagnostic; historical AST predicates keep their
    # old labels. Multiply invalid inputs can report a different first error.
    # The center helper/context/caller are checked on actual live sources by
    # the complete gate before any historical run body is made available.
    record = full_audit.verify(root)
    item = record['sources']['extensions/carla/lane_refinement.mojo']
    previous = full_audit.reverse_center_exact(item['after_source'], item)
    verify_search_semantics(body_from_source(previous, '_run_lane_search'))
'''
assert text.count(old) == 1
text = text.replace(old, new, 1)
updated[NAMES[0]] = text

for name, variable in ((NAMES[1], 'name'), (NAMES[2], 'path')):
    text = original[name]
    old = ("        actual=(root/name).read_text().split('\\ndef ',1)[0].split('\\n@',1)[0].split('\\nstruct ',1)[0]\n"
           if variable == 'name' else
           "        actual = (root/path).read_text().split('\\ndef ',1)[0].split('\\n@',1)[0].split('\\nstruct ',1)[0]\n")
    new = f'''        text = (root/{variable}).read_text()
        if {variable} == 'extensions/carla/lane_refinement.mojo':
            # The added Variant import belongs to the complete, reviewed
            # center extraction. Never erase an import from an unverified view.
            text = full_audit.reviewed_text(root, {variable}, text)
        actual = text.split('\\ndef ',1)[0].split('\\n@',1)[0].split('\\nstruct ',1)[0]
'''
    assert text.count(old) == 1, name
    text = text.replace(old, new, 1)
    old = '            # Only this complete live consumer can request its fixed earlier\n            # declaration. All selector/context/import/reference reads stay live.\n'
    new = '            # Only this complete live consumer can request its fixed earlier\n            # declaration. Selector/context/reference reads remain live; the\n            # lane import scope above consumes the same fully reviewed edge.\n'
    assert text.count(old) == 1, name
    updated[name] = text.replace(old, new, 1)

patch = []
seal = {'status': 'UNQUALIFIED_STATIC_PROPOSAL', 'base': str(BASE), 'changed_paths': [], 'files': {},
        'validation': 'stdlib AST construction only; no repository imports, checks, tests or native execution'}
for name in NAMES:
    path = PREFIX/name
    ast.parse(updated[name])
    atomic(OUT/'proposal'/path, updated[name])
    patch.extend(difflib.unified_diff(original[name].splitlines(True), updated[name].splitlines(True),
                                    fromfile='a/'+str(path), tofile='b/'+str(path)))
    seal['changed_paths'].append(str(path))
    seal['files'][str(path)] = {'before_sha256': hashlib.sha256(original[name].encode()).hexdigest(),
                               'after_sha256': hashlib.sha256(updated[name].encode()).hexdigest()}
# Exact statement-AST retention: each old lane predicate is moved intact,
# and the remaining old predicate subsequence is retained in original order.
old_tree, new_tree = ast.parse(original[NAMES[0]]), ast.parse(updated[NAMES[0]])
old_method = next(n for n in old_tree.body if isinstance(n, ast.FunctionDef) and n.name == 'verify_semantics')
new_method = next(n for n in new_tree.body if isinstance(n, ast.FunctionDef) and n.name == 'verify_semantics')
run_method = next(n for n in new_tree.body if isinstance(n, ast.FunctionDef) and n.name == 'verify_search_semantics')
old_lane = ast.parse('def predicates(run):\n'+first_block+second_block).body[0].body
assert [ast.dump(n) for n in run_method.body[1:]] == [ast.dump(n) for n in old_lane]
lane_dump = [ast.dump(n) for n in old_lane]
expected = []
for n in old_method.body:
    if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name) and n.targets[0].id == 'run':
        continue
    if lane_dump and ast.dump(n) == lane_dump[0]:
        lane_dump.pop(0)
    else:
        expected.append(ast.dump(n))
assert not lane_dump
actual = [ast.dump(n) for n in new_method.body]
for n in expected:
    assert n in actual
    actual = actual[actual.index(n)+1:]
seal['predicate_retention'] = {'old_verify_semantics_top_level_statements': len(old_method.body),
                               'moved_lane_statements': len(old_lane),
                               'retained_nonlane_statements': len(expected),
                               'removed_statement': "run = body(root, 'lane_refinement', '_run_lane_search')",
                               'lane_ast_equal': True, 'nonlane_subsequence_equal': True,
                               'census_call_retained': True}
old_functions = {n.name: n for n in old_tree.body if isinstance(n, ast.FunctionDef)}
new_functions = {n.name: n for n in new_tree.body if isinstance(n, ast.FunctionDef)}
assert set(old_functions) <= set(new_functions)
unchanged = [name for name in old_functions if ast.dump(old_functions[name]) == ast.dump(new_functions[name])]
seal['public_entrypoints'] = {'removed': [], 'added': ['body_from_source', 'verify_search_semantics'],
                             'changed': ['body', 'verify_semantics'], 'unchanged_function_asts': unchanged}
atomic(OUT/'ADAPTERS.patch', ''.join(patch))
atomic(OUT/'ADAPTERS-SEAL.json', json.dumps(seal, indent=2)+'\n')
print(json.dumps(seal, indent=2))
