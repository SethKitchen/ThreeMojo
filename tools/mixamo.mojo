# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Download Mixamo animations, and put them on the game humanoid.

Commands, from the repository root:

    .venv/bin/mojo run -I . tools/mixamo.mojo download --character ID
    .venv/bin/mojo run -I . tools/mixamo.mojo inspect FILE.fbx ...
    .venv/bin/mojo run -I . tools/mixamo.mojo bake

`download` fetches every animation of Mixamo into `.cache/mixamo/animations`,
which git ignores. It needs your own Adobe sign-in: sign in on mixamo.com,
and copy the `access_token` value from the page's local storage into the
environment variable `MIXAMO_TOKEN`, or into a file that `--token-file`
names. `--character` is the id of any character in your account. It is in
the address of the export requests the page makes. A run that stops starts
again where it was.

`inspect` says which bones of the Mixamo skeleton each FBX file holds, and
how long its animations are.

`bake` builds the game humanoid, retargets each FBX file of the folder onto
it, and writes one `.glb` with a clip for each file.

See the wiki page Mixamo animations. Mixamo's terms of use apply to the
files. Do not commit them or share them.
"""

from extensions.humanoid.rig.mixamo import (
    MixamoOptions,
    ROLE_COUNT,
    mixamo_role,
)
from extensions.humanoid.sex import FEMALE, MALE
from core.assets import Assets
from core.scene import Scene
from loaders.fbx import read_fbx
from std.os import getenv
from std.pathlib import Path
from std.sys import argv, exit, stderr
from tools._cli import CommandLine, parse_command_line
from tools._mixamo import (
    Options,
    Transport,
    download_all,
    primary_character,
    require_token,
)
from tools._mixamo_bake import bake_mixamo
from units.si import FOOT, Length

comptime FOLDER = ".cache/mixamo/animations"
comptime OUTPUT = "out/humanoid_mixamo.glb"
comptime TOKEN_VARIABLE = "MIXAMO_TOKEN"

comptime USAGE = "usage: mixamo.mojo download|inspect|bake [options]\n"
comptime HELP = (
    "\nCommands:\n"
    "  download  Fetch every Mixamo animation as an FBX file.\n"
    "  inspect   Say which bones of the Mixamo skeleton an FBX file holds.\n"
    "  bake      Put the FBX files on the game humanoid in one .glb file.\n"
    "\nRun a command with --help for its options.\n"
)


struct Outcome(Movable):
    """What a command printed, and its exit status."""

    var status: Int
    """0 for success."""
    var out: String
    """For the standard output."""
    var err: String
    """For the standard error."""

    def __init__(
        out self, status: Int = 0, printed: String = "", complaint: String = ""
    ):
        """Hold a result.

        Args:
            status: The exit status.
            printed: The standard output text.
            complaint: The standard error text.
        """
        self.status = status
        self.out = printed
        self.err = complaint


def _parsed(
    arguments: List[String],
    command: String,
    help: String,
    flags: List[String],
    valued: List[String],
) -> CommandLine:
    """Parse the options of one command."""
    return parse_command_line(
        arguments,
        "mixamo.mojo " + command,
        "usage: mixamo.mojo " + command + " [options]\n",
        help,
        flags,
        valued,
    )


def _failed(line: CommandLine) -> Outcome:
    """Return the outcome of a command line that did not parse, or asked for
    help."""
    if line.status == -1:
        return Outcome(0, line.message)
    return Outcome(2, "", line.message)


def _number(line: CommandLine, name: String, default: String) raises -> Float64:
    """Return an option that must be a number."""
    var text = line.value(name, default)
    try:
        return Float64(text)
    except:
        raise Error(name + " must be a number, not " + text)


def _whole(line: CommandLine, name: String, default: String) raises -> Int:
    """Return an option that must be a whole number of zero or more."""
    var value = _number(line, name, default)
    if value < 0 or value != Float64(Int(value)):
        raise Error(name + " must be a whole number of zero or more")
    return Int(value)


def _token(line: CommandLine, from_environment: String) raises -> String:
    """Return the token from `--token-file` or the environment."""
    var file = line.value("--token-file", "")
    if file.byte_length() > 0:
        if not Path(file).exists():
            raise Error("There is no token file " + file)
        return require_token(Path(file).read_text())
    if from_environment.byte_length() == 0:
        raise Error(
            "Give the token in the environment variable "
            + TOKEN_VARIABLE
            + " or with --token-file"
        )
    return require_token(from_environment)


def _download_help() -> String:
    """Return the help text of `download`."""
    var text = String("\nFetch every Mixamo animation as an FBX file.\n\n")
    text += "  --character ID    The character to export for. Default: the\n"
    text += "                    account's primary character.\n"
    text += "  --output DIR      The folder. Default " + FOLDER + ".\n"
    text += "  --token-file FILE The file that holds the token.\n"
    text += "  --api URL         The API's address, for a test server.\n"
    text += "  --query TEXT      Only animations whose name has this text.\n"
    text += "  --limit N         Stop after N new files.\n"
    text += "  --format NAME     The file format. Default fbx7.\n"
    text += "  --fps N           Frames a second. Default 30.\n"
    text += "  --delay SECONDS   The wait between polls and animations.\n"
    text += "                    Default 1.\n"
    text += "  --polls N         How often to ask if an export is ready.\n"
    text += "                    Default 120.\n"
    text += "  --in-place        Ask Mixamo to keep the hips in place.\n"
    text += "  --list            Print the names. Fetch nothing.\n"
    return text^


def _download(
    arguments: List[String], from_environment: String, transport: Transport
) raises -> Outcome:
    """Run `download`."""
    var line = _parsed(
        arguments,
        "download",
        _download_help(),
        ["--in-place", "--list"],
        [
            "--character",
            "--output",
            "--token-file",
            "--api",
            "--query",
            "--limit",
            "--format",
            "--fps",
            "--delay",
            "--polls",
        ],
    )
    if line.status != 0:
        return _failed(line)
    var format = line.value("--format", "fbx7")
    if not format.startswith("fbx"):
        return Outcome(2, "", "--format must be an FBX format, as fbx7\n")
    var delay = _number(line, "--delay", "1")
    if delay < 0:
        return Outcome(2, "", "--delay must not be negative\n")
    var live = transport.copy()
    live.token = _token(line, from_environment)
    live.api = line.value("--api", live.api)
    var character = line.value("--character", "")
    if character.byte_length() == 0:
        character = primary_character(live)
    var options = Options(
        character,
        line.value("--output", FOLDER),
        line.value("--query", ""),
        _whole(line, "--limit", "0"),
        format,
        _whole(line, "--fps", "30"),
        "--in-place" in line.flags,
        delay,
        _whole(line, "--polls", "120"),
        "--list" in line.flags,
    )
    var report = download_all(live, options)
    var text = String("saved ") + String(report.saved) + " new files, kept "
    text += String(report.kept) + " that were there, skipped "
    text += String(report.packs) + " bundles, " + String(len(report.failed))
    text += " failed\n"
    for failure in report.failed:
        text += "  " + failure + "\n"
    return Outcome(1 if len(report.failed) > 0 else 0, text)


def _inspect(arguments: List[String]) raises -> Outcome:
    """Run `inspect`: every argument is a file."""
    if len(arguments) == 0 or arguments[0] == "--help" or arguments[0] == "-h":
        return Outcome(
            0 if len(arguments) > 0 else 2,
            (
                "usage: mixamo.mojo inspect FILE.fbx ...\n"
                "\nSay which bones of the Mixamo skeleton each file holds.\n"
            ),
            "usage: mixamo.mojo inspect FILE.fbx ...\n" if len(arguments)
            == 0 else "",
        )
    var text = String()
    var status = 0
    for path in arguments:
        var scene = Scene()
        var assets = Assets()
        var model = read_fbx(path, scene, assets)
        var found = List[Bool](length=ROLE_COUNT, fill=False)
        var used = 0
        for name in model.model_names:
            var role = mixamo_role(name)
            if role >= 0 and not found[role]:
                found[role] = True
                used += 1
        text += path + "\n  bones: " + String(len(model.models))
        text += ", used by the humanoid: " + String(used) + " of "
        text += String(ROLE_COUNT) + "\n"
        for clip in model.animations:
            text += "  animation " + clip.name + ", "
            text += String(clip.length) + " s, "
            text += String(clip.track_count()) + " tracks\n"
        if len(model.animations) == 0:
            text += "  no animation\n"
            status = 1
    return Outcome(status, text)


def _bake(arguments: List[String]) raises -> Outcome:
    """Run `bake`."""
    var line = _parsed(
        arguments,
        "bake",
        (
            "\nBuild the game humanoid and put each FBX file on it.\n\n"
            "  --animations DIR  The folder of FBX files. Default "
            + FOLDER
            + ".\n  --output FILE     The .glb file. Default "
            + OUTPUT
            + ".\n"
            "  --height-feet N   The humanoid's height. Default 6.\n"
            "  --sex NAME        male or female. Default male.\n"
            "  --triangles N     The skin's budget. Default 10000.\n"
            "  --only TEXT       Only files whose name has this text.\n"
            "  --limit N         At most N files.\n"
            "  --fps N           Keys a second in the clips. Default 30.\n"
            "  --keep-travel     Keep the hips' travel along the ground.\n"
        ),
        ["--keep-travel"],
        [
            "--animations",
            "--output",
            "--height-feet",
            "--sex",
            "--triangles",
            "--only",
            "--limit",
            "--fps",
        ],
    )
    if line.status != 0:
        return _failed(line)
    var sex = line.value("--sex", "male")
    if sex != "male" and sex != "female":
        return Outcome(2, "", "--sex must be male or female\n")
    var height = _number(line, "--height-feet", "6")
    if not height > 0:
        return Outcome(2, "", "--height-feet must be above zero\n")
    var fps = _whole(line, "--fps", "30")
    if fps < 1:
        return Outcome(2, "", "--fps must be one or more\n")
    var report = bake_mixamo(
        line.value("--animations", FOLDER),
        line.value("--output", OUTPUT),
        Length(Float32(height), FOOT),
        MALE if sex == "male" else FEMALE,
        _whole(line, "--triangles", "10000"),
        MixamoOptions("--keep-travel" not in line.flags, fps),
        line.value("--only", ""),
        _whole(line, "--limit", "0"),
    )
    var text = (
        "wrote "
        + line.value("--output", OUTPUT)
        + " with "
        + String(report.clips)
        + " clips, skipped "
        + String(len(report.skipped))
        + " files\n"
    )
    for skipped in report.skipped:
        text += "  " + skipped + "\n"
    return Outcome(0, text)


def run(
    arguments: List[String], from_environment: String, transport: Transport
) raises -> Outcome:
    """Run the command line.

    Args:
        arguments: The arguments, without the program name.
        from_environment: The value of `MIXAMO_TOKEN`, or empty.
        transport: How the requests go out. The token is set from the
            options.

    Returns:
        The text for each stream and the exit status.

    Raises:
        Error: If a command fails.
    """
    if len(arguments) == 0:
        return Outcome(2, "", USAGE)
    var command = arguments[0]
    var rest = List[String]()
    for index in range(1, len(arguments)):
        rest.append(arguments[index])
    if command == "download":
        return _download(rest, from_environment, transport)
    if command == "inspect":
        return _inspect(rest)
    if command == "bake":
        return _bake(rest)
    if command == "--help" or command == "-h":
        return Outcome(0, USAGE + HELP)
    return Outcome(
        2, "", USAGE + "mixamo.mojo: error: no command " + command + "\n"
    )


def main() raises:
    """Run the command line from the repository root.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var outcome: Outcome
    try:
        outcome = run(arguments, getenv(TOKEN_VARIABLE, ""), Transport(""))
    except failure:
        outcome = Outcome(1, "", String(failure) + "\n")
    if outcome.out:
        print(outcome.out, end="")
    if outcome.err:
        print(outcome.err, end="", file=stderr)
    exit(outcome.status)
