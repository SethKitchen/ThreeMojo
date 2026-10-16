# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Files, links and stub programs for the tests of the CARLA asset tools."""

from std.ffi import c_int, external_call
from std.os import listdir
from std.os.path import isdir, islink
from std.tempfile import mkdtemp

from tools._carla_files import (
    make_dirs,
    path_exists,
    read_file,
    write_file,
)
from tools._owned_process import c_bytes
from tools._process import run_program
from tools._python_json import sorted_order


def _at(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def scratch() raises -> String:
    """Return a new empty directory.

    Returns:
        Its absolute path.

    Raises:
        Error: If it cannot be made.
    """
    return mkdtemp(prefix="carla tool test ")


def remove_tree(path: String) raises:
    """Remove a directory and everything in it, without following links.

    Args:
        path: The directory.

    Raises:
        Error: If `rm` cannot run.
    """
    _ = run_program(["rm", "-rf", "--", path], 30)


def put(path: String, text: String) raises:
    """Write a file's text, and make its directories.

    Args:
        path: The file.
        text: Its text.

    Raises:
        Error: If it cannot be written.
    """
    put_bytes(path, List[UInt8](text.as_bytes()))


def put_bytes(path: String, data: List[UInt8]) raises:
    """Write a file's bytes, and make its directories.

    Args:
        path: The file.
        data: Its bytes.

    Raises:
        Error: If it cannot be written.
    """
    var cut = path.rfind("/")
    if cut > 0:
        make_dirs(String(path[byte=:cut]))
    write_file(path, Span(data))


def get_text(path: String) raises -> String:
    """Return a file's text.

    Args:
        path: The file.

    Returns:
        Its bytes as text.

    Raises:
        Error: If it cannot be read.
    """
    return String(from_utf8_lossy=read_file(path))


def symlink(target: String, path: String) raises:
    """Make a symbolic link.

    Args:
        target: What the link names.
        path: The link.

    Raises:
        Error: If `symlink` fails.
    """
    var a = c_bytes(target)
    var b = c_bytes(path)
    if external_call["symlink", c_int](
        _at(Int(a.unsafe_ptr())), _at(Int(b.unsafe_ptr()))
    ):
        raise Error("symlink failed: " + path)


def hard_link(target: String, path: String) raises:
    """Make a hard link.

    Args:
        target: The existing file.
        path: The new name.

    Raises:
        Error: If `link` fails.
    """
    var a = c_bytes(target)
    var b = c_bytes(path)
    if external_call["link", c_int](
        _at(Int(a.unsafe_ptr())), _at(Int(b.unsafe_ptr()))
    ):
        raise Error("link failed: " + path)


def make_fifo(path: String) raises:
    """Make a named pipe.

    Args:
        path: The pipe.

    Raises:
        Error: If `mkfifo` fails.
    """
    var a = c_bytes(path)
    if external_call["mkfifo", c_int](_at(Int(a.unsafe_ptr())), UInt32(0o600)):
        raise Error("mkfifo failed: " + path)


def rename(source: String, target: String) raises:
    """Rename a path.

    Args:
        source: The path.
        target: Its new name.

    Raises:
        Error: If `rename` fails.
    """
    var a = c_bytes(source)
    var b = c_bytes(target)
    if external_call["rename", c_int](
        _at(Int(a.unsafe_ptr())), _at(Int(b.unsafe_ptr()))
    ):
        raise Error("rename failed: " + source)


def unlink(path: String) raises:
    """Remove a file or a link.

    Args:
        path: The path.

    Raises:
        Error: If `unlink` fails.
    """
    var a = c_bytes(path)
    if external_call["unlink", c_int](_at(Int(a.unsafe_ptr()))):
        raise Error("unlink failed: " + path)


def remove_dir(path: String) raises:
    """Remove an empty directory.

    Args:
        path: The directory.

    Raises:
        Error: If `rmdir` fails.
    """
    var a = c_bytes(path)
    if external_call["rmdir", c_int](_at(Int(a.unsafe_ptr()))):
        raise Error("rmdir failed: " + path)


def read_link(path: String) raises -> String:
    """Return what a symbolic link names.

    Args:
        path: The link.

    Returns:
        Its target.

    Raises:
        Error: If `readlink` fails.
    """
    var a = c_bytes(path)
    var buffer = List[UInt8](length=4096, fill=0)
    var count = external_call["readlink", Int](
        _at(Int(a.unsafe_ptr())), _at(Int(buffer.unsafe_ptr())), 4096
    )
    if count < 0:
        raise Error("readlink failed: " + path)
    buffer.resize(count, 0)
    return String(from_utf8_lossy=buffer)


def names(path: String) raises -> List[String]:
    """Return a directory's entries, sorted.

    Args:
        path: The directory.

    Returns:
        The names.

    Raises:
        Error: If it cannot be listed.
    """
    var found = List[String]()
    for name in listdir(path):
        found.append(String(name))
    var out = List[String]()
    for index in sorted_order(found):
        out.append(found[index])
    return out^


def tree(root: String) raises -> List[String]:
    """Return every file under a directory, as `path=bytes` lines, sorted.

    A link is listed as `path->target` and is not entered.

    Args:
        root: The directory.

    Returns:
        The lines.

    Raises:
        Error: If a file cannot be read.
    """
    var out = List[String]()
    var pending: List[String] = [""]
    while len(pending) > 0:
        var relative = pending.pop()
        var folder = root + "/" + relative if relative else root
        for name in names(folder):
            var child = relative + "/" + name if relative else name
            var full = root + "/" + child
            if islink(full):
                out.append(child + "->" + read_link(full))
            elif isdir(full):
                pending.append(child)
            else:
                out.append(child + "=" + get_text(full))
    var sorted_lines = List[String]()
    for index in sorted_order(out):
        sorted_lines.append(out[index])
    return sorted_lines^


def stub_program(path: String, script: String) raises:
    """Write an executable shell script.

    Args:
        path: The program.
        script: Its body, after `#!/bin/sh`.

    Raises:
        Error: If it cannot be written.
    """
    put(path, "#!/bin/sh\n" + script)
    _ = run_program(["chmod", "755", path], 10)


def stub_curl(
    folder: String,
    status_line: String,
    content_type: String,
    body: String,
    exit_status: Int = 0,
    message: String = "",
    fail_first: Int = 0,
    data: List[UInt8] = List[UInt8](),
) raises -> String:
    """Write a `curl` that logs each run and answers as a host would.

    The program appends a line to `curl.log` in `folder` for each run. The
    first `fail_first` runs print `message` and exit with `exit_status`.
    The others write the response headers and the body, and exit with 0.

    Args:
        folder: Where the program and its log go.
        status_line: The HTTP status line, such as `HTTP/1.1 200 OK`.
        content_type: The Content-Type value, or empty for none.
        body: The response body.
        exit_status: The status of a failed run.
        message: The error a failed run prints.
        fail_first: How many runs fail first.
        data: The body's bytes, in place of `body` when not empty.

    Returns:
        The program's path.

    Raises:
        Error: If it cannot be written.
    """
    var program = folder + "/curl"
    if len(data) > 0:
        put_bytes(folder + "/body", data)
    else:
        put(folder + "/body", body)
    # A stub with no status line only fails, so it needs no headers file.
    # Some endpoint scanners delete a file that holds only a blank header.
    if status_line:
        var header = status_line + "\r\n"
        if content_type:
            header += "Content-Type: " + content_type + "\r\n"
        put(folder + "/headers", header + "\r\n")
    stub_program(
        program,
        "log='"
        + folder
        + "/curl.log'\n"
        + 'echo run >> "$log"\n'
        + 'count=$(wc -l < "$log" | tr -d " ")\n'
        + "while [ $# -gt 0 ]; do\n"
        + '  case "$1" in\n'
        + "    --dump-header) h=$2; shift;;\n"
        + "    --output) o=$2; shift;;\n"
        + "  esac\n"
        + "  shift\n"
        + "done\n"
        + 'if [ "$count" -le '
        + String(fail_first)
        + " ]; then\n"
        + "  echo '"
        + message
        + "' >&2\n"
        + "  exit "
        + String(exit_status)
        + "\n"
        + "fi\n"
        + "cp '"
        + folder
        + '/headers\' "$h"\n'
        + "cp '"
        + folder
        + '/body\' "$o"\n'
        + "exit 0\n",
    )
    return program^


def runs(folder: String) raises -> Int:
    """Return how many times a stub `curl` ran.

    Args:
        folder: The stub's folder.

    Returns:
        The number of lines in its log.

    Raises:
        Error: If the log cannot be read.
    """
    if not path_exists(folder + "/curl.log"):
        return 0
    return get_text(folder + "/curl.log").count("\n")
