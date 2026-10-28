# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write each CARLA town's environment list.

    carla_town_environment [--root DIR] [--host HOST] [--port N]
        [--client PROGRAM] [TOWN ...]

The client reads the server. This program rounds each position and each
angle to four decimal places and writes `environment/<town>.json`. A
file that is already there is kept.
"""

from std.ffi import external_call
from std.os import getenv, makedirs
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import quote_ascii
from tools._process import run_program
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)
from tools._python_math import round_half_even
from tools.carla_environment_record import record_text


def write_environments(
    root: String,
    host: String,
    port: Int,
    client: List[String],
    towns: List[String],
) raises:
    """Write one JSON file for each town.

    Args:
        root: The export directory. Files go in `environment`.
        host: The CARLA server host.
        port: The CARLA server port.
        client: The program that reads the server. `--list` prints the
            map names. `--town` prints one town's raw objects.
        towns: The town names. An empty list asks the client for the
            maps and sorts them.

    Raises:
        Error: If the client fails or its JSON is not a town record.
    """
    var chosen = List[String]()
    if len(towns) == 0:
        chosen = _sorted(_names(_run(client, host, port, "", True)))
    else:
        for index in range(len(towns)):
            chosen.append(towns[index])
    var folder = _child(root, "environment")
    makedirs(folder, exist_ok=True)
    for index in range(len(chosen)):
        var town = chosen[index]
        var path = _child(folder, town + ".json")
        if Path(path).exists():
            print("kept " + path)
            continue
        var started = _now()
        var raw = PyJson.parse(_run(client, host, port, town, False))
        var count = _write(path, raw)
        var seconds = Int(round_half_even(_now() - started))
        print(
            town
            + ": "
            + String(count)
            + " objects in "
            + String(seconds)
            + " s"
        )


def _write(path: String, raw: PyJson) raises -> Int:
    """Round `raw` and write it with `json.dump(..., indent=0)`."""
    if raw.kind(raw.root) != PY_DICT:
        raise Error("environment dump is not an object")
    var objects = raw.at(raw.root, "objects")
    var count = raw.length(objects)
    var request = String('{"objects":')
    request += _compact(raw, objects)
    request += "}"
    var rounded = PyJson.parse(record_text(request))
    var out = String("{\n")
    out += '"town": ' + quote_ascii(raw.text(raw.at(raw.root, "town"))) + ",\n"
    out += '"map": ' + quote_ascii(raw.text(raw.at(raw.root, "map"))) + ",\n"
    out += (
        '"carla": ' + quote_ascii(raw.text(raw.at(raw.root, "carla"))) + ",\n"
    )
    out += '"objects": ' + _indent0(
        rounded, rounded.at(rounded.root, "objects")
    )
    out += "\n}"
    Path(path).write_text(out)
    return count


def _indent0(doc: PyJson, node: Int) raises -> String:
    """Return `json.dumps(value, indent=0)`."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var count = doc.length(node)
        if count == 0:
            return "{}"
        var out = String("{\n")
        for index in range(count):
            if index > 0:
                out += ",\n"
            out += quote_ascii(doc.key(node, index)) + ": "
            out += _indent0(doc, doc.value(node, index))
        out += "\n}"
        return out
    if kind == PY_LIST:
        var count = doc.length(node)
        if count == 0:
            return "[]"
        var out = String("[\n")
        for index in range(count):
            if index > 0:
                out += ",\n"
            out += _indent0(doc, doc.item(node, index))
        out += "\n]"
        return out
    if kind == PY_STR:
        return quote_ascii(doc.text(node))
    if kind == PY_INT or kind == PY_FLOAT:
        return doc.text(node)
    if kind == PY_BOOL:
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    raise Error("environment value is not JSON")


