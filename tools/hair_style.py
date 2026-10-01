# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Convert a TressFX hair file into a hairstyle for `assets/hair/`.

    python3 tools/hair_style.py layered SINTEL.tfx assets/hair/layered.bin
    python3 tools/hair_style.py mohawk RATBOY_MOHAWK.tfx assets/hair/mohawk.bin

reads a `.tfx` file, the guide strands of AMD TressFX 4 (the layout is
`TressFXTFXFileHeader` in TressFX's `TressFXFileFormat.h`, MIT license),
and writes one little-endian file that `HairStyleFile` reads:

    "THRS", version 1
    u32 each: strands, points a strand
    f32: the offsets' scale
    each strand's root on the unit cranium: i16 x, y, z over 32767
    each strand's points, from its root, in the frame of the cranium
        at its root and in its mean radii: i16 across, up and along,
        times the scale

A hairstyle is kept on no head of its own. Each root is put on the
source head's cranium, an ellipsoid fitted through the roots, and then
on the unit sphere; each strand is kept as offsets from its root in the
cranium's frame there: across (toward plus x), up (the cranium's
normal) and along (their cross product), in its mean radii. So a
style goes on any cranium: the roots land on it, and each strand keeps
its shape to the scalp under it.

Two styles come from the repositories this project draws on:

- `layered`: Sintel's hair, from Sintel Lite 2.57b by BenDansie, in
  frostbitten-hair-webgpu by Marcin Matuszczyk. The model is (c) the
  Blender Foundation, CC-BY 3.0, durian.blender.org.
- `mohawk`: Ratboy's mohawk, from AMD TressFX 4.1, MIT license,
  copyright 2017 Advanced Micro Devices. On Ratboy it runs from the
  brow down the back, so only its crest from the brow to the nape is
  kept, and that arc is stretched onto a human scalp's.

See THIRD-PARTY-NOTICES.md.
"""

import math
import struct
import sys

VERSION = 1
POINTS = 16
TFX_HEADER_BYTES = 160
# The mohawk's crest, as angles from the top of its circle toward the
# back, in degrees: the part of Ratboy's that is kept, and the arc of a
# human scalp's midline from the hairline to the nape it goes on.
MOHAWK_FROM = -15.0
MOHAWK_TO = 100.0
SCALP_FROM = -55.0
SCALP_TO = 110.0
# Only Ratboy's roots this high lie on the head's curve.
MOHAWK_HEAD = 0.6
# Ratboy's crest widens down his neck; a human's stays a strip. The
# roots' spread across the head, and the strands' reach across, are
# narrowed by these.
MOHAWK_NARROW = 0.5
MOHAWK_REACH = 0.6
# A human cranium's radii across, up and along, which a crest's circle
# takes the proportions of.
HUMAN = (8.1, 9.3, 10.6)


def read_tfx(path):
    """Return finite positions from a validated TressFX 4 file.

    The offline converter resamples any strand with at least two points;
    the upstream GPU simulation's power-of-two point count does not apply.
    Malformed headers, offsets, and positions raise ValueError.
    """
    with open(path, "rb") as source:
        data = source.read()
    if len(data) < TFX_HEADER_BYTES:
        raise ValueError(f"Not a complete TressFX header: {path}")
    version, strands, points, offset = struct.unpack_from("<fIII", data, 0)
    if not math.isfinite(version) or not 4.0 <= version < 5.0:
        raise ValueError(f"The converter requires the TressFX 4 layout: {path}")
    if strands == 0 or points < 2:
        raise ValueError(f"A TressFX file with no strands: {path}")
    if offset < TFX_HEADER_BYTES or offset % 8:
        raise ValueError(f"Invalid TressFX position offset: {path}")
    if offset + strands * points * 16 > len(data):
        raise ValueError(f"The TressFX file ends early: {path}")
    result = []
    for s in range(strands):
        strand = []
        for i in range(points):
            # Each position is FLOAT4; the converter uses xyz, not w.
            at = offset + 16 * (s * points + i)
            position = struct.unpack_from("<3f", data, at)
            if not all(math.isfinite(value) for value in position):
                raise ValueError(f"Non-finite TressFX position at strand {s}, point {i}: {path}")
            strand.append(position)
        result.append(strand)
    return result


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _unit(a):
    length = math.sqrt(_dot(a, a))
    return (a[0] / length, a[1] / length, a[2] / length)


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def resample(strand, count=POINTS):
    """Return `count` points spaced evenly along a strand."""
    lengths = [0.0]
    for i in range(1, len(strand)):
        lengths.append(lengths[-1] + math.dist(strand[i - 1], strand[i]))
    total = lengths[-1]
    result = []
    j = 0
    for k in range(count):
        want = total * k / (count - 1)
        while j < len(strand) - 2 and lengths[j + 1] < want:
            j += 1
        span = lengths[j + 1] - lengths[j]
        t = 0.0 if span <= 0 else (want - lengths[j]) / span
        t = max(0.0, min(1.0, t))
        a = strand[j]
        b = strand[j + 1]
        result.append(tuple(a[c] + (b[c] - a[c]) * t for c in range(3)))
    return result


def _solve(matrix, vector):
    """Solve a small linear system by Gauss-Jordan elimination."""
    n = len(vector)
    rows = [matrix[i][:] + [vector[i]] for i in range(n)]
    for c in range(n):
        pivot = max(range(c, n), key=lambda r: abs(rows[r][c]))
        rows[c], rows[pivot] = rows[pivot], rows[c]
        for r in range(n):
            if r != c:
                f = rows[r][c] / rows[c][c]
                rows[r] = [a - f * b for a, b in zip(rows[r], rows[c])]
    return [rows[i][n] / rows[i][i] for i in range(n)]


def fit_cranium(points):
    """Return the center and radii of the ellipsoid, square to the axes
    and on the midline, that passes nearest `points`."""
    rows = [(x * x, y * y, z * z, y, z) for x, y, z in points]
    matrix = [[sum(r[i] * r[j] for r in rows) for j in range(5)] for i in range(5)]
    vector = [sum(r[i] for r in rows) for i in range(5)]
    a, b, c, d, e = _solve(matrix, vector)
    cy = -d / (2 * b)
    cz = -e / (2 * c)
    g = 1 + b * cy * cy + c * cz * cz
    return (0.0, cy, cz), (math.sqrt(g / a), math.sqrt(g / b), math.sqrt(g / c))


def fit_crest(points):
    """Return the center and radius of the circle in the midline's plane,
    y and z, that passes nearest `points`."""
    rows = [(y, z, 1.0) for _, y, z in points]
    rhs = [-(y * y + z * z) for _, y, z in points]
    matrix = [[sum(r[i] * r[j] for r in rows) for j in range(3)] for i in range(3)]
    vector = [sum(r[i] * v for r, v in zip(rows, rhs)) for i in range(3)]
    d, e, f = _solve(matrix, vector)
    cy = -d / 2
    cz = -e / 2
    return (0.0, cy, cz), math.sqrt(cy * cy + cz * cz - f)


def cranium_frame(q, radii):
    """Return the frame of an ellipsoid at the point `q` of its unit
    sphere: across, up (the normal) and along."""
    up = _unit((q[0] / radii[0], q[1] / radii[1], q[2] / radii[2]))
    across = _sub((1.0, 0.0, 0.0), tuple(c * up[0] for c in up))
    if _dot(across, across) < 1e-6:
        across = _sub((0.0, 0.0, 1.0), tuple(c * up[2] for c in up))
    across = _unit(across)
    return across, up, _cross(up, across)


def encode(strands, center, radii):
    """Return each strand as its root on the unit sphere and its points'
    offsets in the cranium's frame, in its mean radii."""
    mean = sum(radii) / 3
    result = []
    for strand in strands:
        root = strand[0]
        q = _unit(tuple((root[k] - center[k]) / radii[k] for k in range(3)))
        across, up, along = cranium_frame(q, radii)
        offsets = []
        for p in strand:
            d = tuple(c / mean for c in _sub(p, root))
            offsets.append((_dot(d, across), _dot(d, up), _dot(d, along)))
        result.append((q, offsets))
    return result


