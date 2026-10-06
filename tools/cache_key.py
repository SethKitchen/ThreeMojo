# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Hash build input identities, contents, flags, and tool versions."""

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys

SKIP = {'.git', '.venv', '.cache', 'out', 'node_modules', '__pycache__', '.agents', '.claude'}


def input_paths(root):
    """Yield consumed files, including new files and package initializers."""
    for directory, folders, files in os.walk(root):
        relative = Path(directory).relative_to(root)
        folders[:] = sorted(
            folder for folder in folders
            if folder not in SKIP and relative / folder != Path('coverage/build')
        )
        for name in sorted(files):
            path = relative / name
            if (path.parts[0] == 'assets' or name == 'Makefile'
                    or path.suffix in {'.mojo', '.py', '.json', '.toml', '.yaml', '.yml', '.mjs', '.c', '.h'}):
                yield path


def cache_key(root, settings):
    """Hash names and contents with lengths so renames and boundaries matter."""
    digest = hashlib.sha256()

    def add(data):
        digest.update(len(data).to_bytes(8, 'big'))
        digest.update(data)

    for setting in settings:
        add(setting.encode())
    for path in sorted(input_paths(root)):
        add(path.as_posix().encode())
        add((root / path).read_bytes())
    return digest.hexdigest()[:20]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--setting', action='append', default=[])
    args = parser.parse_args()
    settings = args.setting + [sys.version]
    # MAX's host package and kernels can change without changing Mojo itself.
    python = args.root / '.venv/bin/python'
    if python.exists():
        result = subprocess.run(
            [str(python), '-c',
             'import importlib.metadata as m; print(sorted((d.metadata["Name"], d.version) for d in m.distributions()))'],
            check=True, capture_output=True, text=True,
        )
        settings.append(result.stdout)
    print(cache_key(args.root, settings))


if __name__ == '__main__':
    main()
