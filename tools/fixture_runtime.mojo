# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reproduce a verified fixture family with its exact Node runtime.

    npm ci --ignore-scripts --prefix tools/fixture-runtime
    mojo run -I . tools/fixture_runtime.mojo vtk|js_number \\
        [--node NODE] [--dependencies DIR] [--diagnose-default-pow]

The tool checks every pin before it runs the generator: the manifest
metadata, the Node and V8 versions, the platform, the flags and the
installed package versions. The generator runs in a private temporary
directory, so the accepted files are never output targets. The tool prints
a JSON report. It exits with 0 only when the generated result matches the
accepted one, 1 when it differs, and 2 when a pin or a step fails.
`--diagnose-default-pow` runs `js_number` without its pinned flag to show
the differences; it never claims a reproduction.
"""

from std.ffi import c_int, external_call
from std.memory import bitcast
from std.os import getenv
from std.os.path import basename, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from loaders.json import JsonDocument, parse_json
from tools.fixture_manifest import (
    MANIFEST,
    digest,
    repository_root,
    runtime_metadata_errors,
)
from tools.json_tools import (
    MISSING,
    JsonWriter,
    equal,
    equals_text,
    get,
    index,
    keys,
    python_text,
)
from tools.process import run_program, shell_quote
from tools.sha256 import sha256_hex

comptime PACKAGES = "tools/fixture-runtime"
"""The locked Node packages, relative to the repository root."""
comptime TIMEOUT = 5
"""The time limit of each Node run, in seconds."""
comptime _HEX = "0123456789ABCDEF"
comptime _TABLE_START = "comptime _SRGB_TO_LINEAR: List[UInt64] = ["


def runtime_errors(
    observed: JsonDocument, manifest: JsonDocument, baseline: Int
) raises -> List[String]:
    """Return differences from the exact supported runtime, including V8.

    Args:
        observed: The runtime that Node reported.
        manifest: The parsed manifest.
        baseline: The family's `verified_runtime` node.

    Returns:
        One `KEY: expected X, got Y` message for each differing key.

    Raises:
        Error: If the baseline lacks one of the keys.
    """
    var errors = List[String]()
    for key in ["node", "v8", "platform", "arch"]:
        var expected = index(manifest, baseline, key)
        var actual = get(observed, observed.root(), key)
        if not equal(observed, actual, manifest, expected):
            errors.append(
                key
                + ": expected "
                + python_text(manifest, expected)
                + ", got "
                + python_text(observed, actual)
            )
    return errors^


def output_words(text: String) raises -> List[UInt64]:
    """Require 256 hexadecimal UInt64 words, without other generated text.

    Args:
        text: Words separated by commas or whitespace.

    Returns:
        The 256 words.

    Raises:
        Error: Unless there are exactly 256 words, each `0x` and 16
            hexadecimal digits.
    """
    var words = List[UInt64]()
    var count = 0
    for token in text.replace(",", " ").split():
        count += 1
        var bytes = token.as_bytes()
        var good = len(bytes) == 18 and bytes[0] == 0x30 and bytes[1] == 0x78
        var value = UInt64(0)
        if good:
            for i in range(2, 18):
                var digit = _hex_digit(bytes[i])
                if digit < 0:
                    good = False
                    break
                value = (value << 4) | UInt64(digit)
        if not good:
            raise Error("expected exactly 256 hexadecimal Float64 words")
        words.append(value)
    if count != 256:
        raise Error("expected exactly 256 hexadecimal Float64 words")
    return words^


def _hex_digit(byte: UInt8) -> Int:
    """Return a hexadecimal digit's value, or -1."""
    if byte >= 0x30 and byte <= 0x39:
        return Int(byte) - 0x30
    if byte >= 0x41 and byte <= 0x46:
        return Int(byte) - 0x41 + 10
    if byte >= 0x61 and byte <= 0x66:
        return Int(byte) - 0x61 + 10
    return -1


