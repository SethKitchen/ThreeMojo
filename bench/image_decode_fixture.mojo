# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Create deterministic, offline image-loading fixtures for #505.

Each dataset is a folder of opaque RGBA8 PNG files, a glTF scene that uses
every image, and an asset manifest. `fixtures.json` records each file's
size and SHA-256, and the output that a correct loader must give.

The PNG streams come from the system zlib at level six, so the bytes and
hashes are the ones the earlier Python generator wrote with the same zlib.

Usage:
    image_decode_fixture DESTINATION [--count N] [--alignment W]
        [--datasets NAME ...]
"""

from std.ffi import OwnedDLHandle, external_call
from std.os import makedirs, mkdir
from std.os.path import exists, realpath
from std.pathlib import Path, cwd
from std.reflection import source_location
from std.sys import CompilationTarget, argv, exit, stderr

from tools._json_value import JsonTree
from tools._sha256 import sha256_hex
from tools._zlib import compress, crc32

comptime FNV_OFFSET = UInt64(14695981039346656037)
"""The FNV-1a 64-bit offset basis."""
comptime FNV_PRIME = UInt64(1099511628211)
"""The FNV-1a 64-bit prime."""
comptime LARGE = 768
"""The size of a slow job's image, in pixels."""


def dataset_names() -> List[String]:
    """Return the dataset names in their fixed order.

    Returns:
        `uniform_tiny`, `uniform_medium`, `stride_skew`, `batch_boundary`.
    """
    return [
        String("uniform_tiny"),
        String("uniform_medium"),
        String("stride_skew"),
        String("batch_boundary"),
    ]


def fnv64(data: Span[UInt8, _], state: UInt64 = FNV_OFFSET) -> UInt64:
    """Return the FNV-1a 64-bit hash of bytes.

    Args:
        data: The bytes.
        state: The running hash to continue.

    Returns:
        The hash.
    """
    var value = state
    for byte in data:
        value = (value ^ UInt64(byte)) * FNV_PRIME
    return value


def dimensions(dataset: String, count: Int, alignment: Int) raises -> List[Int]:
    """Return the image sizes in job order.

    Large jobs test two scheduling failure modes. In `stride_skew`, every
    large job belongs to stride worker zero when there are `alignment`
    workers. In `batch_boundary`, large jobs sit on both sides of
    alternating batch boundaries.

    Args:
        dataset: A dataset name.
        count: The number of images.
        alignment: The worker count that the large jobs align to.

    Returns:
        The width, which is also the height, of each image.

    Raises:
        Error: If the dataset name is unknown.
    """
    var sizes = List[Int]()
    for i in range(count):
        if dataset == "uniform_tiny":
            sizes.append(16)
        elif dataset == "uniform_medium":
            sizes.append(256)
        elif dataset == "stride_skew":
            sizes.append(LARGE if i % alignment == 0 else 64)
        elif dataset == "batch_boundary":
            var place = i % (2 * alignment)
            sizes.append(
                LARGE if place == alignment - 1 or place == alignment else 64
            )
        else:
            raise Error(dataset)
    if count == 0 and not dataset in dataset_names():
        raise Error(dataset)
    return sizes^


def rgba(size: Int, seed: Int) -> List[UInt8]:
    """Return the deterministic RGBA8 pixels of one image.

    Args:
        size: The width and height.
        seed: The image's seed.

    Returns:
        `size * size * 4` bytes, row by row.
    """
    var result = List[UInt8](capacity=size * size * 4)
    for y in range(size):
        for x in range(size):
            result.append(UInt8((17 * x + 29 * y + 13 * seed) & 255))
            result.append(UInt8((x ^ y ^ seed) & 255))
            result.append(UInt8((7 * x + 11 * y + 3 * seed) & 255))
            result.append(255)
    return result^


def _big_endian(mut out: List[UInt8], value: UInt32):
    """Append a 32-bit big-endian integer."""
    for shift in [24, 16, 8, 0]:
        out.append(UInt8((value >> UInt32(shift)) & 255))


