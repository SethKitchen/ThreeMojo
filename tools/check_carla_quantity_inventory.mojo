# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check that the reviewed CARLA scalar inventory covers current declarations.

    check_carla_quantity_inventory [--root DIRECTORY] [--dump | --refresh-lines]

This is a source coverage check, not a numerical or type-safety proof. It
does not infer a physical dimension from an identifier. The inventory,
`docs/validation/carla-quantity-inventory-333.tsv`, owns that review.

The tool reads every public field, parameter and return type under
`extensions/carla/`. It selects each float or quantity, and the exact
integer wire and rate records the review names. The selection must equal the
inventory's rows, as a multiset, and each row must have a reviewed
classification and every review field. `--dump` prints the selection as
JSON. `--refresh-lines` rewrites the line numbers of a matching inventory.
"""

from std.collections import Set
from std.os import listdir
from std.os.path import isdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import JsonWriter
from tools._text import split_lines

comptime INVENTORY = "docs/validation/carla-quantity-inventory-333.tsv"
"""The reviewed inventory, relative to the root."""

comptime INTEGER_RECORDS = [
    ("cameras.mojo", "DVSEvent"),
    ("cameras.mojo", "DVSConfig"),
    ("cameras.mojo", "DVSCamera"),
    ("lidar.mojo", "LidarDescription"),
    ("radar.mojo", "RadarDescription"),
    ("recorder_packets.mojo", "RecorderInfo"),
    ("v2x.mojo", "ReferencePosition"),
    ("v2x.mojo", "HighFrequencyContainer"),
    ("v2x.mojo", "CAM"),
]
"""The records whose integer fields are wire or rate quantities."""

comptime INTEGER_SYMBOLS = [
    ("recorder.mojo", "now_seconds", "return"),
    ("recorder.mojo", "Recorder", "start_ns"),
    ("recorder.mojo", "Recorder.begin", "date"),
    ("recorder.mojo", "Recorder.start", "date"),
    ("recorder.mojo", "Recorder.begin_unix_seconds", "date"),
    ("recorder.mojo", "Recorder.start_unix_seconds", "date"),
    (
        "sensor_manager.mojo",
        "SensorManager.from_cam_epoch_milliseconds",
        "generation_delta0",
    ),
    ("v2x.mojo", "CaService.from_cam_epoch_milliseconds", "generation_delta0"),
    ("sensor_manager.mojo", "SensorManager", "generation_delta0"),
    ("sensor_manager.mojo", "SensorManager.__init__", "generation_delta0"),
    ("v2x.mojo", "CaService", "generation_delta0"),
    ("v2x.mojo", "CaService.__init__", "generation_delta0"),
    ("recorder_format.mojo", "c_date", "seconds"),
    ("v2x.mojo", "speed_value", "return"),
    ("v2x.mojo", "speed_value_meters_per_second", "return"),
]
"""The single integer declarations that are quantities."""

comptime CATEGORIES = [
    "typed-boundary",
    "raw-adapter",
    "source-field",
    "wire-field",
    "internal-state",
    "stage-kernel",
    "dimensionless",
    "generic-numeric",
    "source-code",
    "unimplemented-source-setting",
]
"""The reviewed classifications."""

comptime REVIEW_FIELDS = [
    "unit_or_meaning",
    "typed_boundary",
    "raw_adapter",
    "validation",
    "rationale",
]
"""The fields every inventory row must fill."""


def _is_word(byte: UInt8) -> Bool:
    """Return whether a byte can be part of a name, as `\\w` reads ASCII."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
        or byte >= 128
    )


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is white space."""
    return (
        byte == 32 or (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 31)
    )


def _word_end(text: String, start: Int) -> Int:
    """Return the end of the name that starts at `start`."""
    var bytes = text.as_bytes()
    var end = start
    while end < len(bytes) and _is_word(bytes[end]):
        end += 1
    return end


def _collapse(text: String) -> String:
    """Return text with each run of white space made one space, as
    `" ".join(text.split())` does."""
    var words = List[String]()
    for word in text.split():
        words.append(String(word))
    return " ".join(words)


def _strip(text: String) -> String:
    """Return text without white space at either end."""
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end and _is_space(bytes[start]):
        start += 1
    while end > start and _is_space(bytes[end - 1]):
        end -= 1
    return String(text[byte=start:end])


def _sort_by_parts(var paths: List[String]) -> List[String]:
    """Sort paths component by component, as Python sorts `Path` objects."""
    var keyed = List[String]()
    for path in paths:
        keyed.append(path.replace("/", "\0"))
    sort(keyed)
    var result = List[String]()
    for key in keyed:
        result.append(key.replace("\0", "/"))
    return result^


def _mojo_files(
    root: String, relative: String, recursive: Bool
) -> List[String]:
    """Return the `.mojo` files under a directory, relative to the root."""
    var found = List[String]()
    var pending: List[String] = [relative]
    while len(pending) > 0:
        var directory = pending.pop()
        var names: List[String]
        try:
            names = listdir(root + "/" + directory)
        except:
            continue
        for name in names:
            var path = directory + "/" + name
            if isdir(root + "/" + path):
                if recursive:
                    pending.append(path)
            elif name.endswith(".mojo"):
                found.append(path)
    return _sort_by_parts(found^)


def quantity_names(root: String) raises -> Set[String]:
    """Return the quantity type names: every `comptime NAME = Quantity[`
    alias of `units/` and of the physics quantities, and the photometric
    and temperature types.

    Args:
        root: The repository root.

    Returns:
        The names.

    Raises:
        Error: If a source cannot be read.
    """
    var names = Set[String]()
    for name in [
        "Temperature",
        "Temperature64",
        "Illuminance",
        "Luminance",
        "LuminousFlux",
        "LuminousIntensity",
    ]:
        names.add(name)
    var files = _mojo_files(root, "units", False)
    files.append("extensions/physics/quantities.mojo")
    for path in files:
        for line in split_lines(Path(root + "/" + path).read_text()):
            if not line.startswith("comptime "):
                continue
            var end = _word_end(line, 9)
            if end == 9:
                continue
            var after = _strip(String(line[byte=end:]))
            if after.startswith("=") and _strip(
                String(after[byte=1:])
            ).startswith("Quantity["):
                names.add(String(line[byte=9:end]))
    return names^


struct Row(Copyable, Movable):
    """One public declaration."""

    var file: String
    """The source, relative to the root."""
    var symbol: String
    """The owner, or `Owner.function`, or the function."""
    var member: String
    """The field, the parameter, or `return`."""
    var type: String
    """The declared type, with white space collapsed."""
    var kind: String
    """`field`, `parameter` or `return`."""
    var line: Int
    """The line of the declaration."""

    def __init__(
        out self,
        file: String,
        symbol: String,
        member: String,
        type: String,
        kind: String,
        line: Int,
    ):
        """Make a row.

        Args:
            file: The source.
            symbol: The owner or function.
            member: The field, parameter or `return`.
            type: The declared type.
            kind: `field`, `parameter` or `return`.
            line: The line.
        """
        self.file = file
        self.symbol = symbol
        self.member = member
        self.type = type
        self.kind = kind
        self.line = line

    def key(self) -> String:
        """Return the identity of the declaration, without its line.

        Returns:
            The file, symbol, member, type and kind, separated by tabs.
        """
        return (
            self.file
            + "\t"
            + self.symbol
            + "\t"
            + self.member
            + "\t"
            + self.type
            + "\t"
            + self.kind
        )


def _leading_spaces(line: String) -> Int:
    """Return how many white-space bytes start a line."""
    var bytes = line.as_bytes()
    var count = 0
    while count < len(bytes) and _is_space(bytes[count]):
        count += 1
    return count


def _raw_si(signature: String) -> Bool:
    """Return whether a signature has a parameter of type `_RawSI`."""
    var at = signature.find(": _RawSI")
    while at >= 0:
        var bytes = signature.as_bytes()
        var end = at + 8
        var word_before = at > 0 and _is_word(bytes[at - 1])
        var boundary = end >= len(bytes) or not _is_word(bytes[end])
        if word_before and boundary:
            return True
        at = signature.find(": _RawSI", at + 1)
    return False


def _parameter(part: String, mut name: String, mut type: String) -> Bool:
    """Read `[out|var|mut|ref|read ]NAME: TYPE`.

    Args:
        part: One parameter, stripped.
        name: Set to the parameter's name.
        type: Set to the text after the colon and its white space.

    Returns:
        True when the parameter has a name and a type.
    """
    for prefix in ["out ", "var ", "mut ", "ref ", "read ", ""]:
        if not part.startswith(prefix):
            continue
        var start = prefix.byte_length()
        var end = _word_end(part, start)
        if (
            end == start
            or end >= part.byte_length()
            or part.as_bytes()[end] != 58
        ):
            continue
        var at = end + 1
        while at < part.byte_length() and _is_space(part.as_bytes()[at]):
            at += 1
        name = String(part[byte=start:end])
        type = String(part[byte=at:])
        return True
    return False


def declarations(root: String) raises -> List[Row]:
    """Read the public fields and signatures under `extensions/carla/`.

    Private types and methods, and constructors that need the private
    `_RawSI` capability, are outside the application boundary. A public
    fieldwise constructor is represented by its fields. Generic signatures
    and multiline collection types are included.

    Args:
        root: The repository root.

    Returns:
        The declarations, in file and line order.

    Raises:
        Error: If a source cannot be read.
    """
    var rows = List[Row]()
    for file in _mojo_files(root, "extensions/carla", True):
        var lines = split_lines(Path(root + "/" + file).read_text())
        var owner = String()
        var private = False
        var doc = False
        var i = 0
        while i < len(lines):
            var line = lines[i]
            if line.count('"""') % 2 == 1:
                doc = not doc
                i += 1
                continue
            if doc:
                i += 1
                continue
            var keyword = 7 if line.startswith("struct ") else (
                6 if line.startswith("trait ") else 0
            )
            if keyword > 0 and _word_end(line, keyword) > keyword:
                owner = String(line[byte = keyword : _word_end(line, keyword)])
                private = owner.startswith("_")
                i += 1
                continue
            var indent = _leading_spaces(line)
            var defined = (
                line.find("def ", indent) == indent
                and _word_end(line, indent + 4) > indent + 4
            )
            if defined and indent <= 4:
                var name = String(
                    line[byte = indent + 4 : _word_end(line, indent + 4)]
                )
                var start = i
                if indent == 0:
                    owner = String()
                var symbol = owner + "." + name if owner else name
                var signature = line
                while not _strip(signature).endswith(":") and i + 1 < len(
                    lines
                ):
                    i += 1
                    signature += "\n" + lines[i]
                if (
                    (name.startswith("_") and not name.startswith("__"))
                    or (indent > 0 and private)
                    or _raw_si(signature)
                ):
                    i += 1
                    continue
                var begin = signature.find("(")
                var position = begin + 1
                var depth = 1
                var bytes = signature.as_bytes()
                while depth > 0 and position < len(bytes):
                    if bytes[position] == 40:
                        depth += 1
                    elif bytes[position] == 41:
                        depth -= 1
                    position += 1
                var arguments = String(
                    signature[byte = begin + 1 : max(begin + 1, position - 1)]
                )
                arguments += ","
                var mark = 0
                depth = 0
                var argument_bytes = arguments.as_bytes()
                for j in range(len(argument_bytes)):
                    var character = argument_bytes[j]
                    if character == 40 or character == 91:
                        depth += 1
                    elif character == 41 or character == 93:
                        depth -= 1
                    elif character == 44 and depth == 0:
                        var part = _strip(String(arguments[byte=mark:j]))
                        mark = j + 1
                        var parameter = String()
                        var raw = String()
                        if _parameter(part, parameter, raw):
                            var cut = raw.find(" = ")
                            if cut >= 0:
                                var head = String(raw[byte=:cut])
                                raw = head^
                            rows.append(
                                Row(
                                    file,
                                    symbol,
                                    parameter,
                                    _collapse(_strip(raw)),
                                    "parameter",
                                    start + 1,
                                )
                            )
                var tail = String(signature[byte=position:])
                var arrow = tail.find("->")
                if arrow >= 0:
                    var body = _strip_end(tail)
                    if (
                        body.endswith(":")
                        and body.byte_length() - 1 >= arrow + 2
                    ):
                        var result = String(
                            body[byte = arrow + 2 : body.byte_length() - 1]
                        )
                        rows.append(
                            Row(
                                file,
                                symbol,
                                "return",
                                _collapse(result),
                                "return",
                                start + 1,
                            )
                        )
                i += 1
                continue
            if line.startswith("    var ") and owner and not private:
                var end = _word_end(line, 8)
                if (
                    end > 8
                    and end < line.byte_length()
                    and line.as_bytes()[end] == 58
                ):
                    var field = String(line[byte=8:end])
                    var at = end + 1
                    while at < line.byte_length() and _is_space(
                        line.as_bytes()[at]
                    ):
                        at += 1
                    var stop = at
                    while (
                        stop < line.byte_length()
                        and line.as_bytes()[stop] != 61
                        and line.as_bytes()[stop] != 35
                    ):
                        stop += 1
                    # The pattern needs one type character; with none, it
                    # takes the last space, which strips to an empty type.
                    if (stop > at or at > end + 1) and not field.startswith(
                        "_"
                    ):
                        var start = i
                        var raw = _strip(String(line[byte=at:stop]))
                        var depth = raw.count("[") - raw.count("]")
                        while depth != 0 and i + 1 < len(lines):
                            i += 1
                            raw += " " + _strip(lines[i])
                            depth += lines[i].count("[") - lines[i].count("]")
                        rows.append(
                            Row(
                                file,
                                owner,
                                field,
                                _collapse(raw),
                                "field",
                                start + 1,
                            )
                        )
            i += 1
    return rows^


