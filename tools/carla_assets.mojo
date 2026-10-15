# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fetch, verify and credit the CARLA town's photoscanned assets.

The manifest, `assets/carla/manifest.json`, names each asset: its id, its
kind, its files with their URLs and SHA-256 sums, its license, its author,
its source page and a note on where it came from. This tool downloads the
files into a cache that git ignores, `.cache/carla-assets/`, and checks
each sum. The renderer reads the cache through `extensions/carla/assets`
and falls back to its procedural assets for an entry the cache lacks, so
nothing here is needed to build or to test.

Commands, from the repository root:

    sh tools/tool.sh .venv/bin/mojo carla_assets check
    sh tools/tool.sh .venv/bin/mojo carla_assets status
    sh tools/tool.sh .venv/bin/mojo carla_assets fetch [ID ...] [--pin | --offline]
    sh tools/tool.sh .venv/bin/mojo carla_assets verify [ID ...] [--strict]
    sh tools/tool.sh .venv/bin/mojo carla_assets credits [--all] [--output FILE]
    sh tools/tool.sh .venv/bin/mojo carla_assets stage-render --output NEW_DIRECTORY RENDER_FILE [RENDER_FILE ...]
    sh tools/tool.sh .venv/bin/mojo carla_assets stage-archive --output NEW_DIRECTORY ID [ID ...]

Rules the fetch keeps:

- A file is written to the cache only after its sum matches. It is first
  downloaded beside its place, then renamed into it.
- A verified file is never overwritten. A cached file whose sum does not
  match is reported and left alone; delete it by hand to fetch it again.
- A file with no sum in the manifest is not fetched, unless `--pin` is
  given. Then the first download is trusted, and its sum is written into
  the manifest, so every later fetch must match it.
- An archive (a `.zip`) is verified as a whole, and its members are then
  extracted to the paths the manifest names.
- A file whose URL is null is not hosted yet; its sum is in the manifest.
  It is not fetched. Put the file at its cache path by hand, and the
  next fetch verifies it and extracts it.
- A Google Drive share link is downloaded through Drive's download link.
  A web page sent in place of a file is refused.
- With `--offline`, fetch uses only pinned files already in the cache.
  It verifies archives before extracting missing members and never opens
  a URL. Missing or unpinned files fail the command, as do mismatches.
- With `--strict`, verify fails for missing or unpinned files as well as
  mismatches. Both commands can select entries by id.

It replaces `assets/carla/tools/carla_assets.py`, with the same command
line, texts, files and exit statuses. `curl` downloads the files. An error
that the Python tool did not catch ends with status 1 and the last line of
Python's traceback.
"""

from std.sys import argv, exit, stderr

from tools._carla_assets import (
    CHUNK,
    Report,
    Transport,
    absolute_text,
    check_manifest,
    credits,
    default_cache,
    default_manifest,
    entries_of,
    fetch,
    load_manifest,
    pad,
    path_name,
    path_parts,
    path_text,
    join_path,
    read_json_text,
    save_manifest,
    selected_entries,
    sha256_bytes,
    status_lines,
    verify,
)
from tools._carla_files import (
    FileId,
    close_fd,
    exception_line,
    exception_text,
    fstat_id,
    lstat_id,
    make_dir,
    make_dir_at,
    o_creat,
    o_dir,
    o_excl,
    o_nofollow_flag,
    o_nonblock,
    o_rdonly,
    o_wronly,
    open_at,
    open_path,
    path_exists,
    path_is_link,
    read_all,
    read_some,
    seek_start,
    stat_at,
    write_all,
    write_text,
)
from tools._python_json import PyJson, code_points, py_repr
from tools._sha256 import Sha256

comptime PROGRAM = "carla_assets"
"""The program name in usage and error texts."""

comptime COMMANDS: List[String] = [
    "check",
    "status",
    "fetch",
    "verify",
    "credits",
    "stage-render",
    "stage-archive",
]
"""The subcommands, in the order `--help` lists them."""

comptime _DESCRIPTION = """Fetch, verify and credit the CARLA town's photoscanned assets.

The manifest, `assets/carla/manifest.json`, names each asset: its id, its
kind, its files with their URLs and SHA-256 sums, its license, its author,
its source page and a note on where it came from. This tool downloads the
files into a cache that git ignores, `.cache/carla-assets/`, and checks
each sum. The renderer reads the cache through `extensions/carla/assets`
and falls back to its procedural assets for an entry the cache lacks, so
nothing here is needed to build or to test.

Commands, from the repository root:

    sh tools/tool.sh .venv/bin/mojo carla_assets check
    sh tools/tool.sh .venv/bin/mojo carla_assets status
    sh tools/tool.sh .venv/bin/mojo carla_assets fetch [ID ...] [--pin | --offline]
    sh tools/tool.sh .venv/bin/mojo carla_assets verify [ID ...] [--strict]
    sh tools/tool.sh .venv/bin/mojo carla_assets credits [--all] [--output FILE]
    sh tools/tool.sh .venv/bin/mojo carla_assets stage-render --output NEW_DIRECTORY RENDER_FILE [RENDER_FILE ...]
    sh tools/tool.sh .venv/bin/mojo carla_assets stage-archive --output NEW_DIRECTORY ID [ID ...]

Rules the fetch keeps:

- A file is written to the cache only after its sum matches. It is first
  downloaded beside its place, then renamed into it.
- A verified file is never overwritten. A cached file whose sum does not
  match is reported and left alone; delete it by hand to fetch it again.
- A file with no sum in the manifest is not fetched, unless `--pin` is
  given. Then the first download is trusted, and its sum is written into
  the manifest, so every later fetch must match it.
- An archive (a `.zip`) is verified as a whole, and its members are then
  extracted to the paths the manifest names.
- A file whose URL is null is not hosted yet; its sum is in the manifest.
  It is not fetched. Put the file at its cache path by hand, and the
  next fetch verifies it and extracts it.
