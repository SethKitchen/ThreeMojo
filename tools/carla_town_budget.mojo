# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose which town meshes to keep and how many triangles each keeps.

    carla_town_budget kind MESH_PATH
    carla_town_budget near KIND TRIANGLES MESH_PATH
    carla_town_budget far KIND TRIANGLES MESH_PATH
    carla_town_budget object FULL_NAME
    carla_town_budget serve

`kind` prints the scenery kind, or `skip` when the folder is not scenery.
`near` and `far` print the triangle limit for one copy. `object` prints
the Unreal class, package, and object name, one per line. `serve` reads
one tab-separated request per line and writes one `ok` or `err` line.
"""

from std.ffi import external_call
from std.memory import OpaquePointer
from std.sys import argv, exit, stderr

from tools._owned_process import EINTR, errno
from tools._text import ascii_lower


def kind_of(mesh_path: String) -> String:
    """Return a mesh's kind, or `skip` when the town leaves it out.

    Args:
        mesh_path: The Unreal object path.

    Returns:
        A scenery kind, or `skip`.
    """
    if mesh_path.startswith("/Engine/"):
        return "prop"
    var parts = mesh_path.split("/")
    var folder = String("")
    if len(parts) > 4 and parts[3] == "Static":
        folder = String(parts[4])
    if _skipped(folder):
        return "skip"
    if folder == "Building" or folder == "Bridge":
        return "building"
    if folder == "Wall":
        return "wall"
    if folder == "Fence" or folder == "GuardRail":
        return "fence"
    if folder == "Road":
        return "road"
    if folder == "RoadLine":
        return "road_line"
    if folder == "SideWalk":
        return "sidewalk"
    if folder == "Ground":
        return "ground"
    if folder == "Terrain":
        return "terrain"
    if folder == "Water":
        return "water"
    if folder == "RailTrack":
        return "rail"
    if folder == "Vegetation":
        return "vegetation"
    if folder == "Pole" or folder == "StreetLight":
        return "pole"
    if folder == "TrafficLight":
        return "traffic_light"
    if folder == "TrafficSign":
        return "traffic_sign"
    if (
        folder == "Car"
        or folder == "Truck"
        or folder == "Motorcycle"
        or folder == "Bicycle"
        or folder == "Bus"
    ):
        return "parked_vehicle"
    return "prop"


def near_budget(kind: String, triangles: Int, mesh_path: String) -> Int:
    """Return the most triangles one near copy keeps.

    A flat kind keeps every triangle. A road's paint is only a few
    triangles deep, and simplifying it breaks the paint.

    Args:
        kind: The scenery kind from `kind_of`.
        triangles: The mesh's triangle count.
        mesh_path: The Unreal object path.

    Returns:
        The near triangle limit.
    """
    if _flat(kind):
        return triangles
    if kind == "building":
        return max(min(triangles, 2500), triangles // 6)
    if kind == "parked_vehicle":
        return min(triangles, 2500)
    if kind == "vegetation":
        var cap = 4000
        if "/Bushes/" in mesh_path:
            cap = 800
        return min(triangles, cap)
    if kind == "pole" or kind == "traffic_light" or kind == "traffic_sign":
        return min(triangles, max(400, triangles // 6))
    return min(triangles, max(600, triangles // 4))


def far_budget(kind: String, triangles: Int, mesh_path: String) -> Int:
    """Return the most triangles one far copy keeps.

    Args:
        kind: The scenery kind from `kind_of`.
        triangles: The mesh's triangle count.
        mesh_path: The Unreal object path.

    Returns:
        The far triangle limit, or 0 when the far level leaves the mesh out.
    """
    var low = ascii_lower(mesh_path)
    if kind == "prop" or kind == "parked_vehicle" or kind == "traffic_sign":
        return 0
    if kind == "vegetation":
        if "/trees/" in low:
            return min(triangles, max(150, triangles // 5))
        return 0
    if kind == "building":
        return max(min(triangles, 300), triangles // 60)
    if kind == "pole" or kind == "traffic_light":
        if "glass" in low or "leds" in low:
            return 0
        return min(triangles, max(120, triangles // 12))
    if kind == "wall" or kind == "fence":
        return min(triangles, max(150, triangles // 10))
    return near_budget(kind, triangles, mesh_path)


def object_fields(full_name: String) raises -> List[String]:
    """Return the class, package, and object name.

    Args:
        full_name: UE4SS text such as `StaticMesh /Game/A/B.B`.

    Returns:
        Three strings. The object name is the text after the last `:` or `.`
        in the text that follows the package's last `.`.

    Raises:
        Error: If `full_name` has no class and path.
    """
    var space = full_name.find(" ")
    if space < 0:
        raise Error("object path has no class")
    var cls = String(full_name[byte=0:space])
    var path = String(full_name[byte = space + 1 :])
    var dot = path.rfind(".")
    var package = String("")
    var name = String(path)
    if dot >= 0:
        package = String(path[byte=0:dot])
        name = String(path[byte = dot + 1 :])
    var colon = name.rfind(":")
    if colon >= 0:
        var after_colon = String(name[byte = colon + 1 :])
        name = after_colon
    var nested = name.rfind(".")
    if nested >= 0:
        var after_dot = String(name[byte = nested + 1 :])
        name = after_dot
    var out = List[String]()
    out.append(cls)
    out.append(package)
    out.append(name)
    return out^


def _flat(kind: String) -> Bool:
    """Return whether a kind keeps every triangle."""
    return (
        kind == "road"
        or kind == "road_line"
        or kind == "sidewalk"
        or kind == "ground"
        or kind == "terrain"
        or kind == "water"
        or kind == "rail"
    )


def _skipped(folder: String) -> Bool:
    """Return whether a Static folder is not scenery."""
    return (
        folder == "Sky"
        or folder == "Particles"
        or folder == "Pedestrian"
        or folder == "Hair"
        or folder == "CubeMaps"
        or folder == "HDRi"
        or folder == "Decals"
        or folder == "TestWindowsParts"
    )


def _int(text: String) raises -> Int:
    """Return a decimal integer."""
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error("triangle count is empty")
    var value = 0
    var negative = False
    var start = 0
    if raw[0] == 45:
        negative = True
        start = 1
    if start == len(raw):
        raise Error("triangle count is empty")
    for index in range(start, len(raw)):
        var digit = Int(raw[index]) - 48
        if digit < 0 or digit > 9:
            raise Error("triangle count is not decimal")
        if value > (Int.MAX - digit) // 10:
            raise Error("triangle count is too large")
        value = value * 10 + digit
    if negative:
        return -value
    return value


def _reply(line: String) raises -> String:
    """Return one `ok` line for a tab-separated request."""
    var fields = List[String]()
    for field in line.split("\t"):
        fields.append(String(field))
    if len(fields) == 0:
        raise Error("usage: carla_town_budget kind|near|far|object ...")
    var command = fields[0]
    if command == "kind" and len(fields) == 2:
        return "ok\t" + kind_of(fields[1])
    if command == "near" and len(fields) == 4:
        return "ok\t" + String(
            near_budget(fields[1], _int(fields[2]), fields[3])
        )
    if command == "far" and len(fields) == 4:
        return "ok\t" + String(
            far_budget(fields[1], _int(fields[2]), fields[3])
        )
    if command == "object" and len(fields) == 2:
        var parts = object_fields(fields[1])
        return "ok\t" + parts[0] + "\t" + parts[1] + "\t" + parts[2]
    raise Error("usage: carla_town_budget kind|near|far|object ...")


struct _Taken(Movable):
    """One line from standard input, or the end of the stream."""

    var text: String
    """The line, without its newline."""
    var done: Bool
    """True when no further line is available."""

    def __init__(out self, var text: String, done: Bool):
        """Store one read."""
        self.text = text^
        self.done = done


struct _Reader(Movable):
    """A buffered reader of standard input."""

    var pending: List[UInt8]
    """Bytes read and not yet returned."""
    var at: Int
    """The next unread index in `pending`."""
    var eof: Bool
    """True after a read returns no bytes."""

    def __init__(out self):
        """Start with an empty buffer."""
        self.pending = List[UInt8]()
        self.at = 0
        self.eof = False

    def _fill(mut self) raises:
        """Read another block, or mark the end of the stream."""
        self.pending = List[UInt8]()
        self.at = 0
        var buf = List[UInt8](length=4096, fill=0)
        while True:
            var count = external_call["read", Int](
                Int32(0),
                OpaquePointer[MutAnyOrigin](
                    unsafe_from_address=Int(buf.unsafe_ptr())
                ),
                4096,
            )
            if count > 0:
                for index in range(count):
                    self.pending.append(buf[index])
                return
            if count == 0:
                self.eof = True
                return
            if errno() != Int(EINTR):
                raise Error("cannot read the budget request")

    def take(mut self) raises -> _Taken:
        """Return the next line.

        Returns:
            The line, or `done` at the end of the stream.

        Raises:
            Error: If a read fails or a line is longer than one million bytes.
        """
        var out = List[UInt8]()
        while True:
            if self.at >= len(self.pending):
                if self.eof:
                    if len(out) == 0:
                        return _Taken(String(""), True)
                    break
                self._fill()
                continue
            var byte = self.pending[self.at]
            self.at += 1
            if byte == 10:
                break
            if len(out) >= 1000000:
                raise Error("budget request is too long")
            out.append(byte)
        if len(out) > 0 and out[len(out) - 1] == 13:
            out.resize(len(out) - 1, 0)
        return _Taken(String(unsafe_from_utf8=Span(out)), False)


def _write_stdout(text: String) raises:
    """Write `text` to standard output, retrying an interrupt."""
    var raw = text.as_bytes()
    var sent = 0
    while sent < len(raw):
        var count = external_call["write", Int](
            Int32(1),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(raw.unsafe_ptr()) + sent
            ),
            len(raw) - sent,
        )
        if count > 0:
            sent += count
            continue
        if count == 0 or errno() != Int(EINTR):
            raise Error("cannot write the budget answer")


def serve() raises:
    """Answer requests from standard input until it closes."""
    var reader = _Reader()
    while True:
        var taken = reader.take()
        if taken.done:
            return
        try:
            _write_stdout(_reply(taken.text) + "\n")
        except error:
            _write_stdout("err\t" + String(error) + "\n")


def main() raises:
    """Print one budget answer, or serve requests from standard input."""
    var arguments = argv()
    if len(arguments) < 2:
        print(
            "usage: carla_town_budget kind|near|far|object|serve ...",
            file=stderr,
        )
        exit(2)
    try:
        var command = arguments[1]
        if command == "serve" and len(arguments) == 2:
            serve()
        elif command == "kind" and len(arguments) == 3:
            print(kind_of(arguments[2]))
        elif command == "near" and len(arguments) == 5:
            print(near_budget(arguments[2], _int(arguments[3]), arguments[4]))
        elif command == "far" and len(arguments) == 5:
            print(far_budget(arguments[2], _int(arguments[3]), arguments[4]))
        elif command == "object" and len(arguments) == 3:
            var parts = object_fields(arguments[2])
            print(parts[0])
            print(parts[1])
            print(parts[2])
        else:
            raise Error(
                "usage: carla_town_budget kind|near|far|object|serve ..."
            )
    except error:
        print("carla_town_budget:", error, file=stderr)
        exit(1)