def _strip_end(text: String) -> String:
    """Return text without white space at its end."""
    var bytes = text.as_bytes()
    var end = len(bytes)
    while end > 0 and _is_space(bytes[end - 1]):
        end -= 1
    return String(text[byte=:end])


def _names_a_type(type: String, names: Set[String]) -> Bool:
    """Return whether a type names a float or a quantity as a whole word."""
    var bytes = type.as_bytes()
    var index = 0
    while index < len(bytes):
        if _is_word(bytes[index]) and (
            index == 0 or not _is_word(bytes[index - 1])
        ):
            var end = _word_end(type, index)
            var word = String(type[byte=index:end])
            if word == "Float32" or word == "Float64" or word in names:
                return True
            if word == "DType" and type.find(".", end) == end:
                var next = _word_end(type, end + 1)
                var member = String(type[byte = end + 1 : next])
                if member == "float32" or member == "float64":
                    return True
            index = end
        else:
            index += 1
    return False


def selected(root: String) raises -> List[Row]:
    """Return every float or quantity declaration, and the integer wire and
    rate declarations the review names.

    Args:
        root: The repository root.

    Returns:
        The selected declarations, in file and line order.

    Raises:
        Error: If a source cannot be read.
    """
    var names = quantity_names(root)
    var records = materialize[INTEGER_RECORDS]()
    var symbols = materialize[INTEGER_SYMBOLS]()
    var result = List[Row]()
    for row in declarations(root):
        var file = String(row.file[byte = row.file.rfind("/") + 1 :])
        var integer = (
            row.type == "Int"
            or row.type == "Int32"
            or row.type == "UInt32"
            or row.type == "UInt64"
        )
        var chosen = _names_a_type(row.type, names)
        if not chosen and integer:
            for record in records:
                if record[0] == file and record[1] == row.symbol:
                    chosen = True
        if not chosen:
            for entry in symbols:
                if (
                    entry[0] == file
                    and entry[1] == row.symbol
                    and entry[2] == row.member
                ):
                    chosen = True
        if chosen:
            result.append(row.copy())
    return result^