def _compact(doc: PyJson, node: Int) raises -> String:
    """Return compact JSON, keeping each number's spelling."""
    var kind = doc.kind(node)
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += _compact(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += quote_ascii(doc.key(node, index)) + ":"
            out += _compact(doc, doc.value(node, index))
        out += "}"
        return out
    if kind == PY_STR:
        return quote_ascii(doc.text(node))
    if kind == PY_INT or kind == PY_FLOAT:
        return doc.text(node)
    if kind == PY_BOOL:
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    raise Error("environment value is not JSON")


def _run(
    client: List[String], host: String, port: Int, town: String, listing: Bool
) raises -> String:
    """Return the client's JSON text."""
    var arguments = List[String]()
    for index in range(len(client)):
        arguments.append(client[index])
    arguments.append("--host")
    arguments.append(host)
    arguments.append("--port")
    arguments.append(String(port))
    if listing:
        arguments.append("--list")
    else:
        arguments.append("--town")
        arguments.append(town)
    var ran = run_program(arguments, 180, merge_errors=False)
    if ran.status != 0:
        var message = ran.errors
        if message.byte_length() == 0:
            message = ran.output
        raise Error(message)
    return _trim(ran.output)


def _names(text: String) raises -> List[String]:
    """Return the map names."""
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_LIST:
        raise Error("map names are not a list")
    var names = List[String]()
    for index in range(doc.length(doc.root)):
        var item = doc.item(doc.root, index)
        if doc.kind(item) != PY_STR:
            raise Error("map name is not text")
        names.append(doc.text(item))
    return names^


def _sorted(var names: List[String]) -> List[String]:
    """Return `names` in byte order, as `sorted` does for ASCII."""
    for index in range(1, len(names)):
        var current = names[index]
        var place = index
        while place > 0 and _before(current, names[place - 1]):
            names[place] = names[place - 1]
            place -= 1
        names[place] = current
    return names^


def _before(left: String, right: String) -> Bool:
    """Return whether `left` sorts before `right`."""
    var a = left.as_bytes()
    var b = right.as_bytes()
    var count = len(a)
    if len(b) < count:
        count = len(b)
    for index in range(count):
        if a[index] != b[index]:
            return a[index] < b[index]
    return len(a) < len(b)


def _now() -> Float64:
    """Return seconds from the realtime clock."""
    var now = List[Int64](length=2, fill=0)
    _ = external_call["clock_gettime", Int32](
        Int32(0), now.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    return Float64(Int(now[0])) + Float64(Int(now[1])) / 1000000000.0


def _trim(text: String) -> String:
    """Drop a trailing newline."""
    var raw = text.as_bytes()
    var end = len(raw)
    while end > 0 and (raw[end - 1] == 10 or raw[end - 1] == 13):
        end -= 1
    return String(text[byte=:end])


def _child(root: String, child: String) -> String:
    """Join `child` onto `root` with one slash."""
    var raw = root.as_bytes()
    if len(raw) > 0 and raw[len(raw) - 1] == 47:
        return root + child
    return root + "/" + child


def _absolute(path: String) raises -> String:
    """Return a relative path joined to the working directory."""
    var raw = path.as_bytes()
    if len(raw) > 0 and raw[0] == 47:
        return path
    var pwd = run_program(["pwd"], 5)
    if pwd.status != 0:
        raise Error("cannot read the working directory")
    var cwd = pwd.output
    var length = cwd.byte_length()
    if length > 0 and cwd.as_bytes()[length - 1] == 10:
        var end = length - 1
        var trimmed = String(cwd[byte=:end])
        cwd = trimmed
    if path == "." or path.byte_length() == 0:
        return cwd
    return _child(cwd, path)


def _drive(arguments: List[String]) raises:
    """Read the options and write each town."""
    var root = String()
    var host = String("localhost")
    var port = 2000
    var client = List[String]()
    client.append("python3")
    client.append("assets/carla/tools/export/environment_client.py")
    var towns = List[String]()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--root"
            or word == "--host"
            or word == "--port"
            or word == "--client"
        ):
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            var value = arguments[index + 1]
            if word == "--root":
                root = value
            elif word == "--host":
                host = value
            elif word == "--port":
                port = _port(value)
            else:
                client = List[String]()
                client.append(value)
            index += 2
            continue
        if word.startswith("--"):
            raise Error("unknown argument " + word)
        towns.append(word)
        index += 1
    if root.byte_length() == 0:
        root = getenv("CARLA_EXPORT_DIR", ".")
    write_environments(_absolute(root), host, port, client, towns)


def _port(text: String) raises -> Int:
    """Return a decimal port."""
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error("port is not an integer")
    var value = 0
    for index in range(len(raw)):
        var byte = raw[index]
        if byte < 48 or byte > 57:
            raise Error("port is not an integer")
        value = value * 10 + Int(byte - 48)
    return value


def main() raises:
    """Write the environment files named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    var copied = List[String]()
    for index in range(1, len(arguments)):
        copied.append(String(arguments[index]))
    try:
        _drive(copied)
    except error:
        print("carla_town_environment:", error, file=stderr)
        exit(1)
