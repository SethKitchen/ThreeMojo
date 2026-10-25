# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the coverage generation checkpoint before the producer runs.

    coverage_loop_begin --root DIR --build DIR --compiler TEXT --flags TEXT
        --mojo TEXT [--sources MODULE.mojo ...]

The file `generation-inputs.json` is the canonical checkpoint. It matches
`coverage_loop_proofs.py begin` byte for byte. An empty `origins.ready`
replaces any earlier ready index. The seal step still reads this file.
"""

from std.ffi import OwnedDLHandle, external_call
from std.os import getenv, listdir, makedirs, remove
from std.os.path import exists, isdir, isfile, islink, realpath
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr

from tools._imports import sorted_strings
from tools._process import run_program
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
    py_repr,
)
from tools._sha256 import sha256_hex
from tools.cache_key import input_paths

comptime _MARKER = "from mojo._entrypoints import exec_mojo\n"
"""The line that marks an official Mojo wheel launcher."""
comptime _PROBE = (
    "import importlib.util,json,sys,sysconfig,site; "
    + 'spec=importlib.util.find_spec("mojo"); '
    + 'entry=importlib.util.find_spec("mojo._entrypoints"); '
    + 'print(json.dumps({"version":sys.version,"implementation":sys.implementation.name,'
    + '"cache_tag":sys.implementation.cache_tag,"byteorder":sys.byteorder,"maxsize":sys.maxsize,'
    + '"soabi":sysconfig.get_config_var("SOABI"),"prefix":sys.prefix,'
    + '"sites":site.getsitepackages(),"user_site":site.ENABLE_USER_SITE,'
    + '"mojo_paths":list(spec.submodule_search_locations or []) if spec'
    " else [],"
    + '"entrypoint":entry.origin if entry else None,'
    + '"customizers":[name for name in ("sitecustomize","usercustomize") if'
    " name in sys.modules]}))"
)
"""The isolated probe the wheel identity runs in the launcher interpreter."""
comptime _PACKAGES = ["mojo_compiler", "mojo_compiler_mojo_libs"]
"""The two wheel distributions the identity binds."""


def _usage() -> String:
    """Return the usage line.

    Returns:
        The usage line.
    """
    return (
        "usage: coverage_loop_begin --root DIR --build DIR --compiler TEXT "
        + "--flags TEXT --mojo TEXT [--sources MODULE.mojo ...]"
    )


def _c_string(text: String) -> List[UInt8]:
    """Return `text` with a final zero byte.

    Args:
        text: The text.

    Returns:
        The bytes.
    """
    var bytes = List[UInt8](text.as_bytes())
    bytes.append(0)
    return bytes^


def _read_c_string(address: Int) -> String:
    """Return the zero-terminated text at an address.

    Args:
        address: The address, or zero.

    Returns:
        The text, or empty when the address is zero.
    """
    if address == 0:
        return String()
    var length = external_call["strlen", Int](address)
    var bytes = List[UInt8](length=length, fill=0)
    _ = external_call["memcpy", Int](
        bytes.unsafe_ptr().unsafe_bitcast[NoneType](), address, length
    )
    return String(from_utf8_lossy=bytes)


def _environ_base() raises -> Int:
    """Return the address of this process's environment array.

    Returns:
        The address of the first entry.

    Raises:
        Error: If the process environment cannot be found.
    """
    comptime if CompilationTarget.is_macos():
        var cell = external_call["_NSGetEnviron", Int]()
        var value = List[Int](length=1, fill=0)
        _ = external_call["memcpy", Int](
            value.unsafe_ptr().unsafe_bitcast[NoneType](), cell, 8
        )
        return value[0]
    else:
        var handle = OwnedDLHandle()
        var symbol = handle.get_symbol[Int]("environ")
        return symbol[][]


def _environment() raises -> List[String]:
    """Return this process's environment as `NAME=VALUE` entries.

    Returns:
        The entries, in process order.

    Raises:
        Error: If the environment cannot be read.
    """
    var base = _environ_base()
    var entries = List[String]()
    var cell = List[Int](length=1, fill=0)
    var index = 0
    while base != 0 and index < 100000:
        _ = external_call["memcpy", Int](
            cell.unsafe_ptr().unsafe_bitcast[NoneType](), base + 8 * index, 8
        )
        if cell[0] == 0:
            break
        entries.append(_read_c_string(cell[0]))
        index += 1
    return entries^


def _space(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace.

    Args:
        byte: One byte.

    Returns:
        True for space, tab, newline, carriage return, vertical tab, or
        form feed.
    """
    return (
        byte == 32
        or byte == 9
        or byte == 10
        or byte == 13
        or byte == 11
        or byte == 12
    )


def _strip(text: String) -> String:
    """Return `text` without ASCII whitespace at either end.

    Args:
        text: The text.

    Returns:
        The stripped text.
    """
    var data = text.as_bytes()
    var start = 0
    var end = len(data)
    while start < end and _space(data[start]):
        start += 1
    while end > start and _space(data[end - 1]):
        end -= 1
    if start == 0 and end == len(data):
        return text
    return String(text[byte=start:end])


