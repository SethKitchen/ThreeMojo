"""Bind the finite ordered queue successor without rewriting historical pins."""
import hashlib
import json
from pathlib import Path
import tokenize

try:
    import source_contracts as source
    import sum2_guard_contracts as guard
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
    from tools.carla_lane_oracle import sum2_guard_contracts as guard

RECORD_SHA256 = 'e0aece69b861bc11a197cae17803e3273cdbd0cfed7ed0ca577ca6c3b4d217b1'
PREDECESSOR_SHA256 = 'b607c75982a15122dd8f3de743e48ec66e71f027cb5dd034b459dc46602c5c3e'


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def inventory(root):
    result = {}
    names = {'_run_lane_search', 'lane_refinement'}
    for path in sorted(root.rglob('*.mojo')):
        rel = path.relative_to(root)
        if rel.parts[0] in guard.NONPRODUCTION or any(p.startswith('.') for p in rel.parts):
            continue
        text = path.read_text()
        if not any(name in text for name in names):
            continue
        identifiers = [t.string for t in source.tokens(text) if t.type == tokenize.NAME]
        uses = [[i, name] for i, name in enumerate(identifiers) if name in names]
        if uses:
            result[rel.as_posix()] = {'routing': guard.declaration_routing(text), 'uses': uses}
    return result


def verify(root):
    root = Path(root)
    raw = (root / 'tools/carla_lane_oracle/lane-order-migration.json').read_bytes()
    require(hashlib.sha256(raw).hexdigest() == RECORD_SHA256, 'lane-order record changed')
    record = json.loads(raw)
    require(hashlib.sha256(record['before'].encode()).hexdigest() == record['before_sha256'] == PREDECESSOR_SHA256, 'lane-order predecessor changed')
    require(hashlib.sha256(record['after'].encode()).hexdigest() == record['after_sha256'], 'lane-order successor record changed')
    for rel, expected in record['immutable_predecessor_records'].items():
        require(hashlib.sha256((root / rel).read_bytes()).hexdigest() == expected, 'lane-order predecessor record changed: ' + rel)
    current = (root / record['module']).read_text()
    require(source.token_sha256(current) == source.token_sha256(record['after']), 'lane-order successor module changed')
    for rel, expected in record['premise_modules'].items():
        require(source.token_sha256((root / rel).read_text()) == source.token_sha256(expected), 'lane-order producer premise changed: ' + rel)
    require(inventory(root) == record['inventory'], 'lane-order production routing changed')
    run = guard.declaration(current, '_run_lane_search', ())
    insertions = [{'line_in_function': i + 1, 'operation': line.strip()} for i, line in enumerate(run.splitlines()) if any(word in line for word in ['pending.append(', 'closed.add(', 'terminal.append(', 'closed.recheck('])]
    # Line positions are documentary. Token-bound complete function controls semantics.
    require([x['operation'] for x in insertions] == [x['operation'] for x in record['insertions']], 'lane-order insertion scan changed')
    test = (root / 'tests/test_carla_lane_order_successor.mojo').read_text()
    for name, expected in record['references'].items():
        require(source.token_sha256(guard.declaration(test, name, ())) == source.token_sha256(expected), 'lane-order frozen reference changed: ' + name)
    return record


def predecessor_source(root):
    """Return the exact earlier module only after qualifying its reviewed successor."""
    return verify(root)['before']


if __name__ == '__main__':
    import sys
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    print('Lane finite-order migration: PASS')