- A Google Drive share link is downloaded through Drive's download link.
  A web page sent in place of a file is refused.
- With `--offline`, fetch uses only pinned files already in the cache.
  It verifies archives before extracting missing members and never opens
  a URL. Missing or unpinned files fail the command, as do mismatches.
- With `--strict`, verify fails for missing or unpinned files as well as
  mismatches. Both commands can select entries by id.
"""

comptime MAIN_USAGE = """usage: carla_assets [-h] [--manifest MANIFEST] [--cache CACHE]
                    {check,status,fetch,verify,credits,stage-render,stage-archive}
                    ...
"""
"""The usage text of the main parser."""

comptime MAIN_HELP_TAIL = """
positional arguments:
  {check,status,fetch,verify,credits,stage-render,stage-archive}
    check               check the manifest against its rules
    status              show which entries the cache holds
    fetch               download and verify entries
    verify              re-hash the cached files
    credits             print the attribution list
    stage-render        copy named renders and credits into a new directory
    stage-archive       copy pinned archives, the manifest and credits into a
                        new directory

options:
  -h, --help            show this help message and exit
  --manifest MANIFEST
  --cache CACHE
"""
"""The main help after the description."""


# --- The command line, as argparse reads it -------------------------------------------


@fieldwise_init
struct _Option(Copyable, Movable):
    """One optional argument."""

    var names: List[String]
    """Its option strings, such as `-h` and `--help`."""
    var dest: String
    """Where its value goes."""
    var takes_value: Bool
    """True for an option with one value; False for a flag."""
    var required: Bool
    """True when the command line must give it."""
    var group: Int
    """Its mutually exclusive group, or -1."""


@fieldwise_init
struct _Parser(Copyable, Movable):
    """One parser: its options, its positional argument and its texts."""

    var prog: String
    """The program name in its errors."""
    var usage: String
    """Its usage text, with the final newline."""
    var help: String
    """Its help text after the usage."""
    var options: List[_Option]
    """Its options, `-h` first."""
    var positional: String
    """The positional argument's name, or empty."""
    var nargs: String
    """`*`, `+` or `A...` for a subcommand."""


struct Arguments(Movable):
    """The parsed command line, or the text to print and the status."""

    var status: Int
    """0 to run, or the exit status: 0 after help, 2 after an error."""
    var done: Bool
    """True when the command line was handled by printing `message`."""
    var message: String
    """The help, for the standard output, or the error, for the standard
    error."""
    var values: Dict[String, String]
    """Each option with a value."""
    var flags: List[String]
    """Each flag given."""
    var items: List[String]
    """The positional values of the subcommand."""
    var command: String
    """The subcommand."""

    def __init__(out self):
        """Make an empty result."""
        self.status = 0
        self.done = False
        self.message = String()
        self.values = Dict[String, String]()
        self.flags = List[String]()
        self.items = List[String]()
        self.command = String()

    def flag(self, name: String) -> Bool:
        """Return whether a flag was given.

        Args:
            name: The flag's destination, such as `pin`.

        Returns:
            True when the command line gave it.
        """
        for flag in self.flags:
            if flag == name:
                return True
        return False


def _help_option() -> _Option:
    """Return the `-h` option."""
    return _Option(["-h", "--help"], "help", False, False, -1)


def _subparser(command: String) -> _Parser:
    """Return the parser of one subcommand."""
    var prog = PROGRAM + " " + command
    var options: List[_Option] = [_help_option()]
    if command == "fetch":
        options.append(_Option(["--pin"], "pin", False, False, 0))
        options.append(_Option(["--offline"], "offline", False, False, 0))
        return _Parser(
            prog,
            "usage: carla_assets fetch [-h] [--pin | --offline] [ids ...]\n",
            (
                "\npositional arguments:\n  ids\n\noptions:\n  -h, --help "
                " show this help message and exit\n  --pin       trust the"
                " first download of a file with no sum, and record its\n     "
                "         sum\n  --offline   verify and extract cached files"
                " only; fail if missing or\n              unpinned\n"
            ),
            options^,
            "ids",
            "*",
        )
    if command == "verify":
        options.append(_Option(["--strict"], "strict", False, False, -1))
        return _Parser(
            prog,
            "usage: carla_assets verify [-h] [--strict] [ids ...]\n",
            (
                "\npositional arguments:\n  ids\n\noptions:\n  -h, --help "
                " show this help message and exit\n  --strict    also fail"
                " when a selected file is missing or unpinned\n"
            ),
            options^,
            "ids",
            "*",
        )
    if command == "credits":
        options.append(_Option(["--all"], "all", False, False, -1))
        options.append(_Option(["--output"], "output", True, False, -1))
        return _Parser(
            prog,
            "usage: carla_assets credits [-h] [--all] [--output OUTPUT]\n",
            (
                "\noptions:\n  -h, --help       show this help message and"
                " exit\n  --all            also credit the CC0 entries\n "
                " --output OUTPUT\n"
            ),
            options^,
            "",
            "",
        )
    if command == "stage-render":
        options.append(_Option(["--output"], "output", True, True, -1))
        return _Parser(
            prog,
            (
                "usage: carla_assets stage-render [-h] --output OUTPUT\n     "
                "                            render_files [render_files"
                " ...]\n"
            ),
            (
                "\npositional arguments:\n  render_files\n\noptions:\n  -h,"
                " --help       show this help message and exit\n  --output"
                " OUTPUT\n"
            ),
            options^,
            "render_files",
            "+",
        )
    if command == "stage-archive":
        options.append(_Option(["--output"], "output", True, True, -1))
        return _Parser(
            prog,
            (
                "usage: carla_assets stage-archive [-h] --output OUTPUT ids"
                " [ids ...]\n"
            ),
            (
                "\npositional arguments:\n  ids\n\noptions:\n  -h, --help    "
                "   show this help message and exit\n  --output OUTPUT\n"
            ),
            options^,
            "ids",
            "+",
        )
    return _Parser(
        prog,
        "usage: carla_assets " + command + " [-h]\n",
        "\noptions:\n  -h, --help  show this help message and exit\n",
        options^,
        "",
        "",
    )


