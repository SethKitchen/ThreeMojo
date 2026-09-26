"""Writes TIFF fixtures in this folder with Pillow and libtiff: each mode
with each baseline compression. Run it before `three_tiff.mjs`."""
from PIL import Image

W, H = 7, 5


def pixel(x, y, k):
    return (x * 37 + y * 53 + k * 91) % 256


def image(mode):
    if mode == "1":
        im = Image.new("1", (W, H))
        im.putdata([(x + y) % 2 * 255 for y in range(H) for x in range(W)])
    elif mode == "L":
        im = Image.new("L", (W, H))
        im.putdata([pixel(x, y, 0) for y in range(H) for x in range(W)])
    elif mode == "I;16":
        im = Image.new("I;16", (W, H))
        im.putdata([pixel(x, y, 0) * 251 for y in range(H) for x in range(W)])
    elif mode == "P":
        im = Image.new("P", (W, H))
        im.putpalette([pixel(i, 0, c) for i in range(256) for c in range(3)])
        im.putdata([(x * 3 + y) % 16 for y in range(H) for x in range(W)])
    else:
        bands = len(mode)
        im = Image.new(mode, (W, H))
        im.putdata([tuple(pixel(x, y, k) for k in range(bands)) for y in range(H) for x in range(W)])
    return im


for mode, name in [("1", "bilevel"), ("L", "gray"), ("I;16", "gray16"), ("P", "palette"),
                   ("RGB", "rgb"), ("RGBA", "rgba"), ("CMYK", "cmyk")]:
    for compression in ["raw", "packbits", "tiff_lzw", "tiff_adobe_deflate"]:
        short = {"raw": "raw", "packbits": "packbits", "tiff_lzw": "lzw", "tiff_adobe_deflate": "deflate"}[compression]
        image(mode).save(f"{name}_{short}.tif", compression=compression)
print("ok")


# Files Pillow does not write: tiles, the predictor, big-endian samples,
# and the photometric forms and sample sizes UTIF reads.
import struct
import zlib


def write(name, order, width, height, tags, chunks, offsets_tag=273, counts_tag=279, drop=(), counts=None):
    """Write a TIFF of one IFD: `tags` maps a tag to (type, values), and
    `chunks` are the strips or tiles, whose offsets and counts are filled."""
    e = "<" if order == "II" else ">"
    head = 8
    blobs = b""
    chunk_offsets = []
    for c in chunks:
        chunk_offsets.append(head + len(blobs))
        blobs += c
        if len(blobs) % 2:
            blobs += b"\0"
    tags = dict(tags)
    tags[256] = (4, [width])
    tags[257] = (4, [height])
    tags[offsets_tag] = (4, chunk_offsets)
    tags[counts_tag] = (4, counts or [len(c) for c in chunks])
    for tag in drop:
        tags.pop(tag, None)
    ifd_at = head + len(blobs)
    entries = sorted(tags.items())
    extra_at = ifd_at + 2 + 12 * len(entries) + 4
    extra = b""
    ifd = struct.pack(e + "H", len(entries))
    sizes = {0: "B", 1: "B", 2: "B", 3: "H", 4: "I", 6: "b", 7: "B", 13: "I", 14: "B"}
    for tag, (typ, values) in entries:
        packed = b"".join(struct.pack(e + sizes[typ], v) for v in values)
        if len(packed) <= 4:
            field = packed.ljust(4, b"\0")
        else:
            field = struct.pack(e + "I", extra_at + len(extra))
            extra += packed
            if len(extra) % 2:
                extra += b"\0"
        ifd += struct.pack(e + "HHI", tag, typ, len(values)) + field
    ifd += struct.pack(e + "I", 0)
    data = order.encode() + struct.pack(e + "HI", 42, ifd_at) + blobs + ifd + extra
    open(name, "wb").write(data)


def gray(bits, w=W, h=H):
    """Rows of samples of `bits` each, packed MSB first."""
    rows = b""
    for y in range(h):
        acc, n, row = 0, 0, b""
        for x in range(w):
            acc = (acc << bits) | (pixel(x, y, 0) >> (8 - bits))
            n += bits
            if n == 8:
                row += bytes([acc]); acc, n = 0, 0
        if n:
            row += bytes([acc << (8 - n)])
        rows += row
    return rows


