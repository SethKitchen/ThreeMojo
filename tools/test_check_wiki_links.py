"""Tests for tools/check_wiki_links.py."""

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_wiki_links as links  # noqa: E402


class WikiLinkTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.wiki = self.root / 'docs' / 'wiki'
        self.wiki.mkdir(parents=True)
        (self.wiki / 'Model-files.md').write_text(
            '# Model files\n\n## glTF\n\n## glTF\n\n### `GltfModel` reads it\n',
            encoding='utf-8')

    def tearDown(self):
        self.folder.cleanup()

    def page(self, name, text):
        path = self.wiki / name
        path.write_text(text, encoding='utf-8')
        return path

    def test_good_links_pass(self):
        path = self.page('Geometry.md', (
            '# Geometry\n\nSee the [loader](Model-files#gltf), the '
            '[second](Model-files#gltf-1), [the model](Model-files#gltfmodel-reads-it), '
            '[files](Model-files), [up](#geometry) and '
            '[three.js](https://threejs.org/docs/) and [a file](../../tools/x.py).\n'))
        self.assertEqual(links.check([path], self.wiki), [])

    def test_missing_page_and_anchor_fail(self):
        path = self.page('Geometry.md', (
            '# Geometry\n\nThe [glTF loader](glTF) and [a part](Model-files#gltf-2) '
            'and [here](#nowhere).\n'))
        self.assertEqual(links.check([path], self.wiki), [
            f'{path}:3: no wiki page "glTF"',
            f'{path}:3: no heading for Model-files#gltf-2',
            f'{path}:3: no heading for #nowhere',
        ])

    def test_code_is_not_read(self):
        path = self.page('Scene.md', (
            '# Scene\n\n`objects_by_property[order](3)` is code.\n\n'
            '```mojo\nvar b = make[DType.uint8](256)\n[x](Missing)\n```\n'))
        self.assertEqual(links.check([path], self.wiki), [])

    def test_readme_wiki_urls_are_checked(self):
        readme = self.root / 'README.md'
        readme.write_text(
            '# Readme\n\n- [ok](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#gltf)\n'
            '- [bad](https://github.com/SethKitchen/ThreeMojo/wiki/Nope)\n'
            '- [local](docs/wiki/Model-files.md) and [top](#readme)\n',
            encoding='utf-8')
        self.assertEqual(links.check([readme], self.wiki), [f'{readme}:4: no wiki page "Nope"'])

    def test_main_reports_and_exits(self):
        good = self.page('Good.md', '# Good\n\n[files](Model-files)\n')
        bad = self.page('Bad.md', '# Bad\n\n[gone](Gone)\n')
        saved = links.WIKI
        links.WIKI = self.wiki
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                self.assertEqual(links.main(['check', str(good)]), 0)
                self.assertEqual(links.main(['check', str(bad)]), 1)
                self.assertEqual(links.main(['check']), 2)
        finally:
            links.WIKI = saved
        self.assertIn('no wiki page "Gone"', out.getvalue())

    def test_repository_links_resolve(self):
        root = Path(__file__).resolve().parents[1]
        paths = [root / 'README.md', root / 'CONTRIBUTING.md', *sorted((root / 'docs/wiki').glob('*.md'))]
        self.assertEqual(links.check(paths, root / 'docs/wiki'), [])


if __name__ == '__main__':
    unittest.main()
