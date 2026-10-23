# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact PR780 source and qualification provenance; no physical admission.

This pure leaf reads no files and accepts no root. Its fixed inverse preserves
all original PR760 pins. The owning checker still observes current bytes,
checks the complete dependency graph, and binds its final physical reads.
"""
import hashlib
import json
import sys

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

_EXECUTED_MODULE_CODE = sys._getframe().f_code

# BEGIN FIXED PR780 SUCCESSOR DATA
EDGES = json.loads(r'''
{
  "core/extent.mojo": {
    "before_sha256": "50f3c4fcc55b672ab1d42505cf70baeb3aae85ebf915927369246ab7e214a023",
    "after_sha256": "90490706baa17456a3ec99374c2a00f72768a0178b4e56436571ab4ca673f068",
    "before_token_sha256": "04720c0647200cb22f94d26bc47e87687f4b905791c18733b044ad2706322e50",
    "after_token_sha256": "a730cc2bbfa638ef6a8bc02a8496b3b641da4077ee23c79c7c2130217ace251f",
    "edits": [
      {
        "start": 61,
        "stop": 63,
        "before": [
          "    validate the sizes or guard against an overflowing product.\n"
        ],
        "after": [
          "    validate the sizes. A product that cannot fit in Int raises the\n",
          "    caller's error instead of trapping on signed overflow.\n"
        ]
      },
      {
        "start": 75,
        "stop": 76,
        "before": [
          "            channels.\n"
        ],
        "after": [
          "            channels, or the product cannot fit in Int.\n"
        ]
      },
      {
        "start": 77,
        "stop": 87,
        "before": [
          "    if length != width * height * channels:\n"
        ],
        "after": [
          "    # Two Int factors fit exactly in Int128, including Int.MIN * -1.\n",
          "    # Check the last factor against the final sign's magnitude limit.\n",
          "    # A zero channel count can still make an oversized area fit.\n",
          "    var area = Int128(width) * Int128(height)\n",
          "    var factor = Int128(channels)\n",
          "    var negative = (area < 0) != (factor < 0)\n",
          "    var limit = Int128(Int.MAX) + Int128(negative)\n",
          "    if factor != 0 and abs(area) > limit // abs(factor):\n",
          "        raise Error(message)\n",
          "    if Int128(length) != area * factor:\n"
        ]
      }
    ]
  },
  "extensions/carla/v2x.mojo": {
    "before_sha256": "1a4e8d23c07db07a61f28a0897481c5d2b8b91d14106fc841f681eb3331d03b7",
    "after_sha256": "9177db17caf38940a18b671ea04d3877cc14e966e5352e21576e95ed1449e308",
    "before_token_sha256": "e73e65b416ecc6ec593c61a7041c896a81de7004421ee6c332336d23b85dd57f",
    "after_token_sha256": "7cfecc81c8c883f9feee43b67149d5b94969daafd216a6b8481bbe1c41c7f7db",
    "edits": [
      {
        "start": 57,
        "stop": 62,
        "before": [],
        "after": [
          "- Heading comparisons clamp the cosine before `acos`. An unset previous\n",
          "  heading counts as changed. Every generated CAM stores the current\n",
          "  heading, position and speed, even when one trigger skips the others.\n",
          "  CARLA at `1360bb9` leaves skipped values at their old samples. These\n",
          "  changes prevent missed half turns and extra messages after a turn.\n"
        ]
      },
      {
        "start": 118,
        "stop": 119,
        "before": [],
        "after": [
          "from math.utils import clamp_unit\n"
        ]
      },
      {
        "start": 1992,
        "stop": 2000,
        "before": [
          "        var angle = acos(\n",
          "            Float64(a.dot(b)) / (Float64(a.length()) * Float64(b.length()))\n",
          "        )\n"
        ],
        "after": [
          "        var la = Float64(a.length())\n",
          "        var lb = Float64(b.length())\n",
          "        # An unset heading counts as changed after the minimum interval.\n",
          "        if not (la > 0.0) or not (lb > 0.0):\n",
          "            return True\n",
          "        # Clamp: Float32 rounding can push the cosine of near-parallel unit\n",
          "        # vectors past 1 by an ulp, and acos of that is NaN.\n",
          "        var angle = acos(clamp_unit(Float64(a.dot(b)) / (la * lb)))\n"
        ]
      },
      {
        "start": 2017,
        "stop": 2025,
        "before": [],
        "after": [
          "        # A heading trigger short-circuits the position and speed checks.\n",
          "        # Save the whole current state so the next tick compares against\n",
          "        # this CAM, including the first and fixed-rate messages.\n",
          "        self.vehicle_position = world.get_location(self.owner)\n",
          "        self.vehicle_speed = self._forward_speed(world)\n",
          "        self.vehicle_heading = world.get_transform(\n",
          "            self.owner\n",
          "        ).rotation.forward_vector()\n"
        ]
      }
    ]
  },
  "geometries/box.mojo": {
    "before_sha256": "fecb76f248d3d0e42a1835e15772f4371951d10c615dc54e0851bd3deb88367b",
    "after_sha256": "3092d492c4f7efd3bdc0ae198f14c0556cb3fce10ba2f05e509a60a0a8b3623f",
    "before_token_sha256": "6fe072b5242e30914a4ab2e539690915cac3436c70ffb2034f7fadb5a6549251",
    "after_token_sha256": "c0d380d72488563f232f3009fdb0f42578b1d43299b8f3b877fb53405da42e6a",
    "edits": [
      {
        "start": 22,
        "stop": 28,
        "before": [],
        "after": [
          "\n",
          "## Input validation difference\n",
          "\n",
          "Shape dimensions must be finite before vertices are generated. NaN and\n",
          "either infinity raise an error. This differs from the unchecked three.js\n",
          "r186 input path. Finite supported inputs keep their existing behavior.\n"
        ]
      },
      {
        "start": 43,
        "stop": 44,
        "before": [],
        "after": [
          "    require_finite_extents,\n"
        ]
      },
      {
        "start": 165,
        "stop": 168,
        "before": [
          "        Error: If any extent is not positive, or any segment count is\n",
          "            below one. three.js floors a count and takes what it gets.\n"
        ],
        "after": [
          "        Error: If any extent is not finite or not positive, or any segment\n",
          "            count is below one. three.js floors a count and takes what it\n",
          "            gets.\n"
        ]
      },
      {
        "start": 169,
        "stop": 170,
        "before": [],
        "after": [
          "    require_finite_extents(width.value, height.value, depth.value, \"box\")\n"
        ]
      }
    ]
  },
  "geometries/circle.mojo": {
    "before_sha256": "9b63de2bcac8903b67458ea26901505e7030fc10a5d4c2e3da77debbab0c4605",
    "after_sha256": "8e9fa6d4e98910161c3efc9c2b3c58bd0d75ad05b505968d99de354061571d6e",
    "before_token_sha256": "1e9db0a7ef47b22770ecc835f48c7d167eab54d6714968d4b0566e2b348cc188",
    "after_token_sha256": "eeea9d74cfe15475bf5a82bc8eeb778ee89fafc83847350c822fbacff3f26cbd",
    "edits": [
      {
        "start": 33,
        "stop": 39,
        "before": [],
        "after": [
          "\n",
          "## Input validation difference\n",
          "\n",
          "Shape dimensions must be finite before vertices are generated. NaN and\n",
          "either infinity raise an error. This differs from the unchecked three.js\n",
          "r186 input path. Finite supported inputs keep their existing behavior.\n"
        ]
      },
      {
        "start": 46,
        "stop": 47,
        "before": [
          "from core.ordinal import require_non_negative, require_positive\n"
        ],
        "after": [
          "from core.ordinal import require_positive\n"
        ]
      },
      {
        "start": 48,
        "stop": 49,
        "before": [],
        "after": [
          "from math.finite import require_finite\n"
        ]
      },
      {
        "start": 197,
        "stop": 201,
        "before": [
          "        Error: If the inner radius is negative, the outer radius is not\n",
          "            more than it, either segment count is too small, or the sweep\n",
          "            is not positive or is more than a turn.\n"
        ],
        "after": [
          "        Error: If the inner radius is not finite or is negative, the outer\n",
          "            radius is not finite or not more than it, either segment count\n",
          "            is too small, or the sweep is not positive or is more than a\n",
          "            turn.\n"
        ]
      },
      {
        "start": 202,
        "stop": 209,
        "before": [
          "    require_non_negative(\n",
          "        inner_radius.value, \"A ring's inner radius cannot be negative\"\n",
          "    )\n",
          "    if outer_radius.value <= inner_radius.value:\n"
        ],
        "after": [
          "    require_finite(Float64(inner_radius.value), \"A ring needs finite radii\")\n",
          "    require_finite(Float64(outer_radius.value), \"A ring needs finite radii\")\n",
          "    # `not (x >= 0)`, not `x < 0`: NaN compares false both ways, so the\n",
          "    # < form would let it through.\n",
          "    if not (inner_radius.value >= 0):\n",
          "        raise Error(\"A ring's inner radius cannot be negative\")\n",
          "    if not (outer_radius.value > inner_radius.value):\n"
        ]
      }
    ]
  },
  "geometries/cylinder.mojo": {
    "before_sha256": "34de4d39e213985bb6c1280dcfab394f4f726f4b6051c874d1af37392bffa46e",
    "after_sha256": "40e0c79a6ab1fd26bde143a39cced6c451295c0b9305ac4737e4fdcd61e7e017",
    "before_token_sha256": "46980193661a602bdadd26f2498b4f33a8d16a48c1c753ea383b865083b909ce",
    "after_token_sha256": "811f5b6ec73a75e630c630649d4c6a5b2a4eaa41a0c746a04111857913dee069",
    "edits": [
      {
        "start": 37,
        "stop": 43,
        "before": [],
        "after": [
          "\n",
          "## Input validation difference\n",
          "\n",
          "Shape dimensions must be finite before vertices are generated. NaN and\n",
          "either infinity raise an error. This differs from the unchecked three.js\n",
          "r186 input path. Finite supported inputs keep their existing behavior.\n"
        ]
      },
      {
        "start": 51,
        "stop": 51,
        "before": [
          "from core.ordinal import require_positive\n"
        ],
        "after": []
      },
      {
        "start": 52,
        "stop": 53,
        "before": [],
        "after": [
          "    require_finite_extents,\n"
        ]
      },
      {
        "start": 183,
        "stop": 187,
        "before": [
          "        Error: If either radius is negative or both are zero, the height is\n",
          "            not positive, either segment count is too small, or the sweep\n",
          "            is not positive or is more than a turn.\n"
        ],
        "after": [
          "        Error: If either radius is not finite, is negative, or both are\n",
          "            zero, the height is not finite or not positive, either segment\n",
          "            count is too small, or the sweep is not positive or is more\n",
          "            than a turn.\n"
        ]
      },
      {
        "start": 188,
        "stop": 194,
        "before": [
          "    if radius_top.value < 0 or radius_bottom.value < 0:\n"
        ],
        "after": [
          "    require_finite_extents(\n",
          "        radius_top.value, radius_bottom.value, height.value, \"cylinder\"\n",
          "    )\n",
          "    # `not (x >= 0)`, not `x < 0`: NaN compares false both ways, so the\n",
          "    # < form would let it through.\n",
          "    if not (radius_top.value >= 0) or not (radius_bottom.value >= 0):\n"
        ]
      },
      {
        "start": 197,
        "stop": 199,
        "before": [
          "    require_positive(height.value, \"A cylinder needs a positive height\")\n"
        ],
        "after": [
          "    if not (height.value > 0):\n",
          "        raise Error(\"A cylinder needs a positive height\")\n"
        ]
      }
    ]
  },
  "geometries/plane.mojo": {
    "before_sha256": "f5f006fb58df50e4376d6b3d90180a5497e2af42a9c4ff4b87cec34b96578956",
    "after_sha256": "0ff718306ad6b3370e6e2f2d94a805ea1e6582a1d6f49d5332ed439c1957b712",
    "before_token_sha256": "1c10fc9d0a7fdf43baca02b886ce034a50dca661debef0a8157da2aa200a756d",
    "after_token_sha256": "f1e643b9146d6742eb3ea3153911391cb72e276123452efeb5f7a4fe5ff4f76e",
    "edits": [
      {
        "start": 23,
        "stop": 29,
        "before": [],
        "after": [
          "\n",
          "## Input validation difference\n",
          "\n",
          "Shape dimensions must be finite before vertices are generated. NaN and\n",
          "either infinity raise an error. This differs from the unchecked three.js\n",
          "r186 input path. Finite supported inputs keep their existing behavior.\n"
        ]
      },
      {
        "start": 33,
        "stop": 34,
        "before": [],
        "after": [
          "from math.finite import require_finite\n"
        ]
      },
      {
        "start": 62,
        "stop": 64,
        "before": [
          "        Error: If either extent is not positive, or either segment count is\n",
          "            less than one.\n"
        ],
        "after": [
          "        Error: If either extent is not finite or not positive, or either\n",
          "            segment count is less than one.\n"
        ]
      },
      {
        "start": 65,
        "stop": 70,
        "before": [
          "    if width.value <= 0 or height.value <= 0:\n"
        ],
        "after": [
          "    require_finite(Float64(width.value), \"A plane needs finite extents\")\n",
          "    require_finite(Float64(height.value), \"A plane needs finite extents\")\n",
          "    # `not (x > 0)`, not `x <= 0`: NaN compares false both ways, so the\n",
          "    # <= form would let a NaN extent through.\n",
          "    if not (width.value > 0) or not (height.value > 0):\n"
        ]
      }
    ]
  },
  "geometries/surface.mojo": {
    "before_sha256": "8ff3246d240c90168470bde485496accca02d7096a53270c0d6ce442a4429e04",
    "after_sha256": "deeba40777e10da75651f07b8d8f86abb609d4c916b098f1dc28be228f20d3cd",
    "before_token_sha256": "08d4f6b7acc5d842ae4d68c1b446c07b70a76c7ff9be350e0895964af36e26d2",
    "after_token_sha256": "8d7ee97ba23d77d381a1267b92c9703ae2e932eb3e3353c4100ca34b9f73edf6",
    "edits": [
      {
        "start": 19,
        "stop": 25,
        "before": [],
        "after": [
          "\n",
          "## Input validation difference\n",
          "\n",
          "Shape dimensions must be finite before vertices are generated. NaN and\n",
          "either infinity raise an error. This differs from the unchecked three.js\n",
          "r186 input path. Finite supported inputs keep their existing behavior.\n"
        ]
      },
      {
        "start": 36,
        "stop": 37,
        "before": [],
        "after": [
          "from math.finite import require_finite\n"
        ]
      },
      {
        "start": 252,
        "stop": 253,
        "before": [
          "        Error: If the radius is zero or negative.\n"
        ],
        "after": [
          "        Error: If the radius is not finite, or is zero or negative.\n"
        ]
      },
      {
        "start": 254,
        "stop": 258,
        "before": [
          "    if radius <= 0:\n"
        ],
        "after": [
          "    require_finite(Float64(radius), \"A \" + name + \" needs a finite radius\")\n",
          "    # `not (radius > 0)`, not `radius <= 0`: NaN compares false both ways,\n",
          "    # so the <= form would let it through.\n",
          "    if not (radius > 0):\n"
        ]
      }
    ]
  },
  "loaders/bytes.mojo": {
    "before_sha256": "5600d6d9ca117fc7c7c97a2e5d6a687adc8090627c34cf3181935245dae87c07",
    "after_sha256": "139ca1cb876bdf7b0a7c258d1d3a40375d8f3b73c75af160e26e07e7c9ba062a",
    "before_token_sha256": "6c80798cf958a0d40f9da48e94a9c2303ecabf39201b9129ffdc30de82fe0ee1",
    "after_token_sha256": "8265908cc94802543f3ad3ce2d4ad817cb9e9b59b1c0b932aefc305bb55d8527",
    "edits": [
      {
        "start": 33,
        "stop": 34,
        "before": [
          "    if at + len(expected) > limit:\n"
        ],
        "after": [
          "    if at < 0 or limit > len(bytes) or at > limit or len(expected) > limit - at:\n"
        ]
      }
    ]
  },
  "loaders/draco.mojo": {
    "before_sha256": "985ed0c44c2d519c156d2aeed24e214f59a390f04a298309cf516533892fbb0b",
    "after_sha256": "2c6932ab9e1a108b896fd98c86b690e4daafe3fc4f6182725348fddccdeb9c78",
    "before_token_sha256": "4294f201e3bcd9c5c015ee2cdb41751862a91f493de31108daaa2337865f36ed",
    "after_token_sha256": "c63ead84d7193a84be908f9e91f85fe746c8c319bfce350bcf2d0b45abea5faa",
    "edits": [
      {
        "start": 42,
        "stop": 47,
        "before": [
          "prediction with the wrap transform; this refuses both.\n"
        ],
        "after": [
          "prediction with the wrap transform; this refuses both. Point clouds are\n",
          "limited to 2**26 points. Before attribute decoding, all attributes share\n",
          "a 1 GiB storage budget, counted at eight bytes per component plus eight\n",
          "bytes per point map entry. Input, connectivity, and temporary copies are\n",
          "additional storage.\n"
        ]
      },
      {
        "start": 140,
        "stop": 146,
        "before": [],
        "after": [
          "\n",
          "# The most points a point cloud may declare. Each attribute allocates\n",
          "# `points` elements up front, so an unbounded count is an out-of-memory\n",
          "# wait away; 2**26 points is generous for any real scan.\n",
          "comptime MAX_DRACO_POINTS = 1 << 26\n",
          "comptime MAX_DRACO_ATTRIBUTE_BYTES = 1 << 30\n"
        ]
      },
      {
        "start": 374,
        "stop": 375,
        "before": [],
        "after": [
          "    var attribute_bytes: Int\n"
        ]
      },
      {
        "start": 391,
        "stop": 392,
        "before": [],
        "after": [
          "        self.attribute_bytes = 0\n"
        ]
      },
      {
        "start": 483,
        "stop": 493,
        "before": [],
        "after": [
          "    def reserve_attribute(mut self, components: Int) raises:\n",
          "        \"\"\"Charge decoded components and point mappings before allocation.\"\"\"\n",
          "        var per_point = (components + 1) * 8\n",
          "        draco_require(\n",
          "            self.geometry.points\n",
          "            <= (MAX_DRACO_ATTRIBUTE_BYTES - self.attribute_bytes) // per_point,\n",
          "            \"the attributes are too large to decode\",\n",
          "        )\n",
          "        self.attribute_bytes += self.geometry.points * per_point\n",
          "\n"
        ]
      },
      {
        "start": 511,
        "stop": 512,
        "before": [],
        "after": [
          "            self.reserve_attribute(components)\n"
        ]
      },
      {
        "start": 599,
        "stop": 599,
        "before": [
          "        var points = self.sequence(index)\n"
        ],
        "after": []
      },
      {
        "start": 601,
        "stop": 616,
        "before": [],
        "after": [
          "        if not self.edgebreaker() and self.geometry.points > 0:\n",
          "            var minimum = 0\n",
          "            for i in range(len(ids)):  # pragma: no branch\n",
          "                ref attribute = self.geometry.attributes[ids[i]]\n",
          "                if codings[i] == DRACO_RAW:\n",
          "                    minimum += (\n",
          "                        self.geometry.points\n",
          "                        * attribute.components\n",
          "                        * attribute.data_type.size()\n",
          "                    )\n",
          "                else:\n",
          "                    # Prediction and compression flags precede every stream.\n",
          "                    minimum += 2\n",
          "            self.buffer.need(minimum)\n",
          "        var points = self.sequence(index)\n"
        ]
      },
      {
        "start": 617,
        "stop": 617,
        "before": [
          "            self.geometry.attributes[ids[i]].reset(len(points))\n"
        ],
        "after": []
      },
      {
        "start": 618,
        "stop": 619,
        "before": [],
        "after": [
          "                self.geometry.attributes[ids[i]].count = len(points)\n"
        ]
      },
      {
        "start": 621,
        "stop": 622,
        "before": [],
        "after": [
          "                self.geometry.attributes[ids[i]].reset(len(points))\n"
        ]
      },
      {
        "start": 668,
        "stop": 671,
        "before": [
          "        var size = len(attribute.bytes)\n"
        ],
        "after": [
          "        var size = (\n",
          "            attribute.count * attribute.components * attribute.data_type.size()\n",
          "        )\n"
        ]
      },
      {
        "start": 1021,
        "stop": 1024,
        "before": [],
        "after": [
          "        draco_require(\n",
          "            points <= MAX_DRACO_POINTS, \"the point count is too large\"\n",
          "        )\n"
        ]
      }
    ]
  },
  "loaders/gltf_layout.mojo": {
    "before_sha256": "6061b8eaf1bf4fbe1e1503833a1e4a742d9d959dd488f7b6e05862e3d7e41067",
    "after_sha256": "a9963c0da350d872feb73695ca98e9ced0e43ae99fb635f44d86d6f6d7e54e27",
    "before_token_sha256": "d5f8dabf81174e7c2841fce8d6102648d9b2e2ae8a76566df94d3848da301800",
    "after_token_sha256": "a3f506d03887f3081ff3118e7921005b030112fc9a239826f37860456e19ded9",
    "edits": [
      {
        "start": 4,
        "stop": 8,
        "before": [],
        "after": [
          "\n",
          "Each accessor is limited to 2**26 elements and 1 GiB of decoded component\n",
          "storage, counted at eight bytes per component. This bounds an individual\n",
          "accessor, including an implicit zero array, not the whole scene.\n"
        ]
      },
      {
        "start": 27,
        "stop": 36,
        "before": [],
        "after": [
          "\n",
          "\n",
          "# The most elements one accessor may declare. A bufferView-less accessor\n",
          "# is zero-filled element by element, so a corrupt count would otherwise\n",
          "# spin for billions of iterations; 2**26 elements is generous for any\n",
          "# real asset.\n",
          "comptime MAX_GLTF_ACCESSOR_COUNT = 1 << 26\n",
          "# Accessors can decode to Float64 or Int64, regardless of source width.\n",
          "comptime MAX_GLTF_ACCESSOR_BYTES = 1 << 30\n"
        ]
      },
      {
        "start": 112,
        "stop": 117,
        "before": [
          "        if count < 0 or count > 9223372036854775807 // self.width:\n"
        ],
        "after": [
          "        if (\n",
          "            count < 0\n",
          "            or count > MAX_GLTF_ACCESSOR_COUNT\n",
          "            or count > MAX_GLTF_ACCESSOR_BYTES // (self.width * 8)\n",
          "        ):\n"
        ]
      }
    ]
  },
  "loaders/meshopt.mojo": {
    "before_sha256": "09c9d8e98248fb0f3e05a3e2dcb01f7aafbe691b065e4ec0ec1f6f1de4680aec",
    "after_sha256": "dd98ac61f878c9202c447d526086c113cb5942d9d262ce39023448c8f793a4e9",
    "before_token_sha256": "079200d7dc3c70329177a08b7af961f3faf8310dfa1f13291a73c886b054b155",
    "after_token_sha256": "4fa068fa3453b52162e1ea840c830d3616d8b07ba39985096ce74a6c086e0e19",
    "edits": [
      {
        "start": 30,
        "stop": 33,
        "before": [],
        "after": [
          "\n",
          "**Where this port differs.** Each decoded buffer is limited to 1 GiB.\n",
          "The limit is checked before allocation for all three modes.\n"
        ]
      },
      {
        "start": 239,
        "stop": 253,
        "before": [],
        "after": [
          "def require_meshopt_output(count: Int, size: Int) raises:\n",
          "    \"\"\"Check decoded storage after the mode validates count and size.\n",
          "\n",
          "    Args:\n",
          "        count: The nonnegative element count.\n",
          "        size: The positive bytes per element.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the decoded buffer would exceed 1 GiB.\n",
          "    \"\"\"\n",
          "    if count > (1 << 30) // size:\n",
          "        raise Error(\"meshopt: a buffer too large to decode\")\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 306,
        "stop": 307,
        "before": [],
        "after": [
          "    require_meshopt_output(count, size)\n"
        ]
      },
      {
        "start": 317,
        "stop": 325,
        "before": [],
        "after": [
          "    # Even an all-zero block needs one header per four 16-byte groups.\n",
          "    # Check this lower bound before allocating the decoded buffer.\n",
          "    var full_headers = (block // _GROUP + 3) // 4\n",
          "    var remainder = count % block\n",
          "    var tail_headers = ((remainder + _GROUP - 1) // _GROUP + 3) // 4\n",
          "    var headers = (count // block * full_headers + tail_headers) * size\n",
          "    if count > 0 and headers > end - 1 - max(size, _TAIL_MIN):\n",
          "        raise _malformed(-2)\n"
        ]
      },
      {
        "start": 438,
        "stop": 439,
        "before": [],
        "after": [
          "    require_meshopt_output(count, size)\n"
        ]
      },
      {
        "start": 565,
        "stop": 566,
        "before": [],
        "after": [
          "    require_meshopt_output(count, size)\n"
        ]
      }
    ]
  },
  "math/matrix4.mojo": {
    "before_sha256": "206877d7335ed69e9055ec69b2ac09bd83b493456bfc43c1083ea235a1a44549",
    "after_sha256": "1e72ab51f9dbcee3af4c2bfe9da93946616736bf02f4b20e2160ee7b69b448fa",
    "before_token_sha256": "e081739275371437cd16dd27657c3b19fe6f8b3bc7267aed33ff24fe17fce70f",
    "after_token_sha256": "739ddcb86f0f39a6eca4737c932358c4cbd96a0d1f4bc87ab28a5f643a6ff070",
    "edits": [
      {
        "start": 36,
        "stop": 37,
        "before": [],
        "after": [
          "    _pre_multiply,\n"
        ]
      },
      {
        "start": 244,
        "stop": 245,
        "before": [
          "        var left = Matrix4(copy=other)\n",
          "        left.multiply(self)\n",
          "        self.elements = left.elements.copy()\n"
        ],
        "after": [
          "        _pre_multiply[4](self.elements, other.elements)\n"
        ]
      }
    ]
  },
  "math/square_matrix.mojo": {
    "before_sha256": "04a9f011e814455c9d24a94c66df30b8137f7e9802a2a9b552b0d9bb05538c27",
    "after_sha256": "f1b2e67489949b53594b5f06604a0227260fd961df2fdebe5347d91c82d99a69",
    "before_token_sha256": "d9091249e49cf9e6abca3f6549987c41f0134c0d7dfeb310c128796f486b7f73",
    "after_token_sha256": "61cce77fd47e8b3c17409747300b6b19b9090a48f121f37d01ca05200adde66d",
    "edits": [
      {
        "start": 50,
        "stop": 76,
        "before": [],
        "after": [
          "            result[column * n + row] = total\n",
          "    left = result^\n",
          "\n",
          "\n",
          "@always_inline\n",
          "def _pre_multiply[\n",
          "    n: Int\n",
          "](mut left: Array[Float32, n * n], right: Array[Float32, n * n]):\n",
          "    \"\"\"Replace `left` with `right * left`.\n",
          "\n",
          "    The matrix stored in `left` is applied to a point first. `n` is three or\n",
          "    four, so none of the loops can run zero times.\n",
          "\n",
          "    Parameters:\n",
          "        n: The side length.\n",
          "\n",
          "    Args:\n",
          "        left: The matrix applied first. It is replaced.\n",
          "        right: The matrix applied second.\n",
          "    \"\"\"\n",
          "    var result = Array[Float32, n * n](fill=0.0)\n",
          "    for row in range(n):  # pragma: no branch\n",
          "        for column in range(n):  # pragma: no branch\n",
          "            var total = Float32(0)\n",
          "            for k in range(n):  # pragma: no branch\n",
          "                total += right[k * n + row] * left[column * n + k]\n"
        ]
      }
    ]
  },
  "math/vector4.mojo": {
    "before_sha256": "44797637aae80c1e92c08592bc2a510e90e14e93d1c74bb4a01ca71034b10ee6",
    "after_sha256": "db774733a27a706e5d5c940c4533de2c567d7d6ece3c918215052bccfd87b9aa",
    "before_token_sha256": "ef760bfaac736f0aaeeed0ca854beb94340aa99b6ea4c49176cf8e422d152c95",
    "after_token_sha256": "ef760bfaac736f0aaeeed0ca854beb94340aa99b6ea4c49176cf8e422d152c95",
    "edits": [
      {
        "start": 49,
        "stop": 52,
        "before": [
          "# diagonal entry is too small to divide by: its literal, not the exact\n",
          "# square root of a half.\n"
        ],
        "after": [
          "# diagonal entry is too small to divide by. three.js writes the literal\n",
          "# 0.7071; this port keeps a closer approximation of the exact square\n",
          "# root of a half instead.\n"
        ]
      }
    ]
  },
  "postprocessing/denoise.mojo": {
    "before_sha256": "0cc2fa358a413e982da70aafbf082c5cde41b1105c98cc3770f3d2149d1f0664",
    "after_sha256": "03bd377c4458b6801ba5a19e4cedfe32d985a64d541c16a28ab5e8566a0ada19",
    "before_token_sha256": "3c24d8a6900fb93334b719698dc563ce3d989fb7af36c8cba5e0f49333b1745e",
    "after_token_sha256": "c354eb80dee8e692fbb73d2690024b34a735d5a41073374713422e5b367a9153",
    "edits": [
      {
        "start": 20,
        "stop": 25,
        "before": [],
        "after": [
          "\n",
          "The node multiplies its pixel-space offset by the matrix before dividing\n",
          "by the image size. This order keeps the taps the same size in pixels on\n",
          "rectangular frames. The port's upward texture coordinate reverses only\n",
          "the resulting vertical offset.\n"
        ]
      },
      {
        "start": 132,
        "stop": 133,
        "before": [],
        "after": [
          "    # r186's node reads channel zero as radians, unlike the WebGL shader.\n"
        ]
      },
      {
        "start": 143,
        "stop": 150,
        "before": [
          "        var ox = tap.x * scale / Float32(view.width)\n",
          "        var oy = tap.y * scale / Float32(view.height)\n",
          "        # `mat2(n.x, -n.y, n.x, n.y)` times the offset, column-major, on\n",
          "        # a texture coordinate that grows down.\n",
          "        var su = u + nx * ox + nx * oy\n",
          "        var sv = v + ny * ox - ny * oy\n"
        ],
        "after": [
          "        var ox = tap.x * scale\n",
          "        var oy = tap.y * scale\n",
          "        # r186 multiplies in pixel space, then divides by resolution.\n",
          "        # Its mat2 is column-major and its texture coordinate grows down;\n",
          "        # LightView's v grows up, so negate the matrix's vertical result.\n",
          "        var su = u + (nx * ox + nx * oy) / Float32(view.width)\n",
          "        var sv = v + (ny * ox - ny * oy) / Float32(view.height)\n"
        ]
      }
    ]
  },
  "render/rasterizer.mojo": {
    "before_sha256": "e8d1e85a25a771edc28ab063a8ae1b38946ca1589014c0bb6ea6126aa5a9cf25",
    "after_sha256": "31536268f6086b7b3c88ac5e677cba745564031dd4ee46fe5635f34e83b5701f",
    "before_token_sha256": "49c113f28ee16d52cbbb50c6f93b18902581fde0c15cede8634e71dfb64e16d0",
    "after_token_sha256": "ef9436992ae54e881f609f6c3bafabd7ad471d77980184c1ba9391d2211a2748",
    "edits": [
      {
        "start": 3529,
        "stop": 3530,
        "before": [],
        "after": [
          "    tones.reserve(image.width)\n"
        ]
      },
      {
        "start": 7257,
        "stop": 7258,
        "before": [
          "async def _frame_band(\n"
        ],
        "after": [
          "__async def _frame_band(\n"
        ]
      }
    ]
  },
  "tests/test_byte_extent_boundaries.mojo": {
    "before_sha256": "0622d29b6948317335a96f7eae18cc78a05d9c7f2dce456c72490a6f0cb06127",
    "after_sha256": "d6871fc9d1356886cb8aaa97c40ed7000cd86c97677344c2be566bc98b42878e",
    "before_token_sha256": "35b864d3b151524edd96a28dfe545c9b73b2e04cb0eed259455b2e98d14f0b8f",
    "after_token_sha256": "8fe2e809ce3061d1abbc190113629540898168ae7b112676c8fdda67e68144cb",
    "edits": [
      {
        "start": 77,
        "stop": 118,
        "before": [],
        "after": [
          "def test_texel_count_keeps_signed_and_zero_products() raises:\n",
          "    for width in [-3, 0, 3]:\n",
          "        for height in [-5, 0, 5]:\n",
          "            for channels in [-7, 0, 7]:\n",
          "                var count = width * height * channels\n",
          "                require_texel_count(count, width, height, channels, \"signed\")\n",
          "                with assert_raises(contains=\"signed\"):\n",
          "                    require_texel_count(\n",
          "                        count + 1, width, height, channels, \"signed\"\n",
          "                    )\n",
          "    # The final product fits even when a partial signed product does not.\n",
          "    require_texel_count(Int.MIN, Int.MIN, -1, -1, \"signed\")\n",
          "    require_texel_count(Int.MIN, -1, Int.MIN, -1, \"signed\")\n",
          "    require_texel_count(Int.MIN, -1, -1, Int.MIN, \"signed\")\n",
          "    require_texel_count(Int.MIN, Int.MIN // 2, 2, 1, \"signed\")\n",
          "    require_texel_count(Int.MAX, Int.MAX, 1, 1, \"signed\")\n",
          "    require_texel_count(-Int.MAX, Int.MAX, -1, 1, \"signed\")\n",
          "    require_texel_count(0, Int.MIN, Int.MIN, 0, \"signed\")\n",
          "    require_texel_count(0, Int.MIN, 0, Int.MIN, \"signed\")\n",
          "    require_texel_count(0, 0, Int.MIN, Int.MIN, \"signed\")\n",
          "\n",
          "\n",
          "def test_texel_count_refuses_overflow_with_the_callers_error() raises:\n",
          "    for factors in [\n",
          "        (Int.MAX, 2, 1),\n",
          "        (Int.MAX, 1, 2),\n",
          "        (Int.MIN, -1, 1),\n",
          "        (Int.MIN, 1, -1),\n",
          "        (Int.MIN, 2, 1),\n",
          "        (Int.MIN, 1, 2),\n",
          "        (Int.MIN, Int.MIN, 1),\n",
          "        (Int.MIN, Int.MIN, Int.MIN),\n",
          "        (Int.MIN // 2, -2, 1),\n",
          "        (Int.MIN // 2, -1, 2),\n",
          "    ]:\n",
          "        with assert_raises(contains=\"too many texels\"):\n",
          "            require_texel_count(\n",
          "                0, factors[0], factors[1], factors[2], \"too many texels\"\n",
          "            )\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_carla_sensors_world.mojo": {
    "before_sha256": "0e1d1728b42cb7f40a227d0d0b009256e2efa316cb7a2512a9de6b367127eb4a",
    "after_sha256": "4a7596a49fc4f397509d3e1cd06fc50a1f6ba3d699d30cef28572a593967a8ec",
    "before_token_sha256": "c5693c12310c68e8f5e7dd3c80d2cd81aebbb35bff4eebcc4d31edeaf38db358",
    "after_token_sha256": "8f192d8af21059c08ad10fadfed76787f32d917c3aa37a9e5719c6f0a2cb4297",
    "edits": [
      {
        "start": 121,
        "stop": 122,
        "before": [
          "from std.math import inf, nan\n"
        ],
        "after": [
          "from std.math import inf, isfinite, nan\n"
        ]
      },
      {
        "start": 934,
        "stop": 1019,
        "before": [],
        "after": [
          "def test_cam_snapshots_all_motion_after_a_heading_trigger() raises:\n",
          "    var world = _world()\n",
          "    var car = _car(world, 10, 1.75)\n",
          "    world.set_target_velocity(car, Vector3(2, 0, 0))\n",
          "    var service = CaService(\n",
          "        world, car, Duration(0.1), Duration(1), False, CamNoise()\n",
          "    )\n",
          "    var rng = SensorRandom(0)\n",
          "    var projection = world.map.geo_projection.copy()\n",
          "    var tick = Duration(0.05)\n",
          "    assert_true(Bool(service.trigger(world, projection, tick, rng)))\n",
          "    _near(service.last_cam_position, 10, 1.75, 0)\n",
          "    _near(service.last_cam_heading, 1, 0, 0)\n",
          "    assert_almost_equal(service.last_cam_speed, 2)\n",
          "    assert_equal(service.low_dynamics_counter, 0)\n",
          "    world.elapsed_seconds = 0.2\n",
          "    assert_false(Bool(service.trigger(world, projection, tick, rng)))\n",
          "    # A simultaneous turn, move and speed change takes the heading branch.\n",
          "    var pose = _pose(20, 1.75, 0, 30)\n",
          "    var heading = pose.rotation.forward_vector()\n",
          "    world.set_transform(car, pose)\n",
          "    world.set_target_velocity(car, heading * 4)\n",
          "    assert_true(Bool(service.trigger(world, projection, tick, rng)))\n",
          "    _near(service.last_cam_position, 20, 1.75, 0)\n",
          "    _near(service.last_cam_heading, heading.x, heading.y, heading.z)\n",
          "    assert_almost_equal(service.last_cam_speed, 4, atol=1e-6)\n",
          "    # No motion since that CAM must not trigger another minimum-gap CAM.\n",
          "    world.elapsed_seconds = 0.31\n",
          "    assert_false(Bool(service.trigger(world, projection, tick, rng)))\n",
          "\n",
          "\n",
          "def test_cam_heading_threshold_and_rounded_antiparallel_cosine() raises:\n",
          "    var world = _world()\n",
          "    var car = _car(world, 0, 0)\n",
          "    var service = CaService(\n",
          "        world, car, Duration(0.1), Duration(1), False, CamNoise()\n",
          "    )\n",
          "    assert_true(service._heading_changed(world))\n",
          "    service.last_cam_heading = Vector3(1, 0, 0)\n",
          "    world.set_transform(car, _pose(0, 0, 0, 3.9))\n",
          "    assert_false(service._heading_changed(world))\n",
          "    world.set_transform(car, _pose(0, 0, 0, 4.1))\n",
          "    assert_true(service._heading_changed(world))\n",
          "    world.set_transform(car, _pose(0, 0, 0, 180))\n",
          "    assert_true(service._heading_changed(world))\n",
          "    # At three degrees the Float32 dot and lengths round to a cosine\n",
          "    # greater than one. Negating one heading gives less than minus one,\n",
          "    # although the geometric angle is exactly pi, independently of yaw.\n",
          "    var pose = _pose(0, 0, 0, 3)\n",
          "    world.set_transform(car, pose)\n",
          "    var heading = pose.rotation.forward_vector()\n",
          "    var cosine = Float64(heading.dot(heading)) / (\n",
          "        Float64(heading.length()) * Float64(heading.length())\n",
          "    )\n",
          "    assert_true(cosine > 1)\n",
          "    service.last_cam_heading = heading\n",
          "    assert_false(service._heading_changed(world))\n",
          "    service.last_cam_heading = heading * -1\n",
          "    assert_true(service._heading_changed(world))\n",
          "    # World transforms remain mutable. A nonfinite current heading must\n",
          "    # conservatively count as changed, even with a valid previous sample.\n",
          "    service.last_cam_heading = Vector3(1, 0, 0)\n",
          "    world.set_transform(car, _pose(0, 0, 0, nan[DType.float32]()))\n",
          "    assert_true(service._heading_changed(world))\n",
          "    assert_false(isfinite(service.vehicle_heading.length()))\n",
          "\n",
          "\n",
          "def test_fixed_rate_cam_also_snapshots_motion() raises:\n",
          "    var world = _world()\n",
          "    var car = _car(world, 12, 1.75)\n",
          "    var pose = _pose(12, 1.75, 0, 90)\n",
          "    world.set_transform(car, pose)\n",
          "    var heading = pose.rotation.forward_vector()\n",
          "    world.set_target_velocity(car, heading * 3)\n",
          "    var service = CaService(\n",
          "        world, car, Duration(0.1), Duration(1), True, CamNoise()\n",
          "    )\n",
          "    var rng = SensorRandom(0)\n",
          "    var projection = world.map.geo_projection.copy()\n",
          "    assert_true(Bool(service.trigger(world, projection, Duration(0.05), rng)))\n",
          "    _near(service.last_cam_position, 12, 1.75, 0)\n",
          "    _near(service.last_cam_heading, heading.x, heading.y, heading.z)\n",
          "    assert_almost_equal(service.last_cam_speed, 3, atol=1e-6)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_denoise.mojo": {
    "before_sha256": "568ceff912f36950f00fff1711a1780f9378e4a145c1599e514d80603b38ba95",
    "after_sha256": "812ad9ddd1a35182b784a1fa04736f47b7f72335d72f0a2d861585326ec9c53a",
    "before_token_sha256": "f7a7255dc7749b3c6e27ee5ab383bbb623b17d48a940f66e0d0f7e21a629a3c7",
    "after_token_sha256": "19103a81e6833546107a4120b222b201f5f5024bacebec3aca149dbd9f6f0066",
    "edits": [
      {
        "start": 24,
        "stop": 31,
        "before": [
          "from postprocessing.denoise import DenoiseSettings, check_denoise, denoise_light\n"
        ],
        "after": [
          "from postprocessing.denoise import (\n",
          "    DenoiseSettings,\n",
          "    check_denoise,\n",
          "    denoise_light,\n",
          "    denoise_pixel,\n",
          ")\n",
          "from postprocessing.sampling import LightView\n"
        ]
      },
      {
        "start": 32,
        "stop": 33,
        "before": [],
        "after": [
          "from math.matrix4 import Matrix4\n"
        ]
      },
      {
        "start": 49,
        "stop": 50,
        "before": [],
        "after": [
          "from std.math import cos, sin\n"
        ]
      },
      {
        "start": 186,
        "stop": 235,
        "before": [],
        "after": [
          "def test_node_offsets_match_independent_pixel_space_ramps() raises:\n",
          "    # r186 DenoiseNode.js uses sin(noise[0]), not sin(2*pi*noise[0]).\n",
          "    # Its column-major mat2 has columns (sin, -cos) and (sin, cos).\n",
          "    # Apply that matrix to a pixel offset before normalizing by resolution.\n",
          "    # An affine gray ramp has an exact bilinear sample at that pixel offset.\n",
          "    for size in [(8, 8), (12, 8), (8, 12)]:\n",
          "        var width = size[0]\n",
          "        var height = size[1]\n",
          "        var pixels = List[FloatColor]()\n",
          "        for y in range(height):\n",
          "            for x in range(width):\n",
          "                var gray = Float32(x) * 0.04 + Float32(y) * 0.07\n",
          "                pixels.append(FloatColor(gray, gray, gray, 0.3))\n",
          "        var surface = List[FloatColor](\n",
          "            length=width * height, fill=FloatColor(0, 0, 1, 1)\n",
          "        )\n",
          "        var depth = List[Float32](length=width * height, fill=0)\n",
          "        var view = DepthView(\n",
          "            depth, width, height, Matrix4(), Length(0.1), Length(10)\n",
          "        )\n",
          "        var source = LightView(pixels, width, height)\n",
          "        var normals = LightView(surface, width, height)\n",
          "        var settings = DenoiseSettings()\n",
          "        settings.radius = 1\n",
          "        settings.luma_phi = 1\n",
          "        for turn in [Float32(0), Float32(0.5), Float32(1)]:\n",
          "            var noise = List[Float32](length=64 * 64, fill=0)\n",
          "            # DenoiseNode flips only its noise coordinate, so the source\n",
          "            # row numbered three reads this row in the repeating noise.\n",
          "            noise[(height - 1 - 3) * 64 + 4] = turn\n",
          "            for tap in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 2, 0)]:\n",
          "                var disk: List[Vector3] = [tap]\n",
          "                var dx = sin(Float64(turn)) * Float64(tap.x + tap.y)\n",
          "                var dy = cos(Float64(turn)) * Float64(tap.y - tap.x)\n",
          "                var center = 4.0 * 0.04 + 3.0 * 0.07\n",
          "                var neighbor = center + dx * 0.04 + dy * 0.07\n",
          "                var weight = 1.0 - abs(neighbor - center)\n",
          "                var expected = (center + neighbor * weight) / (1.0 + weight)\n",
          "                var actual = denoise_pixel(\n",
          "                    source, view, normals, noise, disk, 4, 3, settings\n",
          "                )\n",
          "                assert_almost_equal(Float64(actual.r), expected, atol=1e-6)\n",
          "                assert_almost_equal(Float64(actual.g), expected, atol=1e-6)\n",
          "                assert_almost_equal(Float64(actual.b), expected, atol=1e-6)\n",
          "                assert_almost_equal(actual.a, 0.3, atol=1e-7)\n",
          "        _ = pixels^\n",
          "        _ = surface^\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_geometry_inputs.mojo": {
    "before_sha256": "806d6910d12816bafce7a9a291a695a8c685dd5be51c15c72f5064bd426fecd6",
    "after_sha256": "b1edbdd66935ff760dded7eac58e0c33a00bba5e338bfec1dd9b896cbecd400b",
    "before_token_sha256": "41506da7bac57eeface2135b9917cf86b60d21e773d1d10dc4a9e0968e1b06d3",
    "after_token_sha256": "c2ee36a16402f5d4e509d94c829d086b2b2b3a7c959a36d28d7a1d9dd8333876",
    "edits": [
      {
        "start": 5,
        "stop": 6,
        "before": [
          "\"\"\"Finite input contracts for builders without a JSON parameter backstop.\"\"\"\n"
        ],
        "after": [
          "\"\"\"Finite input contracts checked before generated shape allocation.\"\"\"\n"
        ]
      },
      {
        "start": 7,
        "stop": 9,
        "before": [
          "from core.buffer_geometry import POSITION\n"
        ],
        "after": [
          "from core.buffer_geometry import BufferGeometry, POSITION\n",
          "from geometries.box import box\n"
        ]
      },
      {
        "start": 10,
        "stop": 20,
        "before": [
          "from geometries.circle import FULL_TURN, check_sweep\n"
        ],
        "after": [
          "from geometries.circle import FULL_TURN, check_sweep, circle, ring\n",
          "from geometries.cylinder import cylinder\n",
          "from geometries.decal import decal\n",
          "from geometries.plane import plane\n",
          "from geometries.sphere import sphere\n",
          "from geometries.surface import require_positive_radius\n",
          "from geometries.torus import torus, torus_knot\n",
          "from math.euler import Euler, XYZ\n",
          "from math.matrix4 import Matrix4\n",
          "from math.vector3 import Vector3\n"
        ]
      },
      {
        "start": 97,
        "stop": 191,
        "before": [],
        "after": [
          "def test_shapes_refuse_each_nonfinite_dimension_before_generation() raises:\n",
          "    var geometry = box(Length(1, METER), Length(1, METER), Length(1, METER))\n",
          "    for bad in [\n",
          "        nan[DType.float32](),\n",
          "        inf[DType.float32](),\n",
          "        -inf[DType.float32](),\n",
          "    ]:\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            require_positive_radius(bad, \"test\")\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = circle(Length(bad, METER))\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = sphere(Length(bad, METER))\n",
          "        for axis in range(3):\n",
          "            var values = [Float32(1), Float32(1), Float32(1)]\n",
          "            values[axis] = bad\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = box(\n",
          "                    Length(values[0], METER),\n",
          "                    Length(values[1], METER),\n",
          "                    Length(values[2], METER),\n",
          "                )\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = cylinder(\n",
          "                    Length(values[0], METER),\n",
          "                    Length(values[1], METER),\n",
          "                    Length(values[2], METER),\n",
          "                )\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = decal(\n",
          "                    geometry,\n",
          "                    Matrix4(),\n",
          "                    Vector3(0, 0, 0),\n",
          "                    Euler(\n",
          "                        Angle(0, RADIAN),\n",
          "                        Angle(0, RADIAN),\n",
          "                        Angle(0, RADIAN),\n",
          "                        XYZ,\n",
          "                    ),\n",
          "                    Length(values[0], METER),\n",
          "                    Length(values[1], METER),\n",
          "                    Length(values[2], METER),\n",
          "                )\n",
          "        for axis in range(2):\n",
          "            var values = [Float32(1), Float32(2)]\n",
          "            values[axis] = bad\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = plane(Length(values[0], METER), Length(values[1], METER))\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = ring(Length(values[0], METER), Length(values[1], METER))\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = torus(Length(values[0], METER), Length(values[1], METER))\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = torus_knot(\n",
          "                    Length(values[0], METER), Length(values[1], METER)\n",
          "                )\n",
          "\n",
          "\n",
          "def test_finite_shared_radius_validation_keeps_zero_and_negative_errors() raises:\n",
          "    require_positive_radius(Float32(1), \"test\")\n",
          "    for value in [Float32(0), Float32(-1)]:\n",
          "        with assert_raises(contains=\"positive\"):\n",
          "            require_positive_radius(value, \"test\")\n",
          "\n",
          "\n",
          "def test_nonfinite_dimensions_fail_before_topology_or_source_reads() raises:\n",
          "    var bad = Length(inf[DType.float32](), METER)\n",
          "    var one = Length(1, METER)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = box(bad, one, one, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = plane(bad, one, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = circle(bad, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = ring(one, bad, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = cylinder(one, bad, one, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = torus(one, bad, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = torus_knot(one, bad, 0)\n",
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = decal(\n",
          "            BufferGeometry(),\n",
          "            Matrix4(),\n",
          "            Vector3(0, 0, 0),\n",
          "            Euler(Angle(0, RADIAN), Angle(0, RADIAN), Angle(0, RADIAN), XYZ),\n",
          "            one,\n",
          "            one,\n",
          "            bad,\n",
          "        )\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_matrix4.mojo": {
    "before_sha256": "879a370a7aecda5afc8724d03cc3b6cbb4a3b374208ac2aa74de40c1f490448c",
    "after_sha256": "a40cb17b07712d350963076d816254a0640c9549b6f796a1b235cbf1837aa8d9",
    "before_token_sha256": "6d8f2a1cfbef6f0ae37c937fdcc2064ae08522f103f3e2c56cb17cf5c4f6676e",
    "after_token_sha256": "1c85bdec2aae231509783143de025bf4685d650dac5e326ad93fb2c9795def93",
    "edits": [
      {
        "start": 204,
        "stop": 259,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_premultiplication_matches_an_independent_dense_product() raises:\n",
          "    var a = Matrix4()\n",
          "    a.set(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)\n",
          "    var b = Matrix4()\n",
          "    b.set(2, 0, 1, 3, -1, 4, 2, 0, 5, 1, 0, -2, 0, 3, -1, 1)\n",
          "    var before = a\n",
          "    var other = b\n",
          "    a.premultiply(b)\n",
          "    # b*a, independently worked in row-major order with integer sums.\n",
          "    var expected = Matrix4()\n",
          "    expected.set(\n",
          "        50,\n",
          "        56,\n",
          "        62,\n",
          "        68,\n",
          "        37,\n",
          "        42,\n",
          "        47,\n",
          "        52,\n",
          "        -16,\n",
          "        -12,\n",
          "        -8,\n",
          "        -4,\n",
          "        19,\n",
          "        22,\n",
          "        25,\n",
          "        28,\n",
          "    )\n",
          "    assert_same(a, expected)\n",
          "    assert_same(b, other)\n",
          "    # Direct self-aliasing is refused by Mojo; an explicit copy squares it.\n",
          "    var squared = before\n",
          "    squared.premultiply(Matrix4(copy=squared))\n",
          "    var expected_square = Matrix4()\n",
          "    expected_square.set(\n",
          "        90,\n",
          "        100,\n",
          "        110,\n",
          "        120,\n",
          "        202,\n",
          "        228,\n",
          "        254,\n",
          "        280,\n",
          "        314,\n",
          "        356,\n",
          "        398,\n",
          "        440,\n",
          "        426,\n",
          "        484,\n",
          "        542,\n",
          "        600,\n",
          "    )\n",
          "    assert_same(squared, expected_square)\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_pr760_arithmetic_stage.py": {
    "before_sha256": "ac51eb5dd58c8e3768f2405108203351194d72d63f2b53f4e30d5b2d4d8c26ab",
    "after_sha256": "e1511129ab59d3d6a982b0de436f6b42252a20a539e978e628e4a7bc50fe7ae7",
    "before_token_sha256": "73561ca033b0eef88bf6ce996cfe062f8b2b34bc2652feda12dc5aef15de9e68",
    "after_token_sha256": "8780a11ccdebf9303033102ac5fcb5aac586783ee459f5504e449d52f7524691",
    "edits": [
      {
        "start": 12,
        "stop": 13,
        "before": [],
        "after": [
          "import pr780_source_successor as successor\n"
        ]
      },
      {
        "start": 22,
        "stop": 24,
        "before": [
          "        cls.inputs = {path: (ROOT/path).read_bytes() for path in stage.INPUT_SHA256}\n"
        ],
        "after": [
          "        cls.inputs = {path: successor.predecessor_bytes(path, (ROOT/path).read_bytes())\n",
          "                      for path in stage.INPUT_SHA256}\n"
        ]
      },
      {
        "start": 130,
        "stop": 131,
        "before": [
          "            current = (ROOT/path).read_bytes().decode('utf-8')\n"
        ],
        "after": [
          "            current = successor.predecessor_bytes(path, (ROOT/path).read_bytes()).decode('utf-8')\n"
        ]
      },
      {
        "start": 156,
        "stop": 158,
        "before": [
          "        inputs = {path: (ROOT/path).read_bytes() for path in stage.REGISTRY_INPUT_SHA256}\n"
        ],
        "after": [
          "        inputs = {path: successor.predecessor_bytes(path, (ROOT/path).read_bytes())\n",
          "                  for path in stage.REGISTRY_INPUT_SHA256}\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_pr760_physical_image.py": {
    "before_sha256": "6df971f2bf09c710a4e6ababc6adeea8995fd2e86c3e6866e548d5b193ae3669",
    "after_sha256": "bb905630d2fe05f7f7a3153536f5fcbb406793b22f5d7300600647ac80308868",
    "before_token_sha256": "74ca01c4b41870f5b83e81d83ac19063908258e12e2c58026092a958f05e45ec",
    "after_token_sha256": "48e0b075a1764f210c5d662a4ad87a1b90eaf839a1dcc2dc6a7b7da149c8b8a5",
    "edits": [
      {
        "start": 122,
        "stop": 123,
        "before": [],
        "after": [
          "            raw = owner.pr780_successor.predecessor_bytes(path, raw)\n"
        ]
      },
      {
        "start": 241,
        "stop": 243,
        "before": [
          "            previous = (owner.pr776_predecessor_bytes(path, raw) if path in (\n"
        ],
        "after": [
          "            previous = owner.pr780_successor.predecessor_bytes(path, raw)\n",
          "            previous = (owner.pr776_predecessor_bytes(path, previous) if path in (\n"
        ]
      },
      {
        "start": 244,
        "stop": 245,
        "before": [
          "                        'tools/carla_lane_oracle/test_typed_boundary_contracts.py') else raw)\n"
        ],
        "after": [
          "                        'tools/carla_lane_oracle/test_typed_boundary_contracts.py') else previous)\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_pr776_input_successors.py": {
    "before_sha256": "148a021e1d8173122f231f4e6839d4dfd7bb2bb14d76d70e3725ff310620d2aa",
    "after_sha256": "0e69f25b38f18cef70ba7751aa45b7e434593a0a900fa9666029806db6e518e4",
    "before_token_sha256": "a5fbfe1798ba77ac6154f228731a26c54c73174a159328422e2ae95b793c26a5",
    "after_token_sha256": "10847c0ee458a0c5d32ab01194a460436127c7daff25279d6ddaf8af85586875",
    "edits": [
      {
        "start": 61,
        "stop": 62,
        "before": [],
        "after": [
          "        raw = owner.pr780_successor.predecessor_bytes(path, raw)\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_typed_boundary_contracts.py": {
    "before_sha256": "8dee4d9c4bf42214fb2f10fbdcf71a4ba04398095d8c62a16233ad6fc038fce7",
    "after_sha256": "5a8d3d51eae53713e6133f4640d101176ac5d228f7e5085e9bebeb6bfa6d9f5f",
    "before_token_sha256": "f71efcac558cf883d01cc2cf792879074f5275e36fd3cd8c2e2d43b2de380db3",
    "after_token_sha256": "c45993ef4292b45926aed436aab5964e3f70135bade264194e95bb2618a43b2d",
    "edits": [
      {
        "start": 43,
        "stop": 45,
        "before": [
          "            text = (ROOT/name).read_text()\n",
          "            return typed.historical_source(name, text)\n"
        ],
        "after": [
          "            raw = audit.pr780_successor.predecessor_bytes(name, (ROOT/name).read_bytes())\n",
          "            return typed.historical_source(name, raw.decode('utf-8'))\n"
        ]
      },
      {
        "start": 444,
        "stop": 445,
        "before": [],
        "after": [
          "                raw = audit.pr780_successor.predecessor_bytes(path, raw)\n"
        ]
      }
    ]
  },
  "core/deform.mojo": {
    "before_sha256": "6bc25c6adf469a5bc9ea37ae09a4822e9210a03d56c977a1f0c533ed02b9bf58",
    "after_sha256": "62edb70d0bb9fa401f0776b7bc8fc5bcb2e0622b41f80d6c6e5cd5c847af62e8",
    "before_token_sha256": "7d94308b0c36222350314a9a811ace9afc4f3e97762811908a2d80189bc5eb18",
    "after_token_sha256": "1a68883112123b8313baad5b2fc075a6849b0e025dc500325e3d4b7668b51a07",
    "edits": [
      {
        "start": 359,
        "stop": 360,
        "before": [
          "    return SkinPose(skinned.skeleton.pose(placed), skinned.bind_matrix, undo^)\n"
        ],
        "after": [
          "    return SkinPose(skinned.skeleton.pose(placed), skinned.bind_matrix, undo)\n"
        ]
      }
    ]
  },
  "extensions/carla/assets.mojo": {
    "before_sha256": "0bb273644a6d6cffaad986236e8aaafe9355549b37a10289cd9b14555f4e1acc",
    "after_sha256": "b051a911885031a06eee4a609ce030ea8629f0ab09e0f12308d89c009e8bde8d",
    "before_token_sha256": "70261521b837b27b7f0d1068a4422331e927d64089962d57ee20f53c3781cd64",
    "after_token_sha256": "dbc7c2a25e2d68fa3456e410bf66bf921f4dd87779e342df1d53a49f755bdfd8",
    "edits": [
      {
        "start": 1488,
        "stop": 1489,
        "before": [
          "        scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "        scene.add_mesh(mesh)\n"
        ]
      }
    ]
  },
  "extensions/carla/map.mojo": {
    "before_sha256": "b3862a55a54927b2a1e50186af82f64bdf145adbef5cef9f31ab19d9585749df",
    "after_sha256": "288d0e5d3a5bc2e5a6b9542868de6566dc6cb4de6eae39192c0289d76a8c99fa",
    "before_token_sha256": "0263ba183b30437b826ada3ceedb3d2c5a3664dc95245743a17209f568607b79",
    "after_token_sha256": "6531e0d35cf724f88b0c17c310996830b079056ff173b146504de7850b92dfe1",
    "edits": [
      {
        "start": 189,
        "stop": 190,
        "before": [
          "from std.hashlib import Hasher\n"
        ],
        "after": [
          "from std.hash import Hasher\n"
        ]
      }
    ]
  },
  "extensions/carla/map_builder.mojo": {
    "before_sha256": "f5e28830bb017e42b61d3a40f7e96711ad7aa893d121472f311e36b9a9572d0c",
    "after_sha256": "6c705c9a40e045c30f70dfbc160e8b8fc706396ccbc0fc0e21e5ca92ab5b6078",
    "before_token_sha256": "4d153beee1e83966264af944bf260597fbf727785eb193d3710a3b5a0c33a977",
    "after_token_sha256": "e44cd56000fa29e28c8085c1d5b6dfc810c6a775b80f04db9d7d7f6afe0e30e5",
    "edits": [
      {
        "start": 1384,
        "stop": 1385,
        "before": [
          "            RoadInfoGeometry._from_si(s, geometry^)\n"
        ],
        "after": [
          "            RoadInfoGeometry._from_si(s, geometry)\n"
        ]
      }
    ]
  },
  "extensions/carla/model_cache.mojo": {
    "before_sha256": "a5832785f758cd6fe99f32cfa04b90399ebfcd4c9ffdf1e286f79c613cb1cd91",
    "after_sha256": "6c95fe4a1e5218f26dac0c9889e2246d53ec620cebb1230166a184bbe8af93a9",
    "before_token_sha256": "b584c4522bf996506402278ab292de94c65d24a7176f37aeed5ab91b848b2a16",
    "after_token_sha256": "209c439bf0c9449cc6fc47784fe517076de04f80cf52332695e7b85a4afbc864",
    "edits": [
      {
        "start": 246,
        "stop": 247,
        "before": [
          "            scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "            scene.add_mesh(mesh)\n"
        ]
      }
    ]
  },
  "extensions/carla/sensor.mojo": {
    "before_sha256": "e20a4f8341d36615682dd1820a7a1587ebf32aeabac402b36d0646f277239f75",
    "after_sha256": "3dab708ddf17d214821eee9aaf40fce3da8583f602c86bd058da5d3f016ea12b",
    "before_token_sha256": "c58baff8992f6eb88a675fa837c0c962589ec157a41e6e9fbf78b18438fb8119",
    "after_token_sha256": "c58baff8992f6eb88a675fa837c0c962589ec157a41e6e9fbf78b18438fb8119",
    "edits": [
      {
        "start": 69,
        "stop": 70,
        "before": [],
        "after": [
          "# fmt: off\n"
        ]
      },
      {
        "start": 101,
        "stop": 103,
        "before": [
          "]  # fmt: skip\n"
        ],
        "after": [
          "]\n",
          "# fmt: on\n"
        ]
      }
    ]
  },
  "extensions/carla/sensor_manager.mojo": {
    "before_sha256": "d87069be62eb405cbc976d0cba12c5d0c5e5db3d520111b788b2e9c9ca18029e",
    "after_sha256": "c0b21899dabe7e21c7d8744548845c9ca31a12c2e1598eac37ba3077565a1567",
    "before_token_sha256": "fac0a508fbc6540191d09b3a91e449544ebd6557399f2696bc6bf81cbddd86b4",
    "after_token_sha256": "fac0a508fbc6540191d09b3a91e449544ebd6557399f2696bc6bf81cbddd86b4",
    "edits": [
      {
        "start": 235,
        "stop": 236,
        "before": [],
        "after": [
          "# fmt: off\n"
        ]
      },
      {
        "start": 238,
        "stop": 240,
        "before": [
          "]  # fmt: skip\n"
        ],
        "after": [
          "]\n",
          "# fmt: on\n"
        ]
      }
    ]
  },
  "extensions/carla/speed_limits.mojo": {
    "before_sha256": "1e95ebc085e03a44e4daaef20a94b724dedc4240a2099227e82be54d32b045f6",
    "after_sha256": "2d9d5401b3dabf53c1c19f0a8098009275e19edb978f5ae369596fe7ac6557a0",
    "before_token_sha256": "5ba74b5993221135eba428267daafe27011934dbe8fecf9928edd41670572026",
    "after_token_sha256": "62d358aaefa3590d00cd56121ff2d132a87cbfb05ce8786d22bad6bc9eea850a",
    "edits": [
      {
        "start": 145,
        "stop": 146,
        "before": [
          "    var value: Float64\n",
          "    try:\n",
          "        value = Float64(number)\n",
          "    except:\n",
          "        raise Error(\"OpenDRIVE speed needs a numeric max value\")\n"
        ],
        "after": [
          "    var value = Float64(number)\n"
        ]
      }
    ]
  },
  "extensions/carla/town.mojo": {
    "before_sha256": "f1917d2fdbe678e0f6623d0bd44f80f54b4e0a9f9c4bb9c486c312ae6cf50ee5",
    "after_sha256": "dbf66b4953eda09d150e9cec8d7b74b489c5f6bdd38b77049eaddfcda49d3eb8",
    "before_token_sha256": "63f9e55ab1cf9ff7e2722a6a7e1df4a1bb5475bce1bab89f8a58fd1a7f218e5a",
    "after_token_sha256": "0ba1fbf1bdf04f174c844c0335c666b49808fc2873a19b5a62fbcec10b029a5b",
    "edits": [
      {
        "start": 1397,
        "stop": 1398,
        "before": [
          "        scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "        scene.add_mesh(mesh)\n"
        ]
      }
    ]
  },
  "extensions/carla/world.mojo": {
    "before_sha256": "f8d8f6583eef3ea409f0c057263d9c55337c8d647806400b711afa398b88a4c1",
    "after_sha256": "e1c17354267d5ba6f49378cb8c04bf3e60ad61b2e07c50044d3eceee2261a16e",
    "before_token_sha256": "1645044b0a0ccc1d167d981428d28b4739472bc11930348c5c8dc34533a142e4",
    "after_token_sha256": "056d05b7306a1b03390df568cde37ca711653daaf812294967b9b9be96def22c",
    "edits": [
      {
        "start": 162,
        "stop": 163,
        "before": [
          "from std.hashlib import Hasher\n"
        ],
        "after": [
          "from std.hash import Hasher\n"
        ]
      }
    ]
  },
  "extensions/humanoid/skeleton/head/hair/shading.mojo": {
    "before_sha256": "5cd145858e9175d306ce6b21bc4d8e6e674e6aecfd87dc7e5be4fc102b6caa7e",
    "after_sha256": "ba53a4ffb93734551c77b2e844de8448a0d1a7d4a5d1dbf248374125215307b2",
    "before_token_sha256": "0943825a89ef343fdd80c3fb7cb1ede94d9f61d828c9672da52903aaeba252ab",
    "after_token_sha256": "b11d9263c6e4a7c07a7ed753b090508034b922bbe0e984b0ad6a650b10a4c63b",
    "edits": [
      {
        "start": 284,
        "stop": 285,
        "before": [
          "async def _shade_task(\n"
        ],
        "after": [
          "__async def _shade_task(\n"
        ]
      }
    ]
  },
  "extensions/humanoid/skeleton/head/hair/strands.mojo": {
    "before_sha256": "058c0e6fbfce95ee97c79247622185de968c8de5e0ad23240d667da13776404f",
    "after_sha256": "81d104e6b65fe1539bf9c244330ae53b6d337ad081529cb0c5f7bcde27887db5",
    "before_token_sha256": "d7195018a457c231f60d8ccaa36b924288d567c691efd62508554265569a0b4a",
    "after_token_sha256": "4ccdb2217bcdd1e76b39d66dca7643a93ba82487dbb510784686af504b69062d",
    "edits": [
      {
        "start": 252,
        "stop": 253,
        "before": [
          "async def _depth_task(\n"
        ],
        "after": [
          "__async def _depth_task(\n"
        ]
      }
    ]
  },
  "geometries/attribute_utils.mojo": {
    "before_sha256": "0a87276b9264a028a3220a667e39f8e96ff6fde7e41ed2c180e0aed7484ccda6",
    "after_sha256": "91d45ff588571ab0bbda20331d1f60a0b55e124985a76f8cad97d682bdca523e",
    "before_token_sha256": "51190bc7d2e5620e99b873064d00bc4927247686f5726aa262aea1a48268f36b",
    "after_token_sha256": "fc2bdb93fb28ac7beff5a2a2350ef881efc9d61b8ac4100f1186222cbd433bb1",
    "edits": [
      {
        "start": 139,
        "stop": 140,
        "before": [
          "            stored^, size, first.component_type(), first.is_normalized()\n"
        ],
        "after": [
          "            stored, size, first.component_type(), first.is_normalized()\n"
        ]
      }
    ]
  },
  "lights/shadow.mojo": {
    "before_sha256": "e57aabcefe61cebaa8e57ae129f0cae3873215b7b1c0d2171c972d78d4015b81",
    "after_sha256": "649970324f8a80cd0ba959f3278d635b12b9886a5ecb09290620b5b61b3c1d20",
    "before_token_sha256": "c91ae04a499fb4362157f5aa3a48a8b0cc599a85c8504efff633ac7645f3a3d9",
    "after_token_sha256": "c91ae04a499fb4362157f5aa3a48a8b0cc599a85c8504efff633ac7645f3a3d9",
    "edits": [
      {
        "start": 191,
        "stop": 192,
        "before": [],
        "after": [
          "# fmt: off\n"
        ]
      },
      {
        "start": 199,
        "stop": 202,
        "before": [
          ")  # fmt: skip\n"
        ],
        "after": [
          ")\n",
          "# fmt: on\n",
          "# fmt: off\n"
        ]
      },
      {
        "start": 209,
        "stop": 211,
        "before": [
          ")  # fmt: skip\n"
        ],
        "after": [
          ")\n",
          "# fmt: on\n"
        ]
      }
    ]
  },
  "loaders/draco_mesh.mojo": {
    "before_sha256": "1ceb206440f4f2d8ba78b46c5ef77e3d6a85c08ca00a650cac2753c668ce6a70",
    "after_sha256": "ab2f61a4b78469708cb1e5a9aeb33daaea4bc6fae5fbb3d20ffa696a7a97eaee",
    "before_token_sha256": "d9b801dec66befa1a014921a29d5d0cc3e60b37b3e268f1bcc5af91742ffb659",
    "after_token_sha256": "e712b8c1f5a12b4c40de478be4c4b241279b7c566c839b2ca3d9d6e68b479e27",
    "edits": [
      {
        "start": 820,
        "stop": 821,
        "before": [
          "        return self._close(active^, faces, invalid^)\n"
        ],
        "after": [
          "        return self._close(active^, faces, invalid)\n"
        ]
      }
    ]
  },
  "loaders/image_batch.mojo": {
    "before_sha256": "78bb5a01db84c9ee4642b36ad220ecaf7061bc26e4cfd4d711d743ab08189e51",
    "after_sha256": "b8822e6e54c889dace6645c6b38d4847109ef45a5dd9bf7a7b0c332e2a229086",
    "before_token_sha256": "3ea40a23d91c104dd724abf09bb81b41c762820923a2904ea7e70eab47967570",
    "after_token_sha256": "6bbfa7efc0d0957d753d1e4eeb5893403bbb6c81df5e1862b4ebf1d35745de0f",
    "edits": [
      {
        "start": 97,
        "stop": 98,
        "before": [
          "async def _decode_worker[\n"
        ],
        "after": [
          "__async def _decode_worker[\n"
        ]
      }
    ]
  },
  "loaders/js_number.mojo": {
    "before_sha256": "9d7d0dc7f0a7c526881e469ed2b7e918fbcfb8b27258641631515b6893c5905e",
    "after_sha256": "a7f8cd0bdaf91756b5583de24cf27e7d8ee86c7cc91cb68ab2da2dec3bd9b19d",
    "before_token_sha256": "1319e8b960d6c0967c7a90b5a8d56ad36a21f789b899ba1743d8690667e0b204",
    "after_token_sha256": "27d8ca31d4fadc1fe9a25cb151c1c57008298bc2c173bcb895ae3a674973d83d",
    "edits": [
      {
        "start": 16,
        "stop": 17,
        "before": [
          "JavaScript also skips the Unicode spaces. A number with more digits than\n",
          "Mojo's parser reads gives NaN; JavaScript rounds it. A `0x`, `0o` or `0b`\n"
        ],
        "after": [
          "JavaScript also skips the Unicode spaces. A `0x`, `0o` or `0b`\n"
        ]
      },
      {
        "start": 18,
        "stop": 20,
        "before": [
          "differently.\n"
        ],
        "after": [
          "differently. Mojo 1.2 reads any number of decimal digits and rounds to\n",
          "the nearest `Float64`, as JavaScript does.\n"
        ]
      },
      {
        "start": 50,
        "stop": 66,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def _decimal(text: String) -> Float64:\n",
          "    \"\"\"Return the number that a decimal text writes.\n",
          "\n",
          "    Args:\n",
          "        text: A sign, digits, a point and an exponent. Every caller\n",
          "            checks the shape first.\n",
          "\n",
          "    Returns:\n",
          "        The nearest `Float64`, or NaN when Mojo cannot read the text.\n",
          "    \"\"\"\n",
          "    try:\n",
          "        return Float64(text)\n",
          "    except:\n",
          "        return nan[DType.float64]()\n"
        ]
      },
      {
        "start": 117,
        "stop": 118,
        "before": [
          "    try:\n",
          "        return Float64(String(text[byte=start:end]))\n",
          "    except:\n",
          "        return nan[DType.float64]()\n"
        ],
        "after": [
          "    return _decimal(String(text[byte=start:end]))\n"
        ]
      },
      {
        "start": 143,
        "stop": 144,
        "before": [
          "    try:\n",
          "        return Float64(String(text[byte=start:i]))\n",
          "    except:\n",
          "        return nan[DType.float64]()\n"
        ],
        "after": [
          "    return _decimal(String(text[byte=start:i]))\n"
        ]
      }
    ]
  },
  "math/convex_hull.mojo": {
    "before_sha256": "a31ec9ca314e401724838b0eb2b488bf033d03dc0a5403a77a4f0ac905034c9c",
    "after_sha256": "3bca4e4ad3bd88bd02d4ac0e1b29d6942c20f148674190d71f22eb8ec60d486b",
    "before_token_sha256": "6ae8a27a752b6bd838f771441871c2e094fb375589cb16f6ad6678d1669c1443",
    "after_token_sha256": "40d303755f5d6a0ee5d3de2f7496b887b4bea226d5cdf25108b8cdf637d70325",
    "edits": [
      {
        "start": 112,
        "stop": 114,
        "before": [
          "        # Mojo 1.1 frexp does not normalize a subnormal significand.\n"
        ],
        "after": [
          "        # Mojo 1.1 frexp did not normalize a subnormal significand, and\n",
          "        # Mojo 1.2 does. The scaled form is exact on both.\n"
        ]
      },
      {
        "start": 121,
        "stop": 122,
        "before": [
          "    Mojo 1.1 ldexp forms a power of two before multiplication. Exponents\n"
        ],
        "after": [
          "    Mojo 1.1 and 1.2 ldexp form a power of two before multiplication. Exponents\n"
        ]
      }
    ]
  },
  "render/target.mojo": {
    "before_sha256": "cf004fbceafd55ffe634492cddcbb0893a9a0602ccc5da46b374df9a433fefb8",
    "after_sha256": "e33a4bb9c4a90c5aaa3706f583bafa35888a4f37d7322b8077a169036eacedce",
    "before_token_sha256": "52b06ddd33f9ee0e576bb8098db68c8007952eac2ba1da980605ab39739888f6",
    "after_token_sha256": "007a55be8b177bf52c80c6b6577241a31899e2924402533dd13e9c08df501aec",
    "edits": [
      {
        "start": 631,
        "stop": 632,
        "before": [
          "async def _encode_band(\n"
        ],
        "after": [
          "__async def _encode_band(\n"
        ]
      }
    ]
  },
  "render/tasks.mojo": {
    "before_sha256": "efa65ccd751c3430f1fa875382748f6040733f802be4719b92ff239b510804d4",
    "after_sha256": "9b80dcaceec958190ade19bff6d106617c8c4c99e80d37eb0205609741ca2934",
    "before_token_sha256": "d1a53c96ae8996bdbc0fe217437aa5ba1b878ed5a0abc3bfc62654cc76ddb973",
    "after_token_sha256": "65941b3b16a82e34a52fe3f548a6e201ea03cd0c4af01f3151a81e62f06f5800",
    "edits": [
      {
        "start": 3,
        "stop": 4,
        "before": [
          "\"\"\"The single adapter for the pinned Mojo 1.1 task runtime.\n"
        ],
        "after": [
          "\"\"\"The single adapter for the pinned Mojo 1.2 task runtime.\n"
        ]
      }
    ]
  },
  "renderers/renderer.mojo": {
    "before_sha256": "5cc066092d9b0302c60a6676459efc855e220dc319d1f88b5eb84df768f489f9",
    "after_sha256": "990d94c815315c910b12c1b126c076183fc35cdeb9f64a26d1f7e574f424bccd",
    "before_token_sha256": "cda4f5d902566d18ae704ba4bc976141e8324c84d6d2900667739b1e28526ed8",
    "after_token_sha256": "fa2a55e75f6201dab9fd8fd08e36d0e7f40400556a4881f78e2ee64a2bece4d7",
    "edits": [
      {
        "start": 2812,
        "stop": 2813,
        "before": [
          "            corners.append(corner^)\n"
        ],
        "after": [
          "            corners.append(corner)\n"
        ]
      },
      {
        "start": 4498,
        "stop": 4499,
        "before": [
          "async def _wide_task(\n"
        ],
        "after": [
          "__async def _wide_task(\n"
        ]
      },
      {
        "start": 4888,
        "stop": 4889,
        "before": [
          "async def _backdrop_band(\n"
        ],
        "after": [
          "__async def _backdrop_band(\n"
        ]
      },
      {
        "start": 5464,
        "stop": 5465,
        "before": [
          "async def _emit_pieces(\n"
        ],
        "after": [
          "__async def _emit_pieces(\n"
        ]
      },
      {
        "start": 5506,
        "stop": 5507,
        "before": [
          "async def _place_corners(\n"
        ],
        "after": [
          "__async def _place_corners(\n"
        ]
      },
      {
        "start": 5556,
        "stop": 5557,
        "before": [
          "async def _place_renamed(\n"
        ],
        "after": [
          "__async def _place_renamed(\n"
        ]
      }
    ]
  },
  "tests/_sample_dispatch_controls.mojo": {
    "before_sha256": "641e16767420127ced138a93e8c28178c2e904c4b23279e1a6e72b7e784b3443",
    "after_sha256": "776a1bf194339fe4845c240a4098a45aee0efd3a9061538f54149cf908ab0be6",
    "before_token_sha256": "ba605ff2d7d873d16c1f02e3bff7f842f9fd9a256c8183c876c9c51ea8d70030",
    "after_token_sha256": "16d506ce0ce8d692e52582b67bfd2cfde82ced84103aa9fa7bd6d567c11017cf",
    "edits": [
      {
        "start": 25,
        "stop": 26,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(origin, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(origin, geometry)\n"
        ]
      }
    ]
  },
  "tests/_spiral_domain_controls.mojo": {
    "before_sha256": "2dd9eff35cda94bbe5ebd2d805861edc0899b6240d4f7e65a4e65b8a241727f2",
    "after_sha256": "7e67a5e660d7d02529a1923d3023ff2053b0a17a2b913a30ddb1bfe4a638a49f",
    "before_token_sha256": "bd93e5c49ae462262fe2acea93660363a8d52c93eb4e7105d16a33acb279b1ae",
    "after_token_sha256": "54bcc15bcb49d63c9f2eb3882c5a20df9f5acae3ae44047e7b93b5e867cf5017",
    "edits": [
      {
        "start": 93,
        "stop": 94,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(record_s, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(record_s, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_animation_paths.mojo": {
    "before_sha256": "3b7cdb48ef70c6216c7bf530b9d1f9e6385b64494bca3d743b823d744dfd8795",
    "after_sha256": "91f4c820cce066ec7bfd19bd8ec14b2682daf7edb1a5cd32f9b3dc29bff579bd",
    "before_token_sha256": "f0bda3f69eb31417a966a5abe253f5f4fb60548d81c1ae9286b781e947c1f4a3",
    "after_token_sha256": "7bd3c353518dbe9c2b2ec016d2158c3437829379d467bfaf0d2f7830db583732",
    "edits": [
      {
        "start": 281,
        "stop": 282,
        "before": [
          "    var worn = assets.materials.add(paint^)\n"
        ],
        "after": [
          "    var worn = assets.materials.add(paint)\n"
        ]
      },
      {
        "start": 354,
        "stop": 355,
        "before": [
          "    var missing = assets.materials.add(lost^)\n"
        ],
        "after": [
          "    var missing = assets.materials.add(lost)\n"
        ]
      },
      {
        "start": 357,
        "stop": 358,
        "before": [
          "    var negative = assets.materials.add(below^)\n"
        ],
        "after": [
          "    var negative = assets.materials.add(below)\n"
        ]
      }
    ]
  },
  "tests/test_audit_boundaries.mojo": {
    "before_sha256": "540246841a33064e40208b999a5f54314d9c908b2ba7caa40eaa4c4d7ab9c6eb",
    "after_sha256": "0ee4453906bf5c84700534d145a75dc33846d0c68c9e54ef7f79d70cd933e593",
    "before_token_sha256": "c012ef85d66efbaeffcddfcfef77973938e72b326cf4a359b270ef14ad88daa1",
    "after_token_sha256": "9988f33a88af96c752447e2ca84d9ffa48cb5e1ce415267e78d4a9fca54a3d4c",
    "edits": [
      {
        "start": 84,
        "stop": 85,
        "before": [
          "            scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "            scene.add_mesh(mesh)\n"
        ]
      }
    ]
  },
  "tests/test_audit_regressions.mojo": {
    "before_sha256": "5c463c2677de226aa91e2696a3ef3e9b45279d664e7b4f4e2b7570cbdb92167e",
    "after_sha256": "37a6fd0e0c6e4408739edb7d2022482715b34311d32d17afd75f01e0abc20514",
    "before_token_sha256": "f2b87ba3b7ef38e488fc1721db46185d4aa0b3fcc771f5d42d6f8e350ac8c391",
    "after_token_sha256": "5431c6543b3e119226da8479480457cb72ecb0e1e252e988a28cbecf09b21137",
    "edits": [
      {
        "start": 515,
        "stop": 516,
        "before": [
          "        scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "        scene.add_mesh(mesh)\n"
        ]
      },
      {
        "start": 541,
        "stop": 542,
        "before": [
          "            scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "            scene.add_mesh(mesh)\n"
        ]
      }
    ]
  },
  "tests/test_audit_slim.mojo": {
    "before_sha256": "aeda0f90f34ac320e21b57e189ed1fea563416261af1fad97b0909f07b5de803",
    "after_sha256": "31a8eb0918a39dac92a7c1651bafa8e14278050c211de046d5a26b04942588c4",
    "before_token_sha256": "d0996296b752640a5db98d2d1177dc997c11db9b328af030917a2b91395d4d7f",
    "after_token_sha256": "de38f68e6c621122f2727672484374e3e698bae89feea4e96e0f8be110602d5d",
    "edits": [
      {
        "start": 99,
        "stop": 100,
        "before": [
          "    var material = assets.materials.add(surface^)\n"
        ],
        "after": [
          "    var material = assets.materials.add(surface)\n"
        ]
      }
    ]
  },
  "tests/test_carla_axis_direct_road.mojo": {
    "before_sha256": "b832cb9cde8fe3dfa2348e33301d23ac4ebba4e3eced8c4da021fce40397542b",
    "after_sha256": "c40f59ca6e751650e3dc95e954b0df46ad073935cc217aecf8b633aaeb1cf326",
    "before_token_sha256": "f0337ae27a9d6d5c95daf64e0a4784655a77d9daf7e71ff5de3498cd641c6b9b",
    "after_token_sha256": "01f3633e9569f34a22833d6ee0347221965119c1b77de467ff651cdc430d9d3d",
    "edits": [
      {
        "start": 47,
        "stop": 48,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(base, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(base, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_centered_bounds.mojo": {
    "before_sha256": "14951a470cc345168ffda3a1ff965953b5e9afe00870e8f381ba0cc1fe358344",
    "after_sha256": "26a5ab35d7a251369f3708b821af5061a817f66d40b8b63170a466c65ceefbdb",
    "before_token_sha256": "f0917d9e549c6df4c75d66a850c7e8ec0d020819de0c4b3d792780349fe81df3",
    "after_token_sha256": "d2cdd1386da90a4a3326c2584b887e7b5cabc674cece8f86b9b537e7c4009297",
    "edits": [
      {
        "start": 64,
        "stop": 65,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_chord_endpoint_refusals.mojo": {
    "before_sha256": "304cf89c7a8c9cec3589f5f6bf2c706642b318a3f49344948aba970701209627",
    "after_sha256": "ae04b78bd28297e773b463fa74841de3d3e78c29ad163d214cd551e58b8a2b51",
    "before_token_sha256": "8b68cc2a55ce70e59e5438a22c848c05fbddf23adff4c7d0596e21dd73465276",
    "after_token_sha256": "e659bbf1a016219dc013460267f1e08f145c6f4bfb294fbade319fd82fec2f57",
    "edits": [
      {
        "start": 62,
        "stop": 64,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, first^))\n",
          "    road.info.geometries.append(RoadInfoGeometry._from_si(2.0, last^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, first))\n",
          "    road.info.geometries.append(RoadInfoGeometry._from_si(2.0, last))\n"
        ]
      }
    ]
  },
  "tests/test_carla_conditioned_polynomial.mojo": {
    "before_sha256": "bafda6b76c3c4d56f75959be7bf238fe3992b48e449a481d0e34d03dcfa30d8f",
    "after_sha256": "2e25c8610596db4f7e9a1f6a951545f10d5d2d2ca2434163f78c9bc23c427f3d",
    "before_token_sha256": "5d31a22c749c82766f55b7bc2e62761418422f3074b3b258f22c6141e88f98cb",
    "after_token_sha256": "01ef2482862f90add2f4b2a3033c6b1e2fa99d398ca926e718f1f1fd6fca2b20",
    "edits": [
      {
        "start": 91,
        "stop": 92,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry(Length64(0), geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry(Length64(0), geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_cross_candidate_certificates.mojo": {
    "before_sha256": "3376a8b69a2afb499f81f29900678389cb526ef20fdd15711a7fae10b62e783e",
    "after_sha256": "05aabbd0b555368d81fbd9849cd6a768e26cf0385e4d705653dffb17e945a8a3",
    "before_token_sha256": "1dff3a87946b5b0802a45f001647db9afe9cf9bdcaa90f26e14cb545cf946140",
    "after_token_sha256": "ee1052d3e5b826b3bf476e0100e74ebf581848108844686a70f4afcfc98a95e9",
    "edits": [
      {
        "start": 81,
        "stop": 82,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry)\n"
        ]
      }
    ]
  },
  "tests/test_carla_curve_bounds.mojo": {
    "before_sha256": "d33608e0d1a34bf1c0c1ec14516ceb0f4ba1e2838afa9fc20c7caabd71121db5",
    "after_sha256": "4e157f2632108119d4fbd32d6cc1ecf358f00c761571c503852b101d4a2f37d6",
    "before_token_sha256": "2f0ef9e4ef65695b6d9a9befb3febe7bec673d6b4f91060a536ab14995c1ddb2",
    "after_token_sha256": "9ff248b01f1b045f83e67fed62fe35a2b6775573026b5c4692d22102b03e6a4f",
    "edits": [
      {
        "start": 73,
        "stop": 74,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_junction_endpoint_refusals.mojo": {
    "before_sha256": "8917ae79669327cab77e7ff01d91c16606d7604b65428897328d0f8f68f38e21",
    "after_sha256": "c379b4d751c728d4e5c27f1e5569f5ebc22cc64c6f3943b9ecd0d7d1447b8f60",
    "before_token_sha256": "611754c54ebc9ea9a468f6317a571cb4cec4179944dab43a7f7a087b9f8ed4a4",
    "after_token_sha256": "04eb1a8d2a0e333cf236ab4ca145b16faaa46f596fe732957a1273a88aa25dd6",
    "edits": [
      {
        "start": 68,
        "stop": 69,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(-1.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(-1.0, geometry))\n"
        ]
      },
      {
        "start": 167,
        "stop": 168,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_center_bound_phase.mojo": {
    "before_sha256": "4e3d9126f718d50515ef8cba6e9180b0b1a293d9da6545015aacf3aa0b568694",
    "after_sha256": "3e84bedf5ad9cbdca3eda70c866522f6d6c413a326f0a3e61b6fc0e1c8a4750e",
    "before_token_sha256": "97fd4c965d3d317370069c5c94d07c053d3b3e26f388bc79c093a989754b8f48",
    "after_token_sha256": "37f3c79a497322ee1d50efcebdc62fe5a94413f88fb46ea76e72d7924283e126",
    "edits": [
      {
        "start": 90,
        "stop": 91,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(-1.0, spiral^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(-1.0, spiral))\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_certificates.mojo": {
    "before_sha256": "95850cfbd11865bea5ba5e811bd2e85e46b75d04f84b67ee90734c085c2b8a03",
    "after_sha256": "06b76bd1fdb3fe31be9fe6ef042159f5cba72080a4acd472a69b7b30c5c8068a",
    "before_token_sha256": "a77390f05c142b79e84d5dcb855c1b9f0a1d56109a19b95b48c4b36cb6e6eb03",
    "after_token_sha256": "71d5add4297318a6ed55db4c3623b6ef0e24bc0d03de43a54e9d0692af02bd53",
    "edits": [
      {
        "start": 53,
        "stop": 54,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_control_successor.mojo": {
    "before_sha256": "9546e14ef6d9def3e9e15ea7bada15c6f236120e80ad82539f74a158b3a96985",
    "after_sha256": "b5ecc8ffff8a11e33be8c120aeecb23c072d512ad08901a6a4f8901c04168b9e",
    "before_token_sha256": "a8d725c79e9532cf43a1adbd75fe82ef5e940f2fe88b0c4c617bbdac6dbe1c93",
    "after_token_sha256": "b279700ee178ade1a3709c9f72d38f0a663b4d25596c29142c335a4e300d5d18",
    "edits": [
      {
        "start": 814,
        "stop": 815,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry)\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_dispatch_cell_residuals.mojo": {
    "before_sha256": "4fd81dbe809302898ad108d1459e6f248be001df1610d41c97553aede2b10be4",
    "after_sha256": "0b20d8c99a4369edd8bb1d60bcadb62853196e5b6cad19828c02922274661812",
    "before_token_sha256": "98e6dff8fe9e5b1a6acb20c8beb2d8d35891e10426b75b5d6d564ebcd03432d2",
    "after_token_sha256": "790b560f7040d437cc72bd2566af229b3b405d9bc58521e7777480fb503ab50b",
    "edits": [
      {
        "start": 36,
        "stop": 37,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry)\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_helper_guards.mojo": {
    "before_sha256": "226d73f20706bfebd06b137728486afb955af23233a416234dbdf58c7d114f09",
    "after_sha256": "837be15ed5d82c6ae983a1646c14bc7335a6994902d9cefbdc28f1128b501dca",
    "before_token_sha256": "0b5f6d57d91449a1367550fe7f224eae19f5d23a5e3500e9fd141534485750d2",
    "after_token_sha256": "7a4fb5b3df6abc172f315b08b4211dca2a60097ac3bf5c8584af17b4b3ed2771",
    "edits": [
      {
        "start": 302,
        "stop": 303,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.5, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.5, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_order_successor.mojo": {
    "before_sha256": "0b0f67b825b3aacbc8f3721a9bb5387c7fcf2ed3c45370992fe7dd9b5a15c880",
    "after_sha256": "996ab7d9646050616a5d04bb3b1f1afdca21095922bf189c2c1516c7afbe7564",
    "before_token_sha256": "ecd2244216f5e01f9f0379db0b224be6c448974d26404155a8e28bfa0e967b93",
    "after_token_sha256": "0b0a0656e29af8202be5ea11863885c6fbb8464e5523715cd6ee1aa613682a94",
    "edits": [
      {
        "start": 930,
        "stop": 931,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry)\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_search_positive_controls.mojo": {
    "before_sha256": "baa81dad7d34616953388581c12b550de1099474ae3074eb6c014dbb4e498be8",
    "after_sha256": "254c417e9b1d7806779e8879f494fbc12a1a3b4be6d512a2818535c7aca765c3",
    "before_token_sha256": "711c1b29d569a6093cff376211499957a9de91602b82b18168502185b32a481c",
    "after_token_sha256": "a72142597f6a7ca6a94151be91ecd77e2421619fa6e1d95f3aa6a4f5d46bee49",
    "edits": [
      {
        "start": 82,
        "stop": 83,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(start, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(start, geometry)\n"
        ]
      }
    ]
  },
  "tests/test_carla_render_light.mojo": {
    "before_sha256": "7da5773c7be39a3d6a76e88a177d03b7762daa974b635701b8d73c2e31af636b",
    "after_sha256": "14e9f75507d442b63979b88cd8401e1db71b2af3332949b865522357a32dda8a",
    "before_token_sha256": "addcb2731467077978d23ba88c9f783ef269a173b2a456b0023676e032b3f4da",
    "after_token_sha256": "6c62b1c552511dc8b718f0bc73467f850d134678f74a54020cff7d073d0d0ede",
    "edits": [
      {
        "start": 156,
        "stop": 157,
        "before": [
          "    var cube = cube_texture_from(faces^)\n"
        ],
        "after": [
          "    var cube = cube_texture_from(faces)\n"
        ]
      }
    ]
  },
  "tests/test_carla_road_fixed_s.mojo": {
    "before_sha256": "39b18125709aad7af4965198646ead78f66099f6865ccfadab897e6e5f268205",
    "after_sha256": "cef4d9b2eeac04085d98f52497ea03ff0b5246cadb592749d60e64467c7ff620",
    "before_token_sha256": "6cb2433e954186340ce29c655e7a4dbf20667e968cb8a4f86355addc2b14dfee",
    "after_token_sha256": "ef3ea40814f86cd95f2c31e9ffc2359706f2912da3784c1a9571d0f222850c32",
    "edits": [
      {
        "start": 65,
        "stop": 66,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_sampled_box_cover.mojo": {
    "before_sha256": "96576ee10e598c625c489b17fe7b40fa51279c1bb99a88cd6e44da8e48ea536d",
    "after_sha256": "27a2ff73e66463799963ef43eff04da6b1a4fa0a4826f69f2fa01c8e9e59c620",
    "before_token_sha256": "922b2f4b6b1b3187ca9472e8919fd0c4ddcc20136c3bab98cf2922f731f15874",
    "after_token_sha256": "36e16ddb2a990a0eae79daca76a40a573ee2736fd8acbdff529fa11660d3f616",
    "edits": [
      {
        "start": 127,
        "stop": 128,
        "before": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry^)\n"
        ],
        "after": [
          "    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry)\n"
        ]
      }
    ]
  },
  "tests/test_carla_scaled_lane_refinement.mojo": {
    "before_sha256": "5ff5ba2a87a8eb845ce5bbcc4dc89454c17d7adca11d5bf97a82d3509bf3a1b3",
    "after_sha256": "b3c297b47e0ec8ac2c283a90b7f018e06cd0405e7403b795caf7bdc4d3df7316",
    "before_token_sha256": "3ab96c785485b46879941dbc29b5b50b1a78bb4f98c53984d02e5c01a2a20a3b",
    "after_token_sha256": "cb367c403569f90e3d88738d52e8eb4b9b935b33548c19d5eca88053d4d80170",
    "edits": [
      {
        "start": 45,
        "stop": 46,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_speed_parser_exceptions.mojo": {
    "before_sha256": "46ef2fd18fde1f532f06b0027b317f96a3e5f3f2260ddcb7b266f1fe9d58731b",
    "after_sha256": "c6b4a9415cfec9b5929428d0fe9a5c95db56ede90d1802d4f033a78543a4d4d8",
    "before_token_sha256": "e5005d4bd15a6074ea9d73bca08039ecf1a94567903a06b7141512e180a71132",
    "after_token_sha256": "8a85b9da2912d774305237d6cd30fb053e4842cb5a1127ff00a96f1ee753ef9d",
    "edits": [
      {
        "start": 3,
        "stop": 4,
        "before": [
          "\"\"\"Fresh source control for the maintained SDK's real converter exception.\n"
        ],
        "after": [
          "\"\"\"Fresh source control for the speed number converter.\n"
        ]
      },
      {
        "start": 5,
        "stop": 8,
        "before": [
          "The decimal grammar admits the long token. The installed Float64 converter\n",
          "must independently raise, and read_speed_number must translate that actual\n",
          "exception. No injected parser or synthetic coverage trace is used.\n"
        ],
        "after": [
          "The decimal grammar admits a token of any length. The installed Float64\n",
          "converter reads that token and rounds it. It has no failure for a text that\n",
          "the grammar admits, so `read_speed_number` has no parse-failure line.\n"
        ]
      },
      {
        "start": 17,
        "stop": 18,
        "before": [
          "def test_valid_decimal_converter_exception_is_translated() raises:\n"
        ],
        "after": [
          "def test_a_long_decimal_is_read_and_rounded() raises:\n"
        ]
      },
      {
        "start": 21,
        "stop": 23,
        "before": [
          "    # Assert the underlying cause separately, so lexical/range rejection\n",
          "    # cannot masquerade as execution of the converter exception handler.\n",
          "    with assert_raises(contains=\"too long\"):\n",
          "        _ = Float64(number)\n",
          "    with assert_raises(contains=\"OpenDRIVE speed needs a numeric max value\"):\n",
          "        _ = read_speed_number(number)\n"
        ],
        "after": [
          "    assert_equal(Float64(number), Float64(1.2345678901234568e29))\n",
          "    assert_equal(read_speed_number(number), Float64(1.2345678901234568e29))\n"
        ]
      }
    ]
  },
  "tests/test_carla_tiny_cell_enumeration.mojo": {
    "before_sha256": "9bf99178e81d3fd9a1bbc14028b93fbf59482f995aa8b1e64c34dc1a6fc780c2",
    "after_sha256": "14d1f6bdcd1c5267a89e08424f59f99adad34bf880feb9c336ae8fb70033acf3",
    "before_token_sha256": "73a00197815294f74f3ca3834837f85f348ae201313cb05f89cf85339f1e61da",
    "after_token_sha256": "126b231d49e2f8316c828f7ff241d260a196cda03d283d002a867b351c5ee56c",
    "edits": [
      {
        "start": 74,
        "stop": 75,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_carla_unsampled_admission.mojo": {
    "before_sha256": "b335aa9948fe3eadeb620ed842af327925df86a27de2edb7221acc712a88b278",
    "after_sha256": "2c9feb22ea09258f6206b911267c73d7723590c68782eb6e9d2c8e1f02944666",
    "before_token_sha256": "23a6d84018a932c657f17493cf0e7443e3ae635b91cdbe7e9da73178013a430d",
    "after_token_sha256": "70483776014424be90da41f8be313db26f46adcdc5ef7b09af3352a147272565",
    "edits": [
      {
        "start": 42,
        "stop": 43,
        "before": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry^))\n"
        ],
        "after": [
          "    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, geometry))\n"
        ]
      }
    ]
  },
  "tests/test_cast_shadow.mojo": {
    "before_sha256": "a4507a140e0d770cf0ef93024e4db1b42aa991442b674d29598e04b18e8ae080",
    "after_sha256": "9798b4a266cb60844bf80a578aaadc1cbbe032cdff6f108b25f17f287192232d",
    "before_token_sha256": "b4d0249cf76f514708fbf244577ea33c3a528d63a15463bab2eb5543a0342e8b",
    "after_token_sha256": "ee33bbb08f011b30ede9372ab9fd0d19c64d706ab197132170bed37592b8edb5",
    "edits": [
      {
        "start": 404,
        "stop": 405,
        "before": [
          "            assets.materials.add(dotted^),\n"
        ],
        "after": [
          "            assets.materials.add(dotted),\n"
        ]
      }
    ]
  },
  "tests/test_draco.mojo": {
    "before_sha256": "834a6e4518e5f787c0c9f4052574abb6e38f63d3353245a6156d558c37c75ead",
    "after_sha256": "cfd1fbbfaad44e58e065114234ac40b3f230888824da722da89dc64c4fbc47a2",
    "before_token_sha256": "df0cf632f6040bfb580f87e5974c107cb8a299365049e0f245fb835135970a7c",
    "after_token_sha256": "c38feb6a8fcdefa2b384e6bdcbbfb5351485451e45624f55efaf4fb1e33f9d70",
    "edits": [
      {
        "start": 163,
        "stop": 164,
        "before": [
          "            _ = decode_draco(bytes^)\n"
        ],
        "after": [
          "            _ = decode_draco(bytes)\n"
        ]
      },
      {
        "start": 196,
        "stop": 197,
        "before": [
          "    var built = parse_draco(bytes^)\n"
        ],
        "after": [
          "    var built = parse_draco(bytes)\n"
        ]
      },
      {
        "start": 244,
        "stop": 245,
        "before": [
          "        _ = decode_draco(bad^)\n"
        ],
        "after": [
          "        _ = decode_draco(bad)\n"
        ]
      },
      {
        "start": 248,
        "stop": 249,
        "before": [
          "        _ = decode_draco(bad^)\n"
        ],
        "after": [
          "        _ = decode_draco(bad)\n"
        ]
      },
      {
        "start": 252,
        "stop": 253,
        "before": [
          "        _ = decode_draco(bad^)\n"
        ],
        "after": [
          "        _ = decode_draco(bad)\n"
        ]
      }
    ]
  },
  "tests/test_draco_export.mojo": {
    "before_sha256": "1b974269d6109df7bb7e0e560c0f167aa45845fefe62f9452e8101f84f7d997d",
    "after_sha256": "9fb38320aae6bd3e95548584f1a022579a0db63225ed31daed0f210e4601b569",
    "before_token_sha256": "f9302d22c8e04628503bb97fe0d1bce15ceea67912af8a0752d9e4a35aedb1d2",
    "after_token_sha256": "aa4162df8285dae4dced713463008391eaab4c149f3ed82d8e823af3ce006167",
    "edits": [
      {
        "start": 339,
        "stop": 340,
        "before": [
          "    var decoded = decode_draco(bytes^)\n"
        ],
        "after": [
          "    var decoded = decode_draco(bytes)\n"
        ]
      },
      {
        "start": 589,
        "stop": 590,
        "before": [
          "        _ = decode_draco(bytes^)\n"
        ],
        "after": [
          "        _ = decode_draco(bytes)\n"
        ]
      },
      {
        "start": 620,
        "stop": 621,
        "before": [
          "        var decoded = decode_draco(bytes^)\n"
        ],
        "after": [
          "        var decoded = decode_draco(bytes)\n"
        ]
      },
      {
        "start": 641,
        "stop": 642,
        "before": [
          "    var decoded = decode_draco(bytes^)\n"
        ],
        "after": [
          "    var decoded = decode_draco(bytes)\n"
        ]
      }
    ]
  },
  "tests/test_geometry_addons.mojo": {
    "before_sha256": "5022cda5d7e6af5f1f806878bd46cfc826ebb7f5149db566181aa52549e79391",
    "after_sha256": "d2207440b32b3c250956d0aec83accfee715a005438cc6edb1ac6fab344f57de",
    "before_token_sha256": "22675d725e879973e7c2033f7e0446124a9ffbcae12e65d8f022680d939b8ee7",
    "after_token_sha256": "1dedd6cf775ffb03c5d73c653f39c99e1d7aa140f69aa1bb9b9a85b25f02a798",
    "edits": [
      {
        "start": 519,
        "stop": 520,
        "before": [
          "    _ = check_hull(mirrored^)\n"
        ],
        "after": [
          "    _ = check_hull(mirrored)\n"
        ]
      }
    ]
  },
  "tests/test_geometry_signatures.mojo": {
    "before_sha256": "7ea2d59456a9da97f1a83e2680d45da8c3d0b6fe795421a371fbbbbabfef5a2a",
    "after_sha256": "1f70f54b9a7064b741e88decb7bd2289c8a51d5692c624b0ff8e09433be1f7cb",
    "before_token_sha256": "59ea0010afc0ee00162b70155f362d00c003d84a92ccb1b04b404ead5d92b659",
    "after_token_sha256": "94582cc75c9db768b56d761e61adb6f85c54e7f1f95d87ba1e3e3cf4b83e715d",
    "edits": [
      {
        "start": 380,
        "stop": 381,
        "before": [
          "        extrude(two_shapes(), meters(0.5), steps=2, uv_generator=world^),\n"
        ],
        "after": [
          "        extrude(two_shapes(), meters(0.5), steps=2, uv_generator=world),\n"
        ]
      }
    ]
  },
  "tests/test_gpu.mojo": {
    "before_sha256": "3163fbb3825b841a85232ce395cc7c65fed1185ec517a127dc34c40a896aba44",
    "after_sha256": "0138feec9382020007b8b71069459d1cbd057d1762091f3af2c6db9fb95fd675",
    "before_token_sha256": "6af92d3149b7de72a164f76a7961fbf068b6dc4f40f9c8033721c3a6c9b8e6a7",
    "after_token_sha256": "a6eea75470b27e08b3b8855760dd60e8f3fcd79fb0c707c0efb949fd085e66aa",
    "edits": [
      {
        "start": 75,
        "stop": 76,
        "before": [
          "from std.sys import has_apple_gpu_accelerator\n"
        ],
        "after": [
          "from std.sys import default_accelerator\n"
        ]
      },
      {
        "start": 10042,
        "stop": 10043,
        "before": [
          "                assets.materials.add(material^),\n"
        ],
        "after": [
          "                assets.materials.add(material),\n"
        ]
      },
      {
        "start": 10408,
        "stop": 10409,
        "before": [
          "        var scene = shaped_scene(assets, paint.copy(), block^)\n"
        ],
        "after": [
          "        var scene = shaped_scene(assets, paint.copy(), block)\n"
        ]
      },
      {
        "start": 12457,
        "stop": 12458,
        "before": [
          "    return VolumeImage.of_bytes(4, 4, 3, texels^)\n"
        ],
        "after": [
          "    return VolumeImage.of_bytes(4, 4, 3, texels)\n"
        ]
      },
      {
        "start": 13838,
        "stop": 13839,
        "before": [
          "        Data3DTexture(VolumeImage.of_bytes(4, 4, 3, texels^), filter=BILINEAR)\n"
        ],
        "after": [
          "        Data3DTexture(VolumeImage.of_bytes(4, 4, 3, texels), filter=BILINEAR)\n"
        ]
      },
      {
        "start": 15488,
        "stop": 15489,
        "before": [
          "    comptime if has_apple_gpu_accelerator():\n"
        ],
        "after": [
          "    comptime if default_accelerator().is_apple_gpu():\n"
        ]
      }
    ]
  },
  "tests/test_gpu_layout.mojo": {
    "before_sha256": "3485dbc5200ee4471a177de9cb06a9a12cf5ea3b89561f49f6806895eb2f4206",
    "after_sha256": "91b8f54b2e51b6e71a2d65443bf97df3c51881fa1bdc9b7749aecb6c41ec0419",
    "before_token_sha256": "ee1c8e1bad8b3ac6c025240eddf5e60e91330a2f0634c6cbb172e1d047131f35",
    "after_token_sha256": "77ce74bf680d4943b6c2d6d0fd508c9dc8a45eb37d3d3e0d02e274e57d017421",
    "edits": [
      {
        "start": 680,
        "stop": 681,
        "before": [
          "        Mesh(geometry, assets.materials.add(shiny^), scene.add(Object3D()))\n"
        ],
        "after": [
          "        Mesh(geometry, assets.materials.add(shiny), scene.add(Object3D()))\n"
        ]
      },
      {
        "start": 685,
        "stop": 686,
        "before": [
          "        Mesh(geometry, assets.materials.add(dull^), scene.add(Object3D()))\n"
        ],
        "after": [
          "        Mesh(geometry, assets.materials.add(dull), scene.add(Object3D()))\n"
        ]
      }
    ]
  },
  "tests/test_gpu_water.mojo": {
    "before_sha256": "9a944444d4dcb9a9f34ea714f6d31cb5110c8bf427967f71fee3aa9bf4fb625f",
    "after_sha256": "d7b66f38fdd614427e3936c600e0b6df674a190355bbee441cc03a5389a4f526",
    "before_token_sha256": "05bc205d0382c96dfc6b47fd62c8ae6c801471c1b5ae1082d54dbb828c975384",
    "after_token_sha256": "4f0ae7e83d0d3f0705f43130f5b5ff3c82e6ed1240c8766a7b75b8b6a176219e",
    "edits": [
      {
        "start": 39,
        "stop": 40,
        "before": [],
        "after": [
          "    default_accelerator,\n"
        ]
      },
      {
        "start": 41,
        "stop": 41,
        "before": [
          "    has_apple_gpu_accelerator,\n"
        ],
        "after": []
      },
      {
        "start": 325,
        "stop": 326,
        "before": [
          "    return not has_apple_gpu_accelerator()\n"
        ],
        "after": [
          "    return not default_accelerator().is_apple_gpu()\n"
        ]
      }
    ]
  },
  "tests/test_humanoid_bake.mojo": {
    "before_sha256": "98903c17239408b7e76366065d9f0458fc4ac79bd61ec924e071764f0738968b",
    "after_sha256": "4e35f783b3df86db4c9f30e36160e7210563cfb8e64fc8a02f1a7fccd57ed309",
    "before_token_sha256": "77538e39ea2464e8e9fd781936769e7d3c7de79f43eaeafdcd464c3b5e4e5cb9",
    "after_token_sha256": "a82285144033df00a294938e1404513d0c2f29bde01fe2aca3700550f14786b9",
    "edits": [
      {
        "start": 314,
        "stop": 315,
        "before": [
          "            options=options^,\n"
        ],
        "after": [
          "            options=options,\n"
        ]
      },
      {
        "start": 393,
        "stop": 394,
        "before": [
          "    write_gltf(path, bake.scene, bake.assets, GLB, options=options^)\n"
        ],
        "after": [
          "    write_gltf(path, bake.scene, bake.assets, GLB, options=options)\n"
        ]
      }
    ]
  },
  "tests/test_image_batch.mojo": {
    "before_sha256": "b1d26d226db3483c57d796b2bcc9e30600442d7f1120d13ebb56cea32d850661",
    "after_sha256": "7fd75caf5f445b4f0049519d0ee99d4b56cae28ca73cf54ed0b3474afae7cfd6",
    "before_token_sha256": "8257b533bb804f1b3dabdcbc7f88ba70a849583b330489b560ea6ec2b995d413",
    "after_token_sha256": "15dd39579f5c33e25051dc1e62645f519fcf63609803c24e351730b73722dc4b",
    "edits": [
      {
        "start": 74,
        "stop": 75,
        "before": [
          "async def _tracked_task(\n"
        ],
        "after": [
          "__async def _tracked_task(\n"
        ]
      }
    ]
  },
  "tests/test_morph_sequence_indices.mojo": {
    "before_sha256": "45f709f8a46c38cc5ab793a68883c12c2781e1a6e8fd20d6a585ae9ffb42f0d5",
    "after_sha256": "0412b70db025fb26ac05dd7db3422ea772116e1ec85ca7b05ff8e510e775a1f9",
    "before_token_sha256": "f79778de2ed2c7284136a9a25e4b033dd75e61c94672d25522d9240b85b58981",
    "after_token_sha256": "a0196601b57e926895da3d8eff97845d6266e26171edf4278c4c8f6140fc7f39",
    "edits": [
      {
        "start": 33,
        "stop": 34,
        "before": [
          "    scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "    scene.add_mesh(mesh)\n"
        ]
      }
    ]
  },
  "tests/test_norm_review_regressions.mojo": {
    "before_sha256": "2e6d31187d854259850084b9df94c0dbfa2c7e418838c2a671e3ff1ace32b319",
    "after_sha256": "5ba9dc73d034a031f504970d8528d92d0d713cc86002df12d5c3971c84d71bdc",
    "before_token_sha256": "b30e9a1d8b07ed9e01558630f111e23e3bd0ab9759f3091827e4f34372263553",
    "after_token_sha256": "70b1f61557625897dd708454cdace71719e4a5a41bb5a44996511053a9bac078",
    "edits": [
      {
        "start": 305,
        "stop": 306,
        "before": [
          "    var model = parse_amf(bytes^, scene, assets)\n"
        ],
        "after": [
          "    var model = parse_amf(bytes, scene, assets)\n"
        ]
      }
    ]
  },
  "tests/test_projector.mojo": {
    "before_sha256": "bf1d3ccb1accb0746416012134bdf1aa646007c817b63994f4805deed1819f63",
    "after_sha256": "9877cdd9367172af7663cc83718417942712c1e50e37cb7eda2cc57fa8e36a2f",
    "before_token_sha256": "0e241d030a3c3b15e425824000d25ab53a97603ff999252d264d890bc8b4a04d",
    "after_token_sha256": "5337ff1da33c04a60f095468c4f0660949d84008e79b48b679747c79817ed354",
    "edits": [
      {
        "start": 96,
        "stop": 97,
        "before": [
          "    return assets.materials.add(material^)\n"
        ],
        "after": [
          "    return assets.materials.add(material)\n"
        ]
      },
      {
        "start": 224,
        "stop": 225,
        "before": [
          "            assets.materials.add(shaded^),\n"
        ],
        "after": [
          "            assets.materials.add(shaded),\n"
        ]
      },
      {
        "start": 320,
        "stop": 321,
        "before": [
          "    scene.add_sprite(Sprite(assets.materials.add(hidden^), _node(scene)))\n"
        ],
        "after": [
          "    scene.add_sprite(Sprite(assets.materials.add(hidden), _node(scene)))\n"
        ]
      }
    ]
  },
  "tests/test_scene_optimizer.mojo": {
    "before_sha256": "38a9edd0d4ce923e1e366b40cea6c9623aa5150470a2fd78b461fea041bde73a",
    "after_sha256": "8c001171db985ff4e77600c9b6a2b396f5ddaec55637bb9ea17c4ee5e6807885",
    "before_token_sha256": "b5f20918f3f430bad02346497aa1bdc35e2af9eb46028b6b22b6407da9d81ff6",
    "after_token_sha256": "45259a528bd0f06b80f0aeef4e3edcfd6f4dbe2200640ddd7524fe3640bdb3c9",
    "edits": [
      {
        "start": 244,
        "stop": 245,
        "before": [
          "    var paint = assets.materials.add(mapped^)\n"
        ],
        "after": [
          "    var paint = assets.materials.add(mapped)\n"
        ]
      }
    ]
  },
  "tests/test_scratch.mojo": {
    "before_sha256": "3bb38fdd55e0adc15779218c323794d577c9901767c211b67161b0e04cac80f8",
    "after_sha256": "3edd09c82df12d059fa47d446ea1aa70479ed3354718b48cc773568df4dc5e5b",
    "before_token_sha256": "d8af870b59a87756aae6bdf1dc43f4f7b46974a679d04e94171b553323755dff",
    "after_token_sha256": "ae0d61d8361d95d77ba730f8c1c0062c43089a198137f657f18cfe2c3af7be35",
    "edits": [
      {
        "start": 71,
        "stop": 72,
        "before": [
          "            prefix=\"threemojo-test-\", dir=directory^\n"
        ],
        "after": [
          "            prefix=\"threemojo-test-\", dir=directory\n"
        ]
      }
    ]
  },
  "tests/test_shadow_casters.mojo": {
    "before_sha256": "1c7d3a13e824ca7461b619afda25ee530e7e216699781d2f68b14c5183480a93",
    "after_sha256": "3b7575eb961432f5ce1d3f2b795db3da6e0a4951bcc68fd2505b23c4cb957628",
    "before_token_sha256": "ead6ad5fb5a9bfb7e63d26129197a7de630e9a6b956a0da6cb7181ab66f2a454",
    "after_token_sha256": "9c9c52aa129d9ad11ce11213347d1c12dd19208b70740e9932c8d78d49abf150",
    "edits": [
      {
        "start": 386,
        "stop": 387,
        "before": [
          "        scene.meshes[1].material = assets.materials.add(glass^)\n"
        ],
        "after": [
          "        scene.meshes[1].material = assets.materials.add(glass)\n"
        ]
      },
      {
        "start": 431,
        "stop": 433,
        "before": [
          "        scene.add_mesh(Mesh(pane, assets.materials.add(front^), near_node))\n",
          "        scene.add_mesh(Mesh(pane, assets.materials.add(back^), far_node))\n"
        ],
        "after": [
          "        scene.add_mesh(Mesh(pane, assets.materials.add(front), near_node))\n",
          "        scene.add_mesh(Mesh(pane, assets.materials.add(back), far_node))\n"
        ]
      },
      {
        "start": 516,
        "stop": 517,
        "before": [
          "                assets.materials.add(wire^),\n"
        ],
        "after": [
          "                assets.materials.add(wire),\n"
        ]
      },
      {
        "start": 556,
        "stop": 557,
        "before": [
          "                assets.materials.add(paint^),\n"
        ],
        "after": [
          "                assets.materials.add(paint),\n"
        ]
      }
    ]
  },
  "tests/test_strand_triangles.mojo": {
    "before_sha256": "fd3927475305a1a5acbed88d6d9023bd45d26a032d6f1c5fe2036b501231449d",
    "after_sha256": "2991306cbc80e589db9831a764b9cdcdc9aa402583bcfe28b9e891ca0524ece0",
    "before_token_sha256": "1c35f293ff8e244d616689439071df6abe5044800c4d66351d625e40c7b211b8",
    "after_token_sha256": "869bb41153dcd07a185a433ed3417c099d9f8f91a8bb01ba94f0a0d173608477",
    "edits": [
      {
        "start": 63,
        "stop": 64,
        "before": [
          "    var material = assets.materials.add(style^)\n"
        ],
        "after": [
          "    var material = assets.materials.add(style)\n"
        ]
      }
    ]
  },
  "tests/test_svg_renderer.mojo": {
    "before_sha256": "a93e75c88b132548b2bbf7731af352b5adb8f9dad0a4e19e0bcb03212fb4e743",
    "after_sha256": "3d3234ce4e0052f2e43a7b00a7c85dba91401ab4ac577bde96528be21d7b3e65",
    "before_token_sha256": "992347b66f05dd4f01d1b77e4f76f9bf9966564c30ac58b4628a3a70c196f617",
    "after_token_sha256": "7b509092102baa3e61f640b043f753ecd0034cb4df57fda593a4592a42e73beb",
    "edits": [
      {
        "start": 551,
        "stop": 552,
        "before": [
          "            assets.materials.add(paint^),\n"
        ],
        "after": [
          "            assets.materials.add(paint),\n"
        ]
      },
      {
        "start": 598,
        "stop": 599,
        "before": [
          "            assets.materials.add(both^),\n"
        ],
        "after": [
          "            assets.materials.add(both),\n"
        ]
      }
    ]
  },
  "tests/test_visibility.mojo": {
    "before_sha256": "ae596f44e167dceb1b073824b7ce83975cab0cc9e030d24f86a75a68031abc05",
    "after_sha256": "0b7b771830042718dd177822b5b862a5d5d326a81ca44cd62572ed34bcaa4f27",
    "before_token_sha256": "8796595329581f6cc4bb700fce020ca8722947dd2ebfdd404761a6316e48c40b",
    "after_token_sha256": "afe72966b8a4bacb0ce6e73ad83ccd2a61fd3b0627b8d8c1f5ac6729638e741d",
    "edits": [
      {
        "start": 284,
        "stop": 285,
        "before": [
          "    var red = assets.materials.add(glass^)\n"
        ],
        "after": [
          "    var red = assets.materials.add(glass)\n"
        ]
      }
    ]
  },
  "tests/test_wide_line_workers.mojo": {
    "before_sha256": "98486541d2fff814dc1f12550fd2bcefbe5ea3bdfc4f334ef440d95e09e306b9",
    "after_sha256": "2172728ededc3775e0027966860fa8d7520f0babf3dcba68431a0c01858b1672",
    "before_token_sha256": "35ae1bd1fcbd15cd1ef7ef5422ab2c25e0d97c38b4a947a490e872d55868659d",
    "after_token_sha256": "7e540b1e5483b151050b736aeafd0e48fea7cdf29745e01080003eaa0b9d088c",
    "edits": [
      {
        "start": 88,
        "stop": 89,
        "before": [
          "    var lead_material = assets.materials.add(lead_style^)\n"
        ],
        "after": [
          "    var lead_material = assets.materials.add(lead_style)\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/source_contracts.py": {
    "before_sha256": "ebb6e75b90528b5456485433d470de36e6b33e4df98139dd0acadda75a57adf5",
    "after_sha256": "6a1f6f3efed801d586976fb3f7acff672d61409fbc61c957b8bf7cd808d3fda8",
    "before_token_sha256": "b22fc35f7dfa59a57136e32d554c6ae85d2790aef00f672adee10883c1067c7e",
    "after_token_sha256": "943ff2bc5565dbac6d57905f78cf8b8909cbf33f7d85fdfc3580d9c79af6714f",
    "edits": [
      {
        "start": 51,
        "stop": 56,
        "before": [],
        "after": [
          "# Immutable records pin these sources by their digests from before the PR780\n",
          "# successor edit. Their historical view is the exact predecessor.\n",
          "HISTORICAL_SUCCESSOR_PATHS = frozenset((\n",
          "    PREFIX + 'assets.mojo', PREFIX + 'model_cache.mojo', PREFIX + 'sensor.mojo',\n",
          "    PREFIX + 'speed_limits.mojo', 'tests/test_carla_speed_parser_exceptions.mojo'))\n"
        ]
      },
      {
        "start": 355,
        "stop": 357,
        "before": [
          "        if relative not in pr760.CARLA_REGISTRY_PATHS:\n"
        ],
        "after": [
          "        if (relative not in pr760.CARLA_REGISTRY_PATHS\n",
          "                and relative not in HISTORICAL_SUCCESSOR_PATHS):\n"
        ]
      },
      {
        "start": 380,
        "stop": 382,
        "before": [
          "        if relative not in pr760.CARLA_REGISTRY_PATHS:\n"
        ],
        "after": [
          "        if (relative not in pr760.CARLA_REGISTRY_PATHS\n",
          "                and relative not in HISTORICAL_SUCCESSOR_PATHS):\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_typed_owned_operations.py": {
    "before_sha256": "b71272abd022ff7453099ede5e5cd8ca8fc0dc6ba92057a94bdcd85170e39984",
    "after_sha256": "935e782aed3a11816c65001422c1b41e3760b5c9ded88ccf7dd58a7fff23cb5f",
    "before_token_sha256": "c84f544cdbffbd74be814905e13bba935182e54c2df54f44c2d5e2a1a38b885f",
    "after_token_sha256": "f88fa77df27b2afe4c77a143f00ec6074a288ed732e09f19c9592e21264a3938",
    "edits": [
      {
        "start": 165,
        "stop": 167,
        "before": [
          "        historical = typed.historical_source(seed.MODULE, current)\n"
        ],
        "after": [
          "        historical = typed.historical_source(seed.MODULE, fixtures.typed_current_bytes(\n",
          "            seed.MODULE, current.encode()).decode())\n"
        ]
      },
      {
        "start": 181,
        "stop": 183,
        "before": [
          "        old_lane = typed.historical_source('extensions/carla/lane_refinement.mojo', physical_lane)\n"
        ],
        "after": [
          "        old_lane = typed.historical_source('extensions/carla/lane_refinement.mojo', fixtures.typed_current_bytes(\n",
          "            'extensions/carla/lane_refinement.mojo', physical_lane.encode()).decode())\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_witness_format_contracts.py": {
    "before_sha256": "82f7e13e72b4f99ccad63d5dfe55fc0a73c898120b43ed8416b0731489ea6f84",
    "after_sha256": "0f6f81acd262946a8b84fd100f0522d2973325cf712f480eb6476e63e4f0b282",
    "before_token_sha256": "919de972f5e315164ceb6eb6b81a139c388e3749edc5103cfe7f2c9f1206a327",
    "after_token_sha256": "88c1bc33b8807403edda21c8cc8a0507957b2881c0aee3198a6f50bc0eae2b6f",
    "edits": [
      {
        "start": 109,
        "stop": 113,
        "before": [
          "                self.assertEqual(bindings[path], edge['after_sha256'])\n"
        ],
        "after": [
          "                physical = (self.root/path).read_bytes()\n",
          "                self.assertEqual(bindings[path], cleanup.sha(physical))\n",
          "                self.assertEqual(cleanup.sha(fixtures.typed_current_bytes(path, physical)),\n",
          "                                 edge['after_sha256'])\n"
        ]
      },
      {
        "start": 114,
        "stop": 118,
        "before": [
          "                self.assertEqual(bindings[path], witness.AFTER_SHA256[path])\n"
        ],
        "after": [
          "                physical = (self.root/path).read_bytes()\n",
          "                self.assertEqual(bindings[path], cleanup.sha(physical))\n",
          "                self.assertEqual(cleanup.sha(fixtures.typed_current_bytes(path, physical)),\n",
          "                                 witness.AFTER_SHA256[path])\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/translated_parameter_resolution.py": {
    "before_sha256": "0523d91f8d3b508619d37b9e9a73106c2b961cebf5808f23e61758c2a6228be9",
    "after_sha256": "0de1410549e5d230c9f0a7cfa9f9a3b43e09c30d405bb7f9c3824eacedb6c881",
    "before_token_sha256": "a22e21762dedad21f046301b224fbd850c09287354f2b928cf500d8140f2baa1",
    "after_token_sha256": "c72c2c6388b7739f365221c24fffe15079d612c3ed33dba5ebe780ef5eb5de61",
    "edits": [
      {
        "start": 42,
        "stop": 44,
        "before": [
          "    text = _current_bytes(name).decode('utf-8')\n"
        ],
        "after": [
          "    raw = full_audit.pr780_successor.predecessor_bytes(name, _current_bytes(name))\n",
          "    text = raw.decode('utf-8')\n"
        ]
      }
    ]
  },
  "tools/test_conditioned_coverage_loops.py": {
    "before_sha256": "1c7a6f9f0f32ec579b0609c0cac7fec04dedd342c7e22ec9a9956d6c6042c2dc",
    "after_sha256": "9c2c7d223a88f6a974fbdff0f9fc42246ac44583b73162b46c300b83ec2861dd",
    "before_token_sha256": "6d29f83a10d9be3031969d0702b6b5ee80de96a3441115aba4920715e13d03d2",
    "after_token_sha256": "a58817c389e1bfbfcff3ae68cba1ad9503fec8957cc4b5981e63432ba50a5d9d",
    "edits": [
      {
        "start": 29,
        "stop": 31,
        "before": [
          "        self.texts = {module:(ROOT/(module+'.mojo')).read_text()\n"
        ],
        "after": [
          "        self.texts = {module:loops._typed_endpoint(module+'.mojo',\n",
          "                          (ROOT/(module+'.mojo')).read_text())\n"
        ]
      }
    ]
  }
}
''')
BOUND_INPUTS = {'tests/test_anatomy_muscle.mojo': '3653d6056c1f9f639537eedb7cd80364baf80352b4aa984d39c0e737d8801401',
 'tests/test_animation_strings.mojo': 'f5103e3660a63d3d5d9d348a0d928fa106e5cef03059d432a31335bb7dd14184',
 'tests/test_loader_bounds.mojo': '6e0c1487f1ff21f4654c2790e4460c0adf934bf6b9273e826782eec1bfed2d83',
 'tools/carla_lane_oracle/test_pr780_source_successor.py': 'b88cdc20f3a6dfb0b38c6e85ccbe9b5c80d8ba5700ee2d8cf1a982e8e43ceeb0'}
DATA_SHA256 = 'a8a9be7b1adcadcaa6ca836d6c7e78e5d2e5183cfdd558eb68ba753d769d1f06'
# END FIXED PR780 SUCCESSOR DATA


def require(ok, message):
    if not ok:
        raise ValueError('PR780 source successor: ' + message)


def sha(raw):
    return hashlib.sha256(raw.encode('utf-8') if type(raw) is str else raw).hexdigest()


def _data_snapshot():
    """Authenticate and detach the full finite inverse data before consuming it."""
    require(type(DATA_SHA256) is str, 'authority digest selector is not a builtin string')
    require(DATA_SHA256 == 'a8a9be7b1adcadcaa6ca836d6c7e78e5d2e5183cfdd558eb68ba753d769d1f06', 'authority digest selector changed')
    encoded = json.dumps({'edges': EDGES, 'bound_inputs': BOUND_INPUTS},
                         sort_keys=True, separators=(',', ':'))
    require(sha(encoded) == DATA_SHA256, 'fixed source inverse data changed')
    return json.loads(encoded)


def verify_data():
    """Authenticate the complete finite inverse table against executing code."""
    _data_snapshot()


def _predecessor(path, raw, edge):
    require(type(path) is str and type(raw) is bytes,
            'predecessor requires builtin source bytes')
    digest = sha(raw)
    if digest == edge['before_sha256']:
        return raw
    require(digest == edge['after_sha256'], 'unreviewed source endpoint: ' + path)
    text = raw.decode('utf-8')
    require(source.token_sha256(text) == edge['after_token_sha256'],
            'current source tokens changed: ' + path)
    lines = text.splitlines(keepends=True)
    previous = len(lines) + 1
    for edit in reversed(edge['edits']):
        start, stop = edit['start'], edit['stop']
        require(type(start) is int and type(stop) is int
                and 0 <= start <= stop < previous
                and lines[start:stop] == edit['after'],
                'source inverse span changed: ' + path)
        lines[start:stop] = edit['before']
        previous = start
    prior = ''.join(lines)
    require(sha(prior) == edge['before_sha256']
            and source.token_sha256(prior) == edge['before_token_sha256'],
            'source inverse misses its exact predecessor: ' + path)
    return prior.encode('utf-8')


def predecessor_bytes(path, raw):
    """Return a named exact predecessor for pure historical comparisons only."""
    require(type(path) is str and type(raw) is bytes,
            'predecessor requires builtin source bytes')
    edges = _data_snapshot()['edges']
    if path not in edges:
        return raw
    result = _predecessor(path, raw, edges[path])
    verify_data()
    return result


def verify_sources(inputs):
    """Check one exact cohort and return its retained PR760 comparison bytes."""
    edges = _data_snapshot()['edges']
    require(type(inputs) is dict and set(inputs) == set(edges),
            'missing or extra successor source')
    current = []
    result = {}
    for path, edge in edges.items():
        raw = inputs[path]
        result[path] = _predecessor(path, raw, edge)
        current.append(sha(raw) == edge['after_sha256'])
    require(all(current), 'mixed or historical source successor cohort')
    verify_data()
    return result