def predict(rows, width, samples, size):
    """Difference each sample from the one a pixel before, TIFF's
    predictor 2, for bytes (`size` 1) or little-endian shorts (2)."""
    out = bytearray(rows)
    line = width * samples * size
    for y in range(len(rows) // line):
        start = y * line
        for x in range(line - size * samples, 0, -size) if size == 2 else range(line - 1, samples - 1, -1):
            if size == 2:
                a = start + x
                v = int.from_bytes(out[a:a + 2], "little") - int.from_bytes(out[a - 2 * samples:a - 2 * samples + 2], "little")
                out[a:a + 2] = (v & 0xFFFF).to_bytes(2, "little")
            else:
                out[start + x] = (out[start + x] - out[start + x - samples]) & 255
    return bytes(out)


rgb8 = bytes(pixel(x, y, k) for y in range(H) for x in range(W) for k in range(3))
base = {258: (3, [8, 8, 8]), 259: (3, [1]), 262: (3, [2]), 277: (3, [3])}
# Two strips of three and two rows.
write("strips.tif", "II", W, H, {**base, 278: (4, [3])}, [rgb8[:3 * W * 3], rgb8[3 * W * 3:]])
# Predictor 2 on RGB, gray bytes, and little-endian 16-bit gray, deflated.
write("predict_rgb.tif", "II", W, H, {**base, 317: (3, [2])}, [predict(rgb8, W, 3, 1)])
g8 = gray(8)
write("predict_gray.tif", "II", W, H, {258: (3, [8]), 259: (3, [8]), 262: (3, [1]), 317: (3, [2])},
      [zlib.compress(predict(g8, W, 1, 1))])
g16 = b"".join(((pixel(x, y, 0) * 251) & 0xFFFF).to_bytes(2, "little") for y in range(H) for x in range(W))
write("predict_gray16.tif", "II", W, H, {258: (3, [16]), 262: (3, [1]), 317: (3, [2])}, [predict(g16, W, 1, 2)])
# Big-endian 16-bit RGB and RGBA.
rgb16be = b"".join(((pixel(x, y, k) * 257) & 0xFFFF).to_bytes(2, "big") for y in range(H) for x in range(W) for k in range(3))
write("rgb16_be.tif", "MM", W, H, {258: (3, [16, 16, 16]), 262: (3, [2]), 277: (3, [3])}, [rgb16be])
rgba16 = b"".join(((pixel(x, y, k) * 257) & 0xFFFF).to_bytes(2, "little") for y in range(H) for x in range(W) for k in range(4))
write("rgba16.tif", "II", W, H, {258: (3, [16, 16, 16, 16]), 262: (3, [2]), 277: (3, [4])}, [rgba16])
# White is zero at 1, 4, 8 and 16 bits; black is zero at 2 and 4 bits.
for bits in [1, 4, 8]:
    write(f"white{bits}.tif", "II", W, H, {258: (3, [bits]), 262: (3, [0])}, [gray(bits)])
write("white16.tif", "II", W, H, {258: (3, [16]), 262: (3, [0])}, [g16])
for bits in [2, 4]:
    write(f"black{bits}.tif", "II", W, H, {258: (3, [bits]), 262: (3, [1])}, [gray(bits)])
# Gray with alpha: two samples, the first read.
ga = bytes(v for y in range(H) for x in range(W) for v in (pixel(x, y, 0), 99))
write("gray_alpha.tif", "II", W, H, {258: (3, [8, 8]), 262: (3, [1]), 277: (3, [2])}, [ga])
# 32-bit float gray and RGB, the RGB read through UTIF's gamma.
import array
fg = array.array("f", [pixel(x, y, 0) / 255 for y in range(H) for x in range(W)]).tobytes()
write("float_gray.tif", "II", W, H, {258: (3, [32]), 262: (3, [1]), 339: (3, [3])}, [fg])
frgb = array.array("f", [pixel(x, y, k) / 300 for y in range(H) for x in range(W) for k in range(3)]).tobytes()
write("float_rgb.tif", "II", W, H, {258: (3, [32, 32, 32]), 262: (3, [2]), 277: (3, [3]), 339: (3, [3, 3, 3])}, [frgb])
# A 4-bit palette, and an 8-bit palette with an alpha sample.
cmap = [(pixel(i, 1, c) * 257) & 0xFFFF for c in range(3) for i in range(16)]
write("palette4.tif", "II", W, H, {258: (3, [4]), 262: (3, [3]), 320: (3, cmap)}, [gray(4)])
cmap8 = [(pixel(i, 2, c) * 257) & 0xFFFF for c in range(3) for i in range(256)]
pa = bytes(v for y in range(H) for x in range(W) for v in (pixel(x, y, 0), pixel(x, y, 1)))
write("palette_alpha.tif", "II", W, H, {258: (3, [8, 8]), 262: (3, [3]), 277: (3, [2]), 320: (3, cmap8), 338: (3, [2])}, [pa])
# CMYK with a fifth, alpha, sample.
cmyka = bytes(pixel(x, y, k) for y in range(H) for x in range(W) for k in range(5))
write("cmyk_alpha.tif", "II", W, H, {258: (3, [8] * 5), 262: (3, [5]), 277: (3, [5])}, [cmyka])
# Tiles of 16 by 16 over a 20 by 18 RGB image, PackBits and deflate.
TW, TH, IW, IH = 16, 16, 20, 18
def tile(tx, ty):
    return bytes(pixel(tx * TW + x, ty * TH + y, k) if tx * TW + x < IW and ty * TH + y < IH else 0
                 for y in range(TH) for x in range(TW) for k in range(3))
def packbits(raw):
    out = b""
    for i in range(0, len(raw), 128):
        part = raw[i:i + 128]
        out += bytes([len(part) - 1]) + part
    return out
tiles = [tile(tx, ty) for ty in range(2) for tx in range(2)]
tiled = {258: (3, [8, 8, 8]), 262: (3, [2]), 277: (3, [3]), 322: (3, [TW]), 323: (3, [TH])}
write("tiled_packbits.tif", "II", IW, IH, {**tiled, 259: (3, [32773])}, [packbits(t) for t in tiles], 324, 325)
write("tiled_deflate.tif", "MM", IW, IH, {**tiled, 259: (3, [8])}, [zlib.compress(t) for t in tiles], 324, 325)
# A photometric form UTIF does not know: a transparency mask.
write("mask.tif", "II", W, H, {258: (3, [8]), 262: (3, [4])}, [g8])


# Edges of UTIF's decoder, for the coverage of the port's.
import random


def lzw(codes_or_data, clear=True, eoi=True, raw_codes=None):
    """TIFF LZW, most significant bit first, the width growing one code
    early as UTIF reads it. `raw_codes` writes those codes as they are."""
    codes = []
    if raw_codes is not None:
        codes = list(raw_codes)
    else:
        data = codes_or_data
        table = {bytes([i]): i for i in range(256)}
        nxt = 258
        if clear:
            codes.append(256)
        w = b""
        for c in data:
            wc = w + bytes([c])
            if wc in table:
                w = wc
            else:
                codes.append(table[w])
                if nxt < 4096:
                    table[wc] = nxt
                nxt += 1
                w = bytes([c])
        if w:
            codes.append(table[w])
        if eoi:
            codes.append(257)
    # The widths, as the decoder counts them.
    out, acc, n = bytearray(), 0, 0
    width, nxt, first = 9, 258, True
    for code in codes:
        acc = (acc << width) | code
        n += width
        while n >= 8:
            out.append((acc >> (n - 8)) & 255)
            n -= 8
            acc &= (1 << n) - 1
        if code == 256:
            width, nxt, first = 9, 258, True
        elif code == 257:
            pass
        elif first:
            first = False
        else:
            nxt += 1
            if nxt + 1 == 1 << width and width != 12:
                width += 1
    if n:
        out.append((acc << (8 - n)) & 255)
    return bytes(out)


gray8 = {258: (3, [8]), 262: (3, [1])}
rng = random.Random(7)
noise = bytes(rng.randrange(256) for _ in range(128 * 128))
write("lzw_noise.tif", "II", 128, 128, {**gray8, 259: (3, [5])}, [lzw(noise)])
write("lzw_runs.tif", "II", W, H, {**gray8, 259: (3, [5])}, [lzw(bytes([77] * (W * H)))])
write("lzw_no_eoi.tif", "II", W, H, {**gray8, 259: (3, [5])}, [lzw(g8, eoi=False)])
write("lzw_clear_eoi.tif", "II", W, H, {**gray8, 259: (3, [5])}, [lzw(None, raw_codes=[256, 257])])
write("lzw_bad_after_clear.tif", "II", W, H, {**gray8, 259: (3, [5])}, [lzw(None, raw_codes=[256, 300, 257])])
write("lzw_bad.tif", "II", W, H, {**gray8, 259: (3, [5])}, [lzw(None, raw_codes=[256, 65, 66, 400, 257])])
# PackBits: a no-op byte, a literal run past the image and a repeat past it.
pb = bytes([0x80, 4]) + g8[:5] + bytes([0x81, 9, 127]) + bytes(128) + bytes([0x81, 3])
write("packbits_edge.tif", "II", W, H, {**gray8, 259: (3, [32773])}, [pb])
# Tag types UTIF reads and skips: bytes inline and past the end, no
# shorts, an IFD offset, a signed byte of no count, and text.
odd = {**base, 40000: (1, [1, 2, 3]), 40001: (7, list(range(8))), 40003: (3, []), 40004: (13, [8]),
       40005: (6, []), 40006: (2, [65, 66, 67, 0])}
write("tags_odd.tif", "II", W, H, odd, [rgb8])
write("tag_type6.tif", "II", W, H, {**base, 40005: (6, [1])}, [rgb8])
write("tag_type14.tif", "II", W, H, {**base, 40005: (14, [1])}, [rgb8])
# Sizes and layouts UTIF cannot decode.
write("no_width.tif", "II", 0, H, gray8, [g8])
write("no_height.tif", "II", W, 0, gray8, [g8])
write("huge.tif", "II", 65535, 65535, gray8, [g8])
write("planar2.tif", "II", W, H, {**base, 284: (3, [2])}, [rgb8])
write("no_strips.tif", "II", W, H, gray8, [g8], drop=(273, 279))
write("no_counts.tif", "II", W, H, {**gray8, 259: (3, [32773])}, [packbits(g8)], drop=(279,))
write("short_strips.tif", "II", W, H, {**gray8, 278: (4, [2])}, [g8[: 2 * W]])
write("tile_missing.tif", "II", IW, IH, {**tiled, 259: (3, [32773])}, [packbits(t) for t in tiles[:3]], 324, 325)
# A second strip whose byte count runs past the file, and a byte tag
# whose count does.
write("past_end.tif", "II", W, H, {**gray8, 278: (4, [3])}, [g8[: 3 * W], g8[3 * W :]], counts=[3 * W, 5000])
# Its second strip moved to the file's last four bytes.
data = bytearray(open("past_end.tif", "rb").read())
entry = data.index(bytes([0x11, 0x01, 4, 0, 2, 0, 0, 0]))
pointer = int.from_bytes(data[entry + 8 : entry + 12], "little")
data[pointer + 4 : pointer + 8] = (len(data) - 4).to_bytes(4, "little")
open("past_end.tif", "wb").write(bytes(data))
write("tag_past_end.tif", "II", W, H, {**base, 40002: (7, list(range(8)))}, [rgb8])
data = bytearray(open("tag_past_end.tif", "rb").read())
entry = data.index(bytes([0x42, 0x9C, 7, 0]))
data[entry + 4 : entry + 8] = (5000).to_bytes(4, "little")
open("tag_past_end.tif", "wb").write(bytes(data))
open("short_header.tif", "wb").write(b"II*\0\0\0")
open("not_tiff.tif", "wb").write(b"XX*\0\x08\0\0\0\0\0")
# Samples UTIF reads in its own way.
fn = array.array("f", [float("nan") if (x + y) % 3 == 0 else -0.5 if (x + y) % 3 == 1 else 0.25 for y in range(H) for x in range(W)]).tobytes()
write("float_nan.tif", "II", W, H, {258: (3, [32]), 262: (3, [1]), 339: (3, [3])}, [fn])
write("bilevel_no_photometric.tif", "II", W, H, {258: (3, [1])}, [gray(1)])
write("photometric9.tif", "II", W, H, {262: (3, [9])}, [gray(1)], drop=(258,))
write("gray32_int.tif", "II", W, H, {258: (3, [32]), 262: (3, [1])}, [fg])
write("gray12.tif", "II", 2, H, {258: (3, [12]), 262: (3, [1])}, [bytes(3 * H)])
write("rgb_one.tif", "II", W, H, {258: (3, [8]), 262: (3, [2]), 277: (3, [1])}, [g8])
write("rgb_two.tif", "II", W, H, {258: (3, [8, 8]), 262: (3, [2]), 277: (3, [2])}, [ga])
write("rgb16_two.tif", "II", W, H, {258: (3, [16, 16]), 262: (3, [2]), 277: (3, [2])}, [rgba16[: W * H * 4]])
write("rgb4.tif", "II", W, H, {258: (3, [4, 4, 4]), 262: (3, [2]), 277: (3, [3])}, [gray(4) * 3])
write("float_rgb5.tif", "II", W, H, {258: (3, [32] * 5), 262: (3, [2]), 277: (3, [5]), 339: (3, [3] * 5)}, [frgb + frgb[: W * H * 8]])
fneg = array.array("f", [pixel(x, y, k) / 300 - (0.5 if k == 1 else 0) for y in range(H) for x in range(W) for k in range(3)]).tobytes()
write("float_rgb_swap.tif", "II", W, H, {258: (3, [32, 32, 32]), 262: (3, [2]), 277: (3, [3]), 339: (3, [3, 3, 3])}, [fneg])
cmap2 = [(pixel(i, 3, c) * 257) & 0xFFFF for c in range(3) for i in range(4)]
write("palette1.tif", "II", W, H, {258: (3, [1]), 262: (3, [3]), 320: (3, cmap2[:2] + cmap2[4:6] + cmap2[8:10])}, [gray(1)])
write("palette2.tif", "II", W, H, {258: (3, [2]), 262: (3, [3]), 320: (3, cmap2)}, [gray(2)])
write("palette16.tif", "II", W, H, {258: (3, [16]), 262: (3, [3]), 320: (3, cmap2)}, [g16])
# More compressions: an unknown one, deflate by its other number, and a
# deflated strip longer than the image.
write("compression99.tif", "II", W, H, {**gray8, 259: (3, [99])}, [g8])
write("deflate32946.tif", "II", W, H, {**gray8, 259: (3, [32946])}, [zlib.compress(g8)])
write("deflate_big.tif", "II", W, H, {**gray8, 259: (3, [8])}, [zlib.compress(g8 + g8)])
# The predictor over strips whose last is short, and 16-bit big-endian
# samples the same way.
write("predict_strips.tif", "II", W, H, {**gray8, 278: (4, [3]), 317: (3, [2])},
      [predict(g8[: 3 * W], W, 1, 1), predict(g8[3 * W :], W, 1, 1)])
g16be = b"".join(((pixel(x, y, 0) * 251) & 0xFFFF).to_bytes(2, "big") for y in range(H) for x in range(W))
write("gray16_be_strips.tif", "MM", W, H, {258: (3, [16]), 262: (3, [1]), 278: (4, [3])},
      [g16be[: 3 * W * 2], g16be[3 * W * 2 :]])
# Tiles with fewer byte counts than offsets.
write("tile_counts.tif", "II", IW, IH, {**tiled, 259: (3, [32773])}, [packbits(t) for t in tiles], 324, 325,
      counts=[len(packbits(t)) for t in tiles[:3]])
# No photometric tag on 8-bit samples; 2-bit white-is-zero; float RGBA;
# an empty predictor tag; and a tag of type zero.
write("no_photometric8.tif", "II", W, H, {258: (3, [8])}, [g8])
write("white2.tif", "II", W, H, {258: (3, [2]), 262: (3, [0])}, [gray(2)])
frgba = array.array("f", [pixel(x, y, k) / 300 for y in range(H) for x in range(W) for k in range(4)]).tobytes()
write("float_rgba.tif", "II", W, H, {258: (3, [32] * 4), 262: (3, [2]), 277: (3, [4]), 339: (3, [3] * 4)}, [frgba])
write("predictor_empty.tif", "II", W, H, {**gray8, 317: (3, [])}, [g8])
write("tag_type0.tif", "II", W, H, {**gray8, 40005: (0, [])}, [g8])
data = bytearray(open("tag_type0.tif", "rb").read())
entry = data.index(bytes([0x45, 0x9C, 0, 0]))
data[entry + 4 : entry + 8] = (1).to_bytes(4, "little")
open("tag_type0.tif", "wb").write(bytes(data))
print("written")

