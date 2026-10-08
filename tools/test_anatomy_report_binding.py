# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the saved anatomy report's source binding without a native probe."""
import json
from pathlib import Path
import tempfile
import unittest

import anatomy_validity as av


def check_binding(root):
    """Reject a missing or stale report; this does not validate its measurements."""
    report = json.loads((root/'docs/validation/anatomy-template-report.json').read_text())
    digest, hashes, _ = av.source_snapshot(root)
    expected = {
        'source_sha256': digest,
        'report_logic_sha256': hashes['tools/anatomy_validity.py'],
        'inventory_sha256': hashes['docs/validation/anatomy-provenance.json'],
    }
    actual = dict(report)
    actual['source_sha256'] = report['build_provenance']['source_sha256']
    for key, value in expected.items():
        if actual.get(key) != value:
            raise ValueError(f'anatomy report has stale {key}; regenerate on Linux '
                             'with python3 tools/anatomy_validity.py --build '
                             '--output docs/validation/anatomy-template-report.json')


class AnatomyReportBindingTests(unittest.TestCase):
    def test_checked_in_report_matches_current_source(self):
        # Only the probe's import closure, report logic and inventory enter
        # this digest.
        # This Python test and the saved report cannot bind themselves.
        check_binding(av.ROOT)

    def test_missing_and_stale_reports_are_rejected(self):
        for mutation in ('none', 'unrelated_source', 'source', 'added_source',
                         'removed_source', 'probe', 'logic', 'inventory',
                         'missing_report', 'missing_key', 'report_logic_hash'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root/'tools').mkdir()
                (root/'docs/validation').mkdir(parents=True)
                # The probe imports bound, and an `added` module that does
                # not exist yet. Only the probe's import closure is bound.
                probe = root/'tools/anatomy_probe.mojo'
                probe.write_text('from bound import fixture\nfrom added import later\n')
                source = root/'bound.mojo'
                logic = root/'tools/anatomy_validity.py'
                inventory = root/'docs/validation/anatomy-provenance.json'
                source.write_text('def fixture(): pass')
                logic.write_text('report logic')
                inventory.write_text('{}')
                digest, hashes, _ = av.source_snapshot(root)
                report = {'build_provenance': {'source_sha256': digest},
                          'report_logic_sha256': hashes['tools/anatomy_validity.py'],
                          'inventory_sha256': hashes['docs/validation/anatomy-provenance.json']}
                if mutation == 'unrelated_source':
                    (root/'unrelated.mojo').write_text('def elsewhere(): pass')
                elif mutation == 'source':
                    source.write_text('def changed(): pass')
                elif mutation == 'added_source':
                    (root/'added.mojo').write_text('def later(): pass')
                elif mutation == 'probe':
                    probe.write_text('from bound import fixture\n')
                elif mutation == 'removed_source':
                    source.unlink()
                elif mutation == 'logic':
                    logic.write_text('changed logic')
                    # Keep the broad digest current to check the separate hash.
                    report['build_provenance']['source_sha256'] = av.source_digest(root)
                elif mutation == 'inventory':
                    inventory.write_text('{"changed":true}')
                    report['build_provenance']['source_sha256'] = av.source_digest(root)
                elif mutation == 'missing_key':
                    del report['build_provenance']['source_sha256']
                elif mutation == 'report_logic_hash':
                    report['report_logic_sha256'] = 'wrong'
                if mutation != 'missing_report':
                    (root/'docs/validation/anatomy-template-report.json').write_text(json.dumps(report))
                if mutation in ('none', 'unrelated_source'):
                    check_binding(root)
                else:
                    with self.assertRaises((ValueError, FileNotFoundError, KeyError)):
                        check_binding(root)


if __name__ == '__main__':
    unittest.main()
