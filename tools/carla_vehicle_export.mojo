# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Export each CARLA vehicle to one glTF package.

    carla_vehicle_export [--root DIR] [ID ...]

`DIR` is the export directory, or `CARLA_EXPORT_DIR`, or `.`. Each id is
`vehicle.<make>.<model>`. With no id, every vehicle is exported. The
program runs UModel, merges the body and the glass, and writes the
package. One vehicle that fails does not stop the next.
"""

from std.collections import Dict
from std.os import getenv, listdir, makedirs, stat
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_tools import quote_ascii
from tools._json_tree import JsonTree
from tools._process import run_program
from tools._python_json import PY_LIST, PY_STR, PyJson
from tools.carla_gltf_package import package_vehicle
from tools.carla_umodel_class import class_text
from tools.carla_vehicle_merge import merge_gltf
from tools.carla_vehicle_paths import (
    blueprint_path,
    folder_candidates,
    gltf_path,
    package_path,
)
from tools.carla_vehicle_pick import pick_text
from tools.carla_vehicle_refs import reference_text


def export_vehicles(root: String, ids: List[String]) raises:
    """Export each vehicle and print one result line.

    Args:
        root: The export directory. Cooked content is
            `cooked/CarlaUE4/Content`. UModel is `umodel/umodel_64.exe`.
        ids: The vehicle ids. An empty list exports every vehicle, in
            the VehicleFactory order.

    Raises:
        Error: If the working directory cannot be read. A failure of one
            vehicle is printed and does not raise.
    """
    var chosen = List[String]()
    if len(ids) == 0:
        chosen = _all_ids()
    else:
        for index in range(len(ids)):
            chosen.append(ids[index])
    var classes = Dict[String, String]()
    for index in range(len(chosen)):
        print(_one(root, chosen[index], classes))


def _one(
    root: String, vehicle_id: String, mut classes: Dict[String, String]
) -> String:
    """Return one `OK` or `FAIL` line."""
    try:
        var relative = _relative(vehicle_id)
        if relative.byte_length() == 0:
            return _fail(vehicle_id, "KeyError('" + vehicle_id + "')")
        var note = _build(root, vehicle_id, relative, classes)
        if note.startswith("OK\t"):
            return _ok(vehicle_id, String(note[byte=3:]))
        return _fail(vehicle_id, note)
    except error:
        return _fail(vehicle_id, String(error))


def _build(
    root: String,
    vehicle_id: String,
    relative: String,
    mut classes: Dict[String, String],
) raises -> String:
    """Return `OK` and a tab plus the note, or a failure note."""
    var content = _child(root, "cooked/CarlaUE4/Content")
    var raw = _child(root, "raw")
    var umodel = _child(root, "umodel/umodel_64.exe")
    var blueprints = _child(content, "Carla/Blueprints/Vehicles")
    var blueprint = blueprint_path(blueprints, relative)
    var named = _strings(PyJson.parse(reference_text(blueprint)))
    var refs = _choice(content, umodel, named, classes)
    var choice = PyJson.parse(pick_text(_pick_json(refs, List[_Mesh]())))
    var error = choice.text(choice.at(choice.root, "error"))
    if error.byte_length() > 0:
        var extras = _folders(content, umodel, named, classes)
        choice = PyJson.parse(pick_text(_pick_json(refs, extras)))
        error = choice.text(choice.at(choice.root, "error"))
    if error.byte_length() > 0:
        return error
    var skeletal = _strings(choice, choice.at(choice.root, "skeletal"))
    var statics = _strings(choice, choice.at(choice.root, "static"))
    var body = _export(content, raw, umodel, skeletal[0])
    if body.byte_length() == 0:
        return "UModel exported nothing for " + skeletal[0]
    var text = Path(body).read_text()
    var data = Path(_buffer(body, text)).read_bytes()
    var added = 0
    for index in range(len(statics)):
        var extra = _export(content, raw, umodel, statics[index])
        if extra.byte_length() == 0:
            continue
        var extra_text = Path(extra).read_text()
        var extra_bin = Path(_buffer(extra, extra_text)).read_bytes()
        var merged = merge_gltf(text, data^, extra_text, extra_bin^)
        text = merged[0]
        data = merged[1].copy()
        added += 1
    var work = _child(_child(root, "merged"), vehicle_id)
    makedirs(work, exist_ok=True)
    var tree = JsonTree()
    var parsed = tree.parse(text)
    var buffer = tree.at(tree.item(parsed, "buffers"), 0)
    tree.set_text(buffer, "uri", vehicle_id + ".bin")
    Path(_child(work, vehicle_id + ".gltf")).write_text(
        tree.dumps(parsed, False)
    )
    Path(_child(work, vehicle_id + ".bin")).write_bytes(Span(data))
    var out = _child(_child(root, "packages"), vehicle_id)
    try:
        _ = package_vehicle(
            raw,
            _child(work, vehicle_id + ".gltf"),
            out,
            vehicle_id,
            1024,
            35000,
        )
    except error:
        return _tail(String(error))
    var size = _tree_size(out)
    return (
        "OK\t"
        + _basename(skeletal[0])
        + " + "
        + String(added)
        + " attachments, "
        + _megabytes(size)
        + " MB"
    )


def _choice(
    content: String,
    umodel: String,
    named: List[String],
    mut classes: Dict[String, String],
) raises -> List[_Mesh]:
    """Return the blueprint meshes. A pedestrian is not listed."""
    var records = List[_Mesh]()
    for index in range(len(named)):
        var path = named[index]
        if _has(path, "/Pedestrian/"):
            records.append(_Mesh(path, "", 0, ""))
            continue
        var kind = _class(classes, content, umodel, path)
        var size = 0
        if kind == "SkeletalMesh":
            size = _uexp_size(content, path)
        records.append(_Mesh(path, kind, size, ""))
    return records^


def _folders(
    content: String,
    umodel: String,
    named: List[String],
    mut classes: Dict[String, String],
) raises -> List[_Mesh]:
    """Return skeletal candidates from the folders the blueprint names."""
    var found = PyJson.parse(folder_candidates(content, _json_strings(named)))
    var records = List[_Mesh]()
    if found.kind(found.root) != PY_LIST:
        raise Error("folders are not a list")
    for index in range(found.length(found.root)):
        var item = found.item(found.root, index)
        var path = found.text(found.at(item, "path"))
        var name = found.text(found.at(item, "name"))
        var kind = _class(classes, content, umodel, path)
        var size = 0
        if kind == "SkeletalMesh":
            size = _uexp_size(content, path)
        records.append(_Mesh(path, kind, size, name))
    return records^


def _class(
    mut classes: Dict[String, String],
    content: String,
    umodel: String,
    game: String,
) raises -> String:
    """Return the UModel class of one package, cached by its game path."""
    if game in classes:
        return classes[game]
    var package = package_path(content, game)
    var kind = String("")
    if package.byte_length() > 0:
        var rel = _under(package, content)
        var command = List[String]()
        command.append(umodel)
        command.append("-game=ue4.26")
        command.append("-path=" + content)
        command.append("-list")
        command.append(rel)
        var ran = run_program(command, 3600, merge_errors=False)
        kind = class_text(_stem(package), ran.output)
    classes[game] = kind
    return kind


def _export(
    content: String, raw: String, umodel: String, game: String
) raises -> String:
    """Export one package and return its glTF path, or empty text."""
    var package = package_path(content, game)
    if package.byte_length() == 0:
        return String("")
    var rel = _under(package, content)
    var command = List[String]()
    command.append(umodel)
    command.append("-game=ue4.26")
    command.append("-path=" + content)
    command.append("-export")
    command.append("-gltf")
    command.append("-png")
    command.append("-out=" + raw)
    command.append(rel)
    _ = run_program(command, 3600, merge_errors=False)
    var path = gltf_path(raw, content, package)
    if Path(path).exists():
        return path
    return String("")


def _uexp_size(content: String, game: String) raises -> Int:
    """Return the cooked `.uexp` size used to choose the body."""
    var package = package_path(content, game)
    var stem = package.byte_length() - 7
    var path = String(package[byte=:stem]) + ".uexp"
    return Int(stat(path).st_size)


def _pick_json(refs: List[_Mesh], extras: List[_Mesh]) -> String:
    """Return the pick request."""
    var out = String('{"refs":')
    out += _mesh_json(refs)
    out += ',"extras":'
    out += _mesh_json(extras)
    out += "}"
    return out


def _mesh_json(items: List[_Mesh]) -> String:
    """Return a JSON list of mesh records."""
    var out = String("[")
    for index in range(len(items)):
        if index > 0:
            out += ","
        out += '{"path":'
        out += quote_ascii(items[index].path)
        out += ',"class":'
        out += quote_ascii(items[index].kind)
        out += ',"size":'
        out += String(items[index].size)
        if items[index].label.byte_length() > 0:
            out += ',"name":'
            out += quote_ascii(items[index].label)
        out += "}"
    out += "]"
    return out


def _buffer(gltf: String, text: String) raises -> String:
    """Return the buffer file named by the first buffer."""
    var doc = PyJson.parse(text)
    var uri = doc.text(doc.at(doc.item(doc.at(doc.root, "buffers"), 0), "uri"))
    return _child(_dirname(gltf), uri)


def _tree_size(root: String) raises -> Int:
    """Return the sum of the file sizes under `root`."""
    var total = 0
    if not Path(root).is_dir():
        return 0
    for name in listdir(root):
        var path = _child(root, name)
        if Path(path).is_dir():
            total += _tree_size(path)
        else:
            total += Int(stat(path).st_size)
    return total


def _megabytes(size: Int) raises -> String:
    """Return `f"{size / 1e6:.1f}"`."""
    var scaled = Fraction.from_float(Float64(size) / 1000000.0) * Fraction(10)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var quotient = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator:
        quotient = quotient + BigInt(1)
    elif twice == scaled.denominator and quotient.is_odd():
        quotient = quotient + BigInt(1)
    var tenths = quotient.to_int()
    var whole = tenths // 10
    var frac = tenths - whole * 10
    if frac < 0:
        frac = -frac
    return String(whole) + "." + String(frac)


def _tail(text: String) -> String:
    """Return the last 400 bytes, as the package failure note does."""
    var raw = text.as_bytes()
    if len(raw) <= 400:
        return text
    var start = len(raw) - 400
    return String(text[byte=start:])


def _strings(doc: PyJson) raises -> List[String]:
    """Return the strings in the root list."""
    return _at_strings(doc, doc.root)


def _strings(doc: PyJson, node: Int) raises -> List[String]:
    """Return the strings in one list."""
    return _at_strings(doc, node)


def _at_strings(doc: PyJson, node: Int) raises -> List[String]:
    """Return the strings in `node`."""
    if doc.kind(node) != PY_LIST:
        raise Error("names are not a list")
    var out = List[String]()
    for index in range(doc.length(node)):
        var item = doc.item(node, index)
        if doc.kind(item) != PY_STR:
            raise Error("name is not text")
        out.append(doc.text(item))
    return out^


def _json_strings(items: List[String]) -> String:
    """Return a compact JSON list of strings."""
    var out = String("[")
    for index in range(len(items)):
        if index > 0:
            out += ","
        out += quote_ascii(items[index])
    out += "]"
    return out


def _ok(vehicle_id: String, note: String) -> String:
    """Return one success line."""
    return "OK   " + _pad(vehicle_id) + " " + note


def _fail(vehicle_id: String, note: String) -> String:
    """Return one failure line."""
    return "FAIL " + _pad(vehicle_id) + " " + note


def _pad(text: String) -> String:
    """Return `text` padded with spaces to 36 characters."""
    var out = text
    while out.byte_length() < 36:
        out += " "
    return out


def _under(path: String, root: String) raises -> String:
    """Return `path` relative to `root`."""
    var prefix = root
    if not prefix.endswith("/"):
        prefix += "/"
    if not path.startswith(prefix):
        raise Error("package is outside the content directory")
    return String(path[byte = prefix.byte_length() :])


def _stem(path: String) -> String:
    """Return the file name without `.uasset`."""
    var base = _basename(path)
    if base.endswith(".uasset"):
        var end = base.byte_length() - 7
        return String(base[byte=:end])
    return base


def _basename(path: String) -> String:
    """Return the text after the last slash."""
    var slash = path.rfind("/")
    if slash < 0:
        return path
    return String(path[byte = slash + 1 :])


def _dirname(path: String) -> String:
    """Return the text before the last slash."""
    var slash = path.rfind("/")
    if slash < 0:
        return String("")
    return String(path[byte=:slash])


def _child(root: String, child: String) -> String:
    """Join `child` onto `root` with one slash."""
    var raw = root.as_bytes()
    if len(raw) > 0 and raw[len(raw) - 1] == 47:
        return root + child
    if child.byte_length() > 0 and child.as_bytes()[0] == 47:
        return root + child
    return root + "/" + child


def _has(text: String, needle: String) -> Bool:
    """Return whether `needle` occurs in `text`."""
    return text.find(needle) >= 0


def _relative(vehicle_id: String) -> String:
    """Return the blueprint path for `vehicle_id`, or empty text."""
    var rows = _lines(_catalog())
    for index in range(len(rows)):
        var row = rows[index]
        var tab = row.find("\t")
        if tab < 0:
            continue
        if String(row[byte=:tab]) == vehicle_id:
            return String(row[byte = tab + 1 :])
    return String("")


def _all_ids() -> List[String]:
    """Return every vehicle id in VehicleFactory order."""
    var rows = _lines(_catalog())
    var ids = List[String]()
    for index in range(len(rows)):
        var row = rows[index]
        var tab = row.find("\t")
        if tab > 0:
            ids.append(String(row[byte=:tab]))
    return ids^


def _lines(text: String) -> List[String]:
    """Split `text` on newlines and drop a final empty line."""
    var out = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw) + 1):
        if index == len(raw) or raw[index] == 10:
            if index > start:
                out.append(String(text[byte=start:index]))
            start = index + 1
    return out^


def _catalog() -> String:
    """Return each vehicle id and its blueprint, one pair a line."""
    return (
        "vehicle.audi.a2\tAudiA2/BP_AudiA2\n"
        "vehicle.audi.tt\tAudiTT/BP_AudiTT\n"
        "vehicle.bmw.grandtourer\tBmwGrandTourer/BP_BmwGranTourer\n"
        "vehicle.micro.microlino\tBmwIsetta/BP_BmwIsetta\n"
        "vehicle.carlamotors.carlacola\tCarlaCola/BP_CarlaCola\n"
        "vehicle.chevrolet.impala\tChevroletImpala/BP_ChevroletImpala\n"
        "vehicle.citroen.c3\tCitroenC3/BP_CitroenC3\n"
        "vehicle.dodge.charger_police\tDodgeChargerPolice/BP_DodgeCharger\n"
        "vehicle.jeep.wrangler_rubicon\tJeepWranglerRubicon/BP_JeepWranglerRubicon\n"
        "vehicle.mercedes.coupe\tMercedes/BP_MercedesCoupe\n"
        "vehicle.mini.cooper_s\tMini/BP_Mini\n"
        "vehicle.nissan.micra\tNissanMicra/BP_NissanMicra\n"
        "vehicle.nissan.patrol\tNissanPatrol/BP_NissanPatrol\n"
        "vehicle.seat.leon\tSeatLeon/BP_SeatLeon\n"
        "vehicle.toyota.prius\tToyotaPrius/BP_ToyotaPrius\n"
        "vehicle.harley-davidson.low_rider\t2Wheeled/Harley/BP_Harley\n"
        "vehicle.yamaha.yzf\t2Wheeled/Yamaha/BP_Yamaha\n"
        "vehicle.kawasaki.ninja\t2Wheeled/KawasakiNinja/BP_KawasakiNinja\n"
        "vehicle.bh.crossbike\t2Wheeled/CrossBike/BP_CrossBike\n"
        "vehicle.gazelle.omafiets\t2Wheeled/LeisureBike/BP_LeisureBike\n"
        "vehicle.diamondback.century\t2Wheeled/RoadBike/BP_RoadBike\n"
        "vehicle.audi.etron\tAudiETron/BP_Audi_Etron\n"
        "vehicle.tesla.cybertruck\tCybertruck/BP_Cybertruck\n"
        "vehicle.tesla.model3\tTesla/BP_TeslaM3\n"
        "vehicle.volkswagen.t2\tVolkswagenT2/BP_VolkswagenT2\n"
        "vehicle.lincoln.mkz_2017\tLincolnMKZ2017/BP_LincolnMKZ\n"
        "vehicle.ford.mustang\tMustang/BP_Mustang66\n"
        "vehicle.lincoln.mkz_2020\tLincolnMKZ2020/BP_LincolnMKZ2020\n"
        "vehicle.mercedes.coupe_2020\tMercedesCCC/BP_MercedesCCC\n"
        "vehicle.dodge.charger_2020\tDodgeCharger2020/Charger2020/BP_Charger2020\n"
        "vehicle.dodge.charger_police_2020\tDodgeCharger2020/ChargerCop/BP_ChargerCop\n"
        "vehicle.ford.ambulance\tAmbulance/BP_Ambulance\n"
        "vehicle.carlamotors.firetruck\tFireTruck/BP_Firetruck\n"
        "vehicle.vespa.zx125\t2Wheeled/Vespa/BP_Vespa\n"
        "vehicle.mini.cooper_s_2021\tMini2021/BP_Mini2021\n"
        "vehicle.nissan.patrol_2021\tNissanPatrol2021/BP_NissanPatrol2021\n"
        "vehicle.mercedes.sprinter\tSprinter/BP_Sprinter\n"
        "vehicle.ford.crown\tFord_Crown/BP_Ford_Crown\n"
        "vehicle.volkswagen.t2_2021\tVolkswagen_T2_2021/BP_VolkswagenT2_2021\n"
        "vehicle.mitsubishi.fusorosa\tMitsubishiFusoRosa/BP_MitsubishiFusoRosa\n"
        "vehicle.carlamotors.european_hgv\tEuropean_HGV/BP_European_HGV\n"
    )


def _absolute(path: String) raises -> String:
    """Return `path` joined to the working directory when it is relative."""
    var raw = path.as_bytes()
    if len(raw) > 0 and raw[0] == 47:
        return path
    var pwd = run_program(["pwd"], 5)
    if pwd.status != 0:
        raise Error("cannot read the working directory")
    var cwd = pwd.output
    var length = cwd.byte_length()
    var newline = False
    if length > 0:
        newline = cwd.as_bytes()[length - 1] == 10
    if newline:
        var end = length - 1
        var trimmed = String(cwd[byte=:end])
        cwd = trimmed
    if path == "." or path.byte_length() == 0:
        return cwd
    return _child(cwd, path)


def _drive(arguments: List[String]) raises:
    """Read the export options and print each vehicle."""
    var root = String()
    var ids = List[String]()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--root":
            if index + 1 >= len(arguments):
                raise Error("--root needs a value")
            root = arguments[index + 1]
            index += 2
            continue
        if word.startswith("--"):
            raise Error("unknown argument " + word)
        ids.append(word)
        index += 1
    if root.byte_length() == 0:
        root = getenv("CARLA_EXPORT_DIR", ".")
    export_vehicles(_absolute(root), ids)


@fieldwise_init
struct _Mesh:
    """One mesh record sent to the picker."""

    var path: String
    var kind: String
    var size: Int
    var label: String


def main() raises:
    """Export the vehicles named on the command line.

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
        print("carla_vehicle_export:", error, file=stderr)
        exit(1)
