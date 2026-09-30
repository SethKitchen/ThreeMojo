# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fetch, verify and credit the CARLA town's photoscanned assets.

The manifest, `assets/carla/manifest.json`, names each asset: its id, its
kind, its files with their URLs and SHA-256 sums, its license, its author,
its source page and a note on where it came from. This tool downloads the
files into a cache that git ignores, `.cache/carla-assets/`, and checks
each sum. The renderer reads the cache through `extensions/carla/assets`
and falls back to its procedural assets for an entry the cache lacks, so
nothing here is needed to build or to test.

Commands:

    python3 assets/carla/tools/carla_assets.py check
    python3 assets/carla/tools/carla_assets.py status
    python3 assets/carla/tools/carla_assets.py fetch [ID ...] [--pin]
    python3 assets/carla/tools/carla_assets.py verify
    python3 assets/carla/tools/carla_assets.py credits [--all] [--output FILE]

Rules the fetch keeps:

- A file is written to the cache only after its sum matches. It is first
  downloaded beside its place, then renamed into it.
- A verified file is never overwritten. A cached file whose sum does not
  match is reported and left alone; delete it by hand to fetch it again.
- A file with no sum in the manifest is not fetched, unless `--pin` is
  given. Then the first download is trusted, and its sum is written into
  the manifest, so every later fetch must match it.
- An archive (a `.zip`) is verified as a whole, and its members are then
  extracted to the paths the manifest names.
- A file whose URL is null is not hosted yet; its sum is in the manifest.
  It is not fetched. Put the file at its cache path by hand, and the
  next fetch verifies it and extracts it.
- A Google Drive share link is downloaded through Drive's download link.
  A web page sent in place of a file is refused.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / 'assets' / 'carla' / 'manifest.json'
CACHE = ROOT / '.cache' / 'carla-assets'

FORMAT = 1
KINDS = {'texture_set', 'hdri', 'model', 'town'}
LICENSES = {
    'CC0-1.0': 'https://creativecommons.org/publicdomain/zero/1.0/',
    'CC-BY-4.0': 'https://creativecommons.org/licenses/by/4.0/',
}
# The roles each kind's files may take. An archive holds members of the
# other roles.
ROLES = {
    'texture_set': {'albedo', 'normal', 'roughness', 'ao', 'displacement', 'archive'},
    'hdri': {'hdri', 'archive'},
    'model': {'model', 'support', 'archive'},
    'town': {'model', 'support', 'archive'},
}
FORWARDS = {'+x', '-x', '+z', '-z'}
ENTRY_KEYS = {'id', 'kind', 'license', 'author', 'source', 'provenance', 'files'}
OPTIONAL_KEYS = {'title', 'tile_meters', 'forward', 'changes'}
SCHEMES = ('https://', 'file://')
CHUNK = 1 << 16
# Some hosts refuse Python's own user agent.
AGENT = 'ThreeMojo-carla-assets/1.0'
# A download that drops is tried this many times in all, waiting longer
# before each new try.
ATTEMPTS = 5
BACKOFF_SECONDS = 2.0


class ManifestError(ValueError):
    """The manifest breaks one of its rules."""


class FetchError(RuntimeError):
    """A file could not be fetched or did not match its sum."""


def _is_sum(value):
    """Return True for a SHA-256 sum written as 64 lower-case hex digits."""
    return (isinstance(value, str) and len(value) == 64
            and all(c in '0123456789abcdef' for c in value))


def _check_path(path, where):
    """Refuse a cache path that is absolute or climbs out of the cache."""
    if not isinstance(path, str) or not path:
        raise ManifestError(f'{where}: a path must be a non-empty string')
    parts = PurePosixPath(path).parts
    if PurePosixPath(path).is_absolute() or '..' in parts or '\\' in path:
        raise ManifestError(f'{where}: the path {path!r} must stay inside the cache')


def _check_file(entry_id, kind, item, members):
    """Check one file of an entry, or one member of an archive."""
    where = f'{entry_id}: file {item.get("path")!r}'
    role = item.get('role')
    if role not in ROLES[kind] or (members and role == 'archive'):
        raise ManifestError(f'{where}: the role {role!r} is not one a {kind} takes')
    _check_path(item.get('path'), where)
    if members:
        if not isinstance(item.get('member'), str) or not item['member']:
            raise ManifestError(f'{where}: an archive member needs its name in the archive')
        return
    url = item.get('url')
    if url is not None and (not isinstance(url, str) or not url.startswith(SCHEMES)):
        raise ManifestError(f'{where}: the URL must be https://, file:// or null')
    if item.get('sha256') is not None and not _is_sum(item['sha256']):
        raise ManifestError(f'{where}: sha256 must be 64 hex digits or null')
    if url is None and item.get('sha256') is None:
        raise ManifestError(f'{where}: a file that is not hosted yet needs its sum')
    if role == 'archive':
        extract = item.get('extract')
        if not isinstance(extract, list) or not extract:
            raise ManifestError(f'{where}: an archive must name the members to extract')
        for member in extract:
            _check_file(entry_id, kind, member, True)


