# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Test-only exact checker predecessor and current physical line map.

The owner predecessor is deliberately the fixed 5e91dad source (f62dbe69...),
which the retained invariant controls already authenticate. The complete exact
inverse spans the later PR776 typed-witness repair and PR780 composition. It
never replaces a production observation or grants a source admission.
"""
import hashlib
import json

EDGES = {'coverage_loop_proofs.py': {'after_sha256': '0d082e17f3401a607c056e24aae23e986fbe2a0dcf48cb6f79fe6a62782c4189',
                             'before_sha256': '21e3a9637a69c6abbf27e9c8dd193a1addf7ed8537dd8f2734c35ff1a468304d',
                             'edits': ((283,
                                        286,
                                        ("        if words[0] in {'def', "
                                         "'struct', 'trait'} or words[:2] == "
                                         "['async', 'def']:\n",
                                         "            kind = 'def' if words[0] "
                                         "== 'async' else words[0]\n"),
                                        ('        asynchronous = words[0] in '
                                         "{'async', '__async'} and words[1:2] "
                                         "== ['def']\n",
                                         "        if words[0] in {'def', "
                                         "'struct', 'trait'} or "
                                         'asynchronous:\n',
                                         "            kind = 'def' if "
                                         'asynchronous else words[0]\n')),
                                       (287,
                                        288,
                                        ('            name_position = 2 if '
                                         "words[0] == 'async' else 1\n",),
                                        ('            name_position = 2 if '
                                         'asynchronous else 1\n',)),
                                       (375,
                                        407,
                                        (),
                                        ('def _typed_endpoint(name, raw):\n',
                                         '    """Return the exact typed '
                                         'endpoint of a PR780 successor, else '
                                         '`raw`.\n',
                                         '\n',
                                         '    The PR780 successor data is '
                                         'fixed and sealed. A successor is '
                                         'mapped only\n',
                                         '    when its exact inverse is a '
                                         'complete typed endpoint, so a '
                                         'successor cannot\n',
                                         '    make an unrelated source '
                                         'current.\n',
                                         '\n',
                                         '    Args:\n',
                                         '        name: Repository-relative '
                                         'path of the source.\n',
                                         '        raw: Physical source bytes, '
                                         'or the same text decoded as UTF-8.\n',
                                         '\n',
                                         '    Returns:\n',
                                         '        The typed endpoint in the '
                                         'type of `raw`, or `raw` when `name` '
                                         'has no\n',
                                         '        reviewed successor edge or '
                                         '`raw` is not the successor '
                                         'endpoint.\n',
                                         '\n',
                                         '    Raises:\n',
                                         '        ValueError: The successor '
                                         'data or its inverse changed.\n',
                                         '    """\n',
                                         '    from carla_lane_oracle import '
                                         'full_audit_cleanup_contracts as '
                                         'cleanup\n',
                                         '    from carla_lane_oracle import '
                                         'typed_boundary_contracts as typed\n',
                                         '    successor = '
                                         'cleanup.pr780_successor\n',
                                         '    edge = '
                                         'successor.reviewed_edge(name)\n',
                                         "    encoded = raw.encode('utf-8') if "
                                         'type(raw) is str else raw\n',
                                         '    if (edge is None or name not in '
                                         'typed.EDGES\n',
                                         '            or sha256(encoded) != '
                                         "edge['after_sha256']):\n",
                                         '        return raw\n',
                                         '    prior = '
                                         'successor.predecessor_bytes(name, '
                                         'encoded)\n',
                                         '    if not typed.is_current(name, '
                                         'prior):\n',
                                         '        return raw\n',
                                         "    return prior.decode('utf-8') if "
                                         'type(raw) is str else prior\n',
                                         '\n',
                                         '\n')),
                                       (418,
                                        420,
                                        ('    if item is None or not '
                                         'typed.is_current(name, current):\n',),
                                        ('    endpoint = _typed_endpoint(name, '
                                         'current)\n',
                                         '    if item is None or not '
                                         'typed.is_current(name, '
                                         'endpoint):\n')),
                                       (421,
                                        422,
                                        ('    previous = '
                                         'typed.historical_source(name, '
                                         'current)\n',),
                                        ('    previous = '
                                         'typed.historical_source(name, '
                                         'endpoint)\n',)),
                                       (426,
                                        427,
                                        ('    after, after_first, after_last = '
                                         'seed._function_span(current, '
                                         'function, owner)\n',),
                                        ('    after, after_first, after_last = '
                                         'seed._function_span(endpoint, '
                                         'function, owner)\n',)),
                                       (446,
                                        457,
                                        (),
                                        ('    if endpoint is not current:\n',
                                         '        # A reviewed successor keeps '
                                         'the complete ordered loop inventory '
                                         'of the\n',
                                         '        # owner. Its row moves only '
                                         'with the lines the successor '
                                         'shifts.\n',
                                         '        final, final_first, '
                                         'final_last = '
                                         'seed._function_span(current, '
                                         'function, owner)\n',
                                         '        final_statements = '
                                         '_statements(final)\n',
                                         '        if final_statements is '
                                         'None:\n',
                                         '            return None\n',
                                         '        final_rows = '
                                         'for_rows(final_statements, '
                                         'final_first)\n',
                                         '        if [words for _, words in '
                                         'final_rows] != [words for _, words '
                                         'in new_rows]:\n',
                                         '            return None\n',
                                         '        new_rows = final_rows\n')),
                                       (494,
                                        495,
                                        ('            '
                                         "'1e95ebc085e03a44e4daaef20a94b724dedc4240a2099227e82be54d32b045f6',\n",),
                                        ('            '
                                         "'2d9d5401b3dabf53c1c19f0a8098009275e19edb978f5ae369596fe7ac6557a0',\n",)),
                                       (496,
                                        497,
                                        ('        (154, '
                                         "'reviewed-nonempty-iterator', 1, "
                                         "None, 'number.as_bytes()',\n",),
                                        ('        (150, '
                                         "'reviewed-nonempty-iterator', 1, "
                                         "None, 'number.as_bytes()',\n",)),
                                       (546,
                                        547,
                                        ('        '
                                         "'058c0e6fbfce95ee97c79247622185de968c8de5e0ad23240d667da13776404f',\n",),
                                        ('        '
                                         "'81d104e6b65fe1539bf9c244330ae53b6d337ad081529cb0c5f7bcde27887db5',\n",)),
                                       (1222,
                                        1244,
                                        (),
                                        ('# PR780, the Mojo 1.2 port and PR791 '
                                         'change thirteen imported helpers, '
                                         'but\n',
                                         '# leave density, groom, their tests, '
                                         'and every theorem coordinate '
                                         'unchanged.\n',
                                         '# Retain the complete PR760 closure '
                                         'above and admit only this exact '
                                         'local\n',
                                         '# successor cohort. The broader '
                                         'CARLA successor is not a premise for '
                                         'these\n',
                                         '# four local domination theorems.\n',
                                         'DENSITY780_DEPENDENCY_SHA256 = {\n',
                                         "    'core/extent.mojo': "
                                         "'90490706baa17456a3ec99374c2a00f72768a0178b4e56436571ab4ca673f068',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/head/assembly.mojo': "
                                         "'813a09e4b30a5a9682e606cdabb2e22188866f4153318a18f9df62f091c0435e',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/look.mojo': "
                                         "'662665a1ea3c291b45030fcf90d732b2a7900f0c1a591e4d94d854201e8caa48',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/surface_nets.mojo': "
                                         "'98b354cea54d1d1dc33ee23f02b0e89f80466ddb2fc06a6415ea224a3a93aeee',\n",
                                         '    '
                                         "'geometries/attribute_utils.mojo': "
                                         "'91d45ff588571ab0bbda20331d1f60a0b55e124985a76f8cad97d682bdca523e',\n",
                                         "    'geometries/surface.mojo': "
                                         "'deeba40777e10da75651f07b8d8f86abb609d4c916b098f1dc28be228f20d3cd',\n",
                                         "    'lights/shadow.mojo': "
                                         "'649970324f8a80cd0ba959f3278d635b12b9886a5ecb09290620b5b61b3c1d20',\n",
                                         "    'loaders/bytes.mojo': "
                                         "'139ca1cb876bdf7b0a7c258d1d3a40375d8f3b73c75af160e26e07e7c9ba062a',\n",
                                         "    'math/matrix4.mojo': "
                                         "'1e72ab51f9dbcee3af4c2bfe9da93946616736bf02f4b20e2160ee7b69b448fa',\n",
                                         "    'math/square_matrix.mojo': "
                                         "'f1b2e67489949b53594b5f06604a0227260fd961df2fdebe5347d91c82d99a69',\n",
                                         "    'math/vector4.mojo': "
                                         "'db774733a27a706e5d5c940c4533de2c567d7d6ece3c918215052bccfd87b9aa',\n",
                                         "    'objects/gaussian_splat.mojo': "
                                         "'6b5834369f244c8eaf6a4a6d363bcca7f645a4964f72ddea25df62f63097cf3c',\n",
                                         "    'render/tasks.mojo': "
                                         "'9b80dcaceec958190ade19bff6d106617c8c4c99e80d37eb0205609741ca2934',\n",
                                         '}\n',
                                         '\n',
                                         '\n')),
                                       (1250,
                                        1263,
                                        (),
                                        ('\n',
                                         '\n',
                                         'def _density780_dependencies():\n',
                                         '    """Snapshot only the six exact '
                                         'local successor endpoints from live '
                                         'data."""\n',
                                         '    declared = '
                                         "globals().get('DENSITY780_DEPENDENCY_SHA256')\n",
                                         '    if type(declared) is not dict:\n',
                                         "        raise ValueError('Invalid "
                                         'density dependency successor '
                                         "namespace')\n",
                                         '    dependencies = dict(declared)\n',
                                         '    if (any(type(name) is not str or '
                                         'type(digest) is not str\n',
                                         '            for name, digest in '
                                         'dependencies.items())\n',
                                         '            or '
                                         'sha256(canonical(dependencies)) != '
                                         "'e9be8cbe0aa84f423064541280e5800d6de67582a30dfe1a21a1b567ac8ef44a'):\n",
                                         "        raise ValueError('Unreviewed "
                                         'density dependency successor '
                                         "endpoints')\n",
                                         '    return dependencies\n')),
                                       (1302,
                                        1320,
                                        ('        snapshots = {}\n',),
                                        ('        # The generated receipt '
                                         'authenticates its direct producer, '
                                         'not every\n',
                                         '        # live helper. Bind this new '
                                         'authority reader to physical tool '
                                         'code.\n',
                                         '        filename = '
                                         'str(Path(__file__).resolve())\n',
                                         '        checker = '
                                         'Path(filename).read_bytes()\n',
                                         '        if sha256(checker) != '
                                         'ACTIVE_SOURCE_SHA256:\n',
                                         '            return {}\n',
                                         '        expected_reader = '
                                         'cleanup._compiled_functions(checker, '
                                         "filename)['_density780_dependencies']\n",
                                         '        def dependency_pins():\n',
                                         '            live = '
                                         "globals().get('_density780_dependencies')\n",
                                         '            '
                                         'cleanup.require(Path(filename).read_bytes() '
                                         '== checker\n',
                                         '                and type(live) is '
                                         'types.FunctionType\n',
                                         '                and live.__globals__ '
                                         'is globals() and live.__defaults__ '
                                         'is None\n',
                                         '                and '
                                         'live.__kwdefaults__ is None and '
                                         "'__wrapped__' not in live.__dict__\n",
                                         '                and '
                                         'cleanup._code_identity(live.__code__) '
                                         '== '
                                         'cleanup._code_identity(expected_reader),\n',
                                         "                'density dependency "
                                         "successor reader code changed')\n",
                                         '            return live()\n',
                                         '        successor_pins = '
                                         'dependency_pins()\n',
                                         '        snapshots, '
                                         'dependency_sha256, successor = {}, '
                                         '{}, []\n')),
                                       (1323,
                                        1329,
                                        ('            if sha256(value) != '
                                         'expected:\n',),
                                        ('            digest = sha256(value)\n',
                                         '            if name in '
                                         'successor_pins:\n',
                                         '                if digest not in '
                                         '(expected, successor_pins[name]):\n',
                                         '                    return {}\n',
                                         '                '
                                         'successor.append(digest != '
                                         'expected)\n',
                                         '            elif digest != '
                                         'expected:\n')),
                                       (1331,
                                        1334,
                                        (),
                                        ('            dependency_sha256[name] '
                                         '= digest\n',
                                         '        if any(successor) and not '
                                         'all(successor):\n',
                                         '            return {}\n')),
                                       (1374,
                                        1376,
                                        ('        if '
                                         'cleanup.executing_checker_bindings() '
                                         '!= executing or not '
                                         'resolver_ok():\n',),
                                        ('        if '
                                         '(cleanup.executing_checker_bindings() '
                                         '!= executing or not resolver_ok()\n',
                                         '                or dependency_pins() '
                                         '!= successor_pins):\n')),
                                       (1381,
                                        1382,
                                        ("            'proof_id': proof_id, "
                                         "'dependency_sha256': "
                                         'dict(DENSITY760_INPUTS),\n',),
                                        ("            'proof_id': proof_id, "
                                         "'dependency_sha256': "
                                         'dict(dependency_sha256),\n',)),
                                       (1445,
                                        1455,
                                        ('        '
                                         "'5cc066092d9b0302c60a6676459efc855e220dc319d1f88b5eb84df768f489f9',\n",),
                                        ('        '
                                         "'990d94c815315c910b12c1b126c076183fc35cdeb9f64a26d1f7e574f424bccd',\n",
                                         '}, 4049)\n',
                                         '\n',
                                         '\n',
                                         '# PR791 passes the worker count to '
                                         'the splat prepare call, far below '
                                         'the cap\n',
                                         '# loop. The cap function, its '
                                         'producer and its line are '
                                         'unchanged.\n',
                                         'STRAND_CAP_SPLAT_WORKERS_SUCCESSOR = '
                                         '({\n',
                                         '    '
                                         '**STRAND_CAP_FORMATTED_SUCCESSOR[0],\n',
                                         "    'renderers/renderer.mojo':\n",
                                         '        '
                                         "'c08275ccfea2f32dd84dc5ad54205052f6dfd216104836c858ff259224426332',\n")),
                                       (1506,
                                        1509,
                                        ('        if actual == '
                                         'STRAND_CAP_FORMATTED_SUCCESSOR[0]:\n',),
                                        ('        if actual == '
                                         'STRAND_CAP_SPLAT_WORKERS_SUCCESSOR[0]:\n',
                                         '            line = '
                                         'STRAND_CAP_SPLAT_WORKERS_SUCCESSOR[1]\n',
                                         '        elif actual == '
                                         'STRAND_CAP_FORMATTED_SUCCESSOR[0]:\n')),
                                       (1638,
                                        1640,
                                        ('        if typed.is_current(name, '
                                         'raw):\n',),
                                        ('        endpoint = '
                                         '_typed_endpoint(name, raw)\n',
                                         '        if typed.is_current(name, '
                                         'endpoint):\n')),
                                       (1650,
                                        1651,
                                        ('            checked = '
                                         'typed.historical_source(name, '
                                         "raw.decode('utf-8'))\n",),
                                        ('            checked = '
                                         'typed.historical_source(name, '
                                         "endpoint.decode('utf-8'))\n",)),
                                       (1847,
                                        1848,
                                        ('            if '
                                         'typed.is_current(name, current):\n',),
                                        ('            if '
                                         'typed.is_current(name, '
                                         '_typed_endpoint(name, '
                                         'current)):\n',)),
                                       (1857,
                                        1858,
                                        ('        if (typed.is_current(name, '
                                         'current) and _operation is None\n',),
                                        ('        if (typed.is_current(name, '
                                         '_typed_endpoint(name, current)) and '
                                         '_operation is None\n',)),
                                       (1892,
                                        1895,
                                        (),
                                        ('        if not typed_current:\n',
                                         '            typed_current = '
                                         'typed.is_current(\n',
                                         '                module_path, '
                                         '_typed_endpoint(module_path, '
                                         'current))\n')),
                                       (2116,
                                        2117,
                                        ('            or not '
                                         'typed.is_current(name, '
                                         'current)):\n',),
                                        ('            or not '
                                         'typed.is_current(name, '
                                         '_typed_endpoint(name, '
                                         'current))):\n',)),
                                       (2179,
                                        2180,
                                        ('        if typed.is_current(name, '
                                         'current):\n',),
                                        ('        if typed.is_current(name, '
                                         '_typed_endpoint(name, '
                                         'current)):\n',)))},
 'full_audit_cleanup_contracts.py': {'after_sha256': 'efc024d4721fdfdeb406d846aedaad9cbe25329128214f8ba90cbe227a86ee02',
                                     'before_sha256': 'f62dbe69ddd5d15bd79aa4b0a8237d9475fe1a00cea06c2f7124c59af237c833',
                                     'edits': ((56,
                                                57,
                                                (),
                                                ('        from . import '
                                                 'pr780_source_successor as '
                                                 'pr780_successor\n',)),
                                               (71,
                                                72,
                                                (),
                                                ('        import '
                                                 'pr780_source_successor as '
                                                 'pr780_successor\n',)),
                                               (160,
                                                161,
                                                (),
                                                (' '
                                                 "'tools/carla_lane_oracle/pr780_source_successor.py': "
                                                 "'5bc5abd8dbdb091a2e12c0fa1156bd514304fb29f297548cf2e4ac1526cbeefd',\n",)),
                                               (162,
                                                163,
                                                (" 'tools/affected.py': "
                                                 "'a56194a3e722ad341a42f3defec282b8154f5e4db8340df855f0199ea9830ebb',\n",),
                                                (" 'tools/affected.py': "
                                                 "'dcf533b9cd995902f53578aa93b98a32ca732643ccfa6ab7e30f95fd8b321eb3',\n",)),
                                               (170,
                                                171,
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',\n",),
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'6a1f6f3efed801d586976fb3f7acff672d61409fbc61c957b8bf7cd808d3fda8',\n",)),
                                               (250,
                                                252,
                                                ('                 '
                                                 "'tools/carla_lane_oracle/pr760_arithmetic_stage.py')\n",),
                                                ('                 '
                                                 "'tools/carla_lane_oracle/pr760_arithmetic_stage.py',\n",
                                                 '                 '
                                                 "'tools/carla_lane_oracle/pr780_source_successor.py')\n")),
                                               (675,
                                                727,
                                                (),
                                                ('def _code_equal(left, '
                                                 'right):\n',
                                                 '    """Compare complete code '
                                                 'data without building two '
                                                 'recursive images."""\n',
                                                 '    def '
                                                 'constant_equal(first, '
                                                 'second):\n',
                                                 '        kind = type(first)\n',
                                                 '        if kind is not '
                                                 'type(second):\n',
                                                 '            # Both sides '
                                                 'must still reject '
                                                 'unsupported data after a '
                                                 'mismatch.\n',
                                                 '            return '
                                                 '_code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '        if kind is '
                                                 'types.CodeType:\n',
                                                 '            return '
                                                 'code_equal(first, second)\n',
                                                 '        if kind is tuple:\n',
                                                 '            if len(first) != '
                                                 'len(second):\n',
                                                 '                return '
                                                 '_code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '            equal = True\n',
                                                 '            for one, two in '
                                                 'zip(first, second, '
                                                 'strict=True):\n',
                                                 '                equal = '
                                                 'constant_equal(one, two) and '
                                                 'equal\n',
                                                 '            return equal\n',
                                                 '        if kind is '
                                                 'frozenset:\n',
                                                 '            # Preserve typed '
                                                 'elements, float bits and '
                                                 'canonical NaN collapse.\n',
                                                 '            return '
                                                 '_code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '        if kind is float:\n',
                                                 '            return '
                                                 "struct.pack('>d', first) == "
                                                 "struct.pack('>d', second)\n",
                                                 '        if kind is '
                                                 'complex:\n',
                                                 '            return '
                                                 "(struct.pack('>dd', "
                                                 'first.real, first.imag)\n',
                                                 '                    == '
                                                 "struct.pack('>dd', "
                                                 'second.real, second.imag))\n',
                                                 '        if first is '
                                                 'Ellipsis:\n',
                                                 '            return True\n',
                                                 '        if kind is slice:\n',
                                                 '            return '
                                                 'constant_equal((first.start, '
                                                 'first.stop, first.step),\n',
                                                 '                                  '
                                                 '(second.start, second.stop, '
                                                 'second.step))\n',
                                                 '        if kind is str or '
                                                 'kind is bytes or kind is int '
                                                 'or kind is bool or kind is '
                                                 'type(None):\n',
                                                 '            return first == '
                                                 'second\n',
                                                 '        return '
                                                 '_code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '\n',
                                                 '    def code_equal(first, '
                                                 'second):\n',
                                                 '        if type(first) is '
                                                 'not types.CodeType or '
                                                 'type(second) is not '
                                                 'types.CodeType:\n',
                                                 '            return '
                                                 '_code_identity(first) == '
                                                 '_code_identity(second)\n',
                                                 '        equal = True\n',
                                                 '        for name in '
                                                 'sorted(dir(first)):\n',
                                                 '            if '
                                                 "name.startswith('co_') and "
                                                 "name != 'co_filename':\n",
                                                 '                value = '
                                                 'getattr(first, name)\n',
                                                 '                if not '
                                                 'callable(value):\n',
                                                 '                    # Visit '
                                                 'every field: later '
                                                 'unsupported constants must '
                                                 'fail.\n',
                                                 '                    equal = '
                                                 'constant_equal(value, '
                                                 'getattr(second, name)) and '
                                                 'equal\n',
                                                 '        return equal\n',
                                                 '\n',
                                                 '    try:\n',
                                                 '        return '
                                                 'code_equal(left, right)\n',
                                                 '    finally:\n',
                                                 '        # Release the '
                                                 'recursive closures without '
                                                 'waiting for cyclic '
                                                 'collection.\n',
                                                 '        del code_equal, '
                                                 'constant_equal\n',
                                                 '\n',
                                                 '\n')),
                                               (774,
                                                775,
                                                ('for _module in (source, '
                                                 "guard, _sibling('affected'), "
                                                 "_sibling('cache_key'), "
                                                 'consumer_ledger, station, '
                                                 'shared_helpers, '
                                                 'runtime_view, deviation, '
                                                 'witness_format, '
                                                 'typed_boundary, '
                                                 'conditioned_cubic, '
                                                 'scaled_float32, '
                                                 'pr760_stage):\n',),
                                                ('for _module in (source, '
                                                 "guard, _sibling('affected'), "
                                                 "_sibling('cache_key'), "
                                                 'consumer_ledger, station, '
                                                 'shared_helpers, '
                                                 'runtime_view, deviation, '
                                                 'witness_format, '
                                                 'typed_boundary, '
                                                 'conditioned_cubic, '
                                                 'scaled_float32, pr760_stage, '
                                                 'pr780_successor):\n',)),
                                               (823,
                                                834,
                                                (),
                                                ('    compare = '
                                                 "globals().get('_code_equal')\n",
                                                 '    require(type(compare) is '
                                                 'types.FunctionType and '
                                                 'compare.__globals__ is '
                                                 'globals()\n',
                                                 '            and '
                                                 'compare.__defaults__ is None '
                                                 'and compare.__kwdefaults__ '
                                                 'is None\n',
                                                 '            and '
                                                 "'__wrapped__' not in "
                                                 'compare.__dict__,\n',
                                                 "            'executing code "
                                                 'comparison helper '
                                                 "changed')\n",
                                                 '    compare_code = '
                                                 'compare.__code__\n',
                                                 '    '
                                                 'require(_code_identity(compare_code) '
                                                 '== _code_identity(\n',
                                                 '                '
                                                 "_IMPORT_CODE[str(_SELF_PATH)]['_code_equal']),\n",
                                                 "            'executing code "
                                                 'comparison helper '
                                                 "changed')\n",
                                                 '    # Later mutation of the '
                                                 'live function must not '
                                                 'replace this captured '
                                                 'code.\n',
                                                 '    compare = '
                                                 'types.FunctionType(compare_code, '
                                                 'globals())\n')),
                                               (838,
                                                839,
                                                ('               '
                                                 'vars(scaled_float32), '
                                                 'vars(pr760_stage))\n',),
                                                ('               '
                                                 'vars(scaled_float32), '
                                                 'vars(pr760_stage), '
                                                 'vars(pr780_successor))\n',)),
                                               (859,
                                                860,
                                                ('                    '
                                                 'require(actual is not None '
                                                 'and _code_identity(actual) '
                                                 '== _code_identity(code),\n',),
                                                ('                    '
                                                 'require(actual is not None '
                                                 'and compare(actual, '
                                                 'code),\n',)),
                                               (866,
                                                867,
                                                ('                '
                                                 'require(actual is not None '
                                                 'and _code_identity(actual) '
                                                 '== '
                                                 '_code_identity(expected),\n',),
                                                ('                '
                                                 'require(actual is not None '
                                                 'and compare(actual, '
                                                 'expected),\n',)),
                                               (877,
                                                878,
                                                (),
                                                ('    '
                                                 'pr780_successor.verify_data()\n',)),
                                               (3540,
                                                3543,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if extension is not None '
                                                 'and sha(text) == '
                                                 "extension['after_sha256']:\n",
                                                 '        text = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 "text.encode('utf-8')).decode('utf-8')\n")),
                                               (3631,
                                                3634,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if edge is None and '
                                                 'extension is None:\n',
                                                 '        return text\n')),
                                               (3635,
                                                3636,
                                                ('        return text\n',),
                                                ('        edge = '
                                                 'extension\n',)),
                                               (3652,
                                                3659,
                                                ('        new_endpoint = path '
                                                 'in '
                                                 'pr760_stage.CARLA_REGISTRY_PATHS '
                                                 'and '
                                                 'source.token_sha256(text) == '
                                                 "edge['after_token_sha256']\n",
                                                 '        if not (new_endpoint '
                                                 'or '
                                                 'typed_boundary.is_current(path, '
                                                 'text) or\n',
                                                 '                '
                                                 'source.token_sha256(text) == '
                                                 "edge['after_token_sha256']):\n"),
                                                ('        extended = '
                                                 '(extension is not None and '
                                                 'sha(text) != '
                                                 "extension['before_sha256'] "
                                                 'and\n',
                                                 '            '
                                                 'source.token_sha256(text) == '
                                                 "extension['after_token_sha256'])\n",
                                                 '        new_endpoint = path '
                                                 'in '
                                                 'pr760_stage.CARLA_REGISTRY_PATHS '
                                                 'and (extended or\n',
                                                 '            '
                                                 'source.token_sha256(text) == '
                                                 "edge['after_token_sha256'])\n",
                                                 '        if not (extended or '
                                                 'new_endpoint or '
                                                 'typed_boundary.is_current(path, '
                                                 'text) or\n',
                                                 '                (edge is not '
                                                 'extension and\n',
                                                 '                 '
                                                 'source.token_sha256(text) == '
                                                 "edge['after_token_sha256'])):\n")),
                                               (3662,
                                                3664,
                                                ('        require((sha(raw) == '
                                                 "edge['after_sha256']) if "
                                                 'new_endpoint else '
                                                 'typed_boundary.is_current(path, '
                                                 'raw),\n',),
                                                ('        require((sha(raw) == '
                                                 "extension['after_sha256']) "
                                                 'if extended else\n',
                                                 '                (sha(raw) == '
                                                 "edge['after_sha256']) if "
                                                 'new_endpoint else '
                                                 'typed_boundary.is_current(path, '
                                                 'raw),\n')),
                                               (3864,
                                                3868,
                                                (),
                                                ('                else:\n',
                                                 '                    '
                                                 'extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '                    if '
                                                 'extension is not None and '
                                                 'sha(historical) == '
                                                 "extension['after_sha256']:\n",
                                                 '                        '
                                                 'historical = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'historical)\n')),
                                               (4033,
                                                4034,
                                                (),
                                                ('    extensions = '
                                                 "pr780_successor._data_snapshot()['edges']\n",)),
                                               (4037,
                                                4040,
                                                ('                   '
                                                 'source.token_sha256(text) == '
                                                 "pr760_stage.EDGES[p]['after_token_sha256'])}\n",),
                                                ('                   '
                                                 'source.token_sha256(text) == '
                                                 "pr760_stage.EDGES[p]['after_token_sha256'])\n",
                                                 '               or (p in '
                                                 'extensions and '
                                                 'source.token_sha256(text) '
                                                 '==\n',
                                                 '                   '
                                                 "extensions[p]['after_token_sha256'])}\n")),
                                               (4163,
                                                4169,
                                                ('            projected = '
                                                 '(pr760_stage.predecessor_source(path, '
                                                 "current.decode('utf-8'))\n",),
                                                ('            extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '            retained = '
                                                 '(pr780_successor.predecessor_bytes(path, '
                                                 'current)\n',
                                                 '                        if '
                                                 'extension is not None and '
                                                 'sha(current) in (\n',
                                                 '                            '
                                                 "extension['before_sha256'], "
                                                 "extension['after_sha256'])\n",
                                                 '                        else '
                                                 'current)\n',
                                                 '            projected = '
                                                 '(pr760_stage.predecessor_source(path, '
                                                 "retained.decode('utf-8'))\n")),
                                               (4171,
                                                4172,
                                                ('                if '
                                                 'qualification else '
                                                 "current.decode('utf-8'))\n",),
                                                ('                if '
                                                 'qualification else '
                                                 "retained.decode('utf-8'))\n",)),
                                               (4175,
                                                4176,
                                                ('            if current_image '
                                                 'and (path in '
                                                 'pr760_stage.EXAMPLE_PATHS or '
                                                 'qualification):\n',),
                                                ('            if current_image '
                                                 'and (path in '
                                                 'pr760_stage.EXAMPLE_PATHS or '
                                                 'qualification or current != '
                                                 'retained):\n',)),
                                               (4206,
                                                4211,
                                                ('        if '
                                                 'result.get(station.MODULE) '
                                                 '== '
                                                 "typed_boundary.EDGES[station.MODULE]['after_sha256']:\n",),
                                                ('        station_digest = '
                                                 'result.get(station.MODULE)\n',
                                                 '        extension = '
                                                 'pr780_successor.reviewed_edge(station.MODULE)\n',
                                                 '        if extension is not '
                                                 'None and station_digest == '
                                                 "extension['after_sha256']:\n",
                                                 '            station_digest = '
                                                 "extension['before_sha256']\n",
                                                 '        if station_digest == '
                                                 "typed_boundary.EDGES[station.MODULE]['after_sha256']:\n")),
                                               (4279,
                                                4280,
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',\n",),
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'6a1f6f3efed801d586976fb3f7acff672d61409fbc61c957b8bf7cd808d3fda8',\n",)),
                                               (4299,
                                                4302,
                                                (' '
                                                 "'tools/carla_lane_oracle/test_pr760_physical_image.py': "
                                                 "'1c1565c05cb702df67319cb69641f83c8a761d38ccf06a11de91b037dfe5b1ce',\n",
                                                 ' '
                                                 "'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py': "
                                                 "'ac51eb5dd58c8e3768f2405108203351194d72d63f2b53f4e30d5b2d4d8c26ab'}\n"),
                                                (' '
                                                 "'tools/carla_lane_oracle/test_pr760_physical_image.py': "
                                                 "'6df971f2bf09c710a4e6ababc6adeea8995fd2e86c3e6866e548d5b193ae3669',\n",
                                                 ' '
                                                 "'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py': "
                                                 "'ac51eb5dd58c8e3768f2405108203351194d72d63f2b53f4e30d5b2d4d8c26ab',\n",
                                                 ' '
                                                 "'tools/carla_lane_oracle/test_typed_boundary_contracts.py': "
                                                 "'8dee4d9c4bf42214fb2f10fbdcf71a4ba04398095d8c62a16233ad6fc038fce7'}\n")),
                                               (4306,
                                                4307,
                                                ('    return '
                                                 "{'tools/carla_lane_oracle/test_pr776_input_successors.py': "
                                                 "'af0d9aff27b4f06ce8b102979825d84c177ec78b349dbbb1de4a98423c03f132',\n",),
                                                ('    return '
                                                 "{'tools/carla_lane_oracle/test_pr776_input_successors.py': "
                                                 "'148a021e1d8173122f231f4e6839d4dfd7bb2bb14d76d70e3725ff310620d2aa',\n",)),
                                               (4315,
                                                4316,
                                                ('    """Recover exact earlier '
                                                 'comparison bytes for five '
                                                 'named PR776 inputs.\n',),
                                                ('    """Recover exact earlier '
                                                 'comparison bytes for six '
                                                 'named PR776 inputs.\n',)),
                                               (4324,
                                                4327,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if extension is not None '
                                                 'and sha(raw) == '
                                                 "extension['after_sha256']:\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'raw)\n')),
                                               (4708,
                                                4709,
                                                ('                                                          '
                                                 "'1c1565c05cb702df67319cb69641f83c8a761d38ccf06a11de91b037dfe5b1ce',\n",),
                                                ('                                                          '
                                                 "'6df971f2bf09c710a4e6ababc6adeea8995fd2e86c3e6866e548d5b193ae3669',\n",)),
                                               (4710,
                                                4711,
                                                ('                                                            '
                                                 '128,\n',),
                                                ('                                                            '
                                                 '129,\n',)),
                                               (4727,
                                                4730,
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\'):\\n",\n',),
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\',\\n",\n',
                                                 '                                                             '
                                                 "'                        '\n",
                                                 '                                                             '
                                                 '"\'tools/carla_lane_oracle/test_typed_boundary_contracts.py\'):\\n",\n')),
                                               (4736,
                                                4738,
                                                ('                                                           '
                                                 '(239,\n',
                                                 '                                                            '
                                                 '243,\n'),
                                                ('                                                           '
                                                 '(240,\n',
                                                 '                                                            '
                                                 '245,\n')),
                                               (4743,
                                                4744,
                                                ('                                                             '
                                                 "'raw) if path ==\\n',\n",),
                                                ('                                                             '
                                                 "'raw) if path in (\\n',\n",)),
                                               (4745,
                                                4748,
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_expectation_binding_successor.py\' '
                                                 '"\n',),
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_expectation_binding_successor.py\',\\n",\n',
                                                 '                                                             '
                                                 "'                        '\n",
                                                 '                                                             '
                                                 '"\'tools/carla_lane_oracle/test_typed_boundary_contracts.py\') '
                                                 '"\n')),
                                               (4764,
                                                4775,
                                                ('                                                               '
                                                 "'inputs[water])\\n')),))}\n",),
                                                ('                                                               '
                                                 "'inputs[water])\\n')),)),\n",
                                                 ' '
                                                 "'tools/carla_lane_oracle/test_typed_boundary_contracts.py': "
                                                 "('7114f17cce33b84fe226d3559b4d08d1227a6c1cda1f83825441d22e48b51705',\n",
                                                 '                                                              '
                                                 "'8dee4d9c4bf42214fb2f10fbdcf71a4ba04398095d8c62a16233ad6fc038fce7',\n",
                                                 '                                                              '
                                                 '((444,\n',
                                                 '                                                                '
                                                 '446,\n',
                                                 '                                                                '
                                                 '(),\n',
                                                 '                                                                '
                                                 "('                if path == "
                                                 "'\n",
                                                 '                                                                 '
                                                 '"\'tools/compile_fail_expectations.json\':\\n",\n',
                                                 '                                                                 '
                                                 "'                    raw = "
                                                 "'\n",
                                                 '                                                                 '
                                                 "'audit.pr776_predecessor_bytes(path, "
                                                 "'\n",
                                                 '                                                                 '
                                                 "'raw)\\n')),))}\n")),
                                               (4811,
                                                4814,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if extension is not None '
                                                 'and sha(raw) == '
                                                 "extension['after_sha256']:\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'raw)\n')),
                                               (4816,
                                                4819,
                                                (),
                                                ('        raw = '
                                                 'pr776_predecessor_bytes(path, '
                                                 'raw)\n',
                                                 '    if (path == '
                                                 "'tools/carla_lane_oracle/test_typed_boundary_contracts.py'\n",
                                                 '            and sha(raw) == '
                                                 "'8dee4d9c4bf42214fb2f10fbdcf71a4ba04398095d8c62a16233ad6fc038fce7'):\n")),
                                               (5411,
                                                5416,
                                                (),
                                                ('    extension_path = '
                                                 "'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py'\n",
                                                 '    extension = '
                                                 'pr780_successor.reviewed_edge(extension_path)\n',
                                                 '    if (type(raw) is bytes '
                                                 'and\n',
                                                 '            sha(raw) == '
                                                 "extension['after_sha256']):\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(extension_path, '
                                                 'raw)\n')),
                                               (5503,
                                                5504,
                                                (),
                                                ('        extension_data = '
                                                 'pr780_successor._data_snapshot()\n',)),
                                               (5505,
                                                5513,
                                                (),
                                                ('        extended_pins = '
                                                 '{path: '
                                                 "edge['after_sha256']\n",
                                                 '                         for '
                                                 'path, edge in '
                                                 "extension_data['edges'].items()}\n",
                                                 '        '
                                                 'require(set(extended_pins) '
                                                 '<= set(expected) | '
                                                 'set(_pr776_bound_inputs()),\n',
                                                 "                'PR780 "
                                                 'source successor misses a '
                                                 "fixed predecessor')\n",
                                                 '        for path, edge in '
                                                 "extension_data['edges'].items():\n",
                                                 '            '
                                                 "require(edge['before_sha256'] "
                                                 '== '
                                                 'successor_pins.get(path,\n',
                                                 '                    '
                                                 'expected.get(path, '
                                                 '_pr776_bound_inputs().get(path))),\n',
                                                 "                    'PR780 "
                                                 'source successor predecessor '
                                                 "join changed: ' + path)\n")),
                                               (5515,
                                                5516,
                                                ('            require(sha(raw) '
                                                 '== successor_pins.get(path, '
                                                 'digest),\n',),
                                                ('            require(sha(raw) '
                                                 '== extended_pins.get(path, '
                                                 'successor_pins.get(path, '
                                                 'digest)),\n',)),
                                               (5517,
                                                5522,
                                                ('            if path in '
                                                 'successor_pins:\n',
                                                 '                '
                                                 'prior_inputs[path] = '
                                                 'pr776_predecessor_bytes(path, '
                                                 'raw)\n',
                                                 '                '
                                                 'require(sha(prior_inputs[path]) '
                                                 '== digest,\n',
                                                 '                        '
                                                 "'PR776 successor misses "
                                                 "fixed PR760 input: ' + "
                                                 'path)\n'),
                                                ('            retained = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'raw)\n',
                                                 '            '
                                                 'prior_inputs[path] = '
                                                 '(pr776_predecessor_bytes(path, '
                                                 'retained)\n',
                                                 '                                  '
                                                 'if path in successor_pins '
                                                 'else retained)\n',
                                                 '            '
                                                 'require(sha(prior_inputs[path]) '
                                                 '== digest,\n',
                                                 '                    '
                                                 "'PR780/PR776 successor "
                                                 "misses fixed PR760 input: ' "
                                                 '+ path)\n')),
                                               (5523,
                                                5530,
                                                ('            '
                                                 'require(sha(observe(path)) '
                                                 "== digest, 'PR776 bound "
                                                 "input changed: ' + path)\n",),
                                                ('            raw = '
                                                 'observe(path)\n',
                                                 '            require(sha(raw) '
                                                 '== extended_pins.get(path, '
                                                 "digest), 'PR776 bound input "
                                                 "changed: ' + path)\n",
                                                 '            '
                                                 'require(sha(pr780_successor.predecessor_bytes(path, '
                                                 'raw)) == digest,\n',
                                                 "                    'PR780 "
                                                 'successor misses fixed PR776 '
                                                 "input: ' + path)\n",
                                                 '        '
                                                 'pr780_successor.verify_sources({path: '
                                                 'image[path] for path in '
                                                 'extended_pins})\n',
                                                 '        for path, digest in '
                                                 "extension_data['bound_inputs'].items():\n",
                                                 '            '
                                                 'require(sha(observe(path)) '
                                                 "== digest, 'PR780 bound "
                                                 "input changed: ' + path)\n")),
                                               (5546,
                                                5548,
                                                ('                              '
                                                 'if path == '
                                                 "'tools/carla_lane_oracle/test_witness_format_contracts.py' "
                                                 'else '
                                                 "image[path].decode('utf-8'))\n",),
                                                ('                              '
                                                 'if path == '
                                                 "'tools/carla_lane_oracle/test_witness_format_contracts.py'\n",
                                                 '                              '
                                                 'else prior_inputs.get(path, '
                                                 "image[path]).decode('utf-8'))\n")),
                                               (5563,
                                                5564,
                                                ('        helper_texts = '
                                                 '{path: previous.get(path, '
                                                 "image[path].decode('utf-8'))\n",),
                                                ('        helper_texts = '
                                                 '{path: previous.get(path, '
                                                 'prior_inputs.get(path, '
                                                 "image[path]).decode('utf-8'))\n",)),
                                               (5617,
                                                5623,
                                                ('        observed = '
                                                 'inventory(root, '
                                                 '_snapshots=image, '
                                                 '_production=production)\n',),
                                                ('        # The fixed PR760 '
                                                 'inventory binds retained '
                                                 'predecessor tokens, so a\n',
                                                 '        # successor source '
                                                 'contributes the tokens of '
                                                 'its exact predecessor.\n',
                                                 '        observed = {\n',
                                                 '            path: '
                                                 "({'tokens_sha256': "
                                                 "source.token_sha256(prior_inputs[path].decode('utf-8'))}\n",
                                                 '                   if path '
                                                 'in prior_inputs else row)\n',
                                                 '            for path, row in '
                                                 'inventory(root, '
                                                 '_snapshots=image, '
                                                 '_production=production).items()}\n')))},
 'source_contracts.py': {'after_sha256': '6a1f6f3efed801d586976fb3f7acff672d61409fbc61c957b8bf7cd808d3fda8',
                         'before_sha256': 'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',
                         'edits': ((51,
                                    56,
                                    (),
                                    ('# Immutable records pin these sources by '
                                     'their digests from before the PR780\n',
                                     '# successor edit. Their historical view '
                                     'is the exact predecessor.\n',
                                     'HISTORICAL_SUCCESSOR_PATHS = '
                                     'frozenset((\n',
                                     "    PREFIX + 'assets.mojo', PREFIX + "
                                     "'model_cache.mojo', PREFIX + "
                                     "'sensor.mojo',\n",
                                     "    PREFIX + 'speed_limits.mojo', "
                                     "'tests/test_carla_speed_parser_exceptions.mojo'))\n")),
                                   (355,
                                    357,
                                    ('        if relative not in '
                                     'pr760.CARLA_REGISTRY_PATHS:\n',),
                                    ('        if (relative not in '
                                     'pr760.CARLA_REGISTRY_PATHS\n',
                                     '                and relative not in '
                                     'HISTORICAL_SUCCESSOR_PATHS):\n')),
                                   (380,
                                    382,
                                    ('        if relative not in '
                                     'pr760.CARLA_REGISTRY_PATHS:\n',),
                                    ('        if (relative not in '
                                     'pr760.CARLA_REGISTRY_PATHS\n',
                                     '                and relative not in '
                                     'HISTORICAL_SUCCESSOR_PATHS):\n')))}}


