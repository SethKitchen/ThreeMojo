# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Isolated test paths with explicit ownership at the suite entry point."""

from std.os import getenv, setenv, unsetenv
from std.pathlib import Path, cwd
from std.tempfile import TemporaryDirectory
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)

# Environment values cannot contain NUL. Preserve unset and empty separately.
comptime _UNSET = "\x00"


def _restore(name: String, value: String) -> Bool:
    if value == _UNSET:
        return unsetenv(name)
    return setenv(name, value)


def _validate_root(root: String) raises:
    if not root.startswith("/") or not Path(root).is_dir():
        raise Error(
            "A supplied test root must be an absolute existing directory"
        )


struct TestScratch(Movable):
    """Borrow a runner root or own one directory for a direct suite run.

    Use this context once around the suite's entry point. Nested contexts
    borrow the active root. Only a directory created here is removed.

    Args:
        None.

    Returns:
        A context that restores its environment and removes its own files.

    Raises:
        Error: If creating, selecting, or removing its directory fails.
    """

    var _owned: Optional[TemporaryDirectory]
    var _saved_root: String
    var _saved_tmp: String

    def __init__(out self) raises:
        """Capture the environment without creating a fallback for a runner."""
        self._owned = None
        self._saved_root = getenv("THREEMOJO_TEST_TMPDIR", _UNSET)
        self._saved_tmp = getenv("TMPDIR", _UNSET)

    def __enter__(mut self) raises:
        """Create one private root only when no surrounding owner supplied it.
        """
        if self._saved_root != _UNSET and self._saved_root != "":
            _validate_root(self._saved_root)
            return
        var parent = getenv("TMPDIR", "")
        var directory = Optional[String]()
        if parent != "":
            if not parent.startswith("/"):
                parent = String(cwd()) + "/" + parent
            directory = parent
        self._owned = TemporaryDirectory(
            prefix="threemojo-test-", dir=directory^
        )
        var root = self._owned.value().name
        if not root.startswith("/"):
            root = String(cwd()) + "/" + root
        # Cleanup must keep its identity if the test changes its working directory.
        self._owned.value().name = root
        var selected = setenv("THREEMOJO_TEST_TMPDIR", root)
        var selected_tmp = setenv("TMPDIR", root)
        if not selected or not selected_tmp:
            self.__exit__()
            raise Error("Cannot select the temporary test directory")

    def __exit__(mut self) raises:
        """Restore environment state and remove only the owned directory."""
        if self._owned:
            var restored = _restore("THREEMOJO_TEST_TMPDIR", self._saved_root)
            var restored_tmp = _restore("TMPDIR", self._saved_tmp)
            self._owned.value().__exit__()
            self._owned = None
            if not restored or not restored_tmp:
                raise Error("Cannot restore the temporary test environment")

    def __exit__(mut self, error: Error) raises -> Bool:
        """Clean up after an exception without suppressing the exception."""
        self.__exit__()
        return False


def temporary_path(name: String) raises -> String:
    """Return a file or directory under this suite's temporary root.

    Args:
        name: A relative name. An empty name returns the root with a slash.

    Returns:
        An absolute path inside the active private temporary directory.

    Raises:
        Error: If the root is not an absolute existing directory, no owner
        supplied it, or the name escapes it.
    """
    var root = getenv("THREEMOJO_TEST_TMPDIR", "")
    if root == "":
        raise Error(
            "Use TestScratch at the suite entry point or tools/run_suite.py"
        )
    _validate_root(root)
    if (
        name.startswith("/")
        or name.find("\\") >= 0
        or name == ".."
        or name.startswith("../")
        or name.endswith("/..")
        or name.find("/../") >= 0
    ):
        raise Error("A temporary test name must stay inside its root")
    return root + "/" + name


def test_the_owner_provides_an_existing_root() raises:
    assert_true(Path(temporary_path("")).exists())
    assert_true(temporary_path("example.bin").endswith("/example.bin"))


def test_a_temporary_name_cannot_escape_its_root() raises:
    for name in ["/absolute", "..", "../x", "x/..", "x/../y", "x\\y"]:
        with assert_raises(contains="inside its root"):
            _ = temporary_path(name)


