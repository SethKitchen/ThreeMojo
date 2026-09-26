# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write the WebP files here and what libwebp 1.6.0 decodes them to.

Each source image is made here, so that nothing depends on a photograph.
`cwebp` encodes it with one set of options a case, to reach each part of
the decoder: lossy at several qualities, filters, segments and token
partitions; lossy with alpha, raw and compressed, with each alpha filter;
and lossless at every effort, with palettes of several sizes. Some files
are then damaged on purpose. `dwebp -pam` decodes each, and its pixels
are kept as `name.png`; `webp.json` lists the cases, and which libwebp
refuses. `tests/test_webp.mojo` reads them.

Run it with libwebp 1.6.0's `cwebp` and `dwebp`, built from the release
with two additions, as `CWEBP` and `DWEBP` in the environment:

- A `-partitions` option in `cwebp`, `config.partitions = ExUtilGetInt(...)`
  beside `-segments`. The release's `cwebp` has no way to ask for more
  than one token partition, and it needs `-low_memory` to keep them.
- Six switches, read with `getenv`. `WEBP_TEST_NO_MAP` in
  `src/enc/frame_enc.c` puts every macroblock in segment 0 and sends no
  segment map. `WEBP_TEST_I4` in `src/enc/quant_enc.c` predicts every
  macroblock as 4x4 blocks. Four are in `src/enc/syntax_enc.c`.
  `WEBP_TEST_RELATIVE` writes the segments' quantizers and filter levels
  relative to the frame's. `WEBP_TEST_NO_UPDATE` writes segments without
  their values. `WEBP_TEST_LF_DELTA=d` writes a reference delta of `d`
  and a 4x4 mode delta of `-d / 2 - 1`, and `WEBP_TEST_LF_NOUPDATE`
  turns the deltas on without updating them. The release's encoder writes
  none of these forms, and a decoder must read each.
