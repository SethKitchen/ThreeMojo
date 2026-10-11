"""Verify and optionally decode a center-observer evidence packet; never execute it.

Usage: python decode_verify.py [--output NEW_DIRECTORY]
No output directory means verification only. Existing output is never overwritten.
"""
from pathlib import Path, PurePosixPath
import argparse
import base64
import gzip
import hashlib
import io
import json
import stat

MAX_BYTES = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(items):
    result = {}
    for key, value in items:
        need(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique_object)


def safe_path(name):
    need(isinstance(name, str) and name and '\\' not in name and '\0' not in name,
         'Invalid member name')
    path = PurePosixPath(name)
    need(not path.is_absolute() and all(part not in ('', '.', '..') for part in name.split('/'))
         and ':' not in path.parts[0], 'Unsafe member path')
    return Path(*path.parts)


def read_member(root, name):
    path = root
    parts = safe_path(name).parts
    for index, part in enumerate(parts):
        path = path / part
        mode = path.lstat().st_mode
        need(not stat.S_ISLNK(mode), 'Symlink payload refused')
        need(stat.S_ISREG(mode) if index == len(parts) - 1 else stat.S_ISDIR(mode),
             'Nonregular payload refused')
    need(path.stat().st_size <= MAX_BYTES, 'Oversize payload refused')
    return path.read_bytes()


def check_bytes(data, row):
    need(type(row['bytes']) is int and 0 <= row['bytes'] <= MAX_BYTES,
         'Invalid declared size')
    need(len(data) == row['bytes'] and SHA(data) == row['sha256'], 'Payload size or hash mismatch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    outer = parse(read_member(root, 'PUBLISHABLE-EVIDENCE-MANIFEST.json'))
    need(outer['schema'] == 1, 'Unsupported transport manifest')
    outer_paths = set()
    for row in outer['files']:
        name = row['path']
        need(name not in outer_paths, 'Duplicate transport member')
        outer_paths.add(name)
        check_bytes(read_member(root, name), row)
    inner = parse(read_member(root, 'INNER-MEMBER-MANIFEST.json'))
    need(inner['schema'] == 1, 'Unsupported inner manifest')
    original = read_member(root, inner['source_manifest']['transport_path'])
    check_bytes(original, inner['source_manifest'])
    original_manifest = parse(original)
    expected = {}
    for row in original_manifest['files']:
        safe_path(row['path'])
        need(row['path'] not in expected, 'Duplicate original member')
        expected[row['path']] = row
    need(len(expected) == inner['source_payload_files'] == 639, 'Original inventory count differs')
    archive = inner['container']
    encoded = read_member(root, archive['path'])
    packed = base64.b64decode(encoded.strip(), validate=True)
    need(type(archive['json_bytes']) is int and 0 <= archive['json_bytes'] <= MAX_BYTES,
         'Oversize archive refused')
    with gzip.GzipFile(fileobj=io.BytesIO(packed), mode='rb') as stream:
        expanded = stream.read(archive['json_bytes'] + 1)
    need(len(expanded) == archive['json_bytes'] and SHA(expanded) == archive['json_sha256'],
         'Archive content hash differs')
    container = parse(expanded)
    need(container['schema'] == 1 and container['encoding'] == 'base64', 'Unsupported container')
    archived = {}
    for row in container['members']:
        name = row['path']
        safe_path(name)
        need(name not in archived, 'Duplicate archived member')
        data = base64.b64decode(row['data_base64'], validate=True)
        check_bytes(data, row)
        archived[name] = data
    need(len(archived) == archive['members'], 'Container member count differs')
    restored = {}
    used_archived = set()
    for row in inner['members']:
        name = row['path']
        safe_path(name)
        need(name in expected and name not in restored, 'Unknown or duplicate inner member')
        need(row['bytes'] == expected[name]['bytes'] and row['sha256'] == expected[name]['sha256'],
             'Inner member differs from original manifest')
        if row['storage'] == 'readable':
            need(row['transport_path'] in outer_paths, 'Readable member is not in outer manifest')
            data = read_member(root, row['transport_path'])
        else:
            need(row['storage'] == 'container' and row['transport_path'] == archive['path'],
                 'Unknown storage representation')
            data = archived[name]
            used_archived.add(name)
        check_bytes(data, row)
        restored[name] = data
    need(set(restored) == set(expected) and used_archived == set(archived), 'Incomplete member coverage')
    need(sum(len(data) for data in restored.values()) == inner['source_payload_bytes'],
         'Total original bytes differ')
    need('PUBLISHABLE-EVIDENCE-MANIFEST.json' not in restored, 'Recursive source manifest collision')
    restored['PUBLISHABLE-EVIDENCE-MANIFEST.json'] = original
    if args.output is not None:
        need(not args.output.exists() and not args.output.is_symlink(), 'Output already exists')
        args.output.mkdir(parents=False, exist_ok=False)
        for name, data in restored.items():
            target = args.output / safe_path(name)
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as output:
                output.write(data)
            need(target.read_bytes() == data, 'Decoded write verification failed')
    print(json.dumps({'verified_original_payload_files': len(expected),
                      'verified_original_payload_bytes': inner['source_payload_bytes'],
                      'original_manifest_sha256': SHA(original),
                      'verified_transport_payload_files': len(outer_paths),
                      'decoded_files_including_original_manifest': len(restored) if args.output else 0,
                      'content_executed': False}, sort_keys=True))


if __name__ == '__main__':
    main()
