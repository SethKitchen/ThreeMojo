"""Build compact, lossless transport from the immutable center-observer packet.

Only named local files are read or written. No native content is executed and no
external upload occurs. The original packet and any existing output are untouched.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json

R = Path(__file__).resolve().parent
S = R / 'validation-evidence-center-observer-v17-packet'
O = R / 'validation-evidence-center-observer-v17-transport-packet'
SOURCE_MANIFEST_SHA = '154e683afb2eee4de98de73497f4361b78789b918ceb6039ddd2000461314d1a'
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    need(path.is_file() and not path.is_symlink(), 'Nonregular input refused: ' + str(path))
    return path.read_bytes()


need(not O.exists(), 'Never overwrite a transport packet')
source_manifest_bytes = read(S / 'PUBLISHABLE-EVIDENCE-MANIFEST.json')
need(SHA(source_manifest_bytes) == SOURCE_MANIFEST_SHA, 'Original manifest changed')
source_manifest = json.loads(source_manifest_bytes)
need(len(source_manifest['files']) == 639, 'Original inventory count changed')
source_paths = set()
members = []
archived = []
payloads = []
readable_actual = {'actual/RESULT.json', 'actual/SOURCE-SEAL.json',
                   'actual/SDK-BEFORE.json', 'actual/SDK-AFTER.json', 'actual/WINDOW-START.json'}
archive_path = 'containers/RAW-RECEIPTS.json.gz.b64'
for row in source_manifest['files']:
    name = row['path']
    relative = Path(name)
    need(not relative.is_absolute() and '..' not in relative.parts and name not in source_paths,
         'Unsafe or duplicate original path')
    source_paths.add(name)
    data = read(S / name)
    need(len(data) == row['bytes'] and SHA(data) == row['sha256'], 'Original payload changed: ' + name)
    member = {key: row[key] for key in ['path', 'bytes', 'sha256', 'kind']}
    if not name.startswith('actual/') or name in readable_actual:
        payloads.append((name, data, 'byte-exact-readable-original-payload'))
        member.update(storage='readable', transport_path=name)
    else:
        archived.append({'path': name, 'bytes': len(data), 'sha256': SHA(data),
                         'data_base64': base64.b64encode(data).decode('ascii')})
        member.update(storage='container', transport_path=archive_path)
    members.append(member)
need({str(p.relative_to(S)) for p in S.rglob('*') if p.is_file()}
     == source_paths | {'PUBLISHABLE-EVIDENCE-MANIFEST.json'}, 'Unexpected original packet file')
members.sort(key=lambda row: row['path'])
archived.sort(key=lambda row: row['path'])
container = (json.dumps({'schema': 1, 'encoding': 'base64', 'members': archived},
                        sort_keys=True, separators=(',', ':')) + '\n').encode()
packed = gzip.compress(container, compresslevel=9, mtime=0)
encoded = base64.b64encode(packed) + b'\n'
need(gzip.decompress(base64.b64decode(encoded)) == container, 'Lossless container check failed')
payloads.append((archive_path, encoded, 'lossless-original-receipt-container'))
source_manifest_path = 'source-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
payloads.append((source_manifest_path, source_manifest_bytes, 'byte-exact-original-packet-manifest'))
inner = {'schema': 1, 'source_payload_files': len(members),
         'source_payload_bytes': sum(row['bytes'] for row in members),
         'source_manifest': {'transport_path': source_manifest_path,
                             'sha256': SOURCE_MANIFEST_SHA, 'bytes': len(source_manifest_bytes)},
         'container': {'path': archive_path, 'encoding': 'base64 of gzip with mtime=0 containing JSON',
                       'members': len(archived), 'json_bytes': len(container),
                       'json_sha256': SHA(container)}, 'members': members}
payloads.append(('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-member-and-storage-inventory'))
payloads.append(('decode_verify.py', read(R / 'decode_center_observer_v17_transport.py'),
                 'safe-byte-verifier-and-decoder-no-content-execution'))
payloads.append(('reproduce/build_center_observer_v17_transport_packet.py', read(Path(__file__)),
                 'local-transport-builder-no-native-execution'))
guide = '''# Compact frozen-v17 center-observer evidence transport

This transport preserves all 639 payloads of the original evidence packet,
plus the original manifest, byte-for-byte. No validation evidence is dropped.
Source files, configs, seals, summaries, the final result, SDK receipts and
window start remain readable. The other 610 original raw receipt files are
grouped into one deterministic JSON container. Each member carries its original
path, byte length, SHA-256 and base64 data; the JSON is gzip-compressed with
mtime=0 and base64-encoded for text transport.

INNER-MEMBER-MANIFEST.json maps every original member to its readable payload or
container. source-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json is the byte-exact
original manifest. This directory's PUBLISHABLE-EVIDENCE-MANIFEST.json seals
the 35 transport payloads. A manifest does not recursively list itself.

Verify without writing or executing content:
  python -B decode_verify.py

Restore the entire original packet into a new directory:
  python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all outer payloads, original member hashes, inventory and
bytes before writing. It rejects path traversal, duplicate members, symlink
payloads and existing output. It only writes bytes; it never imports, launches,
compiles or executes decoded content. The original absolute local_source paths
in the restored manifest remain historical provenance and are not dereferenced.

The original packet's acceptance and limits are unchanged: 202/202 stages and
49 exact before/after exported-observation pairs per O3/O0 mode, original caps,
unchanged source/SDK receipts and no owned descendants. This is newly executed
reconstructed frozen-v17 observer evidence. It does not restore lost historical
receipts, establish exhaustive internal traces, claim old full-search refusal
reachability, or qualify v18 or other validation. Native executables remain
excluded; their original hashes are preserved.
'''
payloads.append(('TRANSPORT-README.md', guide.encode(), 'transport-format-and-safe-decoding-guide'))
need(len(payloads) == len({name for name, _, _ in payloads}) == 35, 'Transport inventory mismatch')
O.mkdir()
rows = []
for name, data, kind in sorted(payloads):
    target = O / name
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as output:
        output.write(data)
    need(read(target) == data, 'Transport copy check failed')
    rows.append({'path': name, 'local_source': str(target), 'sha256': SHA(data),
                 'bytes': len(data), 'kind': kind})
manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with manifest.open('xb') as output:
    output.write(JSON({'schema': 1, 'scope': source_manifest['scope'],
                       'transport': 'lossless compact representation of immutable original evidence packet',
                       'source_manifest_sha256': SOURCE_MANIFEST_SHA, 'files': rows}))
print(json.dumps({'manifest': str(manifest), 'sha256': SHA(read(manifest)),
                  'files': len(rows), 'bytes': sum(row['bytes'] for row in rows),
                  'manifest_bytes': manifest.stat().st_size,
                  'total_files_including_manifest': len(rows) + 1,
                  'total_bytes_including_manifest': sum(row['bytes'] for row in rows) + manifest.stat().st_size,
                  'original_payload_files': len(members),
                  'container_members': len(archived), 'source_manifest_sha256': SOURCE_MANIFEST_SHA}))
