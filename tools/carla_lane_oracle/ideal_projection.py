# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow ideal stored-half correspondence; not a rounded/error graph proof.

The caller separately binds complete source text and its helper dependency
closure. The lexical adapter below is used only for the two fixed declarations
and does not claim to parse or certify arbitrary Mojo programs.
"""
import ast
import copy
import json

LEGACY_SHA256 = '270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733'
PROJECTED_SHA256 = 'f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06'
CALL_ARGUMENTS = ['step', 'rate', 'step', 'step', 'rate']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def normalized_node(node):
    if isinstance(node, ast.AST):
        fields = [(key, normalized_node(value)) for key, value in ast.iter_fields(node)
                  if value is not None and not (key == 'type_params' and not value)]
        if hasattr(node, '_mojo_type_parameters'):
            fields.append(('mojo_type_parameters', node._mojo_type_parameters))
        return (type(node).__name__, fields)
    if isinstance(node, list):
        return [normalized_node(value) for value in node]
    return node


def dump(node):
    return json.dumps(normalized_node(node), separators=(',', ':'), ensure_ascii=True)


def _ideal_source(text, name):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='ideal-function-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--ideal', str(source), '--name', name],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def function_tree(text, name):
    """Adapt the one already source-bound generic function for AST comparison.

    Qualifiers are retained by the source/routing/dependency checks, not this
    arithmetic projection. No transformation here authorizes their removal.
    """
    try:
        tree = ast.parse(_ideal_source(text, name))
    except SyntaxError as error:
        raise ValueError('unsupported ideal source syntax') from error
    require(len(tree.body) == 1 and isinstance(tree.body[0], ast.FunctionDef)
            and tree.body[0].name == name, 'ambiguous ideal function declaration')
    tree.body[0]._mojo_type_parameters = [
        ('NAME', 'derivatives'), ('OP', ':'), ('NAME', 'Bool')]
    return tree.body[0]


def half_constant():
    return ast.Call(func=ast.Attribute(value=ast.Name(id='Expression', ctx=ast.Load()),
                                     attr='constant', ctx=ast.Load()),
                    args=[ast.Constant(value=0.5)], keywords=[])


class ProjectHalf(ast.NodeTransformer):
    def __init__(self):
        self.arguments = []

    def visit_Call(self, node):
        node = self.generic_visit(node)
        if isinstance(node.func, ast.Name) and node.func.id == '_stored_half':
            require(len(node.args) == 1 and not node.keywords
                    and isinstance(node.args[0], ast.Name), 'unreviewed stored-half call shape')
            self.arguments.append(node.args[0].id)
            return ast.BinOp(left=node.args[0], op=ast.Mult(), right=half_constant())
        return node


def commute_legacy_text(text):
    """Swap each legacy half-rate product to rate times one half."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='commute-legacy-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--commute-legacy', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def direct_imports(text):
    """Return the top-level ``from`` imports in source order."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'source': text}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='direct-imports-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--imports', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def binding_shadow(text, name, allowed_module='', allow_definition=False):
    """Reject a binding that shadows one reviewed helper name."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'source': text,
        'name': name,
        'allowed': allowed_module,
        'allow_definition': allow_definition,
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='binding-shadow-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--binding', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def project_sum2_text(text):
    """Return the projected spiral source and its stored-half arguments."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='project-sum2-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--project-sum2', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def check_stored_half(text):
    """Require the stored-half helper to keep its reviewed result uses."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='stored-half-') as directory:
        path = Path(directory) / 'helper.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--stored-half', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify_helper_projection(helper_text):
    """The pinned helper starts with a half product and only revises error."""
    if not isinstance(helper_text, str):
        raise ValueError('ideal helper declaration or decorator changed')
    check_stored_half(helper_text)