def binding_kind(key):
    """Return the kind of entry a binding key takes: a texture set for a
    surface, the ground or a facade, an HDRI for the sky, a town for a
    `town.` key, and a model for anything else (a vehicle, a walker, a
    tree or a prop)."""
    if key.startswith(('surface.', 'ground.', 'facade.')):
        return 'texture_set'
    if key.startswith('sky.'):
        return 'hdri'
    if key.startswith('town.'):
        return 'town'
    return 'model'


def check_manifest(manifest):
    """Raise `ManifestError` unless the manifest keeps every rule.

    The rules: format 1; unique ids; a known kind and license; an author,
    a source page and a provenance note; files whose roles fit the kind,
    whose paths stay in the cache, whose URLs are https or file, and whose
    sums are 64 hex digits or null; a texture set with an albedo and a
    positive tile size; a model with one model file and a forward axis; a
    town with one model file; an HDRI with one HDRI file; and bindings that name null or an entry of
    the kind `binding_kind` gives the key.
    """
    if not isinstance(manifest, dict) or manifest.get('format') != FORMAT:
        raise ManifestError(f'the manifest must be an object with "format": {FORMAT}')
    entries = manifest.get('entries')
    if not isinstance(entries, list):
        raise ManifestError('the manifest needs a list of entries')
    seen = set()
    paths = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ManifestError('an entry must be an object')
        entry_id = entry.get('id')
        missing = ENTRY_KEYS - set(entry)
        if missing:
            raise ManifestError(f'{entry_id}: missing {sorted(missing)}')
        unknown = set(entry) - ENTRY_KEYS - OPTIONAL_KEYS
        if unknown:
            raise ManifestError(f'{entry_id}: unknown keys {sorted(unknown)}')
        if not isinstance(entry_id, str) or not entry_id or entry_id in seen:
            raise ManifestError(f'{entry_id!r}: an id must be a unique non-empty string')
        seen.add(entry_id)
        kind = entry['kind']
        if kind not in KINDS:
            raise ManifestError(f'{entry_id}: the kind {kind!r} is none of {sorted(KINDS)}')
        if entry['license'] not in LICENSES:
            raise ManifestError(f'{entry_id}: the license must be one of {sorted(LICENSES)}')
        for key in ('author', 'source', 'provenance'):
            if not isinstance(entry[key], str) or not entry[key].strip():
                raise ManifestError(f'{entry_id}: {key} must be a non-empty string')
        files = entry['files']
        if not isinstance(files, list) or not files:
            raise ManifestError(f'{entry_id}: an entry needs at least one file')
        roles = []
        for item in files:
            if not isinstance(item, dict):
                raise ManifestError(f'{entry_id}: a file must be an object')
            _check_file(entry_id, kind, item, False)
            for placed in [item] + item.get('extract', []):
                if placed['path'] in paths:
                    raise ManifestError(f'{entry_id}: two files share the path {placed["path"]!r}')
                paths.add(placed['path'])
                if placed['role'] != 'archive':
                    roles.append(placed['role'])
        if kind == 'texture_set':
            if 'albedo' not in roles:
                raise ManifestError(f'{entry_id}: a texture set needs an albedo map')
            tile = entry.get('tile_meters')
            if not isinstance(tile, (int, float)) or isinstance(tile, bool) or tile <= 0:
                raise ManifestError(f'{entry_id}: a texture set needs a positive tile_meters')
        if kind == 'model':
            if roles.count('model') != 1:
                raise ManifestError(f'{entry_id}: a model needs exactly one model file')
            if entry.get('forward') not in FORWARDS:
                raise ManifestError(f'{entry_id}: a model needs forward, one of {sorted(FORWARDS)}')
        if kind == 'town' and roles.count('model') != 1:
            raise ManifestError(f'{entry_id}: a town needs exactly one model file')
        if kind == 'hdri' and roles.count('hdri') != 1:
            raise ManifestError(f'{entry_id}: an HDRI needs exactly one HDRI file')
    bindings = manifest.get('bindings', {})
    if not isinstance(bindings, dict):
        raise ManifestError('the bindings must be an object')
    kinds = {entry['id']: entry['kind'] for entry in entries}
    for key, value in bindings.items():
        if value is None:
            continue
        if value not in seen:
            raise ManifestError(f'the binding {key!r} names {value!r}, which is no entry')
        wanted = binding_kind(key)
        if kinds[value] != wanted:
            raise ManifestError(f'the binding {key!r} needs a {wanted}, and {value!r} is a {kinds[value]}')