def _lower(text: String) -> String:
    """Return `text` with ASCII letters in lower case.

    Args:
        text: The text.

    Returns:
        The lower-case text.
    """
    var out = String()
    for byte in text.as_bytes():
        if byte >= 65 and byte <= 90:
            out += chr(Int(byte) + 32)
        else:
            out += chr(Int(byte))
    return out^


def _lines(text: String) -> List[String]:
    """Return the lines of `text`, as `str.splitlines` does.

    Args:
        text: The text.

    Returns:
        The lines, without their breaks.
    """
    if text.byte_length() == 0:
        return List[String]()
    var normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    var parts = List[String]()
    for part in normalized.split("\n"):
        parts.append(String(part))
    var data = normalized.as_bytes()
    if len(data) > 0 and data[len(data) - 1] == 10 and len(parts) > 0:
        _ = parts.pop()
    return parts^


def _hash_file(path: String) raises -> String:
    """Return the SHA-256 of a file.

    Args:
        path: The file.

    Returns:
        The lowercase hexadecimal digest.

    Raises:
        Error: If the file cannot be read.
    """
    var data = Path(path).read_bytes()
    return sha256_hex(Span(data))


def _hash_list(data: List[UInt8]) -> String:
    """Return the SHA-256 of `data`.

    Args:
        data: The bytes.

    Returns:
        The lowercase hexadecimal digest.
    """
    return sha256_hex(Span(data))


def _contains(data: List[UInt8], needle: String) -> Bool:
    """Return whether `data` contains `needle`.

    Args:
        data: The bytes.
        needle: The text to find.

    Returns:
        True when the bytes occur together.
    """
    var wanted = needle.as_bytes()
    if len(wanted) == 0 or len(data) < len(wanted):
        return False
    for start in range(len(data) - len(wanted) + 1):
        var same = True
        for offset in range(len(wanted)):
            if data[start + offset] != wanted[offset]:
                same = False
                break
        if same:
            return True
    return False


def _parent(path: String) -> String:
    """Return the directory that holds `path`.

    Args:
        path: A path.

    Returns:
        The parent, or `/` at the root.
    """
    var slash = path.rfind("/")
    if slash <= 0:
        return "/"
    return String(path[byte=:slash])


def _resolve(path: String) raises -> String:
    """Return a path with its links resolved, as `Path.resolve()` does.

    Args:
        path: A path, which need not exist.

    Returns:
        The absolute path.

    Raises:
        Error: If the current directory cannot be found.
    """
    if path.byte_length() == 0:
        return realpath(".")
    var full = path if path.startswith("/") else realpath(".") + "/" + path
    if exists(full):
        return realpath(full)
    var slash = full.rfind("/")
    if slash <= 0:
        return full
    var parent = String(full[byte=:slash])
    var name = String(full[byte=slash:])
    if exists(parent):
        var real = realpath(parent)
        if real == "/":
            return name
        return real + name
    return full


def _join(base: String, child: String) -> String:
    """Join two paths as `pathlib.Path` does.

    Args:
        base: The left path.
        child: The right path.

    Returns:
        `child` when it is absolute, otherwise the two paths joined.
    """
    if child.startswith("/"):
        return child
    if base == "/":
        return "/" + child
    if base.endswith("/"):
        return base + child
    return base + "/" + child


def _inside(path: String, root: String) -> Bool:
    """Return whether `path` is `root` or a file inside it.

    Args:
        path: An absolute path.
        root: An absolute directory.

    Returns:
        True when `path` does not escape `root`.
    """
    if root == "/":
        return path.startswith("/")
    return path == root or path.startswith(root + "/")


def _relative(path: String, root: String) -> String:
    """Return `path` relative to `root`.

    Args:
        path: An absolute path inside `root`.
        root: The directory.

    Returns:
        `.` when the two are the same, otherwise the relative path.
    """
    if path == root:
        return "."
    return String(path[byte = root.byte_length() + 1 :])


def _posix_text(name: String) -> String:
    """Return the `PurePosixPath` spelling of `name`.

    Args:
        name: A path string.

    Returns:
        The normalized spelling.
    """
    var rest = name
    var root = String()
    if name.startswith("/") and not name.startswith("//"):
        root = "/"
        rest = String(name[byte=1:])
    elif name.startswith("//") and not name.startswith("///"):
        root = "//"
        rest = String(name[byte=2:])
    elif name.startswith("///"):
        root = "/"
        rest = String(name[byte=3:])
    var parts = List[String]()
    for part in rest.split("/"):
        var name = String(part)
        if name.byte_length() == 0 or name == ".":
            continue
        parts.append(name)
    if len(parts) == 0:
        return "/" if root == "/" else ("//" if root == "//" else ".")
    if root.byte_length() == 0:
        return "/".join(parts)
    return root + "/".join(parts)