def _chunk(mut out: List[UInt8], kind: String, data: List[UInt8]) raises:
    """Append one PNG chunk with its length and CRC."""
    _big_endian(out, UInt32(len(data)))
    var body = List[UInt8](kind.as_bytes())
    body.extend(Span(data))
    out.extend(Span(body))
    _big_endian(out, crc32(body))


def png(size: Int, pixels: List[UInt8]) raises -> List[UInt8]:
    """Return an RGBA8 PNG with filter zero and a level-six zlib stream.

    Args:
        size: The width and height.
        pixels: The RGBA8 pixels.

    Returns:
        The PNG file.

    Raises:
        Error: If zlib fails.
    """
    var stride = size * 4
    var raw = List[UInt8](capacity=size * (stride + 1))
    for y in range(size):
        raw.append(0)
        raw.extend(Span(pixels)[y * stride : (y + 1) * stride])
    var out: List[UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    var header = List[UInt8]()
    _big_endian(header, UInt32(size))
    _big_endian(header, UInt32(size))
    for value in [8, 6, 0, 0, 0]:
        header.append(UInt8(value))
    _chunk(out, "IHDR", header)
    _chunk(out, "IDAT", compress(raw, 6))
    _chunk(out, "IEND", List[UInt8]())
    return out^


def mip_shape(size: Int) -> List[Int]:
    """Return the size of each mip level, down to one pixel.

    Args:
        size: The base size.

    Returns:
        The sizes, largest first.
    """
    var sizes = List[Int]()
    var level = size
    while True:
        sizes.append(level)
        if level == 1:
            return sizes^
        level = max(1, level // 2)


def write_json(tree: JsonTree, node: Int, path: String) raises:
    """Write a node as `json.dumps(value, indent=2)` and a newline.

    Args:
        tree: The tree.
        node: The value.
        path: The file.

    Raises:
        Error: If the file cannot be written.
    """
    Path(path).write_text(tree.dumps(node, 2, False, ",", ": ") + "\n")


def resolve_path(path: String) raises -> String:
    """Return an absolute path with symbolic links resolved, as
    `pathlib.Path.resolve()` does for a path that may not exist.

    Args:
        path: A path.

    Returns:
        The real path of the longest existing prefix, and the rest.

    Raises:
        Error: If the working directory cannot be read.
    """
    var absolute = path if path.startswith("/") else String(cwd()) + "/" + path
    var parts = List[String]()
    for part in absolute.split("/"):
        if part == "" or part == ".":
            continue
        if part == "..":
            if len(parts) > 0:
                _ = parts.pop()
            continue
        parts.append(String(part))
    # Resolve the longest prefix that exists; keep the rest as written.
    var split = len(parts)
    while split > 0:
        var prefix = String()
        for i in range(split):
            prefix += "/" + parts[i]
        if exists(prefix):
            var result = realpath(prefix)
            for i in range(split, len(parts)):
                result += "/" + parts[i]
            return result
        split -= 1
    var result = String()
    for part in parts:
        result += "/" + part
    return result if result.byte_length() > 0 else String("/")


def zlib_version() raises -> String:
    """Return the version text of the system zlib, `zlibVersion()`.

    Returns:
        The version, such as `1.3`.

    Raises:
        Error: If zlib cannot be loaded.
    """
    var library: OwnedDLHandle
    comptime if CompilationTarget.is_macos():
        library = OwnedDLHandle("libz.1.dylib")
    else:
        library = OwnedDLHandle("libz.so.1")
    var address = library.call["zlibVersion", Int]()
    var length = external_call["strlen", Int](address)
    var bytes = List[UInt8](length=length, fill=0)
    _ = external_call["memcpy", Int](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), address, length
    )
    # The text lives in the library, so keep it loaded until the copy.
    _ = library^
    var text = String(from_utf8_lossy=bytes)
    return text^


def generator_sha256() raises -> String:
    """Return the SHA-256 of this generator's source file.

    Returns:
        The hexadecimal digest.

    Raises:
        Error: If the source file cannot be read.
    """
    return sha256_hex(Span(Path(source_location().file_name()).read_bytes()))


def _file(mut tree: JsonTree, name: String, content: List[UInt8]) raises -> Int:
    """Add a `{path, bytes, sha256}` file record."""
    var record = tree.object()
    tree.set(record, "path", tree.string(name))
    tree.set(record, "bytes", tree.integer(len(content)))
    tree.set(record, "sha256", tree.string(sha256_hex(Span(content))))
    return record


def _vec(mut tree: JsonTree, a: Int, b: Int, c: Int) raises -> Int:
    """Add a three-integer array."""
    var node = tree.array()
    tree.append(node, tree.integer(a))
    tree.append(node, tree.integer(b))
    tree.append(node, tree.integer(c))
    return node


def _view(mut tree: JsonTree, offset: Int, length: Int) raises -> Int:
    """Add a buffer view of buffer zero."""
    var view = tree.object()
    tree.set(view, "buffer", tree.integer(0))
    tree.set(view, "byteOffset", tree.integer(offset))
    tree.set(view, "byteLength", tree.integer(length))
    return view


def _accessor(
    mut tree: JsonTree, view: Int, component: Int, kind: String
) raises -> Int:
    """Add an accessor of three elements."""
    var accessor = tree.object()
    tree.set(accessor, "bufferView", tree.integer(view))
    tree.set(accessor, "componentType", tree.integer(component))
    tree.set(accessor, "count", tree.integer(3))
    tree.set(accessor, "type", tree.string(kind))
    return accessor


def triangle() -> List[UInt8]:
    """Return the geometry buffer: `struct.pack("<15f3H", ...)`.

    Three positions, three texture coordinates, and three 16-bit indices.

    Returns:
        66 little-endian bytes.
    """
    var out = List[UInt8]()
    for value in [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1]:
        # 1.0f is 0x3F800000; 0.0f is all zero bits.
        out.append(0)
        out.append(0)
        out.append(UInt8(0x80 if value == 1 else 0))
        out.append(UInt8(0x3F if value == 1 else 0))
    for index in [0, 1, 2]:
        out.append(UInt8(index))
        out.append(0)
    return out^


def generate_one(
    mut tree: JsonTree,
    root: String,
    dataset: String,
    count: Int,
    alignment: Int,
) raises -> Int:
    """Write one dataset folder and return its record.

    Args:
        tree: The tree for the record.
        root: The fixture folder.
        dataset: The dataset name.
        count: The number of images.
        alignment: The worker count that the large jobs align to.

    Returns:
        The dataset record node.

    Raises:
        Error: If the folder exists or a file cannot be written.
    """
    var destination = root + "/" + dataset
    if exists(destination):
        raise Error("[Errno 17] File exists: '" + destination + "'")
    makedirs(destination)
    var entries = tree.array()
    var images = tree.array()
    var textures = tree.array()
    var materials = tree.array()
    var files = tree.array()
    var bindings = tree.object()
    var base_hash = FNV_OFFSET
    var base_bytes = 0
    var payload_bytes = 0
    var levels = 0
    var compressed_bytes = 0
    var sizes = dimensions(dataset, count, alignment)
    for index in range(len(sizes)):
        var size = sizes[index]
        var number = String(index)
        while number.byte_length() < 4:
            number = "0" + number
        var name = "image-" + number + ".png"
        var pixels = rgba(size, index + 1)
        base_hash = fnv64(Span(pixels), base_hash)
        var encoded = png(size, pixels)
        Path(destination + "/" + name).write_bytes(Span(encoded))
        var digest = sha256_hex(Span(encoded))
        var chain = mip_shape(size)
        base_bytes += len(pixels)
        for level in chain:
            payload_bytes += level * level * 4
        levels += len(chain)
        compressed_bytes += len(encoded)
        var record = _file(tree, name, encoded)
        tree.set(record, "width", tree.integer(size))
        tree.set(record, "height", tree.integer(size))
        tree.set(record, "job", tree.integer(index))
        tree.append(files, record)
        var image = tree.object()
        tree.set(image, "uri", tree.string(name))
        tree.append(images, image)
        var texture = tree.object()
        tree.set(texture, "source", tree.integer(index))
        tree.set(texture, "sampler", tree.integer(0))
        tree.append(textures, texture)
        var base_color = tree.object()
        tree.set(base_color, "index", tree.integer(index))
        var pbr = tree.object()
        tree.set(pbr, "baseColorTexture", base_color)
        tree.set(pbr, "roughnessFactor", tree.number(0.5))
        var material = tree.object()
        tree.set(material, "pbrMetallicRoughness", pbr)
        tree.append(materials, material)
        var identifier = "synthetic.image." + number
        var entry = tree.object()
        tree.set(entry, "id", tree.string(identifier))
        tree.set(entry, "kind", tree.string("texture_set"))
        tree.set(entry, "license", tree.string("CC0-1.0"))
        tree.set(entry, "author", tree.string("ThreeMojo contributors"))
        tree.set(entry, "source", tree.string("synthetic"))
        tree.set(
            entry,
            "provenance",
            tree.string(
                "Deterministic benchmark pixels; no external source data."
            ),
        )
        tree.set(entry, "tile_meters", tree.integer(1))
        var albedo = tree.object()
        tree.set(albedo, "role", tree.string("albedo"))
        tree.set(albedo, "path", tree.string(name))
        tree.set(albedo, "sha256", tree.string(digest))
        var entry_files = tree.array()
        tree.append(entry_files, albedo)
        tree.set(entry, "files", entry_files)
        tree.append(entries, entry)
        tree.set(bindings, "surface." + number, tree.string(identifier))
    # Every material is used by a real triangle. Geometry is deliberately small.
    var binary = triangle()
    Path(destination + "/triangle.bin").write_bytes(Span(binary))
    var gltf = tree.object()
    var asset = tree.object()
    tree.set(asset, "version", tree.string("2.0"))
    tree.set(gltf, "asset", asset)
    tree.set(gltf, "scene", tree.integer(0))
    var scene = tree.object()
    tree.set(scene, "nodes", tree.integers([0]))
    var scenes = tree.array()
    tree.append(scenes, scene)
    tree.set(gltf, "scenes", scenes)
    var node = tree.object()
    tree.set(node, "mesh", tree.integer(0))
    var nodes = tree.array()
    tree.append(nodes, node)
    tree.set(gltf, "nodes", nodes)
    var buffer = tree.object()
    tree.set(buffer, "uri", tree.string("triangle.bin"))
    tree.set(buffer, "byteLength", tree.integer(len(binary)))
    var buffers = tree.array()
    tree.append(buffers, buffer)
    tree.set(gltf, "buffers", buffers)
    var views = tree.array()
    tree.append(views, _view(tree, 0, 36))
    tree.append(views, _view(tree, 36, 24))
    tree.append(views, _view(tree, 60, 6))
    tree.set(gltf, "bufferViews", views)
    var accessors = tree.array()
    var position = _accessor(tree, 0, 5126, "VEC3")
    tree.set(position, "min", _vec(tree, 0, 0, 0))
    tree.set(position, "max", _vec(tree, 1, 1, 0))
    tree.append(accessors, position)
    tree.append(accessors, _accessor(tree, 1, 5126, "VEC2"))
    tree.append(accessors, _accessor(tree, 2, 5123, "SCALAR"))
    tree.set(gltf, "accessors", accessors)
    var primitives = tree.array()
    for index in range(count):
        var attributes = tree.object()
        tree.set(attributes, "POSITION", tree.integer(0))
        tree.set(attributes, "TEXCOORD_0", tree.integer(1))
        var primitive = tree.object()
        tree.set(primitive, "attributes", attributes)
        tree.set(primitive, "indices", tree.integer(2))
        tree.set(primitive, "material", tree.integer(index))
        tree.append(primitives, primitive)
    var mesh = tree.object()
    tree.set(mesh, "primitives", primitives)
    var meshes = tree.array()
    tree.append(meshes, mesh)
    tree.set(gltf, "meshes", meshes)
    tree.set(gltf, "images", images)
    tree.set(gltf, "textures", textures)
    tree.set(gltf, "materials", materials)
    var sampler = tree.object()
    tree.set(sampler, "magFilter", tree.integer(9729))
    tree.set(sampler, "minFilter", tree.integer(9987))
    tree.set(sampler, "wrapS", tree.integer(10497))
    tree.set(sampler, "wrapT", tree.integer(10497))
    var samplers = tree.array()
    tree.append(samplers, sampler)
    tree.set(gltf, "samplers", samplers)
    write_json(tree, gltf, destination + "/scene.gltf")
    var manifest = tree.object()
    tree.set(manifest, "format", tree.integer(1))
    tree.set(manifest, "entries", entries)
    tree.set(manifest, "bindings", bindings)
    write_json(tree, manifest, destination + "/manifest.json")
    for name in ["triangle.bin", "scene.gltf", "manifest.json"]:
        var content = Path(destination + "/" + name).read_bytes()
        tree.append(files, _file(tree, name, content))
    var slow = List[Int]()
    for index in range(len(sizes)):
        if sizes[index] == LARGE:
            slow.append(index)
    var expected = tree.object()
    tree.set(expected, "textures", tree.integer(count))
    tree.set(expected, "base_bytes", tree.integer(base_bytes))
    tree.set(expected, "payload_bytes", tree.integer(payload_bytes))
    tree.set(expected, "mip_levels", tree.integer(levels))
    tree.set(expected, "base_fnv64", tree.unsigned(base_hash))
    var result = tree.object()
    tree.set(result, "name", tree.string(dataset))
    tree.set(result, "path", tree.string(dataset))
    tree.set(result, "count", tree.integer(count))
    tree.set(result, "alignment_workers", tree.integer(alignment))
    tree.set(result, "sizes", tree.integers(sizes))
    tree.set(result, "slow_jobs", tree.integers(slow))
    tree.set(result, "expected", expected)
    tree.set(result, "compressed_bytes", tree.integer(compressed_bytes))
    tree.set(result, "files", files)
    return result


struct Fixtures(Movable):
    """A generated fixture set: its manifest and where it is."""

    var tree: JsonTree
    """The values."""
    var manifest: Int
    """The `fixtures.json` object."""
    var root: String
    """The resolved fixture folder."""

    def __init__(out self, var tree: JsonTree, manifest: Int, var root: String):
        """Keep a generated set.

        Args:
            tree: The values.
            manifest: The `fixtures.json` object.
            root: The resolved fixture folder.
        """
        self.tree = tree^
        self.manifest = manifest
        self.root = root^


def generate(
    root: String,
    count: Int = 16,
    alignment: Int = 4,
    datasets: List[String] = dataset_names(),
) raises -> Fixtures:
    """Write a new fixture folder and its `fixtures.json`.

    Args:
        root: The folder. It can exist, but must not hold `fixtures.json`.
        count: The number of images in each dataset, at least one.
        alignment: The worker count that large jobs align to, at least two.
        datasets: The dataset names to write.

    Returns:
        The manifest and the resolved folder.

    Raises:
        Error: If an argument is out of range, the folder already holds a
            fixture set, or a file cannot be written.
    """
    if count < 1 or alignment < 2:
        raise Error("count must be positive; alignment must be at least two")
    var folder = resolve_path(root)
    makedirs(folder, exist_ok=True)
    if exists(folder + "/fixtures.json"):
        raise Error(
            "Use a new fixture directory; do not overwrite recorded inputs"
        )
    var tree = JsonTree()
    var manifest = tree.object()
    var version = zlib_version()
    tree.set(manifest, "schema", tree.integer(1))
    tree.set(manifest, "generator_sha256", tree.string(generator_sha256()))
    tree.set(manifest, "zlib_version", tree.string(version))
    tree.set(manifest, "zlib_runtime_version", tree.string(version))
    tree.set(
        manifest,
        "png",
        tree.string("RGBA8, opaque, filter zero, zlib level six"),
    )
    var records = tree.array()
    for name in datasets:
        tree.append(records, generate_one(tree, folder, name, count, alignment))
    tree.set(manifest, "datasets", records)
    write_json(tree, manifest, folder + "/fixtures.json")
    return Fixtures(tree^, manifest, folder^)


def _usage() -> String:
    """Return the usage line."""
    return (
        "usage: image_decode_fixture [-h] [--count COUNT] [--alignment"
        " ALIGNMENT]\n                            [--datasets"
        " {uniform_tiny,uniform_medium,stride_skew,batch_boundary}"
        " [...]]\n                            destination"
    )


def _fail(message: String):
    """Print a usage error and exit with status two, as `argparse` does."""
    print(_usage(), file=stderr)
    print("image_decode_fixture: error: " + message, file=stderr)
    exit(2)


def _integer(name: String, text: String) -> Int:
    """Return an integer option, or exit with a usage error."""
    try:
        return Int(text)
    except:
        _fail("argument " + name + ": invalid int value: '" + text + "'")
        return 0


def main() raises:
    """Write the fixtures and print a summary without the file lists.

    Raises:
        Error: If the fixtures cannot be written.
    """
    var given = argv()
    var destination = String()
    var have_destination = False
    var count = 16
    var alignment = 4
    var datasets = dataset_names()
    var i = 1
    while i < len(given):
        var word = String(given[i])
        var value = String()
        var has_value = False
        if word.startswith("--") and "=" in word:
            var at = word.find("=")
            value = String(word[byte = at + 1 :])
            var name = String(word[byte=:at])
            word = name
            has_value = True
        if word == "-h" or word == "--help":
            print(_usage())
            print()
            print("Create deterministic, offline image-loading fixtures.")
            exit(0)
        if word == "--count" or word == "--alignment":
            if not has_value:
                i += 1
                if i >= len(given):
                    _fail("argument " + word + ": expected one argument")
                value = String(given[i])
            if word == "--count":
                count = _integer(word, value)
            else:
                alignment = _integer(word, value)
        elif word == "--datasets":
            datasets = List[String]()
            if has_value:
                datasets.append(value)
            while i + 1 < len(given) and not String(given[i + 1]).startswith(
                "-"
            ):
                i += 1
                datasets.append(String(given[i]))
            if len(datasets) == 0:
                _fail("argument --datasets: expected at least one argument")
            for name in datasets:
                if not name in dataset_names():
                    _fail(
                        "argument --datasets: invalid choice: '"
                        + name
                        + "' (choose from uniform_tiny, uniform_medium,"
                        " stride_skew, batch_boundary)"
                    )
        elif word.startswith("-") and word != "-":
            _fail("unrecognized arguments: " + word)
        elif have_destination:
            _fail("unrecognized arguments: " + word)
        else:
            destination = word
            have_destination = True
        i += 1
    if not have_destination:
        _fail("the following arguments are required: destination")
    var result = generate(destination, count, alignment, datasets)
    var manifest = result.manifest
    ref tree = result.tree
    var summary = tree.object()
    tree.set(summary, "fixtures", tree.string(resolve_path(destination)))
    var records = tree.array()
    var all = tree.get(manifest, "datasets")
    for index in range(tree.length(all)):
        var data = tree.at(all, index)
        var copy = tree.object()
        for key in tree.keys(data):
            if key != "files":
                tree.set(copy, key, tree.get(data, key))
        tree.append(records, copy)
    tree.set(summary, "datasets", records)
    print(tree.dumps(summary, 2, False, ",", ": "))
