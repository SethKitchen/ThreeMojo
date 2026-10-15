# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Zip each CARLA package for upload, and write its sha256 and members.

From the repository root, with `CARLA_EXPORT_DIR` set to the work folder:

    sh tools/tool.sh .venv/bin/mojo carla_export_zip_packages
    sh tools/tool.sh .venv/bin/mojo carla_export_zip_packages --packages town_packages --index towns.json

The first writes the vehicles. Each writes `upload/<id>.zip` for each
package in the packages folder, and an index in `upload/` with each zip's
sha256, its size and the members to extract.

It replaces `assets/carla/tools/export/zip_packages.py`. For the same
folders it writes the same zip bytes as Python's `zipfile` on Linux or
macOS, the same index text and the same summary line. A member is deflated
by the system zlib. The work folder is `CARLA_EXPORT_DIR`, or the working
directory, which `tools/tool.sh` makes the repository root.
"""

from std.os import getenv, listdir
from std.os.path import realpath
from std.sys import argv, exit, stderr

from tools._carla_assets import dumps_indent, sha256_bytes
from tools._carla_files import (
    exception_line,
    make_dirs,
    os_error,
    path_is_dir,
    path_is_link,
    py_abspath,
    py_join,
    py_relpath,
    read_file,
    write_file,
    write_text,
)
from tools._carla_zip import DosTime, ZipMember, python_zip
from tools._cli import parse_command_line
from tools._python_json import PyJson, sorted_order
from tools._python_stats import format_fixed

comptime PROGRAM = "carla_export_zip_packages"
"""The program name in usage and error texts."""
comptime USAGE = (
    "usage: carla_export_zip_packages [-h] [--packages PACKAGES] [--index"
    " INDEX]\n"
)
"""The usage text."""
comptime HELP = (
    "\noptions:\n  -h, --help           show this help message and exit\n "
    " --packages PACKAGES\n  --index INDEX\n"
)
"""The help after the usage."""
comptime DATE = DosTime(2025, 9, 16, 0, 0, 0)
"""A fixed date, so the same package zips to the same sum."""


def sorted_names(names: List[String]) -> List[String]:
    """Return names in Python's `sorted` order.

    Args:
        names: The names.

    Returns:
        The names sorted by code point.
    """
    var out = List[String]()
    for index in sorted_order(names):
        out.append(names[index])
    return out^


def _list(path: String) raises -> List[String]:
    """Return `os.listdir(path)`, with Python's error."""
    if not path_is_dir(path):
        try:
            _ = read_file(path)
        except error:
            raise error^
        raise os_error(20, path)
    var out = List[String]()
    for name in listdir(path):
        out.append(String(name))
    return out^


def walk(top: String) raises -> List[Tuple[String, List[String]]]:
    """Return `sorted(os.walk(top))` as each folder and its files.

    A folder's links to folders are listed with its folders and are not
    entered. Every other entry is a file, a dangling link included. An
    unreadable folder is skipped, as `os.walk` skips it.

    Args:
        top: The folder.

    Returns:
        Each folder path and the names of its files, sorted by path.

    Raises:
        Error: Never for a readable tree.
    """
    var found = List[Tuple[String, List[String]]]()
    var pending: List[String] = [top]
    while len(pending) > 0:
        var folder = pending.pop()
        var names: List[String]
        try:
            names = _list(folder)
        except:
            continue
        var files = List[String]()
        for name in names:
            var full = py_join(folder, name)
            if path_is_dir(full):
                if not path_is_link(full):
                    pending.append(full)
            else:
                files.append(name)
        found.append((folder, files^))
    var paths = List[String]()
    for item in found:
        paths.append(item[0])
    var out = List[Tuple[String, List[String]]]()
    for index in sorted_order(paths):
        out.append((found[index][0], found[index][1].copy()))
    return out^


def zip_packages(
    base: String, packages: String, index_name: String, cwd: String
) raises -> String:
    """Zip every package and write the index, as the Python script does.

    Args:
        base: The work folder, absolute.
        packages: The packages folder, relative to the work folder.
        index_name: The index file's name in `upload/`.
        cwd: The working directory.

    Returns:
        The summary line, with its newline.

    Raises:
        Error: Python's error text: an `OSError` from the folders, or a
            `ValueError` when there is no package.
    """
    var upload = py_join(base, "upload")
    var folder_root = py_join(base, packages)
    make_dirs(upload)
    var doc = PyJson()
    var index = doc.new_dict()
    doc.root = index
    var total = 0
    var largest = -1
    for vehicle_id in sorted_names(_list(folder_root)):
        var folder = py_join(folder_root, vehicle_id)
        if not path_is_dir(folder):
            continue
        var target = py_join(upload, vehicle_id + ".zip")
        var members = List[ZipMember]()
        var names = doc.new_list()
        try:
            for item in walk(folder):
                for name in sorted_names(item[1]):
                    var full = py_join(item[0], name)
                    var relative = py_relpath(full, folder, cwd).replace(
                        "\\", "/"
                    )
                    members.append(ZipMember(relative, read_file(full)))
                    doc.append(names, doc.new_str(relative))
        except error:
            # `ZipFile.close` still writes the members before the failure.
            write_file(
                target, Span(python_zip(members, materialize[DATE](), True))
            )
            raise error^
        var data = python_zip(members, materialize[DATE](), True)
        write_file(target, Span(data))
        var record = doc.new_dict()
        doc.set(record, "zip", doc.new_str(vehicle_id + ".zip"))
        doc.set(record, "sha256", doc.new_str(sha256_bytes(Span(data))))
        doc.set(record, "bytes", doc.new_int(len(data)))
        doc.set(record, "members", names)
        doc.set(index, vehicle_id, record)
        total += len(data)
        largest = max(largest, len(data))
    write_text(py_join(upload, index_name), dumps_indent(doc, index, 1))
    if largest < 0:
        raise Error("ValueError: max() iterable argument is empty")
    return (
        String(doc.length(index))
        + " zips, "
        + format_fixed(Float64(total) / 1e6, 1)
        + " MB, largest "
        + format_fixed(Float64(largest) / 1e6, 1)
        + " MB\n"
    )


def main() raises:
    """Zip the packages of the work folder.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_command_line(
        arguments,
        PROGRAM,
        USAGE,
        HELP,
        List[String](),
        ["--packages", "--index"],
    )
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var cwd = realpath(".")
    var base = py_abspath(getenv("CARLA_EXPORT_DIR", "."), cwd)
    try:
        print(
            zip_packages(
                base,
                command.value("--packages", "packages"),
                command.value("--index", "index.json"),
                cwd,
            ),
            end="",
        )
    except error:
        print(exception_line(error), file=stderr)
        exit(1)
