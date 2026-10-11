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
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from email.message import Message
from unittest.mock import patch
from urllib.error import HTTPError, URLError

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
            'id': 'town02', 'kind': 'town', 'license': 'CC-BY-4.0', 'author': 'B',
            'source': 'https://example.org/town', 'provenance': 'p',
            'files': [{'role': 'model', 'url': 'https://example.org/t.gltf',
                       'sha256': None, 'path': 't.gltf'}],
        }
        tool.check_manifest(manifest_of(town, bindings={'town.Town02': 'town02'}))

    def test_every_repository_carla_entry_keeps_attribution_and_integrity(self):
        # Issue #309: each converted CARLA archive keeps its exact sum, its
        # upstream release, its changes, the CARLA Team credit and the
        # CC BY 4.0 link, whatever host serves it.
        manifest = tool.load_manifest()
        carla = [e for e in manifest['entries'] if e['id'].startswith('carla.')]
        self.assertEqual(len(carla), 47)
        self.assertEqual(sum(e['kind'] == 'model' for e in carla), 41)
        self.assertEqual(sum(e['kind'] == 'town' for e in carla), 6)
        attribution = tool.credits(manifest)
        for entry in carla:
            with self.subTest(entry=entry['id']):
                self.assertEqual(entry['license'], 'CC-BY-4.0')
                self.assertEqual(entry['author'], 'CARLA Team (Computer Vision Center)')
                release = tool.CARLA_RELEASE.fullmatch(entry['source'])
                self.assertIsNotNone(release)
                self.assertIn('CARLA ' + release.group(1), entry['provenance'])
                self.assertTrue(entry['changes'].strip())
                archives = [f for f in entry['files'] if f['role'] == 'archive']
                self.assertEqual(len(archives), 1)
                self.assertTrue(tool._is_sum(archives[0]['sha256']))
                self.assertIn(f'"{entry["title"]}" by CARLA Team (Computer Vision Center), '
                              f'{entry["source"]}, CC BY 4.0 '
                              '(https://creativecommons.org/licenses/by/4.0/). '
                              f'Changes: {entry["changes"]}', attribution)

    def test_a_carla_entry_that_loses_credit_release_changes_or_sum_is_refused(self):
        good = copy.deepcopy(next(e for e in tool.load_manifest()['entries']
                                  if e['id'] == 'carla.vehicle.audi.a2'))
        tool.check_manifest(manifest_of(good))
        changes = [
            lambda e: e.update(license='CC0-1.0'),
            lambda e: e.update(author='Someone Else'),
            lambda e: e.update(source='https://carla.org/'),
            lambda e: e.update(source='https://github.com/carla-simulator/carla/releases/tag/latest'),
            lambda e: e.update(provenance='A CARLA vehicle.'),
            lambda e: e.update(source='https://github.com/carla-simulator/carla/releases/tag/0.9.15'),
            lambda e: e.pop('changes'),
            lambda e: e.update(changes=' '),
            lambda e: e.update(changes=7),
            lambda e: e['files'][0].update(sha256=None),
        ]
        for index, change in enumerate(changes):
            entry = copy.deepcopy(good)
            change(entry)
            with self.subTest(index=index), self.assertRaises(tool.ManifestError):
                tool.check_manifest(manifest_of(entry))

    def test_carla_provenance_matches_a_complete_release_name(self):
        good = copy.deepcopy(next(e for e in tool.load_manifest()['entries']
                                  if e['id'] == 'carla.vehicle.audi.a2'))
        # A release prefix is not the same upstream release.
        prefix = copy.deepcopy(good)
        prefix['source'] = 'https://github.com/carla-simulator/carla/releases/tag/0.9.1'
        with self.assertRaisesRegex(tool.ManifestError, 'provenance must name CARLA 0.9.1'):
            tool.check_manifest(manifest_of(prefix))
        for provenance in ('CARLA 0.9.160', 'CARLA 0.9.16.1', 'CARLA 0.9.16.rc1',
                           'CARLA 0.9.16rc1', 'CARLA 0.9.16-rc1', 'CARLA 0.9.16+build.1',
                           'NOTCARLA 0.9.16', 'CARLA 0.9.16_extra'):
            entry = copy.deepcopy(good)
            entry['provenance'] = provenance
            with self.subTest(provenance=provenance), self.assertRaises(tool.ManifestError):
                tool.check_manifest(manifest_of(entry))
        for provenance in ('CARLA 0.9.16', "CARLA 0.9.16's own vehicle",
                           'CARLA 0.9.16. Converted assets.', '(CARLA 0.9.16), converted.'):
            entry = copy.deepcopy(good)
            entry['provenance'] = provenance
            with self.subTest(provenance=provenance):
                tool.check_manifest(manifest_of(entry))

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

    def test_drive_interstitial_pages_are_named_as_web_pages_even_if_mislabeled(self):
        # Drive sends a page, not the file, for a file it does not share,
        # for a used-up download quota and for its virus-scan confirmation.
        pages = (b'<!DOCTYPE html><html><title>Google Drive - Virus scan warning</title>',
                 b'\n  <html><body>Google Drive - Quota exceeded</body></html>',
                 b'<HTML><title>Sign in - Google Accounts</title>')
        for body in pages:
            response = io.BytesIO(body)
            response.headers = Message()
            response.headers['Content-Type'] = 'application/octet-stream'
            with self.subTest(body=body):
                with patch.object(tool.urllib.request, 'urlopen', return_value=response):
                    with self.assertRaisesRegex(tool.FetchError, 'web page.*quota'):
                        tool.fetch(self.manifest, self.fixture.cache)
                self.assertEqual(list(self.fixture.cache.iterdir()), [])
                self.assertEqual(self.manifest, self.original)

    def test_a_proxy_that_refuses_the_tunnel_is_not_tried_again(self):
        # urllib wraps the refusal: <urlopen error Tunnel connection failed: 403 Forbidden>.
        for error in (URLError(OSError('Tunnel connection failed: 403 Forbidden')),
                      OSError('Tunnel connection failed: 407 Proxy Authentication Required')):
            with self.subTest(error=error), \
                    patch.object(tool.urllib.request, 'urlopen', side_effect=error) as opener, \
                    patch.object(tool.time, 'sleep') as sleeper:
                with self.assertRaisesRegex(tool.FetchError, 'Tunnel connection failed: 40'):
                    tool.fetch(self.manifest, self.fixture.cache)
                opener.assert_called_once()
                sleeper.assert_not_called()
                self.assertEqual(list(self.fixture.cache.iterdir()), [])

    def test_a_dropped_connection_is_tried_again_then_verified(self):
        response = io.BytesIO(self.data)
        response.headers = Message()
        response.headers['Content-Type'] = 'application/zip'
        effects = [ConnectionResetError('reset'), response]
        with patch.object(tool.urllib.request, 'urlopen', side_effect=effects) as opener, \
                patch.object(tool.time, 'sleep') as sleeper:
            self.assertEqual(tool.fetch(self.manifest, self.fixture.cache)[0][2], 'fetched')
        self.assertEqual(opener.call_count, 2)
        sleeper.assert_called_once()
        self.assertEqual(self.extracted.read_bytes(), b'original pixels')

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


class StageRenderTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        self.addCleanup(self.fixture.close)
        self.output = self.fixture.root / 'distribution'
        self.manifest_path = self.fixture.root / 'custom-manifest.json'
        free = texture_entry('https://example.org/asphalt.jpg', None)
        scanned = texture_entry(None, _sum(b'archive'), 'brick', 'brick.jpg')
        scanned.update(license='CC-BY-4.0', author='Custom Author', title='Custom Brick',
                       changes='Converted for this historical render.')
        self.manifest = manifest_of(free, scanned)
        self.manifest_bytes = (' \r\n' + json.dumps(self.manifest, indent=4) + '\r\n\t').encode()
        self.manifest_path.write_bytes(self.manifest_bytes)
        self.render = self.fixture.source / 'render.png'
        self.render.write_bytes(b'\x89PNG\r\n\x1a\n\x00exact fixture bytes\xff')
        self.other = self.fixture.source / 'other.apng'
        self.other.write_bytes(b'animation bytes\x00\xff')

    def run_stage(self, *renders):
        error = io.StringIO()
        with redirect_stderr(error):
            result = tool.main(['--manifest', str(self.manifest_path),
                                '--cache', str(self.fixture.cache), 'stage-render',
                                '--output', str(self.output),
                                *[str(path) for path in renders or (self.render,)]])
        return result, error.getvalue()

    def test_exact_copies_custom_manifest_and_credits_leave_sources_and_cache_unchanged(self):
        self.fixture.cache.mkdir()
        (self.fixture.cache / 'sentinel.zip').write_bytes(b'pinned archive untouched')
        (self.fixture.source / 'render.credits.md').write_bytes(b'do not copy this sidecar')
        before = {path: path.read_bytes() for path in self.fixture.root.rglob('*') if path.is_file()}
        self.assertEqual(self.run_stage(self.render, self.other), (0, ''))
        self.assertEqual({p.name for p in self.output.iterdir()},
                         {'render.png', 'other.apng', 'manifest.json', 'ATTRIBUTION.md'})
        for source in (self.render, self.other):
            self.assertEqual((self.output / source.name).read_bytes(), before[source])
        self.assertEqual((self.output / 'manifest.json').read_bytes(), self.manifest_bytes)
        attribution = (self.output / 'ATTRIBUTION.md').read_text()
        self.assertEqual(attribution, tool.credits(self.manifest, everything=True))
        self.assertIn('Custom Brick', attribution)
        self.assertIn('Custom Author', attribution)
        self.assertIn('Converted for this historical render.', attribution)
        self.assertIn('CC0 entries', attribution)
        self.assertNotIn('CARLA Team', attribution)
        for path, data in before.items():
            self.assertEqual(path.read_bytes(), data, path)
        self.assertEqual(list(self.fixture.cache.iterdir()), [self.fixture.cache / 'sentinel.zip'])
        self.assertFalse((self.fixture.source / 'manifest.json').exists())
        self.assertFalse((self.fixture.source / 'ATTRIBUTION.md').exists())

    def test_manifest_is_read_parsed_and_validated_once_for_both_outputs(self):
        original_credits = tool.credits

        def change_disk_after_snapshot(manifest, everything=False):
            self.manifest_path.write_text(json.dumps(manifest_of()))
            return original_credits(manifest, everything)

        with patch.object(tool, '_stage_source', wraps=tool._stage_source) as opened, \
                patch.object(tool.json, 'loads', wraps=json.loads) as parsed, \
                patch.object(tool, 'check_manifest', wraps=tool.check_manifest) as checked, \
                patch.object(tool, 'credits', side_effect=change_disk_after_snapshot) as credited:
            self.assertEqual(self.run_stage(), (0, ''))
        self.assertEqual(sum(call.args == (self.manifest_path,) for call in opened.call_args_list), 1)
        parsed.assert_called_once()
        checked.assert_called_once()
        credited.assert_called_once_with(checked.call_args.args[0], everything=True)
        self.assertIs(credited.call_args.args[0], checked.call_args.args[0])
        self.assertEqual((self.output / 'manifest.json').read_bytes(), self.manifest_bytes)
        self.assertEqual((self.output / 'ATTRIBUTION.md').read_text(),
                         original_credits(self.manifest, everything=True))

    def test_default_manifest_is_supported(self):
        with redirect_stderr(io.StringIO()):
            self.assertEqual(tool.main(['stage-render', '--output', str(self.output),
                                        str(self.render)]), 0)
        self.assertEqual((self.output / 'manifest.json').read_bytes(), tool.MANIFEST.read_bytes())
        self.assertEqual((self.output / 'ATTRIBUTION.md').read_bytes(),
                         (tool.MANIFEST.parent / 'ATTRIBUTION.md').read_bytes())

    def test_no_cache_network_fetch_export_or_native_process_is_needed(self):
        def forbidden(*args, **kwargs):
            self.fail('staging invoked a network, cache, export or native entry point')
        with patch.object(tool, 'fetch', side_effect=forbidden), \
                patch.object(tool, 'verify', side_effect=forbidden), \
                patch.object(tool, 'cached', side_effect=forbidden), \
                patch.object(tool, '_download', side_effect=forbidden), \
                patch.object(tool, '_extract', side_effect=forbidden), \
                patch.object(tool, 'save_manifest', side_effect=forbidden), \
                patch.object(tool.urllib.request, 'urlopen', side_effect=forbidden), \
                patch.object(subprocess, 'run', side_effect=forbidden), \
                patch.object(subprocess, 'Popen', side_effect=forbidden):
            self.assertEqual(self.run_stage(), (0, ''))
        self.assertFalse(self.fixture.cache.exists())

    def test_bad_render_inputs_fail_before_creating_any_output(self):
        link = self.fixture.source / 'linked.png'
        link.symlink_to(self.render)
        dangling = self.fixture.source / 'dangling.png'
        dangling.symlink_to(self.fixture.source / 'missing.png')
        fifo = self.fixture.source / 'pipe.png'
        os.mkfifo(fifo)
        for bad in (self.fixture.source / 'missing.png', self.fixture.source, link, dangling, fifo):
            with self.subTest(path=bad):
                result, error = self.run_stage(self.render, bad)
                self.assertEqual(result, 1)
                self.assertTrue(error)
                self.assertFalse(self.output.exists())

    def test_duplicate_files_basename_collisions_and_reserved_names_are_refused(self):
        elsewhere = self.fixture.root / 'elsewhere'
        elsewhere.mkdir()
        hardlink = elsewhere / 'hardlink.png'
        os.link(self.render, hardlink)
        collision = elsewhere / self.render.name
        collision.write_bytes(b'other bytes')
        case_collision = elsewhere / 'RENDER.PNG'
        case_collision.write_bytes(b'case collision')
        for duplicate in (self.render, hardlink, collision, case_collision):
            with self.subTest(path=duplicate):
                self.assertEqual(self.run_stage(self.render, duplicate)[0], 1)
                self.assertFalse(self.output.exists())
        for name in ('manifest.json', 'MANIFEST.JSON', 'ATTRIBUTION.md', 'attribution.MD'):
            reserved = elsewhere / name
            reserved.write_bytes(b'reserved')
            with self.subTest(name=name):
                self.assertEqual(self.run_stage(reserved)[0], 1)
                self.assertFalse(self.output.exists())

    def test_invalid_manifest_inputs_fail_before_creating_output(self):
        for data in (b'{broken', b'\xff', b'{}', b'{"format": 1, "entries": false}'):
            with self.subTest(data=data):
                self.manifest_path.write_bytes(data)
                self.assertEqual(self.run_stage()[0], 1)
                self.assertFalse(self.output.exists())
        self.manifest_path.unlink()
        self.assertEqual(self.run_stage()[0], 1)
        self.manifest_path.mkdir()
        self.assertEqual(self.run_stage()[0], 1)
        self.manifest_path.rmdir()
        for target in (self.render, self.fixture.source / 'missing.json'):
            self.manifest_path.symlink_to(target)
            self.assertEqual(self.run_stage()[0], 1)
            self.manifest_path.unlink()
        self.assertFalse(self.output.exists())

    def test_cli_requires_output_and_at_least_one_render(self):
        for args in (['stage-render'], ['stage-render', '--output', str(self.output)],
                     ['stage-render', str(self.render)]):
            with self.subTest(args=args), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    tool.main(args)
                self.assertEqual(raised.exception.code, 2)
        with self.assertRaisesRegex(tool.StageError, 'at least one'):
            tool.stage_render(self.manifest_path, self.output, [])
        self.assertFalse(self.output.exists())

    def test_existing_destinations_are_untouched_including_empty_and_dangling(self):
        self.output.write_bytes(b'existing file')
        self.assertEqual(self.run_stage()[0], 1)
        self.assertEqual(self.output.read_bytes(), b'existing file')
        self.output.unlink()
        self.output.mkdir()
        self.assertEqual(self.run_stage()[0], 1)
        self.assertEqual(list(self.output.iterdir()), [])
        (self.output / 'user.txt').write_bytes(b'user content')
        self.assertEqual(self.run_stage()[0], 1)
        self.assertEqual((self.output / 'user.txt').read_bytes(), b'user content')
        (self.output / 'user.txt').unlink()
        self.output.rmdir()
        for target in (self.fixture.source, self.fixture.root / 'missing'):
            self.output.symlink_to(target)
            self.assertEqual(self.run_stage()[0], 1)
            self.assertTrue(self.output.is_symlink())
            self.assertEqual(self.output.readlink(), target)
            self.output.unlink()

    def test_output_parent_must_exist(self):
        self.output = self.output / 'nested'
        self.assertEqual(self.run_stage()[0], 1)
        self.assertFalse(self.output.parent.exists())

    def test_destination_created_after_preflight_is_not_reused_or_removed(self):
        original_mkdir = Path.mkdir
        for kind in ('directory', 'file', 'symlink'):
            with self.subTest(kind=kind):
                def race(path, *args, **kwargs):
                    if path == self.output:
                        if kind == 'directory':
                            original_mkdir(path)
                            (path / 'user.txt').write_bytes(b'racing directory')
                        elif kind == 'file':
                            path.write_bytes(b'racing file')
                        else:
                            path.symlink_to(self.fixture.root / 'absent')
                    return original_mkdir(path, *args, **kwargs)
                with patch.object(Path, 'mkdir', race):
                    self.assertEqual(self.run_stage()[0], 1)
                if kind == 'directory':
                    self.assertEqual((self.output / 'user.txt').read_bytes(), b'racing directory')
                    (self.output / 'user.txt').unlink()
                    self.output.rmdir()
                elif kind == 'file':
                    self.assertEqual(self.output.read_bytes(), b'racing file')
                    self.output.unlink()
                else:
                    self.assertTrue(self.output.is_symlink())
                    self.output.unlink()

    def test_output_file_created_during_copy_is_never_overwritten(self):
        original_write = tool._stage_write
        for kind in ('file', 'symlink'):
            self.output = self.fixture.root / f'racing-output-{kind}'

            def insert_file(directory, name, source):
                target = self.output / name
                if kind == 'file':
                    target.write_bytes(b'racing user file')
                else:
                    target.symlink_to(self.other)
                original_write(directory, name, source)

            with self.subTest(kind=kind), patch.object(tool, '_stage_write', insert_file):
                result, error = self.run_stage()
            self.assertEqual(result, 1)
            self.assertIn('staging incomplete', error)
            target = self.output / self.render.name
            if kind == 'file':
                self.assertEqual(target.read_bytes(), b'racing user file')
            else:
                self.assertTrue(target.is_symlink())
                self.assertEqual(target.readlink(), self.other)
                self.assertEqual(self.other.read_bytes(), b'animation bytes\x00\xff')
            self.assertEqual(len(list(self.output.iterdir())), 1)

    def test_copy_failures_retain_partial_outputs_with_explicit_status(self):
        original_copy = tool.shutil.copyfileobj
        for fail_at in range(1, 5):
            self.output = self.fixture.root / f'failed-copy-{fail_at}'
            calls = 0

            def fail_copy(source, target):
                nonlocal calls
                calls += 1
                if calls == fail_at:
                    target.write(b'partial output')
                    raise OSError('injected copy failure')
                original_copy(source, target)

            with self.subTest(copy=fail_at), patch.object(tool.shutil, 'copyfileobj', fail_copy):
                result, error = self.run_stage(self.render, self.other)
            self.assertEqual(result, 1)
            self.assertIn('injected copy failure', error)
            self.assertIn('staging incomplete', error)
            self.assertIn(str(self.output.absolute()), error)
            self.assertEqual(len(list(self.output.iterdir())), fail_at)
            partial = (self.render.name, self.other.name, 'manifest.json', 'ATTRIBUTION.md')[fail_at - 1]
            self.assertEqual((self.output / partial).read_bytes(), b'partial output')
            if fail_at <= 2:
                self.assertFalse((self.output / 'manifest.json').exists())
                self.assertFalse((self.output / 'ATTRIBUTION.md').exists())
        self.assertEqual(self.manifest_path.read_bytes(), self.manifest_bytes)
        self.assertEqual(self.render.read_bytes(), b'\x89PNG\r\n\x1a\n\x00exact fixture bytes\xff')

    def test_direct_writer_failure_retains_partial_bytes_and_returns_failure(self):
        original_fdopen = os.fdopen

        class BrokenWriter:
            def __init__(self, stream):
                self.stream = stream

            def __enter__(self):
                self.stream.__enter__()
                return self

            def __exit__(self, *args):
                return self.stream.__exit__(*args)

            def write(self, data):
                self.stream.write(data[:3])
                raise OSError('injected write failure')

        def fail_write(fd, mode, *args, **kwargs):
            stream = original_fdopen(fd, mode, *args, **kwargs)
            return BrokenWriter(stream) if mode == 'wb' else stream

        with patch.object(tool.os, 'fdopen', fail_write):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('injected write failure', error)
        self.assertIn('staging incomplete', error)
        self.assertEqual((self.output / self.render.name).read_bytes(), self.render.read_bytes()[:3])
        self.assertFalse((self.output / 'manifest.json').exists())
        self.assertFalse((self.output / 'ATTRIBUTION.md').exists())

    def test_file_creation_failure_retains_prior_outputs_and_reports_incomplete(self):
        original_open = os.open

        def fail_open(path, *args, **kwargs):
            if path == 'ATTRIBUTION.md':
                raise OSError('injected output creation failure')
            return original_open(path, *args, **kwargs)

        with patch.object(tool.os, 'open', fail_open):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('injected output creation failure', error)
        self.assertIn('staging incomplete', error)
        self.assertEqual((self.output / self.render.name).read_bytes(), self.render.read_bytes())
        self.assertEqual((self.output / 'manifest.json').read_bytes(), self.manifest_bytes)
        self.assertFalse((self.output / 'ATTRIBUTION.md').exists())

    def test_failure_preserves_user_added_or_replaced_files(self):
        original_write = tool._stage_write
        for replacement in ('added', 'replaced', 'symlink'):
            self.output = self.fixture.root / f'failure-{replacement}'
            def fail_after_render(directory, name, source):
                if name == 'manifest.json':
                    if replacement == 'added':
                        (self.output / 'user.txt').write_bytes(b'user addition')
                    else:
                        target = self.output / self.render.name
                        target.unlink()
                        if replacement == 'replaced':
                            target.write_bytes(b'user replacement')
                        else:
                            target.symlink_to(self.other)
                    raise OSError('injected later failure')
                original_write(directory, name, source)

            with self.subTest(replacement=replacement), \
                    patch.object(tool, '_stage_write', fail_after_render):
                result, error = self.run_stage()
            self.assertEqual(result, 1)
            self.assertIn('staging incomplete', error)
            target = self.output / ('user.txt' if replacement == 'added' else self.render.name)
            self.assertEqual(len(list(self.output.iterdir())), 2 if replacement == 'added' else 1)
            if replacement == 'symlink':
                self.assertTrue(target.is_symlink())
                self.assertEqual(target.readlink(), self.other)
            else:
                self.assertEqual(target.read_bytes(),
                                 b'user addition' if replacement == 'added' else b'user replacement')

    def test_replaced_output_directory_is_left_untouched(self):
        original_write = tool._stage_write
        moved = self.fixture.root / 'moved-distribution'

        def replace_directory(directory, name, source):
            original_write(directory, name, source)
            if name == self.render.name:
                self.output.rename(moved)
                self.output.mkdir()
                (self.output / 'user.txt').write_bytes(b'user directory')

        with patch.object(tool, '_stage_write', replace_directory):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('staging incomplete', error)
        self.assertEqual((self.output / 'user.txt').read_bytes(), b'user directory')
        self.assertEqual({p.name for p in moved.iterdir()},
                         {self.render.name, 'manifest.json', 'ATTRIBUTION.md'})

    def test_failure_never_attempts_destructive_cleanup(self):
        with patch.object(tool.shutil, 'copyfileobj', side_effect=OSError('copy failed')), \
                patch.object(tool.os, 'unlink', side_effect=AssertionError('must not unlink')), \
                patch.object(Path, 'rmdir', side_effect=AssertionError('must not remove directories')):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('copy failed', error)
        self.assertIn('staging incomplete', error)
        self.assertIn(str(self.output.absolute()), error)
        self.assertTrue((self.output / self.render.name).exists())

    def test_directory_replaced_immediately_after_mkdir_survives_failure(self):
        original_mkdir = Path.mkdir
        moved = self.fixture.root / 'original-directory'

        def replace_after_mkdir(path, *args, **kwargs):
            result = original_mkdir(path, *args, **kwargs)
            if path == self.output:
                path.rename(moved)
                original_mkdir(path)
                (path / 'user.txt').write_bytes(b'racing user directory')
            return result

        with patch.object(Path, 'mkdir', replace_after_mkdir), \
                patch.object(tool.shutil, 'copyfileobj', side_effect=OSError('copy failed')):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('staging incomplete', error)
        self.assertEqual((self.output / 'user.txt').read_bytes(), b'racing user directory')
        self.assertTrue(moved.is_dir())

    def test_input_replaced_by_symlink_during_open_is_refused(self):
        original_open = os.open

        def replace_input(path, *args, **kwargs):
            if path == self.render:
                self.render.unlink()
                self.render.symlink_to(self.other)
            return original_open(path, *args, **kwargs)

        with patch.object(tool.os, 'open', replace_input):
            self.assertEqual(self.run_stage()[0], 1)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.other.read_bytes(), b'animation bytes\x00\xff')

    def test_input_replaced_by_regular_file_during_open_is_refused(self):
        original_open = os.open
        original_bytes = self.render.read_bytes()
        moved = self.fixture.source / 'original-render.png'

        def replace_input(path, *args, **kwargs):
            if path == self.render:
                self.render.rename(moved)
                self.render.write_bytes(b'replacement input')
            return original_open(path, *args, **kwargs)

        with patch.object(tool.os, 'open', replace_input):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('input changed while opening it', error)
        self.assertFalse(self.output.exists())
        self.assertEqual(moved.read_bytes(), original_bytes)
        self.assertEqual(self.render.read_bytes(), b'replacement input')

    def test_credits_stdout_flags_and_output_still_create_no_sidecars(self):
        common = ['--manifest', str(self.manifest_path), 'credits']
        before = {p for p in self.fixture.root.rglob('*')}
        for everything in (False, True):
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(tool.main([*common, *(['--all'] if everything else [])]), 0)
            self.assertEqual(output.getvalue(), tool.credits(self.manifest, everything))
            self.assertEqual({p for p in self.fixture.root.rglob('*')}, before)
        destination = self.fixture.root / 'custom-credits.md'
        self.assertEqual(tool.main([*common, '--output', str(destination)]), 0)
        self.assertEqual(destination.read_text(), tool.credits(self.manifest))
        self.assertEqual({p for p in self.fixture.root.rglob('*')}, before | {destination})


