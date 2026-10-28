# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Slice, rename, edit, or classify one sampled declaration.

    carla_sampled_text --extract PATH --name NAME
    carla_sampled_text --rename PATH
    carla_sampled_text --drop-intersection PATH --name first|second
    carla_sampled_text --body-roles PATH
    carla_sampled_text --check-roles PATH --name KIND
    carla_sampled_text --body-dump PATH --index N
    carla_sampled_text --return-elts PATH --index N
    carla_sampled_text --return-pair PATH --index N
    carla_sampled_text --top-level PATH --name NAMES
    carla_sampled_text --project-constant PATH
    carla_sampled_text --project-union PATH
    carla_sampled_text --project-reference PATH
    carla_sampled_text --project-lane PATH
    carla_sampled_text --decorators PATH --name NAME
    carla_sampled_text --strip-try-only PATH
    carla_sampled_text --replace-function PATH --name NAME --with PATH
    carla_sampled_text --primitive-aliases PATH
    carla_sampled_text --primitive-declaration PATH
    carla_sampled_text --stored-half-tail PATH
    carla_sampled_text --helper-then-syntax PRIMITIVE TARGET

The extract mode prints one top-level function. The rename mode prints the
declaration with sampled identifiers renamed. The drop mode removes the first
derivative intersection. The body-roles mode prints JSON statement roles.
The check-roles mode requires one reviewed role list.
The body-dump mode prints one statement dump. The return-elts mode prints
JSON dumps of a returned tuple, or null. The return-pair mode requires two
elements and prints those dumps. The top-level mode checks helper
names and statement kinds. The project-constant mode prints the unknown-interval
heading. The project-union mode prints the value-only union signature.
The project-reference mode prints the sampled dispatcher.
The project-lane mode prints the value-only lane dispatcher.
The decorators mode prints the lines above one function.
The strip-try-only mode removes the reviewed reuse refusal.
The replace-function mode substitutes one complete function.
The primitive-aliases mode checks the two derivative aliases.
The primitive-declaration mode requires one Jet primitive.
The stored-half-tail mode prints the source from that declaration onward.
The caller supplies the source.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import (
    body_role_json,
    body_statement_json,
    require_return_pair,
    require_sampled_roles,
    return_elements_json,
)
from tests._python_tokens import (
    primitive_aliases,
    primitive_declaration,
    project_constant_heading,
    decorator_prefix,
    replace_function,
    stored_half_tail,
    strip_try_only_refusal,
    project_lane_value,
    project_reference_value,
    project_union_value,
    sampled_top_level,
)
from tools._sampled_closure import strip_sampled_gates
from tools._sampled_jet_gate import stored_helper_fields
from tools._sampled_value_gate import (
    drop_derivative_intersection,
    extract_sampled_function,
    rename_sampled_identifiers,
    sampled_value_fields,
    sampled_value_imports,
)
from tools.carla_cleanup_gate import classified_syntax_json


