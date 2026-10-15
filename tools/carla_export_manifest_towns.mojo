# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the town packages' entries and bindings into the manifest.

Reads `upload/towns.json`, which `carla_export_zip_packages --packages
town_packages --index towns.json` writes, and replaces every
`carla.town.*` entry. Each entry is one archive: the zip, its sum, and
the members it extracts. Its URL comes from `--urls`, or stays the one
the manifest has when the zip's sum is unchanged, or is null until the
zip is hosted. Each town's binding is `town.<Town>`, the name
`TownSettings.package` takes.

    sh tools/tool.sh .venv/bin/mojo carla_export_manifest_towns [--urls URLS.json]

URLS.json maps a zip name, such as `carla.town.town02.zip`, to its URL.

It replaces `assets/carla/tools/export/manifest_towns.py`, with the same
command line, manifest, texts and exit statuses. The work folder is
`CARLA_EXPORT_DIR`, or the working directory, which `tools/tool.sh` makes
the repository root.
"""

from std.os import getenv
from std.os.path import realpath
from std.sys import argv, exit, stderr

from tools._carla_assets import default_manifest
from tools._carla_files import py_abspath, py_join
from tools._carla_manifests import export_error_line, update_towns
from tools._cli import parse_command_line

comptime PROGRAM = "carla_export_manifest_towns"
"""The program name in usage and error texts."""
comptime USAGE = (
    "usage: carla_export_manifest_towns [-h] [--manifest MANIFEST] [--index"
    " INDEX]\n                                   [--urls URLS]\n"
)
"""The usage text."""
comptime HELP = """
Write the town packages' entries and bindings into the manifest.

Reads `upload/towns.json`, which `carla_export_zip_packages --packages
town_packages --index towns.json` writes, and replaces every
`carla.town.*` entry. Each entry is one archive: the zip, its sum, and
the members it extracts. Its URL comes from `--urls`, or stays the one
the manifest has when the zip's sum is unchanged, or is null until the
zip is hosted. Each town's binding is `town.<Town>`, the name
`TownSettings.package` takes.

    sh tools/tool.sh .venv/bin/mojo carla_export_manifest_towns [--urls URLS.json]

URLS.json maps a zip name, such as `carla.town.town02.zip`, to its URL.

options:
  -h, --help           show this help message and exit
  --manifest MANIFEST
  --index INDEX
  --urls URLS
"""
"""The help after the usage."""


def main() raises:
    """Rewrite the manifest's towns.

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
        ["--manifest", "--index", "--urls"],
    )
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var base = py_abspath(getenv("CARLA_EXPORT_DIR", "."), realpath("."))
    var default_index = py_join(py_join(base, "upload"), "towns.json")
    try:
        print(
            update_towns(
                command.value("--manifest", default_manifest()),
                command.value("--index", default_index),
                command.value("--urls", ""),
            ),
            end="",
        )
    except error:
        var line = export_error_line(error)
        if line.startswith("SystemExit: "):
            var message = String(line[byte=12:])
            line = message^
        print(line, file=stderr)
        exit(1)
