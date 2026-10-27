# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Replace one executable token fragment without following a comment decoy."""


def replace_token_fragment(source, before, after):
    """Mutate one exact executable fragment independent of formatter wrapping.

    Retain actual function selection and every operator/name/literal. Comments
    and whitespace cannot redirect the mutation to a textual decoy. No pin or
    semantic assertion is weakened by this test-fixture normalization.
    """
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='token-fragment-') as directory:
        folder = Path(directory)
        (folder / 'source.text').write_text(source)
        (folder / 'before.text').write_text(before)
        (folder / 'after.text').write_text(after)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--fragment', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line for line in result.stderr.splitlines()
                 if 'Crashpad' not in line]
        raise AssertionError('\n'.join(lines))
    return result.stdout
