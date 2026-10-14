# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Build a reproducible synthetic CARLA model-cache benchmark fixture.

This is a load-size proxy, not a CARLA source asset: 34,992 indexed
triangles, six materials, and one 1024-square RGBA texture with mipmaps.
Run: `mojo run -I . bench/carla_model_cache_fixture.mojo /tmp/carla-cache-bench`

The texture's zlib stream comes from `render/deflate` at level 6, so its
bytes, and its SHA-256, differ from the Python generator that this tool
replaces. Its pixels, the geometry and the glTF text are the same.
"""

from std.memory import bitcast
from std.os import makedirs
from std.pathlib import Path
from std.sys import argv, exit, stderr

from render.deflate import zlib_deflate
from render.png import push_be32, push_chunk, push_ihdr, push_signature
from tools._json_tools import JsonWriter
from tools._sha256 import sha256_hex

comptime CELLS = 54
"""The grid cells along each edge of each box face."""
comptime SIZE = 1024
"""The texture's width and height, in pixels."""
comptime FLOAT = 5126
"""The glTF component type of a float."""
comptime UINT = 5125
"""The glTF component type of an unsigned int."""


struct Model(Movable):
    """The binary buffer and the glTF objects that describe it."""

    var binary: List[UInt8]
    """The vertex and index bytes."""
    var views: List[String]
    """The buffer views, as compact JSON."""
    var accessors: List[String]
    """The accessors, as compact JSON."""

    def __init__(out self):
        """Start an empty model."""
        self.binary = List[UInt8]()
        self.views = List[String]()
        self.accessors = List[String]()

    def _view(mut self, offset: Int) -> Int:
        """Add a buffer view from an offset to the end of the buffer."""
        self.views.append(
            '{"buffer":0,"byteOffset":'
            + String(offset)
            + ',"byteLength":'
            + String(len(self.binary) - offset)
            + "}"
        )
        return len(self.views) - 1

    def _accessor(
        mut self, view: Int, component: Int, count: Int, width: Int
    ) -> Int:
        """Add an accessor of a view."""
        var kind = "SCALAR" if width == 1 else (
            "VEC2" if width == 2 else "VEC3"
        )
        self.accessors.append(
            '{"bufferView":'
            + String(view)
            + ',"componentType":'
            + String(component)
            + ',"count":'
            + String(count)
            + ',"type":"'
            + kind
            + '"}'
        )
        return len(self.accessors) - 1

    def floats(mut self, values: List[Float64], width: Int) -> Int:
        """Add little-endian Float32 values and their accessor.

        Args:
            values: The values, rounded to Float32.
            width: The components per element.

        Returns:
            The accessor index.
        """
        var offset = len(self.binary)
        for value in values:
            _push_le32(self.binary, bitcast[DType.uint32](Float32(value)))
        return self._accessor(
            self._view(offset), FLOAT, len(values) // width, width
        )

    def indices(mut self, values: List[Int]) -> Int:
        """Add little-endian UInt32 indices and their accessor.

        Args:
            values: The indices.

        Returns:
            The accessor index.
        """
        var offset = len(self.binary)
        for value in values:
            _push_le32(self.binary, UInt32(value))
        return self._accessor(self._view(offset), UINT, len(values), 1)


def _push_le32(mut out: List[UInt8], value: UInt32):
    """Append four little-endian bytes."""
    for shift in [0, 8, 16, 24]:
        out.append(UInt8((value >> UInt32(shift)) & 255))


def box(mut model: Model) -> List[String]:
    """Add six gridded box faces, one material each.

    Args:
        model: The model.

    Returns:
        The primitives, as compact JSON.
    """
    var extents: List[Float64] = [2.3, 0.75, 0.9]
    var primitives = List[String]()
    for face in range(6):
        var axis = face // 2
        var sign = 1 if face % 2 else -1
        var u = (axis + 1) % 3
        var v = (axis + 2) % 3
        var positions = List[Float64]()
        var normals = List[Float64]()
        var uv = List[Float64]()
        var indices = List[Int]()
        for row in range(CELLS + 1):
            for column in range(CELLS + 1):
                var point: List[Float64] = [0.0, 0.0, 0.0]
                var normal: List[Float64] = [0.0, 0.0, 0.0]
                point[axis] = Float64(sign) * extents[axis]
                point[u] = (
                    Float64(2 * column) / Float64(CELLS) - 1.0
                ) * extents[u]
                point[v] = (Float64(2 * row) / Float64(CELLS) - 1.0) * extents[
                    v
                ]
                normal[axis] = Float64(sign)
                positions.extend(point^)
                normals.extend(normal^)
                uv.append(Float64(column) / Float64(CELLS))
                uv.append(Float64(row) / Float64(CELLS))
        for row in range(CELLS):
            for column in range(CELLS):
                var a = row * (CELLS + 1) + column
                var b = a + CELLS + 1
                indices.extend([a, a + 1, b, a + 1, b + 1, b])
        var position = model.floats(positions, 3)
        var normal = model.floats(normals, 3)
        var texcoord = model.floats(uv, 2)
        var index = model.indices(indices)
        primitives.append(
            '{"attributes":{"POSITION":'
            + String(position)
            + ',"NORMAL":'
            + String(normal)
            + ',"TEXCOORD_0":'
            + String(texcoord)
            + '},"indices":'
            + String(index)
            + ',"material":'
            + String(face)
            + "}"
        )
    return primitives^


