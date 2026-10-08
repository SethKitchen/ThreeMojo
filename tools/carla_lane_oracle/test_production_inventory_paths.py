"""The pruned census selects the old boundary and always observes new inputs."""
from pathlib import Path
import os
import tempfile
import unittest
from unittest.mock import patch

import cache_key_contracts as cache
import lane_order_contracts as order
import sum2_guard_contracts as guard


def old_paths(root):
    for path in root.rglob('*.mojo'):
        relative = path.relative_to(root)
        if relative.parts[0] not in guard.NONPRODUCTION and not any(
                part.startswith('.') for part in relative.parts):
            yield path


class ProductionInventoryPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='production-paths-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative, text=None):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text if text is not None else (
            'from extensions.carla.lane_refinement import _run_lane_search\n'
            'from extensions.carla.curve_sum2 import _require_sum2_environment\n'))
        return path

    def assert_equivalent(self):
        self.assertEqual(sorted(guard.production_mojo_paths(self.root)),
                         sorted(old_paths(self.root)))
        for inventory in (cache.inventory, order.inventory, guard.protected_inventory):
            with self.subTest(inventory=inventory.__module__):
                current = inventory(self.root)
                with patch.object(guard, 'production_mojo_paths', old_paths):
                    self.assertEqual(current, inventory(self.root))

    def test_old_boundary_nested_names_reexports_and_pruning(self):
        kept = ('root.mojo', 'new_namespace/__init__.mojo',
                'new_namespace/tests/caller.mojo',
                'new_namespace/tools/caller.mojo',
                'new_namespace/coverage/caller.mojo')
        for relative in kept:
            self.write(relative)
        self.write('new_namespace/upper.MOJO')
        for name in guard.NONPRODUCTION:
            self.write(name + '/nested/caller.mojo')
        for relative in ('.hidden/caller.mojo', 'new_namespace/.hidden/caller.mojo',
                         'new_namespace/.caller.mojo'):
            self.write(relative)
        self.assert_equivalent()
        expected = set(kept)
        if Path('upper.MOJO').match('*.mojo'):
            expected.add('new_namespace/upper.MOJO')
        self.assertEqual({p.relative_to(self.root).as_posix()
                          for p in guard.production_mojo_paths(self.root)}, expected)
        scanned = []
        original = os.scandir
        def recording(path):
            scanned.append(Path(path))
            return original(path)
        with patch.object(os, 'scandir', recording):
            list(guard.production_mojo_paths(self.root))
        for path in scanned:
            relative = path.relative_to(self.root)
            if relative.parts:
                self.assertNotIn(relative.parts[0], guard.NONPRODUCTION)
                self.assertFalse(any(p.startswith('.') for p in relative.parts))

    def test_new_caller_changed_bytes_and_deletion_are_seen_after_success(self):
        self.write('initial.mojo')
        self.assert_equivalent()
        inventories = (cache.inventory, order.inventory, guard.protected_inventory)
        before = [inventory(self.root) for inventory in inventories]
        added = self.write('new_namespace/tests/late_caller.mojo')
        self.assert_equivalent()
        after = [inventory(self.root) for inventory in inventories]
        for old, new in zip(before, after):
            self.assertNotEqual(old, new)
            self.assertIn('new_namespace/tests/late_caller.mojo', new)
        added.write_text('alias later = _run_lane_search\n'
                         'alias environment = _require_sum2_environment\n')
        self.assert_equivalent()
        changed = [inventory(self.root) for inventory in inventories]
        for previous, current in zip(after, changed):
            self.assertNotEqual(previous, current)
        added.unlink()
        self.assert_equivalent()
        self.assertEqual(before, [inventory(self.root) for inventory in inventories])
        added = self.write('new_namespace/tests/late_caller.mojo')
        added.write_text('alias irrelevant = 1\n')
        self.assert_equivalent()
        self.assertEqual(before, [inventory(self.root) for inventory in inventories])
        added.unlink()
        self.assert_equivalent()

    def test_symlink_selection_without_directory_descent(self):
        target = self.write('ordinary/real.mojo')
        (self.root / 'file_link.mojo').symlink_to(target)
        (self.root / 'directory_link').symlink_to(target.parent, target_is_directory=True)
        self.assert_equivalent()
        selected = {p.relative_to(self.root).as_posix()
                    for p in guard.production_mojo_paths(self.root)}
        self.assertIn('file_link.mojo', selected)
        self.assertNotIn('directory_link/real.mojo', selected)

    def test_symlink_root_and_global_order_are_preserved(self):
        for relative in ('z/first.mojo', 'a/last.mojo', 'm.mojo'):
            self.write(relative)
        with tempfile.TemporaryDirectory(prefix='production-root-link-') as temporary:
            linked = Path(temporary) / 'root'
            linked.symlink_to(self.root, target_is_directory=True)
            self.assertEqual(sorted(guard.production_mojo_paths(linked)),
                             sorted(old_paths(linked)))
            for inventory in (cache.inventory, order.inventory, guard.protected_inventory):
                current = inventory(linked)
                self.assertEqual(list(current), sorted(current))
                with patch.object(guard, 'production_mojo_paths', old_paths):
                    self.assertEqual(current, inventory(linked))

    def test_matching_directory_and_broken_symlink_still_fail_closed(self):
        for kind in ('directory', 'directory_symlink', 'broken_symlink'):
            with self.subTest(kind=kind):
                target = self.root / 'unusual.mojo'
                if kind == 'directory':
                    target.mkdir()
                elif kind == 'directory_symlink':
                    target.symlink_to(self.root, target_is_directory=True)
                else:
                    target.symlink_to(self.root / 'missing')
                self.assertEqual(sorted(guard.production_mojo_paths(self.root)),
                                 sorted(old_paths(self.root)))
                for inventory in (cache.inventory, order.inventory, guard.protected_inventory):
                    with self.assertRaises(OSError):
                        inventory(self.root)
                    with patch.object(guard, 'production_mojo_paths', old_paths):
                        with self.assertRaises(OSError):
                            inventory(self.root)
                if kind == 'directory':
                    target.rmdir()
                else:
                    target.unlink()

    def test_scan_open_iteration_and_classification_errors_fail_closed(self):
        self.write('initial.mojo')
        with patch.object(os, 'scandir', side_effect=OSError('scan-open failure')):
            for inventory in (cache.inventory, order.inventory, guard.protected_inventory):
                with self.assertRaisesRegex(OSError, 'scan-open failure'):
                    inventory(self.root)

        class FailingScan:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def __iter__(self):
                return self
            def __next__(self):
                raise OSError('iteration failure')

        with patch.object(os, 'scandir', side_effect=lambda path: FailingScan()):
            for inventory in (cache.inventory, order.inventory, guard.protected_inventory):
                with self.assertRaisesRegex(OSError, 'iteration failure'):
                    inventory(self.root)

        class FailingEntry:
            name = 'ordinary_namespace'
            def is_dir(self, *, follow_symlinks):
                raise OSError('classification failure')
        class ClassificationScan:
            def __enter__(self):
                return iter((FailingEntry(),))
            def __exit__(self, *args):
                return False
        with patch.object(os, 'scandir', side_effect=lambda path: ClassificationScan()):
            for inventory in (cache.inventory, order.inventory, guard.protected_inventory):
                with self.assertRaisesRegex(OSError, 'classification failure'):
                    inventory(self.root)

    def test_missing_and_non_directory_roots_fail_closed(self):
        ordinary_file = self.write('ordinary.txt')
        for root in (self.root / 'missing', ordinary_file):
            with self.subTest(root=root):
                with self.assertRaises(OSError):
                    list(guard.production_mojo_paths(root))


if __name__ == '__main__':
    unittest.main()
