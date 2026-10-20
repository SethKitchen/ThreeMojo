# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fetch, verify and credit the scanned buildings.

The scans are too large to keep in git: 15 MB to over 1 GB each. The
manifest, `assets/building_scans/manifest.json`, names each one: its
SuperSplat scene, its author, its CC BY 4.0 or CC0 license, the
construction kit and the frame that `extensions.building.scan` reads it
with, and its files with their URLs and SHA-256 sums. This tool downloads
the files into a cache that git ignores, `.cache/building-scans/`, and
checks each sum, as `tools/carla_assets.mojo` does for the CARLA town.

Commands, from the repository root:

    sh tools/tool.sh .venv/bin/mojo building_scans check
    sh tools/tool.sh .venv/bin/mojo building_scans status
    sh tools/tool.sh .venv/bin/mojo building_scans fetch [ID ...] [--pin | --offline]
    sh tools/tool.sh .venv/bin/mojo building_scans verify [ID ...] [--strict]
    sh tools/tool.sh .venv/bin/mojo building_scans credits [--all]

`--manifest PATH` and `--cache PATH` come before the command.

Rules the fetch keeps:

- An entry with no files is resolved only with `--pin`: the tool reads
  its scene page, finds the scene's `meta.json`, and adds the text and
  each image it names as files with no sum. The pinning fetch then
  downloads them and writes their sums into the manifest.
- A file is written to the cache only after its sum matches, and a
  verified file is never overwritten. A cached file whose sum does not
  match is reported and left alone.
- A file with no sum is not fetched without `--pin`.
- A file whose URL is null is not hosted; put it at its cache path by
  hand, for example after the Download button of its scene page, and the
  next fetch verifies it.
- With `--offline`, fetch uses only pinned files already in the cache, and
  fails for anything else.

The exit status is 0 on success, 1 after an error, and 2 for a command
line that is not understood.
"""

from std.sys import argv, exit, stderr

from tools._building_scans import (
    credits,
    default_cache,
    default_manifest,
    is_cached,
    load_scan_manifest,
    resolve,
    save_scan_manifest,
    scene_path,
)
from tools._carla_assets import (
    Report,
    Transport,
    entries_of,
    fetch,
    selected_entries,
    verify,
)

comptime USAGE = (
    "usage: building_scans [-h] [--manifest MANIFEST] [--cache CACHE]"
    " {check,status,fetch,verify,credits} [ID ...] [--pin] [--offline]"
    " [--strict] [--all]\n"
)
"""The first line of the help and of a usage error."""
comptime HELP = """
Fetch, verify and credit the scanned buildings.

commands:
  check     check the manifest's rules
  status    say which scans are cached
  fetch     download and verify the files of ID, or of every scan
  verify    hash the cached files of ID, or of every scan
  credits   print the attribution of the cached scans

options:
  -h, --help           show this help and exit
  --manifest MANIFEST  the manifest (assets/building_scans/manifest.json)
  --cache CACHE        the cache (.cache/building-scans)
  --pin                resolve unresolved scans and record new sums
  --offline            use only pinned files already in the cache
  --strict             verify fails for missing and unpinned files too
  --all                credit every scan, cached or not
