# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""POSIX file calls for the CARLA asset tools, with Python's error texts.

The asset manager stages renders and archives without following a link
that a racing process puts in place. It opens a file and then compares the
open descriptor with the path it checked, by device and inode, as Python's
`os.path.samestat` does. `std.os` has no `fstat`, `openat`, `fstatat` or
`mkdirat`, so this module calls the C library. It works on Linux (x86-64
and AArch64) and on macOS (arm64).

An error is raised with the text that Python's exception gives, after its
class name: `FileNotFoundError: [Errno 2] No such file or directory:
'path'`. `exception_text` returns the part that `str(error)` gives.

`open` and `openat` are variadic in C. On macOS arm64 a variadic argument
goes on the stack, so the mode cannot be passed. A file that this module
creates on macOS is made with the C library's default bits and then set to
the mode that Python gives it with `fchmod`, before any byte is written.
"""

from std.ffi import c_int, external_call
from std.memory import Pointer
from std.sys import CompilationTarget

from tools._owned_process import (
    at_cwd,
    c_bytes,
    errno,
    o_directory,
    o_nofollow,
    strerror,
)
from tools._python_json import py_repr

comptime ENOENT = 2
"""No such file or directory."""
comptime EEXIST = 17
"""File exists."""
comptime EINTR = 4
"""Interrupted system call."""

comptime S_IFMT = 0o170000
"""The file type bits of a mode."""
comptime S_IFREG = 0o100000
"""A regular file."""
comptime S_IFDIR = 0o040000
"""A directory."""
comptime S_IFLNK = 0o120000
"""A symbolic link."""

comptime _STAT_BYTES = 256
"""Room for a `struct stat` on every supported platform."""

comptime _EXCEPTIONS: List[String] = [
    "ManifestError",
    "FetchError",
    "StageError",
    "OSError",
    "FileNotFoundError",
    "FileExistsError",
    "IsADirectoryError",
    "NotADirectoryError",
    "PermissionError",
    "KeyError",
    "TypeError",
    "ValueError",
    "AttributeError",
    "IndexError",
    "UnicodeDecodeError",
    "json.decoder.JSONDecodeError",
    "zipfile.BadZipFile",
    "OverflowError",
    "RecursionError",
    "RuntimeError",
    "SystemExit",
    "zipfile.LargeZipFile",
    "urllib.error.HTTPError",
    "urllib.error.URLError",
    "zlib.error",
    "NotImplementedError",
]
"""The exception classes whose name starts an error text here."""


def _linux() -> Bool:
    """Return whether the program runs on Linux."""
    return CompilationTarget.is_linux()


def _at(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def o_rdonly() -> Int:
    """Return `O_RDONLY`.

    Returns:
        The flag.
    """
    return 0


def o_wronly() -> Int:
    """Return `O_WRONLY`.

    Returns:
        The flag.
    """
    return 1


def o_creat() -> Int:
    """Return `O_CREAT` for this platform.

    Returns:
        The flag.
    """
    return 0x40 if _linux() else 0x200


def o_excl() -> Int:
    """Return `O_EXCL` for this platform.

    Returns:
        The flag.
    """
    return 0x80 if _linux() else 0x800


def o_trunc() -> Int:
    """Return `O_TRUNC` for this platform.

    Returns:
        The flag.
    """
    return 0x200 if _linux() else 0x400


def o_nonblock() -> Int:
    """Return `O_NONBLOCK` for this platform.

    Returns:
        The flag.
    """
    return 0x800 if _linux() else 0x4


def o_dir() -> Int:
    """Return `O_DIRECTORY` for this platform.

    Returns:
        The flag.
    """
    return o_directory()


def o_nofollow_flag() -> Int:
    """Return `O_NOFOLLOW` for this platform.

    Returns:
        The flag.
    """
    return o_nofollow()


def _at_symlink_nofollow() -> Int:
    """Return `AT_SYMLINK_NOFOLLOW` for this platform."""
    return 0x100 if _linux() else 0x20


def error_class(number: Int) -> String:
    """Return the Python exception class that an `errno` value raises.

    Args:
        number: The `errno` value.

    Returns:
        The class name, such as `FileNotFoundError`.
    """
    if number == ENOENT:
        return "FileNotFoundError"
    if number == EEXIST:
        return "FileExistsError"
    if number == 21:
        return "IsADirectoryError"
    if number == 20:
        return "NotADirectoryError"
    if number == 13 or number == 1:
        return "PermissionError"
    return "OSError"


def os_error(number: Int, filename: String) -> Error:
    """Return the error that Python raises for a failed call on a path.

    Args:
        number: The `errno` value.
        filename: The path that the call named.

    Returns:
        `Class: [Errno N] text: 'filename'`.
    """
    return Error(
        error_class(number)
        + ": [Errno "
        + String(number)
        + "] "
        + strerror(number)
        + ": "
        + py_repr(filename)
    )


def os_error_pair(number: Int, source: String, target: String) -> Error:
    """Return the error that Python raises for a failed call on two paths.

    Args:
        number: The `errno` value.
        source: The first path.
        target: The second path.

    Returns:
        `Class: [Errno N] text: 'source' -> 'target'`.
    """
    return Error(
        error_class(number)
        + ": [Errno "
        + String(number)
        + "] "
        + strerror(number)
        + ": "
        + py_repr(source)
        + " -> "
        + py_repr(target)
    )


def exception_text(error: Error) -> String:
    """Return what `str(exception)` gives for an error raised here.

    Args:
        error: An error whose text starts with an exception class name.

    Returns:
        The text after the class name and its colon, or the whole text.
    """
    var text = String(error)
    var colon = text.find(": ")
    if colon > 0:
        var name = String(text[byte=:colon])
        for known in materialize[_EXCEPTIONS]():
            if known == name:
                return String(text[byte = colon + 2 :])
    return text^


def exception_line(error: Error) -> String:
    """Return the last line of Python's traceback for an error raised here.

    Args:
        error: An error raised by this module or the tools that use it.

    Returns:
        The text with its class name; a text without one is a `ValueError`,
        as `json` raises it.
    """
    var text = String(error)
    var colon = text.find(": ")
    if colon > 0:
        var name = String(text[byte=:colon])
        for known in materialize[_EXCEPTIONS]():
            if known == name:
                return text^
    if text.startswith("'utf-8' codec"):
        return "UnicodeDecodeError: " + text
    return "json.decoder.JSONDecodeError: " + text


struct FileId(ImplicitlyCopyable, Movable):
    """What `os.stat` says of a file: its device, inode and mode."""

    var device: UInt64
    """The device."""
    var inode: UInt64
    """The inode."""
    var mode: Int
    """The type and permission bits."""

    def __init__(out self, device: UInt64, inode: UInt64, mode: Int):
        """Make an identity.

        Args:
            device: The device.
            inode: The inode.
            mode: The mode.
        """
        self.device = device
        self.inode = inode
        self.mode = mode

    def same(self, other: FileId) -> Bool:
        """Return `os.path.samestat(self, other)`.

        Args:
            other: Another identity.

        Returns:
            True when the device and the inode match.
        """
        return self.device == other.device and self.inode == other.inode

    def is_regular(self) -> Bool:
        """Return `stat.S_ISREG(mode)`.

        Returns:
            True for a regular file.
        """
        return self.mode & S_IFMT == S_IFREG

    def is_directory(self) -> Bool:
        """Return `stat.S_ISDIR(mode)`.

        Returns:
            True for a directory.
        """
        return self.mode & S_IFMT == S_IFDIR

    def is_link(self) -> Bool:
        """Return `stat.S_ISLNK(mode)`.

        Returns:
            True for a symbolic link.
        """
        return self.mode & S_IFMT == S_IFLNK


def _u64(buffer: List[UInt8], at: Int) -> UInt64:
    """Return the little-endian 64-bit value at `at`."""
    var value = UInt64(0)
    for index in range(8):
        value |= UInt64(buffer[at + index]) << UInt64(8 * index)
    return value


def _u32(buffer: List[UInt8], at: Int) -> UInt64:
    """Return the little-endian 32-bit value at `at`."""
    var value = UInt64(0)
    for index in range(4):
        value |= UInt64(buffer[at + index]) << UInt64(8 * index)
    return value


def _identity(buffer: List[UInt8]) -> FileId:
    """Read the device, inode and mode of a filled `struct stat`."""
    comptime if CompilationTarget.is_linux():
        comptime if CompilationTarget.is_x86():
            return FileId(
                _u64(buffer, 0), _u64(buffer, 8), Int(_u32(buffer, 24))
            )
        else:
            return FileId(
                _u64(buffer, 0), _u64(buffer, 8), Int(_u32(buffer, 16))
            )
    else:
        return FileId(
            _u32(buffer, 0), _u64(buffer, 8), Int(_u32(buffer, 4) & 0xFFFF)
        )


def fstat_id(fd: Int, filename: String = "") raises -> FileId:
    """Return `os.fstat(fd)`.

    Args:
        fd: An open descriptor.
        filename: Unused; a descriptor error names no file.

    Returns:
        The identity.

    Raises:
        Error: `OSError` text if the call fails.
    """
    var buffer = List[UInt8](length=_STAT_BYTES, fill=0)
    if (
        external_call["fstat", c_int](c_int(fd), _at(Int(buffer.unsafe_ptr())))
        != 0
    ):
        var number = errno()
        raise Error(
            error_class(number)
            + ": [Errno "
            + String(number)
            + "] "
            + strerror(number)
        )
    return _identity(buffer)


def stat_at(
    directory: Int, name: String, follow: Bool = False
) raises -> FileId:
    """Return `os.stat(name, dir_fd=directory, follow_symlinks=follow)`.

    Args:
        directory: A directory descriptor, or `at_cwd()`.
        name: The path, relative to the directory.
        follow: True to follow a final symbolic link.

    Returns:
        The identity.

    Raises:
        Error: `OSError` text that names `name`.
    """
    var buffer = List[UInt8](length=_STAT_BYTES, fill=0)
    var path = c_bytes(name)
    var flags = 0 if follow else _at_symlink_nofollow()
    if (
        external_call["fstatat", c_int](
            c_int(directory),
            _at(Int(path.unsafe_ptr())),
            _at(Int(buffer.unsafe_ptr())),
            c_int(flags),
        )
        != 0
    ):
        raise os_error(errno(), name)
    return _identity(buffer)


def lstat_id(path: String) raises -> FileId:
    """Return `os.lstat(path)`.

    Args:
        path: The path.

    Returns:
        The identity of the path itself, not of a link's target.

    Raises:
        Error: `OSError` text that names the path.
    """
    return stat_at(at_cwd(), path, False)


def stat_id(path: String) raises -> FileId:
    """Return `os.stat(path)`, which follows links.

    Args:
        path: The path.

    Returns:
        The identity.

    Raises:
        Error: `OSError` text that names the path.
    """
    return stat_at(at_cwd(), path, True)


def path_exists(path: String) -> Bool:
    """Return `Path(path).exists()`, which follows links.

    Args:
        path: The path.

    Returns:
        True when the path, or a link's target, exists.
    """
    try:
        _ = stat_id(path)
        return True
    except:
        return False


def path_is_link(path: String) -> Bool:
    """Return `Path(path).is_symlink()`.

    Args:
        path: The path.

    Returns:
        True for a symbolic link, dangling or not.
    """
    try:
        return lstat_id(path).is_link()
    except:
        return False


def path_is_file(path: String) -> Bool:
    """Return `Path(path).is_file()`, which follows links.

    Args:
        path: The path.

    Returns:
        True for a regular file or a link to one.
    """
    try:
        return stat_id(path).is_regular()
    except:
        return False


def path_is_dir(path: String) -> Bool:
    """Return `Path(path).is_dir()`, which follows links.

    Args:
        path: The path.

    Returns:
        True for a directory or a link to one.
    """
    try:
        return stat_id(path).is_directory()
    except:
        return False


def _umask() -> Int:
    """Return the process's file creation mask."""
    var old = external_call["umask", UInt32](UInt32(0o022))
    _ = external_call["umask", UInt32](old)
    return Int(old) & 0o777


