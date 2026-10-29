# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose each town primitive's material name.

    carla_town_slots REQUEST.json

The request holds the component's material paths and each primitive's own
name. A named slot wins over the primitive's position. A null slot, or a
`MaterialInstanceDynamic`, keeps the mesh's own name.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tools import quote_ascii
from tools._json_tree import NOTHING, JsonTree
from tools.carla_town_budget import object_fields


struct _Slot(Movable):
    """One component material, or an empty slot."""

    var present: Bool
    """False when the component has no material in this slot."""
    var cls: String
    """The Unreal class."""
    var name: String
    """The object name."""

    def __init__(out self, present: Bool, var cls: String, var name: String):
        """Store one slot."""
        self.present = present
        self.cls = cls^
        self.name = name^


struct _Own(Movable):
    """A primitive's own material name, which may be absent."""

    var present: Bool
    """False when the primitive names no material."""
    var text: String
    """The name."""

    def __init__(out self, present: Bool, var text: String):
        """Store one name."""
        self.present = present
        self.text = text^


def choose_text(text: String) raises -> String:
    """Return the chosen material names as a JSON array.

    Args:
        text: JSON with `materials` and `own`. A material is a UE4SS path
            or null. `own` is each primitive's material name, or null.

    Returns:
        A JSON array of names, with null where the primitive had none.

    Raises:
        Error: If a material path has no class.
    """
    var tree = JsonTree()
    var root = tree.parse(text)
    var materials = tree.item(root, "materials")
    var own = tree.item(root, "own")
    var slots = List[_Slot]()
    var names = List[_Own]()
    var material_items = tree.items(materials)
    for index in range(len(material_items)):
        var item = material_items[index]
        if tree.is_null(item):
            slots.append(_Slot(False, String(""), String("")))
            names.append(_Own(False, String("")))
        else:
            var parsed = object_fields(tree.text(item))
            var cls = parsed[0]
            var object_name = parsed[2]
            names.append(_Own(True, object_name))
            slots.append(_Slot(True, cls, object_name))
    var owners = List[_Own]()
    var own_items = tree.items(own)
    for index in range(len(own_items)):
        var item = own_items[index]
        if tree.is_null(item):
            owners.append(_Own(False, String("")))
        else:
            owners.append(_Own(True, tree.text(item)))
    var out = String("[")
    for index in range(len(owners)):
        if index > 0:
            out += ","
        var chosen = _choose(slots, names, owners[index], index)
        if not chosen.present:
            out += "null"
        else:
            out += quote_ascii(chosen.text)
    out += "]"
    return out^


def _choose(
    slots: List[_Slot],
    names: List[_Own],
    owned: _Own,
    index: Int,
) -> _Own:
    """Return the name one primitive keeps."""
    var slot = -1
    for at in range(len(names)):
        if _same(names[at], owned):
            slot = at
            break
    if slot < 0:
        if index < len(slots):
            slot = index
    if slot < 0 or not slots[slot].present:
        return _Own(owned.present, owned.text)
    if slots[slot].cls == "MaterialInstanceDynamic":
        return _Own(owned.present, owned.text)
    return _Own(True, slots[slot].name)


def _same(left: _Own, right: _Own) -> Bool:
    """Return whether two names are the same, including both absent."""
    if left.present != right.present:
        return False
    if not left.present:
        return True
    return left.text == right.text


def main() raises:
    """Print the chosen names for the request file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_slots REQUEST.json", file=stderr)
        exit(2)
    try:
        print(choose_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_slots:", error, file=stderr)
        exit(1)
