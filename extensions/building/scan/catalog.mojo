# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The catalog of scanned buildings: the manifest that
`tools/building_scans.mojo` downloads, as typed entries.

Each entry of `assets/building_scans/manifest.json` gives a scan's
credit, the construction kit and the space use that `fit_building` gives
it, and the frame that puts it in meters with z up. `ScanCatalog.open`
reads them, and refuses an entry whose kit, use or frame
`extensions.building` and `extensions.scan` would refuse.

A scan's files are in the cache under its id: `.cache/building-scans/`,
the id, and `meta.json` beside its images. `scene` gives that path when
the text is there. The catalog does not check the files' sums; the tool's
`verify` does.
"""

from extensions.building.kinds import SpaceUse
from extensions.building.kits import KitKind, kit_kind
from extensions.scan.frame import (
    ScanFrame,
    scale_source,
    scan_axis,
)
from generators.utils import Vec3d
from loaders.json import JsonDocument, NO_NODE, parse_json
from std.os.path import isfile
from std.pathlib import Path
from units.si import Angle64, Length64, METER, RADIAN

comptime CATALOG_CACHE = ".cache/building-scans/"
"""The cache that the tool fills, from the repository root."""
comptime CATALOG_MANIFEST = "assets/building_scans/manifest.json"
"""The manifest, from the repository root."""


def space_use(name: String) raises -> SpaceUse:
    """Return the space use that a name gives.

    Args:
        name: A use's name, such as `living`.

    Returns:
        The use.

    Raises:
        Error: If no use has the name.
    """
    for value in range(12):
        if SpaceUse(value).name() == name:
            return SpaceUse(value)
    raise Error("Scan catalog: '" + name + "' is not a space use")


@fieldwise_init
struct ScanEntry(Copyable, Movable):
    """One scanned building of the catalog."""

    var id: String
    """The id, which is also its folder in the cache."""
    var title: String
    """The scene's title."""
    var author: String
    """Who made the scan."""
    var license: String
    """`CC-BY-4.0` or `CC0-1.0`."""
    var source: String
    """The scene's page."""
    var kit: KitKind
    """The construction kit that a fitted model is made of."""
    var use: SpaceUse
    """What a fitted model's spaces are used for."""
    var frame: ScanFrame
    """How the scan's coordinates map to the building's."""


def _string(document: JsonDocument, node: Int, key: String) raises -> String:
    """Return a string that an entry must have.

    Args:
        document: The manifest.
        node: The entry.
        key: The key.

    Returns:
        The string.

    Raises:
        Error: If the key is missing or is not a string.
    """
    return document.string(
        document.required(node, key, "Scan catalog: an entry has no " + key)
    )


def _frame(document: JsonDocument, entry: Int) raises -> ScanFrame:
    """Return an entry's frame, checked.

    Args:
        document: The manifest.
        entry: The entry.

    Returns:
        The frame, with no heading and the scan origin.

    Raises:
        Error: If the frame is missing, or an axis, the unit or the scale
            is refused.
    """
    var node = document.required(
        entry, "frame", "Scan catalog: an entry has no frame"
    )
    var frame = ScanFrame(
        scan_axis(_string(document, node, "up")),
        scan_axis(_string(document, node, "north")),
        Length64(
            document.number(
                document.required(
                    node, "unit_m", "Scan catalog: a frame has no unit_m"
                )
            ),
            METER,
        ),
        scale_source(_string(document, node, "scale")),
        Angle64(0, RADIAN),
        Vec3d(0, 0, 0),
    )
    frame.check()
    return frame


struct ScanCatalog(Movable):
    """The scanned buildings of a manifest, and the cache that holds
    their files."""

    var entries: List[ScanEntry]
    """The entries, in the manifest's order."""
    var cache: String
    """The cache folder, ending in `/`."""

    def __init__(out self, var entries: List[ScanEntry], cache: String):
        """Hold a catalog.

        Args:
            entries: The entries.
            cache: The cache folder. A `/` is added when it has none.
        """
        self.entries = entries^
        self.cache = cache
        if not cache.endswith("/"):
            self.cache += "/"

    @staticmethod
    def parse(text: String, cache: String) raises -> ScanCatalog:
        """Read a manifest's text.

        Args:
            text: The manifest.
            cache: The cache folder.

        Returns:
            The catalog.

        Raises:
            Error: If the text is not JSON, has no entries, or an entry is
                refused; see the module docstring.
        """
        var document = parse_json(text)
        var list = document.required(
            document.root(),
            "entries",
            "Scan catalog: the manifest has no entries",
        )
        var entries = List[ScanEntry]()
        for index in range(document.length(list)):
            var entry = document.at(list, index)
            entries.append(
                ScanEntry(
                    _string(document, entry, "id"),
                    _string(document, entry, "title"),
                    _string(document, entry, "author"),
                    _string(document, entry, "license"),
                    _string(document, entry, "source"),
                    kit_kind(_string(document, entry, "kit")),
                    space_use(_string(document, entry, "use")),
                    _frame(document, entry),
                )
            )
        return ScanCatalog(entries^, cache)

    @staticmethod
    def open(manifest: String, cache: String) raises -> ScanCatalog:
        """Read a manifest file.

        Args:
            manifest: The manifest's path.
            cache: The cache folder.

        Returns:
            The catalog.

        Raises:
            Error: If the file cannot be read, or anything `parse` raises.
        """
        return ScanCatalog.parse(Path(manifest).read_text(), cache)

    def find(self, id: String) raises -> ScanEntry:
        """Return the entry with an id.

        Args:
            id: The id.

        Returns:
            The entry.

        Raises:
            Error: If no entry has the id.
        """
        for entry in self.entries:
            if entry.id == id:
                return entry.copy()
        raise Error("Scan catalog: no scan '" + id + "'")

    def scene(self, id: String) raises -> Optional[String]:
        """Return the path of a scan's `meta.json`, when it is cached.

        Args:
            id: The scan's id.

        Returns:
            The path, or nothing when the file is not in the cache.

        Raises:
            Error: If no entry has the id.
        """
        _ = self.find(id)
        var path = self.cache + id + "/meta.json"
        if isfile(path):
            return path
        return None
