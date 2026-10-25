# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The splats of a scan, and which kind of Gaussian they are.

Every scan reader of `extensions.scan` gives a `ScanScene`: the splats as
a `GaussianSplatGeometry`, and the `SplatModel` that the file names. A SOG
text names it in `model`. A PLY header names it in a comment:
`SplatRenderMode: default`, `mip` or `2dgs`, as Brush writes it, or
`antialiased 0` or `1`, as Postshot writes it. A file that names none
holds 3D Gaussians, `SPLAT_DEFAULT`.

ThreeMojo draws every model as a 3D Gaussian. The model is kept so that a
caller can tell an antialiased or a 2D Gaussian scene apart.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from core.ordinal import ordinal_label, ordinal_valid


@fieldwise_init
struct SplatModel(Equatable, ImplicitlyCopyable, Writable):
    """Which kind of Gaussian a scan says it holds."""

    var value: Int
    """The stored ordinal."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 models.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 3 - 1)

    def name(self) -> String:
        """Return the model's name, as a SOG `meta.json` writes it.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["default", "antialiased", "2dgs"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


comptime SPLAT_DEFAULT = SplatModel(0)
"""A 3D Gaussian, as the 3DGS training code makes it. A file that names no model holds these."""
comptime SPLAT_ANTIALIASED = SplatModel(1)
"""A 3D Gaussian trained with a screen-space filter, as Mip-Splatting does."""
comptime SPLAT_2DGS = SplatModel(2)
"""A flat 2D Gaussian, as 2DGS makes it."""


def splat_model(name: String) raises -> SplatModel:
    """Return the model that a SOG `meta.json` name gives.

    Args:
        name: The text's `model` value.

    Returns:
        The model.

    Raises:
        Error: If the name is not `default`, `antialiased` or `2dgs`.
    """
    for value in range(3):
        if SplatModel(value).name() == name:
            return SplatModel(value)
    raise Error("Scan: unknown splat model '" + name + "'")


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is ASCII white space, as JavaScript trims it.

    Args:
        byte: The byte.

    Returns:
        True for a space, a tab, a line feed, a vertical tab, a form feed
        or a carriage return.
    """
    return byte == 32 or (byte >= 9 and byte <= 13)


def _lower(byte: UInt8) -> UInt8:
    """Return an ASCII letter in lower case, and any other byte as it is.

    Args:
        byte: The byte.

    Returns:
        The byte, lower case.
    """
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def _is(text: Span[UInt8, _], start: Int, end: Int, word: StaticString) -> Bool:
    """Return whether bytes are a word, in any case.

    Args:
        text: The bytes.
        start: The first byte.
        end: One past the last byte.
        word: The word, lower case.

    Returns:
        Whether the bytes and the word are the same, ignoring case.
    """
    var letters = word.as_bytes()
    if end - start != len(letters):
        return False
    # Every word has a byte or more: the loop always runs.
    for k in range(len(letters)):  # pragma: no branch
        if _lower(text[start + k]) != letters[k]:
            return False
    return True


def splat_model_of_comment(
    model: SplatModel, comment: Span[UInt8, _]
) -> SplatModel:
    """Return the model after one PLY header comment, as splat-transform
    3.10.1's `splatModelFromComments` reads it.

    The match ignores case and the white space around the comment and its
    value.

    Args:
        model: The model the comments before it name.
        comment: The comment, without its leading `comment `.

    Returns:
        The model it names, or `model` when it names none.
    """
    var start = 0
    var end = len(comment)
    while start < end and _is_space(comment[start]):
        start += 1
    while end > start and _is_space(comment[end - 1]):
        end -= 1
    var mode = 17
    if end - start >= mode and _is(
        comment, start, start + mode, "splatrendermode: "
    ):
        # The key ends in a space and the trimmed comment does not, so a
        # byte that is not a space comes before the end.
        var at = start + mode
        while _is_space(comment[at]):
            at += 1
        if _is(comment, at, end, "default"):
            return SPLAT_DEFAULT
        if _is(comment, at, end, "mip"):
            return SPLAT_ANTIALIASED
        if _is(comment, at, end, "2dgs"):
            return SPLAT_2DGS
        return model
    var flag = 12
    if end - start >= flag and _is(
        comment, start, start + flag, "antialiased "
    ):
        var at = start + flag
        while _is_space(comment[at]):
            at += 1
        if _is(comment, at, end, "1"):
            return SPLAT_ANTIALIASED
        if _is(comment, at, end, "0"):
            return SPLAT_DEFAULT
    return model


def splat_model_from_comments(comments: List[String]) -> SplatModel:
    """Return the model that a PLY header's comments name, as
    splat-transform 3.10.1's `splatModelFromComments` reads them.

    The last comment that names a model wins. Other comments are skipped;
    see `splat_model_of_comment`.

    Args:
        comments: The comments, without their leading `comment `.

    Returns:
        `SPLAT_DEFAULT`, or the model the last naming comment gives.
    """
    var model = SPLAT_DEFAULT
    for comment in comments:
        model = splat_model_of_comment(model, comment.as_bytes())
    return model


struct ScanScene(Movable):
    """The splats of a scan, and the model that its file names."""

    var geometry: GaussianSplatGeometry
    """The splats, in the file's order."""
    var model: SplatModel
    """Which kind of Gaussian the splats are."""

    def __init__(
        out self, var geometry: GaussianSplatGeometry, model: SplatModel
    ):
        """Hold a scan's splats.

        Args:
            geometry: The splats.
            model: Their model.
        """
        self.geometry = geometry^
        self.model = model