def layered(strands):
    """Return Sintel's strands encoded on the cranium fitted to their
    roots."""
    center, radii = fit_cranium([s[0] for s in strands])
    return encode(strands, center, radii)


def mohawk(strands):
    """Return the crest of Ratboy's mohawk, from the brow to the nape,
    encoded on a human-shaped cranium round its circle, its arc stretched
    onto a human scalp's."""
    head = [s[0] for s in strands if s[0][1] >= MOHAWK_HEAD]
    center, radius = fit_crest(head)
    radii = tuple(radius * h / HUMAN[1] for h in HUMAN)
    kept = []
    for strand in strands:
        _, y, z = strand[0]
        angle = math.degrees(math.atan2(-(z - center[2]), y - center[1]))
        if angle < MOHAWK_FROM or angle > MOHAWK_TO:
            continue
        t = (angle - MOHAWK_FROM) / (MOHAWK_TO - MOHAWK_FROM)
        moved = math.radians(SCALP_FROM + (SCALP_TO - SCALP_FROM) * t)
        # The root goes to its place on the stretched arc, and the
        # strand goes with it, turned as the arc turns.
        turn = moved - math.radians(angle)
        c = math.cos(turn)
        s = math.sin(turn)
        placed = []
        for x, py, pz in strand:
            dy = py - center[1]
            dz = -(pz - center[2])
            placed.append(
                (x, center[1] + dy * c - dz * s, center[2] - (dy * s + dz * c))
            )
        kept.append(placed)
    if not kept:
        raise ValueError("No strand of the mohawk lies on its crest")
    narrowed = []
    for q, offsets in encode(kept, center, radii):
        q = _unit((q[0] * MOHAWK_NARROW, q[1], q[2]))
        offsets = [(o[0] * MOHAWK_REACH, o[1], o[2]) for o in offsets]
        narrowed.append((q, offsets))
    return narrowed


def _i16(value):
    return max(-32767, min(32767, int(round(value))))


def write(path, encoded):
    """Write encoded strands in the layout above."""
    scale = max(
        (abs(c) for _, offsets in encoded for o in offsets for c in o),
        default=1.0,
    ) / 32767 or 1.0 / 32767
    body = bytearray(b"THRS")
    points = len(encoded[0][1])
    body += struct.pack("<III", VERSION, len(encoded), points)
    body += struct.pack("<f", scale)
    for q, _ in encoded:
        body += struct.pack("<3h", *(_i16(c * 32767) for c in q))
    body += bytes(-len(body) % 4)
    for _, offsets in encoded:
        for o in offsets:
            body += struct.pack("<3h", *(_i16(c / scale) for c in o))
    with open(path, "wb") as sink:
        sink.write(body)
    return len(encoded)


def convert(style, source, target):
    """Convert one TressFX file into a hairstyle; return its strands."""
    strands = [resample(s) for s in read_tfx(source)]
    if style == "layered":
        encoded = layered(strands)
    elif style == "mohawk":
        encoded = mohawk(strands)
    else:
        raise ValueError("A style is layered or mohawk")
    return write(target, encoded)


def main(argv):
    """Run the converter from the command line."""
    if len(argv) != 4:
        print(__doc__.splitlines()[0], file=sys.stderr)
        return 2
    print("strands:", convert(argv[1], argv[2], argv[3]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