def project_sum2(tree):
    """Erase only the reviewed error auxiliaries and inline immutable terms.

    This is an ideal-value/derivative projection, never a floating execution
    equivalence. Every admitted statement is exact, occurs once at its fixed
    nesting level, and all auxiliary uses must disappear. The caller compares
    the complete surviving function with the frozen historical ideal graph.
    """
    tree = copy.deepcopy(tree)
    guard = ast.parse("""if not _sum2_supported_environment():
    unknown = Expression(_Interval.whole(), _Interval.whole(), _Interval.whole(), inf[DType.float64]())
    return (unknown, unknown, unknown)
""").body[0]
    require(len(tree.body) == 19 and dump(tree.body[1]) == dump(guard),
            'fresh Sum2 environment refusal changed or moved')
    # Correspondence is conditional on this exact successful live check.
    # Its complete false branch returns only unknown fields/infinite error.
    tree.body.pop(1)
    declarations = [f'{axis}_{kind} = _Interval.point(0.0)'
                    for kind in ('magnitude', 'inherited') for axis in ('x', 'y')]
    # Production order is x/y magnitudes followed by x/y inherited errors.
    terms = {axis: ast.parse(
        f'_stored_half(step) * Expression.constant(weights[i]) * trig[{index}]',
        mode='eval').body for axis, index in (('x', 1), ('y', 0))}
    updates = [f'{axis}_magnitude = {axis}_magnitude + '
               f'_Interval.point(term_{axis}.rounded_value().magnitude())'
               for axis in ('x', 'y')]
    updates += [f'{axis}_inherited = {axis}_inherited + _Interval.point(term_{axis}.error)'
                for axis in ('x', 'y')]
    errors = [f'{axis}.error = _sum2_error_checked({axis}_magnitude.high, '
              f'{axis}_inherited.high, 5 * pieces)' for axis in ('x', 'y')]
    require(len(tree.body) == 18 and isinstance(tree.body[13], ast.While),
            'Sum2 complete ideal statement layout changed')
    outer = tree.body[13]
    require(len(outer.body) == 4 and isinstance(outer.body[2], ast.While),
            'Sum2 complete outer-loop layout changed')
    inner = outer.body[2]
    require(len(inner.body) == 12, 'Sum2 complete node-loop layout changed')
    require([dump(n) for n in tree.body[8:12]] ==
            [dump(ast.parse(s).body[0]) for s in declarations],
            'Sum2 declarations reordered or changed')
    require([dump(n) for n in tree.body[14:16]] ==
            [dump(ast.parse(s).body[0]) for s in errors],
            'Sum2 final error writes reordered or changed')
    require([dump(n) for n in inner.body[7:11]] ==
            [dump(ast.parse(s).body[0]) for s in updates],
            'Sum2 auxiliary updates reordered or changed')
    for offset, axis in enumerate(('x', 'y')):
        expected = ast.Assign(targets=[ast.Name(id='term_' + axis, ctx=ast.Store())],
                              value=terms[axis])
        require(dump(inner.body[3 + offset]) == dump(expected),
                'Sum2 immutable term definition moved or changed')
        require(dump(inner.body[5 + offset]) ==
                dump(ast.parse(f'{axis} = {axis} + term_{axis}').body[0]),
                'Sum2 ideal term accumulation moved or changed')
    erase = {dump(ast.parse(source).body[0]): (source, depth)
             for sources, depth in ((declarations, 0), (updates, 2), (errors, 0))
             for source in sources}
    for axis, value in terms.items():
        node = ast.Assign(targets=[ast.Name(id='term_' + axis, ctx=ast.Store())], value=value)
        erase[dump(node)] = ('term_' + axis, 2)
    seen = {source: 0 for source, depth in erase.values()}
    sums = {axis: 0 for axis in ('x', 'y')}

    def statements(body, depth):
        result = []
        for node in body:
            key = dump(node)
            if key in erase:
                name, wanted_depth = erase[key]
                require(depth == wanted_depth, 'Sum2 auxiliary statement moved: ' + name)
                seen[name] += 1
                require(seen[name] == 1, 'duplicate Sum2 auxiliary: ' + name)
                continue
            for axis in ('x', 'y'):
                expected = ast.parse(f'{axis} = {axis} + term_{axis}').body[0]
                if key == dump(expected):
                    require(depth == 2, 'Sum2 ideal accumulation moved')
                    sums[axis] += 1
                    node.value.right = copy.deepcopy(terms[axis])
            if isinstance(node, (ast.For, ast.While, ast.If)):
                node.body = statements(node.body, depth + 1)
                node.orelse = statements(node.orelse, depth + 1)
            result.append(node)
        return result

    tree.body = statements(tree.body, 0)
    require(all(count == 1 for count in seen.values()), 'missing or changed Sum2 auxiliary statement')
    require(sums == {'x': 1, 'y': 1}, 'missing or changed Sum2 ideal term use')
    forbidden = {'term_x', 'term_y', 'x_magnitude', 'y_magnitude', 'x_inherited', 'y_inherited'}
    require(not any(isinstance(node, ast.Name) and node.id in forbidden
                    for node in ast.walk(tree)), 'Sum2 auxiliary escapes ideal projection')
    return tree


