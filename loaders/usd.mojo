# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""USD scenes: USDA text, USDC crates and USDZ archives, from three.js
r186's `examples/jsm/loaders/USDLoader.js` and `USDZLoader.js`, which is
its old name.

`read_usd` reads a file as three.js's `load` does, and `parse_usd` reads
its bytes as `parse` reads a buffer:

- A file that starts with `PXR-USDC` is a crate, which
  `loaders.usdc_parser` reads.
- A file that starts with `PK` is a USDZ archive. Its first file is the
  stage, a `.usda`, `.usdc` or `.usd` layer. Each layer of the archive is
  parsed, and each PNG, JPEG and AVIF image is kept, for the stage's
  references and textures to find.
- Any other file is USDA text, which `loaders.usda_parser` reads.

`parse_usda` reads a string as three.js's `parse` reads one. Then
`loaders.usd_composer` builds the layer into the scene.

**The folder.** `read_usd` finds a texture that is not in an archive on
the disk, beside the file, as three.js finds it beside the URL. A string
and bytes have no folder unless one is given, so their textures are
found only in their archive.

**What is refused.** What three.js throws on: an archive whose first
file is not a USD layer, and anything the parsers and the composer
refuse. A file that cannot be read is refused too.
"""

from core.assets import Assets
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from loaders.usd_composer import (
    USD_IMAGE,
    USD_LAYER,
    UsdAssets,
    UsdModel,
    compose_usd,
)
from loaders.usd_specs import UsdLayer
from loaders.usda_parser import parse_usda_layer
from loaders.usdc_parser import is_crate, parse_usdc
from loaders.zip import unzip
from std.pathlib import Path


def lowercase_extension(name: String) -> String:
    """Return three.js's `getLowercaseExtension`.

    Args:
        name: A file's name.

    Returns:
        What follows its last `.`, in lower case, or the empty string when
        it has no `.` after its last `/`.
    """
    var dot = name.rfind(".")
    if dot < 0 or name.rfind("/") > dot:
        return ""
    return String(name[byte = dot + 1 :]).lower()


def decode_text(bytes: List[UInt8]) -> String:
    """Return bytes as a `TextDecoder` decodes them: UTF-8, a byte order
    mark dropped, and a replacement for each byte that is not UTF-8.

    Args:
        bytes: The bytes.

    Returns:
        The text.
    """
    var start = 0
    var marked = (
        len(bytes) >= 3
        and bytes[0] == 0xEF
        and bytes[1] == 0xBB
        and bytes[2] == 0xBF
    )
    if marked:
        start = 3
    var rest = List[UInt8](capacity=len(bytes) - start)
    for k in range(start, len(bytes)):
        rest.append(bytes[k])
    return String(from_utf8_lossy=Span(rest))


def _layer(bytes: List[UInt8]) raises -> UsdLayer:
    """Parse a layer: a crate, or USDA text.

    Args:
        bytes: The layer's file.

    Returns:
        The layer.

    Raises:
        Error: If the parser refuses it.
    """
    if is_crate(bytes):
        return parse_usdc(bytes.copy())
    return parse_usda_layer(decode_text(bytes))


def parse_usda(
    text: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
    path: String = "",
) raises -> UsdModel:
    """Read USDA text into a scene, three.js's `USDLoader.parse` of a
    string.

    Args:
        text: The text.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.
        path: The folder textures are found in, or the empty string.

    Returns:
        What was added.

    Raises:
        Error: For anything the parser and the composer refuse.
    """
    return compose_usd(
        parse_usda_layer(text), UsdAssets(), path, scene, assets, parent
    )


def _archive(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
) raises -> UsdModel:
    """Read a USDZ archive into a scene, three.js's USDZ case of
    `parse`.

    Args:
        bytes: The archive.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under.

    Returns:
        What was added.

    Raises:
        Error: If the archive cannot be unzipped, its first file is not a
            USD layer, or a layer is refused.
    """
    var files = UsdAssets()
    var zip = UsdAssets()
    # fflate keeps the last file of a name, in the first one's place, as
    # `add` does.
    for entry in unzip(bytes):
        zip.add(entry.name, USD_IMAGE, entry.data.copy(), UsdLayer())
    for k in zip.order():
        var name = zip.names[k]
        var ext = lowercase_extension(name)
        var image = (
            ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "avif"
        )
        if image:
            files.add(name, USD_IMAGE, zip.images[k].copy(), UsdLayer())
        elif ext == "usd" or ext == "usda" or ext == "usdc":
            files.add(name, USD_LAYER, List[UInt8](), _layer(zip.images[k]))
    var order = zip.order()
    var first = zip.names[order[0]] if len(order) > 0 else String("")
    var ext = lowercase_extension(first)
    var stage = ext == "usda" or ext == "usd" or ext == "usdc"
    if not stage:
        raise Error(
            "USD: invalid USDZ package: the first file must be a USD layer"
            " (.usd, .usda or .usdc)"
        )
    var slash = first.rfind("/")
    var base = String(first[byte=:slash]) if slash >= 0 else String("")
    var root = files.layers[files.find(first)].copy()
    return compose_usd(root^, files, base, scene, assets, parent)


def parse_usd(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
    path: String = "",
) raises -> UsdModel:
    """Read a USD file's bytes into a scene, three.js's `USDLoader.parse`
    of a buffer.

    Args:
        bytes: The file: a USDC crate, a USDZ archive or USDA text.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.
        path: The folder a crate's or a text's textures are found in, or
            the empty string. An archive's are found in the archive.

    Returns:
        What was added.

    Raises:
        Error: For anything the module docstring lists.
    """
    if is_crate(bytes):
        return compose_usd(
            parse_usdc(bytes.copy()), UsdAssets(), path, scene, assets, parent
        )
    if len(bytes) >= 2 and bytes[0] == 0x50 and bytes[1] == 0x4B:
        return _archive(bytes, scene, assets, parent)
    return compose_usd(
        parse_usda_layer(decode_text(bytes)),
        UsdAssets(),
        path,
        scene,
        assets,
        parent,
    )


def url_base(url: String) -> String:
    """Return three.js's `LoaderUtils.extractUrlBase`.

    Args:
        url: A file's path.

    Returns:
        Its folder with the last `/`, or `./` when it has none.
    """
    var slash = url.rfind("/")
    if slash < 0:
        return "./"
    return String(url[byte = : slash + 1])


def read_usd(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Read a USD file into a scene, three.js's `USDLoader.load`: its bytes,
    with its folder for the textures it names.

    Args:
        path: The file: `.usd`, `.usda`, `.usdc` or `.usdz`.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What was added.

    Raises:
        Error: If the file cannot be read, and for anything `parse_usd`
            refuses.
    """
    return parse_usd(
        Path(path).read_bytes(), scene, assets, parent, url_base(path)
    )


def read_usdz(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Read a USD file into a scene, three.js's `USDZLoader.load`: the old
    name of `USDLoader`, which reads every kind of USD file.

    Args:
        path: The file.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What `read_usd` gives.

    Raises:
        Error: For anything `read_usd` refuses.
    """
    return read_usd(path, scene, assets, parent)
