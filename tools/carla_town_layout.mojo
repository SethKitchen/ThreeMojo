# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Dump each CARLA town layout from a running server.

    carla_town_layout [--root DIR] [--limit SECONDS] [--lua FILE]
        [--client PROGRAM] [TOWN ...]

The program installs the UE4SS layout mod, starts CARLA with `-nullrhi`,
and stops the server after `SECONDS`, 60 by default. The client loads
the town and writes the request. A town name that ends in `_Opt` is
stored without that suffix.
"""

from std.ffi import c_int, external_call
from std.os import getenv, makedirs, remove
from std.os.path import join
from std.pathlib import Path, cwd
from std.sys import argv, exit, stderr
from std.time import perf_counter, sleep

from tools._owned_process import (
    SIGKILL,
    SignalHold,
    spawn,
    try_wait,
    wait_blocking,
)
from tools._process import run_program, shell_quote


def dump_layouts(
    root: String,
    lua: String,
    client: List[String],
    towns: List[String],
    limit: Float64,
) raises:
    """Install the mod and dump each town.

    Args:
        root: The export directory. The server is
            `release/CarlaUE4/Binaries/Win64`.
        lua: The mod source, `layout_dump/main.lua`.
        client: The program that loads the town. The tool appends
            `--town`, `--request`, `--target`, and `--seconds`.
        towns: The town names. An empty list uses the six default towns.
        limit: The most seconds one server may run.

    Raises:
        Error: If UE4SS is absent, the mod cannot be copied, or the
            server cannot start.
    """
    if not limit > 0:
        raise Error("limit is not positive")
    var binaries = join(root, "release/CarlaUE4/Binaries/Win64")
    _install(binaries, lua)
    var chosen = List[String]()
    if len(towns) == 0:
        chosen = _default_towns()
    else:
        for index in range(len(towns)):
            chosen.append(towns[index])
    var layout = join(root, "layout")
    makedirs(layout, exist_ok=True)
    for index in range(len(chosen)):
        var note = _dump(binaries, layout, client, chosen[index], limit)
        print(chosen[index] + ": " + note)


def _install(binaries: String, lua: String) raises:
    """Copy the mod and enable only it."""
    if not Path(join(binaries, "ue4ss")).is_dir():
        raise Error("UE4SS is not in " + binaries)
    var scripts = join(binaries, "ue4ss/Mods/LayoutDump/Scripts")
    makedirs(scripts, exist_ok=True)
    var source = Path(lua).read_bytes()
    Path(join(scripts, "main.lua")).write_bytes(Span(source))
    var mods = join(binaries, "ue4ss/Mods")
    Path(join(mods, "mods.json")).write_text(
        '[{"mod_name": "LayoutDump", "mod_enabled": true}]\n'
    )
    Path(join(mods, "mods.txt")).write_text("LayoutDump : 1\n")


def _dump(
    binaries: String,
    layout: String,
    client: List[String],
    town: String,
    limit: Float64,
) raises -> String:
    """Run one server and return its result text."""
    var stem = town
    if town.endswith("_Opt"):
        var end = town.byte_length() - 4
        stem = String(town[byte=:end])
    var target = join(layout, stem + ".jsonl")
    var request = join(binaries, "layout_dump_request.txt")
    _remove(target)
    _remove(target + ".done")
    _remove(target + ".progress")
    _remove(request)
    var script = (
        "cd -- "
        + shell_quote(binaries)
        + " && exec "
        + shell_quote(join(binaries, "CarlaUE4-Win64-Shipping.exe"))
        + " CarlaUE4 -nullrhi >/dev/null 2>&1"
    )
    var command = List[String]()
    command.append("sh")
    command.append("-c")
    command.append(script)
    var hold = SignalHold()
    var pid = spawn(command, hold, -1, False)
    var alive = True
    var note: String
    try:
        note = _drive(pid, client, town, request, target, limit, alive)
        var waited = try_wait(pid)
        if waited.done:
            alive = False
    except error:
        if alive:
            _stop(pid)
        raise error
    if alive:
        _stop(pid)
    return note


def _drive(
    pid: Int,
    client: List[String],
    town: String,
    request: String,
    target: String,
    limit: Float64,
    mut alive: Bool,
) raises -> String:
    """Load the town and wait for the mod to finish."""
    var start = perf_counter()
    var arguments = List[String]()
    for index in range(len(client)):
        arguments.append(client[index])
    arguments.append("--town")
    arguments.append(town)
    arguments.append("--request")
    arguments.append(request)
    arguments.append("--target")
    arguments.append(target)
    arguments.append("--seconds")
    arguments.append(String(limit))
    var ran = run_program(arguments, limit + 5, merge_errors=False)
    if ran.timed_out or ran.status != 0:
        return "the server did not answer"
    while perf_counter() - start < limit:
        if Path(target + ".done").exists():
            return String(Path(target + ".done").read_text().strip(" \t\n\r"))
        var waited = try_wait(pid)
        if waited.done:
            alive = False
            return "the server stopped while reading " + _last_line(
                target + ".progress"
            )
        var remain = limit - (perf_counter() - start)
        if remain <= 0:
            break
        var pause = remain
        if pause > 1:
            pause = 1
        sleep(pause)
    if Path(target + ".done").exists():
        return String(Path(target + ".done").read_text().strip(" \t\n\r"))
    return "out of time"


def _stop(pid: Int):
    """Kill one server and reap it, as `Popen.kill` does."""
    _ = external_call["kill", c_int](c_int(pid), c_int(SIGKILL))
    _ = wait_blocking(pid)


def _remove(path: String) raises:
    """Delete `path` when it exists."""
    if Path(path).exists():
        remove(Path(path))


def _last_line(path: String) raises -> String:
    """Return the last line of `path`, or empty text when it is absent."""
    if not Path(path).exists():
        return String("")
    var text = Path(path).read_text()
    var raw = text.as_bytes()
    var end = len(raw)
    while end > 0 and (raw[end - 1] == 10 or raw[end - 1] == 13):
        end -= 1
    var start = end
    while start > 0 and raw[start - 1] != 10:
        start -= 1
    return String(text[byte=start:end])


def _default_towns() -> List[String]:
    """Return the towns the layout dump writes."""
    var towns = List[String]()
    towns.append("Town01")
    towns.append("Town02")
    towns.append("Town03")
    towns.append("Town04")
    towns.append("Town05")
    towns.append("Town10HD_Opt")
    return towns^


def _absolute(path: String) raises -> String:
    """Return a relative path joined to the working directory."""
    if path.startswith("/"):
        return path
    var here = String(cwd())
    if path == "." or path.byte_length() == 0:
        return here
    return join(here, path)


def _drive_cli(arguments: List[String]) raises:
    """Read the dump options and dump the named towns."""
    var root = String()
    var lua = String("assets/carla/tools/export/layout_dump/main.lua")
    var client = List[String]()
    client.append("python3")
    client.append("assets/carla/tools/export/layout_client.py")
    var limit = Float64(60)
    var towns = List[String]()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--root"
            or word == "--limit"
            or word == "--lua"
            or word == "--client"
        ):
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            var value = arguments[index + 1]
            if word == "--root":
                root = value
            elif word == "--lua":
                lua = value
            elif word == "--client":
                client = List[String]()
                client.append(value)
            else:
                limit = _number(value)
            index += 2
            continue
        if word.startswith("--"):
            raise Error("unknown argument " + word)
        towns.append(word)
        index += 1
    if root.byte_length() == 0:
        root = getenv("CARLA_EXPORT_DIR", ".")
    dump_layouts(_absolute(root), lua, client, towns, limit)


def _number(text: String) raises -> Float64:
    """Return a positive time limit."""
    var value = Float64(0)
    var raw = text.as_bytes()
    var seen = False
    var point = False
    var scale = Float64(1)
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 46 and not point:
            point = True
            continue
        if byte < 48 or byte > 57:
            raise Error("limit is not a number")
        seen = True
        if point:
            scale /= 10
            value += Float64(Int(byte - 48)) * scale
        else:
            value = value * 10 + Float64(Int(byte - 48))
    if not seen:
        raise Error("limit is not a number")
    return value


def main() raises:
    """Dump the towns named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    var copied = List[String]()
    for index in range(1, len(arguments)):
        copied.append(String(arguments[index]))
    try:
        _drive_cli(copied)
    except error:
        print("carla_town_layout:", error, file=stderr)
        exit(1)
