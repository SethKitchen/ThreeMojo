# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Project the copied sampled helpers and the value dispatchers.

Python still compares the constant heading and the lane capture with its
own syntax tree. This pass writes every other reviewed helper.
"""

from tests._python_expr import require_sampled_roles
from tests._python_tokens import (
    decorator_prefix_json,
    project_reference_value,
    project_union_value,
)
from tools._python_json import PyJson
from tools._sampled_closure import sampled_closure
from tools._sampled_copies import sampled_copies
from tools._sampled_declarations import sampled_declarations
from tools._sampled_projection_recipe import sampled_projection_recipe
from tools._sampled_value_gate import (
    drop_derivative_intersection,
    extract_sampled_function,
    rename_sampled_identifiers,
)


def _fail() raises:
    """Raise the reviewed projection-step failure.

    Raises:
        Error: The projection step is not one of the reviewed kinds.
    """
    var doc = PyJson.parse(sampled_closure())
    raise Error(doc.text(doc.at(doc.root, "step")))


def _module_source(
    module: String,
    bounds_name: String,
    bounds: String,
    trig_name: String,
    trig: String,
) raises -> String:
    """Return the source for one reviewed module name.

    Args:
        module: The module file name from the recipe.
        bounds_name: The bounds module file name.
        bounds: The bounds source.
        trig_name: The trig module file name.
        trig: The trig source.

    Returns:
        The source for `module`.

    Raises:
        Error: The module is neither bounds nor trig.
    """
    if module == bounds_name:
        return bounds
    if module == trig_name:
        return trig
    _fail()
    return ""


def _renamed(source: String, name: String) raises -> String:
    """Return one helper with sampled identifiers.

    Args:
        source: The module that declares `name`.
        name: The jet helper name.

    Returns:
        The renamed declaration.

    Raises:
        Error: The helper is missing.
    """
    return rename_sampled_identifiers(extract_sampled_function(source, name))


def _module_prefix(
    mut bounds_doc: PyJson,
    mut trig_doc: PyJson,
    module: String,
    trig_name: String,
    name: String,
) raises -> String:
    """Return one function's decorator prefix from the module that owns it.

    Args:
        bounds_doc: Prefixes from the bounds module.
        trig_doc: Prefixes from the trig module.
        module: The module file name.
        trig_name: The trig module file name.
        name: The function name.

    Returns:
        The decorator text, or an empty string.

    Raises:
        Error: The function is absent from that module's map.
    """
    if module == trig_name:
        return _prefix(trig_doc, name)
    return _prefix(bounds_doc, name)


def _prefix(mut doc: PyJson, name: String) raises -> String:
    """Return one function's decorator prefix.

    Args:
        doc: The prefix map for one module.
        name: The function name.

    Returns:
        The decorator text, or an empty string.

    Raises:
        Error: The function is absent from the map.
    """
    return doc.text(doc.at(doc.root, name))


def _projected(mode: String, source: String) raises -> String:
    """Return one value dispatcher for a project mode.

    Args:
        mode: `--project-union` or `--project-reference`.
        source: The renamed helper.

    Returns:
        The projected declaration.

    Raises:
        Error: The mode is not one of those two.
    """
    if mode == "--project-union":
        return project_union_value(source)
    if mode == "--project-reference":
        return project_reference_value(source)
    _fail()
    return ""


def project_reviewed_helpers(bounds: String, trig: String) raises -> String:
    """Return the copied helpers and the value dispatchers.

    Args:
        bounds: The current `curve_bounds.mojo` source.
        trig: The current `curve_trig.mojo` source.

    Returns:
        JSON object. Each key is a sampled helper name and each value is
        its projected source. Constant and lane helpers are absent.

    Raises:
        Error: A helper, a role list, or a projection step changed.
    """
    var recipe = PyJson.parse(sampled_projection_recipe())
    var copies = PyJson.parse(sampled_copies())
    var declarations = PyJson.parse(sampled_declarations())
    var bounds_name = recipe.text(recipe.at(recipe.root, "bounds_module"))
    var trig_name = recipe.text(recipe.at(recipe.root, "trig_module"))
    var prefix = recipe.text(recipe.at(recipe.root, "trig_prefix"))
    var blend = recipe.at(recipe.root, "blend")
    var blend_name = recipe.text(recipe.at(blend, "name"))
    var names = copies.at(copies.root, "names")
    var bounds_decorators = PyJson.parse(decorator_prefix_json(bounds))
    var trig_decorators = PyJson.parse(decorator_prefix_json(trig))
    var out = PyJson()
    var result = out.new_dict()
    var listed = copies.at(copies.root, "copies")
    var count = copies.length(listed)
    var index = 0
    while index < count:
        var name = copies.text(copies.item(listed, index))
        var source = bounds
        var module_name = bounds_name
        if name.startswith(prefix):
            source = trig
            module_name = trig_name
        var renamed = _renamed(source, name)
        if name == blend_name:
            var fields = recipe.at(blend, "fields")
            var field_count = recipe.length(fields)
            var field_index = 0
            while field_index < field_count:
                renamed = drop_derivative_intersection(
                    renamed, recipe.text(recipe.item(fields, field_index))
                )
                field_index += 1
        var decorated = _module_prefix(
            bounds_decorators,
            trig_decorators,
            module_name,
            trig_name,
            name,
        )
        out.set(
            result,
            copies.text(copies.at(names, name)),
            out.new_str(decorated + renamed),
        )
        index += 1
    var declaration_count = declarations.length(declarations.root)
    var declaration_index = 0
    while declaration_index < declaration_count:
        var key = declarations.key(declarations.root, declaration_index)
        out.set(
            result,
            key,
            out.new_str(
                declarations.text(declarations.at(declarations.root, key))
            ),
        )
        declaration_index += 1
    var steps = recipe.at(recipe.root, "steps")
    var step_count = recipe.length(steps)
    var step_index = 0
    while step_index < step_count:
        var step = recipe.item(steps, step_index)
        var kind = recipe.text(recipe.at(step, "kind"))
        if kind == "project":
            var module = recipe.text(recipe.at(step, "module"))
            var helper = recipe.text(recipe.at(step, "name"))
            var old = _renamed(
                _module_source(module, bounds_name, bounds, trig_name, trig),
                helper,
            )
            require_sampled_roles(old, recipe.text(recipe.at(step, "role")))
            out.set(
                result,
                recipe.text(recipe.at(step, "target")),
                out.new_str(
                    _projected(recipe.text(recipe.at(step, "mode")), old)
                ),
            )
        elif kind == "rename":
            var pairs = recipe.at(step, "pairs")
            var pair_count = recipe.length(pairs)
            var pair_index = 0
            while pair_index < pair_count:
                var pair = recipe.item(pairs, pair_index)
                var old_name = recipe.text(recipe.item(pair, 0))
                var module = recipe.text(recipe.item(pair, 1))
                var source = _module_source(
                    module, bounds_name, bounds, trig_name, trig
                )
                var decorated = _module_prefix(
                    bounds_decorators,
                    trig_decorators,
                    module,
                    trig_name,
                    old_name,
                )
                out.set(
                    result,
                    copies.text(copies.at(names, old_name)),
                    out.new_str(decorated + _renamed(source, old_name)),
                )
                pair_index += 1
        elif kind != "constant" and kind != "lane":
            _fail()
        step_index += 1
    out.root = result
    return out.dumps()