def _invalid_source(name: String) -> Bool:
    """Return whether `name` is not a relative source identity.

    Args:
        name: The source string.

    Returns:
        True when the name is empty, absolute, or not spelled as itself.
    """
    if name.byte_length() == 0:
        return True
    if name.find("\\") >= 0 or name.find(":") >= 0:
        return True
    if _posix_text(name) != name:
        return True
    if name.startswith("/"):
        return True
    for part in name.split("/"):
        if part == "..":
            return True
    return False


def _suffix(name: String) -> String:
    """Return the last suffix of a file name, as `Path.suffix` does.

    Args:
        name: The file name.

    Returns:
        The suffix, including the dot, or empty.
    """
    var dot = name.rfind(".")
    if dot <= 0:
        return String()
    return String(name[byte=dot:])


def _ws(byte: Int) -> Bool:
    """Return whether `byte` separates shell words.

    Args:
        byte: One byte.

    Returns:
        True for space, tab, carriage return, or line feed.
    """
    return byte == 32 or byte == 9 or byte == 13 or byte == 10


def _shlex(text: String) raises -> List[String]:
    """Split `text` as `shlex.split` does in POSIX mode.

    Args:
        text: The command text.

    Returns:
        The words.

    Raises:
        Error: With Python's text when a quote or escape is unfinished.
    """
    var data = text.as_bytes()
    var length = len(data)
    var cursor = 0
    var tokens = List[String]()
    while True:
        var token = List[UInt8]()
        var quoted = False
        var state = 32
        var escaped = 32
        var emit = False
        var done = False
        while True:
            var eof = cursor >= length
            var byte = 0
            if not eof:
                byte = Int(data[cursor])
                cursor += 1
            if state == 32:
                if eof:
                    done = True
                    break
                if _ws(byte):
                    if len(token) > 0 or quoted:
                        emit = True
                        break
                    continue
                if byte == 92:
                    escaped = 97
                    state = byte
                elif byte == 39 or byte == 34:
                    state = byte
                else:
                    token.append(UInt8(byte))
                    state = 97
            elif state == 39 or state == 34:
                quoted = True
                if eof:
                    raise Error("No closing quotation")
                if byte == state:
                    state = 97
                elif state == 34 and byte == 92:
                    escaped = state
                    state = byte
                else:
                    token.append(UInt8(byte))
            elif state == 92:
                if eof:
                    raise Error("No escaped character")
                if (
                    (escaped == 39 or escaped == 34)
                    and byte != 92
                    and byte != escaped
                ):
                    token.append(92)
                token.append(UInt8(byte))
                state = escaped
            else:
                if eof:
                    done = True
                    emit = len(token) > 0 or quoted
                    break
                if _ws(byte):
                    emit = len(token) > 0 or quoted
                    break
                if byte == 39 or byte == 34:
                    state = byte
                elif byte == 92:
                    escaped = 97
                    state = byte
                else:
                    token.append(UInt8(byte))
        if emit and (quoted or len(token) > 0):
            tokens.append(String(from_utf8_lossy=token))
        if done:
            break
    return tokens^


def _can_run(path: String) -> Bool:
    """Return whether `path` is an executable file.

    Args:
        path: The path.

    Returns:
        True when `path` can be run and is not a directory.
    """
    if path.byte_length() == 0 or isdir(path):
        return False
    var bytes = _c_string(path)
    return (
        external_call["access", Int32](
            bytes.unsafe_ptr().unsafe_bitcast[NoneType](), Int32(1)
        )
        == 0
    )


def _which(name: String) -> String:
    """Return the first executable `name` on `PATH`, or empty.

    Args:
        name: The program name or path.

    Returns:
        The path `shutil.which` would return, or empty.
    """
    if name.find("/") >= 0:
        if _can_run(name):
            return name
        return String()
    var path = getenv("PATH", "/bin:/usr/bin")
    for directory in path.split(":"):
        var folder = String(directory)
        var candidate = (
            folder + "/" + name if folder.byte_length() > 0 else name
        )
        if _can_run(candidate):
            return candidate
    return String()


def _executable(value: String, root: String) raises -> String:
    """Return the resolved file named by a command word.

    Args:
        value: The word.
        root: The repository root.

    Returns:
        The absolute path.

    Raises:
        Error: When the word does not name a file.
    """
    var path = _join(root, value) if value.find("/") >= 0 else _which(value)
    if path.byte_length() == 0 or not isfile(path):
        raise Error("Missing capture executable: " + value)
    return _resolve(path)


def _symbolic(path: String, root: String, build: String) raises -> String:
    """Return a path as `@BUILD@`, `@ROOT@`, or an absolute path.

    Args:
        path: A file path.
        root: The resolved repository root.
        build: The resolved build directory.

    Returns:
        The symbolic path.

    Raises:
        Error: If a path cannot be resolved.
    """
    var real = _resolve(path)
    if _inside(real, build):
        if real == build:
            return "@BUILD@"
        return "@BUILD@/" + _relative(real, build)
    if _inside(real, root):
        if real == root:
            return "@ROOT@"
        return "@ROOT@/" + _relative(real, root)
    return real


