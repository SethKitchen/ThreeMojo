# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow ideal stored-half correspondence; not a rounded/error graph proof.

The caller separately binds complete source text and its helper dependency
closure. The lexical adapter below is used only for the two fixed declarations
and does not claim to parse or certify arbitrary Mojo programs.
"""
import ast
import copy
import hashlib
import io
import json
import tokenize

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


def function_tree(text, name):
    """Adapt the one already source-bound generic function for AST comparison.

    Qualifiers are retained by the source/routing/dependency checks, not this
    arithmetic projection. No transformation here authorizes their removal.
    """
    try:
        tokens = [(t.type, t.string) for t in
                  tokenize.generate_tokens(io.StringIO(text).readline)
                  if not (t.type == tokenize.NAME and t.string in ('var', 'comptime'))]
        head = [(kind, word) for kind, word in tokens
                if kind not in (tokenize.COMMENT, tokenize.NL)]
        require(head[:3] == [(tokenize.NAME, 'def'), (tokenize.NAME, name),
                              (tokenize.OP, '[')], 'unsupported ideal function declaration')
        begin = next(i for i, token in enumerate(tokens) if token == (tokenize.OP, '['))
        end, depth = begin + 1, 1
        while end < len(tokens) and depth:
            depth += (tokens[end][1] == '[') - (tokens[end][1] == ']')
            end += 1
        require(depth == 0, 'unclosed ideal generic declaration')
        parameters = [(tokenize.tok_name[k], v) for k, v in tokens[begin+1:end-1]
                      if k not in (tokenize.NL, tokenize.COMMENT)]
        if parameters and parameters[-1][1] == ',':
            parameters.pop()
        require(parameters == [('NAME', 'derivatives'), ('OP', ':'), ('NAME', 'Bool')],
                'changed ideal generic declaration')
        del tokens[begin:end]
        tree = ast.parse(tokenize.untokenize(tokens))
    except (SyntaxError, tokenize.TokenError, IndentationError, StopIteration) as error:
        raise ValueError('unsupported ideal source syntax') from error
    require(len(tree.body) == 1 and isinstance(tree.body[0], ast.FunctionDef)
            and tree.body[0].name == name, 'ambiguous ideal function declaration')
    tree.body[0]._mojo_type_parameters = parameters
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


class CommuteLegacyRateHalf(ast.NodeTransformer):
    def __init__(self):
        self.count = 0

    def visit_BinOp(self, node):
        node = self.generic_visit(node)
        if (isinstance(node.op, ast.Mult) and dump(node.left) == dump(half_constant())
                and isinstance(node.right, ast.Name) and node.right.id == 'rate'):
            self.count += 1
            node.left, node.right = node.right, node.left
        return node


def verify_helper_projection(helper_text):
    """The pinned helper starts with a half product and only revises error."""
    helper = (copy.deepcopy(helper_text) if isinstance(helper_text, ast.FunctionDef)
              else function_tree(helper_text, '_stored_half'))
    signature = copy.deepcopy(helper)
    signature.body = [ast.Pass()]
    expected_signature = function_tree(
        'def _stored_half[derivatives: Bool](value: _JetExpression[derivatives]) '
        '-> _JetExpression[derivatives]:\n    pass\n', '_stored_half')
    require(dump(signature) == dump(expected_signature),
            'ideal helper declaration or decorator changed')
    initial = helper.body[0]
    expected = ast.parse('result = value * _JetExpression[derivatives].constant(0.5)').body[0]
    require(dump(initial) == dump(expected), 'ideal helper initial expression changed')
    allowed_result_names = {id(initial.targets[0])}
    for node in ast.walk(helper):
        if isinstance(node, ast.Return):
            require(isinstance(node.value, ast.Name) and node.value.id == 'result',
                    'ideal helper return changed')
            allowed_result_names.add(id(node.value))
        if isinstance(node, (ast.Assign, ast.AugAssign, ast.AnnAssign)) and node is not initial:
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                require(not (isinstance(target, ast.Name) and target.id == 'result'),
                        'ideal helper result rebound')
                if (isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name)
                        and target.value.id == 'result'):
                    require(target.attr == 'error', 'non-error result field changed')
                    allowed_result_names.add(id(target.value))
        if isinstance(node, ast.Call):
            require(not any(isinstance(arg, ast.Name) and arg.id == 'result'
                            for arg in node.args), 'ideal helper result escapes')
    for node in ast.walk(helper):
        if isinstance(node, ast.Name) and node.id == 'result':
            require(id(node) in allowed_result_names, 'unapproved ideal helper result use')


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


def verify_projection(legacy, current, helper_text):
    require(hashlib.sha256(legacy.encode()).hexdigest() == LEGACY_SHA256,
            'historical ideal source changed')
    verify_helper_projection(helper_text)
    left = function_tree(legacy, '_spiral_expression')
    # A caller inspecting a complete module supplies its unique actual AST
    # declaration, never a text slice that could select a docstring decoy.
    current_tree = (copy.deepcopy(current) if isinstance(current, ast.FunctionDef)
                    else function_tree(current, '_spiral_expression'))
    require(current_tree.name == '_spiral_expression' and
            getattr(current_tree, '_mojo_type_parameters', None) ==
            [('NAME', 'derivatives'), ('OP', ':'), ('NAME', 'Bool')],
            'changed ideal generic declaration')
    right = project_sum2(current_tree)
    commute, project = CommuteLegacyRateHalf(), ProjectHalf()
    left, right = commute.visit(left), project.visit(right)
    require(commute.count == 2, 'expected exactly two historical rate-half commutations')
    require(project.arguments == CALL_ARGUMENTS, 'expected exactly five reviewed stored-half calls')
    require(dump(left) == dump(right), 'ideal expression differs beyond reviewed half projection')
    projected = hashlib.sha256(dump(left).encode()).hexdigest()
    require(projected == PROJECTED_SHA256, 'projected ideal polynomial graph changed')
    return {'helper_projections': len(project.arguments), 'rate_half_commutations': commute.count,
            'projected_ast_sha256': projected, 'sum2_auxiliary_declarations': 4,
            'sum2_term_definitions': 2, 'sum2_auxiliary_updates': 4, 'sum2_error_writes': 2,
            'sum2_environment_guards': 1}


def module_statements(text):
    """Keep the complete top-level routing, declarations and decorators.

    Ignore only the initial module docstring, comments, physical line breaks,
    and function bodies. Selected bodies and stored words have separate checks.
    All top-level names/statements and their ordering remain present. A whole
    logical statement, including any conditional/concatenation/suffix after
    an array literal, is returned before any constant-RHS masking occurs.
    """
    statements, statement, depth = [], [], 0
    try:
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.INDENT:
                depth += 1
            elif token.type == tokenize.DEDENT:
                depth -= 1
            elif token.type == tokenize.NEWLINE:
                if statement:
                    if not statements and len(statement) == 1 and statement[0][0] == 'STRING':
                        pass
                    else:
                        statements.append(statement)
                    statement = []
            elif depth == 0 and token.type not in (tokenize.COMMENT, tokenize.NL,
                                                   tokenize.ENDMARKER, tokenize.ENCODING):
                statement.append((tokenize.tok_name[token.type], token.string))
    except (tokenize.TokenError, IndentationError, ValueError) as error:
        raise ValueError('unsupported top-level source routing') from error
    require(not statement and depth == 0, 'incomplete top-level source routing')
    return statements


def module_routing(text, word_constants=()):
    # Called only after complete logical literal declarations and stored words
    # have been checked. Never use a prefix-only literal match before masking.
    statements = module_statements(text)
    for index, statement in enumerate(statements):
        if (len(statement) > 3 and statement[0] == ('NAME', 'comptime')
                and statement[1][1] in word_constants):
            equals = statement.index(('OP', '='))
            statements[index] = statement[:equals+1] + [('STORED_WORDS', statement[1][1])]
    return json.dumps(statements, separators=(',', ':'), ensure_ascii=True)


def top_level_source_starts(text):
    """Actual top-level declaration/import/decorator token starts.

    Unlike raw-text sentinels these cannot originate inside comments, string
    literals (including a module docstring), or indented function bodies.
    """
    starts, depth, fresh = set(), 0, True
    try:
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.INDENT:
                depth += 1
            elif token.type == tokenize.DEDENT:
                depth -= 1
            elif token.type == tokenize.NEWLINE:
                fresh = True
            elif token.type not in (tokenize.COMMENT, tokenize.NL,
                                    tokenize.ENDMARKER, tokenize.ENCODING):
                if depth == 0 and fresh and token.string in ('def', 'from', '@'):
                    starts.add(token.start)
                fresh = False
    except (tokenize.TokenError, IndentationError) as error:
        raise ValueError('unsupported source-boundary tokens') from error
    return starts