def _main_parser() -> _Parser:
    """Return the main parser."""
    var options: List[_Option] = [
        _help_option(),
        _Option(["--manifest"], "manifest", True, False, -1),
        _Option(["--cache"], "cache", True, False, -1),
    ]
    return _Parser(
        PROGRAM,
        MAIN_USAGE,
        "\n" + _DESCRIPTION + MAIN_HELP_TAIL,
        options^,
        "command",
        "A...",
    )


def _negative_number(word: String) -> Bool:
    """Return whether a word matches argparse's `^-\\d+$|^-\\d*\\.\\d+$`."""
    var bytes = word.as_bytes()
    if len(bytes) < 2 or bytes[0] != 0x2D:
        return False
    var at = 1
    var digits = 0
    while at < len(bytes) and bytes[at] >= 0x30 and bytes[at] <= 0x39:
        at += 1
        digits += 1
    if at == len(bytes):
        return digits > 0
    if bytes[at] != 0x2E:
        return False
    at += 1
    var after = 0
    while at < len(bytes) and bytes[at] >= 0x30 and bytes[at] <= 0x39:
        at += 1
        after += 1
    return at == len(bytes) and after > 0


@fieldwise_init
struct _Match(Copyable, Movable):
    """One reading of an option string."""

    var option: Int
    """The option's index, or -1 for an unknown option."""
    var text: String
    """The option string it matched."""
    var sep: String
    """`=`, empty, or `None` as `\\x00`."""
    var explicit: String
    """The explicit argument."""
    var has_explicit: Bool
    """Whether there is one."""


def _parse_optional(parser: _Parser, word: String) -> List[_Match]:
    """Return argparse's readings of a word; none means a positional."""
    var out = List[_Match]()
    if word.byte_length() == 0 or not word.startswith("-"):
        return out^
    for index in range(len(parser.options)):
        for name in parser.options[index].names:
            if name == word:
                out.append(_Match(index, name, "\x00", "", False))
                return out^
    if word.byte_length() == 1:
        return out^
    var equals = word.find("=")
    if equals >= 0:
        var head = String(word[byte=:equals])
        var tail = String(word[byte = equals + 1 :])
        for index in range(len(parser.options)):
            for name in parser.options[index].names:
                if name == head:
                    out.append(_Match(index, name, "=", tail, True))
                    return out^
    if word.startswith("--"):
        var prefix = word
        var sep = String("\x00")
        var explicit = String()
        var has = False
        if equals >= 0:
            prefix = String(word[byte=:equals])
            sep = "="
            explicit = String(word[byte = equals + 1 :])
            has = True
        for index in range(len(parser.options)):
            for name in parser.options[index].names:
                if name.startswith(prefix):
                    out.append(_Match(index, name, sep, explicit, has))
    else:
        var prefix = String(word[byte=:equals]) if equals >= 0 else word
        var short = String(word[byte=:2])
        var short_explicit = String(word[byte=2:])
        for index in range(len(parser.options)):
            for name in parser.options[index].names:
                if name == short:
                    out.append(_Match(index, name, "", short_explicit, True))
                elif name.startswith(prefix):
                    if equals >= 0:
                        out.append(
                            _Match(
                                index,
                                name,
                                "=",
                                String(word[byte = equals + 1 :]),
                                True,
                            )
                        )
                    else:
                        out.append(_Match(index, name, "\x00", "", False))
    if len(out) > 0:
        return out^
    if _negative_number(word) or word.find(" ") >= 0:
        return out^
    out.append(_Match(-1, word, "\x00", "", False))
    return out^


def _option_label(option: _Option) -> String:
    """Return argparse's name for an option in an error."""
    return "/".join(option.names)


struct _State(Movable):
    """The work of one parse."""

    var pattern: List[String]
    """`A`, `O` or `-` for each word."""
    var readings: List[List[_Match]]
    """The readings of each word; empty for a positional one."""
    var seen: List[Int]
    """The options seen; -2 is the positional."""
    var chosen: List[Int]
    """The options given with a value, for mutual exclusion."""
    var extras: List[String]
    """The words no argument took."""
    var positional_done: Bool
    """Whether the positional argument has its values."""

    def __init__(out self):
        self.pattern = List[String]()
        self.readings = List[List[_Match]]()
        self.seen = List[Int]()
        self.chosen = List[Int]()
        self.extras = List[String]()
        self.positional_done = False


def _error(parser: _Parser, message: String) -> Arguments:
    """Return a usage error."""
    var out = Arguments()
    out.status = 2
    out.done = True
    out.message = parser.usage + parser.prog + ": error: " + message + "\n"
    return out^


def _help(parser: _Parser) -> Arguments:
    """Return the help."""
    var out = Arguments()
    out.status = 0
    out.done = True
    out.message = parser.usage + parser.help
    return out^


def _take_option(
    parser: _Parser,
    mut state: _State,
    mut result: Arguments,
    index: Int,
    value: Optional[String],
) -> Optional[Arguments]:
    """Record an option; return a finished result for help or an error."""
    var option = parser.options[index].copy()
    state.seen.append(index)
    for other in state.chosen:
        if (
            option.group >= 0
            and other != index
            and parser.options[other].group == option.group
        ):
            return _error(
                parser,
                "argument "
                + _option_label(option)
                + ": not allowed with argument "
                + _option_label(parser.options[other]),
            )
    state.chosen.append(index)
    if option.dest == "help":
        return _help(parser)
    if option.takes_value:
        result.values[option.dest] = value.value()
    else:
        result.flags.append(option.dest)
    return None