def _field(text: String, prefix: String) -> String:
    """Return the text after the first line that starts with `prefix`.

    Args:
        text: The metadata text.
        prefix: The label, including its colon and space.

    Returns:
        The remainder of that line, or empty when it is absent.
    """
    for line in _lines(text):
        if line.startswith(prefix):
            return String(line[byte = prefix.byte_length() :])
    return String()


def _csv_row(line: String) -> List[String]:
    """Return one CSV row.

    Args:
        line: One line, without its break.

    Returns:
        The fields.
    """
    var fields = List[String]()
    var current = List[UInt8]()
    var quoted = False
    var data = line.as_bytes()
    var index = 0
    while index < len(data):
        var byte = data[index]
        if quoted:
            if byte == 34:
                if index + 1 < len(data) and data[index + 1] == 34:
                    current.append(34)
                    index += 2
                    continue
                quoted = False
            else:
                current.append(byte)
        elif byte == 34:
            quoted = True
        elif byte == 44:
            fields.append(String(from_utf8_lossy=current))
            current = List[UInt8]()
        else:
            current.append(byte)
        index += 1
    fields.append(String(from_utf8_lossy=current))
    return fields^


def _skip_payload(path: String) -> Bool:
    """Return whether a walked file stays out of the payload.

    Args:
        path: The file path.

    Returns:
        True for a `__pycache__` file or a `.pyc` file.
    """
    var slash = path.rfind("/")
    var name = String(path[byte = slash + 1 :]) if slash >= 0 else path
    if _suffix(name) == ".pyc":
        return True
    for part in path.split("/"):
        if part == "__pycache__":
            return True
    return False


def _add_file(
    mut names: List[String],
    mut paths: List[String],
    name: String,
    path: String,
):
    """Keep one payload file, the first time its relative name appears.

    Args:
        names: The relative names already kept.
        paths: The matching full paths.
        name: The relative name.
        path: The full path.
    """
    for have in names:
        if have == name:
            return
    names.append(name)
    paths.append(path)


def _normalize_row(row: String) -> String:
    """Return a RECORD path with `.` and empty parts removed.

    Args:
        row: The path from the record.

    Returns:
        The relative path `Path` keeps for a non-absolute row.
    """
    var parts = List[String]()
    for part in row.split("/"):
        var name = String(part)
        if name.byte_length() == 0 or name == ".":
            continue
        parts.append(name)
    return "/".join(parts)


def _walk(
    directory: String,
    site: String,
    mut names: List[String],
    mut paths: List[String],
    mut ancestors: List[String],
) raises:
    """Add the files under `directory`, following a directory link.

    Args:
        directory: The directory to read.
        site: The site-packages directory.
        names: The relative payload names.
        paths: The matching full paths.
        ancestors: The real paths of the directories above this one.

    Raises:
        Error: If a directory cannot be resolved.
    """
    var real = realpath(directory)
    for seen in ancestors:
        if seen == real:
            return
    ancestors.append(real)
    var listed: List[String]
    try:
        listed = listdir(directory)
    except:
        _ = ancestors.pop()
        return
    for name in listed:
        var full = directory + "/" + name
        if isdir(full):
            _walk(full, site, names, paths, ancestors)
        elif isfile(full) and not _skip_payload(full):
            if full.startswith(site + "/"):
                _add_file(names, paths, _relative(full, site), full)
    _ = ancestors.pop()


def _override(key: String) -> Bool:
    """Return whether an environment name can redirect the compiler.

    Args:
        key: The variable name.

    Returns:
        True for a blocked name.
    """
    if key.startswith("MODULAR_MOJO_"):
        return True
    return (
        key == "MODULAR_MAX_PACKAGE_ROOT"
        or key == "PYTHONPATH"
        or key == "PYTHONHOME"
        or key == "PYTHONUSERBASE"
        or key == "LD_PRELOAD"
        or key == "LD_LIBRARY_PATH"
        or key == "DYLD_LIBRARY_PATH"
        or key == "DYLD_INSERT_LIBRARIES"
    )


def _reject_overrides() raises:
    """Raise when a compiler override is set.

    Raises:
        Error: With Python's text when a blocked variable is nonempty.
    """
    var keys = List[String]()
    var values = List[String]()
    for entry in _environment():
        var split = entry.find("=")
        if split < 0:
            continue
        var key = String(entry[byte=:split])
        var value = String(entry[byte = split + 1 :])
        var replaced = False
        for index in range(len(keys)):
            if keys[index] == key:
                values[index] = value
                replaced = True
                break
        if not replaced:
            keys.append(key)
            values.append(value)
    var blocked = List[String]()
    var nonempty = False
    for index in range(len(keys)):
        if _override(keys[index]):
            blocked.append(keys[index])
            if values[index].byte_length() > 0:
                nonempty = True
    if nonempty:
        var ordered = sorted_strings(blocked.copy())
        raise Error(
            "Unsupported compiler environment override: " + ", ".join(ordered)
        )