def open_at(
    directory: Int, name: String, flags: Int, mode: Int = 0o777
) raises -> Int:
    """Return `os.open(name, flags, mode, dir_fd=directory)`.

    Args:
        directory: A directory descriptor, or `at_cwd()`.
        name: The path, relative to the directory.
        flags: The `O_` flags.
        mode: The mode of a created file, before the mask.

    Returns:
        The descriptor.

    Raises:
        Error: `OSError` text that names `name`.
    """
    var path = c_bytes(name)
    var fd: Int
    while True:
        fd = Int(
            external_call["openat", c_int](
                c_int(directory),
                _at(Int(path.unsafe_ptr())),
                c_int(flags),
                c_int(mode),
            )
        )
        if fd >= 0 or errno() != EINTR:
            break
    if fd < 0:
        raise os_error(errno(), name)
    comptime if not CompilationTarget.is_linux():
        if flags & o_creat() != 0:
            _ = external_call["fchmod", c_int](
                c_int(fd), UInt32(mode & ~_umask() & 0o7777)
            )
    return fd


def open_path(path: String, flags: Int, mode: Int = 0o777) raises -> Int:
    """Return `os.open(path, flags, mode)`.

    Args:
        path: The path.
        flags: The `O_` flags.
        mode: The mode of a created file, before the mask.

    Returns:
        The descriptor.

    Raises:
        Error: `OSError` text that names the path.
    """
    return open_at(at_cwd(), path, flags, mode)


