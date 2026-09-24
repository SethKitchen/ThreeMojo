# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check every Draco export of `assets/draco/export/` against three.js.

`tests/test_draco_export.mojo` checks a representative subset of the
cases, so that the suite stays fast. This tool checks all of them: each
export must have the bytes that three.js's `DRACOExporter` writes, or be
refused where three.js throws, and each file must decode. It is not in
`make test` or `make coverage`. Run it with `make draco-export-check`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry
from exporters.draco import (
    DRACO_EXPORT_MESH,
    DRACO_EXPORT_POINTS,
    DracoEncoderMethod,
    DracoExportOptions,
    export_draco,
)
from loaders.draco import decode_draco
from loaders.json import JsonDocument, parse_json
from std.memory import bitcast
from std.pathlib import Path

comptime _DIR = "assets/draco/export/"


def _word(words: List[UInt8], i: Int) -> Int:
    """The little-endian 32-bit word `i` of `three.bin`."""
    var at = 4 * i
    return (
        Int(words[at])
        | (Int(words[at + 1]) << 8)
        | (Int(words[at + 2]) << 16)
        | (Int(words[at + 3]) << 24)
    )


def _geometry(
    doc: JsonDocument, words: List[UInt8], name: String
) raises -> BufferGeometry:
    """The input geometry of a case."""
    var g = doc.get(doc.get(doc.root(), "geometries"), name)
    var geometry = BufferGeometry()
    var attributes = doc.get(g, "attributes")
    for a in range(doc.length(attributes)):
        var key = doc.key(attributes, a)
        var entry = doc.get(attributes, key)
        var w = doc.get(entry, "words")
        var start = doc.integer(doc.at(w, 0))
        var values = List[Float32]()
        for i in range(start, start + doc.integer(doc.at(w, 1))):
            values.append(bitcast[DType.float32](UInt32(_word(words, i))))
        geometry.set_attribute(
            key,
            BufferAttribute(values^, doc.integer(doc.get(entry, "itemSize"))),
        )
    if doc.has(g, "index"):
        var w = doc.get(g, "index")
        var start = doc.integer(doc.at(w, 0))
        var index = List[Int]()
        for i in range(start, start + doc.integer(doc.at(w, 1))):
            index.append(_word(words, i))
        geometry.set_index(index^)
    return geometry^


def _options(doc: JsonDocument, entry: Int) raises -> DracoExportOptions:
    """The options of a case, as three.js's `DRACOExporter` reads them."""
    var o = doc.get(entry, "options")
    var options = DracoExportOptions()
    if doc.has(o, "encodeSpeed"):
        options.encode_speed = doc.integer(doc.get(o, "encodeSpeed"))
    if doc.has(o, "decodeSpeed"):
        options.decode_speed = doc.integer(doc.get(o, "decodeSpeed"))
    if doc.has(o, "encoderMethod"):
        options.encoder_method = DracoEncoderMethod(
            doc.integer(doc.get(o, "encoderMethod"))
        )
    if doc.has(o, "exportUvs"):
        options.export_uvs = doc.boolean(doc.get(o, "exportUvs"))
    if doc.has(o, "exportNormals"):
        options.export_normals = doc.boolean(doc.get(o, "exportNormals"))
    if doc.has(o, "exportColor"):
        options.export_color = doc.boolean(doc.get(o, "exportColor"))
    if doc.has(o, "quantization"):
        var q = doc.get(o, "quantization")
        options.quantization.clear()
        for i in range(doc.length(q)):
            options.quantization.append(doc.integer(doc.at(q, i)))
    return options^


def main() raises:
    var doc = parse_json(
        String(unsafe_from_utf8=Path(_DIR + "three.json").read_bytes())
    )
    var words = Path(_DIR + "three.bin").read_bytes()
    var cases = doc.get(doc.root(), "cases")
    var failed = 0
    for k in range(doc.length(cases)):
        var entry = doc.at(cases, k)
        var name = doc.string(doc.get(entry, "geometry"))
        var kind = DRACO_EXPORT_MESH
        var g = doc.get(doc.get(doc.root(), "geometries"), name)
        if doc.string(doc.get(g, "kind")) == "points":
            kind = DRACO_EXPORT_POINTS
        var geometry = _geometry(doc, words, name)
        var options = _options(doc, entry)
        var label = "case " + String(k) + " (" + name + ")"
        if doc.has(entry, "error"):
            try:
                _ = export_draco(geometry, kind, options)
                print("FAIL", label, "is written; three.js throws")
                failed += 1
            except:
                pass
            continue
        var w = doc.get(entry, "bytes")
        var start = doc.integer(doc.at(w, 0))
        var want = List[UInt8]()
        for i in range(doc.integer(doc.at(w, 1))):
            want.append(words[4 * start + i])
        var got = export_draco(geometry, kind, options)
        if got != want:
            print("FAIL", label, "has other bytes than three.js")
            failed += 1
            continue
        _ = decode_draco(got)
    var total = doc.length(cases)
    if failed > 0:
        raise Error(String(failed) + " of " + String(total) + " cases fail")
    print("All", total, "Draco exports match three.js.")