def zip_of(**members):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as bundle:
        for name, data in members.items():
            bundle.writestr(name, data)
    return buffer.getvalue()


class StageArchiveTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture()
        self.addCleanup(self.fixture.close)
        self.output = self.fixture.root / 'package'
        self.manifest_path = self.fixture.root / 'custom-manifest.json'
        # A real CARLA entry keeps its credit, release and changes. Its
        # archive is a small fixture with the same member names, so no
        # CARLA bytes are needed.
        real = next(e for e in tool.load_manifest()['entries'] if e['id'] == 'carla.vehicle.audi.a2')
        self.carla = copy.deepcopy(real)
        self.car = zip_of(**{member['member']: member['path'].encode()
                             for member in self.carla['files'][0]['extract']})
        self.wheel = zip_of(**{'wheel.gltf': b'{"wheel": 1}'})
        self.scan = zip_of(**{'Scan_Color.jpg': b'color texels'})
        self.carla['files'][0]['sha256'] = _sum(self.car)
        self.carla['files'][0]['url'] = None
        self.free = texture_entry(None, None, 'scan', 'unused.jpg')
        self.free['files'] = [{
            'role': 'archive', 'url': None, 'sha256': _sum(self.scan), 'path': 'scan.zip',
            'extract': [{'role': 'albedo', 'member': 'Scan_Color.jpg', 'path': 'scan/color.jpg'}],
        }]
        self.other = texture_entry('https://example.org/other.jpg', None, 'other', 'other.jpg')
        self.other.update(title='Unselected Entry')
        self.manifest = manifest_of(self.carla, self.free, self.other)
        self.write_manifest()
        self.archives = {self.carla['files'][0]['path']: self.car, 'scan.zip': self.scan}
        for path, data in self.archives.items():
            target = self.fixture.cache / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

    def write_manifest(self):
        self.manifest_bytes = (json.dumps(self.manifest, indent=4) + '\r\n').encode()
        self.manifest_path.write_bytes(self.manifest_bytes)

    def run_stage(self, *ids):
        error = io.StringIO()
        with redirect_stderr(error):
            result = tool.main(['--manifest', str(self.manifest_path),
                                '--cache', str(self.fixture.cache), 'stage-archive',
                                '--output', str(self.output),
                                *(ids or ('carla.vehicle.audi.a2', 'scan'))])
        return result, error.getvalue()

    def tree(self, root):
        return {path.relative_to(root).as_posix(): path.read_bytes()
                for path in root.rglob('*') if path.is_file()}

    def test_exact_pinned_archives_manifest_and_selected_credits(self):
        before = self.tree(self.fixture.root)
        self.assertEqual(self.run_stage(), (0, ''))
        staged = self.tree(self.output)
        self.assertEqual(set(staged), {*self.archives, 'manifest.json', 'ATTRIBUTION.md'})
        for path, data in self.archives.items():
            self.assertEqual(staged[path], data)
        self.assertEqual(staged['manifest.json'], self.manifest_bytes)
        attribution = staged['ATTRIBUTION.md'].decode()
        self.assertEqual(attribution, tool.credits(
            {'entries': [self.carla, self.free]}, everything=True))
        for text in ('CARLA Team (Computer Vision Center)', 'Audi A2 (CARLA)',
                     'https://creativecommons.org/licenses/by/4.0/',
                     'https://github.com/carla-simulator/carla/releases/tag/0.9.16',
                     self.carla['changes'], '"scan" by A. Scanner'):
            self.assertIn(text, attribution)
        self.assertNotIn('Unselected Entry', attribution)
        self.assertEqual(self.tree(self.fixture.root),
                         {**before, **{f'package/{k}': v for k, v in staged.items()}})

    def test_package_is_a_cache_root_for_offline_recovery(self):
        self.assertEqual(self.run_stage()[0], 0)
        common = ['--manifest', str(self.output / 'manifest.json'), '--cache', str(self.output)]
        with redirect_stdout(io.StringIO()) as out, \
                patch.object(tool.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            self.assertEqual(tool.main([*common, 'fetch', '--offline', 'carla.vehicle.audi.a2', 'scan']), 0)
            self.assertEqual(tool.main([*common, 'verify', '--strict', 'carla.vehicle.audi.a2', 'scan']), 0)
        self.assertNotIn('mismatch', out.getvalue())
        self.assertEqual((self.output / 'scan/color.jpg').read_bytes(), b'color texels')

    def test_no_network_fetch_extract_or_process_is_needed(self):
        def forbidden(*args, **kwargs):
            self.fail('staging invoked a network, fetch, extract or process entry point')
        with patch.object(tool, 'fetch', side_effect=forbidden), \
                patch.object(tool, '_download', side_effect=forbidden), \
                patch.object(tool, '_extract', side_effect=forbidden), \
                patch.object(tool, 'save_manifest', side_effect=forbidden), \
                patch.object(tool.urllib.request, 'urlopen', side_effect=forbidden), \
                patch.object(subprocess, 'run', side_effect=forbidden), \
                patch.object(subprocess, 'Popen', side_effect=forbidden):
            self.assertEqual(self.run_stage(), (0, ''))

    def test_shared_folders_hold_several_archives(self):
        self.carla['files'].append({
            'role': 'archive', 'url': None, 'sha256': _sum(self.wheel),
            'path': 'carla/vehicles/wheel.zip',
            'extract': [{'role': 'support', 'member': 'wheel.gltf', 'path': 'carla/wheel.gltf'}],
        })
        self.write_manifest()
        (self.fixture.cache / 'carla/vehicles/wheel.zip').write_bytes(self.wheel)
        self.assertEqual(self.run_stage('carla.vehicle.audi.a2')[0], 0)
        self.assertEqual(set(self.tree(self.output)),
                         {self.carla['files'][0]['path'], 'carla/vehicles/wheel.zip',
                          'manifest.json', 'ATTRIBUTION.md'})

    def test_different_missing_unpinned_or_linked_archives_create_no_output(self):
        archive = self.fixture.cache / 'scan.zip'
        archive.write_bytes(zip_of(**{'Scan_Color.jpg': b'rebuilt texels'}))
        result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('does not match the pinned', error)
        self.assertFalse(self.output.exists())
        archive.unlink()
        self.assertEqual(self.run_stage()[0], 1)
        self.assertFalse(self.output.exists())
        archive.symlink_to(self.fixture.cache / self.carla['files'][0]['path'])
        self.assertEqual(self.run_stage()[0], 1)
        self.assertFalse(self.output.exists())
        archive.unlink()
        archive.write_bytes(self.scan)
        self.free['files'][0]['sha256'] = None
        self.free['files'][0]['url'] = 'https://example.org/scan.zip'
        self.write_manifest()
        result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('no pinned sha256', error)
        self.assertFalse(self.output.exists())

    def test_bad_selections_and_manifests_create_no_output(self):
        for ids in (('missing.entry',), ('scan', 'scan'), ('other',)):
            with self.subTest(ids=ids):
                result, error = self.run_stage(*ids)
                self.assertEqual(result, 1)
                self.assertTrue(error)
                self.assertFalse(self.output.exists())
        with self.assertRaisesRegex(tool.StageError, 'at least one'):
            tool.stage_archive(self.manifest_path, self.fixture.cache, self.output, [])
        for data in (b'{broken', b'\xff', b'{}'):
            self.manifest_path.write_bytes(data)
            self.assertEqual(self.run_stage()[0], 1)
        self.assertFalse(self.output.exists())
        for args in (['stage-archive'], ['stage-archive', '--output', str(self.output)],
                     ['stage-archive', 'scan']):
            with self.subTest(args=args), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    tool.main(args)
                self.assertEqual(raised.exception.code, 2)

    def test_reserved_and_case_insensitive_path_clashes_are_refused(self):
        for first, second in (('MANIFEST.JSON', None), ('attribution.md', None),
                              ('Carla/a.zip', 'carla/b.zip'), ('a.zip', 'A.ZIP/b.zip'),
                              ('a/b.zip', 'A/B.ZIP')):
            with self.subTest(paths=(first, second)):
                self.free['files'][0]['path'] = first
                (self.fixture.cache / first).parent.mkdir(parents=True, exist_ok=True)
                (self.fixture.cache / first).write_bytes(self.scan)
                self.manifest['entries'] = [self.free]
                if second:
                    extra = copy.deepcopy(self.free)
                    extra.update(id='second')
                    extra['files'][0]['path'] = second
                    extra['files'][0]['extract'][0]['path'] = 'second/color.jpg'
                    self.manifest['entries'].append(extra)
                self.write_manifest()
                result, error = self.run_stage(*(('scan', 'second') if second else ('scan',)))
                self.assertEqual(result, 1)
                self.assertIn('clashes', error)
                self.assertFalse(self.output.exists())

    def test_existing_destinations_and_missing_parents_are_refused(self):
        self.output.mkdir()
        (self.output / 'user.txt').write_bytes(b'user content')
        self.assertEqual(self.run_stage()[0], 1)
        self.assertEqual(self.tree(self.output), {'user.txt': b'user content'})
        self.output = self.fixture.root / 'dangling'
        self.output.symlink_to(self.fixture.root / 'absent')
        self.assertEqual(self.run_stage()[0], 1)
        self.assertTrue(self.output.is_symlink())
        self.output = self.fixture.root / 'absent' / 'nested'
        self.assertEqual(self.run_stage()[0], 1)
        self.assertFalse(self.output.parent.exists())

    def test_archive_changed_after_preflight_is_reported_and_retained(self):
        original_write = tool._stage_write
        archive = self.fixture.cache / 'scan.zip'

        def change_archive(directory, name, source):
            if name == 'scan.zip':
                with open(archive, 'r+b') as stream:
                    stream.write(b'XX')
            original_write(directory, name, source)

        with patch.object(tool, '_stage_write', change_archive):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('changed from the pinned', error)
        self.assertIn('staging incomplete', error)
        self.assertIn(str(self.output.absolute()), error)
        self.assertEqual(set(self.tree(self.output)), {self.carla['files'][0]['path'], 'scan.zip'})
        self.assertFalse((self.output / 'manifest.json').exists())

    def test_late_failures_retain_partial_output_and_never_overwrite(self):
        original_open = os.open

        def fail_open(path, *args, **kwargs):
            if path == 'ATTRIBUTION.md':
                raise OSError('injected output creation failure')
            return original_open(path, *args, **kwargs)

        with patch.object(tool.os, 'open', fail_open):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('staging incomplete', error)
        self.assertEqual((self.output / 'manifest.json').read_bytes(), self.manifest_bytes)
        self.assertEqual((self.output / 'scan.zip').read_bytes(), self.scan)
        self.assertFalse((self.output / 'ATTRIBUTION.md').exists())

        self.output = self.fixture.root / 'racing'
        original_mkdir = os.mkdir

        def racing_folder(name, *args, **kwargs):
            original_mkdir(name, *args, **kwargs)
            if 'dir_fd' not in kwargs:
                return
            os.rmdir(name, dir_fd=kwargs['dir_fd'])
            os.symlink(str(self.fixture.source), name, dir_fd=kwargs['dir_fd'])

        with patch.object(tool.os, 'mkdir', racing_folder):
            result, error = self.run_stage()
        self.assertEqual(result, 1)
        self.assertIn('staging incomplete', error)
        self.assertEqual(list(self.fixture.source.iterdir()), [])
        self.assertTrue((self.output / 'carla').is_symlink())


    def test_replaced_child_directories_fail_without_deleting_replacements(self):
        original_write = tool._stage_write
        archive_name = Path(self.carla['files'][0]['path']).name
        for child in ('carla', 'carla/vehicles'):
            for moment in ('before archive', 'after archive', 'after metadata'):
                for replacement in ('directory', 'symlink', 'absent'):
                    case = f'{child.replace("/", "-")}-{moment.replace(" ", "-")}-{replacement}'
                    self.output = self.fixture.root / f'package-{case}'
                    moved = self.fixture.root / f'moved-{case}'
                    target = self.output / child
                    touched = False

                    def replace_child():
                        nonlocal touched
                        target.rename(moved)
                        if replacement == 'directory':
                            target.mkdir()
                            (target / 'user.txt').write_bytes(b'user replacement')
                        elif replacement == 'symlink':
                            target.symlink_to(self.fixture.source)
                        touched = True

                    def write_and_replace(directory, name, source):
                        if name == archive_name and moment == 'before archive':
                            replace_child()
                        original_write(directory, name, source)
                        if ((name == archive_name and moment == 'after archive')
                                or (name == 'ATTRIBUTION.md' and moment == 'after metadata')):
                            replace_child()

                    with self.subTest(child=child, moment=moment, replacement=replacement), \
                            patch.object(tool, '_stage_write', write_and_replace), \
                            patch.object(tool.os, 'unlink', side_effect=AssertionError('must not unlink')), \
                            patch.object(Path, 'rmdir', side_effect=AssertionError('must not remove directories')):
                        result, error = self.run_stage('carla.vehicle.audi.a2')
                    self.assertTrue(touched)
                    self.assertEqual(result, 1)
                    self.assertIn('staging incomplete', error)
                    self.assertIn(str(self.output.absolute()), error)
                    self.assertTrue(moved.is_dir())
                    if replacement == 'directory':
                        self.assertEqual(self.tree(target), {'user.txt': b'user replacement'})
                    elif replacement == 'symlink':
                        self.assertTrue(target.is_symlink())
                        self.assertEqual(list(self.fixture.source.iterdir()), [])
                    else:
                        self.assertFalse(target.exists())

    def test_child_replaced_between_stat_and_open_is_refused(self):
        original_open = tool.os.open
        target = self.output / 'carla/vehicles'
        moved = self.fixture.root / 'original-vehicles'

        def replace_before_open(path, *args, **kwargs):
            if path == 'vehicles' and 'dir_fd' in kwargs:
                target.rename(moved)
                target.mkdir()
                (target / 'user.txt').write_bytes(b'user replacement')
            return original_open(path, *args, **kwargs)

        with patch.object(tool.os, 'open', replace_before_open):
            result, error = self.run_stage('carla.vehicle.audi.a2')
        self.assertEqual(result, 1)
        self.assertIn('output changed while opening it', error)
        self.assertIn('staging incomplete', error)
        self.assertEqual(self.tree(target), {'user.txt': b'user replacement'})
        self.assertEqual(list(moved.iterdir()), [])


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