def _positional_count(parser: _Parser, state: _State, start: Int) -> Int:
    """Return how many words the positional argument takes from `start`,
    or -1 when its pattern does not match there."""
    ref pattern = state.pattern
    var at = start
    while at < len(pattern) and pattern[at] == "-":
        at += 1
    if parser.nargs == "A...":
        if at >= len(pattern) or pattern[at] != "A":
            return -1
        return len(pattern) - start
    if parser.nargs == "+":
        if at >= len(pattern) or pattern[at] != "A":
            return -1
    var end = at
    while end < len(pattern) and (pattern[end] == "A" or pattern[end] == "-"):
        end += 1
    var count = end - start
    if count == 0 and end < len(pattern) and pattern[end] == "O":
        # `_match_arguments_partial` drops an empty match before an option.
        return -1
    return count


def _parse(
    parser: _Parser, arguments: List[String], mut result: Arguments
) -> Optional[Arguments]:
    """Parse one parser's words into `result`; return a finished result for
    help or an error. Unclaimed words go to `result.items` of the extras."""
    var state = _State()
    var double_dash = False
    for index in range(len(arguments)):
        var word = arguments[index]
        if double_dash:
            state.pattern.append("A")
            state.readings.append(List[_Match]())
        elif word == "--":
            state.pattern.append("-")
            state.readings.append(List[_Match]())
            double_dash = True
        else:
            var readings = _parse_optional(parser, word)
            if len(readings) == 0:
                state.pattern.append("A")
            else:
                state.pattern.append("O")
            state.readings.append(readings^)
    var options = List[Int]()
    for index in range(len(state.pattern)):
        if state.pattern[index] == "O":
            options.append(index)
    var last = options[len(options) - 1] if len(options) > 0 else -1
    var start = 0

    while start <= last:
        var next = start
        for index in options:
            if index >= start:
                next = index
                break
        if start != next:
            var stop = start
            if not state.positional_done and parser.positional:
                var count = _positional_count(parser, state, start)
                if count >= 0:
                    var done = _take_positional(
                        parser, state, result, arguments, start, count
                    )
                    if done:
                        return done^
                    stop = start + count
            if stop > start:
                start = stop
                continue
        if not _in(options, start):
            for index in range(start, next):
                state.extras.append(arguments[index])
            start = next
        # Consume the option at `start`.
        var readings = state.readings[start].copy()
        if len(readings) > 1:
            var names = List[String]()
            for reading in readings:
                names.append(reading.text)
            return _error(
                parser,
                "ambiguous option: "
                + arguments[start]
                + " could match "
                + ", ".join(names),
            )
        var reading = readings[0].copy()
        if reading.option < 0:
            state.extras.append(arguments[start])
            start += 1
            continue
        var option = parser.options[reading.option].copy()
        if reading.has_explicit:
            if option.takes_value:
                var done = _take_option(
                    parser, state, result, reading.option, reading.explicit
                )
                if done:
                    return done^
                start += 1
                continue
            var explicit = reading.explicit
            if not reading.text.startswith("--") and explicit.byte_length() > 0:
                if reading.sep == "=" or explicit.startswith("-"):
                    return _error(
                        parser,
                        "argument "
                        + _option_label(option)
                        + ": ignored explicit argument "
                        + py_repr(explicit),
                    )
                # `-hx`: the help runs before `x` is read.
                var done = _take_option(
                    parser, state, result, reading.option, None
                )
                if done:
                    return done^
                state.extras.append("-" + explicit)
                start += 1
                continue
            return _error(
                parser,
                "argument "
                + _option_label(option)
                + ": ignored explicit argument "
                + py_repr(explicit),
            )
        if option.takes_value:
            if (
                start + 1 >= len(state.pattern)
                or state.pattern[start + 1] != "A"
            ):
                return _error(
                    parser,
                    "argument "
                    + _option_label(option)
                    + ": expected one argument",
                )
            var done = _take_option(
                parser, state, result, reading.option, arguments[start + 1]
            )
            if done:
                return done^
            start += 2
        else:
            var done = _take_option(parser, state, result, reading.option, None)
            if done:
                return done^
            start += 1
    var stop = start
    if not state.positional_done and parser.positional:
        var count = _positional_count(parser, state, start)
        if count >= 0:
            var done = _take_positional(
                parser, state, result, arguments, start, count
            )
            if done:
                return done^
            stop = start + count
    for index in range(stop, len(arguments)):
        state.extras.append(arguments[index])
    var required = List[String]()
    for index in range(len(parser.options)):
        if parser.options[index].required and not _in(state.seen, index):
            required.append(_option_label(parser.options[index]))
    if parser.positional and parser.nargs != "*" and not state.positional_done:
        required.append(parser.positional)
    if len(required) > 0:
        return _error(
            parser,
            "the following arguments are required: " + ", ".join(required),
        )
    for extra in state.extras:
        result.items.append("\x00" + extra)
    return None


def _in(items: List[Int], value: Int) -> Bool:
    """Return whether a list holds a value."""
    for item in items:
        if item == value:
            return True
    return False


def _take_positional(
    parser: _Parser,
    mut state: _State,
    mut result: Arguments,
    arguments: List[String],
    start: Int,
    count: Int,
) -> Optional[Arguments]:
    """Record the positional values; for a subcommand, parse its words."""
    state.positional_done = True
    var values = List[String]()
    for index in range(start, start + count):
        values.append(arguments[index])
    var dash = False
    for index in range(start, start + count):
        if state.pattern[index] == "-":
            dash = True
    if parser.nargs == "A...":
        if state.pattern[start] == "-":
            _ = values.pop(0)
        var command = values[0]
        var known = False
        for name in materialize[COMMANDS]():
            if name == command:
                known = True
        if not known:
            return _error(
                parser,
                "argument command: invalid choice: "
                + py_repr(command)
                + " (choose from "
                + ", ".join(materialize[COMMANDS]())
                + ")",
            )
        result.command = command
        var rest = List[String]()
        for index in range(1, len(values)):
            rest.append(values[index])
        var sub = _subparser(command)
        var done = _parse(sub, rest, result)
        if done:
            return done^
        return None
    if dash:
        for index in range(len(values)):
            if values[index] == "--":
                _ = values.pop(index)
                break
    for value in values:
        result.items.append(value)
    return None