def close_fd(fd: Int):
    """Close a descriptor and ignore an error.

    Args:
        fd: The descriptor.
    """
    _ = external_call["close", c_int](c_int(fd))


def seek_start(fd: Int) raises:
    """Move a descriptor to its first byte, as `seek(0)` does.

    Args:
        fd: The descriptor.

    Raises:
        Error: `OSError` text if the call fails.
    """
    if external_call["lseek", Int](c_int(fd), Int(0), c_int(0)) < 0:
        var number = errno()
        raise Error(
            error_class(number)
            + ": [Errno "
            + String(number)
            + "] "
            + strerror(number)
        )


def read_some(fd: Int, size: Int) raises -> List[UInt8]:
    """Read up to `size` bytes; an empty list is the end of the file.

    Args:
        fd: The descriptor.
        size: The most bytes to read.

    Returns:
        The bytes read.

    Raises:
        Error: `OSError` text if the call fails.
    """
    var out = List[UInt8](length=size, fill=0)
    while True:
        var count = external_call["read", Int](
            fd, _at(Int(out.unsafe_ptr())), size
        )
        if count >= 0:
            out.resize(count, 0)
            return out^
        var number = errno()
        if number != EINTR:
            raise Error(
                error_class(number)
                + ": [Errno "
                + String(number)
                + "] "
                + strerror(number)
            )


