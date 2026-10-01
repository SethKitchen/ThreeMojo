# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep the shared mechanics import graph independent of simulation domains."""

from pathlib import Path
import unittest

import affected


class SharedPhysicsDependencies(unittest.TestCase):
    def test_core_imports_no_carla_or_humanoid_module(self):
        root = Path(__file__).resolve().parent.parent
        known = set(affected.mojo_files())
        pending = [path for path in known if path.startswith('extensions/physics/')]
        self.assertTrue(pending)
        visited = set()
        while pending:
            path = pending.pop()
            if path in visited:
                continue
            visited.add(path)
            self.assertFalse(path.startswith(('extensions/carla/', 'extensions/humanoid/')), path)
            for name in affected.imported_names((root / path).read_text()):
                pending.extend(affected.resolve(name, path, known))
        self.assertIn('extensions/physics/world.mojo', visited)
        self.assertIn('math/vector3.mojo', visited)
        self.assertIn('units/si.mojo', visited)


if __name__ == '__main__':
    unittest.main()