def parse_arguments(arguments: List[String]) -> Arguments:
    """Read a command line as the Python tool's argparse parser reads it.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The values, or the help or error text with its exit status.
    """
    var parser = _main_parser()
    var result = Arguments()
    var done = _parse(parser, arguments, result)
    if done:
        return done.take()
    var items = List[String]()
    var extras = List[String]()
    for item in result.items:
        if item.startswith("\x00"):
            extras.append(String(item[byte=1:]))
        else:
            items.append(item)
    result.items = items^
    if len(extras) > 0:
        return _error(parser, "unrecognized arguments: " + " ".join(extras))
    return result^


# --- Staging ------------------------------------------------------------------------------


trait StageHooks:
    """Points where a test can act as a racing process would.

    Each method runs at one moment of staging. The command line uses
    `NoHooks`, whose methods do nothing.
    """

    def before_mkdir(mut self, output: String) raises:
        """Run before the output directory is made.

        Args:
            output: The output directory.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def after_mkdir(mut self, output: String) raises:
        """Run after the output directory is made.

        Args:
            output: The output directory.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def before_source_open(mut self, path: String) raises:
        """Run after an input is checked and before it is opened.

        Args:
            path: The input.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def before_write(mut self, name: String) raises:
        """Run before an output file is created.

        Args:
            name: The file's name in its directory.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def before_copy(mut self, name: String, fd: Int) raises:
        """Run after an output file is created and before its bytes go in.

        Args:
            name: The file's name in its directory.
            fd: The open output file.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def after_write(mut self, name: String) raises:
        """Run after an output file is written and closed.

        Args:
            name: The file's name in its directory.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def after_child_mkdir(mut self, relative: String) raises:
        """Run after a folder inside the output is made.

        Args:
            relative: The folder, relative to the output.

        Raises:
            Error: To fail at this moment.
        """
        ...

    def before_child_open(mut self, relative: String) raises:
        """Run after a new folder is checked and before it is opened.

        Args:
            relative: The folder, relative to the output.

        Raises:
            Error: To fail at this moment.
        """
        ...


struct NoHooks(StageHooks):
    """Staging as the command line runs it: no hook acts."""

    def __init__(out self):
        """Make the hooks."""
        pass

    def before_mkdir(mut self, output: String) raises:
        """Do nothing.

        Args:
            output: The output directory.

        Raises:
            Error: Never.
        """
        pass

    def after_mkdir(mut self, output: String) raises:
        """Do nothing.

        Args:
            output: The output directory.

        Raises:
            Error: Never.
        """
        pass

    def before_source_open(mut self, path: String) raises:
        """Do nothing.

        Args:
            path: The input.

        Raises:
            Error: Never.
        """
        pass

    def before_write(mut self, name: String) raises:
        """Do nothing.

        Args:
            name: The file's name.

        Raises:
            Error: Never.
        """
        pass

    def before_copy(mut self, name: String, fd: Int) raises:
        """Do nothing.

        Args:
            name: The file's name.
            fd: The open output file.

        Raises:
            Error: Never.
        """
        pass

    def after_write(mut self, name: String) raises:
        """Do nothing.

        Args:
            name: The file's name.

        Raises:
            Error: Never.
        """
        pass

    def after_child_mkdir(mut self, relative: String) raises:
        """Do nothing.

        Args:
            relative: The folder.

        Raises:
            Error: Never.
        """
        pass

    def before_child_open(mut self, relative: String) raises:
        """Do nothing.

        Args:
            relative: The folder.

        Raises:
            Error: Never.
        """
        pass


def _stage_error(text: String) -> Error:
    """Return a `StageError`."""
    return Error("StageError: " + text)


def casefold(text: String) -> String:
    """Return `str.casefold()` for the scripts a file name uses most.

    ASCII, Latin-1, Latin Extended-A, Greek and Cyrillic capitals become
    small letters, and `ß` becomes `ss`. Other characters stay.

    Args:
        text: The str.

    Returns:
        The folded str.
    """
    var out = String()
    for point in code_points(text, False):
        var folded = point
        if point >= 0x41 and point <= 0x5A:
            folded = point + 0x20
        elif (point >= 0xC0 and point <= 0xDE) and point != 0xD7:
            folded = point + 0x20
        elif point == 0xDF:
            out += "ss"
            continue
        elif point == 0xB5:
            folded = 0x3BC
        elif point >= 0x100 and point <= 0x17F:
            if point == 0x130 or point == 0x131 or point == 0x138:
                folded = point
            elif point == 0x149 or point == 0x17F:
                folded = point
            elif (point >= 0x139 and point <= 0x148) or (
                point >= 0x179 and point <= 0x17E
            ):
                folded = point + 1 if point % 2 == 1 else point
            elif point == 0x178:
                folded = 0xFF
            else:
                folded = point + 1 if point % 2 == 0 else point
        elif point >= 0x391 and point <= 0x3AB and point != 0x3A2:
            folded = point + 0x20
        elif point == 0x3C2:
            folded = 0x3C3
        elif point >= 0x410 and point <= 0x42F:
            folded = point + 0x20
        elif point >= 0x400 and point <= 0x40F:
            folded = point + 0x50
        if folded >= 0xD800 and folded <= 0xDFFF:
            out += "�"
        else:
            out += chr(folded)
    return out^


