# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check that production code does not consume the containing model.

The objective-model module may name its own helpers. Every other production
module must not. Lane refinement must not restore the removed search names.
A comment or a string does not count.
"""

from std.os import listdir
from std.os.path import isdir, islink
from std.pathlib import Path

from tests._python_tokens import _tokenize

from tools._model_mentions import framed_texts, model_mentions
from tools._optional_runtime_messages import optional_runtime_messages
from tools._python_json import PyJson
from tools._watched_model_names import watched_model_names


comptime _NAME = 1
comptime _HELPER = "extensions/carla/curve_objective_model.mojo"
comptime _LANE = "extensions/carla/lane_refinement.mojo"


def _fail(message: String) raises:
    """Raise an optional-runtime consumer error.

    Args:
        message: The failure text.

    Raises:
        Error: A production module names a reviewed helper.
    """
    raise Error("optional runtime contract: " + message)


def _skipped_root(name: String) -> Bool:
    """Return whether `name` is outside the production scan.

    Args:
        name: One top-level directory or file name.

    Returns:
        True for a hidden name or a non-production tree.
    """
    if name.startswith("."):
        return True
    if name == "tests" or name == "examples" or name == "bench":
        return True
    if name == "tools" or name == "docs" or name == "assets":
        return True
    if name == "out" or name == "coverage" or name == "cache":
        return True
    if name == "build" or name == "node_modules":
        return True
    return False


def _hidden(relative: String) -> Bool:
    """Return whether any path part is hidden.

    Args:
        relative: A path relative to the repository root.

    Returns:
        True when a part starts with `.`.
    """
    var rest = relative
    while rest.byte_length() > 0:
        var slash = rest.find("/")
        var part = rest
        if slash >= 0:
            part = String(rest[byte=0:slash])
            var tail = String(rest[byte = slash + 1 :])
            rest = tail
        else:
            rest = ""
        if part.startswith("."):
            return True
    return False


def _model(name: String) -> Bool:
    """Return whether `name` is an objective-model helper.

    Args:
        name: One executable name.

    Returns:
        True for a reviewed model name.
    """
    if name == "curve_objective_model" or name == "_ObjectiveModel":
        return True
    if name == "_try_objective_model" or name == "_restrict_objective_model":
        return True
    if name == "_objective_followup_room":
        return True
    return name == "_objective_recheck_room"


def _removed(name: String) -> Bool:
    """Return whether `name` is removed search state.

    Args:
        name: One executable name.

    Returns:
        True for a removed lane-search name.
    """
    if name == "cached_model" or name == "reused_domain":
        return True
    if name == "reused_delta" or name == "reused_lower":
        return True
    if name == "reused_tolerance" or name == "reused_center_s":
        return True
    if name == "reused_center_work" or name == "reused_center":
        return True
    if name == "ideal_center" or name == "reused_support":
        return True
    if name == "needs_model":
        return True
    return name == "packed_model"


def _mentioned(text: String) -> Bool:
    """Return whether `text` can contain a reviewed name.

    Args:
        text: One module.

    Returns:
        True when a reviewed spelling occurs anywhere in the text.
    """
    if text.find("curve_objective_model") >= 0:
        return True
    if (
        text.find("_ObjectiveModel") >= 0
        or text.find("_try_objective_model") >= 0
    ):
        return True
    if text.find("_restrict_objective_model") >= 0:
        return True
    if text.find("_objective_followup_room") >= 0:
        return True
    if text.find("_objective_recheck_room") >= 0:
        return True
    if text.find("cached_model") >= 0 or text.find("reused_domain") >= 0:
        return True
    if text.find("reused_delta") >= 0 or text.find("reused_lower") >= 0:
        return True
    if text.find("reused_tolerance") >= 0 or text.find("reused_center_s") >= 0:
        return True
    if text.find("reused_center_work") >= 0 or text.find("reused_center") >= 0:
        return True
    if text.find("ideal_center") >= 0 or text.find("reused_support") >= 0:
        return True
    if text.find("needs_model") >= 0:
        return True
    return text.find("packed_model") >= 0


def _sorted(var items: List[String]) -> List[String]:
    """Sort paths by code point.

    Args:
        items: The paths, consumed by this call.

    Returns:
        The same paths, in order.
    """
    for i in range(1, len(items)):
        var j = i
        while j > 0 and items[j] < items[j - 1]:
            items.swap_elements(j, j - 1)
            j -= 1
    return items^


def _collect(root: String, relative: String, mut paths: List[String]) raises:
    """Append production `.mojo` paths below `relative`.

    Args:
        root: The repository root.
        relative: The directory to read, relative to `root`.
        paths: The collected paths, appended by this call.

    Raises:
        Error: A directory cannot be read.
    """
    var full = root if relative == "" else root + "/" + relative
    var names = listdir(full)
    for name in names:
        var child = full + "/" + name
        var path = name if relative == "" else relative + "/" + name
        if isdir(child):
            if islink(child):
                continue
            if name.startswith("."):
                continue
            if relative == "" and _skipped_root(name):
                continue
            _collect(root, path, paths)
        elif path.endswith(".mojo") and not _hidden(path):
            if relative != "" or not _skipped_root(name):
                paths.append(path)


def _executable(text: String, mut model: Bool, mut removed: Bool) raises:
    """Record reviewed names that occur as executable tokens.

    Args:
        text: One module.
        model: Set when an objective-model name occurs.
        removed: Set when a removed search name occurs.

    Raises:
        Error: The module cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(text, kinds, texts)
    var index = 0
    while index < len(kinds):
        if kinds[index] == _NAME:
            var token = texts[index]
            if _model(token):
                model = True
            if _removed(token):
                removed = True
        index += 1


