"""Verify and optionally decode evidence bytes, without executing or loading them.

Usage: python -B decode_verify.py [--output NEW_DIRECTORY]
In particular, profile.pstats is never unmarshaled or loaded by this program.
"""
from pathlib import Path, PurePosixPath
import argparse
import base64
import gzip
import hashlib
import io
import json
import stat

LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def unique(items):
    result = {}
    for key, value in items:
        need(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique)


def relative(name):
    need(isinstance(name, str) and name and '\\' not in name and '\0' not in name,
         'Invalid path')
    path = PurePosixPath(name)
    need(not path.is_absolute() and all(p not in ('', '.', '..') for p in name.split('/'))
         and ':' not in path.parts[0], 'Unsafe path')
    return Path(*path.parts)


def read(root, name):
    path = root
    parts = relative(name).parts
    for index, part in enumerate(parts):
        path /= part
        mode = path.lstat().st_mode
        need(not stat.S_ISLNK(mode), 'Symlink refused')
        need(stat.S_ISREG(mode) if index == len(parts) - 1 else stat.S_ISDIR(mode),
             'Nonregular payload refused')
    need(path.stat().st_size <= LIMIT, 'Oversize payload')
    return path.read_bytes()


def check(data, row):
    need(type(row['bytes']) is int and 0 <= row['bytes'] <= LIMIT, 'Invalid size')
    need(len(data) == row['bytes'] and SHA(data) == row['sha256'], 'Size or hash mismatch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    outer = parse(read(root, 'PUBLISHABLE-EVIDENCE-MANIFEST.json'))
    need(outer['schema'] == 1, 'Unsupported manifest')
    outer_names = set()
    for row in outer['files']:
        need(row['path'] not in outer_names, 'Duplicate outer member')
        outer_names.add(row['path'])
        check(read(root, row['path']), row)
    inner = parse(read(root, 'INNER-MEMBER-MANIFEST.json'))
    need(inner['schema'] == 1, 'Unsupported member manifest')
    archive = inner['container']
    need(archive['path'] in outer_names, 'Unsealed archive')
    packed = base64.b64decode(read(root, archive['path']).strip(), validate=True)
    need(type(archive['json_bytes']) is int and 0 <= archive['json_bytes'] <= LIMIT,
         'Oversize archive')
    with gzip.GzipFile(fileobj=io.BytesIO(packed), mode='rb') as stream:
        expanded = stream.read(archive['json_bytes'] + 1)
    need(len(expanded) == archive['json_bytes'] and SHA(expanded) == archive['json_sha256'],
         'Container hash mismatch')
    container = parse(expanded)
    need(container['schema'] == 1 and container['encoding'] == 'base64', 'Unsupported container')
    archived = {}
    for row in container['members']:
        relative(row['path'])
        need(row['path'] not in archived, 'Duplicate archived member')
        data = base64.b64decode(row['data_base64'], validate=True)
        check(data, row)
        archived[row['path']] = data
    need(len(archived) == archive['members'], 'Archive inventory mismatch')
    restored = {}
    used = set()
    for row in inner['members']:
        name = row['path']
        relative(name)
        need(name not in restored, 'Duplicate original member')
        if row['storage'] == 'readable':
            need(row['transport_path'] in outer_names, 'Unsealed readable member')
            data = read(root, row['transport_path'])
        else:
            need(row['storage'] == 'container' and row['transport_path'] == archive['path'],
                 'Unknown member storage')
            data = archived[name]
            used.add(name)
        check(data, row)
        restored[name] = data
    need(used == set(archived) and len(restored) == inner['original_member_count'],
         'Incomplete original inventory')
    need(sum(map(len, restored.values())) == inner['original_member_bytes'],
         'Original byte count mismatch')
    if args.output is not None:
        need(not args.output.exists() and not args.output.is_symlink(), 'Output already exists')
        args.output.mkdir(parents=False, exist_ok=False)
        for name, data in restored.items():
            path = args.output / relative(name)
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('xb') as target:
                target.write(data)
            need(path.read_bytes() == data, 'Decoded write mismatch')
    print(json.dumps({'verified_transport_payloads': len(outer_names),
                      'verified_original_members': len(restored),
                      'verified_original_bytes': inner['original_member_bytes'],
                      'decoded': args.output is not None, 'content_executed_or_unmarshaled': False},
                     sort_keys=True))


if __name__ == '__main__':
    main()