def table_words(source: String) raises -> List[UInt64]:
    """Read only the accepted sRGB table, with one word for each byte.

    Args:
        source: The text of `loaders/js_number.mojo`.

    Returns:
        The table's 256 words.

    Raises:
        Error: If the table is missing or malformed.
    """
    var start = source.find(_TABLE_START)
    if start < 0:
        raise Error("accepted sRGB table was not found")
    start += _TABLE_START.byte_length()
    var end = source.find("]", start)
    if end < 0:
        raise Error("accepted sRGB table was not found")
    return output_words(String(source[byte=start:end]))


def word_digest(words: List[UInt64]) -> String:
    """Hash Float64 words as 2048 bytes in big-endian order.

    Args:
        words: The words.

    Returns:
        The SHA-256 as lowercase hexadecimal digits.
    """
    var bytes = List[UInt8](capacity=8 * len(words))
    for word in words:
        for shift in range(7, -1, -1):
            bytes.append(UInt8((word >> UInt64(8 * shift)) & 0xFF))
    return sha256_hex(Span(bytes))


def word_text(word: UInt64) -> String:
    """Return `0x` and 16 uppercase hexadecimal digits.

    Args:
        word: The word.

    Returns:
        The text, as Python's `f'0x{word:016X}'` writes it.
    """
    var out = String("0x")
    for shift in range(15, -1, -1):
        out += chr(Int(_HEX.as_bytes()[Int((word >> UInt64(4 * shift)) & 15)]))
    return out^


def write_word_differences(
    accepted: List[UInt64], generated: List[UInt64], mut writer: JsonWriter
) raises:
    """Write each changed sRGB Float64 word and its Float32 effect.

    Args:
        accepted: The accepted words.
        generated: The generated words.
        writer: Receives an array of difference records.

    Raises:
        Error: If the word counts differ.
    """
    if len(accepted) != len(generated):
        raise Error("sRGB word counts differ")
    writer.begin_array()
    for byte in range(len(accepted)):
        var old = accepted[byte]
        var new = generated[byte]
        if old == new:
            continue
        var old_value = Float32(bitcast[DType.float64](old))
        var new_value = Float32(bitcast[DType.float64](new))
        writer.begin_object()
        writer.key("byte")
        writer.integer(byte)
        writer.key("accepted")
        writer.string(word_text(old))
        writer.key("generated")
        writer.string(word_text(new))
        writer.key("ulp_delta")
        writer.integer(Int(new) - Int(old))
        writer.key("float32_unchanged")
        writer.boolean(
            bitcast[DType.uint32](old_value) == bitcast[DType.uint32](new_value)
        )
        writer.end()
    writer.end()


def _command_text(arguments: List[String]) -> String:
    """Return a command as Python's list representation prints it."""
    var out = String("[")
    for i in range(len(arguments)):
        if i > 0:
            out += ", "
        out += "'" + arguments[i].replace("'", "\\'") + "'"
    return out + "]"


def node_output(
    arguments: List[String], directory: String = ""
) raises -> String:
    """Run Node, keep its standard error visible, and return its output.

    Args:
        arguments: Node and its arguments.
        directory: The working directory, or empty for the current one.

    Returns:
        The standard output.

    Raises:
        Error: As Python's `check_output` did, for a time-out or a non-zero
            exit status.
    """
    var result = run_program(
        arguments, Float64(TIMEOUT), merge_errors=False, directory=directory
    )
    print(result.errors, end="", file=stderr)
    if result.timed_out:
        raise Error(
            "Command '"
            + _command_text(arguments)
            + "' timed out after "
            + String(TIMEOUT)
            + " seconds"
        )
    if result.status != 0:
        raise Error(
            "Command '"
            + _command_text(arguments)
            + "' returned non-zero exit status "
            + String(result.status)
            + "."
        )
    return result.output


