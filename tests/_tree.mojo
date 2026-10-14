# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A file tree in a temporary directory, for the tests of the project tools."""

from std.collections import Set
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
