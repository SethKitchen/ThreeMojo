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

EDGES = {'full_audit_cleanup_contracts.py': {'before_sha256': 'f62dbe69ddd5d15bd79aa4b0a8237d9475fe1a00cea06c2f7124c59af237c833',
                                     'after_sha256': '2542c8ff7d8ed131ec78d70d4b53077d6195ff087e8cf4ec8533c991e72a4f59',
                                     'edits': ((56,
                                                57,
                                                (),
                                                ('        from . import pr780_source_successor as '
                                                 'pr780_successor\n',)),
                                               (71,
                                                72,
                                                (),
                                                ('        import pr780_source_successor as '
                                                 'pr780_successor\n',)),
                                               (160,
                                                161,
                                                (),
                                                (' '
                                                 "'tools/carla_lane_oracle/pr780_source_successor.py': "
                                                 "'bd70f8aba6c03e0359c2324cad6cf519ce423766037fe778f269def09a6b0c88',\n",)),
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
                                                ('def _code_equal(left, right):\n',
                                                 '    """Compare complete code data without '
                                                 'building two recursive images."""\n',
                                                 '    def constant_equal(first, second):\n',
                                                 '        kind = type(first)\n',
                                                 '        if kind is not type(second):\n',
                                                 '            # Both sides must still reject '
                                                 'unsupported data after a mismatch.\n',
                                                 '            return _code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '        if kind is types.CodeType:\n',
                                                 '            return code_equal(first, second)\n',
                                                 '        if kind is tuple:\n',
                                                 '            if len(first) != len(second):\n',
                                                 '                return _code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '            equal = True\n',
                                                 '            for one, two in zip(first, second, '
                                                 'strict=True):\n',
                                                 '                equal = constant_equal(one, two) '
                                                 'and equal\n',
                                                 '            return equal\n',
                                                 '        if kind is frozenset:\n',
                                                 '            # Preserve typed elements, float '
                                                 'bits and canonical NaN collapse.\n',
                                                 '            return _code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '        if kind is float:\n',
                                                 "            return struct.pack('>d', first) == "
                                                 "struct.pack('>d', second)\n",
                                                 '        if kind is complex:\n',
                                                 "            return (struct.pack('>dd', "
                                                 'first.real, first.imag)\n',
                                                 "                    == struct.pack('>dd', "
                                                 'second.real, second.imag))\n',
                                                 '        if first is Ellipsis:\n',
                                                 '            return True\n',
                                                 '        if kind is slice:\n',
                                                 '            return constant_equal((first.start, '
                                                 'first.stop, first.step),\n',
                                                 '                                  (second.start, '
                                                 'second.stop, second.step))\n',
                                                 '        if kind is str or kind is bytes or kind '
                                                 'is int or kind is bool or kind is type(None):\n',
                                                 '            return first == second\n',
                                                 '        return _code_constant(first) == '
                                                 '_code_constant(second)\n',
                                                 '\n',
                                                 '    def code_equal(first, second):\n',
                                                 '        if type(first) is not types.CodeType or '
                                                 'type(second) is not types.CodeType:\n',
                                                 '            return _code_identity(first) == '
                                                 '_code_identity(second)\n',
                                                 '        equal = True\n',
                                                 '        for name in sorted(dir(first)):\n',
                                                 "            if name.startswith('co_') and name "
                                                 "!= 'co_filename':\n",
                                                 '                value = getattr(first, name)\n',
                                                 '                if not callable(value):\n',
                                                 '                    # Visit every field: later '
                                                 'unsupported constants must fail.\n',
                                                 '                    equal = '
                                                 'constant_equal(value, getattr(second, name)) and '
                                                 'equal\n',
                                                 '        return equal\n',
                                                 '\n',
                                                 '    try:\n',
                                                 '        return code_equal(left, right)\n',
                                                 '    finally:\n',
                                                 '        # Release the recursive closures without '
                                                 'waiting for cyclic collection.\n',
                                                 '        del code_equal, constant_equal\n',
                                                 '\n',
                                                 '\n')),
                                               (774,
                                                775,
                                                ('for _module in (source, guard, '
                                                 "_sibling('affected'), _sibling('cache_key'), "
                                                 'consumer_ledger, station, shared_helpers, '
                                                 'runtime_view, deviation, witness_format, '
                                                 'typed_boundary, conditioned_cubic, '
                                                 'scaled_float32, pr760_stage):\n',),
                                                ('for _module in (source, guard, '
                                                 "_sibling('affected'), _sibling('cache_key'), "
                                                 'consumer_ledger, station, shared_helpers, '
                                                 'runtime_view, deviation, witness_format, '
                                                 'typed_boundary, conditioned_cubic, '
                                                 'scaled_float32, pr760_stage, '
                                                 'pr780_successor):\n',)),
                                               (823,
                                                834,
                                                (),
                                                ("    compare = globals().get('_code_equal')\n",
                                                 '    require(type(compare) is types.FunctionType '
                                                 'and compare.__globals__ is globals()\n',
                                                 '            and compare.__defaults__ is None and '
                                                 'compare.__kwdefaults__ is None\n',
                                                 "            and '__wrapped__' not in "
                                                 'compare.__dict__,\n',
                                                 "            'executing code comparison helper "
                                                 "changed')\n",
                                                 '    compare_code = compare.__code__\n',
                                                 '    require(_code_identity(compare_code) == '
                                                 '_code_identity(\n',
                                                 '                '
                                                 "_IMPORT_CODE[str(_SELF_PATH)]['_code_equal']),\n",
                                                 "            'executing code comparison helper "
                                                 "changed')\n",
                                                 '    # Later mutation of the live function must '
                                                 'not replace this captured code.\n',
                                                 '    compare = types.FunctionType(compare_code, '
                                                 'globals())\n')),
                                               (838,
                                                839,
                                                ('               vars(scaled_float32), '
                                                 'vars(pr760_stage))\n',),
                                                ('               vars(scaled_float32), '
                                                 'vars(pr760_stage), vars(pr780_successor))\n',)),
                                               (859,
                                                860,
                                                ('                    require(actual is not None '
                                                 'and _code_identity(actual) == '
                                                 '_code_identity(code),\n',),
                                                ('                    require(actual is not None '
                                                 'and compare(actual, code),\n',)),
                                               (866,
                                                867,
                                                ('                require(actual is not None and '
                                                 '_code_identity(actual) == '
                                                 '_code_identity(expected),\n',),
                                                ('                require(actual is not None and '
                                                 'compare(actual, expected),\n',)),
                                               (877,
                                                878,
                                                (),
                                                ('    pr780_successor.verify_data()\n',)),
                                               (3540,
                                                3543,
                                                (),
                                                ('    extension = '
                                                 "pr780_successor._data_snapshot()['edges'].get(path)\n",
                                                 '    if extension is not None and sha(text) == '
                                                 "extension['after_sha256']:\n",
                                                 '        text = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 "text.encode('utf-8')).decode('utf-8')\n")),
                                               (3631,
                                                3634,
                                                (),
                                                ('    extension = '
                                                 "pr780_successor._data_snapshot()['edges'].get(path)\n",
                                                 '    if edge is None and extension is None:\n',
                                                 '        return text\n')),
                                               (3635,
                                                3636,
                                                ('        return text\n',),
                                                ('        edge = extension\n',)),
                                               (3652,
                                                3657,
                                                ('        new_endpoint = path in '
                                                 'pr760_stage.CARLA_REGISTRY_PATHS and '
                                                 'source.token_sha256(text) == '
                                                 "edge['after_token_sha256']\n",
                                                 '        if not (new_endpoint or '
                                                 'typed_boundary.is_current(path, text) or\n'),
                                                ('        extended = (extension is not None and\n',
                                                 '            source.token_sha256(text) == '
                                                 "extension['after_token_sha256'])\n",
                                                 '        new_endpoint = path in '
                                                 'pr760_stage.CARLA_REGISTRY_PATHS and (extended '
                                                 'or\n',
                                                 '            source.token_sha256(text) == '
                                                 "edge['after_token_sha256'])\n",
                                                 '        if not (extended or new_endpoint or '
                                                 'typed_boundary.is_current(path, text) or\n')),
                                               (3661,
                                                3663,
                                                ('        require((sha(raw) == '
                                                 "edge['after_sha256']) if new_endpoint else "
                                                 'typed_boundary.is_current(path, raw),\n',),
                                                ('        require((sha(raw) == '
                                                 "extension['after_sha256']) if extended else\n",
                                                 '                (sha(raw) == '
                                                 "edge['after_sha256']) if new_endpoint else "
                                                 'typed_boundary.is_current(path, raw),\n')),
                                               (4028,
                                                4029,
                                                (),
                                                ('    extensions = '
                                                 "pr780_successor._data_snapshot()['edges']\n",)),
                                               (4032,
                                                4035,
                                                ('                   source.token_sha256(text) == '
                                                 "pr760_stage.EDGES[p]['after_token_sha256'])}\n",),
                                                ('                   source.token_sha256(text) == '
                                                 "pr760_stage.EDGES[p]['after_token_sha256'])\n",
                                                 '               or (p in extensions and '
                                                 'source.token_sha256(text) ==\n',
                                                 '                   '
                                                 "extensions[p]['after_token_sha256'])}\n")),
                                               (4158,
                                                4160,
                                                ('            projected = '
                                                 '(pr760_stage.predecessor_source(path, '
                                                 "current.decode('utf-8'))\n",),
                                                ('            retained = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'current)\n',
                                                 '            projected = '
                                                 '(pr760_stage.predecessor_source(path, '
                                                 "retained.decode('utf-8'))\n")),
                                               (4162,
                                                4163,
                                                ('                if qualification else '
                                                 "current.decode('utf-8'))\n",),
                                                ('                if qualification else '
                                                 "retained.decode('utf-8'))\n",)),
                                               (4166,
                                                4167,
                                                ('            if current_image and (path in '
                                                 'pr760_stage.EXAMPLE_PATHS or qualification):\n',),
                                                ('            if current_image and (path in '
                                                 'pr760_stage.EXAMPLE_PATHS or qualification or '
                                                 'current != retained):\n',)),
                                               (4286,
                                                4289,
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
                                               (4293,
                                                4294,
                                                ('    return '
                                                 "{'tools/carla_lane_oracle/test_pr776_input_successors.py': "
                                                 "'af0d9aff27b4f06ce8b102979825d84c177ec78b349dbbb1de4a98423c03f132',\n",),
                                                ('    return '
                                                 "{'tools/carla_lane_oracle/test_pr776_input_successors.py': "
                                                 "'148a021e1d8173122f231f4e6839d4dfd7bb2bb14d76d70e3725ff310620d2aa',\n",)),
                                               (4302,
                                                4303,
                                                ('    """Recover exact earlier comparison bytes '
                                                 'for five named PR776 inputs.\n',),
                                                ('    """Recover exact earlier comparison bytes '
                                                 'for six named PR776 inputs.\n',)),
                                               (4311,
                                                4314,
                                                (),
                                                ('    extension = '
                                                 "pr780_successor._data_snapshot()['edges'].get(path)\n",
                                                 '    if extension is not None and sha(raw) == '
                                                 "extension['after_sha256']:\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(path, raw)\n')),
                                               (4695,
                                                4696,
                                                ('                                                          '
                                                 "'1c1565c05cb702df67319cb69641f83c8a761d38ccf06a11de91b037dfe5b1ce',\n",),
                                                ('                                                          '
                                                 "'6df971f2bf09c710a4e6ababc6adeea8995fd2e86c3e6866e548d5b193ae3669',\n",)),
                                               (4697,
                                                4698,
                                                ('                                                            '
                                                 '128,\n',),
                                                ('                                                            '
                                                 '129,\n',)),
                                               (4714,
                                                4717,
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\'):\\n",\n',),
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\',\\n",\n',
                                                 '                                                             '
                                                 "'                        '\n",
                                                 '                                                             '
                                                 '"\'tools/carla_lane_oracle/test_typed_boundary_contracts.py\'):\\n",\n')),
                                               (4723,
                                                4725,
                                                ('                                                           '
                                                 '(239,\n',
                                                 '                                                            '
                                                 '243,\n'),
                                                ('                                                           '
                                                 '(240,\n',
                                                 '                                                            '
                                                 '245,\n')),
                                               (4730,
                                                4731,
                                                ('                                                             '
                                                 "'raw) if path ==\\n',\n",),
                                                ('                                                             '
                                                 "'raw) if path in (\\n',\n",)),
                                               (4732,
                                                4735,
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
                                               (4751,
                                                4762,
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
                                                 "('                if path == '\n",
                                                 '                                                                 '
                                                 '"\'tools/compile_fail_expectations.json\':\\n",\n',
                                                 '                                                                 '
                                                 "'                    raw = '\n",
                                                 '                                                                 '
                                                 "'audit.pr776_predecessor_bytes(path, '\n",
                                                 '                                                                 '
                                                 "'raw)\\n')),))}\n")),
                                               (4798,
                                                4801,
                                                (),
                                                ('    extension = '
                                                 "pr780_successor._data_snapshot()['edges'].get(path)\n",
                                                 '    if extension is not None and sha(raw) == '
                                                 "extension['after_sha256']:\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(path, raw)\n')),
                                               (4803,
                                                4806,
                                                (),
                                                ('        raw = pr776_predecessor_bytes(path, '
                                                 'raw)\n',
                                                 '    if (path == '
                                                 "'tools/carla_lane_oracle/test_typed_boundary_contracts.py'\n",
                                                 '            and sha(raw) == '
                                                 "'8dee4d9c4bf42214fb2f10fbdcf71a4ba04398095d8c62a16233ad6fc038fce7'):\n")),
                                               (5398,
                                                5403,
                                                (),
                                                ('    extension_path = '
                                                 "'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py'\n",
                                                 '    extension = '
                                                 "pr780_successor._data_snapshot()['edges'][extension_path]\n",
                                                 '    if (type(raw) is bytes and\n',
                                                 '            sha(raw) == '
                                                 "extension['after_sha256']):\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(extension_path, '
                                                 'raw)\n')),
                                               (5490,
                                                5491,
                                                (),
                                                ('        extension_data = '
                                                 'pr780_successor._data_snapshot()\n',)),
                                               (5492,
                                                5500,
                                                (),
                                                ('        extended_pins = {path: '
                                                 "edge['after_sha256']\n",
                                                 '                         for path, edge in '
                                                 "extension_data['edges'].items()}\n",
                                                 '        require(set(extended_pins) <= '
                                                 'set(expected) | set(_pr776_bound_inputs()),\n',
                                                 "                'PR780 source successor misses a "
                                                 "fixed predecessor')\n",
                                                 '        for path, edge in '
                                                 "extension_data['edges'].items():\n",
                                                 "            require(edge['before_sha256'] == "
                                                 'successor_pins.get(path,\n',
                                                 '                    expected.get(path, '
                                                 '_pr776_bound_inputs().get(path))),\n',
                                                 "                    'PR780 source successor "
                                                 "predecessor join changed: ' + path)\n")),
                                               (5502,
                                                5503,
                                                ('            require(sha(raw) == '
                                                 'successor_pins.get(path, digest),\n',),
                                                ('            require(sha(raw) == '
                                                 'extended_pins.get(path, successor_pins.get(path, '
                                                 'digest)),\n',)),
                                               (5504,
                                                5509,
                                                ('            if path in successor_pins:\n',
                                                 '                prior_inputs[path] = '
                                                 'pr776_predecessor_bytes(path, raw)\n',
                                                 '                require(sha(prior_inputs[path]) '
                                                 '== digest,\n',
                                                 "                        'PR776 successor misses "
                                                 "fixed PR760 input: ' + path)\n"),
                                                ('            retained = '
                                                 'pr780_successor.predecessor_bytes(path, raw)\n',
                                                 '            prior_inputs[path] = '
                                                 '(pr776_predecessor_bytes(path, retained)\n',
                                                 '                                  if path in '
                                                 'successor_pins else retained)\n',
                                                 '            require(sha(prior_inputs[path]) == '
                                                 'digest,\n',
                                                 "                    'PR780/PR776 successor "
                                                 "misses fixed PR760 input: ' + path)\n")),
                                               (5510,
                                                5517,
                                                ('            require(sha(observe(path)) == '
                                                 "digest, 'PR776 bound input changed: ' + "
                                                 'path)\n',),
                                                ('            raw = observe(path)\n',
                                                 '            require(sha(raw) == '
                                                 "extended_pins.get(path, digest), 'PR776 bound "
                                                 "input changed: ' + path)\n",
                                                 '            '
                                                 'require(sha(pr780_successor.predecessor_bytes(path, '
                                                 'raw)) == digest,\n',
                                                 "                    'PR780 successor misses "
                                                 "fixed PR776 input: ' + path)\n",
                                                 '        pr780_successor.verify_sources({path: '
                                                 'image[path] for path in extended_pins})\n',
                                                 '        for path, digest in '
                                                 "extension_data['bound_inputs'].items():\n",
                                                 '            require(sha(observe(path)) == '
                                                 "digest, 'PR780 bound input changed: ' + "
                                                 'path)\n')),
                                               (5533,
                                                5535,
                                                ('                              if path == '
                                                 "'tools/carla_lane_oracle/test_witness_format_contracts.py' "
                                                 "else image[path].decode('utf-8'))\n",),
                                                ('                              if path == '
                                                 "'tools/carla_lane_oracle/test_witness_format_contracts.py'\n",
                                                 '                              else '
                                                 'prior_inputs.get(path, '
                                                 "image[path]).decode('utf-8'))\n")),
                                               (5550,
                                                5551,
                                                ('        helper_texts = {path: previous.get(path, '
                                                 "image[path].decode('utf-8'))\n",),
                                                ('        helper_texts = {path: previous.get(path, '
                                                 'prior_inputs.get(path, '
                                                 "image[path]).decode('utf-8'))\n",)))},
 'coverage_loop_proofs.py': {'before_sha256': '21e3a9637a69c6abbf27e9c8dd193a1addf7ed8537dd8f2734c35ff1a468304d',
                             'after_sha256': 'fbef0f009324c4303392e6964b85574ab576de31c01b404c37bcedcd21f61f7f',
                             'edits': ((1177,
                                        1191,
                                        (),
                                        ('# PR780 changes six imported helpers, but leaves '
                                         'density, groom, their tests,\n',
                                         '# and every theorem coordinate unchanged. Retain the '
                                         'complete PR760 closure\n',
                                         '# above and admit only this exact local successor '
                                         'cohort. The broader CARLA\n',
                                         '# successor is not a premise for these four local '
                                         'domination theorems.\n',
                                         'DENSITY780_DEPENDENCY_SHA256 = {\n',
                                         "    'core/extent.mojo': "
                                         "'90490706baa17456a3ec99374c2a00f72768a0178b4e56436571ab4ca673f068',\n",
                                         "    'geometries/surface.mojo': "
                                         "'deeba40777e10da75651f07b8d8f86abb609d4c916b098f1dc28be228f20d3cd',\n",
                                         "    'loaders/bytes.mojo': "
                                         "'139ca1cb876bdf7b0a7c258d1d3a40375d8f3b73c75af160e26e07e7c9ba062a',\n",
                                         "    'math/matrix4.mojo': "
                                         "'1e72ab51f9dbcee3af4c2bfe9da93946616736bf02f4b20e2160ee7b69b448fa',\n",
                                         "    'math/square_matrix.mojo': "
                                         "'f1b2e67489949b53594b5f06604a0227260fd961df2fdebe5347d91c82d99a69',\n",
                                         "    'math/vector4.mojo': "
                                         "'db774733a27a706e5d5c940c4533de2c567d7d6ece3c918215052bccfd87b9aa',\n",
                                         '}\n',
                                         '\n',
                                         '\n')),
                                       (1197,
                                        1210,
                                        (),
                                        ('\n',
                                         '\n',
                                         'def _density780_dependencies():\n',
                                         '    """Snapshot only the six exact local successor '
                                         'endpoints from live data."""\n',
                                         '    declared = '
                                         "globals().get('DENSITY780_DEPENDENCY_SHA256')\n",
                                         '    if type(declared) is not dict:\n',
                                         "        raise ValueError('Invalid density dependency "
                                         "successor namespace')\n",
                                         '    dependencies = dict(declared)\n',
                                         '    if (any(type(name) is not str or type(digest) is not '
                                         'str\n',
                                         '            for name, digest in dependencies.items())\n',
                                         '            or sha256(canonical(dependencies)) != '
                                         "'e58c79dd871f936c9ec0ad0488408d0635d93d6b451a379e844b2ca07ead972b'):\n",
                                         "        raise ValueError('Unreviewed density dependency "
                                         "successor endpoints')\n",
                                         '    return dependencies\n')),
                                       (1249,
                                        1267,
                                        ('        snapshots = {}\n',),
                                        ('        # The generated receipt authenticates its direct '
                                         'producer, not every\n',
                                         '        # live helper. Bind this new authority reader to '
                                         'physical tool code.\n',
                                         '        filename = str(Path(__file__).resolve())\n',
                                         '        checker = Path(filename).read_bytes()\n',
                                         '        if sha256(checker) != ACTIVE_SOURCE_SHA256:\n',
                                         '            return {}\n',
                                         '        expected_reader = '
                                         'cleanup._compiled_functions(checker, '
                                         "filename)['_density780_dependencies']\n",
                                         '        def dependency_pins():\n',
                                         '            live = '
                                         "globals().get('_density780_dependencies')\n",
                                         '            cleanup.require(Path(filename).read_bytes() '
                                         '== checker\n',
                                         '                and type(live) is types.FunctionType\n',
                                         '                and live.__globals__ is globals() and '
                                         'live.__defaults__ is None\n',
                                         '                and live.__kwdefaults__ is None and '
                                         "'__wrapped__' not in live.__dict__\n",
                                         '                and '
                                         'cleanup._code_identity(live.__code__) == '
                                         'cleanup._code_identity(expected_reader),\n',
                                         "                'density dependency successor reader "
                                         "code changed')\n",
                                         '            return live()\n',
                                         '        successor_pins = dependency_pins()\n',
                                         '        snapshots, dependency_sha256, successor = {}, '
                                         '{}, []\n')),
                                       (1270,
                                        1276,
                                        ('            if sha256(value) != expected:\n',),
                                        ('            digest = sha256(value)\n',
                                         '            if name in successor_pins:\n',
                                         '                if digest not in (expected, '
                                         'successor_pins[name]):\n',
                                         '                    return {}\n',
                                         '                successor.append(digest != expected)\n',
                                         '            elif digest != expected:\n')),
                                       (1278,
                                        1281,
                                        (),
                                        ('            dependency_sha256[name] = digest\n',
                                         '        if any(successor) and not all(successor):\n',
                                         '            return {}\n')),
                                       (1321,
                                        1323,
                                        ('        if cleanup.executing_checker_bindings() != '
                                         'executing or not resolver_ok():\n',),
                                        ('        if (cleanup.executing_checker_bindings() != '
                                         'executing or not resolver_ok()\n',
                                         '                or dependency_pins() != '
                                         'successor_pins):\n')),
                                       (1328,
                                        1329,
                                        ("            'proof_id': proof_id, 'dependency_sha256': "
                                         'dict(DENSITY760_INPUTS),\n',),
                                        ("            'proof_id': proof_id, 'dependency_sha256': "
                                         'dict(dependency_sha256),\n',)))}}


def predecessor(name, raw):
    """Compose exact current checkers into the retained 5e91dad comparison."""
    if type(raw) is not bytes:
        raise AssertionError('checker source must be physical builtin bytes')
    if hashlib.sha256(json.dumps(EDGES, sort_keys=True, separators=(',', ':')).encode()).hexdigest() != 'f3eba1aca18c351e17ced3cc450abd3c2f70d191a5babf43de662d1a5e452172':
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
