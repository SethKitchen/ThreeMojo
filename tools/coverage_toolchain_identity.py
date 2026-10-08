# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Relocatable identities for the official Mojo wheel entry point.

Only the validated Python shebang is normalized. All launcher code, interpreter
bytes/capabilities and compiler runtime payload remain bound by content.
Unrecognized executables retain their exact byte identity.
"""

import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            result.update(block)
    return result.hexdigest()


def executable_identity(path):
    path = Path(path)
    raw = path.read_bytes()
    marker = b'from mojo._entrypoints import exec_mojo\n'
    if not raw.startswith(b'#!') or marker not in raw:
        return {'sha256': hashlib.sha256(raw).hexdigest()}
    shebang, separator, body = raw.partition(b'\n')
    interpreter = Path(os.fsdecode(shebang[2:]))
    if (not separator or not interpreter.is_absolute() or not interpreter.is_file()
            or interpreter.name not in {'python', 'python3', 'python3.12', 'python3.13', 'python3.14'}):
        raise ValueError('Unsupported Mojo launcher interpreter; use the official wheel entry point')
    environment = path.parent.parent.resolve()
    if interpreter.parent.resolve() != (environment / 'bin').resolve():
        raise ValueError('Mojo interpreter belongs to a different environment')
    config = environment / 'pyvenv.cfg'
    if not config.is_file():
        raise ValueError('Missing supported Mojo virtual environment configuration')
    fields = {}
    for line in config.read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep:
            key = key.strip().lower()
            if key in fields:
                raise ValueError('Duplicate Mojo virtual environment setting')
            fields[key] = value.strip()
    if fields.get('include-system-site-packages', '').lower() != 'false':
        raise ValueError('Mojo environment must exclude system site-packages')
    if Path(fields.get('home', '')).resolve() != interpreter.resolve().parent:
        raise ValueError('Mojo virtual environment home does not match its interpreter')
    sites = list((environment / 'lib').glob('python*/site-packages'))
    if len(sites) != 1:
        raise ValueError('Ambiguous or missing Mojo wheel site-packages')
    site = sites[0]
    overrides = [key for key in os.environ if key.startswith('MODULAR_MOJO_')
                 or key in {'MODULAR_MAX_PACKAGE_ROOT', 'PYTHONPATH', 'PYTHONHOME',
                            'PYTHONUSERBASE', 'LD_PRELOAD', 'LD_LIBRARY_PATH',
                            'DYLD_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES'}]
    if any(os.environ[key] for key in overrides):
        raise ValueError('Unsupported compiler environment override: ' + ', '.join(sorted(overrides)))
    # Reject import hooks before starting Python. Binding just the hook bytes
    # would not bind the arbitrary external module tree they could select.
    if (list(site.glob('*.pth')) or list(site.glob('sitecustomize*'))
            or list(site.glob('usercustomize*'))):
        raise ValueError('Unsupported Mojo environment import redirection')
    if (any(list(path.parent.glob(pattern)) for pattern in ('*.py', '*.pyc', '*.so', '*.pyd'))
            or any(child.is_dir() and child.name != '__pycache__' for child in path.parent.iterdir())):
        raise ValueError('Unsupported Mojo launcher-directory import shadow')
    if list((site / 'mojo').glob('__init__*')):
        raise ValueError('Unsupported non-namespace Mojo package initialization')
    probe = subprocess.run([str(interpreter), '-I', '-c',
        'import importlib.util,json,sys,sysconfig,site; '
        'spec=importlib.util.find_spec("mojo"); entry=importlib.util.find_spec("mojo._entrypoints"); '
        'print(json.dumps({"version":sys.version,"implementation":sys.implementation.name,'
        '"cache_tag":sys.implementation.cache_tag,"byteorder":sys.byteorder,"maxsize":sys.maxsize,'
        '"soabi":sysconfig.get_config_var("SOABI"),"prefix":sys.prefix,'
        '"sites":site.getsitepackages(),"user_site":site.ENABLE_USER_SITE,'
        '"mojo_paths":list(spec.submodule_search_locations or []) if spec else [],'
        '"entrypoint":entry.origin if entry else None,'
        '"customizers":[name for name in ("sitecustomize","usercustomize") if name in sys.modules]}))'],
        check=True, capture_output=True, text=True, timeout=30)
    capabilities = json.loads(probe.stdout)
    if (capabilities['implementation'] != 'cpython'
            or Path(capabilities.pop('prefix')).resolve() != environment
            or capabilities.pop('user_site') is not False
            or capabilities.pop('customizers')):
        raise ValueError('Unsupported Mojo interpreter environment or import customization')
    probe_sites = {Path(value).resolve() for value in capabilities.pop('sites')}
    if probe_sites != {site.resolve()}:
        raise ValueError('Mojo interpreter site-packages does not match its environment')
    if [Path(value).resolve() for value in capabilities.pop('mojo_paths')] != [(site / 'mojo').resolve()]:
        raise ValueError('Mojo package resolution does not match its bound payload')
    if Path(capabilities.pop('entrypoint') or '').resolve() != (site / 'mojo/_entrypoints.py').resolve():
        raise ValueError('Mojo entrypoint resolution does not match its bound payload')
    payload = {}
    versions = {}
    files = set()
    for package in ('mojo_compiler', 'mojo_compiler_mojo_libs'):
        metadata = list(site.glob(package + '-*.dist-info/METADATA'))
        if len(metadata) != 1:
            raise ValueError('Ambiguous or missing Mojo compiler distribution metadata')
        text = metadata[0].read_text()
        name = next((line[6:] for line in text.splitlines() if line.startswith('Name: ')), None)
        version = next((line[9:] for line in text.splitlines() if line.startswith('Version: ')), None)
        if not name or not version:
            raise ValueError('Malformed Mojo compiler distribution metadata')
        versions[name] = {'version': version, 'metadata_sha256': digest(metadata[0])}
        record = metadata[0].parent / 'RECORD'
        for row in csv.reader(record.read_text().splitlines()):
            if not row or not row[0]:
                raise ValueError('Malformed Mojo compiler package inventory')
            file = site / row[0]
            # Wheel-generated bin entry points are outside site-packages.
            # The invoked launcher is separately bound above. The driver and
            # linker payload, runtime libraries and stdlib are inside it.
            if row[0].startswith('../../../bin/'):
                continue
            if not file.resolve().is_relative_to(site.resolve()):
                raise ValueError('Escaped Mojo compiler package inventory')
            if '.dist-info' in row[0] or '__pycache__' in file.parts or file.suffix == '.pyc':
                continue
            files.add(file)
    for folder in (site / 'mojo', site / 'modular/lib/mojo'):
        if not folder.is_dir():
            raise ValueError('Incomplete supported Mojo compiler payload')
        files.update(file for file in folder.rglob('*') if file.is_file()
                     and '__pycache__' not in file.parts and file.suffix != '.pyc')
    if site / 'modular/bin/mojo' not in files or site / 'modular/bin/lld' not in files:
        raise ValueError('Incomplete supported Mojo driver/linker inventory')
    for file in files:
        if not file.is_file() or not file.resolve().is_relative_to(site.resolve()):
            raise ValueError('Missing or escaped Mojo payload file')
        payload[file.relative_to(site).as_posix()] = digest(file)
    return {'kind': 'mojo-wheel-python-entry-v1',
            'launcher_body_sha256': hashlib.sha256(body).hexdigest(),
            'interpreter': {'sha256': digest(interpreter.resolve()), 'capabilities': capabilities},
            'distributions': versions, 'payload': dict(sorted(payload.items()))}
