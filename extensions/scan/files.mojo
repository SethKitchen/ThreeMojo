# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scan files of any splat format, read into one `ScanScene`.

`read_scan` reads a file of any format that ThreeMojo reads, and
`parse_scan` reads the bytes of one. `scan_format` tells the formats apart
by their first bytes, and by the name where a format has no mark:

| Format | Mark | Reader |
|---|---|---|
| `SCAN_SOG` | `PK` and 3, 4: a ZIP file | `extensions.scan.sog.parse_sog_bundle` |
| `SCAN_SOG_FOLDER` | a name that ends in `meta.json` | `extensions.scan.sog.read_sog` |
| `SCAN_COMPRESSED_PLY` | `ply`, and `packed_position` in its header | `extensions.scan.compressed_ply` |
| `SCAN_PLY` | `ply` | `loaders.gaussian_splat_ply` |
| `SCAN_SPZ` | gzip's 31, 139, or `NGSP` | `loaders.spz` |
| `SCAN_KSPLAT` | a name that ends in `.ksplat` | `loaders.ksplat` |
| `SCAN_SPLAT` | a name that ends in `.splat` | `loaders.splat` |

**Axes.** Every format but SPZ holds the axes of the 3D Gaussian Splatting
training code: x to the right, y down and z forward, as COLMAP gives them.
SPZ holds x to the right, y up and z back, as three.js does.
`ScanFormat.y_down` says which, so a viewer can turn a scan upright.

A SOG folder needs the images beside its `meta.json`, so only `read_scan`
reads one. A file with no mark and no name that tells is refused.
"""

from core.ordinal import ordinal_label, ordinal_valid
from extensions.scan.compressed_ply import (
    is_compressed_ply,
    parse_compressed_ply,
)
from extensions.scan.scene import SPLAT_DEFAULT, ScanScene
from extensions.scan.sog import parse_sog_bundle, read_sog
from loaders.gaussian_splat_ply import parse_gaussian_splat_ply
from loaders.ksplat import parse_ksplat
from loaders.splat import parse_splat
from loaders.spz import parse_spz
from std.pathlib import Path


@fieldwise_init
struct ScanFormat(Equatable, ImplicitlyCopyable, Writable):
    """Which splat format a scan file holds."""

    var value: Int
    """The stored ordinal."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the 7 formats.

        Returns:
            Whether the value is 0 to 6.
        """
        return ordinal_valid(self.value, 7 - 1)

    def name(self) -> String:
        """Return the format's name.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = [
            "sog",
            "sog-folder",
            "compressed-ply",
            "ply",
            "spz",
            "ksplat",
            "splat",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")

    def y_down(self) -> Bool:
        """Return whether the format holds y down, as the training code does.

        Returns:
            True for every valid format but `SCAN_SPZ`.
        """
        return self.is_valid() and self != SCAN_SPZ


comptime SCAN_SOG = ScanFormat(0)
"""A SOG bundle: a ZIP file of `meta.json` and its images."""
comptime SCAN_SOG_FOLDER = ScanFormat(1)
"""A SOG `meta.json` file, with its images beside it."""
comptime SCAN_COMPRESSED_PLY = ScanFormat(2)
"""A compressed PLY file, as SuperSplat writes it."""
comptime SCAN_PLY = ScanFormat(3)
"""A splat PLY file, as the training code writes it."""
comptime SCAN_SPZ = ScanFormat(4)
"""A `.spz` file, Niantic's compressed splats."""
comptime SCAN_KSPLAT = ScanFormat(5)
"""A `.ksplat` file, GaussianSplats3D's format."""
comptime SCAN_SPLAT = ScanFormat(6)
"""A `.splat` file, 32 bytes a splat."""


def _starts(bytes: List[UInt8], mark: List[UInt8]) -> Bool:
    """Return whether bytes start with a mark.

    Args:
        bytes: The file.
        mark: The first bytes to look for.

    Returns:
        Whether the file is at least as long, and starts with them.
    """
    if len(bytes) < len(mark):
        return False
    # Every mark has a byte or more: the loop always runs.
    for index in range(len(mark)):  # pragma: no branch
        if bytes[index] != mark[index]:
            return False
    return True


def scan_format(name: String, bytes: List[UInt8]) raises -> ScanFormat:
    """Return the format of a scan file.

    Args:
        name: The file's name or path, or empty when there is none.
        bytes: The file's first bytes: the whole file for a PLY file,
            whose header tells a compressed file apart.

    Returns:
        The format; see the module docstring. The marks come before the
        names.

    Raises:
        Error: If neither the bytes nor the name tell the format.
    """
    if _starts(bytes, [0x50, 0x4B, 0x03, 0x04]):
        return SCAN_SOG
    if _starts(bytes, [0x70, 0x6C, 0x79]):
        if is_compressed_ply(bytes):
            return SCAN_COMPRESSED_PLY
        return SCAN_PLY
    if _starts(bytes, [0x1F, 0x8B]) or _starts(bytes, [0x4E, 0x47, 0x53, 0x50]):
        return SCAN_SPZ
    if name.endswith("meta.json"):
        return SCAN_SOG_FOLDER
    if name.endswith(".ksplat"):
        return SCAN_KSPLAT
    if name.endswith(".splat"):
        return SCAN_SPLAT
    raise Error(
        "Scan: the format of '"
        + name
        + "' is not known: it is not SOG, PLY, SPZ, KSPLAT or SPLAT"
    )


def parse_scan(bytes: List[UInt8], format: ScanFormat) raises -> ScanScene:
    """Read the bytes of a scan file of a format.

    Args:
        bytes: The whole file.
        format: Its format, from `scan_format`.

    Returns:
        The splats, and the model that the file names. A format with no
        model gives `SPLAT_DEFAULT`.

    Raises:
        Error: If the format is not valid or is `SCAN_SOG_FOLDER`, or
            anything that the format's reader raises.
    """
    if format == SCAN_SOG:
        return parse_sog_bundle(bytes)
    if format == SCAN_COMPRESSED_PLY:
        return parse_compressed_ply(bytes)
    if format == SCAN_PLY:
        return ScanScene(parse_gaussian_splat_ply(bytes), SPLAT_DEFAULT)
    if format == SCAN_SPZ:
        return ScanScene(parse_spz(bytes), SPLAT_DEFAULT)
    if format == SCAN_KSPLAT:
        return ScanScene(parse_ksplat(bytes), SPLAT_DEFAULT)
    if format == SCAN_SPLAT:
        return ScanScene(parse_splat(bytes), SPLAT_DEFAULT)
    if format == SCAN_SOG_FOLDER:
        raise Error(
            "Scan: a SOG folder needs the images beside its meta.json; read"
            " it with read_scan"
        )
    raise Error("Scan: a scan format is 0 to 6, not " + String(format.value))


def read_scan(path: String) raises -> ScanScene:
    """Read a scan file of any format.

    Args:
        path: The file. A path that ends in `meta.json` is a SOG folder.

    Returns:
        The splats, and their model; see `parse_scan`.

    Raises:
        Error: If the file cannot be read, its format is not known, or
            anything that its reader raises.
    """
    if path.endswith("meta.json"):
        return read_sog(path)
    var bytes = Path(path).read_bytes()
    return parse_scan(bytes, scan_format(path, bytes))
