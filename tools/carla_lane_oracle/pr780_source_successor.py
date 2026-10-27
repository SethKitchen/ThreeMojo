# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact PR780 and PR791 source and qualification provenance; no physical admission.

This pure leaf reads no files and accepts no root. Its fixed inverse preserves
all original PR760 pins. PR791 adds the five sources that the scan renderer
changes to the same table. The owning checker still observes current bytes,
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
    "after_sha256": "d31186a9f02b328dc644194a1246a0b71ff7bc4c68f8556b8b18e3a623bb90cb",
    "before_token_sha256": "0263ba183b30437b826ada3ceedb3d2c5a3664dc95245743a17209f568607b79",
    "after_token_sha256": "482b296f13d4f26b242b1700b1ae416e6248ca45b7b599b1640c0a7c172dfe27",
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
      },
      {
        "start": 3954,
        "stop": 3956,
        "before": [
          "            Error: If the distance is not positive.\n"
        ],
        "after": [
          "            Error: If the distance is not positive, or a road needs more\n",
          "                waypoints than this port walks.\n"
        ]
      },
      {
        "start": 3961,
        "stop": 3965,
        "before": [],
        "after": [
          "            if not (road.length / distance < Float64(16777216)):\n",
          "                raise Error(\n",
          "                    \"A generated waypoint count is larger than this port walks\"\n",
          "                )\n"
        ]
      },
      {
        "start": 3978,
        "stop": 3979,
        "before": [
          "                if not isfinite(following) or following <= s:\n"
        ],
        "after": [
          "                if not isfinite(following):\n"
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
    "after_sha256": "966c0050ee1e67e77c6371a6f415f0afe9bef561804d167dd35e50aa5633c73d",
    "before_token_sha256": "63f9e55ab1cf9ff7e2722a6a7e1df4a1bb5475bce1bab89f8a58fd1a7f218e5a",
    "after_token_sha256": "772a3d8cbcfe16852c97cf6af447b083754ad8cb1a12d275d42c338d480a708e",
    "edits": [
      {
        "start": 21,
        "stop": 23,
        "before": [
          "  each crosswalk outline of `Map.all_crosswalk_zones`.\n"
        ],
        "after": [
          "  each crosswalk outline of `Map.all_crosswalk_zones`. A crosswalk that\n",
          "  needs more than 16777216 stripes is refused.\n"
        ]
      },
      {
        "start": 25,
        "stop": 30,
        "before": [
          "  another road or another lot is left empty. Each building has a row of\n",
          "  shops on its ground floor, a cornice above it, floors of windows, and\n",
          "  a parapet round its roof. A ring of tall buildings far out makes the\n",
          "  skyline.\n"
        ],
        "after": [
          "  another road or another lot is left empty. A road that needs more than\n",
          "  16777216 lots is refused. Each building has a row of shops on its\n",
          "  ground floor, a cornice above it, floors of windows, and a parapet\n",
          "  round its roof. A ring of tall buildings far out makes the skyline.\n",
          "  A ring of more than 16777216 buildings is refused.\n"
        ]
      },
      {
        "start": 32,
        "stop": 34,
        "before": [
          "  night.\n"
        ],
        "after": [
          "  night. The spacing must be a finite positive distance. A road that needs\n",
          "  more than 16777216 lamps is refused.\n"
        ]
      },
      {
        "start": 164,
        "stop": 165,
        "before": [
          "from std.math import atan2, cos, pow, sin, sqrt\n"
        ],
        "after": [
          "from std.math import atan2, cos, isfinite, pow, sin, sqrt\n"
        ]
      },
      {
        "start": 192,
        "stop": 196,
        "before": [],
        "after": [
          "# Lots, lamps and stripes. A finer walk does not finish.\n",
          "comptime _MAX_TOWN_STEPS = 16777216\n",
          "# A lot is at least 10 m wide, then a gap of 1.5 m.\n",
          "comptime _MIN_LOT_STEP = 11.5\n"
        ]
      },
      {
        "start": 527,
        "stop": 529,
        "before": [
          "        Error: If a map query fails.\n"
        ],
        "after": [
          "        Error: If a road needs more lots than this port walks, or a map\n",
          "            query fails.\n"
        ]
      },
      {
        "start": 534,
        "stop": 536,
        "before": [],
        "after": [
          "        if not (road.length / _MIN_LOT_STEP < Float64(_MAX_TOWN_STEPS)):\n",
          "            raise Error(\"A building lot count is larger than this port walks\")\n"
        ]
      },
      {
        "start": 597,
        "stop": 598,
        "before": [
          "        Error: If the count is less than one.\n"
        ],
        "after": [
          "        Error: If the count is less than one, or more than this port builds.\n"
        ]
      },
      {
        "start": 601,
        "stop": 603,
        "before": [],
        "after": [
          "    if count > 16777216:\n",
          "        raise Error(\"A skyline count is larger than this port builds\")\n"
        ]
      },
      {
        "start": 644,
        "stop": 646,
        "before": [
          "        Error: If the spacing is not positive, or a map query fails.\n"
        ],
        "after": [
          "        Error: If the spacing is not a finite positive distance, a road\n",
          "            needs more lamps than this port walks, or a map query fails.\n"
        ]
      },
      {
        "start": 647,
        "stop": 647,
        "before": [
          "    if not (spacing.to(METER) > 0):\n",
          "        raise Error(\"Street lamps need a positive spacing\")\n"
        ],
        "after": []
      },
      {
        "start": 648,
        "stop": 650,
        "before": [],
        "after": [
          "    if not isfinite(step) or not (step > 0.0):\n",
          "        raise Error(\"Street lamps need a finite positive spacing\")\n"
        ]
      },
      {
        "start": 654,
        "stop": 656,
        "before": [],
        "after": [
          "        if not (road.length / step < Float64(_MAX_TOWN_STEPS)):\n",
          "            raise Error(\"A street lamp count is larger than this port walks\")\n"
        ]
      },
      {
        "start": 687,
        "stop": 689,
        "before": [
          "        Error: Never for finite corners; the geometry's checks are passed\n",
          "            on.\n"
        ],
        "after": [
          "        Error: If a crosswalk needs more stripes than this port walks, or\n",
          "            the geometry's checks fail.\n"
        ]
      },
      {
        "start": 708,
        "stop": 712,
        "before": [],
        "after": [
          "            if not (length < Float32(_MAX_TOWN_STEPS)):\n",
          "                raise Error(\n",
          "                    \"A crosswalk stripe count is larger than this port walks\"\n",
          "                )\n"
        ]
      },
      {
        "start": 1416,
        "stop": 1417,
        "before": [
          "        scene.add_mesh(mesh^)\n"
        ],
        "after": [
          "        scene.add_mesh(mesh)\n"
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
  "geometries/box.mojo": {
    "before_sha256": "fecb76f248d3d0e42a1835e15772f4371951d10c615dc54e0851bd3deb88367b",
    "after_sha256": "228ce1bd43f2d65dfe0c9c8c0d9e645f18051fde11c94079e060a3543ed039ff",
    "before_token_sha256": "6fe072b5242e30914a4ab2e539690915cac3436c70ffb2034f7fadb5a6549251",
    "after_token_sha256": "b1bea1966af81baf573217be5f00aa588435c00e6f0ead994868eb72f52ca258",
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
        "stop": 45,
        "before": [],
        "after": [
          "    require_finite_extents,\n",
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 166,
        "stop": 169,
        "before": [
          "        Error: If any extent is not positive, or any segment count is\n",
          "            below one. three.js floors a count and takes what it gets.\n"
        ],
        "after": [
          "        Error: If any extent is not finite or not positive, any segment\n",
          "            count is below one, or a face has more than 16777216 cells.\n",
          "            three.js floors a count and takes what it gets.\n"
        ]
      },
      {
        "start": 170,
        "stop": 171,
        "before": [],
        "after": [
          "    require_finite_extents(width.value, height.value, depth.value, \"box\")\n"
        ]
      },
      {
        "start": 174,
        "stop": 189,
        "before": [],
        "after": [
          "    require_grid_cells(\n",
          "        width_segments,\n",
          "        height_segments,\n",
          "        \"A box's segment count is larger than this port builds\",\n",
          "    )\n",
          "    require_grid_cells(\n",
          "        width_segments,\n",
          "        depth_segments,\n",
          "        \"A box's segment count is larger than this port builds\",\n",
          "    )\n",
          "    require_grid_cells(\n",
          "        depth_segments,\n",
          "        height_segments,\n",
          "        \"A box's segment count is larger than this port builds\",\n",
          "    )\n"
        ]
      }
    ]
  },
  "geometries/circle.mojo": {
    "before_sha256": "9b63de2bcac8903b67458ea26901505e7030fc10a5d4c2e3da77debbab0c4605",
    "after_sha256": "2621a469cf49b116a511b28e77671793fc8cfb8d998dd38b11514310757b6e62",
    "before_token_sha256": "1e9db0a7ef47b22770ecc835f48c7d167eab54d6714968d4b0566e2b348cc188",
    "after_token_sha256": "3f91b2fa8d26d026c4b12430860d7c62d8e50a1a8161000825adf22f4b1568da",
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
        "start": 53,
        "stop": 54,
        "before": [],
        "after": [
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 131,
        "stop": 133,
        "before": [
          "            segments, or the sweep is not positive or is more than a turn.\n"
        ],
        "after": [
          "            segments, there are more than 16777216 segments, or the sweep\n",
          "            is not positive or is more than a turn.\n"
        ]
      },
      {
        "start": 136,
        "stop": 139,
        "before": [],
        "after": [
          "    require_grid_cells(\n",
          "        segments, 1, \"A circle's segment count is larger than this port builds\"\n",
          "    )\n"
        ]
      },
      {
        "start": 202,
        "stop": 206,
        "before": [
          "        Error: If the inner radius is negative, the outer radius is not\n",
          "            more than it, either segment count is too small, or the sweep\n",
          "            is not positive or is more than a turn.\n"
        ],
        "after": [
          "        Error: If the inner radius is not finite or is negative, the outer\n",
          "            radius is not finite or not more than it, either segment count\n",
          "            is too small, the grid has more than 16777216 cells, or the\n",
          "            sweep is not positive or is more than a turn.\n"
        ]
      },
      {
        "start": 207,
        "stop": 214,
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
      },
      {
        "start": 220,
        "stop": 225,
        "before": [],
        "after": [
          "    )\n",
          "    require_grid_cells(\n",
          "        theta_segments,\n",
          "        phi_segments,\n",
          "        \"A ring's segment count is larger than this port builds\",\n"
        ]
      }
    ]
  },
  "geometries/cylinder.mojo": {
    "before_sha256": "34de4d39e213985bb6c1280dcfab394f4f726f4b6051c874d1af37392bffa46e",
    "after_sha256": "24daed650dee9e86940d7731d5957edd7d2215c93e05a8273ba926d9f527c0ba",
    "before_token_sha256": "46980193661a602bdadd26f2498b4f33a8d16a48c1c753ea383b865083b909ce",
    "after_token_sha256": "8eae85b5cc3041cf45ab1e728effbe77331ce8e74546208f0f54ad476a5e5421",
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
        "start": 57,
        "stop": 58,
        "before": [],
        "after": [
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 184,
        "stop": 188,
        "before": [
          "        Error: If either radius is negative or both are zero, the height is\n",
          "            not positive, either segment count is too small, or the sweep\n",
          "            is not positive or is more than a turn.\n"
        ],
        "after": [
          "        Error: If either radius is not finite, is negative, or both are\n",
          "            zero, the height is not finite or not positive, either segment\n",
          "            count is too small, the grid has more than 16777216 cells, or\n",
          "            the sweep is not positive or is more than a turn.\n"
        ]
      },
      {
        "start": 189,
        "stop": 195,
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
        "start": 198,
        "stop": 200,
        "before": [
          "    require_positive(height.value, \"A cylinder needs a positive height\")\n"
        ],
        "after": [
          "    if not (height.value > 0):\n",
          "        raise Error(\"A cylinder needs a positive height\")\n"
        ]
      },
      {
        "start": 205,
        "stop": 210,
        "before": [],
        "after": [
          "    )\n",
          "    require_grid_cells(\n",
          "        radial_segments,\n",
          "        height_segments,\n",
          "        \"A cylinder's segment count is larger than this port builds\",\n"
        ]
      },
      {
        "start": 369,
        "stop": 371,
        "before": [
          "            count is too small, or the sweep is not positive or is more than\n",
          "            a turn.\n"
        ],
        "after": [
          "            count is too small, the grid has more than 16777216 cells, or\n",
          "            the sweep is not positive or is more than a turn.\n"
        ]
      }
    ]
  },
  "geometries/plane.mojo": {
    "before_sha256": "f5f006fb58df50e4376d6b3d90180a5497e2af42a9c4ff4b87cec34b96578956",
    "after_sha256": "bd637d96488eb38d18e68d458d7a5a45c74c90be5ba60ab6dbb1e59246dd3632",
    "before_token_sha256": "1c10fc9d0a7fdf43baca02b886ce034a50dca661debef0a8157da2aa200a756d",
    "after_token_sha256": "4feb1930135b1c09e9cdfd9f52c9f982512ecef9121231ebd293c6b5e1f5e227",
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
        "start": 39,
        "stop": 40,
        "before": [],
        "after": [
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 63,
        "stop": 66,
        "before": [
          "        Error: If either extent is not positive, or either segment count is\n",
          "            less than one.\n"
        ],
        "after": [
          "        Error: If either extent is not finite or not positive, either\n",
          "            segment count is less than one, or the grid has more than\n",
          "            16777216 cells.\n"
        ]
      },
      {
        "start": 67,
        "stop": 72,
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
      },
      {
        "start": 75,
        "stop": 80,
        "before": [],
        "after": [
          "    require_grid_cells(\n",
          "        width_segments,\n",
          "        height_segments,\n",
          "        \"A plane's segment count is larger than this port builds\",\n",
          "    )\n"
        ]
      }
    ]
  },
  "geometries/surface.mojo": {
    "before_sha256": "8ff3246d240c90168470bde485496accca02d7096a53270c0d6ce442a4429e04",
    "after_sha256": "28c95efe56afc7b247ab47ecbf93f595cfa5ccb16c3ca1ed12885daca3069dff",
    "before_token_sha256": "08d4f6b7acc5d842ae4d68c1b446c07b70a76c7ff9be350e0895964af36e26d2",
    "after_token_sha256": "82a8c4d6b71513df9861f38e8818c7d8ad53ba8846ec456913285f7822b57dc6",
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
      },
      {
        "start": 259,
        "stop": 284,
        "before": [],
        "after": [
          "\n",
          "\n",
          "# A grid past this many cells does not finish. A side past 2^24 also\n",
          "# collapses in `Float32`. 4096 by 4096 is this many cells, and so is one\n",
          "# row of 16777216.\n",
          "comptime MAX_GRID_CELLS = 16777216\n",
          "\n",
          "\n",
          "def require_grid_cells(across: Int, down: Int, message: String) raises:\n",
          "    \"\"\"Refuse a grid this port does not build.\n",
          "\n",
          "    Nothing. The call returns when the cell count fits. `across` must\n",
          "    already be at least one, so the division stands. A side of `Int.MAX`\n",
          "    wraps the extra vertex and the walk does not finish.\n",
          "\n",
          "    Args:\n",
          "        across: Cells along the first side.\n",
          "        down: Cells along the second side.\n",
          "        message: The error text for this solid.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the grid has more than 16777216 cells.\n",
          "    \"\"\"\n",
          "    if down > MAX_GRID_CELLS // across:\n",
          "        raise Error(message)\n"
        ]
      }
    ]
  },
  "lights/shadow.mojo": {
    "before_sha256": "e57aabcefe61cebaa8e57ae129f0cae3873215b7b1c0d2171c972d78d4015b81",
    "after_sha256": "36394e7969cf0f6a8647011e5d49b057440600004b35fdd97479107def5d0793",
    "before_token_sha256": "c91ae04a499fb4362157f5aa3a48a8b0cc599a85c8504efff633ac7645f3a3d9",
    "after_token_sha256": "d5290fbe9f8e613317647b54d1420af1b9b03caf6e9a51cc1c1abdeabfbf639c",
    "edits": [
      {
        "start": 163,
        "stop": 181,
        "before": [],
        "after": [
          "def _map_texels(size: Int, factor: Int) raises -> Int:\n",
          "    \"\"\"Return `factor * size * size`, or refuse a product that does not fit.\n",
          "\n",
          "    Args:\n",
          "        size: Texels a side. The caller has checked that it is positive.\n",
          "        factor: How many squares. One or more.\n",
          "\n",
          "    Returns:\n",
          "        The texel count.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the product does not fit in an integer.\n",
          "    \"\"\"\n",
          "    if size > (Int.MAX // factor) // size:\n",
          "        raise Error(\"A shadow map is larger than this port reads\")\n",
          "    return factor * size * size\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 209,
        "stop": 210,
        "before": [],
        "after": [
          "# fmt: off\n"
        ]
      },
      {
        "start": 217,
        "stop": 220,
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
        "start": 227,
        "stop": 229,
        "before": [
          ")  # fmt: skip\n"
        ],
        "after": [
          ")\n",
          "# fmt: on\n"
        ]
      },
      {
        "start": 505,
        "stop": 509,
        "before": [
          "            Error: If the size is not positive, the type is none of the\n",
          "                four, the depths do not fill the square, or two squares\n",
          "                under `VSM_SHADOW_MAP`, or the colors fill no square.\n"
        ],
        "after": [
          "            Error: If the size is not positive, the texel count does not\n",
          "                fit, the type is none of the four, the depths do not fill\n",
          "                the square, or two squares under `VSM_SHADOW_MAP`, or the\n",
          "                colors fill no square.\n"
        ]
      },
      {
        "start": 515,
        "stop": 516,
        "before": [
          "        if len(depths) != squares * size * size:\n"
        ],
        "after": [
          "        if len(depths) != _map_texels(size, squares):\n"
        ]
      },
      {
        "start": 517,
        "stop": 518,
        "before": [
          "        if len(colors) != 0 and len(colors) != 4 * size * size:\n"
        ],
        "after": [
          "        if len(colors) != 0 and len(colors) != _map_texels(size, 4):\n"
        ]
      },
      {
        "start": 574,
        "stop": 578,
        "before": [
          "            Error: If the size is not positive, the type is none of the\n",
          "                four, the depths or the colors do not fill six squares, or\n",
          "                the far plane does not lie beyond the near plane.\n"
        ],
        "after": [
          "            Error: If the size is not positive, the texel count does not\n",
          "                fit, the type is none of the four, the depths or the colors\n",
          "                do not fill six squares, or the far plane does not lie\n",
          "                beyond the near plane.\n"
        ]
      },
      {
        "start": 581,
        "stop": 582,
        "before": [
          "        if len(depths) != CUBE_FACES * size * size:\n"
        ],
        "after": [
          "        if len(depths) != _map_texels(size, CUBE_FACES):\n"
        ]
      },
      {
        "start": 583,
        "stop": 586,
        "before": [
          "        if len(colors) != 0 and len(colors) != 4 * CUBE_FACES * size * size:\n"
        ],
        "after": [
          "        if len(colors) != 0 and len(colors) != _map_texels(\n",
          "            size, 4 * CUBE_FACES\n",
          "        ):\n"
        ]
      },
      {
        "start": 1291,
        "stop": 1329,
        "before": [],
        "after": [
          "def _shadow_index(value: Float32) -> Int:\n",
          "    \"\"\"Return the floor of a shadow-map coordinate.\n",
          "\n",
          "    A value that is not finite, or that does not fit in an integer, lies\n",
          "    past the map. `Int` of such a float is not that texel.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate, in texels.\n",
          "\n",
          "    Returns:\n",
          "        The floor, or `Int.MAX` or `Int.MIN` when `value` does not fit.\n",
          "    \"\"\"\n",
          "    # `Float32(Int.MAX)` is 2^63, as `Float64(Int.MAX)` is, and the floor\n",
          "    # of a `Float32` is a `Float32`: the same test and index without\n",
          "    # `Float64`, which a Metal kernel cannot run.\n",
          "    if not isfinite(value) or value >= Float32(Int.MAX):\n",
          "        return Int.MAX\n",
          "    if value <= -Float32(Int.MAX):\n",
          "        return Int.MIN\n",
          "    return Int(floor(value))\n",
          "\n",
          "\n",
          "def _shifted_shadow_index(value: Float32, shift: Int) -> Int:\n",
          "    \"\"\"Return `_shadow_index` moved by `shift` without wrapping.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate, in texels.\n",
          "        shift: Texels to add. A sentinel is left where it is.\n",
          "\n",
          "    Returns:\n",
          "        The shifted index, held at `Int.MAX` or `Int.MIN`.\n",
          "    \"\"\"\n",
          "    var index = _shadow_index(value)\n",
          "    if index == Int.MAX or index == Int.MIN:\n",
          "        return index\n",
          "    return index + shift\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 1347,
        "stop": 1351,
        "before": [
          "    var column = Int(floor(place.x * Float32(size) + 0.5)) + tap % 4 - 2\n",
          "    var row = Int(floor(place.y * Float32(size) + 0.5)) + tap // 4 - 2\n"
        ],
        "after": [
          "    var column = _shifted_shadow_index(\n",
          "        place.x * Float32(size) + 0.5, tap % 4 - 2\n",
          "    )\n",
          "    var row = _shifted_shadow_index(place.y * Float32(size) + 0.5, tap // 4 - 2)\n"
        ]
      },
      {
        "start": 1366,
        "stop": 1368,
        "before": [],
        "after": [
          "    if not isfinite(texels):\n",
          "        return Float32(0)\n"
        ]
      },
      {
        "start": 1426,
        "stop": 1428,
        "before": [
          "    var column = Int(floor(across - 0.5)) + corner % 2\n",
          "    var row = Int(floor(down - 0.5)) + corner // 2\n"
        ],
        "after": [
          "    var column = _shifted_shadow_index(across - 0.5, corner % 2)\n",
          "    var row = _shifted_shadow_index(down - 0.5, corner // 2)\n"
        ]
      },
      {
        "start": 1441,
        "stop": 1445,
        "before": [
          "    return fraction(at - 0.5)\n"
        ],
        "after": [
          "    var past = at - 0.5\n",
          "    if not isfinite(past):\n",
          "        return Float32(0)\n",
          "    return fraction(past)\n"
        ]
      },
      {
        "start": 1532,
        "stop": 1533,
        "before": [
          ") -> List[Float32]:\n"
        ],
        "after": [
          ") raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 1553,
        "stop": 1557,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the size is below one, two squares do not fit, the\n",
          "            depths do not fill one square, or there is no sample.\n"
        ]
      },
      {
        "start": 1558,
        "stop": 1563,
        "before": [
          "    # `LightShadow.validate` holds the size and the samples at one or\n",
          "    # more, so no loop below runs zero times.\n"
        ],
        "after": [
          "    require_shadow_size(size)\n",
          "    if samples < 1:\n",
          "        raise Error(\"A variance map takes at least one sample\")\n",
          "    # Two squares are stored: the means and the spreads.\n",
          "    _ = _map_texels(size, 2)\n"
        ]
      },
      {
        "start": 1564,
        "stop": 1566,
        "before": [],
        "after": [
          "    if len(depths) != square:\n",
          "        raise Error(\"A variance map's depths must fill its square\")\n"
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
  "objects/gaussian_splat.mojo": {
    "before_sha256": "01fe94cc3159b21a70c104ea92a3631e57c217f19ad26f17bd2bd3ad3ff0f80f",
    "after_sha256": "6b5834369f244c8eaf6a4a6d363bcca7f645a4964f72ddea25df62f63097cf3c",
    "before_token_sha256": "ba6d8c9dc92963163d2d47f69c5ddb8f0c1e312ee202f941e5efcb4ebdc6e347",
    "after_token_sha256": "73030c3daaa18367bf29232d859f5e6a3774ba0cd6a1ed0230fa6072b1bb1dd8",
    "edits": [
      {
        "start": 27,
        "stop": 30,
        "before": [
          "  furthest first.\n"
        ],
        "after": [
          "  furthest first. Workers share a large sort out in runs of the splats;\n",
          "  each run counts its bins, and places its splats after the earlier runs'\n",
          "  in each bin. So the order is the same for any count of workers.\n"
        ]
      },
      {
        "start": 54,
        "stop": 55,
        "before": [],
        "after": [
          "from render.tasks import TaskGroup\n"
        ]
      },
      {
        "start": 72,
        "stop": 207,
        "before": [],
        "after": [
          "comptime SORT_RUN = 16384\n",
          "\"\"\"The fewest splats a sort worker takes: a shorter run is not worth a task.\"\"\"\n",
          "\n",
          "\n",
          "@fieldwise_init\n",
          "struct _SortKey(ImplicitlyCopyable):\n",
          "    \"\"\"What `sort_bin` reads of the view, so that a worker reads no splat\n",
          "    object.\"\"\"\n",
          "\n",
          "    var m2: Float64\n",
          "    \"\"\"The sort matrix's element 2.\"\"\"\n",
          "    var m6: Float64\n",
          "    \"\"\"Its element 6.\"\"\"\n",
          "    var m10: Float64\n",
          "    \"\"\"Its element 10.\"\"\"\n",
          "    var m14: Float64\n",
          "    \"\"\"Its element 14.\"\"\"\n",
          "    var near: Float64\n",
          "    \"\"\"The nearest depth the bins span.\"\"\"\n",
          "    var scale: Float64\n",
          "    \"\"\"Bins a unit of depth.\"\"\"\n",
          "\n",
          "    def bin(self, x: Float32, y: Float32, z: Float32) -> Int:\n",
          "        \"\"\"Return the bin of a center; see `GaussianSplat.sort_bin`.\n",
          "\n",
          "        Args:\n",
          "            x: The center's x, in the object's space.\n",
          "            y: Its y.\n",
          "            z: Its z.\n",
          "\n",
          "        Returns:\n",
          "            0 for the furthest depths up to `BIN_COUNT - 1` for the\n",
          "            nearest.\n",
          "        \"\"\"\n",
          "        var depth = -(\n",
          "            self.m2 * Float64(x)\n",
          "            + self.m6 * Float64(y)\n",
          "            + self.m10 * Float64(z)\n",
          "            + self.m14\n",
          "        )\n",
          "        var bin = min(\n",
          "            Float64(BIN_COUNT - 1),\n",
          "            max(Float64(0), floor((depth - self.near) * self.scale)),\n",
          "        )\n",
          "        return BIN_COUNT - 1 - Int(bin)\n",
          "\n",
          "\n",
          "def _count_bins(\n",
          "    centers: MutPointer[Float32, MutAnyOrigin],\n",
          "    key: _SortKey,\n",
          "    bins: MutPointer[UInt16, MutAnyOrigin],\n",
          "    counts: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"Find the bins of a run of splats, and count them.\n",
          "\n",
          "    Args:\n",
          "        centers: The splats' centers, three floats a splat.\n",
          "        key: The view.\n",
          "        bins: Each splat's bin, written for the run.\n",
          "        counts: The run's count of each bin.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    for index in range(first, past):\n",
          "        var bin = key.bin(\n",
          "            centers[unsafe_offset=index * 3],\n",
          "            centers[unsafe_offset=index * 3 + 1],\n",
          "            centers[unsafe_offset=index * 3 + 2],\n",
          "        )\n",
          "        bins[unsafe_offset=index] = UInt16(bin)\n",
          "        counts[unsafe_offset=bin] += 1\n",
          "\n",
          "\n",
          "__async def _count_task(\n",
          "    centers: MutPointer[Float32, MutAnyOrigin],\n",
          "    key: _SortKey,\n",
          "    bins: MutPointer[UInt16, MutAnyOrigin],\n",
          "    counts: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_count_bins` as a task of `GaussianSplat.sort_cpu`.\n",
          "\n",
          "    Args:\n",
          "        centers: The splats' centers.\n",
          "        key: The view.\n",
          "        bins: Each splat's bin.\n",
          "        counts: The run's counts.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    _count_bins(centers, key, bins, counts, first, past)\n",
          "\n",
          "\n",
          "def _place_bins(\n",
          "    order: MutPointer[Int, MutAnyOrigin],\n",
          "    bins: MutPointer[UInt16, MutAnyOrigin],\n",
          "    offsets: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"Place a run of splats in the order, each at its bin's next place.\n",
          "\n",
          "    Args:\n",
          "        order: The draw order.\n",
          "        bins: Each splat's bin.\n",
          "        offsets: The run's next place in each bin.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    for index in range(first, past):\n",
          "        var bin = Int(bins[unsafe_offset=index])\n",
          "        order[unsafe_offset=offsets[unsafe_offset=bin]] = index\n",
          "        offsets[unsafe_offset=bin] += 1\n",
          "\n",
          "\n",
          "__async def _place_task(\n",
          "    order: MutPointer[Int, MutAnyOrigin],\n",
          "    bins: MutPointer[UInt16, MutAnyOrigin],\n",
          "    offsets: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_place_bins` as a task of `GaussianSplat.sort_cpu`.\n",
          "\n",
          "    Args:\n",
          "        order: The draw order.\n",
          "        bins: Each splat's bin.\n",
          "        offsets: The run's next places.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    _place_bins(order, bins, offsets, first, past)\n"
        ]
      },
      {
        "start": 666,
        "stop": 671,
        "before": [
          "        mut self, world: Matrix4, view: Matrix4, near: Length\n"
        ],
        "after": [
          "        mut self,\n",
          "        world: Matrix4,\n",
          "        view: Matrix4,\n",
          "        near: Length,\n",
          "        workers: Int = 1,\n"
        ]
      },
      {
        "start": 680,
        "stop": 681,
        "before": [],
        "after": [
          "            workers: How many threads sort; see `sort_cpu`.\n"
        ]
      },
      {
        "start": 693,
        "stop": 694,
        "before": [
          "        self.sort_cpu()\n"
        ],
        "after": [
          "        self.sort_cpu(workers)\n"
        ]
      },
      {
        "start": 744,
        "stop": 755,
        "before": [],
        "after": [
          "        ref c = self.splat_geometry.centers\n",
          "        return self._sort_key().bin(\n",
          "            c[index * 3], c[index * 3 + 1], c[index * 3 + 2]\n",
          "        )\n",
          "\n",
          "    def _sort_key(self) -> _SortKey:\n",
          "        \"\"\"Return what `sort_bin` reads of the view.\n",
          "\n",
          "        Returns:\n",
          "            The sort matrix's depth row, and the bins' near depth and scale.\n",
          "        \"\"\"\n"
        ]
      },
      {
        "start": 756,
        "stop": 764,
        "before": [
          "        ref c = self.splat_geometry.centers\n",
          "        var depth = -(\n",
          "            Float64(m[2]) * Float64(c[index * 3])\n",
          "            + Float64(m[6]) * Float64(c[index * 3 + 1])\n",
          "            + Float64(m[10]) * Float64(c[index * 3 + 2])\n",
          "            + Float64(m[14])\n"
        ],
        "after": [
          "        var span = max(self.sort_far - self.sort_near, MIN_SORT_RANGE)\n",
          "        return _SortKey(\n",
          "            Float64(m[2]),\n",
          "            Float64(m[6]),\n",
          "            Float64(m[10]),\n",
          "            Float64(m[14]),\n",
          "            self.sort_near,\n",
          "            Float64(BIN_COUNT - 1) / span,\n"
        ]
      },
      {
        "start": 765,
        "stop": 783,
        "before": [
          "        var span = max(self.sort_far - self.sort_near, MIN_SORT_RANGE)\n",
          "        var scale = Float64(BIN_COUNT - 1) / span\n",
          "        var bin = min(\n",
          "            Float64(BIN_COUNT - 1),\n",
          "            max(Float64(0), floor((depth - self.sort_near) * scale)),\n"
        ],
        "after": [
          "\n",
          "    def sort_cpu(mut self, workers: Int = 1):\n",
          "        \"\"\"Sort the splats by `sort_bin`, stably, into `order`: three.js's\n",
          "        `CountingSort.computeCPU`.\n",
          "\n",
          "        Args:\n",
          "            workers: How many threads sort. Each takes a run of at least\n",
          "                `SORT_RUN` splats. The order is the same for any count.\n",
          "        \"\"\"\n",
          "        var count = self.count()\n",
          "        var runs = max(1, min(workers, count // SORT_RUN))\n",
          "        var key = self._sort_key()\n",
          "        var bins = List[UInt16](length=count, fill=0)\n",
          "        var counts = List[Int](length=runs * BIN_COUNT, fill=0)\n",
          "        var centers = (\n",
          "            self.splat_geometry.centers.unsafe_ptr().unsafe_origin_cast[\n",
          "                MutAnyOrigin\n",
          "            ]()\n"
        ]
      },
      {
        "start": 784,
        "stop": 803,
        "before": [
          "        return BIN_COUNT - 1 - Int(bin)\n",
          "\n",
          "    def sort_cpu(mut self):\n",
          "        \"\"\"Sort the splats by `sort_bin`, stably, into `order`: three.js's\n",
          "        `CountingSort.computeCPU`.\"\"\"\n",
          "        var count = self.count()\n",
          "        var bins = List[Int](capacity=count)\n",
          "        var counts = List[Int](length=BIN_COUNT, fill=0)\n",
          "        for index in range(count):\n",
          "            var bin = self.sort_bin(index)\n",
          "            bins.append(bin)\n",
          "            counts[bin] += 1\n",
          "        var offsets = List[Int](length=BIN_COUNT, fill=0)\n"
        ],
        "after": [
          "        var bin_at = bins.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "        var count_at = counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "        if runs == 1:\n",
          "            _count_bins(centers, key, bin_at, count_at, 0, count)\n",
          "        else:\n",
          "            var group = TaskGroup()\n",
          "            for run in range(runs):  # pragma: no branch\n",
          "                group.create_task(\n",
          "                    _count_task(\n",
          "                        centers,\n",
          "                        key,\n",
          "                        bin_at,\n",
          "                        count_at.unsafe_offset(run * BIN_COUNT),\n",
          "                        run * count // runs,\n",
          "                        (run + 1) * count // runs,\n",
          "                    )\n",
          "                )\n",
          "            group.wait()\n",
          "        # Each run's first place in each bin: bin by bin, run by run.\n"
        ]
      },
      {
        "start": 805,
        "stop": 832,
        "before": [
          "            offsets[bin] = sum\n",
          "            sum += counts[bin]\n",
          "        for index in range(count):\n",
          "            self.order[offsets[bins[index]]] = index\n",
          "            offsets[bins[index]] += 1\n"
        ],
        "after": [
          "            for run in range(runs):  # pragma: no branch\n",
          "                var here = counts[run * BIN_COUNT + bin]\n",
          "                counts[run * BIN_COUNT + bin] = sum\n",
          "                sum += here\n",
          "        var order_at = self.order.unsafe_ptr().unsafe_origin_cast[\n",
          "            MutAnyOrigin\n",
          "        ]()\n",
          "        if runs == 1:\n",
          "            _place_bins(order_at, bin_at, count_at, 0, count)\n",
          "        else:\n",
          "            var group = TaskGroup()\n",
          "            for run in range(runs):  # pragma: no branch\n",
          "                group.create_task(\n",
          "                    _place_task(\n",
          "                        order_at,\n",
          "                        bin_at,\n",
          "                        count_at.unsafe_offset(run * BIN_COUNT),\n",
          "                        run * count // runs,\n",
          "                        (run + 1) * count // runs,\n",
          "                    )\n",
          "                )\n",
          "            group.wait()\n",
          "        # The tasks reach the lists through pointers the compiler cannot\n",
          "        # see. These reads keep them alive until every task has finished.\n",
          "        _ = len(bins)\n",
          "        _ = len(counts)\n",
          "        _ = len(self.splat_geometry.centers)\n"
        ]
      },
      {
        "start": 850,
        "stop": 853,
        "before": [
          "            var direction = self._center(index) - camera\n",
          "            direction.normalize()\n",
          "            ref g = self.splat_geometry\n",
          "            var rgb = _band_sum(g.sh1, index, 1, direction)\n",
          "            if degree >= 2:\n",
          "                rgb = rgb + _band_sum(g.sh2, index, 2, direction)\n",
          "            if degree >= 3:\n",
          "                rgb = rgb + _band_sum(g.sh3, index, 3, direction)\n",
          "            append_vector3(out, rgb)\n"
        ],
        "after": [
          "            append_vector3(\n",
          "                out, self.spherical_harmonics_color(index, camera, degree)\n",
          "            )\n"
        ]
      },
      {
        "start": 854,
        "stop": 878,
        "before": [],
        "after": [
          "\n",
          "    def spherical_harmonics_color(\n",
          "        self, index: Int, camera: Vector3, degree: Int\n",
          "    ) -> Vector3:\n",
          "        \"\"\"Return one splat's view-dependent color, as\n",
          "        `spherical_harmonics_colors` gives it.\n",
          "\n",
          "        Args:\n",
          "            index: Which splat.\n",
          "            camera: The camera's position, in the object's space.\n",
          "            degree: The splats' degree, 1 through 3.\n",
          "\n",
          "        Returns:\n",
          "            The three floats added to the splat's color.\n",
          "        \"\"\"\n",
          "        var direction = self._center(index) - camera\n",
          "        direction.normalize()\n",
          "        ref g = self.splat_geometry\n",
          "        var rgb = _band_sum(g.sh1, index, 1, direction)\n",
          "        if degree >= 2:\n",
          "            rgb = rgb + _band_sum(g.sh2, index, 2, direction)\n",
          "        if degree >= 3:\n",
          "            rgb = rgb + _band_sum(g.sh3, index, 3, direction)\n",
          "        return rgb\n"
        ]
      },
      {
        "start": 897,
        "stop": 898,
        "before": [
          "def _weights(degree: Int, d: Vector3) -> List[Float32]:\n"
        ],
        "after": [
          "def _weights(degree: Int, d: Vector3) -> SIMD[DType.float32, 8]:\n"
        ]
      },
      {
        "start": 900,
        "stop": 902,
        "before": [],
        "after": [
          "\n",
          "    The weights are lanes of one vector, so that no splat allocates.\n"
        ]
      },
      {
        "start": 908,
        "stop": 909,
        "before": [
          "        `2 degree + 1` weights.\n"
        ],
        "after": [
          "        `2 degree + 1` weights in the first lanes, and zeros after them.\n"
        ]
      },
      {
        "start": 913,
        "stop": 914,
        "before": [],
        "after": [
          "    var w = SIMD[DType.float32, 8](0)\n"
        ]
      },
      {
        "start": 915,
        "stop": 919,
        "before": [
          "        return [y * -0.4886025, z * 0.4886025, x * -0.4886025]\n"
        ],
        "after": [
          "        w[0] = y * -0.4886025\n",
          "        w[1] = z * 0.4886025\n",
          "        w[2] = x * -0.4886025\n",
          "        return w\n"
        ]
      },
      {
        "start": 923,
        "stop": 929,
        "before": [
          "        return [\n",
          "            x * y * 1.0925484,\n",
          "            y * z * -1.0925484,\n",
          "            (zz * 2 - xx - yy) * 0.3153915,\n",
          "            x * z * -1.0925484,\n",
          "            (xx - yy) * 0.5462742,\n",
          "        ]\n"
        ],
        "after": [
          "        w[0] = x * y * 1.0925484\n",
          "        w[1] = y * z * -1.0925484\n",
          "        w[2] = (zz * 2 - xx - yy) * 0.3153915\n",
          "        w[3] = x * z * -1.0925484\n",
          "        w[4] = (xx - yy) * 0.5462742\n",
          "        return w\n"
        ]
      },
      {
        "start": 930,
        "stop": 938,
        "before": [
          "    return [\n",
          "        y * (xx * 3 - yy) * -0.5900436,\n",
          "        xy * z * 2.8906114,\n",
          "        y * (zz * 4 - xx - yy) * -0.4570458,\n",
          "        z * (zz * 2 - xx * 3 - yy * 3) * 0.3731763,\n",
          "        x * (zz * 4 - xx - yy) * -0.4570458,\n",
          "        z * (xx - yy) * 1.4453057,\n",
          "        x * (xx - yy * 3) * -0.5900436,\n",
          "    ]\n"
        ],
        "after": [
          "    w[0] = y * (xx * 3 - yy) * -0.5900436\n",
          "    w[1] = xy * z * 2.8906114\n",
          "    w[2] = y * (zz * 4 - xx - yy) * -0.4570458\n",
          "    w[3] = z * (zz * 2 - xx * 3 - yy * 3) * 0.3731763\n",
          "    w[4] = x * (zz * 4 - xx - yy) * -0.4570458\n",
          "    w[5] = z * (xx - yy) * 1.4453057\n",
          "    w[6] = x * (xx - yy * 3) * -0.5900436\n",
          "    return w\n"
        ]
      },
      {
        "start": 956,
        "stop": 957,
        "before": [],
        "after": [
          "    var coefficients = degree * 2 + 1\n"
        ]
      },
      {
        "start": 958,
        "stop": 961,
        "before": [
          "    var words = (len(weights) * 3 + 3) // 4\n",
          "    var start = index * words * 4\n"
        ],
        "after": [
          "    var words = (coefficients * 3 + 3) // 4\n",
          "    # The caller's index is a splat of `band`, so its bytes are in range.\n",
          "    var bytes = band.unsafe_ptr().unsafe_offset(index * words * 4)\n"
        ]
      },
      {
        "start": 962,
        "stop": 967,
        "before": [
          "    for k in range(len(weights)):  # pragma: no branch\n",
          "        var at = start + k * 3\n",
          "        sum.x += (Float32(band[at]) - 128) / 128 * weights[k]\n",
          "        sum.y += (Float32(band[at + 1]) - 128) / 128 * weights[k]\n",
          "        sum.z += (Float32(band[at + 2]) - 128) / 128 * weights[k]\n"
        ],
        "after": [
          "    for k in range(coefficients):  # pragma: no branch\n",
          "        var at = k * 3\n",
          "        sum.x += (Float32(bytes[unsafe_offset=at]) - 128) / 128 * weights[k]\n",
          "        sum.y += (Float32(bytes[unsafe_offset=at + 1]) - 128) / 128 * weights[k]\n",
          "        sum.z += (Float32(bytes[unsafe_offset=at + 2]) - 128) / 128 * weights[k]\n"
        ]
      }
    ]
  },
  "postprocessing/denoise.mojo": {
    "before_sha256": "0cc2fa358a413e982da70aafbf082c5cde41b1105c98cc3770f3d2149d1f0664",
    "after_sha256": "752761528fcd47de2252b8f7b8a6cd937cd562c445c46936c76e908fc428ca34",
    "before_token_sha256": "3c24d8a6900fb93334b719698dc563ce3d989fb7af36c8cba5e0f49333b1745e",
    "after_token_sha256": "7e3f8df77ad88974527a63da4639fb779a74822bb8b7e1f9f56461f7f8ddd0d4",
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
        "start": 103,
        "stop": 104,
        "before": [
          ") -> FloatColor:\n"
        ],
        "after": [
          ") raises -> FloatColor:\n"
        ]
      },
      {
        "start": 120,
        "stop": 123,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a surface pixel reads noise shorter than a 64 by 64 grid.\n"
        ]
      },
      {
        "start": 133,
        "stop": 135,
        "before": [],
        "after": [
          "    # The node turns the disk with a 64 by 64 noise texture. A shorter\n",
          "    # list would read past its last texel.\n"
        ]
      },
      {
        "start": 136,
        "stop": 138,
        "before": [],
        "after": [
          "    if len(noise) < side * side:\n",
          "        raise Error(\"Denoise noise must cover a 64 by 64 grid\")\n"
        ]
      },
      {
        "start": 139,
        "stop": 140,
        "before": [],
        "after": [
          "    # r186's node reads channel zero as radians, unlike the WebGL shader.\n"
        ]
      },
      {
        "start": 150,
        "stop": 157,
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
    "after_sha256": "27ddb80f3915f1a76797029bba82fbd9b0b94b749e7a82d604a05f2632f6a8ed",
    "before_token_sha256": "49c113f28ee16d52cbbb50c6f93b18902581fde0c15cede8634e71dfb64e16d0",
    "after_token_sha256": "d1583719b722dd15129d6fc7b3b0d36e3f10816bfa7a06af90ea53adc5c9fcb3",
    "edits": [
      {
        "start": 17,
        "stop": 19,
        "before": [
          "of several hundred triangles made that difference impossible to ignore.\n"
        ],
        "after": [
          "of several hundred triangles made that difference impossible to ignore. A\n",
          "screen coordinate that does not fit in an integer lies past the image.\n"
        ]
      },
      {
        "start": 299,
        "stop": 313,
        "before": [],
        "after": [
          "        # A corner that is not finite snaps to some grid point, which can\n",
          "        # give the triangle an area. It covers no pixel.\n",
          "        var corners = SIMD[DType.float32, 8](\n",
          "            triangle.a.x,\n",
          "            triangle.a.y,\n",
          "            triangle.b.x,\n",
          "            triangle.b.y,\n",
          "            triangle.c.x,\n",
          "            triangle.c.y,\n",
          "            0,\n",
          "            0,\n",
          "        )\n",
          "        if not isfinite(corners).reduce_and():\n",
          "            area = 0\n"
        ]
      },
      {
        "start": 480,
        "stop": 525,
        "before": [],
        "after": [
          "def _screen_index(value: Float32, round_up: Bool) -> Int:\n",
          "    \"\"\"Return the pixel index of a screen coordinate.\n",
          "\n",
          "    A value that is not finite, or that does not fit in an integer, is\n",
          "    past every pixel: positive past the last, negative before the first.\n",
          "    `Int` of such a float is not that coordinate.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate, in pixels.\n",
          "        round_up: True to round toward positive infinity.\n",
          "\n",
          "    Returns:\n",
          "        The index, or `Int.MAX` or `Int.MIN` when `value` does not fit.\n",
          "    \"\"\"\n",
          "    # `Float32(Int.MAX)` is 2^63, as `Float64(Int.MAX)` is, and the floor\n",
          "    # of a `Float32` is a `Float32`: the same test and index without\n",
          "    # `Float64`, which a Metal kernel cannot run.\n",
          "    if not isfinite(value) or value >= Float32(Int.MAX):\n",
          "        return Int.MAX\n",
          "    if value <= -Float32(Int.MAX):\n",
          "        return Int.MIN\n",
          "    if round_up:\n",
          "        return Int(ceil(value))\n",
          "    return Int(floor(value))\n",
          "\n",
          "\n",
          "def _shifted_index(value: Float32, round_up: Bool, pad: Int) -> Int:\n",
          "    \"\"\"Return `_screen_index` moved by `pad` without wrapping.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate, in pixels.\n",
          "        round_up: True to round toward positive infinity.\n",
          "        pad: Rows to add when rounding up, or to subtract otherwise.\n",
          "\n",
          "    Returns:\n",
          "        The shifted index, held at `Int.MAX` or `Int.MIN`.\n",
          "    \"\"\"\n",
          "    var index = _screen_index(value, round_up)\n",
          "    if index == Int.MAX or index == Int.MIN or pad == 0:\n",
          "        return index\n",
          "    if round_up:\n",
          "        return index + pad\n",
          "    return index - pad\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 554,
        "stop": 558,
        "before": [
          "        max(0, Int(floor(left))),\n",
          "        min(width - 1, Int(ceil(right))),\n",
          "        max(first_row, Int(floor(top))),\n",
          "        min(lowest, Int(ceil(bottom))),\n"
        ],
        "after": [
          "        max(0, _screen_index(left, False)),\n",
          "        min(width - 1, _screen_index(right, True)),\n",
          "        max(first_row, _screen_index(top, False)),\n",
          "        min(lowest, _screen_index(bottom, True)),\n"
        ]
      },
      {
        "start": 3589,
        "stop": 3590,
        "before": [],
        "after": [
          "    tones.reserve(image.width)\n"
        ]
      },
      {
        "start": 7276,
        "stop": 7278,
        "before": [
          "        rows.append(Int(floor(top)) - pad)\n",
          "        rows.append(Int(ceil(bottom)) + pad)\n"
        ],
        "after": [
          "        rows.append(_shifted_index(top, False, pad))\n",
          "        rows.append(_shifted_index(bottom, True, pad))\n"
        ]
      },
      {
        "start": 7297,
        "stop": 7299,
        "before": [
          "        rows.append(Int(floor(points[index].y - half)))\n",
          "        rows.append(Int(ceil(points[index].y + half)))\n"
        ],
        "after": [
          "        rows.append(_screen_index(points[index].y - half, False))\n",
          "        rows.append(_screen_index(points[index].y + half, True))\n"
        ]
      },
      {
        "start": 7317,
        "stop": 7318,
        "before": [
          "async def _frame_band(\n"
        ],
        "after": [
          "__async def _frame_band(\n"
        ]
      },
      {
        "start": 7518,
        "stop": 7520,
        "before": [
          "        rows.append(Int(floor(top)))\n",
          "        rows.append(Int(ceil(bottom)))\n"
        ],
        "after": [
          "        rows.append(_screen_index(top, False))\n",
          "        rows.append(_screen_index(bottom, True))\n"
        ]
      }
    ]
  },
  "render/splat_raster.mojo": {
    "before_sha256": "5ec9036208ec0d16e12f078a99a49e2ecba067075fda893bc74810ee9c7c119b",
    "after_sha256": "b04a3a48443dcf175246d60fa27735d1780f6abf44103ee779fe7aba99734c7d",
    "before_token_sha256": "45395f0b57e02961ae691bdc96474e37caa9ac519e7348f8dd8537717008e5d3",
    "after_token_sha256": "d381c6315e1af0718cf53dd1a009e7b8d9300f71d3522c3c46f73e337772a845",
    "edits": [
      {
        "start": 19,
        "stop": 20,
        "before": [
          "front of it.\n"
        ],
        "after": [
          "front of it. A center that does not fit in an integer lies past the image.\n"
        ]
      },
      {
        "start": 30,
        "stop": 40,
        "before": [],
        "after": [
          "\n",
          "**Workers.** Each step takes a count of workers, one by default. The\n",
          "sort and the projection share the splats out in runs. The projection\n",
          "reads the splats in their own order, front to back, and then gathers them\n",
          "in draw order. The fill shares the rows out in bands. It sorts the splats\n",
          "by the bands their rows reach, keeping draw order in each band, and every\n",
          "band blends its own splats in that order. So each pixel takes the same\n",
          "blends in the same order as on one thread, and the picture is the same to\n",
          "the bit. A row of a splat visits only the columns of its disc;\n",
          "`splat_row_span` says why that draws what the whole box draws.\n"
        ]
      },
      {
        "start": 51,
        "stop": 53,
        "before": [],
        "after": [
          "    SPLAT_LANES,\n",
          "    SPLAT_RADIUS_SQ,\n"
        ]
      },
      {
        "start": 55,
        "stop": 56,
        "before": [
          "    splat_alpha,\n"
        ],
        "after": [
          "    splat_alphas,\n"
        ]
      },
      {
        "start": 61,
        "stop": 63,
        "before": [
          "from std.math import ceil, floor, max, min\n"
        ],
        "after": [
          "from render.tasks import TaskGroup\n",
          "from std.math import ceil, floor, fma, isfinite, max, min, sqrt\n"
        ]
      },
      {
        "start": 65,
        "stop": 78,
        "before": [],
        "after": [
          "\n",
          "comptime SPLAT_BANDS_PER_WORKER = 8\n",
          "\"\"\"How many bands of rows a fill worker has: a scan's splats crowd some rows, and more bands than workers share them out evenly.\"\"\"\n",
          "comptime SPLAT_RUN = 4096\n",
          "\"\"\"The fewest splats a projection worker takes: a shorter run is not worth a task.\"\"\"\n",
          "comptime SPLAT_ROW_SLACK = Float64(1e-6)\n",
          "\"\"\"How much taller, as a share, the rows that `splat_disc_rows` keeps are\n",
          "than the disc: more than the rounding of `splat_row_span`'s `Float64`\n",
          "discriminant.\"\"\"\n",
          "comptime SPLAT_SPAN_SLACK = Float64(1e-4)\n",
          "\"\"\"How much wider, as a share of `SPLAT_RADIUS_SQ`, the disc whose row\n",
          "spans `splat_row_span` finds is: far more than the rounding of\n",
          "`splat_alpha`'s `Float32` arithmetic.\"\"\"\n"
        ]
      },
      {
        "start": 106,
        "stop": 107,
        "before": [],
        "after": [
          "    workers: Int = 1,\n"
        ]
      },
      {
        "start": 109,
        "stop": 112,
        "before": [],
        "after": [
          "\n",
          "    Parameters:\n",
          "        C: The camera's type.\n"
        ]
      },
      {
        "start": 122,
        "stop": 124,
        "before": [],
        "after": [
          "        workers: How many threads sort and project the splats; see the\n",
          "            module docstring.\n"
        ]
      },
      {
        "start": 144,
        "stop": 145,
        "before": [
          "            world, view, Length(camera.near_distance(), METER)\n"
        ],
        "after": [
          "            world, view, Length(camera.near_distance(), METER), workers\n"
        ]
      },
      {
        "start": 153,
        "stop": 153,
        "before": [
          "    var shading = splat.spherical_harmonics_colors(eye)\n",
          "    var shaded = len(shading) > 0\n"
        ],
        "after": []
      },
      {
        "start": 161,
        "stop": 276,
        "before": [],
        "after": [
          "    var run = _SplatRun(\n",
          "        place,\n",
          "        eye,\n",
          "        splat.splat_geometry.spherical_harmonics_degree(),\n",
          "        Float32(rect.x),\n",
          "        Float32(rect.top(height)),\n",
          "    )\n",
          "    var count = len(splat.order)\n",
          "    var tasks = max(1, min(workers, count // SPLAT_RUN))\n",
          "    # Project the splats in their own order, so that their arrays are read\n",
          "    # front to back, and then gather them in draw order.\n",
          "    var projected = List[ProjectedSplat](capacity=count)\n",
          "    projected.resize(unsafe_uninit_length=count)\n",
          "    var shown = List[Bool](length=count, fill=False)\n",
          "    var projected_at = projected.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    var shown_at = shown.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    var order_at = splat.order.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    var starts = List[Int](length=tasks + 1, fill=0)\n",
          "    if tasks == 1:\n",
          "        _project_span(projected_at, shown_at, splat, run, 0, count)\n",
          "        starts[1] = _shown_count(order_at, shown_at, 0, count)\n",
          "    else:\n",
          "        var group = TaskGroup()\n",
          "        for task in range(tasks):  # pragma: no branch\n",
          "            group.create_task(\n",
          "                _project_task(\n",
          "                    projected_at,\n",
          "                    shown_at,\n",
          "                    Pointer(to=splat).unsafe_origin_cast[MutAnyOrigin](),\n",
          "                    Pointer(to=run).unsafe_origin_cast[MutAnyOrigin](),\n",
          "                    task * count // tasks,\n",
          "                    (task + 1) * count // tasks,\n",
          "                )\n",
          "            )\n",
          "        group.wait()\n",
          "        var counting = TaskGroup()\n",
          "        for task in range(tasks):  # pragma: no branch\n",
          "            counting.create_task(\n",
          "                _count_task(\n",
          "                    starts.unsafe_ptr()\n",
          "                    .unsafe_offset(task + 1)\n",
          "                    .unsafe_origin_cast[MutAnyOrigin](),\n",
          "                    order_at,\n",
          "                    shown_at,\n",
          "                    task * count // tasks,\n",
          "                    (task + 1) * count // tasks,\n",
          "                )\n",
          "            )\n",
          "        counting.wait()\n",
          "    for task in range(tasks):  # pragma: no branch\n",
          "        starts[task + 1] += starts[task]\n",
          "    out.resize(unsafe_uninit_length=starts[tasks])\n",
          "    var out_at = out.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    if tasks == 1:\n",
          "        _gather(out_at, order_at, shown_at, projected_at, 0, count)\n",
          "    else:\n",
          "        var gathering = TaskGroup()\n",
          "        for task in range(tasks):  # pragma: no branch\n",
          "            gathering.create_task(\n",
          "                _gather_task(\n",
          "                    out_at.unsafe_offset(starts[task]),\n",
          "                    order_at,\n",
          "                    shown_at,\n",
          "                    projected_at,\n",
          "                    task * count // tasks,\n",
          "                    (task + 1) * count // tasks,\n",
          "                )\n",
          "            )\n",
          "        gathering.wait()\n",
          "    # The tasks reach the lists, `splat` and `run` through pointers the\n",
          "    # compiler cannot see. These reads keep them alive until every task\n",
          "    # has finished.\n",
          "    _ = len(projected)\n",
          "    _ = len(shown)\n",
          "    _ = len(splat.order)\n",
          "    _ = len(starts)\n",
          "    _ = run.degree\n",
          "    return out^\n",
          "\n",
          "\n",
          "@fieldwise_init\n",
          "struct _SplatRun(ImplicitlyCopyable):\n",
          "    \"\"\"What projecting a run of the draw order needs of the view.\"\"\"\n",
          "\n",
          "    var place: SplatView\n",
          "    \"\"\"The camera and the camera rectangle.\"\"\"\n",
          "    var eye: Vector3\n",
          "    \"\"\"The camera's position, in the object's space.\"\"\"\n",
          "    var degree: Int\n",
          "    \"\"\"The splats' spherical harmonics degree.\"\"\"\n",
          "    var left: Float32\n",
          "    \"\"\"The camera rectangle's first column in the target.\"\"\"\n",
          "    var top: Float32\n",
          "    \"\"\"The camera rectangle's first row in the target, from the top.\"\"\"\n",
          "\n",
          "\n",
          "def _project_span(\n",
          "    projected: MutPointer[ProjectedSplat, MutAnyOrigin],\n",
          "    shown: MutPointer[Bool, MutAnyOrigin],\n",
          "    splat: GaussianSplat,\n",
          "    run: _SplatRun,\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"Shade and project a run of the splats, in their own order.\n",
          "\n",
          "    Args:\n",
          "        projected: Each splat on the screen, written where `shown` is\n",
          "            True.\n",
          "        shown: Whether each splat is on the screen.\n",
          "        splat: The splats.\n",
          "        run: The view.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n"
        ]
      },
      {
        "start": 277,
        "stop": 281,
        "before": [
          "    for position in range(len(splat.order)):\n",
          "        var index = splat.order[position]\n"
        ],
        "after": [
          "    # The run is inside the splats, so their arrays are read unchecked.\n",
          "    var colors = geometry.colors.unsafe_ptr()\n",
          "    var centers = geometry.centers.unsafe_ptr()\n",
          "    for index in range(first, past):\n"
        ]
      },
      {
        "start": 282,
        "stop": 286,
        "before": [
          "            Float32(geometry.colors[index * 4]) / 255,\n",
          "            Float32(geometry.colors[index * 4 + 1]) / 255,\n",
          "            Float32(geometry.colors[index * 4 + 2]) / 255,\n",
          "            Float32(geometry.colors[index * 4 + 3]) / 255,\n"
        ],
        "after": [
          "            Float32(colors[unsafe_offset=index * 4]) / 255,\n",
          "            Float32(colors[unsafe_offset=index * 4 + 1]) / 255,\n",
          "            Float32(colors[unsafe_offset=index * 4 + 2]) / 255,\n",
          "            Float32(colors[unsafe_offset=index * 4 + 3]) / 255,\n"
        ]
      },
      {
        "start": 287,
        "stop": 295,
        "before": [
          "        if shaded:\n",
          "            color.r += shading[index * 3]\n",
          "            color.g += shading[index * 3 + 1]\n",
          "            color.b += shading[index * 3 + 2]\n",
          "        var projected = project_splat(\n"
        ],
        "after": [
          "        if run.degree > 0:\n",
          "            var shading = splat.spherical_harmonics_color(\n",
          "                index, run.eye, run.degree\n",
          "            )\n",
          "            color.r += shading.x\n",
          "            color.g += shading.y\n",
          "            color.b += shading.z\n",
          "        var found = project_splat(\n"
        ]
      },
      {
        "start": 296,
        "stop": 299,
        "before": [
          "                geometry.centers[index * 3],\n",
          "                geometry.centers[index * 3 + 1],\n",
          "                geometry.centers[index * 3 + 2],\n"
        ],
        "after": [
          "                centers[unsafe_offset=index * 3],\n",
          "                centers[unsafe_offset=index * 3 + 1],\n",
          "                centers[unsafe_offset=index * 3 + 2],\n"
        ]
      },
      {
        "start": 303,
        "stop": 304,
        "before": [
          "            place,\n"
        ],
        "after": [
          "            run.place,\n"
        ]
      },
      {
        "start": 305,
        "stop": 426,
        "before": [
          "        if Bool(projected):\n",
          "            var placed = projected.value()\n",
          "            placed.x += Float32(rect.x)\n",
          "            placed.y += Float32(rect.top(height))\n",
          "            out.append(placed)\n",
          "    return out^\n"
        ],
        "after": [
          "        if Bool(found):\n",
          "            var placed = found.value()\n",
          "            placed.x += run.left\n",
          "            placed.y += run.top\n",
          "            projected[unsafe_offset=index] = placed\n",
          "            shown[unsafe_offset=index] = True\n",
          "\n",
          "\n",
          "__async def _project_task(\n",
          "    projected: MutPointer[ProjectedSplat, MutAnyOrigin],\n",
          "    shown: MutPointer[Bool, MutAnyOrigin],\n",
          "    splat: MutPointer[GaussianSplat, MutAnyOrigin],\n",
          "    run: MutPointer[_SplatRun, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_project_span` as a task of `prepare_gaussian_splat`.\n",
          "\n",
          "    The tasks only read the splats and the view, and each writes its own\n",
          "    run of `projected` and `shown`.\n",
          "\n",
          "    Args:\n",
          "        projected: Each splat on the screen.\n",
          "        shown: Whether each splat is on the screen.\n",
          "        splat: The splats.\n",
          "        run: The view.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    _project_span(projected, shown, splat[], run[], first, past)\n",
          "\n",
          "\n",
          "def _shown_count(\n",
          "    order: MutPointer[Int, MutAnyOrigin],\n",
          "    shown: MutPointer[Bool, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          ") -> Int:\n",
          "    \"\"\"Return how many splats of a run of the draw order are on the screen.\n",
          "\n",
          "    Args:\n",
          "        order: The draw order.\n",
          "        shown: Whether each splat is on the screen.\n",
          "        first: The run's first place in the order.\n",
          "        past: One past its last place.\n",
          "\n",
          "    Returns:\n",
          "        The count.\n",
          "    \"\"\"\n",
          "    var count = 0\n",
          "    for position in range(first, past):\n",
          "        if shown[unsafe_offset=order[unsafe_offset=position]]:\n",
          "            count += 1\n",
          "    return count\n",
          "\n",
          "\n",
          "__async def _count_task(\n",
          "    count: MutPointer[Int, MutAnyOrigin],\n",
          "    order: MutPointer[Int, MutAnyOrigin],\n",
          "    shown: MutPointer[Bool, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_shown_count` as a task of `prepare_gaussian_splat`.\n",
          "\n",
          "    Args:\n",
          "        count: Where the run's count goes.\n",
          "        order: The draw order.\n",
          "        shown: Whether each splat is on the screen.\n",
          "        first: The run's first place in the order.\n",
          "        past: One past its last place.\n",
          "    \"\"\"\n",
          "    count[] = _shown_count(order, shown, first, past)\n",
          "\n",
          "\n",
          "def _gather(\n",
          "    drawn: MutPointer[ProjectedSplat, MutAnyOrigin],\n",
          "    order: MutPointer[Int, MutAnyOrigin],\n",
          "    shown: MutPointer[Bool, MutAnyOrigin],\n",
          "    projected: MutPointer[ProjectedSplat, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"Copy the splats of a run of the draw order that are on the screen,\n",
          "    in that order.\n",
          "\n",
          "    Args:\n",
          "        drawn: Where the run's splats go.\n",
          "        order: The draw order.\n",
          "        shown: Whether each splat is on the screen.\n",
          "        projected: Each splat on the screen.\n",
          "        first: The run's first place in the order.\n",
          "        past: One past its last place.\n",
          "    \"\"\"\n",
          "    var at = 0\n",
          "    for position in range(first, past):\n",
          "        var index = order[unsafe_offset=position]\n",
          "        if shown[unsafe_offset=index]:\n",
          "            drawn[unsafe_offset=at] = projected[unsafe_offset=index]\n",
          "            at += 1\n",
          "\n",
          "\n",
          "__async def _gather_task(\n",
          "    drawn: MutPointer[ProjectedSplat, MutAnyOrigin],\n",
          "    order: MutPointer[Int, MutAnyOrigin],\n",
          "    shown: MutPointer[Bool, MutAnyOrigin],\n",
          "    projected: MutPointer[ProjectedSplat, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_gather` as a task of `prepare_gaussian_splat`.\n",
          "\n",
          "    Args:\n",
          "        drawn: Where the run's splats go.\n",
          "        order: The draw order.\n",
          "        shown: Whether each splat is on the screen.\n",
          "        projected: Each splat on the screen.\n",
          "        first: The run's first place in the order.\n",
          "        past: One past its last place.\n",
          "    \"\"\"\n",
          "    _gather(drawn, order, shown, projected, first, past)\n"
        ]
      },
      {
        "start": 429,
        "stop": 430,
        "before": [
          "    mut target: RenderTarget, splats: List[ProjectedSplat]\n"
        ],
        "after": [
          "    mut target: RenderTarget, splats: List[ProjectedSplat], workers: Int = 1\n"
        ]
      },
      {
        "start": 436,
        "stop": 438,
        "before": [],
        "after": [
          "        workers: How many bands of rows fill at once; see the module\n",
          "            docstring.\n"
        ]
      },
      {
        "start": 443,
        "stop": 758,
        "before": [
          "    for index in range(len(splats)):\n",
          "        rasterize_splat(target, splats[index], 0, target.height - 1)\n"
        ],
        "after": [
          "    var bands = min(workers * SPLAT_BANDS_PER_WORKER, target.height)\n",
          "    if workers <= 1 or bands <= 1:\n",
          "        for index in range(len(splats)):\n",
          "            rasterize_splat(target, splats[index], 0, target.height - 1)\n",
          "        return\n",
          "    # Each band's splats, in draw order: a counting sort of the splats by\n",
          "    # the bands that their rows reach, in runs, as `GaussianSplat.sort_cpu`\n",
          "    # sorts. So a band reads only the splats that reach it.\n",
          "    var count = len(splats)\n",
          "    var runs = max(1, min(workers, count // SPLAT_RUN))\n",
          "    var band_of = List[Int](capacity=target.height)\n",
          "    for band in range(bands):  # pragma: no branch\n",
          "        for _ in range(\n",
          "            band * target.height // bands, (band + 1) * target.height // bands\n",
          "        ):  # pragma: no branch\n",
          "            band_of.append(band)\n",
          "    var reach = List[Int32](length=count * 2, fill=0)\n",
          "    var counts = List[Int](length=runs * bands, fill=0)\n",
          "    var splats_at = splats.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()\n",
          "    var band_at = band_of.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    var reach_at = reach.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    var count_at = counts.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    if runs == 1:\n",
          "        _band_reach(\n",
          "            splats_at, band_at, target.height, reach_at, count_at, 0, count\n",
          "        )\n",
          "    else:\n",
          "        var reaching = TaskGroup()\n",
          "        for run in range(runs):  # pragma: no branch\n",
          "            reaching.create_task(\n",
          "                _band_reach_task(\n",
          "                    splats_at,\n",
          "                    band_at,\n",
          "                    target.height,\n",
          "                    reach_at,\n",
          "                    count_at.unsafe_offset(run * bands),\n",
          "                    run * count // runs,\n",
          "                    (run + 1) * count // runs,\n",
          "                )\n",
          "            )\n",
          "        reaching.wait()\n",
          "    # Each run's first place in each band: band by band, run by run.\n",
          "    var starts = List[Int](length=bands + 1, fill=0)\n",
          "    var sum = 0\n",
          "    for band in range(bands):  # pragma: no branch\n",
          "        starts[band] = sum\n",
          "        for run in range(runs):  # pragma: no branch\n",
          "            var here = counts[run * bands + band]\n",
          "            counts[run * bands + band] = sum\n",
          "            sum += here\n",
          "    starts[bands] = sum\n",
          "    var members = List[Int](capacity=sum)\n",
          "    members.resize(unsafe_uninit_length=sum)\n",
          "    var member_at = members.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    if runs == 1:\n",
          "        _band_place(member_at, reach_at, count_at, 0, count)\n",
          "    else:\n",
          "        var placing = TaskGroup()\n",
          "        for run in range(runs):  # pragma: no branch\n",
          "            placing.create_task(\n",
          "                _band_place_task(\n",
          "                    member_at,\n",
          "                    reach_at,\n",
          "                    count_at.unsafe_offset(run * bands),\n",
          "                    run * count // runs,\n",
          "                    (run + 1) * count // runs,\n",
          "                )\n",
          "            )\n",
          "        placing.wait()\n",
          "    var errors = List[String](length=bands, fill=String())\n",
          "    var group = TaskGroup()\n",
          "    for band in range(bands):  # pragma: no branch\n",
          "        group.create_task(\n",
          "            _splat_band(\n",
          "                Pointer(to=target).unsafe_origin_cast[MutAnyOrigin](),\n",
          "                splats_at,\n",
          "                member_at.unsafe_offset(starts[band]),\n",
          "                starts[band + 1] - starts[band],\n",
          "                errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),\n",
          "                band,\n",
          "                band * target.height // bands,\n",
          "                (band + 1) * target.height // bands - 1,\n",
          "            )\n",
          "        )\n",
          "    group.wait()\n",
          "    # The tasks read the lists through pointers the compiler cannot see.\n",
          "    # These reads keep them alive until every task has finished.\n",
          "    _ = len(splats)\n",
          "    _ = len(band_of)\n",
          "    _ = len(reach)\n",
          "    _ = len(counts)\n",
          "    _ = len(members)\n",
          "    raise_splat_band_errors(errors)\n",
          "\n",
          "\n",
          "def _band_reach(\n",
          "    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],\n",
          "    band_of: MutPointer[Int, MutAnyOrigin],\n",
          "    height: Int,\n",
          "    reach: MutPointer[Int32, MutAnyOrigin],\n",
          "    counts: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"Find the bands that a run of splats reaches, and count them.\n",
          "\n",
          "    Args:\n",
          "        splats: The splats, in draw order.\n",
          "        band_of: The band of each row.\n",
          "        height: The target's height in rows.\n",
          "        reach: Each splat's first and last band, written for the run. The\n",
          "            last is before the first for a splat that reaches no row.\n",
          "        counts: The run's count of the splats that reach each band.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    for index in range(first, past):\n",
          "        var rows = splat_disc_rows(splats[unsafe_offset=index])\n",
          "        var top = max(rows[0], 0)\n",
          "        var bottom = min(rows[1], height - 1)\n",
          "        var low = 1\n",
          "        var high = 0\n",
          "        if top <= bottom:\n",
          "            low = band_of[unsafe_offset=top]\n",
          "            high = band_of[unsafe_offset=bottom]\n",
          "        reach[unsafe_offset=index * 2] = Int32(low)\n",
          "        reach[unsafe_offset=index * 2 + 1] = Int32(high)\n",
          "        for band in range(low, high + 1):\n",
          "            counts[unsafe_offset=band] += 1\n",
          "\n",
          "\n",
          "__async def _band_reach_task(\n",
          "    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],\n",
          "    band_of: MutPointer[Int, MutAnyOrigin],\n",
          "    height: Int,\n",
          "    reach: MutPointer[Int32, MutAnyOrigin],\n",
          "    counts: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_band_reach` as a task of `rasterize_splats`.\n",
          "\n",
          "    Args:\n",
          "        splats: The splats.\n",
          "        band_of: The band of each row.\n",
          "        height: The target's height.\n",
          "        reach: Each splat's bands.\n",
          "        counts: The run's counts.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    _band_reach(splats, band_of, height, reach, counts, first, past)\n",
          "\n",
          "\n",
          "def _band_place(\n",
          "    members: MutPointer[Int, MutAnyOrigin],\n",
          "    reach: MutPointer[Int32, MutAnyOrigin],\n",
          "    next: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"Put each splat of a run among the members of the bands it reaches.\n",
          "\n",
          "    Args:\n",
          "        members: Each band's splats, band after band.\n",
          "        reach: Each splat's first and last band.\n",
          "        next: The run's next place in each band.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    for index in range(first, past):\n",
          "        for band in range(\n",
          "            Int(reach[unsafe_offset=index * 2]),\n",
          "            Int(reach[unsafe_offset=index * 2 + 1]) + 1,\n",
          "        ):\n",
          "            members[unsafe_offset=next[unsafe_offset=band]] = index\n",
          "            next[unsafe_offset=band] += 1\n",
          "\n",
          "\n",
          "__async def _band_place_task(\n",
          "    members: MutPointer[Int, MutAnyOrigin],\n",
          "    reach: MutPointer[Int32, MutAnyOrigin],\n",
          "    next: MutPointer[Int, MutAnyOrigin],\n",
          "    first: Int,\n",
          "    past: Int,\n",
          "):\n",
          "    \"\"\"`_band_place` as a task of `rasterize_splats`.\n",
          "\n",
          "    Args:\n",
          "        members: Each band's splats.\n",
          "        reach: Each splat's bands.\n",
          "        next: The run's next places.\n",
          "        first: The run's first splat.\n",
          "        past: One past its last.\n",
          "    \"\"\"\n",
          "    _band_place(members, reach, next, first, past)\n",
          "\n",
          "\n",
          "__async def _splat_band(\n",
          "    target: MutPointer[RenderTarget, MutAnyOrigin],\n",
          "    splats: Pointer[ProjectedSplat, ImmutAnyOrigin],\n",
          "    members: MutPointer[Int, MutAnyOrigin],\n",
          "    count: Int,\n",
          "    errors: MutPointer[String, MutAnyOrigin],\n",
          "    band: Int,\n",
          "    first_row: Int,\n",
          "    last_row: Int,\n",
          "):\n",
          "    \"\"\"Blend the splats that reach one band of rows into it, a task of\n",
          "    `rasterize_splats`.\n",
          "\n",
          "    A band owns its rows, so no two bands touch one pixel. A task cannot\n",
          "    raise, so an error goes into the band's slot.\n",
          "\n",
          "    Args:\n",
          "        target: The target.\n",
          "        splats: The splats, in draw order.\n",
          "        members: The places in `splats` of the splats that reach the\n",
          "            band, in draw order.\n",
          "        count: How many members.\n",
          "        errors: One slot a band.\n",
          "        band: This band.\n",
          "        first_row: Its first row.\n",
          "        last_row: Its last row, inclusive.\n",
          "    \"\"\"\n",
          "    try:\n",
          "        require_splat_depth(target[].depth_mode)\n",
          "        for member in range(count):\n",
          "            rasterize_splat(\n",
          "                target[],\n",
          "                splats[unsafe_offset=members[unsafe_offset=member]],\n",
          "                first_row,\n",
          "                last_row,\n",
          "            )\n",
          "    except error:\n",
          "        errors[unsafe_offset=band] = String(error)\n",
          "\n",
          "\n",
          "def raise_splat_band_errors(errors: List[String]) raises:\n",
          "    \"\"\"Raise the first error a band of `rasterize_splats` carried back.\n",
          "\n",
          "    `rasterize_splats` checks the depth mode before any band starts, and\n",
          "    each band clamps its rows and columns to the target, so a band meets no\n",
          "    error. This net catches a check that a later change puts inside a band.\n",
          "\n",
          "    Args:\n",
          "        errors: One slot a band, empty where the band finished.\n",
          "\n",
          "    Raises:\n",
          "        Error: The first band's error, if any band has one.\n",
          "    \"\"\"\n",
          "    for band in range(len(errors)):\n",
          "        if errors[band] != \"\":\n",
          "            raise Error(errors[band])\n",
          "\n",
          "\n",
          "def _splat_index(value: Float32, round_up: Bool) -> Int:\n",
          "    \"\"\"Return the pixel index of a splat edge.\n",
          "\n",
          "    A value that is not finite, or that does not fit in an integer, is\n",
          "    past every pixel. `Int` of such a float is not that coordinate.\n",
          "\n",
          "    Args:\n",
          "        value: The edge, in pixels.\n",
          "        round_up: True to round toward positive infinity.\n",
          "\n",
          "    Returns:\n",
          "        The index, or `Int.MAX` or `Int.MIN` when `value` does not fit.\n",
          "    \"\"\"\n",
          "    # `Float32(Int.MAX)` is 2^63, as `Float64(Int.MAX)` is, and the floor\n",
          "    # of a `Float32` is a `Float32`: the same test and index without\n",
          "    # `Float64`, which a Metal kernel cannot run.\n",
          "    if not isfinite(value) or value >= Float32(Int.MAX):\n",
          "        return Int.MAX\n",
          "    if value <= -Float32(Int.MAX):\n",
          "        return Int.MIN\n",
          "    if round_up:\n",
          "        return Int(ceil(value))\n",
          "    return Int(floor(value))\n",
          "\n",
          "\n",
          "def _splat_low(value: Float32, floor_at: Int) -> Int:\n",
          "    \"\"\"Return the first pixel at or before `value`, held at `floor_at`.\n",
          "\n",
          "    Args:\n",
          "        value: The near edge, in pixels.\n",
          "        floor_at: The first pixel the band may touch.\n",
          "\n",
          "    Returns:\n",
          "        The column or row the walk starts at, or past the image.\n",
          "    \"\"\"\n",
          "    var index = _splat_index(value, False)\n",
          "    if index == Int.MIN:\n",
          "        return floor_at\n",
          "    if index == Int.MAX:\n",
          "        return Int.MAX\n",
          "    return max(index - 1, floor_at)\n",
          "\n",
          "\n",
          "def _splat_high(value: Float32, ceil_at: Int) -> Int:\n",
          "    \"\"\"Return the last pixel at or after `value`, held at `ceil_at`.\n",
          "\n",
          "    Args:\n",
          "        value: The far edge, in pixels.\n",
          "        ceil_at: The last pixel the band may touch.\n",
          "\n",
          "    Returns:\n",
          "        The column or row the walk ends at, or before the image.\n",
          "    \"\"\"\n",
          "    var index = _splat_index(value, True)\n",
          "    if index == Int.MAX:\n",
          "        return ceil_at\n",
          "    if index == Int.MIN:\n",
          "        return Int.MIN\n",
          "    return min(index + 1, ceil_at)\n"
        ]
      },
      {
        "start": 778,
        "stop": 791,
        "before": [
          "    var left = max(Int(floor(splat.x - reach[0])) - 1, 0)\n",
          "    var right = min(Int(ceil(splat.x + reach[0])) + 1, target.width - 1)\n",
          "    var top = max(Int(floor(splat.y - reach[1])) - 1, max(0, first_row))\n"
        ],
        "after": [
          "    # The box, inside the target and its scissor. The scissor's corner\n",
          "    # counts up from the bottom. An edge that is not finite, or that does\n",
          "    # not fit in an integer, is past every pixel.\n",
          "    ref cut = target.scissor\n",
          "    var left = _splat_low(splat.x - reach[0], max(0, cut.x))\n",
          "    var right = _splat_high(\n",
          "        splat.x + reach[0], min(target.width - 1, cut.x + cut.width - 1)\n",
          "    )\n",
          "    var rule = _row_rule(splat)\n",
          "    var rows = _rule_rows(rule, splat_rows(splat))\n",
          "    var top = max(\n",
          "        rows[0], max(max(0, first_row), target.height - cut.y - cut.height)\n",
          "    )\n"
        ]
      },
      {
        "start": 792,
        "stop": 794,
        "before": [
          "        Int(ceil(splat.y + reach[1])) + 1, min(target.height - 1, last_row)\n"
        ],
        "after": [
          "        rows[1],\n",
          "        min(min(target.height - 1, last_row), target.height - 1 - cut.y),\n"
        ]
      },
      {
        "start": 795,
        "stop": 1017,
        "before": [
          "    for y in range(top, bottom + 1):\n",
          "        _blend_row(target, splat, y, left, right)\n"
        ],
        "after": [
          "    if left > right or top > bottom:\n",
          "        return\n",
          "    # The return above leaves at least one row.\n",
          "    for y in range(top, bottom + 1):  # pragma: no branch\n",
          "        var span = _rule_span(rule, y, left, right)\n",
          "        _blend_row(target, splat, y, span[0], span[1])\n",
          "\n",
          "\n",
          "def splat_rows(splat: ProjectedSplat) -> Tuple[Int, Int]:\n",
          "    \"\"\"Return the rows that a splat's box spans, before any clamp.\n",
          "\n",
          "    Args:\n",
          "        splat: The splat.\n",
          "\n",
          "    Returns:\n",
          "        The first and the last row of its quad, with a row of margin at\n",
          "        each end, as `rasterize_splat` takes them. An edge that is not\n",
          "        finite, or that does not fit in an integer, is `Int.MAX` or\n",
          "        `Int.MIN`, past every row.\n",
          "    \"\"\"\n",
          "    var reach = splat_reach(splat)\n",
          "    return (\n",
          "        _splat_low(splat.y - reach[1], Int.MIN),\n",
          "        _splat_high(splat.y + reach[1], Int.MAX),\n",
          "    )\n",
          "\n",
          "\n",
          "def splat_disc_rows(splat: ProjectedSplat) -> Tuple[Int, Int]:\n",
          "    \"\"\"Return the rows whose spans can hold a splat's disc.\n",
          "\n",
          "    `splat_row_span` solves a quadratic along a row. Its discriminant is\n",
          "    `4 a R - 4 dy^2 A B (ax^2 + ay^2)^2`, with `A` and `B` the inverse\n",
          "    squared scales and `R` the slackened radius squared. So a row whose\n",
          "    center is further than `h = sqrt(a R / (A B (ax^2 + ay^2)^2))` from\n",
          "    the splat's center spans nothing. These are the rows within `h`, with\n",
          "    `h` widened by `SPLAT_ROW_SLACK`, inside the box's rows. A tiny splat\n",
          "    takes one or two rows, where its box takes four or five.\n",
          "\n",
          "    Args:\n",
          "        splat: The splat.\n",
          "\n",
          "    Returns:\n",
          "        The first and the last row. A splat with a scale that is zero,\n",
          "        infinite or not a number, or with no axis, gets the box's rows, as\n",
          "        its spans get the box's columns.\n",
          "    \"\"\"\n",
          "    return _rule_rows(_row_rule(splat), splat_rows(splat))\n",
          "\n",
          "\n",
          "def _rule_rows(rule: _RowRule, box: Tuple[Int, Int]) -> Tuple[Int, Int]:\n",
          "    \"\"\"Return the rows of a splat's disc from its quadratic; see\n",
          "    `splat_disc_rows`.\n",
          "\n",
          "    Args:\n",
          "        rule: The splat's quadratic.\n",
          "        box: The rows of its box, from `splat_rows`.\n",
          "\n",
          "    Returns:\n",
          "        The first and the last row.\n",
          "    \"\"\"\n",
          "    var reach = sqrt(\n",
          "        rule.a\n",
          "        * Float64(SPLAT_RADIUS_SQ)\n",
          "        * (1 + SPLAT_SPAN_SLACK)\n",
          "        / (rule.across * rule.along * rule.norm * rule.norm)\n",
          "    ) * (1 + SPLAT_ROW_SLACK)\n",
          "    # Below these bounds no product of the quadratic can overflow. A\n",
          "    # reach that is not finite is a splat that crosses every row.\n",
          "    if not (\n",
          "        rule.across < 1e30\n",
          "        and rule.along < 1e30\n",
          "        and rule.a > 0\n",
          "        and isfinite(reach)\n",
          "    ):\n",
          "        return box\n",
          "    # A row's center is half a row below its top.\n",
          "    var center = rule.y - 0.5\n",
          "    var first = max(Float64(box[0]), ceil(center - reach))\n",
          "    var last = min(Float64(box[1]), floor(center + reach))\n",
          "    return (Int(first), Int(last))\n",
          "\n",
          "\n",
          "@fieldwise_init\n",
          "struct _RowRule(ImplicitlyCopyable):\n",
          "    \"\"\"What `splat_row_span` needs of a splat for every row: the quadratic\n",
          "    of the disc along a row, less the row's own terms.\"\"\"\n",
          "\n",
          "    var x: Float64\n",
          "    \"\"\"The splat's center column.\"\"\"\n",
          "    var y: Float64\n",
          "    \"\"\"Its center row.\"\"\"\n",
          "    var a: Float64\n",
          "    \"\"\"The square term's coefficient.\"\"\"\n",
          "    var b: Float64\n",
          "    \"\"\"The linear term's coefficient, a unit of row offset.\"\"\"\n",
          "    var c: Float64\n",
          "    \"\"\"The constant term's coefficient, a unit of squared row offset.\"\"\"\n",
          "    var across: Float64\n",
          "    \"\"\"The inverse squared scale across the first axis.\"\"\"\n",
          "    var along: Float64\n",
          "    \"\"\"The inverse squared scale along it.\"\"\"\n",
          "    var norm: Float64\n",
          "    \"\"\"The axis's squared length.\"\"\"\n",
          "\n",
          "\n",
          "def _row_rule(splat: ProjectedSplat) -> _RowRule:\n",
          "    \"\"\"Return the quadratic of a splat's disc along its rows.\n",
          "\n",
          "    Args:\n",
          "        splat: The splat.\n",
          "\n",
          "    Returns:\n",
          "        The coefficients; see `splat_row_span`.\n",
          "    \"\"\"\n",
          "    var ax = Float64(splat.axis_x)\n",
          "    var ay = Float64(splat.axis_y)\n",
          "    var across = 1 / (Float64(splat.scale1) * Float64(splat.scale1))\n",
          "    var along = 1 / (Float64(splat.scale2) * Float64(splat.scale2))\n",
          "    return _RowRule(\n",
          "        Float64(splat.x),\n",
          "        Float64(splat.y),\n",
          "        ax * ax * across + ay * ay * along,\n",
          "        2 * ax * ay * (across - along),\n",
          "        ay * ay * across + ax * ax * along,\n",
          "        across,\n",
          "        along,\n",
          "        ax * ax + ay * ay,\n",
          "    )\n",
          "\n",
          "\n",
          "def _rule_span(\n",
          "    rule: _RowRule, y: Int, left: Int, right: Int\n",
          ") -> Tuple[Int, Int]:\n",
          "    \"\"\"Return a row's span from a splat's quadratic; see `splat_row_span`.\n",
          "\n",
          "    Args:\n",
          "        rule: The splat's quadratic.\n",
          "        y: The row, down from the top.\n",
          "        left: The box's first column.\n",
          "        right: The box's last column.\n",
          "\n",
          "    Returns:\n",
          "        The first and the last column of the span.\n",
          "    \"\"\"\n",
          "    var dy = rule.y - (Float64(y) + 0.5)\n",
          "    var b = rule.b * dy\n",
          "    var c = dy * dy * rule.c - Float64(SPLAT_RADIUS_SQ) * (1 + SPLAT_SPAN_SLACK)\n",
          "    var discriminant = b * b - 4 * rule.a * c\n",
          "    if not isfinite(discriminant) or not (rule.a > 0):\n",
          "        return (left, right)\n",
          "    if discriminant < 0:\n",
          "        return (left, left - 1)\n",
          "    var root = sqrt(discriminant)\n",
          "    var low = (-b - root) / (2 * rule.a)\n",
          "    var high = (-b + root) / (2 * rule.a)\n",
          "    # A pixel's center is half a pixel right of its left edge.\n",
          "    var first = Int(ceil(rule.x + low - 0.5))\n",
          "    var last = Int(floor(rule.x + high - 0.5))\n",
          "    return (max(first, left), min(last, right))\n",
          "\n",
          "\n",
          "def splat_row_span(\n",
          "    splat: ProjectedSplat, y: Int, left: Int, right: Int\n",
          ") -> Tuple[Int, Int]:\n",
          "    \"\"\"Return the columns of one row that a splat's disc can cover.\n",
          "\n",
          "    The disc is `u^2 + v^2 <= 4`, which along a row is a quadratic in the\n",
          "    pixel center's offset from the splat's center. Its roots are found for\n",
          "    a disc wider by `SPLAT_SPAN_SLACK`, in `Float64`, and the span is the\n",
          "    pixels whose centers are between them. So every pixel whose center\n",
          "    `splat_alpha` puts in the disc is in the span, and `splat_alpha` still\n",
          "    decides each pixel: a row draws what its whole box draws, and the\n",
          "    pixels it skips are the ones that would add nothing.\n",
          "\n",
          "    Args:\n",
          "        splat: The splat.\n",
          "        y: The row, down from the top.\n",
          "        left: The box's first column.\n",
          "        right: The box's last column.\n",
          "\n",
          "    Returns:\n",
          "        The first and the last column of the span, inside `left` and\n",
          "        `right`. The first is past the last for a row that the disc misses.\n",
          "        A splat with a scale that is not positive and finite gets the whole\n",
          "        box.\n",
          "    \"\"\"\n",
          "    return _rule_span(_row_rule(splat), y, left, right)\n",
          "\n",
          "\n",
          "def blend_splat_pixel(\n",
          "    mut target: RenderTarget, slot: Int, splat: ProjectedSplat, alpha: Float32\n",
          "):\n",
          "    \"\"\"Blend a splat's color into one pixel: source over, with straight\n",
          "    alpha, as `RenderTarget.blend` mixes under the normal mode.\n",
          "\n",
          "    Each sum of products is one fused multiply-add, which rounds once\n",
          "    wherever the compiler puts it. So the fill gives a pixel the same bits\n",
          "    in any band and on any count of workers. `render.blend.blend_fragment`\n",
          "    leaves the compiler to fuse, so the two can differ in the last bit.\n",
          "\n",
          "    Args:\n",
          "        target: The target. Its normal attachment is left alone, and the\n",
          "            pixel becomes light.\n",
          "        slot: The pixel, row by row. It must be inside the target and its\n",
          "            scissor: it is read and written unchecked.\n",
          "        splat: The splat.\n",
          "        alpha: Its opacity at the pixel, above zero.\n",
          "    \"\"\"\n",
          "    var colors = target.colors.unsafe_ptr()\n",
          "    var data = target.data.unsafe_ptr()\n",
          "    var stored = colors[unsafe_offset=slot]\n",
          "    # A data pixel is stored straight; see `RenderTarget.light_at`.\n",
          "    var behind = stored.premultiplied() if data[unsafe_offset=slot] else stored\n",
          "    data[unsafe_offset=slot] = False\n",
          "    var share = min(max(alpha, 0), 1)\n",
          "    var keep = 1 - share\n",
          "    colors[unsafe_offset=slot] = FloatColor(\n",
          "        max(Float32(0), fma(splat.r, share, behind.r * keep)),\n",
          "        max(Float32(0), fma(splat.g, share, behind.g * keep)),\n",
          "        max(Float32(0), fma(splat.b, share, behind.b * keep)),\n",
          "        min(max(fma(behind.a, keep, share), 0), 1),\n",
          "    )\n"
        ]
      },
      {
        "start": 1026,
        "stop": 1028,
        "before": [
          "    \"\"\"Blend one splat into one row of pixels.\n"
        ],
        "after": [
          "    \"\"\"Blend one splat into one row of pixels, `SPLAT_LANES` opacities at\n",
          "    a time.\n"
        ]
      },
      {
        "start": 1037,
        "stop": 1039,
        "before": [
          "        Error: Never; the columns and the row are inside the target.\n"
        ],
        "after": [
          "        Error: Never; the columns and the row are inside the target and its\n",
          "            scissor.\n"
        ]
      },
      {
        "start": 1040,
        "stop": 1060,
        "before": [
          "    for x in range(left, right + 1):\n",
          "        var stored = target.depth[y * target.width + x]\n",
          "        if not splat_depth_passes(target.depth_mode, splat.depth, stored):\n",
          "            continue\n",
          "        target.blend(\n",
          "            x,\n",
          "            y,\n",
          "            FloatColor(splat.r, splat.g, splat.b, splat_alpha(splat, x, y)),\n",
          "        )\n"
        ],
        "after": [
          "    # The row is inside the target, so it is read and written unchecked.\n",
          "    var depth = target.depth.unsafe_ptr().unsafe_offset(y * target.width)\n",
          "    var first = left\n",
          "    while first <= right:\n",
          "        var alphas = splat_alphas(splat, first, y)\n",
          "        for lane in range(\n",
          "            min(SPLAT_LANES, right - first + 1)\n",
          "        ):  # pragma: no branch\n",
          "            var x = first + lane\n",
          "            # A clear fragment blends nothing under source-over, so the\n",
          "            # pixels of the box outside the disc stop here.\n",
          "            var alpha = alphas[lane]\n",
          "            if not alpha > 0:\n",
          "                continue\n",
          "            if not splat_depth_passes(\n",
          "                target.depth_mode, splat.depth, depth[unsafe_offset=x]\n",
          "            ):\n",
          "                continue\n",
          "            blend_splat_pixel(target, y * target.width + x, splat, alpha)\n",
          "        first += SPLAT_LANES\n"
        ]
      },
      {
        "start": 1070,
        "stop": 1071,
        "before": [],
        "after": [
          "    workers: Int = 1,\n"
        ]
      },
      {
        "start": 1074,
        "stop": 1077,
        "before": [],
        "after": [
          "\n",
          "    Parameters:\n",
          "        C: The camera's type.\n"
        ]
      },
      {
        "start": 1085,
        "stop": 1086,
        "before": [],
        "after": [
          "        workers: How many threads draw; see the module docstring.\n"
        ]
      },
      {
        "start": 1098,
        "stop": 1099,
        "before": [],
        "after": [
          "        workers,\n"
        ]
      },
      {
        "start": 1100,
        "stop": 1101,
        "before": [
          "    rasterize_splats(target, splats)\n"
        ],
        "after": [
          "    rasterize_splats(target, splats, workers)\n"
        ]
      }
    ]
  },
  "render/splatrule.mojo": {
    "before_sha256": "96bf5f834a4bcde8df349b8ff8862b50cacdac296cd34dc640af6af0caf0cb02",
    "after_sha256": "7a60d54bb1d6f24c24bc19824f19e5041c5e75602985ba608114c2ed738d8997",
    "before_token_sha256": "b747b01b5e8b9628ca035245fceefb12236d7b7390e33af01afa3b61dda2b1d3",
    "after_token_sha256": "4ce9bb899d656a518eed76341ff1ed4da812cac4b2f12c5854c0e68557643f94",
    "edits": [
      {
        "start": 57,
        "stop": 58,
        "before": [
          "from std.math import atan2, cos, exp, log2, max, min, sin, sqrt\n"
        ],
        "after": [
          "from std.math import copysign, exp, fma, log2, max, min, sqrt\n"
        ]
      },
      {
        "start": 144,
        "stop": 170,
        "before": [
          "    var dx = Float32(x) + 0.5 - splat.x\n"
        ],
        "after": [
          "    return _alpha_lanes[1](splat, SIMD[DType.float32, 1](Float32(x)), y)[0]\n",
          "\n",
          "\n",
          "def _alpha_lanes[\n",
          "    width: Int\n",
          "](splat: ProjectedSplat, columns: SIMD[DType.float32, width], y: Int) -> SIMD[\n",
          "    DType.float32, width\n",
          "]:\n",
          "    \"\"\"Return the opacities a splat gives pixels of one row.\n",
          "\n",
          "    `splat_alpha` and `splat_alphas` both run this one expression, and\n",
          "    `exp` gives a lane what it gives one number. So a lane of eight is the\n",
          "    lane of one to the bit.\n",
          "\n",
          "    Parameters:\n",
          "        width: How many pixels.\n",
          "\n",
          "    Args:\n",
          "        splat: The splat.\n",
          "        columns: The pixels' columns.\n",
          "        y: Their row, down from the top.\n",
          "\n",
          "    Returns:\n",
          "        Each pixel's opacity; see `splat_alpha`.\n",
          "    \"\"\"\n",
          "    var dx = columns + 0.5 - splat.x\n"
        ]
      },
      {
        "start": 171,
        "stop": 214,
        "before": [
          "    var u = (dx * splat.axis_x + dy * splat.axis_y) / splat.scale1\n",
          "    var v = (dy * splat.axis_x - dx * splat.axis_y) / splat.scale2\n",
          "    var r2 = squared_length2[DType.float32](u, v)\n",
          "    if r2 > SPLAT_RADIUS_SQ:\n",
          "        return 0\n",
          "    return exp(r2 * -0.5) * splat.a\n"
        ],
        "after": [
          "    # Explicit fused products: each rounds once, in any width, so the\n",
          "    # compiler has nothing left to fuse one way in a lane and another way\n",
          "    # alone.\n",
          "    var along = SIMD[DType.float32, width](dy * splat.axis_y)\n",
          "    var across = SIMD[DType.float32, width](dy * splat.axis_x)\n",
          "    var u = fma(dx, SIMD[DType.float32, width](splat.axis_x), along) / (\n",
          "        splat.scale1\n",
          "    )\n",
          "    var v = fma(-dx, SIMD[DType.float32, width](splat.axis_y), across) / (\n",
          "        splat.scale2\n",
          "    )\n",
          "    var r2 = fma(u, u, v * v)\n",
          "    return r2.gt(SPLAT_RADIUS_SQ).select(\n",
          "        SIMD[DType.float32, width](0), exp(r2 * -0.5) * splat.a\n",
          "    )\n",
          "\n",
          "\n",
          "comptime SPLAT_LANES = 8\n",
          "\"\"\"How many pixels of a row `splat_alphas` shades at once.\"\"\"\n",
          "\n",
          "\n",
          "def splat_alphas(\n",
          "    splat: ProjectedSplat, x: Int, y: Int\n",
          ") -> SIMD[DType.float32, SPLAT_LANES]:\n",
          "    \"\"\"Return the opacities a splat gives `SPLAT_LANES` pixels of a row.\n",
          "\n",
          "    The lanes run the expression of `splat_alpha`. So each lane is\n",
          "    `splat_alpha` of its pixel, to the bit, at a fraction of the time.\n",
          "\n",
          "    Args:\n",
          "        splat: The splat.\n",
          "        x: The first pixel's column.\n",
          "        y: The pixels' row, down from the top.\n",
          "\n",
          "    Returns:\n",
          "        Lane `k` is `splat_alpha(splat, x + k, y)`.\n",
          "    \"\"\"\n",
          "    # Columns below 2^24 are exact in `Float32`, so lane k's column is the\n",
          "    # one `splat_alpha` makes of `x + k`.\n",
          "    var columns = SIMD[DType.float32, SPLAT_LANES](\n",
          "        0, 1, 2, 3, 4, 5, 6, 7\n",
          "    ) + Float32(x)\n",
          "    return _alpha_lanes[SPLAT_LANES](splat, columns, y)\n"
        ]
      },
      {
        "start": 319,
        "stop": 321,
        "before": [
          "        at: Where this splat's six floats start.\n"
        ],
        "after": [
          "        at: Where this splat's six floats start. They must be inside\n",
          "            `covariance`: they are read unchecked.\n"
        ]
      },
      {
        "start": 348,
        "stop": 353,
        "before": [
          "    var cov0 = Vector3(covariance[at], covariance[at + 1], covariance[at + 2])\n"
        ],
        "after": [
          "    # The caller gives a splat's six floats; they are read unchecked.\n",
          "    var six = covariance.unsafe_ptr().unsafe_offset(at)\n",
          "    var cov0 = Vector3(\n",
          "        six[unsafe_offset=0], six[unsafe_offset=1], six[unsafe_offset=2]\n",
          "    )\n"
        ]
      },
      {
        "start": 354,
        "stop": 355,
        "before": [
          "        covariance[at + 1], covariance[at + 3], covariance[at + 4]\n"
        ],
        "after": [
          "        six[unsafe_offset=1], six[unsafe_offset=3], six[unsafe_offset=4]\n"
        ]
      },
      {
        "start": 357,
        "stop": 358,
        "before": [
          "        covariance[at + 2], covariance[at + 4], covariance[at + 5]\n"
        ],
        "after": [
          "        six[unsafe_offset=2], six[unsafe_offset=4], six[unsafe_offset=5]\n"
        ]
      },
      {
        "start": 395,
        "stop": 404,
        "before": [
          "    var angle = atan2(b * 2, a - c) * 0.5\n",
          "    var axis_x = cos(angle)\n",
          "    var axis_y = sin(angle)\n"
        ],
        "after": [
          "    # The major axis is at half the angle of (a - c, 2 b), three.js's\n",
          "    # `atan2`. The half-angle formulas give its cosine and sine with two\n",
          "    # square roots in place of three trigonometric calls.\n",
          "    # A round splat has no gap: three.js's atan2(0, 0) keeps its axis at\n",
          "    # (1, 0).\n",
          "    var gap = sqrt(squared_length2[DType.float32](half_gap, b))\n",
          "    var cos2 = half_gap / gap if gap > 0 else Float32(1)\n",
          "    var axis_x = sqrt(max((1 + cos2) * 0.5, 0))\n",
          "    var axis_y = copysign(sqrt(max((1 - cos2) * 0.5, 0)), b)\n"
        ]
      }
    ]
  },
  "render/target.mojo": {
    "before_sha256": "cf004fbceafd55ffe634492cddcbb0893a9a0602ccc5da46b374df9a433fefb8",
    "after_sha256": "280f61ed85ed118c0afa6612e4607218f26a03c0373f2e99d5b757a48924e438",
    "before_token_sha256": "52b06ddd33f9ee0e576bb8098db68c8007952eac2ba1da980605ab39739888f6",
    "after_token_sha256": "2a79a4ba4e31c90d3041ad03a8d0dd1935c68a510761d4ed0fd071a20f059824",
    "edits": [
      {
        "start": 315,
        "stop": 316,
        "before": [
          "        three for nine and four for sixteen.\n"
        ],
        "after": [
          "        three for nine and four for sixteen. A larger count is still four.\n"
        ]
      },
      {
        "start": 318,
        "stop": 321,
        "before": [
          "    while (side + 1) * (side + 1) <= samples:\n"
        ],
        "after": [
          "    # Stop at a side of four. Past that, `(side + 1)` squared wraps and\n",
          "    # the walk does not finish.\n",
          "    while side * side < MAX_SAMPLES and (side + 1) * (side + 1) <= samples:\n"
        ]
      },
      {
        "start": 633,
        "stop": 634,
        "before": [
          "async def _encode_band(\n"
        ],
        "after": [
          "__async def _encode_band(\n"
        ]
      },
      {
        "start": 747,
        "stop": 750,
        "before": [
          "            Error: If either dimension is not positive, `check_target`\n",
          "                refuses the type or the outputs, or `check_samples`\n",
          "                refuses the sample count.\n"
        ],
        "after": [
          "            Error: If either dimension is not positive, the pixel count\n",
          "                does not fit, `check_target` refuses the type or the\n",
          "                outputs, or `check_samples` refuses the sample count.\n"
        ]
      },
      {
        "start": 754,
        "stop": 758,
        "before": [],
        "after": [
          "        # Divide before multiplying. A wrapped product would allocate the\n",
          "        # wrong number of pixels.\n",
          "        if width > Int.MAX // height:\n",
          "            raise Error(\"A render target is larger than this port draws\")\n"
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
    "after_sha256": "7fcdce220f3420c7a7739c0419d8af1087a06f79343a9f86cac4f8313fa6fa18",
    "before_token_sha256": "cda4f5d902566d18ae704ba4bc976141e8324c84d6d2900667739b1e28526ed8",
    "after_token_sha256": "baf2094e9758113bc9ab8d3bd408b3cf9212b5b3d9785874667bb56fecf09ce9",
    "edits": [
      {
        "start": 186,
        "stop": 193,
        "before": [
          "from math.utils import mix_delta\n"
        ],
        "after": [
          "from math.utils import (\n",
          "    mix_delta,\n",
          "    texel_center,\n",
          "    texel_center_from_end,\n",
          "    texel_ndc,\n",
          "    texel_ndc_up,\n",
          ")\n"
        ]
      },
      {
        "start": 2429,
        "stop": 2431,
        "before": [
          "        Error: If the view cannot be inverted.\n"
        ],
        "after": [
          "        Error: If the view cannot be inverted, or a material's plane\n",
          "            count is below zero or above eight.\n"
        ]
      },
      {
        "start": 2819,
        "stop": 2820,
        "before": [
          "            corners.append(corner^)\n"
        ],
        "after": [
          "            corners.append(corner)\n"
        ]
      },
      {
        "start": 4505,
        "stop": 4506,
        "before": [
          "async def _wide_task(\n"
        ],
        "after": [
          "__async def _wide_task(\n"
        ]
      },
      {
        "start": 4861,
        "stop": 4863,
        "before": [
          "                var ndc_x = (Float32(x - self.viewport.x) + 0.5) / Float32(\n",
          "                    self.viewport.width\n",
          "                ) * 2 - 1\n",
          "                var ndc_y = (\n",
          "                    1\n",
          "                    - (Float32(y - self.top) + 0.5)\n",
          "                    / Float32(self.viewport.height)\n",
          "                    * 2\n",
          "                )\n"
        ],
        "after": [
          "                var ndc_x = texel_ndc(x - self.viewport.x, self.viewport.width)\n",
          "                var ndc_y = texel_ndc_up(y - self.top, self.viewport.height)\n"
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
      },
      {
        "start": 8403,
        "stop": 8404,
        "before": [],
        "after": [
          "                self.workers,\n"
        ]
      },
      {
        "start": 10010,
        "stop": 10012,
        "before": [
          "                        var u = (Float32(x - viewport.x) + 0.5) / Float32(\n",
          "                            viewport.width\n",
          "                        )\n",
          "                        var v = 1 - (Float32(y - top) + 0.5) / Float32(\n",
          "                            viewport.height\n",
          "                        )\n"
        ],
        "after": [
          "                        var u = texel_center(x - viewport.x, viewport.width)\n",
          "                        var v = texel_center_from_end(y - top, viewport.height)\n"
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
    "after_sha256": "746f6b0cc8dfe9d2e9d57916f87012736160f9109bcb6768c12a29f9f0b50c93",
    "before_token_sha256": "addcb2731467077978d23ba88c9f783ef269a173b2a456b0023676e032b3f4da",
    "after_token_sha256": "1f73b362a1765512f7abd9ff15a3472cc55ecc5b322c3a0596fc6bdbc745cf69",
    "edits": [
      {
        "start": 32,
        "stop": 33,
        "before": [],
        "after": [
          "    texel_solid_angle,\n"
        ]
      },
      {
        "start": 38,
        "stop": 39,
        "before": [],
        "after": [
          "from math.utils import texel_ndc, texel_ndc_up\n"
        ]
      },
      {
        "start": 48,
        "stop": 49,
        "before": [],
        "after": [
          "from std.math import pow\n"
        ]
      },
      {
        "start": 148,
        "stop": 169,
        "before": [],
        "after": [
          "def test_a_wide_sky_texel_stays_inside_its_face() raises:\n",
          "    var small = texel_solid_angle(0, 0, 4)\n",
          "    var place = (Float32(0) + 0.5) / Float32(4) * 2 - 1\n",
          "    var side = Float32(2) / Float32(4)\n",
          "    assert_equal(\n",
          "        small,\n",
          "        side * side / pow(1 + place * place + place * place, Float32(1.5)),\n",
          "    )\n",
          "    var size = 16777217\n",
          "    var wide = texel_solid_angle(size - 1, 0, size)\n",
          "    var edge = (Float32(size - 1) + 0.5) / Float32(size) * 2 - 1\n",
          "    var across = (Float32(0) + 0.5) / Float32(size) * 2 - 1\n",
          "    var wide_side = Float32(2) / Float32(size)\n",
          "    assert_true(\n",
          "        wide\n",
          "        != wide_side\n",
          "        * wide_side\n",
          "        / pow(1 + edge * edge + across * across, Float32(1.5))\n",
          "    )\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 180,
        "stop": 181,
        "before": [
          "    var cube = cube_texture_from(faces^)\n"
        ],
        "after": [
          "    var cube = cube_texture_from(faces)\n"
        ]
      },
      {
        "start": 218,
        "stop": 227,
        "before": [],
        "after": [
          "def test_a_wide_view_keeps_the_last_pixel_inside() raises:\n",
          "    var wide = 16777217\n",
          "    var rays = ViewRays(wide, 4, Matrix4(), Matrix4())\n",
          "    var point = rays.view_point(wide - 1, 0, 0)\n",
          "    assert_equal(point.x, texel_ndc(wide - 1, wide))\n",
          "    assert_true(point.x < 1)\n",
          "    assert_equal(point.y, texel_ndc_up(0, 4))\n",
          "\n",
          "\n"
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
  "tests/test_denoise.mojo": {
    "before_sha256": "568ceff912f36950f00fff1711a1780f9378e4a145c1599e514d80603b38ba95",
    "after_sha256": "909333fda77f602e485236fabb97247a8cabc215a7e6f523238bc134b6e270d5",
    "before_token_sha256": "f7a7255dc7749b3c6e27ee5ab383bbb623b17d48a940f66e0d0f7e21a629a3c7",
    "after_token_sha256": "5620ea971c34690681f74845984b8c4dc2934a675096e55f1c165845a3c002b9",
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
        "start": 161,
        "stop": 185,
        "before": [],
        "after": [
          "def test_denoise_noise_must_cover_its_grid() raises:\n",
          "    var depth = List[Float32](length=1, fill=0)\n",
          "    var view = DepthView(\n",
          "        depth, 1, 1, Matrix4(), Length(0.1, METER), Length(10, METER)\n",
          "    )\n",
          "    var source = LightView(\n",
          "        List[FloatColor](length=1, fill=FloatColor(0.2, 0.2, 0.2, 1)), 1, 1\n",
          "    )\n",
          "    var normals = LightView(\n",
          "        List[FloatColor](length=1, fill=FloatColor(0, 0, 1, 1)), 1, 1\n",
          "    )\n",
          "    with assert_raises(contains=\"64 by 64\"):\n",
          "        _ = denoise_pixel(\n",
          "            source,\n",
          "            view,\n",
          "            normals,\n",
          "            List[Float32](),\n",
          "            List[Vector3](),\n",
          "            0,\n",
          "            0,\n",
          "            DenoiseSettings(),\n",
          "        )\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 210,
        "stop": 259,
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
    "after_sha256": "9553accaeeff277776de433c8f6c9600ef6d01c6f2826582c2a6361092feea0f",
    "before_token_sha256": "22675d725e879973e7c2033f7e0446124a9ffbcae12e65d8f022680d939b8ee7",
    "after_token_sha256": "f7ef6af957a6c161fb48d18caa9dcf7075157f71f3784266c5a871db1d978fe1",
    "edits": [
      {
        "start": 252,
        "stop": 260,
        "before": [],
        "after": [
          "    var strip = parametric(SurfaceFunction[parametric_plane](), 4096, 1)\n",
          "    assert_equal(strip.vertex_count(), 4097 * 2)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = parametric(SurfaceFunction[parametric_plane](), 16777217, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = parametric(SurfaceFunction[parametric_plane](), 1, Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = parametric(SurfaceFunction[parametric_plane](), 4097, 4096)\n"
        ]
      },
      {
        "start": 527,
        "stop": 528,
        "before": [
          "    _ = check_hull(mirrored^)\n"
        ],
        "after": [
          "    _ = check_hull(mirrored)\n"
        ]
      },
      {
        "start": 1029,
        "stop": 1033,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = rounded_box(one, one, one, 2048)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = rounded_box(one, one, one, Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_geometry_inputs.mojo": {
    "before_sha256": "806d6910d12816bafce7a9a291a695a8c685dd5be51c15c72f5064bd426fecd6",
    "after_sha256": "e6982bf126f25f2bf39ff42a838cd97c440ef152c235ff41783bf8a7a659de7b",
    "before_token_sha256": "41506da7bac57eeface2135b9917cf86b60d21e773d1d10dc4a9e0968e1b06d3",
    "after_token_sha256": "8c26bb9c1b203ae58b8fa42d975f5da393d07670db36fdd225bd0c9a0563a0e7",
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
        "stop": 23,
        "before": [
          "from geometries.circle import FULL_TURN, check_sweep\n"
        ],
        "after": [
          "from geometries.capsule import capsule\n",
          "from geometries.circle import FULL_TURN, check_sweep, circle, ring\n",
          "from geometries.cylinder import cylinder\n",
          "from geometries.decal import decal\n",
          "from geometries.extrude import check_extrusion\n",
          "from geometries.plane import plane\n",
          "from geometries.sphere import sphere\n",
          "from geometries.surface import require_positive_radius\n",
          "from geometries.torus import torus, torus_knot\n",
          "from geometries.tube import tube\n",
          "from math.euler import Euler, XYZ\n",
          "from math.matrix4 import Matrix4\n",
          "from math.vector3 import Vector3\n"
        ]
      },
      {
        "start": 100,
        "stop": 261,
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
          "\n",
          "def _bad_lengths() -> List[Float32]:\n",
          "    return [\n",
          "        nan[DType.float32](),\n",
          "        inf[DType.float32](),\n",
          "        -inf[DType.float32](),\n",
          "    ]\n",
          "\n",
          "\n",
          "def test_capsule_length_refuses_nonfinite_values_before_generation() raises:\n",
          "    var one = Length(1, METER)\n",
          "    for bad in _bad_lengths():\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = capsule(one, Length(bad, METER), 1, 3, 1)\n",
          "    var built = capsule(one, Length(0, METER), 1, 3, 1)\n",
          "    assert_true(built.vertex_count() > 0)\n",
          "\n",
          "\n",
          "def test_tube_path_points_refuse_nonfinite_values_before_frames() raises:\n",
          "    var radius = Length(0.2, METER)\n",
          "    var origin = Vector3(0, 0, 0)\n",
          "    var ahead = Vector3(1, 0, 0)\n",
          "    for bad in _bad_lengths():\n",
          "        for axis in range(3):\n",
          "            var point = Vector3(1, 0, 0)\n",
          "            if axis == 0:\n",
          "                point.x = bad\n",
          "            elif axis == 1:\n",
          "                point.y = bad\n",
          "            else:\n",
          "                point.z = bad\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = tube([origin, point], radius, 3)\n",
          "            with assert_raises(contains=\"finite\"):\n",
          "                _ = tube([point, ahead, origin], radius, 3, closed=True)\n",
          "    var built = tube([origin, ahead], radius, 3)\n",
          "    assert_true(built.vertex_count() > 0)\n",
          "\n",
          "\n",
          "def test_extrusion_refuses_nonfinite_depth_and_bevel_amounts() raises:\n",
          "    var one = Length(1, METER)\n",
          "    var zero = Length(0, METER)\n",
          "    for bad in _bad_lengths():\n",
          "        var bad_length = Length(bad, METER)\n",
          "        with assert_raises(contains=\"finite depth\"):\n",
          "            check_extrusion(bad_length, 1, 1, False, one, one, 1, zero)\n",
          "        with assert_raises(contains=\"finite thickness\"):\n",
          "            check_extrusion(one, 1, 1, True, bad_length, one, 1, zero)\n",
          "        with assert_raises(contains=\"finite size\"):\n",
          "            check_extrusion(one, 1, 1, True, one, bad_length, 1, zero)\n",
          "        with assert_raises(contains=\"finite offset\"):\n",
          "            check_extrusion(one, 1, 1, True, one, zero, 1, bad_length)\n",
          "        # A bevel that is off does not read those amounts.\n",
          "        check_extrusion(one, 1, 1, False, bad_length, bad_length, 1, bad_length)\n",
          "    with assert_raises(contains=\"positive depth\"):\n",
          "        check_extrusion(zero, 1, 1, False, one, one, 1, zero)\n",
          "    with assert_raises(contains=\"positive thickness\"):\n",
          "        check_extrusion(one, 1, 1, True, zero, one, 1, zero)\n",
          "    with assert_raises(contains=\"negative distance\"):\n",
          "        check_extrusion(one, 1, 1, True, one, Length(-1, METER), 1, zero)\n",
          "    with assert_raises(contains=\"one band\"):\n",
          "        check_extrusion(\n",
          "            one, 1, 1, True, Length(nan[DType.float32](), METER), one, 0, zero\n",
          "        )\n",
          "    # A negative offset is a lip inward, and a size of zero is square.\n",
          "    check_extrusion(one, 1, 1, True, one, zero, 1, Length(-0.25, METER))\n",
          "\n",
          "\n"
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
    "after_sha256": "2656073cd53685734c4b481af9f60f889d716478a8108e69202e4fc732d8e46a",
    "before_token_sha256": "d8af870b59a87756aae6bdf1dc43f4f7b46974a679d04e94171b553323755dff",
    "after_token_sha256": "72f368333dd8870c39c11757e47c805abede03437b77138033737f040f53bd3d",
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
      },
      {
        "start": 116,
        "stop": 117,
        "before": [
          "            \"Use TestScratch at the suite entry point or tools/run_suite.py\"\n"
        ],
        "after": [
          "            \"Use TestScratch at the suite entry point or tools/run_suite.mojo\"\n"
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
    "after_sha256": "f4cf5b03da59b5a5070f9cdf8e26b486d4e1cd965eed172578018619ea788afe",
    "before_token_sha256": "b22fc35f7dfa59a57136e32d554c6ae85d2790aef00f672adee10883c1067c7e",
    "after_token_sha256": "c0e6fc03c3295433c521f8af4402ed587239a76e965919d1efc031d486c671a8",
    "edits": [
      {
        "start": 51,
        "stop": 59,
        "before": [],
        "after": [
          "# Immutable records pin these sources by their digests from before the PR780\n",
          "# successor edit. Their historical view is the exact predecessor.\n",
          "HISTORICAL_SUCCESSOR_PATHS = frozenset((\n",
          "    PREFIX + 'assets.mojo', PREFIX + 'model_cache.mojo', PREFIX + 'sensor.mojo',\n",
          "    PREFIX + 'speed_limits.mojo', 'tests/test_carla_speed_parser_exceptions.mojo',\n",
          "    PREFIX + 'lidar.mojo', PREFIX + 'semantic_lidar.mojo', PREFIX + 'render_post.mojo',\n",
          "    PREFIX + 'render_sky.mojo', PREFIX + 'render_textures.mojo',\n",
          "    PREFIX + 'render_weather.mojo'))\n"
        ]
      },
      {
        "start": 358,
        "stop": 360,
        "before": [
          "        if relative not in pr760.CARLA_REGISTRY_PATHS:\n"
        ],
        "after": [
          "        if (relative not in pr760.CARLA_REGISTRY_PATHS\n",
          "                and relative not in HISTORICAL_SUCCESSOR_PATHS):\n"
        ]
      },
      {
        "start": 383,
        "stop": 385,
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
    "after_sha256": "d0f1e87aba0343343f4a06dbc4ab18e911a32357f43076760b183cc8af8c4b91",
    "before_token_sha256": "a5fbfe1798ba77ac6154f228731a26c54c73174a159328422e2ae95b793c26a5",
    "after_token_sha256": "1263c3927082f972745b2ddc04e4bd2bf175eab219b5a342541a8eb4e14427d4",
    "edits": [
      {
        "start": 42,
        "stop": 44,
        "before": [
          "        raw = (ROOT/EXPECTATIONS).read_bytes()\n"
        ],
        "after": [
          "        # Later records join through the PR780 table, so this reads the PR776 endpoint.\n",
          "        raw = owner.pr780_successor.predecessor_bytes(EXPECTATIONS, (ROOT/EXPECTATIONS).read_bytes())\n"
        ]
      },
      {
        "start": 62,
        "stop": 63,
        "before": [],
        "after": [
          "        raw = owner.pr780_successor.predecessor_bytes(path, raw)\n"
        ]
      },
      {
        "start": 92,
        "stop": 93,
        "before": [
          "        raw = (ROOT/EXPECTATIONS).read_bytes()\n"
        ],
        "after": [
          "        raw = owner.pr780_successor.predecessor_bytes(EXPECTATIONS, (ROOT/EXPECTATIONS).read_bytes())\n"
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
  "tools/carla_lane_oracle/test_typed_owned_operations.py": {
    "before_sha256": "b71272abd022ff7453099ede5e5cd8ca8fc0dc6ba92057a94bdcd85170e39984",
    "after_sha256": "ff7ce184c8a71b84a523ee6a22652604b76f1e463f37cac7276f37c85a8c7edd",
    "before_token_sha256": "c84f544cdbffbd74be814905e13bba935182e54c2df54f44c2d5e2a1a38b885f",
    "after_token_sha256": "5d3aadca1fb008c03df6f502588987eea34019ceb31a91b3d567f0080bad6311",
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
      },
      {
        "start": 253,
        "stop": 255,
        "before": [
          "        historical = typed.historical_source(seed.MODULE, current.decode()).encode()\n"
        ],
        "after": [
          "        historical = typed.historical_source(seed.MODULE, fixtures.typed_current_bytes(\n",
          "            seed.MODULE, current).decode()).encode()\n"
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
  "tools/compile_fail_expectations.json": {
    "before_sha256": "cae00c1721392c75b10af5793e6de851d963350c8396e405ef0233c19af5b723",
    "after_sha256": "2383eb3c4f6b812c24b88bf777eb74809691036f5c9dc62b7fbce63b3b625a52",
    "before_token_sha256": "f4adb6494fee3e96a00ed12990e3c1979b42e31df987492561c08e8354ac4ba2",
    "after_token_sha256": "6b9ab7c588d1eb981ea9b993503e4f180b38ca2b45c09dd17d4e44865094c930",
    "edits": [
      {
        "start": 83,
        "stop": 95,
        "before": [],
        "after": [
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_blow_outcome_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 21,\n",
          "        \"message\": \"invalid call to 'require_outcome': value passed to 'outcome' cannot be converted from 'IntLiteral[1]' to 'BlowOutcome'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n"
        ]
      },
      {
        "start": 257,
        "stop": 269,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_bump_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 18,\n",
          "        \"message\": \"invalid call to 'require_bump': value passed to 'bump' cannot be converted from 'IntLiteral[1]' to 'Bump'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n"
        ]
      },
      {
        "start": 373,
        "stop": 385,
        "before": [],
        "after": [
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_cluster_fate_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 26,\n",
          "        \"message\": \"invalid call to 'require_cluster_fate': value passed to 'fate' cannot be converted from 'IntLiteral[0]' to 'ClusterFate'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n"
        ]
      },
      {
        "start": 1151,
        "stop": 1187,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_dye_channel_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 25,\n",
          "        \"message\": \"invalid call to 'require_dye_channel': value passed to 'channel' cannot be converted from 'IntLiteral[1]' to 'DyeChannel'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_dye_pattern_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 25,\n",
          "        \"message\": \"invalid call to 'require_dye_pattern': value passed to 'pattern' cannot be converted from 'IntLiteral[1]' to 'DyePattern'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_fabric_kind_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 25,\n",
          "        \"message\": \"invalid call to 'require_fabric_kind': value passed to 'kind' cannot be converted from 'IntLiteral[1]' to 'FabricKind'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n"
        ]
      },
      {
        "start": 1463,
        "stop": 1475,
        "before": [],
        "after": [
          "  },\n",
          "  \"tests/compile_fail/a_garment_layer_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 19,\n",
          "        \"message\": \"invalid call to 'require_layer': value passed to 'layer' cannot be converted from 'IntLiteral[1]' to 'Layer'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n"
        ]
      },
      {
        "start": 1898,
        "stop": 1908,
        "before": [],
        "after": [
          "  },\n",
          "  \"tests/compile_fail/a_kit_kind_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 25,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[0]' value to 'KitKind'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n"
        ]
      },
      {
        "start": 2606,
        "stop": 2616,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_part_fill_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 26,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[0]' value to 'PartFill'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n",
          "  },\n"
        ]
      },
      {
        "start": 2808,
        "stop": 2832,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_plant_detail_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 13,\n",
          "        \"column\": 51,\n",
          "        \"message\": \"invalid call to 'planted': value passed to 'plants' cannot be converted from 'IntLiteral[1]' to 'PlantDetail'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_plant_kind_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 24,\n",
          "        \"message\": \"invalid call to 'require_plant_kind': value passed to 'kind' cannot be converted from 'IntLiteral[2]' to 'PlantKind'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n"
        ]
      },
      {
        "start": 2944,
        "stop": 2956,
        "before": [],
        "after": [
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_quality_preset_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 32,\n",
          "        \"message\": \"invalid call to 'game_quality': value passed to 'preset' cannot be converted from 'IntLiteral[0]' to 'QualityPreset'\"\n"
        ]
      },
      {
        "start": 3148,
        "stop": 3178,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_scale_source_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 29,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[0]' value to 'ScaleSource'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n",
          "  },\n",
          "  \"tests/compile_fail/a_scan_axis_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 26,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[0]' value to 'ScanAxis'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n",
          "  },\n",
          "  \"tests/compile_fail/a_scan_format_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 28,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[0]' value to 'ScanFormat'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n",
          "  },\n"
        ]
      },
      {
        "start": 3357,
        "stop": 3367,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_shadow_mode_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 13,\n",
          "        \"column\": 24,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[2]' value to 'ShadowMode'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n",
          "  },\n"
        ]
      },
      {
        "start": 3461,
        "stop": 3473,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_slot_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 18,\n",
          "        \"message\": \"invalid call to 'require_slot': value passed to 'slot' cannot be converted from 'IntLiteral[1]' to 'Slot'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n"
        ]
      },
      {
        "start": 3479,
        "stop": 3491,
        "before": [],
        "after": [
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_socket_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 22,\n",
          "        \"message\": \"invalid call to 'socket_joint': value passed to 'socket' cannot be converted from 'IntLiteral[1]' to 'Socket'\"\n"
        ]
      },
      {
        "start": 3589,
        "stop": 3599,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_splat_model_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 28,\n",
          "        \"message\": \"cannot implicitly convert 'IntLiteral[0]' value to 'SplatModel'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": []\n",
          "  },\n"
        ]
      },
      {
        "start": 3639,
        "stop": 3651,
        "before": [],
        "after": [
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/a_stance_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 19,\n",
          "        \"message\": \"invalid call to 'clip_of': value passed to 'stance' cannot be converted from 'IntLiteral[2]' to 'Stance'\"\n"
        ]
      },
      {
        "start": 4513,
        "stop": 4525,
        "before": [],
        "after": [
          "  \"tests/compile_fail/a_wear_kind_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 23,\n",
          "        \"message\": \"invalid call to 'require_wear_kind': value passed to 'kind' cannot be converted from 'IntLiteral[1]' to 'WearKind'\"\n",
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n"
        ]
      },
      {
        "start": 5026,
        "stop": 5038,
        "before": [],
        "after": [
          "      }\n",
          "    ],\n",
          "    \"notes\": [\n",
          "      \"function declared here\"\n",
          "    ]\n",
          "  },\n",
          "  \"tests/compile_fail/an_articulation_is_not_a_bare_int.mojo\": {\n",
          "    \"errors\": [\n",
          "      {\n",
          "        \"line\": 12,\n",
          "        \"column\": 26,\n",
          "        \"message\": \"invalid call to 'require_articulation': value passed to 'articulation' cannot be converted from 'IntLiteral[1]' to 'Articulation'\"\n"
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
  },
  "core/gaussian_splat_utils.mojo": {
    "before_sha256": "63e4123f61a1e8ae6845b0eae449b5c173368bdf0ca691d7327255d33c8533b3",
    "after_sha256": "596021972df04a9f2b0721de3ae422147b808fd463a99fbf6ece93ea75376d29",
    "before_token_sha256": "3d1e3b322df7b3f42cce5e0be9c837bf4f25997a8eb23bdd63a8cc0ee010a4c7",
    "after_token_sha256": "e6b2b1e800c6aac31f0a92b61d707de9e8715b93a615b639f59a72505b0e306a",
    "edits": [
      {
        "start": 328,
        "stop": 330,
        "before": [
          "        Error: If the degree is not 1 through 3, or the count is negative.\n"
        ],
        "after": [
          "        Error: If the degree is not 1 through 3, the count is negative,\n",
          "            or `count` times the bytes of one splat does not fit in Int.\n"
        ]
      },
      {
        "start": 337,
        "stop": 344,
        "before": [
          "    return List[UInt8](\n",
          "        length=count * sh_band_words(degree) * 4, fill=SH_ZERO_BYTE\n",
          "    )\n"
        ],
        "after": [
          "    var words = sh_band_words(degree)\n",
          "    var per_splat = words * 4\n",
          "    # `count * per_splat` wraps to a negative length, and that list is\n",
          "    # built. The band then holds none of its bytes.\n",
          "    if count > Int.MAX // per_splat:\n",
          "        raise Error(\"A Gaussian splat band is larger than this port stores\")\n",
          "    return List[UInt8](length=count * per_splat, fill=SH_ZERO_BYTE)\n"
        ]
      }
    ]
  },
  "core/morph.mojo": {
    "before_sha256": "8c84adfbad9405ae1f582ba6e3f6a9b39db14bbf8ac20e96bee1d03e9d6be47d",
    "after_sha256": "9b16bcef0cd08741f84c1e256965781cb0bbd081ad2a9c37043bb46676b66c3d",
    "before_token_sha256": "e543d52f14e060954de2ae502a45f93a7c2d46534fc49e2533a6e99aa5142cfe",
    "after_token_sha256": "5e674d8b5fca5821a40fa1f46e4a8551c8e8f1c0536a7b12421e84e15a91c1d3",
    "edits": [
      {
        "start": 25,
        "stop": 30,
        "before": [],
        "after": [
          "\n",
          "\n",
          "# `set` grows the list one weight at a time. The maximum integer never\n",
          "# finishes that growth. A list holds at most this many weights.\n",
          "comptime MAX_MORPH_WEIGHTS = 16777216\n"
        ]
      },
      {
        "start": 63,
        "stop": 64,
        "before": [
          "            Error: If the count is negative.\n"
        ],
        "after": [
          "            Error: If the count is negative or above 16777216.\n"
        ]
      },
      {
        "start": 68,
        "stop": 70,
        "before": [],
        "after": [
          "        if count > MAX_MORPH_WEIGHTS:\n",
          "            raise Error(\"A morph weight count is larger than this port stores\")\n"
        ]
      },
      {
        "start": 127,
        "stop": 129,
        "before": [
          "            Error: If the target is negative or the weight is not a number.\n"
        ],
        "after": [
          "            Error: If the target is negative or at least 16777216, or the\n",
          "                weight is not a number.\n"
        ]
      },
      {
        "start": 132,
        "stop": 134,
        "before": [],
        "after": [
          "        if target >= MAX_MORPH_WEIGHTS:\n",
          "            raise Error(\"A morph target index is larger than this port stores\")\n"
        ]
      }
    ]
  },
  "core/raycaster.mojo": {
    "before_sha256": "102bc263484bcd5a696945731ac66a04dd28c2ebec4d6657ff168c7d377df0a3",
    "after_sha256": "d02b0a9223ede06531914509c96a6ea76bce3c4bd148098075c0389c5e19ac7f",
    "before_token_sha256": "2944060ec74335d7ea17f449f04f1e5d1da312dfa1f95f76187f9090bc353be6",
    "after_token_sha256": "d4bd78bbf4b636b2ce9a9d581d6a96d5f456b02a8098fdab9145138c92d75241",
    "edits": [
      {
        "start": 621,
        "stop": 622,
        "before": [
          "        is at (i + 0.5, j + 0.5).\n"
        ],
        "after": [
          "        is at (i + 0.5, j + 0.5). A side past 2^24 is divided in `Float64`.\n"
        ]
      },
      {
        "start": 636,
        "stop": 647,
        "before": [
          "        self.set_from_camera(\n",
          "            Vector2(\n",
          "                x / Float32(width) * 2 - 1,\n",
          "                1 - y / Float32(height) * 2,\n",
          "            ),\n",
          "            camera,\n",
          "            scene,\n",
          "        )\n"
        ],
        "after": [
          "        # A `Float32` side past 2^24 is not that side, so the last pixel\n",
          "        # reads as the edge. A smaller image keeps the `Float32` quotient.\n",
          "        var nx: Float32\n",
          "        var ny: Float32\n",
          "        if width > 16777216 or height > 16777216:\n",
          "            nx = Float32(Float64(x) / Float64(width) * 2 - 1)\n",
          "            ny = Float32(1 - Float64(y) / Float64(height) * 2)\n",
          "        else:\n",
          "            nx = x / Float32(width) * 2 - 1\n",
          "            ny = 1 - y / Float32(height) * 2\n",
          "        self.set_from_camera(Vector2(nx, ny), camera, scene)\n"
        ]
      }
    ]
  },
  "extensions/carla/agents.mojo": {
    "before_sha256": "76fdfa47c0504e409b2c2655fb4fdff1843fb7cdaf316ac4c2845ed4361ec6ab",
    "after_sha256": "0789e9056ca117b2474f7daede991044a7b885f03175f606af55ad2871d472d6",
    "before_token_sha256": "017d52aeb521978419b74767bab3ac3b4e18d78f0ae4066e2db858c63138b4df",
    "after_token_sha256": "0a33a16cdc44ca1fd5479d0121a414752a788a10d8d524426650924ed98553e0",
    "edits": [
      {
        "start": 46,
        "stop": 47,
        "before": [],
        "after": [
          "from std.math import isfinite\n"
        ]
      },
      {
        "start": 815,
        "stop": 818,
        "before": [
          "            Error: If the direction is not a valid road option, or a map\n"
        ],
        "after": [
          "            Error: If the direction is not a valid road option, the step\n",
          "                is not a finite positive distance, the plan or the lane\n",
          "                change count is larger than this port drives, or a map\n"
        ]
      },
      {
        "start": 826,
        "stop": 834,
        "before": [],
        "after": [
          "        if not isfinite(step) or not (step > 0):\n",
          "            raise Error(\"A lane plan step must be a finite positive distance\")\n",
          "        if lane_changes > 16777216:\n",
          "            raise Error(\"A lane change count is larger than this port drives\")\n",
          "        if not (same / step < Float64(16777216)) or not (\n",
          "            other / step < Float64(16777216)\n",
          "        ):\n",
          "            raise Error(\"A lane plan is larger than this port drives\")\n"
        ]
      },
      {
        "start": 877,
        "stop": 878,
        "before": [
          "        distance += Float64(\n"
        ],
        "after": [
          "        var moved = Float64(\n"
        ]
      },
      {
        "start": 880,
        "stop": 884,
        "before": [],
        "after": [
          "        # A step that stays put never covers the distance.\n",
          "        if not (moved > 0):\n",
          "            return False\n",
          "        distance += moved\n"
        ]
      }
    ]
  },
  "extensions/carla/agents_route.mojo": {
    "before_sha256": "3a42c429be8013319fb9e60cbd92ffcfc8b5ce68e446ec47d3b1e5e1b71f782c",
    "after_sha256": "e53221dee2acec98cee82cb2191aa0d713eee2c0f3b202d6454c569c3438c939",
    "before_token_sha256": "6d82804020610531b865583ab7f238a17d029e25714fa29cf6a7988081ee8133",
    "after_token_sha256": "eaae55a6da0443d32fd1afed603e8c398c8c7fedd5ca0d09ff16bd3876b5f477",
    "edits": [
      {
        "start": 12,
        "stop": 15,
        "before": [
          "   `sampling_resolution`, and stops one resolution short of the exit.\n"
        ],
        "after": [
          "   `sampling_resolution`, and stops one resolution short of the exit. The\n",
          "   resolution must be a finite distance that moves a waypoint. A lane that\n",
          "   needs more than 16777216 samples is refused.\n"
        ]
      },
      {
        "start": 74,
        "stop": 75,
        "before": [
          "from extensions.carla.map import Map, Waypoint\n"
        ],
        "after": [
          "from extensions.carla.map import EPSILON, Map, Waypoint\n"
        ]
      },
      {
        "start": 85,
        "stop": 86,
        "before": [
          "from std.math import floor, sqrt\n"
        ],
        "after": [
          "from std.math import floor, isfinite, sqrt\n"
        ]
      },
      {
        "start": 94,
        "stop": 95,
        "before": [],
        "after": [
          "comptime _MAX_ROUTE_SAMPLES = 16777216\n"
        ]
      },
      {
        "start": 255,
        "stop": 261,
        "before": [],
        "after": [
          "def _require_route_samples(span: Float64, resolution: Float64) raises:\n",
          "    # The walk takes one sample about every resolution along the lane.\n",
          "    if not (span / resolution < Float64(_MAX_ROUTE_SAMPLES)):\n",
          "        raise Error(\"A route sample count is larger than this port drives\")\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 329,
        "stop": 332,
        "before": [
          "            Error: If the resolution is not more than zero, or a map query\n",
          "                fails.\n"
        ],
        "after": [
          "            Error: If the resolution is not a finite distance more than\n",
          "                zero, does not move a waypoint, a lane needs more samples\n",
          "                than this port drives, or a map query fails.\n"
        ]
      },
      {
        "start": 333,
        "stop": 341,
        "before": [
          "        if not (sampling_resolution.value > 0.0):\n",
          "            raise Error(\"The sampling resolution must be more than zero\")\n"
        ],
        "after": [
          "        var spacing = Float64(sampling_resolution.value)\n",
          "        if not isfinite(spacing) or not (spacing > 0.0):\n",
          "            raise Error(\n",
          "                \"The sampling resolution must be a finite distance more than\"\n",
          "                \" zero\"\n",
          "            )\n",
          "        if not (spacing > EPSILON):\n",
          "            raise Error(\"A route sample step must move the waypoint\")\n"
        ]
      },
      {
        "start": 375,
        "stop": 376,
        "before": [],
        "after": [
          "                _require_route_samples(map.road(pair[0].road_id).length, res)\n"
        ]
      },
      {
        "start": 467,
        "stop": 468,
        "before": [],
        "after": [
          "            _require_route_samples(map.road(end.road_id).length, res)\n"
        ]
      }
    ]
  },
  "extensions/carla/cameras.mojo": {
    "before_sha256": "f4c1bd63d6a68df99b23db9f668f8de29a50260c587c97f65d0f5e5ab80f7dd0",
    "after_sha256": "1635205c929008c0fe3eae1eb77c363d1cbb6927572f8dbd76eee4b3a7e7c17a",
    "before_token_sha256": "b631e1dbe6630902a5c0522836b854066a038d20ad40fe8bfc1015cad22008fb",
    "after_token_sha256": "64b062c8938248045dd97ea3de8dbc3294922196b6efc057bc8a3f52a8c9a352",
    "edits": [
      {
        "start": 944,
        "stop": 967,
        "before": [],
        "after": [
          "def _require_crossing_step(\n",
          "    previous: Float32, current: Float32, step: Float32\n",
          ") raises:\n",
          "    \"\"\"Refuse a contrast step that does not finish the crossing walk.\n",
          "\n",
          "    The walk adds `step` when the pixel rises and subtracts it when the\n",
          "    pixel falls. A step that leaves either gray level unchanged never\n",
          "    finishes.\n",
          "\n",
          "    Args:\n",
          "        previous: The gray level of the last frame.\n",
          "        current: The gray level of this frame.\n",
          "        step: The positive contrast threshold for this direction.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the step does not change the previous level or the\n",
          "            current level.\n",
          "    \"\"\"\n",
          "    var delta = step if current >= previous else -step\n",
          "    if previous + delta == previous or current + delta == current:\n",
          "        raise Error(\"An event camera crossing count is larger than this port\")\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 1031,
        "stop": 1032,
        "before": [
          "            Error: If the frame's size is not the camera's, or the time is\n"
        ],
        "after": [
          "            Error: If the frame's size is not the camera's, the time is\n"
        ]
      },
      {
        "start": 1033,
        "stop": 1035,
        "before": [
          "                an `Int`.\n"
        ],
        "after": [
          "                an `Int`, the settings are no longer valid, or the\n",
          "                contrast step does not change either gray level.\n"
        ]
      },
      {
        "start": 1048,
        "stop": 1049,
        "before": [],
        "after": [
          "        self.config.validate()\n"
        ]
      },
      {
        "start": 1088,
        "stop": 1089,
        "before": [],
        "after": [
          "                _require_crossing_step(it, itdt, c)\n"
        ]
      }
    ]
  },
  "extensions/carla/geometry.mojo": {
    "before_sha256": "374fd1621142ec8354a29b24357503db7f45ce419cb39089b913b5c39b4e983e",
    "after_sha256": "94c59e3951b4137461c3f0f2d4c897e81b7a4dcb21d793feb0e4c8f8fa34cf4a",
    "before_token_sha256": "c75e56e0b6863b5676c988ab3570695b68daccfbffc5f942417ce1e330616934",
    "after_token_sha256": "2f3821c1d5ae94346906ef716563b0daf6fbb3e3970c83b47cb9ad6480e6da8c",
    "edits": [
      {
        "start": 782,
        "stop": 787,
        "before": [],
        "after": [
          "            # A finite count past the query budget does not finish this loop.\n",
          "            if work >= 4194304.0:\n",
          "                raise Error(\n",
          "                    \"Spiral derivative work exceeds its spiral work limit\"\n",
          "                )\n"
        ]
      }
    ]
  },
  "extensions/carla/lane_geometry.mojo": {
    "before_sha256": "c43bf5bff2304e580beb59d1d10b125f04b1c5e7bc7897784bed54e2dd93d49b",
    "after_sha256": "f0a4900cc046cf42e925ed912b6557db494eeab3f342a71d72387fe49c667be5",
    "before_token_sha256": "5cc12dddb825ab15509621d3faf51f14cf40d19cdbb7d248a840190765b3c144",
    "after_token_sha256": "ac81b8c4a560139c98b16a963c3bd057ed3ce894e38aa5a0d5ce5f0823734859",
    "edits": [
      {
        "start": 11,
        "stop": 13,
        "before": [
          "scalar witnesses with an ideal trigonometric or moment approximation.\n"
        ],
        "after": [
          "scalar witnesses with an ideal trigonometric or moment approximation. A\n",
          "spiral derivative also refuses a piece count past the query work limit.\n"
        ]
      },
      {
        "start": 54,
        "stop": 56,
        "before": [
          "        Error: If a SPIRAL uses an unsupported arithmetic mode.\n"
        ],
        "after": [
          "        Error: If a SPIRAL uses an unsupported arithmetic mode, or its\n",
          "            piece count passes the query work limit.\n"
        ]
      },
      {
        "start": 133,
        "stop": 138,
        "before": [
          "    var pieces = 1 + Int(ceil(d * (1.0 + reach)))\n"
        ],
        "after": [
          "    # The public geometry query refuses this estimate before `Int` conversion.\n",
          "    var work = ceil(d * (1.0 + reach))\n",
          "    if not isfinite(work) or work >= 9223372036854775807.0 or work >= 4194304.0:\n",
          "        raise Error(\"Geometry query exceeds its spiral work limit\")\n",
          "    var pieces = 1 + Int(work)\n"
        ]
      },
      {
        "start": 202,
        "stop": 205,
        "before": [],
        "after": [
          "        # A finite count past the query budget does not finish this loop.\n",
          "        if work >= 4194304.0:\n",
          "            raise Error(\"Spiral derivative work exceeds its spiral work limit\")\n"
        ]
      }
    ]
  },
  "extensions/carla/lidar.mojo": {
    "before_sha256": "919e2efbb74445d59c45dd7ae32b4ba21f6558cf9115b2d0d15c6ce24d5c8783",
    "after_sha256": "7e6c49a3e8ec17858eafbc74b7051492da1f9da6c6f7302010b5ff38c42741db",
    "before_token_sha256": "17e7bf74b87e3013c1ed6b97a9ea4b3dbe72548fd0b926618c31adf081749824",
    "after_token_sha256": "2639355bf471ab087d2389ef4caf5551defb7d39e98ebfd12209b93502554880",
    "edits": [
      {
        "start": 28,
        "stop": 29,
        "before": [
          "from std.math import cos, exp, log, sin, sqrt, trunc\n"
        ],
        "after": [
          "from std.math import cos, exp, isfinite, log, sin, sqrt, trunc\n"
        ]
      },
      {
        "start": 42,
        "stop": 63,
        "before": [],
        "after": [
          "\n",
          "\n",
          "# A laser angle is a Float32, and the maximum integer never finishes the\n",
          "# laser list.\n",
          "comptime MAX_LIDAR_CHANNELS = 16777216\n",
          "\n",
          "\n",
          "def require_lidar_channels(channels: Int) raises:\n",
          "    \"\"\"Refuse a LiDAR channel count this port cannot cast.\n",
          "\n",
          "    Nothing. The call returns when the count is at most 16777216. A\n",
          "    count below one is left for `validate`.\n",
          "\n",
          "    Args:\n",
          "        channels: How many lasers.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the count is above 16777216.\n",
          "    \"\"\"\n",
          "    if channels > MAX_LIDAR_CHANNELS:\n",
          "        raise Error(\"A LiDAR channel count is larger than this port casts\")\n"
        ]
      },
      {
        "start": 135,
        "stop": 136,
        "before": [],
        "after": [
          "        require_lidar_channels(self.channels)\n"
        ]
      },
      {
        "start": 171,
        "stop": 172,
        "before": [
          "    def laser_angles(self) -> List[Angle]:\n"
        ],
        "after": [
          "    def laser_angles(self) raises -> List[Angle]:\n"
        ]
      },
      {
        "start": 177,
        "stop": 180,
        "before": [],
        "after": [
          "\n",
          "        Raises:\n",
          "            Error: If the channel count is above 16777216.\n"
        ]
      },
      {
        "start": 181,
        "stop": 182,
        "before": [],
        "after": [
          "        require_lidar_channels(self.channels)\n"
        ]
      },
      {
        "start": 193,
        "stop": 194,
        "before": [
          "    def points_per_laser(self, tick: Duration) -> Int:\n"
        ],
        "after": [
          "    def points_per_laser(self, tick: Duration) raises -> Int:\n"
        ]
      },
      {
        "start": 195,
        "stop": 199,
        "before": [],
        "after": [
          "\n",
          "        The quotient and its rounding are `Float32`, as CARLA's\n",
          "        `RoundHalfFromZero(PointsPerSecond * DeltaTime / float(ChannelCount))`\n",
          "        is: 5 points a second on one channel for 0.7 seconds is 4 points.\n"
        ]
      },
      {
        "start": 206,
        "stop": 210,
        "before": [],
        "after": [
          "\n",
          "        Raises:\n",
          "            Error: If the rounded count is not finite or does not fit in\n",
          "                an integer.\n"
        ]
      },
      {
        "start": 216,
        "stop": 226,
        "before": [
          "        return Int(exact + 0.5)\n"
        ],
        "after": [
          "        var scaled = Float64(exact + 0.5)\n",
          "        # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "        # a count. A float below `-2^63` is not one either.\n",
          "        if (\n",
          "            not isfinite(scaled)\n",
          "            or scaled < -Float64(Int.MAX)\n",
          "            or scaled >= Float64(Int.MAX)\n",
          "        ):\n",
          "            raise Error(\"A LiDAR point count does not fit in an integer\")\n",
          "        return Int(scaled)\n"
        ]
      },
      {
        "start": 317,
        "stop": 319,
        "before": [
          "            or a mesh cannot be tested.\n"
        ],
        "after": [
          "            the point count does not fit in an integer, or a mesh cannot\n",
          "            be tested.\n"
        ]
      }
    ]
  },
  "extensions/carla/math.mojo": {
    "before_sha256": "9fa94b3bb8850c4f6d282ef70795004c2c1217f22fd1c1a6eee448c8ac62ee2e",
    "after_sha256": "fc4fa96bbb1470dc10a4ea894003055610ffb1d08e7d6b2558f204bb243045f0",
    "before_token_sha256": "30b49cf1a3c0a3c99f994d43ef50baf33bb2677f831b89c326df24999b121780",
    "after_token_sha256": "f23103f0beeea44bda9180ca0c955dd5e41e6cdee3eed4fd66447115144616c7",
    "edits": [
      {
        "start": 284,
        "stop": 289,
        "before": [
          "def generate_range(a: Int, b: Int) -> List[Int]:\n"
        ],
        "after": [
          "# Inclusive. A wider list does not finish.\n",
          "comptime _MAX_GENERATED_RANGE = 16777216\n",
          "\n",
          "\n",
          "def generate_range(a: Int, b: Int) raises -> List[Int]:\n"
        ]
      },
      {
        "start": 298,
        "stop": 301,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the list would hold more than 16777216 numbers.\n"
        ]
      },
      {
        "start": 302,
        "stop": 312,
        "before": [],
        "after": [
          "    var low = a\n",
          "    var high = b\n",
          "    if high < low:\n",
          "        low = b\n",
          "        high = a\n",
          "    # `high - low` overflows when the ends are too far apart.\n",
          "    if low < 0 and high > Int.MAX + low:\n",
          "        raise Error(\"A generated range is larger than this port walks\")\n",
          "    if high - low > _MAX_GENERATED_RANGE - 1:\n",
          "        raise Error(\"A generated range is larger than this port walks\")\n"
        ]
      },
      {
        "start": 313,
        "stop": 314,
        "before": [],
        "after": [
          "    var i = a\n"
        ]
      },
      {
        "start": 315,
        "stop": 316,
        "before": [
          "        for i in range(a, b + 1):  # pragma: no branch\n"
        ],
        "after": [
          "        while True:\n"
        ]
      },
      {
        "start": 317,
        "stop": 320,
        "before": [],
        "after": [
          "            if i == b:\n",
          "                break\n",
          "            i += 1\n"
        ]
      },
      {
        "start": 321,
        "stop": 322,
        "before": [
          "        for i in range(a, b - 1, -1):  # pragma: no branch\n"
        ],
        "after": [
          "        while True:\n"
        ]
      },
      {
        "start": 323,
        "stop": 326,
        "before": [],
        "after": [
          "            if i == b:\n",
          "                break\n",
          "            i -= 1\n"
        ]
      }
    ]
  },
  "extensions/carla/navigation_mesh.mojo": {
    "before_sha256": "9e02190556addad6e00c58b4c2416b83f51e88eb6ec2051d69533db2c271724a",
    "after_sha256": "19314a6e5db27de8843bbd93f52e9ac185c62af1e8fc71e5de54a79659015e9b",
    "before_token_sha256": "3e0cf9c47c85a955a9b8704bd6622b0a30ff15bf8c9f1a279fbd2835371f96dc",
    "after_token_sha256": "5a8ef52a66e00c7c183706ecb5dafdcddd5875fedefcd7a6cb9762f43c651fc6",
    "edits": [
      {
        "start": 14,
        "stop": 18,
        "before": [
          "  ends of each crosswalk. Each strip is a convex quad from the lane's two\n",
          "  edges, `Road.lane_corners`, which also raise a sidewalk by its curb. A\n"
        ],
        "after": [
          "  ends of each crosswalk. The resolution must be a finite distance more\n",
          "  than zero. A section that needs more than 16777216 stations is refused.\n",
          "  Each strip is a convex quad from the lane's two edges,\n",
          "  `Road.lane_corners`, which also raise a sidewalk by its curb. A\n"
        ]
      },
      {
        "start": 87,
        "stop": 89,
        "before": [],
        "after": [
          "# Stations along one section. A finer spacing does not finish.\n",
          "comptime _MAX_MESH_STATIONS = 16777216\n"
        ]
      },
      {
        "start": 1293,
        "stop": 1294,
        "before": [
          ") -> List[Float64]:\n"
        ],
        "after": [
          ") raises -> List[Float64]:\n"
        ]
      },
      {
        "start": 1295,
        "stop": 1298,
        "before": [],
        "after": [
          "    var span = end - start\n",
          "    if not (span / step < Float64(_MAX_MESH_STATIONS)):\n",
          "        raise Error(\"A navigation mesh is larger than this port walks\")\n"
        ]
      },
      {
        "start": 1328,
        "stop": 1331,
        "before": [
          "        Error: If the resolution is not more than zero, or a map query\n",
          "            fails.\n"
        ],
        "after": [
          "        Error: If the resolution is not a finite distance more than zero,\n",
          "            a section needs more stations than this port walks, or a map\n",
          "            query fails.\n"
        ]
      },
      {
        "start": 1332,
        "stop": 1337,
        "before": [
          "    if not (resolution.value > 0.0):\n",
          "        raise Error(\"The mesh resolution must be more than zero\")\n"
        ],
        "after": [
          "    var step = Float64(resolution.value)\n",
          "    if not isfinite(step) or not (step > 0.0):\n",
          "        raise Error(\n",
          "            \"The mesh resolution must be a finite distance more than zero\"\n",
          "        )\n"
        ]
      },
      {
        "start": 1339,
        "stop": 1339,
        "before": [
          "    var step = Float64(resolution.value)\n"
        ],
        "after": []
      }
    ]
  },
  "extensions/carla/physics/simulation.mojo": {
    "before_sha256": "999a5e3cf97a628c9238a6ede3f84fa01df8645190bb98fb385d5fcc541581f6",
    "after_sha256": "071d0d78f9da887d677b029ae0ecd20033192a24d3860eecf2b18261c775ebc1",
    "before_token_sha256": "f221d15a49c55e4c774e771d50602704e2535a29a988fffcab0b88e1339c3440",
    "after_token_sha256": "bc6ed8134531252fbe65935893e0612925485e94b37fe361da4978b66be71476",
    "edits": [
      {
        "start": 53,
        "stop": 57,
        "before": [],
        "after": [
          "\n",
          "# The most substeps one tick walks. `range` of `Int.MAX` never ends, and\n",
          "# a larger count is not an exact `Float32` divisor of the step.\n",
          "comptime MAX_PHYSICS_SUBSTEPS = 16777216\n"
        ]
      },
      {
        "start": 427,
        "stop": 429,
        "before": [
          "            Error: If the step is not more than zero, or `substeps` is\n",
          "                less than one.\n"
        ],
        "after": [
          "            Error: If the step is not more than zero, `substeps` is less\n",
          "                than one, or `substeps` is above 16777216.\n"
        ]
      },
      {
        "start": 432,
        "stop": 434,
        "before": [],
        "after": [
          "        if substeps > MAX_PHYSICS_SUBSTEPS:\n",
          "            raise Error(\"A physics substep count is larger than this port runs\")\n"
        ]
      }
    ]
  },
  "extensions/carla/radar.mojo": {
    "before_sha256": "cf8db5cb57b7010212de7688e0e4f10659a26185d70577b1543b2c7e6aae4428",
    "after_sha256": "79d31d62991aa60a35e008098fda25c9ba559e94c5823bbfe768061a5005f775",
    "before_token_sha256": "3488f9430a2195094123a95e7c0da06d21da8c22860be16252e3e6255ddb3cb3",
    "after_token_sha256": "5b88320412919d5c6913c514c919eb92d412317149d82b2071e56837c2c04ccf",
    "edits": [
      {
        "start": 49,
        "stop": 50,
        "before": [
          "from std.math import atan2, cos, sin, sqrt, tan\n"
        ],
        "after": [
          "from std.math import atan2, cos, isfinite, sin, sqrt, tan\n"
        ]
      },
      {
        "start": 124,
        "stop": 125,
        "before": [
          "    def points_in(self, tick: Duration) -> Int:\n"
        ],
        "after": [
          "    def points_in(self, tick: Duration) raises -> Int:\n"
        ]
      },
      {
        "start": 126,
        "stop": 129,
        "before": [],
        "after": [
          "\n",
          "        The product is a `Float32`, as CARLA's `PointsPerSecond *\n",
          "        DeltaTime` is: 10 points a second for 0.7 seconds is 7 points.\n"
        ]
      },
      {
        "start": 135,
        "stop": 139,
        "before": [],
        "after": [
          "\n",
          "        Raises:\n",
          "            Error: If the product is not finite or does not fit in an\n",
          "                integer.\n"
        ]
      },
      {
        "start": 140,
        "stop": 150,
        "before": [
          "        return Int(Float32(self.points_per_second) * tick.to(SECOND))\n"
        ],
        "after": [
          "        var count = Float64(Float32(self.points_per_second) * tick.to(SECOND))\n",
          "        # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "        # a count. A float below `-2^63` is not one either.\n",
          "        if (\n",
          "            not isfinite(count)\n",
          "            or count < -Float64(Int.MAX)\n",
          "            or count >= Float64(Int.MAX)\n",
          "        ):\n",
          "            raise Error(\"A radar point count does not fit in an integer\")\n",
          "        return Int(count)\n"
        ]
      },
      {
        "start": 309,
        "stop": 311,
        "before": [
          "                or the scene cannot be tested.\n"
        ],
        "after": [
          "                the point count does not fit in an integer, or the scene\n",
          "                cannot be tested.\n"
        ]
      }
    ]
  },
  "extensions/carla/render_post.mojo": {
    "before_sha256": "8fe64d4c0ba39b549e714e640b2283d70d60a1bdf1816497bc295319b2f009c7",
    "after_sha256": "24c2f807ef5cc5d1b6025aa951feedb8c33d2df665185c63bb91a996de7b73fb",
    "before_token_sha256": "189415ad4283a0adcd4ddbf37d951d494da95de78177d19cf1ca37d86d029dfb",
    "after_token_sha256": "32cfd69e0b0348cfbb05bbd453d4014e48f3916f1c6aac0581bae51f52ded2bb",
    "edits": [
      {
        "start": 34,
        "stop": 35,
        "before": [
          "from math.utils import SeededRandom\n"
        ],
        "after": [
          "from math.utils import SeededRandom, texel_ndc, texel_ndc_up\n"
        ]
      },
      {
        "start": 132,
        "stop": 134,
        "before": [
          "                the near plane and 1 at the far.\n"
        ],
        "after": [
          "                the near plane and 1 at the far. A side above 2^23\n",
          "                measures the pixel center in `Float64`.\n"
        ]
      },
      {
        "start": 138,
        "stop": 140,
        "before": [
          "        var u = (Float32(x) + 0.5) / Float32(self.width) * 2 - 1\n",
          "        var v = 1 - (Float32(y) + 0.5) / Float32(self.height) * 2\n"
        ],
        "after": [
          "        var u = texel_ndc(x, self.width)\n",
          "        var v = texel_ndc_up(y, self.height)\n"
        ]
      },
      {
        "start": 290,
        "stop": 291,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 304,
        "stop": 307,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: Everything `RainSettings.streaks` raises.\n"
        ]
      },
      {
        "start": 506,
        "stop": 509,
        "before": [],
        "after": [
          "    A side above 8388608 pixels measures each pixel's center in\n",
          "    `Float64`.\n",
          "\n"
        ]
      },
      {
        "start": 522,
        "stop": 524,
        "before": [
          "            var u = (Float32(x) + 0.5) / w * 2 - 1\n",
          "            var v = (Float32(y) + 0.5) / h * 2 - 1\n"
        ],
        "after": [
          "            var u = texel_ndc(x, frame.width)\n",
          "            var v = texel_ndc(y, frame.height)\n"
        ]
      }
    ]
  },
  "extensions/carla/render_sky.mojo": {
    "before_sha256": "19e9c8493ffe16a79d24238b480be0904d8ccd490bcee0435554932b5897bff3",
    "after_sha256": "959a2e6bb586f0d10654f5f5bff2af261cab75da75db6e3fdd42b069133c3afc",
    "before_token_sha256": "aef0fe5e18e88bbc735cbb372bfa925c517cb1a80241977a53adcf5a71f09233",
    "after_token_sha256": "2728a28edf4e5744aae9e95d72b4d794cb2f874e9007fd0622e50328d46f6179",
    "edits": [
      {
        "start": 70,
        "stop": 71,
        "before": [],
        "after": [
          "from math.utils import texel_ndc\n"
        ]
      },
      {
        "start": 319,
        "stop": 321,
        "before": [],
        "after": [
          "    A face above 8388608 texels measures the center in `Float64`.\n",
          "\n"
        ]
      },
      {
        "start": 330,
        "stop": 338,
        "before": [
          "    var a = (Float32(x) + 0.5) / Float32(size) * 2 - 1\n",
          "    var b = (Float32(y) + 0.5) / Float32(size) * 2 - 1\n"
        ],
        "after": [
          "    var a: Float32\n",
          "    var b: Float32\n",
          "    if size > 8388608:\n",
          "        a = texel_ndc(x, size)\n",
          "        b = texel_ndc(y, size)\n",
          "    else:\n",
          "        a = (Float32(x) + 0.5) / Float32(size) * 2 - 1\n",
          "        b = (Float32(y) + 0.5) / Float32(size) * 2 - 1\n"
        ]
      }
    ]
  },
  "extensions/carla/render_textures.mojo": {
    "before_sha256": "d79c12e55dff9ad3ca829f7219365a8bbe1ac5ca6a6be799ce10cc56e0feb42b",
    "after_sha256": "12a198cbcef1d0c43df2b8feebfcf4c332f8e1366295adf3aade78ffb46ea16a",
    "before_token_sha256": "3d34e513e8b4ffd016d7e7c91073de83c9627da8581cb36f645d7ce0b5bd38ac",
    "after_token_sha256": "e6d04d26ffa17bb84e85a97884e472e2eba39e9719efc3b02919d49786787743",
    "edits": [
      {
        "start": 31,
        "stop": 32,
        "before": [
          "The sizes and colors are this port's own choices.\n"
        ],
        "after": [
          "The sizes and colors are this port's own choices. A side whose texel buffer does not fit in an integer is refused.\n"
        ]
      },
      {
        "start": 160,
        "stop": 162,
        "before": [
          "        Error: If `size` is less than one, or the heights are not\n",
          "            `size * size`.\n"
        ],
        "after": [
          "        Error: If `size` is less than one, its texel buffer does not fit,\n",
          "            or the heights are not `size * size`.\n"
        ]
      },
      {
        "start": 231,
        "stop": 232,
        "before": [
          "        Error: If `size` is less than one.\n"
        ],
        "after": [
          "        Error: If `size` is less than one, or its texel buffer does not fit.\n"
        ]
      },
      {
        "start": 283,
        "stop": 285,
        "before": [
          "        Error: If `size` or `slabs` is less than one.\n"
        ],
        "after": [
          "        Error: If `size` is less than one, its texel buffer does not fit,\n",
          "            or `slabs` is less than one.\n"
        ]
      },
      {
        "start": 338,
        "stop": 339,
        "before": [
          "        Error: If `size` is less than one.\n"
        ],
        "after": [
          "        Error: If `size` is less than one, or its texel buffer does not fit.\n"
        ]
      },
      {
        "start": 375,
        "stop": 376,
        "before": [
          "        Error: If `size` is less than one.\n"
        ],
        "after": [
          "        Error: If `size` is less than one, or its texel buffer does not fit.\n"
        ]
      },
      {
        "start": 640,
        "stop": 651,
        "before": [
          "    \"\"\"Refuse a texture of no texels.\"\"\"\n"
        ],
        "after": [
          "    \"\"\"Refuse a texture of no texels, or one whose texel buffer wraps.\n",
          "\n",
          "    Four bytes a texel is the largest product these builders allocate.\n",
          "\n",
          "    Args:\n",
          "        size: Texels on a side.\n",
          "\n",
          "    Raises:\n",
          "        Error: If `size` is less than one, or `4 * size * size` does not\n",
          "            fit in an integer.\n",
          "    \"\"\"\n"
        ]
      },
      {
        "start": 653,
        "stop": 655,
        "before": [],
        "after": [
          "    if size > (Int.MAX // 4) // size:\n",
          "        raise Error(\"A texture is larger than this port builds\")\n"
        ]
      }
    ]
  },
  "extensions/carla/render_weather.mojo": {
    "before_sha256": "4f6fbd3dd6597a05900dd64a4dcc799f2e9ffed0b22be63bc96c2d0a6f1822c4",
    "after_sha256": "b227b692f690d6614d16f055927ade3b3fdcaf2237b03e5d2ff8df2a28ba3804",
    "before_token_sha256": "e45de6f4e05e534ef922e3a42d871ad85e6873f6f57df0ad315e4f413fa880dc",
    "after_token_sha256": "1be4294dd3c81c829de4a3a292d33ad376e488e443ea03ade3ac074fa32ed1ef",
    "edits": [
      {
        "start": 67,
        "stop": 68,
        "before": [
          "from std.math import cos, exp, pow, sin, sqrt\n"
        ],
        "after": [
          "from std.math import cos, exp, isfinite, pow, sin, sqrt\n"
        ]
      },
      {
        "start": 126,
        "stop": 129,
        "before": [],
        "after": [
          "# The most streaks one image draws. A larger count does not finish, and\n",
          "# `Int` of a count past 2^63 is not that count.\n",
          "comptime MAX_RAIN_STREAKS = 16777216\n"
        ]
      },
      {
        "start": 615,
        "stop": 616,
        "before": [
          "    def streaks(self, width: Int, height: Int) -> Int:\n"
        ],
        "after": [
          "    def streaks(self, width: Int, height: Int) raises -> Int:\n"
        ]
      },
      {
        "start": 623,
        "stop": 629,
        "before": [
          "            The density times the pixels, in millions, rounded down.\n"
        ],
        "after": [
          "            The density times the pixels, in millions, rounded down. Zero\n",
          "            when a side is below one.\n",
          "\n",
          "        Raises:\n",
          "            Error: If the density is not a finite number that is not\n",
          "                negative, or the streak count is above 16777216.\n"
        ]
      },
      {
        "start": 630,
        "stop": 641,
        "before": [
          "        return Int(self.density * Float32(width * height) / 1e6)\n"
        ],
        "after": [
          "        if not isfinite(self.density) or not (self.density >= 0):\n",
          "            raise Error(\n",
          "                \"A rain density must be a finite number that is not negative\"\n",
          "            )\n",
          "        if width < 1 or height < 1:\n",
          "            return 0\n",
          "        var pixels = Float64(width) * Float64(height)\n",
          "        var count = pixels * Float64(self.density) / 1e6\n",
          "        if not (count < Float64(MAX_RAIN_STREAKS + 1)):\n",
          "            raise Error(\"A rain streak count is larger than this port draws\")\n",
          "        return Int(count)\n"
        ]
      }
    ]
  },
  "extensions/carla/semantic_lidar.mojo": {
    "before_sha256": "057c4be981b28dcd16a5a536706eea66bc6ecb547ac75d8aa8dae7e33aae6f55",
    "after_sha256": "b0f93217b8a55ca63c5904397673f57d264efa8b46e5b3691b2d68eb93269b84",
    "before_token_sha256": "f2c83ee9bffd103e60a6f508ae0a667ab7ffa70e8160e6c377af66960e4547e8",
    "after_token_sha256": "589c877baf5a5a2a7f3e214719bcc87afcf464a488e50f14d65b3ba135ed334a",
    "edits": [
      {
        "start": 63,
        "stop": 64,
        "before": [],
        "after": [
          "    isfinite,\n"
        ]
      },
      {
        "start": 312,
        "stop": 333,
        "before": [
          "def _per_laser(description: LidarDescription, tick: Duration) -> Int:\n",
          "    return round_half_from_zero(\n",
          "        Float32(description.points_per_second)\n",
          "        * tick.to(SECOND)\n",
          "        / Float32(description.channels)\n",
          "    )\n"
        ],
        "after": [
          "def _per_laser(description: LidarDescription, tick: Duration) raises -> Int:\n",
          "    # The same `Float32` quotient as `points_per_laser`, as CARLA has it,\n",
          "    # and one past 2^63 is refused before `Int`.\n",
          "    return description.points_per_laser(tick)\n",
          "\n",
          "\n",
          "def require_lidar_rays(channels: Int, per_laser: Int) raises:\n",
          "    \"\"\"Refuse a ray list whose length does not fit.\n",
          "\n",
          "    Nothing. The call returns when `channels * per_laser` fits in an\n",
          "    integer. A laser with no ray has an empty list.\n",
          "\n",
          "    Args:\n",
          "        channels: How many lasers.\n",
          "        per_laser: How many rays one laser fires.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the product does not fit in an integer.\n",
          "    \"\"\"\n",
          "    if per_laser > 0 and channels > Int.MAX // per_laser:\n",
          "        raise Error(\"A LiDAR ray count is larger than this port casts\")\n"
        ]
      },
      {
        "start": 397,
        "stop": 398,
        "before": [],
        "after": [
          "    require_lidar_rays(description.channels, per_laser)\n"
        ]
      },
      {
        "start": 500,
        "stop": 501,
        "before": [],
        "after": [
          "    require_lidar_rays(description.channels, per_laser)\n"
        ]
      },
      {
        "start": 539,
        "stop": 541,
        "before": [
          "        Error: If the resolution or field of view is nonfinite.\n"
        ],
        "after": [
          "        Error: If the resolution or field of view is nonfinite, or the\n",
          "            ray count does not fit in an integer.\n"
        ]
      },
      {
        "start": 550,
        "stop": 558,
        "before": [
          "    return round_half_from_zero(fov / step)\n"
        ],
        "after": [
          "    var quotient = fov / step\n",
          "    var scaled = Float64(quotient) + 0.5\n",
          "    # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "    # a count. The field of view is held at zero or more and the step is\n",
          "    # positive, so the quotient is never negative.\n",
          "    if not isfinite(scaled) or scaled >= Float64(Int.MAX):\n",
          "        raise Error(\"A LiDAR point count does not fit in an integer\")\n",
          "    return round_half_from_zero(quotient)\n"
        ]
      },
      {
        "start": 592,
        "stop": 593,
        "before": [],
        "after": [
          "    require_lidar_rays(description.channels, per_laser)\n"
        ]
      }
    ]
  },
  "extensions/carla/sensor_data.mojo": {
    "before_sha256": "68338226a0a0a1cee1176aeb01224d3916c2c51fd3a3eaf9afc0595baf256b8c",
    "after_sha256": "ce3e3089c75c25090f534c988506c2739d494ff4269ee5014b068af4e66481c8",
    "before_token_sha256": "e9502e3b74e79fdb593124723da0d0b06f477f77a4766a9a1f1bac43d1324afc",
    "after_token_sha256": "9aae2d5b5572bac1ab5e85f83a8eafe285e804b0f122db1cd57e3b9b6e4a8cdd",
    "edits": [
      {
        "start": 459,
        "stop": 461,
        "before": [
          "        Error: If the angle or flow length is invalid.\n"
        ],
        "after": [
          "        Error: If the angle or flow length is invalid, or the image is\n",
          "            larger than this port writes.\n"
        ]
      },
      {
        "start": 480,
        "stop": 482,
        "before": [
          "        Error: If `flow` does not hold two numbers a pixel.\n"
        ],
        "after": [
          "        Error: If the field of view is invalid, `flow` does not hold two\n",
          "            numbers a pixel, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 484,
        "stop": 486,
        "before": [],
        "after": [
          "    if width > 0 and height > (Int.MAX // 2) // width:\n",
          "        raise Error(\"An optical flow image is larger than this port writes\")\n"
        ]
      }
    ]
  },
  "extensions/carla/traffic_light.mojo": {
    "before_sha256": "42e87ab1f73a8d23817bef09364c737a3a92ab559c579929614e85b5439dc961",
    "after_sha256": "c5c9a860a7d6668d2fa0a803a20fce84bd598512d42b3ebc98f01c27af9d939e",
    "before_token_sha256": "3c94429328a58f0b2e4f675b75aa43411327e81ca946da67b75fe163999a3d6b",
    "after_token_sha256": "bf96b9494c914078edec4644ff3419b66fe61b471b96cb15d51ab8998cc8500e",
    "edits": [
      {
        "start": 57,
        "stop": 58,
        "before": [],
        "after": [
          "from extensions.carla.math import generate_range\n"
        ]
      },
      {
        "start": 62,
        "stop": 63,
        "before": [],
        "after": [
          "from std.math import isfinite\n"
        ]
      },
      {
        "start": 672,
        "stop": 674,
        "before": [
          "        Error: If the id is not valid.\n"
        ],
        "after": [
          "        Error: If the id is not valid, or a lane range is larger than\n",
          "            this port walks.\n"
        ]
      },
      {
        "start": 679,
        "stop": 683,
        "before": [
          "            var lanes = List[Int]()\n",
          "            if v.from_lane.value < v.to_lane.value:\n",
          "                # from < to, so the range holds two lanes at least.\n",
          "                for lane in range(\n",
          "                    v.from_lane.value, v.to_lane.value + 1\n",
          "                ):  # pragma: no branch\n",
          "                    lanes.append(lane)\n",
          "            else:\n",
          "                # from >= to, so the range holds one lane at least.\n",
          "                for lane in range(\n",
          "                    v.from_lane.value, v.to_lane.value - 1, -1\n",
          "                ):  # pragma: no branch\n",
          "                    lanes.append(lane)\n",
          "            # Either range above holds one lane at least.\n",
          "            for lane in lanes:  # pragma: no branch\n"
        ],
        "after": [
          "            # The range holds both its ends, so one lane at least.\n",
          "            for lane in generate_range(\n",
          "                v.from_lane.value, v.to_lane.value\n",
          "            ):  # pragma: no branch\n"
        ]
      },
      {
        "start": 711,
        "stop": 713,
        "before": [
          "        Error: If a map query fails.\n"
        ],
        "after": [
          "        Error: If the trigger extent is not finite, its one-meter steps\n",
          "            do not finish, or a map query fails.\n"
        ]
      },
      {
        "start": 717,
        "stop": 728,
        "before": [
          "    var x = Float32(-0.9) * trigger_volume.extent.x\n",
          "    var end = Float32(0.9) * trigger_volume.extent.x\n"
        ],
        "after": [
          "    var half = trigger_volume.extent.x\n",
          "    if not isfinite(half):\n",
          "        raise Error(\"A traffic light trigger extent must be finite\")\n",
          "    var x = Float32(-0.9) * half\n",
          "    var end = Float32(0.9) * half\n",
          "    # A step of one meter that does not move never leaves the trigger.\n",
          "    if x < end and not (x + 1 > x):\n",
          "        raise Error(\"A traffic light trigger is larger than this port walks\")\n",
          "    var span = Float64(end) - Float64(x)\n",
          "    if x < end and not (span < Float64(16777216)):\n",
          "        raise Error(\"A traffic light trigger is larger than this port walks\")\n"
        ]
      }
    ]
  },
  "extensions/carla/traffic_sign.mojo": {
    "before_sha256": "8cb7e5a0fdc30d80e9589ec787b3fcd3c35219454ec5d3f6e7f6f67453ae6502",
    "after_sha256": "70997f536d06786103665c5c70aa9e710f0645df0bc5e67bfb57886b15cf370a",
    "before_token_sha256": "f32dcd5863bb397124025e84b698249f38fa53556b370b8c319d8febbc8a1dc8",
    "after_token_sha256": "57e68cf098ac1c1012e418880a087dcbf950c5b0b0de6e4675cc58958f200a50",
    "edits": [
      {
        "start": 84,
        "stop": 86,
        "before": [],
        "after": [
          "# One lap of a lane, in steps. A second lap does not finish.\n",
          "comptime _MAX_SIGN_STEPS = 16777216\n"
        ]
      },
      {
        "start": 234,
        "stop": 236,
        "before": [
          "        Error: If the id is not valid.\n"
        ],
        "after": [
          "        Error: If the id is not valid, or a lane range is larger than\n",
          "            this port walks.\n"
        ]
      },
      {
        "start": 289,
        "stop": 295,
        "before": [],
        "after": [
          "            var span = map.road(w.road_id).length\n",
          "            # A second lap of this lane does not finish.\n",
          "            if not (span / step < Float64(_MAX_SIGN_STEPS)):\n",
          "                raise Error(\"A sign check walks its lane more than once\")\n",
          "            var budget = Int(span / step) + 3\n",
          "            var taken = 0\n"
        ]
      },
      {
        "start": 296,
        "stop": 298,
        "before": [],
        "after": [
          "                if taken >= budget:\n",
          "                    raise Error(\"A sign check walks its lane more than once\")\n"
        ]
      },
      {
        "start": 303,
        "stop": 304,
        "before": [],
        "after": [
          "                taken += 1\n"
        ]
      },
      {
        "start": 321,
        "stop": 327,
        "before": [],
        "after": [
          "                    # A huge speed leaves this time unchanged, so a ring\n",
          "                    # of predecessors never ends.\n",
          "                    if not (remaining < item[0]):\n",
          "                        raise Error(\n",
          "                            \"A sign check cannot advance against its lane\"\n",
          "                        )\n"
        ]
      },
      {
        "start": 362,
        "stop": 364,
        "before": [
          "        Error: If the id is not valid.\n"
        ],
        "after": [
          "        Error: If the id is not valid, or a lane range is larger than\n",
          "            this port walks.\n"
        ]
      },
      {
        "start": 409,
        "stop": 411,
        "before": [
          "        Error: If the id is not valid.\n"
        ],
        "after": [
          "        Error: If the id is not valid, or a lane range is larger than\n",
          "            this port walks.\n"
        ]
      }
    ]
  },
  "extensions/humanoid/skeleton/head/hair/groom.mojo": {
    "before_sha256": "67f8ea34485c0f1a8b561dece38a933cdc5d0e6aea47d038196d68ee0b617fbd",
    "after_sha256": "48a2324a527b58e63546a562e168744656fbc8a02ba8f6c9aa3274b66ebc85e5",
    "before_token_sha256": "e7e6c80b6c258755e97cdad8c169705a4ff5236df2f3066a7a3c989b7a00af94",
    "after_token_sha256": "d355297e8a8460217cfa2f03c290b33817cbd7dcf2b6dfa252babeabb0c9f4cf",
    "edits": [
      {
        "start": 78,
        "stop": 79,
        "before": [
          "from std.math import acos, cos, max, min, pi, pow, sin, sqrt\n"
        ],
        "after": [
          "from std.math import acos, cos, isfinite, max, min, pi, pow, sin, sqrt\n"
        ]
      },
      {
        "start": 86,
        "stop": 88,
        "before": [],
        "after": [
          "# A larger try count does not finish. Each try walks the scalp.\n",
          "comptime MAX_ROOT_TRIES = 16777216\n"
        ]
      },
      {
        "start": 111,
        "stop": 114,
        "before": [],
        "after": [
          "# A guide's samples. A zero step never advances, and a count past 2^24\n",
          "# is not a Float32 index the strand can store.\n",
          "comptime MAX_HAIR_STEPS = 16777216\n"
        ]
      },
      {
        "start": 388,
        "stop": 389,
        "before": [
          "        if guides < 1 or guides > MAX_GUIDES:\n",
          "            raise Error(\"A groom's guides number one through 20000\")\n",
          "        if followers < 0 or followers > MAX_FOLLOWERS:\n",
          "            raise Error(\"A guide's followers number zero through 64\")\n"
        ],
        "after": [
          "        require_groom_counts(guides, followers, ROOT_TRIES)\n"
        ]
      },
      {
        "start": 708,
        "stop": 709,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 711,
        "stop": 712,
        "before": [],
        "after": [
          "    require_hair_steps(spec.step, target)\n"
        ]
      },
      {
        "start": 744,
        "stop": 791,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def require_groom_counts(guides: Int, followers: Int, root_tries: Int) raises:\n",
          "    \"\"\"Refuse a groom count this port cannot grow.\n",
          "\n",
          "    Nothing. The call returns when the guides are one through 20000,\n",
          "    the followers are zero through 64, and the root tries are zero\n",
          "    through 16777216.\n",
          "\n",
          "    Args:\n",
          "        guides: How many guide strands.\n",
          "        followers: How many follow strands round each guide.\n",
          "        root_tries: How many roots are tried for each guide.\n",
          "\n",
          "    Raises:\n",
          "        Error: If a guide count is outside one through 20000, a follower\n",
          "            count is outside zero through 64, or a root try count is\n",
          "            below zero or above 16777216.\n",
          "    \"\"\"\n",
          "    if guides < 1 or guides > MAX_GUIDES:\n",
          "        raise Error(\"A groom's guides number one through 20000\")\n",
          "    if followers < 0 or followers > MAX_FOLLOWERS:\n",
          "        raise Error(\"A guide's followers number zero through 64\")\n",
          "    if root_tries < 0:\n",
          "        raise Error(\"A groom's root tries must be zero or more\")\n",
          "    if root_tries > MAX_ROOT_TRIES:\n",
          "        raise Error(\"A groom's root try count is larger than this port grows\")\n",
          "\n",
          "\n",
          "def require_hair_steps(step: Float32, span: Float32) raises:\n",
          "    \"\"\"Refuse a hair step this port cannot walk.\n",
          "\n",
          "    Nothing. The call returns when `step` is a positive finite length\n",
          "    and `span / step` is at most 16777216.\n",
          "\n",
          "    Args:\n",
          "        step: How far one sample moves, in meters.\n",
          "        span: How far the walk may run, in meters.\n",
          "\n",
          "    Raises:\n",
          "        Error: If `step` is not a positive finite length, or the sample\n",
          "            count is above 16777216.\n",
          "    \"\"\"\n",
          "    if not isfinite(step) or not (step > 0):\n",
          "        raise Error(\"A hair step must be a positive length\")\n",
          "    if not (span / step <= Float32(MAX_HAIR_STEPS)):\n",
          "        raise Error(\"A hair step count is larger than this port grows\")\n"
        ]
      },
      {
        "start": 828,
        "stop": 832,
        "before": [
          "            not named or its file cannot be read, or if no guide finds a\n",
          "            root.\n"
        ],
        "after": [
          "            not named or its file cannot be read, if no guide finds a\n",
          "            root, if a guide, follower, or root try count is out of\n",
          "            range, or if a step is not a positive length or asks for more\n",
          "            than 16777216 samples.\n"
        ]
      },
      {
        "start": 833,
        "stop": 834,
        "before": [],
        "after": [
          "    require_groom_counts(spec.guides, spec.followers, spec.root_tries)\n"
        ]
      },
      {
        "start": 835,
        "stop": 838,
        "before": [],
        "after": [
          "    require_hair_steps(spec.step, spec.longest)\n",
          "    if spec.curl > 0:\n",
          "        require_hair_steps(spec.curl_length, spec.longest)\n"
        ]
      },
      {
        "start": 1174,
        "stop": 1175,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 1192,
        "stop": 1193,
        "before": [],
        "after": [
          "    require_hair_steps(step, length)\n"
        ]
      },
      {
        "start": 1214,
        "stop": 1215,
        "before": [
          ") -> Float32:\n"
        ],
        "after": [
          ") raises -> Float32:\n"
        ]
      },
      {
        "start": 1233,
        "stop": 1236,
        "before": [
          "    var count = max(1, Int(angle * (ra + rb) / 2 / spec.step))\n"
        ],
        "after": [
          "    var span = angle * (ra + rb) / Float32(2)\n",
          "    require_hair_steps(spec.step, span)\n",
          "    var count = max(1, Int(span / spec.step))\n"
        ]
      },
      {
        "start": 1264,
        "stop": 1265,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 1277,
        "stop": 1278,
        "before": [],
        "after": [
          "    require_hair_steps(step, length)\n"
        ]
      },
      {
        "start": 1295,
        "stop": 1296,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 1308,
        "stop": 1309,
        "before": [],
        "after": [
          "    require_hair_steps(step, length)\n"
        ]
      },
      {
        "start": 1326,
        "stop": 1327,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 1346,
        "stop": 1348,
        "before": [
          "    var climb = Int(\n",
          "        acos(min(Float32(1), max(Float32(-1), bottom.dot(first))))\n",
          "        * radius\n",
          "        / step\n"
        ],
        "after": [
          "    var climb_span = (\n",
          "        acos(min(Float32(1), max(Float32(-1), bottom.dot(first)))) * radius\n"
        ]
      },
      {
        "start": 1349,
        "stop": 1351,
        "before": [],
        "after": [
          "    require_hair_steps(step, climb_span)\n",
          "    var climb = Int(climb_span / step)\n"
        ]
      },
      {
        "start": 1355,
        "stop": 1358,
        "before": [
          "    var count = Int(turns * Float32(2 * pi) * radius / step) + 1\n"
        ],
        "after": [
          "    var wind = turns * Float32(2 * pi) * radius\n",
          "    require_hair_steps(step, wind)\n",
          "    var count = Int(wind / step) + 1\n"
        ]
      },
      {
        "start": 1371,
        "stop": 1372,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 1388,
        "stop": 1389,
        "before": [],
        "after": [
          "    require_hair_steps(spacing, total)\n"
        ]
      }
    ]
  },
  "extensions/physics/world.mojo": {
    "before_sha256": "24bfdb54d50fc9fc06eda2e3590ec7eea57705d9b626d3ceaee163bb58632144",
    "after_sha256": "e00619a06a4fca262493ae59e649d4793ea8125859991398d52c8fa5c596b69e",
    "before_token_sha256": "7766c152ed111b29bc21a0281ead78dff59b79f825ba3c59c974af94416e7a43",
    "after_token_sha256": "5de816dded9bc6c585ffb66c7cbc7d507f50cbeb54fe9aad8649ab1ab21eda08",
    "edits": [
      {
        "start": 196,
        "stop": 200,
        "before": [],
        "after": [
          "# Each solver pass walks every contact. The maximum integer never finishes.\n",
          "comptime MAX_SOLVER_ITERATIONS = 16777216\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 353,
        "stop": 356,
        "before": [
          "            Error: If the step is not more than zero and finite, or a\n",
          "                body's mode or mass state is inconsistent.\n"
        ],
        "after": [
          "            Error: If the step is not more than zero and finite, a\n",
          "                velocity or position iteration count is above 16777216,\n",
          "                or a body's mode or mass state is inconsistent.\n"
        ]
      },
      {
        "start": 361,
        "stop": 369,
        "before": [],
        "after": [
          "        if self.velocity_iterations > MAX_SOLVER_ITERATIONS:\n",
          "            raise Error(\n",
          "                \"A velocity iteration count is larger than this port solves\"\n",
          "            )\n",
          "        if self.position_iterations > MAX_SOLVER_ITERATIONS:\n",
          "            raise Error(\n",
          "                \"A position iteration count is larger than this port solves\"\n",
          "            )\n"
        ]
      }
    ]
  },
  "extensions/streamline/jitter.mojo": {
    "before_sha256": "51a7d80cf43c03ffcab21312fc2daee6af14276b710826a5695c1e1cc9245507",
    "after_sha256": "fb82fd941677db5e50a505498c0f84a8d62c1432c415ce9fe1fb10bdabd689ca",
    "before_token_sha256": "7d11d8b2fd787bf71088cb446b386b0e83b743867bcdbea53a5f23ee4df4ec6b",
    "after_token_sha256": "7e6d4b86803485e9094ca23f1215371306585859c6290932ed550581655f8901",
    "edits": [
      {
        "start": 42,
        "stop": 44,
        "before": [
          "        Error: If a size has a side below one pixel, or the render is wider\n",
          "            than the output.\n"
        ],
        "after": [
          "        Error: If a size has a side below one pixel, the render is wider\n",
          "            than the output, or the count does not fit in an integer.\n"
        ]
      },
      {
        "start": 50,
        "stop": 54,
        "before": [
          "    return Int(ceil(8.0 * ratio * ratio))\n"
        ],
        "after": [
          "    var wide = ceil(8.0 * ratio * ratio)\n",
          "    if not (wide < Float64(Int.MAX)):\n",
          "        raise Error(\"A jitter phase count does not fit in an integer\")\n",
          "    return Int(wide)\n"
        ]
      }
    ]
  },
  "extensions/streamline/sizing.mojo": {
    "before_sha256": "8da8084667f413d3354af700b2414bdbb0783033eeca55f8e7a60cf1768b7976",
    "after_sha256": "7067cb671c14249ec13a97be6af849b852bd209b182553af9a71cebb7104db9a",
    "before_token_sha256": "b06e15e58d0503294fde85bcc6f9e03844207c217c3911b00b850cb94de2bf3a",
    "after_token_sha256": "9b78bbf2091eb281b528cdea28ea967686ba7d4e31cea37650771d5b6f5808ef",
    "edits": [
      {
        "start": 77,
        "stop": 84,
        "before": [
          "    \"\"\"Return a side at a scale, to the nearest pixel and at least one.\"\"\"\n"
        ],
        "after": [
          "    \"\"\"Return a side at a scale, to the nearest pixel and at least one.\n",
          "\n",
          "    A scale of one keeps the side. `Float64` of a side at 2^63 rounds up,\n",
          "    so adding a half and casting that is not the side.\n",
          "    \"\"\"\n",
          "    if scale == 1:\n",
          "        return side\n"
        ]
      }
    ]
  },
  "extensions/streamline/upscaler.mojo": {
    "before_sha256": "7a4edcae38ae426f7cee81ba6f032c56aaded6ce1ca4741f941c5cdb8b9120d9",
    "after_sha256": "6df3bdfad985264fb06daebdc677adb0338b7278935012f0315eee0a40ae2672",
    "before_token_sha256": "6fd141f95745cc7004e7e54900412c9b3853456ecbfb8966598454c35b45ee02",
    "after_token_sha256": "9ff0b8295d41b23c5438867fa70ba3d32100ae617cbd036ba932f86aac67f36f",
    "edits": [
      {
        "start": 75,
        "stop": 77,
        "before": [
          "                output, or the colors are not `render` sized.\n"
        ],
        "after": [
          "                output, a pixel count does not fit in an integer, or the\n",
          "                colors are not `render` sized.\n"
        ]
      },
      {
        "start": 140,
        "stop": 142,
        "before": [
          "                the output, or the colors are not `render` sized.\n"
        ],
        "after": [
          "                the output, a pixel count does not fit in an integer, or\n",
          "                the colors are not `render` sized.\n"
        ]
      },
      {
        "start": 153,
        "stop": 157,
        "before": [],
        "after": [
          "        if render.width > Int.MAX // render.height:\n",
          "            raise Error(\"A render is larger than this port upscales\")\n",
          "        if output.width > Int.MAX // output.height:\n",
          "            raise Error(\"An output is larger than this port upscales\")\n"
        ]
      }
    ]
  },
  "geometries/capsule.mojo": {
    "before_sha256": "f26377f233ac53c93330e60a536cecc85adef9b272105185b9b4979f36621499",
    "after_sha256": "3bb7db6d72c8a2872e9a63559b8591bd13546b21527d887fd23864e8a7f6f6ef",
    "before_token_sha256": "ec77749fe46ddf01c789acbc18ad3efe08bad301aceaf28dae2bd05fcb1daaf7",
    "after_token_sha256": "1b102f09b491e19f752c3e06f1326c5c555638ddc37d70a2e118ceee411389c7",
    "edits": [
      {
        "start": 19,
        "stop": 26,
        "before": [],
        "after": [
          "\n",
          "## Input validation difference\n",
          "\n",
          "The radius and the length must be finite before vertices are generated.\n",
          "NaN and either infinity raise an error. This differs from the unchecked\n",
          "three.js r186 input path. Finite supported inputs keep their existing\n",
          "behavior. A length of zero stays a sphere.\n"
        ]
      },
      {
        "start": 29,
        "stop": 29,
        "before": [
          "from core.ordinal import require_non_negative\n"
        ],
        "after": []
      },
      {
        "start": 33,
        "stop": 34,
        "before": [],
        "after": [
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 38,
        "stop": 39,
        "before": [],
        "after": [
          "from math.finite import require_finite\n"
        ]
      },
      {
        "start": 71,
        "stop": 74,
        "before": [
          "        Error: If the radius is not positive, the length is negative, or\n",
          "            any segment count is too small.\n"
        ],
        "after": [
          "        Error: If the radius is not finite or not positive, the length is\n",
          "            not finite or is negative, any segment count is too small, or\n",
          "            the grid has more than 16777216 cells.\n"
        ]
      },
      {
        "start": 76,
        "stop": 81,
        "before": [
          "    require_non_negative(length.value, \"A capsule's length cannot be negative\")\n"
        ],
        "after": [
          "    require_finite(Float64(length.value), \"A capsule needs a finite length\")\n",
          "    # `not (x >= 0)`, not `x < 0`: NaN compares false both ways, so the\n",
          "    # < form would let it through.\n",
          "    if not (length.value >= 0):\n",
          "        raise Error(\"A capsule's length cannot be negative\")\n"
        ]
      },
      {
        "start": 89,
        "stop": 98,
        "before": [],
        "after": [
          "    )\n",
          "    # `2 * cap + height` is the row count. A cap of `Int.MAX` wraps it,\n",
          "    # and the walk then does not finish.\n",
          "    if cap_segments > (Int.MAX - height_segments) // 2:\n",
          "        raise Error(\"A capsule's segment count is larger than this port builds\")\n",
          "    require_grid_cells(\n",
          "        radial_segments,\n",
          "        cap_segments * 2 + height_segments,\n",
          "        \"A capsule's segment count is larger than this port builds\",\n"
        ]
      }
    ]
  },
  "geometries/rounded_box.mojo": {
    "before_sha256": "86beaead1f7ad942d1edb1fba795346a74f3f2798494b148aa0bc29e9e7efabf",
    "after_sha256": "3984fbb14c5bdc4c563b4b539cb7c6f6659a8730e69fd8a39a4de4e430e1cbbb",
    "before_token_sha256": "412a0796e1c3130b1131ab107f85f404552c17083e4e32ee60e3c4885d04b0f9",
    "after_token_sha256": "19eef4aebd2d092fa65507bea35f04cdc2a21bc42699c5426bd4732be3b26214",
    "edits": [
      {
        "start": 31,
        "stop": 32,
        "before": [],
        "after": [
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 173,
        "stop": 175,
        "before": [
          "            than one, or the radius is not finite or is negative.\n"
        ],
        "after": [
          "            than one, a face has more than 16777216 cells, or the radius\n",
          "            is not finite or is negative.\n"
        ]
      },
      {
        "start": 186,
        "stop": 192,
        "before": [],
        "after": [
          "    # The face grid is `2 * segments + 1` cells each way. A segment count\n",
          "    # of `Int.MAX` wraps that sum, and the walk then does not finish.\n",
          "    if segments > (Int.MAX - 1) // 2:\n",
          "        raise Error(\n",
          "            \"A rounded box's segment count is larger than this port builds\"\n",
          "        )\n"
        ]
      },
      {
        "start": 206,
        "stop": 211,
        "before": [],
        "after": [
          "    require_grid_cells(\n",
          "        total_segments,\n",
          "        total_segments,\n",
          "        \"A rounded box's segment count is larger than this port builds\",\n",
          "    )\n"
        ]
      }
    ]
  },
  "geometries/sphere.mojo": {
    "before_sha256": "f8ad29b989cf47c8ed8b6577e7747738d343921dde9b88048f03496863ebb538",
    "after_sha256": "29842095d3b923a4804f44f1f0d7721b05612e81195086241a6840b123b6b561",
    "before_token_sha256": "5ac4f4a2de67c8ef7655009ead1a4b04c38889cc09026dcaeebe2124af98c8b7",
    "after_token_sha256": "9fd80b622b8afb596cd879286c435f1f820d58b2e58d37c201350bb45bc38cc2",
    "edits": [
      {
        "start": 32,
        "stop": 33,
        "before": [],
        "after": [
          "    require_grid_cells,\n"
        ]
      },
      {
        "start": 72,
        "stop": 74,
        "before": [
          "            small to close a surface, or an angle is not finite.\n"
        ],
        "after": [
          "            small to close a surface, the grid has more than 16777216\n",
          "            cells, or an angle is not finite.\n"
        ]
      },
      {
        "start": 81,
        "stop": 86,
        "before": [],
        "after": [
          "    require_grid_cells(\n",
          "        width_segments,\n",
          "        height_segments,\n",
          "        \"A sphere's segment count is larger than this port builds\",\n",
          "    )\n"
        ]
      }
    ]
  },
  "lights/csm.mojo": {
    "before_sha256": "f25b0af19e143cb0cbb44b3aae41756e32a62ff97d9b52486cd6a3859cbd4d46",
    "after_sha256": "afed7168d284719059f54fae6656a7c8f0633ac657ee74931efd149429f5d8c6",
    "before_token_sha256": "e7cc17bf17d170a0de856350ae20d832f21663227f8fa72bb1ab6ad38c206e04",
    "after_token_sha256": "ebdee2cb2faba807fb4f483b4a734af9e92c77abb7ab6873fed3bb1fe7511dea",
    "edits": [
      {
        "start": 95,
        "stop": 98,
        "before": [],
        "after": [
          "# The most slices a split walks. `range` of `Int.MAX` never ends, and a\n",
          "# count past 2^24 is not an exact `Float32` step.\n",
          "comptime MAX_CSM_CASCADES = 16777216\n"
        ]
      },
      {
        "start": 100,
        "stop": 119,
        "before": [
          "def uniform_split(amount: Int, near: Float32, far: Float32) -> List[Float32]:\n"
        ],
        "after": [
          "def require_csm_cascades(amount: Int) raises:\n",
          "    \"\"\"Refuse a cascade count this port cannot slice.\n",
          "\n",
          "    Nothing. The call returns when the count is in range. A count below\n",
          "    one is refused separately.\n",
          "\n",
          "    Args:\n",
          "        amount: How many slices.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the count is above 16777216.\n",
          "    \"\"\"\n",
          "    if amount > MAX_CSM_CASCADES:\n",
          "        raise Error(\"A CSM cascade count is larger than this port slices\")\n",
          "\n",
          "\n",
          "def uniform_split(\n",
          "    amount: Int, near: Float32, far: Float32\n",
          ") raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 129,
        "stop": 132,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If `amount` is above 16777216.\n"
        ]
      },
      {
        "start": 133,
        "stop": 134,
        "before": [],
        "after": [
          "    require_csm_cascades(amount)\n"
        ]
      },
      {
        "start": 145,
        "stop": 146,
        "before": [
          ") -> List[Float32]:\n"
        ],
        "after": [
          ") raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 156,
        "stop": 159,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If `amount` is above 16777216.\n"
        ]
      },
      {
        "start": 160,
        "stop": 161,
        "before": [],
        "after": [
          "    require_csm_cascades(amount)\n"
        ]
      },
      {
        "start": 172,
        "stop": 173,
        "before": [
          ") -> List[Float32]:\n"
        ],
        "after": [
          ") raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 185,
        "stop": 188,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If `amount` is above 16777216.\n"
        ]
      },
      {
        "start": 189,
        "stop": 190,
        "before": [],
        "after": [
          "    require_csm_cascades(amount)\n"
        ]
      },
      {
        "start": 387,
        "stop": 390,
        "before": [
          "                not a positive length or the margin not finite; the custom\n",
          "                breaks do not fit `CUSTOM_SPLIT`; or a light is refused by\n",
          "                `Light.validate`.\n"
        ],
        "after": [
          "                not a positive length or the margin not finite; the cascade\n",
          "                count is above 16777216; the custom breaks do not fit\n",
          "                `CUSTOM_SPLIT`; or a light is refused by `Light.validate`.\n"
        ]
      },
      {
        "start": 392,
        "stop": 393,
        "before": [],
        "after": [
          "        require_csm_cascades(cascades)\n"
        ]
      }
    ]
  },
  "loaders/vrml_geometry.mojo": {
    "before_sha256": "e723ff538d86cb5c75370a75cf172abc78bf34618c975b836b31f588462341b2",
    "after_sha256": "11a22563cadea5e567adf626fef540fe7ecc05ae46cc5bb2e1ab35e2efc2dc09",
    "before_token_sha256": "ad368eb6f7d2eeecf9cf58000a6f39adbc6f902980eddb3656c82e6d6fa64021",
    "after_token_sha256": "e09b95680d660ff64111f6df5f62b12a51df933358f893cd3d0f0b4a2ad2d99d",
    "edits": [
      {
        "start": 544,
        "stop": 562,
        "before": [],
        "after": [
          "def _require_grid_count(x_dimension: Int, z_dimension: Int) raises:\n",
          "    \"\"\"Refuse a grid whose point-index length does not fit in `Int`.\n",
          "\n",
          "    A dimension comes from `_whole`, so it can be almost `1e15`. The\n",
          "    product `xDimension * zDimension` then wraps, and a later `index * 3`\n",
          "    wraps sooner. Either one makes a short index look valid.\n",
          "\n",
          "    Args:\n",
          "        x_dimension: The points along x.\n",
          "        z_dimension: The points along z.\n",
          "\n",
          "    Raises:\n",
          "        Error: If `3 * x_dimension * z_dimension` does not fit.\n",
          "    \"\"\"\n",
          "    if z_dimension > 0 and x_dimension > (Int.MAX // 3) // z_dimension:\n",
          "        raise Error(\"VRML: an elevation grid is larger than this port builds\")\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 569,
        "stop": 570,
        "before": [
          ") -> Tuple[List[Float64], List[Float64]]:\n"
        ],
        "after": [
          ") raises -> Tuple[List[Float64], List[Float64]]:\n"
        ]
      },
      {
        "start": 587,
        "stop": 590,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the grid's index length does not fit in an integer.\n"
        ]
      },
      {
        "start": 591,
        "stop": 592,
        "before": [],
        "after": [
          "    _require_grid_count(x_dimension, z_dimension)\n"
        ]
      },
      {
        "start": 616,
        "stop": 617,
        "before": [
          ") -> List[Float64]:\n"
        ],
        "after": [
          ") raises -> List[Float64]:\n"
        ]
      },
      {
        "start": 631,
        "stop": 634,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the grid's index length does not fit in an integer.\n"
        ]
      },
      {
        "start": 635,
        "stop": 636,
        "before": [],
        "after": [
          "    _require_grid_count(x_dimension, z_dimension)\n"
        ]
      },
      {
        "start": 659,
        "stop": 660,
        "before": [
          ") -> List[Float64]:\n"
        ],
        "after": [
          ") raises -> List[Float64]:\n"
        ]
      },
      {
        "start": 674,
        "stop": 677,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the grid's index length does not fit in an integer.\n"
        ]
      },
      {
        "start": 678,
        "stop": 679,
        "before": [],
        "after": [
          "    _require_grid_count(x_dimension, z_dimension)\n"
        ]
      }
    ]
  },
  "materials/material.mojo": {
    "before_sha256": "0722ad172e97c70cc530348a627eb52cde41c643cabef385423ee8ea6d8b77b9",
    "after_sha256": "a9d7e4f2aa4096a9c768d8bd68a696ddd619bd75da5a2e710136242dbea82ff5",
    "before_token_sha256": "3b5ffd499e0f2c9796f8f3ba8d0dfe7ec67096f14f90c0b14e691e9169613277",
    "after_token_sha256": "1a479bfdcf7aa1d190712aaa82e4382f81ddcafe6454ccc079b4d5bd95a60890",
    "edits": [
      {
        "start": 715,
        "stop": 720,
        "before": [],
        "after": [
          "# One ray of more steps than this does not finish a fragment. The\n",
          "# default is 25.\n",
          "comptime MAX_VOLUME_STEPS = 4096\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 721,
        "stop": 722,
        "before": [
          "    \"\"\"Refuse a number of ray steps that marches nothing.\n"
        ],
        "after": [
          "    \"\"\"Refuse a number of ray steps this port does not march.\n"
        ]
      },
      {
        "start": 727,
        "stop": 729,
        "before": [
          "        Error: If `steps` is below one: three.js divides the ray by it.\n"
        ],
        "after": [
          "        Error: If `steps` is below one, or above 4096. three.js divides\n",
          "            the ray by the count.\n"
        ]
      },
      {
        "start": 731,
        "stop": 733,
        "before": [],
        "after": [
          "    if steps > MAX_VOLUME_STEPS:\n",
          "        raise Error(\"A volume's step count is larger than this port marches\")\n"
        ]
      },
      {
        "start": 2865,
        "stop": 2867,
        "before": [
          "            Error: If the material is not `VOLUME`, or `steps` is below one;\n",
          "                see `check_steps`.\n"
        ],
        "after": [
          "            Error: If the material is not `VOLUME`, or `steps` is below one\n",
          "                or above 4096; see `check_steps`.\n"
        ]
      },
      {
        "start": 3009,
        "stop": 3010,
        "before": [
          "            Error: Never for planes that were set: each was a plane.\n"
        ],
        "after": [
          "            Error: If the plane count is below zero or above eight.\n"
        ]
      },
      {
        "start": 3011,
        "stop": 3017,
        "before": [],
        "after": [
          "        if self.clip_plane_count < 0:\n",
          "            raise Error(\"A clipping plane count must be zero or more\")\n",
          "        if self.clip_plane_count > MAX_CLIPPING_PLANES:\n",
          "            raise Error(\n",
          "                \"A clipping plane count is larger than this port stores\"\n",
          "            )\n"
        ]
      }
    ]
  },
  "materials/volume_node_material.mojo": {
    "before_sha256": "f8e08ddbfb285a9d5344c156a9424cb8c309cb4771ff132f7eaca193f69eab29",
    "after_sha256": "97ec23fa0e1e181f7c4b3b6f13ce0bc3564402ce02b0ea0ac61fac6697120a9f",
    "before_token_sha256": "4af43647675454d33bd5aea9498d06f66b909b068e9d036e290d5ffb38c75212",
    "after_token_sha256": "6a3679ec893c1544fa0ec6d817c998a5fa0d9a0760ac6ef7197bfc747de4bb91",
    "edits": [
      {
        "start": 46,
        "stop": 47,
        "before": [],
        "after": [
          "    MAX_VOLUME_STEPS,\n"
        ]
      },
      {
        "start": 164,
        "stop": 166,
        "before": [
          "        steps: How many steps the ray takes, from one.\n"
        ],
        "after": [
          "        steps: How many steps the ray takes, from one. Above 4096 the\n",
          "            ray gathers nothing, so the march cannot fail to finish.\n"
        ]
      },
      {
        "start": 178,
        "stop": 180,
        "before": [],
        "after": [
          "    if steps > MAX_VOLUME_STEPS:\n",
          "        return Vector3(0, 0, 0)\n"
        ]
      },
      {
        "start": 238,
        "stop": 241,
        "before": [
          "        Error: If `steps` is below one, `opacity` is outside zero to one,\n",
          "            or `nodes` is a negative other than `NO_NODES`.\n"
        ],
        "after": [
          "        Error: If `steps` is below one or above 4096, `opacity` is\n",
          "            outside zero to one, or `nodes` is a negative other than\n",
          "            `NO_NODES`.\n"
        ]
      }
    ]
  },
  "math/curve.mojo": {
    "before_sha256": "579839a0981c00cc9e188a0a57ff9f0c5822b09f3cd8ae6fa5b667d97d8ff5d9",
    "after_sha256": "d0a404a892191700a00bcda9f5bc92837995d5166c0c953933453e79dcf25c45",
    "before_token_sha256": "b865bdd753cd653883d3e3aba7dba844ad6c8f5158d2843c24f48cf2ead8e885",
    "after_token_sha256": "c1de714a8a62e237d7f2a3cd8ca62a33457ca2771368424c8c4c4869130285cc",
    "edits": [
      {
        "start": 345,
        "stop": 348,
        "before": [
          "        Error: If `divisions` is less than one, the sample count cannot\n",
          "            fit in Int, the table has fewer than two entries, or `take`\n",
          "            raises.\n"
        ],
        "after": [
          "        Error: If `divisions` is less than one, above 16777216, the sample\n",
          "            count cannot fit in Int, the table has fewer than two entries,\n",
          "            or `take` raises.\n"
        ]
      },
      {
        "start": 554,
        "stop": 557,
        "before": [
          "        var segment = Int(floor(Float32(last) * t))\n"
        ],
        "after": [
          "        # `Float64`, as JavaScript's number is. A `Float32` product drops\n",
          "        # whole segments past 2^24, so `t` of one misses the last point.\n",
          "        var segment = Int(floor(Float64(last) * Float64(t)))\n"
        ]
      },
      {
        "start": 570,
        "stop": 571,
        "before": [],
        "after": [
          "        var span = Float64(last) * Float64(t)\n"
        ]
      },
      {
        "start": 572,
        "stop": 573,
        "before": [
          "        var weight = Float32(last) * t - Float32(segment)\n"
        ],
        "after": [
          "        var weight = Float32(span - Float64(segment))\n"
        ]
      },
      {
        "start": 665,
        "stop": 668,
        "before": [
          "            Error: If `divisions` is less than one, its sample count cannot\n",
          "                fit in Int, or the mutable curve is not valid.\n"
        ],
        "after": [
          "            Error: If `divisions` is less than one, above 16777216, its\n",
          "                sample count cannot fit in Int, or the mutable curve is\n",
          "                not valid.\n"
        ]
      },
      {
        "start": 682,
        "stop": 685,
        "before": [
          "            Error: If `divisions` is less than one, its sample count cannot\n",
          "                fit in Int, or the mutable curve is not valid.\n"
        ],
        "after": [
          "            Error: If `divisions` is less than one, above 16777216, its\n",
          "                sample count cannot fit in Int, or the mutable curve is\n",
          "                not valid.\n"
        ]
      },
      {
        "start": 774,
        "stop": 777,
        "before": [
          "            Error: If `divisions` is less than one, its sample count cannot\n",
          "                fit in Int, or the mutable curve is not valid.\n"
        ],
        "after": [
          "            Error: If `divisions` is less than one, above 16777216, its\n",
          "                sample count cannot fit in Int, or the mutable curve is\n",
          "                not valid.\n"
        ]
      }
    ]
  },
  "math/curve_checks.mojo": {
    "before_sha256": "9ad53ff5ed5a540a85ed4ed00860e8d9c1b537c67edda2a8d6f58b458ae5a8ef",
    "after_sha256": "1c6cf558aaf2102941d874ff9d814423b71fea1a9eb159eae7c549325ee274ff",
    "before_token_sha256": "77ab05f3e0fb25c5489ecaf4f50174eafd68862d3a04c9e859f9ac5182a8c286",
    "after_token_sha256": "2cb1165ef5b79554e557dab9f76265006c0c4c88dde4dfe61ce5f0a668cfd7ff",
    "edits": [
      {
        "start": 13,
        "stop": 18,
        "before": [],
        "after": [
          "\n",
          "# A sample step is `Float32(index) / Float32(divisions)`. Every integer\n",
          "# through 16777216 is exact in `Float32`. One more is not, and a count\n",
          "# of `Int.MAX` does not finish the sample loop.\n",
          "comptime MAX_CURVE_DIVISIONS = 16777216\n"
        ]
      },
      {
        "start": 121,
        "stop": 126,
        "before": [],
        "after": [
          "    A division count above 16777216 is refused. `Float32` cannot tell\n",
          "    those steps apart, and a count at the top of `Int` does not finish\n",
          "    the sample loop. A count of `Int.MAX` still reports that the sum\n",
          "    cannot fit, before this limit.\n",
          "\n"
        ]
      },
      {
        "start": 133,
        "stop": 135,
        "before": [
          "        Error: If divisions is not positive or the sample count overflows.\n"
        ],
        "after": [
          "        Error: If divisions is not positive, above 16777216, or the\n",
          "            sample count overflows.\n"
        ]
      },
      {
        "start": 137,
        "stop": 141,
        "before": [
          "    return curve_count_sum(divisions, 1)\n"
        ],
        "after": [
          "    var count = curve_count_sum(divisions, 1)\n",
          "    if divisions > MAX_CURVE_DIVISIONS:\n",
          "        raise Error(\"A curve's division count is larger than this port samples\")\n",
          "    return count\n"
        ]
      },
      {
        "start": 219,
        "stop": 221,
        "before": [
          "        Error: If `divisions` is less than one, the sample count cannot\n",
          "            fit in Int, or `take` raises.\n"
        ],
        "after": [
          "        Error: If `divisions` is less than one, above 16777216, the sample\n",
          "            count cannot fit in Int, or `take` raises.\n"
        ]
      }
    ]
  },
  "math/path.mojo": {
    "before_sha256": "e182834e6ecb1019ca882beeb2272053dfbbee263f4bfd45bcd35c5c53197f11",
    "after_sha256": "124ac09790b335df31554c6a7744bf6b49954d2a6faa456632d779409951468f",
    "before_token_sha256": "fd08eee9a9d5d5921dcf806afcc158ba2d979005a6fda85cc5fe43917004937b",
    "after_token_sha256": "0ace5a92be8a9de1a84939c48b4f476e260acc72e4151268c22f90e84f1a2e4f",
    "edits": [
      {
        "start": 432,
        "stop": 434,
        "before": [
          "                is less than one, or a sample count cannot fit in Int.\n"
        ],
        "after": [
          "                is less than one, one curve asks for more than 16777216\n",
          "                runs, or a sample count cannot fit in Int.\n"
        ]
      }
    ]
  },
  "math/utils.mojo": {
    "before_sha256": "d32e99704324833af194084f0b1d646a894c63bdd0b8ce1baa0da8a287c1d690",
    "after_sha256": "fb4335138e5fe5ec4c1761105343a01996dae1152f3a9e1b2779f62a6323c772",
    "before_token_sha256": "09aae4effc4236d14e85367f694c436b5b761ba75fb37e6b7df93006804cb915",
    "after_token_sha256": "1f3a1816f2ab539359659e372492f4f1851a66d57e4673d238b5e80c3f498695",
    "edits": [
      {
        "start": 28,
        "stop": 29,
        "before": [],
        "after": [
          "from std.sys import is_gpu\n"
        ]
      },
      {
        "start": 154,
        "stop": 236,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def texel_center(pixel: Int, count: Int) -> Float32:\n",
          "    \"\"\"Return the center of a pixel as a fraction of its side.\n",
          "\n",
          "    A count above 2^23 is not a side a `Float32` can address by halves, so\n",
          "    the last pixel reads as the edge. That center is measured in\n",
          "    `Float64`. A smaller count keeps the `Float32` quotient.\n",
          "\n",
          "    Args:\n",
          "        pixel: The column or the row.\n",
          "        count: The side, in pixels. It must be positive.\n",
          "\n",
          "    Returns:\n",
          "        The center, from just above zero through just below one.\n",
          "    \"\"\"\n",
          "    # Metal has no `Float64`, and no GPU image is 2^23 pixels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 8388608:\n",
          "            return Float32((Float64(pixel) + 0.5) / Float64(count))\n",
          "    return (Float32(pixel) + 0.5) / Float32(count)\n",
          "\n",
          "\n",
          "def texel_center_from_end(pixel: Int, count: Int) -> Float32:\n",
          "    \"\"\"Return one minus a pixel's center, as a fraction of its side.\n",
          "\n",
          "    The subtraction is in `Float64` when the count is above 2^23. Doing\n",
          "    it after the `Float32` cast sends the last pixel to zero.\n",
          "\n",
          "    Args:\n",
          "        pixel: The column or the row.\n",
          "        count: The side, in pixels. It must be positive.\n",
          "\n",
          "    Returns:\n",
          "        One minus the center.\n",
          "    \"\"\"\n",
          "    # Metal has no `Float64`, and no GPU image is 2^23 pixels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 8388608:\n",
          "            return Float32(1 - (Float64(pixel) + 0.5) / Float64(count))\n",
          "    return 1 - (Float32(pixel) + 0.5) / Float32(count)\n",
          "\n",
          "\n",
          "def texel_ndc(pixel: Int, count: Int) -> Float32:\n",
          "    \"\"\"Return a pixel's center in normalized device space, from minus one\n",
          "    to one.\n",
          "\n",
          "    The whole quotient is a `Float64` when the count is above 2^23.\n",
          "    Scaling a `Float32` fraction sends the last pixel to one.\n",
          "\n",
          "    Args:\n",
          "        pixel: The column or the row.\n",
          "        count: The side, in pixels. It must be positive.\n",
          "\n",
          "    Returns:\n",
          "        The center, from just above minus one through just below one.\n",
          "    \"\"\"\n",
          "    # Metal has no `Float64`, and no GPU image is 2^23 pixels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 8388608:\n",
          "            return Float32((Float64(pixel) + 0.5) / Float64(count) * 2 - 1)\n",
          "    return (Float32(pixel) + 0.5) / Float32(count) * 2 - 1\n",
          "\n",
          "\n",
          "def texel_ndc_up(pixel: Int, count: Int) -> Float32:\n",
          "    \"\"\"Return a pixel's center in normalized device space, y up.\n",
          "\n",
          "    One is the top of the image. The subtraction is in `Float64` when the\n",
          "    count is above 2^23.\n",
          "\n",
          "    Args:\n",
          "        pixel: The row, down from the top.\n",
          "        count: The side, in pixels. It must be positive.\n",
          "\n",
          "    Returns:\n",
          "        The center, from just below one through just above minus one.\n",
          "    \"\"\"\n",
          "    # Metal has no `Float64`, and no GPU image is 2^23 pixels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 8388608:\n",
          "            return Float32(1 - (Float64(pixel) + 0.5) / Float64(count) * 2)\n",
          "    return 1 - (Float32(pixel) + 0.5) / Float32(count) * 2\n"
        ]
      },
      {
        "start": 887,
        "stop": 904,
        "before": [],
        "after": [
          "def _difference_fits(high: Int, low: Int) -> Bool:\n",
          "    \"\"\"Return whether `high - low` fits in an integer.\n",
          "\n",
          "    Args:\n",
          "        high: The end that is subtracted from.\n",
          "        low: The end that is subtracted.\n",
          "\n",
          "    Returns:\n",
          "        Whether the difference fits.\n",
          "    \"\"\"\n",
          "    if low > 0:\n",
          "        return high >= Int.MIN + low\n",
          "    if low < 0:\n",
          "        return high <= Int.MAX + low\n",
          "    return True\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 979,
        "stop": 982,
        "before": [],
        "after": [
          "        A width that does not fit in an integer is drawn in `Float64` and\n",
          "        held inside the range. Widths that fit keep the integer product.\n",
          "\n"
        ]
      },
      {
        "start": 987,
        "stop": 988,
        "before": [
          "            The number.\n"
        ],
        "after": [
          "            The number. It lies in the range when `low` is at most `high`.\n"
        ]
      },
      {
        "start": 989,
        "stop": 999,
        "before": [
          "        return low + Int(floor(self.next() * Float64(high - low + 1)))\n"
        ],
        "after": [
          "        var unit = self.next()\n",
          "        if _difference_fits(high, low):\n",
          "            var diff = high - low\n",
          "            if diff < Int.MAX:\n",
          "                return low + Int(floor(unit * Float64(diff + 1)))\n",
          "        if high < low:\n",
          "            return low\n",
          "        var width = Float64(high) - Float64(low)\n",
          "        var value = Float64(low) + floor(unit * (width + 1))\n",
          "        return Int(value)\n"
        ]
      },
      {
        "start": 1221,
        "stop": 1250,
        "before": [],
        "after": [
          "\n",
          "\n",
          "# A side of an image or a view times a `Float32` scale.\n",
          "#\n",
          "# A scale such as 0.9 is stored as the `Float32` nearest it, a little\n",
          "# below 0.9. The `Float32` product of an ordinary side rounds back up to\n",
          "# the whole number that JavaScript gets from its `Float64` 0.9: 1000 times\n",
          "# 0.9 is 900. The `Float64` product of the same `Float32` scale stays\n",
          "# below, at 899.99998. Past 2^24 a `Float32` cannot hold every whole side,\n",
          "# so the product is a `Float64` there.\n",
          "comptime EXACT_SIDES = 16777216\n",
          "\"\"\"The largest side whose every whole value a `Float32` holds: 2^24.\"\"\"\n",
          "\n",
          "\n",
          "def scaled_side(size: Int, scale: Float32) -> Float64:\n",
          "    \"\"\"Return a side times a scale, as the renderers have scaled it.\n",
          "\n",
          "    Args:\n",
          "        size: The side, in pixels.\n",
          "        scale: The scale.\n",
          "\n",
          "    Returns:\n",
          "        The `Float32` product, as a `Float64`, for a side of at most 2^24\n",
          "        either way. The `Float64` product for a larger side. Either can\n",
          "        be infinite, for the caller to refuse.\n",
          "    \"\"\"\n",
          "    if size <= EXACT_SIDES and size >= -EXACT_SIDES:\n",
          "        return Float64(Float32(size) * scale)\n",
          "    return Float64(size) * Float64(scale)\n"
        ]
      }
    ]
  },
  "objects/line_segments2.mojo": {
    "before_sha256": "fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021",
    "after_sha256": "2557d496f1dc49c204314d389bd105c9eaaab4c7762920b7b0d5f97613d4c3cd",
    "before_token_sha256": "7e96fc16c731458d7395fc579b0afb09ca597154c9c4c58f165fafc2efab4191",
    "after_token_sha256": "325a623b54aa479db62a10adfadc19befd4c0aa24f7d90c0179f31b5acc11d1a",
    "edits": [
      {
        "start": 51,
        "stop": 52,
        "before": [
          "from std.math import ceil, floor, max, min, pi, sqrt\n"
        ],
        "after": [
          "from std.math import ceil, floor, isfinite, max, min, pi, sqrt\n"
        ]
      },
      {
        "start": 349,
        "stop": 353,
        "before": [
          "        Error: If the pattern repeats more than `MAX_DASHES_PER_SEGMENT`\n",
          "            times along the segment.\n"
        ],
        "after": [
          "        Error: If a distance is not finite, the dash pattern is not a\n",
          "            positive finite length, or the pattern repeats more than\n",
          "            `MAX_DASHES_PER_SEGMENT` times along the segment. A repeat\n",
          "            count that does not fit in an integer is that refusal.\n"
        ]
      },
      {
        "start": 354,
        "stop": 356,
        "before": [],
        "after": [
          "    if not isfinite(start) or not isfinite(end):\n",
          "        raise Error(\"A wide line's distance must be finite\")\n"
        ]
      },
      {
        "start": 363,
        "stop": 365,
        "before": [],
        "after": [
          "    if not isfinite(period) or period <= 0:\n",
          "        raise Error(\"A wide line's dash pattern must be finite\")\n"
        ]
      },
      {
        "start": 367,
        "stop": 379,
        "before": [
          "    var first = Int(floor(low / period))\n",
          "    var last = Int(floor(high / period))\n",
          "    if last - first >= MAX_DASHES_PER_SEGMENT:\n"
        ],
        "after": [
          "    # Count the repeats in `Float64` before they become integers. A\n",
          "    # difference past 2^63 overflows the subtraction, and the old check\n",
          "    # then lets the walk run without end. A quotient past 2^63 is not a\n",
          "    # repeat index either, and two different distances that far apart are\n",
          "    # more than 4096 periods.\n",
          "    var low_q = floor(Float64(low) / Float64(period))\n",
          "    var high_q = floor(Float64(high) / Float64(period))\n",
          "    if (\n",
          "        not (high_q < Float64(Int.MAX))\n",
          "        or not (low_q > -Float64(Int.MAX))\n",
          "        or high_q - low_q >= Float64(MAX_DASHES_PER_SEGMENT)\n",
          "    ):\n"
        ]
      },
      {
        "start": 383,
        "stop": 385,
        "before": [],
        "after": [
          "    var first = Int(low_q)\n",
          "    var last = Int(high_q)\n"
        ]
      }
    ]
  },
  "postprocessing/antialiasing.mojo": {
    "before_sha256": "f872ef3a6d27aa2f0bf0210007d7e7d420edb36dab1da7b66fc235c5dfb80358",
    "after_sha256": "9d7e718c734d4e3bd5a621cf1efb85eb8ca0cc4aaf872b6a151d26961a50b621",
    "before_token_sha256": "c1bc4d7832e1a5e74da0d81aa28ec1fd1df8ca85f3f6fab22d86df41ffae7eae",
    "after_token_sha256": "c4890965d15d845ee63d3dcd52defac7a27acf4413eb6531b4b2d69129ba97c3",
    "edits": [
      {
        "start": 244,
        "stop": 263,
        "before": [],
        "after": [
          "def require_smaa_extent(width: Int, height: Int) raises:\n",
          "    \"\"\"Refuse an SMAA frame that is empty or whose pixel count would wrap.\n",
          "\n",
          "    Nothing. The call returns when both sides are at least one and their\n",
          "    product fits in an integer.\n",
          "\n",
          "    Args:\n",
          "        width: The frame's width in pixels.\n",
          "        height: The frame's height in pixels.\n",
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n",
          "    \"\"\"\n",
          "    if width < 1 or height < 1:\n",
          "        raise Error(\"An SMAA frame must be at least one pixel each way\")\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"An SMAA frame is larger than this port builds\")\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 275,
        "stop": 276,
        "before": [
          "    def __init__(out self, width: Int, height: Int):\n"
        ],
        "after": [
          "    def __init__(out self, width: Int, height: Int) raises:\n"
        ]
      },
      {
        "start": 281,
        "stop": 284,
        "before": [],
        "after": [
          "\n",
          "        Raises:\n",
          "            Error: If a side is below one, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 285,
        "stop": 286,
        "before": [],
        "after": [
          "        require_smaa_extent(width, height)\n"
        ]
      },
      {
        "start": 315,
        "stop": 316,
        "before": [
          "    def transposed(self) -> EdgeMap:\n"
        ],
        "after": [
          "    def transposed(self) raises -> EdgeMap:\n"
        ]
      },
      {
        "start": 325,
        "stop": 328,
        "before": [],
        "after": [
          "\n",
          "        Raises:\n",
          "            Error: If the turned pixel count does not fit.\n"
        ]
      },
      {
        "start": 344,
        "stop": 347,
        "before": [
          "def smaa_edges(colors: List[FloatColor], width: Int, height: Int) -> EdgeMap:\n"
        ],
        "after": [
          "def smaa_edges(\n",
          "    colors: List[FloatColor], width: Int, height: Int\n",
          ") raises -> EdgeMap:\n"
        ]
      },
      {
        "start": 362,
        "stop": 365,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 589,
        "stop": 590,
        "before": [
          "    def __init__(out self, width: Int, height: Int):\n"
        ],
        "after": [
          "    def __init__(out self, width: Int, height: Int) raises:\n"
        ]
      },
      {
        "start": 595,
        "stop": 598,
        "before": [],
        "after": [
          "\n",
          "        Raises:\n",
          "            Error: If a side is below one, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 599,
        "stop": 600,
        "before": [],
        "after": [
          "        require_smaa_extent(width, height)\n"
        ]
      },
      {
        "start": 619,
        "stop": 620,
        "before": [
          "def smaa_weights(edges: EdgeMap) -> BlendWeights:\n"
        ],
        "after": [
          "def smaa_weights(edges: EdgeMap) raises -> BlendWeights:\n"
        ]
      },
      {
        "start": 629,
        "stop": 632,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the pixel count does not fit.\n"
        ]
      },
      {
        "start": 725,
        "stop": 726,
        "before": [
          "def smaa_light(mut frame: RenderTarget):\n"
        ],
        "after": [
          "def smaa_light(mut frame: RenderTarget) raises:\n"
        ]
      },
      {
        "start": 731,
        "stop": 734,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the frame's pixel count does not fit.\n"
        ]
      }
    ]
  },
  "postprocessing/composer.mojo": {
    "before_sha256": "c1a644fed62e5904fb9405bb22033fd2709266ccbf74f478570dc60879cd05fd",
    "after_sha256": "67776f4c9f5e1ca407bde4e5a3c781d49c425e1dc0b0fd54451c8c1cf8dca630",
    "before_token_sha256": "4b843744b2abe4bcb87b9c7f09f8c7263aefd02177905f54c86cb5c8dcd037a5",
    "after_token_sha256": "bbdfe72baff56852feedb5f2438b0ac5f6322e13f02327417169e4aca08e0889",
    "edits": [
      {
        "start": 4475,
        "stop": 4477,
        "before": [
          "    past the kernel zero as a shader's unset uniforms are.\n"
        ],
        "after": [
          "    past the kernel zero as a shader's unset uniforms are. A ceil past\n",
          "    2^63 uses that cap.\n"
        ]
      },
      {
        "start": 4485,
        "stop": 4493,
        "before": [
          "    var built = 2 * Int(ceil(sigma * 3)) + 1\n",
          "    if built > MAX_BLOOM_KERNEL:\n"
        ],
        "after": [
          "    # `2 * ceil(sigma * 3) + 1` is 25 at a ceil of 12, and three.js cuts a\n",
          "    # wider kernel there. A ceil past 2^63 is not that product: `Int` of\n",
          "    # it is a garbage index, so the old cap compared the wrong number.\n",
          "    var wide = ceil(sigma * 3)\n",
          "    var built: Int\n",
          "    if not (wide < Float32((MAX_BLOOM_KERNEL - 1) // 2)) or not (\n",
          "        wide > -Float32(Int.MAX)\n",
          "    ):\n"
        ]
      },
      {
        "start": 4494,
        "stop": 4496,
        "before": [],
        "after": [
          "    else:\n",
          "        built = 2 * Int(wide) + 1\n"
        ]
      }
    ]
  },
  "postprocessing/display_nodes.mojo": {
    "before_sha256": "8f5c82c9cb63f5d611a854ba0a5e912c1c7cd16a2d237badd6b287f0bec515f2",
    "after_sha256": "63b8aa00f7339c4c7d1bcfd917cf2c4a0a9da029ea6e88579f3145f5e07a8b50",
    "before_token_sha256": "7a715e6659c3d083e77a96cf2c6bd85bc64bfcf4763a8c4bb96f14bc7356b80a",
    "after_token_sha256": "489f4df80a39e48ae4f155c263988a832e9646f18f7880114366af2b88a4ef7f",
    "edits": [
      {
        "start": 51,
        "stop": 52,
        "before": [],
        "after": [
          "from math.utils import scaled_side\n"
        ]
      },
      {
        "start": 142,
        "stop": 153,
        "before": [],
        "after": [
          "# A display tap index is a `Float32`. Past 16777216 it is no longer that\n",
          "# index. A count of the maximum integer does not finish the walk, and one\n",
          "# more than it wraps a motion blur's loop bound.\n",
          "comptime MAX_DISPLAY_TAPS = 16777216\n",
          "\n",
          "# A box blur is a square of `2 * size + 1` taps. Size 2047 is 4095 taps\n",
          "# on a side. One more side is more than 16777216 taps, and the maximum\n",
          "# integer wraps `size + 1`, so the square is empty.\n",
          "comptime MAX_BOX_BLUR_SIZE = 2047\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 164,
        "stop": 167,
        "before": [
          "            needs; or a depth of field's focal length is not positive.\n"
        ],
        "after": [
          "            needs; a hash blur, an anamorphic streak, a lens flare, or a\n",
          "            motion blur has more than 16777216 taps; a box blur's size is\n",
          "            above 2047; or a depth of field's focal length is not positive.\n"
        ]
      },
      {
        "start": 200,
        "stop": 202,
        "before": [],
        "after": [
          "    if settings.size > MAX_BOX_BLUR_SIZE:\n",
          "        raise Error(\"A box blur's size is larger than this port takes\")\n"
        ]
      },
      {
        "start": 210,
        "stop": 222,
        "before": [],
        "after": [
          "    if settings.repeats > MAX_DISPLAY_TAPS:\n",
          "        raise Error(\"A hash blur's repeat count is larger than this port takes\")\n",
          "    if settings.samples > MAX_DISPLAY_TAPS:\n",
          "        raise Error(\n",
          "            \"An anamorphic streak's sample count is larger than this port takes\"\n",
          "        )\n",
          "    if settings.ghost_samples > MAX_DISPLAY_TAPS:\n",
          "        raise Error(\"A lens flare's ghost count is larger than this port takes\")\n",
          "    if settings.motion_samples > MAX_DISPLAY_TAPS:\n",
          "        raise Error(\n",
          "            \"A motion blur's sample count is larger than this port takes\"\n",
          "        )\n"
        ]
      },
      {
        "start": 259,
        "stop": 285,
        "before": [
          "def scaled_size(size: Int, scale: Float32) -> Int:\n"
        ],
        "after": [
          "def _rounded_side(value: Float64) raises -> Int:\n",
          "    \"\"\"Return `Math.max(Math.round(value), 1)`.\n",
          "\n",
          "    Args:\n",
          "        value: The side before rounding.\n",
          "\n",
          "    Returns:\n",
          "        The side, at least one.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the rounded side is not finite or does not fit in an\n",
          "            integer.\n",
          "    \"\"\"\n",
          "    var scaled = floor(value + 0.5)\n",
          "    # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "    # the side. A float below `-2^63` is not one either.\n",
          "    if (\n",
          "        not isfinite(scaled)\n",
          "        or scaled < -Float64(Int.MAX)\n",
          "        or scaled >= Float64(Int.MAX)\n",
          "    ):\n",
          "        raise Error(\"A scaled size does not fit in an integer\")\n",
          "    return max(Int(scaled), 1)\n",
          "\n",
          "\n",
          "def scaled_size(size: Int, scale: Float32) raises -> Int:\n"
        ]
      },
      {
        "start": 287,
        "stop": 291,
        "before": [],
        "after": [
          "\n",
          "    The product is `math.utils.scaled_side`'s: `Float32` to 2^24, as\n",
          "    JavaScript gets the whole size of a scale such as 0.9, and `Float64`\n",
          "    past it.\n"
        ]
      },
      {
        "start": 298,
        "stop": 302,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the rounded side is not finite or does not fit in an\n",
          "            integer.\n"
        ]
      },
      {
        "start": 303,
        "stop": 321,
        "before": [
          "    return max(Int(floor(Float32(size) * scale + 0.5)), 1)\n"
        ],
        "after": [
          "    return _rounded_side(scaled_side(size, scale))\n",
          "\n",
          "\n",
          "def require_scaled_extent(width: Int, height: Int) raises:\n",
          "    \"\"\"Refuse a scaled frame whose pixel count would wrap.\n",
          "\n",
          "    Both sides are already at least one. Nothing. The call returns when\n",
          "    their product fits in an integer.\n",
          "\n",
          "    Args:\n",
          "        width: The scaled width in pixels.\n",
          "        height: The scaled height in pixels.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the pixel count does not fit.\n",
          "    \"\"\"\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"A scaled frame is larger than this port builds\")\n"
        ]
      },
      {
        "start": 339,
        "stop": 340,
        "before": [
          "def gaussian_coefficients(sigma: Float32) -> List[Float32]:\n"
        ],
        "after": [
          "def gaussian_coefficients(sigma: Float32) raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 342,
        "stop": 345,
        "before": [],
        "after": [
          "\n",
          "    The loop index is a `Float32`. Past 16777216 that index is no longer\n",
          "    the integer it counts, and a kernel of that size does not finish.\n"
        ]
      },
      {
        "start": 351,
        "stop": 354,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the kernel has more than 16777216 weights.\n"
        ]
      },
      {
        "start": 356,
        "stop": 358,
        "before": [],
        "after": [
          "    if kernel_size > Float32(16777216):\n",
          "        raise Error(\"A Gaussian blur's kernel is larger than this port builds\")\n"
        ]
      },
      {
        "start": 409,
        "stop": 412,
        "before": [
          "def gaussian_blur_light(mut frame: RenderTarget, settings: DisplaySettings):\n"
        ],
        "after": [
          "def gaussian_blur_light(\n",
          "    mut frame: RenderTarget, settings: DisplaySettings\n",
          ") raises:\n"
        ]
      },
      {
        "start": 419,
        "stop": 424,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a scaled side does not fit in an integer, the scaled\n",
          "            pixel count does not fit, or the kernel has more than\n",
          "            16777216 weights.\n"
        ]
      },
      {
        "start": 427,
        "stop": 428,
        "before": [],
        "after": [
          "    require_scaled_extent(width, height)\n"
        ]
      },
      {
        "start": 473,
        "stop": 475,
        "before": [
          "            premultiplied.\n"
        ],
        "after": [
          "            premultiplied. A size above 2047, or below zero, returns the\n",
          "            pixel.\n"
        ]
      },
      {
        "start": 477,
        "stop": 479,
        "before": [
          "        The mean, as the frame holds it.\n"
        ],
        "after": [
          "        The mean, as the frame holds it. The pixel alone when the size is\n",
          "        below zero or above 2047.\n"
        ]
      },
      {
        "start": 482,
        "stop": 487,
        "before": [],
        "after": [
          "    if settings.size < 0 or settings.size > MAX_BOX_BLUR_SIZE:\n",
          "        return _stored(\n",
          "            _tap(source, u, v, settings.premultiplied_alpha),\n",
          "            settings.premultiplied_alpha,\n",
          "        )\n"
        ]
      },
      {
        "start": 520,
        "stop": 521,
        "before": [
          "            premultiplied.\n"
        ],
        "after": [
          "            premultiplied. More than 16777216 repeats returns the pixel.\n"
        ]
      },
      {
        "start": 523,
        "stop": 525,
        "before": [
          "        The mean, as the frame holds it.\n"
        ],
        "after": [
          "        The mean, as the frame holds it. The pixel alone when the repeat\n",
          "        count is above 16777216.\n"
        ]
      },
      {
        "start": 528,
        "stop": 533,
        "before": [],
        "after": [
          "    if settings.repeats > MAX_DISPLAY_TAPS:\n",
          "        return _stored(\n",
          "            _tap(source, u, v, settings.premultiplied_alpha),\n",
          "            settings.premultiplied_alpha,\n",
          "        )\n"
        ]
      },
      {
        "start": 632,
        "stop": 634,
        "before": [
          "        samples: `numSamples`, at least two.\n"
        ],
        "after": [
          "        samples: `numSamples`, at least two. A count above 16777216\n",
          "            returns the pixel.\n"
        ]
      },
      {
        "start": 636,
        "stop": 638,
        "before": [
          "        The mean, as the frame holds it.\n"
        ],
        "after": [
          "        The mean, as the frame holds it. The pixel alone when `samples`\n",
          "        is above 16777216.\n"
        ]
      },
      {
        "start": 641,
        "stop": 643,
        "before": [],
        "after": [
          "    if samples > MAX_DISPLAY_TAPS:\n",
          "        return _stored(_tap(source, u, v, False), False)\n"
        ]
      },
      {
        "start": 827,
        "stop": 828,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 841,
        "stop": 844,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a halved side does not fit in an integer.\n"
        ]
      },
      {
        "start": 1009,
        "stop": 1010,
        "before": [
          "def anamorphic_light(mut frame: RenderTarget, settings: DisplaySettings):\n"
        ],
        "after": [
          "def anamorphic_light(mut frame: RenderTarget, settings: DisplaySettings) raises:\n"
        ]
      },
      {
        "start": 1022,
        "stop": 1026,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If there are more than 16777216 samples, a scaled side does\n",
          "            not fit in an integer, or the scaled pixel count does not fit.\n"
        ]
      },
      {
        "start": 1027,
        "stop": 1031,
        "before": [],
        "after": [
          "    if settings.samples > MAX_DISPLAY_TAPS:\n",
          "        raise Error(\n",
          "            \"An anamorphic streak's sample count is larger than this port takes\"\n",
          "        )\n"
        ]
      },
      {
        "start": 1033,
        "stop": 1034,
        "before": [],
        "after": [
          "    require_scaled_extent(width, height)\n"
        ]
      },
      {
        "start": 1078,
        "stop": 1079,
        "before": [
          "def lensflare_light(mut frame: RenderTarget, settings: DisplaySettings):\n"
        ],
        "after": [
          "def lensflare_light(mut frame: RenderTarget, settings: DisplaySettings) raises:\n"
        ]
      },
      {
        "start": 1091,
        "stop": 1095,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If there are more than 16777216 ghosts, a flare side does\n",
          "            not fit in an integer, or the flare's pixel count does not fit.\n"
        ]
      },
      {
        "start": 1096,
        "stop": 1100,
        "before": [
          "    var width = max(\n",
          "        Int(floor(Float32(frame.width) / settings.down_sample_ratio + 0.5)), 1\n"
        ],
        "after": [
          "    if settings.ghost_samples > MAX_DISPLAY_TAPS:\n",
          "        raise Error(\"A lens flare's ghost count is larger than this port takes\")\n",
          "    var width = _rounded_side(\n",
          "        Float64(frame.width) / Float64(settings.down_sample_ratio)\n"
        ]
      },
      {
        "start": 1101,
        "stop": 1103,
        "before": [
          "    var height = max(\n",
          "        Int(floor(Float32(frame.height) / settings.down_sample_ratio + 0.5)), 1\n"
        ],
        "after": [
          "    var height = _rounded_side(\n",
          "        Float64(frame.height) / Float64(settings.down_sample_ratio)\n"
        ]
      },
      {
        "start": 1104,
        "stop": 1105,
        "before": [],
        "after": [
          "    require_scaled_extent(width, height)\n"
        ]
      }
    ]
  },
  "postprocessing/effects.mojo": {
    "before_sha256": "187b5eede717872d6381bc2232743d940e3c1e38598b54493953ff730962cd96",
    "after_sha256": "ffc41647caee56f7a0a6e0661efcb57d88a5affe0eec0c49bcbc6fd3232a7cb7",
    "before_token_sha256": "f0861fba5063e3305085ad46947c472c4e380b455baa07aee257080438de5cd7",
    "after_token_sha256": "38431519b24041e77a1cba7a34a6bdd3985baf65df9f8504a1891cc937b062d9",
    "edits": [
      {
        "start": 373,
        "stop": 375,
        "before": [
          "            size: The map's texels a side, three.js's `dt_size`.\n"
        ],
        "after": [
          "            size: The map's texels a side, three.js's `dt_size`. A side\n",
          "                below zero or above 4096 leaves the map undrawn.\n"
        ]
      },
      {
        "start": 381,
        "stop": 387,
        "before": [],
        "after": [
          "        # A negative side, or one past 4096, makes a square that wraps or\n",
          "        # does not finish. The pass check still refuses that side.\n",
          "        if size < 0 or size > GLITCH_MAX_SIZE:\n",
          "            self.trigger = GLITCH_TRIGGER_LOW\n",
          "            self.state = 0\n",
          "            return\n"
        ]
      },
      {
        "start": 417,
        "stop": 418,
        "before": [
          "def glitch_heightmap(size: Int, seed: Int) -> List[Float32]:\n"
        ],
        "after": [
          "def glitch_heightmap(size: Int, seed: Int) raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 422,
        "stop": 423,
        "before": [
          "        size: Texels a side.\n"
        ],
        "after": [
          "        size: Texels a side, zero through 4096. Zero returns an empty map.\n"
        ]
      },
      {
        "start": 427,
        "stop": 430,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If `size` is negative or above 4096.\n"
        ]
      },
      {
        "start": 431,
        "stop": 433,
        "before": [],
        "after": [
          "    if size < 0 or size > GLITCH_MAX_SIZE:\n",
          "        raise Error(\"A glitch map is one through 4096 texels a side\")\n"
        ]
      },
      {
        "start": 434,
        "stop": 435,
        "before": [
          "    var values = List[Float32](capacity=max(size * size, 0))\n"
        ],
        "after": [
          "    var values = List[Float32](capacity=size * size)\n"
        ]
      },
      {
        "start": 1372,
        "stop": 1373,
        "before": [
          ") -> List[FloatColor]:\n"
        ],
        "after": [
          ") raises -> List[FloatColor]:\n"
        ]
      },
      {
        "start": 1386,
        "stop": 1389,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 1390,
        "stop": 1394,
        "before": [],
        "after": [
          "    if width < 1 or height < 1:\n",
          "        raise Error(\"A texture overlay must be at least one pixel each way\")\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"A texture overlay is larger than this port builds\")\n"
        ]
      },
      {
        "start": 1444,
        "stop": 1447,
        "before": [
          "def texture_light(mut frame: RenderTarget, texture: Texture, opacity: Float32):\n"
        ],
        "after": [
          "def texture_light(\n",
          "    mut frame: RenderTarget, texture: Texture, opacity: Float32\n",
          ") raises:\n"
        ]
      },
      {
        "start": 1458,
        "stop": 1462,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the frame is below one pixel, or its pixel count does\n",
          "            not fit.\n"
        ]
      },
      {
        "start": 1812,
        "stop": 1815,
        "before": [
          "            near plane is not in front of the far one; or there are fewer\n",
          "            than one ring or one sample.\n"
        ],
        "after": [
          "            near plane is not in front of the far one; there are fewer\n",
          "            than one ring or one sample; or the rings' taps pass\n",
          "            16777216.\n"
        ]
      },
      {
        "start": 1840,
        "stop": 1870,
        "before": [],
        "after": [
          "    if not _bokeh2_taps_fit(settings.rings, settings.samples):\n",
          "        raise Error(\n",
          "            \"A bokeh 2 ring or sample count is larger than this port takes\"\n",
          "        )\n",
          "\n",
          "\n",
          "# One ring of `samples` taps, the next of twice that, through `rings`.\n",
          "# The sum is `samples * rings * (rings + 1) / 2`. Past 16777216 taps the\n",
          "# index is no longer a `Float32` integer, and the maximum integer does\n",
          "# not finish the walk. `rings + 1` also wraps at the maximum integer.\n",
          "comptime MAX_BOKEH2_TAPS = 16777216\n",
          "\n",
          "\n",
          "def _bokeh2_taps_fit(rings: Int, samples: Int) -> Bool:\n",
          "    \"\"\"Return whether a bokeh's rings stay within 16777216 taps.\n",
          "\n",
          "    Args:\n",
          "        rings: How many rings.\n",
          "        samples: How many taps the first ring takes.\n",
          "\n",
          "    Returns:\n",
          "        Whether the walk fits. A count below one fits, because that loop\n",
          "        does not run.\n",
          "    \"\"\"\n",
          "    if rings > MAX_BOKEH2_TAPS or samples > MAX_BOKEH2_TAPS:\n",
          "        return False\n",
          "    if rings < 1 or samples < 1:\n",
          "        return True\n",
          "    var pairs = rings * (rings + 1) // 2\n",
          "    return samples <= MAX_BOKEH2_TAPS // pairs\n"
        ]
      },
      {
        "start": 2006,
        "stop": 2007,
        "before": [
          "    if blur >= 0.05:\n"
        ],
        "after": [
          "    if blur >= 0.05 and _bokeh2_taps_fit(settings.rings, settings.samples):\n"
        ]
      }
    ]
  },
  "postprocessing/filter_nodes.mojo": {
    "before_sha256": "cb22b8fc5bc0b27281ddb3ebda412e0fe14e6f23b60094953acbf45d52415071",
    "after_sha256": "827f1d87931bfd4b605ab753e9eada1b29ca0b08781311b7a396ae056a32b746",
    "before_token_sha256": "a9bc14fdffe561a5977f47cf65610337dc3e2a862467a8f568d6560bb6bd305f",
    "after_token_sha256": "39671156dea1b881a459b8b6ead6dc993a7fd2a81c09c8eac2b5901fdd2b9ec1",
    "edits": [
      {
        "start": 49,
        "stop": 50,
        "before": [
          "from postprocessing.sampling import LightView, u_of\n"
        ],
        "after": [
          "from postprocessing.sampling import LightView, clamped_texel, u_of\n"
        ]
      },
      {
        "start": 130,
        "stop": 135,
        "before": [],
        "after": [
          "# A radial tap index is a `Float32`. Past 16777216 it is no longer that\n",
          "# index, and a count of the maximum integer does not finish the walk.\n",
          "comptime MAX_RADIAL_TAPS = 16777216\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 176,
        "stop": 178,
        "before": [],
        "after": [
          "    if settings.count > MAX_RADIAL_TAPS:\n",
          "        raise Error(\"A radial blur's tap count is larger than this port takes\")\n"
        ]
      },
      {
        "start": 204,
        "stop": 205,
        "before": [
          "        u * Float32(view.width) - 0.5, v_down * Float32(view.height) - 0.5\n"
        ],
        "after": [
          "        clamped_texel(u, view.width), clamped_texel(v_down, view.height)\n"
        ]
      },
      {
        "start": 382,
        "stop": 383,
        "before": [
          "    var v = (Float32(y) + 0.5) / Float32(source.height)\n"
        ],
        "after": [
          "    var v = u_of(y, source.height)\n"
        ]
      },
      {
        "start": 450,
        "stop": 452,
        "before": [
          "        The pixel, premultiplied.\n"
        ],
        "after": [
          "        The pixel, premultiplied. The pixel alone when the count is\n",
          "        above 16777216.\n"
        ]
      },
      {
        "start": 454,
        "stop": 455,
        "before": [
          "    var v = (Float32(y) + 0.5) / Float32(source.height)\n"
        ],
        "after": [
          "    var v = u_of(y, source.height)\n"
        ]
      },
      {
        "start": 457,
        "stop": 464,
        "before": [],
        "after": [
          "    if settings.count > MAX_RADIAL_TAPS:\n",
          "        var held = base\n",
          "        if premultiplied:\n",
          "            held = held.unpremultiplied()\n",
          "        return FloatColor(\n",
          "            held.r, held.g, held.b, min(held.a, 1)\n",
          "        ).premultiplied()\n"
        ]
      },
      {
        "start": 543,
        "stop": 544,
        "before": [
          "    var v = (Float32(y) + 0.5) / Float32(source.height)\n"
        ],
        "after": [
          "    var v = u_of(y, source.height)\n"
        ]
      },
      {
        "start": 570,
        "stop": 573,
        "before": [
          "def bilateral_blur_light(mut frame: RenderTarget, settings: FilterSettings):\n"
        ],
        "after": [
          "def bilateral_blur_light(\n",
          "    mut frame: RenderTarget, settings: FilterSettings\n",
          ") raises:\n"
        ]
      },
      {
        "start": 579,
        "stop": 582,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the Gaussian kernel has more than 16777216 weights.\n"
        ]
      },
      {
        "start": 696,
        "stop": 697,
        "before": [
          "    var v = (Float32(y) + 0.5) / Float32(height)\n"
        ],
        "after": [
          "    var v = u_of(y, height)\n"
        ]
      },
      {
        "start": 721,
        "stop": 723,
        "before": [
          "    var px = min(max(u * Float32(width) - 0.5, 0), Float32(width - 1))\n",
          "    var py = min(max(v_down * Float32(height) - 0.5, 0), Float32(height - 1))\n"
        ],
        "after": [
          "    var px = clamped_texel(u, width)\n",
          "    var py = clamped_texel(v_down, height)\n"
        ]
      },
      {
        "start": 857,
        "stop": 858,
        "before": [
          "    var v = (Float32(y) + 0.5) / Float32(h)\n"
        ],
        "after": [
          "    var v = u_of(y, h)\n"
        ]
      }
    ]
  },
  "postprocessing/gtao.mojo": {
    "before_sha256": "e501de3e71eadbd4de6c5e74d9ddce9517749ab3b53c8d8c2c3ffd58cd3482eb",
    "after_sha256": "1e86994966146a1afc35e9a55469a97c3b3f456ace61c87b0d40340ac1d51967",
    "before_token_sha256": "bbecc4b36bd98696083ca1a90ad710557d050d79001c06010501bfc84b043e3c",
    "after_token_sha256": "602695d16d98a4cc244c786946beb7eb88fef7812ef562fd682c4c2a8cbcd8ad",
    "edits": [
      {
        "start": 124,
        "stop": 133,
        "before": [],
        "after": [
          "# A sample index is a `Float32` in the occlusion and a `Float64` in the\n",
          "# denoise disk. Past 16777216 the occlusion step is no longer that index\n",
          "# once the slices are counted in. The maximum integer wraps\n",
          "# `samples + directions`, and a count just below that does not finish.\n",
          "# The denoise disk walks one tap per sample and does not finish at the\n",
          "# maximum integer.\n",
          "comptime MAX_GTAO_SAMPLES = 16777216\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 144,
        "stop": 146,
        "before": [
          "            negative; a sample count is below two, or the denoise's radius\n",
          "            below one.\n"
        ],
        "after": [
          "            negative; a sample count is below two or above 16777216, or\n",
          "            the denoise's radius below one.\n"
        ]
      },
      {
        "start": 183,
        "stop": 188,
        "before": [],
        "after": [
          "    if (\n",
          "        settings.samples > MAX_GTAO_SAMPLES\n",
          "        or settings.denoise_samples > MAX_GTAO_SAMPLES\n",
          "    ):\n",
          "        raise Error(\"A GTAO sample count is larger than this port takes\")\n"
        ]
      },
      {
        "start": 192,
        "stop": 200,
        "before": [
          "def magic_square(size: Int) -> List[Int]:\n"
        ],
        "after": [
          "# An even side is made the odd side above it. 4095 squared is 16769025.\n",
          "# The next odd side is past 16777216 cells. A side near three billion\n",
          "# never leaves the placement loop. The maximum integer wraps the cell\n",
          "# count to one, and one below that wraps the rounded side.\n",
          "comptime MAX_MAGIC_SIDE = 4095\n",
          "\n",
          "\n",
          "def magic_square(size: Int) raises -> List[Int]:\n"
        ]
      },
      {
        "start": 205,
        "stop": 207,
        "before": [
          "        size: The side, positive.\n"
        ],
        "after": [
          "        size: The side. Zero becomes one. An even side becomes the odd\n",
          "            side above it, through 4095.\n"
        ]
      },
      {
        "start": 210,
        "stop": 213,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the odd side is below one or above 4095.\n"
        ]
      },
      {
        "start": 217,
        "stop": 219,
        "before": [],
        "after": [
          "    if n < 1 or n > MAX_MAGIC_SIDE:\n",
          "        raise Error(\"A magic square's side is larger than this port builds\")\n"
        ]
      },
      {
        "start": 250,
        "stop": 251,
        "before": [
          "def gtao_noise(size: Int = GTAO_NOISE_SIZE) -> List[FloatColor]:\n"
        ],
        "after": [
          "def gtao_noise(size: Int = GTAO_NOISE_SIZE) raises -> List[FloatColor]:\n"
        ]
      },
      {
        "start": 255,
        "stop": 257,
        "before": [
          "        size: The side, positive; an even size is made odd.\n"
        ],
        "after": [
          "        size: The side. Zero becomes one. An even size is made odd, and\n",
          "            the odd side must be from one through 4095.\n"
        ]
      },
      {
        "start": 262,
        "stop": 265,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: Everything `magic_square` raises.\n"
        ]
      },
      {
        "start": 285,
        "stop": 291,
        "before": [],
        "after": [
          "# One texel a cell. 4096 squared is 16777216. The next side is a longer\n",
          "# walk, and the maximum integer wraps the cell count and then never\n",
          "# leaves the row loop.\n",
          "comptime MAX_DENOISE_NOISE_SIDE = 4096\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 299,
        "stop": 300,
        "before": [
          "        size: The side.\n"
        ],
        "after": [
          "        size: The side, at most 4096.\n"
        ]
      },
      {
        "start": 305,
        "stop": 307,
        "before": [
          "        Error: Everything `SimplexNoise.noise` raises.\n"
        ],
        "after": [
          "        Error: If `size` is above 4096, and everything `SimplexNoise.noise`\n",
          "            raises.\n"
        ]
      },
      {
        "start": 308,
        "stop": 310,
        "before": [],
        "after": [
          "    if size > MAX_DENOISE_NOISE_SIDE:\n",
          "        raise Error(\"A denoise noise side is larger than this port builds\")\n"
        ]
      },
      {
        "start": 322,
        "stop": 323,
        "before": [
          ") -> List[Vector3]:\n"
        ],
        "after": [
          ") raises -> List[Vector3]:\n"
        ]
      },
      {
        "start": 328,
        "stop": 329,
        "before": [
          "        samples: How many, at least two.\n"
        ],
        "after": [
          "        samples: How many, at least two, and at most 16777216.\n"
        ]
      },
      {
        "start": 334,
        "stop": 337,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If `samples` is above 16777216.\n"
        ]
      },
      {
        "start": 338,
        "stop": 340,
        "before": [],
        "after": [
          "    if samples > MAX_GTAO_SAMPLES:\n",
          "        raise Error(\"A GTAO sample count is larger than this port takes\")\n"
        ]
      },
      {
        "start": 392,
        "stop": 413,
        "before": [],
        "after": [
          "def gtao_grid_side(count: Int) raises -> Int:\n",
          "    \"\"\"Return the side of a square noise grid that fits in `count` texels.\n",
          "\n",
          "    The side is the greatest integer whose square is at most `count`.\n",
          "    A `Float32` square root rounds some lengths up, and the last read is\n",
          "    then past the list.\n",
          "\n",
          "    Args:\n",
          "        count: How many noise texels there are.\n",
          "\n",
          "    Returns:\n",
          "        The side, at least one.\n",
          "\n",
          "    Raises:\n",
          "        Error: If `count` is below one.\n",
          "    \"\"\"\n",
          "    if count < 1:\n",
          "        raise Error(\"GTAO noise needs a texel\")\n",
          "    return Int(floor(sqrt(Float64(count))))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 420,
        "stop": 421,
        "before": [
          ") -> Float32:\n"
        ],
        "after": [
          ") raises -> Float32:\n"
        ]
      },
      {
        "start": 435,
        "stop": 439,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a surface pixel reads noise that has no texel, or its\n",
          "            sample count is above 16777216.\n"
        ]
      },
      {
        "start": 444,
        "stop": 446,
        "before": [],
        "after": [
          "    if settings.samples > MAX_GTAO_SAMPLES:\n",
          "        raise Error(\"A GTAO sample count is larger than this port takes\")\n"
        ]
      },
      {
        "start": 455,
        "stop": 456,
        "before": [
          "    var side = Int(sqrt(Float32(len(noise))))\n"
        ],
        "after": [
          "    var side = gtao_grid_side(len(noise))\n"
        ]
      },
      {
        "start": 528,
        "stop": 529,
        "before": [
          ") -> Float32:\n"
        ],
        "after": [
          ") raises -> Float32:\n"
        ]
      },
      {
        "start": 544,
        "stop": 547,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a surface pixel reads noise that has no texel.\n"
        ]
      },
      {
        "start": 557,
        "stop": 558,
        "before": [
          "    var side = Int(sqrt(Float32(len(noise))))\n"
        ],
        "after": [
          "    var side = gtao_grid_side(len(noise))\n"
        ]
      },
      {
        "start": 616,
        "stop": 618,
        "before": [
          "        Error: Everything `denoise_noise` raises.\n"
        ],
        "after": [
          "        Error: Everything `gtao_occlusion`, `denoise_noise` and\n",
          "            `denoise_disk` raise.\n"
        ]
      }
    ]
  },
  "postprocessing/render_passes.mojo": {
    "before_sha256": "1f5f381266824c65bf6423dae8d9cf78734a96ec4da806956037c0f7679d385e",
    "after_sha256": "882cb1fefbb1ce6476aef70507828b4d985db3d3bbdeaa8cd45e1fe6e13d9b6e",
    "before_token_sha256": "182efe9860af35eaf44814fb2f0a88105f79cfbe11e9311775c18f69997fae92",
    "after_token_sha256": "35376119f85f063778d02a4be54dbb7be9d11301b4a7071beb2e9a203c1d9c86",
    "edits": [
      {
        "start": 422,
        "stop": 424,
        "before": [
          "        Error: If the camera's matrices cannot be built.\n"
        ],
        "after": [
          "        Error: If a side is below one, the pixel count does not fit, or\n",
          "            the camera's matrices cannot be built.\n"
        ]
      },
      {
        "start": 425,
        "stop": 429,
        "before": [],
        "after": [
          "    if width < 1 or height < 1:\n",
          "        raise Error(\"A cube overlay must be at least one pixel each way\")\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"A cube overlay is larger than this port builds\")\n"
        ]
      }
    ]
  },
  "postprocessing/sampling.mojo": {
    "before_sha256": "310d11eb570ce5ed1cb0a2d35f5cadf759935b3b5d674c0b4a1bc59dec28fe0d",
    "after_sha256": "09080c213e2d3e8d899c127ac53019894a50008df1916300cad60011908d7144",
    "before_token_sha256": "027ae468f0a6ea4cbb1c5b2d3219d06fda94968b63b4dc42c13b00145b0e872a",
    "after_token_sha256": "6322c83ff7fc5904bcaee344228b31c9a17c05c80b0861362b4cac010fd47294",
    "edits": [
      {
        "start": 15,
        "stop": 18,
        "before": [
          "from math.utils import edge_index\n"
        ],
        "after": [
          "from math.utils import edge_index, texel_center, texel_center_from_end\n",
          "from std.sys import is_gpu\n",
          "from std.math import floor, isfinite\n"
        ]
      },
      {
        "start": 191,
        "stop": 213,
        "before": [],
        "after": [
          "def nearest_held_index(unit: Float32, count: Int) -> Int:\n",
          "    \"\"\"Return the nearest pixel of a coordinate, held at the edges.\n",
          "\n",
          "    A coordinate that is not finite, or one below zero, reads the first\n",
          "    pixel. A coordinate at or past one reads the last. A coordinate\n",
          "    inside the image is `floor` of the scaled coordinate.\n",
          "\n",
          "    Args:\n",
          "        unit: Across or down, zero at the first edge and one at the far\n",
          "            edge.\n",
          "        count: How many pixels there are. One or more.\n",
          "\n",
          "    Returns:\n",
          "        The pixel, from zero through `count - 1`.\n",
          "    \"\"\"\n",
          "    if not isfinite(unit) or unit <= 0:\n",
          "        return 0\n",
          "    if unit >= 1:\n",
          "        return count - 1\n",
          "    return Int(floor(unit * Float32(count)))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 249,
        "stop": 252,
        "before": [],
        "after": [
          "    A width above 2^23 is measured in `Float64`, so the last column stays\n",
          "    inside the image. A smaller width keeps the `Float32` quotient.\n",
          "\n"
        ]
      },
      {
        "start": 259,
        "stop": 260,
        "before": [
          "    return (Float32(x) + 0.5) / Float32(width)\n"
        ],
        "after": [
          "    return texel_center(x, width)\n"
        ]
      },
      {
        "start": 264,
        "stop": 267,
        "before": [],
        "after": [
          "\n",
          "    A height above 2^23 subtracts in `Float64`, so the last row stays\n",
          "    above zero. A smaller height keeps the `Float32` quotient.\n"
        ]
      },
      {
        "start": 275,
        "stop": 276,
        "before": [
          "    return 1 - (Float32(y) + 0.5) / Float32(height)\n"
        ],
        "after": [
          "    return texel_center_from_end(y, height)\n"
        ]
      },
      {
        "start": 285,
        "stop": 288,
        "before": [],
        "after": [
          "    A count past 2^24 is not a whole `Float32`. That count is multiplied\n",
          "    in `Float64`, so one still names the last pixel.\n",
          "\n"
        ]
      },
      {
        "start": 295,
        "stop": 311,
        "before": [
          "    return min(max(coordinate * Float32(count) - 0.5, 0), Float32(count - 1))\n"
        ],
        "after": [
          "    # Every integer through 2^24 is a `Float32`. The bit-exact clamps for\n",
          "    # those counts stay in `Float32`.\n",
          "    # Metal has no `Float64`, and no GPU image is 2^24 texels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 16777216:\n",
          "            var span = Float64(coordinate) * Float64(count) - 0.5\n",
          "            var limit = Float64(count) - 1\n",
          "            if span < 0:\n",
          "                span = 0\n",
          "            if span > limit:\n",
          "                span = limit\n",
          "            return Float32(span)\n",
          "    return min(\n",
          "        max(coordinate * Float32(count) - 0.5, Float32(0)),\n",
          "        Float32(count - 1),\n",
          "    )\n"
        ]
      }
    ]
  },
  "postprocessing/screen_space.mojo": {
    "before_sha256": "efc4c80b5308c811da4bc8492619bd256ecd1eac7f82fca8214fd45f4867b6f7",
    "after_sha256": "ed64de612ccaca008a041bc1cc984aad2a3b19720ffa96b959799ce4c1061ac8",
    "before_token_sha256": "3db7447cb83f42be8063848e510e64e98977f2950c0f20484fbc5cc0ffb662d0",
    "after_token_sha256": "1335f7884da890b574388d985e24464b11660f9c7c37c5e04000bbe1728c27d4",
    "edits": [
      {
        "start": 550,
        "stop": 556,
        "before": [],
        "after": [
          "# The sample index is a `Float32`, and the loop adds one each sample.\n",
          "# Past 16777216 the index is no longer that sample. The maximum integer\n",
          "# wraps the counter, so the walk never ends.\n",
          "comptime MAX_SSAO_SAMPLES = 16777216\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 557,
        "stop": 559,
        "before": [
          "    \"\"\"Refuse an SSAO kernel that holds no sample.\n"
        ],
        "after": [
          "    \"\"\"Refuse an SSAO kernel that holds no sample, or more than this\n",
          "    port walks.\n"
        ]
      },
      {
        "start": 560,
        "stop": 562,
        "before": [
          "    Nothing. The call returns when the kernel holds at least one sample.\n"
        ],
        "after": [
          "    Nothing. The call returns when the kernel holds from one sample\n",
          "    through 16777216.\n"
        ]
      },
      {
        "start": 567,
        "stop": 568,
        "before": [
          "        Error: If `size` is below one.\n"
        ],
        "after": [
          "        Error: If `size` is below one or above 16777216.\n"
        ]
      },
      {
        "start": 570,
        "stop": 572,
        "before": [],
        "after": [
          "    if size > MAX_SSAO_SAMPLES:\n",
          "        raise Error(\"An SSAO kernel is larger than this port takes\")\n"
        ]
      },
      {
        "start": 582,
        "stop": 584,
        "before": [
          "            is negative or not finite, or the kernel is empty.\n"
        ],
        "after": [
          "            is negative or not finite, or the kernel is empty or above\n",
          "            16777216.\n"
        ]
      },
      {
        "start": 617,
        "stop": 618,
        "before": [
          "        Error: If the size is not positive.\n"
        ],
        "after": [
          "        Error: If the size is below one or above 16777216.\n"
        ]
      },
      {
        "start": 759,
        "stop": 781,
        "before": [
          "def ssao_blur(values: List[Float32], width: Int, height: Int) -> List[Float32]:\n"
        ],
        "after": [
          "def require_screen_extent(width: Int, height: Int) raises:\n",
          "    \"\"\"Refuse a screen-space frame that is empty or whose pixel count wraps.\n",
          "\n",
          "    Nothing. The call returns when both sides are at least one and their\n",
          "    product fits in an integer.\n",
          "\n",
          "    Args:\n",
          "        width: The frame's width in pixels.\n",
          "        height: The frame's height in pixels.\n",
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n",
          "    \"\"\"\n",
          "    if width < 1 or height < 1:\n",
          "        raise Error(\"A screen-space frame must be at least one pixel each way\")\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"A screen-space frame is larger than this port builds\")\n",
          "\n",
          "\n",
          "def ssao_blur(\n",
          "    values: List[Float32], width: Int, height: Int\n",
          ") raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 791,
        "stop": 794,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 795,
        "stop": 796,
        "before": [],
        "after": [
          "    require_screen_extent(width, height)\n"
        ]
      },
      {
        "start": 913,
        "stop": 919,
        "before": [],
        "after": [
          "# A blur tap index is a `Float32`. Past 16777216 it is no longer that\n",
          "# index. One more than the maximum integer wraps the weight count, so\n",
          "# the center weight is missing, and one below that does not finish.\n",
          "comptime MAX_SAO_BLUR_RADIUS = 16777216\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 928,
        "stop": 930,
        "before": [
          "            is negative, or the scale, kernel radius or standard deviation\n",
          "            is not positive.\n"
        ],
        "after": [
          "            is negative, the blur radius is above 16777216, or the scale,\n",
          "            kernel radius or standard deviation is not positive.\n"
        ]
      },
      {
        "start": 949,
        "stop": 951,
        "before": [],
        "after": [
          "    if settings.blur_radius > MAX_SAO_BLUR_RADIUS:\n",
          "        raise Error(\"An SAO blur radius is larger than this port takes\")\n"
        ]
      },
      {
        "start": 1095,
        "stop": 1096,
        "before": [
          "def blur_weights(radius: Int, std_dev: Float32) -> List[Float32]:\n"
        ],
        "after": [
          "def blur_weights(radius: Int, std_dev: Float32) raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 1100,
        "stop": 1102,
        "before": [
          "        radius: The farthest tap.\n",
          "        std_dev: The standard deviation, in pixels.\n"
        ],
        "after": [
          "        radius: The farthest tap. Zero through 16777216.\n",
          "        std_dev: The standard deviation of the Gaussian, in taps.\n"
        ]
      },
      {
        "start": 1105,
        "stop": 1108,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If `radius` is negative or above 16777216.\n"
        ]
      },
      {
        "start": 1109,
        "stop": 1113,
        "before": [],
        "after": [
          "    if radius < 0:\n",
          "        raise Error(\"An SAO blur radius must not be negative\")\n",
          "    if radius > MAX_SAO_BLUR_RADIUS:\n",
          "        raise Error(\"An SAO blur radius is larger than this port takes\")\n"
        ]
      },
      {
        "start": 1377,
        "stop": 1404,
        "before": [],
        "after": [
          "def _ssr_max_step(width: Int, height: Int) -> Float32:\n",
          "    \"\"\"Return the frame's diagonal in pixels, three.js's `MAX_STEP`.\n",
          "\n",
          "    The squares are `Float64`. An `Int` product wraps a wide frame, and\n",
          "    `Int` of the square root is then not the diagonal.\n",
          "\n",
          "    Args:\n",
          "        width: The frame's width, in pixels.\n",
          "        height: The frame's height, in pixels.\n",
          "\n",
          "    Returns:\n",
          "        The diagonal, cut toward zero. A diagonal past what an integer\n",
          "        holds is the `Float32` of that square root.\n",
          "\n",
          "    Error: Never.\n",
          "    \"\"\"\n",
          "    var span = Float64(width) * Float64(width) + Float64(height) * Float64(\n",
          "        height\n",
          "    )\n",
          "    var steps = floor(sqrt(span))\n",
          "    # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "    # the step count.\n",
          "    if steps >= Float64(Int.MAX):\n",
          "        return Float32(steps)\n",
          "    return Float32(Int(steps))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 1455,
        "stop": 1456,
        "before": [
          "    var max_step = Float32(Int(sqrt(Float32(width * width + height * height))))\n"
        ],
        "after": [
          "    var max_step = _ssr_max_step(width, height)\n"
        ]
      },
      {
        "start": 1505,
        "stop": 1506,
        "before": [
          ") -> List[FloatColor]:\n"
        ],
        "after": [
          ") raises -> List[FloatColor]:\n"
        ]
      },
      {
        "start": 1517,
        "stop": 1520,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n"
        ]
      },
      {
        "start": 1521,
        "stop": 1522,
        "before": [],
        "after": [
          "    require_screen_extent(width, height)\n"
        ]
      }
    ]
  },
  "postprocessing/shaders.mojo": {
    "before_sha256": "052526c1ec9b91c7e1e250ca7ace945d2403aec55abfa0c678c9a82081864b7f",
    "after_sha256": "f28e9e019ac662c453a68f6851c86a5fcdee0670dbb8e4d0d142ba362906718b",
    "before_token_sha256": "228105d752af61ab95ca249aaf16a74d158e5fa4868f7b6436645a639d7d5731",
    "after_token_sha256": "e6b495a42388097a71051dd32de816ec51a8999c73ee65e3cb9ab22fbdf81b5c",
    "edits": [
      {
        "start": 70,
        "stop": 71,
        "before": [],
        "after": [
          "from math.utils import scaled_side\n"
        ]
      },
      {
        "start": 1365,
        "stop": 1366,
        "before": [
          "def god_rays_size(size: Int, scale: Float32) -> Int:\n"
        ],
        "after": [
          "def god_rays_size(size: Int, scale: Float32) raises -> Int:\n"
        ]
      },
      {
        "start": 1368,
        "stop": 1372,
        "before": [],
        "after": [
          "\n",
          "    The product is `math.utils.scaled_side`'s: `Float32` to 2^24, so 1000 times\n",
          "    0.9 is 900 as in JavaScript, and `Float64` past it. The cut is toward\n",
          "    zero.\n"
        ]
      },
      {
        "start": 1379,
        "stop": 1382,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the product is not finite or does not fit in an integer.\n"
        ]
      },
      {
        "start": 1383,
        "stop": 1393,
        "before": [
          "    return max(1, Int(Float32(size) * scale))\n"
        ],
        "after": [
          "    var scaled = scaled_side(size, scale)\n",
          "    # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "    # the size. A float below `-2^63` is not one either.\n",
          "    if (\n",
          "        not isfinite(scaled)\n",
          "        or scaled < -Float64(Int.MAX)\n",
          "        or scaled >= Float64(Int.MAX)\n",
          "    ):\n",
          "        raise Error(\"A god-ray size does not fit in an integer\")\n",
          "    return max(1, Int(scaled))\n"
        ]
      },
      {
        "start": 1627,
        "stop": 1628,
        "before": [
          ") -> List[FloatColor]:\n"
        ],
        "after": [
          ") raises -> List[FloatColor]:\n"
        ]
      },
      {
        "start": 1639,
        "stop": 1642,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a ray size does not fit in an integer.\n"
        ]
      },
      {
        "start": 1672,
        "stop": 1673,
        "before": [
          "):\n"
        ],
        "after": [
          ") raises:\n"
        ]
      },
      {
        "start": 1681,
        "stop": 1684,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a ray size does not fit in an integer.\n"
        ]
      }
    ]
  },
  "postprocessing/ssgi.mojo": {
    "before_sha256": "00088da9e550fd6172c970f06d0d87a8dfdb9a37ced23ccab6c373bb0dff2dfd",
    "after_sha256": "2d8ba4d709bb4996b0185b5a72df8c32fe60968c6c31242daf621c7a0905ee17",
    "before_token_sha256": "54627448dfc189a441c69bc1d053ec43214e5fe85f8c1d3f35aadaa0653fc16c",
    "after_token_sha256": "7f60293bceaa4efd674e1be4f2de570bccfe12bcd0309aa24bb27e0bd756d9e0",
    "edits": [
      {
        "start": 125,
        "stop": 130,
        "before": [],
        "after": [
          "# A slice or a step index is a `Float32`. Past 16777216 it is no longer\n",
          "# that index, and a count of the maximum integer does not finish the march.\n",
          "comptime MAX_SSGI_TAPS = 16777216\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 138,
        "stop": 140,
        "before": [
          "            or the step's growth is not positive, or the frame count is\n",
          "            negative.\n"
        ],
        "after": [
          "            or the step's growth is not positive, the frame count is\n",
          "            negative, or a slice or step count is above 16777216.\n"
        ]
      },
      {
        "start": 143,
        "stop": 150,
        "before": [],
        "after": [
          "    if (\n",
          "        settings.slice_count > MAX_SSGI_TAPS\n",
          "        or settings.step_count > MAX_SSGI_TAPS\n",
          "    ):\n",
          "        raise Error(\n",
          "            \"An SSGI slice or step count is larger than this port marches\"\n",
          "        )\n"
        ]
      },
      {
        "start": 292,
        "stop": 296,
        "before": [],
        "after": [
          "    A count past 32 covers only the 32 sectors of the slice. `Int` of a\n",
          "    count past 2^63 is not that count. A span that is not a positive\n",
          "    number covers nothing.\n",
          "\n"
        ]
      },
      {
        "start": 301,
        "stop": 302,
        "before": [
          "        The bits.\n"
        ],
        "after": [
          "        The bits that fall inside the 32 sectors.\n"
        ]
      },
      {
        "start": 303,
        "stop": 305,
        "before": [
          "    var first = UInt32(Int(start * Float32(SSGI_SECTORS)))\n",
          "    var count = Int(ceil(span * Float32(SSGI_SECTORS)))\n",
          "    if count <= 0:\n"
        ],
        "after": [
          "    var wide = ceil(Float64(span) * Float64(SSGI_SECTORS))\n",
          "    if not (wide > 0):\n"
        ]
      },
      {
        "start": 306,
        "stop": 321,
        "before": [
          "    # A span that covers a sector starts inside the slice, so the shift is\n",
          "    # below 32.\n",
          "    var field = UInt32(0xFFFFFFFF) >> UInt32(SSGI_SECTORS - count)\n",
          "    return field << first\n"
        ],
        "after": [
          "    var count = SSGI_SECTORS\n",
          "    if wide < Float64(SSGI_SECTORS):\n",
          "        count = Int(wide)\n",
          "    var begin = Float64(start) * Float64(SSGI_SECTORS)\n",
          "    var end = begin + Float64(count)\n",
          "    if not (end > 0) or not (begin < Float64(SSGI_SECTORS)):\n",
          "        return 0\n",
          "    if begin < 0:\n",
          "        begin = 0\n",
          "    if end > Float64(SSGI_SECTORS):\n",
          "        end = Float64(SSGI_SECTORS)\n",
          "    var first = Int(begin)\n",
          "    var covered = Int(end) - first\n",
          "    var field = UInt32(0xFFFFFFFF) >> UInt32(SSGI_SECTORS - covered)\n",
          "    return field << UInt32(first)\n"
        ]
      },
      {
        "start": 467,
        "stop": 469,
        "before": [
          "        surface, as three.js's target is cleared.\n"
        ],
        "after": [
          "        surface, as three.js's target is cleared. A slice or step count\n",
          "        above 16777216 returns no indirect light.\n"
        ]
      },
      {
        "start": 477,
        "stop": 482,
        "before": [],
        "after": [
          "    if (\n",
          "        settings.slice_count > MAX_SSGI_TAPS\n",
          "        or settings.step_count > MAX_SSGI_TAPS\n",
          "    ):\n",
          "        return FloatColor(0, 0, 0, stored(1, UNSIGNED_BYTE_TARGET))\n"
        ]
      }
    ]
  },
  "postprocessing/ssr_node.mojo": {
    "before_sha256": "5f67ef82f9e973a1fb0c3eed286302c1c5a4b2ea60c72f7698905b4f129ed2a2",
    "after_sha256": "5a3482876ba7058dd2fb72e1e47fdacc3df0c7604f5d90b6925d355cf7467c55",
    "before_token_sha256": "1510fdbbb9a24d90396b6c6c4250f5b0746c304a61b16841e69f4b47818bdc5b",
    "after_token_sha256": "d2180c8fd2e888f47cad5cf24df8439ea6f833f2a3eb3b6967937970692a5079",
    "edits": [
      {
        "start": 103,
        "stop": 105,
        "before": [
          "            positive, the thickness is negative, or the blur's reach is\n",
          "            negative.\n"
        ],
        "after": [
          "            positive, the thickness is negative, the blur's reach is\n",
          "            negative, or the blur's reach is above 2047.\n"
        ]
      },
      {
        "start": 119,
        "stop": 121,
        "before": [],
        "after": [
          "    if settings.blur_quality > 2047:\n",
          "        raise Error(\"An SSR blur's reach is larger than this port takes\")\n"
        ]
      },
      {
        "start": 324,
        "stop": 325,
        "before": [
          ") -> List[FloatColor]:\n"
        ],
        "after": [
          ") raises -> List[FloatColor]:\n"
        ]
      },
      {
        "start": 338,
        "stop": 342,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, the pixel count does not fit, or\n",
          "            the reach is above 2047 taps from the center.\n"
        ]
      },
      {
        "start": 343,
        "stop": 349,
        "before": [],
        "after": [
          "    if size > 2047:\n",
          "        raise Error(\"An SSR blur's reach is larger than this port takes\")\n",
          "    if width < 1 or height < 1:\n",
          "        raise Error(\"An SSR blur must be at least one pixel each way\")\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"An SSR blur is larger than this port builds\")\n"
        ]
      }
    ]
  },
  "postprocessing/taau.mojo": {
    "before_sha256": "61cd620a5a8bd512595053cb03d35453f5caf679bbef254df641671caec81ff3",
    "after_sha256": "9b860bde0c1a826b52851b3764f83ea9758a822469d98c60cd5a128a35ec5547",
    "before_token_sha256": "b402850bff8fb0f667627fc55e2a321b905b3a25bfdb5b5757ba4e2290be546a",
    "after_token_sha256": "ce0f324a3cd83deacbd93e138fc77d8d53176047194101f397de0bff29e39707",
    "edits": [
      {
        "start": 559,
        "stop": 560,
        "before": [
          "def taau_input_size(size: Int, scale: Float32) -> Int:\n"
        ],
        "after": [
          "def taau_input_size(size: Int, scale: Float32) raises -> Int:\n"
        ]
      },
      {
        "start": 569,
        "stop": 572,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the rounded side does not fit in an integer.\n"
        ]
      }
    ]
  },
  "postprocessing/temporal_denoise.mojo": {
    "before_sha256": "e46cc2113e4577c324bc13e43ff058594614b41a6e54f5c391c1aba537e89da7",
    "after_sha256": "2e72af9f46d43482ec9d71b260f4694d51ffc14a6ef230cfd1e902eb3fd7ed11",
    "before_token_sha256": "7f0d2152f76bdea22465daaf553ef04a264ff48fc329901866000702a61ee169",
    "after_token_sha256": "2a58e5922c3db56a4a7c11c50db85657f90406c9160bc61272366cd3238c55aa",
    "edits": [
      {
        "start": 53,
        "stop": 54,
        "before": [
          "from postprocessing.sampling import LightView\n"
        ],
        "after": [
          "from postprocessing.sampling import LightView, nearest_held_index\n"
        ]
      },
      {
        "start": 337,
        "stop": 356,
        "before": [],
        "after": [
          "def require_denoise_extent(width: Int, height: Int) raises:\n",
          "    \"\"\"Refuse a denoise frame that is empty or whose pixel count would wrap.\n",
          "\n",
          "    Nothing. The call returns when both sides are at least one and their\n",
          "    product fits in an integer.\n",
          "\n",
          "    Args:\n",
          "        width: The frame's width in pixels.\n",
          "        height: The frame's height in pixels.\n",
          "\n",
          "    Raises:\n",
          "        Error: If a side is below one, or the pixel count does not fit.\n",
          "    \"\"\"\n",
          "    if width < 1 or height < 1:\n",
          "        raise Error(\"A denoise frame must be at least one pixel each way\")\n",
          "    if width > Int.MAX // height:\n",
          "        raise Error(\"A denoise frame is larger than this port builds\")\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 396,
        "stop": 398,
        "before": [
          "            Error: If a list does not have one entry a pixel.\n"
        ],
        "after": [
          "            Error: If a side is below one, the pixel count does not fit,\n",
          "                or a list does not have one entry a pixel.\n"
        ]
      },
      {
        "start": 399,
        "stop": 400,
        "before": [],
        "after": [
          "        require_denoise_extent(width, height)\n"
        ]
      },
      {
        "start": 902,
        "stop": 905,
        "before": [
          "            Error: If a list does not have one entry a pixel, or the\n",
          "                projection cannot be inverted.\n"
        ],
        "after": [
          "            Error: If a side is below one, the pixel count does not fit, a\n",
          "                list does not have one entry a pixel, or the projection\n",
          "                cannot be inverted.\n"
        ]
      },
      {
        "start": 906,
        "stop": 907,
        "before": [],
        "after": [
          "        require_denoise_extent(width, height)\n"
        ]
      },
      {
        "start": 960,
        "stop": 962,
        "before": [
          "            The depth.\n"
        ],
        "after": [
          "            The depth. A coordinate at or past the far edge reads the last\n",
          "            pixel. A coordinate that is not finite reads the first.\n"
        ]
      },
      {
        "start": 963,
        "stop": 965,
        "before": [
          "        var x = edge_index(Int(floor(u * Float32(self.width))), self.width)\n",
          "        var y = edge_index(Int(floor(v * Float32(self.height))), self.height)\n"
        ],
        "after": [
          "        var x = nearest_held_index(u, self.width)\n",
          "        var y = nearest_held_index(v, self.height)\n"
        ]
      }
    ]
  },
  "postprocessing/traa.mojo": {
    "before_sha256": "82e768d9ef82b46099fe8bf0b0c29767ca5256dd577399f368f5c3995576ec38",
    "after_sha256": "8343ed88fa83b29529a664adb3602989cb427b0fa8772fb3a873eee16889884e",
    "before_token_sha256": "d79b66da89b66076777041c6f3c11cd9299559102d894a5e54a930356c72ca07",
    "after_token_sha256": "4309d6dcaae5ea1881f69e16fe9197ed21cb354abd1d2191fcd9914f192dba01",
    "edits": [
      {
        "start": 52,
        "stop": 53,
        "before": [
          "from postprocessing.sampling import LightView, Untracked\n"
        ],
        "after": [
          "from postprocessing.sampling import LightView, Untracked, nearest_held_index\n"
        ]
      },
      {
        "start": 63,
        "stop": 64,
        "before": [
          "from std.math import floor, isfinite, max, min, sqrt\n"
        ],
        "after": [
          "from std.math import isfinite, max, min, sqrt\n"
        ]
      },
      {
        "start": 537,
        "stop": 539,
        "before": [
          "    var x = Int(floor(u * Float32(previous.width)))\n",
          "    var y = Int(floor(v_down * Float32(previous.height)))\n"
        ],
        "after": [
          "    var x = nearest_held_index(u, previous.width)\n",
          "    var y = nearest_held_index(v_down, previous.height)\n"
        ]
      }
    ]
  },
  "postprocessing/upscaling.mojo": {
    "before_sha256": "5d62ba790a684375501e15dbea98dae6005d696efc889dfa7a83c7cb0c3cc96d",
    "after_sha256": "2bb5962659d0ad8d4f1e7d63d7ebf5aff13a559d3b08685d24084fd24a6d7a8e",
    "before_token_sha256": "fd9fa580429fdfe48e9058184eaa7ee09cf0c7777dd602bd38808248fc1dad5c",
    "after_token_sha256": "bace6882cad5eabcc1be957a8a5dee6af9764833466b4bff45beaf34e72be35d",
    "edits": [
      {
        "start": 465,
        "stop": 466,
        "before": [
          "def fsr1_light(mut frame: RenderTarget, settings: UpscaleSettings):\n"
        ],
        "after": [
          "def fsr1_light(mut frame: RenderTarget, settings: UpscaleSettings) raises:\n"
        ]
      },
      {
        "start": 474,
        "stop": 477,
        "before": [],
        "after": [
          "\n",
          "    Raises:\n",
          "        Error: If the scaled side does not fit in an integer.\n"
        ]
      }
    ]
  },
  "render/css_color.mojo": {
    "before_sha256": "bcfa54778b83bf4056cbf15b7602f6a66e0a01c6778e87b75440fa667275e567",
    "after_sha256": "c8150acb98edb979bb217d44099dc935f47a5f61128f27ca1a5affe4fec080c9",
    "before_token_sha256": "60db987a9a1bdca8c7822256f9a01be7b1255048e85ad85f61d4acb9884a011d",
    "after_token_sha256": "9ec3e1ec6381797b3d4fa633bcf3ef267b73c76bfbab70baec63b661cfed0b10",
    "edits": [
      {
        "start": 33,
        "stop": 34,
        "before": [],
        "after": [
          "from loaders.js_number import js_to_fixed\n"
        ]
      },
      {
        "start": 37,
        "stop": 39,
        "before": [
          "from math.utils import js_round_int\n",
          "from std.math import floor\n"
        ],
        "after": [
          "from math.utils import js_round\n",
          "from std.math import isfinite\n"
        ]
      },
      {
        "start": 666,
        "stop": 705,
        "before": [
          "def _fixed3(value: Float32) -> String:\n",
          "    \"\"\"Return `value` with three decimals, as JavaScript's `toFixed(3)`\n",
          "    writes it: a tie rounds away from zero, and a negative value keeps its\n",
          "    sign even when it rounds to zero.\"\"\"\n",
          "    var magnitude = abs(Float64(value))\n",
          "    var thousandths = Int(floor(magnitude * 1000 + 0.5))\n",
          "    var fraction = String(thousandths % 1000)\n",
          "    while fraction.byte_length() < 3:\n",
          "        fraction = \"0\" + fraction\n",
          "    var sign = \"-\" if value < 0 else \"\"\n",
          "    return sign + String(thousandths // 1000) + \".\" + fraction\n"
        ],
        "after": [
          "def _fixed3(value: Float32) raises -> String:\n",
          "    \"\"\"Return `value` with three decimals, JavaScript's `toFixed(3)`.\n",
          "\n",
          "    A tie rounds away from zero. A negative value keeps its sign even\n",
          "    when it rounds to zero. From `1e21` up, and for NaN and the\n",
          "    infinities, the text is JavaScript's `String`.\n",
          "\n",
          "    Args:\n",
          "        value: The channel.\n",
          "\n",
          "    Returns:\n",
          "        The text.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the digit count is refused. This call passes three.\n",
          "    \"\"\"\n",
          "    return js_to_fixed(Float64(value), 3)\n",
          "\n",
          "\n",
          "def _channel_text(value: Float32) raises -> String:\n",
          "    \"\"\"Return one encoded channel as JavaScript's `Math.round` writes it.\n",
          "\n",
          "    Args:\n",
          "        value: The linear channel.\n",
          "\n",
          "    Returns:\n",
          "        The whole number. A rounded value at or past 2^63, or one that\n",
          "        is not finite, is written by `toFixed`, which uses exponent text\n",
          "        from `1e21`.\n",
          "\n",
          "    Raises:\n",
          "        Error: If the digit count is refused. This call passes zero.\n",
          "    \"\"\"\n",
          "    var rounded = js_round(Float64(linear_to_srgb(value)) * 255)\n",
          "    # `Float64(Int.MAX)` is 2^63. `Int` of a float at or past it is not\n",
          "    # the number. From 2^53 the value is already a whole number.\n",
          "    if not isfinite(rounded) or abs(rounded) >= Float64(Int.MAX):\n",
          "        return js_to_fixed(rounded, 0)\n",
          "    return String(Int(rounded))\n"
        ]
      },
      {
        "start": 727,
        "stop": 728,
        "before": [
          "            + String(js_round_int(Float64(linear_to_srgb(color.r)) * 255))\n"
        ],
        "after": [
          "            + _channel_text(color.r)\n"
        ]
      },
      {
        "start": 729,
        "stop": 730,
        "before": [
          "            + String(js_round_int(Float64(linear_to_srgb(color.g)) * 255))\n"
        ],
        "after": [
          "            + _channel_text(color.g)\n"
        ]
      },
      {
        "start": 731,
        "stop": 732,
        "before": [
          "            + String(js_round_int(Float64(linear_to_srgb(color.b)) * 255))\n"
        ],
        "after": [
          "            + _channel_text(color.b)\n"
        ]
      }
    ]
  },
  "render/cube_texture.mojo": {
    "before_sha256": "28c83baf52788ffb412328360ceef2397de1ec33489ee1516d447e3fc8d1f79c",
    "after_sha256": "28aac07dfc280acbea10d121c32db300e772cc42de75f43ccab7c3e6cdda3300",
    "before_token_sha256": "d894d0a2e318cb4d1e61e02ca05cd50308a7d5d3129f492008fbfa735b22fc50",
    "after_token_sha256": "07f7e67f083f917dffc53a4c1f291658fff23c3e648e2b13093e835fe0b02447",
    "edits": [
      {
        "start": 841,
        "stop": 843,
        "before": [
          "    on the plane one unit out along `face_forward`.\n"
        ],
        "after": [
          "    on the plane one unit out along `face_forward`. A face above 2^23\n",
          "    measures that center in `Float64`.\n"
        ]
      },
      {
        "start": 858,
        "stop": 869,
        "before": [
          "    var across = (Float32(x) + 0.5) / Float32(size) * 2 - 1\n",
          "    var upward = 1 - (Float32(y) + 0.5) / Float32(size) * 2\n"
        ],
        "after": [
          "    # A `Float32` face above 2^23 cannot add the half that marks a texel\n",
          "    # center, so the last texel reads as the edge. A smaller face keeps\n",
          "    # the `Float32` quotient.\n",
          "    var across: Float32\n",
          "    var upward: Float32\n",
          "    if size > 8388608:\n",
          "        across = Float32((Float64(x) + 0.5) / Float64(size) * 2 - 1)\n",
          "        upward = Float32(1 - (Float64(y) + 0.5) / Float64(size) * 2)\n",
          "    else:\n",
          "        across = (Float32(x) + 0.5) / Float32(size) * 2 - 1\n",
          "        upward = 1 - (Float32(y) + 0.5) / Float32(size) * 2\n"
        ]
      }
    ]
  },
  "render/cube_uv.mojo": {
    "before_sha256": "8bd7e1dd5fb4eb131747759c7dfdb86f71ec2f77d4d99dd6735d924ae7756bbe",
    "after_sha256": "6fa1910f90bf4ac79240570a2b1a483229f158838fc8bcf884ac2db2cf88c97b",
    "before_token_sha256": "ec3d604a65abe615e654e82ac2b8bd0479c4dd0a0efa4d1671669abb31920d69",
    "after_token_sha256": "9249b07bd9e41bb14b0dfd1818a4ee9096c1d8a224045d90511e0ebd7f0bb5e6",
    "edits": [
      {
        "start": 181,
        "stop": 183,
        "before": [
          "        rounded down.\n"
        ],
        "after": [
          "        rounded down. A height past the sizes an integer can name reads\n",
          "        as sixty.\n"
        ]
      },
      {
        "start": 185,
        "stop": 187,
        "before": [
          "    while (4 << (lod + 1)) <= height:\n"
        ],
        "after": [
          "    # `4 << 61` wraps, so a larger shift is not a taller image.\n",
          "    while lod < 60 and (4 << (lod + 1)) <= height:\n"
        ]
      }
    ]
  },
  "render/fillrule.mojo": {
    "before_sha256": "8fd002f05d9f75b8f4d10050fbf6b1b92b2247db030cdb9974f90eb2b820a7c8",
    "after_sha256": "6b1b0737f40bf8f611faabaa424deb04ad1eea27ce482b4ec08ccce48e362320",
    "before_token_sha256": "bfcbfbac9aeba049a01ccdc97c768205f348adf44698f98a5cf0ab8b555411b2",
    "after_token_sha256": "f72f47a513bb38e6501443e3b7f4eb58cf684cbed252b70bc4e8e0f23e675052",
    "edits": [
      {
        "start": 43,
        "stop": 48,
        "before": [],
        "after": [
          "# The edge function multiplies two coordinate deltas. A snap at \u00b12^29 keeps\n",
          "# the widest difference of those products inside an integer. That is a\n",
          "# screen coordinate of \u00b12^25 pixels.\n",
          "comptime _GUARD_PIXELS = 1 << 25\n",
          "comptime _GUARD_SNAP = _GUARD_PIXELS * SUBPIXEL\n"
        ]
      },
      {
        "start": 51,
        "stop": 62,
        "before": [
          "    \"\"\"Return a screen coordinate on the subpixel grid, as an integer.\"\"\"\n"
        ],
        "after": [
          "    \"\"\"Return a screen coordinate on the subpixel grid, as an integer.\n",
          "\n",
          "    A coordinate at or past 2^25 pixels is held on that guard band. Past\n",
          "    it, the edge function's product does not fit in an integer, and `Int`\n",
          "    of a float past 2^63 is not that coordinate.\n",
          "    \"\"\"\n",
          "    var guard = Float32(_GUARD_PIXELS)\n",
          "    if not (value < guard):\n",
          "        return _GUARD_SNAP\n",
          "    if value <= -guard:\n",
          "        return -_GUARD_SNAP\n"
        ]
      }
    ]
  },
  "render/framebuffer.mojo": {
    "before_sha256": "cc907b6c905ad936f68fca609a7ddcffcd2090977088170670c4b43bfa6ad6ef",
    "after_sha256": "c6b8bf7ff701e94efeae63aa0526e564290351519eab9bd33cfc87818f7a34c0",
    "before_token_sha256": "e70af1c36bb5d37d96a6b21f241a38e07b88d4d6c7964bde8734b2e8c1388aa4",
    "after_token_sha256": "1b34b108d7f0fe7f5a90fbcfb6f02e58fa39b83f62d391cfc9159a0e508f9275",
    "edits": [
      {
        "start": 862,
        "stop": 865,
        "before": [
          "    The fraction is multiplied by 255, one half is added, and the whole\n",
          "    number is kept.\n"
        ],
        "after": [
          "    The fraction is held from zero to one, multiplied by 255, and rounded\n",
          "    to the nearest byte. A half rounds up. NaN and positive infinity are\n",
          "    one, so the byte is 255. Negative infinity is zero.\n"
        ]
      },
      {
        "start": 875,
        "stop": 879,
        "before": [
          "    return UInt8(Int(value * 255 + 0.5))\n"
        ],
        "after": [
          "    # `clamp` holds NaN at one and an infinity at the nearer end. The\n",
          "    # product then stays inside 0.5 through 255.5, so the cast fits.\n",
          "    var held = clamp(value, 0, 1)\n",
          "    return UInt8(Int(held * 255 + 0.5))\n"
        ]
      },
      {
        "start": 1020,
        "stop": 1022,
        "before": [
          "        Error: If the width or the height is not positive.\n"
        ],
        "after": [
          "        Error: If the width or the height is not positive, or four bytes\n",
          "            a pixel does not fit in an integer.\n"
        ]
      },
      {
        "start": 1026,
        "stop": 1030,
        "before": [],
        "after": [
          "    # Four bytes a pixel is the larger product. A wrapped count would\n",
          "    # allocate the wrong buffer.\n",
          "    if width > (Int.MAX // 4) // height:\n",
          "        raise Error(\"A framebuffer is larger than this port stores\")\n"
        ]
      }
    ]
  },
  "render/jpeg.mojo": {
    "before_sha256": "6c21c7fbd0b7293bb7b087e17d6fc309b025b0dc214e8dba90b2fe5c8ad39166",
    "after_sha256": "96c053bd6387fb1b2f15cd4917d54bd8099d99ff625c18d02c82fb6675d40473",
    "before_token_sha256": "ffa2aeccbf20b6c652cb245bb832e99873c81e307824568ca393201dd016845f",
    "after_token_sha256": "77dac5b0a615da06f5ba29ce47c70a153c1c30de35d8b335bf4ea57add4bce82",
    "edits": [
      {
        "start": 277,
        "stop": 281,
        "before": [],
        "after": [
          "    A value below -0.5, or one that is not a number, is zero. A value at\n",
          "    255.5 or past it is 255. `Int` of a sample past 2^63 is not that\n",
          "    sample, so the range is checked before the cast.\n",
          "\n"
        ]
      },
      {
        "start": 287,
        "stop": 288,
        "before": [
          "    var rounded = Int(floor(value + 0.5))\n",
          "    if rounded < 0:\n"
        ],
        "after": [
          "    if not (value >= -0.5):\n"
        ]
      },
      {
        "start": 289,
        "stop": 290,
        "before": [
          "    if rounded > 255:\n"
        ],
        "after": [
          "    if not (value < 255.5):\n"
        ]
      },
      {
        "start": 291,
        "stop": 292,
        "before": [
          "    return UInt8(rounded)\n"
        ],
        "after": [
          "    return UInt8(Int(floor(value + 0.5)))\n"
        ]
      }
    ]
  },
  "render/linerule.mojo": {
    "before_sha256": "0d809e132f3019d04cef9734e9841dfbd0244aac738ed4d09bb40b9c45faf07e",
    "after_sha256": "2aa592b2b8e171fd31997c558495ba52228d101c683a48d901417146f6f4aab2",
    "before_token_sha256": "f0ed4323fa3d600f6f29db55d3c0e09fac3b99f0c067ebed1e28d07643912ddd",
    "after_token_sha256": "790c0b8173fa218d368f47293abec5481d4391d944422628578e5ff0c1e22a92",
    "edits": [
      {
        "start": 91,
        "stop": 134,
        "before": [],
        "after": [
          "# Far enough past any image a render target can name, and far enough from\n",
          "# either end of `Int` that a step count can subtract it. 2^62.\n",
          "comptime _AXIS_FAR = 1 << 62\n",
          "\n",
          "\n",
          "def _axis_index(value: Float32) -> Int:\n",
          "    \"\"\"Return the floor of one screen coordinate.\n",
          "\n",
          "    A value that is not finite, or that does not fit in an integer, is\n",
          "    not a stable pixel index. It is held at `\u00b12^62`, past the image, where\n",
          "    a later subtraction still fits.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate, in pixels.\n",
          "\n",
          "    Returns:\n",
          "        The floor, or `\u00b1_AXIS_FAR` when `value` does not fit.\n",
          "    \"\"\"\n",
          "    var limit = Float32(Int.MAX)\n",
          "    if not (value < limit):\n",
          "        return _AXIS_FAR\n",
          "    if value <= -limit:\n",
          "        return -_AXIS_FAR\n",
          "    return Int(floor(value))\n",
          "\n",
          "\n",
          "def _step_count(start: Int, end: Int) -> Int:\n",
          "    \"\"\"Return how many steps lie from `start` through `end`, inclusive.\n",
          "\n",
          "    Args:\n",
          "        start: The first major-axis index.\n",
          "        end: The last major-axis index.\n",
          "\n",
          "    Returns:\n",
          "        The count, or `Int.MAX` when the distance does not fit.\n",
          "    \"\"\"\n",
          "    var low = min(start, end)\n",
          "    var high = max(start, end)\n",
          "    if low < 0 and high > Int.MAX + low:\n",
          "        return Int.MAX\n",
          "    return high - low + 1\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 138,
        "stop": 141,
        "before": [
          "    two ends land on one pixel lights that pixel.\n"
        ],
        "after": [
          "    two ends land on one pixel lights that pixel. An end that does not fit\n",
          "    in an integer lies past the image, and a span that does not fit is\n",
          "    `Int.MAX`.\n"
        ]
      },
      {
        "start": 150,
        "stop": 152,
        "before": [
          "        return Int(abs(floor(b.x) - floor(a.x))) + 1\n",
          "    return Int(abs(floor(b.y) - floor(a.y))) + 1\n"
        ],
        "after": [
          "        return _step_count(_axis_index(a.x), _axis_index(b.x))\n",
          "    return _step_count(_axis_index(a.y), _axis_index(b.y))\n"
        ]
      },
      {
        "start": 156,
        "stop": 158,
        "before": [],
        "after": [
          "\n",
          "    An end that does not fit in an integer lies past the image.\n"
        ]
      },
      {
        "start": 168,
        "stop": 169,
        "before": [
          "        var start = Int(floor(a.x))\n"
        ],
        "after": [
          "        var start = _axis_index(a.x)\n"
        ]
      },
      {
        "start": 172,
        "stop": 173,
        "before": [
          "    var start = Int(floor(a.y))\n"
        ],
        "after": [
          "    var start = _axis_index(a.y)\n"
        ]
      },
      {
        "start": 249,
        "stop": 250,
        "before": [
          "    return Int(floor(minor_at(a, b, major)))\n"
        ],
        "after": [
          "    return _axis_index(minor_at(a, b, major))\n"
        ]
      },
      {
        "start": 278,
        "stop": 279,
        "before": [
          "    return Int(floor(minor_at(a, b, major) - Float32(width - 1) / 2))\n"
        ],
        "after": [
          "    return _axis_index(minor_at(a, b, major) - Float32(width - 1) / 2)\n"
        ]
      },
      {
        "start": 303,
        "stop": 305,
        "before": [
          "    var first = Int(floor(a.y))\n",
          "    var last = Int(floor(b.y))\n"
        ],
        "after": [
          "    var first = _axis_index(a.y)\n",
          "    var last = _axis_index(b.y)\n"
        ]
      },
      {
        "start": 306,
        "stop": 308,
        "before": [
          "        first = Int(floor(a.x))\n",
          "        last = Int(floor(b.x))\n"
        ],
        "after": [
          "        first = _axis_index(a.x)\n",
          "        last = _axis_index(b.x)\n"
        ]
      }
    ]
  },
  "render/pmrem.mojo": {
    "before_sha256": "6b055c91b26dbd7357e9c45d64d9d1625b5950e91366a89d139c57b692595348",
    "after_sha256": "9ff8dd71d6012f4568f052db99c9905c8a937c0675295bef967897d458ef8a82",
    "before_token_sha256": "b5079eb441327523c8fea2e1943df6b877e95f6399baf923f1f450b02ff1674f",
    "after_token_sha256": "cf686b3b596905c0950b105f274aba09c704135caf86dc216d2d9a04102f9c13",
    "edits": [
      {
        "start": 130,
        "stop": 132,
        "before": [
          "        smaller than sixteen texels is read at sixteen.\n"
        ],
        "after": [
          "        smaller than sixteen texels is read at sixteen. A source past the\n",
          "        sizes an integer can name is read at sixty-two.\n"
        ]
      },
      {
        "start": 134,
        "stop": 136,
        "before": [
          "    while (2 << lod) <= size:\n"
        ],
        "after": [
          "    # `2 << 62` wraps, so a larger shift is not a larger size.\n",
          "    while lod < 62 and (2 << lod) <= size:\n"
        ]
      }
    ]
  },
  "render/pointrule.mojo": {
    "before_sha256": "d14ec24423ca7c77257aa379d657fefb34aa3f5658eb729d334cdab4ae9390ab",
    "after_sha256": "9ae8436f346cef4d3f931daa609aa5f41d3e801538e8b3861dddc25c37d8c871",
    "before_token_sha256": "0ced7cee25e4e68325bc7a135caf94d6697d6717558ca67a97d44a7dfd61a832",
    "after_token_sha256": "2b6ea7fdba12f42b5aff77cde792ddd7d489cbac1fbbaedaaffbdab498390068",
    "edits": [
      {
        "start": 181,
        "stop": 204,
        "before": [],
        "after": [
          "def _covered_index(edge: Float32, round_up: Bool) -> Int:\n",
          "    \"\"\"Return the pixel index of one edge of a point.\n",
          "\n",
          "    An edge that is not finite, or that does not fit in an integer, is\n",
          "    past every pixel. `Int` of such a float is not that coordinate.\n",
          "\n",
          "    Args:\n",
          "        edge: The edge, in pixels.\n",
          "        round_up: True to round toward positive infinity.\n",
          "\n",
          "    Returns:\n",
          "        The index, or `Int.MAX` or `Int.MIN` when `edge` does not fit.\n",
          "    \"\"\"\n",
          "    var limit = Float32(Int.MAX)\n",
          "    if not (edge < limit):\n",
          "        return Int.MAX\n",
          "    if edge <= -limit:\n",
          "        return Int.MIN\n",
          "    if round_up:\n",
          "        return Int(ceil(edge))\n",
          "    return Int(floor(edge))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 213,
        "stop": 215,
        "before": [
          "    visits at most two pixels per axis it need not.\n"
        ],
        "after": [
          "    visits at most two pixels per axis it need not. An edge that does not\n",
          "    fit in an integer lies past the image.\n"
        ]
      },
      {
        "start": 221,
        "stop": 223,
        "before": [
          "        The column or row.\n"
        ],
        "after": [
          "        The column or row, or `Int.MAX` or `Int.MIN` when the edge does\n",
          "        not fit.\n"
        ]
      },
      {
        "start": 224,
        "stop": 225,
        "before": [
          "    return Int(floor(center - size / 2 - 0.5))\n"
        ],
        "after": [
          "    return _covered_index(center - size / 2 - 0.5, False)\n"
        ]
      },
      {
        "start": 232,
        "stop": 234,
        "before": [
          "    more than one pixel late.\n"
        ],
        "after": [
          "    more than one pixel late. An edge that does not fit in an integer\n",
          "    lies past the image.\n"
        ]
      },
      {
        "start": 240,
        "stop": 242,
        "before": [
          "        The column or row.\n"
        ],
        "after": [
          "        The column or row, or `Int.MAX` or `Int.MIN` when the edge does\n",
          "        not fit.\n"
        ]
      },
      {
        "start": 243,
        "stop": 244,
        "before": [
          "    return Int(ceil(center + size / 2 - 0.5))\n"
        ],
        "after": [
          "    return _covered_index(center + size / 2 - 0.5, True)\n"
        ]
      }
    ]
  },
  "render/texture.mojo": {
    "before_sha256": "3552ba623c9c6c8dd2ea0d7b6f4eb0aac924854086a0ddd9b90865e3f1978c15",
    "after_sha256": "608965e963ad8753c64777ed0b3127dc1c6cf950a3c3156e953c4e72bb02b1d5",
    "before_token_sha256": "44e314755a6659caf4e1994252ad35a083c779d9c584675209e31729db8c0781",
    "after_token_sha256": "139877be559cee5e17f6ca9815fcca9bfce451931408261e0fcccc8789dffcc9",
    "edits": [
      {
        "start": 140,
        "stop": 141,
        "before": [],
        "after": [
          "from std.sys import is_gpu\n"
        ]
      },
      {
        "start": 854,
        "stop": 897,
        "before": [],
        "after": [
          "\n",
          "\n",
          "@always_inline\n",
          "def _nearest_texel(unit: Float32, count: Int) -> Int:\n",
          "    \"\"\"Return the texel a nearest sample reads.\n",
          "\n",
          "    A count past 2^24 is not that count in `Float32`, so the product is\n",
          "    made in `Float64` and cut there. A smaller count keeps the `Float32`\n",
          "    product.\n",
          "\n",
          "    Args:\n",
          "        unit: The coordinate, in image fractions.\n",
          "        count: The texels on that side.\n",
          "\n",
          "    Returns:\n",
          "        The texel index, before wrapping.\n",
          "    \"\"\"\n",
          "    # Metal has no `Float64`, and no GPU image is 2^24 texels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 16777216:\n",
          "            return Int(floor(Float64(unit) * Float64(count)))\n",
          "    return Int(floor(unit * Float32(count)))\n",
          "\n",
          "\n",
          "@always_inline\n",
          "def _bilinear_place(unit: Float32, count: Int) -> Float32:\n",
          "    \"\"\"Return `unit * count - 0.5`, where texel centers are integers.\n",
          "\n",
          "    A count past 2^24 is scaled in `Float64` before the half is taken\n",
          "    off. Casting the product first rounds the center onto the neighbor.\n",
          "\n",
          "    Args:\n",
          "        unit: The coordinate, in image fractions.\n",
          "        count: The texels on that side.\n",
          "\n",
          "    Returns:\n",
          "        The place, in texels from a center.\n",
          "    \"\"\"\n",
          "    # Metal has no `Float64`, and no GPU image is 2^24 texels a side.\n",
          "    comptime if not is_gpu():\n",
          "        if count > 16777216:\n",
          "            return Float32(Float64(unit) * Float64(count) - 0.5)\n",
          "    return unit * Float32(count) - 0.5\n"
        ]
      },
      {
        "start": 1763,
        "stop": 1764,
        "before": [],
        "after": [
          "        A side above 16777216 texels is scaled in `Float64`.\n"
        ]
      },
      {
        "start": 1807,
        "stop": 1809,
        "before": [],
        "after": [
          "        var su = sample_coordinate(u, self.wrap_s)\n",
          "        var sv = sample_coordinate(v, self.wrap_t)\n"
        ]
      },
      {
        "start": 1811,
        "stop": 1812,
        "before": [
          "        var from_top = row_coordinate(v, self.flip_y)\n"
        ],
        "after": [
          "        var from_top = row_coordinate(sv, self.flip_y)\n"
        ]
      },
      {
        "start": 1815,
        "stop": 1817,
        "before": [
          "                Int(floor(u * Float32(wide))),\n",
          "                Int(floor(from_top * Float32(tall))),\n"
        ],
        "after": [
          "                _nearest_texel(su, wide),\n",
          "                _nearest_texel(from_top, tall),\n"
        ]
      },
      {
        "start": 1822,
        "stop": 1824,
        "before": [
          "        var across = u * Float32(wide) - 0.5\n",
          "        var down = from_top * Float32(tall) - 0.5\n"
        ],
        "after": [
          "        var across = _bilinear_place(su, wide)\n",
          "        var down = _bilinear_place(from_top, tall)\n"
        ]
      },
      {
        "start": 2077,
        "stop": 2096,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def sample_coordinate(value: Float32, mode: Wrap) -> Float32:\n",
          "    \"\"\"Return the coordinate a sampler reads at: 0 for one that is not\n",
          "    finite, and `gradient_sample_coordinate` of the others.\n",
          "\n",
          "    `Texture._sample_at` and the GPU's `_sample_filtered` both call this,\n",
          "    so the two backends read the same texel.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate.\n",
          "        mode: The texture's checked wrap mode.\n",
          "\n",
          "    Returns:\n",
          "        The coordinate to sample at.\n",
          "    \"\"\"\n",
          "    if not isfinite(value):\n",
          "        return 0\n",
          "    return gradient_sample_coordinate(value, mode)\n"
        ]
      }
    ]
  },
  "render/transmission.mojo": {
    "before_sha256": "15d61d13206956721b27d67bf60d2794b1f631a709c7f4a80f281bb7309c075c",
    "after_sha256": "0c08499fcce1b291f131ca78ea20f9c3c0423cac69759d82d4a0f8f8bdcdebec",
    "before_token_sha256": "f0dfbaab3f5896a8f10e1ba7c9fc954934de29f6e9ea86431543c8dd51e0c4b6",
    "after_token_sha256": "bb482c16a42f3f6975424d1f0e4f48246fce2e32aca24bc24d55cb447d4e1865",
    "edits": [
      {
        "start": 588,
        "stop": 590,
        "before": [
          "    by the fraction. A level past the chain reads the last level.\n"
        ],
        "after": [
          "    by the fraction. A level past the chain, or one that is not finite,\n",
          "    reads the last level. A level below zero reads the first.\n"
        ]
      },
      {
        "start": 600,
        "stop": 609,
        "before": [
          "    var lower = min(Int(floor(lod)), last)\n"
        ],
        "after": [
          "    # `Int` of a level past 2^63 is not that level. It used to become an\n",
          "    # index into the chain and the read fell off the texture.\n",
          "    if not isfinite(lod):\n",
          "        return bicubic(source, uv, last)\n",
          "    var lower = last\n",
          "    if lod <= 0:\n",
          "        lower = 0\n",
          "    elif lod < Float32(last):\n",
          "        lower = Int(floor(lod))\n"
        ]
      }
    ]
  },
  "render/uastc.mojo": {
    "before_sha256": "defc4845174f742420d0e5cfd28a1c337ca62402c079c78829d4c5f64607c6de",
    "after_sha256": "f0e0c128ad12d27a4460789fbf215b7ac53f263f400de3e8e30ebf6283eb0a60",
    "before_token_sha256": "4d0d0f44597d1770f59387e6f8fe1c94e10deee40c3bef8423abdb1a6c66b811",
    "after_token_sha256": "e7257c200d1ce8a8485c1d6c1f194c31d52a0f3e9978f8f0c18c163237129851",
    "edits": [
      {
        "start": 35,
        "stop": 37,
        "before": [],
        "after": [
          "from core.extent import require_positive_extent\n",
          "from render.compressed_texture import check_decoded_size\n"
        ]
      },
      {
        "start": 488,
        "stop": 492,
        "before": [
          "        Error: If `data` is not one block per four by four texels, or a\n",
          "            block is malformed; see `uastc_block`.\n"
        ],
        "after": [
          "        Error: If the size is not positive, the image would decode to\n",
          "            more than `MAX_DECODED_BYTES`, `data` is not one block per\n",
          "            four by four texels, or a block is malformed; see\n",
          "            `uastc_block`.\n"
        ]
      },
      {
        "start": 493,
        "stop": 495,
        "before": [],
        "after": [
          "    require_positive_extent(width, height, \"UASTC: dimensions must be positive\")\n",
          "    check_decoded_size(width, height, False)\n"
        ]
      }
    ]
  },
  "render/uastc_hdr.mojo": {
    "before_sha256": "35404622c83c7b2ac1feabb9745d270d64dff460103e30fb3851dd7edf9eca0a",
    "after_sha256": "7c9e095ddf5a42386ae12d11894cf09826bb87c7f038d64f2b5cd12dbad59216",
    "before_token_sha256": "fff9b5156e57069d918de6ca3829c3dcf508e4c7da9b6d866fa12ccb85b7dd3e",
    "after_token_sha256": "2076c0fd72d2dd275e67e3673ad005381750f32469b8a0da992702ae38578de9",
    "edits": [
      {
        "start": 1314,
        "stop": 1318,
        "before": [
          "        Error: If `data` is not one block per four by four texels, or a\n",
          "            block is malformed; see `uastc_hdr_block`.\n"
        ],
        "after": [
          "        Error: If the size is not positive, the image would decode to\n",
          "            more than `MAX_DECODED_BYTES`, `data` is not one block per\n",
          "            four by four texels, or a block is malformed; see\n",
          "            `uastc_hdr_block`.\n"
        ]
      },
      {
        "start": 1319,
        "stop": 1323,
        "before": [],
        "after": [
          "    require_positive_extent(\n",
          "        width, height, \"UASTC HDR: dimensions must be positive\"\n",
          "    )\n",
          "    check_decoded_size(width, height, True)\n"
        ]
      }
    ]
  },
  "render/volume_texture.mojo": {
    "before_sha256": "e599b4924490cdd8d828749ae4e25cea751f59bfa59198cd3350b5823bda52bf",
    "after_sha256": "4887e63a767ffb7cc8c764be1bc8256c2b4589bc149b4486e8a1c7446ac09557",
    "before_token_sha256": "83ed6ab119ab59fceeb4908da67588e807ab53e43ffb30a07111f014cc76d0e0",
    "after_token_sha256": "9c94bfe94b558d41f4e1cb3e0fbf668c3f6d8ce1aaf23601a3c671d2f52b8bfd",
    "edits": [
      {
        "start": 60,
        "stop": 61,
        "before": [],
        "after": [
          "    gradient_sample_coordinate,\n"
        ]
      },
      {
        "start": 66,
        "stop": 67,
        "before": [
          "from std.math import floor\n"
        ],
        "after": [
          "from std.math import floor, isfinite, isnan\n"
        ]
      },
      {
        "start": 542,
        "stop": 544,
        "before": [
          "        `sampler3D`, by `filter_volume`.\n"
        ],
        "after": [
          "        `sampler3D`, by `filter_volume`. A coordinate past 1048576, or one\n",
          "        that is not finite, is reduced before the index is taken.\n"
        ]
      },
      {
        "start": 614,
        "stop": 633,
        "before": [],
        "after": [
          "def _bounded_axis(value: Float32, mode: Wrap) -> Float32:\n",
          "    \"\"\"Return a coordinate that can become a texel index.\n",
          "\n",
          "    A coordinate that is not finite is read at zero. A finite coordinate\n",
          "    past 1048576 is reduced by its wrap mode. A smaller coordinate is\n",
          "    unchanged, so an ordinary sample stays the same.\n",
          "\n",
          "    Args:\n",
          "        value: The coordinate on one axis.\n",
          "        mode: That axis's wrap mode.\n",
          "\n",
          "    Returns:\n",
          "        The coordinate the sampler indexes.\n",
          "    \"\"\"\n",
          "    if not isfinite(value):\n",
          "        return 0\n",
          "    return gradient_sample_coordinate(value, mode)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 654,
        "stop": 657,
        "before": [
          "    levels. Each index is wrapped by its axis's mode.\n"
        ],
        "after": [
          "    levels. Each index is wrapped by its axis's mode. A coordinate past\n",
          "    1048576, or one that is not finite, is reduced before the index is\n",
          "    taken.\n"
        ]
      },
      {
        "start": 674,
        "stop": 677,
        "before": [],
        "after": [
          "    var ss = _bounded_axis(s, wrap_s)\n",
          "    var tt = _bounded_axis(t, wrap_t)\n",
          "    var rr = _bounded_axis(r, wrap_r)\n"
        ]
      },
      {
        "start": 682,
        "stop": 685,
        "before": [
          "            wrap_index(Int(floor(s * wide)), width, wrap_s),\n",
          "            wrap_index(Int(floor(t * tall)), height, wrap_t),\n",
          "            wrap_index(Int(floor(r * deep)), depth, wrap_r),\n"
        ],
        "after": [
          "            wrap_index(Int(floor(ss * wide)), width, wrap_s),\n",
          "            wrap_index(Int(floor(tt * tall)), height, wrap_t),\n",
          "            wrap_index(Int(floor(rr * deep)), depth, wrap_r),\n"
        ]
      },
      {
        "start": 686,
        "stop": 689,
        "before": [
          "    var across = s * wide - 0.5\n",
          "    var up = t * tall - 0.5\n",
          "    var into = r * deep - 0.5\n"
        ],
        "after": [
          "    var across = ss * wide - 0.5\n",
          "    var up = tt * tall - 0.5\n",
          "    var into = rr * deep - 0.5\n"
        ]
      },
      {
        "start": 885,
        "stop": 887,
        "before": [
          "    inside the stack. `floor(layer + 0.5)`, so a half rounds up.\n"
        ],
        "after": [
          "    inside the stack. `floor(layer + 0.5)`, so a half rounds up. A\n",
          "    coordinate that is not a number reads the first layer.\n"
        ]
      },
      {
        "start": 896,
        "stop": 898,
        "before": [],
        "after": [
          "    if isnan(rounded):\n",
          "        return 0\n"
        ]
      },
      {
        "start": 1014,
        "stop": 1018,
        "before": [
          "        blends the four around it. Two layers are never blended.\n"
        ],
        "after": [
          "        blends the four around it. Two layers are never blended. A\n",
          "        coordinate past 1048576, or one that is not finite, is reduced\n",
          "        before the index is taken. A layer that is not a number reads the\n",
          "        first layer.\n"
        ]
      },
      {
        "start": 1060,
        "stop": 1063,
        "before": [
          "    blends the four around it. Two layers are never blended.\n"
        ],
        "after": [
          "    blends the four around it. Two layers are never blended. A coordinate\n",
          "    past 1048576, or one that is not finite, is reduced before the index\n",
          "    is taken. A layer that is not a number reads the first layer.\n"
        ]
      },
      {
        "start": 1080,
        "stop": 1082,
        "before": [],
        "after": [
          "    var su = _bounded_axis(u, wrap_s)\n",
          "    var sv = _bounded_axis(v, wrap_t)\n"
        ]
      },
      {
        "start": 1086,
        "stop": 1088,
        "before": [
          "            wrap_index(Int(floor(u * wide)), width, wrap_s),\n",
          "            wrap_index(Int(floor(v * tall)), height, wrap_t),\n"
        ],
        "after": [
          "            wrap_index(Int(floor(su * wide)), width, wrap_s),\n",
          "            wrap_index(Int(floor(sv * tall)), height, wrap_t),\n"
        ]
      },
      {
        "start": 1090,
        "stop": 1092,
        "before": [
          "    var across = u * wide - 0.5\n",
          "    var up = v * tall - 0.5\n"
        ],
        "after": [
          "    var across = su * wide - 0.5\n",
          "    var up = sv * tall - 0.5\n"
        ]
      }
    ]
  },
  "renderers/draw_filter.mojo": {
    "before_sha256": "b9a95c5a8d33215ad303ce68d08e72434069c66b84b9eb68247a4ed1e37328f7",
    "after_sha256": "6bd4353c718e9b18e95bae7e135d6879ccaeba6ce056154eb211b12e8a35be69",
    "before_token_sha256": "ca18c11af0bad4f8f3ae724f1eb6f7f584c66368d2a7b299074a666bc4702bab",
    "after_token_sha256": "8ad56b9da95040d26d1ee2b050ddefb9b7753732c92ff5a07d74133d004c8ef2",
    "edits": [
      {
        "start": 117,
        "stop": 118,
        "before": [
          "def _from_center(value: Float32, half: Float32) -> Float32:\n"
        ],
        "after": [
          "def _from_center(value: Float32, half: Float64) -> Float32:\n"
        ]
      },
      {
        "start": 119,
        "stop": 122,
        "before": [],
        "after": [
          "\n",
          "    The half is a `Float64`. A `Float32` half of a side past 2^24 drops\n",
          "    the half pixel at the center.\n"
        ]
      },
      {
        "start": 130,
        "stop": 131,
        "before": [
          "    return floor(value - half + 0.5) + half\n"
        ],
        "after": [
          "    return Float32(floor(Float64(value) - half + 0.5) + half)\n"
        ]
      },
      {
        "start": 143,
        "stop": 145,
        "before": [
          "    var half_w = Float32(width) * 0.5\n",
          "    var half_h = Float32(height) * 0.5\n"
        ],
        "after": [
          "    var half_w = Float64(width) * 0.5\n",
          "    var half_h = Float64(height) * 0.5\n"
        ]
      },
      {
        "start": 160,
        "stop": 162,
        "before": [
          "    var half_w = Float32(width) * 0.5\n",
          "    var half_h = Float32(height) * 0.5\n"
        ],
        "after": [
          "    var half_w = Float64(width) * 0.5\n",
          "    var half_h = Float64(height) * 0.5\n"
        ]
      }
    ]
  },
  "tests/test_anatomy_shared.mojo": {
    "before_sha256": "c48a9061b13acdb292a25a7136121fce82cda3bb018525450399392e40860215",
    "after_sha256": "7df2c7e7963fcac75709e8db87317b58cd96b4e5b9e23da57b0c5283838ecb96",
    "before_token_sha256": "83f1442aea9f22e4e51164f92e1de19fad6ee7b06e32c4a21371af9310f0bb22",
    "after_token_sha256": "8dd95c03c15aa3c1bb5ea987ed5f51a8bf2050f2dc41ceb648877f4318acd582",
    "edits": [
      {
        "start": 24,
        "stop": 25,
        "before": [],
        "after": [
          "    muscle_tissue,\n"
        ]
      },
      {
        "start": 26,
        "stop": 27,
        "before": [],
        "after": [
          "from extensions.humanoid.skeleton.soft_tissue import sample_soft_mass\n"
        ]
      },
      {
        "start": 35,
        "stop": 36,
        "before": [
          "from std.testing import TestSuite, assert_equal, assert_raises\n"
        ],
        "after": [
          "from std.testing import TestSuite, assert_equal, assert_raises, assert_true\n"
        ]
      },
      {
        "start": 229,
        "stop": 277,
        "before": [],
        "after": [
          "    var flesh = muscle_tissue()\n",
          "    for invalid in [inf[DType.float32](), nan[DType.float32]()]:\n",
          "        with assert_raises(contains=\"finite and ordered\"):\n",
          "            _ = sample_soft_mass(\n",
          "                field,\n",
          "                Vector3(invalid, 0, 0),\n",
          "                Vector3(1, 1, 1),\n",
          "                flesh,\n",
          "                Length(20, MILLIMETER),\n",
          "                \"test\",\n",
          "            )\n",
          "        with assert_raises(contains=\"finite and ordered\"):\n",
          "            _ = sample_soft_mass(\n",
          "                field,\n",
          "                Vector3(0, 0, 0),\n",
          "                Vector3(1, invalid, 1),\n",
          "                flesh,\n",
          "                Length(20, MILLIMETER),\n",
          "                \"test\",\n",
          "            )\n",
          "    with assert_raises(contains=\"finite and ordered\"):\n",
          "        _ = sample_soft_mass(\n",
          "            field,\n",
          "            Vector3(0, 0, 1),\n",
          "            Vector3(1, 1, 0),\n",
          "            flesh,\n",
          "            Length(20, MILLIMETER),\n",
          "            \"test\",\n",
          "        )\n",
          "    for low_x in [Float32(0), Float32(-3e38)]:\n",
          "        with assert_raises(contains=\"span is too large\"):\n",
          "            _ = sample_soft_mass(\n",
          "                field,\n",
          "                Vector3(low_x, 0, 0),\n",
          "                Vector3(Float32(3e38), 1, 1),\n",
          "                flesh,\n",
          "                Length(20, MILLIMETER),\n",
          "                \"test\",\n",
          "            )\n",
          "    var one = sample_soft_mass(\n",
          "        field,\n",
          "        Vector3(0, 0, 0),\n",
          "        Vector3(0.02, 0.02, 0.02),\n",
          "        flesh,\n",
          "        Length(20, MILLIMETER),\n",
          "        \"test\",\n",
          "    )\n",
          "    assert_true(one.mass.value >= 0)\n"
        ]
      }
    ]
  },
  "tests/test_animation_loader.mojo": {
    "before_sha256": "072c6d8019ebb299f875115725d84f3a33076d3a237c9780303707c8d83049e7",
    "after_sha256": "71c72d8cacc3a64b182eb26a2c7be8b5257fc0db53a081f70c2612f5a9c8943a",
    "before_token_sha256": "7353816c77bc96475aa7d929ca5ff5c58548795f31d11ec736d388a935f7ff40",
    "after_token_sha256": "fbfdd165314e52c1229f5293a8e4a0f8f7b7c6d8e7deb306c24d3d62cbe51d75",
    "edits": [
      {
        "start": 279,
        "stop": 283,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = animation_path(clip, NodeId(1), 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = animation_path(clip, NodeId(1), Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_arcball_controls.mojo": {
    "before_sha256": "e825c8ac875a53ccff03a7e4b663f4792c281ca733ba78f158d394d9f1f6a0c8",
    "after_sha256": "d06d19678c72f145094228a5d97ddea7e9cc91f77390ddece3a2256338e0a369",
    "before_token_sha256": "1d3ebba4c1dbe5d2b749fd1f6dd7c881b8eb9ee90739f0e585d32a610fbff499",
    "after_token_sha256": "6bb038e09ece5e7d78e6e485cdd9c3a4d618684bcec1cc5411bb03978cb53bef",
    "edits": [
      {
        "start": 17,
        "stop": 18,
        "before": [],
        "after": [
          "    _apart,\n"
        ]
      },
      {
        "start": 1744,
        "stop": 1796,
        "before": [],
        "after": [
          "def test_a_wide_view_keeps_the_pixel_center_inside() raises:\n",
          "    var camera = _perspective()\n",
          "    var controls = ArcballControls(camera)\n",
          "    controls._width = 100\n",
          "    controls._height = 100\n",
          "    var small = controls._ndc(50.5, 50.5)\n",
          "    assert_equal(small.x, Float32(50.5) / Float32(100) * 2 - 1)\n",
          "    assert_equal(small.y, (Float32(100) - Float32(50.5)) / Float32(100) * 2 - 1)\n",
          "    var wide = 16777217\n",
          "    controls._width = wide\n",
          "    controls._height = wide\n",
          "    var center = Float64(wide - 1) + 0.5\n",
          "    var ndc = controls._ndc(center, 0.5)\n",
          "    assert_equal(ndc.x, Float32(center / Float64(wide) * 2 - 1))\n",
          "    assert_true(ndc.x < 1)\n",
          "    # Each bound of the small quotient, with the others inside it.\n",
          "    controls._width = wide\n",
          "    controls._height = 100\n",
          "    var across = controls._ndc(50.5, 0.5)\n",
          "    assert_equal(across.x, Float32(50.5 / Float64(wide) * 2 - 1))\n",
          "    controls._width = 100\n",
          "    controls._height = wide\n",
          "    var down = controls._ndc(0.5, 50.5)\n",
          "    assert_equal(\n",
          "        down.y, Float32((Float64(wide) - 50.5) / Float64(wide) * 2 - 1)\n",
          "    )\n",
          "    controls._height = 100\n",
          "    var big_x = controls._ndc(8388608.5, 0.5)\n",
          "    assert_equal(big_x.x, Float32(8388608.5 / Float64(100) * 2 - 1))\n",
          "    var big_y = controls._ndc(0.5, 8388608.5)\n",
          "    assert_equal(\n",
          "        big_y.y, Float32((Float64(100) - 8388608.5) / Float64(100) * 2 - 1)\n",
          "    )\n",
          "    var low_x = controls._ndc(-8388608, 0.5)\n",
          "    assert_equal(low_x.x, Float32(-8388608 / Float64(100) * 2 - 1))\n",
          "    var low_y = controls._ndc(0.5, -8388608)\n",
          "    assert_equal(\n",
          "        low_y.y, Float32((Float64(100) - -8388608) / Float64(100) * 2 - 1)\n",
          "    )\n",
          "    # Two adjacent pixels past 2^24 are one pixel apart, not the same point.\n",
          "    assert_equal(_apart(16777216.5, 0.5, 16777217.5, 0.5), 1)\n",
          "    assert_equal(_apart(10.5, 20.5, 14.5, 23.5), 5)\n",
          "    assert_equal(_apart(-8388608, 0.5, -8388607, 0.5), 1)\n",
          "    assert_equal(_apart(8388608.5, 0.5, 8388609.5, 0.5), 1)\n",
          "    assert_equal(_apart(0.5, -8388608, 0.5, -8388607), 1)\n",
          "    assert_equal(_apart(0.5, 8388608.5, 0.5, 8388609.5), 1)\n",
          "    assert_equal(_apart(0.5, 0.5, -8388608, 0.5), Float32(8388608.5))\n",
          "    assert_equal(_apart(0.5, 0.5, 8388608.5, 0.5), Float32(8388608))\n",
          "    assert_equal(_apart(0.5, 0.5, 0.5, -8388608), Float32(8388608.5))\n",
          "    assert_equal(_apart(0.5, 0.5, 0.5, 8388608.5), Float32(8388608))\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_carla_agents.mojo": {
    "before_sha256": "5edecca8aaa0449f3691177ec9e8bdb497dcdfd4db7de03d19fbc6656db8b471",
    "after_sha256": "75d5572cea8270b290d4477a3c3759e6ee5181c09c78240558438bd6d74e54cf",
    "before_token_sha256": "d681aeffee62ac736b7d19312862bb2f954d386af67a74d3f2082a656ee690e3",
    "after_token_sha256": "e5f945e7844bbf199ae97a9f7f758af671cbcec3ced3874b5e4440a5d7953cdf",
    "edits": [
      {
        "start": 80,
        "stop": 81,
        "before": [
          "from std.math import floor, isnan\n"
        ],
        "after": [
          "from std.math import floor, inf, isnan\n"
        ]
      },
      {
        "start": 895,
        "stop": 909,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = GlobalRoutePlanner(\n",
          "            load_opendrive(\"<OpenDRIVE/>\"),\n",
          "            Length(inf[DType.float32](), METER),\n",
          "        )\n",
          "    with assert_raises(contains=\"move the waypoint\"):\n",
          "        _ = GlobalRoutePlanner(\n",
          "            load_opendrive(\"<OpenDRIVE/>\"),\n",
          "            Length(Float32(1e-20), METER),\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = GlobalRoutePlanner(\n",
          "            load_opendrive(TWO_LANE), Length(Float32(1e-6), METER)\n",
          "        )\n"
        ]
      }
    ]
  },
  "tests/test_carla_agents_drive.mojo": {
    "before_sha256": "4bad764c7dd7261b39b553e62c1870fc26927dc430d937a44ca69bbc7c684c35",
    "after_sha256": "9c2ce87eab18e817b3fde55f8b111a5907126ae7a809586e33825578e3b54a94",
    "before_token_sha256": "f2a8e81cb5d536c8930d3c681acf8628f900aea32fb4a26645d506baa03cbeaf",
    "after_token_sha256": "da799627a2fe58361bc8c1fa0e4d4407d5f58b72bb155b9169ef4acd47f2897a",
    "edits": [
      {
        "start": 55,
        "stop": 56,
        "before": [
          "from std.math import floor\n"
        ],
        "after": [
          "from std.math import floor, nan\n"
        ]
      },
      {
        "start": 513,
        "stop": 585,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_lane_plan_refuses_a_walk_that_does_not_finish() raises:\n",
          "    var world = _world(_two_lane())\n",
          "    var car = _car(world, 5.3, 1.75)\n",
          "    var agent = BasicAgent(world, car)\n",
          "    var w = Waypoint._from_si(RoadId(1), SectionId(0), LaneId(-1), 5.3)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = agent.generate_lane_change_path(\n",
          "            world.map, w, OPTION_CHANGE_LANE_RIGHT, Length(1e20, METER)\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = agent.generate_lane_change_path(\n",
          "            world.map,\n",
          "            w,\n",
          "            OPTION_CHANGE_LANE_RIGHT,\n",
          "            Length(10, METER),\n",
          "            Length(1e20, METER),\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = agent.generate_lane_change_path(\n",
          "            world.map,\n",
          "            w,\n",
          "            OPTION_CHANGE_LANE_RIGHT,\n",
          "            Length(10, METER),\n",
          "            Length(25, METER),\n",
          "            Length(25, METER),\n",
          "            True,\n",
          "            16777217,\n",
          "        )\n",
          "    with assert_raises(contains=\"positive distance\"):\n",
          "        _ = agent.generate_lane_change_path(\n",
          "            world.map,\n",
          "            w,\n",
          "            OPTION_CHANGE_LANE_RIGHT,\n",
          "            Length(10, METER),\n",
          "            Length(25, METER),\n",
          "            Length(25, METER),\n",
          "            True,\n",
          "            1,\n",
          "            Length(0, METER),\n",
          "        )\n",
          "    with assert_raises(contains=\"positive distance\"):\n",
          "        _ = agent.generate_lane_change_path(\n",
          "            world.map,\n",
          "            w,\n",
          "            OPTION_CHANGE_LANE_RIGHT,\n",
          "            Length(10, METER),\n",
          "            Length(25, METER),\n",
          "            Length(25, METER),\n",
          "            True,\n",
          "            1,\n",
          "            Length(nan[DType.float32](), METER),\n",
          "        )\n",
          "    # At this station a two-meter step does not move, so the walk stops.\n",
          "    ref road = world.map.road(RoadId(1))\n",
          "    var saved = road.length\n",
          "    road.length = 1e17\n",
          "    var far = Waypoint._from_si(RoadId(1), SectionId(0), LaneId(-1), 1e17 - 10)\n",
          "    var stuck = agent.generate_lane_change_path(\n",
          "        world.map,\n",
          "        far,\n",
          "        OPTION_CHANGE_LANE_RIGHT,\n",
          "        Length(10, METER),\n",
          "        Length(10, METER),\n",
          "        Length(10, METER),\n",
          "        False,\n",
          "        1,\n",
          "        Length(2, METER),\n",
          "    )\n",
          "    road.length = saved\n",
          "    assert_equal(len(stuck), 0)\n"
        ]
      }
    ]
  },
  "tests/test_carla_geom.mojo": {
    "before_sha256": "eee5e0dd931e2fdd4ec4ee9fddb56ea816be879188b8efca9a050fc0be16a69e",
    "after_sha256": "86e914bd35ecec53772c20d4f8b5baa4a6581a887dcc0bec64faf77b5e4b9f1c",
    "before_token_sha256": "e213bd21c94671e4a2bd83749e72f3c0426cec7b696508c3e7e2f30ecee462f1",
    "after_token_sha256": "2f4d4817453d9dbc7fad81f4f5644b67ffe7b9fa1956060b54667a7b3cec7a26",
    "edits": [
      {
        "start": 325,
        "stop": 330,
        "before": [],
        "after": [
          "    # 16777217 numbers do not finish, and the ends can overflow a subtraction.\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = generate_range(0, 16777216)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = generate_range(Int.MIN, 0)\n"
        ]
      }
    ]
  },
  "tests/test_carla_junction_bounds.mojo": {
    "before_sha256": "bc5871a9d0da711feaca07c4df5da42f13585254d1464296300915dd7e23edbd",
    "after_sha256": "c9cfe07f837b27697fddf042968068c8bad988490ada85f9a5113a4a3a4a7c91",
    "before_token_sha256": "c2ca46f3dbc2e7a8cf2e265126a17f98ae05e2734b3b619d8e47cec26eeb4926",
    "after_token_sha256": "d3e96e8606705116bfd0d3fc79fb26404b8981c6c5993f98ab37328350f32f85",
    "edits": [
      {
        "start": 15,
        "stop": 16,
        "before": [],
        "after": [
          "from extensions.carla.road import LaneKey\n"
        ]
      },
      {
        "start": 279,
        "stop": 373,
        "before": [],
        "after": [
          "def _crossing() raises -> Map:\n",
          "    var b = MapBuilder()\n",
          "    for id in [1, 2]:\n",
          "        var r = _road(b, id, 90, 1)\n",
          "        b.add_road_geometry_arc_si(\n",
          "            r, 0, 0, -20.0 * Float64(id - 1), 0, 90, PI / 90.0\n",
          "        )\n",
          "        if id == 2:\n",
          "            b.roads[r].sections[0].lanes[0].successor = LaneId(1)\n",
          "            for n in [1, 2]:\n",
          "                var sec = b.add_road_section_si(\n",
          "                    r, SectionId(n), Float64(n) * 30.0\n",
          "                )\n",
          "                _ = b.add_road_section_lane(\n",
          "                    r,\n",
          "                    sec,\n",
          "                    LaneId(1),\n",
          "                    LANE_DRIVING,\n",
          "                    False,\n",
          "                    LaneId(1),\n",
          "                    LaneId(1),\n",
          "                )\n",
          "                b.create_lane_width_si(\n",
          "                    b.lane_si(RoadId(2), LaneId(1), Float64(n) * 30.0),\n",
          "                    Float64(n) * 30.0,\n",
          "                    3.5,\n",
          "                    0,\n",
          "                    0,\n",
          "                    0,\n",
          "                )\n",
          "    _connect(b, [1, 2])\n",
          "    return b.build()\n",
          "\n",
          "\n",
          "def test_a_sign_check_refuses_a_lane_it_would_walk_twice() raises:\n",
          "    var wide_map = _crossing()\n",
          "    # A length past one lap is refused before the walk starts.\n",
          "    wide_map.road(RoadId(2)).length = 1e20\n",
          "    var wide = List[TriggerBox]()\n",
          "    with assert_raises(contains=\"more than once\"):\n",
          "        _check_boxes(wide_map, RoadId(1), List[Int](), wide)\n",
          "    var map = _crossing()\n",
          "    ref conflict = map.road(RoadId(2))\n",
          "    # Lane 1 runs against s, so the ring joins its last section to its first.\n",
          "    var last = len(conflict.sections) - 1\n",
          "    conflict.sections[0].lanes[0].next_lanes.clear()\n",
          "    conflict.sections[0].lanes[0].next_lanes.append(\n",
          "        LaneKey(\n",
          "            RoadId(2),\n",
          "            conflict.sections[last].id,\n",
          "            conflict.sections[last].lanes[0].id,\n",
          "        )\n",
          "    )\n",
          "    var loop = List[TriggerBox]()\n",
          "    with assert_raises(contains=\"more than once\"):\n",
          "        _check_boxes(map, RoadId(1), List[Int](), loop)\n",
          "    # One billion meters a second does not change the anticipation time.\n",
          "    var fast = MapBuilder()\n",
          "    for id in [1, 2]:\n",
          "        var r = _road(fast, id, 90, 1)\n",
          "        fast.add_road_geometry_arc_si(\n",
          "            r, 0, 0, -20.0 * Float64(id - 1), 0, 90, PI / 90.0\n",
          "        )\n",
          "        if id == 2:\n",
          "            fast.create_road_speed_opendrive(r, 0.0, \"Town\", 1e9, \"m/s\")\n",
          "            var sec = fast.add_road_section_si(r, SectionId(1), 45.0)\n",
          "            _ = fast.add_road_section_lane(\n",
          "                r, sec, LaneId(1), LANE_DRIVING, False, LaneId(1), LaneId(1)\n",
          "            )\n",
          "            fast.create_lane_width_si(\n",
          "                fast.lane_si(RoadId(2), LaneId(1), 45.0), 45.0, 3.5, 0, 0, 0\n",
          "            )\n",
          "    _connect(fast, [1, 2])\n",
          "    var fast_map = fast.build()\n",
          "    ref fast_road = fast_map.road(RoadId(2))\n",
          "    var fast_last = len(fast_road.sections) - 1\n",
          "    fast_road.sections[0].lanes[0].prev_lanes.clear()\n",
          "    fast_road.sections[fast_last].lanes[0].prev_lanes.append(\n",
          "        LaneKey(\n",
          "            RoadId(2),\n",
          "            fast_road.sections[0].id,\n",
          "            fast_road.sections[0].lanes[0].id,\n",
          "        )\n",
          "    )\n",
          "    var ahead = List[TriggerBox]()\n",
          "    with assert_raises(contains=\"against its lane\"):\n",
          "        _check_boxes(fast_map, RoadId(1), List[Int](), ahead)\n",
          "    # The same predecessor at 40 m/s still shortens the anticipation time.\n",
          "    fast_road.info.speeds[0].speed = 40.0\n",
          "    var ordinary = List[TriggerBox]()\n",
          "    _check_boxes(fast_map, RoadId(1), List[Int](), ordinary)\n",
          "    assert_true(len(ordinary) > 0)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_carla_lane_geometry_guard_controls.mojo": {
    "before_sha256": "1da2268eb3066b588f33acf78dad727fb6cdd2fbbc263100853e9f0dfcb21a14",
    "after_sha256": "adbf67973734dde82434efc273766537a7acc2705f4a7e3c748f4896fc9acac4",
    "before_token_sha256": "6592fb12bd2978e7f94deb46f3b281cd85b793e579e626f668cb98e59127df6e",
    "after_token_sha256": "619537e9479addfa29e7fe9b4af1e0e93e6fab0aa5116f605bc5b82baa393cff",
    "edits": [
      {
        "start": 7,
        "stop": 13,
        "before": [
          "from extensions.carla.geometry import ARC, LINE, RoadGeometry\n"
        ],
        "after": [
          "from extensions.carla.geometry import (\n",
          "    ARC,\n",
          "    LINE,\n",
          "    RoadGeometry,\n",
          "    with_spiral_si,\n",
          ")\n"
        ]
      },
      {
        "start": 69,
        "stop": 85,
        "before": [],
        "after": [
          "def test_canonical_spiral_derivative_refuses_a_finite_piece_count() raises:\n",
          "    # 1e18 fits in an integer. The quadrature would not finish.\n",
          "    var geometry = with_spiral_si(\n",
          "        RoadGeometry.from_meters(LINE, 0.0, 0.0, 0.0, 0.0, 2.0), 1e18, 1e18\n",
          "    )\n",
          "    with assert_raises(contains=\"spiral work limit\"):\n",
          "        _ = _lane_geometry_derivative_at(geometry, 2.0)\n",
          "    var smooth = with_spiral_si(\n",
          "        RoadGeometry.from_meters(LINE, 0.0, 0.0, 0.0, 0.0, 2.0), 0.1, 0.1\n",
          "    )\n",
          "    var derivative = _lane_geometry_derivative_at(smooth, 0.0)\n",
          "    assert_almost_equal(derivative[0], 1.0, atol=1e-12, rtol=0)\n",
          "    assert_almost_equal(derivative[1], 0.0, atol=1e-12, rtol=0)\n",
          "    assert_almost_equal(derivative[2], 0.1, atol=1e-12, rtol=0)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_carla_map_quantity.mojo": {
    "before_sha256": "057089749004558f06c493f1e7e86d05a0408bd1e2b92db11c7a74f362674032",
    "after_sha256": "eb9e859317365ce0df30ccf9f9bcf7a1681ae32e0bb2f389374a87295f5b93c4",
    "before_token_sha256": "e39a1b08d4a7fbec5e8e142c4e6353c8ca6ff659605519cddcc9c03ef93fccda",
    "after_token_sha256": "211a7f9c33fb92ea229370aa676425952c7392646316d2af067d59ea640f50d6",
    "edits": [
      {
        "start": 5825,
        "stop": 5826,
        "before": [
          "    # The smallest spacing fails immediately when adding it cannot advance.\n"
        ],
        "after": [
          "    # The smallest spacing is more stations than this port walks.\n"
        ]
      },
      {
        "start": 5827,
        "stop": 5828,
        "before": [
          "    with assert_raises(contains=\"advance\"):\n"
        ],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n"
        ]
      }
    ]
  },
  "tests/test_carla_reference_derivative_controls.mojo": {
    "before_sha256": "744f0aa0ccb91f1428a462b7a55f5bd42caa85ecfe9f6d1a05fd7b1072d5d497",
    "after_sha256": "dd5c9291251a46746583cab9c43909119dcafc27876b101f95072e5b85326848",
    "before_token_sha256": "590c89d7a4a1521480e1325ecd49b40eba13bcedf5c56496f0f3c4c8d09f1eb3",
    "after_token_sha256": "beb335c4f2d1fca0bb5eb44ec6fa4e001eccf0145593b2ea566424594e043de5",
    "edits": [
      {
        "start": 128,
        "stop": 132,
        "before": [],
        "after": [
          "    # 1e18 fits in an integer. The quadrature would not finish.\n",
          "    var finite = with_spiral(_line(), 1e18, 1e18)\n",
          "    with assert_raises(contains=\"spiral work limit\"):\n",
          "        _ = finite._derivative_at(2.0)\n"
        ]
      }
    ]
  },
  "tests/test_carla_render_scene.mojo": {
    "before_sha256": "34b3d068c59bc17f4bb7267d9f0b98fd5cf7cb0af6e04c263eeae71433d74a92",
    "after_sha256": "9e0d89c4c45dc6612c0d91773f2e148940caebb064603f9b4f772dbd735d33d1",
    "before_token_sha256": "ac6fa6d1a6c90ddb46b28af70df96c969f9ce40835969bd4a34a6221fa5ccd19",
    "after_token_sha256": "b1f90a640dd69f4a3952ce867d0ba938c5751e4942c14aca5eef871b494697b4",
    "edits": [
      {
        "start": 189,
        "stop": 190,
        "before": [
          "from std.math import atan, log2, pi, pow, sqrt\n"
        ],
        "after": [
          "from std.math import atan, inf, log2, pi, pow, sqrt\n"
        ]
      },
      {
        "start": 333,
        "stop": 350,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"finite\"):\n",
          "        _ = lamp_posts(map, Length(inf[DType.float32](), METER))\n",
          "    for i in range(len(map.roads)):\n",
          "        map.roads[i].length = 1e20\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = lamp_posts(map, Length(1, METER))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = building_lots(map, _small())\n",
          "    var long: List[Vector3] = [\n",
          "        Vector3(0, 0, 0),\n",
          "        Vector3(2e7, 0, 0),\n",
          "        Vector3(2e7, 3, 0),\n",
          "        Vector3(0, 3, 0),\n",
          "        Vector3(0, 0, 0),\n",
          "    ]\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = crosswalk_stripes(long)\n"
        ]
      },
      {
        "start": 364,
        "stop": 366,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = skyline_lots(bounds, 16777217, 3)\n"
        ]
      }
    ]
  },
  "tests/test_carla_sensors.mojo": {
    "before_sha256": "4ef9bda07b4d524dea636828529dd6ae5feebbbe7373c6158e00f6be906a145b",
    "after_sha256": "bb829a327acdc1c72c00eb3d8087d909b5229638f5b5987abb115139615830e2",
    "before_token_sha256": "cb85d0a8e7533bafc32225e86902e5983d8b44958b4a732b413ca36fdca6b111",
    "after_token_sha256": "ac41288ed2b6cd5c530894f758b43ad47a0c2b962f4a08f6550cb593e8ac6ddb",
    "edits": [
      {
        "start": 92,
        "stop": 93,
        "before": [],
        "after": [
          "    _postprocess,\n"
        ]
      },
      {
        "start": 98,
        "stop": 99,
        "before": [],
        "after": [
          "    require_lidar_rays,\n"
        ]
      },
      {
        "start": 489,
        "stop": 503,
        "before": [],
        "after": [
          "def test_a_lidar_channel_count_this_port_cannot_cast_is_refused() raises:\n",
          "    var d = LidarDescription()\n",
          "    d.channels = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        d.validate()\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = d.laser_angles()\n",
          "    d.channels = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = d.laser_angles()\n",
          "    d.channels = 1\n",
          "    assert_equal(len(d.laser_angles()), 1)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 555,
        "stop": 578,
        "before": [],
        "after": [
          "def test_a_lidar_counts_its_points_in_float_as_carla_does() raises:\n",
          "    var d = LidarDescription()\n",
          "    d.channels = 32\n",
          "    assert_equal(d.points_per_laser(_s(0.05)), 88)\n",
          "    # CARLA's float product: 5 points a second for 0.7 seconds is 4, and\n",
          "    # one past 2^24 rounds to 2^24.\n",
          "    d.channels = 1\n",
          "    d.points_per_second = 5\n",
          "    assert_equal(d.points_per_laser(_s(0.7)), 4)\n",
          "    d.points_per_second = 16777217\n",
          "    assert_equal(d.points_per_laser(_s(1)), 16777216)\n",
          "    d.points_per_second = 56000\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = d.points_per_laser(_s(Float32(1e20)))\n",
          "    d.channels = 0\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = d.points_per_laser(_s(0.05))\n",
          "    d.channels = 1\n",
          "    d.points_per_second = -6000000000000000000\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = d.points_per_laser(_s(2))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 595,
        "stop": 623,
        "before": [],
        "after": [
          "    var wide = _lidar()\n",
          "    wide.channels = 1\n",
          "    wide.horizontal_fov = Angle(Float32(1e20), DEGREE)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = hss_points_per_laser(wide, _deg(0.01))\n",
          "    # The widest finite field over the finest step overflows to infinity.\n",
          "    wide.horizontal_fov = Angle(Float32(3e38), DEGREE)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = hss_points_per_laser(wide, _deg(0.01))\n",
          "    # A laser of no ray fits whatever the channel count, and a laser whose\n",
          "    # rays all miss keeps no detection.\n",
          "    require_lidar_rays(16777216, 0)\n",
          "    var none = _lidar()\n",
          "    none.channels = 1\n",
          "    var quiet = _postprocess(\n",
          "        _pose(0, 0, 2),\n",
          "        none,\n",
          "        [List[SensorHit]()],\n",
          "        0,\n",
          "        0,\n",
          "        _deg(0),\n",
          "        rng,\n",
          "    )\n",
          "    assert_equal(len(quiet.detections), 0)\n",
          "    wide.channels = 16777216\n",
          "    wide.horizontal_fov = Angle(Float32(1e10), DEGREE)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = scan_hss_lidar(scene, _pose(0, 0, 2), wide, _deg(0.01), rng)\n"
        ]
      },
      {
        "start": 732,
        "stop": 747,
        "before": [],
        "after": [
          "    # CARLA's float product: 10 points a second for 0.7 seconds is 7, and\n",
          "    # one past 2^24 rounds to 2^24.\n",
          "    d.points_per_second = 10\n",
          "    assert_equal(d.points_in(_s(0.7)), 7)\n",
          "    d.points_per_second = 16777217\n",
          "    assert_equal(d.points_in(_s(1)), 16777216)\n",
          "    d.points_per_second = 1500\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = d.points_in(_s(Float32(1e20)))\n",
          "    d.points_per_second = -6000000000000000000\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = d.points_in(_s(2))\n",
          "    d.points_per_second = 1500\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = d.points_in(_s(nan[DType.float32]()))\n"
        ]
      },
      {
        "start": 1233,
        "stop": 1253,
        "before": [],
        "after": [
          "def test_event_camera_refuses_a_step_that_does_not_move() raises:\n",
          "    # A threshold changed to zero is refused before the frame is stored.\n",
          "    var dvs = DVSCamera(_linear(30), 1, 1, 0)\n",
          "    _ = dvs.simulate(_frame([100]), Duration64(1.0))\n",
          "    dvs.config.positive_threshold = 0\n",
          "    with assert_raises(contains=\"must be positive\"):\n",
          "        _ = dvs.simulate(_frame([200]), Duration64(1.1))\n",
          "    assert_equal(dvs.current_time, 1000000000)\n",
          "    # A dark pixel that becomes bright never leaves the crossing walk.\n",
          "    var dark = DVSCamera(_linear(Float32(1e-20)), 1, 1, 0)\n",
          "    _ = dark.simulate(_frame([0]), Duration64(0.0))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = dark.simulate(_frame([255]), Duration64(0.1))\n",
          "    # The previous level itself does not move.\n",
          "    var mid = DVSCamera(_linear(Float32(1e-20)), 1, 1, 0)\n",
          "    _ = mid.simulate(_frame([100]), Duration64(0.0))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = mid.simulate(_frame([110]), Duration64(0.1))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 1670,
        "stop": 1672,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = optical_flow_data(1 << 31, 1 << 32, 90, List[Float32]())\n"
        ]
      }
    ]
  },
  "tests/test_carla_tight_rounding.mojo": {
    "before_sha256": "4600eda1b2c47e5be0ae151e94725727c81ba829476f26bf97b113e52aa2a85e",
    "after_sha256": "21c3777f3a7a698fd160396523d32c7ea4c3735641493417b58df5b21d6ad032",
    "before_token_sha256": "fb03ea0450449538cfd9cc67bd87e906832bb32c1d17797c67e12be7a0930031",
    "after_token_sha256": "fb03ea0450449538cfd9cc67bd87e906832bb32c1d17797c67e12be7a0930031",
    "edits": [
      {
        "start": 66,
        "stop": 67,
        "before": [
          "    # Exact words derived by test_sample_blend_migration.py. The coupled\n"
        ],
        "after": [
          "    # Exact words derived by tests/test_carla_blend_reference_tool.mojo. The coupled\n"
        ]
      }
    ]
  },
  "tests/test_carla_world_signals.mojo": {
    "before_sha256": "6e14b3c1c191b110446e5ecef2259168f13a3392fafb89ae8145c455ee0cd20c",
    "after_sha256": "45544fffd77290bac12d79ef84734fa6563a4f3005a6169ff549b40379cd2e73",
    "before_token_sha256": "38918ce0102801aa73586ea7074a4810e639a258f2e9d42ad9c29ff355cf177c",
    "after_token_sha256": "990b284e148e59d2f916910760257609196adfab4fd9b7d7ebd094e0730c57d0",
    "edits": [
      {
        "start": 1181,
        "stop": 1200,
        "before": [],
        "after": [
          "def test_stop_waypoints_refuse_an_extent_that_does_not_finish() raises:\n",
          "    var empty = load_opendrive(\"<OpenDRIVE></OpenDRIVE>\")\n",
          "    var pose = _pose(0, 0, 0, 0)\n",
          "    # 1e7 m still steps, and the step count does not finish.\n",
          "    var wide = BoundingBox(Vector3(0, 0, 0), Vector3(1e7, 1, 1))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = stop_waypoints(empty, pose, wide)\n",
          "    # 2e7 m does not move when the walk adds one meter.\n",
          "    var stuck = BoundingBox(Vector3(0, 0, 0), Vector3(2e7, 1, 1))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = stop_waypoints(empty, pose, stuck)\n",
          "    var bad = BoundingBox(Vector3(0, 0, 0), Vector3(1, 1, 1))\n",
          "    bad.extent.x = inf[DType.float32]()\n",
          "    with assert_raises(contains=\"must be finite\"):\n",
          "        _ = stop_waypoints(empty, pose, bad)\n",
          "    var zero = BoundingBox(Vector3(0, 0, 0), Vector3(0, 1, 1))\n",
          "    assert_equal(len(stop_waypoints(empty, pose, zero)), 0)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_ccd_ik_solver.mojo": {
    "before_sha256": "87599e0cddda29e6714039c1c3ffe2142f1001fadcc8eec2f48a3c453e263a6c",
    "after_sha256": "5d4587a839c0a67cf7cdef2ddd59c84213f7dcef56882b8b5d3b615954fc04c4",
    "before_token_sha256": "287c3a530f57c8b45a1af74ef8e6ddb3b379e0775638db388689bbc5e9fbf00f",
    "after_token_sha256": "3992a6d02fa4049e4dc570c99f646f7106a83f3cd91bb7cbe7c25c67b12a8a60",
    "edits": [
      {
        "start": 248,
        "stop": 266,
        "before": [],
        "after": [
          "    var too_many = reach(two_links())\n",
          "    too_many.iteration = 16777217\n",
          "    chains = List[IkChain]()\n",
          "    chains.append(too_many^)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CCDIKSolver(scene, 0, chains^)\n",
          "    var maximum = reach(two_links())\n",
          "    maximum.iteration = Int.MAX\n",
          "    chains = List[IkChain]()\n",
          "    chains.append(maximum^)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CCDIKSolver(scene, 0, chains^)\n",
          "    var at_cap = IkChain(3, 2, List[IkLink]())\n",
          "    at_cap.iteration = 16777216\n",
          "    chains = List[IkChain]()\n",
          "    chains.append(at_cap^)\n",
          "    var capped = CCDIKSolver(scene, 0, chains^)\n",
          "    capped.update(scene)\n"
        ]
      }
    ]
  },
  "tests/test_city_generator.mojo": {
    "before_sha256": "355aa421052dcbeae141e3ca69039e9a273c1de7e654250fe83e4f5bb2af08e0",
    "after_sha256": "2f01712fc6ebbf9504fe9400e19df64560309c50524e3b937b02d52c49c48aad",
    "before_token_sha256": "e2cd9861e5a287b61e05bf6eced7164bdd571b3abd665af581a0be51c6e08e34",
    "after_token_sha256": "63cf904bb648a88118cd182655a90f8d8825a2de4f54f39930024eafaa4a1be2",
    "edits": [
      {
        "start": 29,
        "stop": 30,
        "before": [],
        "after": [
          "from std.math import inf, nan\n"
        ]
      },
      {
        "start": 408,
        "stop": 471,
        "before": [],
        "after": [
          "    for bad in [\n",
          "        nan[DType.float32](),\n",
          "        inf[DType.float32](),\n",
          "        -inf[DType.float32](),\n",
          "    ]:\n",
          "        p = CityParameters()\n",
          "        p.lot = Length(bad, METER)\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = city_layout(p)\n",
          "        p = CityParameters()\n",
          "        p.street = Length(bad, METER)\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = city_layout(p)\n",
          "        p = CityParameters()\n",
          "        p.sidewalk_width = Length(bad, METER)\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.lot = Length(1e20, METER)\n",
          "    with assert_raises(contains=\"larger than this port lays out\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.street = Length(2000, METER)\n",
          "    with assert_raises(contains=\"larger than this port lays out\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.sidewalk_width = Length(2000, METER)\n",
          "    with assert_raises(contains=\"larger than this port lays out\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.lots_x = 17\n",
          "    with assert_raises(contains=\"more blocks or lots\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.lots_z = 17\n",
          "    with assert_raises(contains=\"more blocks or lots\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.blocks_x = 17\n",
          "    with assert_raises(contains=\"more blocks or lots\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.blocks_z = 17\n",
          "    with assert_raises(contains=\"more blocks or lots\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.lots_x = 16\n",
          "    p.lot = Length(200, METER)\n",
          "    with assert_raises(contains=\"block is larger\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.lots_z = 16\n",
          "    p.lot = Length(200, METER)\n",
          "    with assert_raises(contains=\"block is larger\"):\n",
          "        _ = city_layout(p)\n",
          "    p = CityParameters()\n",
          "    p.lots_x = 16\n",
          "    p.lots_z = 1\n",
          "    p.blocks_x = 1\n",
          "    p.blocks_z = 1\n",
          "    p.lot = Length(100, METER)\n",
          "    var wide = city_layout(p)\n",
          "    assert_equal(wide.block_w, 1600)\n"
        ]
      }
    ]
  },
  "tests/test_clipping.mojo": {
    "before_sha256": "b6bb47ea6541bcb193b904cc55badf21905a6d6bb9c91849b684d7f319ea7422",
    "after_sha256": "2217136b01d077c9c98ab16a212eb3f614f0892804adf6ba98278da4a5b7f53d",
    "before_token_sha256": "a0be7f72c06a1be7bbe9d9f006aae25e7fef44071fe0d4ee14b1189c345fc897",
    "after_token_sha256": "2c66de8a2316ae8063e59506514e8cb0c371d1f2ce921d05aa9800dbce9e9055",
    "edits": [
      {
        "start": 156,
        "stop": 172,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_changed_clipping_plane_count_is_refused() raises:\n",
          "    var material = Material(Color(255, 0, 0))\n",
          "    material.set_clipping_planes([Plane(Vector3(1, 0, 0), 0)])\n",
          "    material.clip_plane_count = -1\n",
          "    with assert_raises(contains=\"zero or more\"):\n",
          "        _ = material.clipping_planes()\n",
          "    material.clip_plane_count = MAX_CLIPPING_PLANES + 1\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = material.clipping_planes()\n",
          "    material.clip_plane_count = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = material.clipping_planes()\n",
          "    material.clip_plane_count = 1\n",
          "    assert_equal(len(material.clipping_planes()), 1)\n"
        ]
      }
    ]
  },
  "tests/test_computation.mojo": {
    "before_sha256": "bf91ccecbb5e42c6117409b57439f4ce8ac3381589abcd0ef5566c5971cfa6ea",
    "after_sha256": "0225c00bf8da2514b07449081c00fd908b5b98e047c5154d6e466fa203095665",
    "before_token_sha256": "7e11fca66c1ae2194216102ef780424ec17b9a12e5dbd3557a2d4640e7f6dad1",
    "after_token_sha256": "6da493c81f86d88459a461edc625a4c2eb016ddfde5f3f631a0efe1d4da12f4d",
    "edits": [
      {
        "start": 61,
        "stop": 64,
        "before": [
          "def _starting_positions(computation: GPUComputationRenderer) -> List[Float32]:\n"
        ],
        "after": [
          "def _starting_positions(\n",
          "    computation: GPUComputationRenderer,\n",
          ") raises -> List[Float32]:\n"
        ]
      },
      {
        "start": 157,
        "stop": 218,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def _read(wrap: Int, u: Float32, v: Float32) -> Float32:\n",
          "    \"\"\"Return the red of a 2 by 2 image whose red is `x + 2y + 1`.\"\"\"\n",
          "    var code = List[Float32](length=4, fill=0)\n",
          "    var images = List[Float32]()\n",
          "    for y in range(2):\n",
          "        for x in range(2):\n",
          "            images.append(Float32(x + 2 * y + 1))\n",
          "            images.append(0)\n",
          "            images.append(0)\n",
          "            images.append(1)\n",
          "    var wraps = List[Int32]()\n",
          "    wraps.append(Int32(wrap))\n",
          "    wraps.append(Int32(wrap))\n",
          "    var source = ComputeNodes(\n",
          "        code.unsafe_ptr()\n",
          "        .unsafe_mut_cast[False]()\n",
          "        .unsafe_origin_cast[Untracked](),\n",
          "        images.unsafe_ptr()\n",
          "        .unsafe_mut_cast[False]()\n",
          "        .unsafe_origin_cast[Untracked](),\n",
          "        wraps.unsafe_ptr()\n",
          "        .unsafe_mut_cast[False]()\n",
          "        .unsafe_origin_cast[Untracked](),\n",
          "        2,\n",
          "        2,\n",
          "        0,\n",
          "        0,\n",
          "    )\n",
          "    var red = source.sample(0, u, v).r\n",
          "    _ = code^\n",
          "    _ = images^\n",
          "    _ = wraps^\n",
          "    return red\n",
          "\n",
          "\n",
          "def test_a_coordinate_past_1048576_is_reduced_before_the_index() raises:\n",
          "    assert_equal(\n",
          "        _read(CLAMP.value, Float32(1e20), 0.25), _read(CLAMP.value, 1, 0.25)\n",
          "    )\n",
          "    assert_equal(\n",
          "        _read(CLAMP.value, Float32(-1e20), 0.25), _read(CLAMP.value, 0, 0.25)\n",
          "    )\n",
          "    assert_equal(\n",
          "        _read(CLAMP.value, nan[DType.float32](), 0.25),\n",
          "        _read(CLAMP.value, 0, 0.25),\n",
          "    )\n",
          "    assert_equal(\n",
          "        _read(CLAMP.value, 0.25, nan[DType.float32]()),\n",
          "        _read(CLAMP.value, 0.25, 0),\n",
          "    )\n",
          "    assert_equal(\n",
          "        _read(REPEAT.value, Float32(1e20), 0.25), _read(REPEAT.value, 0, 0.25)\n",
          "    )\n",
          "    assert_equal(\n",
          "        _read(MIRROR.value, Float32(1e20), 0.25), _read(MIRROR.value, 0, 0.25)\n",
          "    )\n",
          "    assert_equal(\n",
          "        _read(MIRROR.value, Float32(-1e20), 0.25), _read(MIRROR.value, 0, 0.25)\n",
          "    )\n"
        ]
      },
      {
        "start": 339,
        "stop": 341,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = GPUComputationRenderer(1 << 31, 1 << 31)\n"
        ]
      },
      {
        "start": 355,
        "stop": 381,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_changed_computation_size_is_refused() raises:\n",
          "    var computation = GPUComputationRenderer(4, 4)\n",
          "    computation.size_x = 0\n",
          "    with assert_raises(contains=\"need a size\"):\n",
          "        _ = computation.create_texture()\n",
          "    computation.size_x = 4\n",
          "    computation.size_y = -1\n",
          "    with assert_raises(contains=\"need a size\"):\n",
          "        _ = computation.create_texture()\n",
          "    computation.size_x = 1 << 31\n",
          "    computation.size_y = 1 << 31\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = computation.create_texture()\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = computation.add_variable(\"a\", SLOW, List[Float32]())\n",
          "    assert_equal(len(computation.variables), 0)\n",
          "    computation.size_x = 4\n",
          "    computation.size_y = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        computation.compute()\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = computation.current_texture(0)\n",
          "    computation.size_y = 4\n",
          "    assert_equal(len(computation.create_texture()), 64)\n"
        ]
      }
    ]
  },
  "tests/test_compute_nodes.mojo": {
    "before_sha256": "8730a2c9e1c329180f25e976836ddcfd48fe40f12d9bc0a45ecea6eb0fe4ca60",
    "after_sha256": "8c10af34776b6b8ebefc5cb7e5eeb2d770f276624646864d36e2d724947feb50",
    "before_token_sha256": "95a991e8e6a724929770dbc01cfa29847dda38de2d9ec8a67cfbc600821cb5f5",
    "after_token_sha256": "2636e703f619601307e6ec84f87507c4b823233ee6743309f29104462ec7895d",
    "edits": [
      {
        "start": 132,
        "stop": 139,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = StorageBuffer(Int.MAX // 4 + 1, NODE_VEC4)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = StorageBuffer(Int.MAX // 2 + 1, NODE_VEC2)\n",
          "    var wide = StorageBufferStore()\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = wide.storage_texture(Int.MAX, 2)\n"
        ]
      },
      {
        "start": 325,
        "stop": 360,
        "before": [],
        "after": [
          "def test_a_compute_dispatch_this_port_cannot_run_is_refused() raises:\n",
          "    var store = StorageBufferStore()\n",
          "    var data = store.instanced_array(1, NODE_FLOAT)\n",
          "    var kernel = ComputeKernel()\n",
          "    kernel.assign(data, kernel.graph.float(0), kernel.graph.float(1))\n",
          "    var node = kernel.compute(4, 64)\n",
          "    node.count = 0\n",
          "    with assert_raises(contains=\"one invocation\"):\n",
          "        run_compute(store, node)\n",
          "    node.count = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        run_compute(store, node)\n",
          "    node.count = Int.MAX // 4 + 1\n",
          "    node.results = 1\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        run_compute(store, node)\n",
          "    node.count = 4\n",
          "    node.workgroup_size = 0\n",
          "    with assert_raises(contains=\"workgroup\"):\n",
          "        run_compute(store, node)\n",
          "    node.workgroup_size = 1025\n",
          "    with assert_raises(contains=\"workgroup\"):\n",
          "        run_compute(store, node)\n",
          "    node.workgroup_size = 64\n",
          "    node.results = -1\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        run_compute(store, node)\n",
          "    node.results = 1 << 62\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        run_compute(store, node)\n",
          "    node.results = 1\n",
          "    run_compute(store, node)\n",
          "    assert_equal(_floats(store, data)[0], 1)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 460,
        "stop": 477,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_workgroup_copy_that_does_not_fit_is_refused() raises:\n",
          "    var store = StorageBufferStore()\n",
          "    var data = store.instanced_array(1, NODE_FLOAT)\n",
          "    var kernel = ComputeKernel()\n",
          "    _ = kernel.workgroup_array(NODE_VEC4, Int.MAX // 4 + 1)\n",
          "    kernel.add_assign(data, kernel.instance_index(), kernel.graph.float(1))\n",
          "    var node = kernel.compute(1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = pack_storage(store, node)\n",
          "    var wide = ComputeKernel()\n",
          "    _ = wide.workgroup_array(NODE_FLOAT, Int.MAX // 2)\n",
          "    wide.add_assign(data, wide.instance_index(), wide.graph.float(1))\n",
          "    var many = wide.compute(3, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = pack_storage(store, many)\n"
        ]
      }
    ]
  },
  "tests/test_csm.mojo": {
    "before_sha256": "3c7b689e76082dc9381a307b1c3527d52397a78a174675bbf8a1f10401d88df9",
    "after_sha256": "38095a45ea04ce8ab7f08ebde4f272335166ec93c1d4c2abb3d624c380be16c7",
    "before_token_sha256": "450932ea2e8b72d91dc3e84b43339ef495dbbdd883d06e30b1acb7676ec923e9",
    "after_token_sha256": "513818e66b7f03505b8ff403275b4207caf1bdc8030f079dd0121db2c08641a6",
    "edits": [
      {
        "start": 362,
        "stop": 372,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CSM(scene, camera, cascades=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CSM(scene, camera, cascades=Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = uniform_split(Int.MAX, 1, 100)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = logarithmic_split(16777217, 1, 100)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = practical_split(Int.MAX, 1, 100, 0.5)\n"
        ]
      }
    ]
  },
  "tests/test_cube_depth_texture.mojo": {
    "before_sha256": "77d7ae1b8e9fc781a37da6e2cba24d012c313a82e54c1c54dc4d9d58b681441d",
    "after_sha256": "098a1ee06b6648d75fbeef86124cbc039d36bc4dc617e1d677817af1de620223",
    "before_token_sha256": "e7545422f5436a7b96b6444823fd8ee39b56fed4b12b5930e6444e5773e9b4f4",
    "after_token_sha256": "3dbe93fe8ea5c662bec7be476becf1efe195bf3049bfaca750276cfc80767ac0",
    "edits": [
      {
        "start": 77,
        "stop": 79,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = cube_depth_texture(1 << 32, List[Float32]())\n"
        ]
      }
    ]
  },
  "tests/test_curve.mojo": {
    "before_sha256": "e201a849d56b5021adc702b640dd0a08662c47b4f16bf9cc31ae25ac30fccf11",
    "after_sha256": "99ee0080f0aed41778d91be9a1f46c20a97eb729b280914c93641491234d8fed",
    "before_token_sha256": "f95adea6b94a8b4c8817ca91b5f130487ff6f0d8d91d73606a96568effdc1f59",
    "after_token_sha256": "e7b0506527d5b9af51cf9a7b4f16526dea6806c88a1c26261cdebfb6ad6ec4ba",
    "edits": [
      {
        "start": 208,
        "stop": 217,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_long_spline_ends_on_its_last_point() raises:\n",
          "    # A `Float32` count of 16777217 is 16777216, so `t` of one used to\n",
          "    # stop on the point before the last.\n",
          "    var count = 16777218\n",
          "    var points = List[Vector2](length=count, fill=Vector2(0, 0))\n",
          "    points[count - 1] = Vector2(1, 0)\n",
          "    assert_point(spline(points^).point(1), 1, 0)\n"
        ]
      }
    ]
  },
  "tests/test_curve3.mojo": {
    "before_sha256": "c33cc9e72f53414996dd321fd82d23f769f15ef51025a7f2dba07867a2590093",
    "after_sha256": "c9a7f8f7e25c2e9e47595971d758e8fb3e8a513a1aefde8d60231efbc3e3aded",
    "before_token_sha256": "bc93307830d88d91f4dc20a59c2772c698893f6606fb044166478b52d31e57f9",
    "after_token_sha256": "fd735795e1d3244b2328a7409541645d1d1508edc251aebbf2e20adfb77744fb",
    "edits": [
      {
        "start": 207,
        "stop": 216,
        "before": [],
        "after": [
          "def test_a_long_spline_ends_on_its_last_point() raises:\n",
          "    # A `Float32` count of 16777217 is 16777216, so `t` of one used to\n",
          "    # stop on the point before the last.\n",
          "    var count = 16777218\n",
          "    var points = List[Vector3](length=count, fill=Vector3(0, 0, 0))\n",
          "    points[count - 1] = Vector3(1, 0, 0)\n",
          "    assert_xyz(catmull_rom3(points^).point(1), 1, 0, 0, CLOSE)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 391,
        "stop": 395,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = tube(curve, Length(0.1, METER), Int.MAX, 8)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = tube(curve, Length(0.1, METER), 8, 2097153)\n"
        ]
      }
    ]
  },
  "tests/test_curve_boundaries.mojo": {
    "before_sha256": "2b1e36d6e51979909363a87acf1ec7dcd61e2f019a4d90a0bc6c01d7b15abfc8",
    "after_sha256": "49bea6044209382052fe3918f6c8dba7c8663243ce6060917aa32277bb1f64b9",
    "before_token_sha256": "848b07ddb514b8ef28475f68725c3d42cebd8adbcf09ab6bfe3f90c995459385",
    "after_token_sha256": "2304f5ed05c09a563e9647ed54a5b155516c60acfc5c962ff7ff0deb13953ef9",
    "edits": [
      {
        "start": 272,
        "stop": 277,
        "before": [
          "    assert_equal(curve_sample_count(Int.MAX - 1), Int.MAX)\n"
        ],
        "after": [
          "    assert_equal(curve_sample_count(16777216), 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = curve_sample_count(16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = curve_sample_count(Int.MAX - 1)\n"
        ]
      },
      {
        "start": 308,
        "stop": 312,
        "before": [],
        "after": [
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.sample(Int.MAX - 1)\n",
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.sample(16777217)\n"
        ]
      },
      {
        "start": 314,
        "stop": 316,
        "before": [],
        "after": [
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.lengths(Int.MAX - 1)\n"
        ]
      },
      {
        "start": 318,
        "stop": 320,
        "before": [],
        "after": [
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.spaced_points(16777217)\n"
        ]
      },
      {
        "start": 326,
        "stop": 330,
        "before": [],
        "after": [
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.sample(Int.MAX - 1)\n",
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.sample(16777217)\n"
        ]
      },
      {
        "start": 334,
        "stop": 336,
        "before": [],
        "after": [
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.spaced_points(16777217)\n"
        ]
      },
      {
        "start": 338,
        "stop": 340,
        "before": [],
        "after": [
          "        with assert_raises(contains=\"larger than this port\"):\n",
          "            _ = curve.frenet_frames(Int.MAX - 1, False)\n"
        ]
      },
      {
        "start": 347,
        "stop": 351,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = path.sample(Int.MAX - 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = path.sample(16777217)\n"
        ]
      },
      {
        "start": 353,
        "stop": 355,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = path.spaced_points(Int.MAX - 1)\n"
        ]
      },
      {
        "start": 357,
        "stop": 359,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = path.frenet_frames(16777217, False)\n"
        ]
      },
      {
        "start": 364,
        "stop": 365,
        "before": [],
        "after": [
          "    assert_equal(len(straight.sample(Int.MAX - 1)), 2)\n"
        ]
      },
      {
        "start": 376,
        "stop": 377,
        "before": [],
        "after": [
          "    assert_equal(len(pen.sample(16777217)), 2)\n"
        ]
      },
      {
        "start": 386,
        "stop": 388,
        "before": [
          "    # Each piece fits, but their total sample count does not. No huge\n",
          "    # first-piece allocation may precede the total-count check.\n"
        ],
        "after": [
          "    # Each piece asks for more runs than this port samples. The preflight\n",
          "    # refuses that before it samples the first piece.\n"
        ]
      },
      {
        "start": 391,
        "stop": 392,
        "before": [
          "    with assert_raises():\n"
        ],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n"
        ]
      },
      {
        "start": 393,
        "stop": 399,
        "before": [],
        "after": [
          "    # A spline multiplies the division count by its point count. Three\n",
          "    # points at 5592406 runs is 16777218, which the sample refuses.\n",
          "    var wide = Path(Vector2(0, 0))\n",
          "    wide.curves.append(planar[3].copy())\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = wide.sample(5592406)\n"
        ]
      },
      {
        "start": 414,
        "stop": 418,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = lengths_of(curve, Int.MAX - 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = lengths_of(curve, 16777217)\n"
        ]
      },
      {
        "start": 422,
        "stop": 424,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = points_of(curve, 16777217)\n"
        ]
      },
      {
        "start": 436,
        "stop": 438,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = frames3_of(curve, Int.MAX - 1)\n"
        ]
      },
      {
        "start": 440,
        "stop": 442,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = frames_of(curve, 16777217)\n"
        ]
      }
    ]
  },
  "tests/test_display_nodes.mojo": {
    "before_sha256": "1629091c28886f5bb7933d74cfb520fb66d7f8d6ea41593766a0f468230b1767",
    "after_sha256": "0d202176df4b933a883dd8666d157b0475d0a43687b27e105444dce28131eb4e",
    "before_token_sha256": "ef54b06b2aaf57f60472cd88965f0525229cd620cf545c289a62dc469123c3dc",
    "after_token_sha256": "5287bd4696b4d2d27de87f1769db70672404c3a09a944bf09ed256a65b1b5314",
    "edits": [
      {
        "start": 46,
        "stop": 47,
        "before": [],
        "after": [
          "from std.math import nan\n"
        ]
      },
      {
        "start": 99,
        "stop": 116,
        "before": [],
        "after": [
          "    # A `Float32` product of 16777217 is 16777216. JavaScript keeps it.\n",
          "    assert_equal(scaled_size(16777217, 1), 16777217)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = scaled_size(Int.MAX, 1)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = scaled_size(Int.MIN, 1.5)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = scaled_size(1, nan[DType.float32]())\n",
          "    # A kernel past 2^24 is not a stable weight index, and the walk does\n",
          "    # not finish.\n",
          "    with assert_raises(contains=\"kernel\"):\n",
          "        _ = gaussian_coefficients(Float32(1e20))\n",
          "    var wide = DisplaySettings()\n",
          "    wide.sigma = Float32(1e20)\n",
          "    var held = even(FloatColor(0.5, 0.5, 0.5, 1))\n",
          "    with assert_raises(contains=\"kernel\"):\n",
          "        gaussian_blur_light(held, wide)\n"
        ]
      },
      {
        "start": 123,
        "stop": 137,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_scaled_frame_must_fit() raises:\n",
          "    var settings = DisplaySettings()\n",
          "    settings.resolution_scale = Float32(1 << 31)\n",
          "    var frame = RenderTarget(2, 2, Color(0, 0, 0))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        gaussian_blur_light(frame, settings)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        anamorphic_light(frame, settings)\n",
          "    settings.resolution_scale = 1\n",
          "    settings.down_sample_ratio = Float32(1) / Float32(1 << 31)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        lensflare_light(frame, settings)\n"
        ]
      },
      {
        "start": 249,
        "stop": 287,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = box_blur_pass(2048, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = box_blur_pass(Int.MAX, 1)\n",
          "    var boxed = even(FloatColor(0.25, 0.5, 0.75, 1))\n",
          "    var broad = DisplaySettings()\n",
          "    broad.size = Int.MAX\n",
          "    box_blur_light(boxed, broad)\n",
          "    assert_almost_equal(boxed.colors[20].g, Float32(0.5), atol=1e-5)\n",
          "    # A size below zero also keeps the pixel.\n",
          "    var shrunk = even(FloatColor(0.25, 0.5, 0.75, 1))\n",
          "    var below = DisplaySettings()\n",
          "    below.size = -1\n",
          "    box_blur_light(shrunk, below)\n",
          "    assert_almost_equal(shrunk.colors[20].g, Float32(0.5), atol=1e-5)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = hash_blur_pass(repeats=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = hash_blur_pass(repeats=Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = anamorphic_pass(0.9, 3, Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = lensflare_pass(ghost_samples=16777217)\n",
          "    var kept = even(FloatColor(0.25, 0.5, 0.75, 1))\n",
          "    var heavy = DisplaySettings()\n",
          "    heavy.repeats = Int.MAX\n",
          "    hash_blur_light(kept, heavy)\n",
          "    assert_almost_equal(kept.colors[20].b, Float32(0.75), atol=1e-5)\n",
          "    var streak = RenderTarget(2, 2, Color(0, 0, 0))\n",
          "    var wide = DisplaySettings()\n",
          "    wide.samples = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        anamorphic_light(streak, wide)\n",
          "    wide.samples = 32\n",
          "    wide.ghost_samples = Int.MAX\n",
          "    wide.down_sample_ratio = 1\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        lensflare_light(streak, wide)\n"
        ]
      }
    ]
  },
  "tests/test_fbx.mojo": {
    "before_sha256": "17a2ce6d8efbebcc2f03b0c57aa5cc6c3636c39e264a733b4a0858c2d966ca6d",
    "after_sha256": "313e88b7af4dcc197131a05fff5b2fbd1b0714d575a3889d2ee06a0c6253bf31",
    "before_token_sha256": "29fb276b5f434a5b053bcbebb2973897ed2a0b7f73fc3726a64a279715db1829",
    "after_token_sha256": "0f2874db763d8416e82dae3480cf6801a5606e05338594fba2254d258c225afe",
    "edits": [
      {
        "start": 59,
        "stop": 60,
        "before": [],
        "after": [
          "    require_fbx_whole,\n"
        ]
      },
      {
        "start": 981,
        "stop": 984,
        "before": [],
        "after": [
          "    var huge = parse_fbx_text(\"; FBX\\nFBXVersion: 7400\\nNode: 1e20\\n\")\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        _ = huge.integer(huge.child(huge.root(), \"Node\"), 0)\n"
        ]
      },
      {
        "start": 1676,
        "stop": 1730,
        "before": [],
        "after": [
          "    var bad_order = Scene()\n",
          "    var bad_assets = Assets()\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        _ = load_text(\n",
          "            objects(\n",
          "                '\\tModel: 1, \"Model::A\", \"Null\" {\\n\\t\\tProperties70:  {\\n'\n",
          "                + '\\t\\t\\tP: \"RotationOrder\", \"enum\", \"\", \"\",1e20\\n\\t\\t}\\n\\t}\\n'\n",
          "            ),\n",
          "            bad_order,\n",
          "            bad_assets,\n",
          "        )\n",
          "    # A number past the low end of an integer is refused too.\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        require_fbx_whole(-1e20)\n",
          "    var fraction = Scene()\n",
          "    var fraction_assets = Assets()\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        _ = load_text(\n",
          "            objects(\n",
          "                '\\tModel: 1, \"Model::A\", \"Null\" {\\n\\t\\tProperties70:  {\\n'\n",
          "                + '\\t\\t\\tP: \"InheritType\", \"enum\", \"\", \"\",1.5\\n\\t\\t}\\n\\t}\\n'\n",
          "            ),\n",
          "            fraction,\n",
          "            fraction_assets,\n",
          "        )\n",
          "    var bad_light = Scene()\n",
          "    var light_assets = Assets()\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        _ = load_text(\n",
          "            objects(\n",
          "                '\\tModel: 1, \"Model::Lamp\", \"Light\" {\\n\\t}\\n'\n",
          "                + '\\tNodeAttribute: 2, \"NodeAttribute::L\", \"Light\"'\n",
          "                + \" {\\n\\t\\tProperties70:  {\\n\"\n",
          "                + '\\t\\t\\tP: \"LightType\", \"enum\", \"\", \"\",1e20\\n\\t\\t}\\n\\t}\\n',\n",
          "                '\\tC: \"OO\",2,1\\n',\n",
          "            ),\n",
          "            bad_light,\n",
          "            light_assets,\n",
          "        )\n",
          "    var bad_camera = Scene()\n",
          "    var camera_assets = Assets()\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        _ = load_text(\n",
          "            objects(\n",
          "                '\\tModel: 1, \"Model::Cam\", \"Camera\" {\\n\\t}\\n'\n",
          "                + '\\tNodeAttribute: 2, \"NodeAttribute::C\", \"Camera\"'\n",
          "                + \" {\\n\\t\\tProperties70:  {\\n\"\n",
          "                + '\\t\\t\\tP: \"CameraProjectionType\", \"enum\", \"\", \"\",1.5\\n'\n",
          "                + \"\\t\\t}\\n\\t}\\n\",\n",
          "                '\\tC: \"OO\",2,1\\n',\n",
          "            ),\n",
          "            bad_camera,\n",
          "            camera_assets,\n",
          "        )\n"
        ]
      }
    ]
  },
  "tests/test_fbx_rig.mojo": {
    "before_sha256": "c3c637a995edb5f00553b37c9ced86182ae1eadf03d092c529a7f2b222576798",
    "after_sha256": "17514a1612c7ad6090b81bc397cecaf8e272c44de1c85c12ce4bb10ab64a7920",
    "before_token_sha256": "a76adeefe5fbc65dcd4aa86e5000791dd97956edc23f80ed155ad2f57a6febf6",
    "after_token_sha256": "5f88b8d80183a61875539619552b8b42db9dcab08355b6cfec2a69e4f45ccafd",
    "edits": [
      {
        "start": 377,
        "stop": 396,
        "before": [],
        "after": [
          "def test_an_inverse_bind_that_rounds_off_the_last_row_is_kept_affine() raises:\n",
          "    # A real bind from a Mixamo file. Its Float32 inverse ends at\n",
          "    # (0, 0, 0, 0.99999994) before the loader sets the last row.\n",
          "    var knee = String(\"a: 1,0,0,0,0,1,0,0,0,0,1,0,1,1,0,1\")\n",
          "    var real = String(\n",
          "        \"a: 0.9999999999999968,-6.7238402738571e-08,4.426546278275548e-08,0,\"\n",
          "        \"7.211829798733264e-08,0.9925921726345991,-0.12149394562907734,0,\"\n",
          "        \"-3.57684930297053e-08,0.12149394562908016,0.9925921726346006,0,\"\n",
          "        \"-1.2848989892782086e-05,133.57119840012686,-1.1555181104463805,1\"\n",
          "    )\n",
          "    var scene = Scene()\n",
          "    var assets = Assets()\n",
          "    _ = load(swap(rig(), knee, real), scene, assets)\n",
          "    ref bind = scene.skinned_meshes[0].skeleton.bones[1].inverse_bind\n",
          "    assert_true(bind.is_affine())\n",
          "    assert_almost_equal(bind.elements[5], Float32(0.9925922), atol=1e-6)\n",
          "    assert_almost_equal(bind.elements[13], Float32(-132.7), atol=0.1)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 425,
        "stop": 434,
        "before": [],
        "after": [
          "    )\n",
          "    # A bind that is not affine, or has no inverse, makes no skeleton.\n",
          "    refused(\n",
          "        swap(text, link, \"*16 {\\n\\t\\t\\ta: 1,0,0,1,0,1,0,0,0,0,1,0,1,1,0,1\"),\n",
          "        \"inverse bind must be affine\",\n",
          "    )\n",
          "    refused(\n",
          "        swap(text, link, \"*16 {\\n\\t\\t\\ta: 0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,1\"),\n",
          "        \"inverse bind must be affine\",\n"
        ]
      }
    ]
  },
  "tests/test_filter_nodes.mojo": {
    "before_sha256": "2d1316af4a32e400a62549301d2588917e547fd6073925103004c126fa32510d",
    "after_sha256": "b30b8fb9edc5b2242a0ca2fa05971bcb1eb770a82fa09d9f678c114a110693be",
    "before_token_sha256": "0aed49ecacc7206c17bcd8848c3a4de31c3c3ba5ce8df7df9ba919a3b02de1ff",
    "after_token_sha256": "02762b5fce11135ffd88cf403190973b23a9ef9c3345c3711450062063e85dbb",
    "edits": [
      {
        "start": 12,
        "stop": 13,
        "before": [],
        "after": [
          "from math.matrix4 import Matrix4\n"
        ]
      },
      {
        "start": 43,
        "stop": 44,
        "before": [],
        "after": [
          "    depth_aware_blur_value,\n"
        ]
      },
      {
        "start": 138,
        "stop": 148,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = radial_blur_pass(count=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = radial_blur_pass(count=Int.MAX)\n",
          "    var frame = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET)\n",
          "    frame.colors[0] = FloatColor(0.25, 0.5, 0.75, 1)\n",
          "    var heavy = FilterSettings()\n",
          "    heavy.count = Int.MAX\n",
          "    radial_blur_light(frame, heavy)\n",
          "    assert_almost_equal(frame.colors[0].g, Float32(0.5), atol=1e-5)\n"
        ]
      },
      {
        "start": 232,
        "stop": 237,
        "before": [],
        "after": [
          "    # A count past 16777216 keeps the pixel, premultiplied too.\n",
          "    settings.count = 16777217\n",
          "    out = radial_blur_pixel(LightView(even, SIZE, SIZE), 2, 5, settings)\n",
          "    assert_almost_equal(out.r, 0.2, atol=1e-4)\n",
          "    assert_almost_equal(out.a, 1, atol=1e-6)\n"
        ]
      },
      {
        "start": 283,
        "stop": 302,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_wide_blur_reads_the_center_texel() raises:\n",
          "    var width = 16777217\n",
          "    var values = List[Float32](length=width, fill=0)\n",
          "    values[8388608] = 1\n",
          "    var depth = List[Float32](length=width, fill=0)\n",
          "    var view = DepthView(\n",
          "        depth,\n",
          "        width,\n",
          "        1,\n",
          "        Matrix4(),\n",
          "        Length(0.1, METER),\n",
          "        Length(50.0, METER),\n",
          "    )\n",
          "    var got = depth_aware_blur_value(\n",
          "        values, width, 1, view, 8388608, 0, 0, 0, FilterSettings()\n",
          "    )\n",
          "    assert_equal(got, 1)\n"
        ]
      }
    ]
  },
  "tests/test_gaussian_splat.mojo": {
    "before_sha256": "3bf552e1d09bcd79643fac9fa8481351ee8170b6d05e60aaf77f87b6e78c4dc6",
    "after_sha256": "32c6f1472332c1c7ee6167fa71928f4f108ba2a73fddc97112b7e4599cb4b94e",
    "before_token_sha256": "f23f966f814b66230b598a5cf3d304ca15127fce081a6a5129de8aa6db8dd3f3",
    "after_token_sha256": "8bc1fd1e3b6044fdd30d7e6b566312f31aba7e54cd15d1bf2be56f7b5e38b4ff",
    "edits": [
      {
        "start": 57,
        "stop": 59,
        "before": [],
        "after": [
          "    _splat_high,\n",
          "    _splat_low,\n"
        ]
      },
      {
        "start": 167,
        "stop": 171,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = packed_band(Int.MAX // 12 + 1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = packed_band(Int.MAX // 24 + 1, 3)\n"
        ]
      },
      {
        "start": 825,
        "stop": 839,
        "before": [],
        "after": [
          "    rasterize_splats(target, [unit_splat(Float32(1e20), 4)])\n",
          "    rasterize_splats(target, [unit_splat(Float32(-1e20), 4)])\n",
          "    rasterize_splats(target, [unit_splat(nan[DType.float32](), 4)])\n",
          "    assert_equal(target.color_at(4, 0).r, 0)\n",
          "    assert_equal(target.color_at(0, 4).r, 0)\n",
          "    # The bounds themselves, so a center past an integer is not scanned.\n",
          "    assert_equal(_splat_low(Float32(1e20), 0), Int.MAX)\n",
          "    assert_equal(_splat_high(Float32(1e20), 7), 7)\n",
          "    assert_equal(_splat_low(Float32(-1e20), 0), 0)\n",
          "    assert_equal(_splat_high(Float32(-1e20), 7), Int.MIN)\n",
          "    assert_equal(_splat_low(2, 0), 1)\n",
          "    assert_equal(_splat_high(6, 7), 7)\n",
          "    assert_equal(_splat_low(nan[DType.float32](), 0), Int.MAX)\n",
          "    assert_equal(_splat_high(nan[DType.float32](), 7), 7)\n"
        ]
      }
    ]
  },
  "tests/test_geometry.mojo": {
    "before_sha256": "e815cf18c4e9891411e42dedf8e548bacea9b18023762861c738ca15355817dc",
    "after_sha256": "3d6730175e044bbf73e74d5bc4bdd9302f1a51c25bcf1e86edcf38fd7ac4db97",
    "before_token_sha256": "db049f71344c24cb55510794bae1a10ca5d0765b263e98b3edc345736a025f29",
    "after_token_sha256": "c8c99f3ac9c22a74c4cc8266a77e4e9175036cab74950697c9cba066b0736721",
    "edits": [
      {
        "start": 449,
        "stop": 458,
        "before": [],
        "after": [
          "    var one = Length(1.0, METER)\n",
          "    var strip = box(one, one, one, 4096, 1, 1)\n",
          "    assert_equal(strip.vertex_count(), 32784)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = box(one, one, one, Int.MAX, 1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = box(one, one, one, 1, 1, Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = box(one, one, one, 1, 4097, 4096)\n"
        ]
      },
      {
        "start": 571,
        "stop": 581,
        "before": [],
        "after": [
          "    var belt = sphere(Length(1.0, METER), 4096, 2)\n",
          "    assert_equal(belt.vertex_count(), 4097 * 3)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = sphere(Length(1.0, METER), 16777217, 2)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = sphere(Length(1.0, METER), 3, 5592406)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = sphere(Length(1.0, METER), Int.MAX, 16)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = sphere(Length(1.0, METER), 32, Int.MAX)\n"
        ]
      },
      {
        "start": 834,
        "stop": 847,
        "before": [],
        "after": [
          "    var strip = plane(Length(2.0, METER), Length(1.0, METER), 4096, 1)\n",
          "    assert_equal(strip.vertex_count(), 4097 * 2)\n",
          "    assert_equal(strip.triangle_count(), 4096 * 2)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = plane(Length(1.0, METER), Length(1.0, METER), 16777217, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = plane(Length(1.0, METER), Length(1.0, METER), 1, 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = plane(Length(1.0, METER), Length(1.0, METER), 4097, 4096)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = plane(Length(1.0, METER), Length(1.0, METER), Int.MAX, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = plane(Length(1.0, METER), Length(1.0, METER), 1, Int.MAX)\n"
        ]
      },
      {
        "start": 960,
        "stop": 967,
        "before": [],
        "after": [
          "    var disk = circle(Length(1.0, METER), 4096)\n",
          "    assert_equal(disk.vertex_count(), 4098)\n",
          "    assert_equal(disk.triangle_count(), 4096)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = circle(Length(1.0, METER), 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = circle(Length(1.0, METER), Int.MAX)\n"
        ]
      },
      {
        "start": 1131,
        "stop": 1140,
        "before": [],
        "after": [
          "    var washer = ring(Length(1.0, METER), Length(2.0, METER), 4096, 1)\n",
          "    assert_equal(washer.vertex_count(), 4097 * 2)\n",
          "    assert_equal(washer.triangle_count(), 4096 * 2)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ring(Length(1.0, METER), Length(2.0, METER), 16777217, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ring(Length(1.0, METER), Length(2.0, METER), 8, 2097153)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ring(Length(1.0, METER), Length(2.0, METER), Int.MAX, 1)\n"
        ]
      },
      {
        "start": 1347,
        "stop": 1358,
        "before": [],
        "after": [
          "    var pipe = cylinder(one, one, Length(2.0, METER), 4096, 1, True)\n",
          "    assert_equal(pipe.vertex_count(), 4097 * 2)\n",
          "    assert_equal(pipe.triangle_count(), 4096 * 2)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = cylinder(one, one, one, 16777217, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = cylinder(one, one, one, 8, 2097153)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = cylinder(one, one, one, Int.MAX, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = cone(one, one, Int.MAX, 1)\n"
        ]
      },
      {
        "start": 1603,
        "stop": 1609,
        "before": [],
        "after": [
          "    var hoop = torus(two, half, 3, 4096)\n",
          "    assert_equal(hoop.vertex_count(), 4 * 4097)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = torus(two, half, Int.MAX, 12)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = torus(two, half, 3, 5592406)\n"
        ]
      },
      {
        "start": 2049,
        "stop": 2055,
        "before": [],
        "after": [
          "    var fine = polyhedron(vertices, indices, one, 256)\n",
          "    assert_equal(fine.vertex_count(), 257 * 257 * 3)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = polyhedron(vertices, indices, one, 257)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = icosahedron(one, Int.MAX)\n"
        ]
      },
      {
        "start": 2197,
        "stop": 2205,
        "before": [],
        "after": [
          "    var pill = capsule(one, one, 1, 4096, 1)\n",
          "    assert_equal(pill.vertex_count(), 4 * 4097)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = capsule(one, one, Int.MAX, 8, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = capsule(one, one, 1, Int.MAX, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = capsule(one, one, 1, 8, 2097153)\n"
        ]
      },
      {
        "start": 2330,
        "stop": 2336,
        "before": [],
        "after": [
          "    var turned = lathe(profile([1, 0, 1, 1]), 4096)\n",
          "    assert_equal(turned.vertex_count(), 4097 * 2)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = lathe(profile([1, 0, 1, 1]), Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = lathe(profile([1, 0, 1, 1]), 16777217)\n"
        ]
      },
      {
        "start": 2638,
        "stop": 2644,
        "before": [],
        "after": [
          "    var pipe = tube(straight_path(2), thin, 4096)\n",
          "    assert_equal(pipe.vertex_count(), 2 * 4097)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = tube(straight_path(2), thin, Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = tube(straight_path(2), thin, 16777217)\n"
        ]
      },
      {
        "start": 2661,
        "stop": 2667,
        "before": [],
        "after": [
          "    var knot = torus_knot(two, tenth, 4096, 3)\n",
          "    assert_equal(knot.vertex_count(), 4097 * 4)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = torus_knot(two, tenth, Int.MAX, 8)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = torus_knot(two, tenth, 5592406, 3)\n"
        ]
      }
    ]
  },
  "tests/test_geometry_tools.mojo": {
    "before_sha256": "2ed2203286ad368106da3c17b7f1e24fb2cf463fc9aec87fc3a7ab88a151d709",
    "after_sha256": "3d91253eadeaaac830466f93aca1a363de0474cc5ca3a7f9c256ce7b37458889",
    "before_token_sha256": "61481fdfe1cd6157c9bb92b2e4b3570b6e701ac8e27b671e2f3fdef8d57c3a83",
    "after_token_sha256": "70f83b93221a16eae1118028f4f9be1c20a064eab17cb820e0f25c6264e5bdce",
    "edits": [
      {
        "start": 26,
        "stop": 33,
        "before": [
          "from helpers.uvs_debug import UVS_BACKGROUND, UVS_LINE, uvs_debug\n"
        ],
        "after": [
          "from helpers.uvs_debug import (\n",
          "    UVS_BACKGROUND,\n",
          "    UVS_LINE,\n",
          "    _clip_segment,\n",
          "    _wrap,\n",
          "    uvs_debug,\n",
          ")\n"
        ]
      },
      {
        "start": 47,
        "stop": 48,
        "before": [
          "from std.math import cos, pi, sin\n"
        ],
        "after": [
          "from std.math import cos, nan, pi, sin\n"
        ]
      },
      {
        "start": 49,
        "stop": 50,
        "before": [],
        "after": [
          "from math.vector2 import Vector2\n"
        ]
      },
      {
        "start": 126,
        "stop": 134,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = hilbert2d(iterations=12)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = hilbert2d(iterations=Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = hilbert3d(iterations=8)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = hilbert3d(iterations=Int.MAX)\n"
        ]
      },
      {
        "start": 323,
        "stop": 329,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = roller_coaster_geometry(_Track(), Int.MAX - 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = roller_coaster_lifters_geometry(_Track(), 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = roller_coaster_shadow_geometry(_Track(), Int.MAX)\n"
        ]
      },
      {
        "start": 653,
        "stop": 731,
        "before": [],
        "after": [
          "def test_a_coordinate_that_is_not_a_number_is_left_off_the_image() raises:\n",
          "    assert_equal(_wrap(nan[DType.float32]()), 0)\n",
          "    assert_equal(_wrap(Float32(1e30)), 0)\n",
          "    var a = Vector2(1, 1)\n",
          "    for bad in [\n",
          "        Vector2(1, nan[DType.float32]()),\n",
          "        Vector2(nan[DType.float32](), 1),\n",
          "    ]:\n",
          "        assert_false(_clip_segment(a, bad, 8, 8)[0])\n",
          "        assert_false(_clip_segment(bad, a, 8, 8)[0])\n",
          "\n",
          "\n",
          "def test_an_outline_in_the_last_column_is_drawn() raises:\n",
          "    # A pixel is `u * (size - 2) + 0.5` across. Every corner lies in the\n",
          "    # last column of a 16-pixel image, from 15.06 to 15.9 pixels across.\n",
          "    var geometry = BufferGeometry()\n",
          "    geometry.set_attribute(\n",
          "        String(UV),\n",
          "        BufferAttribute([Float32(1.04), 0.3, 1.06, 0.5, 1.1, 0.7], 2),\n",
          "    )\n",
          "    var drawn = uvs_debug(geometry, 16)\n",
          "    var inked = 0\n",
          "    for y in range(16):\n",
          "        if drawn.image.get_pixel(15, y).r == UVS_LINE.r:\n",
          "            inked += 1\n",
          "    assert_true(inked > 0)\n",
          "\n",
          "\n",
          "def test_a_uv_past_an_integer_is_left_off_the_image() raises:\n",
          "    var geometry = BufferGeometry()\n",
          "    geometry.set_attribute(\n",
          "        String(UV),\n",
          "        BufferAttribute(\n",
          "            [\n",
          "                Float32(1e20),\n",
          "                0.5,\n",
          "                Float32(1e20),\n",
          "                0.6,\n",
          "                Float32(1e20),\n",
          "                0.4,\n",
          "            ],\n",
          "            2,\n",
          "        ),\n",
          "    )\n",
          "    var drawn = uvs_debug(geometry, 16)\n",
          "    var inked = 0\n",
          "    for y in range(16):\n",
          "        for x in range(16):\n",
          "            if drawn.image.get_pixel(x, y).r == UVS_LINE.r:\n",
          "                inked += 1\n",
          "    assert_equal(inked, 0)\n",
          "    var cross = BufferGeometry()\n",
          "    cross.set_attribute(\n",
          "        String(UV),\n",
          "        BufferAttribute(\n",
          "            [Float32(0.2), 0.5, Float32(1e20), 0.5, Float32(0.2), 0.8],\n",
          "            2,\n",
          "        ),\n",
          "    )\n",
          "    var cut = uvs_debug(cross, 16)\n",
          "    var marked = 0\n",
          "    for y in range(16):\n",
          "        for x in range(16):\n",
          "            if cut.image.get_pixel(x, y).r == UVS_LINE.r:\n",
          "                marked += 1\n",
          "    assert_true(marked > 0)\n",
          "    var missing = BufferGeometry()\n",
          "    missing.set_attribute(\n",
          "        String(UV),\n",
          "        BufferAttribute(\n",
          "            [nan[DType.float32](), 0.5, 0.2, 0.2, 0.8, 0.8],\n",
          "            2,\n",
          "        ),\n",
          "    )\n",
          "    var quiet = uvs_debug(missing, 16)\n",
          "    assert_equal(len(quiet.outlines), 1)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_gpgpu_sort.mojo": {
    "before_sha256": "af1616402576e509b7dbd6ff34938b14c8e7ecb2249535d635c420c63d60f36e",
    "after_sha256": "314f504924513c54dbe5c50a551ef6e159d18fea3a6ecac3a52096d2bbc73513",
    "before_token_sha256": "2928a5ec638d44574652ba7544355727d702c47ef95f75094df6d374641ed628",
    "after_token_sha256": "cb66f7180d4657f1099bf0549a96b3bc94423942896262fa2a58b44b258dd41b",
    "edits": [
      {
        "start": 208,
        "stop": 216,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CountingSort(store, 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CountingSort(store, Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CountingSort(store, 4, 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CountingSort(store, 4, Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_hair_strands.mojo": {
    "before_sha256": "aa4f7e7fa8770f4b18c74bbdac64cc5230f290fd4f37c2f4c457768a3b505613",
    "after_sha256": "a8f95a144274696f03df774124446d7fa7762a6b6c1bbed8d74422ea32f82675",
    "before_token_sha256": "c5f0cee96d54f770862b3acc27205e97d107a1dd096bfbbeb9fd4f7064b4f215",
    "after_token_sha256": "5e7031a9266cdd9359b998ccaff95c2e16b47b9fc085da6579c2c361e90df92d",
    "edits": [
      {
        "start": 79,
        "stop": 133,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_changed_groom_count_this_port_cannot_grow_is_refused() raises:\n",
          "    var dims = head_muscle_dimensions(_person())\n",
          "    var spec = GroomSpec(dims, 4, 0)\n",
          "    spec.guides = 0\n",
          "    with assert_raises(contains=\"guides\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.guides = 20001\n",
          "    with assert_raises(contains=\"guides\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.guides = Int.MAX\n",
          "    with assert_raises(contains=\"guides\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.guides = 4\n",
          "    spec.followers = -1\n",
          "    with assert_raises(contains=\"followers\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.followers = 65\n",
          "    with assert_raises(contains=\"followers\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.followers = Int.MAX\n",
          "    with assert_raises(contains=\"followers\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.followers = 0\n",
          "    spec.root_tries = -1\n",
          "    with assert_raises(contains=\"zero or more\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.root_tries = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.root_tries = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "\n",
          "\n",
          "def test_a_hair_step_that_cannot_grow_is_refused() raises:\n",
          "    var dims = head_muscle_dimensions(_person())\n",
          "    var spec = GroomSpec(dims, 4, 0)\n",
          "    spec.step = 0\n",
          "    with assert_raises(contains=\"positive length\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec.step = nan[DType.float32]()\n",
          "    with assert_raises(contains=\"positive length\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec = GroomSpec(dims, 4, 0)\n",
          "    spec.step = Float32(1e-20)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = groom_hair(dims, spec)\n",
          "    spec = GroomSpec(dims, 4, 0)\n",
          "    spec.curl = Float32(0.01)\n",
          "    spec.curl_length = 0\n",
          "    with assert_raises(contains=\"positive length\"):\n",
          "        _ = groom_hair(dims, spec)\n"
        ]
      }
    ]
  },
  "tests/test_helpers.mojo": {
    "before_sha256": "08b7bbc271f7553d4bdea30fc15908f7edca03bd4c1dcabcd7c8cf0f7c2724bb",
    "after_sha256": "6554c300ffb53506fe489043a7735b815df91e02a9e52c61ce084e491f5cc56a",
    "before_token_sha256": "5ba10770b0cbf0b6afaaea989a19c693d32d39ea9194be50d860894411e8b977",
    "after_token_sha256": "cb3732ed4fb1dc6d7ea148a3e550c2fa080ba6b093a742d3b8c2d1d8661c406a",
    "edits": [
      {
        "start": 217,
        "stop": 221,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = grid_helper(Length(1.0, METER), 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = grid_helper(Length(1.0, METER), Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_humanoid_loft.mojo": {
    "before_sha256": "a4632cac899fd9dca4ddc80ac494b09034ec91541ebd40214b54076706fef2cb",
    "after_sha256": "0fc9fd92abdfeb4d7d0b65c27c2c572f39e53b34eedc44f92ec8a8a0813f8ec0",
    "before_token_sha256": "0b89dcedc4e71f02e8b130921aceb9ed4afc2c4df307e32e990d3c481b50400f",
    "after_token_sha256": "67996b5568c947c6a815898c367aff64ea78ac44eb140134c0ac98df66e079b6",
    "edits": [
      {
        "start": 108,
        "stop": 123,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_long_rod_along_a_section_still_fits() raises:\n",
          "    # The slice count is `Int` of the length over half the finest radius,\n",
          "    # then held at sixteen. A rod of 1e20 along the section used to cast\n",
          "    # that ratio before the cap.\n",
          "    var loft = fit_loft(\n",
          "        _rod(Vector3(0, 0, 0), Vector3(Float32(1e20), 0, 0), Float32(1e-5)),\n",
          "        AXIS_Z,\n",
          "        -0.1,\n",
          "        0.1,\n",
          "        3,\n",
          "        _covers(3, 0),\n",
          "    )\n",
          "    assert_equal(loft.count, 3)\n"
        ]
      }
    ]
  },
  "tests/test_layered_targets.mojo": {
    "before_sha256": "f44ab2ae1ac1e55671b8fe5c0e0c288a04907902589165ce5c7c82cbaa7a080f",
    "after_sha256": "4729c154c8765125699b44b691bb6f4d8b57f4a72cbbe705c05a2ae12c13199d",
    "before_token_sha256": "8f83893c66f6e0191f874275582d134404dfd9cb123f610a9e31f29cb0871366",
    "after_token_sha256": "ab4d1c9defa4373dc9b4617ac307c90ca12db87af18b613e3cfdf678eb3a8725",
    "edits": [
      {
        "start": 74,
        "stop": 76,
        "before": [],
        "after": [
          "    assert_equal(sample_grid(25), 4)\n",
          "    assert_equal(sample_grid(Int.MAX), 4)\n"
        ]
      }
    ]
  },
  "tests/test_light_probe_grid.mojo": {
    "before_sha256": "604e7742bd920ee0d1d084cac614d1b8e79ae482ccfe5800ee2e0715c1b80e15",
    "after_sha256": "3bb01b99a664309d51def17defa9de95871be3836d6d53e861a926c6ad4e371e",
    "before_token_sha256": "825e3e76bbd68ba7d6a8042feac59557cc383fa913519698e294c3ebfd1474a2",
    "after_token_sha256": "8cd120b26122a17e7677cf078cbaacb22f15fa282575c9b5e936d3c59b6e2e78",
    "edits": [
      {
        "start": 567,
        "stop": 579,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        bake_light_probe_grid(grid, renderer, room, assets, bounces=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        bake_light_probe_grid(grid, renderer, room, assets, bounces=Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        bake_light_probe_grid(\n",
          "            grid, renderer, room, assets, sample_count=16777217\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        bake_light_probe_grid(\n",
          "            grid, renderer, room, assets, sample_count=Int.MAX\n",
          "        )\n"
        ]
      },
      {
        "start": 586,
        "stop": 590,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = project_sh(cube, 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = project_sh(cube, Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_lines.mojo": {
    "before_sha256": "e520dbb8d5e1d24215a474911617542f9ceac5a9aaceef82de54ff85b9b130d7",
    "after_sha256": "2e81b9dff96e25e999f763d651b285bbe43161624f7c67ffd4bf705b7d17082e",
    "before_token_sha256": "d93926de1154ae887feddc53033b32f4c4027913ef0789f94ad9ae1eaeea97d6",
    "after_token_sha256": "54207b1f201fd3df138713ae3b3c87457042c08b39e41353df9ba712a3df58cc",
    "edits": [
      {
        "start": 248,
        "stop": 278,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_an_endpoint_past_an_integer_lies_past_the_image() raises:\n",
          "    var far = Float32(1e20)\n",
          "    var near = Float32(-1e20)\n",
          "    # Both ends on one side of every image: one step, and it is not here.\n",
          "    assert_equal(span_of(Vector2(far, 0.5), Vector2(far, 0.5)), 1)\n",
          "    assert_equal(major_at(Vector2(far, 0.5), Vector2(far, 0.5), 0), 1 << 62)\n",
          "    assert_equal(\n",
          "        major_at(Vector2(near, 0.5), Vector2(near, 0.5), 0), -(1 << 62)\n",
          "    )\n",
          "    assert_equal(span_of(Vector2(near, 0.5), Vector2(far, 0.5)), Int.MAX)\n",
          "    assert_false(covers(Vector2(far, 0.5), Vector2(far, 0.5), 4, 0))\n",
          "    assert_false(covers(Vector2(near, 3.5), Vector2(near, 3.5), 0, 3))\n",
          "    # A finite end still names the pixels the line crosses on the image.\n",
          "    var onto = Vector2(3.5, 0.5)\n",
          "    assert_true(covers(Vector2(near, 0.5), onto, 0, 0))\n",
          "    assert_true(covers(Vector2(near, 0.5), onto, 3, 0))\n",
          "    assert_false(covers(Vector2(near, 0.5), onto, 4, 0))\n",
          "    assert_equal(other_at(Vector2(0.5, far), Vector2(4.5, far), 2), 1 << 62)\n",
          "    var off = RenderTarget(8, 8, Color(0, 0, 0))\n",
          "    rasterize_line(end(far, 0.5), end(far, 0.5), off)\n",
          "    rasterize_line(end(near, 3.5), end(near, 3.5), off)\n",
          "    rasterize_line(end(nan[DType.float32](), 3.5), end(4.5, 3.5), off)\n",
          "    assert_equal(lit(off), 0)\n",
          "    var crossing = RenderTarget(8, 8, Color(0, 0, 0))\n",
          "    rasterize_line(end(near, 0.5), end(3.5, 0.5), crossing)\n",
          "    assert_equal(lit(crossing), 4)\n",
          "    for x in range(4):\n",
          "        assert_true(is_lit(crossing, x, 0))\n"
        ]
      }
    ]
  },
  "tests/test_lower_first_sampling.mojo": {
    "before_sha256": "9b9e4bfcb405f181126ee0ab6f5357b0829e26322612f11c8b937ab18fda963b",
    "after_sha256": "bb8739a7b0396296a175c44fae398c8c9de2b928d2f6b7236a2ccdc0ba86f756",
    "before_token_sha256": "9e1e734266b1fec04c939a0438b2ea81c84ac317f68b4321fce5769e03f21313",
    "after_token_sha256": "67102758642d61a3d1be15517734fc254bf1594a0f7414ca2ac0967d606254ea",
    "edits": [
      {
        "start": 26,
        "stop": 27,
        "before": [
          "from postprocessing.sampling import clamped_texel\n"
        ],
        "after": [
          "from postprocessing.sampling import clamped_texel, u_of, v_of\n"
        ]
      },
      {
        "start": 198,
        "stop": 222,
        "before": [],
        "after": [
          "def test_a_wide_image_clamps_one_to_its_last_pixel() raises:\n",
          "    # `Float32` of 16777217 is 16777216, so one used to stop a pixel early.\n",
          "    assert_equal(clamped_texel(1, 16777217), Float32(16777216))\n",
          "    assert_equal(clamped_texel(0, 16777217), Float32(0))\n",
          "    assert_equal(clamped_texel(2, 16777217), Float32(16777216))\n",
          "    assert_equal(clamped_texel(-1, 16777217), Float32(0))\n",
          "    assert_equal(clamped_texel(0.5, 16777217), Float32(8388608))\n",
          "\n",
          "\n",
          "def test_a_wide_frame_keeps_the_texel_center_inside() raises:\n",
          "    assert_equal(u_of(1, 4), (Float32(1) + 0.5) / Float32(4))\n",
          "    assert_equal(v_of(1, 4), 1 - (Float32(1) + 0.5) / Float32(4))\n",
          "    var wide = 8388609\n",
          "    assert_equal(\n",
          "        u_of(wide - 1, wide),\n",
          "        Float32((Float64(wide - 1) + 0.5) / Float64(wide)),\n",
          "    )\n",
          "    var count = 16777217\n",
          "    assert_equal(\n",
          "        v_of(count - 1, count),\n",
          "        Float32(1 - (Float64(count - 1) + 0.5) / Float64(count)),\n",
          "    )\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_lwo.mojo": {
    "before_sha256": "cd3ac97653f100d1d99f64600ef80f09014ffeffbe5121926e57f4db5390187e",
    "after_sha256": "150c794520852a81c5f6063f86472c94f4cd47f6e48850013bd7b0bd256acbc9",
    "before_token_sha256": "b4675d2fc41205b64e82c86145f001360c3024e9563c252423d37f2bab603026",
    "after_token_sha256": "56112c7c1ed81bd83a42bef0b0bc1977f062b642f5bb5dbb5a23460af33679e3",
    "edits": [
      {
        "start": 26,
        "stop": 28,
        "before": [],
        "after": [
          "    _split_indices,\n",
          "    _split_material_indices,\n"
        ]
      },
      {
        "start": 385,
        "stop": 437,
        "before": [],
        "after": [
          "def test_a_polygon_corner_count_that_does_not_fit_is_refused() raises:\n",
          "    var indices = List[Float64]()\n",
          "    indices.append(0)\n",
          "    indices.append(1)\n",
          "    indices.append(2)\n",
          "    var triangle = List[Float64]()\n",
          "    triangle.append(3)\n",
          "    var split = _split_indices(indices, triangle)\n",
          "    assert_equal(len(split), 3)\n",
          "    assert_equal(split[0], 0)\n",
          "    assert_equal(split[2], 2)\n",
          "    var huge = List[Float64]()\n",
          "    huge.append(1e20)\n",
          "    huge.append(3)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = _split_indices(indices, huge)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = _split_material_indices(huge, indices)\n",
          "    var negative = List[Float64]()\n",
          "    negative.append(-1)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = _split_indices(indices, negative)\n",
          "    var fraction = List[Float64]()\n",
          "    fraction.append(3.5)\n",
          "    with assert_raises(contains=\"whole number\"):\n",
          "        _ = _split_indices(indices, fraction)\n",
          "    var wide = List[Float64]()\n",
          "    wide.append(5)\n",
          "    with assert_raises(contains=\"past its indices\"):\n",
          "        _ = _split_indices(indices, wide)\n",
          "    # A vertex index of 1e20 is not a point. `Int` of it is the minimum\n",
          "    # integer, which the later range check keeps.\n",
          "    var named = List[Float64]()\n",
          "    named.append(1e20)\n",
          "    named.append(1)\n",
          "    named.append(2)\n",
          "    with assert_raises(contains=\"index does not fit\"):\n",
          "        _ = _split_indices(named, triangle)\n",
          "    var backwards = List[Float64]()\n",
          "    backwards.append(-1)\n",
          "    backwards.append(0)\n",
          "    backwards.append(1)\n",
          "    with assert_raises(contains=\"index does not fit\"):\n",
          "        _ = _split_indices(backwards, triangle)\n",
          "    var half = List[Float64]()\n",
          "    half.append(1.5)\n",
          "    half.append(0)\n",
          "    half.append(1)\n",
          "    with assert_raises(contains=\"index must be a whole number\"):\n",
          "        _ = _split_indices(half, triangle)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_marching_cubes.mojo": {
    "before_sha256": "12835f85ca10ec431e85a9c877618fa922616d1396a51fd3ae95a76bb107396b",
    "after_sha256": "04ae8bf6e0e0451ef0b2c0a291c20e4531c996b70b468a3776c56ae58c48b36f",
    "before_token_sha256": "ad55f302d8b3cb28297041a460aa017e41bfdd6e70c98658382c6be5559ae360",
    "after_token_sha256": "3ea3e889d70aec5ddf1db4911a40836f97407f4799b672f91e2dee6b816776c9",
    "edits": [
      {
        "start": 202,
        "stop": 204,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = MarchingCubes(1 << 21)\n"
        ]
      }
    ]
  },
  "tests/test_materialx.mojo": {
    "before_sha256": "fe2cb1f26165fb308f432ab6f8d1927b11d99b24b9b4b4f7bce3b2c0af0a364b",
    "after_sha256": "881c81e61ce3456328fe5c41750aadc3d8d2851cbb21041f83727771fbf2a052",
    "before_token_sha256": "05f164f515c05204b667286a5d7652bdd354c3bf54dedd45ba394c659adf79b5",
    "after_token_sha256": "446800ba6ed013fcb8fbbce826e359a94f71efc11dbe0c0df48f52c88d6b91b7",
    "edits": [
      {
        "start": 901,
        "stop": 945,
        "before": [],
        "after": [
          "        + '<input name=\"index\" type=\"integer\" value=\"1e20\" /></extract>'\n",
          "        + tail,\n",
          "        \"extract reads a component zero to three\",\n",
          "    )\n",
          "    refused(\n",
          "        graph\n",
          "        + '<extract name=\"n\" type=\"float\">'\n",
          "        + '<input name=\"in\" type=\"vector3\" value=\"1, 2, 3\" />'\n",
          "        + '<input name=\"index\" type=\"integer\" value=\"1.5\" /></extract>'\n",
          "        + tail,\n",
          "        \"extract reads a component zero to three\",\n",
          "    )\n",
          "    refused(\n",
          "        graph\n",
          "        + '<fractal3d name=\"n\" type=\"float\">'\n",
          "        + '<input name=\"octaves\" type=\"integer\" value=\"1e20\" /></fractal3d>'\n",
          "        + tail,\n",
          "        \"1024\",\n",
          "    )\n",
          "    refused(\n",
          "        graph\n",
          "        + '<fractal3d name=\"n\" type=\"float\">'\n",
          "        + '<input name=\"octaves\" type=\"integer\" value=\"2000\" /></fractal3d>'\n",
          "        + tail,\n",
          "        \"1024\",\n",
          "    )\n",
          "    refused(\n",
          "        graph\n",
          "        + '<fractal3d name=\"n\" type=\"float\">'\n",
          "        + '<input name=\"octaves\" type=\"integer\" value=\"3.5\" /></fractal3d>'\n",
          "        + tail,\n",
          "        \"1024\",\n",
          "    )\n",
          "    refused(\n",
          "        graph\n",
          "        + '<fractal3d name=\"n\" type=\"float\">'\n",
          "        + '<input name=\"octaves\" type=\"integer\" value=\"-1\" /></fractal3d>'\n",
          "        + tail,\n",
          "        \"1024\",\n",
          "    )\n",
          "    refused(\n",
          "        graph\n",
          "        + '<extract name=\"n\" type=\"float\">'\n",
          "        + '<input name=\"in\" type=\"vector3\" value=\"1, 2, 3\" />'\n"
        ]
      }
    ]
  },
  "tests/test_more_helpers.mojo": {
    "before_sha256": "9d72137cb7f17a8885f647ab0fffe2ef8e4a2ea79ade920633312f2051af9385",
    "after_sha256": "841ce5897f51a5ade4eeb0a23b9501c387ee2ba15e457f3d0cbf6d0532029400",
    "before_token_sha256": "6708cf63839d256cbd28a6abfba010eadbfb0dda64484c2bd53a8c9d92d2e9b7",
    "after_token_sha256": "68dae8b87c11af49a00b503a4dc47b1fbd8f727b2d46dc08fc53532f69364aad",
    "edits": [
      {
        "start": 245,
        "stop": 251,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = polar_grid_helper(meters(1), 16777217, 0, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = polar_grid_helper(meters(1), 0, 16777217, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = polar_grid_helper(meters(1), 0, 0, Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_morph.mojo": {
    "before_sha256": "db64c9d38de391b1535013e58bd3dfd304c473a5841318bed2fa4fb55c88eb95",
    "after_sha256": "b7096c734cfd5655d0371a53340eedd7f979e02198aca3d05bf90722b1b3b1e7",
    "before_token_sha256": "76ad929980b0f45b22606bf0c3b6b77da760a013b5be8f55093bc34fd7744c94",
    "after_token_sha256": "d8e6f35912ad78153b981d13a9f4ad416d2aa4eaa9eebd5827bbeba6fe0a3e85",
    "edits": [
      {
        "start": 422,
        "stop": 431,
        "before": [],
        "after": [
          "    assert_equal(worn.get(16777216), 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        worn.set(16777216, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        worn.set(Int.MAX, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = MorphInfluences(count=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = MorphInfluences(count=Int.MAX)\n"
        ]
      }
    ]
  },
  "tests/test_object_json.mojo": {
    "before_sha256": "24730cef15efc02eabe61ed63b763d064a04ccbe6c5a75af49760d0346f58c56",
    "after_sha256": "0091bdf6ecb03012a7b4d984a60f56b22330cc5d3df02d10459fe9cc92844a85",
    "before_token_sha256": "6416aef8065d1b1787ac210870cdb593793c36b8a6b30751b8f4023ba020ea66",
    "after_token_sha256": "307efadf57f695347011efb77fb4addd0f0e56ca8c7506223a374ef34bc6e93d",
    "edits": [
      {
        "start": 74,
        "stop": 76,
        "before": [],
        "after": [
          "    shadow_map_size,\n",
          "    wrap_number,\n"
        ]
      },
      {
        "start": 1489,
        "stop": 1494,
        "before": [],
        "after": [
          "    # `Int` of 1e20 is not that number. The cast used to run before the\n",
          "    # range check.\n",
          "    _refuses(_textured(',\"wrap\":[1e20,1000]'))\n",
          "    _refuses(_textured(',\"wrap\":[2000,1000]'))\n",
          "    _refuses(_textured(',\"wrap\":[1000.5,1000]'))\n"
        ]
      },
      {
        "start": 1657,
        "stop": 1669,
        "before": [],
        "after": [
          "    assert_equal(wrap_number(1000), 1000)\n",
          "    assert_equal(shadow_map_size(2048), 2048)\n",
          "    assert_equal(shadow_map_size(1), 1)\n",
          "    assert_equal(shadow_map_size(8192), 8192)\n",
          "    with assert_raises(contains=\"8192\"):\n",
          "        _ = shadow_map_size(0)\n",
          "    with assert_raises(contains=\"8192\"):\n",
          "        _ = shadow_map_size(10000)\n",
          "    with assert_raises(contains=\"8192\"):\n",
          "        _ = shadow_map_size(Float32(1e20))\n",
          "    with assert_raises(contains=\"8192\"):\n",
          "        _ = shadow_map_size(512.5)\n"
        ]
      },
      {
        "start": 1670,
        "stop": 1676,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"wrap\"):\n",
          "        _ = wrap_number(Float32(1e20))\n",
          "    with assert_raises(contains=\"wrap\"):\n",
          "        _ = wrap_number(2000)\n",
          "    with assert_raises(contains=\"wrap\"):\n",
          "        _ = wrap_number(1000.5)\n"
        ]
      },
      {
        "start": 1681,
        "stop": 1683,
        "before": [],
        "after": [
          "    with assert_raises():\n",
          "        _ = wrap_of(999)\n"
        ]
      },
      {
        "start": 1836,
        "stop": 1853,
        "before": [],
        "after": [
          "    _refuses(\n",
          "        '\"object\":{\"uuid\":\"a\",\"type\":\"DirectionalLight\",\"shadow\":'\n",
          "        + '{\"mapSize\":[1e20,1e20]}}'\n",
          "    )\n",
          "    _refuses(\n",
          "        '\"object\":{\"uuid\":\"a\",\"type\":\"DirectionalLight\",\"shadow\":'\n",
          "        + '{\"mapSize\":[10000,10000]}}'\n",
          "    )\n",
          "    _refuses(\n",
          "        '\"object\":{\"uuid\":\"a\",\"type\":\"DirectionalLight\",\"shadow\":'\n",
          "        + '{\"mapSize\":[512.5,512.5]}}'\n",
          "    )\n",
          "    var sized = _read(\n",
          "        '\"object\":{\"uuid\":\"a\",\"type\":\"DirectionalLight\",\"shadow\":'\n",
          "        + '{\"mapSize\":[8192,8192]}}'\n",
          "    )\n",
          "    assert_equal(sized[0].lights[0].shadow.map_size, 8192)\n"
        ]
      },
      {
        "start": 2081,
        "stop": 2089,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"version 4\"):\n",
          "        _ = read_object_json(\n",
          "            '{\"metadata\":{\"version\":5,\"type\":\"Object\"}}', scene, assets\n",
          "        )\n",
          "    with assert_raises(contains=\"version 4\"):\n",
          "        _ = read_object_json(\n",
          "            '{\"metadata\":{\"version\":1e20,\"type\":\"Object\"}}', scene, assets\n",
          "        )\n"
        ]
      }
    ]
  },
  "tests/test_object_json_objects.mojo": {
    "before_sha256": "0bb476d48242f65dc22f20031806be1e76fe2d1e96ccb995e964122a4bc68f6c",
    "after_sha256": "80c7e81e459eef882af58454c169db4e7a285d8e35589f4d068b8033dd6d732c",
    "before_token_sha256": "1be1796706a71c93e92f3dfdb079f29da848a1ba60bfdb9adab908d46d37b8d0",
    "after_token_sha256": "6c25f787998d51bc2e00d69cb99a4c6149ed69282f2e04148133a3c27ee666c5",
    "edits": [
      {
        "start": 21,
        "stop": 27,
        "before": [
          "from exporters.object_json import object_to_json, object_uuid\n"
        ],
        "after": [
          "from exporters.object_json import (\n",
          "    _instance_texture_side,\n",
          "    _matrix_texture_side,\n",
          "    object_to_json,\n",
          "    object_uuid,\n",
          ")\n"
        ]
      },
      {
        "start": 942,
        "stop": 957,
        "before": [],
        "after": [
          "def test_a_batch_texture_side_matches_three_js_and_fits() raises:\n",
          "    assert_equal(_matrix_texture_side(0), 4)\n",
          "    assert_equal(_matrix_texture_side(1), 4)\n",
          "    assert_equal(_matrix_texture_side(3), 4)\n",
          "    assert_equal(_matrix_texture_side(5), 8)\n",
          "    assert_equal(_instance_texture_side(0), 0)\n",
          "    assert_equal(_instance_texture_side(1), 1)\n",
          "    assert_equal(_instance_texture_side(3), 2)\n",
          "    assert_equal(_instance_texture_side(5), 3)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = _matrix_texture_side(9007199254740993)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = _instance_texture_side(Int.MAX)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_oit.mojo": {
    "before_sha256": "0ab3d557dcefebf0282c1dbbff72511886b5de327abb27d7dfac67e6435e05a8",
    "after_sha256": "52f4b3c5c618e8ee3e5178c429e28e1fcc742f9a95f740a7d995003da6a50ea8",
    "before_token_sha256": "9540ac107118083f125c639c8c516a48a1e464c4e97ca8d9caa3df4ee90cfc1c",
    "after_token_sha256": "99fd6b14da5175e7cc4a044b9c3e844b68b982c33300e14ccbeaf554974e9027",
    "edits": [
      {
        "start": 273,
        "stop": 282,
        "before": [],
        "after": [
          "def test_a_wide_frame_snaps_from_its_real_center() raises:\n",
          "    var corners = List[RasterVertex]()\n",
          "    corners.append(RasterVertex(0, 1, 0, 1, FloatColor(0, 0, 0, 1)))\n",
          "    corners.append(RasterVertex(1.5, 1, 0, 1, FloatColor(0, 0, 0, 1)))\n",
          "    snap_to_pixels(corners, 16777217, 4)\n",
          "    assert_equal(corners[0].x, 0.5)\n",
          "    assert_equal(corners[1].x, 1.5)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_person_generator.mojo": {
    "before_sha256": "e812c0ec178b21063b8ec22432ba2bbb960abc2d8b01d0493b689eafc16d36d5",
    "after_sha256": "24ab307ad21d08e3ff2798a00954e76b4cc5f897e18a4db0a475f57e7a1b2122",
    "before_token_sha256": "d647f8b49a006996892ef18a7fbaf8e094134d7b8eb6c3e0acaf3f288f56d7dd",
    "after_token_sha256": "ca5941cc981ade54e03919168a66f45f9bbccbf738711ae0bee9e0058d575d90",
    "edits": [
      {
        "start": 38,
        "stop": 39,
        "before": [
          "from std.math import pi\n"
        ],
        "after": [
          "from std.math import inf, nan, pi\n"
        ]
      },
      {
        "start": 158,
        "stop": 165,
        "before": [],
        "after": [
          "    for bad in [\n",
          "        nan[DType.float32](),\n",
          "        inf[DType.float32](),\n",
          "        -inf[DType.float32](),\n",
          "    ]:\n",
          "        with assert_raises(contains=\"finite\"):\n",
          "            _ = person_geometry(WALK, Length(bad, METER))\n"
        ]
      }
    ]
  },
  "tests/test_pointrule.mojo": {
    "before_sha256": "f763142efb42dcec0ab0858b64ef3b73e77b58a0f3de028cd2b1929804e3f07d",
    "after_sha256": "69d58ee308cd207eeaa491ed006e9d70809c3353ffbe25003b2b1d7a5a463c00",
    "before_token_sha256": "5ec8aa29cb9655064485efed0bfae6b0881fc2dd4a7ef2ca043ea0ba4f840c86",
    "after_token_sha256": "1dd02480b13385d2d9ad3be204c49286c7c5f663c7a7f6d6a189db67c7b2cbfe",
    "edits": [
      {
        "start": 243,
        "stop": 263,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_center_past_an_integer_lies_past_the_image() raises:\n",
          "    # The ordinary square still rounds outward by at most one pixel.\n",
          "    assert_equal(first_covered(4.5, 3), 2)\n",
          "    assert_equal(last_covered(4.5, 3), 6)\n",
          "    # Past 2^63 the cast is not the coordinate. The walk stays off the image.\n",
          "    assert_equal(first_covered(Float32(1e20), 1), Int.MAX)\n",
          "    assert_equal(last_covered(Float32(1e20), 1), Int.MAX)\n",
          "    assert_equal(first_covered(Float32(-1e20), 1), Int.MIN)\n",
          "    assert_equal(last_covered(Float32(-1e20), 1), Int.MIN)\n",
          "    assert_equal(first_covered(nan[DType.float32](), 1), Int.MAX)\n",
          "    assert_equal(last_covered(nan[DType.float32](), 1), Int.MAX)\n",
          "    assert_equal(first_covered(inf[DType.float32](), 1), Int.MAX)\n",
          "    assert_equal(last_covered(-inf[DType.float32](), 1), Int.MIN)\n",
          "    var target = RenderTarget(8, 8, Color(0, 0, 0))\n",
          "    rasterize_point(dot(Float32(1e20), 4.5, 3), target)\n",
          "    rasterize_point(dot(Float32(-1e20), 4.5, 3), target)\n",
          "    rasterize_point(dot(4.5, nan[DType.float32](), 3), target)\n",
          "    assert_equal(lit(target), 0)\n"
        ]
      }
    ]
  },
  "tests/test_postprocessing.mojo": {
    "before_sha256": "1bfc71a6b103911c5cb2fd144baf6b8003ce12fb2611b0bb2ff7231da3094dee",
    "after_sha256": "0a6502a35bcfc78be41b2f479de621378866f4c5312d249bc8c857c66e7b971c",
    "before_token_sha256": "56a7a6dd2ebfeaa74272c0e17434055b9b5d2b1a7f8f4febb89e1b8df89d9b98",
    "after_token_sha256": "50781afbf8be9123804663d8925c70b83f7b327f0732e3f38ae9a577e4c01fce",
    "edits": [
      {
        "start": 953,
        "stop": 965,
        "before": [],
        "after": [
          "    # A sigma of 1e20 is not a kernel width. The ceil used to become a\n",
          "    # garbage index, and the read fell off an empty list.\n",
          "    var far = bloom_kernel(Float32(1e20), 25)\n",
          "    var far_total = Float32(0)\n",
          "    for at in range(25):\n",
          "        far_total += far[at]\n",
          "    assert_almost_equal(far_total, Float32(1), atol=1e-5)\n",
          "    var low = bloom_kernel(-Float32(1e20), 25)\n",
          "    var low_total = Float32(0)\n",
          "    for at in range(25):\n",
          "        low_total += low[at]\n",
          "    assert_almost_equal(low_total, Float32(1), atol=1e-5)\n"
        ]
      }
    ]
  },
  "tests/test_postprocessing_antialias.mojo": {
    "before_sha256": "06cd3fdf44f5dee0045483de10ac5c5be360137a1f9d3e87d7325c40464cdc1e",
    "after_sha256": "6ca94e7974615306e12613c9bafb1006580419a4c8b83bed3223a8527d4c1261",
    "before_token_sha256": "08c2ad4d0e8a7c3d7bc616a75701f7185b111e35bdda4421fce9985cbc7b2862",
    "after_token_sha256": "d22bffbce86281c8c047327def393e10bf0750e974ad54f46beeb5ee0be34659",
    "edits": [
      {
        "start": 754,
        "stop": 767,
        "before": [],
        "after": [
          "def test_an_smaa_frame_must_fit() raises:\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = EdgeMap(0, 1)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = EdgeMap(1, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = EdgeMap(1 << 32, 1 << 32)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = BlendWeights(0, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = BlendWeights(1 << 32, 1 << 32)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_postprocessing_effects.mojo": {
    "before_sha256": "2ae729dc3887905fee86008a69eb983ddffdd855a0d2c94e5078075991f4ece0",
    "after_sha256": "06b4800dfb1f4292dd112351e1cdba83f6fbc491a4b82ea42c820c8b9cab658f",
    "before_token_sha256": "a348e47c0905152e150672380e368cc9ecebc8025637ebadad96cfdc40386183",
    "after_token_sha256": "93579b6fb0cac942ac758ee26e3e18d3ea94fdb78cb1c7fc12cdb3bbf012c964",
    "edits": [
      {
        "start": 52,
        "stop": 53,
        "before": [],
        "after": [
          "    _bokeh2_taps_fit,\n"
        ]
      },
      {
        "start": 99,
        "stop": 100,
        "before": [],
        "after": [
          "    texture_overlay,\n"
        ]
      },
      {
        "start": 257,
        "stop": 263,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        _ = glitch_pass(-1)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        _ = glitch_pass(4097)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        _ = glitch_pass(Int.MAX)\n"
        ]
      },
      {
        "start": 419,
        "stop": 434,
        "before": [],
        "after": [
          "    var huge = GlitchSettings(Int.MAX, 3)\n",
          "    assert_equal(huge.trigger, 120)\n",
          "    assert_equal(huge.state, 0)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        check_glitch(huge)\n",
          "    var negative = GlitchSettings(-1, 3)\n",
          "    assert_equal(negative.state, 0)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        check_glitch(negative)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        _ = glitch_heightmap(-1, 7)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        _ = glitch_heightmap(4097, 7)\n",
          "    with assert_raises(contains=\"glitch map\"):\n",
          "        _ = glitch_heightmap(Int.MAX, 7)\n"
        ]
      },
      {
        "start": 951,
        "stop": 961,
        "before": [],
        "after": [
          "def test_a_texture_overlay_must_fit() raises:\n",
          "    var texture = data_texture(1, 1, [1.0, 0.0, 0.0, 1.0])\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = texture_overlay(texture, 0, 1)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = texture_overlay(texture, 1, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = texture_overlay(texture, 1 << 32, 1 << 32)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 1106,
        "stop": 1115,
        "before": [],
        "after": [
          "    # A count the rings cannot finish keeps the pixel.\n",
          "    var huge = settings\n",
          "    huge.rings = Int.MAX\n",
          "    var held = bokeh2_pixel(view, depth, 12, 5, huge)\n",
          "    assert_almost_equal(held.r, frame.colors[5 * WIDTH + 12].r, atol=1e-5)\n",
          "    huge.rings = 3\n",
          "    huge.samples = 16777217\n",
          "    held = bokeh2_pixel(view, depth, 12, 5, huge)\n",
          "    assert_almost_equal(held.r, frame.colors[5 * WIDTH + 12].r, atol=1e-5)\n"
        ]
      },
      {
        "start": 1175,
        "stop": 1193,
        "before": [],
        "after": [
          "    var wide = Bokeh2Settings()\n",
          "    wide.rings = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_bokeh2(wide)\n",
          "    wide.rings = 3\n",
          "    wide.samples = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_bokeh2(wide)\n",
          "    wide.rings = 100\n",
          "    wide.samples = 10000\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_bokeh2(wide)\n",
          "    wide.rings = 1\n",
          "    wide.samples = 16777216\n",
          "    check_bokeh2(wide)\n",
          "    # A count below one fits, because that walk does not run.\n",
          "    assert_true(_bokeh2_taps_fit(0, 5))\n",
          "    assert_true(_bokeh2_taps_fit(3, 0))\n"
        ]
      }
    ]
  },
  "tests/test_postprocessing_passes.mojo": {
    "before_sha256": "e2493104d4df57905b1174a69a1e93340f4964eacbbc6f2386dd644b6f6bbc68",
    "after_sha256": "82b27e3dd255307f211c3a5ed1eef890432274b5ff54aa1df59386917bfa4495",
    "before_token_sha256": "695d56d902d3dc1edf7e18c9b6ce79a51a02b0d61ea26b39693ac4c1f6d2c252",
    "after_token_sha256": "b8411d01fb188dfd54ac8ccc702de049322aadc2d9b904405ecec145499caf29",
    "edits": [
      {
        "start": 70,
        "stop": 71,
        "before": [],
        "after": [
          "    gtao_grid_side,\n"
        ]
      },
      {
        "start": 579,
        "stop": 587,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = cube_overlay(assets.cube_textures.get(sky), camera, scene, 0, 1)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = cube_overlay(assets.cube_textures.get(sky), camera, scene, 1, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = cube_overlay(\n",
          "            assets.cube_textures.get(sky), camera, scene, 1 << 32, 1 << 32\n",
          "        )\n"
        ]
      },
      {
        "start": 685,
        "stop": 702,
        "before": [],
        "after": [
          "    var wide = GtaoSettings()\n",
          "    wide.samples = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_gtao(wide)\n",
          "    wide.samples = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_gtao(wide)\n",
          "    wide = GtaoSettings()\n",
          "    wide.denoise_samples = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_gtao(wide)\n",
          "    wide.denoise_samples = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_gtao(wide)\n",
          "    wide.samples = 16777216\n",
          "    wide.denoise_samples = 16777216\n",
          "    check_gtao(wide)\n"
        ]
      },
      {
        "start": 722,
        "stop": 735,
        "before": [],
        "after": [
          "    assert_equal(len(magic_square(0)), 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = magic_square(-1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = magic_square(4096)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = magic_square(Int.MAX - 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = magic_square(Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = gtao_noise(4096)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = gtao_noise(Int.MAX)\n"
        ]
      },
      {
        "start": 742,
        "stop": 746,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = denoise_noise(1, 4097)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = denoise_noise(1, Int.MAX)\n"
        ]
      },
      {
        "start": 754,
        "stop": 758,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = denoise_disk(Int.MAX, 2, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = denoise_disk(16777217, 1, 1)\n"
        ]
      },
      {
        "start": 806,
        "stop": 809,
        "before": [],
        "after": [
          "    var huge = settings\n",
          "    huge.samples = Int.MAX\n",
          "    near(gtao_occlusion(sky, up, noise, 0, 0, huge), 1)\n"
        ]
      },
      {
        "start": 826,
        "stop": 828,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = gtao_occlusion(wall, up, still, 0, 0, huge)\n"
        ]
      },
      {
        "start": 854,
        "stop": 884,
        "before": [],
        "after": [
          "    _ = ao^\n",
          "\n",
          "\n",
          "def test_gtao_noise_side_fits_the_list() raises:\n",
          "    var wall = DepthView(\n",
          "        List[Float32](length=1, fill=-0.5),\n",
          "        1,\n",
          "        1,\n",
          "        Matrix4(),\n",
          "        meters(0.1),\n",
          "        meters(20),\n",
          "    )\n",
          "    var up = List[Vector3](length=1, fill=Vector3(0, 0, 1))\n",
          "    var settings = GtaoSettings()\n",
          "    with assert_raises(contains=\"needs a texel\"):\n",
          "        _ = gtao_occlusion(wall, up, List[FloatColor](), 0, 0, settings)\n",
          "    var ao = List[FloatColor](length=1, fill=FloatColor(0.5, 0.5, 0.5, 1))\n",
          "    with assert_raises(contains=\"needs a texel\"):\n",
          "        _ = gtao_denoise(\n",
          "            LightView(ao, 1, 1),\n",
          "            wall,\n",
          "            up,\n",
          "            List[Float32](),\n",
          "            List[Vector3](),\n",
          "            0,\n",
          "            0,\n",
          "            settings,\n",
          "        )\n",
          "    # `Float32` of this length rounds up to a square one texel past it.\n",
          "    assert_equal(gtao_grid_side(16785408), 4096)\n"
        ]
      }
    ]
  },
  "tests/test_postprocessing_screen_space.mojo": {
    "before_sha256": "a8b41842887016a0e5759c53a474e727c7f4a51a95ceb30ac66848e5fba97a99",
    "after_sha256": "df1f061413ac8b7bc82e1eb7f6c5c8ab9f685dcf5ce1005f09e6db22202c7e3e",
    "before_token_sha256": "0371ecc42d846788aa53729eeda9dfa3e8214bd2fa7cc33c37061c84528d2cca",
    "after_token_sha256": "051fca47ffe6f9c38cee31be2d0d361e7b50189141db425f1a29351366d8ab2b",
    "edits": [
      {
        "start": 68,
        "stop": 69,
        "before": [],
        "after": [
          "    _ssr_max_step,\n"
        ]
      },
      {
        "start": 329,
        "stop": 337,
        "before": [],
        "after": [
          "    bad.kernel_size = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_ssao(bad)\n",
          "    bad.kernel_size = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_ssao(bad)\n",
          "    bad.kernel_size = 16777216\n",
          "    check_ssao(bad)\n"
        ]
      },
      {
        "start": 384,
        "stop": 393,
        "before": [],
        "after": [
          "    bad = SaoSettings()\n",
          "    bad.blur_radius = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_sao(bad)\n",
          "    bad.blur_radius = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_sao(bad)\n",
          "    bad.blur_radius = 16777216\n",
          "    check_sao(bad)\n"
        ]
      },
      {
        "start": 653,
        "stop": 657,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssao_kernel(16777217, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssao_kernel(Int.MAX, 1)\n"
        ]
      },
      {
        "start": 713,
        "stop": 724,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_screen_space_frame_must_fit() raises:\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = ssao_blur(List[Float32](), 0, 1)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = ssr_blur(List[FloatColor](), 1, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssao_blur(List[Float32](), 1 << 32, 1 << 32)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssr_blur(List[FloatColor](), 1 << 32, 1 << 32)\n"
        ]
      },
      {
        "start": 821,
        "stop": 827,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"negative\"):\n",
          "        _ = blur_weights(-1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = blur_weights(16777217, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = blur_weights(Int.MAX, 1)\n"
        ]
      },
      {
        "start": 1029,
        "stop": 1039,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_wide_frame_keeps_its_diagonal() raises:\n",
          "    # Two by two is `floor(sqrt(8))`.\n",
          "    assert_equal(_ssr_max_step(2, 2), Float32(2))\n",
          "    # `4000000000` squared does not fit in an integer. The diagonal is the\n",
          "    # width itself.\n",
          "    assert_equal(_ssr_max_step(4000000000, 1), Float32(4000000000))\n",
          "    # Two sides of `Int.MAX` have a diagonal past 2^63.\n",
          "    assert_true(_ssr_max_step(Int.MAX, Int.MAX) > Float32(1e19))\n"
        ]
      }
    ]
  },
  "tests/test_postprocessing_shaders.mojo": {
    "before_sha256": "5624e8d0fa06d3f696f13ec5887c2a1ffd1053f39a6fb59cedcb8d14963e04f6",
    "after_sha256": "ee203ddbbb10bb3a354bd0039a8968b3bd30f31cb4e2500dc408d97dd67270d0",
    "before_token_sha256": "ab0ad8a90ba6e753451766991e6db1fd0f34694a0ea780649c6ab20fd9ec1204",
    "after_token_sha256": "895b12c8a24e50672b3addbc2ec7e61da901c1f897e5cdc66e7dbe6ce1ba1833",
    "edits": [
      {
        "start": 896,
        "stop": 904,
        "before": [],
        "after": [
          "    # A Float32 product of 16777217 is 16777216, one pixel short.\n",
          "    assert_equal(god_rays_size(16777217, 1), 16777217)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = god_rays_size(Int.MAX, 1)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = god_rays_size(Int.MIN, 1.5)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = god_rays_size(1, nan[DType.float32]())\n"
        ]
      }
    ]
  },
  "tests/test_progressive_light_map.mojo": {
    "before_sha256": "5e944d84ed8a59ea055395dfbfb5de21b836b6442395d58f825b0fb4ef5d0b5a",
    "after_sha256": "c1c1a647b8836fc91160abe02ac078d736521df0128180c23de6fc5b7e8b21f5",
    "before_token_sha256": "8ee910da002e34c2214ed18d1a6aa986a08bbfe0b26fcc89439c077460d40c39",
    "after_token_sha256": "1807b06dbd58ef82729ac7dc889becbedd64fafe477262a8cef0306522fee5f7",
    "edits": [
      {
        "start": 93,
        "stop": 95,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ProgressiveLightMap(assets, 1 << 31)\n"
        ]
      }
    ]
  },
  "tests/test_rasterizer.mojo": {
    "before_sha256": "c9b8ef35771ba133ae0d6fffee64bc356be659d36319b0317093f07991aa9ef6",
    "after_sha256": "2b625bee444cebe0d840222e78c1d6af1d808e5160bb7d814169bb77da541f06",
    "before_token_sha256": "0a82afc332fe35999429acd3fda68168d25d23b5530fdee00279392984042428",
    "after_token_sha256": "a38d73bd7cbf71eccf7da8bd1eb85cffc1cc712bce187fb469f8cd40c768a9f7",
    "edits": [
      {
        "start": 87,
        "stop": 88,
        "before": [],
        "after": [
          "    _bounds,\n"
        ]
      },
      {
        "start": 127,
        "stop": 128,
        "before": [],
        "after": [
          "    _rows_of,\n"
        ]
      },
      {
        "start": 312,
        "stop": 365,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_coordinate_past_an_integer_lies_past_the_image() raises:\n",
          "    var background = Color(20, 24, 32)\n",
          "    var fb = Framebuffer(4, 4, background)\n",
          "    var off = Triangle(\n",
          "        Vector2(Float32(1e20), 0),\n",
          "        Vector2(Float32(1e20), 4),\n",
          "        Vector2(Float32(1e20), 2),\n",
          "    )\n",
          "    rasterize(off, fb, Color(255, 0, 0))\n",
          "    var missing = Triangle(\n",
          "        Vector2(nan[DType.float32](), 1), Vector2(1, 1), Vector2(1, 3)\n",
          "    )\n",
          "    rasterize(missing, fb, Color(255, 0, 0))\n",
          "    var before = Triangle(\n",
          "        Vector2(Float32(-1e20), 0),\n",
          "        Vector2(Float32(-1e20), 4),\n",
          "        Vector2(Float32(-1e20), 2),\n",
          "    )\n",
          "    rasterize(before, fb, Color(255, 0, 0))\n",
          "    for y in range(4):\n",
          "        for x in range(4):\n",
          "            assert_equal(fb.get_pixel(x, y).r, background.r)\n",
          "    # Corners that are not numbers bound no column: the box is empty.\n",
          "    var lost = nan[DType.float32]()\n",
          "    var box = _bounds(\n",
          "        Triangle(Vector2(lost, lost), Vector2(lost, lost), Vector2(lost, lost)),\n",
          "        4,\n",
          "        4,\n",
          "    )\n",
          "    assert_true(box.left > box.right)\n",
          "    var corners = List[RasterVertex]()\n",
          "    corners.append(RasterVertex(0, Float32(1e20), 0, 1, FloatColor(0, 0, 0)))\n",
          "    corners.append(RasterVertex(0, Float32(1e20), 0, 1, FloatColor(0, 0, 0)))\n",
          "    var below = _rows_of(corners, 2, 2)\n",
          "    assert_equal(below[0], Int.MAX)\n",
          "    assert_equal(below[1], Int.MAX)\n",
          "    var above = List[RasterVertex]()\n",
          "    above.append(RasterVertex(0, Float32(-1e20), 0, 1, FloatColor(0, 0, 0)))\n",
          "    above.append(RasterVertex(0, Float32(-1e20), 0, 1, FloatColor(0, 0, 0)))\n",
          "    var high = _rows_of(above, 2, 2)\n",
          "    assert_equal(high[0], Int.MIN)\n",
          "    assert_equal(high[1], Int.MIN)\n",
          "    var near = List[RasterVertex]()\n",
          "    near.append(RasterVertex(0, 3.2, 0, 1, FloatColor(0, 0, 0)))\n",
          "    near.append(RasterVertex(0, 5.2, 0, 1, FloatColor(0, 0, 0)))\n",
          "    var band = _rows_of(near, 2, 0)\n",
          "    assert_equal(band[0], 3)\n",
          "    assert_equal(band[1], 6)\n",
          "    var wide = _rows_of(near, 2, 2)\n",
          "    assert_equal(wide[0], 1)\n",
          "    assert_equal(wide[1], 8)\n"
        ]
      }
    ]
  },
  "tests/test_raycaster.mojo": {
    "before_sha256": "ec1646ade9273567ccdc8bdf7ddb03981ddbaf39c94bd6b0a08ad3f9364b243b",
    "after_sha256": "92d03f6a7d32ff43d28950a6dfe84d40611eea14cdb01dac2a2b9823f639f98f",
    "before_token_sha256": "504eb50c7e1c142ab7456714e7765fc836a36e08a80c6226394eb139c540865b",
    "after_token_sha256": "a50e98a34d5843b0e0a959cf3943c477ae9d0dee330e5f585d69eaaa87f512df",
    "edits": [
      {
        "start": 225,
        "stop": 241,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_wide_image_keeps_the_last_pixel_inside() raises:\n",
          "    var scene = Scene()\n",
          "    var camera = square_camera()\n",
          "    var wide = 16777217\n",
          "    var last = down_z()\n",
          "    last.set_from_pixel(Float32(wide - 1), 0.5, wide, 100, camera, scene)\n",
          "    var edge = down_z()\n",
          "    edge.set_from_camera(Vector2(1, 0), camera, scene)\n",
          "    assert_true(last.ray.direction.x < edge.ray.direction.x)\n",
          "    var tall = down_z()\n",
          "    tall.set_from_pixel(0.5, Float32(wide - 1), 100, wide, camera, scene)\n",
          "    var bottom = down_z()\n",
          "    bottom.set_from_camera(Vector2(0, -1), camera, scene)\n",
          "    assert_true(tall.ray.direction.y > bottom.ray.direction.y)\n"
        ]
      }
    ]
  },
  "tests/test_renderer_effects.mojo": {
    "before_sha256": "6575b3a32a3b6e016bf4f07abaef935e774d7ee5c33153c35449949d65ddd721",
    "after_sha256": "9354c7e99c360aa4023c7df2710679ae2073b9ceee787ff81cdeb5ec73076d90",
    "before_token_sha256": "4624900df3e4d83643a279968d61f1eb9d2bef48b8c1fcf4d7c53c77701f9a3c",
    "after_token_sha256": "d4d20c6e804e5173197039c753007b0e810a96dafe337013718f4c59ea5c6b8b",
    "edits": [
      {
        "start": 236,
        "stop": 245,
        "before": [],
        "after": [
          "    # A `Float32` count of 16777218 loses a character. The dark pixel\n",
          "    # must name the last one, and a count past an integer is refused.\n",
          "    assert_equal(ascii_index(0, 16777218, False), 16777217)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = ascii_index(0, Int.MAX, False)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = ascii_index(Float32(1e20), 10, False)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = ascii_index(nan[DType.float32](), 10, False)\n"
        ]
      },
      {
        "start": 259,
        "stop": 268,
        "before": [],
        "after": [
          "    # A `Float32` product of 16777217 is 16777216. JavaScript keeps the\n",
          "    # extra pixel. A product at 2^63, below `-2^63`, or not finite is refused.\n",
          "    assert_equal(ascii_size(16777217, 1), 16777217)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = ascii_size(Int.MAX, 1)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = ascii_size(Int.MIN, 1.5)\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = ascii_size(1, nan[DType.float32]())\n"
        ]
      }
    ]
  },
  "tests/test_sculptor.mojo": {
    "before_sha256": "57654c8e09dbc63a2a04202309540b315f7daa7572e029355dbc7b148eb1facf",
    "after_sha256": "bfa9699af53814a8e6ead24a620f6049be7a8316fd61945b31b219d6cddc300b",
    "before_token_sha256": "a192099bbc7314fa160c27e02a46c0e513324bd5be2f9abf74d7077fba3b4230",
    "after_token_sha256": "ee0cc9c1bf841ea865b722af35026b699b5b10bec916544bd6d242fb6ef35a49",
    "edits": [
      {
        "start": 54,
        "stop": 55,
        "before": [],
        "after": [
          "    _stamp_count,\n"
        ]
      },
      {
        "start": 336,
        "stop": 346,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_long_pointer_move_stamps_a_bounded_count() raises:\n",
          "    assert_equal(_stamp_count(1.0, 0.15), 6)\n",
          "    assert_equal(_stamp_count(0.1, 0.15), 0)\n",
          "    assert_equal(_stamp_count(Float64(1e18), 0.15), 4096)\n",
          "    assert_equal(_stamp_count(Float64(1e20), 0.15), 4096)\n",
          "    assert_equal(_stamp_count(nan[DType.float64](), 0.15), 0)\n",
          "    assert_equal(_stamp_count(10.0, nan[DType.float64]()), 0)\n",
          "    assert_equal(_stamp_count(10.0, 0.0), 0)\n"
        ]
      },
      {
        "start": 2020,
        "stop": 2035,
        "before": [],
        "after": [
          "def test_a_long_move_whose_first_stamp_misses_changes_nothing() raises:\n",
          "    var assets = Assets()\n",
          "    var scene = _scene(_bumpy(), assets, Object3D())\n",
          "    var sculptor = _pointer_sculptor(scene, assets, SCULPT_BRUSH, 30)\n",
          "    var camera = _camera()\n",
          "    sculptor.pointer_down(camera, scene, 100, 100)\n",
          "    assert_true(sculptor.is_sculpting())\n",
          "    var events = len(sculptor.events)\n",
          "    # A move of 10^9 pixels holds its stamps at 4096 steps, so its first\n",
          "    # step is far past the plane and the stroke stamps nothing.\n",
          "    sculptor.pointer_move(camera, scene, assets, 1e9, 100)\n",
          "    assert_equal(len(sculptor.events), events)\n",
          "    assert_true(sculptor.is_sculpting())\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_shadow.mojo": {
    "before_sha256": "83e4d788688394779c04f3dce56e7dd6fdb04bd9cedf8ee566d842ae950af6a2",
    "after_sha256": "02d293b4d13736f05cd2a84b1b245edc263e54b4df457f1c4877f323dbb42b0d",
    "before_token_sha256": "3045b3074f523dc3bb6c41cb782a75fcb4a3ee4599a8d3d58fcc036712bdab7a",
    "after_token_sha256": "8e214b76b72f79bdfd5bca4f5603e4337cc01067827130ae2cff7973258b6122",
    "edits": [
      {
        "start": 311,
        "stop": 314,
        "before": [],
        "after": [
          "    # 3037000500 squared does not fit in a signed integer.\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ShadowMap(0, 3037000500, flat_frame(), List[Float32](), 0, 0, 1)\n"
        ]
      },
      {
        "start": 1219,
        "stop": 1228,
        "before": [],
        "after": [
          "    # Past an integer, still the edge. The cast is not that texel.\n",
          "    var far = Vector3(Float32(1e20), 0.5, 0.5)\n",
          "    assert_equal(soft_texel(far, 0, 4), 3)\n",
          "    var behind = Vector3(Float32(-1e20), 0.5, 0.5)\n",
          "    assert_equal(soft_texel(behind, 15, 4), 12)\n",
          "    var missing = Vector3(nan[DType.float32](), 0.5, 0.5)\n",
          "    assert_equal(soft_texel(missing, 0, 4), 3)\n",
          "    assert_equal(soft_fraction(Float32(1e20), 4), Float32(0))\n",
          "    assert_equal(soft_fraction(nan[DType.float32](), 4), Float32(0))\n"
        ]
      },
      {
        "start": 1290,
        "stop": 1294,
        "before": [],
        "after": [
          "    assert_equal(bilinear_texel(Float32(1e20), 2.5, 0, 4), 2 * 4 + 3)\n",
          "    assert_equal(bilinear_texel(0.2, Float32(-1e20), 0, 4), 0)\n",
          "    assert_equal(bilinear_fraction(Float32(1e20)), Float32(0))\n",
          "    assert_equal(bilinear_fraction(nan[DType.float32]()), Float32(0))\n"
        ]
      },
      {
        "start": 1330,
        "stop": 1341,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_a_variance_map_refuses_a_size_that_does_not_fit() raises:\n",
          "    with assert_raises(contains=\"at least one texel\"):\n",
          "        _ = vsm_moments(List[Float32](), 0, 1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = vsm_moments(List[Float32](), 3037000500, 1, 1)\n",
          "    with assert_raises(contains=\"must fill its square\"):\n",
          "        _ = vsm_moments([Float32(0)], 2, 1, 1)\n",
          "    with assert_raises(contains=\"at least one sample\"):\n",
          "        _ = vsm_moments([Float32(0)], 1, 1, 0)\n"
        ]
      }
    ]
  },
  "tests/test_shape.mojo": {
    "before_sha256": "a74d40abe298ae08f3da5be90b2c5d95bb520eb3862182a504646d7e010b23dc",
    "after_sha256": "a6c1cbed8246d5e1e3e3193ac4c8593806393cc500ee17c01b46864b1400b6c9",
    "before_token_sha256": "f1bd15bdcb17e73f3652ab3577bc50f2e97651480f3dc79b0a1fb4db1798b67a",
    "after_token_sha256": "5fe43df44dde1c296ff26e60e3b72bbc3696a122770d250dc490cba76b31099f",
    "edits": [
      {
        "start": 597,
        "stop": 610,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = extrude(square(4), Length(2, METER), steps=Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = extrude(square(4), Length(2, METER), steps=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = extrude(square(4), Length(2, METER), curve_segments=Int.MAX)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = extrude(\n",
          "            square(4),\n",
          "            Length(2, METER),\n",
          "            bevel_enabled=True,\n",
          "            bevel_segments=Int.MAX,\n",
          "        )\n"
        ]
      }
    ]
  },
  "tests/test_skyscraper_generator.mojo": {
    "before_sha256": "99cf01ec3304968b51337b2f43c7e989f3a3aa99ebfdafe5ed02ba1d1cf60a03",
    "after_sha256": "c4645788d8764bd1d401dfea547069b319eb5f14eb8152f5c0d8ee7d4438500c",
    "before_token_sha256": "326cad5fff7823414e6f4be20165bd0eb81e79266c34decbb5585e946f448f0b",
    "after_token_sha256": "eb8ecafe8fefe1408388f9ffd01c1b77248ba736e7ba8b5670bd6dcd3cc09ef3",
    "edits": [
      {
        "start": 423,
        "stop": 433,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"positive distance\"):\n",
          "        _ = faces[0].bays(0)\n",
          "    with assert_raises(contains=\"positive distance\"):\n",
          "        _ = faces[0].bays(inf[DType.float64]())\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = faces[0].bays(1e-8)\n",
          "    var huge = _small()\n",
          "    huge.footprint_width = Length(1e8, METER)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = SkyscraperStyle(huge)\n"
        ]
      }
    ]
  },
  "tests/test_ssgi.mojo": {
    "before_sha256": "9fe42cc9e1ac50a6eeb89ddd096652f3a44411d40274f7e87d1d368f89a14b74",
    "after_sha256": "765dae9f97062fa503c933277f471bf1a101adcd37470e6e8425e044ce78fd16",
    "before_token_sha256": "2a42c3fb391d56782841e0e86a127a7a428481153845695db2ef31e98c9d4503",
    "after_token_sha256": "3e8d51bd0efc518209ea75b3dd327e0567f6a0830114307c859b553c03397fae",
    "edits": [
      {
        "start": 85,
        "stop": 92,
        "before": [],
        "after": [
          "    # A span of 1.1 used to shift by a negative count and keep four bits.\n",
          "    assert_equal(occluded_sectors(0, 1.1), UInt32(0xFFFFFFFF))\n",
          "    assert_equal(occluded_sectors(0, Float32(1e20)), UInt32(0xFFFFFFFF))\n",
          "    assert_equal(occluded_sectors(0.5, 1), UInt32(0xFFFF) << 16)\n",
          "    assert_equal(occluded_sectors(Float32(1e20), 0.25), UInt32(0))\n",
          "    assert_equal(occluded_sectors(-1, 0.1), UInt32(0))\n",
          "    assert_equal(occluded_sectors(-0.125, 0.25), UInt32(0xF))\n"
        ]
      },
      {
        "start": 145,
        "stop": 157,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssgi_pass(slice_count=16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssgi_pass(step_count=Int.MAX)\n",
          "    bad = SsgiSettings()\n",
          "    bad.step_count = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_ssgi(bad)\n",
          "    bad = SsgiSettings()\n",
          "    bad.slice_count = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_ssgi(bad)\n"
        ]
      },
      {
        "start": 261,
        "stop": 276,
        "before": [],
        "after": [
          "    # A count the march cannot finish returns the unoccluded pixel.\n",
          "    var surface = -1\n",
          "    for slot in range(SIZE * SIZE):\n",
          "        if signal[slot].a < 1:\n",
          "            surface = slot\n",
          "            break\n",
          "    assert_true(surface >= 0)\n",
          "    var huge = SsgiSettings()\n",
          "    huge.step_count = Int.MAX\n",
          "    var stopped = ssgi_pixel(inputs, surface % SIZE, surface // SIZE, huge)\n",
          "    assert_equal(stopped.r, 0)\n",
          "    huge.step_count = 12\n",
          "    huge.slice_count = 16777217\n",
          "    stopped = ssgi_pixel(inputs, surface % SIZE, surface // SIZE, huge)\n",
          "    assert_equal(stopped.r, 0)\n"
        ]
      }
    ]
  },
  "tests/test_ssr_node.mojo": {
    "before_sha256": "a8ff275ec062366e50679c9b7e31ffcc4de1817a4954bdabd2bb9a5f3b690278",
    "after_sha256": "6db01fe909d6ccf1605aa09ea7df89e7eeb7c0deef424d1573b1c05d26d971c3",
    "before_token_sha256": "37a2da1baf53620db2b2ddf6b87749414fdbbdf6d22f3d2ff2229004fa37e691",
    "after_token_sha256": "177c27c5101a33170b6535230e94898a5e126c95c27650f93e8352dbdca16eed",
    "edits": [
      {
        "start": 35,
        "stop": 36,
        "before": [],
        "after": [
          "    ssr_node_blur,\n"
        ]
      },
      {
        "start": 120,
        "stop": 127,
        "before": [],
        "after": [
          "        check_ssr_node(bad)\n",
          "    bad = SsrNodeSettings()\n",
          "    bad.blur_quality = 2048\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        check_ssr_node(bad)\n",
          "    bad.blur_quality = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n"
        ]
      },
      {
        "start": 442,
        "stop": 458,
        "before": [],
        "after": [
          "def test_an_ssr_blur_must_fit() raises:\n",
          "    var colors = List[FloatColor](length=1, fill=FloatColor(0, 0, 0, 0))\n",
          "    var source = LightView(colors, 1, 1)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = ssr_node_blur(source, 0, 1, 1, 1)\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = ssr_node_blur(source, 1, 0, 1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssr_node_blur(source, 1 << 32, 1 << 32, 1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssr_node_blur(source, 1, 1, 2048, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ssr_node_blur(source, 1, 1, Int.MAX, 1)\n",
          "    _ = colors^\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_streamline_sizing.mojo": {
    "before_sha256": "e2ee07176204d094b4da958714caa5ba91939b5bdfacee63ecba8e35ee5ca641",
    "after_sha256": "6f278d19e3471b8e0aed9850cd566dec20e076761f9ef7822db9eb9cdad234b7",
    "before_token_sha256": "4066fa2b36d3617810c5f6af8242a33cf19511adfc8d27ea8a5c0c26bead576b",
    "after_token_sha256": "484b670bbf60f47db10e24fbb26b6b71ada3f734edd33746aa83e1d4eea5dcef",
    "edits": [
      {
        "start": 75,
        "stop": 83,
        "before": [],
        "after": [
          "    # `Float64` of a side at 2^63 rounds up. Adding a half then cast that\n",
          "    # to zero. A scale of one is the side itself.\n",
          "    var wide = FrameSize(Int.MAX, 8)\n",
          "    assert_equal(estimated_render_size(MODE_DLAA, wide), wide)\n",
          "    assert_equal(\n",
          "        estimated_render_size(MODE_OFF, FrameSize(1 << 62, 4)),\n",
          "        FrameSize(1 << 62, 4),\n",
          "    )\n"
        ]
      },
      {
        "start": 207,
        "stop": 213,
        "before": [],
        "after": [
          "    # Eight times the square of 2^29 still fits. The square of 2^30 is 2^63.\n",
          "    assert_equal(\n",
          "        jitter_phase_count(FrameSize(1, 1), FrameSize(1 << 29, 1)), 1 << 61\n",
          "    )\n",
          "    with assert_raises(contains=\"does not fit\"):\n",
          "        _ = jitter_phase_count(FrameSize(1, 1), FrameSize(1 << 30, 1))\n"
        ]
      }
    ]
  },
  "tests/test_streamline_upscaler.mojo": {
    "before_sha256": "f4c1e4c217d332a77dd3079afce7ce7e3e5713183ac575507305c200b3061958",
    "after_sha256": "cf725a1c7cd3b3ec17dedc4afc96d07d6415663f7ffffbac5e4a8d83205ed3c3",
    "before_token_sha256": "96ed49259e1c30c52752748fa030548bb9b8693bc7277041647c0a3ab7be38bb",
    "after_token_sha256": "458475af92225e181053ecf0f06fcd7fa57fb3052661eee86dfc0a4d3ffe94f5",
    "edits": [
      {
        "start": 164,
        "stop": 178,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = upscaler.evaluate(\n",
          "            SUPER_RESOLUTION,\n",
          "            List[FloatColor](),\n",
          "            FrameSize(1 << 32, 1 << 32),\n",
          "            FrameSize(1 << 32, 1 << 32),\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = upscaler.evaluate(\n",
          "            SUPER_RESOLUTION,\n",
          "            ramp(2, 2),\n",
          "            FrameSize(2, 2),\n",
          "            FrameSize(1 << 32, 1 << 32),\n",
          "        )\n"
        ]
      }
    ]
  },
  "tests/test_temporal_denoise.mojo": {
    "before_sha256": "cb16cc0873469abc64a2b9b7dc18b8bed327c3f2bea168101ee048131a539865",
    "after_sha256": "1cf0ed025be44931de732676fabea14f09b20e9f73a17db086777ebf44ffb8be",
    "before_token_sha256": "f388adba2614e2f7230c9b1216a1dcd6b256a8e2806a1fa3d21930aa5680cd47",
    "after_token_sha256": "9c0c13bb96f02eb0d7d85d528d4a47152d01702b0a4f7fd70db1969c9f800d4c",
    "edits": [
      {
        "start": 42,
        "stop": 43,
        "before": [],
        "after": [
          "from std.math import nan\n"
        ]
      },
      {
        "start": 245,
        "stop": 266,
        "before": [],
        "after": [
          "def test_a_depth_past_an_integer_reads_the_edge() raises:\n",
          "    var depth = List[Float32]()\n",
          "    for index in range(SIDE * SIDE):\n",
          "        depth.append(Float32(index))\n",
          "    var inputs = DenoiseInputs(\n",
          "        SIDE,\n",
          "        SIDE,\n",
          "        plane_of(FloatColor(0, 0, 0, 1)),\n",
          "        plane_of(FloatColor(0, 0, 0, 1)),\n",
          "        depth^,\n",
          "        plane_of(Vector3(0, 0, 1)),\n",
          "        Matrix4(),\n",
          "        Matrix4(),\n",
          "    )\n",
          "    assert_equal(inputs.depth_at(0.1, 0.1), 0)\n",
          "    assert_equal(inputs.depth_at(1, 0.1), 3)\n",
          "    assert_equal(inputs.depth_at(Float32(1e20), 0.1), 3)\n",
          "    assert_equal(inputs.depth_at(Float32(-1e20), 0.1), 0)\n",
          "    assert_equal(inputs.depth_at(nan[DType.float32](), 0.1), 0)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 396,
        "stop": 445,
        "before": [],
        "after": [
          "def test_a_denoise_frame_must_fit() raises:\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = ReprojectInputs(\n",
          "            0,\n",
          "            1,\n",
          "            List[FloatColor](),\n",
          "            List[FloatColor](),\n",
          "            List[Float32](),\n",
          "            List[Float32](),\n",
          "            List[Vector3](),\n",
          "            List[Vector3](),\n",
          "            List[Vector2](),\n",
          "        )\n",
          "    with assert_raises(contains=\"at least one pixel\"):\n",
          "        _ = DenoiseInputs(\n",
          "            1,\n",
          "            0,\n",
          "            List[FloatColor](),\n",
          "            List[FloatColor](),\n",
          "            List[Float32](),\n",
          "            List[Vector3](),\n",
          "            Matrix4(),\n",
          "            Matrix4(),\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = ReprojectInputs(\n",
          "            1 << 32,\n",
          "            1 << 32,\n",
          "            List[FloatColor](),\n",
          "            List[FloatColor](),\n",
          "            List[Float32](),\n",
          "            List[Float32](),\n",
          "            List[Vector3](),\n",
          "            List[Vector3](),\n",
          "            List[Vector2](),\n",
          "        )\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = DenoiseInputs(\n",
          "            1 << 32,\n",
          "            1 << 32,\n",
          "            List[FloatColor](),\n",
          "            List[FloatColor](),\n",
          "            List[Float32](),\n",
          "            List[Vector3](),\n",
          "            Matrix4(),\n",
          "            Matrix4(),\n",
          "        )\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_transmission.mojo": {
    "before_sha256": "794401fe4b88d34b187065e772d062ab3cdba915761fe065815afec8f6e1adc3",
    "after_sha256": "792bea8a0f84c1d7ff82e54c592513cc410e02369bd2a1e2a9d8b2ef2d9b00ba",
    "before_token_sha256": "a19e3c060b2c83b5ac238f2dafe105b71c6c4c644721e33d5d278800454d86b3",
    "after_token_sha256": "9efc727d872a26a336912dd2cae70b5ae6de9adecc802331ac13cdefb55b623c",
    "edits": [
      {
        "start": 38,
        "stop": 39,
        "before": [
          "from std.math import inf\n"
        ],
        "after": [
          "from std.math import inf, nan\n"
        ]
      },
      {
        "start": 193,
        "stop": 205,
        "before": [],
        "after": [
          "    # A level past 2^63 is not an index. It reads the last level, as a\n",
          "    # level past the chain does, and a level below zero reads the first.\n",
          "    var past = texture_bicubic(source, Vector2(0.6875, 0.5), 9.5)\n",
          "    var huge = texture_bicubic(source, Vector2(0.6875, 0.5), Float32(1e20))\n",
          "    var missing = texture_bicubic(\n",
          "        source, Vector2(0.6875, 0.5), nan[DType.float32]()\n",
          "    )\n",
          "    var below = texture_bicubic(source, Vector2(0.6875, 0.5), -1)\n",
          "    assert_almost_equal(huge.r, past.r, atol=TOLERANCE)\n",
          "    assert_almost_equal(missing.r, past.r, atol=TOLERANCE)\n",
          "    assert_almost_equal(below.r, sharp.r, atol=TOLERANCE)\n",
          "    assert_true(past.r < sharp.r)\n"
        ]
      }
    ]
  },
  "tests/test_tsl_helpers.mojo": {
    "before_sha256": "30924880edd2b65cb8f0266ede2fff12486eeced41a67d435bf4ac778685be99",
    "after_sha256": "d1a99872f9c013f40039c582f9115e1144f44d320c2adf0705ca02397e210644",
    "before_token_sha256": "afc468c5ceb009a57909916f32b89fc80957c14245cb77352d8800893511f7ca",
    "after_token_sha256": "08cd998fc07c21f4b4961d047052a5ee640eb99f676ea4cff66039a1c0f01c08",
    "edits": [
      {
        "start": 136,
        "stop": 140,
        "before": [],
        "after": [
          "    # `Int` of `sqrt(3)` times a step count past 2^63 is not that count.\n",
          "    assert_equal(raymarch_count(Int.MAX), Int.MAX)\n",
          "    with assert_raises(contains=\"from one step to 1024 times\"):\n",
          "        _ = RaymarchingBox(g, Int.MAX, to_local)\n"
        ]
      }
    ]
  },
  "tests/test_velocity.mojo": {
    "before_sha256": "c78060f034b971257d793f4db837ca91799b59a16e5c62f660ba7e79c8f908e8",
    "after_sha256": "76386a549527725c85b1088b1739cdcc3562f68a477fabe877c8ae2b26ab14e0",
    "before_token_sha256": "821507fd18ac67c73414bce9de0a71782679acd6d4087f17a2401bb24a632492",
    "after_token_sha256": "69739ff894b40e1f04812ca6e125a654b9d5884768401d8a0ff0329b78c86b95",
    "edits": [
      {
        "start": 429,
        "stop": 442,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = motion_blur_pass(1, 16777217)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = motion_blur_pass(1, Int.MAX)\n",
          "    var held = a_bright_column()\n",
          "    var huge = DisplaySettings()\n",
          "    huge.motion_samples = Int.MAX\n",
          "    motion_blur_light(held, huge)\n",
          "    assert_almost_equal(held.colors[4 * SIZE + 8].r, 3, atol=1e-5)\n",
          "    held = a_bright_column()\n",
          "    huge.motion_samples = 16777217\n",
          "    motion_blur_light(held, huge)\n",
          "    assert_almost_equal(held.colors[4 * SIZE + 8].r, 3, atol=1e-5)\n"
        ]
      }
    ]
  },
  "tests/test_volume_node_material.mojo": {
    "before_sha256": "2a901aa7f2763805b55fc199de7f86f6651be16ee83df01f14f8eef829d1d575",
    "after_sha256": "88da0fa6f520fbc00d73d0c254aef84232c090b2c6963939a419356b6efe2eeb",
    "before_token_sha256": "c80451f2a035f97579089ba0cfc72dbaddb48a725a16a112b6121bf0aa3e1f67",
    "after_token_sha256": "8bad5a8f27cafa8c2f58797b12ec2a76dba45bdc0c2a6714511371fbd80d0597",
    "edits": [
      {
        "start": 162,
        "stop": 176,
        "before": [],
        "after": [
          "    # A step count past the march limit gathers nothing. It does not walk.\n",
          "    var huge = volumetric_light(\n",
          "        AboveHalf(),\n",
          "        ProgramSource(Pointer(to=program)),\n",
          "        False,\n",
          "        at_surface(),\n",
          "        Vector3(0, 0, 2),\n",
          "        0.5,\n",
          "        Int.MAX,\n",
          "        0,\n",
          "    )\n",
          "    assert_equal(huge.x, 0)\n",
          "    assert_equal(huge.y, 0)\n",
          "    assert_equal(huge.z, 0)\n"
        ]
      },
      {
        "start": 290,
        "stop": 295,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = volume_node_material(steps=4097)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = volume_node_material(steps=Int.MAX)\n",
          "    assert_equal(volume_node_material(steps=4096).steps, 4096)\n"
        ]
      }
    ]
  },
  "tests/test_vrml.mojo": {
    "before_sha256": "776c8dda159b24e77095d8901466e9bdb0b1c06ea55ee8c426ca5e70bfe90fdc",
    "after_sha256": "81b7206e3fd10195fe5f12c061d6040c21370c61c52abc635bce035a61fe56b1",
    "before_token_sha256": "5c29cfb8f83e74e32a8cb4acc751231977e5725366b2a5a5ffe0af0347e988fc",
    "after_token_sha256": "19475c5bdcb30f95f5a02502fb71e5bccd45b72ad077f285b8d86736ebf23713",
    "edits": [
      {
        "start": 486,
        "stop": 537,
        "before": [],
        "after": [
          "    refuses(\n",
          "        (\n",
          "            \"Shape { appearance Appearance { texture PixelTexture { image\"\n",
          "            \" 2000000000 2000000000 1 } } }\"\n",
          "        ),\n",
          "        \"larger than this port\",\n",
          "    )\n",
          "    # 3037000500 * 3037000500 wraps in Int. The old index length was a\n",
          "    # short loop, so the grid looked small enough to build.\n",
          "    refuses(\n",
          "        (\n",
          "            \"Shape { geometry ElevationGrid { xDimension 3037000500\"\n",
          "            \" zDimension 3037000500 } }\"\n",
          "        ),\n",
          "        \"larger than this port\",\n",
          "    )\n",
          "    # 2^31 points on a side: the point count fits, and `index * 3` does not.\n",
          "    refuses(\n",
          "        (\n",
          "            \"Shape { geometry ElevationGrid { xDimension 2147483648\"\n",
          "            \" zDimension 2147483648 } }\"\n",
          "        ),\n",
          "        \"larger than this port\",\n",
          "    )\n",
          "    # 1e20 is a multiple of 2048, so the byte is zero. 257 keeps its remainder.\n",
          "    var model = parse_vrml(\n",
          "        (\n",
          "            \"#VRML V2.0 utf8\\nShape { appearance Appearance { texture\"\n",
          "            \" PixelTexture { image 5 1 1 255 257 1e20 -1e20 -1 } } }\"\n",
          "        ),\n",
          "        scene,\n",
          "        assets,\n",
          "    )\n",
          "    ref pixels = model.textures[0].data\n",
          "    assert_equal(Int(pixels[0]), 255)\n",
          "    assert_equal(Int(pixels[4]), 1)\n",
          "    assert_equal(Int(pixels[8]), 0)\n",
          "    assert_equal(Int(pixels[12]), 0)\n",
          "    assert_equal(Int(pixels[16]), 255)\n",
          "    assert_equal(Int(pixels[19]), 1)\n",
          "    # A zero height makes no bytes. It is not an overflow.\n",
          "    var empty = Scene()\n",
          "    var empty_assets = Assets()\n",
          "    _ = parse_vrml(\n",
          "        (\n",
          "            \"#VRML V2.0 utf8\\nShape { appearance Appearance { texture\"\n",
          "            \" PixelTexture { image 1 0 1 } } }\"\n",
          "        ),\n",
          "        empty,\n",
          "        empty_assets,\n",
          "    )\n"
        ]
      }
    ]
  },
  "tests/test_vxgi_node.mojo": {
    "before_sha256": "9a5a11f15ac4f3f891f7dfc11bd7cd48ab4eb174c3e6e55726e70de10862b43e",
    "after_sha256": "fef642a9eafd0b74d53c3e525ec1b8f957b5deedf42af05abb9270bd14c11d3c",
    "before_token_sha256": "cbed36d6fa82d5d3c82f61e9dd3b48583f73b71231bbf528ee14847a66f47904",
    "after_token_sha256": "5aed3adfd9bc9b6406b00b448e599170aabecca785bd31d898a2a3f366076186",
    "edits": [
      {
        "start": 196,
        "stop": 204,
        "before": [],
        "after": [
          "    node = VXGINode()\n",
          "    node.cone_count = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        node.validate()\n",
          "    node = VXGINode()\n",
          "    node.cone_count = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        node.validate()\n"
        ]
      },
      {
        "start": 367,
        "stop": 395,
        "before": [],
        "after": [
          "    # Zero cones make the first comparison fail. A count past the cap\n",
          "    # makes the second fail. Neither walk starts.\n",
          "    params[PARAM_CONES] = 0\n",
          "    var none = vxgi_pixel(\n",
          "        node.volume.grid,\n",
          "        floats_of(node.volume.opacity),\n",
          "        floats_of(node.volume.radiance),\n",
          "        floats_of(params),\n",
          "        0.5,\n",
          "        Vector3(0, 0, 1),\n",
          "        1,\n",
          "        1,\n",
          "    )\n",
          "    assert_equal(none[0], 1)\n",
          "    assert_equal(none[3], 1)\n",
          "    params[PARAM_CONES] = Float32(1e20)\n",
          "    var huge = vxgi_pixel(\n",
          "        node.volume.grid,\n",
          "        floats_of(node.volume.opacity),\n",
          "        floats_of(node.volume.radiance),\n",
          "        floats_of(params),\n",
          "        0.5,\n",
          "        Vector3(0, 0, 1),\n",
          "        1,\n",
          "        1,\n",
          "    )\n",
          "    assert_equal(huge[0], 1)\n",
          "    assert_equal(huge[3], 1)\n"
        ]
      }
    ]
  },
  "tests/test_vxgi_scene_collector.mojo": {
    "before_sha256": "982afe0db546152028797bd3627a49ad05973f977b69ce57a068c0dff2679817",
    "after_sha256": "ee1b0df105a007e7a6e8437b8733eb82779fca8c5d673be7260f72abad3ac2d3",
    "before_token_sha256": "a72fe97c70591fc944545cd32468055151b4b6fd15a996024f3a4ae5eadacece",
    "after_token_sha256": "9761636b5cfbf7e05a1249ff744ff1f77c97d6489c1d6d907d2b4f4e3cc66f06",
    "edits": [
      {
        "start": 19,
        "stop": 20,
        "before": [],
        "after": [
          "    _clip_triangle,\n"
        ]
      },
      {
        "start": 61,
        "stop": 62,
        "before": [
          "from std.math import inf\n"
        ],
        "after": [
          "from std.math import inf, nan\n"
        ]
      },
      {
        "start": 492,
        "stop": 505,
        "before": [],
        "after": [
          "    # A coordinate that is not finite, or past an integer, is read at zero.\n",
          "    assert_equal(\n",
          "        sample_texture(repeat, nan[DType.float32](), 0.25).r,\n",
          "        sample_texture(repeat, 0, 0.25).r,\n",
          "    )\n",
          "    assert_equal(\n",
          "        sample_texture(mirror, Float32(1e20), 0.25).b,\n",
          "        sample_texture(mirror, 0, 0.25).b,\n",
          "    )\n",
          "    assert_equal(\n",
          "        sample_texture(mirror, Float32(-1e20), 0.25).b,\n",
          "        sample_texture(mirror, 0, 0.25).b,\n",
          "    )\n"
        ]
      },
      {
        "start": 561,
        "stop": 615,
        "before": [],
        "after": [
          "\n",
          "\n",
          "def test_an_edge_past_the_volume_does_not_keep_splitting() raises:\n",
          "    var bounds = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))\n",
          "    var assets = Assets()\n",
          "    var scene = Scene()\n",
          "    _ = placed(\n",
          "        assets,\n",
          "        scene,\n",
          "        one_triangle(\n",
          "            Vector3(0, 0, 0), Vector3(0.5, 0, 0), Vector3(Float32(1e20), 0.2, 0)\n",
          "        ),\n",
          "        Material(WHITE),\n",
          "    )\n",
          "    scene.update()\n",
          "    var records = collect(scene, assets, max_edge=3, bounds=bounds)\n",
          "    assert_true(len(records) > 0)\n",
          "    assert_true(len(records) < 32 * TRIANGLE_STRIDE)\n",
          "    assert_equal(len(records) % TRIANGLE_STRIDE, 0)\n",
          "    var corner = 0\n",
          "    while corner < len(records):\n",
          "        if corner % TRIANGLE_STRIDE < 12:\n",
          "            assert_true(records[corner] < 8)\n",
          "            assert_true(records[corner] > -8)\n",
          "        corner += 1\n",
          "    for shift in range(3):\n",
          "        var corners = List[Vector3]()\n",
          "        corners.append(Vector3(0, 0, 0))\n",
          "        corners.append(Vector3(0.5, 0, 0))\n",
          "        corners.append(Vector3(0, 0.5, 0))\n",
          "        if shift == 0:\n",
          "            corners[0] = Vector3(nan[DType.float32](), 0, 0)\n",
          "        elif shift == 1:\n",
          "            corners[1] = Vector3(0.5, nan[DType.float32](), 0)\n",
          "        else:\n",
          "            corners[2] = Vector3(0, 0.5, inf[DType.float32]())\n",
          "        var gone = Assets()\n",
          "        var empty = Scene()\n",
          "        _ = placed(\n",
          "            gone,\n",
          "            empty,\n",
          "            one_triangle(corners[0], corners[1], corners[2]),\n",
          "            Material(WHITE),\n",
          "        )\n",
          "        empty.update()\n",
          "        assert_equal(len(collect(empty, gone, bounds=bounds)), 0)\n",
          "    var missed = _clip_triangle(\n",
          "        Vector3(10, 10, 10),\n",
          "        Vector3(11, 10, 10),\n",
          "        Vector3(10, 11, 10),\n",
          "        Vector3(-1, -1, -1),\n",
          "        Vector3(1, 1, 1),\n",
          "    )\n",
          "    assert_equal(len(missed), 0)\n"
        ]
      }
    ]
  },
  "tests/test_vxgi_volume.mojo": {
    "before_sha256": "1927ccf8ff6dac2b85847c98cec8015f7ca5d3762f6c78aa599e0afbc3996b51",
    "after_sha256": "b7022536035da4811eed12a6e7ef2571765c7447bc9d767fe3d40c00c64cf254",
    "before_token_sha256": "cfc47d4ff0ae95e0e7d7a3c3ba86836b937a8ecf39bac95e422ce2ca477c44fb",
    "after_token_sha256": "69620767c6d5775b2b34fd53e7350209591ae4a0be10b8114ad1d541b1d48387",
    "edits": [
      {
        "start": 24,
        "stop": 25,
        "before": [],
        "after": [
          "    VxgiGrid,\n"
        ]
      },
      {
        "start": 30,
        "stop": 32,
        "before": [],
        "after": [
          "    _grid_index,\n",
          "    _padded,\n"
        ]
      },
      {
        "start": 49,
        "stop": 50,
        "before": [
          "from std.math import cos, nan, sqrt\n"
        ],
        "after": [
          "from std.math import cos, inf, nan, sqrt\n"
        ]
      },
      {
        "start": 161,
        "stop": 292,
        "before": [],
        "after": [
          "def _record(\n",
          "    ax: Float32,\n",
          "    ay: Float32,\n",
          "    az: Float32,\n",
          "    bx: Float32,\n",
          "    by: Float32,\n",
          "    bz: Float32,\n",
          "    cx: Float32,\n",
          "    cy: Float32,\n",
          "    cz: Float32,\n",
          ") -> List[Float32]:\n",
          "    \"\"\"Return one triangle record in the collector's layout.\"\"\"\n",
          "    var values = List[Float32]()\n",
          "    values.extend([ax, ay, az, 0, bx, by, bz, 0, cx, cy, cz, 0])\n",
          "    values.extend([1, 1, 1, 0, 0, 0, 0, 0])\n",
          "    return values^\n",
          "\n",
          "\n",
          "def _small_grid() -> VxgiGrid:\n",
          "    \"\"\"Return an 8-voxel grid of voxel size 1/8.\"\"\"\n",
          "    return VxgiGrid(Vector3(0, 0, 0), Vector3(1, 1, 1), 0.125, 8, 8, 8, 1, 1)\n",
          "\n",
          "\n",
          "def _setup(grid: VxgiGrid, values: List[Float32]) -> VoxelTriangle:\n",
          "    \"\"\"Set up one record while `values` is still alive.\"\"\"\n",
          "    return VoxelTriangle(floats_of(values), 0, grid)\n",
          "\n",
          "\n",
          "def test_a_triangle_past_an_integer_lies_past_the_grid() raises:\n",
          "    var grid = _small_grid()\n",
          "    var near = _setup(\n",
          "        grid, _record(0.1, 0.1, 0.1, 0.2, 0.1, 0.1, 0.1, 0.2, 0.15)\n",
          "    )\n",
          "    assert_equal(near.i0, 1)\n",
          "    assert_equal(near.i1, 3)\n",
          "    assert_equal(near.j0, 1)\n",
          "    assert_equal(near.j1, 3)\n",
          "    assert_true(near.usable)\n",
          "    var far = _setup(\n",
          "        grid,\n",
          "        _record(\n",
          "            Float32(1e20),\n",
          "            0.2,\n",
          "            0.2,\n",
          "            Float32(1e20),\n",
          "            0.4,\n",
          "            0.2,\n",
          "            Float32(1e20),\n",
          "            0.2,\n",
          "            0.4,\n",
          "        ),\n",
          "    )\n",
          "    assert_equal(far.i0, 3)\n",
          "    assert_equal(far.i1, 6)\n",
          "    var far_column = far.column(4, 4)\n",
          "    assert_true(far_column[1] > far_column[2])\n",
          "    assert_false(far.covers(4, 4, 0))\n",
          "    var past = _setup(\n",
          "        grid,\n",
          "        _record(\n",
          "            Float32(1e20),\n",
          "            Float32(1e20),\n",
          "            Float32(1e20),\n",
          "            Float32(1e20),\n",
          "            Float32(2e20),\n",
          "            Float32(1e20),\n",
          "            Float32(1e20),\n",
          "            Float32(1e20),\n",
          "            Float32(2e20),\n",
          "        ),\n",
          "    )\n",
          "    assert_true(past.i0 > past.i1)\n",
          "    assert_false(past.covers(0, 0, 0))\n",
          "    var under = _setup(\n",
          "        grid,\n",
          "        _record(\n",
          "            Float32(-1e20),\n",
          "            Float32(-1e20),\n",
          "            Float32(-1e20),\n",
          "            Float32(-1e20),\n",
          "            Float32(-2e20),\n",
          "            Float32(-1e20),\n",
          "            Float32(-1e20),\n",
          "            Float32(-1e20),\n",
          "            Float32(-2e20),\n",
          "        ),\n",
          "    )\n",
          "    assert_true(under.i0 > under.i1)\n",
          "    assert_false(under.covers(0, 0, 0))\n",
          "    var below = _setup(\n",
          "        grid,\n",
          "        _record(\n",
          "            Float32(-1e20),\n",
          "            0.2,\n",
          "            0.2,\n",
          "            Float32(-1e20),\n",
          "            0.4,\n",
          "            0.2,\n",
          "            Float32(-1e20),\n",
          "            0.2,\n",
          "            0.4,\n",
          "        ),\n",
          "    )\n",
          "    assert_equal(below.i0, 3)\n",
          "    assert_equal(below.i1, 6)\n",
          "    var below_column = below.column(4, 4)\n",
          "    assert_true(below_column[1] > below_column[2])\n",
          "    assert_false(below.covers(4, 4, 0))\n",
          "    var deep = _setup(\n",
          "        grid,\n",
          "        _record(\n",
          "            0.2,\n",
          "            0.2,\n",
          "            Float32(1e20),\n",
          "            0.4,\n",
          "            0.2,\n",
          "            Float32(1e20),\n",
          "            0.2,\n",
          "            0.4,\n",
          "            Float32(1e20),\n",
          "        ),\n",
          "    )\n",
          "    assert_true(deep.i0 <= deep.i1)\n",
          "    assert_false(deep.covers(3, 3, 0))\n",
          "    var missing = _setup(\n",
          "        grid,\n",
          "        _record(nan[DType.float32](), 0.2, 0.2, 0.3, 0.2, 0.2, 0.2, 0.4, 0.3),\n",
          "    )\n",
          "    assert_false(missing.covers(3, 3, 3))\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 339,
        "stop": 354,
        "before": [],
        "after": [
          "def test_a_grid_index_or_an_axis_that_does_not_fit_is_refused() raises:\n",
          "    # A coordinate at no place lies past the high side of the grid.\n",
          "    assert_equal(_grid_index(nan[DType.float32]()), Int.MAX)\n",
          "    assert_equal(_grid_index(Float32(-1e30)), Int.MIN)\n",
          "    assert_equal(_grid_index(2.5), 2)\n",
          "    # An axis is its size, a voxel each side, up to the coarsest step.\n",
          "    assert_equal(_padded(6, 1, 4), 8)\n",
          "    # A voxel count past an integer is refused, and so is a group count\n",
          "    # whose voxels do not fit in one.\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = _padded(1e300, 1, 1)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = _padded(9223372036854774784.0, 1, 1 << 20)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 362,
        "stop": 372,
        "before": [],
        "after": [
          "    volume = VXGIVolume()\n",
          "    volume.bounces = 16777217\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        volume.validate()\n",
          "    volume = VXGIVolume()\n",
          "    volume.bounces = Int.MAX\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        volume.validate()\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        volume.update_lighting()\n"
        ]
      },
      {
        "start": 405,
        "stop": 415,
        "before": [],
        "after": [
          "    var scene = Scene()\n",
          "    var assets = Assets()\n",
          "    var huge = VXGIVolume(1 << 22)\n",
          "    huge.bounds = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        huge.prepare_voxels(scene, assets)\n",
          "    var open = VXGIVolume(8)\n",
          "    open.bounds = Box3(Vector3(0, 0, 0), Vector3(inf[DType.float32](), 1, 1))\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        open.prepare_voxels(scene, assets)\n"
        ]
      }
    ]
  },
  "tests/test_water.mojo": {
    "before_sha256": "179f2cb6ef20a44c9f862453d56fdb967b5ba1c6978996ecc750f7da3a4e5d7a",
    "after_sha256": "3e029fe046c851a16197063c45e02d953ad79832cc539d19e90607e968d6756d",
    "before_token_sha256": "cd69d45240dd263bfdb1212253e04b8487c2282a06943ef26770c34ae4a6e415",
    "after_token_sha256": "41abd6ff1fb6d1202e3ae054d0b59e663c6d4e0c27cf9e017c61da622ddb4c9b",
    "edits": [
      {
        "start": 17,
        "stop": 20,
        "before": [],
        "after": [
          "    _Splat,\n",
          "    _caustic_high,\n",
          "    _caustic_low,\n"
        ]
      },
      {
        "start": 27,
        "stop": 28,
        "before": [
          "from extensions.water.filter import anisotropic_step\n"
        ],
        "after": [
          "from extensions.water.filter import anisotropic_step, lod_blend\n"
        ]
      },
      {
        "start": 35,
        "stop": 37,
        "before": [],
        "after": [
          "    _at_rest,\n",
          "    _height_bound,\n"
        ]
      },
      {
        "start": 269,
        "stop": 278,
        "before": [],
        "after": [
          "    var missing_x = sample_ripple(field, nan[DType.float32](), 0.0)\n",
          "    assert_almost_equal(missing_x.height, 0.0)\n",
          "    assert_almost_equal(missing_x.slope_x, 0.0)\n",
          "    var missing_z = sample_ripple(field, 0.0, nan[DType.float32]())\n",
          "    assert_almost_equal(missing_z.height, 0.0)\n",
          "    step_ripple(field, nan[DType.float32](), 0.0, 0.5, 0.5, 0.08, 0.07)\n",
          "    assert_almost_equal(sample_ripple(field, 0.0, 0.0).height, 0.0)\n",
          "    step_ripple(field, 0.0, nan[DType.float32](), 0.5, 0.5, 0.08, 0.07)\n",
          "    assert_almost_equal(sample_ripple(field, 0.0, 0.0).slope_z, 0.0)\n"
        ]
      },
      {
        "start": 364,
        "stop": 366,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = CausticField(1 << 31, Length(4.6))\n"
        ]
      },
      {
        "start": 385,
        "stop": 401,
        "before": [],
        "after": [
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = render_caustics(flat, sun, Length(1.6), Int.MAX, 4)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = render_caustics(flat, sun, Length(1.6), 1 << 31, 4)\n",
          "    # A bed 1e20 meters down sends the refracted triangles past every texel.\n",
          "    var far = render_caustics(flat, Vector3(0.6, 0.8, 0.0), Length(1e20), 2, 8)\n",
          "    assert_equal(far.channel(0, 0, 0), 0.0)\n",
          "    assert_equal(far.channel(4, 4, 1), 0.0)\n",
          "    assert_equal(_caustic_low(Float32(1.2)), 1)\n",
          "    assert_equal(_caustic_high(Float32(3.8)), 4)\n",
          "    assert_equal(_caustic_low(Float32(1e20)), Int.MAX)\n",
          "    assert_equal(_caustic_high(Float32(1e20)), Int.MAX)\n",
          "    assert_equal(_caustic_low(Float32(-1e20)), Int.MIN)\n",
          "    assert_equal(_caustic_high(Float32(-1e20)), Int.MIN)\n",
          "    assert_equal(_caustic_low(nan[DType.float32]()), Int.MAX)\n",
          "    assert_equal(_caustic_high(nan[DType.float32]()), Int.MAX)\n"
        ]
      },
      {
        "start": 479,
        "stop": 489,
        "before": [],
        "after": [
          "    # A Float32 height of 2^25 + 1 is 2^25, so the wide side rounds to 2.\n",
          "    var odd = glare_grid_size(4, 16777216, 33554433)\n",
          "    assert_equal(odd[0], 1)\n",
          "    # A side of zero makes the fit infinite. `Int` of that was not below\n",
          "    # one, so the grid width stayed zero.\n",
          "    with assert_raises(contains=\"positive\"):\n",
          "        _ = glare_grid_size(4, 0, 10)\n",
          "    with assert_raises(contains=\"positive\"):\n",
          "        _ = glare_grid_size(4, 10, 0)\n",
          "    assert_equal(odd[1], 3)\n"
        ]
      },
      {
        "start": 506,
        "stop": 536,
        "before": [],
        "after": [
          "    # A width past 2^24 is not a whole `Float32`. The last column and the\n",
          "    # last pixel must stay inside the image and the grid.\n",
          "    assert_equal(glare_sample_x(16777216, 16777217, 100), 99)\n",
          "    assert_equal(glare_sample_y(16777216, 16777217, 100), 99)\n",
          "    assert_equal(glare_sample_x(2, 3, 16777217), 13981014)\n",
          "    assert_equal(glare_cell_x(16777216, 16777217, 48), 47)\n",
          "    assert_equal(glare_cell_y(16777216, 16777217, 48), 47)\n",
          "    # A wide image or a wide grid on either axis uses the wide arithmetic.\n",
          "    assert_equal(glare_sample_y(2, 3, 16777217), 13981014)\n",
          "    assert_equal(glare_cell_x(2, 3, 16777217), 11184811)\n",
          "    assert_equal(glare_cell_y(2, 3, 16777217), 11184811)\n",
          "    # A coordinate at the far side reads the last column or row.\n",
          "    assert_equal(glare_sample_x(10, 10, 100), 99)\n",
          "    assert_equal(glare_sample_y(10, 10, 100), 99)\n",
          "    assert_equal(glare_cell_x(640, 640, 48), 47)\n",
          "    assert_equal(glare_cell_y(360, 360, 48), 47)\n",
          "    # Past 2^53 the last column's ratio is one, so it used to read one\n",
          "    # past the image and one past the grid. A zero side is not a column.\n",
          "    assert_equal(glare_sample_x(Int.MAX - 1, Int.MAX, 100), 99)\n",
          "    assert_equal(glare_sample_y(Int.MAX - 1, Int.MAX, 100), 99)\n",
          "    assert_equal(glare_cell_x(Int.MAX - 1, Int.MAX, 48), 47)\n",
          "    assert_equal(glare_cell_y(Int.MAX - 1, Int.MAX, 48), 47)\n",
          "    assert_equal(glare_sample_x(0, 0, 100), 0)\n",
          "    assert_equal(glare_sample_x(0, 2, 0), 0)\n",
          "    assert_equal(glare_sample_y(0, 0, 100), 0)\n",
          "    assert_equal(glare_sample_y(0, 2, 0), 0)\n",
          "    assert_equal(glare_cell_x(0, 0, 4), 0)\n",
          "    assert_equal(glare_cell_x(3, 10, 0), 0)\n",
          "    assert_equal(glare_cell_y(0, 0, 4), 0)\n",
          "    assert_equal(glare_cell_y(3, 10, 0), 0)\n"
        ]
      },
      {
        "start": 887,
        "stop": 937,
        "before": [],
        "after": [
          "    var values = List[Float32]()\n",
          "    values.append(0)\n",
          "    values.append(0)\n",
          "    values.append(0)\n",
          "    values.append(0)\n",
          "    values.append(8)\n",
          "    values.append(8)\n",
          "    values.append(8)\n",
          "    values.append(0)\n",
          "    values.append(2)\n",
          "    for slot in range(9):\n",
          "        var trial = values.copy()\n",
          "        trial[slot] = nan[DType.float32]()\n",
          "        var broken = anisotropic_step(\n",
          "            trial[0],\n",
          "            trial[1],\n",
          "            trial[2],\n",
          "            trial[3],\n",
          "            trial[4],\n",
          "            trial[5],\n",
          "            trial[6],\n",
          "            trial[7],\n",
          "            trial[8],\n",
          "        )\n",
          "        assert_equal(broken.taps, 1)\n",
          "        assert_equal(broken.lod, 0)\n",
          "    var capped = anisotropic_step(\n",
          "        1.0, 0.0, 0.0, 0.0001, 64.0, 64.0, Float32(1e20), 1.0, 2.0\n",
          "    )\n",
          "    assert_equal(capped.taps, 4096)\n",
          "    var none = lod_blend(0, 0)\n",
          "    assert_equal(none[0], 0)\n",
          "    assert_equal(none[1], 0)\n",
          "    var blend = lod_blend(1.5, 4)\n",
          "    assert_equal(blend[0], 1)\n",
          "    assert_equal(blend[1], 2)\n",
          "    assert_almost_equal(blend[2], 0.5)\n",
          "    var top = lod_blend(4, 4)\n",
          "    assert_equal(top[0], 4)\n",
          "    assert_equal(top[1], 4)\n",
          "    var huge = lod_blend(Float32(1e20), 4)\n",
          "    assert_equal(huge[0], 4)\n",
          "    assert_equal(huge[1], 4)\n",
          "    assert_equal(huge[2], 0)\n",
          "    var missing = lod_blend(nan[DType.float32](), 4)\n",
          "    assert_equal(missing[0], 4)\n",
          "    assert_equal(missing[1], 4)\n",
          "    var below = lod_blend(-1, 4)\n",
          "    assert_equal(below[0], 0)\n",
          "    assert_equal(below[1], 1)\n"
        ]
      },
      {
        "start": 1146,
        "stop": 1168,
        "before": [],
        "after": [
          "    # 2^63 meters is not a texel index. The patch is 8 m, so it repeats\n",
          "    # onto the same sample as the origin.\n",
          "    var origin = sample_surface(surface, 0, 2.5)\n",
          "    var spun = sample_surface(surface, Float32(9223372036854775808.0), 2.5)\n",
          "    assert_almost_equal(spun.height, origin.height)\n",
          "    var down = sample_surface(surface, 2.5, Float32(-9223372036854775808.0))\n",
          "    assert_almost_equal(down.height, sample_surface(surface, 2.5, 0).height)\n",
          "    var missing = sample_surface(surface, nan[DType.float32](), 2.5)\n",
          "    assert_almost_equal(missing.height, 0)\n",
          "    assert_almost_equal(missing.slope_x, 0)\n",
          "    assert_almost_equal(\n",
          "        sample_surface_smooth(\n",
          "            surface, Float32(9223372036854775808.0), 2.5\n",
          "        ).height,\n",
          "        sample_surface_smooth(surface, 0, 2.5).height,\n",
          "    )\n",
          "    assert_almost_equal(\n",
          "        sample_surface_filtered(\n",
          "            surface, nan[DType.float32](), 2.5, 0, 0, 0, 0, False\n",
          "        ).height,\n",
          "        0,\n",
          "    )\n"
        ]
      },
      {
        "start": 1172,
        "stop": 1176,
        "before": [],
        "after": [
          "    var missing_u = sample_pebble(bed, nan[DType.float32](), 0.5)\n",
          "    assert_almost_equal(missing_u.r, 0)\n",
          "    var missing_v = sample_pebble(bed, 0.25, nan[DType.float32]())\n",
          "    assert_almost_equal(missing_v.g, 0)\n"
        ]
      },
      {
        "start": 1178,
        "stop": 1219,
        "before": [],
        "after": [
          "    )\n",
          "    var missing_grad = sample_pebble_grad(\n",
          "        bed, inf[DType.float32](), 0.5, 0, 0, 0, 0\n",
          "    )\n",
          "    assert_almost_equal(missing_grad.b, 0)\n",
          "    var missing_grad_v = sample_pebble_grad(\n",
          "        bed, 0.25, nan[DType.float32](), 0, 0, 0, 0\n",
          "    )\n",
          "    assert_almost_equal(missing_grad_v.r, 0)\n",
          "    with assert_raises(contains=\"larger than this port\"):\n",
          "        _ = PebbleBed(1 << 31, 1 << 31, List[Float32]())\n",
          "\n",
          "\n",
          "def test_a_far_axis_repeats_beside_a_near_or_missing_axis() raises:\n",
          "    var grid = ComplexField(SpectrumResolution(8))\n",
          "    for y in range(8):\n",
          "        for x in range(8):\n",
          "            grid.put(x, y, 0, Float32(x + 8 * y))\n",
          "    var surface = SurfaceField(Length(8), grid^)\n",
          "    # 2^63 meters is not a texel index. The patch is 8 m, so it repeats\n",
          "    # onto the origin.\n",
          "    var far = Float32(9223372036854775808.0)\n",
          "    var missing = nan[DType.float32]()\n",
          "    assert_almost_equal(\n",
          "        sample_surface_smooth(surface, 2.5, far).height,\n",
          "        sample_surface_smooth(surface, 2.5, 0).height,\n",
          "    )\n",
          "    assert_almost_equal(\n",
          "        sample_surface_filtered(surface, far, 2.5, 0, 0, 0, 0, False).height,\n",
          "        sample_surface_filtered(surface, 0, 2.5, 0, 0, 0, 0, False).height,\n",
          "    )\n",
          "    # A position with one missing axis is flat, also when the other axis\n",
          "    # is far.\n",
          "    assert_almost_equal(sample_surface(surface, far, missing).height, 0)\n",
          "    assert_almost_equal(sample_surface_smooth(surface, missing, 2.5).height, 0)\n",
          "    assert_almost_equal(sample_surface_smooth(surface, far, missing).height, 0)\n",
          "    assert_almost_equal(\n",
          "        sample_surface_filtered(\n",
          "            surface, 2.5, missing, 0, 0, 0, 0, False\n",
          "        ).height,\n",
          "        0,\n"
        ]
      },
      {
        "start": 1244,
        "stop": 1245,
        "before": [
          "    var image = CausticField(1, Length(1))\n"
        ],
        "after": [
          "    var plane = List[Float32](length=1, fill=0)\n"
        ]
      },
      {
        "start": 1248,
        "stop": 1266,
        "before": [],
        "after": [
          "    # One texel on a patch of a meter, the green channel, no shift.\n",
          "    var splat = _Splat(1, 1, 1, 1, 0, 0, 0.5, 1)\n",
          "    var out = plane.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin]()\n",
          "    var xs = (\n",
          "        x.unsafe_ptr()\n",
          "        .unsafe_mut_cast[False]()\n",
          "        .unsafe_origin_cast[ImmutAnyOrigin]()\n",
          "    )\n",
          "    var zs = (\n",
          "        z.unsafe_ptr()\n",
          "        .unsafe_mut_cast[False]()\n",
          "        .unsafe_origin_cast[ImmutAnyOrigin]()\n",
          "    )\n",
          "    var lives = (\n",
          "        live.unsafe_ptr()\n",
          "        .unsafe_mut_cast[False]()\n",
          "        .unsafe_origin_cast[ImmutAnyOrigin]()\n",
          "    )\n"
        ]
      },
      {
        "start": 1267,
        "stop": 1269,
        "before": [
          "    _splat(image, x, z, live, 0, 1, 2, 1, 0, 0, 0, 0, 0.5, 1)\n",
          "    assert_almost_equal(image.channel(0, 0, 1), Float32(0))\n"
        ],
        "after": [
          "    _splat(out, xs, zs, lives, 0, 1, 2, 0, 0, splat)\n",
          "    assert_almost_equal(plane[0], Float32(0))\n"
        ]
      },
      {
        "start": 1277,
        "stop": 1282,
        "before": [
          "    _splat(image, x, z, live, 0, 1, 2, 1, 0, 0, 0, 0, 0.5, 1)\n",
          "    assert_almost_equal(image.channel(0, 0, 1), Float32(40))\n"
        ],
        "after": [
          "    _splat(out, xs, zs, lives, 0, 1, 2, 0, 0, splat)\n",
          "    assert_almost_equal(plane[0], Float32(40))\n",
          "    _ = len(x)\n",
          "    _ = len(z)\n",
          "    _ = len(live)\n"
        ]
      },
      {
        "start": 1991,
        "stop": 1993,
        "before": [],
        "after": [
          "        _height_bound(surface, water._ripples),\n",
          "        False,\n"
        ]
      },
      {
        "start": 2219,
        "stop": 2290,
        "before": [],
        "after": [
          "def test_cheaper_water_shades_a_grid_and_keeps_its_surface() raises:\n",
          "    var stones = _stones()\n",
          "    var width = 29\n",
          "    var height = 41\n",
          "    var camera = _page_camera(width, height)\n",
          "    var fine = _scene(Duration(5.0, SECOND))\n",
          "    var coarse = _scene(Duration(5.0, SECOND))\n",
          "    coarse.shade_step = 4\n",
          "    coarse.refresh_every = 3\n",
          "    var one = Framebuffer(width, height, Color(0, 0, 0))\n",
          "    var two = Framebuffer(width, height, Color(0, 0, 0))\n",
          "    var drawn = fine.compose(one, camera, Length(0.0, METER), stones)\n",
          "    assert_true(drawn > 0)\n",
          "    assert_true(coarse.compose(two, camera, Length(0.0, METER), stones) > 0)\n",
          "    # Shaded on a grid and mixed between, the water is near the fine one.\n",
          "    var near = 0\n",
          "    for i in range(width * height):\n",
          "        var a = one.pixels[i * 4]\n",
          "        var b = two.pixels[i * 4]\n",
          "        if abs(Int(a) - Int(b)) < 40:\n",
          "            near += 1\n",
          "    assert_true(near > width * height * 3 // 4)\n",
          "    # An eye just above the still water, below the highest wave, tests\n",
          "    # every pixel where the waves are.\n",
          "    var low = _page_camera(width, height)\n",
          "    low.place(Vector3(0, 0.002, 0), Vector3(0, -0.5, -3))\n",
          "    var skim = Framebuffer(width, height, Color(0, 0, 0))\n",
          "    assert_true(fine.compose(skim, low, Length(0.0, METER), stones) > 0)\n",
          "    # The surface found on the third call is shown from the fourth.\n",
          "    for _ in range(4):\n",
          "        var frame = Framebuffer(width, height, Color(0, 0, 0))\n",
          "        _ = coarse.compose(frame, camera, Length(0.0, METER), stones)\n",
          "    assert_false(Bool(coarse._surface_next))\n",
          "    # A view with no water rows draws nothing.\n",
          "    var sky = Framebuffer(width, height, Color(0, 0, 0))\n",
          "    for i in range(width * height):\n",
          "        sky.depth[i] = -1\n",
          "    assert_equal(coarse.compose(sky, camera, Length(0.0, METER), stones), 0)\n",
          "    with assert_raises(contains=\"shade step\"):\n",
          "        coarse.shade_step = 0\n",
          "        _ = coarse.compose(sky, camera, Length(0.0, METER), stones)\n",
          "    with assert_raises(contains=\"shade step\"):\n",
          "        coarse.shade_step = 65\n",
          "        _ = coarse.compose(sky, camera, Length(0.0, METER), stones)\n",
          "    with assert_raises(contains=\"refresh\"):\n",
          "        coarse.shade_step = 2\n",
          "        coarse.refresh_every = 0\n",
          "        _ = coarse.compose(sky, camera, Length(0.0, METER), stones)\n",
          "\n",
          "\n",
          "def test_calm_ripples_skip_their_step_and_caustics_split_by_channel() raises:\n",
          "    var water = _scene(Duration(5.0, SECOND))\n",
          "    water.advance(Duration(1.0 / 60.0, SECOND), False)\n",
          "    assert_true(water._calm)\n",
          "    var still = water._ripples.normal.copy()\n",
          "    water.advance(Duration(1.0 / 60.0, SECOND), False)\n",
          "    assert_true(water._ripples.normal == still)\n",
          "    water.reset()\n",
          "    assert_false(water._calm)\n",
          "    # A window that is level but still moving is not at rest.\n",
          "    water._ripples.velocity[3] = 0.01\n",
          "    assert_false(_at_rest(water._ripples))\n",
          "    # One worker splats the channels in turn; every core gives its bits.\n",
          "    var surface = water._surface()\n",
          "    water.workers = 1\n",
          "    var serial = water._caustics(surface)\n",
          "    water.workers = 0\n",
          "    var parallel = water._caustics(surface)\n",
          "    assert_true(serial.samples == parallel.samples)\n",
          "\n",
          "\n"
        ]
      }
    ]
  },
  "tests/test_wide_lines.mojo": {
    "before_sha256": "f72f98f16f8ba22c5437c4710bd4d8aae033db7d129c3ca1655c6f9200630f34",
    "after_sha256": "4d928c5518aee857a8e23ac837d44c8a0523f7069318613d9d2015d669f3bbb0",
    "before_token_sha256": "79fdf0adf536ec84776d40a47bc7101a8a2db84c37d616d9a30bccbba9487a2c",
    "after_token_sha256": "01e5e15f1989d7c425557eb74b59c4d3f83caf1e53abf8959b50f12ce8890008",
    "edits": [
      {
        "start": 297,
        "stop": 317,
        "before": [],
        "after": [
          "    # The repeat count is 2^63. The old subtraction overflowed, and the\n",
          "    # walk did not finish.\n",
          "    var far = Float32(4611686018427387904.0)\n",
          "    with assert_raises(contains=\"too fine\"):\n",
          "        _ = dash_spans(-far, far, 0.5, 0.5)\n",
          "    # A quotient past 2^63 is not a repeat index. The segment used to\n",
          "    # draw nothing.\n",
          "    var huge = Float32(1e20)\n",
          "    with assert_raises(contains=\"too fine\"):\n",
          "        _ = dash_spans(0, huge, 1, 1)\n",
          "    with assert_raises(contains=\"too fine\"):\n",
          "        _ = dash_spans(-huge, 0, 1, 1)\n",
          "    with assert_raises(contains=\"distance must be finite\"):\n",
          "        _ = dash_spans(nan[DType.float32](), 4, 1, 1)\n",
          "    with assert_raises(contains=\"distance must be finite\"):\n",
          "        _ = dash_spans(0, inf[DType.float32](), 1, 1)\n",
          "    with assert_raises(contains=\"pattern must be finite\"):\n",
          "        _ = dash_spans(0, 4, nan[DType.float32](), 1)\n",
          "    with assert_raises(contains=\"pattern must be finite\"):\n",
          "        _ = dash_spans(0, 4, -1, 1)\n"
        ]
      }
    ]
  },
  "core/fog.mojo": {
    "before_sha256": "8026f0db83e2eef31d0e63793f65a449cb9eebae917e081e950a851ab98ca66c",
    "after_sha256": "5fc886a7eb9fdc5e78a9f68bfec300db4d88e95d14c3c6fa8af2add0abfdd342",
    "before_token_sha256": "f9977a301ec01207ac7e7ab352e95305d7c7e1b611c3a7a85dbeea92ee498261",
    "after_token_sha256": "f61b6984ab2c72744a6f681956f22410d5627efbd6e25304c47fa76c3ff36810",
    "edits": [
      {
        "start": 66,
        "stop": 67,
        "before": [
          "from std.math import exp, isfinite\n"
        ],
        "after": [
          "from std.math import exp, exp2, isfinite\n"
        ]
      },
      {
        "start": 239,
        "stop": 265,
        "before": [],
        "after": [
          "comptime LOG2_E = Float32(1.4426950408889634)\n",
          "\"\"\"`log2(e)`, to take `exp(x)` as `exp2(x * LOG2_E)`.\"\"\"\n",
          "\n",
          "\n",
          "@always_inline\n",
          "def exp2_veil[\n",
          "    w: Int\n",
          "](density: Float32, depth: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:\n",
          "    \"\"\"Return how much of an exponential-squared fog's color shows.\n",
          "\n",
          "    Parameters:\n",
          "        w: The SIMD width.\n",
          "\n",
          "    Args:\n",
          "        density: How fast the fog thickens.\n",
          "        depth: The camera-space depth of each lane.\n",
          "\n",
          "    Returns:\n",
          "        `1 - exp(-(density * depth)^2)` for each lane, with the power\n",
          "        taken as `exp2` of the exponent times `log2(e)`: `exp2` is one\n",
          "        vector instruction on every width, and `exp` is a call a lane.\n",
          "    \"\"\"\n",
          "    var scaled = density * depth\n",
          "    return 1 - exp2(-(scaled * scaled) * LOG2_E)\n",
          "\n",
          "\n"
        ]
      },
      {
        "start": 293,
        "stop": 294,
        "before": [
          "        var scaled = density * depth\n",
          "        return 1 - exp(-scaled * scaled)\n"
        ],
        "after": [
          "        return exp2_veil[1](density, depth)\n"
        ]
      }
    ]
  },
  "core/geometry_store.mojo": {
    "before_sha256": "c42cde4b1e8c5668b138d462a997ac23d36cfe9789cddd22eaee142a2cec6f06",
    "after_sha256": "771d8d8b068353bf23c0f572511c981a2a67c375cfaa2b8c63a5a5ab103a16c3",
    "before_token_sha256": "095e5b75ab174c143d40a630c09ad230114fa2052e50fef1c47944c5f7f8f5c0",
    "after_token_sha256": "cf12dc2c69d05624c5a04ed6e9362d436ddf65a4e01f74a423cca56e8ed1823d",
    "edits": [
      {
        "start": 47,
        "stop": 50,
        "before": [],
        "after": [
          "    # How many times each geometry has been replaced. A cache of a\n",
          "    # geometry's data reads it again when this changes.\n",
          "    var _generations: List[Int]\n"
        ]
      },
      {
        "start": 59,
        "stop": 60,
        "before": [],
        "after": [
          "        self._generations = List[Int]()\n"
        ]
      },
      {
        "start": 76,
        "stop": 84,
        "before": [
          "        return GeometryId(len(self.geometries) - 1)\n"
        ],
        "after": [
          "        var index = len(self.geometries) - 1\n",
          "        # A caller that popped a geometry off `geometries` reuses its id,\n",
          "        # and the id's new geometry must read as changed.\n",
          "        if index < len(self._generations):\n",
          "            self._generations[index] += 1\n",
          "        else:\n",
          "            self._generations.append(0)\n",
          "        return GeometryId(index)\n"
        ]
      },
      {
        "start": 136,
        "stop": 157,
        "before": [],
        "after": [
          "        self._generations[id.value] += 1\n",
          "\n",
          "    def generation(self, id: GeometryId) raises -> Int:\n",
          "        \"\"\"Return how many times a geometry has been replaced.\n",
          "\n",
          "        A cache of a geometry's data keeps the generation it read, and reads\n",
          "        the geometry again when `replace` gives it a new one. A geometry\n",
          "        changed in place through `geometries` keeps its generation.\n",
          "\n",
          "        Args:\n",
          "            id: Which geometry.\n",
          "\n",
          "        Returns:\n",
          "            Zero for a geometry never replaced, and one more for each\n",
          "            `replace`.\n",
          "\n",
          "        Raises:\n",
          "            Error: If no geometry has that id.\n",
          "        \"\"\"\n",
          "        self._require_geometry(id)\n",
          "        return self._generations[id.value]\n"
        ]
      }
    ]
  },
  "render/tonemap.mojo": {
    "before_sha256": "b76247c94eb39a631b0b0cc24711e29babc23ef5fc1fd20b99ea4ea561995f5e",
    "after_sha256": "3728b3c1585ba0a2c62745c6f0752cd42d4298de184c1886b292ef530117f85a",
    "before_token_sha256": "2f181f1b161344e188b9a9b96c4a024b877856e27ee2686f3937f6936b3f90be",
    "after_token_sha256": "cba4eb4dd92cb96f307042ecd2bffc387dd316ae88dc252cf1c9022c22e1e72b",
    "edits": [
      {
        "start": 191,
        "stop": 225,
        "before": [
          "def _rrt_and_odt_fit(v: Float32) -> Float32:\n",
          "    \"\"\"One channel of three.js's `RRTAndODTFit`, the ACES curve itself.\"\"\"\n"
        ],
        "after": [
          "@always_inline\n",
          "def saturate_lanes[\n",
          "    w: Int\n",
          "](value: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:\n",
          "    \"\"\"Return each lane held from zero to one, as GLSL's `saturate`.\n",
          "\n",
          "    `max(0, min(1, value))`, the operations of `math.utils.saturate` in\n",
          "    its order, so a lane gives the bits that the scalar call gives.\n",
          "\n",
          "    Parameters:\n",
          "        w: The SIMD width.\n",
          "\n",
          "    Args:\n",
          "        value: The lanes.\n",
          "\n",
          "    Returns:\n",
          "        Each lane within zero and one.\n",
          "    \"\"\"\n",
          "    return max(SIMD[DType.float32, w](0), min(SIMD[DType.float32, w](1), value))\n",
          "\n",
          "\n",
          "@always_inline\n",
          "def aces_fit[w: Int](v: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:\n",
          "    \"\"\"Return three.js's `RRTAndODTFit`, the ACES curve itself, on each lane.\n",
          "\n",
          "    Parameters:\n",
          "        w: The SIMD width.\n",
          "\n",
          "    Args:\n",
          "        v: One channel in the ACES working primaries.\n",
          "\n",
          "    Returns:\n",
          "        The fitted channel.\n",
          "    \"\"\"\n"
        ]
      },
      {
        "start": 228,
        "stop": 274,
        "before": [],
        "after": [
          "\n",
          "\n",
          "@always_inline\n",
          "def aces_tone[\n",
          "    w: Int\n",
          "](\n",
          "    r: SIMD[DType.float32, w],\n",
          "    g: SIMD[DType.float32, w],\n",
          "    b: SIMD[DType.float32, w],\n",
          "    exposure: Float32,\n",
          ") -> Tuple[\n",
          "    SIMD[DType.float32, w], SIMD[DType.float32, w], SIMD[DType.float32, w]\n",
          "]:\n",
          "    \"\"\"Return three.js's `ACESFilmicToneMapping` of linear light.\n",
          "\n",
          "    Scaled by the exposure over 0.6, into the ACES working primaries by\n",
          "    `ACESInputMat`, through `aces_fit`, back out by `ACESOutputMat`, and\n",
          "    clamped.\n",
          "\n",
          "    Parameters:\n",
          "        w: The SIMD width.\n",
          "\n",
          "    Args:\n",
          "        r: The red channel, linear.\n",
          "        g: The green channel, linear.\n",
          "        b: The blue channel, linear.\n",
          "        exposure: The exposure.\n",
          "\n",
          "    Returns:\n",
          "        The tone-mapped red, green and blue, each from zero to one.\n",
          "    \"\"\"\n",
          "    var scale = exposure / 0.6\n",
          "    var sr = r * scale\n",
          "    var sg = g * scale\n",
          "    var sb = b * scale\n",
          "    var ir = 0.59719 * sr + 0.35458 * sg + 0.04823 * sb\n",
          "    var ig = 0.07600 * sr + 0.90834 * sg + 0.01566 * sb\n",
          "    var ib = 0.02840 * sr + 0.13383 * sg + 0.83777 * sb\n",
          "    var fr = aces_fit(ir)\n",
          "    var fg = aces_fit(ig)\n",
          "    var fb = aces_fit(ib)\n",
          "    return (\n",
          "        saturate_lanes(1.60475 * fr - 0.53108 * fg - 0.07367 * fb),\n",
          "        saturate_lanes(-0.10208 * fr + 1.10813 * fg - 0.00605 * fb),\n",
          "        saturate_lanes(-0.00327 * fr - 0.07276 * fg + 1.07602 * fb),\n",
          "    )\n"
        ]
      },
      {
        "start": 283,
        "stop": 284,
        "before": [
          "    has no matrix type.\n"
        ],
        "after": [
          "    has no matrix type. `aces_tone` at width one.\n"
        ]
      },
      {
        "start": 285,
        "stop": 287,
        "before": [
          "    var scale = exposure / 0.6\n",
          "    var sr = r * scale\n",
          "    var sg = g * scale\n",
          "    var sb = b * scale\n",
          "    var ir = 0.59719 * sr + 0.35458 * sg + 0.04823 * sb\n",
          "    var ig = 0.07600 * sr + 0.90834 * sg + 0.01566 * sb\n",
          "    var ib = 0.02840 * sr + 0.13383 * sg + 0.83777 * sb\n",
          "    var fr = _rrt_and_odt_fit(ir)\n",
          "    var fg = _rrt_and_odt_fit(ig)\n",
          "    var fb = _rrt_and_odt_fit(ib)\n",
          "    return FloatColor(\n",
          "        saturate(1.60475 * fr - 0.53108 * fg - 0.07367 * fb),\n",
          "        saturate(-0.10208 * fr + 1.10813 * fg - 0.00605 * fb),\n",
          "        saturate(-0.00327 * fr - 0.07276 * fg + 1.07602 * fb),\n",
          "    )\n"
        ],
        "after": [
          "    var toned = aces_tone[1](r, g, b, exposure)\n",
          "    return FloatColor(toned[0], toned[1], toned[2])\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_main_rebase_successor.py": {
    "before_sha256": "2ca5e9f72a38766945e182fbe004e3e64011efa897e22445ab7372102634a792",
    "after_sha256": "2703f53a7e97665590595428491ff05428c2cbff3b7ffc514a8561e10ce8168e",
    "before_token_sha256": "37aacea9b14d4507130af4c73e47892ef4d5340813b1a221db765aec9379c6a5",
    "after_token_sha256": "b208fbec1a3325401316ce2bd088a34f5ccf4b6bac1b6c7017fbd28b076b7664",
    "edits": [
      {
        "start": 45,
        "stop": 47,
        "before": [],
        "after": [
          "                # A reviewed PR780 successor keeps main's bytes as its exact predecessor.\n",
          "                raw = owner.pr780_successor.predecessor_bytes(path, raw)\n"
        ]
      }
    ]
  },
  "tools/carla_lane_oracle/test_shared_helper_contracts.py": {
    "before_sha256": "63645797e8134e48b9a9bcfe01b33fcba83ac9c140e696af23937c43296ca494",
    "after_sha256": "e7a600c523f2c85ad82051ab3c85bee3a88c82ea3555849e5dd45728bbca5715",
    "before_token_sha256": "44335a69c3c21ac57fc2925684cd62a5ffb1703180e6ea152bc0043fdc21eb03",
    "after_token_sha256": "0d1e9c36c7cc9ae93e08ff4d2f29a079ec251365af2ded3d353bcd19b6d8bb3d",
    "edits": [
      {
        "start": 147,
        "stop": 150,
        "before": [
          "        self.assertTrue(cleanup.typed_boundary.is_current(fixture, raw))\n"
        ],
        "after": [
          "        # #792 extended the typed endpoint; the PR780 predecessor is that endpoint.\n",
          "        self.assertTrue(cleanup.typed_boundary.is_current(\n",
          "            fixture, cleanup.pr780_successor.predecessor_bytes(fixture, raw)))\n"
        ]
      }
    ]
  }
}
''')
BOUND_INPUTS = {'tests/test_anatomy_muscle.mojo': '3653d6056c1f9f639537eedb7cd80364baf80352b4aa984d39c0e737d8801401',
 'tests/test_animation_strings.mojo': 'f5103e3660a63d3d5d9d348a0d928fa106e5cef03059d432a31335bb7dd14184',
 'tests/test_loader_bounds.mojo': '6e0c1487f1ff21f4654c2790e4460c0adf934bf6b9273e826782eec1bfed2d83',
 'tools/carla_lane_oracle/test_pr780_source_successor.py': 'fad1fe54f34c47efeff20f5d26f3c644dcc6eb129848290bada4235215815606'}
EDGE_SHA256 = {'core/deform.mojo': 'b6afec67eea77b1a76cae98df1b4399de366b2a82878edf56aa1b53d26c046e9',
 'core/extent.mojo': '3bde830a747999835ef471ceba2eac3e73bbff4e300162851a8096a194a58726',
 'core/fog.mojo': '169cba41367e8b43aa03669352d7cd95b4cbda487c1a2cbd9ec5b762268e8083',
 'core/gaussian_splat_utils.mojo': 'f2cfee48e9ad27ec981475898fc9be0b00e0f89c11d14c1f8775d6354e44aaef',
 'core/geometry_store.mojo': 'abc0642924c935f50f727de2bfb9ebe5e6ef00f1bf3cb21c2090c15e15f20483',
 'core/morph.mojo': '920451971fca0b7d64687981ecea353290f959fa88cc8a6406dd4b070119d25a',
 'core/raycaster.mojo': 'da6491a955938b7fd883bd44ad72b0d2c20ee978e8156e98a120e263d18c4d95',
 'extensions/carla/agents.mojo': '7dc1f0300ff6b23cbd8d6190647ca17c544baeaa826d1085863a5e3a51eb3477',
 'extensions/carla/agents_route.mojo': 'a71d4f7a33296671ff481134438f871ccd313299563e6c865972359e0508c4d3',
 'extensions/carla/assets.mojo': '1f82f569bc1ee02238d2925e063ab4a1bccf71b80d2045d4197695d164123fa9',
 'extensions/carla/cameras.mojo': '5eb8f2f38290d3328361cd4c8c03775fd11d4c21bfcdd01c483afe2231832d1e',
 'extensions/carla/geometry.mojo': '8e4dc462a9a4544066ba162b7afe9739456342ac778d159d77855e5fb4019683',
 'extensions/carla/lane_geometry.mojo': '2bd5a91d7e40d2b3e40314f753184002ba7aee0eccab46900a9dddbb53d7e382',
 'extensions/carla/lidar.mojo': '0412a9fb327c1134e1ddde0b9411197172b9f1867d66279e85f1fbe4d3841cdf',
 'extensions/carla/map.mojo': '7ef06d5eadf7933d6caec740444cf39ae2a48da5a22fcbb9092632196f955b21',
 'extensions/carla/map_builder.mojo': 'f10f4855653a78039ea7b08e16732f20cd2c810b347dca7ed650bb9bb8ffac39',
 'extensions/carla/math.mojo': '4d0770dc31ef89a0438eb1ad4cda697ec09bee8ca71aa69dbf82085c62f40500',
 'extensions/carla/model_cache.mojo': '33f5acadc7a3efbab1fa2481da70d2c920034f337d646c85caf87e432c7d1d1d',
 'extensions/carla/navigation_mesh.mojo': '31e8ea1ce205256e623588ddaee54e745d40ee08d91941cdb9ec16af1ba79961',
 'extensions/carla/physics/simulation.mojo': 'f07fa2f08961b9b087d6e0b9849c4a05ccef52276ceefe57211fe806c9638867',
 'extensions/carla/radar.mojo': '6a15d7c7edcb813a2cf627d328a7450c5c9ad1b3456af39eb1df669a3546772e',
 'extensions/carla/render_post.mojo': 'c0a2820c6a6e1434f89e73a6385ef9ff749d67e5ccc1e50577ca19ccaa24a1e7',
 'extensions/carla/render_sky.mojo': '35caf04e12b7137690c73ba9aafc16234bd33379d47412fdd6a62ccdcd10d236',
 'extensions/carla/render_textures.mojo': '7816aa15fb9eed608183777ab26769688540e84453eb0021bf64b2a930b39e2a',
 'extensions/carla/render_weather.mojo': 'df1f076e52c856b2279c50293edfadb81bb22ee1968cc4f2f7604b31d2133b72',
 'extensions/carla/semantic_lidar.mojo': 'e72064a4b99d643585b07bc1d0e888248710d71de3dd8dbf8e249e545b08b0a3',
 'extensions/carla/sensor.mojo': '4f8123d63ba83d79627b57c8f15bce7027a8c40f622a8c187e4bcdb4b89496df',
 'extensions/carla/sensor_data.mojo': 'fd7f9bed3a11bfc5d48c8397259e16957d187a747dc83d49cff31133f854ad3b',
 'extensions/carla/sensor_manager.mojo': '26af2114c101807527138252638fa5d85a3a4bed2c4fa63679723d8f62429639',
 'extensions/carla/speed_limits.mojo': '9ea486a37f7b62ff037dcf11d5482153466d6f8ef01f729efe5e85b5c739dac5',
 'extensions/carla/town.mojo': '4becbe2f7273cfbc0406779aa1e385e9cf95bace0b3e4af2f2a4099f30b1fb4a',
 'extensions/carla/traffic_light.mojo': '28c15cdf7fd23ca3eedc849bee6b918bd2e915a463cfc7d945243eea7c3dd2c0',
 'extensions/carla/traffic_sign.mojo': '361bd58742d1d9f96051bf8a4aa312a8711bbaf20bb5868c6d1f30a9f53ead56',
 'extensions/carla/v2x.mojo': 'fe4f85ef760c4b25d99b75ab05b7f137f7e22041129f2e0ed8f8f63f887e99d8',
 'extensions/carla/world.mojo': 'aeec9ddf2a5c0a2546e82643678125e2dad5bfca9437421f6ba3e8bd7a2db6ca',
 'extensions/humanoid/skeleton/head/hair/groom.mojo': '35bf93c386804e0836a953b981790af7378e42362f4cb72e0d1622f785542c00',
 'extensions/humanoid/skeleton/head/hair/shading.mojo': '750bad042961cf21294f6a0c352ca332d42fce673acea3643b4a39a4bf77003f',
 'extensions/humanoid/skeleton/head/hair/strands.mojo': '7448d4398a1552b0fce1ee1a4131c5f667e79f0854c56f45ddda8fa8f37fdc7f',
 'extensions/physics/world.mojo': '651e723bc91bf4571740dbb09bd87b79f87ba09557886dd01818a6fc58ca9652',
 'extensions/streamline/jitter.mojo': '14c5e5ade3adcfb47dd98956111a63c72ca32cf72cbe2e9d58553a4988c3f625',
 'extensions/streamline/sizing.mojo': '277c1e59b3adb49e2f408132784d5fa6966e6b2982f4c4302c237a19b0642ab7',
 'extensions/streamline/upscaler.mojo': '82562a1c39870c43667d0c0ee62f349f587f17089e094b48d10d919e8afe2230',
 'geometries/attribute_utils.mojo': 'b64808aa33e920a8d55294eb65e40e76379642771cbf391f7195b030be8b359d',
 'geometries/box.mojo': 'e9261ef7fb92f6f6ceed4d8c802b2ba85799a6a3bdd88954c55ac9c3a130dadc',
 'geometries/capsule.mojo': 'd494e0e786b51b4341c10a8c564de270335589a47358c68040eae50a7f616915',
 'geometries/circle.mojo': '577e59e679b5f5d125cc6c19df7fb7324f314cc0bdfae55b7f0707c343657313',
 'geometries/cylinder.mojo': '334c35edbe3cebd1e253cf2dbd2c09c6e0db68f9a7a8db441642128d24c10c81',
 'geometries/plane.mojo': '497d5defae8188b8e1c40036ed05252c11a2fcdbdaba2fddc4c385b1acdb0315',
 'geometries/rounded_box.mojo': '55ac8d0f7f5f59b6dfb2fea1855ed3d46fae5bba5c8fe44bf1b338be0fecaaad',
 'geometries/sphere.mojo': 'cf8ce17c7391467ced87e7b7d4ae4b2be7769d862d240e16f5c811194556e5c2',
 'geometries/surface.mojo': '400741e666390985d0d97040de3bbc06f7e1b002d460fd07e765266ac1681dd5',
 'lights/csm.mojo': 'dd3e60b605242700c39f701f066c2419c955beabbaa17fef51f5c8c6953fdaf3',
 'lights/shadow.mojo': '1565cd6fc6da6dab3f851c7217596f8ba72aa9a29516375877664b34c6ff7861',
 'loaders/bytes.mojo': '7e433bce46cd84a26d82898684ddc565f9ce43e10a147a4ca17f1cbaee424683',
 'loaders/draco.mojo': 'e50c9ca8beed22e467b2adf8057ea34da9e02402ea0d268bed90ec03ab45eec7',
 'loaders/draco_mesh.mojo': 'a2d7906ebb2a158d60c39600a1715f39575c05b9694887ff9669b13a0a0670dd',
 'loaders/gltf_layout.mojo': '3faf915314dbc3859d1a77f8726ff4813141452f119370a9efe62415ee6def4d',
 'loaders/image_batch.mojo': '3cfee85ce4e0e788deee3556bd33866f2e801c23a8d4c08f7e82f3bd3747c4f3',
 'loaders/js_number.mojo': '09c981f063332e9a8eb35102bc63c812e142d74c97d8dd61dc32f526cf68c6b3',
 'loaders/meshopt.mojo': '2e6e4544b362eb86202877b7d0f59655cf9755392bf2bc6a653e13674da6e1e5',
 'loaders/vrml_geometry.mojo': 'be56edbb5b62f74ae3f785e6eb98dc58d927e52b0e14bae2c3f8ebb4dc548ef8',
 'materials/material.mojo': '0a954f13d419b16c2030f105018d25f3fac4ab2eaf7e46df04654421c0395ada',
 'materials/volume_node_material.mojo': 'bf69266b2a7e76ee130609d963d7cde5d8e689f3ee84c2bdc5dd3482bb12f8a9',
 'math/convex_hull.mojo': '7c3f56da413ade65c3f40974cc86c1e2f91029e920206566f9952ebedd589e11',
 'math/curve.mojo': '32d98bdd06a489fb45fbcef911af073651389c231078af5f1d83a76acd391cc3',
 'math/curve_checks.mojo': 'abd2d874b739d4b7ebd1e6d7da48a9b7c9f3b692dcae5336f4875c108dce6ef9',
 'math/matrix4.mojo': '3a14fb7473be39825f01e0b25141dc11deae32815083038f273f1dc88f0d3b45',
 'math/path.mojo': '6c2cd1c42f7df845460b128c2765c02410dfd1ebbbe057c2623ac1fa283ccf2c',
 'math/square_matrix.mojo': '0654dc0cfd85f05b383961d1507464559d00fefc15e49d682d8d3a4a8aa95ed9',
 'math/utils.mojo': 'f7ec709a20c0823399e0948bf9b6b7a60739516317789053a06bce248741214e',
 'math/vector4.mojo': '3bf820cf0f2f9ad74083de036282f10d01d9fed78a6a90ac2ff65bfa6bc440d1',
 'objects/gaussian_splat.mojo': '4469b3d742b43810e8752266ef1b5f6d10fbf5894d46d434c2bc26cf4ab51483',
 'objects/line_segments2.mojo': '289763b1859e683324ce7cfaee1096753f2c3c92ad0bf0e7f0d96f95c790db0e',
 'postprocessing/antialiasing.mojo': '93b3732b150959edfd3cca78e5df6c151aa2cf3939bfc548be3043e261fe7372',
 'postprocessing/composer.mojo': 'cf71d82388dfbaee968e0bfaf9b9fdc175aaa576bc8d7314552c30001b284006',
 'postprocessing/denoise.mojo': '66a3f8468a202f4c1874e3c1d16c323e92ab095cfa2ed9a97e64d4bfc1c868c7',
 'postprocessing/display_nodes.mojo': '971406c79c83b54b0e9057b69f4b5ac6604140bd483d18053645048c857d8577',
 'postprocessing/effects.mojo': '035bac80d3148af61d2c77cd2b3130e24656a3bcf4025943a426714871dbd60a',
 'postprocessing/filter_nodes.mojo': 'e4418b40903991eda041b79ba1a8f43d06ed36ca9d8c1e06cf99f88bf8f5fd50',
 'postprocessing/gtao.mojo': 'c0fd6ed0a7662e96e548e7b5b90f6ddef4dd5f155a565493438c2e02e341c98a',
 'postprocessing/render_passes.mojo': '9eb2200bfdf9efe3c4db4c342dc9c7e1e2ff0f43d30ca28e7be0e2306c8daf7e',
 'postprocessing/sampling.mojo': 'c5c15e4de46908a89b6be38cbc88faa68e1039383450a47a28e261d31d8ac537',
 'postprocessing/screen_space.mojo': '8b775f0e8c9dadc722649e591537cf4a6c7919bfdc2660b0a7821325cbd88a5f',
 'postprocessing/shaders.mojo': '6e045ed0a008b33c9cbbe387c39b3a5c2a2c438052142ec7910c625f5e7ec203',
 'postprocessing/ssgi.mojo': '2e2f13286c83e2299f64e95d7b1c4e6ccaa6942c436398f27709762e768dc4e4',
 'postprocessing/ssr_node.mojo': '1db558f15ab39622488a946dff80d96ddc3eb9a7aceaba245716d3fd37145bb0',
 'postprocessing/taau.mojo': '5b17a928ea6bdd319d7ceab2386d3666bc8b623fc9ae753e9da54f0acb171e59',
 'postprocessing/temporal_denoise.mojo': 'b86a5f719bde54b48ac4689166fb04deec68dc26727974a795ed4959985b3d1a',
 'postprocessing/traa.mojo': 'd6c055c6bee0772dffa4e57900adaf201f7401554140b8ac2539ce3b6e411e92',
 'postprocessing/upscaling.mojo': '34ee75f2df77f57f453a8dc0c2769285b331581534cc2449779a2363cfa9d443',
 'render/css_color.mojo': '074ed0833eea912037bbc6bad7830ca8359b82f7ac4258deb2ea386fa929c695',
 'render/cube_texture.mojo': 'd6ea30d4b84b172d18cd50c0ce40c5b64935e7dfaacd1d73556f126f38109423',
 'render/cube_uv.mojo': 'b0b46e71d1bdda93c0bebe1b0a7d398cfb69fbe30e09d0397c1a3434115088b8',
 'render/fillrule.mojo': '5d5df92eb9b636e09d79badb5adc5e988adda45b7f72684b884f2667a056935c',
 'render/framebuffer.mojo': '114b6668d2e56e998d61aa620691f91858e49bcb6f54fa610dada48e6815c646',
 'render/jpeg.mojo': '84d35611bdd32872c724b5eee78f26e547ec6f3830447b5df38506afc603b953',
 'render/linerule.mojo': 'f26043bc934bac2a377b1d015dd593953e13fad7381cc41c8d5961deb99dae4b',
 'render/pmrem.mojo': 'edaf56fcf886c01ac6d7d4b47c0f9fa4491ecd6643e49a9a7a59746f690afcd7',
 'render/pointrule.mojo': 'd7394adf9e10c8bdff437647c6d2f339c89b68c04f5dae322262391d9351a2ae',
 'render/rasterizer.mojo': '74c15deb20687b15b91a6b1201eea01161bc5c97c77062b1a8904eb4f35e2e62',
 'render/splat_raster.mojo': 'd2de91534c22ac728e1999ba820a09174f2ca0db16c81fa8f9769dac6ca25081',
 'render/splatrule.mojo': '54e73c0e96327cdf863613db0b082672240aec0562e09e9bc471a1da2c4a39a6',
 'render/target.mojo': '5d33e908ee6d26cee44948ff3800f48cda2759a5f7ca0e3e8993c2b377df76ee',
 'render/tasks.mojo': 'b8dfd9c3417ae3c05156a394811e45a7eb7a990cedb22f8d21652053d9ce61a6',
 'render/texture.mojo': '369e10cc6ae69358660ca656d7f92c674a3dc3104a21a0773c9cd6ce04d40822',
 'render/tonemap.mojo': '9b7ec9c567c09176ccd5b338302b4d59985869c7035855754b819444464f1065',
 'render/transmission.mojo': 'bb1b8248c04478e3845e9f1b4f76e18f0294f0181ac3ae5d23ed093124d938c4',
 'render/uastc.mojo': 'e6833f17255cf058e2f4356e45c0fc7123d971c524fadd0fd3dda02d9d590a77',
 'render/uastc_hdr.mojo': 'a5b7c10868d00d06ec33ea6f8c8b42ad836e8f833a413b6b9b484a6e5cc0def4',
 'render/volume_texture.mojo': 'dce742109273a9f46fe0c39f3b234ff89a835e69ee266557d83f95c2018744d3',
 'renderers/draw_filter.mojo': '3c97c433033ee0b0e6c0de6c712395b621b14969d017dbd47ae62bf0849a0291',
 'renderers/renderer.mojo': '20e908a01406c82b262ded794b8f11bdeac37231f47efd2013eb7e942d7b4a8b',
 'tests/_sample_dispatch_controls.mojo': '1b8250d0cb155e2f0bf7e9d6fbef2c3bd94f1b243c9cf1b43e542c0e67661782',
 'tests/_spiral_domain_controls.mojo': '007f97c95ad5c7e712c93b9c3fd97d8cbd5395544f4b538c1e094dd485137f22',
 'tests/test_anatomy_shared.mojo': '3bc83ed699d74f981847d597e63eefcceac1499ab248e04300ad60b8eca4d2d5',
 'tests/test_animation_loader.mojo': 'e9bbf99f4c69bef991b90b344d9165b1aa5e18f011c5623d6a1bc162599bee30',
 'tests/test_animation_paths.mojo': '82400a6046544f6088206cb4458e86edde85e992b42738a8e4f5efde1f89ebe3',
 'tests/test_arcball_controls.mojo': 'c1ec44a38a670a87d6487b0fe500fb9ef30874891bef2b1c9ac08206d686e7c6',
 'tests/test_audit_boundaries.mojo': '70ad35b3a59f6d910f2f434c4665d4a3144b64b310da9b3798b7c8fae18940df',
 'tests/test_audit_regressions.mojo': '82d32882bf4c0f74fe35a9b253ebde6f49f0ef326fb9f150cc0745c19f3e2411',
 'tests/test_audit_slim.mojo': '86faaa5d826e188bbef50589f74f43b5528abb3473cc4067f98a11d8071787af',
 'tests/test_byte_extent_boundaries.mojo': '546193eda4e2499ca8be0ff495e628de56fc43c6b484ac02fb5ba6ef011c1552',
 'tests/test_carla_agents.mojo': 'c35427b99b7e91036c65536e32c848c6b5126cdb20a20bc3ecda6608c513dc5c',
 'tests/test_carla_agents_drive.mojo': '74373977a6ff78727cb741df251a3291147ddda79872d0d7b27018558733f2d0',
 'tests/test_carla_axis_direct_road.mojo': '43c37e0c1c3c90429b161b42539591a2be6436642bdbb0f1d77fd596fb7a11a8',
 'tests/test_carla_centered_bounds.mojo': '6922875f17e44e981fd6a8f1d5e41601b551ce53141ac26a4b324fcb50e98655',
 'tests/test_carla_chord_endpoint_refusals.mojo': 'dd667ee7d581c0222d777f4d654353115b61e1538605bff919400b5b695a266b',
 'tests/test_carla_conditioned_polynomial.mojo': 'ca77a8a162e0380f894b8ff3e5d17c4077c173e9262e1a64a38fee771ec6fb0b',
 'tests/test_carla_cross_candidate_certificates.mojo': 'e5b2355fa39ef4c907826f41fb9f1df8b865f9dcf934b1c19b57dcbee175190b',
 'tests/test_carla_curve_bounds.mojo': '317138510f87f7577a7454792171ab321ca5f60e676c1c61b1467d6c897697fc',
 'tests/test_carla_geom.mojo': 'ba88a91eb96832c486d4894c789784238e7b17f71eebc4b2c726a5e423d5ba5e',
 'tests/test_carla_junction_bounds.mojo': '3efee848971477e0bc03c5b3096d567d7692f5cf4f9b4b60e2b9979abdfab1ff',
 'tests/test_carla_junction_endpoint_refusals.mojo': '62aabd16af04bb7638eceb42d863fd5a2c2bbf95d86ffc3c08f57018e304e94d',
 'tests/test_carla_lane_center_bound_phase.mojo': 'b05ad08b43a5980f8c5ede640e855c1ec9c2d2923fb5c4ab5464bfb7b2b0a3a0',
 'tests/test_carla_lane_certificates.mojo': 'fe7605b6019e63bf032f3cf6c4ac598b290e6f45125b5b19c9a66cadeec7add0',
 'tests/test_carla_lane_control_successor.mojo': 'a77158dd8babf857f648aada8f8ab68d3d3fef52e47223cc3e05fbc8d49fdbc4',
 'tests/test_carla_lane_dispatch_cell_residuals.mojo': 'e6aa6eb4a962fba4bd85d71048c608fe99e5cd7ef8a7d4190377af321140718c',
 'tests/test_carla_lane_geometry_guard_controls.mojo': '102ca37db70f27294b7e5bff420fbdf8875f0acf1938723455b6a1c5c7650d09',
 'tests/test_carla_lane_helper_guards.mojo': '1d10847201043e0acd7fe10d3b5f746314fab0db3cafadd844b0767128360a01',
 'tests/test_carla_lane_order_successor.mojo': '04bed87e5085305c688b3886139ddb70f99907c43a6c21018ff8bb40d9bea897',
 'tests/test_carla_lane_search_positive_controls.mojo': '5d7e0ee71cebbf73c1258d50058a117a50edad70c53c8cf2cd6c6ef5eac68030',
 'tests/test_carla_map_quantity.mojo': 'c830c74e9f64bb201d1060859f10e394b6272304ff7c610888d5459cf24c40cf',
 'tests/test_carla_reference_derivative_controls.mojo': 'd6be8d637ff2e114e20562fbc28e0b3175dcdd138a7eb05cc7e5e7133ee7162b',
 'tests/test_carla_render_light.mojo': '6703c9c3871c79556670b67c432c225984f338b68fcd8b18cb0df22e26036fdd',
 'tests/test_carla_render_scene.mojo': '3220d75d38b90d478b66ceb196180279d5f9c307249a6c0de3d0bd1ca4b78186',
 'tests/test_carla_road_fixed_s.mojo': 'db41f9c38e18a4b9b4a7064a7862931870ca396c92689221f2d3243a32cf867a',
 'tests/test_carla_sampled_box_cover.mojo': '1f89d12d4b3179fdd0e7904560d2f37f944878dddaf92c60e7b652268bda1018',
 'tests/test_carla_scaled_lane_refinement.mojo': 'd0608befa93df7ea91da9f40c42a2844bd49aa66c4aa3f4c093e3d057297484f',
 'tests/test_carla_sensors.mojo': '7e0d87bc082d57700b69a298d7823c5e59b5090a26394cb9b866b48a62b90503',
 'tests/test_carla_sensors_world.mojo': '2757a7a57aebb6162c7ae58c236a33aa893a55ca07731b3339097d60e481d6bf',
 'tests/test_carla_speed_parser_exceptions.mojo': 'fee54ffb5e01aed94eb2e1951af548bfa7feac04e5dd0bb01c21d486fb4a4941',
 'tests/test_carla_tight_rounding.mojo': '1ec90a5ed03883465957404e01c1f4e9b3c046d4b91b3632149f42073dcb3709',
 'tests/test_carla_tiny_cell_enumeration.mojo': 'd1c1fe9ab86e767828c87199e938c7a507471943e7ac2bd3b9ba1a28418087d0',
 'tests/test_carla_unsampled_admission.mojo': '4562ded403e057a1950e6e78f657e6488adba27e15593dc97536a13c1cb85b7a',
 'tests/test_carla_world_signals.mojo': '5abd8e8e84235728318846c6172d84e0acffcf84957b7669cd36e1dce2680e09',
 'tests/test_cast_shadow.mojo': '7362d06404012c685058a0bd797d7feb980fca71a396aaa7ad0a6c00fab7d5fc',
 'tests/test_ccd_ik_solver.mojo': 'e4b6b4ba801e6b04fd59e8bdbae28d5e0e8cc229f5683d164bde1cd5950c674b',
 'tests/test_city_generator.mojo': 'a03ca178e23c95859113afe198605b79fdb6ff7ca24a1b22d3a49784a354a783',
 'tests/test_clipping.mojo': '2b1a0e49dc36a7496ba7b8ee6a9f6b9b13a08b09edb17690fda12cd62e93316f',
 'tests/test_computation.mojo': '354c2788f8edaf56eaef442c5ca218bc9de205ab0847b4d5dedc084edf948a13',
 'tests/test_compute_nodes.mojo': '8572a0d2f7378b8bfe5eb94eed4ed710b1fa8ddb084c978115616d5731698071',
 'tests/test_csm.mojo': 'ddb93741109c97633d0faf2b175f155a6ddcf4d57afb56e4358a9dee9ad084a0',
 'tests/test_cube_depth_texture.mojo': 'a6c0316a5fe4005bcc2a97dd5cc14c59b26ad4574d7968effb3b46440f1b3fd5',
 'tests/test_curve.mojo': 'db0876cfa3a3f7ad69a3e1dc2597583bd6528c62b8e853082992b6a99b688b2e',
 'tests/test_curve3.mojo': 'fc07cf18840e3079a7d4badf39330dd0300e4652a059c7b7af398b61ff324694',
 'tests/test_curve_boundaries.mojo': 'c6e5ab3305c8095911e34d76d2daedb218b5f9ccb1f0f68621672fb68032b694',
 'tests/test_denoise.mojo': 'd50947f898060041c068114c6368a74e49ae2e36c38916f5ec1cc67e19c386b9',
 'tests/test_display_nodes.mojo': '550c6ce47c52e28c7e9d77b8034c65899a536282513bddccc91c343baadcba2a',
 'tests/test_draco.mojo': 'b6d583c0d224af6b2f881d4c5da1d4145f9e5b2119df81b6594cdb122e077ebf',
 'tests/test_draco_export.mojo': '1c60b89e44fd43032acd77dd6c8d1c4d06a692e505617695a9ea0a2696e7fbbd',
 'tests/test_fbx.mojo': '0fe5090b034ac9e868d7df81ba67f2776684f2a735de4fdafdf779a9cd62fe81',
 'tests/test_fbx_rig.mojo': '71c35db1b0577a0a0fb5e01a4d12306a7964fb1395d62638d9b7e498005c5bbf',
 'tests/test_filter_nodes.mojo': '15b1d1553a540f64aba911b903950c233bce79d67a82756aba53ddaa869ebfd0',
 'tests/test_gaussian_splat.mojo': 'cc385bc98e800e70867d07160e0384c8fe0d24a8a1ed0a66f5ea0bc0b9adbc69',
 'tests/test_geometry.mojo': 'f5fd9f04e809630209caafe91cf4299ba8d7bb2010a1ac43fb87e0f611bbd95c',
 'tests/test_geometry_addons.mojo': 'e4a2ecdea11428330fd71b7a3c71a6bddb71d0b30daff381b7b4b053c2d61fba',
 'tests/test_geometry_inputs.mojo': 'f6fe97ba4e3fee2c95861e6d37dad6eeba84a3538bfc82726fc5c977464d108b',
 'tests/test_geometry_signatures.mojo': '8e98a77013a6545f33dc7e9012716b125cbb5cd92ffa45a9460d9d1fddde1c1e',
 'tests/test_geometry_tools.mojo': 'a342bb28290820411cb8cdb80690aa6c9666e088ab38b17e9aeeddbbbf18d9ac',
 'tests/test_gpgpu_sort.mojo': '0914b784255e675365549f1778f24bf578e2496fd5e1d6e458a7081ccf1ff2e9',
 'tests/test_gpu.mojo': 'c205408079bb797a553b1623d15120eb9ad1d58205f366692b742ffe65db35f4',
 'tests/test_gpu_layout.mojo': '0d065631b2e39eed26f83e39036a5d841fa48eee90c7253310d14b61d40e1682',
 'tests/test_gpu_water.mojo': '0e330277b81d1cf8f2d1791b00d34ad63355666a99ad48e1de60893cc9362d89',
 'tests/test_hair_strands.mojo': 'a1866acccba40a195bf290857e8c2f061dcae7e4bc659994ae2de6056d0c34e7',
 'tests/test_helpers.mojo': 'e9a34a5dac99d781cadb1fa2fec996282bf751f6d605de96afc93870a395489c',
 'tests/test_humanoid_bake.mojo': 'fbf4f1b8601b102957f6d52243f89853084b62034ed4230368b4bfc8ae23c9b5',
 'tests/test_humanoid_loft.mojo': 'ad67b9ac82f957092f24f172b9616fd6f7073ad5ecd771ed3f7e179a3d6282b6',
 'tests/test_image_batch.mojo': 'd5ffbdbbabbfa1359f82c30992bbb22d611723f1f5ee04939fc0303725cc13a0',
 'tests/test_layered_targets.mojo': '8ae6e115b941119dc6dcac7d6ebbc106e412694b83da260a8e803859f4215b0e',
 'tests/test_light_probe_grid.mojo': '2951e8def1fb835d12aabaf596963e810eb2ccdc4bd6213e4b8b94004c45405f',
 'tests/test_lines.mojo': '4b5a8df87906a90ec067760bbdd90b33afda413d34f943d90563d084dd401664',
 'tests/test_lower_first_sampling.mojo': '89d9e5a331795526d92c4986b3ef165d208bdaa7693bbfab31fec56b9f19972e',
 'tests/test_lwo.mojo': 'eb7e2b15e2a79abd12ce8c59955ce37d792f62af3d7416fd9106f90213723418',
 'tests/test_marching_cubes.mojo': '4cac5d0c7936eb47846f70f90556d10152796b5f8c4664f94e973afc00383272',
 'tests/test_materialx.mojo': 'd09b9a7556496dbb1d50a777f1a39efac0ad31b70b97ab9f3347988e426c146a',
 'tests/test_matrix4.mojo': '2b259391fe4b483a214d9ed581e3324ecf90a2138ca2a626587777e4effac7cc',
 'tests/test_more_helpers.mojo': '22a70102fad74357db4d3ee996a7099eb509b53c2c091ef23506cb381cc93bd2',
 'tests/test_morph.mojo': 'b0c28f59fbc8934eca12fff9232e968e95a14aefd10d1cac95a7ee988256fff1',
 'tests/test_morph_sequence_indices.mojo': '3cca7e0f9b16ea29b05ce0c13c156c2f7c40703df62c66cc426d7dfbe75500e1',
 'tests/test_norm_review_regressions.mojo': 'd40f259ea7408859c5022cbda00b8cd6251b698e9ca6ce6ad079c94e5e247e6f',
 'tests/test_object_json.mojo': 'd7aa9d674567c583c526b39ef701e0a0794cf49accbadbf09a4968992a710da5',
 'tests/test_object_json_objects.mojo': '1ce855ab65ca17b11a201ab0a3e68514814f97c60520ab7556235611466594bf',
 'tests/test_oit.mojo': 'f69ece09392fbc889a9def44e39419f37a610121259a57d040d46550a92fdc51',
 'tests/test_person_generator.mojo': 'e465412eb1580948a0971fcb9fff170f5b89d50c721d29e2216aed8e82c065a2',
 'tests/test_pointrule.mojo': 'b207e1847c5203986e1db93a507596174865cd4ef6ae2e200f8d5d1b0211df9b',
 'tests/test_postprocessing.mojo': '1754d92864ab136ca7f3c2de36e45921d5f6e449cc516ee779c83fb15190a582',
 'tests/test_postprocessing_antialias.mojo': 'a18f0f900237c2893235714311e8468d07c55af351cb45c4e213d6e686a44065',
 'tests/test_postprocessing_effects.mojo': '09a1d93be42cb95d64ca0b6b96f0916cb1555c53e008bda97f51c11ff165872c',
 'tests/test_postprocessing_passes.mojo': '24e81a6427e7559eb0d6a8ee0ea308d873aeb1363b793033fd9ba72dc9365da5',
 'tests/test_postprocessing_screen_space.mojo': 'e4259961228a6a9bfb46d99151b5659b0d7195ce9a91238c731a930383b432d0',
 'tests/test_postprocessing_shaders.mojo': '2b5b1263e102088c31b13ebac763182d2c809129114a9cd3d5297b7f953ef093',
 'tests/test_progressive_light_map.mojo': '4df79c1b5e917ea781a6b7091504e564d5f9033c97373e6e76aa652995a15348',
 'tests/test_projector.mojo': 'dc21f222e0babb98bafd7ed4110bfe253853ca74d3013ab55b2b6b6a1661249b',
 'tests/test_rasterizer.mojo': '54bd2bafe99201a0f9dd7908ac71fcccba158500de61762b54791e445c7ff5c9',
 'tests/test_raycaster.mojo': '8175ebce8b5a4644974ab5bceef63fd39e35308f1a19df18cdedb00340c5690f',
 'tests/test_renderer_effects.mojo': '6a4b6917e27263d91c1260b26327a3cbb4d0d83fea157abf248ef244b4eae5b9',
 'tests/test_scene_optimizer.mojo': '94f9557fdb7bd5a59efb11c4b632160dd8ac7bb16c0cab43d3eb05672e160ed9',
 'tests/test_scratch.mojo': '4399930cf3f8f212382e703f0aaad6aa22d52cc9fac88320be09d07a573b268c',
 'tests/test_sculptor.mojo': '53bd53e565dffe96744501ae476505a8f117caa016a0dc2e4e691a03628d0c62',
 'tests/test_shadow.mojo': '24a5b863e7bfc82e22049aeb0a48af7fce8024cf5afbd57a825c04ff720bf255',
 'tests/test_shadow_casters.mojo': '0e5ff505a7c7167989697737467d0e0bdaaba482c8acc23daa99f9cdb47abca0',
 'tests/test_shape.mojo': '99203f726a7b3b35ea49a48b314f3ac87e598501610da748056669cf3f9ddb61',
 'tests/test_skyscraper_generator.mojo': '5ca5e897dfd5f2b4c9b88020c7811bda604e9749a99b2d0d9cb2886c7fa430f8',
 'tests/test_ssgi.mojo': '55c764733217a1e0a6fd3c08571f1c6661fde380fa7f3bfc515851823d8053ee',
 'tests/test_ssr_node.mojo': 'c479fdc478c07aafc41e699d9fc021ac9bdad65982166685633bbe6bce49bc76',
 'tests/test_strand_triangles.mojo': '159581520b40d67559cd7e7c39d4030ab6ae225c3ef5dca580b91200dda81099',
 'tests/test_streamline_sizing.mojo': '2e42ad6cadf90cb23d10efea4a7064f29fbc8a00108f31cce6127d45ed171469',
 'tests/test_streamline_upscaler.mojo': '217287978496502db2972cfa6dabf4a31e17fbad09e3d5659802ddd76caa881b',
 'tests/test_svg_renderer.mojo': 'ddd92e65870a96d703a380eec17ed1827535a21b11da79ff605aabb947252c83',
 'tests/test_temporal_denoise.mojo': '6717abf5d0d99229e2d70ed948b4d2d0538c00880ea13fcf67d9a9e58f2b33ed',
 'tests/test_transmission.mojo': '8bfb804d2e51cd3a26c063898e6dd726878d2f30a302c8db3b56539c73474245',
 'tests/test_tsl_helpers.mojo': '80f1fa722354ca97372177963720649adcbe96c2b50e1e7cac744aa11b88ffe6',
 'tests/test_velocity.mojo': 'e4aa666a40dee2653a6408341027059a1c59c19be0d5b9a8f17f3e2481f34398',
 'tests/test_visibility.mojo': 'f15d91b888cb658367569400ce7994d1d64c04535d406037998cd2f88028c98f',
 'tests/test_volume_node_material.mojo': '92911e3b2537bac9af81671ad80c5ebd7bebf6c8181211f6424b6fcdba7b7d01',
 'tests/test_vrml.mojo': '19a3ffe7707b5c120dedf65354018df58e36488d7e9ebb6bc06e5ca4aa2811a6',
 'tests/test_vxgi_node.mojo': 'a9b81a644740f46bf692bbfe358960aec2f38ef491b72cd0fba05f979fb1df81',
 'tests/test_vxgi_scene_collector.mojo': '56b671e6a45634e3ebcce39dd30dbc6b2a741d88d8669a2cfb9d16535dbdad02',
 'tests/test_vxgi_volume.mojo': '6525b6aca7500c80ba58f62de7e0777cdfddffacb16432afca8ddbde4ef74d7c',
 'tests/test_water.mojo': '628c88b8f045ebf32c67ae46c737758ba3d88f99783eca9c2bef246351f2bec6',
 'tests/test_wide_line_workers.mojo': '2df16a02373e7f1145573f41df89971d8483ddddd1439607c114642f3a0e2b09',
 'tests/test_wide_lines.mojo': '7682cd7250d40b39523caf930ca435d094260c23881fcea0a0d37fdc3029ec5f',
 'tools/carla_lane_oracle/source_contracts.py': 'a4d9eedbdb156c45a4edd507002a2fb169e261ff5f0bc1cd4830c559c4dd2685',
 'tools/carla_lane_oracle/test_main_rebase_successor.py': '598b7f235d6dd347551dfbdcca7390a73016e23ff16a970246e07dbfe48a6459',
 'tools/carla_lane_oracle/test_pr760_arithmetic_stage.py': '39c4e84ee8f2480d1039369011c39ab38c055f71fae6bf0962778b558be9b82f',
 'tools/carla_lane_oracle/test_pr760_physical_image.py': 'fb6a9d7dfab6f5d7e620e6d42ae9dd47ee8fbd609e65a2f82a7e56e888734970',
 'tools/carla_lane_oracle/test_pr776_input_successors.py': 'dde181f02ca49efaa0550a5f9d24847dfc618d14113e2caea7aea3422edd7042',
 'tools/carla_lane_oracle/test_shared_helper_contracts.py': 'eb63c115282ae3e667a35e52d57657e8cfe63c64081fa87e25cd601b661cf3ed',
 'tools/carla_lane_oracle/test_typed_boundary_contracts.py': '0be305bc14258206747f94b71996e5e9d29650e7a0a49ccc9dc2ea97b3ce2f89',
 'tools/carla_lane_oracle/test_typed_owned_operations.py': '56a59b04408d344079048ccc8a32e3a5c0e1af4505cb06aa281c01364738b1eb',
 'tools/carla_lane_oracle/test_witness_format_contracts.py': '554b6db980e099747c3d536eaf722f210f0f17d3f78983cf08bb180c588a22ae',
 'tools/carla_lane_oracle/translated_parameter_resolution.py': '1c63297c0097ce50b9f314ba321e7f4d04c009f6379552a84adefb62a2a7f375',
 'tools/compile_fail_expectations.json': 'a15d4cff3d89429312350a4da95604569da83be105f69a0690025904c2cfbc84',
 'tools/test_conditioned_coverage_loops.py': 'f88451e7313fd84cc788847b1c960dc395b98736779a92c81a1d056ff2977520'}
DATA_SHA256 = 'c7aaa81f8724d96e98a419838ad36e5f3e48e40ab5530ebbee1453e0efc61780'
# END FIXED PR780 SUCCESSOR DATA


def require(ok, message):
    if not ok:
        raise ValueError('PR780 source successor: ' + message)


def sha(raw):
    return hashlib.sha256(raw.encode('utf-8') if type(raw) is str else raw).hexdigest()


def _index_snapshot():
    """Authenticate and detach the fixed per-edge digests and bound inputs."""
    require(type(DATA_SHA256) is str, 'authority digest selector is not a builtin string')
    require(DATA_SHA256 == 'c7aaa81f8724d96e98a419838ad36e5f3e48e40ab5530ebbee1453e0efc61780', 'authority digest selector changed')
    encoded = json.dumps({'edges': EDGE_SHA256, 'bound_inputs': BOUND_INPUTS},
                         sort_keys=True, separators=(',', ':'))
    require(sha(encoded) == DATA_SHA256, 'fixed source inverse data changed')
    return json.loads(encoded)


def _edge_snapshot(path, digest):
    """Authenticate and detach one inverse edge against its fixed digest."""
    require(type(EDGES) is dict and path in EDGES, 'fixed source inverse edge missing: ' + path)
    encoded = json.dumps(EDGES[path], sort_keys=True, separators=(',', ':'))
    require(sha(encoded) == digest, 'fixed source inverse data changed')
    return json.loads(encoded)


def reviewed_edge(path):
    """Return one authenticated detached edge, or None for an unreviewed path."""
    digest = _index_snapshot()['edges'].get(path)
    return None if digest is None else _edge_snapshot(path, digest)


def _data_snapshot():
    """Authenticate and detach the full finite inverse data before consuming it."""
    index = _index_snapshot()
    require(type(EDGES) is dict and set(EDGES) == set(index['edges']),
            'fixed source inverse data changed')
    return {'edges': {path: _edge_snapshot(path, digest)
                      for path, digest in index['edges'].items()},
            'bound_inputs': index['bound_inputs']}


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
    reviewed = reviewed_edge(path)
    if reviewed is None:
        return raw
    result = _predecessor(path, raw, reviewed)
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
