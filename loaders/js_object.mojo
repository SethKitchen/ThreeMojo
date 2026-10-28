# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The order in which a JavaScript object walks its keys, for the loaders
that copy an order three.js gets from an object.

A JavaScript object walks its array-index keys first, from the smallest.
An array index is a whole number from zero to 2^32 - 2, written without a
sign or a leading zero. The object then walks its other keys in the order
they were added. `js_key_places` gives that order for string keys, and
`js_id_places` gives it for whole-number ids. `js_key_order` gives the
keys themselves.
"""

# The largest key that a JavaScript object walks as an array index.
comptime _LARGEST_INDEX = 4294967294


def js_id_places(ids: List[Int]) -> List[Int]:
    """Return the places of ids in the order a JavaScript object walks
    them as keys.

    three.js keeps the FBX objects in objects keyed by id, so this is the
    order in which it meets them.

    Args:
        ids: The ids, each once, in the order they were added.

    Returns:
        The places in `ids`: first the ids from zero to 2^32 - 2, in
        numeric order, then the others in the order given.
    """
    var count = len(ids)
    # Each index id and its place in one word, so that one sort orders
    # them: the ids are distinct, and `count` is far below 2^31.
    var indices = List[Int]()
    var others = List[Int]()
    for place in range(count):
        if ids[place] >= 0 and ids[place] <= _LARGEST_INDEX:
            indices.append(ids[place] * count + place)
        else:
            others.append(place)
    sort(indices)
    var out = List[Int](capacity=count)
    for word in indices:
        out.append(word % count)
    out.extend(others^)
    return out^


def js_key_places(keys: List[String]) -> List[Int]:
    """Return the places of keys in the order a JavaScript object walks
    them.

    Args:
        keys: The keys, each once, in the order they were added.

    Returns:
        The places in `keys`: first the array indices, from the smallest,
        then the others in the order given.
    """
    var ids = List[Int](capacity=len(keys))
    for key in keys:
        ids.append(_array_index(key))
    return js_id_places(ids)


def js_key_order(keys: List[String]) -> List[String]:
    """Return keys in the order a JavaScript object walks them.

    Args:
        keys: The keys, each once, in the order they were added.

    Returns:
        The keys that are array indices, from the smallest, then the
        others in the order given.
    """
    var out = List[String](capacity=len(keys))
    for place in js_key_places(keys):
        out.append(keys[place])
    return out^


def _array_index(key: String) -> Int:
    """Return the array index a key is, or -1.

    Args:
        key: The key.

    Returns:
        Its value when it is a whole number written without a sign or a
        leading zero and at most 2^32 - 2, or -1.
    """
    var bytes = key.as_bytes()
    if len(bytes) == 0 or len(bytes) > 10:
        return -1
    if len(bytes) > 1 and bytes[0] == 48:
        return -1
    var value = 0
    # The key is not empty here: the loop always runs.
    for byte in bytes:  # pragma: no branch
        if byte < 48 or byte > 57:
            return -1
        value = value * 10 + Int(byte) - 48
    if value > _LARGEST_INDEX:
        return -1
    return value