def predecessor(name, raw):
    """Compose exact current checkers into the retained 5e91dad comparison."""
    if type(raw) is not bytes:
        raise AssertionError('checker source must be physical builtin bytes')
    if hashlib.sha256(json.dumps(EDGES, sort_keys=True, separators=(',', ':')).encode()).hexdigest() != 'a3f105e3657184a2a398da63409601c1acfe11b6bd85ffeb5302b30c662481d8':
        raise AssertionError('PR780 checker inverse data changed')
    digest = hashlib.sha256(raw).hexdigest()
    edge = EDGES.get(name)
    if edge is None or digest != edge['after_sha256']:
        # This grants no acceptance. The preserved next inverse still checks its
        # complete before/after endpoint and refuses every unreviewed source.
        return raw, {line: (line, line) for line in range(1, len(raw.splitlines())+1)}
    lines = raw.decode('utf-8').splitlines(keepends=True)
    result, mapping, cursor = [], {}, 0
    for start, stop, before, after in edge['edits']:
        if not cursor <= start <= stop <= len(lines) or tuple(lines[start:stop]) != after:
            raise AssertionError(('PR780 checker inverse span changed', start, stop))
        for current in range(cursor, start):
            mapping[len(result)+1] = (current+1, current+1)
            result.append(lines[current])
        for line in before:
            mapping[len(result)+1] = (start+1, stop)
            result.append(line)
        cursor = stop
    for current in range(cursor, len(lines)):
        mapping[len(result)+1] = (current+1, current+1)
        result.append(lines[current])
    prior = ''.join(result).encode('utf-8')
    if hashlib.sha256(prior).hexdigest() != edge['before_sha256']:
        raise AssertionError('PR780 checker inverse misses the exact PR776 owner')
    return prior, mapping


def compose(inner, outer):
    """Translate existing retained observer sites into current physical ranges."""
    result = {}
    for line, (first, last) in inner.items():
        if first > last:
            result[line] = (first, last)
            continue
        ranges = [outer[index] for index in range(first, last+1)]
        result[line] = (min(start for start, stop in ranges), max(stop for start, stop in ranges))
    return result