def read_all(fd: Int) raises -> List[UInt8]:
    """Read a descriptor to its end.

    Args:
        fd: The descriptor.

    Returns:
        Every remaining byte.

    Raises:
        Error: `OSError` text if a read fails.
    """
    var out = List[UInt8]()
    while True:
        var block = read_some(fd, 1 << 20)
        if len(block) == 0:
            return out^
        out.extend(block^)


def write_all(fd: Int, data: Span[UInt8, _]) raises:
    """Write every byte, as a buffered Python writer does.

    Args:
        fd: The descriptor.
        data: The bytes.

    Raises:
        Error: `OSError` text if a write fails.
    """
    var done = 0
    var base = Int(data.unsafe_ptr())
    while done < len(data):
        var count = external_call["write", Int](
            fd, _at(base + done), len(data) - done
        )
        if count < 0:
            var number = errno()
            if number == EINTR:
                continue
            raise Error(
                error_class(number)
                + ": [Errno "
                + String(number)
                + "] "
                + strerror(number)
            )
        done += count


def make_dir_at(directory: Int, name: String, mode: Int = 0o777) raises:
    """Run `os.mkdir(name, mode, dir_fd=directory)`.

    Args:
        directory: A directory descriptor, or `at_cwd()`.
        name: The new directory, relative to `directory`.
        mode: Its mode, before the mask.

    Raises:
        Error: `OSError` text that names `name`.
    """
    var path = c_bytes(name)
    if (
        external_call["mkdirat", c_int](
            c_int(directory), _at(Int(path.unsafe_ptr())), UInt32(mode)
        )
        != 0
    ):
        raise os_error(errno(), name)


def make_dir(path: String) raises:
    """Run `Path(path).mkdir()`.

    Args:
        path: The new directory.

    Raises:
        Error: `OSError` text that names the path.
    """
    make_dir_at(at_cwd(), path)


def make_dirs(path: String) raises:
    """Run `Path(path).mkdir(parents=True, exist_ok=True)`.

    Args:
        path: The directory.

    Raises:
        Error: `OSError` text that names the path or a parent.
    """
    if path_is_dir(path):
        return
    var cut = path.rfind("/")
    if cut > 0:
        var parent = String(path[byte=:cut])
        if not path_exists(parent):
            make_dirs(parent)
    try:
        make_dir(path)
    except error:
        # A directory that appeared meanwhile is fine, as `exist_ok` says.
        if not path_is_dir(path):
            raise error^


def replace_file(source: String, target: String) raises:
    """Run `os.replace(source, target)`.

    Args:
        source: The path to move.
        target: Its new path, replaced if it exists.

    Raises:
        Error: `OSError` text that names both paths.
    """
    var a = c_bytes(source)
    var b = c_bytes(target)
    if (
        external_call["rename", c_int](
            _at(Int(a.unsafe_ptr())), _at(Int(b.unsafe_ptr()))
        )
        != 0
    ):
        raise os_error_pair(errno(), source, target)


def remove_file(path: String) raises:
    """Run `os.remove(path)`.

    Args:
        path: The file.

    Raises:
        Error: `OSError` text that names the path.
    """
    var a = c_bytes(path)
    if external_call["unlink", c_int](_at(Int(a.unsafe_ptr()))) != 0:
        raise os_error(errno(), path)