def reproduce(
    root: String,
    manifest: JsonDocument,
    family: Int,
    node: String,
    dependencies: String,
    diagnose_default_pow: Bool,
) raises -> Tuple[String, Bool]:
    """Check pins before running the generator; return a comparison report.

    Args:
        root: The repository root.
        manifest: The parsed manifest.
        family: The family node.
        node: The Node executable.
        dependencies: The installed `node_modules` directory.
        diagnose_default_pow: True to run `js_number` without its pinned
            flag.

    Returns:
        The report text and whether the result matches.

    Raises:
        Error: If a pin differs or a step fails.
    """
    var name = manifest.string(index(manifest, family, "family"))
    if name != "vtk" and name != "js_number":
        raise Error("this family has no supported runtime verifier")
    var baseline = index(manifest, family, "verified_runtime")
    if getenv("NODE_OPTIONS").byte_length() > 0:
        raise Error("unset NODE_OPTIONS before fixture verification")
    var flags = List[String]()
    var flag_node = index(manifest, baseline, "node_flags")
    for i in range(manifest.length(flag_node)):
        flags.append(manifest.string(manifest.at(flag_node, i)))
    var pow_flag = List[String]()
    pow_flag.append("--no-use-std-math-pow")
    if name == "js_number" and flags != pow_flag:
        raise Error("the accepted sRGB baseline requires --no-use-std-math-pow")
    if name == "vtk" and len(flags) > 0:
        raise Error("the verified VTK baseline has no extra Node flags")
    var metadata = runtime_metadata_errors(root, manifest, family)
    if len(metadata) > 0:
        raise Error(String("; ").join(metadata))
    if diagnose_default_pow:
        if name != "js_number":
            raise Error("--diagnose-default-pow is only for js_number")
        flags = List[String]()
    var probe = List[String]()
    probe.append(node)
    probe.extend(flags.copy())
    probe.append("-p")
    probe.append(
        "JSON.stringify({node:process.versions.node,v8:process.versions.v8,"
        + "platform:process.platform,arch:process.arch})"
    )
    var observed = parse_json(node_output(probe))
    var errors = runtime_errors(observed, manifest, baseline)
    var expected_packages = index(manifest, baseline, "dependencies")
    var package_names = keys(manifest, expected_packages)
    var package_versions = List[String]()
    for package in package_names:
        var expected = manifest.get(expected_packages, package)
        var document = parse_json(
            Path(dependencies + "/" + package + "/package.json").read_text()
        )
        var actual = index(document, document.root(), "version")
        package_versions.append(python_text(document, actual))
        if not equal(document, actual, manifest, expected):
            errors.append(
                package
                + ": expected "
                + python_text(manifest, expected)
                + ", got "
                + python_text(document, actual)
            )
    if len(errors) > 0:
        raise Error(String("; ").join(errors))
    var generator = (
        root + "/" + manifest.string(index(manifest, family, "generator"))
    )
    if not equals_text(
        manifest, index(manifest, family, "generator_sha256"), digest(generator)
    ):
        raise Error("generator differs from the accepted manifest")

    var writer = JsonWriter()
    writer.begin_object()
    writer.key("family")
    writer.string(name)
    writer.key("runtime")
    writer.begin_object()
    var wrote_flags = False
    for key in keys(observed, observed.root()):
        writer.key(key)
        if key == "node_flags":
            _write_strings(writer, flags)
            wrote_flags = True
        else:
            writer.node(observed, observed.get(observed.root(), key))
    if not wrote_flags:
        writer.key("node_flags")
        _write_strings(writer, flags)
    writer.end()
    writer.key("dependencies")
    writer.begin_object()
    for i in range(len(package_names)):
        writer.key(package_names[i])
        writer.string(package_versions[i])
    writer.end()
    writer.key("generator_sha256")
    writer.string(digest(generator))
    writer.key("historical_environment_recovered")
    writer.boolean(False)
    writer.key("mode")
    writer.string(
        "diagnostic_only" if diagnose_default_pow else "verify_accepted"
    )

    # Each generator runs in a private working directory. The accepted
    # files are never output targets. No package install runs in this tool.
    var work = mkdtemp(prefix="threemojo-fixture-")
    var matches: Bool
    try:
        var link = work + "/node_modules"
        var target = realpath(dependencies)
        if external_call["symlink", c_int](
            target.as_c_string_span().ptr(), link.as_c_string_span().ptr()
        ):
            raise Error("cannot link node_modules")
        var copy = work + "/" + basename(generator)
        Path(copy).write_bytes(Span(Path(generator).read_bytes()))
        var run = List[String]()
        run.append(node)
        run.extend(flags.copy())
        run.append(basename(generator))
        var generated = node_output(run, work)
        var artifacts = index(manifest, family, "artifacts")
        if name == "vtk":
            matches = True
            writer.key("artifacts")
            writer.begin_array()
            for path in keys(manifest, artifacts):
                var actual = digest(work + "/" + basename(path))
                var same = equals_text(
                    manifest, manifest.get(artifacts, path), actual
                )
                matches = matches and same
                writer.begin_object()
                writer.key("path")
                writer.string(path)
                writer.key("sha256")
                writer.string(actual)
                writer.key("matches")
                writer.boolean(same)
                writer.end()
            writer.end()
            writer.key("matches")
            writer.boolean(matches)
        else:
            var table = root + "/loaders/js_number.mojo"
            if not equals_text(
                manifest,
                index(manifest, artifacts, "loaders/js_number.mojo"),
                digest(table),
            ):
                raise Error("accepted sRGB source differs from the manifest")
            var accepted = table_words(Path(table).read_text())
            var words = output_words(generated)
            matches = accepted == words
            writer.key("word_count")
            writer.integer(len(words))
            writer.key("accepted_words_sha256")
            writer.string(word_digest(accepted))
            writer.key("generated_words_sha256")
            writer.string(word_digest(words))
            writer.key("differences")
            write_word_differences(accepted, words, writer)
            writer.key("not_regenerated")
            writer.begin_array()
            writer.string("assets/js_number/v8.json")
            writer.end()
            writer.key("matches")
            writer.boolean(matches)
    finally:
        _ = run_program(["rm", "-rf", work], 60)
    writer.end()
    return (writer.text(), matches)