"""
"""The help after the usage line."""
comptime COMMANDS: List[String] = [
    "check",
    "status",
    "fetch",
    "verify",
    "credits",
]
"""The commands."""
comptime FLAGS: List[String] = ["--pin", "--offline", "--strict", "--all"]
"""The flags, which any command takes and only some use."""


struct Arguments(Movable):
    """The parsed command line, or the text to print and the status."""

    var status: Int
    """0 to run, -1 after `--help`, or 2 for a usage error."""
    var message: String
    """The help or error text."""
    var command: String
    """The command."""
    var ids: List[String]
    """The entry ids after the command."""
    var flags: List[String]
    """The flags given."""
    var manifest: String
    """The manifest path, or empty for the default."""
    var cache: String
    """The cache path, or empty for the default."""

    def __init__(out self):
        """Make an empty command line."""
        self.status = 0
        self.message = String()
        self.command = String()
        self.ids = List[String]()
        self.flags = List[String]()
        self.manifest = String()
        self.cache = String()

    def has(self, flag: String) -> Bool:
        """Return whether a flag was given.

        Args:
            flag: The flag, such as `--pin`.

        Returns:
            Whether it was.
        """
        for given in self.flags:
            if given == flag:
                return True
        return False


def _usage_error(var arguments: Arguments, problem: String) -> Arguments:
    """Return the arguments with a usage error."""
    arguments.status = 2
    arguments.message = USAGE + "building_scans: error: " + problem + "\n"
    return arguments^


def parse_arguments(words: List[String]) -> Arguments:
    """Parse the command line, without the program name.

    Args:
        words: The arguments.

    Returns:
        The parsed command line. A nonzero status carries the text to
        print.
    """
    var out = Arguments()
    var index = 0
    while index < len(words):
        var word = words[index]
        index += 1
        if word == "-h" or word == "--help":
            out.status = -1
            out.message = USAGE + HELP
            return out^
        if word == "--manifest" or word == "--cache":
            if index >= len(words):
                return _usage_error(
                    out^, "argument " + word + ": expected one argument"
                )
            if word == "--manifest":
                out.manifest = words[index]
            else:
                out.cache = words[index]
            index += 1
            continue
        if word.startswith("-"):
            var known = False
            for flag in materialize[FLAGS]():
                if flag == word:
                    known = True
            if not known:
                return _usage_error(out^, "unrecognized arguments: " + word)
            out.flags.append(word)
            continue
        if out.command == "":
            var known = False
            for command in materialize[COMMANDS]():
                if command == word:
                    known = True
            if not known:
                return _usage_error(
                    out^, "argument command: invalid choice: '" + word + "'"
                )
            out.command = word
        else:
            out.ids.append(word)
    if out.command == "":
        return _usage_error(
            out^, "the following arguments are required: command"
        )
    if out.has("--pin") and out.has("--offline"):
        return _usage_error(out^, "--pin and --offline cannot be used together")
    return out^


struct Outcome(Movable):
    """What a run prints and its exit status."""

    var status: Int
    """The exit status."""
    var output: String
    """The standard output."""
    var errors: String
    """The standard error."""

    def __init__(out self, status: Int, var output: String, var errors: String):
        """Make an outcome.

        Args:
            status: The exit status.
            output: The standard output.
            errors: The standard error.
        """
        self.status = status
        self.output = output^
        self.errors = errors^


def _report_lines(reports: List[Report]) -> String:
    """Return one line for each file: its status and its path."""
    var text = String()
    for report in reports:
        text += report.status + "  " + report.path + "\n"
    return text^


def run(words: List[String], transport: Transport) -> Outcome:
    """Run the tool; see the module docstring.

    Args:
        words: The arguments, without the program name.
        transport: How downloads run.

    Returns:
        What to print and the exit status.
    """
    var arguments = parse_arguments(words)
    if arguments.status == -1:
        return Outcome(0, arguments.message, "")
    if arguments.status != 0:
        return Outcome(arguments.status, "", arguments.message)
    try:
        var manifest_path = arguments.manifest
        if manifest_path == "":
            manifest_path = default_manifest()
        var cache = arguments.cache
        if cache == "":
            cache = default_cache()
        var doc = load_scan_manifest(manifest_path)
        var root = doc.root
        if arguments.command == "check":
            return Outcome(
                0,
                "manifest ok: "
                + String(len(entries_of(doc, root)))
                + " entries\n",
                "",
            )
        if arguments.command == "status":
            var text = String()
            for entry in entries_of(doc, root):
                var name = doc.text(doc.get(entry, "id"))
                if is_cached(doc, entry, cache):
                    text += (
                        name
                        + "  cached  "
                        + scene_path(doc, entry, cache)
                        + "\n"
                    )
                elif doc.length(doc.get(entry, "files")) == 0:
                    text += (
                        name
                        + "  unresolved (fetch --pin reads its scene page)\n"
                    )
                else:
                    text += name + "  missing\n"
            return Outcome(0, text^, "")
        if arguments.command == "credits":
            return Outcome(
                0, credits(doc, root, cache, arguments.has("--all")), ""
            )
        if arguments.command == "verify":
            var reports = List[Report]()
            for entry in selected_entries(doc, root, arguments.ids):
                if doc.length(doc.get(entry, "files")) == 0:
                    var name = doc.text(doc.get(entry, "id"))
                    reports.append(Report(name, name + "/", "unresolved"))
            reports.extend(verify(doc, root, cache, arguments.ids))
            var failed = False
            for report in reports:
                if report.status == "mismatch":
                    failed = True
                if arguments.has("--strict") and report.status != "ok":
                    failed = True
            return Outcome(1 if failed else 0, _report_lines(reports), "")
        # fetch
        var pin = arguments.has("--pin")
        var offline = arguments.has("--offline")
        var unresolved = List[Report]()
        var changed = False
        for entry in selected_entries(doc, root, arguments.ids):
            if doc.length(doc.get(entry, "files")) > 0:
                continue
            if not pin:
                var name = doc.text(doc.get(entry, "id"))
                unresolved.append(Report(name, name + "/", "unresolved"))
                continue
            _ = resolve(doc, entry, cache, transport)
            changed = True
        var reports = fetch(
            doc, root, cache, arguments.ids, pin, offline, transport
        )
        var failed = len(unresolved) > 0 and offline
        for report in reports:
            if report.status == "pinned":
                changed = True
            if report.status == "mismatch":
                failed = True
            if offline and report.status != "kept":
                failed = True
        if changed:
            save_scan_manifest(doc, root, manifest_path)
        unresolved.extend(reports^)
        return Outcome(1 if failed else 0, _report_lines(unresolved), "")
    except error:
        return Outcome(1, "", String(error) + "\n")


def main() raises:
    """Run the tool with the process's arguments and exit with its status."""
    var words = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        words.append(String(given[index]))
    var outcome = run(words, Transport())
    if outcome.output:
        print(outcome.output, end="")
    if outcome.errors:
        print(outcome.errors, end="", file=stderr)
    exit(outcome.status)
