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
from pathlib import Path
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout

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
        archive = copy.deepcopy(good)
        archive['files'] = [{'role': 'archive', 'url': 'https://example.org/a.zip',
                             'sha256': None, 'path': 'a.zip', 'extract': []}]
        cases.append(manifest_of(archive))
        for manifest in cases:
            with self.assertRaises(tool.ManifestError):
                tool.check_manifest(manifest)

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


class CreditTests(unittest.TestCase):
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
