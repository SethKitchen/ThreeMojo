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
    "after_sha256": "afa58187363fb35fdc38c5b5eb82b2e8a4fa06302f83808598c6651331cbe258",
    "before_token_sha256": "49c113f28ee16d52cbbb50c6f93b18902581fde0c15cede8634e71dfb64e16d0",
    "after_token_sha256": "dae0c2430f5406f73468a1eaef61503066bee9883f93eefd9eca274bab3141c4",
    "edits": [
      {
        "start": 3529,
        "stop": 3530,
        "before": [],
        "after": [
          "    tones.reserve(image.width)\n"
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
    "after_sha256": "a2a5fdf4e6f686d6a24f8ed5288feef0275a8bd7696f4ebbe498f4d2c2d2138f",
    "before_token_sha256": "73561ca033b0eef88bf6ce996cfe062f8b2b34bc2652feda12dc5aef15de9e68",
    "after_token_sha256": "b9d12a50d3cbd2dc7706e9f5ed5aede6667f90d11459f394fbfebf9466fb0934",
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
    "before_sha256": "1c1565c05cb702df67319cb69641f83c8a761d38ccf06a11de91b037dfe5b1ce",
    "after_sha256": "d23c66fc6c90babdf7072060a4d68e3548e2d8b7b67a8f20a289b43a981652be",
    "before_token_sha256": "8679cc01efc5f133b6c59c9fe4f5e1c7132d0cd119054de274b77ef95b1d87a4",
    "after_token_sha256": "db6676250cb26305433429abbdfe1e9cce344329cb37a49b8aa6e5c3dbf718cd",
    "edits": [
      {
        "start": 122,
        "stop": 123,
        "before": [],
        "after": [
          "            raw = owner.pr780_successor.predecessor_bytes(path, raw)\n"
        ]
      }
    ]
  }
}
''')
BOUND_INPUTS = {'tests/test_anatomy_muscle.mojo': '3653d6056c1f9f639537eedb7cd80364baf80352b4aa984d39c0e737d8801401',
 'tests/test_animation_strings.mojo': 'f5103e3660a63d3d5d9d348a0d928fa106e5cef03059d432a31335bb7dd14184',
 'tests/test_loader_bounds.mojo': '6e0c1487f1ff21f4654c2790e4460c0adf934bf6b9273e826782eec1bfed2d83',
 'tools/carla_lane_oracle/test_pr780_source_successor.py': '5ceb366ebcf3500a1b61cf6ddc330997cd8906cf8c52b0620e2d335bd324c430'}
DATA_SHA256 = '365df60b88c6d641fbfdbc4986a4866aeb4d6e40ad53884987872de5bdad3d53'
# END FIXED PR780 SUCCESSOR DATA


def require(ok, message):
    if not ok:
        raise ValueError('PR780 source successor: ' + message)


def sha(raw):
    return hashlib.sha256(raw.encode('utf-8') if type(raw) is str else raw).hexdigest()


def _data_snapshot():
    """Authenticate and detach the full finite inverse data before consuming it."""
    require(DATA_SHA256 == '365df60b88c6d641fbfdbc4986a4866aeb4d6e40ad53884987872de5bdad3d53', 'authority digest selector changed')
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
