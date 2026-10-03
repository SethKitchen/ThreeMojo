# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Tests of the CARLA asset manifest and its fetch tool, on file:// fixtures.

Every expected sum is computed here with hashlib from the fixture's own
bytes, not read back from the tool.
"""

import copy
import hashlib
import io
import json
import math
from pathlib import Path
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from email.message import Message
from unittest.mock import patch
from urllib.error import HTTPError

import carla_assets as tool


def _sum(data):
    return hashlib.sha256(data).hexdigest()


class Fixture:
    """A temporary folder with source files, a cache and a manifest."""

    def __init__(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.source = self.root / 'source'
        self.cache = self.root / 'cache'
        self.source.mkdir()

    def file(self, name, data):
        path = self.source / name
        path.write_bytes(data)
        return path.as_uri()

    def close(self):
        self.folder.cleanup()


def texture_entry(url, digest, entry_id='asphalt', path='asphalt/color.jpg'):
    return {
        'id': entry_id, 'kind': 'texture_set', 'license': 'CC0-1.0',
        'author': 'A. Scanner', 'source': 'https://example.org/asphalt',
        'provenance': 'A test fixture.', 'tile_meters': 4,
        'files': [{'role': 'albedo', 'url': url, 'sha256': digest, 'path': path}],
    }


def manifest_of(*entries, bindings=None):
    return {'format': 1, 'entries': list(entries), 'bindings': bindings or {}}


class ManifestTests(unittest.TestCase):
    def test_repository_manifest_keeps_the_rules(self):
        manifest = tool.load_manifest()
        ids = [entry['id'] for entry in manifest['entries']]
        self.assertEqual(len(ids), len(set(ids)))
        # Every surface kind the town builds has a key in the table.
        for key in ('surface.road', 'surface.sidewalk', 'surface.curb', 'surface.wall',
                    'ground.grass', 'ground.paving', 'sky.clear', 'vehicle.*', 'walker.*'):
            self.assertIn(key, manifest['bindings'])

    def test_a_good_manifest_passes(self):
        tool.check_manifest(manifest_of(texture_entry('https://example.org/a.jpg', None),
                                        bindings={'surface.road': 'asphalt', 'vehicle.*': None}))

    def test_each_broken_rule_is_refused(self):
        good = texture_entry('https://example.org/a.jpg', None)
        cases = []

        def broken(change):
            entry = copy.deepcopy(good)
            change(entry)
            cases.append(manifest_of(entry))

        broken(lambda e: e.update(kind='sound'))
        broken(lambda e: e.update(license='GPL-3.0'))
        broken(lambda e: e.update(author=' '))
        broken(lambda e: e.pop('provenance'))
        broken(lambda e: e.update(colour='red'))
        broken(lambda e: e.update(tile_meters=0))
        broken(lambda e: e.update(tile_meters=True))
        broken(lambda e: e.update(files=[]))
        broken(lambda e: e['files'][0].update(role='hdri'))
        broken(lambda e: e['files'][0].update(role='normal'))
        broken(lambda e: e['files'][0].update(path='../escape.jpg'))
        broken(lambda e: e['files'][0].update(path='/abs.jpg'))
        broken(lambda e: e['files'][0].update(url='http://example.org/a.jpg'))
        broken(lambda e: e['files'][0].update(sha256='ABC'))
        broken(lambda e: e['files'][0].update(url=None))  # no URL and no sum
        broken(lambda e: e['files'][0].update(url=7))
        cases.append({'format': 2, 'entries': []})
        cases.append(manifest_of(good, copy.deepcopy(good)))
        cases.append(manifest_of(good, bindings={'surface.road': 'nothing'}))
        cases.append(manifest_of(good, bindings={'sky.clear': 'asphalt'}))
        model = {
            'id': 'car', 'kind': 'model', 'license': 'CC-BY-4.0', 'author': 'B',
            'source': 'https://example.org/car', 'provenance': 'p',
            'files': [{'role': 'model', 'url': 'https://example.org/car.glb',
                       'sha256': None, 'path': 'car.glb'}],
        }
        cases.append(manifest_of(model))  # no forward axis
        town = copy.deepcopy(model)
        town.update(id='town', kind='town')
        town['files'][0]['role'] = 'support'
        cases.append(manifest_of(town))  # no model file
        cases.append(manifest_of(dict(model, forward='+x'), bindings={'town.Town02': 'car'}))
        archive = copy.deepcopy(good)
        archive['files'] = [{'role': 'archive', 'url': 'https://example.org/a.zip',
                             'sha256': None, 'path': 'a.zip', 'extract': []}]
        cases.append(manifest_of(archive))
        for manifest in cases:
            with self.assertRaises(tool.ManifestError):
                tool.check_manifest(manifest)

    def test_tile_sizes_must_remain_positive_finite_float32(self):
        for value in (math.nan, math.inf, -math.inf, 1e100, 1e-100, 0, -1, True, '2', 10**10000):
            entry = texture_entry('https://example.org/a.jpg', None)
            entry['tile_meters'] = value
            with self.assertRaisesRegex(tool.ManifestError, 'Float32 tile_meters'):
                tool.check_manifest(manifest_of(entry))
        for value in (1, 0.25, 1e-40, 3.4028234663852886e38):
            entry = texture_entry('https://example.org/a.jpg', None)
            entry['tile_meters'] = value
            tool.check_manifest(manifest_of(entry))

    def test_manifest_format_is_numeric_not_boolean(self):
        for value in (True, False):
            manifest = manifest_of()
            manifest['format'] = value
            with self.assertRaises(tool.ManifestError):
                tool.check_manifest(manifest)
        manifest = manifest_of()
        manifest['format'] = 1.0
        tool.check_manifest(manifest)

    def test_a_town_passes(self):
        town = {
            'id': 'carla.town.town02', 'kind': 'town', 'license': 'CC-BY-4.0', 'author': 'B',
            'source': 'https://example.org/town', 'provenance': 'p',
            'files': [{'role': 'model', 'url': 'https://example.org/t.gltf',
                       'sha256': None, 'path': 't.gltf'}],
        }
        tool.check_manifest(manifest_of(town, bindings={'town.Town02': 'carla.town.town02'}))

    def test_a_file_not_hosted_yet_passes_with_its_sum(self):
        tool.check_manifest(manifest_of(texture_entry(None, _sum(b'scan'))))

    def test_a_drive_share_link_becomes_its_download(self):
        download = 'https://drive.usercontent.google.com/download?export=download&confirm=t&id='
        self.assertEqual(tool.direct_url('https://drive.google.com/file/d/1aB-c_9/view?usp=sharing'),
                         download + '1aB-c_9')
        self.assertEqual(tool.direct_url('https://drive.google.com/open?id=1aB-c_9'), download + '1aB-c_9')
        self.assertEqual(tool.direct_url('https://drive.google.com/uc?export=download&id=XY'), download + 'XY')
        self.assertEqual(tool.direct_url('https://example.org/a.zip'), 'https://example.org/a.zip')

    def test_binding_kinds(self):
        self.assertEqual(tool.binding_kind('surface.road'), 'texture_set')
        self.assertEqual(tool.binding_kind('facade.brick'), 'texture_set')
        self.assertEqual(tool.binding_kind('sky.overcast'), 'hdri')
        self.assertEqual(tool.binding_kind('vehicle.tesla.model3'), 'model')
        self.assertEqual(tool.binding_kind('town.Town02'), 'town')


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        self.data = b'photoscanned asphalt'
        self.url = self.fixture.file('asphalt.jpg', self.data)

    def tearDown(self):
        self.fixture.close()

    def test_fetch_verifies_then_keeps(self):
        manifest = manifest_of(texture_entry(self.url, _sum(self.data)))
        report = tool.fetch(manifest, self.fixture.cache)
        self.assertEqual(report, [('asphalt', 'asphalt/color.jpg', 'fetched')])
        target = self.fixture.cache / 'asphalt/color.jpg'
        self.assertEqual(target.read_bytes(), self.data)
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'kept')
        self.assertEqual(tool.verify(manifest, self.fixture.cache), [('asphalt/color.jpg', 'ok')])
        self.assertTrue(tool.cached(manifest['entries'][0], self.fixture.cache))

    def test_a_wrong_sum_leaves_nothing(self):
        manifest = manifest_of(texture_entry(self.url, _sum(b'something else')))
        with self.assertRaises(tool.FetchError):
            tool.fetch(manifest, self.fixture.cache)
        folder = self.fixture.cache / 'asphalt'
        self.assertEqual(list(folder.iterdir()), [])
        self.assertFalse(tool.cached(manifest['entries'][0], self.fixture.cache))

    def test_a_verified_file_is_never_overwritten(self):
        manifest = manifest_of(texture_entry(self.url, _sum(self.data)))
        tool.fetch(manifest, self.fixture.cache)
        # The source changes; the manifest now expects the new bytes.
        (self.fixture.source / 'asphalt.jpg').write_bytes(b'new bytes')
        manifest['entries'][0]['files'][0]['sha256'] = _sum(b'new bytes')
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'mismatch')
        self.assertEqual((self.fixture.cache / 'asphalt/color.jpg').read_bytes(), self.data)
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[0][1], 'mismatch')

    def test_unpinned_needs_pin(self):
        manifest = manifest_of(texture_entry(self.url, None))
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'unpinned')
        self.assertFalse((self.fixture.cache / 'asphalt/color.jpg').exists())
        self.assertEqual(tool.fetch(manifest, self.fixture.cache, pin=True)[0][2], 'pinned')
        self.assertEqual(manifest['entries'][0]['files'][0]['sha256'], _sum(self.data))
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'kept')

    def test_a_cached_unpinned_file_is_pinned_from_disk(self):
        manifest = manifest_of(texture_entry(self.url, None))
        target = self.fixture.cache / 'asphalt/color.jpg'
        target.parent.mkdir(parents=True)
        target.write_bytes(b'placed by hand')
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'unpinned')
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[0][1], 'unpinned')
        self.assertEqual(tool.fetch(manifest, self.fixture.cache, pin=True)[0][2], 'pinned')
        self.assertEqual(manifest['entries'][0]['files'][0]['sha256'], _sum(b'placed by hand'))

    def test_missing_source_and_unknown_id(self):
        manifest = manifest_of(texture_entry(self.url + '.gone', _sum(self.data)))
        with self.assertRaises(tool.FetchError):
            tool.fetch(manifest, self.fixture.cache)
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[0][1], 'missing')
        with self.assertRaises(tool.ManifestError):
            tool.fetch(manifest, self.fixture.cache, ['nothing'])

    def test_a_file_not_hosted_yet_is_placed_by_hand(self):
        manifest = manifest_of(texture_entry(None, _sum(self.data)))
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'unhosted')
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[0][1], 'missing')
        target = self.fixture.cache / 'asphalt/color.jpg'
        target.parent.mkdir(parents=True)
        target.write_bytes(self.data)
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'kept')

    def test_a_web_page_in_place_of_the_file_is_refused(self):
        url = self.fixture.file('sign-in.html', b'<html>Sign in</html>')
        manifest = manifest_of(texture_entry(url, None))
        with self.assertRaises(tool.FetchError):
            tool.fetch(manifest, self.fixture.cache, pin=True)
        self.assertEqual(list((self.fixture.cache / 'asphalt').iterdir()), [])

    def test_only_named_entries_are_fetched(self):
        other = texture_entry(self.url, _sum(self.data), 'other', 'other/color.jpg')
        manifest = manifest_of(texture_entry(self.url, _sum(self.data)), other)
        report = tool.fetch(manifest, self.fixture.cache, ['other'])
        self.assertEqual(report, [('other', 'other/color.jpg', 'fetched')])
        self.assertFalse((self.fixture.cache / 'asphalt/color.jpg').exists())

    def test_an_archive_is_verified_then_extracted(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as bundle:
            bundle.writestr('Scan_Color.jpg', b'color texels')
            bundle.writestr('Scan_NormalGL.jpg', b'normal texels')
        data = buffer.getvalue()
        url = self.fixture.file('scan.zip', data)
        entry = texture_entry(url, None)
        entry['files'] = [{
            'role': 'archive', 'url': url, 'sha256': _sum(data), 'path': 'scan.zip',
            'extract': [
                {'role': 'albedo', 'member': 'Scan_Color.jpg', 'path': 'scan/color.jpg'},
                {'role': 'normal', 'member': 'Scan_NormalGL.jpg', 'path': 'scan/normal.jpg'},
            ],
        }]
        manifest = manifest_of(entry)
        tool.check_manifest(manifest)
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'fetched')
        self.assertEqual((self.fixture.cache / 'scan/color.jpg').read_bytes(), b'color texels')
        self.assertTrue(tool.cached(entry, self.fixture.cache))
        # A member removed by hand comes back from the kept archive.
        (self.fixture.cache / 'scan/normal.jpg').unlink()
        self.assertFalse(tool.cached(entry, self.fixture.cache))
        self.assertEqual(tool.fetch(manifest, self.fixture.cache)[0][2], 'kept')
        self.assertEqual((self.fixture.cache / 'scan/normal.jpg').read_bytes(), b'normal texels')
        entry['files'][0]['extract'][1]['member'] = 'Missing.jpg'
        (self.fixture.cache / 'scan/normal.jpg').unlink()
        with self.assertRaises(tool.FetchError):
            tool.fetch(manifest, self.fixture.cache)

    def test_corrupt_extracted_member_is_reported_and_never_overwritten(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as bundle:
            bundle.writestr('color.jpg', b'original pixels')
        data = buffer.getvalue()
        url = self.fixture.file('checked.zip', data)
        entry = texture_entry(url, None)
        entry['files'] = [{
            'role': 'archive', 'url': url, 'sha256': _sum(data), 'path': 'checked.zip',
            'extract': [{'role': 'albedo', 'member': 'color.jpg', 'path': 'scan/color.jpg'}],
        }]
        manifest = manifest_of(entry)
        tool.fetch(manifest, self.fixture.cache)
        extracted = self.fixture.cache / 'scan/color.jpg'
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[1], ('scan/color.jpg', 'ok'))
        extracted.write_bytes(b'corrupted pixels')
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[1], ('scan/color.jpg', 'mismatch'))
        with self.assertRaisesRegex(tool.FetchError, 'extracted member differs'):
            tool.fetch(manifest, self.fixture.cache)
        self.assertEqual(extracted.read_bytes(), b'corrupted pixels')
        extracted.unlink()
        self.assertEqual(tool.verify(manifest, self.fixture.cache)[1], ('scan/color.jpg', 'missing'))
        tool.fetch(manifest, self.fixture.cache)
        self.assertEqual(extracted.read_bytes(), b'original pixels')

    def test_command_line_pins_into_the_manifest(self):
        path = self.fixture.root / 'manifest.json'
        path.write_text(json.dumps(manifest_of(texture_entry(self.url, None))))
        common = ['--manifest', str(path), '--cache', str(self.fixture.cache)]
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(tool.main(common + ['check']), 0)
            self.assertEqual(tool.main(common + ['fetch']), 0)
            self.assertEqual(tool.main(common + ['fetch', '--pin']), 0)
            self.assertEqual(tool.main(common + ['verify']), 0)
            self.assertEqual(tool.main(common + ['status']), 0)
        self.assertIn('pinned', out.getvalue())
        self.assertIn('cached', out.getvalue())
        saved = json.loads(path.read_text())
        self.assertEqual(saved['entries'][0]['files'][0]['sha256'], _sum(self.data))
        (self.fixture.cache / 'asphalt/color.jpg').write_bytes(b'tampered')
        with redirect_stdout(io.StringIO()):
            self.assertEqual(tool.main(common + ['verify']), 1)
            self.assertEqual(tool.main(common + ['fetch']), 1)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as bundle:
            bundle.writestr('color.jpg', b'original pixels')
        self.data = buffer.getvalue()
        self.item = {
            'role': 'archive', 'url': 'https://example.org/scan.zip',
            'sha256': _sum(self.data), 'path': 'scan.zip',
            'extract': [{'role': 'albedo', 'member': 'color.jpg', 'path': 'scan/color.jpg'}],
        }
        entry = texture_entry(self.item['url'], self.item['sha256'])
        entry['files'] = [self.item]
        self.manifest = manifest_of(entry)
        self.original = copy.deepcopy(self.manifest)
        self.archive = self.fixture.cache / 'scan.zip'
        self.extracted = self.fixture.cache / 'scan/color.jpg'

    def tearDown(self):
        self.fixture.close()

    def _place_archive(self, data=None):
        self.fixture.cache.mkdir(exist_ok=True)
        self.archive.write_bytes(self.data if data is None else data)

    def _cli(self, *args):
        path = self.fixture.root / 'manifest.json'
        path.write_text(json.dumps(self.manifest), encoding='utf-8')
        before = path.read_bytes()
        with redirect_stdout(io.StringIO()) as out:
            result = tool.main(['--manifest', str(path), '--cache', str(self.fixture.cache), *args])
        self.assertEqual(path.read_bytes(), before)
        return result, out.getvalue()

    def test_offline_extracts_then_repairs_only_missing_members_without_urls(self):
        self._place_archive()
        with patch.object(tool.urllib.request, 'urlopen', side_effect=AssertionError('network access')):
            self.assertEqual(self._cli('fetch', 'asphalt', '--offline')[0], 0)
            self.assertEqual(self.extracted.read_bytes(), b'original pixels')
            self.assertEqual(self._cli('verify', 'asphalt', '--strict')[0], 0)
            self.extracted.unlink()
            self.assertEqual(self._cli('verify', '--strict', 'asphalt')[0], 1)
            self.assertEqual(self._cli('fetch', '--offline', 'asphalt')[0], 0)
            self.assertEqual(self.extracted.read_bytes(), b'original pixels')
            self.assertEqual(self._cli('verify', 'asphalt', '--strict')[0], 0)
        self.assertEqual(self.manifest, self.original)
        self.assertEqual(self.archive.read_bytes(), self.data)

    def test_offline_missing_archives_fail_without_creating_cache_or_opening_urls(self):
        for url in (self.item['url'], None, self.fixture.source.as_uri()):
            with self.subTest(url=url), patch.object(tool.urllib.request, 'urlopen') as opener:
                self.item['url'] = url
                result, output = self._cli('fetch', '--offline')
                self.assertEqual(result, 1)
                self.assertIn('missing', output)
                opener.assert_not_called()
                self.assertFalse(self.fixture.cache.exists())

    def test_offline_corrupt_archive_is_unchanged_and_never_extracted(self):
        self._place_archive(b'corrupt archive')
        with patch.object(tool, '_download') as download, patch.object(tool, '_extract') as extract:
            result, output = self._cli('fetch', '--offline')
            self.assertEqual(result, 1)
            self.assertIn('mismatch', output)
            download.assert_not_called()
            extract.assert_not_called()
        self.assertEqual(self.archive.read_bytes(), b'corrupt archive')
        self.assertFalse(self.extracted.exists())
        self.assertEqual(self.manifest, self.original)

    def test_offline_pinned_nonarchive_checks_bytes_without_opening_urls(self):
        data = b'plain texture pixels'
        self.manifest = manifest_of(texture_entry('https://example.org/color.jpg', _sum(data)))
        original = copy.deepcopy(self.manifest)
        target = self.fixture.cache / 'asphalt/color.jpg'
        with patch.object(tool.urllib.request, 'urlopen') as opener:
            self.assertEqual(self._cli('fetch', '--offline')[0], 1)
            target.parent.mkdir(parents=True)
            target.write_bytes(data)
            result, output = self._cli('fetch', '--offline')
            self.assertEqual(result, 0)
            self.assertIn('kept', output)
            self.assertEqual(self._cli('verify', '--strict')[0], 0)
            target.write_bytes(b'corrupt texture pixels')
            result, output = self._cli('fetch', '--offline')
            self.assertEqual(result, 1)
            self.assertIn('mismatch', output)
            self.assertEqual(self._cli('verify', '--strict')[0], 1)
            opener.assert_not_called()
        self.assertEqual(target.read_bytes(), b'corrupt texture pixels')
        self.assertEqual(self.manifest, original)

    def test_offline_corrupt_member_is_unchanged_and_fails_verification(self):
        self._place_archive()
        tool.fetch(self.manifest, self.fixture.cache, offline=True)
        self.extracted.write_bytes(b'corrupt pixels')
        with patch.object(tool.urllib.request, 'urlopen') as opener:
            with self.assertRaisesRegex(tool.FetchError, 'extracted member differs'):
                tool.fetch(self.manifest, self.fixture.cache, offline=True)
            self.assertEqual(self._cli('verify', '--strict')[0], 1)
            opener.assert_not_called()
        self.assertEqual(self.extracted.read_bytes(), b'corrupt pixels')

    def test_offline_unpinned_files_are_never_trusted(self):
        self.item['sha256'] = None
        for present in (False, True):
            if present:
                self._place_archive()
            with self.subTest(present=present), patch.object(tool, '_download') as download:
                result, output = self._cli('fetch', '--offline')
                self.assertEqual(result, 1)
                self.assertIn('unpinned', output)
                self.assertEqual(self._cli('verify', '--strict')[0], 1)
                self.assertEqual(self._cli('verify')[0], 0)
                self.assertIsNone(self.item['sha256'])
                self.assertFalse(self.extracted.exists())
                download.assert_not_called()

    def test_offline_cannot_pin_through_api_or_cli(self):
        self.item['sha256'] = None
        with self.assertRaisesRegex(tool.FetchError, 'cannot pin'):
            tool.fetch(self.manifest, self.fixture.cache, pin=True, offline=True)
        with self.assertRaisesRegex(tool.FetchError, 'cannot pin'):
            tool.fetch_file(self.item, self.fixture.cache, pin=True, offline=True)
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stopped:
            self._cli('fetch', '--offline', '--pin')
        self.assertEqual(stopped.exception.code, 2)
        self.assertIsNone(self.item['sha256'])
        self.assertFalse(self.fixture.cache.exists())

    def test_strict_verification_is_opt_in_and_selection_excludes_other_missing_files(self):
        self.manifest['entries'].append(texture_entry(None, _sum(b'other'), 'other', 'other.jpg'))
        self.assertEqual(self._cli('verify')[0], 0)
        self.assertEqual(self._cli('verify', '--strict')[0], 1)
        self._place_archive()
        self.assertEqual(self._cli('fetch', '--offline', 'asphalt')[0], 0)
        self.assertEqual(self._cli('verify', '--strict', 'asphalt')[0], 0)
        self.assertEqual(self._cli('verify', '--strict')[0], 1)
        self.assertEqual(self._cli('fetch', '--offline')[0], 1)
        self.assertEqual(tool.verify(self.manifest, self.fixture.cache, ['asphalt']),
                         [('scan.zip', 'ok'), ('scan/color.jpg', 'ok')])

    def test_unknown_selection_is_rejected_before_any_cache_work(self):
        self._place_archive()
        with patch.object(tool, 'fetch_file') as fetcher, patch.object(tool, 'sha256_of') as hasher:
            with self.assertRaisesRegex(tool.ManifestError, 'no entry'):
                tool.fetch(self.manifest, self.fixture.cache, ['asphalt', 'unknown'], offline=True)
            with self.assertRaisesRegex(tool.ManifestError, 'no entry'):
                tool.verify(self.manifest, self.fixture.cache, ['asphalt', 'unknown'])
            fetcher.assert_not_called()
            hasher.assert_not_called()

    def test_permission_quota_and_missing_http_responses_leave_no_download(self):
        for code in (403, 429, 404):
            error = HTTPError(self.item['url'], code, 'synthetic failure', {}, None)
            with self.subTest(code=code), patch.object(tool.urllib.request, 'urlopen', side_effect=error) as opener:
                with self.assertRaisesRegex(tool.FetchError, str(code)):
                    tool.fetch(self.manifest, self.fixture.cache)
                opener.assert_called_once()
                self.assertEqual(list(self.fixture.cache.iterdir()), [])
                self.assertEqual(self.manifest, self.original)

    def test_html_permission_and_quota_pages_are_refused_even_if_mislabeled(self):
        for content_type in ('text/html', 'application/octet-stream'):
            for body in (b'<html>Sign in for permission</html>', b'<html>Download quota exceeded</html>'):
                response = io.BytesIO(body)
                response.headers = Message()
                response.headers['Content-Type'] = content_type
                with self.subTest(content_type=content_type, body=body):
                    with patch.object(tool.urllib.request, 'urlopen', return_value=response):
                        with self.assertRaises(tool.FetchError):
                            tool.fetch(self.manifest, self.fixture.cache)
                    self.assertEqual(list(self.fixture.cache.iterdir()), [])
                    self.assertEqual(self.manifest, self.original)

    def test_synthetic_clean_cache_download_verifies_before_extracting(self):
        response = io.BytesIO(self.data)
        response.headers = Message()
        response.headers['Content-Type'] = 'application/zip'
        with patch.object(tool.urllib.request, 'urlopen', return_value=response) as opener:
            self.assertEqual(tool.fetch(self.manifest, self.fixture.cache)[0][2], 'fetched')
            opener.assert_called_once()
        self.assertEqual(self.archive.read_bytes(), self.data)
        self.assertEqual(self.extracted.read_bytes(), b'original pixels')
        self.assertEqual(self._cli('verify', '--strict')[0], 0)
        self.assertEqual(self.manifest, self.original)


class CreditTests(unittest.TestCase):
    def test_committed_attribution_matches_every_manifest_entry(self):
        manifest = tool.load_manifest()
        expected = tool.credits(manifest, everything=True)
        path = tool.MANIFEST.parent / 'ATTRIBUTION.md'
        self.assertEqual(path.read_text(encoding='utf-8'), expected)
        required = [e for e in manifest['entries'] if e['license'] == 'CC-BY-4.0']
        self.assertEqual(len(required), 47)
        for entry in required:
            self.assertIn(entry['title'], expected)
            self.assertIn(entry['author'], expected)
            self.assertIn(entry['source'], expected)
            self.assertIn(entry['changes'], expected)
        self.assertIn('https://creativecommons.org/licenses/by/4.0/', expected)


    def test_cc_by_entries_are_credited(self):
        free = texture_entry('https://example.org/a.jpg', None)
        scanned = texture_entry('https://example.org/b.jpg', None, 'bricks', 'bricks/color.jpg')
        scanned.update(license='CC-BY-4.0', title='Old Bricks', author='C. Mason',
                       source='https://example.org/bricks', changes='Resized to 2048 texels.')
        manifest = manifest_of(free, scanned)
        text = tool.credits(manifest)
        self.assertIn('- "Old Bricks" by C. Mason, https://example.org/bricks, CC BY 4.0 '
                      '(https://creativecommons.org/licenses/by/4.0/). Changes: Resized to 2048 texels.',
                      text)
        self.assertNotIn('asphalt', text)
        everything = tool.credits(manifest, everything=True)
        self.assertIn('"asphalt" by A. Scanner', everything)
        self.assertIn('No CC BY entry', tool.credits(manifest_of(free)))

    def test_credits_command_writes_a_file(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'credits.md'
            self.assertEqual(tool.main(['credits', '--all', '--output', str(output)]), 0)
            self.assertTrue(output.read_text().startswith('## Credits'))


if __name__ == '__main__':
    unittest.main()