def texture() raises -> List[UInt8]:
    """Return a 1024-square RGBA PNG of coordinate patterns.

    Returns:
        The PNG file.

    Raises:
        Error: If compression fails.
    """
    var rows = List[UInt8](capacity=SIZE * (SIZE * 4 + 1))
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            rows.append(UInt8(x % 256))
            rows.append(UInt8(y % 256))
            rows.append(UInt8((x ^ y) % 256))
            rows.append(255)
    var png = List[UInt8]()
    push_signature(png)
    push_ihdr(png, SIZE, SIZE)
    push_chunk(png, "IDAT", zlib_deflate(Span(rows)))
    push_chunk(png, "IEND", List[UInt8]())
    return png^


def _join(items: List[String]) -> String:
    """Return a compact JSON array of JSON values."""
    return "[" + ",".join(items) + "]"


def generate(destination: String) raises -> String:
    """Write a manifest and its self-contained glTF dependencies.

    Args:
        destination: The folder to write in. It is created if needed.

    Returns:
        The summary: the triangle count and each file's hash, as JSON.

    Raises:
        Error: If a file cannot be written.
    """
    makedirs(destination, exist_ok=True)
    var model = Model()
    var primitives = box(model)
    Path(destination + "/vehicle.bin").write_bytes(model.binary)
    Path(destination + "/vehicle.png").write_bytes(texture())
    var materials = List[String]()
    for tag in ["paint", "heads", "tails", "glass", "rubber", "chrome"]:
        materials.append(
            '{"extras":{"carla":"'
            + tag
            + '"},"pbrMetallicRoughness":{"baseColorTexture":{"index":0},'
            + '"roughnessFactor":0.5}}'
        )
    var gltf = (
        '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],'
        + '"nodes":[{"mesh":0}],"buffers":[{"byteLength":'
        + String(len(model.binary))
        + ',"uri":"vehicle.bin"}],"bufferViews":'
        + _join(model.views)
        + ',"accessors":'
        + _join(model.accessors)
        + ',"meshes":[{"primitives":'
        + _join(primitives)
        + '}],"materials":'
        + _join(materials)
        + ',"images":[{"uri":"vehicle.png"}],'
        + '"samplers":[{"minFilter":9987}],'
        + '"textures":[{"source":0,"sampler":0}]}\n'
    )
    Path(destination + "/vehicle.gltf").write_text(gltf)
    var manifest = JsonWriter()
    manifest.begin_object()
    manifest.key("format")
    manifest.integer(1)
    manifest.key("entries")
    manifest.begin_array()
    manifest.begin_object()
    for pair in [
        ("id", "synthetic.vehicle"),
        ("kind", "model"),
        ("license", "CC0-1.0"),
        ("author", "ThreeMojo contributors"),
        ("source", "https://github.com/SethKitchen/ThreeMojo/issues/291"),
        ("provenance", "Synthetic load-size proxy. No CARLA source data."),
        ("forward", "+x"),
    ]:
        manifest.key(pair[0])
        manifest.string(pair[1])
    manifest.key("files")
    var summary = JsonWriter()
    summary.begin_object()
    summary.key("triangles")
    summary.integer(6 * CELLS * CELLS * 2)
    summary.key("files")
    manifest.begin_array()
    summary.begin_array()
    for pair in [
        ("model", "vehicle.gltf"),
        ("support", "vehicle.bin"),
        ("support", "vehicle.png"),
    ]:
        var digest = sha256_hex(
            Span(Path(destination + "/" + pair[1]).read_bytes())
        )
        manifest.begin_object()
        summary.begin_object()
        manifest.key("role")
        manifest.string(pair[0])
        summary.key("role")
        summary.string(pair[0])
        manifest.key("path")
        manifest.string(pair[1])
        summary.key("path")
        summary.string(pair[1])
        manifest.key("url")
        manifest.null()
        summary.key("url")
        summary.null()
        manifest.key("sha256")
        manifest.string(digest)
        summary.key("sha256")
        summary.string(digest)
        manifest.end()
        summary.end()
    manifest.end()
    summary.end()
    summary.end()
    manifest.end()
    manifest.end()
    manifest.key("bindings")
    manifest.begin_object()
    manifest.key("vehicle.*")
    manifest.string("synthetic.vehicle")
    manifest.end()
    manifest.end()
    Path(destination + "/manifest.json").write_text(manifest.text() + "\n")
    return summary.text()


def main() raises:
    var given = argv()
    if len(given) != 2:
        print("usage: carla_model_cache_fixture DESTINATION", file=stderr)
        exit(2)
    print(generate(String(given[1])))
