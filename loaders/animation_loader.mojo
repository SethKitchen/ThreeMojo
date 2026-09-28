# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Animation clips read from a JSON file, ported from three.js
`src/loaders/AnimationLoader.js`.

three.js's `AnimationLoader` reads a JSON array of clips, each as
`AnimationClip.toJSON` writes it, and gives each to `AnimationClip.parse`.
`parse_animations` does the same with `animation.animation_json.read_clip`.
`read_animations` reads the text from a file first, three.js's `load`.

## A track needs a target

A three.js track keeps its name, `Hips.position`, and finds its target
when a mixer plays it. Here a track holds a `TrackTarget`, so the loader
finds each target when it reads the clip. It looks below a root node, as
three.js's `PropertyBinding.findNode` looks below the root a mixer plays
the clip on:

- An empty node name, `.`, or the root's own name is the root.
- Any other name is the first node below the root, depth first, with that
  name.
- `.bones[name]` is the first node below that node with the bone's name.
- `.material` and `.map` are the material of the first mesh at the node.
- `.morphTargetInfluences[i]` is a morph target of the first mesh at the
  node, by index or by name in its `morph_target_dictionary`. With no
  index it is every morph target.
- A light's property is the first light at the node.

## What differs from three.js

three.js keeps a track whose name finds nothing, and binds it to nothing
when it plays. Here such a track is left out when the clip is read, and a
clip whose every track is left out is left out too. A track on a camera,
on `.material[i]` or on `.materials` binds nothing, as a scene holds no
camera and a mesh here names one material for a track. A morph track
binds to a `Mesh`, and not to a `SkinnedMesh`.
"""

from animation.animation_clip import AnimationClip
from animation.animation_json import (
    element_axis,
    parse_track_name,
    property_kind,
    read_clip,
    track_names,
)
from animation.keyframe_track import (
    LightIndex,
    MORPH_INFLUENCE,
    TrackTarget,
    light_target,
    material_target,
    node_element_target,
    node_target,
)
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from loaders.json import ARRAY, JsonDocument, parse_json
from std.pathlib import Path


def _named_below(scene: Scene, root: NodeId, name: String) raises -> NodeId:
    """Return the first node below `root`, depth first, with `name`, or
    `NO_PARENT` for none, three.js's `searchNodeSubtree`."""
    var nodes = scene.traverse(root)
    # `traverse` lists the root first, and the root is not below itself.
    for at in range(1, len(nodes)):
        if scene.get(nodes[at]).name == name:
            return nodes[at]
    return NO_PARENT


def _find_node(scene: Scene, root: NodeId, name: String) raises -> NodeId:
    """Return the node a track's node name names below a root, three.js's
    `PropertyBinding.findNode`, or `NO_PARENT` for none."""
    if name == "" or name == "." or name == scene.get(root).name:
        return root
    return _named_below(scene, root, name)


def _is_count(text: String) -> Bool:
    """Return True if a text holds decimal digits and nothing else. Every
    caller has a text of one character or more."""
    var bytes = text.as_bytes()
    for at in range(len(bytes)):  # pragma: no branch
        if bytes[at] < 48 or bytes[at] > 57:
            return False
    return True


def _morph_target(
    scene: Scene, node: NodeId, index: String
) raises -> Optional[TrackTarget]:
    """Return the morph target a track names on the first mesh at a node:
    every target for no index, one by number, or one by its name in the
    mesh's `morph_target_dictionary`."""
    for mesh in range(len(scene.meshes)):
        if scene.meshes[mesh].node != node:
            continue
        var slot = _slot_of(scene.meshes[mesh].morph_target_dictionary, index)
        if not slot:
            return None
        return TrackTarget(MORPH_INFLUENCE, mesh, slot.value())
    return None


def _slot_of(names: Dict[String, Int], index: String) raises -> Optional[Int]:
    """Return which morph target an index names: -1 for every target when
    it is empty, the number it holds, or the target its name names, or
    None when no target has the name."""
    if index == "":
        return -1
    if _is_count(index):
        return atol(index)
    return names.get(index)


def track_target(
    scene: Scene, root: NodeId, name: String
) raises -> Optional[TrackTarget]:
    """Return what a track's name drives below a root node, three.js's
    `PropertyBinding` for that name.

    Args:
        scene: The scene the clip plays on.
        root: The node the clip plays on, where the names are looked up.
        name: The track's name, such as `Hips.position` or
            `.morphTargetInfluences[smile]`.

    Returns:
        The target, or None when three.js would bind the track to nothing
        here: no node has the name, or the node has no such bone, mesh,
        material or light. See the module docstring.

    Raises:
        Error: If the root is not in the scene, or the name is refused by
            `parse_track_name` or `property_kind`.
    """
    _ = scene.get(root)
    var path = parse_track_name(name)
    var kind = property_kind(path)
    var node = _find_node(scene, root, path.node_name)
    if node == NO_PARENT:
        return None
    if path.object_name == "bones":
        node = _named_below(scene, node, path.object_index)
        if node == NO_PARENT:
            return None
    if kind.is_element():
        return node_element_target(node, kind, element_axis(path))
    if kind.is_node():
        return node_target(node, kind)
    if kind.is_morph():
        return _morph_target(scene, node, path.property_index)
    if kind.is_light():
        for light in range(len(scene.lights)):
            if scene.lights[light].node == node:
                return light_target(LightIndex(light), kind)
        return None
    if path.object_name == "materials" or path.object_index != "":
        return None
    if kind.is_material():
        for mesh in range(len(scene.meshes)):
            if scene.meshes[mesh].node == node:
                return material_target(scene.meshes[mesh].material, kind)
        return None
    # A camera's property: a scene holds no camera to bind.
    return None


def parse_animations(
    text: String, scene: Scene, root: NodeId
) raises -> List[AnimationClip]:
    """Read clips from JSON text, three.js's `AnimationLoader.parse`.

    Args:
        text: A JSON array of clips, each as `AnimationClip.toJSON` writes
            it.
        scene: The scene the clips play on.
        root: The node the clips play on, where the tracks' node names are
            looked up; see `track_target`.

    Returns:
        The clips, in order. A clip none of whose tracks finds a target is
        left out.

    Raises:
        Error: If the text is not JSON, is not an array, or a clip is
            refused by `track_names`, `track_target` or `read_clip`.
    """
    var document = parse_json(text)
    var top = document.root()
    if document.kind(top) != ARRAY:
        raise Error("An animation file must hold a JSON array of clips")
    var clips = List[AnimationClip]()
    for index in range(document.length(top)):
        var clip = document.at(top, index)
        var names = track_names(document, clip)
        var targets = List[Optional[TrackTarget]]()
        for track in range(len(names)):
            targets.append(track_target(scene, root, names[track]))
        var read = read_clip(document, clip, targets)
        if Bool(read):
            clips.append(read.take())
    return clips^


def read_animations(
    path: String, scene: Scene, root: NodeId
) raises -> List[AnimationClip]:
    """Read clips from a JSON file, three.js's `AnimationLoader.load`.

    Args:
        path: The file.
        scene: The scene the clips play on.
        root: The node the clips play on.

    Returns:
        What `parse_animations` gives.

    Raises:
        Error: If the file cannot be read, or for anything
            `parse_animations` refuses.
    """
    return parse_animations(Path(path).read_text(), scene, root)
