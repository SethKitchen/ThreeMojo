# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Enforce public docstrings, negative-fixture coverage, and package layering.

    sh tools/tool.sh .venv/bin/mojo check_repository_contracts

`make repository-check` and `make docstrings` run this verifier. It checks
three repository-wide invariants without compiling the library:

1. Every public `struct`, `trait`, top-level `def`, and public `struct`
   method in `LIB_DIRS` has a docstring (`\"\"\"...\"\"\"`).
2. Every public single-integer wrapper `struct` with `def is_valid(` in a
   non-GPU library module is covered by `tests/compile_fail/` and
   `tools/compile_fail_expectations.json`.
3. Core three.js port directories do not import `extensions.*` outside the
   `window/` C ABI host adapters, and `extensions/*` domains respect the
   declared domain layering graph.
"""

from std.collections import Set
from std.os import listdir
from std.os.path import dirname, isdir
from std.pathlib import Path
from std.reflection import source_location
from std.sys import exit, stderr

from tools._imports import imported_names
from tools._text import split_lines

comptime LIB_DIRS = [
    "math",
    "render",
    "units",
    "cameras",
    "core",
    "geometries",
    "helpers",
    "objects",
    "renderers",
    "materials",
    "lights",
    "loaders",
    "animation",
    "postprocessing",
    "controls",
    "window",
    "exporters",
    "environments",
    "generators",
    "extensions",
]
"""The library directories audited by repository contracts."""

comptime ALLOWED_WINDOW_ADAPTERS = [
    "window/capi_gamepad.mojo",
    "window/capi_water_gpu.mojo",
    "window/splat_app.mojo",
    "window/village_app.mojo",
    "window/water_app.mojo",
]
"""Host C ABI adapter modules in `window/` permitted to wrap an extension."""

comptime ALLOWED_EXTENSION_EDGES = [
    "animals:anatomy",
    "animals:physics",
    "animals:sdf",
    "attire:anatomy",
    "attire:humanoid",
    "building:energy",
    "building:scan",
    "building:structure",
    "building:topology",
    "carla:physics",
    "carla:visual",
    "castle:building",
    "castle:geotech",
    "castle:numerics",
    "castle:scan",
    "castle:structure",
    "castle:visual",
    "castle:water",
    "cfd:numerics",
    "chemistry:numerics",
    "chemistry:visual",
    "clinical:imaging",
    "clinical:numerics",
    "design:building",
    "design:geotech",
    "design:structure",
    "energy:building",
    "energy:numerics",
    "fem:imaging",
    "fem:numerics",
    "fem:sdf",
    "hydraulics:numerics",
    "humanoid:anatomy",
    "imaging:humanoid",
    "imaging:numerics",
    "imaging:sdf",
    "molecule:chemistry",
    "molecule:humanoid",
    "molecule:imaging",
    "molecule:numerics",
    "molecule:sdf",
    "scan:physics",
    "structure:building",
    "structure:numerics",
    "village:anatomy",
    "village:animals",
    "village:attire",
    "village:building",
    "village:gamepad",
    "village:humanoid",
    "village:scan",
    "village:topology",
    "village:vegetation",
    "village:water",
    "warp:numerics",
]
"""Allowed `source_domain:target_domain` edges inside `extensions/`."""


def _walk_mojo(
    root: String, relative_dir: String, mut out: List[String]
) raises:
    """Append non-`__init__` `.mojo` files under `root/relative_dir`."""
    var full_dir = root + "/" + relative_dir
    if not isdir(full_dir):
        return
    var names = List[String]()
    for entry in listdir(full_dir):
        names.append(String(entry))
    sort(names)
    for name in names:
        var rel = relative_dir + "/" + name
        var full = root + "/" + rel
        if isdir(full):
            _walk_mojo(root, rel, out)
        elif name.endswith(".mojo") and name != "__init__.mojo":
            out.append(rel)


def _is_ident_char(byte: UInt8) -> Bool:
    """Return whether `byte` is an ASCII identifier byte."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _after_keyword(line: String, prefix: String) -> String:
    """Return the identifier immediately after `prefix`, or empty."""
    if not line.startswith(prefix):
        return String()
    var rest = String(line[byte = prefix.byte_length() :])
    var bytes = rest.as_bytes()
    var end = 0
    while end < len(bytes) and _is_ident_char(bytes[end]):
        end += 1
    if end == 0:
        return String()
    return String(rest[byte=:end])