def dump(rows: List[Row]) -> String:
    """Return the rows as JSON with two-space indentation.

    Args:
        rows: The declarations.

    Returns:
        A list of objects with `file`, `symbol`, `member`, `type`, `kind`
        and `line`.
    """
    var writer = JsonWriter()
    writer.begin_array()
    for row in rows:
        writer.begin_object()
        writer.key("file")
        writer.string(row.file)
        writer.key("symbol")
        writer.string(row.symbol)
        writer.key("member")
        writer.string(row.member)
        writer.key("type")
        writer.string(row.type)
        writer.key("kind")
        writer.string(row.kind)
        writer.key("line")
        writer.integer(row.line)
        writer.end()
    writer.end()
    return writer.text()


def _python_key(key: String) -> String:
    """Write a declaration key as Python writes the tuple."""
    var parts = List[String]()
    for part in key.split("\t"):
        var text = String(part)
        var quote = "'" if text.find("'") < 0 or text.find('"') >= 0 else '"'
        parts.append(quote + text.replace("\\", "\\\\") + quote)
    return "(" + ", ".join(parts) + ")"


def check(root: String, refresh_lines: Bool) raises -> Tuple[Int, String]:
    """Compare the declarations with the inventory.

    Args:
        root: The repository root.
        refresh_lines: True to rewrite the inventory's line numbers when it
            matches.

    Returns:
        The exit status and the report.

    Raises:
        Error: If a file cannot be read or written.
    """
    var rows = selected(root)
    var lines = split_lines(Path(root + "/" + INVENTORY).read_text())
    var header = List[String]()
    for field in lines[0].split("\t"):
        header.append(String(field))
    var inventory = List[Dict[String, String]]()
    for index in range(1, len(lines)):
        var values = lines[index].split("\t")
        var row = Dict[String, String]()
        for column in range(len(header)):
            row[header[column]] = (
                String(values[column]) if column < len(values) else String()
            )
        inventory.append(row^)
    var expected = Dict[String, Int]()
    var order = List[String]()
    for row in rows:
        var key = row.key()
        if not key in expected:
            order.append(key)
        expected[key] = expected.get(key).or_else(0) + 1
    var found = Dict[String, Int]()
    var found_order = List[String]()
    for row in inventory:
        var key = (
            row["file"]
            + "\t"
            + row["symbol"]
            + "\t"
            + row["member"]
            + "\t"
            + row["type"]
            + "\t"
            + row["kind"]
        )
        if not key in found:
            found_order.append(key)
        found[key] = found.get(key).or_else(0) + 1
    var failures = List[String]()
    for key in order:
        var missing = expected[key] - found.get(key).or_else(0)
        if missing > 0:
            failures.append(
                "Missing "
                + String(missing)
                + " declaration(s): "
                + _python_key(key)
            )
    for key in found_order:
        var stale = found[key] - expected.get(key).or_else(0)
        if stale > 0:
            failures.append(
                "Stale "
                + String(stale)
                + " declaration(s): "
                + _python_key(key)
            )
    var categories = materialize[CATEGORIES]()
    for row in inventory:
        var key = _python_key(
            row["file"]
            + "\t"
            + row["symbol"]
            + "\t"
            + row["member"]
            + "\t"
            + row["type"]
            + "\t"
            + row["kind"]
        )
        var reviewed = False
        for category in categories:
            if row.get("classification").or_else(String()) == category:
                reviewed = True
        if not reviewed:
            failures.append("Unreviewed classification: " + key)
        for field in materialize[REVIEW_FIELDS]():
            if not row.get(field).or_else(String()):
                failures.append("Missing " + field + ": " + key)
    if len(failures) > 0:
        return (1, "\n".join(failures))
    if refresh_lines:
        var current = Dict[String, List[Int]]()
        for row in rows:
            var key = row.key()
            if not key in current:
                current[key] = List[Int]()
            current[key].append(row.line)
        var text = "\t".join(header) + "\n"
        for index in range(len(inventory)):
            var key = (
                inventory[index]["file"]
                + "\t"
                + inventory[index]["symbol"]
                + "\t"
                + inventory[index]["member"]
                + "\t"
                + inventory[index]["type"]
                + "\t"
                + inventory[index]["kind"]
            )
            inventory[index]["line"] = String(current[key].pop(0))
            var values = List[String]()
            for name in header:
                values.append(inventory[index][name])
            text += "\t".join(values) + "\n"
        Path(root + "/" + INVENTORY).write_text(text)
    return (
        0,
        "PASS: "
        + String(len(rows))
        + " current public scalar/quantity declarations; all rows have a"
        " reviewed disposition.\n"
        + "This checks inventory coverage only. It does not prove numerical"
        " correctness or passing runtime tests.",
    )


def main() raises:
    var given = argv()
    var root = String(".")
    var dump_rows = False
    var refresh = False
    var index = 1
    while index < len(given):
        var argument = String(given[index])
        if argument == "--dump":
            dump_rows = True
        elif argument == "--refresh-lines":
            refresh = True
        elif argument == "--root" and index + 1 < len(given):
            index += 1
            root = String(given[index])
        else:
            print(
                "check_carla_quantity_inventory: unknown argument:",
                argument,
                file=stderr,
            )
            exit(2)
        index += 1
    if dump_rows:
        print(dump(selected(root)))
        return
    var outcome = check(root, refresh)
    print(outcome[1])
    exit(outcome[0])
