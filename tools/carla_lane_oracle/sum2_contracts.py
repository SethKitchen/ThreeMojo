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

if __package__:
    from .ideal_projection import (
        declaration, selected_block, stored_half_tail, verify_projection)
else:
    from ideal_projection import (
        declaration, selected_block, stored_half_tail, verify_projection)


# Initial accepted arithmetic checkpoint. The guarded and final format/doc
# source bindings are preserved in sum2-correspondence-migration.json.
REVIEWED_HELPER_SHA256 = '41995592963bae61a2b690b465bdad6c759b02ddbe98141ba5da30d0df5d5c8e'


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


def require(condition, message):
    if not condition:
        raise ValueError(message)


def _sum2_import_gate(mode, payload):
    """Require the reviewed Sum2 imports through the Mojo import gate."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sum2-imports-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(json.dumps(payload, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_imports',
             mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _graph_equal(
    left, left_name, right, right_name, message, rename='', *,
    drop_first=False, expect_first='',
):
    """Require two Sum2 function dumps to match."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = {
        'left': left, 'left_name': left_name, 'right': right,
        'right_name': right_name, 'message': message,
    }
    if rename:
        payload['rename'] = rename
    if drop_first:
        payload['drop_first'] = True
    if expect_first:
        payload['expect_first'] = expect_first
    with tempfile.TemporaryDirectory(prefix='sum2-graph-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(json.dumps(payload, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_graph',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _require_function(text, name):
    """Require one top-level function to be present."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='require-function-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--slice', str(path), '--name', name],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _sum2_result(projection, guard):
    """Return the Sum2 correspondence result in historical field order."""
    import ast
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'projection': projection, 'environment_guard': guard},
        separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='sum2-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sum2_result',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = 'KeyError: '
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
    names = ('curve_sum2', 'lane_geometry', 'curve_bounds', 'spiral_roundoff_proof')
    texts = {name: _typed_source.historical_text(root, root / ('extensions/carla/' + name + '.mojo'), source._observe_text(root, (root / ('extensions/carla/' + name + '.mojo')).relative_to(root).as_posix(), (root / ('extensions/carla/' + name + '.mojo')).read_text(), _operation=_operation), _operation=_operation)
             for name in names}
    guard_result = guards.verify(root, _operation=_operation)
    # Validate actual selector producers before restoring the exact historical
    # eligibility helper for the retained complete-function comparison.
    if __package__:
        from . import selection_finiteness_contracts as selection
    else:
        import selection_finiteness_contracts as selection
    texts['spiral_roundoff_proof'] = selection.predecessor_text(
        root, 'extensions/carla/spiral_roundoff_proof.mojo', _operation=_operation)

    # The complete lexical contract above retains all keyword-subscripts and
    # decorators. Separately relate the unchanged arithmetic leaf/recurrence
    # to the initial station-reviewed declarations using actual token spans.
    checkpoints = _checkpoints()
    _graph_equal(
        declaration(texts['curve_sum2'], '_sum2_update'), '_sum2_update',
        checkpoints['helper'], '_sum2_update', 'Sum2 recurrence changed')
    _graph_equal(
        declaration(texts['curve_sum2'], '_sum2_error_checked'),
        '_sum2_error_checked', checkpoints['helper'], '_sum2_error',
        'Sum2 checked arithmetic leaf changed', '_sum2_error')
    _graph_equal(
        texts['lane_geometry'], '_lane_spiral', checkpoints['scalar'], '_lane_spiral',
        'Sum2 complete caller graph changed: _lane_spiral',
        drop_first=True, expect_first='_require_sum2_environment()')
    for module, name, expected in (
            ('spiral_roundoff_proof', '_sum2_envelope_error', checkpoints['envelope']),
            ('spiral_roundoff_proof', '_try_spiral_roundoff_envelope', checkpoints['eligibility'])):
        _graph_equal(
            texts[module], name, expected, name,
            'Sum2 complete caller graph changed: ' + name)
    # Require the exact direct import inventory and reject all shadow forms.
    _sum2_import_gate('--helpers', {
        'lane': texts['lane_geometry'],
        'bounds': texts['curve_bounds'],
        'roundoff': texts['spiral_roundoff_proof'],
    })
    pins = json.loads(_typed_source.historical_text(root, root / 'tools/carla_lane_oracle/spiral-moment-pins.json', source._observe_text(root, (root / 'tools/carla_lane_oracle/spiral-moment-pins.json').relative_to(root).as_posix(), (root / 'tools/carla_lane_oracle/spiral-moment-pins.json').read_text(), _operation=_operation), _operation=_operation))
    interval = _typed_source.historical_text(root, root / 'extensions/carla/curve_interval.mojo', source._observe_text(root, (root / 'extensions/carla/curve_interval.mojo').relative_to(root).as_posix(), (root / 'extensions/carla/curve_interval.mojo').read_text(), _operation=_operation), _operation=_operation)
    try:
        _require_function(interval, '_stored_half')
    except ValueError as error:
        raise c.CheckError(str(error)) from error
    _sum2_import_gate('--half', {
        'bounds': texts['curve_bounds'], 'interval': interval,
    })
    projection = verify_projection(
        pins['ideal_projection']['legacy_normalized_source'],
        selected_block(
            texts['curve_bounds'], 'def _spiral_expression[', 'def _sample_index('),
        stored_half_tail(interval))
    return _sum2_result(projection, guard_result)
