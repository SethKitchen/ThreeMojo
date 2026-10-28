# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow ideal stored-half correspondence; not a rounded/error graph proof.

The caller separately binds complete source text and its helper dependency
closure. The lexical adapter below is used only for the two fixed declarations
and does not claim to parse or certify arbitrary Mojo programs.
"""
import json
_DIGESTS = None


def _digests():
    """Return the legacy digest and the projected digest."""
    global _DIGESTS
    if _DIGESTS is not None:
        return _DIGESTS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_ideal_digests'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _DIGESTS = json.loads(result.stdout)
    return _DIGESTS


def __getattr__(name):
    if name == 'LEGACY_SHA256':
        return _digests()['legacy']
    if name == 'PROJECTED_SHA256':
        return _digests()['projected']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


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


def _projection_tool(mode, payload, binary=False):
    """Run one projection-result mode."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='projection-result-') as directory:
        path = Path(directory) / 'payload'
        if binary:
            path.write_bytes(payload)
        else:
            path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_projection_result', mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _require_source_text(value, message):
    """Require `value` to be a string, with `message` on any other value."""
    try:
        payload = json.dumps(
            {'text': value, 'message': message},
            separators=(',', ':'), allow_nan=False)
    except (TypeError, ValueError):
        payload = json.dumps(
            {'text': None, 'message': message}, separators=(',', ':'))
    _projection_tool('--text', payload)


def projection_result(digest):
    """Return the reviewed ideal-projection result record."""
    return json.loads(_projection_tool('--record', digest))


def verify_helper_projection(helper_text):
    """The pinned helper starts with a half product and only revises error."""
    _require_source_text(helper_text, 'ideal helper declaration or decorator changed')
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
    """Check the legacy digest, the helper, and the projected graph."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        'legacy': legacy,
        'current': current,
        'helper': helper_text,
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='ideal-projection-') as directory:
        path = Path(directory) / 'projection.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_moment_projection', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


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


def hex_integers(words):
    """Return each hexadecimal word as an int."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(list(words), separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='hex-integers-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--integers', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


