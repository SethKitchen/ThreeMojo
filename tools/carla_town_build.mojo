# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build one CARLA town package.

    carla_town_build TOWN [--max-size N] [--tile N]
        [--raw DIR] [--layout DIR] [--maps DIR] [--out DIR]
        [--summary] [--top N]

The program reads the town layout, lowers each mesh, bakes far buildings
and tree impostors, and writes one binary glTF plus the OpenDRIVE map.
A repeated build of the same inputs writes the same bytes.
"""

from std.ffi import c_int, external_call
from std.os import getenv, listdir, makedirs
from std.os.path import exists, isdir, islink
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._imports import sorted_strings
from tools._process import _remove_tree, run_program
from tools._sha256 import Sha256
from tools._python_float import parse_float, python_repr
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools.carla_bake_identity import bake_key
from tools.carla_file_index import index_text
from tools.carla_geometry_digest import digest_text
from tools.carla_gltf_compact import gltf_text
from tools.carla_gltf_rebuild import rebuild_text
from tools.carla_town_albedo import albedo_text
from tools.carla_town_attach import attach_text
from tools.carla_town_bake import bake_text
from tools.carla_town_budget import object_fields
from tools.carla_town_copies import copies_text
from tools.carla_town_cube import cube_text
from tools.carla_town_group import group_text
from tools.carla_town_impostor import impostor_text
from tools.carla_town_join import join_text
from tools.carla_town_lamps import heads_text
from tools.carla_town_lower import lower_text
from tools.carla_town_mesh import mesh_text
from tools.carla_town_paths import export_path
from tools.carla_town_plan import plan_text
from tools.carla_town_rows import rows_text
from tools.carla_town_simplify import town_simplify_text
from tools.carla_town_slots import choose_text
from tools.carla_town_tree import tree_text
from tools.carla_town_write import write_town


comptime _GRID = "WorldGridMaterial"
comptime _KEEP = 400
comptime _BAKE_DENSITY = "6.0"
comptime _BAKE_MOST = "512"
comptime _CLUSTER_CELL = "0.25"
comptime _CLUSTER_DIVISIONS = "200"
comptime _IMPOSTOR_SIZE = "256"
comptime _IMPOSTOR_SAMPLES = "4"
comptime _VIEWS = (
    "[[1.0,0.0,0.0],[0.0,0.0,-1.0],[0.0,1.0,0.0]],"
    "[[-1.0,0.0,0.0],[0.0,0.0,1.0],[0.0,1.0,0.0]],"
    "[[0.0,0.0,1.0],[1.0,0.0,0.0],[0.0,1.0,0.0]],"
    "[[0.0,0.0,-1.0],[-1.0,0.0,0.0],[0.0,1.0,0.0]],"
    "[[0.0,1.0,0.0],[1.0,0.0,0.0],[0.0,0.0,-1.0]]"
)


@fieldwise_init
struct _Prim(Copyable, ImplicitlyCopyable, Movable):
    """One mesh primitive and the id used to hash it once."""

    var positions: String
    var normals: String
    var uvs: String
    var triangles: String
    var material: String
    var id: String
    var count: Int


struct _Library:
    """The package materials and the texture files they store."""

    var gltf: PyJson
    var out_dir: String
    var max_size: Int
    var mats: PyJson
    var props: PyJson
    var pngs: String
    var names: Dict[String, Int]
    var masked: Dict[String, Bool]
    var digests: Dict[String, String]
    var cache: String
    var light: String

    def __init__(out self, out_dir: String, max_size: Int, raw: String) raises:
        """Start an empty package for `out_dir`.

        Args:
            out_dir: The package directory.
            max_size: The longest side of a stored texture, in pixels.
            raw: The directory of `.mat`, `.props.txt` and `.png` files.

        Raises:
            Error: If a material index cannot be read.
        """
        self.out_dir = out_dir
        self.max_size = max_size
        self.gltf = PyJson()
        var root = self.gltf.new_dict()
        self.gltf.root = root
        self.gltf.set(root, "materials", self.gltf.new_list())
        self.gltf.set(root, "images", self.gltf.new_list())
        self.gltf.set(root, "textures", self.gltf.new_list())
        var sampler = self.gltf.new_dict()
        self.gltf.set(sampler, "magFilter", self.gltf.new_int(9729))
        self.gltf.set(sampler, "minFilter", self.gltf.new_int(9987))
        self.gltf.set(sampler, "wrapS", self.gltf.new_int(10497))
        self.gltf.set(sampler, "wrapT", self.gltf.new_int(10497))
        var samplers = self.gltf.new_list()
        self.gltf.append(samplers, sampler)
        self.gltf.set(root, "samplers", samplers)
        self.mats = PyJson.parse(index_text(raw, ".mat"))
        self.props = PyJson.parse(index_text(raw, ".props.txt"))
        self.pngs = index_text(raw, ".png")
        self.names = Dict[String, Int]()
        self.masked = Dict[String, Bool]()
        self.digests = Dict[String, String]()
        self.cache = "[]"
        self.light = impostor_text('{"mode":"light"}')

    def material(mut self, name: String) raises -> Int:
        """Return the glTF index of the material named `name`.

        Args:
            name: The UModel material name, or an empty name.

        Returns:
            The index in `gltf.materials`.

        Raises:
            Error: If the material files cannot be read or stored.
        """
        if name in self.names:
            return self.names[name]
        var chosen = PyJson.parse(
            attach_text('{"mode":"resolve","name":' + _json_string(name) + "}")
        )
        var action = chosen.text(chosen.at(chosen.root, "action"))
        var material: PyJson
        if action == "plain":
            material = chosen.subtree(chosen.at(chosen.root, "material"))
        else:
            var request = String('{"material":{"name":')
            request += _json_string(name)
            request += '},"mat":'
            request += _file_json(self._path(self.mats, name))
            request += ',"props":'
            request += _file_json(self._path(self.props, name))
            request += ',"pngs":'
            request += self.pngs
            request += ',"out_dir":'
            request += _json_string(self.out_dir)
            request += ',"max_size":'
            request += String(self.max_size)
            request += ',"texture_count":'
            request += String(
                self.gltf.length(self.gltf.at(self.gltf.root, "textures"))
            )
            request += ',"cache":'
            request += self.cache
            request += ',"town":true}'
            var result = PyJson.parse(rebuild_text(request))
            material = result.subtree(result.at(result.root, "material"))
            var images = result.at(result.root, "images")
            var listed = self.gltf.at(self.gltf.root, "images")
            var textures = self.gltf.at(self.gltf.root, "textures")
            for index in range(result.length(images)):
                var image = self.gltf.new_dict()
                self.gltf.set(
                    image,
                    "uri",
                    self.gltf.new_str(result.text(result.item(images, index))),
                )
                self.gltf.append(listed, image)
                var texture = self.gltf.new_dict()
                self.gltf.set(texture, "sampler", self.gltf.new_int(0))
                self.gltf.set(
                    texture,
                    "source",
                    self.gltf.new_int(self.gltf.length(listed) - 1),
                )
                self.gltf.append(textures, texture)
            var added = result.at(result.root, "cache_add")
            if result.length(added) > 0:
                var cache = PyJson.parse(self.cache)
                for index in range(result.length(added)):
                    cache.append(
                        cache.root,
                        cache.adopt(result, result.item(added, index)),
                    )
                self.cache = cache.dumps()
        var materials = self.gltf.at(self.gltf.root, "materials")
        self.gltf.append(materials, self.gltf.adopt(material, material.root))
        var index = self.gltf.length(materials) - 1
        var stored = self.gltf.item(materials, index)
        var mode = self.gltf.get(stored, "alphaMode")
        var cutout = False
        if mode != MISSING and self.gltf.text(mode) == "MASK":
            cutout = True
        self.names[name] = index
        self.masked[name] = cutout
        return index

    def tag(
        mut self,
        mesh: String,
        kind: String,
        prims: List[_Prim],
        materials: List[Int],
        target: Int,
    ) raises -> String:
        """Return the atlas tag for these parts.

        Args:
            mesh: The source mesh path.
            kind: `baked` or `impostor`.
            prims: The primitives, in order.
            materials: The glTF material index of each primitive.
            target: The far triangle goal. Impostors ignore it.

        Returns:
            The tag `bake_key` prints.

        Raises:
            Error: If a primitive or a texture file cannot be hashed.
        """
        var parts = String("[")
        for index in range(len(prims)):
            if index > 0:
                parts += ","
            parts += "["
            parts += _json_string(self._digest(prims[index]))
            parts += ","
            parts += String(materials[index])
            parts += "]"
        parts += "]"
        var settings = String("[")
        if kind == "baked":
            settings += String(target)
            settings += ","
            settings += _BAKE_DENSITY
            settings += ","
            settings += _BAKE_MOST
            settings += ",["
            settings += _VIEWS
            settings += "],"
            settings += _CLUSTER_CELL
            settings += ","
            settings += _CLUSTER_DIVISIONS
        else:
            settings += _IMPOSTOR_SIZE
            settings += ","
            settings += _IMPOSTOR_SAMPLES
            settings += ","
            settings += self.light
        settings += "]"
        var request = String('{"gltf":')
        request += self.gltf.dumps()
        request += ',"out_dir":'
        request += _json_string(self.out_dir)
        request += ',"mesh":'
        request += _json_string(mesh)
        request += ',"kind":'
        request += _json_string(kind)
        request += ',"parts":'
        request += parts
        request += ',"settings":'
        request += settings
        request += "}"
        return bake_key(request)

    def mark_lamp(mut self, index: Int) raises:
        """Mark material `index` as a street-lamp glass.

        Args:
            index: The glTF material index.

        Raises:
            Error: If `index` is outside the material list.
        """
        var materials = self.gltf.at(self.gltf.root, "materials")
        var material = self.gltf.item(materials, index)
        var extras = self.gltf.new_dict()
        self.gltf.set(extras, "carla", self.gltf.new_str("lamp"))
        self.gltf.set(material, "extras", extras)

    def _digest(mut self, prim: _Prim) raises -> String:
        """Return the geometry digest of `prim`, cached by its id.

        Args:
            prim: The primitive.

        Returns:
            64 lowercase hex digits.

        Raises:
            Error: If the primitive JSON cannot be hashed.
        """
        if prim.id in self.digests:
            return self.digests[prim.id]
        var request = String('{"primitives":[')
        request += _prim_json(prim)
        request += "]}"
        var lines = digest_text(request)
        if len(lines) != 1:
            raise Error("geometry digest count mismatch")
        self.digests[prim.id] = lines[0]
        return lines[0]

    def _path(self, index: PyJson, name: String) raises -> String:
        """Return the indexed file for `name`, or an empty path.

        Args:
            index: A stem-to-path object.
            name: The material stem.

        Returns:
            The path, or empty when the stem is absent.

        Raises:
            Error: If the stored value is not text.
        """
        var node = index.get(index.root, name)
        if node == MISSING:
            return ""
        return index.text(node)


def _town_key(
    town: String,
    max_size: Int,
    tile: Float64,
    raw: String,
    layout: String,
    maps: String,
) raises -> String:
    """Return the content key of one town's inputs.

    Args:
        town: The town name.
        max_size: The texture limit, in pixels.
        tile: The tile width, in meters.
        raw: The mesh and material directory.
        layout: The layout directory.
        maps: The map directory.

    Returns:
        The SHA-256 hex digest of those inputs.

    Raises:
        Error: If an input file cannot be read.
    """
    var hasher = Sha256()
    hasher.update(Span(town.as_bytes()))
    hasher.update(Span(String(max_size).as_bytes()))
    hasher.update(Span(python_repr(tile).as_bytes()))
    _hash_file(hasher, layout + "/" + town + ".jsonl")
    _hash_file(hasher, maps + "/" + town + ".xodr")
    _hash_dir(hasher, raw)
    return hasher^.hexdigest()


def _hash_file(mut hasher: Sha256, path: String) raises:
    """Mix one file's bytes into `hasher`.

    Args:
        hasher: The running digest.
        path: The file.

    Raises:
        Error: If the file cannot be read.
    """
    hasher.update(Span(String(path).as_bytes()))
    hasher.update(Span(Path(path).read_bytes()))


def _hash_dir(mut hasher: Sha256, directory: String) raises:
    """Mix a directory tree into `hasher`, in sorted name order.

    Args:
        hasher: The running digest.
        directory: The directory.

    Raises:
        Error: If a file cannot be read.
    """
    var found = List[String]()
    for name in listdir(directory):
        found.append(name)
    var names = sorted_strings(found^)
    for name in names:
        var path = directory + "/" + name
        hasher.update(Span(String(name).as_bytes()))
        if islink(path):
            hasher.update(Span(Path(path).read_bytes()))
        elif isdir(path):
            hasher.update(Span(String("/").as_bytes()))
            _hash_dir(hasher, path)
        else:
            hasher.update(Span(Path(path).read_bytes()))


def _copy_dir(source: String, destination: String) raises:
    """Copy a directory tree of regular files.

    Args:
        source: The existing directory.
        destination: The new directory.

    Raises:
        Error: If a file cannot be copied.
    """
    makedirs(destination, exist_ok=True)
    for name in listdir(source):
        var src = source + "/" + name
        var dst = destination + "/" + name
        if isdir(src) and not islink(src):
            _copy_dir(src, dst)
        else:
            _copy_file(src, dst)


def _remembered_town(
    town: String,
    max_size: Int,
    tile: Float64,
    raw: String,
    layout: String,
    maps: String,
    out_root: String,
) raises -> String:
    """Return a previous package when the inputs are unchanged.

    Args:
        town: The town name.
        max_size: The texture limit, in pixels.
        tile: The tile width, in meters.
        raw: The mesh and material directory.
        layout: The layout directory.
        maps: The map directory.
        out_root: The directory that receives the package.

    Returns:
        The saved summary, or an empty string when this is the first build.

    Raises:
        Error: If the saved package cannot be copied.
    """
    var key = _town_key(town, max_size, tile, raw, layout, maps)
    var cache = ".cache/town-package/" + key
    if not exists(cache + "/result.txt") or islink(cache):
        return ""
    var out_dir = out_root + "/carla.town." + _lower_ascii(town)
    var removed = run_program(["rm", "-rf", out_dir], 30.0)
    if removed.status != 0:
        raise Error(removed.output)
    _copy_dir(cache + "/tree", out_dir)
    return Path(cache + "/result.txt").read_text()


def _remember_town(
    town: String,
    max_size: Int,
    tile: Float64,
    raw: String,
    layout: String,
    maps: String,
    out_dir: String,
    result: String,
):
    """Save one finished package for a later identical build.

    Args:
        town: The town name.
        max_size: The texture limit, in pixels.
        tile: The tile width, in meters.
        raw: The mesh and material directory.
        layout: The layout directory.
        maps: The map directory.
        out_dir: The package directory.
        result: The summary text.
    """
    try:
        var key = _town_key(town, max_size, tile, raw, layout, maps)
        var cache = ".cache/town-package/" + key
        if exists(cache + "/result.txt"):
            return
        var partial = cache + ".partial"
        var removed = run_program(["rm", "-rf", partial], 30.0)
        if removed.status != 0:
            return
        _copy_dir(out_dir, partial + "/tree")
        Path(partial + "/result.txt").write_text(result)
        _ = run_program(["mkdir", "-p", ".cache/town-package"], 30.0)
        var moved = run_program(["mv", "-f", partial, cache], 30.0)
        if moved.status != 0:
            _ = run_program(["rm", "-rf", partial], 30.0)
    except error:
        _ = String(error)


def build_town(
    town: String,
    max_size: Int,
    tile: Float64,
    raw: String,
    layout: String,
    maps: String,
    out_root: String,
) raises -> String:
    """Write one town package and return its triangle counts.

    Args:
        town: The town name, such as `Town01` or `Fixture`.
        max_size: The longest side of a stored texture, in pixels.
        tile: The tile width, in meters.
        raw: The directory of exported meshes and material files.
        layout: The directory of `<town>.jsonl` layout files.
        maps: The directory of `<town>.xodr` maps.
        out_root: The directory that receives `carla.town.<town>`.

    Returns:
        JSON with `triangles`, the near and far counts, and `nodes`.

    Raises:
        Error: If the layout, a mesh, or the package cannot be written.
    """
    if max_size < 0:
        raise Error("max_size is negative")
    if not (tile > 0.0):
        raise Error("tile is not positive")
    var remembered = _remembered_town(
        town, max_size, tile, raw, layout, maps, out_root
    )
    if remembered.byte_length() > 0:
        return remembered
    var name = "carla.town." + _lower_ascii(town)
    var out_dir = out_root + "/" + name
    var removed = run_program(["rm", "-rf", out_dir], 30.0)
    if removed.status != 0:
        raise Error(removed.output)
    makedirs(out_dir, exist_ok=True)
    var library = _Library(out_dir, max_size, raw)
    var rows = PyJson.parse(rows_text(layout + "/" + town + ".jsonl"))
    var row_list = rows.root
    if rows.kind(row_list) != PY_LIST:
        raise Error("layout is not a list")
    var visible_at = List[Int]()
    var visible_mesh = List[String]()
    var select = String('{"mode":"select","rows":[')
    var select_first = True
    for index in range(rows.length(row_list)):
        var row = rows.item(row_list, index)
        if rows.kind(row) != PY_DICT:
            raise Error("layout row is not an object")
        if not rows.flag(rows.at(row, "visible")):
            continue
        var fields = object_fields(rows.text(rows.at(row, "mesh")))
        var mesh = fields[1]
        if not select_first:
            select += ","
        select_first = False
        select += '{"mesh":'
        select += _json_string(mesh)
        select += ',"visible":true}'
        visible_at.append(index)
        visible_mesh.append(mesh)
    select += "]}"
    var chosen = PyJson.parse(plan_text(select))
    var chosen_rows = chosen.at(chosen.root, "rows")
    var prims = List[_Prim]()
    var mesh_at = Dict[String, Int]()
    var mesh_len = Dict[String, Int]()
    var prep_row = List[Int]()
    var prep_mesh = List[String]()
    var prep_at = List[Int]()
    var prep_len = List[Int]()
    var prep_names = List[String]()
    var prep_copies = List[String]()
    var prep_triangles = List[Int]()
    var prep_spline = List[String]()
    for slot in range(chosen.length(chosen_rows)):
        var visible = _whole_node(chosen, chosen.item(chosen_rows, slot))
        var mesh = visible_mesh[visible]
        if not (mesh in mesh_at):
            var loaded = _load_mesh(raw, mesh)
            mesh_at[mesh] = len(prims)
            mesh_len[mesh] = len(loaded)
            for prim in loaded:
                prims.append(prim)
        var count = mesh_len[mesh]
        if count == 0:
            continue
        var start = mesh_at[mesh]
        var row = rows.item(row_list, visible_at[visible])
        var owned = List[String]()
        for offset in range(count):
            owned.append(prims[start + offset].material)
        var names = choose_text(
            '{"materials":'
            + _dump(rows, rows.at(row, "materials"))
            + ',"own":'
            + _string_array(owned)
            + "}"
        )
        prep_row.append(visible_at[visible])
        prep_mesh.append(mesh)
        prep_at.append(start)
        prep_len.append(count)
        prep_names.append(names)
        prep_copies.append(_copies(rows, row))
        var triangles = 0
        for offset in range(count):
            triangles += prims[start + offset].count
        prep_triangles.append(triangles)
        var spline = rows.get(row, "spline")
        if spline == MISSING:
            prep_spline.append("")
        else:
            prep_spline.append(_dump(rows, spline))
    var jobs_request = String('{"mode":"jobs","rows":[')
    for index in range(len(prep_mesh)):
        if index > 0:
            jobs_request += ","
        var copy_doc = PyJson.parse(prep_copies[index])
        jobs_request += '{"mesh":'
        jobs_request += _json_string(prep_mesh[index])
        jobs_request += ',"copies":'
        jobs_request += String(copy_doc.length(copy_doc.root))
        jobs_request += ',"triangles":'
        jobs_request += String(prep_triangles[index])
        jobs_request += ',"materials":'
        jobs_request += prep_names[index]
        jobs_request += "}"
    jobs_request += "]}"
    var plan = PyJson.parse(plan_text(jobs_request))
    var jobs = plan.at(plan.root, "jobs")
    if plan.length(jobs) != len(prep_mesh):
        raise Error("town plan job count mismatch")
    var heads = Dict[String, String]()
    var lowered = Dict[String, String]()
    var stat_order = List[String]()
    var stat_count = Dict[String, Int]()
    var lamps = String("[")
    var lamp_first = True
    var pending = String("[")
    var pending_first = True
    for index in range(len(prep_mesh)):
        var job = plan.item(jobs, index)
        var mesh = prep_mesh[index]
        var kind = plan.text(plan.at(job, "kind"))
        var lamp = plan.flag(plan.at(job, "lamp_glass"))
        var matrices = PyJson.parse(prep_copies[index])
        var selected = plan.at(job, "copies")
        var used = String("[")
        for copy in range(plan.length(selected)):
            if copy > 0:
                used += ","
            var at = _whole_node(plan, plan.item(selected, copy))
            used += _dump(matrices, matrices.item(matrices.root, at))
        used += "]"
        if not (mesh in heads):
            heads[mesh] = _lamp_heads(
                mesh, prims, prep_at[index], prep_len[index]
            )
        if heads[mesh] != "null" and plan.length(selected) > 0:
            var placed = heads_text(
                '{"heads":' + heads[mesh] + ',"matrices":' + used + "}"
            )
            _join_array(lamps, lamp_first, placed)
        var parts = plan.at(job, "parts")
        for part_index in range(plan.length(parts)):
            var part = plan.item(parts, part_index)
            var prim_index = _whole_node(plan, plan.at(part, "index"))
            var material_name = plan.text(plan.at(part, "material"))
            var material = library.material(material_name)
            if lamp:
                library.mark_lamp(material)
            var levels = plan.at(part, "levels")
            for level_index in range(plan.length(levels)):
                var level = plan.item(levels, level_index)
                var action = plan.text(plan.at(level, "action"))
                if action == "skip":
                    continue
                var lod = _whole_node(plan, plan.at(level, "lod"))
                var factor = _dump(plan, plan.at(level, "factor"))
                var mesh_json: String
                var part_material = material
                if action == "baked" or action == "impostor":
                    var goal = 0
                    if action == "baked":
                        goal = _whole_node(plan, plan.at(level, "goal"))
                    var kept = _kept_prims(
                        prims, prep_at[index], prep_names[index]
                    )
                    var kept_materials = _kept_materials(
                        library, prep_names[index]
                    )
                    var key = library.tag(
                        mesh, action, kept, kept_materials, goal
                    )
                    var cache_key = action + ":" + key
                    if not (cache_key in lowered):
                        lowered[cache_key] = _far_mesh(
                            library,
                            action,
                            mesh,
                            prims,
                            prep_at[index],
                            prep_names[index],
                            goal,
                            key,
                        )
                    var cached = PyJson.parse(lowered[cache_key])
                    if cached.text(cached.at(cached.root, "empty")) == "true":
                        continue
                    mesh_json = _dump(cached, cached.at(cached.root, "mesh"))
                    part_material = _whole_node(
                        cached, cached.at(cached.root, "material")
                    )
                else:
                    var key = (
                        mesh
                        + ":"
                        + String(prim_index)
                        + ":"
                        + material_name
                        + ":"
                        + String(lod)
                    )
                    if not (key in lowered):
                        var source = prims[prep_at[index] + prim_index]
                        lowered[key] = _lower_mesh(
                            source,
                            kind,
                            mesh,
                            prim_index,
                            prep_triangles[index],
                            library.masked[material_name],
                            lod,
                            factor,
                        )
                    var cached = PyJson.parse(lowered[key])
                    if cached.text(cached.at(cached.root, "empty")) == "true":
                        continue
                    mesh_json = _dump(cached, cached.at(cached.root, "mesh"))
                if not pending_first:
                    pending += ","
                pending_first = False
                pending += '{"lod":'
                pending += String(lod)
                pending += ',"kind":'
                pending += _json_string(kind)
                pending += ',"material":'
                pending += String(part_material)
                pending += ","
                pending += _mesh_fields(mesh_json)
                pending += ',"copies":'
                pending += _copy_entries(used, prep_spline[index])
                pending += "}"
                var produced = _triangle_count(mesh_json) * plan.length(
                    selected
                )
                if not (mesh in stat_count):
                    stat_order.append(mesh)
                    stat_count[mesh] = 0
                stat_count[mesh] += produced
    pending += "]"
    lamps += "]"
    var grouped = PyJson.parse(
        group_text(
            '{"tile":' + _json_number(tile) + ',"parts":' + pending + "}"
        )
    )
    _copy_file(maps + "/" + town + ".xodr", out_dir + "/" + town + ".xodr")
    var payload = String('{"out_dir":')
    payload += _json_string(out_dir)
    payload += ',"name":'
    payload += _json_string(name)
    payload += ',"gltf":'
    payload += gltf_text(library.gltf)
    payload += ',"groups":'
    payload += _dump(grouped, grouped.at(grouped.root, "groups"))
    payload += ',"lamps":'
    payload += lamps
    payload += "}"
    var written = PyJson.parse(write_town(payload))
    var meshes = written.new_list()
    for mesh in stat_order:
        var item = written.new_dict()
        written.set(item, "path", written.new_str(mesh))
        written.set(item, "triangles", written.new_int(stat_count[mesh]))
        written.append(meshes, item)
    written.set(written.root, "meshes", meshes)
    var result = written.dumps()
    _remember_town(town, max_size, tile, raw, layout, maps, out_dir, result)
    return result


def main() raises:
    """Build the towns named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    var towns = List[String]()
    var max_size = 512
    var tile = 32.0
    var base = getenv("CARLA_EXPORT_DIR", ".")
    var raw = base + "/raw_town"
    var layout = base + "/layout"
    var maps = base + "/release/CarlaUE4/Content/Carla/Maps/OpenDrive"
    var out_root = base + "/town_packages"
    var summary = False
    var top = 0
    var index = 1
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--summary":
            summary = True
            index += 1
            continue
        if (
            argument == "--max-size"
            or argument == "--tile"
            or argument == "--raw"
            or argument == "--layout"
            or argument == "--maps"
            or argument == "--out"
            or argument == "--top"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if argument == "--max-size":
                max_size = _whole(value)
            elif argument == "--tile":
                tile = parse_float(value)
            elif argument == "--raw":
                raw = value
            elif argument == "--layout":
                layout = value
            elif argument == "--maps":
                maps = value
            elif argument == "--top":
                top = _whole(value)
                summary = True
            else:
                out_root = value
            index += 2
            continue
        if _starts(argument, "--"):
            _usage()
        towns.append(argument)
        index += 1
    if len(towns) == 0:
        towns.append("Town01")
        towns.append("Town02")
        towns.append("Town03")
        towns.append("Town04")
        towns.append("Town05")
        towns.append("Town10HD")
    try:
        for town in towns:
            var text = build_town(
                town, max_size, tile, raw, layout, maps, out_root
            )
            if not summary:
                print(text)
                continue
            var doc = PyJson.parse(text)
            var triangles = doc.at(doc.root, "triangles")
            var folder = out_root + "/carla.town." + _lower_ascii(town)
            print(
                town_summary_line(
                    town,
                    Int(doc.text(doc.item(triangles, 0))),
                    Int(doc.text(doc.item(triangles, 1))),
                    Int(doc.text(doc.at(doc.root, "nodes"))),
                    directory_byte_count(folder),
                )
            )
            var ranks = ranked_mesh_lines(doc, top)
            if ranks.byte_length() > 0:
                print(ranks)
    except error:
        print("carla_town_build:", error, file=stderr)
        exit(1)


def grouped_digits(value: Int) -> String:
    """Return `value` with a comma between each group of three digits.

    Args:
        value: A non-negative count.

    Returns:
        The text Python `format(value, ",")` gives. A negative value keeps
        its sign and groups the magnitude.
    """
    var sign = String("")
    var number = value
    if number < 0:
        sign = "-"
        number = -number
    var digits = String(number)
    var out = String("")
    var count = 0
    var index = digits.byte_length()
    while index > 0:
        index -= 1
        out = String(digits[byte = index : index + 1]) + out
        count += 1
        if count == 3 and index > 0:
            out = "," + out
            count = 0
    return sign + out


def package_megabytes(byte_count: Int) -> String:
    """Return `byte_count / 1e6` with one digit after the point.

    Args:
        byte_count: The package size, in bytes.

    Returns:
        The text Python `%.1f` gives for that quotient.
    """
    var buffer = List[UInt8](length=64, fill=0)
    var format = "%.1f"
    var value = Float64(byte_count) / 1000000.0
    _ = external_call["snprintf", c_int](
        buffer.unsafe_ptr(),
        Int(64),
        format.as_c_string_span().ptr(),
        value,
    )
    var end = 0
    while end < 64 and buffer[end] != 0:
        end += 1
    var bytes = List[UInt8]()
    var index = 0
    while index < end:
        bytes.append(buffer[index])
        index += 1
    return String(from_utf8_lossy=Span(bytes))


def town_summary_line(
    town: String,
    near: Int,
    far: Int,
    nodes: Int,
    byte_count: Int,
) -> String:
    """Return one town's triangle and size line.

    Args:
        town: The town name.
        near: The near-level triangle count.
        far: The far-level triangle count.
        nodes: The mesh node count.
        byte_count: The package size, in bytes.

    Returns:
        The line `python build_towns.py` printed for that town.
    """
    return (
        town
        + ": "
        + grouped_digits(near)
        + " triangles near, "
        + grouped_digits(far)
        + " far, "
        + String(nodes)
        + " meshes, "
        + package_megabytes(byte_count)
        + " MB"
    )


def directory_byte_count(root: String) raises -> Int:
    """Return the sum of the file sizes under `root`.

    Args:
        root: A package directory.

    Returns:
        The byte count. A symbolic link is not followed.

    Raises:
        Error: If a directory cannot be read.
    """
    var total = 0
    var pending = List[String]()
    pending.append(root)
    while len(pending) > 0:
        var directory = pending.pop()
        var names: List[String]
        try:
            names = listdir(directory)
        except:
            raise Error("cannot read " + directory)
        for name in names:
            var full = directory + "/" + String(name)
            if isdir(full) and not islink(full):
                pending.append(full)
            elif not isdir(full):
                total += len(Path(full).read_bytes())
    return total


def ranked_mesh_lines(doc: PyJson, top: Int) raises -> String:
    """Return the largest mesh lines, highest triangle count first.

    Args:
        doc: A town result whose `meshes` list has `path` and `triangles`.
        top: How many lines to return. Zero returns an empty string.

    Returns:
        One line per mesh, padded like the Python command. An equal count
        keeps the earlier mesh.

    Raises:
        Error: If a mesh record is missing a field.
    """
    if top <= 0:
        return ""
    var meshes = doc.at(doc.root, "meshes")
    var count = doc.length(meshes)
    var order = List[Int]()
    var index = 0
    while index < count:
        var triangles = Int(
            doc.text(doc.at(doc.item(meshes, index), "triangles"))
        )
        var place = len(order)
        order.append(index)
        while place > 0:
            var previous = order[place - 1]
            var previous_count = Int(
                doc.text(doc.at(doc.item(meshes, previous), "triangles"))
            )
            if previous_count >= triangles:
                break
            order[place] = previous
            place -= 1
        order[place] = index
        index += 1
    var shown = top
    if shown > count:
        shown = count
    var out = String("")
    var line = 0
    while line < shown:
        var slot = order[line]
        var item = doc.item(meshes, slot)
        var path = doc.text(doc.at(item, "path"))
        var marker = "/Static/"
        var at = path.rfind(marker)
        var tail = path
        if at >= 0:
            tail = String(path[byte = at + marker.byte_length() :])
        var count_text = grouped_digits(
            Int(doc.text(doc.at(item, "triangles")))
        )
        while count_text.byte_length() < 10:
            count_text = " " + count_text
        if out.byte_length() > 0:
            out += "\n"
        out += "  " + count_text + "  " + tail
        line += 1
    return out


def _usage() raises:
    """Print the usage line and stop."""
    print(
        (
            "usage: carla_town_build TOWN [--max-size N] [--tile N] [--raw DIR]"
            " [--layout DIR] [--maps DIR] [--out DIR] [--summary] [--top N]"
        ),
        file=stderr,
    )
    exit(2)


def _load_mesh(raw: String, mesh: String) raises -> List[_Prim]:
    """Return the primitives of `mesh`.

    Args:
        raw: The export directory.
        mesh: The `/Game` or `/Engine` path.

    Returns:
        The primitives. An engine cube is synthesized. A missing file is
        an empty list.

    Raises:
        Error: If a present mesh cannot be read.
    """
    var out = List[_Prim]()
    if _starts(mesh, "/Engine/"):
        out.append(_prim_from(PyJson.parse(cube_text()), mesh + "#0"))
        return out^
    var path = export_path(raw, mesh, ".gltf")
    if not Path(path).is_file():
        return out^
    var doc = PyJson.parse(mesh_text(path))
    if doc.kind(doc.root) != PY_LIST:
        raise Error("mesh is not a list")
    for index in range(doc.length(doc.root)):
        var item = doc.item(doc.root, index)
        out.append(_prim_from(doc.subtree(item), mesh + "#" + String(index)))
    return out^


def _prim_from(doc: PyJson, id: String) raises -> _Prim:
    """Return one primitive from a parsed object.

    Args:
        doc: A document whose root is the primitive.
        id: The cache id.

    Returns:
        The primitive.

    Raises:
        Error: If a field is missing.
    """
    var triangles = doc.at(doc.root, "triangles")
    return _Prim(
        _dump(doc, doc.at(doc.root, "positions")),
        _dump(doc, doc.at(doc.root, "normals")),
        _dump(doc, doc.at(doc.root, "uvs")),
        _dump(doc, triangles),
        doc.text(doc.at(doc.root, "material")),
        id,
        doc.length(triangles),
    )


def _prim_json(prim: _Prim) raises -> String:
    """Return `prim` as a JSON object."""
    var out = String('{"positions":')
    out += prim.positions
    out += ',"normals":'
    out += prim.normals
    out += ',"uvs":'
    out += prim.uvs
    out += ',"triangles":'
    out += prim.triangles
    out += ',"material":'
    out += _json_string(prim.material)
    out += "}"
    return out


def _copies(rows: PyJson, row: Int) raises -> String:
    """Return the world matrices of one layout row.

    Args:
        rows: The layout document.
        row: The row node.

    Returns:
        A JSON array of 4×4 matrices.

    Raises:
        Error: If the placement cannot be built.
    """
    var request = String('{"scale":')
    request += _dump(rows, rows.at(row, "scale"))
    request += ',"rotation":'
    request += _dump(rows, rows.at(row, "rotation"))
    request += ',"location":'
    request += _dump(rows, rows.at(row, "location"))
    var instances = rows.get(row, "instances")
    if instances != MISSING:
        request += ',"instances":'
        request += _dump(rows, instances)
    request += "}"
    var directory = mkdtemp(prefix="town-copies-")
    var path = directory + "/row.json"
    Path(path).write_text(request)
    var result = copies_text(path)
    _remove_tree(directory)
    return result


def _lamp_heads(
    mesh: String, prims: List[_Prim], start: Int, count: Int
) raises -> String:
    """Return the lamp heads of `mesh`, or `null`.

    Args:
        mesh: The mesh path.
        prims: Every loaded primitive.
        start: The first primitive of `mesh`.
        count: The primitive count.

    Returns:
        A JSON array, or `null` when the mesh is not a lamp.

    Raises:
        Error: If a lamp mesh has no usable corners.
    """
    var request = String('{"mesh":')
    request += _json_string(mesh)
    request += ',"primitives":['
    for index in range(count):
        if index > 0:
            request += ","
        var prim = prims[start + index]
        request += '{"positions":'
        request += prim.positions
        request += ',"triangles":'
        request += prim.triangles
        request += "}"
    request += "]}"
    return heads_text(request)


def _lower_mesh(
    prim: _Prim,
    kind: String,
    mesh: String,
    index: Int,
    total: Int,
    masked: Bool,
    lod: Int,
    factor: String,
) raises -> String:
    """Return one lowered primitive as a cache record.

    Args:
        prim: The source primitive.
        kind: The town kind.
        mesh: The mesh path.
        index: The primitive index.
        total: The mesh triangle count.
        masked: True when the material is a cut-out.
        lod: The level, 0 or 1.
        factor: The kind's share, as JSON.

    Returns:
        JSON with `empty` and, when present, `mesh`.

    Raises:
        Error: If the collapse cannot run.
    """
    var request = String('{"positions":')
    request += prim.positions
    request += ',"normals":'
    request += prim.normals
    request += ',"uvs":'
    request += prim.uvs
    request += ',"triangles":'
    request += prim.triangles
    request += ',"material":'
    request += _json_string(prim.material)
    request += ',"kind":'
    request += _json_string(kind)
    request += ',"mesh":'
    request += _json_string(mesh)
    request += ',"index":'
    request += String(index)
    request += ',"total":'
    request += String(total)
    request += ',"masked":'
    if masked:
        request += "true"
    else:
        request += "false"
    request += ',"lod":'
    request += String(lod)
    request += ',"factor":'
    request += factor
    request += ',"keep":'
    request += String(_KEEP)
    request += "}"
    var result = PyJson.parse(lower_text(request))
    var action = result.text(result.at(result.root, "action"))
    if action == "none":
        return '{"empty":"true"}'
    if action == "whole":
        return '{"empty":"false","mesh":' + _prim_json(prim) + "}"
    var mesh_id = (
        "lower:"
        + mesh
        + ":"
        + String(index)
        + ":"
        + String(lod)
        + ":"
        + prim.material
    )
    var changed = _Prim(
        _dump(result, result.at(result.root, "positions")),
        _dump(result, result.at(result.root, "normals")),
        _dump(result, result.at(result.root, "uvs")),
        _dump(result, result.at(result.root, "triangles")),
        prim.material,
        mesh_id,
        result.length(result.at(result.root, "triangles")),
    )
    return '{"empty":"false","mesh":' + _prim_json(changed) + "}"


def _far_mesh(
    mut library: _Library,
    action: String,
    mesh: String,
    prims: List[_Prim],
    start: Int,
    names_json: String,
    goal: Int,
    tag: String,
) raises -> String:
    """Return one baked or impostor mesh and its material index.

    Args:
        library: The package library.
        action: `baked` or `impostor`.
        mesh: The source mesh path.
        prims: Every loaded primitive.
        start: The first primitive of `mesh`.
        names_json: The material name of each primitive, as a JSON array.
        goal: The far triangle goal.
        tag: The atlas tag.

    Returns:
        JSON with `empty`, and `mesh` plus `material` when the level exists.

    Raises:
        Error: If the picture or the collapse cannot be written.
    """
    var kept = _kept_prims(prims, start, names_json)
    var indexes = _kept_materials(library, names_json)
    if len(kept) == 0:
        return '{"empty":"true"}'
    makedirs(library.out_dir + "/textures", exist_ok=True)
    if action == "impostor":
        var frame = tree_text(
            '{"size":'
            + _IMPOSTOR_SIZE
            + ',"samples":'
            + _IMPOSTOR_SAMPLES
            + ',"out":'
            + _json_string(library.out_dir + "/textures/" + tag + ".png")
            + ',"parts":'
            + _colored_parts(library, kept, indexes)
            + "}"
        )
        var parsed = PyJson.parse(frame)
        var quad = _Prim(
            _dump(parsed, parsed.at(parsed.root, "positions")),
            _dump(parsed, parsed.at(parsed.root, "normals")),
            _dump(parsed, parsed.at(parsed.root, "uvs")),
            _dump(parsed, parsed.at(parsed.root, "triangles")),
            tag,
            "impostor:" + tag,
            parsed.length(parsed.at(parsed.root, "triangles")),
        )
        var material = _picture(library, "impostor", tag, ".png")
        return (
            '{"empty":"false","material":'
            + String(material)
            + ',"mesh":'
            + _prim_json(quad)
            + "}"
        )
    var joined = PyJson.parse(join_text('{"parts":' + _join_parts(kept) + "}"))
    var whole = _Prim(
        _dump(joined, joined.at(joined.root, "positions")),
        _dump(joined, joined.at(joined.root, "normals")),
        _dump(joined, joined.at(joined.root, "uvs")),
        _dump(joined, joined.at(joined.root, "triangles")),
        mesh,
        "join:" + tag,
        joined.length(joined.at(joined.root, "triangles")),
    )
    var simplified = PyJson.parse(
        town_simplify_text(
            '{"mode":"weld","positions":'
            + whole.positions
            + ',"uvs":'
            + whole.uvs
            + ',"triangles":'
            + whole.triangles
            + ',"material":'
            + _json_string(mesh)
            + ',"target":'
            + String(goal)
            + ',"small":false,"keep":'
            + String(_KEEP)
            + "}"
        )
    )
    var far = whole
    var same = False
    var same_node = simplified.get(simplified.root, "same")
    if same_node != MISSING:
        if simplified.flag(same_node):
            same = True
    if not same:
        var empty_node = simplified.get(simplified.root, "empty")
        if empty_node != MISSING:
            if simplified.flag(empty_node):
                return '{"empty":"true"}'
        if not same:
            far = _prim_from(simplified, "weld:" + tag)
    if same:
        var flat = PyJson.parse(
            bake_text(
                '{"mode":"flat","positions":'
                + whole.positions
                + ',"triangles":'
                + whole.triangles
                + "}"
            )
        )
        far = _Prim(
            _dump(flat, flat.at(flat.root, "positions")),
            _dump(flat, flat.at(flat.root, "normals")),
            whole.uvs,
            _dump(flat, flat.at(flat.root, "triangles")),
            mesh,
            "flat:" + tag,
            flat.length(flat.at(flat.root, "triangles")),
        )
    var packed = PyJson.parse(
        bake_text(
            '{"out":'
            + _json_string(library.out_dir + "/textures/" + tag + ".jpg")
            + ',"density":'
            + _BAKE_DENSITY
            + ',"most":'
            + _BAKE_MOST
            + ',"whole":{"positions":'
            + whole.positions
            + '},"far":{"positions":'
            + far.positions
            + ',"normals":'
            + far.normals
            + '},"parts":'
            + _colored_parts(library, kept, indexes)
            + ',"views":['
            + _view_objects()
            + "]}"
        )
    )
    far.uvs = _dump(packed, packed.at(packed.root, "uvs"))
    far.material = tag
    var material = _picture(library, "baked", tag, ".jpg")
    return (
        '{"empty":"false","material":'
        + String(material)
        + ',"mesh":'
        + _prim_json(far)
        + "}"
    )


def _picture(
    mut library: _Library, kind: String, tag: String, suffix: String
) raises -> Int:
    """Append one picture material and return its index.

    Args:
        library: The package library.
        kind: `baked` or `impostor`.
        tag: The atlas tag.
        suffix: `.jpg` or `.png`.

    Returns:
        The new material index.

    Raises:
        Error: If the picture record cannot be built.
    """
    var record = PyJson.parse(
        attach_text(
            '{"mode":"picture","kind":'
            + _json_string(kind)
            + ',"name":'
            + _json_string(tag)
            + ',"uri":'
            + _json_string("textures/" + tag + suffix)
            + ',"images":'
            + String(
                library.gltf.length(
                    library.gltf.at(library.gltf.root, "images")
                )
            )
            + ',"textures":'
            + String(
                library.gltf.length(
                    library.gltf.at(library.gltf.root, "textures")
                )
            )
            + ',"materials":'
            + String(
                library.gltf.length(
                    library.gltf.at(library.gltf.root, "materials")
                )
            )
            + "}"
        )
    )
    library.gltf.append(
        library.gltf.at(library.gltf.root, "images"),
        library.gltf.adopt(record, record.at(record.root, "image")),
    )
    library.gltf.append(
        library.gltf.at(library.gltf.root, "textures"),
        library.gltf.adopt(record, record.at(record.root, "texture")),
    )
    library.gltf.append(
        library.gltf.at(library.gltf.root, "materials"),
        library.gltf.adopt(record, record.at(record.root, "material")),
    )
    return _whole_node(record, record.at(record.root, "index"))


def _colored_parts(
    library: _Library, prims: List[_Prim], materials: List[Int]
) raises -> String:
    """Return the picture parts for these primitives.

    Args:
        library: The package library.
        prims: The primitives.
        materials: The glTF material index of each primitive.

    Returns:
        A JSON array.

    Raises:
        Error: If a material color cannot be read.
    """
    var out = String("[")
    for index in range(len(prims)):
        if index > 0:
            out += ","
        var material = library.gltf.item(
            library.gltf.at(library.gltf.root, "materials"), materials[index]
        )
        var color = PyJson.parse(
            albedo_text(
                '{"out_dir":'
                + _json_string(library.out_dir)
                + ',"material":'
                + _dump(library.gltf, material)
                + ',"textures":'
                + _dump(
                    library.gltf, library.gltf.at(library.gltf.root, "textures")
                )
                + ',"images":'
                + _dump(
                    library.gltf, library.gltf.at(library.gltf.root, "images")
                )
                + "}"
            )
        )
        var prim = prims[index]
        var cut = String("0.5")
        var cutoff = library.gltf.get(material, "alphaCutoff")
        if cutoff != MISSING:
            cut = _dump(library.gltf, cutoff)
        var masked = False
        var mode = library.gltf.get(material, "alphaMode")
        if mode != MISSING and library.gltf.text(mode) == "MASK":
            masked = True
        out += '{"positions":'
        out += prim.positions
        out += ',"normals":'
        out += prim.normals
        out += ',"uvs":'
        out += prim.uvs
        out += ',"triangles":'
        out += prim.triangles
        out += ',"factor":'
        out += _dump(color, color.at(color.root, "factor"))
        out += ',"cut":'
        out += cut
        out += ',"masked":'
        if masked:
            out += "true"
        else:
            out += "false"
        var image = color.get(color.root, "image")
        if image != MISSING:
            out += ',"image":'
            out += _dump(color, image)
        out += "}"
    out += "]"
    return out


def _join_parts(prims: List[_Prim]) -> String:
    """Return the join request parts."""
    var out = String("[")
    for index in range(len(prims)):
        if index > 0:
            out += ","
        var prim = prims[index]
        out += '{"positions":'
        out += prim.positions
        out += ',"normals":'
        out += prim.normals
        out += ',"uvs":'
        out += prim.uvs
        out += ',"triangles":'
        out += prim.triangles
        out += "}"
    out += "]"
    return out


def _kept_prims(
    prims: List[_Prim], start: Int, names_json: String
) raises -> List[_Prim]:
    """Return the primitives whose material is not the engine grid.

    Args:
        prims: Every loaded primitive.
        start: The first primitive of this mesh.
        names_json: The material name of each primitive, as a JSON array.

    Returns:
        The kept primitives.

    Raises:
        Error: If a material name is not text.
    """
    var names = PyJson.parse(names_json)
    var out = List[_Prim]()
    for index in range(names.length(names.root)):
        var name = names.text(names.item(names.root, index))
        if name == _GRID:
            continue
        out.append(prims[start + index])
    return out^


def _kept_materials(
    mut library: _Library, names_json: String
) raises -> List[Int]:
    """Return the glTF indexes of the non-grid materials.

    Args:
        library: The package library.
        names_json: The material name of each primitive, as a JSON array.

    Returns:
        The indexes, in primitive order.

    Raises:
        Error: If a material cannot be stored.
    """
    var names = PyJson.parse(names_json)
    var out = List[Int]()
    for index in range(names.length(names.root)):
        var name = names.text(names.item(names.root, index))
        if name == _GRID:
            continue
        out.append(library.material(name))
    return out^


def _view_objects() -> String:
    """Return the five bake views as JSON objects."""
    return (
        '{"forward":[1.0,0.0,0.0],"right":[0.0,0.0,-1.0],"up":[0.0,1.0,0.0]},'
        '{"forward":[-1.0,0.0,0.0],"right":[0.0,0.0,1.0],"up":[0.0,1.0,0.0]},'
        '{"forward":[0.0,0.0,1.0],"right":[1.0,0.0,0.0],"up":[0.0,1.0,0.0]},'
        '{"forward":[0.0,0.0,-1.0],"right":[-1.0,0.0,0.0],"up":[0.0,1.0,0.0]},'
        '{"forward":[0.0,1.0,0.0],"right":[1.0,0.0,0.0],"up":[0.0,0.0,-1.0]}'
    )


def _copy_entries(matrices: String, spline: String) raises -> String:
    """Return copy records for these matrices.

    Args:
        matrices: A JSON array of 4×4 matrices.
        spline: The spline JSON, or empty.

    Returns:
        A JSON array of copy objects.

    Raises:
        Error: If `matrices` is not an array.
    """
    var doc = PyJson.parse(matrices)
    var out = String("[")
    for index in range(doc.length(doc.root)):
        if index > 0:
            out += ","
        out += '{"matrix":'
        out += _dump(doc, doc.item(doc.root, index))
        if spline.byte_length() > 0:
            out += ',"spline":'
            out += spline
        out += "}"
    out += "]"
    return out


def _join_array(mut dest: String, mut first: Bool, extra: String) raises:
    """Append the elements of a JSON array to `dest`.

    Args:
        dest: The destination array body, without the closing bracket.
        first: True when `dest` has no element yet.
        extra: A JSON array.

    Raises:
        Error: If `extra` is not an array.
    """
    if extra == "null" or extra == "[]":
        return
    var doc = PyJson.parse(extra)
    for index in range(doc.length(doc.root)):
        if not first:
            dest += ","
        first = False
        dest += _dump(doc, doc.item(doc.root, index))


def _triangle_count(text: String) raises -> Int:
    """Return the triangle count of a primitive JSON object.

    Args:
        text: A primitive JSON object.

    Returns:
        The number of triangles.

    Raises:
        Error: If `triangles` is missing.
    """
    var doc = PyJson.parse(text)
    return doc.length(doc.at(doc.root, "triangles"))


def _mesh_fields(text: String) raises -> String:
    """Return the four mesh arrays in a group part.

    Args:
        text: A primitive JSON object.

    Returns:
        `positions`, `normals`, `uvs` and `triangles` as JSON fields.

    Raises:
        Error: If a field is missing.
    """
    var doc = PyJson.parse(text)
    var out = String('"positions":')
    out += _dump(doc, doc.at(doc.root, "positions"))
    out += ',"normals":'
    out += _dump(doc, doc.at(doc.root, "normals"))
    out += ',"uvs":'
    out += _dump(doc, doc.at(doc.root, "uvs"))
    out += ',"triangles":'
    out += _dump(doc, doc.at(doc.root, "triangles"))
    return out


def _file_json(path: String) raises -> String:
    """Return a JSON string of a file, or `null` when `path` is empty.

    Args:
        path: The file path.

    Returns:
        JSON text.

    Raises:
        Error: If the file cannot be read.
    """
    if path.byte_length() == 0:
        return "null"
    var raw = Path(path).read_bytes()
    return _json_string(String(from_utf8_lossy=Span(raw)))


def _copy_file(source: String, destination: String) raises:
    """Copy `source` onto `destination`.

    Args:
        source: The existing file.
        destination: The new file.

    Raises:
        Error: If the file cannot be read or written.
    """
    var data = Path(source).read_bytes()
    Path(destination).write_bytes(data)


def _json_string(text: String) raises -> String:
    """Return `text` as a JSON string.

    Args:
        text: The text.

    Returns:
        The quoted JSON.

    Raises:
        Error: If the text cannot be encoded.
    """
    var doc = PyJson()
    doc.root = doc.new_str(text)
    return doc.dumps()


def _json_number(value: Float64) raises -> String:
    """Return `value` as Python writes it.

    Args:
        value: The number.

    Returns:
        The JSON number.

    Raises:
        Error: If the number is not finite.
    """
    return python_repr(value)


def _string_array(values: List[String]) raises -> String:
    """Return `values` as a JSON array of strings.

    Args:
        values: The strings.

    Returns:
        The JSON array.

    Raises:
        Error: If a string cannot be encoded.
    """
    var out = String("[")
    for index in range(len(values)):
        if index > 0:
            out += ","
        out += _json_string(values[index])
    out += "]"
    return out


def _dump(doc: PyJson, node: Int) raises -> String:
    """Return the canonical JSON of one node.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The JSON text.

    Raises:
        Error: If the value is not finite.
    """
    var child = doc.subtree(node)
    return child.dumps()


def _whole_node(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The integer.

    Raises:
        Error: If the value is not an integer.
    """
    return _whole(doc.text(node))


def _whole(text: String) raises -> Int:
    """Return the integer written in `text`.

    Args:
        text: The digits.

    Returns:
        The integer.

    Raises:
        Error: If `text` is not an integer.
    """
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error("expected an integer")
    var start = 0
    if raw[0] == UInt8(ord("-")):
        start = 1
    var index = start
    while index < len(raw):
        var digit = Int(raw[index])
        if digit < ord("0") or digit > ord("9"):
            raise Error("expected an integer")
        index += 1
    if index == start:
        raise Error("expected an integer")
    try:
        return Int(text)
    except:
        raise Error("expected an integer")


def _lower_ascii(text: String) -> String:
    """Return `text` with ASCII capitals folded."""
    var raw = text.as_bytes()
    var out = List[UInt8]()
    for index in range(len(raw)):
        var value = Int(raw[index])
        if value >= 65 and value <= 90:
            value += 32
        out.append(UInt8(value))
    return String(unsafe_from_utf8=Span(out))


def _starts(text: String, prefix: String) -> Bool:
    """Return whether `text` begins with `prefix`."""
    var raw = text.as_bytes()
    var head = prefix.as_bytes()
    if len(raw) < len(head):
        return False
    for index in range(len(head)):
        if raw[index] != head[index]:
            return False
    return True