def _same_set(left: List[String], right: List[String]) -> Bool:
    """Return whether two lists hold the same strings.

    Args:
        left: One list.
        right: The other list.

    Returns:
        True when each string of either list is in the other.
    """
    for item in left:
        var found = False
        for other in right:
            if item == other:
                found = True
                break
        if not found:
            return False
    for item in right:
        var found = False
        for other in left:
            if item == other:
                found = True
                break
        if not found:
            return False
    return True


def _string_list(doc: PyJson, node: Int) raises -> List[String]:
    """Return the strings in a JSON list.

    Args:
        doc: The probe document.
        node: A list node.

    Returns:
        The strings.

    Raises:
        Error: If an item is not a string.
    """
    var found = List[String]()
    if doc.kind(node) != PY_LIST:
        raise Error("probe list")
    for index in range(doc.length(node)):
        var item = doc.item(node, index)
        if doc.kind(item) != PY_STR:
            raise Error("probe string")
        found.append(doc.text(item))
    return found^


def _apply_wheel(
    mut doc: PyJson, item: Int, path: String, raw: List[UInt8]
) raises:
    """Add the wheel identity of a Mojo launcher to `item`.

    Args:
        doc: The checkpoint document.
        item: The command-word dict.
        path: The launcher path, as the caller resolved it.
        raw: The launcher bytes.

    Raises:
        Error: With Python's text when the launcher is not a supported wheel.
    """
    var newline = -1
    for index in range(len(raw)):
        if raw[index] == 10:
            newline = index
            break
    var interpreter = String()
    if newline >= 2:
        var bytes = List[UInt8]()
        for index in range(2, newline):
            bytes.append(raw[index])
        interpreter = String(from_utf8_lossy=bytes)
    var base = interpreter
    var slash = interpreter.rfind("/")
    if slash >= 0:
        base = String(interpreter[byte = slash + 1 :])
    if (
        newline < 0
        or not interpreter.startswith("/")
        or not isfile(interpreter)
        or (
            base != "python"
            and base != "python3"
            and base != "python3.12"
            and base != "python3.13"
            and base != "python3.14"
        )
    ):
        raise Error(
            "Unsupported Mojo launcher interpreter; use the official wheel"
            " entry point"
        )
    var environment = _resolve(_parent(_parent(path)))
    if _resolve(_parent(interpreter)) != _resolve(environment + "/bin"):
        raise Error("Mojo interpreter belongs to a different environment")
    var config = environment + "/pyvenv.cfg"
    if not isfile(config):
        raise Error("Missing supported Mojo virtual environment configuration")
    var fields_key = List[String]()
    var fields_value = List[String]()
    for line in _lines(Path(config).read_text()):
        var split = line.find("=")
        if split < 0:
            continue
        var key = _lower(_strip(String(line[byte=:split])))
        var value = _strip(String(line[byte = split + 1 :]))
        for have in fields_key:
            if have == key:
                raise Error("Duplicate Mojo virtual environment setting")
        fields_key.append(key)
        fields_value.append(value)
    var include = String()
    var home = String()
    for index in range(len(fields_key)):
        if fields_key[index] == "include-system-site-packages":
            include = fields_value[index]
        elif fields_key[index] == "home":
            home = fields_value[index]
    if _lower(include) != "false":
        raise Error("Mojo environment must exclude system site-packages")
    # `resolve()` follows the interpreter link before the parent is taken.
    if _resolve(home) != _parent(_resolve(interpreter)):
        raise Error(
            "Mojo virtual environment home does not match its interpreter"
        )
    var sites = List[String]()
    var lib = environment + "/lib"
    if isdir(lib):
        for name in listdir(lib):
            if name.startswith("python"):
                var candidate = lib + "/" + name + "/site-packages"
                if exists(candidate):
                    sites.append(candidate)
    if len(sites) != 1:
        raise Error("Ambiguous or missing Mojo wheel site-packages")
    var site = sites[0]
    _reject_overrides()
    if isdir(site):
        for name in listdir(site):
            if (
                name.endswith(".pth")
                or name.startswith("sitecustomize")
                or name.startswith("usercustomize")
            ):
                raise Error("Unsupported Mojo environment import redirection")
    var bin_dir = _parent(path)
    if isdir(bin_dir):
        for name in listdir(bin_dir):
            var child = bin_dir + "/" + name
            if isdir(child) and name != "__pycache__":
                raise Error("Unsupported Mojo launcher-directory import shadow")
            var suffix = _suffix(name)
            if (
                suffix == ".py"
                or suffix == ".pyc"
                or suffix == ".so"
                or suffix == ".pyd"
            ):
                raise Error("Unsupported Mojo launcher-directory import shadow")
    var mojo_dir = site + "/mojo"
    if isdir(mojo_dir):
        for name in listdir(mojo_dir):
            if name.startswith("__init__"):
                raise Error(
                    "Unsupported non-namespace Mojo package initialization"
                )
    var probe = run_program(
        [interpreter, "-I", "-B", "-c", _PROBE], 30.0, merge_errors=False
    )
    if probe.status != 0:
        raise Error("Mojo interpreter identity probe failed")
    var parsed = PyJson.parse(probe.output)
    var root = parsed.root
    if parsed.kind(root) != PY_DICT:
        raise Error("Mojo interpreter identity probe failed")
    var implementation = parsed.at(root, "implementation")
    var prefix = parsed.at(root, "prefix")
    var user_site = parsed.at(root, "user_site")
    var customizers = parsed.at(root, "customizers")
    if (
        parsed.kind(implementation) != PY_STR
        or parsed.text(implementation) != "cpython"
        or parsed.kind(prefix) != PY_STR
        or _resolve(parsed.text(prefix)) != environment
        or parsed.kind(user_site) != PY_BOOL
        or parsed.flag(user_site)
        or parsed.kind(customizers) != PY_LIST
        or parsed.length(customizers) != 0
    ):
        raise Error(
            "Unsupported Mojo interpreter environment or import customization"
        )
    var site_real = _resolve(site)
    var probe_sites = List[String]()
    for place in _string_list(parsed, parsed.at(root, "sites")):
        var real = _resolve(place)
        var seen = False
        for have in probe_sites:
            if have == real:
                seen = True
                break
        if not seen:
            probe_sites.append(real)
    var wanted_sites = List[String]()
    wanted_sites.append(site_real)
    if not _same_set(probe_sites, wanted_sites):
        raise Error(
            "Mojo interpreter site-packages does not match its environment"
        )
    var packages = _string_list(parsed, parsed.at(root, "mojo_paths"))
    var wanted_mojo = _resolve(mojo_dir)
    if len(packages) != 1 or _resolve(packages[0]) != wanted_mojo:
        raise Error("Mojo package resolution does not match its bound payload")
    var entry = parsed.at(root, "entrypoint")
    var entry_path = String()
    if parsed.kind(entry) == PY_STR:
        entry_path = parsed.text(entry)
    elif parsed.kind(entry) != PY_NONE:
        raise Error(
            "Mojo entrypoint resolution does not match its bound payload"
        )
    if _resolve(entry_path) != _resolve(mojo_dir + "/_entrypoints.py"):
        raise Error(
            "Mojo entrypoint resolution does not match its bound payload"
        )
    parsed.remove(root, "prefix")
    parsed.remove(root, "user_site")
    parsed.remove(root, "customizers")
    parsed.remove(root, "sites")
    parsed.remove(root, "mojo_paths")
    parsed.remove(root, "entrypoint")
    var names = List[String]()
    var paths = List[String]()
    var versions = doc.new_dict()
    for package in materialize[_PACKAGES]():
        var metadata = List[String]()
        var prefix_name = package + "-"
        if isdir(site):
            for name in listdir(site):
                if name.startswith(prefix_name) and name.endswith(".dist-info"):
                    var meta = site + "/" + name + "/METADATA"
                    if exists(meta):
                        metadata.append(meta)
        if len(metadata) != 1:
            raise Error(
                "Ambiguous or missing Mojo compiler distribution metadata"
            )
        var meta_path = metadata[0]
        var meta_text = Path(meta_path).read_text()
        var dist_name = _field(meta_text, "Name: ")
        var dist_version = _field(meta_text, "Version: ")
        if dist_name.byte_length() == 0 or dist_version.byte_length() == 0:
            raise Error("Malformed Mojo compiler distribution metadata")
        var dist = doc.new_dict()
        doc.set(dist, "version", doc.new_str(dist_version))
        doc.set(dist, "metadata_sha256", doc.new_str(_hash_file(meta_path)))
        doc.set(versions, dist_name, dist)
        var record = _parent(meta_path) + "/RECORD"
        for line in _lines(Path(record).read_text()):
            var row = _csv_row(line)
            if len(row) == 0 or row[0].byte_length() == 0:
                raise Error("Malformed Mojo compiler package inventory")
            if row[0].startswith("../../../bin/"):
                continue
            var relative = row[0] if row[0].startswith("/") else _normalize_row(
                row[0]
            )
            var full = relative if row[0].startswith("/") else _join(
                site, relative
            )
            if not _inside(_resolve(full), site_real):
                raise Error("Escaped Mojo compiler package inventory")
            if row[0].find(".dist-info") >= 0 or _skip_payload(full):
                continue
            if row[0].startswith("/"):
                if full.startswith(site + "/"):
                    _add_file(names, paths, _relative(full, site), full)
            else:
                _add_file(names, paths, relative, full)
    for folder in [mojo_dir, site + "/modular/lib/mojo"]:
        if not isdir(folder):
            raise Error("Incomplete supported Mojo compiler payload")
        var ancestors = List[String]()
        _walk(folder, site, names, paths, ancestors)
    var has_driver = False
    var has_linker = False
    for name in names:
        if name == "modular/bin/mojo":
            has_driver = True
        elif name == "modular/bin/lld":
            has_linker = True
    if not has_driver or not has_linker:
        raise Error("Incomplete supported Mojo driver/linker inventory")
    var payload = doc.new_dict()
    for index in range(len(names)):
        var full = paths[index]
        if not isfile(full) or not _inside(_resolve(full), site_real):
            raise Error("Missing or escaped Mojo payload file")
        doc.set(payload, names[index], doc.new_str(_hash_file(full)))
    var body = List[UInt8]()
    for index in range(newline + 1, len(raw)):
        body.append(raw[index])
    var interpreter_node = doc.new_dict()
    doc.set(
        interpreter_node,
        "sha256",
        doc.new_str(_hash_file(_resolve(interpreter))),
    )
    doc.set(interpreter_node, "capabilities", doc.adopt(parsed, root))
    doc.set(item, "kind", doc.new_str("mojo-wheel-python-entry-v1"))
    doc.set(item, "launcher_body_sha256", doc.new_str(_hash_list(body)))
    doc.set(item, "interpreter", interpreter_node)
    doc.set(item, "distributions", versions)
    doc.set(item, "payload", payload)


