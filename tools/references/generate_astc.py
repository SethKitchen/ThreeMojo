#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Generate raw ASTC reference texels with pinned Arm astcenc 5.3.0.

Build the adapter as documented in docs/validation/raw-astc.md. This script
never calls ThreeMojo. Seeded random blocks and every 11-bit block mode are
validated by the independent decoder. The output is portable hex text.
"""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import random
import struct

PIN = "30aabb3f42406df45a910d8496f9bee17eeba9bb"
SEED = 617180


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    lib = C.CDLL(str(args.library.resolve()))
    lib.reference_context.argtypes = [C.c_uint, C.c_uint]
    lib.reference_context.restype = C.c_void_p
    lib.reference_free.argtypes = [C.c_void_p]
    lib.reference_block.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p,
                                    C.c_void_p, C.c_uint, C.c_uint]
    rng = random.Random(SEED)
    lines = ["# Arm astcenc 5.3.0 " + PIN,
             "# size profile(0=UNORM,1=sRGB,2=SFLOAT) block_hex output_hex"]
    report = {"reference_commit": PIN, "seed": SEED, "sizes": {}}
    invalid = []
    for size in (4, 6):
        contexts = [lib.reference_context(size, p) for p in range(3)]
        assert all(contexts)
        metadata = (C.c_uint * 15)()
        pixels = (C.c_ubyte * (size * size * 8))()
        selected = []
        invalid_count = 0
        seen = set()
        modes = set()
        stats = {"endpoint_modes": set(), "partitions": set(), "grids": set(),
                 "weight_levels": set(), "endpoint_levels": set(), "dual_components": set()}

        def inspect(block, force=False):
            nonlocal invalid_count
            result = lib.reference_block(contexts[2], block, metadata, pixels, size, 2)
            if result != 0:
                if invalid_count < 4096:
                    invalid.append(f"{size} {block.hex()}")
                    invalid_count += 1
                return
            m = list(metadata)
            raw = bytes(pixels)
            halves = struct.unpack('<' + 'H' * (size * size * 4), raw)
            if any(h & 0x7c00 == 0x7c00 for h in halves):
                return
            if m[1]:
                features = {('constant', (block[1] >> 1) & 1)}
            else:
                bm = int.from_bytes(block[:2], 'little') & 2047
                modes.add(bm)
                features = {('mode', bm), ('partitions', m[4]), ('grid', m[13], m[14]),
                            ('weight_levels', m[12]), ('endpoint_levels', m[11])}
                features.update(('endpoint', e) for e in m[7:7 + m[4]])
                if m[3]:
                    features.add(('dual', m[6]))
                # Keep separate coverage for HDR and LDR endpoint/weight combinations.
                features.add(('kind_mode', m[2], bm))
                for key, values in [('endpoint_modes', m[7:7+m[4]]),
                                    ('partitions', [m[4]]), ('grids', [(m[13], m[14])]),
                                    ('weight_levels', [m[12]]), ('endpoint_levels', [m[11]]),
                                    ('dual_components', [m[6]] if m[3] else [])]:
                    stats[key].update(values)
            if not force and features <= seen:
                return
            seen.update(features)
            selected.append((block, m, raw))

        # All encodable 11-bit layouts. One partition, LDR luminance CEM 0
        # leaves the maximum endpoint budget; invalid modes cannot be rescued
        # by spending more bits on extra partitions or endpoint values.
        for mode in range(2048):
            tail = rng.getrandbits(128)
            value = (tail & ~((1 << 17) - 1)) | mode
            inspect(value.to_bytes(16, 'little'), force=True)
        for _ in range(120000):
            inspect(rng.getrandbits(128).to_bytes(16, 'little'))
        # Exact UNORM rounding boundaries and signed/HDR half constants.
        for colors, hdr in [([0, 0xffff, 0x8080, 0x00ff], 0),
                            ([0x0100, 0x7fff, 0x8000, 0xff00], 0),
                            ([0x0001, 0x3c00, 0x7bff, 0x3800], 1),
                            ([0xbc00, 0x0000, 0x4000, 0x3c00], 1)]:
            header = 0xfffffffffffffdfc | (hdr << 9)
            inspect(struct.pack('<Q4H', header, *colors), force=True)
        records = 0
        for block, meta, hdr_pixels in selected:
            profiles = [2] if meta[2] or (meta[1] and block[1] & 2) else [0, 1, 2]
            for profile in profiles:
                result = lib.reference_block(contexts[profile], block, metadata, pixels, size, profile)
                assert result == 0
                count = size * size * (8 if profile == 2 else 4)
                lines.append(f"{size} {profile} {block.hex()} {bytes(pixels)[:count].hex()}")
                records += 1
        report['sizes'][str(size)] = {"blocks": len(selected), "records": records,
            "block_modes": sorted(modes), **{k: sorted(v) for k, v in stats.items()}}
        for ctx in contexts:
            lib.reference_free(ctx)
    text = '\n'.join(lines) + '\n'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text)
    args.output.with_name("raw_astc_invalid.txt").write_text("\n".join(invalid) + "\n")
    report['fixture_sha256'] = hashlib.sha256(text.encode()).hexdigest()
    args.output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: {'blocks': v['blocks'], 'records': v['records'],
                          'block_modes': len(v['block_modes'])} for k, v in report['sizes'].items()}))
    print(report['fixture_sha256'])


if __name__ == '__main__':
    main()
