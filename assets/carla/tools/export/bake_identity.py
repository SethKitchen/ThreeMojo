# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Content identities for a town's immutable far-bake inputs, without NumPy."""

import hashlib
import json
import os


# Bump this when the identity encoding or a bake's fixed algorithm/format
# changes. Explicit settings are also hashed. This is a name schema, not a
# persistent cache: each build creates a new BakeIdentity.
_IDENTITY_VERSION = 1


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     allow_nan=False).encode("utf-8")).hexdigest()


class BakeIdentity:
    """Cache resolved material and texture identities for one package build.

    Materials and packaged texture files must stay unchanged after first use.
    A new build must use a new instance. No cache persists between builds.

    Args:
        gltf: The package's glTF tables, which can grow during the build.
        out_dir: The directory that holds the package's texture files.

    Returns:
        A build-local identity cache.

    Raises:
        None.
    """

    def __init__(self, gltf, out_dir):
        self.gltf = gltf
        self.out_dir = out_dir
        self._materials = {}
        self._images = {}

    def _image(self, index):
        image = dict(self.gltf["images"][index])
        uri = image["uri"]
        if uri not in self._images:
            digest = hashlib.sha256()
            with open(os.path.join(self.out_dir, uri), "rb") as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(block)
            self._images[uri] = digest.hexdigest()
        # Keep the relative URI and image properties, never the output root
        # or a transient index. A changed file at the same URI gets a new
        # identity when the next build creates its cache.
        image["sha256"] = self._images[uri]
        return image

    def _resolve(self, value):
        if isinstance(value, list):
            return [self._resolve(item) for item in value]
        if not isinstance(value, dict):
            return value
        result = {}
        for key, item in value.items():
            if key.endswith("Texture") and isinstance(item, dict) and "index" in item:
                info = dict(item)
                texture = dict(self.gltf["textures"][info.pop("index")])
                texture["source"] = self._image(texture["source"])
                if "sampler" in texture:
                    texture["sampler"] = self.gltf["samplers"][texture["sampler"]]
                info["texture"] = texture
                result[key] = info
            else:
                result[key] = self._resolve(item)
        return result

    def key(self, mesh_path, kind, parts, settings):
        """Return a stable atlas tag for an ordered list of resolved parts.

        Args:
            mesh_path: The source mesh's path.
            kind: The existing atlas prefix, baked or impostor.
            parts: Ordered pairs of geometry digests and material indices.
            settings: The bake settings that affect the output.

        Returns:
            The prefix followed by a SHA-256 of the complete input identity.

        Raises:
            OSError: A referenced texture cannot be read.
            KeyError: A required glTF property is absent.
            IndexError: A glTF reference is out of range.
            ValueError: A numeric material or setting is not finite.
        """
        ordered = []
        for geometry, material in parts:
            if material not in self._materials:
                self._materials[material] = _digest(self._resolve(self.gltf["materials"][material]))
            ordered.append((geometry, self._materials[material]))
        return kind + "_" + _digest([_IDENTITY_VERSION, mesh_path, kind, ordered, settings])