def _write_strings(mut writer: JsonWriter, items: List[String]):
    """Write an array of strings."""
    writer.begin_array()
    for item in items:
        writer.string(item)
    writer.end()


comptime USAGE = (
    "usage: fixture_runtime.mojo [-h] [--node NODE] [--dependencies"
    " DEPENDENCIES] [--diagnose-default-pow] {js_number,vtk}"
)


def _usage_error(message: String):
    """Print a usage error and exit with status 2, as `argparse` does."""
    print(USAGE, file=stderr)
    print("fixture_runtime.mojo: error: " + message, file=stderr)
    exit(2)


def main() raises:
    var arguments = argv()
    var root = repository_root()
    var family_name = String()
    var node = String("node")
    var dependencies = root + "/" + PACKAGES + "/node_modules"
    var diagnose = False
    var i = 1
    while i < len(arguments):
        var argument = String(arguments[i])
        i += 1
        if argument == "-h" or argument == "--help":
            print(USAGE)
            return
        if argument == "--diagnose-default-pow":
            diagnose = True
            continue
        var option = argument
        var value = String()
        var has_value = False
        var equals = argument.find("=")
        if argument.startswith("--") and equals >= 0:
            option = String(argument[byte=:equals])
            value = String(argument[byte = equals + 1 :])
            has_value = True
        if option == "--node" or option == "--dependencies":
            if not has_value:
                if i >= len(arguments):
                    _usage_error(
                        "argument " + option + ": expected one argument"
                    )
                value = String(arguments[i])
                i += 1
            if option == "--node":
                node = value
            else:
                dependencies = value
        elif argument.startswith("-"):
            _usage_error("unrecognized arguments: " + argument)
        elif family_name.byte_length() > 0:
            _usage_error("unrecognized arguments: " + argument)
        else:
            family_name = argument
    if family_name.byte_length() == 0:
        _usage_error("the following arguments are required: family")
    if family_name != "vtk" and family_name != "js_number":
        _usage_error(
            "argument family: invalid choice: '"
            + family_name
            + "' (choose from js_number, vtk)"
        )
    var manifest = parse_json(Path(root + "/" + MANIFEST).read_text())
    var families = index(manifest, manifest.root(), "families")
    var family = MISSING
    for k in range(manifest.length(families)):
        var candidate = manifest.at(families, k)
        if equals_text(
            manifest, get(manifest, candidate, "family"), family_name
        ):
            family = candidate
            break
    var report: Tuple[String, Bool]
    try:
        report = reproduce(root, manifest, family, node, dependencies, diagnose)
    except error:
        print("Fixture verification failed: " + String(error), file=stderr)
        exit(2)
        return
    print(report[0])
    exit(0 if report[1] and not diagnose else 1)