def _apply_identity(mut doc: PyJson, item: Int, path: String) raises:
    """Add the identity of one executable to its command word.

    Args:
        doc: The checkpoint document.
        item: The command-word dict.
        path: The executable.

    Raises:
        Error: When a wheel launcher is not supported, or a file cannot be
            read.
    """
    var raw = Path(path).read_bytes()
    if (
        len(raw) < 2
        or raw[0] != 35
        or raw[1] != 33
        or not _contains(raw, _MARKER)
    ):
        doc.set(item, "sha256", doc.new_str(_hash_list(raw)))
        return
    _apply_wheel(doc, item, path, raw)


def _command_words(
    mut doc: PyJson, words: List[String], root: String, build: String
) raises -> Int:
    """Return the identity of compiler words.

    Args:
        doc: The checkpoint document.
        words: The command words, already split.
        root: The resolved repository root.
        build: The resolved build directory.

    Returns:
        A list node.

    Raises:
        Error: When the command is empty or an executable is missing.
    """
    if len(words) == 0:
        raise Error("Compiler invocation identity is required")
    var items = doc.new_list()
    for index in range(len(words)):
        var word = words[index]
        var item = doc.new_dict()
        if index == 0:
            var path = _executable(word, root)
            doc.set(item, "path", doc.new_str(_symbolic(path, root, build)))
            _apply_identity(doc, item, path)
        else:
            var candidate = _join(root, word)
            var found = False
            if isfile(candidate):
                found = True
            else:
                var looked = _which(word)
                if looked.byte_length() > 0 and isfile(looked):
                    candidate = looked
                    found = True
            if found:
                doc.set(
                    item, "path", doc.new_str(_symbolic(candidate, root, build))
                )
                _apply_identity(doc, item, candidate)
            else:
                doc.set(item, "literal", doc.new_str(word))
        doc.append(items, item)
    return items