def _stage_source[H: StageHooks](path: String, mut hooks: H) raises -> Int:
    """Open a regular, non-symlink input without following a replaced link."""
    var before = lstat_id(path)
    if not before.is_regular():
        raise _stage_error(
            path + ": expected a regular file, not a directory or symlink"
        )
    hooks.before_source_open(path)
    var fd = open_path(path, o_rdonly() | o_nofollow_flag() | o_nonblock())
    try:
        if not before.same(fstat_id(fd)):
            raise _stage_error(path + ": input changed while opening it")
    except error:
        close_fd(fd)
        raise error^
    return fd


def _copy_fd(source: Int, target: Int, mut digest: Sha256) raises:
    """Copy a descriptor to its end into another, hashing the bytes."""
    while True:
        var block = read_some(source, CHUNK)
        if len(block) == 0:
            return
        digest.update(Span(block))
        write_all(target, Span(block))


def _stage_write[
    H: StageHooks
](directory: Int, name: String, source: Int, mut hooks: H) raises -> String:
    """Create one output exclusively from an open input, without following a
    racing symlink, and return the SHA-256 of the bytes copied."""
    hooks.before_write(name)
    var fd = open_at(
        directory,
        name,
        o_wronly() | o_creat() | o_excl() | o_nofollow_flag(),
        0o666,
    )
    var digest = Sha256()
    try:
        hooks.before_copy(name, fd)
        _copy_fd(source, fd, digest)
    finally:
        close_fd(fd)
    hooks.after_write(name)
    return digest^.hexdigest()


def _stage_write_bytes[
    H: StageHooks
](directory: Int, name: String, data: List[UInt8], mut hooks: H) raises:
    """Create one output exclusively from bytes."""
    hooks.before_write(name)
    var fd = open_at(
        directory,
        name,
        o_wronly() | o_creat() | o_excl() | o_nofollow_flag(),
        0o666,
    )
    try:
        hooks.before_copy(name, fd)
        write_all(fd, Span(data))
    finally:
        close_fd(fd)
    hooks.after_write(name)


struct _Snapshot(Movable):
    """One manifest read once: its bytes and the checked value."""

    var data: List[UInt8]
    """The exact bytes."""
    var doc: PyJson
    """The manifest parsed from them."""

    def __init__(out self, var data: List[UInt8], var doc: PyJson):
        self.data = data^
        self.doc = doc^


def _stage_snapshot[
    H: StageHooks
](manifest_path: String, mut hooks: H, mut fds: List[Int]) raises -> _Snapshot:
    """Read, parse and check one manifest snapshot; its input stays open in
    `fds`."""
    var fd = _stage_source(path_text(manifest_path), hooks)
    fds.append(fd)
    var data = read_all(fd)
    var doc = read_json_text(data)
    check_manifest(doc, doc.root)
    return _Snapshot(data^, doc^)


def _output_exists(output: String) raises:
    """Refuse an output that already exists, even as a dangling link."""
    if path_exists(output) or path_is_link(output):
        raise _stage_error(path_text(output) + ": output already exists")


def _stage_begin[H: StageHooks](output: String, mut hooks: H) raises:
    """Make the new output directory; an error here is not wrapped."""
    hooks.before_mkdir(output)
    make_dir(output)
    hooks.after_mkdir(output)


def _incomplete(error: Error, output: String) raises -> Error:
    """Return the error of a staging that failed after its directory was
    made."""
    return _stage_error(
        exception_text(error)
        + "; staging incomplete; retained output at "
        + absolute_text(output)
        + " for manual inspection"
    )


def _open_output(output: String) raises -> Tuple[FileId, Int]:
    """Open the new output directory and check it is the one made."""
    var identity = lstat_id(output)
    var directory = open_path(output, o_rdonly() | o_dir() | o_nofollow_flag())
    if not identity.same(fstat_id(directory)):
        close_fd(directory)
        raise _stage_error(output + ": output changed while opening it")
    return (identity, directory)


def stage_render[
    H: StageHooks
](
    manifest_path: String,
    output: String,
    render_files: List[String],
    mut hooks: H,
) raises:
    """Copy named renders and one manifest snapshot into a new directory.

    Args:
        manifest_path: The manifest that corresponds to these renders.
        output: A directory that must not already exist. Its parent must.
        render_files: Explicit regular, non-symlink files to copy by
            basename.
        hooks: Points where a test acts; `NoHooks` for the command line.

    Raises:
        Error: `StageError` text if inputs collide, change identity, or
            staging is incomplete; a `ManifestError`, decoding error or
            `OSError` from the inputs or the new directory.
    """
    var target = path_text(output)
    _output_exists(output)
    var fds = List[Int]()
    try:
        var snapshot = _stage_snapshot(manifest_path, hooks, fds)
        var attribution = credits(
            snapshot.doc, entries_of(snapshot.doc, snapshot.doc.root), True
        )
        var names: List[String] = ["manifest.json", "attribution.md"]
        var identities = List[FileId]()
        var sources = List[Tuple[String, Int]]()
        for value in render_files:
            var path = path_text(value)
            var name = casefold(path_name(value))
            for known in names:
                if known == name:
                    raise _stage_error(
                        path + ": duplicate or reserved output basename"
                    )
            names.append(name)
            var fd = _stage_source(path, hooks)
            fds.append(fd)
            var info = fstat_id(fd)
            for known in identities:
                if known.same(info):
                    raise _stage_error(path + ": duplicate input file")
            identities.append(info)
            sources.append((path_name(value), fd))
        if len(sources) == 0:
            raise _stage_error("at least one render file is required")
        _stage_begin(target, hooks)
        var directory = -1
        try:
            var opened = _open_output(target)
            directory = opened[1]
            for source in sources:
                _ = _stage_write(directory, source[0], source[1], hooks)
            _stage_write_bytes(directory, "manifest.json", snapshot.data, hooks)
            var text = List[UInt8](attribution.as_bytes())
            _stage_write_bytes(directory, "ATTRIBUTION.md", text, hooks)
            if not lstat_id(target).same(opened[0]):
                raise _stage_error(target + ": output changed while staging it")
        except error:
            raise _incomplete(error, target)
        finally:
            if directory >= 0:
                close_fd(directory)
    finally:
        for fd in fds:
            close_fd(fd)