def helper_fields_then_syntax(
    primitive: String, target: String
) raises -> String:
    """Check the stored helpers, then prepare the lane-value syntax.

    Args:
        primitive: The interval module.
        target: The lane-value module.

    Returns:
        The syntax JSON for `target`. The helper check runs before that
        syntax is prepared.

    Raises:
        Error: A stored helper changed, or the target syntax is unclosed
            or ambiguous. The helper check runs before the syntax is
            prepared.
    """
    stored_helper_fields(primitive)
    return classified_syntax_json(target)


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_sampled_text --extract PATH --name NAME | --rename"
            " PATH | --drop-intersection PATH --name first|second |"
            " --helper-fields PATH | --helper-then-syntax PRIMITIVE TARGET |"
            " --value-fields PATH | --value-imports PATH"
            " | --body-roles PATH | --check-roles PATH --name KIND |"
            " --body-dump PATH --index N | --return-elts PATH --index N |"
            " --return-pair PATH --index N | --top-level PATH --name NAMES |"
            " --project-constant PATH | --project-union PATH |"
            " --project-reference PATH | --project-lane PATH | --decorators"
            " PATH --name NAME | --strip-try-only PATH | --replace-function"
            " PATH --name NAME --with PATH | --primitive-aliases PATH |"
            " --stored-half-tail PATH | --primitive-declaration PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Slice, rename, or classify one sampled declaration.

    Raises:
        Error: The command is invalid, or the function is missing.
    """
    var extract = String("")
    var rename = String("")
    var drop = String("")
    var helper_fields = String("")
    var value_fields = String("")
    var value_imports = String("")
    var body_roles = String("")
    var check_roles = String("")
    var body_dump = String("")
    var return_elts = String("")
    var return_pair = String("")
    var top_level = String("")
    var project_constant = String("")
    var project_union = String("")
    var project_reference = String("")
    var project_lane = String("")
    var decorators = String("")
    var strip_try_only = String("")
    var replace_path = String("")
    var primitive_alias_path = String("")
    var primitive_declaration_path = String("")
    var stored_half = String("")
    var with_path = String("")
    var name = String("")
    var index_text = String("")
    var strip_gates = False
    var arguments = argv()
    if len(arguments) == 4 and arguments[1] == "--helper-then-syntax":
        try:
            print(
                helper_fields_then_syntax(
                    Path(arguments[2]).read_text(),
                    Path(arguments[3]).read_text(),
                ),
                end="",
            )
        except error:
            print(strip_sampled_gates(String(error)), file=stderr)
            exit(1)
        return
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--strip-gates":
            strip_gates = True
            index += 1
            continue
        if (
            word == "--extract"
            or word == "--rename"
            or word == "--drop-intersection"
            or word == "--helper-fields"
            or word == "--value-fields"
            or word == "--value-imports"
            or word == "--body-roles"
            or word == "--check-roles"
            or word == "--body-dump"
            or word == "--return-elts"
            or word == "--return-pair"
            or word == "--top-level"
            or word == "--project-constant"
            or word == "--project-union"
            or word == "--project-reference"
            or word == "--project-lane"
            or word == "--decorators"
            or word == "--strip-try-only"
            or word == "--replace-function"
            or word == "--primitive-aliases"
            or word == "--primitive-declaration"
            or word == "--stored-half-tail"
            or word == "--with"
            or word == "--index"
            or word == "--name"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--extract":
                extract = value
            elif word == "--rename":
                rename = value
            elif word == "--drop-intersection":
                drop = value
            elif word == "--helper-fields":
                helper_fields = value
            elif word == "--value-fields":
                value_fields = value
            elif word == "--value-imports":
                value_imports = value
            elif word == "--body-roles":
                body_roles = value
            elif word == "--check-roles":
                check_roles = value
            elif word == "--body-dump":
                body_dump = value
            elif word == "--return-elts":
                return_elts = value
            elif word == "--return-pair":
                return_pair = value
            elif word == "--top-level":
                top_level = value
            elif word == "--project-constant":
                project_constant = value
            elif word == "--project-union":
                project_union = value
            elif word == "--project-reference":
                project_reference = value
            elif word == "--project-lane":
                project_lane = value
            elif word == "--decorators":
                decorators = value
            elif word == "--strip-try-only":
                strip_try_only = value
            elif word == "--replace-function":
                replace_path = value
            elif word == "--primitive-aliases":
                primitive_alias_path = value
            elif word == "--primitive-declaration":
                primitive_declaration_path = value
            elif word == "--stored-half-tail":
                stored_half = value
            elif word == "--with":
                with_path = value
            elif word == "--index":
                index_text = value
            else:
                name = value
            index += 2
            continue
        _usage()
    var modes = 0
    if extract.byte_length() > 0:
        modes += 1
    if rename.byte_length() > 0:
        modes += 1
    if drop.byte_length() > 0:
        modes += 1
    if helper_fields.byte_length() > 0:
        modes += 1
    if value_fields.byte_length() > 0:
        modes += 1
    if value_imports.byte_length() > 0:
        modes += 1
    if body_roles.byte_length() > 0:
        modes += 1
    if check_roles.byte_length() > 0:
        modes += 1
    if body_dump.byte_length() > 0:
        modes += 1
    if return_elts.byte_length() > 0:
        modes += 1
    if return_pair.byte_length() > 0:
        modes += 1
    if top_level.byte_length() > 0:
        modes += 1
    if project_constant.byte_length() > 0:
        modes += 1
    if project_union.byte_length() > 0:
        modes += 1
    if project_reference.byte_length() > 0:
        modes += 1
    if project_lane.byte_length() > 0:
        modes += 1
    if decorators.byte_length() > 0:
        modes += 1
    if strip_try_only.byte_length() > 0:
        modes += 1
    if replace_path.byte_length() > 0:
        modes += 1
    if primitive_alias_path.byte_length() > 0:
        modes += 1
    if primitive_declaration_path.byte_length() > 0:
        modes += 1
    if stored_half.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if (
        extract.byte_length() > 0
        or drop.byte_length() > 0
        or top_level.byte_length() > 0
        or decorators.byte_length() > 0
        or replace_path.byte_length() > 0
        or check_roles.byte_length() > 0
    ) and name.byte_length() == 0:
        _usage()
    if rename.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    if body_roles.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    if project_constant.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    if project_union.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    if project_reference.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    if project_lane.byte_length() > 0 and name.byte_length() > 0:
        _usage()
    if replace_path.byte_length() > 0 and with_path.byte_length() == 0:
        _usage()
    if replace_path.byte_length() == 0 and with_path.byte_length() > 0:
        _usage()
    if (
        body_dump.byte_length() > 0
        or return_elts.byte_length() > 0
        or return_pair.byte_length() > 0
    ) and name.byte_length() > 0:
        _usage()
    if (
        body_dump.byte_length() > 0
        or return_elts.byte_length() > 0
        or return_pair.byte_length() > 0
    ) and index_text.byte_length() == 0:
        _usage()
    if (
        body_dump.byte_length() == 0
        and return_elts.byte_length() == 0
        and return_pair.byte_length() == 0
    ) and index_text.byte_length() > 0:
        _usage()
    var statement_index = 0
    if index_text.byte_length() > 0:
        try:
            statement_index = Int(index_text)
        except:
            _usage()
        if statement_index < 0:
            _usage()
    try:
        if extract.byte_length() > 0:
            print(
                extract_sampled_function(Path(extract).read_text(), name),
                end="",
            )
            return
        if drop.byte_length() > 0:
            print(
                drop_derivative_intersection(Path(drop).read_text(), name),
                end="",
            )
            return
        if helper_fields.byte_length() > 0:
            stored_helper_fields(Path(helper_fields).read_text())
            return
        if value_fields.byte_length() > 0:
            sampled_value_fields(Path(value_fields).read_text())
            return
        if value_imports.byte_length() > 0:
            sampled_value_imports(Path(value_imports).read_text())
            return
        if body_roles.byte_length() > 0:
            print(body_role_json(Path(body_roles).read_text()), end="")
            return
        if check_roles.byte_length() > 0:
            require_sampled_roles(Path(check_roles).read_text(), name)
            return
        if body_dump.byte_length() > 0:
            print(
                body_statement_json(
                    Path(body_dump).read_text(), statement_index
                ),
                end="",
            )
            return
        if return_elts.byte_length() > 0:
            print(
                return_elements_json(
                    Path(return_elts).read_text(), statement_index
                ),
                end="",
            )
            return
        if return_pair.byte_length() > 0:
            print(
                require_return_pair(
                    Path(return_pair).read_text(), statement_index
                ),
                end="",
            )
            return
        if top_level.byte_length() > 0:
            sampled_top_level(Path(top_level).read_text(), name)
            return
        if project_constant.byte_length() > 0:
            print(
                project_constant_heading(Path(project_constant).read_text()),
                end="",
            )
            return
        if project_union.byte_length() > 0:
            print(project_union_value(Path(project_union).read_text()), end="")
            return
        if project_reference.byte_length() > 0:
            print(
                project_reference_value(Path(project_reference).read_text()),
                end="",
            )
            return
        if project_lane.byte_length() > 0:
            print(project_lane_value(Path(project_lane).read_text()), end="")
            return
        if decorators.byte_length() > 0:
            print(decorator_prefix(Path(decorators).read_text(), name), end="")
            return
        if strip_try_only.byte_length() > 0:
            print(
                strip_try_only_refusal(Path(strip_try_only).read_text()),
                end="",
            )
            return
        if primitive_alias_path.byte_length() > 0:
            primitive_aliases(Path(primitive_alias_path).read_text())
            return
        if primitive_declaration_path.byte_length() > 0:
            primitive_declaration(Path(primitive_declaration_path).read_text())
            return
        if stored_half.byte_length() > 0:
            print(stored_half_tail(Path(stored_half).read_text()), end="")
            return
        if replace_path.byte_length() > 0:
            print(
                replace_function(
                    Path(replace_path).read_text(),
                    name,
                    Path(with_path).read_text(),
                ),
                end="",
            )
            return
        print(rename_sampled_identifiers(Path(rename).read_text()), end="")
    except error:
        var message = String(error)
        if strip_gates:
            message = strip_sampled_gates(message)
        print(message, file=stderr)
        exit(1)