def make_temporary(
    directory: String, prefix: String, suffix: String
) raises -> String:
    """Create an empty file as `tempfile.mkstemp` does, and close it.

    The file has mode 0600 and a random name: the prefix, six characters
    and the suffix.

    Args:
        directory: The directory to create it in.
        prefix: The start of its name.
        suffix: The end of its name.

    Returns:
        Its path.

    Raises:
        Error: `OSError` text if it cannot be created.
    """
    var template = c_bytes(directory + "/" + prefix + "XXXXXX" + suffix)
    var fd = Int(
        external_call["mkstemps", c_int](
            _at(Int(template.unsafe_ptr())), c_int(suffix.byte_length())
        )
    )
    _ = template.pop()
    var name = String(unsafe_from_utf8=template)
    if fd < 0:
        raise os_error(errno(), name)
    close_fd(fd)
    return name^


def read_file(path: String) raises -> List[UInt8]:
    """Return a file's bytes, as `Path(path).read_bytes()` does.

    Args:
        path: The file.

    Returns:
        Its bytes.

    Raises:
        Error: `OSError` text that names the path.
    """
    var fd = open_path(path, o_rdonly())
    try:
        var info = fstat_id(fd)
        if info.is_directory():
            raise os_error(21, path)
        return read_all(fd)
    finally:
        close_fd(fd)


def write_file(path: String, data: Span[UInt8, _]) raises:
    """Write a file, as `Path(path).write_bytes(data)` does.

    Args:
        path: The file, created or truncated, with mode 0666 less the mask.
        data: Its new bytes.

    Raises:
        Error: `OSError` text that names the path.
    """
    var fd = open_path(path, o_wronly() | o_creat() | o_trunc(), 0o666)
    try:
        write_all(fd, data)
    finally:
        close_fd(fd)


def write_text(path: String, text: String) raises:
    """Write a file, as `Path(path).write_text(text, encoding='utf-8')`.

    Args:
        path: The file.
        text: Its new text.

    Raises:
        Error: `OSError` text that names the path.
    """
    write_file(path, text.as_bytes())


# --- os.path ---------------------------------------------------------------------------


def py_normpath(path: String) -> String:
    """Return `os.path.normpath(path)` on POSIX.

    Args:
        path: A path.

    Returns:
        The path without empty and `.` parts, with `..` folded where a
        name comes before it; two leading slashes stay two.
    """
    if path.byte_length() == 0:
        return "."
    var initial = 0
    if path.startswith("/"):
        initial = 1
        if path.startswith("//") and not path.startswith("///"):
            initial = 2
    var parts = List[String]()
    for piece in path.split("/"):
        var name = String(piece)
        if name == "" or name == ".":
            continue
        if (
            name != ".."
            or (initial == 0 and len(parts) == 0)
            or (len(parts) > 0 and parts[len(parts) - 1] == "..")
        ):
            parts.append(name)
        elif len(parts) > 0:
            _ = parts.pop()
    var out = String("/") * initial + "/".join(parts)
    if out.byte_length() == 0:
        return "."
    return out


def py_abspath(path: String, cwd: String) -> String:
    """Return `os.path.abspath(path)` for a working directory.

    Args:
        path: A path.
        cwd: The working directory, as `os.getcwd()` gives it.

    Returns:
        The normalized absolute path; links are not resolved.
    """
    if path.startswith("/"):
        return py_normpath(path)
    return py_normpath(py_join(cwd, path))


def py_join(base: String, name: String) -> String:
    """Return `os.path.join(base, name)` on POSIX.

    Args:
        base: The first path.
        name: The second; an absolute one replaces the first.

    Returns:
        The joined path, not normalized.
    """
    if name.startswith("/"):
        return name
    if base.byte_length() == 0 or base.endswith("/"):
        return base + name
    return base + "/" + name


def py_relpath(path: String, start: String, cwd: String) -> String:
    """Return `os.path.relpath(path, start)`.

    Args:
        path: The path.
        start: The directory to be relative to.
        cwd: The working directory.

    Returns:
        The relative path, or `.`.
    """
    var target = List[String]()
    for piece in py_abspath(path, cwd).split("/"):
        if String(piece) != "":
            target.append(String(piece))
    var origin = List[String]()
    for piece in py_abspath(start, cwd).split("/"):
        if String(piece) != "":
            origin.append(String(piece))
    var common = 0
    while (
        common < len(target)
        and common < len(origin)
        and target[common] == origin[common]
    ):
        common += 1
    var parts = List[String]()
    for _ in range(len(origin) - common):
        parts.append("..")
    for index in range(common, len(target)):
        parts.append(target[index])
    if len(parts) == 0:
        return "."
    return "/".join(parts)
