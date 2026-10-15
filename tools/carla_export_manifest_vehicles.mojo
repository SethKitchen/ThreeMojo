# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the exported CARLA vehicles into the asset manifest.

`carla_export_zip_packages` writes `upload/index.json`: each vehicle's zip,
its sum, its size and its members. This tool makes one model entry per
vehicle, with the zip as its archive, and binds each blueprint id to its
entry. A vehicle keeps its URL from the manifest, or takes one from
`--urls`, or has a null URL until its zip is hosted.

    sh tools/tool.sh .venv/bin/mojo carla_export_manifest_vehicles [--urls URLS.json]

URLS.json maps a zip name, such as `vehicle.audi.a2.zip`, to its URL. A
Google Drive share link is fine: the fetch tool turns it into a download.

It replaces `assets/carla/tools/export/manifest_vehicles.py`, with the same
command line, manifest, texts and exit statuses. The work folder is
`CARLA_EXPORT_DIR`, or the working directory, which `tools/tool.sh` makes
the repository root.
"""

from std.os import getenv
from std.os.path import realpath
from std.sys import argv, exit, stderr

from tools._carla_assets import default_manifest
from tools._carla_files import py_abspath, py_join
from tools._carla_manifests import export_error_line, update_vehicles
from tools._cli import parse_command_line

comptime PROGRAM = "carla_export_manifest_vehicles"
"""The program name in usage and error texts."""
comptime USAGE = (
    "usage: carla_export_manifest_vehicles [-h] [--manifest MANIFEST]\n"
    "                                      [--index INDEX] [--urls URLS]\n"
)
"""The usage text."""
comptime HELP = """
Write the exported CARLA vehicles into the asset manifest.

`carla_export_zip_packages` writes `upload/index.json`: each vehicle's zip,
its sum, its size and its members. This tool makes one model entry per
vehicle, with the zip as its archive, and binds each blueprint id to its
entry. A vehicle keeps its URL from the manifest, or takes one from
`--urls`, or has a null URL until its zip is hosted.

    sh tools/tool.sh .venv/bin/mojo carla_export_manifest_vehicles [--urls URLS.json]

URLS.json maps a zip name, such as `vehicle.audi.a2.zip`, to its URL. A
Google Drive share link is fine: the fetch tool turns it into a download.

options:
  -h, --help           show this help message and exit
  --manifest MANIFEST
  --index INDEX
  --urls URLS
"""
"""The help after the usage."""


def main() raises:
    """Rewrite the manifest's vehicles.

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
    var default_index = py_join(py_join(base, "upload"), "index.json")
    try:
        print(
            update_vehicles(
                command.value("--manifest", default_manifest()),
                command.value("--index", default_index),
                command.value("--urls", ""),
            ),
            end="",
        )
    except error:
        print(export_error_line(error), file=stderr)
        exit(1)