def _check_text(path: String, text: String) raises:
    """Require one observed module to keep the reviewed names out.

    Args:
        path: The module path relative to the repository root.
        text: The observed source.

    Raises:
        Error: The module names the model or restores search state.
    """
    if not _mentioned(text):
        return
    var model = False
    var removed = False
    _executable(text, model, removed)
    if path != _HELPER and model:
        _fail(
            "containing-objective model production consumer reintroduced: "
            + path
        )
    if path == _LANE and removed:
        _fail("containing-objective model search state reintroduced")


def _models_changed() raises:
    """Raise the model-name set failure.

    Raises:
        Error: The framed texts and the path list disagree.
    """
    var messages = PyJson.parse(optional_runtime_messages())
    raise Error(messages.text(messages.at(messages.root, "models")))


def mentioned_consumers(
    framed: String, paths_json: String, expected: Int
) raises:
    """Read the watched names, then check the texts that mention one.

    Args:
        framed: Length lines followed by the exact UTF-8 bytes of each text.
        paths_json: A JSON list of module paths, one per framed text.
        expected: The number of texts the caller framed.

    Raises:
        Error: A length line is invalid, the flag count differs from
            `expected`, or a mentioned module names a reviewed helper.
            The watched names are read before the texts.
    """
    var names = watched_model_names()
    var flags_text = model_mentions(names, framed)
    var flags = PyJson.parse(flags_text)
    if flags.length(flags.root) != expected:
        _models_changed()
    var paths = PyJson.parse(paths_json)
    if paths.length(paths.root) != expected:
        _models_changed()
    var texts = framed_texts(framed)
    var index = 0
    while index < expected:
        if flags.flag(flags.item(flags.root, index)):
            _check_text(paths.text(paths.item(paths.root, index)), texts[index])
        index += 1


def require_observed_consumers(payload: String) raises:
    """Require observed modules to keep the reviewed names out.

    Args:
        payload: A JSON list of `path` and `text` objects, in scan order.

    Raises:
        Error: A module names the model or restores search state.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        _check_text(
            doc.text(doc.at(item, "path")), doc.text(doc.at(item, "text"))
        )
        index += 1


def containing_model_consumers(root: String) raises:
    """Require the reviewed production absence.

    Args:
        root: The repository root.

    Raises:
        Error: A production module names the model or restores search state.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var paths = List[String]()
    _collect(base, "", paths)
    var ordered = _sorted(paths^)
    var index = 0
    while index < len(ordered):
        var path = ordered[index]
        var text = Path(base + "/" + path).read_text()
        _check_text(path, text)
        index += 1