def _is_gpu_module(path: String) -> Bool:
    """Return whether `path` is a MAX GPU module."""
    var slash = path.rfind("/")
    var name = path if slash < 0 else String(path[byte = slash + 1 :])
    return (
        name == "gpu.mojo"
        or name.startswith("gpu_")
        or name.endswith("_gpu.mojo")
    )


def _snake_case(name: String) -> String:
    """Convert `CamelCase` to `snake_case`."""
    var out = List[UInt8]()
    var bytes = name.as_bytes()
    for index in range(len(bytes)):
        var b = bytes[index]
        if b >= 65 and b <= 90:
            if index > 0:
                out.append(95)
            out.append(b + 32)
        else:
            out.append(b)
    return String(unsafe_from_utf8=out)


def check_file_docstrings(path: String, text: String) -> List[String]:
    """Return missing-docstring diagnostics for public symbols in `text`.

    Args:
        path: Repository-relative file path.
        text: Mojo source text.

    Returns:
        One line per public `struct`, `trait`, `def`, or method without a
        docstring.
    """
    var errors = List[String]()
    var lines = split_lines(text)
    var in_docstring = False
    var in_public_struct = False
    var index = 0
    while index < len(lines):
        var line = lines[index]
        var quotes = line.count('"""')
        if in_docstring:
            if quotes % 2 == 1:
                in_docstring = False
            index += 1
            continue
        if quotes % 2 == 1:
            in_docstring = True
            index += 1
            continue
        var kind = String()
        var symbol = String()
        var s_name = _after_keyword(line, "struct ")
        var t_name = _after_keyword(line, "trait ")
        var d_name = _after_keyword(line, "def ")
        if s_name != "":
            in_public_struct = not s_name.startswith("_")
            if in_public_struct:
                kind = "struct"
                symbol = s_name
        elif t_name != "":
            in_public_struct = False
            if not t_name.startswith("_"):
                kind = "trait"
                symbol = t_name
        elif d_name != "":
            in_public_struct = False
            if not d_name.startswith("_"):
                kind = "def"
                symbol = d_name
        elif line.startswith("comptime "):
            in_public_struct = False
        elif in_public_struct and line.startswith("    def "):
            var m_name = _after_keyword(line, "    def ")
            if m_name != "" and not m_name.startswith("_"):
                kind = "method"
                symbol = m_name
        if symbol != "":
            var header_end = index
            while header_end < len(lines) and not String(
                lines[header_end].strip()
            ).endswith(":"):
                header_end += 1
            var body = header_end + 1
            while body < len(lines):
                var trimmed = String(lines[body].strip())
                if trimmed == "" or trimmed.startswith("#"):
                    body += 1
                else:
                    break
            if body >= len(lines) or not String(lines[body].strip()).startswith(
                '"""'
            ):
                errors.append(
                    path
                    + ":"
                    + String(index + 1)
                    + ": public "
                    + kind
                    + " '"
                    + symbol
                    + "' is missing a docstring"
                )
        index += 1
    return errors^


