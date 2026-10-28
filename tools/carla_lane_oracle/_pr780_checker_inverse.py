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

EDGES = {'coverage_loop_proofs.py': {'after_sha256': '74a9689e11eeeb34b9520924a59681346e80986c9ea049c50bec0c538963df21',
                             'before_sha256': '21e3a9637a69c6abbf27e9c8dd193a1addf7ed8537dd8f2734c35ff1a468304d',
                             'edits': ((45,
                                        49,
                                        ('    '
                                         "'tools/coverage_toolchain_identity.py', "
                                         "'tools/coverage_process_group.py',\n",
                                         "    'tools/coverage_hit_aot.py', "
                                         "'tools/coverage_hit_cache.c',\n",
                                         '    '
                                         "'tools/coverage_write_interposer.c', "
                                         "'tools/test_environment.py',\n",
                                         "    'tools/run_suite.py', "
                                         "'Makefile',\n"),
                                        ('    '
                                         "'tools/coverage_toolchain_identity.py',\n",
                                         "    'tools/coverage_hit_aot.mojo', "
                                         "'tools/coverage_hit_cache.c',\n",
                                         '    '
                                         "'tools/coverage_write_interposer.c',\n",
                                         "    'tools/run_suite.mojo', "
                                         "'Makefile',\n")),
                                       (283,
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
                                        1272,
                                        (),
                                        ('# PR780, the Mojo 1.2 port and PR791 '
                                         'change thirteen imported helpers, '
                                         'but\n',
                                         '# leave density, groom, their tests, '
                                         'and every theorem coordinate '
                                         'unchanged.\n',
                                         '# PR843 changes groom and 23 more '
                                         'helpers. Groom refuses a root try or '
                                         'hair\n',
                                         '# step count it cannot finish, '
                                         'before any guide grows. The helpers '
                                         'refuse\n',
                                         '# sizes they cannot hold, take '
                                         'shared fog, tone and texel helpers, '
                                         'or keep\n',
                                         '# Float64 out of a GPU build. Each '
                                         'edit adds a refusal, a helper or a\n',
                                         '# docstring line. A returned groom '
                                         'is still nonempty by '
                                         '`require_hair_roots`,\n',
                                         '# and no counted range changes, so '
                                         'the four rows keep their '
                                         'cardinalities.\n',
                                         '# Groom reaches its guarded '
                                         'predecessor through its PR780 '
                                         'edge.\n',
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
                                         "    'core/fog.mojo': "
                                         "'5fc886a7eb9fdc5e78a9f68bfec300db4d88e95d14c3c6fa8af2add0abfdd342',\n",
                                         '    '
                                         "'core/gaussian_splat_utils.mojo': "
                                         "'596021972df04a9f2b0721de3ae422147b808fd463a99fbf6ece93ea75376d29',\n",
                                         "    'core/geometry_store.mojo': "
                                         "'771d8d8b068353bf23c0f572511c981a2a67c375cfaa2b8c63a5a5ab103a16c3',\n",
                                         "    'core/morph.mojo': "
                                         "'9b16bcef0cd08741f84c1e256965781cb0bbd081ad2a9c37043bb46676b66c3d',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/head/assembly.mojo': "
                                         "'813a09e4b30a5a9682e606cdabb2e22188866f4153318a18f9df62f091c0435e',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/head/hair/groom.mojo': "
                                         "'48a2324a527b58e63546a562e168744656fbc8a02ba8f6c9aa3274b66ebc85e5',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/loft.mojo': "
                                         "'fe36bfbe8b8022fcf37a145368865b5841a194cbb2549a3335bc1f07aaab4e91',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/look.mojo': "
                                         "'662665a1ea3c291b45030fcf90d732b2a7900f0c1a591e4d94d854201e8caa48',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/surface_nets.mojo': "
                                         "'05a7d079446a90673256f9f38529922c861c3c137151edd332195cd00d011e81',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/torso/bones/dimensions.mojo': "
                                         "'7da0adc38b32b78766ec9685c53015e215a814c7eb92b44d0663ee27b188d332',\n",
                                         '    '
                                         "'extensions/humanoid/skeleton/torso/sweep.mojo': "
                                         "'1eb865b559862c5d27371f4ae9e5a576b827eb49f7b2e0906c7e00bee8aa34a1',\n",
                                         '    '
                                         "'geometries/attribute_utils.mojo': "
                                         "'91d45ff588571ab0bbda20331d1f60a0b55e124985a76f8cad97d682bdca523e',\n",
                                         "    'geometries/surface.mojo': "
                                         "'28c95efe56afc7b247ab47ecbf93f595cfa5ccb16c3ca1ed12885daca3069dff',\n",
                                         "    'lights/shadow.mojo': "
                                         "'36394e7969cf0f6a8647011e5d49b057440600004b35fdd97479107def5d0793',\n",
                                         "    'loaders/bytes.mojo': "
                                         "'139ca1cb876bdf7b0a7c258d1d3a40375d8f3b73c75af160e26e07e7c9ba062a',\n",
                                         "    'materials/material.mojo': "
                                         "'a9d7e4f2aa4096a9c768d8bd68a696ddd619bd75da5a2e710136242dbea82ff5',\n",
                                         "    'math/curve.mojo': "
                                         "'d0a404a892191700a00bcda9f5bc92837995d5166c0c953933453e79dcf25c45',\n",
                                         "    'math/curve_checks.mojo': "
                                         "'1c6cf558aaf2102941d874ff9d814423b71fea1a9eb159eae7c549325ee274ff',\n",
                                         "    'math/matrix4.mojo': "
                                         "'1e72ab51f9dbcee3af4c2bfe9da93946616736bf02f4b20e2160ee7b69b448fa',\n",
                                         "    'math/path.mojo': "
                                         "'124ac09790b335df31554c6a7744bf6b49954d2a6faa456632d779409951468f',\n",
                                         "    'math/square_matrix.mojo': "
                                         "'f1b2e67489949b53594b5f06604a0227260fd961df2fdebe5347d91c82d99a69',\n",
                                         "    'math/utils.mojo': "
                                         "'fb4335138e5fe5ec4c1761105343a01996dae1152f3a9e1b2779f62a6323c772',\n",
                                         "    'math/vector4.mojo': "
                                         "'db774733a27a706e5d5c940c4533de2c567d7d6ece3c918215052bccfd87b9aa',\n",
                                         "    'objects/gaussian_splat.mojo': "
                                         "'6b5834369f244c8eaf6a4a6d363bcca7f645a4964f72ddea25df62f63097cf3c',\n",
                                         "    'objects/line_segments2.mojo': "
                                         "'2557d496f1dc49c204314d389bd105c9eaaab4c7762920b7b0d5f97613d4c3cd',\n",
                                         "    'render/css_color.mojo': "
                                         "'c8150acb98edb979bb217d44099dc935f47a5f61128f27ca1a5affe4fec080c9',\n",
                                         "    'render/cube_texture.mojo': "
                                         "'28aac07dfc280acbea10d121c32db300e772cc42de75f43ccab7c3e6cdda3300',\n",
                                         "    'render/cube_uv.mojo': "
                                         "'6fa1910f90bf4ac79240570a2b1a483229f158838fc8bcf884ac2db2cf88c97b',\n",
                                         "    'render/framebuffer.mojo': "
                                         "'c6b8bf7ff701e94efeae63aa0526e564290351519eab9bd33cfc87818f7a34c0',\n",
                                         "    'render/linerule.mojo': "
                                         "'2aa592b2b8e171fd31997c558495ba52228d101c683a48d901417146f6f4aab2',\n",
                                         "    'render/tasks.mojo': "
                                         "'9b80dcaceec958190ade19bff6d106617c8c4c99e80d37eb0205609741ca2934',\n",
                                         "    'render/texture.mojo': "
                                         "'608965e963ad8753c64777ed0b3127dc1c6cf950a3c3156e953c4e72bb02b1d5',\n",
                                         "    'render/volume_texture.mojo': "
                                         "'4887e63a767ffb7cc8c764be1bc8256c2b4589bc149b4486e8a1c7446ac09557',\n",
                                         '}\n',
                                         '\n',
                                         '\n')),
                                       (1278,
                                        1291,
                                        (),
                                        ('\n',
                                         '\n',
                                         'def _density780_dependencies():\n',
                                         '    """Snapshot only the exact local '
                                         'successor endpoints from live '
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
                                         "'04e451c1901d3dec8993c7c620104719ba4750845d6d8e87a1d6a004a4d7bd7b'):\n",
                                         "        raise ValueError('Unreviewed "
                                         'density dependency successor '
                                         "endpoints')\n",
                                         '    return dependencies\n')),
                                       (1297,
                                        1318,
                                        ('    filename = '
                                         "Path(__file__).resolve().parent/'carla_lane_oracle/pr760_arithmetic_stage.py'\n",
                                         '    '
                                         'cleanup.require(Path(stage.__file__).resolve() '
                                         '== filename,\n',
                                         "                    'density inverse "
                                         "executing origin changed')\n",
                                         '    compiled = compile(raw, '
                                         "str(filename), 'exec', "
                                         'dont_inherit=True, '
                                         'optimize=sys.flags.optimize)\n',
                                         '    '
                                         'cleanup.require(cleanup._code_identity(stage._EXECUTED_MODULE_CODE)\n',
                                         '                    == '
                                         'cleanup._code_identity(compiled), '
                                         "'density inverse module code "
                                         "changed')\n",
                                         '    defaults = '
                                         'cleanup._compiled_defaults(raw)\n',
                                         '    for name, expected in '
                                         'cleanup._compiled_functions(raw, '
                                         'str(filename)).items():\n',
                                         "        if name.startswith('<'):\n",
                                         '            continue\n',
                                         '        live = getattr(stage, name, '
                                         'None)\n'),
                                        ('    filename = '
                                         "Path(__file__).resolve().parent/'carla_lane_oracle/pr760_arithmetic_stage.py'\n",
                                         '    '
                                         'cleanup.require(Path(stage.__file__).resolve() '
                                         '== filename,\n',
                                         "                    'density inverse "
                                         "executing origin changed')\n",
                                         '    # Import already compiled this '
                                         'source and compared it with the '
                                         'executing\n',
                                         '    # module. The same bytes and the '
                                         'same code object need no second '
                                         'compile.\n',
                                         '    key = str(filename.resolve())\n',
                                         '    executed = '
                                         'stage._EXECUTED_MODULE_CODE\n',
                                         '    if '
                                         '(cleanup._IMPORT_IDENTITIES.get(key) '
                                         '== cleanup.sha(raw)\n',
                                         '            and '
                                         'cleanup._IMPORT_MODULE_CODE.get(key) '
                                         'is executed):\n',
                                         '        functions = '
                                         'cleanup._IMPORT_CODE[key]\n',
                                         '        defaults = '
                                         'cleanup._IMPORT_DEFAULTS[key]\n',
                                         '    else:\n',
                                         '        compiled = compile(raw, '
                                         "str(filename), 'exec', "
                                         'dont_inherit=True, '
                                         'optimize=sys.flags.optimize)\n',
                                         '        '
                                         'cleanup.require(cleanup._code_identity(executed)\n',
                                         '                        == '
                                         'cleanup._code_identity(compiled), '
                                         "'density inverse module code "
                                         "changed')\n",
                                         '        functions = '
                                         'cleanup._compiled_functions(raw, '
                                         'str(filename))\n',
                                         '        defaults = '
                                         'cleanup._compiled_defaults(raw)\n',
                                         '    for name, expected in '
                                         'functions.items():\n',
                                         "        if name.startswith('<'):\n",
                                         '            continue\n',
                                         '        live = getattr(stage, name, '
                                         'None)\n')),
                                       (1340,
                                        1358,
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
                                       (1361,
                                        1367,
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
                                       (1369,
                                        1384,
                                        (),
                                        ('            dependency_sha256[name] '
                                         '= digest\n',
                                         '        if any(successor) and not '
                                         'all(successor):\n',
                                         '            return {}\n',
                                         '        # The PR843 CSS color '
                                         'successor writes a channel through '
                                         'the\n',
                                         '        # JavaScript number module. '
                                         'Only the complete successor cohort '
                                         'adds\n',
                                         '        # that one exact file to the '
                                         'closure; the historical cohort has '
                                         'none.\n',
                                         '        added = {}\n',
                                         '        if all(successor):\n',
                                         '            for name, expected in '
                                         "(('loaders/js_number.mojo',\n",
                                         '                    '
                                         "'a7f8cd0bdaf91756b5583de24cf27e7d8ee86c7cc91cb68ab2da2dec3bd9b19d'),):\n",
                                         '                value = '
                                         '_coverage_observe_bytes(root, '
                                         'name,\n',
                                         '                    '
                                         'relative_source(root, name, '
                                         '**operation_args).read_bytes(), '
                                         '_operation=_operation)\n',
                                         '                if sha256(value) != '
                                         'expected:\n',
                                         '                    return {}\n',
                                         '                added[name] = '
                                         'value\n')),
                                       (1389,
                                        1391,
                                        ('        if '
                                         'sha256(stage.predecessor_source(groom, '
                                         'snapshots[groom].decode()).encode()) '
                                         '!= '
                                         'GUARDED_LOOP_SOURCE_SHA256[groom]:\n',),
                                        ('        physical_groom = '
                                         'cleanup.pr780_successor.predecessor_bytes(groom, '
                                         'snapshots[groom])\n',
                                         '        if '
                                         'sha256(stage.predecessor_source(groom, '
                                         'physical_groom.decode()).encode()) '
                                         '!= '
                                         'GUARDED_LOOP_SOURCE_SHA256[groom]:\n')),
                                       (1392,
                                        1393,
                                        ('        paths = {name for name in '
                                         'snapshots if '
                                         "name.endswith('.mojo')}\n",),
                                        ('        paths = {name for name in '
                                         "snapshots if name.endswith('.mojo')} "
                                         '| set(added)\n',)),
                                       (1418,
                                        1419,
                                        ('        for name, value in '
                                         'snapshots.items():\n',),
                                        ('        for name, value in '
                                         '(snapshots | added).items():\n',)),
                                       (1425,
                                        1427,
                                        ('        if '
                                         'cleanup.executing_checker_bindings() '
                                         '!= executing or not '
                                         'resolver_ok():\n',),
                                        ('        if '
                                         '(cleanup.executing_checker_bindings() '
                                         '!= executing or not resolver_ok()\n',
                                         '                or dependency_pins() '
                                         '!= successor_pins):\n')),
                                       (1432,
                                        1433,
                                        ("            'proof_id': proof_id, "
                                         "'dependency_sha256': "
                                         'dict(DENSITY760_INPUTS),\n',),
                                        ("            'proof_id': proof_id, "
                                         "'dependency_sha256': "
                                         'dict(dependency_sha256),\n',)),
                                       (1496,
                                        1497,
                                        ('        '
                                         "'5cc066092d9b0302c60a6676459efc855e220dc319d1f88b5eb84df768f489f9',\n",),
                                        ('        '
                                         "'990d94c815315c910b12c1b126c076183fc35cdeb9f64a26d1f7e574f424bccd',\n",)),
                                       (1498,
                                        1519,
                                        (),
                                        ('\n',
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
                                         "'c08275ccfea2f32dd84dc5ad54205052f6dfd216104836c858ff259224426332',\n",
                                         '}, 4049)\n',
                                         '\n',
                                         '\n',
                                         '# PR843 adds texel helpers to the '
                                         'imports and a line to a docstring '
                                         'above the\n',
                                         '# cap loop, which moves it seven '
                                         'lines down, and refuses a dash count '
                                         'past an\n',
                                         '# integer in the producer. '
                                         '`cap_steps` and its two-to-64 clamp '
                                         'are unchanged.\n',
                                         'STRAND_CAP_GUARDED_SUCCESSOR = ({\n',
                                         '    '
                                         '**STRAND_CAP_SPLAT_WORKERS_SUCCESSOR[0],\n',
                                         "    'renderers/renderer.mojo':\n",
                                         '        '
                                         "'7fcdce220f3420c7a7739c0419d8af1087a06f79343a9f86cac4f8313fa6fa18',\n",
                                         "    'objects/line_segments2.mojo':\n",
                                         '        '
                                         "'2557d496f1dc49c204314d389bd105c9eaaab4c7762920b7b0d5f97613d4c3cd',\n",
                                         '}, 4056)\n')),
                                       (1569,
                                        1574,
                                        ('        if actual == '
                                         'STRAND_CAP_FORMATTED_SUCCESSOR[0]:\n',),
                                        ('        if actual == '
                                         'STRAND_CAP_GUARDED_SUCCESSOR[0]:\n',
                                         '            line = '
                                         'STRAND_CAP_GUARDED_SUCCESSOR[1]\n',
                                         '        elif actual == '
                                         'STRAND_CAP_SPLAT_WORKERS_SUCCESSOR[0]:\n',
                                         '            line = '
                                         'STRAND_CAP_SPLAT_WORKERS_SUCCESSOR[1]\n',
                                         '        elif actual == '
                                         'STRAND_CAP_FORMATTED_SUCCESSOR[0]:\n')),
                                       (1703,
                                        1705,
                                        ('        if typed.is_current(name, '
                                         'raw):\n',),
                                        ('        endpoint = '
                                         '_typed_endpoint(name, raw)\n',
                                         '        if typed.is_current(name, '
                                         'endpoint):\n')),
                                       (1715,
                                        1716,
                                        ('            checked = '
                                         'typed.historical_source(name, '
                                         "raw.decode('utf-8'))\n",),
                                        ('            checked = '
                                         'typed.historical_source(name, '
                                         "endpoint.decode('utf-8'))\n",)),
                                       (1912,
                                        1913,
                                        ('            if '
                                         'typed.is_current(name, current):\n',),
                                        ('            if '
                                         'typed.is_current(name, '
                                         '_typed_endpoint(name, '
                                         'current)):\n',)),
                                       (1922,
                                        1923,
                                        ('        if (typed.is_current(name, '
                                         'current) and _operation is None\n',),
                                        ('        if (typed.is_current(name, '
                                         '_typed_endpoint(name, current)) and '
                                         '_operation is None\n',)),
                                       (1957,
                                        1960,
                                        (),
                                        ('        if not typed_current:\n',
                                         '            typed_current = '
                                         'typed.is_current(\n',
                                         '                module_path, '
                                         '_typed_endpoint(module_path, '
                                         'current))\n')),
                                       (2181,
                                        2182,
                                        ('            or not '
                                         'typed.is_current(name, '
                                         'current)):\n',),
                                        ('            or not '
                                         'typed.is_current(name, '
                                         '_typed_endpoint(name, '
                                         'current))):\n',)),
                                       (2244,
                                        2245,
                                        ('        if typed.is_current(name, '
                                         'current):\n',),
                                        ('        if typed.is_current(name, '
                                         '_typed_endpoint(name, '
                                         'current)):\n',)),
(2442,
 2556,
 (
  'def generation_checkpoint(root, build, compiler, flags, mojo, sources):\n',
  '    root, build = Path(root).resolve(), Path(build).resolve()\n',
  '    names = list(sources)\n',
  '    if not names or len(names) != len(set(names)):\n',
  "        raise ValueError('Generation requires distinct source identities')\n",
  '    for name in names:\n',
  "        if not name.endswith('.mojo'):\n",
  "            raise ValueError('Generation source must be a Mojo module')\n",
  '        relative_source(root, name)\n',
  "    return {'schema': 'coverage-generation-v1', 'root_inputs': maintained_inputs(root, exclude=build),\n",
  "            'python': sys.version, 'compiler': compiler, 'flags': flags,\n",
  "            'compiler_command': _command_identity(mojo or ['.venv/bin/mojo'], root, build),\n",
  "            'producer_arguments': ['run', *shlex.split(flags), 'coverage/build_cli.mojo', '@BUILD@', *names],\n",
  "            'sources': names}\n",
  '\n',
  '\n',
  'def begin_generation(root, build, compiler, flags, *, mojo=None, sources):\n',
  '    """Checkpoint before loading/compiling the trusted producer, never after."""\n',
  '    build = Path(build)\n',
  '    build.mkdir(parents=True, exist_ok=True)\n',
  "    (build / 'origins.ready').write_bytes(b'')\n",
  "    path = build / 'generation-inputs.json'\n",
  '    path.unlink(missing_ok=True)\n',
  '    checkpoint = generation_checkpoint(root, build, compiler, flags, mojo, sources)\n',
  "    path.write_bytes(canonical(checkpoint) + b'\\n')\n",
  '    return checkpoint\n',
  '\n',
 ),
 (
  'def _mojo_command(mojo):\n',
  '    """Return the producer command text for the checkpoint program.\n',
  '\n',
  '    Args:\n',
  '        mojo: A command string, a word list, or none.\n',
  '\n',
  '    Returns:\n',
  '        The command text. None selects `.venv/bin/mojo`.\n',
  '    """\n',
  '    if mojo is None:\n',
  "        return '.venv/bin/mojo'\n",
  '    if isinstance(mojo, str):\n',
  '        return mojo\n',
  '    return shlex.join(str(word) for word in mojo)\n',
  '\n',
  '\n',
  'def _run_coverage_begin(root, build, compiler, flags, mojo, sources):\n',
  '    """Ask Mojo for one generation checkpoint and return that document.\n',
  '\n',
  '    Args:\n',
  '        root: The repository root.\n',
  '        build: The build directory. The program writes the checkpoint here.\n',
  '        compiler: The compiler text.\n',
  '        flags: The flag text.\n',
  '        mojo: The producer command.\n',
  '        sources: The module names, in command order.\n',
  '\n',
  '    Returns:\n',
  '        The checkpoint document.\n',
  '\n',
  '    Raises:\n',
  '        ValueError: The checkpoint program rejects the inputs.\n',
  '    """\n',
  '    import subprocess\n',
  '    repo = Path(__file__).resolve().parents[1]\n',
  "    program = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))\n",
  '    command = [\n',
  "        'sh', str(repo / 'tools' / 'tool.sh'), program, 'coverage_loop_begin',\n",
  "        '--root', str(root), '--build', str(build),\n",
  "        '--compiler', compiler, '--flags', flags,\n",
  "        '--mojo', _mojo_command(mojo), '--sources',\n",
  '        *[str(name) for name in sources],\n',
  '    ]\n',
  '    result = subprocess.run(command, capture_output=True, text=True)\n',
  '    if result.returncode != 0:\n',
  '        errors = [line.strip() for line in result.stderr.splitlines()\n',
  "                  if line.strip() and 'Crashpad' not in line]\n",
  '        message = errors[-1] if errors else result.stdout.strip()\n',
  "        prefix = 'coverage_loop_begin: '\n",
  '        if message.startswith(prefix):\n',
  '            message = message[len(prefix):]\n',
  '        raise ValueError(message)\n',
  "    text = (Path(build) / 'generation-inputs.json').read_bytes()\n",
  "    if not text.endswith(b'\\n'):\n",
  "        raise ValueError('Missing generation checkpoint')\n",
  '    return json.loads(text[:-1])\n',
  '\n',
  '\n',
  'def generation_checkpoint(root, build, compiler, flags, mojo, sources):\n',
  '    """Return the generation checkpoint without keeping the program\'s writes.\n',
  '\n',
  '    Args:\n',
  '        root: The repository root.\n',
  '        build: The build directory used to exclude staged files.\n',
  '        compiler: The compiler text.\n',
  '        flags: The flag text.\n',
  '        mojo: The producer command.\n',
  '        sources: The module names, in command order.\n',
  '\n',
  '    Returns:\n',
  '        The checkpoint document.\n',
  '\n',
  '    Raises:\n',
  '        ValueError: The checkpoint program rejects the inputs.\n',
  '    """\n',
  '    root, build = Path(root).resolve(), Path(build).resolve()\n',
  "    ready = build / 'origins.ready'\n",
  "    path = build / 'generation-inputs.json'\n",
  '    saved_ready = ready.read_bytes() if ready.is_file() else None\n',
  '    saved_json = path.read_bytes() if path.is_file() else None\n',
  '    try:\n',
  '        return _run_coverage_begin(root, build, compiler, flags, mojo, sources)\n',
  '    finally:\n',
  '        if saved_ready is None:\n',
  '            if ready.exists():\n',
  '                ready.unlink()\n',
  '        else:\n',
  '            ready.write_bytes(saved_ready)\n',
  '        if saved_json is None:\n',
  '            if path.exists():\n',
  '                path.unlink()\n',
  '        else:\n',
  '            path.write_bytes(saved_json)\n',
  '\n',
  '\n',
  'def begin_generation(root, build, compiler, flags, *, mojo=None, sources):\n',
  '    """Checkpoint before loading/compiling the trusted producer, never after.\n',
  '\n',
  '    Args:\n',
  '        root: The repository root.\n',
  '        build: The build directory.\n',
  '        compiler: The compiler text.\n',
  '        flags: The flag text.\n',
  '        mojo: The producer command. None selects `.venv/bin/mojo`.\n',
  '        sources: The module names, in command order.\n',
  '\n',
  '    Returns:\n',
  '        The checkpoint document.\n',
  '\n',
  '    Raises:\n',
  '        ValueError: The checkpoint program rejects the inputs.\n',
  '    """\n',
  '    return _run_coverage_begin(root, build, compiler, flags, mojo, sources)\n',
  '\n',
 )),
                                       (2578,
                                        2578,
                                        ('    runner = '
                                         "(['@ROOT@/tools/native_test_support.py', "
                                         "'run'] if profile == 'raw'\n",
                                         '              else '
                                         "['@ROOT@/tools/coverage_hit_aot.py', "
                                         "'--profile', profile])\n"),
                                        ()),
                                       (2579,
                                        2589,
                                        ('    return '
                                         "[contract['python']['path'], "
                                         "*runner, '--root', '@BUILD@',\n",),
                                        ("    if profile == 'raw':\n",
                                         '        # `tools/tool.sh` is inside '
                                         'the repository, so its sealed path '
                                         'does\n',
                                         '        # not depend on where `sh` '
                                         'lives. The cached program starts at '
                                         'once\n',
                                         '        # after the first build.\n',
                                         '        return '
                                         "['@ROOT@/tools/tool.sh', *compiler, "
                                         "'native_test_support', 'run',\n",
                                         "                '--root', '@BUILD@', "
                                         "'--suite', '@BUILD@/' + suite,\n",
                                         "                '--cache', "
                                         "contract['cache'], '--',\n",
                                         "                *compiler, 'run', "
                                         "'-I', '@BUILD@', '@BUILD@/' + "
                                         'suite]\n',
                                         "    return ['@ROOT@/tools/tool.sh', "
                                         "*compiler, 'coverage_hit_aot',\n",
                                         "            '--profile', profile, "
                                         "'--root', '@BUILD@',\n")),
                                       (2705,
                                        2722,
                                        ("        'execution': "
                                         'execution_contract(root, build, '
                                         'inputs, mojo=mojo,\n',
                                         '                                        '
                                         'capture_cache=capture_cache, '
                                         'suites=suites)}\n',
                                         '    cleanup = None\n',
                                         '    if '
                                         "importlib.util.find_spec('carla_lane_oracle') "
                                         'is None:\n',
                                         '        # Standalone plain receipts '
                                         'need no CARLA semantic authority. A '
                                         'known\n',
                                         '        # reviewed source may never '
                                         'silently become a plain-only '
                                         'receipt.\n',
                                         '        reviewed_modules = '
                                         '(set(REVIEWED_LOOP_RULES)\n',
                                         '                            | '
                                         '{row[0] for row in '
                                         'GUARDED_LOOP_RULES}\n',
                                         '                            | '
                                         "{'renderers/renderer', "
                                         "'extensions/carla/map',\n",
                                         '                               '
                                         "DENSITY_SOURCE.removesuffix('.mojo')})\n",
                                         '        if reviewed_modules & '
                                         "{name.removesuffix('.mojo') for name "
                                         "in generation['modules']}:\n",
                                         '            raise '
                                         "ValueError('Reviewed loop authority "
                                         "is unavailable')\n",
                                         '    else:\n',
                                         '        # A present but broken '
                                         'authority installation is an error, '
                                         'not fallback.\n',
                                         '        from carla_lane_oracle '
                                         'import full_audit_cleanup_contracts '
                                         'as cleanup\n',
                                         '    _plain_seed = '
                                         'canonical(_receipt_seed) if cleanup '
                                         'is None else None\n'),
                                        ("        'execution': "
                                         'execution_contract(root, build, '
                                         'inputs, mojo=mojo,\n',
                                         '                                        '
                                         'capture_cache=capture_cache, '
                                         'suites=suites)}\n',
                                         '    cleanup = None\n',
                                         '    # Standalone plain receipts need '
                                         'no CARLA semantic authority. A '
                                         'known\n',
                                         '    # reviewed source may never '
                                         'silently become a plain-only '
                                         'receipt.\n',
                                         '    reviewed_modules = '
                                         '(set(REVIEWED_LOOP_RULES)\n',
                                         '                        | {row[0] '
                                         'for row in GUARDED_LOOP_RULES}\n',
                                         '                        | '
                                         "{'renderers/renderer', "
                                         "'extensions/carla/map',\n",
                                         '                           '
                                         "DENSITY_SOURCE.removesuffix('.mojo')})\n",
                                         '    needs_authority = '
                                         'bool(reviewed_modules & {\n',
                                         "        name.removesuffix('.mojo') "
                                         'for name in '
                                         "generation['modules']})\n",
                                         '    if needs_authority and '
                                         "importlib.util.find_spec('carla_lane_oracle') "
                                         'is None:\n',
                                         "        raise ValueError('Reviewed "
                                         "loop authority is unavailable')\n",
                                         '    if needs_authority:\n',
                                         '        # A present but broken '
                                         'authority installation is an error, '
                                         'not fallback.\n',
                                         '        from carla_lane_oracle '
                                         'import full_audit_cleanup_contracts '
                                         'as cleanup\n',
                                         '    _plain_seed = '
                                         'canonical(_receipt_seed) if cleanup '
                                         'is None else None\n')),
(2789,
 2832,
 (
  'def _load_json(path):\n',
  '    def pairs(items):\n',
  '        result = {}\n',
  '        for key, value in items:\n',
  '            if key in result:\n',
  "                raise ValueError('Duplicate receipt key: ' + key)\n",
  '            result[key] = value\n',
  '        return result\n',
  "    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=pairs)\n",
  '\n',
  '\n',
 ),
 (
  '_GATED_RECEIPT_KEYS = None\n',
  '\n',
  '\n',
  'def _refuse_duplicate_receipt_keys(text):\n',
  '    """Refuse a repeated receipt key before the document is parsed.\n',
  '\n',
  '    The same text is not checked again. A changed text is checked again.\n',
  '    A failed check is not kept.\n',
  '    """\n',
  '    global _GATED_RECEIPT_KEYS\n',
  '    if _GATED_RECEIPT_KEYS == text:\n',
  '        return\n',
  '    import os\n',
  '    import subprocess\n',
  '    import tempfile\n',
  '    root = Path(__file__).resolve().parents[1]\n',
  "    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))\n",
  "    with tempfile.TemporaryDirectory(prefix='receipt-keys-') as directory:\n",
  "        target = Path(directory) / 'receipt.json'\n",
  "        target.write_text(text, encoding='utf-8')\n",
  '        result = subprocess.run(\n',
  "            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'receipt_keys',\n",
  "             str(target)],\n",
  '            capture_output=True, text=True)\n',
  '    if result.returncode != 0:\n',
  '        lines = [line.strip() for line in result.stderr.splitlines()\n',
  "                 if line.strip() and 'Crashpad' not in line]\n",
  '        message = lines[-1] if lines else result.stdout.strip()\n',
  "        prefix = 'coverage_io: '\n",
  '        if message.startswith(prefix):\n',
  '            message = message[len(prefix):]\n',
  "        if message.startswith('Duplicate receipt key:'):\n",
  '            raise ValueError(message)\n',
  '        return\n',
  '    _GATED_RECEIPT_KEYS = text\n',
  '\n',
  '\n',
  'def _load_json(path):\n',
  "    text = Path(path).read_text(encoding='utf-8')\n",
  '    _refuse_duplicate_receipt_keys(text)\n',
  '    return json.loads(text)\n',
  '\n',
  '\n',
 )),
(2860,
 2906,
 (
  'def masked_manifest(raw, envelope):\n',
  '    """Preserve all original entries except the explicit outcome masks."""\n',
  "    receipt = envelope['receipt']\n",
  "    if sha256(raw) != receipt['manifest_sha256']:\n",
  "        raise ValueError('Loop-proof manifest binding mismatch')\n",
  '    manifest_records(raw)\n',
  "    masks = {(proof['module'], str(proof['line'])): proof for proof in receipt['proofs']}\n",
  "    rows = ['P ' + SCHEMA + ' ' + envelope['sha256']]\n",
  '    used = set()\n',
  "    for line in raw.decode('utf-8').splitlines():\n",
  '        fields = line.split()\n',
  '        key = tuple(fields[1:3])\n',
  "        if fields and fields[0] == 'B' and key in masks:\n",
  '            proof = masks[key]\n',
  "            line = ' '.join(['R', *key, proof['required'], proof['kind'], str(proof['cardinality'])])\n",
  '            used.add(key)\n',
  '        rows.append(line)\n',
  '    if used != set(masks):\n',
  "        raise ValueError('Loop proof does not identify one original branch')\n",
  "    return ('\\n'.join(rows) + '\\n').encode('utf-8')\n",
  '\n',
 ),
 (
  '_GATED_MASK = None\n',
  '\n',
  '\n',
  'def masked_manifest(raw, envelope):\n',
  '    """Preserve all original entries except the explicit outcome masks.\n',
  '\n',
  '    The same manifest and envelope are not masked again. A changed input\n',
  '    is masked again. A failed mask is not kept.\n',
  '\n',
  '    Args:\n',
  '        raw: The original manifest bytes.\n',
  '        envelope: The receipt envelope.\n',
  '\n',
  '    Returns:\n',
  '        The masked manifest bytes.\n',
  '\n',
  '    Raises:\n',
  '        ValueError: The manifest or a proof does not match.\n',
  '    """\n',
  '    global _GATED_MASK\n',
  '    key = (raw, canonical(envelope))\n',
  '    cached = _GATED_MASK\n',
  '    if cached is not None and cached[0] == key:\n',
  '        return cached[1]\n',
  '    import subprocess\n',
  '    import tempfile\n',
  '    root = Path(__file__).resolve().parents[1]\n',
  "    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))\n",
  "    with tempfile.TemporaryDirectory(prefix='coverage-mask-') as directory:\n",
  '        folder = Path(directory)\n',
  "        manifest = folder / 'manifest.txt'\n",
  "        payload = folder / 'envelope.json'\n",
  '        manifest.write_bytes(raw)\n',
  "        payload.write_text(json.dumps(envelope), encoding='utf-8')\n",
  '        result = subprocess.run(\n',
  "            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'coverage_mask',\n",
  '             str(manifest), str(payload)],\n',
  '            capture_output=True)\n',
  '    if result.returncode != 0:\n',
  '        errors = [line.strip() for line in result.stderr.splitlines()\n',
  "                  if line.strip() and b'Crashpad' not in line]\n",
  '        message = (errors[-1] if errors else result.stdout).decode()\n',
  '        raise ValueError(message)\n',
  '    _GATED_MASK = (key, result.stdout)\n',
  '    return result.stdout\n',
  '\n',
 )))},
 'full_audit_cleanup_contracts.py': {'after_sha256': 'fedd18390f00d54fc4a892bd179730d38bc2dc796d9c1645a4f6d67044aab8aa',
                                     'before_sha256': 'f62dbe69ddd5d15bd79aa4b0a8237d9475fe1a00cea06c2f7124c59af237c833',
                                     'edits': ((11,
                                                12,
                                                (),
                                                ('from contextvars import '
                                                 'ContextVar\n',)),
                                               (57,
                                                58,
                                                (),
                                                ('        from . import '
                                                 'pr780_source_successor as '
                                                 'pr780_successor\n',)),
                                               (72,
                                                73,
                                                (),
                                                ('        import '
                                                 'pr780_source_successor as '
                                                 'pr780_successor\n',)),
                                               (161,
                                                162,
                                                (),
                                                (' '
                                                 "'tools/carla_lane_oracle/pr780_source_successor.py': "
                                                 "'3d3452a0659002ccf4aeca7e4282c2a4686f2df269f62ceb1e9a92d454c97ae5',\n",)),
                                               (163,
                                                164,
                                                (" 'tools/affected.py': "
                                                 "'a56194a3e722ad341a42f3defec282b8154f5e4db8340df855f0199ea9830ebb',\n",),
                                                (" 'tools/affected.py': "
                                                 "'dcf533b9cd995902f53578aa93b98a32ca732643ccfa6ab7e30f95fd8b321eb3',\n",)),
                                               (169,
                                                170,
                                                (" 'tools/carla_lane_oracle/runtime_view_contracts.py': "
                                                 "'67316129402fac643be3c6e49ceef94bcb25c1ef92f81fd764a6abb583f89e34',\n",),
                                                (" 'tools/carla_lane_oracle/runtime_view_contracts.py': "
                                                 "'7bdf5dad517fd43f6de3559fec188c15e12e1a52dfad4a594d2b93df221d9a51',\n",)),
                                               (171,
                                                172,
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',\n",),
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'f4cf5b03da59b5a5070f9cdf8e26b486d4e1cd965eed172578018619ea788afe',\n",)),
                                               (251,
                                                253,
                                                ('                 '
                                                 "'tools/carla_lane_oracle/pr760_arithmetic_stage.py')\n",),
                                                ('                 '
                                                 "'tools/carla_lane_oracle/pr760_arithmetic_stage.py',\n",
                                                 '                 '
                                                 "'tools/carla_lane_oracle/pr780_source_successor.py')\n")),
                                               (562,
                                                563,
                                                ('        record = json.loads(raw, object_pairs_hook=source.unique_keys)\n',),
                                                ('        record = _load_unique_json(raw)\n',)),
                                               (676,
                                                728,
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
                                               (729,
                                                734,
                                                ('    module_code = '
                                                 'compile(raw, filename, '
                                                 "'exec', dont_inherit=True, "
                                                 'optimize=sys.flags.optimize)\n',),
                                                ('    tree = ast.parse(raw)\n',
                                                 '    module_code = '
                                                 'compile(tree, filename, '
                                                 "'exec', dont_inherit=True, "
                                                 'optimize=sys.flags.optimize)\n',
                                                 '    _compiled_functions.last '
                                                 '= module_code\n',
                                                 '    '
                                                 '_compiled_functions.last_raw '
                                                 '= raw\n',
                                                 '    '
                                                 '_compiled_functions.last_tree '
                                                 '= tree\n')),
                                               (752,
                                                757,
                                                ('    '
                                                 'collect(ast.parse(raw).body)\n',),
                                                ('    if '
                                                 'getattr(_compiled_functions, '
                                                 "'last_raw', None) is raw:\n",
                                                 '        statements = '
                                                 '_compiled_functions.last_tree.body\n',
                                                 '    else:\n',
                                                 '        statements = '
                                                 'ast.parse(raw).body\n',
                                                 '    collect(statements)\n')),
                                               (776,
                                                778,
                                                ('require(_code_identity(sys._getframe().f_code) '
                                                 '== _code_identity(compile(\n',
                                                 '        _SELF_RAW, __file__, '
                                                 "'exec', dont_inherit=True, "
                                                 'optimize=sys.flags.optimize)),\n'),
                                                ('_IMPORT_CODE[str(_SELF_PATH)] '
                                                 '= '
                                                 '_compiled_functions(_SELF_RAW, '
                                                 '__file__)\n',
                                                 'require(_code_equal(sys._getframe().f_code, '
                                                 '_compiled_functions.last),\n')),
                                               (780,
                                                780,
                                                ('_IMPORT_CODE[str(_SELF_PATH)] '
                                                 '= '
                                                 '_compiled_functions(_SELF_RAW, '
                                                 '__file__)\n',),
                                                ()),
                                               (782,
                                                783,
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
                                               (796,
                                                797,
                                                ('            and '
                                                 '_code_identity(_executed) == '
                                                 '_code_identity(compile(_raw, '
                                                 "_module.__file__, 'exec',\n",
                                                 '                '
                                                 'dont_inherit=True, '
                                                 'optimize=sys.flags.optimize)),\n'),
                                                ('            and '
                                                 '_code_equal(_executed, '
                                                 '_compiled_functions.last),\n',)),
                                               (830,
                                                841,
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
                                               (845,
                                                846,
                                                ('               '
                                                 'vars(scaled_float32), '
                                                 'vars(pr760_stage))\n',),
                                                ('               '
                                                 'vars(scaled_float32), '
                                                 'vars(pr760_stage), '
                                                 'vars(pr780_successor))\n',)),
                                               (866,
                                                867,
                                                ('                    '
                                                 'require(actual is not None '
                                                 'and _code_identity(actual) '
                                                 '== _code_identity(code),\n',),
                                                ('                    '
                                                 'require(actual is not None '
                                                 'and compare(actual, '
                                                 'code),\n',)),
                                               (873,
                                                874,
                                                ('                '
                                                 'require(actual is not None '
                                                 'and _code_identity(actual) '
                                                 '== '
                                                 '_code_identity(expected),\n',),
                                                ('                '
                                                 'require(actual is not None '
                                                 'and compare(actual, '
                                                 'expected),\n',)),
                                               (884,
                                                885,
                                                (),
                                                ('    '
                                                 'pr780_successor.verify_data()\n',)),
                                               (901,
                                                918,
                                                (),
                                                ('# One census reuses '
                                                 'directory checks. None means '
                                                 'every call checks again.\n',
                                                 '# Each thread has its own '
                                                 'value, and a new thread '
                                                 'starts with None. The\n',
                                                 '# token puts back the exact '
                                                 'earlier value, so concurrent '
                                                 'censuses cannot\n',
                                                 '# leave a stale cache '
                                                 'behind.\n',
                                                 '_CHECKED_DIRS = '
                                                 "ContextVar('full_audit_checked_dirs', "
                                                 'default=None)\n',
                                                 '\n',
                                                 '\n',
                                                 'def _use_dir_cache():\n',
                                                 '    """Start a directory '
                                                 'cache for one census. '
                                                 'Callers restore the old '
                                                 'value."""\n',
                                                 '    return '
                                                 '_CHECKED_DIRS.set(set())\n',
                                                 '\n',
                                                 '\n',
                                                 'def '
                                                 '_restore_dir_cache(previous):\n',
                                                 '    """Put the directory '
                                                 'cache back, including the '
                                                 'uncached state."""\n',
                                                 '    '
                                                 '_CHECKED_DIRS.reset(previous)\n',
                                                 '\n',
                                                 '\n')),
                                               (925,
                                                945,
                                                (),
                                                ('    checked = '
                                                 '_CHECKED_DIRS.get()\n',
                                                 '    if (checked is not None '
                                                 "and os.name == 'posix' and "
                                                 'type(root) is PosixPath\n',
                                                 '            and '
                                                 '_canonical_relative_text(relative)):\n',
                                                 '        root_key = '
                                                 'os.fspath(root)\n',
                                                 '        if root_key not in '
                                                 'checked:\n',
                                                 '            '
                                                 'require(_root_unaliased(root), '
                                                 "'symbolic root or "
                                                 "ancestor')\n",
                                                 '            '
                                                 'checked.add(root_key)\n',
                                                 '        current = root_key\n',
                                                 '        last = len(parts) - '
                                                 '1\n',
                                                 '        for index, part in '
                                                 'enumerate(parts):\n',
                                                 "            current += '/' + "
                                                 'part\n',
                                                 '            if index != last '
                                                 'and current in checked:\n',
                                                 '                continue\n',
                                                 '            info = '
                                                 'os.lstat(current)\n',
                                                 '            require(not '
                                                 'stat.S_ISLNK(info.st_mode), '
                                                 "'symlink input: ' + "
                                                 'relative)\n',
                                                 '            if index == '
                                                 'last:\n',
                                                 '                '
                                                 'require(stat.S_ISREG(info.st_mode), '
                                                 "'input is not a regular "
                                                 "file: ' + relative)\n",
                                                 '            else:\n',
                                                 '                '
                                                 'checked.add(current)\n',
                                                 '        return '
                                                 'Path(current)\n')),
                                               (997,
                                                1005,
                                                (),
                                                ('    previous = '
                                                 '_use_dir_cache()\n',
                                                 '    try:\n',
                                                 '        return '
                                                 '_dependency_inventory(root, '
                                                 'roots=roots, '
                                                 'entries=entries, '
                                                 '_known=_known, '
                                                 '_snapshots=_snapshots)\n',
                                                 '    finally:\n',
                                                 '        '
                                                 '_restore_dir_cache(previous)\n',
                                                 '\n',
                                                 '\n',
                                                 'def '
                                                 '_dependency_inventory(root, '
                                                 '*, roots, entries, _known, '
                                                 '_snapshots):\n')),
                                               (1293,
                                                1309,
                                                ('    known = {path.as_posix() '
                                                 'for path in '
                                                 "_sibling('cache_key').input_paths(root)\n",
                                                 '             if path.suffix '
                                                 "== '.mojo'}\n",
                                                 '    '
                                                 '_operation_known_paths(root, '
                                                 'known, '
                                                 '_operation=_operation)\n',
                                                 '    image = {}\n',
                                                 '    for path in '
                                                 'sorted(known):\n',
                                                 '        raw = '
                                                 '_observe_bytes(root, path, '
                                                 '_regular(root, '
                                                 'path).read_bytes(), '
                                                 '_operation=_operation)\n',
                                                 '        require(type(raw) is '
                                                 "bytes, 'render entry source "
                                                 "is not physical bytes: ' + "
                                                 'path)\n',
                                                 '        image[path] = raw\n',
                                                 '    entries = '
                                                 "tuple(_sibling('affected').entry_directories(\n",
                                                 '        {path: '
                                                 '_physical_text(raw) for '
                                                 'path, raw in '
                                                 'image.items()}))\n',
                                                 '    return entries, image\n'),
                                                ('    # The reads stay in this '
                                                 'frame: controls patch them '
                                                 'by their caller.\n',
                                                 '    previous = '
                                                 '_use_dir_cache()\n',
                                                 '    try:\n',
                                                 '        known = '
                                                 '{path.as_posix() for path in '
                                                 "_sibling('cache_key').input_paths(root)\n",
                                                 '                 if '
                                                 "path.suffix == '.mojo'}\n",
                                                 '        '
                                                 '_operation_known_paths(root, '
                                                 'known, '
                                                 '_operation=_operation)\n',
                                                 '        image = {}\n',
                                                 '        for path in '
                                                 'sorted(known):\n',
                                                 '            raw = '
                                                 '_observe_bytes(root, path, '
                                                 '_regular(root, '
                                                 'path).read_bytes(), '
                                                 '_operation=_operation)\n',
                                                 '            '
                                                 'require(type(raw) is bytes, '
                                                 "'render entry source is not "
                                                 "physical bytes: ' + path)\n",
                                                 '            image[path] = '
                                                 'raw\n',
                                                 '        entries = '
                                                 "tuple(_sibling('affected').entry_directories(\n",
                                                 '            {path: '
                                                 '_physical_text(raw) for '
                                                 'path, raw in image.items() '
                                                 "if b'main' in raw}))\n",
                                                 '        return entries, '
                                                 'image\n',
                                                 '    finally:\n',
                                                 '        '
                                                 '_restore_dir_cache(previous)\n')),
                                               (1313,
                                                1324,
                                                ('    for path, raw in '
                                                 'image.items():\n',
                                                 '        actual = '
                                                 '_observe_bytes(root, path, '
                                                 '_regular(root, '
                                                 'path).read_bytes(), '
                                                 '_operation=_operation)\n',
                                                 '        require(type(actual) '
                                                 'is bytes and actual == raw, '
                                                 "'render entry source "
                                                 "changed: ' + path)\n",
                                                 '    known = {path.as_posix() '
                                                 'for path in '
                                                 "_sibling('cache_key').input_paths(root)\n",
                                                 '             if path.suffix '
                                                 "== '.mojo'}\n",
                                                 '    '
                                                 '_operation_known_paths(root, '
                                                 'known, '
                                                 '_operation=_operation)\n',
                                                 '    require(known == '
                                                 "set(image), 'render entry "
                                                 "path census changed')\n"),
                                                ('    previous = '
                                                 '_use_dir_cache()\n',
                                                 '    try:\n',
                                                 '        for path, raw in '
                                                 'image.items():\n',
                                                 '            actual = '
                                                 '_observe_bytes(root, path, '
                                                 '_regular(root, '
                                                 'path).read_bytes(), '
                                                 '_operation=_operation)\n',
                                                 '            '
                                                 'require(type(actual) is '
                                                 'bytes and actual == raw, '
                                                 "'render entry source "
                                                 "changed: ' + path)\n",
                                                 '        known = '
                                                 '{path.as_posix() for path in '
                                                 "_sibling('cache_key').input_paths(root)\n",
                                                 '                 if '
                                                 "path.suffix == '.mojo'}\n",
                                                 '        '
                                                 '_operation_known_paths(root, '
                                                 'known, '
                                                 '_operation=_operation)\n',
                                                 '        require(known == '
                                                 "set(image), 'render entry "
                                                 "path census changed')\n",
                                                 '    finally:\n',
                                                 '        '
                                                 '_restore_dir_cache(previous)\n')),
                                               (1350,
                                                1351,
                                                ("    expected = json.loads(raw, object_pairs_hook=source.unique_keys)['entry_directories']\n",),
                                                ("    expected = _load_unique_json(raw)['entry_directories']\n",)),
                                               (1597,
                                                1598,
                                                ('            record = json.loads(self._record_raw, object_pairs_hook=source.unique_keys)\n',),
                                                ('            record = _load_unique_json(self._record_raw)\n',)),
                                               (2518,
                                                2519,
                                                ('        seed = json.loads(self._receipt_seed, object_pairs_hook=source.unique_keys)\n',),
                                                ('        seed = _load_unique_json(self._receipt_seed)\n',)),
                                               (2668,
                                                2669,
                                                ('            seed = json.loads(self._receipt_seed, object_pairs_hook=source.unique_keys)\n',),
                                                ('            seed = _load_unique_json(self._receipt_seed)\n',)),
                                               (2819,
                                                2820,
                                                ('            return json.loads(self._record_raw, object_pairs_hook=source.unique_keys)\n',),
                                                ('            return _load_unique_json(self._record_raw)\n',)),
                                               (3150,
                                                3151,
                                                (),
                                                ('        retained = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 "raw).decode('utf-8') if "
                                                 'pr780_successor.reviewed_edge(path) '
                                                 'is not None and sha(raw) == '
                                                 "pr780_successor.reviewed_edge(path)['after_sha256'] "
                                                 'else '
                                                 "raw.decode('utf-8')\n",)),
                                               (3152,
                                                3153,
                                                ('                 else '
                                                 'pr760_stage.predecessor_source(path, '
                                                 "raw.decode('utf-8'))\n",
                                                 '                 if current '
                                                 'and path in '
                                                 'pr760_stage.CARLA_REGISTRY_PATHS '
                                                 "else raw.decode('utf-8'))\n"),
                                                ('                 else '
                                                 'pr760_stage.predecessor_source(path, '
                                                 'retained) if current and '
                                                 'path in '
                                                 'pr760_stage.CARLA_REGISTRY_PATHS '
                                                 'else retained)\n',)),
                                               (3174,
                                                3175,
                                                ('        if path in tests and '
                                                 'typed_boundary.is_current(path, '
                                                 'raw):\n',),
                                                ('        if path in tests and '
                                                 '(typed_boundary.is_current(path, '
                                                 'raw) or '
                                                 'pr780_successor.reviewed_edge(path) '
                                                 'is not None and sha(raw) == '
                                                 "pr780_successor.reviewed_edge(path)['after_sha256']):\n",)),
                                               (3183,
                                                3184,
                                                ('    texts = {path: '
                                                 "raw.decode('utf-8') for "
                                                 'path, raw in '
                                                 'sources.items()}\n',),
                                                ('    texts = {path: '
                                                 '(pr780_successor.predecessor_bytes(path, '
                                                 "raw).decode('utf-8') if "
                                                 'pr780_successor.reviewed_edge(path) '
                                                 'is not None and sha(raw) == '
                                                 "pr780_successor.reviewed_edge(path)['after_sha256'] "
                                                 "else raw.decode('utf-8')) "
                                                 'for path, raw in '
                                                 'sources.items()}\n',)),
                                               (3296,
                                                3302,
                                                (),
                                                ('    # A reviewed PR780 '
                                                 'successor extends a helper '
                                                 'endpoint. Its exact\n',
                                                 '    # predecessor, which the '
                                                 'bindings above admitted, '
                                                 'selects the edge.\n',
                                                 '    bindings = {path: '
                                                 "(pr780_successor.reviewed_edge(path)['before_sha256']\n",
                                                 '                       if '
                                                 'pr780_successor.reviewed_edge(path) '
                                                 'is not None\n',
                                                 '                       and '
                                                 'digest == '
                                                 "pr780_successor.reviewed_edge(path)['after_sha256'] "
                                                 'else digest)\n',
                                                 '                for path, '
                                                 'digest in '
                                                 'bindings.items()}\n')),
                                               (3492,
                                                3493,
                                                ('    record = json.loads(raw, object_pairs_hook=source.unique_keys)\n',),
                                                ('    record = _load_unique_json(raw)\n',)),
                                               (3607,
                                                3610,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if extension is not None '
                                                 'and sha(text) == '
                                                 "extension['after_sha256']:\n",
                                                 '        text = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 "text.encode('utf-8')).decode('utf-8')\n")),
                                               (3698,
                                                3701,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if edge is None and '
                                                 'extension is None:\n',
                                                 '        return text\n')),
                                               (3702,
                                                3703,
                                                ('        return text\n',),
                                                ('        edge = '
                                                 'extension\n',)),
                                               (3719,
                                                3726,
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
                                               (3729,
                                                3731,
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
                                               (3931,
                                                3935,
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
                                               (4100,
                                                4101,
                                                (),
                                                ('    extensions = '
                                                 "pr780_successor._data_snapshot()['edges']\n",)),
                                               (4104,
                                                4107,
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
                                               (4230,
                                                4236,
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
                                               (4238,
                                                4239,
                                                ('                if '
                                                 'qualification else '
                                                 "current.decode('utf-8'))\n",),
                                                ('                if '
                                                 'qualification else '
                                                 "retained.decode('utf-8'))\n",)),
                                               (4242,
                                                4243,
                                                ('            if current_image '
                                                 'and (path in '
                                                 'pr760_stage.EXAMPLE_PATHS or '
                                                 'qualification):\n',),
                                                ('            if current_image '
                                                 'and (path in '
                                                 'pr760_stage.EXAMPLE_PATHS or '
                                                 'qualification or current != '
                                                 'retained):\n',)),
                                               (4273,
                                                4278,
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
                                               (4346,
                                                4347,
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',\n",),
                                                (' '
                                                 "'tools/carla_lane_oracle/source_contracts.py': "
                                                 "'f4cf5b03da59b5a5070f9cdf8e26b486d4e1cd965eed172578018619ea788afe',\n",)),
                                               (4366,
                                                4369,
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
                                               (4373,
                                                4374,
                                                ('    return '
                                                 "{'tools/carla_lane_oracle/test_pr776_input_successors.py': "
                                                 "'af0d9aff27b4f06ce8b102979825d84c177ec78b349dbbb1de4a98423c03f132',\n",),
                                                ('    return '
                                                 "{'tools/carla_lane_oracle/test_pr776_input_successors.py': "
                                                 "'148a021e1d8173122f231f4e6839d4dfd7bb2bb14d76d70e3725ff310620d2aa',\n",)),
                                               (4382,
                                                4383,
                                                ('    """Recover exact earlier '
                                                 'comparison bytes for five '
                                                 'named PR776 inputs.\n',),
                                                ('    """Recover exact earlier '
                                                 'comparison bytes for six '
                                                 'named PR776 inputs.\n',)),
                                               (4391,
                                                4394,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if extension is not None '
                                                 'and sha(raw) == '
                                                 "extension['after_sha256']:\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'raw)\n')),
                                               (4775,
                                                4776,
                                                ('                                                          '
                                                 "'1c1565c05cb702df67319cb69641f83c8a761d38ccf06a11de91b037dfe5b1ce',\n",),
                                                ('                                                          '
                                                 "'6df971f2bf09c710a4e6ababc6adeea8995fd2e86c3e6866e548d5b193ae3669',\n",)),
                                               (4777,
                                                4778,
                                                ('                                                            '
                                                 '128,\n',),
                                                ('                                                            '
                                                 '129,\n',)),
                                               (4794,
                                                4797,
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\'):\\n",\n',),
                                                ('                                                             '
                                                 '"\'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py\',\\n",\n',
                                                 '                                                             '
                                                 "'                        '\n",
                                                 '                                                             '
                                                 '"\'tools/carla_lane_oracle/test_typed_boundary_contracts.py\'):\\n",\n')),
                                               (4803,
                                                4805,
                                                ('                                                           '
                                                 '(239,\n',
                                                 '                                                            '
                                                 '243,\n'),
                                                ('                                                           '
                                                 '(240,\n',
                                                 '                                                            '
                                                 '245,\n')),
                                               (4810,
                                                4811,
                                                ('                                                             '
                                                 "'raw) if path ==\\n',\n",),
                                                ('                                                             '
                                                 "'raw) if path in (\\n',\n",)),
                                               (4812,
                                                4815,
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
                                               (4831,
                                                4842,
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
                                               (4878,
                                                4881,
                                                (),
                                                ('    extension = '
                                                 'pr780_successor.reviewed_edge(path)\n',
                                                 '    if extension is not None '
                                                 'and sha(raw) == '
                                                 "extension['after_sha256']:\n",
                                                 '        raw = '
                                                 'pr780_successor.predecessor_bytes(path, '
                                                 'raw)\n')),
                                               (4883,
                                                4886,
                                                (),
                                                ('        raw = '
                                                 'pr776_predecessor_bytes(path, '
                                                 'raw)\n',
                                                 '    if (path == '
                                                 "'tools/carla_lane_oracle/test_typed_boundary_contracts.py'\n",
                                                 '            and sha(raw) == '
                                                 "'8dee4d9c4bf42214fb2f10fbdcf71a4ba04398095d8c62a16233ad6fc038fce7'):\n")),
                                               (5478,
                                                5483,
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
                                               (5570,
                                                5571,
                                                (),
                                                ('        extension_data = '
                                                 'pr780_successor._data_snapshot()\n',)),
                                               (5572,
                                                5580,
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
                                               (5582,
                                                5583,
                                                ('            require(sha(raw) '
                                                 '== successor_pins.get(path, '
                                                 'digest),\n',),
                                                ('            require(sha(raw) '
                                                 '== extended_pins.get(path, '
                                                 'successor_pins.get(path, '
                                                 'digest)),\n',)),
                                               (5584,
                                                5589,
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
                                               (5590,
                                                5597,
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
                                               (5613,
                                                5615,
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
                                               (5630,
                                                5631,
                                                ('        helper_texts = '
                                                 '{path: previous.get(path, '
                                                 "image[path].decode('utf-8'))\n",),
                                                ('        helper_texts = '
                                                 '{path: previous.get(path, '
                                                 'prior_inputs.get(path, '
                                                 "image[path]).decode('utf-8'))\n",)),
                                               (5684,
                                                5690,
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
                                                 '_production=production).items()}\n')),
                                               (5719,
                                                5762,
                                                (),
                                                (
                                                 '_GATED_JSON_KEYS = set()\n',
                                                 '\n',
                                                 '\n',
                                                 'def _load_unique_json(payload):\n',
                                                 '    """Parse JSON after a repeated key is refused.\n',
                                                 '\n',
                                                 '    The same bytes are not checked again. A failed key check is not kept.\n',
                                                 '\n',
                                                 '    Args:\n',
                                                 '        payload: The JSON bytes.\n',
                                                 '\n',
                                                 '    Returns:\n',
                                                 '        The parsed value.\n',
                                                 '\n',
                                                 '    Raises:\n',
                                                 '        ValueError: A key is repeated, or the bytes are not JSON.\n',
                                                 '    """\n',
                                                 '    digest = sha(payload)\n',
                                                 '    if digest in _GATED_JSON_KEYS:\n',
                                                 '        return json.loads(payload)\n',
                                                 '    import subprocess\n',
                                                 '    import tempfile\n',
                                                 '    root = Path(__file__).resolve().parents[2]\n',
                                                 "    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))\n",
                                                 "    with tempfile.TemporaryDirectory(prefix='audit-json-keys-') as directory:\n",
                                                 "        path = Path(directory) / 'record.json'\n",
                                                 '        path.write_bytes(payload)\n',
                                                 '        result = subprocess.run(\n',
                                                 "            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_pins',\n",
                                                 "             '--keys', str(path)],\n",
                                                 '            capture_output=True, text=True)\n',
                                                 '    if result.returncode != 0:\n',
                                                 '        lines_out = [line.strip() for line in result.stderr.splitlines()\n',
                                                 "                     if line.strip() and 'Crashpad' not in line]\n",
                                                 '        message = lines_out[-1] if lines_out else result.stdout.strip()\n',
                                                 "        if message.startswith('duplicate runtime source pin key:'):\n",
                                                 '            raise ValueError(message)\n',
                                                 '        return json.loads(payload)\n',
                                                 '    parsed = json.loads(payload)\n',
                                                 '    _GATED_JSON_KEYS.add(digest)\n',
                                                 '    return parsed\n',
                                                 '\n',
                                                 '\n',
                                                )))},

 'source_contracts.py': {'after_sha256': 'f4cf5b03da59b5a5070f9cdf8e26b486d4e1cd965eed172578018619ea788afe',
                         'before_sha256': 'ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5',
                         'edits': ((51,
                                    59,
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
                                     "'tests/test_carla_speed_parser_exceptions.mojo',\n",
                                     "    PREFIX + 'lidar.mojo', PREFIX + "
                                     "'semantic_lidar.mojo', PREFIX + "
                                     "'render_post.mojo',\n",
                                     "    PREFIX + 'render_sky.mojo', PREFIX + "
                                     "'render_textures.mojo',\n",
                                     "    PREFIX + 'render_weather.mojo'))\n")),
                                   (358,
                                    360,
                                    ('        if relative not in '
                                     'pr760.CARLA_REGISTRY_PATHS:\n',),
                                    ('        if (relative not in '
                                     'pr760.CARLA_REGISTRY_PATHS\n',
                                     '                and relative not in '
                                     'HISTORICAL_SUCCESSOR_PATHS):\n')),
                                   (383,
                                    385,
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
    if hashlib.sha256(json.dumps(EDGES, sort_keys=True, separators=(',', ':')).encode()).hexdigest() != '9e8938067edb71ba67afee2b1d7e229f52b457467910e98f96e188cb2ef3c6f6':
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