def load_manifest(path=MANIFEST):
    """Return the manifest at `path`, checked."""
    manifest = json.loads(Path(path).read_text(encoding='utf-8'))
    check_manifest(manifest)
    return manifest


def save_manifest(manifest, path=MANIFEST):
    """Write the manifest back, two-space indented, with a final newline."""
    check_manifest(manifest)
    Path(path).write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')


def sha256_of(path):
    """Return the SHA-256 sum of a file, as 64 lower-case hex digits."""
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(CHUNK), b''):
            digest.update(block)
    return digest.hexdigest()


def direct_url(url):
    """Return the URL that downloads a file.

    A Google Drive share link, `https://drive.google.com/file/d/ID/view`
    or `https://drive.google.com/open?id=ID`, opens a web page; it becomes
    the link that downloads the file, past the page Drive shows before a
    large file. Any other URL is returned as it is.
    """
    match = re.match(r'https://drive\.google\.com/(?:file/d/([\w-]+)|(?:open|uc)\?(?:.*&)?id=([\w-]+))', url)
    if not match:
        return url
    return ('https://drive.usercontent.google.com/download?export=download&confirm=t&id='
            + (match.group(1) or match.group(2)))


def _download(url, destination):
    """Copy a URL's bytes into `destination`. A web page sent in place of
    the file, which is what a host sends for a file it does not share, is
    refused."""
    request = urllib.request.Request(direct_url(url), headers={'User-Agent': AGENT})
    for attempt in range(ATTEMPTS):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.headers.get_content_type() == 'text/html':
                    raise FetchError(f'{url}: the host sent a web page, not the file; '
                                     'check the file is shared with anyone who has the link')
                with open(destination, 'wb') as out:
                    shutil.copyfileobj(response, out, CHUNK)
            return
        except urllib.error.HTTPError as error:
            # The host answered: another try gets the same answer.
            raise FetchError(f'{url}: {error}') from error
        except OSError as error:
            # A dropped connection or a timeout: try again from the start.
            # A local file that is not there will not be there next time.
            if attempt + 1 == ATTEMPTS or not url.startswith('https://'):
                raise FetchError(f'{url}: {error}') from error
            time.sleep(BACKOFF_SECONDS * (attempt + 1))


def _extract(archive, item, cache):
    """Extract an archive's named members to their paths, never over a
    file that is already there."""
    with zipfile.ZipFile(archive) as bundle:
        names = set(bundle.namelist())
        for member in item['extract']:
            target = cache / member['path']
            if target.exists():
                continue
            if member['member'] not in names:
                raise FetchError(f'{item["url"]}: the archive has no member {member["member"]!r}')
            target.parent.mkdir(parents=True, exist_ok=True)
            partial = target.with_name(target.name + '.part')
            with bundle.open(member['member']) as source, open(partial, 'wb') as out:
                shutil.copyfileobj(source, out, CHUNK)
            os.replace(partial, target)


def fetch_file(item, cache, pin=False):
    """Bring one manifest file into the cache, and return what happened.

    Returns one of "kept" (already there and matching), "fetched",
    "pinned" (fetched and its sum recorded in `item`), "unhosted" (no URL
    and not in the cache), "unpinned" (no sum and no `--pin`, so not
    fetched) or "mismatch" (a cached file whose sum differs, left alone). A download whose sum differs raises `FetchError`
    and leaves nothing behind.
    """
    target = cache / item['path']
    expected = item.get('sha256')
    if target.exists():
        found = sha256_of(target)
        if expected is None:
            if not pin:
                return 'unpinned'
            item['sha256'] = found
            status = 'pinned'
        elif found != expected:
            return 'mismatch'
        else:
            status = 'kept'
        if item['role'] == 'archive':
            _extract(target, item, cache)
        return status
    if item['url'] is None:
        return 'unhosted'
    if expected is None and not pin:
        return 'unpinned'
    target.parent.mkdir(parents=True, exist_ok=True)
    handle, partial = tempfile.mkstemp(prefix=target.name + '.', suffix='.part', dir=target.parent)
    os.close(handle)
    try:
        _download(item['url'], partial)
        found = sha256_of(partial)
        if expected is not None and found != expected:
            raise FetchError(f'{item["url"]}: sha256 {found} does not match {expected}')
        if target.exists():
            raise FetchError(f'{target}: appeared during the download; it was not overwritten')
        os.replace(partial, target)
    finally:
        if os.path.exists(partial):
            os.remove(partial)
    status = 'fetched'
    if expected is None:
        item['sha256'] = found
        status = 'pinned'
    if item['role'] == 'archive':
        _extract(target, item, cache)
    return status