def _key(parts: List[String], depth: Int, fold: Bool) -> String:
    """Return the first `depth` parts as one key."""
    var out = String()
    for index in range(depth):
        if index > 0:
            out += "\x00"
        out += casefold(parts[index]) if fold else parts[index]
    return out^


def _stage_claim(mut claimed: Dict[String, String], parts: List[String]) raises:
    """Reserve one output file path and its parent directories."""
    for depth in range(1, len(parts) + 1):
        var kind = "file" if depth == len(parts) else "directory"
        var key = _key(parts, depth, True)
        var wanted = kind + "\x01" + _key(parts, depth, False)
        if key in claimed and (kind == "file" or claimed[key] != wanted):
            raise _stage_error(
                "/".join(parts)
                + ": the output path clashes with another staged or reserved"
                " path"
            )
        claimed[key] = wanted


struct _Folders(Movable):
    """The folders made in the output, each with its open descriptor."""

    var keys: List[String]
    """Each folder's parts joined by `/`; the output itself is empty."""
    var fds: List[Int]
    """Each folder's descriptor."""

    def __init__(out self, directory: Int):
        self.keys = [""]
        self.fds = [directory]

    def find(self, key: String) -> Int:
        """Return a folder's descriptor, or -1."""
        for index in range(len(self.keys)):
            if self.keys[index] == key:
                return self.fds[index]
        return -1

    def check(self) raises:
        """Refuse a folder whose name no longer names its descriptor."""
        for index in range(1, len(self.keys)):
            var key = self.keys[index]
            var cut = key.rfind("/")
            var parent = String(key[byte=:cut]) if cut >= 0 else String()
            var name = String(key[byte = cut + 1 :])
            var current = stat_at(self.find(parent), name, False)
            if not current.same(fstat_id(self.fds[index])):
                raise _stage_error(
                    key + ": output directory changed while staging it"
                )

    def close(self):
        """Close every folder but the output itself."""
        for index in range(1, len(self.fds)):
            close_fd(self.fds[index])


def stage_archive[
    H: StageHooks
](
    manifest_path: String,
    cache: String,
    output: String,
    ids: List[String],
    mut hooks: H,
) raises:
    """Copy the pinned archives of named entries, one manifest snapshot and
    their attribution into a new directory.

    Each archive keeps its cache path under the new directory, so the
    directory can serve as a cache root for `fetch --offline`.

    Args:
        manifest_path: The manifest whose sums pin the archives.
        cache: The cache root that holds the archives.
        output: A directory that must not already exist.
        ids: Explicit entry ids; each entry must have at least one archive.
        hooks: Points where a test acts; `NoHooks` for the command line.

    Raises:
        Error: `StageError` text if an id repeats, an entry has no archive,
            an archive is unpinned, a sum differs, paths collide, inputs
            change identity, or staging is incomplete; a `ManifestError`,
            decoding error or `OSError` otherwise.
    """
    var target = path_text(output)
    _output_exists(output)
    var fds = List[Int]()
    try:
        var snapshot = _stage_snapshot(manifest_path, hooks, fds)
        if len(ids) == 0:
            raise _stage_error("at least one entry id is required")
        for i in range(len(ids)):
            for j in range(i + 1, len(ids)):
                if ids[i] == ids[j]:
                    raise _stage_error("each entry id must be named once")
        ref doc = snapshot.doc
        var entries = selected_entries(doc, doc.root, ids)
        var attribution = credits(doc, entries, True)
        var claimed = Dict[String, String]()
        _stage_claim(claimed, ["manifest.json"])
        _stage_claim(claimed, ["ATTRIBUTION.md"])
        var parts_of = List[List[String]]()
        var sources = List[Int]()
        var sums = List[String]()
        for entry in entries:
            var files = doc.get(entry, "files")
            var archives = List[Int]()
            for index in range(doc.length(files)):
                var item = doc.item(files, index)
                var role = doc.get(item, "role")
                if doc.text(role) == "archive":
                    archives.append(item)
            if len(archives) == 0:
                raise _stage_error(
                    doc.text(doc.get(entry, "id"))
                    + ": the entry has no archive to stage"
                )
            for item in archives:
                var relative = doc.text(doc.get(item, "path"))
                var expected = doc.get(item, "sha256")
                if doc.is_none(expected):
                    raise _stage_error(
                        relative + ": the archive has no pinned sha256"
                    )
                var parts = path_parts(relative)
                _stage_claim(claimed, parts)
                var path = join_path(path_text(cache), relative)
                var fd = _stage_source(path, hooks)
                fds.append(fd)
                var digest = Sha256()
                while True:
                    var block = read_some(fd, CHUNK)
                    if len(block) == 0:
                        break
                    digest.update(Span(block))
                var found = digest^.hexdigest()
                if found != doc.text(expected):
                    raise _stage_error(
                        path
                        + ": sha256 "
                        + found
                        + " does not match the pinned "
                        + doc.text(expected)
                    )
                seek_start(fd)
                parts_of.append(parts^)
                sources.append(fd)
                sums.append(doc.text(expected))
        _stage_begin(target, hooks)
        var directory = -1
        try:
            var opened = _open_output(target)
            directory = opened[1]
            var folders = _Folders(directory)
            try:
                for index in range(len(sources)):
                    ref parts = parts_of[index]
                    folders.check()
                    for depth in range(1, len(parts)):
                        var key = "/".join(parts[:depth])
                        if folders.find(key) < 0:
                            var parent = folders.find(
                                "/".join(parts[: depth - 1])
                            )
                            var name = parts[depth - 1]
                            make_dir_at(parent, name)
                            hooks.after_child_mkdir(key)
                            var identity = stat_at(parent, name, False)
                            hooks.before_child_open(key)
                            var fd = open_at(
                                parent,
                                name,
                                o_rdonly() | o_dir() | o_nofollow_flag(),
                            )
                            folders.keys.append(key)
                            folders.fds.append(fd)
                            if not identity.same(fstat_id(fd)):
                                raise _stage_error(
                                    key + ": output changed while opening it"
                                )
                    folders.check()
                    var holder = folders.find("/".join(parts[: len(parts) - 1]))
                    var found = _stage_write(
                        holder, parts[len(parts) - 1], sources[index], hooks
                    )
                    folders.check()
                    if found != sums[index]:
                        raise _stage_error(
                            "/".join(parts)
                            + ": sha256 "
                            + found
                            + " changed from the pinned "
                            + sums[index]
                            + " while staging it"
                        )
                _stage_write_bytes(
                    directory, "manifest.json", snapshot.data, hooks
                )
                var text = List[UInt8](attribution.as_bytes())
                _stage_write_bytes(directory, "ATTRIBUTION.md", text, hooks)
                folders.check()
            finally:
                folders.close()
            if not lstat_id(target).same(opened[0]):
                raise _stage_error(target + ": output changed while staging it")
        except error:
            raise _incomplete(error, target)
        finally:
            if directory >= 0:
                close_fd(directory)
    finally:
        for fd in fds:
            close_fd(fd)


