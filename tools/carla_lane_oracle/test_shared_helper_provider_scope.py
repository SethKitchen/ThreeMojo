# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Physical helper-provider scope at exact historical source endpoints."""
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
import unittest

import full_audit_cleanup_contracts as cleanup
import shared_helper_contracts as helpers
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
XML = 'loaders/xml.mojo'
UTF8 = 'loaders/utf8.mojo'
SKY = 'extensions/carla/render_sky.mojo'
WEATHER = 'extensions/carla/render_weather.mojo'
COLOR = 'render/color_math.mojo'


class PhysicalProviderScopeControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        case = SimpleNamespace(addCleanup=cls.addClassCleanup)
        cls.root = fixtures.copy_historical_boundary_root(case, ROOT)

    @contextmanager
    def changed(self, path, raw):
        target = self.root/path
        before = target.read_bytes()
        if raw is None:
            target.unlink()
        else:
            target.write_bytes(raw)
        try:
            yield
        finally:
            target.write_bytes(before)

    def test_only_exact_old_xml_excludes_its_provider(self):
        before = helpers.predecessor_source(XML, (self.root/XML).read_text()).encode('utf-8')
        with self.changed(XML, before), self.changed(UTF8, None):
            self.assertEqual(cleanup.shared_helper_proof_bindings(self.root, paths=(XML,)), {})
        with self.changed(XML, before + b'\n# unreviewed endpoint\n'):
            with self.assertRaises(ValueError):
                cleanup.shared_helper_proof_bindings(self.root, paths=(XML,))
            with self.changed(UTF8, None):
                with self.assertRaises(FileNotFoundError) as caught:
                    cleanup.shared_helper_proof_bindings(self.root, paths=(XML,))
                self.assertEqual(caught.exception.filename, str(self.root/UTF8))

    def test_shared_provider_remains_required_by_any_live_helper(self):
        paths = (SKY, WEATHER)
        old = {path: helpers.predecessor_source(path, (self.root/path).read_text()).encode('utf-8')
               for path in paths}
        for inactive in paths:
            with self.subTest(inactive=inactive), self.changed(inactive, old[inactive]):
                bound = cleanup.shared_helper_proof_bindings(self.root, paths=paths)
                self.assertEqual(bound[COLOR], cleanup.sha((self.root/COLOR).read_bytes()))
                with self.changed(COLOR, None):
                    with self.assertRaises(FileNotFoundError) as caught:
                        cleanup.shared_helper_proof_bindings(self.root, paths=paths)
                    self.assertEqual(caught.exception.filename, str(self.root/COLOR))
        with self.changed(SKY, old[SKY]), self.changed(WEATHER, old[WEATHER]), self.changed(COLOR, None):
            self.assertEqual(cleanup.shared_helper_proof_bindings(self.root, paths=paths), {})


if __name__ == '__main__':
    unittest.main()