def test_no_shared_fallback_is_used_without_an_owner() raises:
    var saved = getenv("THREEMOJO_TEST_TMPDIR", "")
    _ = setenv("THREEMOJO_TEST_TMPDIR", "")
    with assert_raises(contains="Use TestScratch"):
        _ = temporary_path("example.bin")
    _ = setenv("THREEMOJO_TEST_TMPDIR", saved)


def test_nested_contexts_borrow_the_same_root() raises:
    var root = temporary_path("")
    with TestScratch():
        assert_equal(temporary_path(""), root)
        Path(temporary_path("borrowed.bin")).write_text("retained")
    assert_true(Path(root).exists())
    assert_equal(Path(temporary_path("borrowed.bin")).read_text(), "retained")


def test_owned_context_restores_empty_environment_on_success_and_error() raises:
    var saved = getenv("THREEMOJO_TEST_TMPDIR", "")
    var saved_tmp = getenv("TMPDIR", _UNSET)
    _ = setenv("THREEMOJO_TEST_TMPDIR", "")
    var root = String("")
    with TestScratch():
        root = temporary_path("")
        assert_equal(getenv("TMPDIR"), getenv("THREEMOJO_TEST_TMPDIR"))
        Path(temporary_path("fixture.bin")).write_text("owned")
    assert_false(Path(root).exists())
    assert_equal(getenv("THREEMOJO_TEST_TMPDIR", _UNSET), "")
    assert_equal(getenv("TMPDIR", _UNSET), saved_tmp)
    with assert_raises(contains="expected scratch failure"):
        with TestScratch():
            root = temporary_path("")
            Path(temporary_path("fixture.bin")).write_text("owned")
            raise Error("expected scratch failure")
    assert_false(Path(root).exists())
    assert_equal(getenv("THREEMOJO_TEST_TMPDIR", _UNSET), "")
    assert_equal(getenv("TMPDIR", _UNSET), saved_tmp)
    _ = setenv("THREEMOJO_TEST_TMPDIR", saved)


def test_owned_context_restores_an_unset_environment() raises:
    var saved = getenv("THREEMOJO_TEST_TMPDIR", "")
    var saved_tmp = getenv("TMPDIR", _UNSET)
    _ = unsetenv("THREEMOJO_TEST_TMPDIR")
    _ = unsetenv("TMPDIR")
    var root = String("")
    with TestScratch():
        root = temporary_path("")
        assert_true(root.startswith("/"))
    assert_false(Path(root).exists())
    assert_equal(getenv("THREEMOJO_TEST_TMPDIR", _UNSET), _UNSET)
    assert_equal(getenv("TMPDIR", _UNSET), _UNSET)
    _ = setenv("THREEMOJO_TEST_TMPDIR", saved)
    _ = _restore("TMPDIR", saved_tmp)


def test_cleanup_never_uses_a_replaced_environment_path() raises:
    var saved = getenv("THREEMOJO_TEST_TMPDIR")
    var sentinel = temporary_path("caller-owned.bin")
    Path(sentinel).write_text("keep")
    _ = setenv("THREEMOJO_TEST_TMPDIR", "")
    var owned = String("")
    with TestScratch():
        owned = temporary_path("")
        _ = setenv("THREEMOJO_TEST_TMPDIR", saved)
    assert_false(Path(owned).exists())
    assert_equal(Path(sentinel).read_text(), "keep")
    assert_equal(getenv("THREEMOJO_TEST_TMPDIR"), "")
    _ = setenv("THREEMOJO_TEST_TMPDIR", saved)


def test_supplied_roots_must_be_absolute_existing_directories() raises:
    var saved = getenv("THREEMOJO_TEST_TMPDIR")
    var saved_tmp = getenv("TMPDIR", _UNSET)
    var file = temporary_path("not-a-directory.bin")
    Path(file).write_text("keep")
    for root in [String("relative-root"), saved + "/missing-root", file]:
        _ = setenv("THREEMOJO_TEST_TMPDIR", root)
        with assert_raises(contains="absolute existing directory"):
            with TestScratch():
                pass
        with assert_raises(contains="absolute existing directory"):
            _ = temporary_path("fixture.bin")
        assert_equal(getenv("THREEMOJO_TEST_TMPDIR"), root)
        assert_equal(getenv("TMPDIR", _UNSET), saved_tmp)
    assert_equal(Path(file).read_text(), "keep")
    _ = setenv("THREEMOJO_TEST_TMPDIR", saved)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
