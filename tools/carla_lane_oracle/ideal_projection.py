# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow ideal stored-half correspondence; not a rounded/error graph proof.

The caller separately binds complete source text and its helper dependency
closure. The lexical adapter below is used only for the two fixed declarations
and does not claim to parse or certify arbitrary Mojo programs.
"""
import json

LEGACY_SHA256 = '270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733'
PROJECTED_SHA256 = 'f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06'


def require(condition, message):
    if not condition:
        raise ValueError(message)


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


def stored_half_tail(text):
    """Return the interval source from its one stored-half declaration."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='stored-half-tail-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_text',
             '--stored-half-tail', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


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


def _run_ideal_half(arguments):
    """Run one ideal-half mode and return its stdout."""
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_ideal_half',
         *arguments],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _ideal_legacy_dump(legacy):
    """Return the commuted legacy dump after the name and count checks."""
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='ideal-legacy-') as directory:
        path = Path(directory) / 'legacy.mojo'
        path.write_text(legacy)
        return _run_ideal_half(['--legacy', str(path)])


def _ideal_current_matches(current, left_dump):
    """Require the live spiral to match the commuted legacy dump."""
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='ideal-current-') as directory:
        folder = Path(directory)
        current_path = folder / 'current.mojo'
        dump_path = folder / 'dump.txt'
        current_path.write_text(current)
        dump_path.write_text(left_dump)
        _run_ideal_half(
            ['--current', str(current_path), '--dump', str(dump_path)])


def verify_projection(legacy, current, helper_text):
    _gate(legacy.encode(), 'legacy')
    verify_helper_projection(helper_text)
    left_dump = _ideal_legacy_dump(legacy)
    # The caller supplies the ideal spiral as source text.
    require(isinstance(current, str), 'changed ideal generic declaration')
    _ideal_current_matches(current, left_dump)
    _gate(left_dump.encode(), 'projected')
    projected = PROJECTED_SHA256
    return {'helper_projections': 5, 'rate_half_commutations': 2,
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


def apply_pin_transitions(pins, transitions):
    """Return the pins after each historical transition value is written."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'pins': pins, 'transitions': transitions}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='pin-apply-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_pin_apply',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


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


def hex_words(words):
    """Return each word as ``0x`` and 16 uppercase hex digits."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps([str(word) for word in words], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='hex-words-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--hex', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def require_moment_pins(pins, spec):
    """Require the moment pin document to match `spec`."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'pins': pins, 'spec': spec}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-pins-') as directory:
        path = Path(directory) / 'pins.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_pins',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def require_legacy_digest(actual, expected):
    """Require the legacy pin digest to match `expected`."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'actual': actual, 'expected': expected},
                         separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='legacy-digest-') as directory:
        path = Path(directory) / 'digest.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_pins',
             '--legacy', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def require_projection_result(projection, result_pins):
    """Require each projection result pin to match."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'projection': projection, 'result': result_pins},
                         separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='projection-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_pins',
             '--result', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def require_stored_words(words, expected, message):
    """Require each word to match its pinned ``0x`` spelling."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'words': [str(word) for word in words],
        'expected': list(expected),
        'message': message,
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='stored-words-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--require', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def derive_rows(nodes, weights, cosine, sine):
    """Return the 64 derived moment rows for four stored word lists."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path

    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'nodes': hex_words(nodes), 'weights': hex_words(weights),
        'cosine': hex_words(cosine), 'sine': hex_words(sine),
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

    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'nodes': hex_words(nodes), 'weights': hex_words(weights)},
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
    payload = json.dumps(hex_words(words), separators=(',', ':'))
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


def moment_report(meta, blobs):
    """Return the stored-moment report for one payload and its pin files."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(meta, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-report-') as directory:
        folder = Path(directory)
        meta_path = folder / 'meta.json'
        meta_path.write_text(payload)
        command = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                   'carla_moment_report', str(meta_path)]
        for index, blob in enumerate(blobs):
            path = folder / ('pin-' + str(index))
            path.write_bytes(blob)
            command.append(str(path))
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def moment_guard(mode, payload):
    """Require one stored-moment count, name set, or output path guard."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-guard-') as directory:
        path = Path(directory) / 'guard.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_guards',
             mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


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


def _try_only_gate(text):
    """Require the lane proof's reviewed try-only refusal."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='try-only-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--try-only', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify_try_only_reference(text, root, _operation=None):
    """Admit the reference module, then check the try-only refusal in Mojo."""
    try:
        try:
            import full_audit_cleanup_contracts as full_audit
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit
        text = full_audit.reviewed_text(
            root, 'extensions/carla/curve_bounds.mojo', text, _operation=_operation)
    except (ValueError, OSError) as error:
        raise ValueError(
            'reference module changed; renewed review required: curve_bounds.mojo: '
            + str(error)) from error
    try:
        try:
            import envelope_budget_contracts as budget
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import envelope_budget_contracts as budget
        budget.historical_function(text, root=root)
    except ValueError as error:
        raise ValueError(
            'reference module changed; renewed review required: curve_bounds.mojo: '
            + str(error)) from error
    _try_only_gate(text)


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


def _pin_text(payload):
    """Run one pin-text check and return its stdout."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='pin-text-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(json.dumps(payload, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_pin_text',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def require_operation_block(text, begin, end, expected, digest, name):
    """Return one source block that matches its pin."""
    return _pin_text({
        'kind': 'block', 'source': text, 'begin': begin, 'end': end,
        'expected': expected, 'digest': digest, 'name': name,
    })


def require_text_digest(text, digest, message):
    """Require the SHA-256 of `text` to equal `digest`."""
    _pin_text({
        'kind': 'digest', 'text': text, 'digest': digest, 'message': message,
    })


def require_same_text(actual, expected, message):
    """Require two texts to be identical."""
    _pin_text({
        'kind': 'same', 'actual': actual, 'expected': expected,
        'message': message,
    })


def texts_match(actual, expected):
    """Return whether two texts are the same string."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'actual': actual, 'expected': expected}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='texts-match-') as directory:
        path = Path(directory) / 'texts.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_source',
             '--match', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip() == 'true'


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