def _gate(payload, kind):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='ideal-gate-') as directory:
        target = Path(directory) / 'payload'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_ideal_gate',
             '--bytes', str(target), '--kind', kind],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify_projection(legacy, current, helper_text):
    _gate(legacy.encode(), 'legacy')
    verify_helper_projection(helper_text)
    legacy_half = commute_legacy_text(legacy)
    left = ast.parse(legacy_half['source']).body[0]
    left._mojo_type_parameters = [
        ('NAME', 'derivatives'), ('OP', ':'), ('NAME', 'Bool')]
    require(left.name == '_spiral_expression', 'changed ideal generic declaration')
    require(legacy_half['count'] == 2,
            'expected exactly two historical rate-half commutations')
    # A caller inspecting a complete module supplies its unique actual AST
    # declaration, never a text slice that could select a docstring decoy.
    current_tree = (copy.deepcopy(current) if isinstance(current, ast.FunctionDef)
                    else function_tree(current, '_spiral_expression'))
    require(current_tree.name == '_spiral_expression' and
            getattr(current_tree, '_mojo_type_parameters', None) ==
            [('NAME', 'derivatives'), ('OP', ':'), ('NAME', 'Bool')],
            'changed ideal generic declaration')
    if isinstance(current, str):
        projected = project_sum2_text(current)
        right = ast.parse(projected['source']).body[0]
        right._mojo_type_parameters = current_tree._mojo_type_parameters
        arguments = projected['arguments']
    else:
        project = ProjectHalf()
        right = project.visit(project_sum2(current_tree))
        arguments = project.arguments
    require(arguments == CALL_ARGUMENTS, 'expected exactly five reviewed stored-half calls')
    require(dump(left) == dump(right), 'ideal expression differs beyond reviewed half projection')
    projected_bytes = dump(left).encode()
    _gate(projected_bytes, 'projected')
    projected = PROJECTED_SHA256
    return {'helper_projections': len(arguments), 'rate_half_commutations': legacy_half['count'],
            'projected_ast_sha256': projected, 'sum2_auxiliary_declarations': 4,
            'sum2_term_definitions': 2, 'sum2_auxiliary_updates': 4, 'sum2_error_writes': 2,
            'sum2_environment_guards': 1}


def _module_statements(text):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='module-statements-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--statements', str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _constant_literals(text, name, kind, size=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='constant-literals-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        command = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                   'carla_cleanup_gate', '--literals', str(source),
                   '--name', name, '--kind', kind]
        if size is not None:
            command.extend(['--size', str(size)])
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def pin_transition_rows(pins, transitions):
    """Return the current value at each coverage pin transition."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'pins': pins, 'transitions': transitions}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='pin-rows-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--pin-rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def decimal_words(literals):
    """Return the nearest binary64 word of each decimal literal."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(list(literals), separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='decimal-words-') as directory:
        path = Path(directory) / 'literals.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--decimal', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = 'spiral moment word: '
        if message.startswith(prefix):
            message = message[len(prefix):]
        raise ValueError(message)
    return [int(item, 16) for item in json.loads(result.stdout)]


def derive_rows(nodes, weights, cosine, sine):
    """Return the 64 derived moment rows for four stored word lists."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path

    def spell(words):
        return [f'0x{word:016X}' for word in words]

    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'nodes': spell(nodes), 'weights': spell(weights),
        'cosine': spell(cosine), 'sine': spell(sine),
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-rows-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = 'spiral moment derive: '
        if message.startswith(prefix):
            message = message[len(prefix):]
        raise ValueError(message)
    return json.loads(result.stdout)


def rounded_node_sums(nodes, weights):
    """Return the rounded `1 + node` words for the stored nodes and weights."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path

    def spell(words):
        return [f'0x{word:016X}' for word in words]

    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'nodes': spell(nodes), 'weights': spell(weights)},
        separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='node-sums-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--node-sums', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item, 16) for item in json.loads(result.stdout)]


