# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A file tree in a temporary directory, for the tests of the project tools."""

from std.collections import Set
from std.os.path import isfile, realpath
from std.pathlib import Path
from std.tempfile import mkdtemp

from tools._imports import mojo_files
from tools._process import ProcessResult, run_program


struct Tree(Movable):
    """Files in a temporary directory."""

    var root: String
    """The directory."""

    def __init__(out self) raises:
        """Make an empty directory."""
        self.root = mkdtemp(prefix="test tool tree ")

    def write(self, relative: String, text: String) raises:
        """Write a file, and make its directories."""
        var slash = relative.rfind("/")
        if slash > 0:
            _ = run_program(
                [
                    "mkdir",
                    "-p",
                    self.root + "/" + String(relative[byte=:slash]),
                ],
                10,
            )
        Path(self.root + "/" + relative).write_text(text)

    def remove(self, relative: String) raises:
        """Remove a file."""
        _ = run_program(["rm", "-f", self.root + "/" + relative], 10)

    def known(self) -> Set[String]:
        """Return the tree's `.mojo` files."""
        var found = Set[String]()
        for path in mojo_files(self.root):
            found.add(path)
        return found^

    def read(self, relative: String) raises -> String:
        """Return a file's text."""
        return Path(self.root + "/" + relative).read_text()

    def git(self, arguments: List[String]) raises -> ProcessResult:
        """Run git in the tree, which must succeed."""
        var command: List[String] = [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.invalid",
            "-c",
            "commit.gpgsign=false",
        ]
        command.extend(arguments.copy())
        var result = run_program(command, 30, directory=self.root)
        if result.status != 0:
            raise Error("git failed: " + result.output)
        return result^

    def commit(self) raises:
        """Commit every file, in a new repository the first time."""
        if not Path(self.root + "/.git").exists():
            _ = self.git(["init", "-q"])
        _ = self.git(["add", "-A"])
        _ = self.git(["commit", "-qm", "fixture", "--allow-empty"])

    def close(self) raises:
        """Remove the tree. A test calls it last, which also keeps the tree
        alive until the test ends."""
        _ = run_program(["rm", "-rf", self.root], 10)


def tool_mojo() raises -> String:
    """Return the compiler that builds the project tools, as the Makefile's
    `TOOL_MOJO` chooses it, with an absolute path."""
    if isfile(".venv/bin/mojo"):
        return realpath(".venv/bin/mojo")
    return "mojo"


def copy_suite_runner(
    tree: Tree, var extra: List[String] = List[String]()
) raises:
    """Give a project the built suite runner and the files it runs.

    The runner is built once in the repository. The project gets it and its
    sources with their times, so `tools/tool.sh` there does not build again.

    Args:
        tree: The project.
        extra: More repository files to copy into the project's `tools/`.
    """
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "run_suite"], 120
    )
    if built.status != 0:
        raise Error("cannot build the suite runner: " + built.output)
    var copy: List[String] = [
        "cp",
        "-p",
        "tools/tool.sh",
        "tools/run_suite.mojo",
        "tools/_process.mojo",
        "tools/_text.mojo",
    ]
    copy.extend(extra^)
    _ = run_program(
        ["mkdir", "-p", tree.root + "/tools", tree.root + "/.cache"], 10
    )
    copy.append(tree.root + "/tools/")
    var copied = run_program(copy, 10)
    if copied.status != 0:
        raise Error("cannot copy the suite runner: " + copied.output)
    _ = run_program(["cp", "-Rp", ".cache/tools", tree.root + "/.cache/"], 10)
