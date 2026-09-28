# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Report physical MAX devices before compiling accelerator kernels.

With --available, exit 0 for a device, 1 for no device, and 2 on error.
Compiler target support alone does not mean a physical device is present.
"""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--available', action='store_true')
    args = parser.parse_args()
    try:
        from max.driver import accelerator_count, is_virtual_device_mode
        available = not is_virtual_device_mode() and accelerator_count() > 0
    except Exception as error:
        print(f'GPU detection failed: {error}', file=sys.stderr)
        return 2
    if args.available:
        return 0 if available else 1
    if available:
        print('GPU: present. Device parity tests will run.')
    else:
        print('GPU: absent. Device parity tests SKIP; host layout tests still run.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