def sha256_texts(texts):
    """Return the SHA-256 hex digest of each text."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(list(texts), separators=(',', ':'), ensure_ascii=True)
    with tempfile.TemporaryDirectory(prefix='sha-texts-') as directory:
        path = Path(directory) / 'texts.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--sha-texts', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def fraction_texts(words):
    """Return the exact fraction spelling of each binary64 word."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        [f'0x{word:016X}' for word in words], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='fraction-texts-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--fractions', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = 'spiral moment word: '
        if message.startswith(prefix):
            message = message[len(prefix):]
        raise ValueError(message)
    return json.loads(result.stdout)


def verify_moment_table(text, words):
    """Return the table words when they match the derived canonical source."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='moment-table-') as directory:
        folder = Path(directory)
        (folder / 'table.text').write_text(text)
        (folder / 'words.json').write_text(
            json.dumps(list(words), separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--verify-table', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item, 16) for item in json.loads(result.stdout)]


def moment_payload(words):
    """Return the big-endian payload and the canonical source digest."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='moment-payload-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(json.dumps(list(words), separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--moment-payload', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def declaration(text, name, owner=()):
    """Return one declaration selected by the cleanup gate."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='ideal-declaration-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_cleanup_gate', '--declaration', str(source),
                     '--name', name]
        for part in owner:
            arguments.extend(['--owner', part])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def token_sha256(text):
    """Return the kept-token SHA-256 of one source text."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='token-sha-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--token-sha', str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def array_literals(text, name, size):
    """Return the source spellings of one complete constant array."""
    return _constant_literals(text, name, 'array', size)


def scalar_literal(text, name):
    """Return the source spelling of one complete scalar constant."""
    values = _constant_literals(text, name, 'scalar')
    if len(values) != 1:
        raise ValueError('missing or ambiguous scalar: ' + name)
    return values[0]


def moment_source(words):
    """Return the canonical stored-moment table for one word list."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='moment-source-') as directory:
        payload = Path(directory) / 'words.json'
        payload.write_text(json.dumps(words, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--moment-source', str(payload)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def moment_words(text, count):
    """Return the `0x` words from one generated moment table."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='moment-table-') as directory:
        source = Path(directory) / 'table.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--table', str(source), '--count', str(count)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def strip_try_only(routing_json):
    """Remove the default-false try-only parameter from one routing document."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='strip-try-') as directory:
        payload = Path(directory) / 'routing.json'
        payload.write_text(routing_json)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--strip-try', str(payload)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def selected_block(text, begin, end):
    """Return one normalized source block between two markers."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='selected-block-') as directory:
        folder = Path(directory)
        (folder / 'source.text').write_text(text)
        (folder / 'begin.text').write_text(begin)
        (folder / 'end.text').write_text(end)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--block', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def normalized_block(text):
    """Drop comments and blank lines from one source block."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='normalized-block-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--normalize', str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def module_statements(text):
    """Keep the complete top-level routing, declarations and decorators.

    Ignore only the initial module docstring, comments, physical line breaks,
    and function bodies. Selected bodies and stored words have separate checks.
    All top-level names/statements and their ordering remain present. A whole
    logical statement, including any conditional/concatenation/suffix after
    an array literal, is returned before any constant-RHS masking occurs.
    """
    return [[(kind, word) for kind, word in statement]
            for statement in _module_statements(text)]


def module_routing(text, word_constants=()):
    # Called only after complete logical literal declarations and stored words
    # have been checked. Never use a prefix-only literal match before masking.
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='module-routing-') as directory:
        folder = Path(directory)
        source = folder / 'source.mojo'
        source.write_text(text)
        (folder / 'constants.json').write_text(json.dumps(sorted(word_constants)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--routing', str(source), '--constants', str(folder / 'constants.json')],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _top_level_source_starts(text):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='source-starts-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--starts', str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def top_level_source_starts(text):
    """Actual top-level declaration/import/decorator token starts.

    Unlike raw-text sentinels these cannot originate inside comments, string
    literals (including a module docstring), or indented function bodies.
    """
    return {(line, column) for line, column in _top_level_source_starts(text)}
