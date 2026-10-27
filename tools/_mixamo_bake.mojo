# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bake a folder of Mixamo FBX files into one humanoid file.

`tools/mixamo.mojo bake` calls `bake_mixamo`. It builds the game humanoid
as `examples/game_humanoid.mojo` does, retargets each FBX file of the folder
onto its bones, and writes one sealed `.glb` with the clips. A game loads
that file with `read_gltf` and finds each clip by its name. The name is the
file's, as `Walking.fbx` gives `Walking`.

A file that cannot be read, or lacks a bone the retarget needs, is skipped
and listed in the report. It does not stop the run.
"""

from animation.animation_clip import AnimationClip
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.bake import write_sealed_bake
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    GAME_RECIPE,
    humanoid_provenance,
)
from extensions.humanoid.rig.game import add_game_humanoid, game_build_settings
from extensions.humanoid.rig.mixamo import MixamoOptions, read_mixamo
from extensions.humanoid.sex import Sex
from extensions.humanoid.spec import HumanoidSpec
from renderers.renderer import available_workers
from std.os import listdir
from tools._json_value import sorted_strings
from units.si import FOOT, Length

# The record's asset revision, as the game example writes it.
comptime ASSET_REVISION = "unverified-converted-ICTF-THRS"


struct Baked(Movable):
    """What a bake did."""

    var clips: Int
    """Clips written."""
    var skipped: List[String]
    """One line for each file that was skipped, with the reason."""

    def __init__(out self):
        """Start with nothing done."""
        self.clips = 0
        self.skipped = List[String]()


def fbx_files(folder: String, only: String = "") raises -> List[String]:
    """Return the FBX files of a folder, in name order.

    Args:
        folder: The folder.
        only: Keep a file only if its name has this text, in any case. Empty
            keeps all.

    Returns:
        The paths, each the folder and a slash and the file's name.

    Raises:
        Error: If the folder cannot be read.
    """
    var names = List[String]()
    var wanted = only.lower()
    for name in listdir(folder):
        var lower = name.lower()
        if not lower.endswith(".fbx"):
            continue
        if wanted.byte_length() > 0 and lower.find(wanted) < 0:
            continue
        names.append(name)
    var paths = List[String]()
    for name in sorted_strings(names^):  # pragma: no branch
        paths.append(folder + "/" + name)
    return paths^


def _taken(name: String, taken: List[String]) -> Bool:
    """Return whether a clip so far has the name."""
    for other in taken:  # pragma: no branch
        if other == name:
            return True
    return False


def _unique(name: String, taken: List[String]) -> String:
    """Return a name that no clip so far has.

    The first of `name`, `name 2`, `name 3` and so on that is free. A flag
    loop around the search crashed the Mojo 1.2.0 compiler for
    `arm64-apple-macosx` in LLVM's dominator tree construction.
    """
    var candidate = name
    var number = 2
    while _taken(candidate, taken):
        candidate = name + " " + String(number)
        number += 1
    return candidate^


def bake_mixamo(
    folder: String,
    output: String,
    stature: Length,
    sex: Sex,
    triangles: Int,
    options: MixamoOptions = MixamoOptions(),
    only: String = "",
    limit: Int = 0,
    detail: Int = 56,
    hand_detail: Int = 24,
    hair_detail: Int = 32,
) raises -> Baked:
    """Build a humanoid and bake the folder's animations onto it.

    Args:
        folder: The folder of FBX files.
        output: The `.glb` file to write.
        stature: The humanoid's standing height.
        sex: Its osteological template.
        triangles: The skin's triangle budget.
        options: Whether the hips stay in place, and the sampling rate.
        only: Bake a file only if its name has this text, in any case.
        limit: Bake at most this many files, or zero for no limit.
        detail: The body's sampling detail.
        hand_detail: The hands' sampling detail.
        hair_detail: The hair's sampling detail.

    Returns:
        How many clips were written, and which files were skipped.

    Raises:
        Error: If the folder holds no FBX file to bake, the humanoid cannot
            be built, or the file cannot be written.
    """
    var files = fbx_files(folder, only)
    if limit > 0 and len(files) > limit:
        files.resize(limit, "")
    var assets = Assets()
    var scene = Scene()
    var root = scene.add(Object3D())
    var spec = HumanoidSpec(stature, sex)
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        spec,
        triangles,
        detail,
        hand_detail,
        hair_detail,
        workers=available_workers(),
    )
    var report = Baked()
    var clips = List[AnimationClip]()
    var names = List[String]()
    for path in files:  # pragma: no branch
        try:
            var found = read_mixamo(path, person.bones, person.rig, options)
            for index in range(len(found)):  # pragma: no branch
                found[index].name = _unique(found[index].name, names)
                names.append(found[index].name)
                clips.append(found[index].copy())
        except failure:
            report.skipped.append(path + ": " + String(failure))
    if len(clips) == 0:
        raise Error("No Mixamo animation could be baked from " + folder)
    var record = humanoid_provenance(
        spec,
        game_build_settings(triangles, detail, hand_detail, hair_detail),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        ASSET_REVISION,
    )
    write_sealed_bake(output, scene, assets, record, animations=clips)
    report.clips = len(clips)
    return report^