# --- Running a command ---------------------------------------------------------------------


struct Outcome(Movable):
    """What a command line printed and its exit status."""

    var status: Int
    """The exit status."""
    var out: String
    """The standard output."""
    var err: String
    """The standard error."""

    def __init__(out self):
        """Make an empty outcome that succeeds."""
        self.status = 0
        self.out = String()
        self.err = String()


def _uncaught(error: Error) -> Bool:
    """Return whether a staging error is one the Python tool did not catch:
    neither an `OSError`, a `ValueError` nor a `StageError`."""
    var text = String(error)
    for name in [
        "KeyError: ",
        "TypeError: ",
        "AttributeError: ",
        "IndexError: ",
        "RecursionError: ",
    ]:
        if text.startswith(name):
            return True
    return False


def run[
    H: StageHooks
](
    arguments: List[String], transport: Transport, mut hooks: H
) raises -> Outcome:
    """Run one command line, as the Python tool's `main(argv)` does.

    Args:
        arguments: The arguments, without the program name.
        transport: How downloads run.
        hooks: The staging hooks; `NoHooks` for the command line.

    Returns:
        The printed texts and the exit status.

    Raises:
        Error: If the working directory cannot be read.
    """
    var outcome = Outcome()
    var args = parse_arguments(arguments)
    if args.done:
        outcome.status = args.status
        if args.status == 0:
            outcome.out = args.message
        else:
            outcome.err = args.message
        return outcome^
    var manifest_path = path_text(
        args.values.get("manifest").or_else(default_manifest())
    )
    var cache = path_text(args.values.get("cache").or_else(default_cache()))
    var command = args.command
    if command == "stage-render" or command == "stage-archive":
        var output = args.values.get("output").or_else("")
        try:
            if command == "stage-render":
                stage_render(manifest_path, output, args.items, hooks)
            else:
                stage_archive(manifest_path, cache, output, args.items, hooks)
        except error:
            outcome.status = 1
            if _uncaught(error):
                outcome.err = exception_line(error) + "\n"
            else:
                outcome.err = command + ": " + exception_text(error) + "\n"
        return outcome^
    try:
        var doc = load_manifest(manifest_path)
        var manifest = doc.root
        if command == "check":
            var bindings = doc.get(manifest, "bindings")
            var count = doc.length(bindings) if bindings >= 0 else 0
            outcome.out = (
                manifest_path
                + ": "
                + String(len(entries_of(doc, manifest)))
                + " entries, "
                + String(count)
                + " bindings, all rules kept\n"
            )
            return outcome^
        if command == "status":
            outcome.out = "\n".join(status_lines(doc, manifest, cache)) + "\n"
            return outcome^
        if command == "fetch":
            var pin = args.flag("pin")
            var offline = args.flag("offline")
            var report: List[Report]
            try:
                report = fetch(
                    doc, manifest, cache, args.items, pin, offline, transport
                )
            finally:
                if pin:
                    save_manifest(doc, manifest, manifest_path)
            var failed = False
            for line in report:
                outcome.out += (
                    pad(line.status, 9)
                    + " "
                    + line.entry_id
                    + ": "
                    + line.path
                    + "\n"
                )
                if line.status == "mismatch" or (
                    offline and line.status != "kept"
                ):
                    failed = True
            outcome.status = 1 if failed else 0
            return outcome^
        if command == "verify":
            var strict = args.flag("strict")
            var failed = False
            for line in verify(doc, manifest, cache, args.items):
                outcome.out += pad(line.status, 9) + " " + line.path + "\n"
                if line.status == "mismatch" or (
                    strict and line.status != "ok"
                ):
                    failed = True
            outcome.status = 1 if failed else 0
            return outcome^
        var text = credits(doc, entries_of(doc, manifest), args.flag("all"))
        var destination = args.values.get("output")
        if destination:
            write_text(path_text(destination.value()), text)
        else:
            outcome.out = text
        return outcome^
    except error:
        outcome.status = 1
        outcome.err += exception_line(error) + "\n"
        return outcome^


def main() raises:
    """Run the command line from the repository root.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var hooks = NoHooks()
    var outcome = run(arguments, Transport(), hooks)
    if outcome.out:
        print(outcome.out, end="")
    if outcome.err:
        print(outcome.err, end="", file=stderr)
    exit(outcome.status)