def signed_classified_word(token, zero):
    """Return `signed`, or one rounded word, after the sign check."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    body = json.dumps({'token': token, 'zero': bool(zero)}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='signed-word-') as directory:
        path = Path(directory) / 'word.json'
        path.write_text(body)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_errors',
             '--signed-word', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['word']
        if message.startswith(prefix):
            message = message[len(prefix):]
        raise ValueError(message)
    return result.stdout


def classified_decimal_word(token):
    """Return one rounded decimal word after its count check."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='classified-decimal-') as directory:
        path = Path(directory) / 'token.txt'
        path.write_text(token)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_errors',
             '--classified', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['word']
        if message.startswith(prefix):
            message = message[len(prefix):]
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
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--decimal', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['word']
        if message.startswith(prefix):
            message = message[len(prefix):]
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


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
        'nodes': [str(word) for word in nodes],
        'weights': [str(word) for word in weights],
        'cosine': [str(word) for word in cosine],
        'sine': [str(word) for word in sine],
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-rows-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--decimal-rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['derive']
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
    payload = json.dumps({
        'nodes': [str(word) for word in nodes],
        'weights': [str(word) for word in weights],
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='node-sums-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--node-sums', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


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
    payload = json.dumps([str(word) for word in words], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='fraction-texts-') as directory:
        path = Path(directory) / 'words.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--fractions', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['word']
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
    return hex_integers(json.loads(result.stdout))


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


def payload_bytes(text):
    """Return bytes from hex digits, as ``bytes.fromhex`` reads them."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='payload-bytes-') as directory:
        folder = Path(directory)
        source = folder / 'payload.hex'
        dest = folder / 'payload.bin'
        source.write_bytes(text.encode('utf-8'))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_payload_bytes',
             str(source), str(dest)],
            capture_output=True, text=True)
        if result.returncode != 0:
            lines = [line.strip() for line in result.stderr.splitlines()
                     if line.strip() and 'Crashpad' not in line]
            message = lines[-1] if lines else result.stdout.strip()
            raise ValueError(message)
        return dest.read_bytes()


def moment_meta(payload, root, projection, dependencies, routing, blocks):
    """Return the stored-moment report meta in historical field order."""
    import ast
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root_dir = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root_dir / '.venv' / 'bin' / 'mojo'))
    body = json.dumps({
        'payload': payload, 'root': root, 'projection': projection,
        'dependencies': dependencies, 'routing': routing, 'blocks': blocks,
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-meta-') as directory:
        path = Path(directory) / 'meta.json'
        path.write_text(body)
        result = subprocess.run(
            ['sh', str(root_dir / 'tools' / 'tool.sh'), mojo,
             'carla_moment_meta', str(path)],
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


def _token_digest(payload):
    """Return whether one kept-token comparison agrees."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='token-digest-') as directory:
        path = Path(directory) / 'digest.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_token_digest',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def token_texts_match(left, right):
    """Return whether two sources have the same kept-token digest."""
    return _token_digest({'left': left, 'right': right}) == 'true'


def token_digest_equals(text, digest):
    """Return whether one source has the pinned kept-token digest."""
    return _token_digest({'text': text, 'digest': digest}) == 'true'


def array_literals(text, name, size):
    """Return the source spellings of one complete constant array."""
    return _constant_literals(text, name, 'array', size)


def rounded_array_words(text, name, size):
    """Return the rounded words of one complete constant array."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    body = json.dumps(
        {'source': text, 'name': name, 'size': size}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='rounded-array-') as directory:
        path = Path(directory) / 'array.json'
        path.write_text(body)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--rounded-array', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


_CONTRACT_PREFIXES = None


def _contract_prefixes():
    """Return the reviewed contract prefixes."""
    global _CONTRACT_PREFIXES
    if _CONTRACT_PREFIXES is not None:
        return _CONTRACT_PREFIXES
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_contract_prefixes'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CONTRACT_PREFIXES = json.loads(result.stdout)
    return _CONTRACT_PREFIXES


_CLI_FAILURES = None


def _cli_failures():
    """Return the checker failure prefixes."""
    global _CLI_FAILURES
    if _CLI_FAILURES is not None:
        return _CLI_FAILURES
    import os
    import subprocess
    from pathlib import Path
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


def scalar_literal(text, name):
    """Return the source spelling of one complete scalar constant."""
    values = _constant_literals(text, name, 'scalar')
    if len(values) != 1:
        raise ValueError(_contract_prefixes()['scalar'] + name)
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


_SAMPLED_CLOSURE = None


def _sampled_closure():
    """Return the sampled reference names and the closure groups."""
    global _SAMPLED_CLOSURE
    if _SAMPLED_CLOSURE is not None:
        return _SAMPLED_CLOSURE
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_closure'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SAMPLED_CLOSURE = json.loads(result.stdout)
    return _SAMPLED_CLOSURE


def _reference_refusal():
    """Return the bounds path and the reference-module refusal."""
    closure = _sampled_closure()
    return (
        closure['bounds_path'],
        closure['reference_changed'] + closure['reviewed'] + ': ',
    )


def project_try_only_reference(text, root, _operation=None):
    """Admit the reference module and return its projected text."""
    bounds, refusal = _reference_refusal()
    try:
        try:
            import full_audit_cleanup_contracts as full_audit
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit
        text = full_audit.reviewed_text(
            root, bounds, text, _operation=_operation)
    except (ValueError, OSError) as error:
        raise ValueError(refusal + str(error)) from error
    try:
        try:
            import envelope_budget_contracts as budget
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import envelope_budget_contracts as budget
        budget.historical_function(text, root=root)
    except ValueError as error:
        raise ValueError(refusal + str(error)) from error
    return text


def verify_try_only_reference(text, root, _operation=None):
    """Admit the reference module, then check the try-only refusal in Mojo."""
    _try_only_gate(project_try_only_reference(text, root, _operation=_operation))


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


def _texts_match_query(payload):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='texts-match-') as directory:
        path = Path(directory) / 'texts.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_source',
             '--match', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def texts_match(actual, expected):
    """Return whether two texts are the same string."""
    return _texts_match_query({'actual': actual, 'expected': expected}) == 'true'


def texts_match_all(pairs):
    """Return whether each text equals its pair."""
    if not pairs:
        return []
    flags = json.loads(_texts_match_query([
        {'actual': actual, 'expected': expected} for actual, expected in pairs]))
    return [flag == 'true' for flag in flags]


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