def _command(
    mut doc: PyJson, command: String, root: String, build: String
) raises -> Int:
    """Return the identity of a compiler command.

    Args:
        doc: The checkpoint document.
        command: The command text.
        root: The resolved repository root.
        build: The resolved build directory.

    Returns:
        A list node.

    Raises:
        Error: When the command is empty or an executable is missing.
    """
    return _command_words(doc, _shlex(command), root, build)


def _duplicates(names: List[String]) -> Bool:
    """Return whether a source list repeats a name.

    Args:
        names: The source names.

    Returns:
        True when a name appears twice.
    """
    for index in range(len(names)):
        for other in range(index + 1, len(names)):
            if names[index] == names[other]:
                return True
    return False


def _python_version() raises -> String:
    """Return `sys.version` of the `python3` on `PATH`.

    Returns:
        The version text, with no added newline.

    Raises:
        Error: If `python3` cannot be run.
    """
    var ran = run_program(
        ["python3", "-c", "import sys; sys.stdout.write(sys.version)"],
        30.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error("Cannot read the Python version")
    return ran.output


def _checkpoint(
    root: String,
    build: String,
    compiler: String,
    flags: String,
    mojo: String,
    sources: List[String],
) raises -> String:
    """Return the canonical checkpoint text, without its final newline.

    Args:
        root: The repository root.
        build: The build directory.
        compiler: The compiler text.
        flags: The flag text.
        mojo: The producer command.
        sources: The module names, in command order.

    Returns:
        The canonical JSON text.

    Raises:
        Error: With Python's text when a source, input, or compiler is not
            acceptable.
    """
    var root_real = _resolve(root)
    var build_real = _resolve(build)
    if len(sources) == 0 or _duplicates(sources):
        raise Error("Generation requires distinct source identities")
    for name in sources:
        if not name.endswith(".mojo"):
            raise Error("Generation source must be a Mojo module")
        if _invalid_source(name):
            raise Error("Invalid coverage source identity: " + py_repr(name))
        var full = _join(root_real, name)
        if not isfile(full) or not _inside(_resolve(full), root_real):
            raise Error("Missing or escaped coverage source: " + name)
    var doc = PyJson()
    var tree = doc.new_dict()
    doc.root = tree
    doc.set(tree, "schema", doc.new_str("coverage-generation-v1"))
    var inputs = doc.new_dict()
    for relative in input_paths(root_real):
        if _invalid_source(relative):
            raise Error(
                "Invalid coverage source identity: " + py_repr(relative)
            )
        var full = _join(root_real, relative)
        if not isfile(full) or not _inside(_resolve(full), root_real):
            raise Error("Missing or escaped coverage source: " + relative)
        if _inside(_resolve(full), build_real):
            continue
        doc.set(inputs, relative, doc.new_str(_hash_file(full)))
    doc.set(tree, "root_inputs", inputs)
    doc.set(tree, "python", doc.new_str(_python_version()))
    doc.set(tree, "compiler", doc.new_str(compiler))
    doc.set(tree, "flags", doc.new_str(flags))
    doc.set(
        tree, "compiler_command", _command(doc, mojo, root_real, build_real)
    )
    var produced = doc.new_list()
    doc.append(produced, doc.new_str("run"))
    for word in _shlex(flags):
        doc.append(produced, doc.new_str(word))
    doc.append(produced, doc.new_str("coverage/build_cli.mojo"))
    doc.append(produced, doc.new_str("@BUILD@"))
    for name in sources:
        doc.append(produced, doc.new_str(name))
    doc.set(tree, "producer_arguments", produced)
    var source_list = doc.new_list()
    for name in sources:
        doc.append(source_list, doc.new_str(name))
    doc.set(tree, "sources", source_list)
    return doc.dumps()


def _value(arguments: List[String], name: String, index: Int) raises -> String:
    """Return the value that follows a flag.

    Args:
        arguments: The command arguments.
        name: The flag.
        index: The position of the flag.

    Returns:
        The value.

    Raises:
        Error: When the flag is the last argument.
    """
    if index + 1 >= len(arguments):
        raise Error(_usage())
    return arguments[index + 1]


def _child(parent: String, name: String) -> String:
    """Return a path inside `parent`.

    Args:
        parent: The directory.
        name: The file name.

    Returns:
        The joined path.
    """
    if parent.endswith("/"):
        return parent + name
    return parent + "/" + name


def run_cli(arguments: List[String]) raises -> Int:
    """Write the generation checkpoint named on the command line.

    Args:
        arguments: The arguments after the program name.

    Returns:
        Zero after the checkpoint is written.

    Raises:
        Error: For a bad command line, or with the checkpoint's own text
            when a source or compiler cannot be bound.
    """
    var root = String()
    var build = String()
    var compiler = String()
    var flags = String()
    var mojo = String()
    var sources = List[String]()
    var taking = False
    var saw_root = False
    var saw_build = False
    var saw_compiler = False
    var saw_flags = False
    var saw_mojo = False
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if taking and not word.startswith("--"):
            sources.append(word)
            index += 1
            continue
        taking = False
        if word == "--root":
            root = _value(arguments, word, index)
            saw_root = True
            index += 2
        elif word.startswith("--root="):
            root = String(word[byte=7:])
            saw_root = True
            index += 1
        elif word == "--build":
            build = _value(arguments, word, index)
            saw_build = True
            index += 2
        elif word.startswith("--build="):
            build = String(word[byte=8:])
            saw_build = True
            index += 1
        elif word == "--compiler":
            compiler = _value(arguments, word, index)
            saw_compiler = True
            index += 2
        elif word.startswith("--compiler="):
            compiler = String(word[byte=11:])
            saw_compiler = True
            index += 1
        elif word == "--flags":
            flags = _value(arguments, word, index)
            saw_flags = True
            index += 2
        elif word.startswith("--flags="):
            flags = String(word[byte=8:])
            saw_flags = True
            index += 1
        elif word == "--mojo":
            mojo = _value(arguments, word, index)
            saw_mojo = True
            index += 2
        elif word.startswith("--mojo="):
            mojo = String(word[byte=7:])
            saw_mojo = True
            index += 1
        elif word == "--sources":
            taking = True
            index += 1
        elif word.startswith("--sources="):
            sources.append(String(word[byte=10:]))
            index += 1
        elif word == "--help" or word == "-h":
            raise Error(_usage())
        else:
            raise Error(_usage())
    if (
        not saw_root
        or not saw_build
        or not saw_compiler
        or not saw_flags
        or not saw_mojo
    ):
        raise Error(_usage())
    makedirs(build, exist_ok=True)
    var ready = _child(build, "origins.ready")
    Path(ready).write_text("")
    var checkpoint = _child(build, "generation-inputs.json")
    if islink(checkpoint) or exists(checkpoint):
        remove(checkpoint)
    var text = _checkpoint(root, build, compiler, flags, mojo, sources)
    Path(checkpoint).write_text(text + "\n")
    print("Coverage generation checkpoint prepared")
    return 0


def main() raises:
    """Write one coverage generation checkpoint."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(run_cli(arguments))
    except error:
        print("coverage_loop_begin: " + String(error), file=stderr)
        var text = String(error)
        if text.startswith("usage:"):
            exit(2)
        exit(1)