def fetch(manifest, cache, ids=None, pin=False):
    """Fetch every file of the named entries, or of every entry.

    Returns a list of (entry id, path, status). Raises `ManifestError` for
    an id the manifest does not have.
    """
    known = {entry['id'] for entry in manifest['entries']}
    for wanted in ids or []:
        if wanted not in known:
            raise ManifestError(f'no entry {wanted!r}')
    report = []
    for entry in manifest['entries']:
        if ids and entry['id'] not in ids:
            continue
        for item in entry['files']:
            report.append((entry['id'], item['path'], fetch_file(item, cache, pin)))
    return report


def cached(entry, cache):
    """Return True when every file the renderer reads of an entry is in
    the cache: each non-archive file and each archive member."""
    for item in entry['files']:
        placed = item['extract'] if item['role'] == 'archive' else [item]
        for member in placed:
            if not (cache / member['path']).is_file():
                return False
    return True


def verify(manifest, cache):
    """Re-hash every cached file that has a sum. Return a list of
    (path, status) with status "ok", "mismatch", "missing" or "unpinned"."""
    report = []
    for entry in manifest['entries']:
        for item in entry['files']:
            target = cache / item['path']
            if item.get('sha256') is None:
                report.append((item['path'], 'unpinned'))
            elif not target.exists():
                report.append((item['path'], 'missing'))
            elif sha256_of(target) != item['sha256']:
                report.append((item['path'], 'mismatch'))
            else:
                report.append((item['path'], 'ok'))
    return report


def credits(manifest, everything=False):
    """Return the attribution list as Markdown.

    Every CC-BY entry is listed with its title, author, source page,
    license and changes, as CC BY 4.0 asks. With `everything`, the CC0
    entries follow as a courtesy.
    """
    def line(entry):
        title = entry.get('title', entry['id'])
        license_name = 'CC BY 4.0' if entry['license'] == 'CC-BY-4.0' else 'CC0 1.0'
        text = (f'- "{title}" by {entry["author"]}, {entry["source"]}, '
                f'{license_name} ({LICENSES[entry["license"]]}).')
        if entry.get('changes'):
            text += f' Changes: {entry["changes"]}'
        return text

    required = [e for e in manifest['entries'] if e['license'] == 'CC-BY-4.0']
    lines = ['## Credits', '']
    if required:
        lines += [line(e) for e in sorted(required, key=lambda e: e['id'])]
    else:
        lines.append('No CC BY entry is in the manifest.')
    if everything:
        free = [e for e in manifest['entries'] if e['license'] == 'CC0-1.0']
        lines += ['', 'CC0 entries, credited as a courtesy:', '']
        lines += [line(e) for e in sorted(free, key=lambda e: e['id'])]
    return '\n'.join(lines) + '\n'


def status(manifest, cache):
    """Return one line per entry: its id, kind, license and whether the
    cache holds it."""
    return [
        f'{e["id"]:40} {e["kind"]:12} {e["license"]:10} '
        f'{"cached" if cached(e, cache) else "missing (procedural fallback)"}'
        for e in manifest['entries']
    ]


def main(argv=None):
    """Run a command line."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--manifest', type=Path, default=MANIFEST)
    parser.add_argument('--cache', type=Path, default=CACHE)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check', help='check the manifest against its rules')
    commands.add_parser('status', help='show which entries the cache holds')
    getter = commands.add_parser('fetch', help='download and verify entries')
    getter.add_argument('ids', nargs='*')
    getter.add_argument('--pin', action='store_true',
                        help='trust the first download of a file with no sum, and record its sum')
    commands.add_parser('verify', help='re-hash the cached files')
    teller = commands.add_parser('credits', help='print the attribution list')
    teller.add_argument('--all', action='store_true', help='also credit the CC0 entries')
    teller.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    manifest = load_manifest(args.manifest)
    if args.command == 'check':
        print(f'{args.manifest}: {len(manifest["entries"])} entries, '
              f'{len(manifest.get("bindings", {}))} bindings, all rules kept')
        return 0
    if args.command == 'status':
        print('\n'.join(status(manifest, args.cache)))
        return 0
    if args.command == 'fetch':
        failed = False
        try:
            report = fetch(manifest, args.cache, args.ids, args.pin)
        finally:
            if args.pin:
                save_manifest(manifest, args.manifest)
        for entry_id, path, state in report:
            print(f'{state:9} {entry_id}: {path}')
            failed = failed or state == 'mismatch'
        return 1 if failed else 0
    if args.command == 'verify':
        report = verify(manifest, args.cache)
        for path, state in report:
            print(f'{state:9} {path}')
        return 1 if any(state == 'mismatch' for _, state in report) else 0
    text = credits(manifest, args.all)
    if args.output:
        args.output.write_text(text, encoding='utf-8')
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