"""

import json
import math
import os
import struct
import subprocess
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
CWEBP = os.environ.get("CWEBP", "cwebp")
DWEBP = os.environ.get("DWEBP", "dwebp")

seed = 1


def rand():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed / 0x7FFFFFFF


def photo(w, h, alpha=False):
    """Smooth color, texture, noise and a few hard shapes."""
    out = []
    for y in range(h):
        for x in range(w):
            u, v = x / max(w - 1, 1), y / max(h - 1, 1)
            r = 128 + 100 * math.sin(u * 5 + v * 2) + 20 * rand()
            g = 60 + 150 * v + 25 * math.cos(x * 0.9) * math.sin(y * 0.7)
            b = 200 - 120 * u + 30 * rand()
            if (x - w * 0.6) ** 2 + (y - h * 0.4) ** 2 < (min(w, h) * 0.2) ** 2:
                r, g, b = 250, 240, 20
            if w * 0.1 < x < w * 0.3 and h * 0.55 < y < h * 0.8:
                r, g, b = 10, 30, 90
            px = [max(0, min(255, int(c))) for c in (r, g, b)]
            if alpha:
                a = int(255 * u)
                if (x // 8 + y // 8) % 3 == 0:
                    a = 255
                if x < w * 0.15:
                    a = 0
                px.append(a)
            out.append(px)
    return out


def flat(w, h):
    """One color, with a square of another: most macroblocks skip."""
    out = []
    for y in range(h):
        for x in range(w):
            inside = 16 <= x < 32 and 16 <= y < 32
            out.append([200, 40, 90] if inside else [60, 120, 180])
    return out


def palette(w, h, n):
    """Blocks and stripes of `n` colors."""
    colors = [
        (int(255 * rand()), int(255 * rand()), int(255 * rand()), 255)
        for _ in range(n)
    ]
    out = []
    for y in range(h):
        for x in range(w):
            out.append(list(colors[(x // 3 + (y // 2) * 7 + x * y // 11) % n]))
    return out


def write_pam(path, w, h, pixels):
    depth = len(pixels[0])
    kind = "RGB_ALPHA" if depth == 4 else "RGB"
    head = "P7\nWIDTH %d\nHEIGHT %d\nDEPTH %d\nMAXVAL 255\nTUPLTYPE %s\nENDHDR\n" % (
        w,
        h,
        depth,
        kind,
    )
    with open(path, "wb") as f:
        f.write(head.encode())
        f.write(bytes(c for px in pixels for c in px))


def read_pam(path):
    data = open(path, "rb").read()
    end = data.index(b"ENDHDR\n") + 7
    fields = dict(
        line.split(" ", 1)
        for line in data[:end].decode().split("\n")[1:-2]
    )
    w, h, depth = int(fields["WIDTH"]), int(fields["HEIGHT"]), int(fields["DEPTH"])
    assert depth == 4
    return w, h, data[end:]


def write_png(path, w, h, rgba):
    raw = b"".join(b"\x00" + rgba[y * w * 4 : (y + 1) * w * 4] for y in range(h))

    def chunk(tag, body):
        c = tag + body
        return struct.pack(">I", len(body)) + c + struct.pack(">I", zlib.crc32(c))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


cases = []
tmp = tempfile.mkdtemp()


def reference(name):
    """Decode `name.webp` with dwebp; keep its pixels, or note that it
    refuses the file."""
    src = os.path.join(HERE, name + ".webp")
    pam = os.path.join(tmp, name + ".pam")
    done = subprocess.run([DWEBP, "-pam", src, "-o", pam], capture_output=True)
    if done.returncode != 0:
        cases.append({"name": name, "error": True})
        return
    w, h, rgba = read_pam(pam)
    write_png(os.path.join(HERE, name + ".png"), w, h, rgba)
    cases.append({"name": name, "error": False, "width": w, "height": h})


def encode(name, source, options, env=None):
    out = os.path.join(HERE, name + ".webp")
    subprocess.run(
        [CWEBP, "-quiet"] + options + [source, "-o", out],
        check=True,
        env=dict(os.environ, **(env or {})),
    )
    reference(name)


def damage(name, source_name, change):
    data = bytearray(open(os.path.join(HERE, source_name + ".webp"), "rb").read())
    data = change(data)
    open(os.path.join(HERE, name + ".webp"), "wb").write(bytes(data))
    reference(name)


def source(name, w, h, pixels):
    path = os.path.join(tmp, name + ".pam")
    write_pam(path, w, h, pixels)
    return path


rgb = source("photo", 67, 45, photo(67, 45))
big = source("big", 130, 97, photo(130, 97))
rgba = source("alpha", 67, 45, photo(67, 45, alpha=True))
one = source("one", 1, 1, [[200, 30, 90]])
tiny = source("tiny", 3, 2, photo(3, 2))
line = source("line", 17, 1, photo(17, 1))
plain = source("flat", 64, 48, flat(64, 48))
# One color everywhere: every macroblock in one segment, so the segment
# map is not sent, and nearly every macroblock skips its residual.
uniform = source("uniform", 64, 48, [[60, 120, 180]] * (64 * 48))

# Lossy.
for name, options in [
    ("lossy_q75", []),
    ("lossy_q0", ["-q", "0"]),
    ("lossy_q30", ["-q", "30"]),
    ("lossy_q100", ["-q", "100"]),
    ("lossy_m0", ["-m", "0"]),
    ("lossy_m6", ["-m", "6"]),
    ("lossy_one_segment", ["-segments", "1"]),
    ("lossy_no_sns", ["-sns", "0"]),
    ("lossy_sns100", ["-sns", "100", "-q", "50"]),
    ("lossy_no_filter", ["-f", "0"]),
    ("lossy_strong_sharp", ["-f", "100", "-sharpness", "7", "-strong"]),
    ("lossy_sharpness3", ["-sharpness", "3", "-f", "80"]),
    ("lossy_simple", ["-nostrong"]),
    ("lossy_simple_strong", ["-nostrong", "-f", "90", "-q", "20"]),
    ("lossy_two_partitions", ["-partitions", "1", "-low_memory"]),
    ("lossy_four_partitions", ["-partitions", "2", "-low_memory"]),
    ("lossy_sharp_yuv", ["-sharp_yuv"]),
    ("lossy_auto_filter", ["-af"]),
]:
    encode(name, rgb, options)
encode("lossy_big", big, ["-q", "50", "-partitions", "3", "-low_memory"])
encode("lossy_big_simple", big, ["-q", "60", "-nostrong", "-segments", "2"])
encode("lossy_relative", rgb, ["-q", "40"], {"WEBP_TEST_RELATIVE": "1"})
encode("lossy_lf_delta", rgb, ["-f", "50"], {"WEBP_TEST_LF_DELTA": "9"})
encode(
    "lossy_lf_delta_off",
    big,
    ["-f", "20", "-nostrong"],
    {"WEBP_TEST_LF_DELTA": "-30", "WEBP_TEST_RELATIVE": "1"},
)
encode("lossy_no_update", rgb, [], {"WEBP_TEST_NO_UPDATE": "1"})
encode("lossy_lf_no_update", rgb, [], {"WEBP_TEST_LF_NOUPDATE": "1"})
encode("lossy_flat", plain, ["-q", "80"])
encode("lossy_flat_simple", plain, ["-q", "80", "-nostrong"])
# The encoder skips residuals only off its token buffer, with -low_memory.
encode(
    "lossy_uniform",
    uniform,
    ["-segments", "4", "-low_memory"],
    {"WEBP_TEST_NO_MAP": "1"},
)
encode("lossy_uniform_i4", uniform, ["-low_memory"], {"WEBP_TEST_I4": "1"})
encode("lossy_one", one, [])
encode("lossy_tiny", tiny, [])
encode("lossy_line", line, ["-q", "90"])

# Lossy with alpha.
for name, options in [
    ("alpha_default", []),
    ("alpha_raw", ["-alpha_method", "0"]),
    ("alpha_no_filter", ["-alpha_filter", "none"]),
    ("alpha_best_filter", ["-alpha_filter", "best"]),
    ("alpha_levels", ["-alpha_q", "40"]),
    ("alpha_exact", ["-exact", "-q", "60"]),
]:
    encode(name, rgba, options)

# Lossless.
for z in range(10):
    encode("lossless_z%d" % z, rgb, ["-lossless", "-z", str(z)])
encode("lossless_alpha", rgba, ["-lossless"])
encode("lossless_alpha_exact", rgba, ["-lossless", "-exact", "-z", "9"])
encode("lossless_near", rgb, ["-lossless", "-near_lossless", "40"])
encode("lossless_big", big, ["-lossless", "-z", "6"])
encode("lossless_one", one, ["-lossless"])
encode("lossless_line", line, ["-lossless"])
for n in [2, 3, 5, 16, 17, 200]:
    for w in [13, 40]:
        path = source("palette%d_%d" % (n, w), w, 9, palette(w, 9, n))
        encode("lossless_palette%d_w%d" % (n, w), path, ["-lossless", "-z", "9"])

# Damaged files: libwebp's answer is the reference either way.
damage("cut_lossy", "lossy_q75", lambda d: d[: len(d) // 2])
damage("cut_lossless", "lossless_z5", lambda d: d[: len(d) - 40])
damage("cut_alpha", "alpha_default", lambda d: d[: len(d) - 10])


def riff_size(d, size):
    d[4:8] = struct.pack("<I", size)
    return d


damage("riff_too_big", "lossy_q75", lambda d: riff_size(d, len(d)))
damage("riff_too_small", "lossy_q75", lambda d: riff_size(d, 4))


def animated(d):
    # alpha_default is VP8X; set its animation flag.
    d[20] |= 0x02
    return d


def canvas(d):
    d[24] ^= 1
    return d


def alpha_header(d, value):
    at = d.index(b"ALPH") + 8
    d[at] = value
    return d


damage("animated", "alpha_default", animated)
damage("canvas_mismatch", "alpha_default", canvas)
damage("alpha_bad_method", "alpha_default", lambda d: alpha_header(d, 0x03))
damage("alpha_reserved", "alpha_default", lambda d: alpha_header(d, 0xC1))
damage("alpha_levels_bad", "alpha_default", lambda d: alpha_header(d, 0x21))


def flip(offset):
    def change(d):
        d[len(d) * offset // 100] ^= 0x5A
        return d

    return change


# The encoder picks the horizontal filter for these images; the others are
# read with the same data.
for name, method in [("alpha_raw", 0), ("alpha_default", 1)]:
    for f, fname in [(2, "vertical"), (3, "gradient")]:
        damage(
            "%s_%s" % (name, fname),
            name,
            lambda d, f=f: alpha_header(d, (d[d.index(b"ALPH") + 8] & ~0x0C) | (f << 2)),
        )

for k, offset in enumerate([30, 50, 70, 90]):
    damage("flip_lossy%d" % k, "lossy_q75", flip(offset))
    damage("flip_lossless%d" % k, "lossless_z5", flip(offset))

json.dump({"cases": cases}, open(os.path.join(HERE, "webp.json"), "w"), indent=1)
print(len(cases), "cases,", sum(c["error"] for c in cases), "refused")
