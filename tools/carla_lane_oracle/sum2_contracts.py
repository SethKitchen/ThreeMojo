#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow semantic contracts for the reviewed canonical stored-term Sum2 graph.

The reviewed helper and caller texts are the source checkpoint, not an
automatically refreshed digest. AST equality binds the original recurrence
and arithmetic leaf. Complete lexical contracts retain
the environment guard, keyword subscripts, callers and decorators; dependency
and qualifier token gates separately cover the surrounding modules. The
cleanup gate supplies the sampled declaration syntax. This checker cannot
qualify native code generation.
"""
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

if __package__:
    from . import sum2_guard_contracts as guards
else:
    import sum2_guard_contracts as guards
import json
from pathlib import Path


# Initial accepted arithmetic checkpoint. The guarded and final format/doc
# source bindings are preserved in sum2-correspondence-migration.json.
def __getattr__(name):
    if name == 'REVIEWED_HELPER_SHA256':
        return _sum2_plan()['helper_sha']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def _checkpoints():
    """Return the reviewed helper, scalar, envelope, and eligibility texts."""
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_checkpoints'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


_SUM2_PLAN = None


_CARLA_PACKAGE = None


def _carla_package():
    """Return the CARLA extension package path."""
    global _CARLA_PACKAGE
    if _CARLA_PACKAGE is not None:
        return _CARLA_PACKAGE
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_carla_package'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CARLA_PACKAGE = result.stdout
    return _CARLA_PACKAGE


def _sum2_plan():
    """Return the Sum2 module names, caller comparisons, and helper map."""
    global _SUM2_PLAN
    if _SUM2_PLAN is not None:
        return _SUM2_PLAN
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_plan'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SUM2_PLAN = json.loads(result.stdout)
    return _SUM2_PLAN


def require(condition, message):
    if not condition:
        raise ValueError(message)


def _graphs_and_imports(texts, checkpoints, interval):
    """Compare every caller graph, then check the helper imports."""
    import os
    import subprocess
    import tempfile
    payload = {
        'texts': texts,
        'checkpoints': checkpoints,
        'interval': interval,
    }
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='sum2-graphs-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_graphs',
             '--with-imports', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


_CLI_FAILURES = None


def _cli_failures():
    """Return the checker failure prefixes."""
    global _CLI_FAILURES
    if _CLI_FAILURES is not None:
        return _CLI_FAILURES
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cli_failures'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CLI_FAILURES = json.loads(result.stdout)
    return _CLI_FAILURES


def _sum2_projected_result(payload, guard):
    """Project the Sum2 spiral, then return the correspondence result."""
    import ast
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    body = dict(payload)
    body['environment_guard'] = guard
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(body, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='sum2-projected-') as directory:
        path = Path(directory) / 'projected.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_result',
             '--projected', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['key']
        if message.startswith(prefix):
            raise KeyError(ast.literal_eval(message[len(prefix):])) from None
        raise ValueError(message)
    return json.loads(result.stdout)


def verify(root, *, _operation=None):
    # Lazy import avoids a checker-module cycle; no source is executed.
    if __package__:
        from . import check_sampled_values as c
    else:
        import check_sampled_values as c
    plan = _sum2_plan()
    names = tuple(plan['modules'])
    texts = {name: _typed_source.historical_text(root, root / ('extensions/carla/' + name + '.mojo'), source._observe_text(root, (root / ('extensions/carla/' + name + '.mojo')).relative_to(root).as_posix(), (root / ('extensions/carla/' + name + '.mojo')).read_text(), _operation=_operation), _operation=_operation)
             for name in names}
    guard_result = guards.verify(root, _operation=_operation)
    # Validate actual selector producers before restoring the exact historical
    # eligibility helper for the retained complete-function comparison.
    if __package__:
        from . import selection_finiteness_contracts as selection
    else:
        import selection_finiteness_contracts as selection
    helpers = plan['helpers']
    roundoff = helpers['roundoff']
    texts[roundoff] = selection.predecessor_text(
        root, _carla_package() + '/' + roundoff + '.mojo', _operation=_operation)

    # The complete lexical contract above retains all keyword-subscripts and
    # decorators. Separately relate the unchanged arithmetic leaf/recurrence
    # to the initial station-reviewed declarations using actual token spans.
    # Require the exact direct import inventory and reject all shadow forms.
    pins = json.loads(_typed_source.historical_text(root, root / 'tools/carla_lane_oracle/spiral-moment-pins.json', source._observe_text(root, (root / 'tools/carla_lane_oracle/spiral-moment-pins.json').relative_to(root).as_posix(), (root / 'tools/carla_lane_oracle/spiral-moment-pins.json').read_text(), _operation=_operation), _operation=_operation))
    interval = _typed_source.historical_text(root, root / 'extensions/carla/curve_interval.mojo', source._observe_text(root, (root / 'extensions/carla/curve_interval.mojo').relative_to(root).as_posix(), (root / 'extensions/carla/curve_interval.mojo').read_text(), _operation=_operation), _operation=_operation)
    try:
        _graphs_and_imports(texts, _checkpoints(), interval)
    except ValueError as error:
        if str(error).startswith('missing or ambiguous function: '):
            raise c.CheckError(str(error)) from error
        raise
    return _sum2_projected_result({
        'legacy': pins['ideal_projection']['legacy_normalized_source'],
        'bounds': texts[helpers['bounds']],
        'begin': plan['spiral_begin'],
        'end': plan['spiral_end'],
        'interval': interval,
    }, guard_result)
