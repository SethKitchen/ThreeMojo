# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Project the copied sampled helpers and the value dispatchers.

Python still compares the constant heading and the lane capture with its
own syntax tree. This pass writes those helpers and the statement dumps
the comparison uses.
"""

from tests._python_expr import (
    body_statement_json,
    require_return_pair,
    require_sampled_roles,
    sampled_lane_dumps,
)
from tests._python_tokens import (
    decorator_prefix_json,
    project_constant_heading,
    project_lane_value,
    project_reference_value,
    project_union_value,
    sampled_top_level,
)
from tools._python_json import MISSING, PyJson
from tools._sampled_closure import sampled_closure
from tools._sampled_copies import sampled_copies
from tools._sampled_declarations import sampled_declarations
from tools._sampled_projection_recipe import sampled_projection_recipe
from tools._sampled_value_gate import (
    drop_derivative_intersection,
    extract_sampled_function,
    rename_sampled_identifiers,
    sampled_value_imports,
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
        JSON with `helpers`, `constant`, and `lane`. `helpers` maps each
        sampled name to its projected source. `constant` holds the
        constructor dump and the return-pair dumps. `lane` holds the
        refusal dump and the capture dump.

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
    var constant = out.new_dict()
    var lane = out.new_dict()
    var saw_constant = False
    var saw_lane = False
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
        elif kind == "constant" or kind == "lane":
            var module = recipe.text(recipe.at(step, "module"))
            var helper = recipe.text(recipe.at(step, "name"))
            var old = _renamed(
                _module_source(module, bounds_name, bounds, trig_name, trig),
                helper,
            )
            var target = recipe.text(recipe.at(step, "target"))
            if kind == "constant":
                require_sampled_roles(old, recipe.text(recipe.at(step, "role")))
                var dump_index = Int(
                    recipe.text(recipe.at(step, "constructor_index"))
                )
                var pair_index = Int(recipe.text(recipe.at(step, "pair_index")))
                out.set(
                    constant,
                    "dump",
                    out.new_str(body_statement_json(old, dump_index)),
                )
                out.set(
                    constant,
                    "pair",
                    out.new_str(require_return_pair(old, pair_index)),
                )
                out.set(
                    result,
                    target,
                    out.new_str(
                        _module_prefix(
                            bounds_decorators,
                            trig_decorators,
                            module,
                            trig_name,
                            helper,
                        )
                        + project_constant_heading(old)
                    ),
                )
                saw_constant = True
            else:
                var dumps = PyJson.parse(
                    sampled_lane_dumps(
                        old,
                        Int(recipe.text(recipe.at(step, "refusal_index"))),
                        Int(recipe.text(recipe.at(step, "capture_index"))),
                    )
                )
                out.set(
                    lane,
                    "refusal",
                    out.new_str(dumps.text(dumps.item(dumps.root, 0))),
                )
                out.set(
                    lane,
                    "capture",
                    out.new_str(dumps.text(dumps.item(dumps.root, 1))),
                )
                out.set(result, target, out.new_str(project_lane_value(old)))
                saw_lane = True
        else:
            _fail()
        step_index += 1
    if not saw_constant or not saw_lane:
        _fail()
    var envelope = out.new_dict()
    out.set(envelope, "helpers", result)
    out.set(envelope, "constant", constant)
    out.set(envelope, "lane", lane)
    out.root = envelope
    return out.dumps()


def project_with_recipe(payload: String) raises -> String:
    """Read the copy plan and the projection steps, then project the helpers.

    Args:
        payload: JSON with `bounds` and `trig` source texts.

    Returns:
        JSON with `plan`, `recipe`, and `record`. `plan` is the copy
        order and the rename map. `recipe` is the projection steps.
        `record` is the copied helpers and the value dispatchers.

    Raises:
        Error: A helper, a role list, or a projection step changed. The
            copy plan is read before the steps, and the steps are read
            before the helpers are projected.
    """
    var plan = sampled_copies()
    var recipe = sampled_projection_recipe()
    var doc = PyJson.parse(payload)
    var record = project_reviewed_helpers(
        doc.text(doc.at(doc.root, "bounds")),
        doc.text(doc.at(doc.root, "trig")),
    )
    return (
        '{"plan":' + plan + ',"recipe":' + recipe + ',"record":' + record + "}"
    )


def project_after_imports(payload: String) raises -> String:
    """Check the sampled value imports, then project the copied helpers.

    Args:
        payload: JSON with `target`, `bounds`, and `trig`. `target` is
            the lane-value module. `bounds` and `trig` are the helper
            sources.

    Returns:
        JSON with `plan`, `recipe`, and `record`, as
        `project_with_recipe` returns them.

    Raises:
        Error: An import changed, or a helper projection changed. An
            import error starts with `sampled imports: `. The imports are
            checked before the copy plan.
    """
    var doc = PyJson.parse(payload)
    try:
        sampled_value_imports(doc.text(doc.at(doc.root, "target")))
    except error:
        raise Error("sampled imports: " + String(error))
    return project_with_recipe(payload)


def _sort_names(mut names: List[String]):
    """Sort helper names in code-point order.

    Args:
        names: The helper names, replaced by the sorted list.
    """
    var index = 1
    while index < len(names):
        var value = names[index]
        var cursor = index
        while cursor > 0 and names[cursor - 1] > value:
            names[cursor] = names[cursor - 1]
            cursor -= 1
        names[cursor] = value
        index += 1


def _require_copied_names(
    doc: PyJson, copies: Int, names: Int, helpers: Int
) raises:
    """Require each copied helper's new name to be present.

    Args:
        doc: The document that stores the plan and the helpers.
        copies: The copy-name list.
        names: The rename map.
        helpers: The sampled helper object.

    Raises:
        Error: A renamed copy is absent. The text is `sampled projection
            step changed`. The copies are checked in order.
    """
    var closure = PyJson.parse(sampled_closure())
    var message = closure.text(closure.at(closure.root, "step"))
    var count = doc.length(copies)
    var index = 0
    while index < count:
        var name = doc.text(doc.item(copies, index))
        var renamed = doc.text(doc.at(names, name))
        if doc.get(helpers, renamed) == MISSING:
            raise Error(message)
        index += 1


def copied_names_match(payload: String) raises:
    """Require each copied helper's new name to be present.

    Args:
        payload: JSON with `copies`, `names`, and `helpers`.

    Raises:
        Error: A renamed copy is absent. The text is `sampled projection
            step changed`. The copies are checked in order.
    """
    var doc = PyJson.parse(payload)
    _require_copied_names(
        doc,
        doc.at(doc.root, "copies"),
        doc.at(doc.root, "names"),
        doc.at(doc.root, "helpers"),
    )


def project_after_top_level(payload: String) raises -> String:
    """Project the copied helpers, then check the top-level names.

    Args:
        payload: JSON with `target`, `bounds`, and `trig`. `target` is
            the lane-value module.

    Returns:
        JSON with `plan`, `recipe`, and `record`, as
        `project_after_imports` returns them.

    Raises:
        Error: An import changed, a helper projection changed, a
            top-level name differs, or a copied name is absent. The
            imports and the projection run before the top-level names.
            The copied names are checked after those top-level names.
            A top-level error starts with `sampled top-level: `.
    """
    var doc = PyJson.parse(payload)
    var projected = project_after_imports(payload)
    var parsed = PyJson.parse(projected)
    var helpers = parsed.at(parsed.at(parsed.root, "record"), "helpers")
    var names = List[String]()
    var count = parsed.length(helpers)
    var index = 0
    while index < count:
        names.append(parsed.key(helpers, index))
        index += 1
    _sort_names(names)
    var joined = String("")
    index = 0
    while index < len(names):
        if index > 0:
            joined += ","
        joined += names[index]
        index += 1
    try:
        sampled_top_level(doc.text(doc.at(doc.root, "target")), joined)
    except error:
        raise Error("sampled top-level: " + String(error))
    var plan = parsed.at(parsed.root, "plan")
    _require_copied_names(
        parsed,
        parsed.at(plan, "copies"),
        parsed.at(plan, "names"),
        helpers,
    )
    return projected
