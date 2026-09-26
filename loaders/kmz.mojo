# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Zipped KML models, from three.js `examples/jsm/loaders/KMZLoader.js`.

A KMZ file is a ZIP archive that holds a Collada model. `parse_kmz` finds
the model as three.js does and reads it with `load_collada`.

**Which model.** When the archive has a `doc.kml`, the model is the file
that its first `href` inside a `Link`, inside a `Model`, inside a
`Placemark` names, three.js's `querySelector( 'Placemark Model Link href'
)`. An element matches by its local name, so a prefix does not matter.
With no `doc.kml`, the model is the first file whose extension is `dae`,
in any case. The files are walked in JavaScript key order, and the last
file of a name is the one read, as fflate's `unzipSync` keeps it.

**Images.** An image is the first file of the archive whose name ends
with the image's path, as three.js's URL modifier finds it. An image
that no name ends with is read from the directory given, as three.js
loads the URL it was given.

**Nothing to read.** A `doc.kml` that names no model, or an archive with
no `doc.kml` and no `.dae`, gives an empty node, as three.js gives an
empty `Group`.

**What is refused.** A `doc.kml` that names a file that is not in the
archive, which three.js throws on. A `doc.kml` or a model that is not
UTF-8 or not XML, which three.js decodes with replacement characters or
parses to an error document. And everything `unzip` and `load_collada`
refuse.
"""

from core.assets import Assets
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from loaders.collada import ColladaModel, load_collada
from loaders.three_mf import js_key_order
from loaders.xml import NO_ELEMENT, XmlDocument, parse_xml
from loaders.zip import ZipEntry, unzip
from std.pathlib import Path


def _local(name: String) -> String:
    """Return an element name less its prefix, the name a CSS type
    selector matches.

    Args:
        name: The qualified name.

    Returns:
        The part after the last `:`.
    """
    return String(name[byte = name.rfind(":") + 1 :])


def _above(document: XmlDocument, element: Int, name: String) raises -> Int:
    """Return the nearest ancestor of an element with a local name.

    Args:
        document: The document.
        element: Where to start, which is not itself looked at.
        name: The local name.

    Returns:
        The ancestor, or `NO_ELEMENT`.
    """
    var at = document.parent(element)
    while at != NO_ELEMENT:
        if _local(document.name(at)) == name:
            return at
        at = document.parent(at)
    return NO_ELEMENT


def kml_model_path(kml: String) raises -> Optional[String]:
    """Return the model a `doc.kml` names, three.js's
    `xml.querySelector( 'Placemark Model Link href' ).textContent`.

    Args:
        kml: The document.

    Returns:
        The text of the first matching `href`, or none.

    Raises:
        Error: If the text is not XML.
    """
    var document = parse_xml(kml)
    # Elements are held in document order.
    for element in range(document.count()):  # pragma: no branch
        if _local(document.name(element)) != "href":
            continue
        var link = _above(document, element, "Link")
        if link == NO_ELEMENT:
            continue
        var model = _above(document, link, "Model")
        if model == NO_ELEMENT:
            continue
        if _above(document, model, "Placemark") != NO_ELEMENT:
            return document.text_content(element)
    return None


def _file(entries: List[ZipEntry], name: String) -> Optional[List[UInt8]]:
    """Return the last file of a name, as fflate's object keeps it.

    Args:
        entries: The archive.
        name: The file's name.

    Returns:
        Its bytes, or none.
    """
    var found: Optional[List[UInt8]] = None
    for entry in entries:
        if entry.name == name:
            found = entry.data.copy()
    return found^


def _text(bytes: List[UInt8], name: String) raises -> String:
    """Return a file as UTF-8 text, fflate's `strFromU8`.

    Args:
        bytes: The file.
        name: Its name, for the message.

    Returns:
        The text.

    Raises:
        Error: If the bytes are not UTF-8.
    """
    try:
        return String(from_utf8=Span(bytes))
    except:
        raise Error("KMZ: " + name + " is not UTF-8 text")


def parse_kmz(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    directory: String = "",
) raises -> ColladaModel:
    """Read a KMZ file's bytes into a scene, three.js's `KMZLoader.parse`.

    Args:
        bytes: The whole file.
        scene: The scene to add the nodes to.
        assets: Where the geometries, materials and textures go.
        directory: Where an image that is not in the archive is read
            from, ending in a slash, or empty for the working directory.

    Returns:
        What the model put where, or an empty node when there is no
        model.

    Raises:
        Error: For anything the module docstring lists.
    """
    var entries = unzip(bytes)
    var names = List[String]()
    for entry in entries:
        if entry.name not in names:
            names.append(entry.name)
    var order = js_key_order(names)
    var kml = _file(entries, "doc.kml")
    if Bool(kml):
        var path = kml_model_path(_text(kml.value(), "doc.kml"))
        if Bool(path):
            var model = _file(entries, path.value())
            if not Bool(model):
                raise Error(
                    "KMZ: doc.kml names " + path.value() + ", which is not here"
                )
            return load_collada(
                _text(model.value(), path.value()),
                directory,
                scene,
                assets,
                entries,
            )
    else:
        for name in order:
            var extension = String(name[byte = name.rfind(".") + 1 :]).lower()
            if extension == "dae":
                return load_collada(
                    _text(_file(entries, name).value(), name),
                    directory,
                    scene,
                    assets,
                    entries,
                )
    var empty = ColladaModel()
    empty.root = scene.attach(Object3D(), NO_PARENT)
    return empty^


def read_kmz(
    path: String, mut scene: Scene, mut assets: Assets
) raises -> ColladaModel:
    """Read a KMZ file into a scene. An image that is not in the archive
    is read from the file's own directory.

    Args:
        path: The file.
        scene: The scene to add the nodes to.
        assets: Where the geometries, materials and textures go.

    Returns:
        What `parse_kmz` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_kmz`
            refuses.
    """
    var directory = String(path[byte = 0 : path.rfind("/") + 1])
    return parse_kmz(Path(path).read_bytes(), scene, assets, directory)