def _single_int_is_valid_structs(text: String) -> List[String]:
    """Return public single-integer wrapper structs defining `def is_valid(`."""
    var found = List[String]()
    var lines = split_lines(text)
    var in_doc = False
    var current = String()
    var has_is_valid = False
    var field_count = 0
    var int_field = False
    for line in lines:
        var q = line.count('"""')
        if in_doc:
            if q % 2 == 1:
                in_doc = False
            continue
        if q % 2 == 1:
            in_doc = True
            continue
        var s_name = _after_keyword(line, "struct ")
        if s_name != "" or line.startswith("def ") or line.startswith("trait "):
            if (
                current != ""
                and not current.startswith("_")
                and has_is_valid
                and field_count == 1
                and int_field
            ):
                found.append(current)
            current = s_name
            has_is_valid = False
            field_count = 0
            int_field = False
            continue
        if current == "":
            continue
        if line.startswith("    def is_valid("):
            has_is_valid = True
        elif line.startswith("    var "):
            field_count += 1
            var colon = line.find(":")
            if colon >= 0:
                var ty = String(String(line[byte = colon + 1 :]).strip())
                if (
                    ty == "Int"
                    or ty == "Int32"
                    or ty == "UInt8"
                    or ty == "UInt16"
                    or ty == "UInt32"
                ):
                    int_field = True
    if (
        current != ""
        and not current.startswith("_")
        and has_is_valid
        and field_count == 1
        and int_field
    ):
        found.append(current)
    return found^


def check_repository(root: String) raises -> List[String]:
    """Verify public docstrings, `is_valid` negative fixtures, and layering.

    Args:
        root: Repository root directory.

    Returns:
        A list of contract violations; empty when every contract holds.
    """
    var errors = List[String]()
    var allowed_window = Set[String]()
    for item in materialize[ALLOWED_WINDOW_ADAPTERS]():
        allowed_window.add(item)
    var allowed_edges = Set[String]()
    for edge in materialize[ALLOWED_EXTENSION_EDGES]():
        allowed_edges.add(edge)

    var cf_corpus = String()
    var exp_path = root + "/tools/compile_fail_expectations.json"
    if Path(exp_path).is_file():
        cf_corpus += Path(exp_path).read_text() + "\n"
    var cf_dir = root + "/tests/compile_fail"
    if isdir(cf_dir):
        for entry in listdir(cf_dir):
            var name = String(entry)
            if name.endswith(".mojo"):
                cf_corpus += name + "\n"
                cf_corpus += Path(cf_dir + "/" + name).read_text() + "\n"

    var files = List[String]()
    for directory in materialize[LIB_DIRS]():
        _walk_mojo(root, directory, files)

    for rel in files:
        var text = Path(root + "/" + rel).read_text()
        for err in check_file_docstrings(rel, text):
            errors.append(err)

        if not _is_gpu_module(rel):
            for sname in _single_int_is_valid_structs(text):
                var snake = _snake_case(sname)
                if cf_corpus.find(sname) < 0 and cf_corpus.find(snake) < 0:
                    errors.append(
                        rel
                        + ": boundary type '"
                        + sname
                        + "' has no tests/compile_fail/ fixture"
                    )

        var slash = rel.find("/")
        var top = rel if slash < 0 else String(rel[byte=:slash])
        for imp in imported_names(text):
            if not imp.startswith("extensions."):
                continue
            var rest = String(imp[byte=11:])
            var dot = rest.find(".")
            var target_dom = rest if dot < 0 else String(rest[byte=:dot])
            if top != "extensions":
                if rel not in allowed_window:
                    errors.append(
                        rel
                        + ": core module must not import extensions."
                        + target_dom
                    )
            else:
                var after_ext = String(rel[byte=11:])
                var sub_slash = after_ext.find("/")
                if sub_slash > 0:
                    var src_dom = String(after_ext[byte=:sub_slash])
                    if src_dom != target_dom:
                        var key = src_dom + ":" + target_dom
                        if key not in allowed_edges:
                            errors.append(
                                rel
                                + ": forbidden cross-extension import "
                                + src_dom
                                + " -> "
                                + target_dom
                            )
    return errors^


def main() raises:
    """Run all repository contract checks on the working tree."""
    var root = dirname(dirname(String(source_location().file_name())))
    var problems = check_repository(root)
    if len(problems) > 0:
        for item in problems:
            print(item, file=stderr)
        exit(1)
    print(
        "Repository contracts hold: docstrings, compile-fail types and"
        " layering."
    )
